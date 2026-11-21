// App/AppModel+Assistant.swift: the meeting side panel's summary and questions.
import { tr, trf } from "../i18n";
import { formatClock, newID, nowReference } from "../support/format";
import { ChatContext } from "../models/chatContext";
import { ChatHistory } from "../models/chatHistory";
import { ContextBudgets } from "../models/contextBudget";
import { TranscriptSelection } from "../models/transcriptSelection";
import { newTurn } from "../models/chatSession";
import { MeetingAssistantRecordOps, type MeetingAssistantRecord } from "../models/meeting";
import { renderedSource } from "../models/transcript";
import { selectedModel } from "../models/localModels";
import { LLMKeys, Profiles } from "../models/llmConfiguration";
import { RemoteLLM } from "../engine/remoteLLM";
import { AppModel, MeetingAssistantState } from "./model";

declare module "./model" {
  interface AppModel {
    readonly assistantIsBusy: boolean;
    readonly canGenerateAssistant: boolean;
    assistantState(meetingID: string): MeetingAssistantState;
    generateAssistant(meetingID: string, question?: string | null): void;
    stopAssistant(meetingID: string): void;
    updateAssistantRecord(meetingID: string, change: (r: MeetingAssistantRecord) => MeetingAssistantRecord): void;
  }
}

const P = AppModel.prototype;

Object.defineProperty(P, "assistantIsBusy", {
  get(this: AppModel) {
    return Object.keys(this.chatRuns).length > 0 || Object.values(this.assistantStates).some((s) => s.isGenerating) || this.engine.isGenerating;
  },
});

Object.defineProperty(P, "canGenerateAssistant", {
  get(this: AppModel) {
    if (this.localModels.switchingID !== null || this.localModels.deletingID !== null) return false;
    if (this.llmConfiguration.mode === "api") return this.llmConfiguration.activeProfile !== null;
    return this.engine.readiness !== "preparing" && this.engine.readiness !== "unavailable" && this.localModels.installed.has(selectedModel("assistant").id);
  },
});

P.assistantState = function (meetingID) {
  let state = this.assistantStates[meetingID];
  if (!state) {
    state = new MeetingAssistantState(this.meetings.find((m) => m.id === meetingID)?.assistant);
    this.assistantStates[meetingID] = state;
  }
  return state;
};

P.stopAssistant = function (meetingID) {
  this.assistantStates[meetingID]?.controller?.abort();
};

P.generateAssistant = function (meetingID, question = null) {
  const stored = this.meetings.find((m) => m.id === meetingID);
  if (!this.canGenerateAssistant || this.assistantStates[meetingID]?.isGenerating || !stored) return;
  const meeting = this.current(stored);
  const state = this.assistantState(meetingID);
  const lines = meeting.paragraphs
    .map((p) => {
      const text = renderedSource(p, meeting.sourceLanguage).trim();
      return text ? `[${formatClock(p.openedAt)}] ${text}` : null;
    })
    .filter((x): x is string => !!x);
  if (!lines.length) {
    state.error = tr("这场会议还没有转写内容。");
    return this.changed();
  }
  const transcriptEnd = Math.max(0, ...meeting.paragraphs.map((p) => p.openedAt));
  const summary = question === null;
  const language = this.prompts.modelLanguageName;
  const system = ChatContext.composedSystemPrompt({
    language, allowsWeb: false, hasPassages: true, skills: this.prompts.skills,
    memory: question !== null ? this.memoryPrompt(question) : this.memoryPrompt(meeting.title, new Set(["style", "preference"])),
  });
  const mode = this.llmConfiguration.mode;
  const profile = this.llmConfiguration.activeProfile;
  const budget = ContextBudgets.current(mode, profile);
  const summaryTask = "Summarize the main ideas, key terms, conclusions and any stated action items. Organize with short headings and cite timestamps.";
  const pieces = summary
    ? TranscriptSelection.chunks(lines, budget.sidePanelTranscript, mode === "local" ? 4 : 8)
    : { chunks: [TranscriptSelection.pick(lines, question ?? "", budget.sidePanelTranscript)], skipped: false };
  const earlier = state.answers.map((a) => newTurn(a.question, a.answer, a.modelName, { createdAt: a.createdAt }));
  const history = ChatHistory.window(earlier, budget, { dated: false });
  const name = this.assistantModelName;
  const controller = new AbortController();
  state.isGenerating = true;
  state.generatingSummary = summary;
  state.draft = "";
  state.error = null;
  state.controller = controller;
  this.changed();
  const show = (partial: string) => {
    state.draft = partial;
    this.changed();
  };
  const generate = async (prompt: string, onUpdate?: (t: string) => void): Promise<string> => {
    if (mode === "api") {
      if (!profile) throw new Error(tr("请先在设置中选择 API 配置。"));
      const key = await LLMKeys.read(profile);
      if (!Profiles.isLoopback(profile) && !key) throw new Error(tr("请输入 API 密钥。"));
      return RemoteLLM.generate(profile, key, system, prompt, [], onUpdate, controller.signal);
    }
    return this.engine.generate(system, prompt, { onUpdate, signal: controller.signal });
  };
  void (async () => {
    try {
      if (mode === "local") {
        await this.waitForAfterAnswerWork();
        await this.waitForQuestionWork();
      }
      let text: string;
      if (summary && pieces.chunks.length > 1) {
        const partials: string[] = [];
        for (let i = 0; i < pieces.chunks.length; i++) {
          if (controller.signal.aborted) throw new Error("cancelled");
          show(trf("正在整理第 %d/%d 段…", i + 1, pieces.chunks.length));
          const part = `This is part ${i + 1} of ${pieces.chunks.length} of one lecture transcript. Summarize this part in at most 800 characters, keeping the timestamps of the main points.`;
          partials.push(await generate(`${part}\n\nMeeting title: ${meeting.title}\n<transcript>\n${pieces.chunks[i].join("\n")}\n</transcript>`));
        }
        const note = pieces.skipped ? " The parts are evenly spaced samples of a long transcript, not all of it; begin with one line saying so." : "";
        const combined = partials.map((p, i) => `Part ${i + 1}:\n${p}`).join("\n\n");
        text = await generate(`Combine these partial summaries of one lecture into one summary. ${summaryTask}${note}\n\nMeeting title: ${meeting.title}\n<partial_summaries>\n${combined}\n</partial_summaries>`, show);
      } else {
        const transcript = pieces.chunks[0]?.join("\n") ?? "";
        const task = summary ? summaryTask : `Answer this question: ${question ?? ""}` + (history.text ? "\n\n" + history.text : "");
        text = await generate(`${task}\n\nMeeting title: ${meeting.title}\n<transcript>\n${transcript}\n</transcript>`, show);
      }
      const now = nowReference();
      if (summary) {
        state.summary = text;
        state.summaryModelName = name;
        this.updateAssistantRecord(meetingID, (r) => ({ ...r, summary: text, summaryModelName: name, summaryAt: now, summaryCoversUntil: transcriptEnd }));
      } else {
        const answer = { id: newID(), question: question ?? "", answer: text, modelName: name, createdAt: now };
        state.answers = [...state.answers, answer];
        this.updateAssistantRecord(meetingID, (r) => MeetingAssistantRecordOps.append(r, answer));
      }
    } catch (error) {
      if (!controller.signal.aborted) state.error = error instanceof Error ? error.message : String(error);
    } finally {
      state.isGenerating = false;
      state.draft = "";
      state.controller = null;
      this.changed();
    }
  })();
};

P.updateAssistantRecord = function (meetingID, change) {
  this.meetings = this.meetings.map((m) => (m.id === meetingID ? { ...m, assistant: change(m.assistant ?? { answers: [] }) } : m));
};

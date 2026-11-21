// App/AppModel+QA.swift: the teacher's questions, found while recording and answered in turn,
// and the question pop-up.
import { tr } from "../i18n";
import { newID, nowReference } from "../support/format";
import { prefs } from "../support/prefs";
import { ChatContext } from "../models/chatContext";
import { ContextBudgets } from "../models/contextBudget";
import { emptyHistory } from "../models/chatHistory";
import { newTurn } from "../models/chatSession";
import { MeetingQA, MeetingQAStore, QuestionFinder, type QALine } from "../models/meetingQA";
import { renderedSource } from "../models/transcript";
import { LLMKeys, Profiles, type LLMAPIProfile, type LLMMode } from "../models/llmConfiguration";
import { RemoteLLM } from "../engine/remoteLLM";
import { AppModel } from "./model";
type QuestionPopup = import("./model").QuestionPopup;

export const QuestionPopupPreference = {
  key: "lecturenote.questionPopups",
  get isOn() {
    return prefs.bool(this.key) ?? true;
  },
};

declare module "./model" {
  interface AppModel {
    qa(meetingID: string): MeetingQA;
    saveQA(state: MeetingQA): void;
    transcriptLines(meetingID: string, includingOpen?: boolean): QALine[];
    startLiveQuestionScan(meetingID: string): void;
    finishQuestionScan(meetingID: string): void;
    checkLatestLineForQuestion(): void;
    findQuestions(meetingID: string, fromStart?: boolean, includingOpen?: boolean): Promise<void>;
    kickQuestionQueue(): void;
    waitForQuestionWork(): Promise<void>;
    setAutoAnswer(on: boolean, meetingID: string): void;
    askQuestion(id: string, meetingID: string): void;
    askAllQuestions(meetingID: string): void;
    editQuestion(id: string, meetingID: string, text: string): void;
    deleteQuestion(id: string, meetingID: string): void;
    moveQuestion(id: string, meetingID: string, by: number): void;
    continueQuestionInChat(id: string, meetingID: string): void;
    jumpTranscript(meetingID: string, time: number): void;
    forgetQA(meetingID: string): void;
    showQuestionPopup(popup: QuestionPopup): void;
    questionFor(popup: QuestionPopup): MeetingQA["questions"][number] | null;
    answerPopupQuestionNow(): void;
    answerPopupQuestionLater(): void;
    questionPopupTimedOut(): void;
    settleQuestionPopups(): void;
    closeQuestionPopup(): void;
    openPopupQuestionInQA(): void;
  }
}

const P = AppModel.prototype;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

P.qa = function (meetingID) {
  const existing = this.qaStates[meetingID];
  if (existing) return existing;
  const state = new MeetingQA(meetingID);
  this.qaStates[meetingID] = state;
  if (this.chatsReady) {
    void MeetingQAStore.load(meetingID).then((stored) => {
      if (!stored) return;
      state.questions = stored.questions.map((q) => (q.status === "answering" ? { ...q, status: "queued", answer: "" } : q));
      state.autoAnswer = stored.autoAnswer;
      state.scannedThrough = stored.scannedThrough;
      if (state.questions.some((q) => q.status === "queued")) this.kickQuestionQueue();
      this.changed();
    });
  }
  return state;
};

P.saveQA = function (state) {
  if (!this.chatsReady) return;
  MeetingQAStore.save(state.meetingID, { questions: state.questions, autoAnswer: state.autoAnswer, scannedThrough: state.scannedThrough });
  this.changed();
};

P.transcriptLines = function (meetingID, includingOpen = false) {
  const meeting = this.meetings.find((m) => m.id === meetingID);
  if (!meeting) return [];
  const live = meetingID === this.recordingMeetingID;
  const paragraphs = live ? this.engine.transcript.paragraphs.filter((p) => p.closed || includingOpen) : meeting.paragraphs;
  return paragraphs.flatMap((p) => {
    const text = renderedSource(p, meeting.sourceLanguage).trim();
    return text ? [{ at: p.openedAt, text }] : [];
  });
};

P.startLiveQuestionScan = function (meetingID) {
  if (this.questionScanTimer) clearInterval(this.questionScanTimer);
  this.questionScanTimer = setInterval(() => {
    if (this.recordingMeetingID !== meetingID) {
      if (this.questionScanTimer) clearInterval(this.questionScanTimer);
      this.questionScanTimer = null;
      return;
    }
    void this.findQuestions(meetingID);
  }, 120_000);
};

P.finishQuestionScan = function (meetingID) {
  if (this.questionScanTimer) clearInterval(this.questionScanTimer);
  this.questionScanTimer = null;
  if (this.quickQuestionTimer) clearTimeout(this.quickQuestionTimer);
  this.settleQuestionPopups();
  if (this.meetings.some((m) => m.id === meetingID)) void this.findQuestions(meetingID);
};

P.checkLatestLineForQuestion = function () {
  const id = this.recordingMeetingID;
  if (!id || !QuestionPopupPreference.isOn) return;
  const state = this.qa(id);
  const fresh = this.transcriptLines(id, true).filter((l) => l.at > state.scannedThrough).slice(-2);
  if (!QuestionFinder.candidates(fresh).length) return;
  if (this.quickQuestionTimer) clearTimeout(this.quickQuestionTimer);
  this.quickQuestionTimer = setTimeout(() => {
    if (this.recordingMeetingID === id) void this.findQuestions(id, false, true);
  }, 3000);
};

async function waitUntilQuiet(m: AppModel, local: boolean, forChat: boolean): Promise<boolean> {
  for (;;) {
    const chatting = m.isChatAnswering || Object.values(m.assistantStates).some((s) => s.isGenerating);
    const busyLocally = local && (m.assistantIsBusy || m.afterAnswerGenerating || m.questionWorkGenerating);
    if (!(forChat ? chatting || busyLocally : busyLocally)) return true;
    await sleep(2000);
  }
}

P.findQuestions = async function (meetingID, fromStart = false, includingOpen = false) {
  if (!this.canRunBackgroundWork) return;
  const state = this.qa(meetingID);
  if (state.scanning) return;
  state.scanning = true;
  state.scanError = null;
  this.changed();
  try {
    if (fromStart) state.scannedThrough = -1;
    const closed = this.transcriptLines(meetingID);
    const fresh = this.transcriptLines(meetingID, includingOpen).filter((l) => l.at > state.scannedThrough);
    const readUpTo = (at: number) => Math.min(at, closed.at(-1)?.at ?? state.scannedThrough);
    const live = meetingID === this.recordingMeetingID && QuestionPopupPreference.isOn;
    const language = this.prompts.modelLanguageName;
    for (const chunk of QuestionFinder.chunks(fresh)) {
      const last = chunk.at(-1);
      if (!last || state.questions.length >= QuestionFinder.perMeeting) break;
      if (!QuestionFinder.candidates(chunk).length) {
        state.scannedThrough = Math.max(state.scannedThrough, readUpTo(last.at));
        continue;
      }
      const mode = this.llmConfiguration.mode;
      await waitUntilQuiet(this, mode === "local", false);
      this.questionWorkGenerating = true;
      let reply: string | null = null;
      try {
        reply = await this.backgroundReply(mode, this.llmConfiguration.activeProfile, QuestionFinder.findSystem(language), QuestionFinder.findPrompt(chunk, state.questions), 700);
      } catch {
        reply = null;
      }
      this.questionWorkGenerating = false;
      if (reply === null) {
        state.scanError = tr("暂时没能找出问题，稍后会再试。");
        break;
      }
      const found = QuestionFinder.parse(reply, chunk, state.questions, live ? "waiting" : state.autoAnswer ? "queued" : "waiting");
      state.questions = [...state.questions, ...found];
      state.scannedThrough = Math.max(state.scannedThrough, readUpTo(last.at));
      this.saveQA(state);
      if (live) found.forEach((q) => this.showQuestionPopup({ meetingID, questionID: q.id, answering: false }));
    }
    this.saveQA(state);
    if (state.questions.some((q) => q.status === "queued")) this.kickQuestionQueue();
  } finally {
    state.scanning = false;
    this.changed();
  }
};

P.kickQuestionQueue = function () {
  if (this.questionQueueRunning) return;
  this.questionQueueRunning = true;
  void (async () => {
    try {
      for (;;) {
        const next = nextQueued(this);
        if (!next) break;
        const local = this.llmConfiguration.mode === "local";
        await waitUntilQuiet(this, local, true);
        const q = next.state.questions.find((x) => x.id === next.id);
        if (!q || q.status !== "queued") continue;
        if (local) this.questionWorkGenerating = true;
        await answer(this, next.id, next.state);
        this.questionWorkGenerating = false;
        if (next.state.questions.find((x) => x.id === next.id)?.status === "queued") break;
      }
    } finally {
      this.questionQueueRunning = false;
      this.changed();
    }
  })();
};

function nextQueued(m: AppModel): { state: MeetingQA; id: string } | null {
  if (m.urgentQuestionID) {
    for (const state of Object.values(m.qaStates)) if (state.questions.some((q) => q.id === m.urgentQuestionID && q.status === "queued")) return { state, id: m.urgentQuestionID };
    m.urgentQuestionID = null;
  }
  for (const state of Object.values(m.qaStates)) {
    const q = [...state.questions].reverse().find((x) => x.status === "queued");
    if (q) return { state, id: q.id };
  }
  return null;
}

async function answer(m: AppModel, id: string, state: MeetingQA) {
  const meeting = m.meetings.find((x) => x.id === state.meetingID);
  const question = state.questions.find((q) => q.id === id);
  if (!m.canRunBackgroundWork || !meeting || !question) return;
  const update = (change: Partial<typeof question>) => {
    state.questions = state.questions.map((q) => (q.id === id ? { ...q, ...change } : q));
    m.changed();
  };
  update({ status: "answering", answer: "", error: null });
  const mode = m.llmConfiguration.mode;
  const profile = m.llmConfiguration.activeProfile;
  const name = m.assistantModelName;
  const budget = ContextBudgets.current(mode, profile);
  const lines = m.transcriptLines(meeting.id);
  const lecture = m.current(meeting);
  const linked = m.sources.filter((s) => (m.meetingLinks[meeting.id] ?? []).includes(s.id));
  let blocks = QuestionFinder.moment(question, lines, meeting.id, meeting.title);
  const around = new Set(blocks.map((b) => b.body));
  const packed = ChatContext.pack(await m.passageBlocks([lecture], linked), question.text, budget.scope);
  blocks = [...blocks, ...packed.filter((b) => !around.has(b.body))];
  const chatID = m.meetingChatID[meeting.id];
  const chat = chatID ? m.chats.find((c) => c.id === chatID) : null;
  if ((chat?.allowsWeb ?? false) && m.webSearch.isActiveReady) {
    const found = await m.searchPasses([question.text]).catch(() => null);
    if (found) blocks = [...blocks, ...found.blocks];
  }
  const memory = m.memoryPrompt(question.text);
  let system = QuestionFinder.answerSystem(m.prompts.modelLanguageName, blocks.some((b) => b.url));
  if (memory) system += "\n\n" + memory;
  const prompt = ChatContext.userPrompt({ question: QuestionFinder.answerQuestion(question), history: emptyHistory(), blocks });
  try {
    const text = await questionReply(m, mode, profile, system, prompt, (partial) => update({ answer: partial }));
    update({ answer: text, citations: ChatContext.citations(text, blocks), modelName: name, status: "answered" });
  } catch (error) {
    update({ status: "failed", error: error instanceof Error ? error.message : String(error) });
  }
  m.saveQA(state);
}

async function questionReply(m: AppModel, mode: LLMMode, profile: LLMAPIProfile | null, system: string, prompt: string, onUpdate: (t: string) => void): Promise<string> {
  if (mode === "api") {
    if (!profile) throw new Error(tr("请先在设置中选择 API 配置。"));
    const key = await LLMKeys.read(profile);
    if (!Profiles.isLoopback(profile) && !key) throw new Error(tr("请输入 API 密钥。"));
    return RemoteLLM.generate(profile, key, system, prompt, [], onUpdate);
  }
  return m.engine.generate(system, prompt, { maxTokens: 900, background: true, onUpdate });
}

P.waitForQuestionWork = async function () {
  while (this.questionWorkGenerating) await sleep(300);
};

P.setAutoAnswer = function (on, meetingID) {
  const state = this.qa(meetingID);
  state.autoAnswer = on;
  state.questions = state.questions.map((q) => (on && q.status === "waiting" ? { ...q, status: "queued" } : !on && q.status === "queued" ? { ...q, status: "waiting" } : q));
  this.saveQA(state);
  if (on) this.kickQuestionQueue();
};

P.askQuestion = function (id, meetingID) {
  const state = this.qa(meetingID);
  const q = state.questions.find((x) => x.id === id);
  if (!q || q.status === "answering") return;
  state.questions = state.questions.map((x) => (x.id === id ? { ...x, status: "queued", error: null } : x));
  this.saveQA(state);
  this.kickQuestionQueue();
};

P.askAllQuestions = function (meetingID) {
  const state = this.qa(meetingID);
  state.questions = state.questions.map((q) => (q.status === "waiting" || q.status === "failed" ? { ...q, status: "queued" } : q));
  this.saveQA(state);
  this.kickQuestionQueue();
};

P.editQuestion = function (id, meetingID, text) {
  const state = this.qa(meetingID);
  const trimmed = text.trim();
  const q = state.questions.find((x) => x.id === id);
  if (!trimmed || !q || q.status === "answering" || q.text === trimmed) return;
  const reset = q.status === "answered" || q.status === "failed";
  const status = reset ? (state.autoAnswer ? "queued" : "waiting") : q.status;
  state.questions = state.questions.map((x) => (x.id === id ? { ...x, text: trimmed, ...(reset ? { answer: "", citations: [], status } : {}) } : x));
  this.saveQA(state);
  if (status === "queued") this.kickQuestionQueue();
};

P.deleteQuestion = function (id, meetingID) {
  const state = this.qa(meetingID);
  if (state.questions.find((q) => q.id === id)?.status === "answering") return;
  state.questions = state.questions.filter((q) => q.id !== id);
  this.saveQA(state);
};

P.moveQuestion = function (id, meetingID, by) {
  const state = this.qa(meetingID);
  const index = state.questions.findIndex((q) => q.id === id);
  const target = index + by;
  if (index < 0 || target < 0 || target >= state.questions.length) return;
  const list = [...state.questions];
  [list[index], list[target]] = [list[target], list[index]];
  state.questions = list;
  this.saveQA(state);
};

P.continueQuestionInChat = function (id, meetingID) {
  const q = this.qa(meetingID).questions.find((x) => x.id === id);
  if (!q || q.status !== "answered") return;
  this.appendTurnToMeetingChat(meetingID, newTurn(q.text, q.answer, q.modelName, { citations: q.citations }));
};

P.jumpTranscript = function (meetingID, time) {
  this.transcriptJump = { meetingID, time, token: newID(), createdAt: Date.now() };
  this.changed();
};

P.forgetQA = function (meetingID) {
  delete this.qaStates[meetingID];
  MeetingQAStore.delete(meetingID);
};

P.showQuestionPopup = function (popup) {
  if (this.questionPopup?.questionID === popup.questionID || this.questionPopupQueue.some((p) => p.questionID === popup.questionID)) return;
  if (!this.questionPopup) this.questionPopup = popup;
  else this.questionPopupQueue = [...this.questionPopupQueue, popup];
  this.changed();
};

P.questionFor = function (popup) {
  return this.qa(popup.meetingID).questions.find((q) => q.id === popup.questionID) ?? null;
};

P.answerPopupQuestionNow = function () {
  const popup = this.questionPopup;
  if (!popup) return;
  this.urgentQuestionID = popup.questionID;
  this.askQuestion(popup.questionID, popup.meetingID);
  this.questionPopup = { ...popup, answering: true };
  this.changed();
};

P.answerPopupQuestionLater = function () {
  this.closeQuestionPopup();
};

P.questionPopupTimedOut = function () {
  const popup = this.questionPopup;
  if (!popup) return;
  const state = this.qa(popup.meetingID);
  if (!popup.answering && state.autoAnswer && state.questions.find((q) => q.id === popup.questionID)?.status === "waiting") this.askQuestion(popup.questionID, popup.meetingID);
  this.closeQuestionPopup();
};

P.settleQuestionPopups = function () {
  while (this.questionPopup) {
    if (this.questionPopup.answering) this.closeQuestionPopup();
    else this.questionPopupTimedOut();
  }
};

P.closeQuestionPopup = function () {
  this.questionPopup = this.questionPopupQueue[0] ?? null;
  this.questionPopupQueue = this.questionPopupQueue.slice(1);
  this.changed();
};

P.openPopupQuestionInQA = function () {
  const popup = this.questionPopup;
  const question = popup ? this.questionFor(popup) : null;
  if (!popup || !question) return;
  this.page = "meetings";
  this.openMeetingID = popup.meetingID;
  this.detailTabRequest = { meetingID: popup.meetingID, tab: "qa", token: newID() };
  this.jumpTranscript(popup.meetingID, question.at);
  this.closeQuestionPopup();
};

export const nowRef = nowReference;

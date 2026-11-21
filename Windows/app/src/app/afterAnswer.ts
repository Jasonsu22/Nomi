// App/AppModel+AfterAnswer.swift and AppModel+Memory.swift: the chat's running summary, then the memory pass.
import { tr } from "../i18n";
import { nowReference, toDate } from "../support/format";
import { ChatSummaries } from "../models/chatHistory";
import { ContextBudgets } from "../models/contextBudget";
import { MemoryLearning, type MemoryItem, type MemoryKind } from "../models/userMemory";
import type { ChatSummary, ChatTurn } from "../models/chatSession";
import { LLMKeys, type LLMAPIProfile, type LLMMode } from "../models/llmConfiguration";
import { RemoteLLM, Cancelled } from "../engine/remoteLLM";
import { CancellationError } from "../engine/localEngine";
import { AppModel } from "./model";

type SummaryJob = { chatID: string; turns: ChatTurn[]; previous: ChatSummary | null; mode: LLMMode; profile: LLMAPIProfile | null; modelName: string; system: string; prompt: string; limit: number };
type MemoryJob = { mode: LLMMode; profile: LLMAPIProfile | null; system: string; prompt: string; known: MemoryItem[]; last: ChatTurn };

const isCancellation = (e: unknown) => e instanceof CancellationError || e instanceof Cancelled;

declare module "./model" {
  interface AppModel {
    readonly canRunBackgroundWork: boolean;
    scheduleAfterAnswerWork(chatID: string | null): void;
    waitForAfterAnswerWork(): Promise<void>;
    backgroundReply(mode: LLMMode, profile: LLMAPIProfile | null, system: string, prompt: string, maxTokens: number): Promise<string>;
    unlearnedTurns(): ChatTurn[];
    readonly memoryEnabled: boolean;
    showMemorySettings(): void;
    memoryPrompt(question: string, kinds?: Set<MemoryKind> | null): string;
  }
}

const P = AppModel.prototype;

Object.defineProperty(P, "canRunBackgroundWork", {
  get(this: AppModel) {
    return this.llmConfiguration.mode === "api" ? this.llmConfiguration.activeProfile !== null : true;
  },
});

P.scheduleAfterAnswerWork = function (chatID) {
  if (this.afterAnswerTask) return;
  const summary = chatID ? summaryJob(this, chatID) : null;
  const memory = memoryJob(this);
  if (!summary && !memory) return;
  const local = this.llmConfiguration.mode === "local";
  const task = { cancelled: false, done: Promise.resolve() };
  this.afterAnswerTask = task;
  const mayStart = () => !task.cancelled && (!local || (!this.isChatAnswering && !this.assistantIsBusy && !this.questionWorkGenerating));
  task.done = (async () => {
    try {
      if (local) await new Promise((r) => setTimeout(r, 30_000));
      if (summary && mayStart()) {
        await runSummary(this, summary);
        this.afterAnswerGenerating = false;
      }
      if (memory && this.memoryEnabled && mayStart()) await runMemory(this, memory);
    } finally {
      this.afterAnswerTask = null;
      this.afterAnswerGenerating = false;
      this.changed();
    }
  })();
};

P.waitForAfterAnswerWork = async function () {
  const task = this.afterAnswerTask;
  if (!task) return;
  task.cancelled = true;
  if (this.afterAnswerGenerating) {
    await this.engine.cancelBackgroundGeneration();
    await task.done;
  }
};

function summaryJob(m: AppModel, chatID: string): SummaryJob | null {
  if (!m.canRunBackgroundWork || (m.summaryFailures[chatID] ?? 0) >= ChatSummaries.maxFailures) return null;
  const chat = m.chats.find((c) => c.id === chatID);
  if (!chat) return null;
  const mode = m.llmConfiguration.mode;
  const profile = m.llmConfiguration.activeProfile;
  const budget = ContextBudgets.current(mode, profile);
  const turns = ChatSummaries.pending(chat.turns, chat.summary, budget);
  if (!turns) return null;
  const limit = ChatSummaries.limit(mode);
  return { chatID, turns, previous: chat.summary ?? null, mode, profile, modelName: m.assistantModelName, system: ChatSummaries.system(m.prompts.modelLanguageName, limit), prompt: ChatSummaries.prompt(chat.summary, turns, budget), limit };
}

async function runSummary(m: AppModel, job: SummaryJob) {
  m.afterAnswerGenerating = true;
  const last = job.turns.at(-1);
  if (!last) return;
  let reply: string;
  try {
    reply = await m.backgroundReply(job.mode, job.profile, job.system, job.prompt, 500);
  } catch (error) {
    if (!isCancellation(error)) m.summaryFailures[job.chatID] = (m.summaryFailures[job.chatID] ?? 0) + 1;
    return;
  }
  const text = ChatSummaries.cleaned(reply, job.limit);
  if (!text) {
    m.summaryFailures[job.chatID] = (m.summaryFailures[job.chatID] ?? 0) + 1;
    return;
  }
  delete m.summaryFailures[job.chatID];
  const chat = m.chats.find((c) => c.id === job.chatID);
  if (!chat || (chat.summary?.throughTurnID ?? null) !== (job.previous?.throughTurnID ?? null)) return;
  m.mutateChat(job.chatID, (s) => ({ ...s, summary: { text, throughTurnID: last.id, throughDate: last.createdAt, coveredTurns: (job.previous?.coveredTurns ?? 0) + job.turns.length, modelName: job.modelName, updatedAt: nowReference() } }), false);
}

P.backgroundReply = async function (mode, profile, system, prompt, maxTokens) {
  if (mode === "api") {
    if (!profile) throw new Error(tr("请先在设置中选择 API 配置。"));
    const key = await LLMKeys.read(profile);
    return RemoteLLM.generate(profile, key, system, prompt);
  }
  return this.engine.generate(system, prompt, { maxTokens, background: true });
};

P.unlearnedTurns = function () {
  const since = this.memory.learnedThrough ? new Date(this.memory.learnedThrough).getTime() : 0;
  return this.chats
    .flatMap((c) => c.turns)
    .filter((t) => toDate(t.createdAt).getTime() > since && !t.error && t.answer.trim())
    .sort((a, b) => a.createdAt - b.createdAt)
    .slice(-8);
};

Object.defineProperty(P, "memoryEnabled", { get(this: AppModel) { return this.memory.isEnabled(this.llmConfiguration.mode); } });

function memoryJob(m: AppModel): MemoryJob | null {
  if (!m.memoryEnabled || !m.canRunBackgroundWork) return null;
  const turns = m.unlearnedTurns();
  const needed = Math.min(MemoryLearning.batch + 3 * m.memoryFailures, 8);
  const last = turns.at(-1);
  if (turns.length < needed || !last) return null;
  const known = m.memory.items;
  return { mode: m.llmConfiguration.mode, profile: m.llmConfiguration.activeProfile, system: MemoryLearning.system(m.prompts.modelLanguageName), prompt: MemoryLearning.prompt(known, turns), known, last };
}

async function runMemory(m: AppModel, job: MemoryJob) {
  m.afterAnswerGenerating = true;
  let reply: string;
  try {
    reply = await m.backgroundReply(job.mode, job.profile, job.system, job.prompt, 300);
  } catch (error) {
    if (isCancellation(error)) return;
    m.memoryFailures++;
    if (m.memoryFailures >= 3) {
      m.memory.skip(toDate(job.last.createdAt));
      m.memoryFailures = 0;
    }
    return;
  }
  m.memoryFailures = 0;
  const learned = m.memory.learn(MemoryLearning.parse(reply, job.known), toDate(job.last.createdAt));
  if (!learned.length) return;
  const chat = m.chats.find((c) => c.turns.some((t) => t.id === job.last.id));
  if (chat) m.mutateChat(chat.id, (s) => ({ ...s, turns: s.turns.map((t) => (t.id === job.last.id ? { ...t, memoryNote: learned } : t)) }), false);
}

P.showMemorySettings = function () {
  this.revealMemorySettings = true;
  this.page = "settings";
  this.changed();
};

P.memoryPrompt = function (question, kinds = null) {
  if (!this.memoryEnabled) return "";
  const items = kinds ? this.memory.items.filter((i) => kinds.has(i.kind)) : this.memory.items;
  return MemoryLearning.promptBlock(MemoryLearning.selected(items, question));
};

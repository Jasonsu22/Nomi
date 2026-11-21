// App/AppModel+Chat.swift: asking, answering with lookups, steps, demos, citations.
import { tr, trf } from "../i18n";
import { formatClock, newID, nowReference, toDate } from "../support/format";
import { shell } from "../platform";
import { AppModel, type ChatRun } from "./model";
import { ChatStore, SourceStore } from "./stores";
import { ChatContext, type LibraryTool, type WebTool } from "../models/chatContext";
import { ChatHistory, forMessages, historyMessages } from "../models/chatHistory";
import { ChatTools } from "../models/chatTools";
import { AnswerStepSummary, newStep, stepSeconds, isRunning, type AnswerStepKind } from "../models/answerSteps";
import { ContextBudgets } from "../models/contextBudget";
import type { ContextBlock } from "../models/contextBlock";
import { LibraryDates, LibraryRequests, LibrarySearch, libraryRequest, type LibraryDocument, type LibraryExclusions, type LibraryRequest } from "../models/librarySearch";
import { newChat, newTurn, Scope, type ChatCitation, type ChatScope, type ChatSession, type ChatTurn, type ScopeCategoryName, type ScopeItem } from "../models/chatSession";
import { ChatImages, isDraftFile, type ChatFileRef, type ChatImage, type ChatImageDraft, type ModelImage } from "../models/chatImage";
import { safeFileName, type KnowledgeSource } from "../models/knowledgeSource";
import { shownParagraphs, type Meeting } from "../models/meeting";
import { renderedSource, renderedTranslation } from "../models/transcript";
import { SourceTextCache } from "../models/sourceText";
import { LLMKeys, Profiles, type LLMAPIProfile, type LLMMode, type ThinkingLevel } from "../models/llmConfiguration";
import { singleRequest, type LLMMessage, type LLMProgress, type LLMRequest } from "../engine/llmRequest";
import { RemoteLLM, Cancelled } from "../engine/remoteLLM";
import { CancellationError, LocalEngine } from "../engine/localEngine";
import { hitBlock, type SearchVendor } from "../engine/search";
import { fs } from "../platform";
import { CitationKind } from "./citations";

declare module "./model" {
  interface AppModel {
    readonly currentChat: ChatSession | null;
    readonly chatHistory: ChatSession[];
    chatHistoryAnchored(meetingID: string | null): ChatSession[];
    chatAnchored(meetingID: string | null): ChatSession | null;
    ensureChat(): void;
    ensureMeetingChat(meetingID: string): void;
    beginNewChat(anchor?: string | null): void;
    openChat(id: string, forAnchor?: string | null): void;
    deleteChat(id: string): void;
    renameChat(id: string, title: string): void;
    updateChatScope(scope: ChatScope): void;
    setChatWeb(enabled: boolean, anchor?: string | null): void;
    removeSearch(vendor: SearchVendor): Promise<void>;
    useLocalChatModel(): void;
    readonly apiModelChoices: string[];
    refreshActiveAPIModels(): Promise<void>;
    useAPIModel(modelID: string): void;
    useChatProfile(id: string): void;
    citationIsOpenable(c: ChatCitation): boolean;
    openCitation(c: ChatCitation): void;
    ask(question: string, o?: { images?: ChatImageDraft[]; anchor?: string | null; chatID?: string | null; steered?: boolean }): boolean;
    stopChat(chatID: string): void;
    searchPasses(queries: string[], signal?: AbortSignal): Promise<{ blocks: ContextBlock[]; notice: string | null }>;
    completeChat(mode: LLMMode, profile: LLMAPIProfile | null, request: LLMRequest, o: { localMaxTokens?: number; signal: AbortSignal; onProgress: (p: LLMProgress) => void }): Promise<string>;
    beginStep(chatID: string, kind: AnswerStepKind, title: string, count?: number): string;
    finishStep(chatID: string, stepID: string, detail: string): void;
    chatMeetingItems(): ScopeItem[];
    chatSourceItems(): ScopeItem[];
    chatCategoryNames(): ScopeCategoryName[];
    appendTurnToMeetingChat(meetingID: string, turn: ChatTurn): void;
    mutateChat(id: string, body: (s: ChatSession) => ChatSession, touch?: boolean): void;
    saveChat(session: ChatSession): void;
    addChatFiles(drafts: ChatImageDraft[], meetingID: string | null): Promise<KnowledgeSource[]>;
    readonly hasLibrary: boolean;
    passageBlocks(meetings: Meeting[], sources: KnowledgeSource[], summaryAbove?: number): Promise<ContextBlock[]>;
  }
}

const P = AppModel.prototype;

function check(signal: AbortSignal) {
  if (signal.aborted) throw new CancellationError();
}
const isCancel = (e: unknown) => e instanceof CancellationError || e instanceof Cancelled || (e instanceof DOMException && e.name === "AbortError");

Object.defineProperty(P, "currentChat", {
  get(this: AppModel) {
    return this.chats.find((c) => c.id === this.currentChatID) ?? null;
  },
});

Object.defineProperty(P, "chatHistory", {
  get(this: AppModel) {
    return this.chats.filter((c) => c.turns.length).sort((a, b) => b.updatedAt - a.updatedAt);
  },
});

P.chatHistoryAnchored = function (meetingID) {
  return meetingID ? this.chatHistory.filter((c) => c.anchorMeetingID === meetingID) : this.chatHistory;
};

P.chatAnchored = function (meetingID) {
  if (meetingID) {
    const id = this.meetingChatID[meetingID];
    return id ? this.chats.find((c) => c.id === id) ?? null : null;
  }
  return this.currentChat;
};

P.ensureChat = function () {
  const current = this.currentChat;
  if (current && !current.anchorMeetingID) return;
  const existing = this.chats.find((c) => !c.anchorMeetingID);
  if (existing) {
    this.currentChatID = existing.id;
    return;
  }
  const session = newChat();
  this.chats = [session, ...this.chats];
  this.currentChatID = session.id;
  this.changed();
};

P.ensureMeetingChat = function (meetingID) {
  const id = this.meetingChatID[meetingID];
  if (id && this.chats.some((c) => c.id === id && c.anchorMeetingID === meetingID)) return;
  const existing = this.chats.find((c) => c.anchorMeetingID === meetingID);
  if (existing) {
    this.meetingChatID[meetingID] = existing.id;
    return;
  }
  const session = newChat({ anchorMeetingID: meetingID });
  this.chats = [session, ...this.chats];
  this.meetingChatID[meetingID] = session.id;
  this.changed();
};

function discardComposerImages(m: AppModel, ids: string[]) {
  for (const id of ids) {
    for (const d of m.composerImages[id] ?? []) void ChatImages.discard(d);
    delete m.composerImages[id];
  }
}

P.beginNewChat = function (anchor = null) {
  if (anchor) {
    const id = this.meetingChatID[anchor];
    const current = id ? this.chats.find((c) => c.id === id) : null;
    if (current && !current.turns.length) {
      this.chatFocusRequest++;
      return this.changed();
    }
    const removing = this.chats.filter((c) => c.anchorMeetingID === anchor && !c.turns.length && !this.chatRuns[c.id]).map((c) => c.id);
    discardComposerImages(this, removing);
    const session = newChat({ anchorMeetingID: anchor });
    this.chats = [session, ...this.chats.filter((c) => !removing.includes(c.id))];
    this.meetingChatID[anchor] = session.id;
    this.chatError = null;
    this.chatFocusRequest++;
    return this.changed();
  }
  const current = this.currentChat;
  if (current && !current.anchorMeetingID && !current.turns.length) {
    this.chatFocusRequest++;
    return this.changed();
  }
  const scope = current && !current.anchorMeetingID ? current.scope : Scope.normalize(null);
  const removing = this.chats.filter((c) => !c.anchorMeetingID && !c.turns.length && !this.chatRuns[c.id]).map((c) => c.id);
  discardComposerImages(this, removing);
  const session = newChat({ scope });
  this.chats = [session, ...this.chats.filter((c) => !removing.includes(c.id))];
  this.currentChatID = session.id;
  this.chatError = null;
  this.chatFocusRequest++;
  this.changed();
};

function applyStoredModel(m: AppModel, session: ChatSession) {
  if (!session.modelMode) return;
  if (session.modelMode === "local") return m.llmConfiguration.setMode("local");
  const id = session.profileID;
  if (!id || !m.llmConfiguration.profiles.some((p) => p.id === id)) return;
  m.llmConfiguration.setMode("api");
  m.llmConfiguration.activate(id);
}

P.openChat = function (id, forAnchor = null) {
  const session = this.chats.find((c) => c.id === id);
  if (!session) return;
  if (forAnchor && session.anchorMeetingID === forAnchor) this.meetingChatID[forAnchor] = id;
  else this.currentChatID = id;
  this.chatError = null;
  applyStoredModel(this, session);
  this.chatFocusRequest++;
  this.changed();
};

P.deleteChat = function (id) {
  if (this.chatRuns[id]) return;
  const session = this.chats.find((c) => c.id === id);
  if (session) {
    for (const turn of session.turns) {
      this.visualControllers[turn.id]?.abort();
      delete this.visualControllers[turn.id];
      this.preparingVisualTurnIDs.delete(turn.id);
    }
    void ChatImages.delete(session.turns.flatMap((t) => t.images));
    discardComposerImages(this, [id]);
    this.clearQueue(id);
  }
  const anchor = session?.anchorMeetingID ?? null;
  this.chats = this.chats.filter((c) => c.id !== id);
  if (this.chatsReady) void ChatStore.delete(id);
  if (anchor && this.meetingChatID[anchor] === id) {
    const next = this.chats.find((c) => c.anchorMeetingID === anchor);
    if (next) this.meetingChatID[anchor] = next.id;
    else delete this.meetingChatID[anchor];
  }
  if (this.currentChatID === id) {
    this.currentChatID = this.chats.find((c) => !c.anchorMeetingID)?.id ?? null;
    const current = this.currentChat;
    if (current) applyStoredModel(this, current);
    else {
      const fresh = newChat();
      this.chats = [fresh, ...this.chats];
      this.currentChatID = fresh.id;
    }
    this.chatError = null;
  }
  this.changed();
};

P.renameChat = function (id, title) {
  const trimmed = title.trim();
  if (!trimmed) return;
  this.mutateChat(id, (s) => ({ ...s, title: [...trimmed].slice(0, 80).join(""), titleCustom: true }));
};

P.updateChatScope = function (scope) {
  this.ensureChat();
  if (this.currentChatID) this.mutateChat(this.currentChatID, (s) => ({ ...s, scope }));
};

P.setChatWeb = function (enabled, anchor = null) {
  if (anchor) this.ensureMeetingChat(anchor);
  else this.ensureChat();
  if (!this.webSearch.isActiveReady) return;
  const id = (anchor ? this.meetingChatID[anchor] : null) ?? this.currentChatID;
  if (id) this.mutateChat(id, (s) => ({ ...s, allowsWeb: enabled }));
};

P.removeSearch = async function (vendor) {
  if (!(await this.webSearch.delete(vendor))) return;
  for (const chat of this.chats.filter((c) => c.allowsWeb)) this.mutateChat(chat.id, (s) => ({ ...s, allowsWeb: false }));
};

P.useLocalChatModel = function () {
  this.llmConfiguration.setMode("local");
  this.ensureChat();
  if (this.currentChatID) this.mutateChat(this.currentChatID, (s) => ({ ...s, modelMode: "local", profileID: null }));
};

Object.defineProperty(P, "apiModelChoices", {
  get(this: AppModel) {
    const profile = this.llmConfiguration.activeProfile;
    if (!profile) return [];
    const choices = [...profile.savedModelIDs];
    for (const id of this.llmConfiguration.listedModels[profile.id] ?? []) if (!choices.includes(id)) choices.push(id);
    if (profile.modelID && !choices.includes(profile.modelID)) choices.unshift(profile.modelID);
    return choices;
  },
});

P.refreshActiveAPIModels = async function () {
  const profile = this.llmConfiguration.activeProfile;
  if (this.llmConfiguration.mode !== "api" || !profile) return;
  const key = await LLMKeys.read(profile).catch(() => "");
  if (!Profiles.isLoopback(profile) && !key) return;
  const models = await RemoteLLM.models(profile, key).catch(() => []);
  if (models.length) this.llmConfiguration.setListedModels(models, profile.id);
};

P.useAPIModel = function (modelID) {
  this.llmConfiguration.setMode("api");
  this.llmConfiguration.selectModel(modelID);
  this.ensureChat();
  if (this.currentChatID) this.mutateChat(this.currentChatID, (s) => ({ ...s, modelMode: "api", profileID: this.llmConfiguration.activeID }));
};

P.useChatProfile = function (id) {
  if (!this.llmConfiguration.profiles.some((p) => p.id === id)) return;
  this.llmConfiguration.setMode("api");
  this.llmConfiguration.activate(id);
  this.ensureChat();
  if (this.currentChatID) this.mutateChat(this.currentChatID, (s) => ({ ...s, modelMode: "api", profileID: id }));
};

P.citationIsOpenable = function (c) {
  if (c.meetingID) return this.meetings.some((m) => m.id === c.meetingID);
  if (c.sourceID) return this.sources.some((s) => s.id === c.sourceID);
  return !!c.url;
};

P.openCitation = function (c) {
  if (c.meetingID && this.meetings.some((m) => m.id === c.meetingID)) {
    this.openMeeting(c.meetingID);
    if (CitationKind.of(c) === "summary") this.detailTabRequest = { meetingID: c.meetingID, tab: "summary", token: newID() };
    else {
      const d = this.citationDetails(c);
      const at = d.lineAt ?? d.at;
      if (at != null) this.jumpTranscript(c.meetingID, at);
    }
    return this.changed();
  }
  if (c.sourceID) {
    const source = this.sources.find((s) => s.id === c.sourceID);
    if (source) {
      const file = SourceStore.fileURL(source);
      if (file.toLowerCase().endsWith(".pdf")) this.showPDF(file, c.page ?? null, c.quote ?? null);
      else void shell.openPath(file);
      return;
    }
  }
  if (c.chatID) {
    const chat = this.chats.find((x) => x.id === c.chatID);
    if (chat) {
      if (chat.anchorMeetingID && this.meetings.some((m) => m.id === chat.anchorMeetingID)) {
        this.openChat(chat.id, chat.anchorMeetingID);
        this.openMeeting(chat.anchorMeetingID);
      } else {
        this.openChat(chat.id);
        this.page = "ask";
        this.changed();
      }
      return;
    }
  }
  if (c.url) void shell.openURL(c.url);
};

function joinedAnswer(current: string, next: string) {
  const piece = next.trim();
  if (!piece) return current;
  const base = current.trim();
  return base ? base + "\n\n" + piece : piece;
}

function setRun(m: AppModel, id: string, change: (r: ChatRun) => ChatRun) {
  const run = m.chatRuns[id];
  if (!run) return;
  m.chatRuns = { ...m.chatRuns, [id]: change(run) };
  m.changed();
}

P.beginStep = function (chatID, kind, title, count = 0) {
  const step = { ...newStep(kind, title, nowReference()), count };
  setRun(this, chatID, (r) => ({ ...r, steps: [...r.steps, step] }));
  return step.id;
};

P.finishStep = function (chatID, stepID, detail) {
  setRun(this, chatID, (r) => ({ ...r, steps: r.steps.map((s) => (s.id === stepID && isRunning(s) ? { ...s, detail, endedAt: nowReference() } : s)) }));
};

function markThinking(m: AppModel, chatID: string, stepID: string) {
  const step = m.chatRuns[chatID]?.steps.find((s) => s.id === stepID);
  if (!step || !isRunning(step) || step.kind === "thinking") return;
  setRun(m, chatID, (r) => ({ ...r, steps: r.steps.map((s) => (s.id === stepID ? { ...s, kind: "thinking", title: tr("正在思考…") } : s)) }));
}

function finishWaiting(m: AppModel, chatID: string, stepID: string) {
  const run = m.chatRuns[chatID];
  const step = run?.steps.find((s) => s.id === stepID);
  if (!run || !step || !isRunning(step)) return;
  const thought = run.thinking.trim();
  setRun(m, chatID, (r) => ({ ...r, steps: r.steps.map((s) => (s.id === stepID ? { ...s, thought } : s)) }));
  m.finishStep(chatID, stepID, thought ? trf("思考了 %d 秒", stepSeconds(step, nowReference())) : "");
}

P.ask = function (question0, o = {}) {
  const question = question0.trim();
  const images = o.images ?? [];
  const anchor = o.anchor ?? null;
  if (!question && !images.length) return false;
  if (!o.chatID) {
    if (anchor) this.ensureMeetingChat(anchor);
    else this.ensureChat();
  }
  const id = o.chatID ?? (anchor ? this.meetingChatID[anchor] : null) ?? this.currentChatID;
  const session = id ? this.chats.find((c) => c.id === id) : null;
  if (!id || !session || this.chatRuns[id] || !this.canStartAnotherAnswer || !this.canGenerateAssistant) {
    this.chatError = tr("现在不能提问。");
    this.changed();
    return false;
  }
  const boundMeeting = anchor ?? session.anchorMeetingID ?? null;
  const boundClass = boundMeeting ? this.meetings.find((m) => m.id === boundMeeting) ?? null : null;
  const meetingItems = this.chatMeetingItems();
  const sourceItems = this.chatSourceItems();
  let chosenMeetings: Set<string>;
  let chosenSources: Set<string>;
  let hasScope: boolean;
  if (boundMeeting) {
    chosenMeetings = new Set([boundMeeting]);
    chosenSources = new Set(this.meetingLinks[boundMeeting] ?? []);
    const meeting = boundClass ? this.current(boundClass) : null;
    const hasText = meeting?.paragraphs.some((p) => renderedSource(p, meeting.sourceLanguage)) ?? false;
    hasScope = hasText || chosenSources.size > 0;
  } else {
    chosenMeetings = Scope.selectedMeetings(session.scope, meetingItems);
    chosenSources = Scope.selectedSources(session.scope, sourceItems);
    hasScope = chosenMeetings.size > 0 || chosenSources.size > 0;
  }
  this.chatError = null;
  const pictures = images.filter((d) => !isDraftFile(d));
  const allowsWeb = session.allowsWeb && this.webSearch.isActiveReady;
  const mode = this.llmConfiguration.mode;
  const profile = this.llmConfiguration.activeProfile;
  const name = this.assistantModelName;
  const language = this.prompts.modelLanguageName;
  const remembered = this.memoryPrompt(question);
  const history = session.turns;
  const chatSummary = session.summary ?? null;
  const pickedMeetings = this.meetings.filter((m) => chosenMeetings.has(m.id)).map((m) => this.current(m));
  this.mutateChat(id, (s) => ({ ...s, modelMode: mode, profileID: mode === "api" ? profile?.id ?? null : null }));
  const controller = new AbortController();
  const signal = controller.signal;
  this.chatControllers[id] = controller;
  this.chatRuns = { ...this.chatRuns, [id]: { question, images, mode, answer: "", citations: [], steps: [], thinking: "", startedAt: Date.now() } };
  this.changed();

  const run = async () => {
    let attached: KnowledgeSource[] = [];
    try {
      attached = await this.addChatFiles(images.filter(isDraftFile), boundMeeting);
      for (const s of attached) chosenSources.add(s.id);
      const attachedIDs = new Set(attached.map((s) => s.id));
      const pickedSources = this.sources.filter((s) => chosenSources.has(s.id) && !attachedIDs.has(s.id));
      const contextBudget = ContextBudgets.current(mode, profile);
      const usesMessages = mode === "api";
      const fileBlocks: ContextBlock[][] = [];
      if (attached.length) {
        const names = attached.map((s) => s.fileName).join("、");
        const step = this.beginStep(id, "files", trf("正在读取 %@…", AnswerStepSummary.quoted(names)), attached.length);
        for (const source of attached) fileBlocks.push(await this.passageBlocks([], [source]));
        this.finishStep(id, step, attached.length === 1 ? trf("读取了 %@", AnswerStepSummary.quoted(names)) : trf("读取了 %d 个文件 · %@", attached.length, AnswerStepSummary.quoted(names)));
      }
      const filePassages = ChatContext.packFiles(fileBlocks, question, contextBudget.scope);
      if (attached.length && !filePassages.length) throw new Error(tr("附加的文件里没有可以阅读的文字。"));
      const fileUsed = filePassages.reduce((n, b) => n + [...b.body].length, 0);
      const scopeBudget = attached.length ? Math.max(Math.floor(contextBudget.scope / 4), contextBudget.scope - fileUsed) : contextBudget.scope;
      const scopeStep = !pickedMeetings.length && !pickedSources.length ? null : this.beginStep(id, "files", tr("正在阅读所选的课和资料…"));
      const packed = [...filePassages, ...ChatContext.pack(await this.passageBlocks(pickedMeetings, pickedSources, scopeBudget), question, scopeBudget)];
      if (scopeStep) this.finishStep(id, scopeStep, trf("读了 %d 段课和资料", packed.length - filePassages.length));
      if (hasScope && !packed.length) throw new Error(tr("所选范围里还没有可以阅读的文字。"));
      check(signal);
      const seesImages = ChatImages.seesImages(mode, profile?.modelID ?? "");
      const imagePlan = ChatImages.attachedImages(history, pictures.length);
      const promptImages = seesImages ? await promptImagesFor(pictures, imagePlan.history) : [];
      const historyWindow = ChatHistory.window(history, contextBudget, { summary: chatSummary, omittedImageTurns: seesImages ? imagePlan.omittedTurnIDs : new Set(), stableStart: usesMessages });
      let blocks = [...packed];
      let answer = "";
      const briefs: string[] = [];
      let webNotice: string | null = null;
      let searched = false;
      let prefetched = false;
      let webReachable = allowsWeb;
      let library: LibraryTool = this.hasLibrary ? "available" : "off";
      let libraryDocs: LibraryDocument[] | null = null;
      const excluded: LibraryExclusions = { turns: historyWindow.includedTurns, meetings: chosenMeetings, sources: chosenSources };
      const searchLibrary = async (request: LibraryRequest) => {
        const step = this.beginStep(id, "library", trf("正在资料库中搜索「%@」…", AnswerStepSummary.quoted(request.query)));
        if (!libraryDocs) libraryDocs = await libraryDocuments(this, excluded);
        const found = LibrarySearch.run(request, libraryDocs, new Date(), contextBudget.library);
        this.finishStep(id, step, found.length ? trf("在资料库找到 %d 段", found.length) : tr("资料库里没有找到相关内容"));
        return found;
      };
      const searchWeb = async (queries: string[]) => {
        const shown = queries.map((q) => `「${AnswerStepSummary.quoted(q)}」`).join("");
        const step = this.beginStep(id, "web", trf("正在联网搜索%@…", shown));
        const found = await this.searchPasses(queries, signal);
        const sites = AnswerStepSummary.sites(found.blocks);
        this.finishStep(id, step, !found.blocks.length ? tr("联网搜索没有结果") : sites ? trf("找到 %d 个网页 · %@", found.blocks.length, sites) : trf("找到 %d 个网页", found.blocks.length));
        return found;
      };
      const searchesFirst = boundClass ? LibraryRequests.pointsOutsideClass(question, toDate(boundClass.startedAt)) : LibraryRequests.referencesPast(question);
      if (library === "available" && searchesFirst) {
        const found = await searchLibrary(libraryRequest(question, undefined, LibraryDates.range(question)));
        check(signal);
        if (found.length) {
          blocks = [...blocks, ...found];
          library = "prefetched";
        }
      }
      if (allowsWeb) {
        const query = ChatContext.searchQuery(question, history);
        if (query) {
          const found = await searchWeb([query]);
          if (!found.blocks.length) {
            if (found.notice) {
              webNotice = found.notice;
              webReachable = false;
            }
          } else {
            blocks = [...blocks, ...found.blocks];
            prefetched = true;
          }
        }
      }
      const thinkingLevel: ThinkingLevel = usesMessages && profile ? Profiles.effectiveThinking(profile) : "off";
      let messages: LLMMessage[] = [];
      let system = "";
      let sentPassages = 0;
      let lastRaw = "";
      const histMessages = historyMessages(historyWindow);
      for (let round = 0; round < 3; round++) {
        const webTool: WebTool = !webReachable ? "off" : searched ? "used" : prefetched ? "prefetched" : "available";
        const libraryOpen = library === "available" || library === "prefetched";
        const mayStillSearch = (webReachable && !searched) || libraryOpen;
        const currentClass = boundClass ? ChatContext.classLabel(boundClass.title, toDate(boundClass.startedAt)) : null;
        let request: LLMRequest;
        if (usesMessages) {
          if (round === 0) {
            system = ChatContext.composedSystemPrompt({ language, allowsWeb, hasPassages: blocks.length > 0, skills: this.prompts.skills, tools: true, webTool, library, currentClass, memory: remembered });
            const prompt = ChatContext.userPrompt({ question, history: forMessages(historyWindow), blocks, mentionsOlderImages: seesImages && imagePlan.mentionsOlderImages, mentionsLibrary: libraryOpen, steered: o.steered, attachedFiles: attached.map((s) => s.title) });
            messages = [...histMessages, { role: "user", text: prompt, images: promptImages }];
          } else {
            messages[histMessages.length] = { ...messages[histMessages.length], cacheMark: true };
            messages.push({ role: "assistant", text: lastRaw, images: [] });
            messages.push({
              role: "user",
              text: ChatContext.continuationPrompt({ newBlocks: blocks.slice(sentPassages), offset: sentPassages, webFinished: allowsWeb && (searched || !webReachable), libraryFinished: library === "used", draftEmpty: !answer.trim(), searchFailed: webNotice !== null }),
              images: [],
            });
          }
          sentPassages = blocks.length;
          request = { system, messages: [...messages], thinking: thinkingLevel, cacheKey: id, label: round === 0 ? "answer" : `answer-${round + 1}` };
        } else {
          const localSystem = ChatContext.composedSystemPrompt({ language, allowsWeb: blocks.length > packed.length, hasPassages: blocks.length > 0, skills: this.prompts.skills, tools: true, webTool, library, currentClass, memory: remembered });
          let prompt = ChatContext.userPrompt({ question, history: historyWindow, blocks, mentionsOlderImages: seesImages && imagePlan.mentionsOlderImages, mentionsLibrary: libraryOpen, steered: o.steered, attachedFiles: attached.map((s) => s.title) });
          if (round > 0) {
            const draft = answer.trim();
            prompt += draft ? `\n\nDraft already shown to the user:\n${draft}\n\nContinue from here. Do not repeat the draft.` : "\n\nThe lookup finished and its results are in the numbered passages. Answer the question in Markdown.";
            if (webNotice !== null && blocks.length === packed.length) prompt += "\n\nThe search returned nothing. Answer from the material you already have.";
          }
          request = singleRequest(localSystem, prompt, promptImages, "answer");
        }
        const carried = answer;
        const cited = blocks;
        const thinks = thinkingLevel !== "off";
        const waitStep = this.beginStep(id, thinks ? "thinking" : "writing", thinks ? tr("正在思考…") : round === 0 ? tr("正在写回答…") : tr("正在继续写回答…"));
        setRun(this, id, (r) => ({ ...r, thinking: "" }));
        const text = await this.completeChat(mode, profile, request, {
          signal,
          onProgress: (progress) => {
            if (progress.thinking) {
              setRun(this, id, (r) => ({ ...r, thinking: progress.thinking }));
              markThinking(this, id, waitStep);
            }
            const shown = ChatTools.parse(ChatContext.streamingDisplay(progress.answer), true, mayStillSearch).visible;
            if (shown.trim()) finishWaiting(this, id, waitStep);
            const combined = joinedAnswer(carried, shown);
            setRun(this, id, (r) => ({ ...r, answer: combined, citations: ChatContext.citations(combined, cited) }));
          },
        });
        finishWaiting(this, id, waitStep);
        check(signal);
        lastRaw = text;
        const parsed = ChatTools.parse(ChatContext.splitVisual(text, false).text, false, mayStillSearch);
        answer = joinedAnswer(answer, parsed.visible);
        briefs.push(...parsed.calls.filter((c) => c.name === ChatTools.createDemo).map((c) => c.body));
        const queries = parsed.calls.filter((c) => c.name === ChatTools.webSearch).map((c) => c.body);
        const libraryCalls = parsed.calls.filter((c) => c.name === ChatTools.searchLibrary).map((c) => c.body);
        let looked = false;
        if (libraryOpen && libraryCalls.length) {
          looked = true;
          library = "used";
          blocks = [...blocks, ...(await searchLibrary(LibraryRequests.parse(libraryCalls[0])))];
          check(signal);
        }
        if (webReachable && !searched && queries.length) {
          looked = true;
          searched = true;
          const found = await searchWeb(queries.slice(0, 2));
          if (!found.blocks.length) {
            if (!prefetched) webNotice = found.notice ?? tr("联网搜索没有返回结果，这次只根据会议和资料回答。");
          } else blocks = [...blocks, ...found.blocks];
        }
        if (!looked) break;
      }
      const current = this.chatRuns[id];
      const stored = await storedImages(images);
      const turnID = finishChat(this, id, {
        question, answer, modelName: name, citations: ChatContext.citations(answer, blocks), error: null, images: stored, files: fileRefs(attached),
        steps: current?.steps ?? [], seconds: current ? (Date.now() - current.startedAt) / 1000 : null,
      });
      clearRun(this, id);
      if (webNotice) this.chatError = webNotice;
      this.scheduleAfterAnswerWork(id);
      const skipsDemo = ChatContext.skipsDemo(question, library !== "available" && library !== "off");
      const brief = skipsDemo ? null : [...briefs].reverse().find((b) => b.trim()) ?? null;
      const fallback = !skipsDemo && !brief && mode === "api" && ChatContext.wantsFallbackVisual(question, answer);
      const queueWaiting = mode === "local" && this.chatQueue.some((q) => !this.queuePaused.has(q.chatID));
      if (turnID && (brief || fallback) && !queueWaiting) startVisual(this, { chatID: id, turnID, brief, question, answer, mode, profile, language });
      this.chatDidEnd(id, true);
    } catch (error) {
      if (isCancel(error) || signal.aborted) {
        chatWasStopped(this, id, question, images, name, attached);
      } else {
        finishChat(this, id, { question, answer: "", modelName: name, citations: [], error: error instanceof Error ? error.message : String(error), images: await storedImages(images), files: fileRefs(attached) });
        clearRun(this, id);
        this.chatDidEnd(id, false);
      }
    } finally {
      clearRun(this, id);
      delete this.chatControllers[id];
      this.changed();
    }
  };
  void run();
  return true;
};

function clearRun(m: AppModel, id: string) {
  if (!(id in m.chatRuns)) return;
  const next = { ...m.chatRuns };
  delete next[id];
  m.chatRuns = next;
  m.changed();
}

P.stopChat = function (chatID) {
  this.chatControllers[chatID]?.abort();
};

P.searchPasses = async function (queries, signal) {
  const blocks: ContextBlock[] = [];
  let notice: string | null = null;
  for (const query of queries) {
    const text = query.trim();
    if (!text) continue;
    try {
      const hits = await this.webSearch.lookup([...text].slice(0, 300).join(""));
      if (signal?.aborted) throw new CancellationError();
      blocks.push(...hits.map(hitBlock));
    } catch (error) {
      if (isCancel(error) || signal?.aborted) throw new CancellationError();
      notice = error instanceof Error ? error.message : String(error);
    }
  }
  return { blocks, notice };
};

P.completeChat = async function (mode, profile, request, o) {
  if (mode === "api") {
    if (!profile) throw new Error(tr("请先在设置中选择 API 配置。"));
    const key = await LLMKeys.read(profile);
    if (!Profiles.isLoopback(profile) && !key) throw new Error(tr("请输入 API 密钥。"));
    const result = await RemoteLLM.stream(profile, key, request, o.onProgress, o.signal);
    this.llmConfiguration.noteUnsupported(profile.id, !!result.responsesRejected, !!result.thinkingRejected);
    return result.answer;
  }
  await this.waitForAfterAnswerWork();
  await this.waitForQuestionWork();
  check(o.signal);
  const prompt = request.messages.at(-1)?.text ?? "";
  return this.engine.generate(request.system, prompt, { maxTokens: o.localMaxTokens ?? 2048, signal: o.signal, onUpdate: (text) => o.onProgress({ answer: text, thinking: "" }) });
};

function startVisual(m: AppModel, o: { chatID: string; turnID: string; brief: string | null; question: string; answer: string; mode: LLMMode; profile: LLMAPIProfile | null; language: string }) {
  const requested = o.brief !== null;
  m.preparingVisualTurnIDs.add(o.turnID);
  const controller = new AbortController();
  m.visualControllers[o.turnID] = controller;
  m.changed();
  void (async () => {
    let claimed = false;
    try {
      if (o.mode === "local") {
        while (m.localVisualBusy || Object.values(m.chatRuns).filter((r) => r.mode === "local").length >= LocalEngine.maxReplies) {
          await new Promise((r) => setTimeout(r, 200));
          check(controller.signal);
        }
        m.localVisualBusy = true;
        claimed = true;
      }
      const system = ChatContext.visualSystemPrompt(o.language);
      let prompt = ChatContext.visualUserPrompt(o.brief, o.question, o.answer);
      const attempts = o.mode === "api" ? 2 : 1;
      for (let attempt = 0; attempt < attempts; attempt++) {
        check(controller.signal);
        const visual = await m.completeChat(o.mode, o.profile, singleRequest(system, prompt, [], "demo"), { localMaxTokens: 4096, signal: controller.signal, onProgress: () => {} });
        check(controller.signal);
        if (visual.trim().toUpperCase() === "NONE") return;
        const fence = ChatContext.htmlFence(visual);
        if (fence && ChatContext.rendersWidget(fence)) {
          m.mutateChat(o.chatID, (s) => ({ ...s, turns: s.turns.map((t) => (t.id === o.turnID && !t.answer.includes(fence) ? { ...t, answer: t.answer + "\n\n" + fence } : t)) }));
          return;
        }
        if (attempt === 0) prompt = ChatContext.visualRetryPrompt(prompt);
      }
      if (requested) m.chatError = tr("这次没能生成图示。");
    } catch (error) {
      if (!isCancel(error) && !controller.signal.aborted) m.chatError = error instanceof Error ? error.message : String(error);
    } finally {
      m.preparingVisualTurnIDs.delete(o.turnID);
      delete m.visualControllers[o.turnID];
      if (claimed) m.localVisualBusy = false;
      m.changed();
    }
  })();
}

P.chatMeetingItems = function () {
  return this.meetings.map((m) => ({ id: m.id, categoryID: m.categoryID ?? null, live: m.isLive }));
};

P.chatSourceItems = function () {
  return this.sources.map((s) => ({ id: s.id, categoryID: s.categoryID ?? null }));
};

P.chatCategoryNames = function () {
  return [...[...this.categories].sort((a, b) => a.sortOrder - b.sortOrder).map((c) => ({ id: c.id, name: c.name })), { id: null, name: tr("未分类") }];
};

P.appendTurnToMeetingChat = function (meetingID, turn) {
  this.ensureMeetingChat(meetingID);
  const id = this.meetingChatID[meetingID];
  if (id) this.mutateChat(id, (s) => ({ ...s, turns: [...s.turns, turn] }));
};

P.mutateChat = function (id, body, touch = true) {
  const index = this.chats.findIndex((c) => c.id === id);
  if (index < 0) return;
  const next = body(this.chats[index]);
  const updated = touch ? { ...next, updatedAt: nowReference() } : next;
  this.chats = this.chats.map((c, i) => (i === index ? updated : c));
  this.changed();
  if (this.chatsReady && updated.turns.length) this.saveChat(updated);
};

P.saveChat = function (session) {
  ChatStore.save(session).catch(() => {
    this.chatError = tr("无法保存对话。");
    this.changed();
  });
};

function chatWasStopped(m: AppModel, id: string, question: string, images: ChatImageDraft[], modelName: string, attached: KnowledgeSource[]) {
  const steer = m.pendingSteers[id];
  if (!steer) {
    m.composerImages[id] = images;
    const showing = m.currentChatID === id || Object.values(m.meetingChatID).includes(id);
    if (showing) m.chatDraftRestore = question;
    clearRun(m, id);
    m.chatDidEnd(id, false);
    return;
  }
  delete m.pendingSteers[id];
  const run = m.chatRuns[id];
  const shown = (run?.answer ?? "").trim();
  void (async () => {
    const turnID = finishChat(m, id, { question, answer: shown, modelName, citations: run?.citations ?? [], error: null, images: await storedImages(images), files: fileRefs(attached), steps: run?.steps ?? [] });
    if (turnID) m.mutateChat(id, (s) => ({ ...s, turns: s.turns.map((t) => (t.id === turnID ? { ...t, interrupted: true } : t)) }), false);
    clearRun(m, id);
    setTimeout(() => {
      if (!m.ask(steer.text, { images: steer.images, chatID: id, steered: true })) {
        m.chatQueue = [steer, ...m.chatQueue];
        m.queuePaused.add(id);
        m.changed();
      }
    }, 0);
  })();
}

function finishChat(m: AppModel, id: string, o: { question: string; answer: string; modelName: string; citations: ChatCitation[]; error: string | null; images?: ChatImage[]; files?: ChatFileRef[]; steps?: ChatRun["steps"]; seconds?: number | null }): string | null {
  if (!m.chats.some((c) => c.id === id)) return null;
  const turn = newTurn(o.question, o.answer, o.modelName, { citations: o.citations, error: o.error, images: o.images ?? [], files: o.files?.length ? o.files : null });
  const kept = AnswerStepSummary.kept(o.steps ?? []);
  if (kept.length) turn.steps = kept;
  if (!o.error) turn.answerSeconds = o.seconds ?? null;
  m.mutateChat(id, (s) => {
    let title = s.title;
    if (!s.titleCustom && !title) {
      const source = o.question || o.files?.[0]?.name || o.images?.[0]?.name || "";
      title = [...source].slice(0, 20).join("");
    }
    return { ...s, title, turns: [...s.turns, turn] };
  });
  return turn.id;
}

async function storedImages(drafts: ChatImageDraft[]): Promise<ChatImage[]> {
  for (const d of drafts.filter(isDraftFile)) void ChatImages.discard(d);
  const out: ChatImage[] = [];
  for (const d of drafts.filter((x) => !isDraftFile(x))) {
    const image = await ChatImages.promote(d);
    if (image) out.push(image);
  }
  return out;
}

const fileRefs = (sources: KnowledgeSource[]): ChatFileRef[] => sources.map((s) => ({ sourceID: s.id, name: s.fileName }));

P.addChatFiles = async function (drafts, meetingID) {
  const meeting = meetingID ? this.meetings.find((m) => m.id === meetingID) ?? null : null;
  const added: KnowledgeSource[] = [];
  for (const draft of drafts.filter(isDraftFile)) {
    const existing = await existingSource(this, draft);
    if (existing) {
      added.push(existing);
      continue;
    }
    try {
      const source = await SourceStore.stage(draft.fileURL, meeting?.categoryID ?? null);
      this.sources = [...this.sources, source];
      added.push(source);
    } catch (error) {
      this.chatError = trf("无法加入 %@：%@", draft.name, error instanceof Error ? error.message : String(error));
    }
  }
  if (meetingID && meeting && added.length) {
    const links = this.meetingLinks[meetingID] ?? [];
    this.meetingLinks = { ...this.meetingLinks, [meetingID]: [...links, ...added.map((s) => s.id).filter((x) => !links.includes(x))] };
  }
  return added;
};

async function existingSource(m: AppModel, draft: ChatImageDraft): Promise<KnowledgeSource | null> {
  if (!isDraftFile(draft)) return null;
  const stat = await fs.stat(draft.fileURL);
  if (!stat) return null;
  return m.sources.find((s) => s.fileName === safeFileName(draft.name) && s.byteCount === stat.size) ?? null;
}

async function promptImagesFor(current: ChatImageDraft[], history: ChatImage[]): Promise<ModelImage[]> {
  const out: ModelImage[] = [];
  for (const d of current.slice(0, ChatImages.countLimit)) {
    const payload = await ChatImages.payload(d.fileURL, d.mime);
    if (payload) out.push(payload);
  }
  for (const image of history) {
    if (out.length >= ChatImages.countLimit) break;
    const payload = await ChatImages.payload(ChatImages.fileURL(image), image.mime);
    if (payload) out.push(payload);
  }
  return out;
}

Object.defineProperty(P, "hasLibrary", {
  get(this: AppModel) {
    return this.sources.length > 0 || this.meetings.some((m) => this.current(m).paragraphs.length > 0) || this.chats.some((c) => c.turns.length > 0 && !this.chatRuns[c.id]);
  },
});

async function libraryDocuments(m: AppModel, excluded: LibraryExclusions): Promise<LibraryDocument[]> {
  const docs: LibraryDocument[] = [];
  for (const meeting of m.meetings.map((x) => m.current(x))) {
    if (excluded.meetings.has(meeting.id)) continue;
    docs.push(
      ...LibrarySearch.meetingDocuments(
        meeting.id,
        meeting.title,
        toDate(meeting.startedAt),
        shownParagraphs(meeting).map((p) => ({ openedAt: p.openedAt, source: renderedSource(p, meeting.sourceLanguage), translation: renderedTranslation(p, meeting.targetLanguage) })),
        meeting.assistant?.summary,
      ),
    );
  }
  for (const chat of m.chats) {
    const turns = chat.turns.filter((t) => !excluded.turns.has(t.id)).map((t) => ({ ...t, createdAt: toDate(t.createdAt) }));
    docs.push(...LibrarySearch.chatDocuments(chat.id, turns, chat.summary ? { text: chat.summary.text, throughDate: toDate(chat.summary.throughDate) } : null));
  }
  SourceTextCache.keepOnly(new Set(m.sources.map((s) => s.id)));
  for (const source of m.sources.filter((s) => !excluded.sources.has(s.id))) {
    const blocks = await SourceTextCache.blocks(source, SourceStore.fileURL(source));
    docs.push(...LibrarySearch.sourceDocuments({ id: source.id, importedAt: toDate(source.importedAt) }, blocks));
  }
  return docs;
}

P.passageBlocks = async function (meetings, sources, summaryAbove = Number.MAX_SAFE_INTEGER) {
  const blocks: ContextBlock[] = [];
  for (const meeting of meetings) {
    const length = meeting.paragraphs.reduce((n, p) => n + [...renderedSource(p, meeting.sourceLanguage)].length, 0);
    const summary = meeting.assistant?.summary;
    if (length > summaryAbove && summary) blocks.push({ title: meeting.title, detail: tr("会议摘要"), body: summary, meetingID: meeting.id, pinned: true });
    for (const p of shownParagraphs(meeting)) {
      const text = renderedSource(p, meeting.sourceLanguage).trim();
      if (text) blocks.push({ title: meeting.title, detail: formatClock(p.openedAt), body: text, meetingID: meeting.id, at: p.openedAt });
    }
  }
  for (const source of sources) blocks.push(...(await SourceTextCache.blocks(source, SourceStore.fileURL(source))));
  return blocks;
};

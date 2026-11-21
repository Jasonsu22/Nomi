// App/AppModel.swift: the app's state and actions. Feature files (chat.ts, qa.ts, …) add methods
// to this class the way the Mac's AppModel+*.swift extensions do.
import { tr, trf } from "../i18n";
import { formatMeetingTime, newID, nowReference, toDate } from "../support/format";
import { LectureLanguages } from "../support/languages";
import { prefs } from "../support/prefs";
import { dialogs, fs, paths, shell } from "../platform";
import { categoryMatches, CategoryFilterStore, MeetingGroupingStore, placing, type CategoryFilter, type MeetingCategory, type MeetingGrouping } from "../models/category";
import { liveMeeting, meetingMarkdown, transcriptEnd, type Meeting } from "../models/meeting";
import type { KnowledgeSource } from "../models/knowledgeSource";
import { renderedSource, renderedTranslation, type Paragraph } from "../models/transcript";
import { RepeatCleanup } from "../models/repeatCleanup";
import { TranscriptionTopic } from "../models/transcriptionTopic";
import { SourceText, SourceTextCache } from "../models/sourceText";
import type { ChatSession, ChatCitation } from "../models/chatSession";
import type { ChatImageDraft } from "../models/chatImage";
import type { AnswerStep } from "../models/answerSteps";
import type { MeetingAssistantRecord } from "../models/meeting";
import type { MeetingQA } from "../models/meetingQA";
import { UserMemory } from "../models/userMemory";
import { LLMConfiguration, type LLMMode } from "../models/llmConfiguration";
import { PromptPreferences } from "../models/promptPreferences";
import { selectedModel, type LocalModelDefinition, type LocalModelRole } from "../models/localModels";
import type { VoiceSpan } from "../models/meetingVoices";
import { SearchConfiguration } from "../engine/search";
import { AudioInputs } from "../engine/audioInputs";
import { LocalEngine } from "../engine/localEngine";
import { ChatStore, MeetingSourceLinkStore, MeetingStore, SourceStore } from "./stores";
import { LocalModelLibrary } from "./localModelLibrary";
import { AppUpdater } from "./updater";

export type AppPage = "meetings" | "ask" | "sources" | "help" | "settings";
export const keptAlive: AppPage[] = ["meetings", "sources", "ask"];
export const pageTitle = (p: AppPage) => ({ meetings: tr("会议"), ask: tr("提问"), sources: tr("资料"), help: tr("帮助"), settings: tr("设置") })[p];

export type TutorialStop = "meetings" | "record" | "sources" | "chat" | "settings";
export const tutorialStops: TutorialStop[] = ["meetings", "record", "sources", "chat", "settings"];

export type DetailTab = "transcript" | "ask" | "qa" | "summary" | "sources" | "info";
export type DetailTabRequest = { meetingID: string; tab: DetailTab; token: string };
export type TranscriptJump = { meetingID: string; time: number; token: string; createdAt: number };
export type QuestionPopup = { meetingID: string; questionID: string; answering: boolean };
export type PDFViewerRequest = { id: string; path: string; page: number | null; quote: string | null };

export type ChatRun = {
  question: string;
  images: ChatImageDraft[];
  mode: LLMMode;
  answer: string;
  citations: ChatCitation[];
  steps: AnswerStep[];
  thinking: string;
  startedAt: number;
};

export type QueuedPrompt = { id: string; chatID: string; text: string; images: ChatImageDraft[]; createdAt: number };

export type AssistantAnswer = { id: string; question: string; answer: string; modelName: string; createdAt: number };
export class MeetingAssistantState {
  answers: AssistantAnswer[] = [];
  summary: string | null = null;
  summaryModelName = "";
  isGenerating = false;
  generatingSummary = false;
  draft = "";
  error: string | null = null;
  controller: AbortController | null = null;
  constructor(record?: MeetingAssistantRecord | null) {
    if (!record) return;
    this.summary = record.summary ?? null;
    this.summaryModelName = record.summaryModelName ?? "";
    this.answers = record.answers.map((a) => ({ ...a }));
  }
}

type Listener = () => void;

export class AppModel {
  // Pages and sheets
  page: AppPage = "meetings";
  tutorialStep: TutorialStop | null = null;
  onboardingPresented = false;
  revealSearchSettings = false;
  revealMemorySettings = false;
  recordingSetupPresented = false;
  recordingResumeID: string | null = null;
  exportError: string | null = null;
  storageError: string | null = null;
  sourceError: string | null = null;
  pdfViewer: PDFViewerRequest | null = null;
  enlargedImage: { path: string; name: string } | null = null;

  // Meetings
  private _meetings: Meeting[] = [];
  private _categories: MeetingCategory[] = [];
  private _filter: CategoryFilter = { kind: "all" };
  private _grouping: MeetingGrouping = "time";
  private _query = "";
  appliedQuery = "";
  searchRequest = 0;
  private _openMeetingID: string | null = null;
  meetingCompact = false;
  checkingVoices = new Set<string>();
  voiceError: Record<string, string> = {};
  liveSpeakerSpans: VoiceSpan[] = [];
  liveSpeakerPrints: Record<string, number[]> = {};
  transcriptJump: TranscriptJump | null = null;
  questionPopup: QuestionPopup | null = null;
  questionPopupQueue: QuestionPopup[] = [];
  urgentQuestionID: string | null = null;
  detailTabRequest: DetailTabRequest | null = null;
  assistantStates: Record<string, MeetingAssistantState> = {};
  qaStates: Record<string, MeetingQA> = {};

  // Sources
  private _sources: KnowledgeSource[] = [];
  private _meetingLinks: Record<string, string[]> = {};

  // Chat
  chats: ChatSession[] = [];
  currentChatID: string | null = null;
  meetingChatID: Record<string, string> = {};
  chatRuns: Record<string, ChatRun> = {};
  composerImages: Record<string, ChatImageDraft[]> = {};
  chatQueue: QueuedPrompt[] = [];
  queuePaused = new Set<string>();
  pendingSteers: Record<string, QueuedPrompt> = {};
  preparingVisualTurnIDs = new Set<string>();
  chatError: string | null = null;
  chatDraftRestore: string | null = null;
  chatFocusRequest = 0;
  chatsReady = false;
  chatControllers: Record<string, AbortController> = {};
  visualControllers: Record<string, AbortController> = {};
  localVisualBusy = false;
  afterAnswerTask: { cancelled: boolean; done: Promise<void> } | null = null;
  afterAnswerGenerating = false;
  summaryFailures: Record<string, number> = {};
  memoryFailures = 0;
  questionWorkGenerating = false;
  questionQueueRunning = false;
  questionScanTimer: ReturnType<typeof setInterval> | null = null;
  quickQuestionTimer: ReturnType<typeof setTimeout> | null = null;
  transcriptionTopicToken = 0;

  // Recording languages
  private _recordingSourceLanguage: string;
  private _recordingTargetLanguage: string;

  // Services
  engine = new LocalEngine();
  audioInputs = new AudioInputs();
  localModels = new LocalModelLibrary();
  llmConfiguration = new LLMConfiguration();
  prompts = new PromptPreferences();
  webSearch = new SearchConfiguration();
  updater = new AppUpdater();
  memory = new UserMemory(true);

  private liveMeetingID: string | null = null;
  private resumedMeetingSnapshot: Meeting | null = null;
  private persistenceEnabled = false;
  private sourcesPersistence = false;
  private meetingLinksReady = false;
  private persistenceTimer: ReturnType<typeof setTimeout> | undefined;
  private searchTimer: ReturnType<typeof setTimeout> | undefined;

  // Change notification, for React.
  private listeners = new Set<Listener>();
  version = 0;
  private frame = 0;

  constructor() {
    const pair = LectureLanguages.currentPair();
    this._recordingSourceLanguage = pair.source;
    this._recordingTargetLanguage = pair.target;
    const notify = () => this.changed();
    this.audioInputs.onChange = notify;
    this.localModels.onChange = notify;
    this.llmConfiguration.onChange = notify;
    this.prompts.onChange = notify;
    this.webSearch.onChange = notify;
    this.memory.onChange = notify;
    this.updater.onChange = notify;
    this.engine.onChange = notify;
    this.engine.transcript.onChange = notify;
    this.engine.onFinished = (paragraphs, duration) => this.finishLiveMeeting(paragraphs, duration);
    this.engine.onInputFallback = (name) => {
      const id = this.liveMeetingID;
      if (!id) return;
      this.meetings = this.meetings.map((m) => (m.id === id ? { ...m, inputDeviceName: name } : m));
    };
    this.engine.onSpeakers = (spans, prints) => {
      this.liveSpeakerSpans = spans;
      this.liveSpeakerPrints = prints;
      this.changed();
    };
    this.engine.transcript.onCommitted = () => {
      this.schedulePersistence();
      this.checkLatestLineForQuestion();
    };
  }

  subscribe(listener: Listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** Something changed; views update on the next frame. */
  changed() {
    if (this.frame) return;
    this.frame = requestAnimationFrame(() => {
      this.frame = 0;
      this.version++;
      this.listeners.forEach((l) => l());
    });
  }

  async load() {
    let stored: Awaited<ReturnType<typeof MeetingStore.load>> = null;
    try {
      stored = await MeetingStore.load();
      this.persistenceEnabled = true;
    } catch {
      this.storageError = tr("无法读取本地会议记录，原文件已保留。");
    }
    let loaded = (stored?.meetings ?? []).filter((m) => m.paragraphs.length || m.duration > 0).map((m) => ({ ...m, isLive: false }));
    let cleaned = false;
    loaded = loaded.map((m) => {
      const fixed = RepeatCleanup.cleaned(m.paragraphs);
      if (!fixed) return m;
      cleaned = true;
      return { ...m, paragraphs: fixed };
    });
    this._meetings = loaded;
    this._categories = stored?.categories ?? [];
    this._filter = CategoryFilterStore.load();
    this._grouping = MeetingGroupingStore.load();
    try {
      this._sources = await SourceStore.load();
      this.sourcesPersistence = true;
      const files = this._sources;
      setTimeout(async () => {
        for (const file of files) await SourceTextCache.blocks(file, SourceStore.fileURL(file)).catch(() => []);
      }, 2000);
    } catch {
      this.sourceError = tr("无法读取资料库，原文件已保留。");
    }
    try {
      this.chats = (await ChatStore.load()).sort((a, b) => b.updatedAt - a.updatedAt);
      this.chatsReady = true;
      this.currentChatID = this.chats.find((c) => !c.anchorMeetingID)?.id ?? null;
    } catch {
      this.chatError = tr("无法读取对话记录，原文件已保留。");
    }
    this._meetingLinks = await MeetingSourceLinkStore.load();
    this.meetingLinksReady = true;
    await this.memory.load();
    if (this._filter.kind === "category" && !this.category(this._filter.id)) {
      this._filter = { kind: "all" };
      CategoryFilterStore.save(this._filter);
    }
    if (cleaned) this.schedulePersistence();
    await this.engine.connect();
    await this.audioInputs.refresh();
    await this.localModels.connect();
    this.engine.launch();
    this.changed();
  }

  // MARK: Observed properties with side effects

  get meetings() {
    return this._meetings;
  }
  set meetings(value: Meeting[]) {
    this._meetings = value;
    this.schedulePersistence();
    this.changed();
  }

  get categories() {
    return this._categories;
  }
  set categories(value: MeetingCategory[]) {
    this._categories = value;
    this.schedulePersistence();
    this.changed();
  }

  get sources() {
    return this._sources;
  }
  set sources(value: KnowledgeSource[]) {
    this._sources = value;
    if (this.sourcesPersistence) SourceStore.save(value).catch(() => (this.sourceError = tr("资料保存失败，请重试。")));
    this.changed();
  }

  get meetingLinks() {
    return this._meetingLinks;
  }
  set meetingLinks(value: Record<string, string[]>) {
    const old = this._meetingLinks;
    this._meetingLinks = value;
    if (this.meetingLinksReady) MeetingSourceLinkStore.save(value).catch(() => (this.sourceError = tr("资料保存失败，请重试。")));
    const id = this.liveMeetingID;
    if (id && JSON.stringify(old[id]) !== JSON.stringify(value[id])) this.refreshTranscriptionTopic(id);
    this.changed();
  }

  get filter() {
    return this._filter;
  }
  set filter(value: CategoryFilter) {
    this._filter = value;
    CategoryFilterStore.save(value);
    this.changed();
  }

  get grouping() {
    return this._grouping;
  }
  set grouping(value: MeetingGrouping) {
    this._grouping = value;
    MeetingGroupingStore.save(value);
    this.changed();
  }

  get query() {
    return this._query;
  }
  set query(value: string) {
    this._query = value;
    clearTimeout(this.searchTimer);
    if (!value.trim()) this.appliedQuery = "";
    else
      this.searchTimer = setTimeout(() => {
        this.appliedQuery = value;
        this.changed();
      }, 150);
    this.changed();
  }

  get openMeetingID() {
    return this._openMeetingID;
  }
  set openMeetingID(value: string | null) {
    this._openMeetingID = value;
    if (value === null) this.meetingCompact = false;
    this.changed();
  }

  get recordingSourceLanguage() {
    return this._recordingSourceLanguage;
  }
  set recordingSourceLanguage(value: string) {
    this._recordingSourceLanguage = value;
    prefs.set(LectureLanguages.sourceKey, value);
    this.changed();
  }

  get recordingTargetLanguage() {
    return this._recordingTargetLanguage;
  }
  set recordingTargetLanguage(value: string) {
    this._recordingTargetLanguage = value;
    prefs.set(LectureLanguages.targetKey, value);
    this.changed();
  }

  /** Assigns several fields and notifies once. */
  set<K extends keyof this>(key: K, value: this[K]) {
    this[key] = value;
    this.changed();
  }

  // MARK: Status

  get canStart() {
    return this.engine.canStart && this.localModels.deletingID === null;
  }

  get canSwitchModels() {
    return this.engine.session.phase === "idle" && this.localModels.switchingID === null && this.localModels.deletingID === null && !this.assistantIsBusy && this.engine.readiness !== "preparing";
  }

  async selectLocalModel(model: LocalModelDefinition, requestedRole?: LocalModelRole) {
    const role = requestedRole ?? (model.role as LocalModelRole);
    if (!this.canSwitchModels) return;
    if (!this.localModels.installed.has(model.id)) {
      await this.localModels.refresh();
      this.localModels.errors[model.id] = tr("模型文件不完整，请重新下载。");
      this.changed();
      return;
    }
    this.localModels.switchingID = model.id;
    this.localModels.switchingRole = role;
    delete this.localModels.errors[model.id];
    this.changed();
    try {
      await this.engine.selectModel(model, role);
      this.localModels.rememberSelection(model, role);
    } catch (error) {
      this.localModels.errors[model.id] = error instanceof Error ? error.message : String(error);
    } finally {
      this.localModels.switchingID = null;
      this.localModels.switchingRole = null;
      this.changed();
    }
  }

  async deleteLocalModel(model: LocalModelDefinition) {
    if (!this.canSwitchModels) return;
    this.localModels.deletingID = model.id;
    delete this.localModels.errors[model.id];
    this.changed();
    try {
      await this.engine.unloadModel(model).catch(() => {});
      await this.localModels.trash(model);
    } catch (error) {
      this.localModels.errors[model.id] = error instanceof Error ? error.message : String(error);
    } finally {
      this.localModels.deletingID = null;
      this.changed();
    }
  }

  get statusTitle(): string {
    const e = this.engine;
    switch (e.session.phase) {
      case "preparing":
        return tr("准备中");
      case "listening":
        return e.session.isPaused ? tr("已暂停") : tr("正在转录");
      case "stopping":
        return tr("正在保存");
      case "idle":
        if (e.loadError) return e.loadError;
        return { preview: tr("预览 · 示例回放"), preparing: tr("准备中"), ready: tr("本机 · 模型就绪"), sourceOnly: tr("本机 · 只出原文"), asrMissing: tr("缺少识别模型"), unavailable: tr("引擎未启动") }[e.readiness];
    }
  }

  get statusIsLive() {
    return this.engine.session.phase === "listening" && !this.engine.session.isPaused;
  }

  get statusStays(): boolean {
    if (this.engine.session.phase !== "idle") return true;
    if (this.engine.loadError) return true;
    return this.engine.readiness !== "ready";
  }

  get statusIsError(): boolean {
    if (this.engine.session.phase !== "idle") return false;
    if (this.engine.loadError) return true;
    return this.engine.readiness === "asrMissing" || this.engine.readiness === "unavailable";
  }

  // MARK: Meetings

  get visibleMeetings(): Meeting[] {
    return this.meetings.filter((m) => this.matches(m));
  }

  count(filter: CategoryFilter) {
    return this.meetings.filter((m) => categoryMatches(m.categoryID, filter)).length;
  }

  category(id: string | null | undefined): MeetingCategory | null {
    if (!id) return null;
    return this.categories.find((c) => c.id === id) ?? null;
  }

  categoryName(meeting: Meeting) {
    return this.category(meeting.categoryID)?.name ?? null;
  }

  select(page: AppPage) {
    if (page === "meetings" && this.page === "meetings") this.openMeetingID = null;
    this.page = page;
    this.changed();
  }

  get resumableMeeting(): Meeting | null {
    if (this.page !== "meetings" || !this.openMeetingID) return null;
    return this.meetings.find((m) => m.id === this.openMeetingID && !m.isLive) ?? null;
  }

  get recordingSetupMeeting(): Meeting | null {
    return this.meetings.find((m) => m.id === this.recordingResumeID) ?? null;
  }

  get recordingActionTitle() {
    return this.resumableMeeting ? tr("继续录制") : tr("开始转录");
  }

  performRecordingAction() {
    const m = this.resumableMeeting;
    if (m) {
      if (this.canRecord) this.resumeTranscription(m.id);
      else this.prepareRecording(m.id);
    } else this.prepareRecording();
  }

  prepareRecording(id: string | null = null) {
    if (this.engine.session.phase !== "idle") return;
    void this.audioInputs.refresh();
    this.recordingResumeID = id;
    this.recordingSetupPresented = true;
    this.changed();
  }

  cancelRecordingSetup() {
    this.recordingSetupPresented = false;
    this.recordingResumeID = null;
    this.changed();
  }

  get canRecord() {
    return this.canStart && this.audioInputs.devices.length > 0;
  }

  startTranscription(title?: string, categoryID?: string | null, startedAt?: number) {
    if (!this.canRecord) return;
    const resume = this.recordingResumeID;
    if (resume && this.meetings.some((m) => m.id === resume)) {
      const trimmed = title?.trim() ?? "";
      this.meetings = this.meetings.map((m) => (m.id === resume ? { ...m, title: trimmed || m.title, categoryID: this.category(categoryID)?.id ?? null, startedAt: startedAt ?? m.startedAt } : m));
      this.resumeTranscription(resume);
      return;
    }
    const device = this.audioInputs.selectedDevice;
    let meeting = liveMeeting(this.recordingSourceLanguage, this.recordingTargetLanguage, device?.name);
    const trimmed = title?.trim() ?? "";
    if (trimmed) meeting.title = trimmed;
    meeting.categoryID = this.category(categoryID)?.id ?? null;
    if (startedAt) meeting.startedAt = startedAt;
    meeting = this.nextAudioFile(meeting);
    this.engine.recordingURL = this.currentAudioPath(meeting);
    this.engine.sourceLanguage = meeting.sourceLanguage;
    this.engine.targetLanguage = meeting.targetLanguage;
    this.engine.inputDeviceUID = this.audioInputs.selectedUID === AudioInputs.systemDefault ? null : device?.id ?? null;
    this.recordingSetupPresented = false;
    this.recordingResumeID = null;
    this.resumedMeetingSnapshot = null;
    this.meetings = [meeting, ...this.meetings];
    this.liveMeetingID = meeting.id;
    this.startLiveQuestionScan(meeting.id);
    this.refreshTranscriptionTopic(meeting.id);
    this.openMeetingID = meeting.id;
    this.page = "meetings";
    this.startLiveSpeakers(meeting.id, 0);
    this.engine.start();
    this.changed();
  }

  private resumeTranscription(id: string) {
    const index = this.meetings.findIndex((m) => m.id === id && !m.isLive);
    if (!this.canRecord || index < 0) return;
    const saved = this.meetings[index];
    const offset = Math.max(saved.duration, transcriptEnd(saved.paragraphs));
    const history = saved.paragraphs.map((p) => ({ ...p, sourceLanguage: p.sourceLanguage ?? saved.sourceLanguage, targetLanguage: p.targetLanguage ?? saved.targetLanguage }));
    this.resumedMeetingSnapshot = saved;
    const device = this.audioInputs.selectedDevice;
    this.engine.sourceLanguage = this.recordingSourceLanguage;
    this.engine.targetLanguage = this.recordingTargetLanguage;
    this.engine.inputDeviceUID = this.audioInputs.selectedUID === AudioInputs.systemDefault ? null : device?.id ?? null;
    let updated: Meeting = { ...saved, sourceLanguage: this.recordingSourceLanguage, targetLanguage: this.recordingTargetLanguage, inputDeviceName: device?.name ?? null, isLive: true };
    updated = this.nextAudioFile(updated);
    this.engine.recordingURL = this.currentAudioPath(updated);
    this.meetings = this.meetings.map((m) => (m.id === id ? updated : m));
    this.liveMeetingID = id;
    this.startLiveQuestionScan(id);
    this.refreshTranscriptionTopic(id);
    this.openMeetingID = id;
    this.page = "meetings";
    this.recordingSetupPresented = false;
    this.recordingResumeID = null;
    this.startLiveSpeakers(id, offset);
    this.engine.start(history, offset);
    this.changed();
  }

  stopTranscription() {
    this.engine.stop();
  }

  togglePause() {
    this.engine.togglePause();
  }

  /** Each recording run gets its own file. Windows records WAV, which the Mac app also reads. */
  private nextAudioFile(meeting: Meeting): Meeting {
    if (!this.persistenceEnabled) return meeting;
    const name = `audio-${(meeting.audioFiles?.length ?? 0) + 1}.wav`;
    return { ...meeting, audioFiles: [...(meeting.audioFiles ?? []), name] };
  }

  private currentAudioPath(meeting: Meeting): string | null {
    const name = meeting.audioFiles?.at(-1);
    return name ? paths.join(MeetingStore.audioDirectory(meeting.id), name) : null;
  }

  private async removeAudio(meeting: Meeting, kept?: string[]) {
    const dir = MeetingStore.audioDirectory(meeting.id);
    if (!kept) {
      await fs.remove(dir).catch(() => {});
      return;
    }
    for (const name of meeting.audioFiles ?? []) if (!kept.includes(name)) await fs.remove(paths.join(dir, name)).catch(() => {});
  }

  openMeeting(id: string) {
    this.openMeetingID = id;
    this.page = "meetings";
    this.changed();
  }

  startTutorial() {
    this.tutorialStep = "meetings";
    this.changed();
  }

  openLiveMeeting() {
    const id = this.liveMeetingID;
    if (id && this.meetings.some((m) => m.id === id)) this.openMeeting(id);
  }

  closeMeeting() {
    this.openMeetingID = null;
  }

  rename(id: string, title: string) {
    this.meetings = this.meetings.map((m) => (m.id === id ? { ...m, title } : m));
  }

  setStartTime(id: string, date: Date) {
    const startedAt = date.getTime() / 1000 - 978_307_200;
    this.meetings = this.meetings.map((m) => (m.id === id ? { ...m, startedAt } : m));
  }

  async shutdown() {
    await this.persistMeetings();
    await ChatStore.flush();
    await this.memory.flush();
    await this.engine.shutdown();
  }

  private schedulePersistence() {
    if (!this.persistenceEnabled) return;
    clearTimeout(this.persistenceTimer);
    this.persistenceTimer = setTimeout(() => void this.persistMeetings(), 300);
  }

  private async persistMeetings() {
    if (!this.persistenceEnabled) return;
    clearTimeout(this.persistenceTimer);
    const saved: Meeting[] = [];
    for (const meeting of this.meetings) {
      if (meeting.id !== this.liveMeetingID) {
        saved.push(meeting);
        continue;
      }
      const paragraphs = this.engine.transcript.snapshot(this.engine.session.elapsed);
      const hasText = paragraphs.some((p) => renderedSource(p, meeting.sourceLanguage));
      if (!hasText) {
        if (this.resumedMeetingSnapshot) saved.push(this.resumedMeetingSnapshot);
        continue;
      }
      saved.push({ ...meeting, paragraphs, duration: Math.max(meeting.duration, this.engine.session.elapsed, transcriptEnd(paragraphs)), isLive: false });
    }
    try {
      await MeetingStore.save({ meetings: saved, categories: this.categories });
    } catch {
      this.storageError = tr("会议保存失败，请导出备份后重试。");
      this.changed();
    }
  }

  assign(meetingIDs: Set<string>, categoryID: string | null) {
    if (!meetingIDs.size) return;
    let changed = false;
    const updated = this.meetings.map((m) => {
      if (!meetingIDs.has(m.id) || (m.categoryID ?? null) === categoryID) return m;
      changed = true;
      return { ...m, categoryID };
    });
    if (!changed) return;
    this.meetings = updated;
    this.syncLinkedSources(meetingIDs, categoryID);
  }

  linkedSources(meetingID: string): KnowledgeSource[] {
    return (this.meetingLinks[meetingID] ?? []).map((id) => this.sources.find((s) => s.id === id)).filter((s): s is KnowledgeSource => !!s);
  }

  async importLinkedSources(files: string[], meetingID: string) {
    const meeting = this.meetings.find((m) => m.id === meetingID);
    if (!meeting) return;
    const added: string[] = [];
    let rejected: string | null = null;
    for (const file of files) {
      const existing = SourceStore.sourceID(file);
      if (existing && this.sources.some((s) => s.id === existing)) {
        added.push(existing);
        continue;
      }
      if (!SourceStore.accepts(file)) {
        rejected = rejected ?? file;
        continue;
      }
      try {
        const source = await SourceStore.stage(file, meeting.categoryID);
        this.sources = [...this.sources, source];
        added.push(source.id);
      } catch (error) {
        this.sourceError = error instanceof Error ? error.message : String(error);
      }
    }
    if (rejected) this.sourceError = SourceText.refusal(rejected);
    if (!added.length) return this.changed();
    const links = this.meetingLinks[meetingID] ?? [];
    this.meetingLinks = { ...this.meetingLinks, [meetingID]: [...links, ...added.filter((id) => !links.includes(id))] };
  }

  refreshTranscriptionTopic(meetingID: string) {
    const meeting = this.meetings.find((m) => m.id === meetingID);
    if (!meeting) return;
    const title = meeting.title;
    const course = this.categoryName(meeting);
    this.engine.updateTranscriptionTopic(TranscriptionTopic.text(title, course, []));
    const files = this.linkedSources(meetingID);
    if (!files.length) return;
    const token = ++this.transcriptionTopicToken;
    void (async () => {
      const blocks = (await Promise.all(files.map((s) => SourceText.blocks(SourceStore.fileURL(s), s.title, s.id)))).flat();
      const terms = TranscriptionTopic.terms(blocks.map((b) => b.body).join("\n"));
      if (token !== this.transcriptionTopicToken || this.liveMeetingID !== meetingID) return;
      this.engine.updateTranscriptionTopic(TranscriptionTopic.text(title, course, terms));
    })();
  }

  linkSource(sourceID: string, meetingID: string) {
    const meeting = this.meetings.find((m) => m.id === meetingID);
    if (!meeting || !this.sources.some((s) => s.id === sourceID)) return;
    const links = this.meetingLinks[meetingID] ?? [];
    if (links.includes(sourceID)) return;
    this.meetingLinks = { ...this.meetingLinks, [meetingID]: [...links, sourceID] };
    const source = this.sources.find((s) => s.id === sourceID);
    if (source && (source.categoryID ?? null) !== (meeting.categoryID ?? null)) {
      this.sources = this.sources.map((s) => (s.id === sourceID ? { ...s, categoryID: meeting.categoryID ?? null } : s));
    }
  }

  unlinkSource(sourceID: string, meetingID: string) {
    const links = (this.meetingLinks[meetingID] ?? []).filter((id) => id !== sourceID);
    const next = { ...this.meetingLinks };
    if (links.length) next[meetingID] = links;
    else delete next[meetingID];
    this.meetingLinks = next;
  }

  private syncLinkedSources(meetingIDs: Set<string>, categoryID: string | null) {
    const ids = new Set([...meetingIDs].flatMap((id) => this.meetingLinks[id] ?? []));
    if (!ids.size) return;
    let changed = false;
    const updated = this.sources.map((s) => {
      if (!ids.has(s.id) || (s.categoryID ?? null) === categoryID) return s;
      changed = true;
      return { ...s, categoryID };
    });
    if (changed) this.sources = updated;
  }

  deleteMeetings(ids: Set<string>) {
    for (const id of ids) this.deleteMeeting(id);
  }

  deleteMeeting(id: string) {
    if (id === this.liveMeetingID || this.assistantStates[id]?.isGenerating) return;
    const meeting = this.meetings.find((m) => m.id === id);
    if (meeting) void this.removeAudio(meeting);
    this.meetings = this.meetings.filter((m) => m.id !== id);
    delete this.assistantStates[id];
    this.forgetQA(id);
    const links = { ...this.meetingLinks };
    delete links[id];
    this.meetingLinks = links;
    delete this.meetingChatID[id];
    if (this.openMeetingID === id) this.openMeetingID = null;
  }

  addCategory(name: string, colorIndex: number, symbol: string, select = true): string | null {
    const trimmed = name.trim();
    if (!trimmed) return null;
    const category: MeetingCategory = { id: newID(), name: trimmed, colorIndex, symbol, sortOrder: Math.max(-1, ...this.categories.map((c) => c.sortOrder)) + 1 };
    this.categories = [...this.categories, category];
    if (select) this.filter = { kind: "category", id: category.id };
    return category.id;
  }

  placeCategory(id: string, targetID: string) {
    const updated = placing(this.categories, id, targetID);
    if (updated) this.categories = updated;
  }

  updateCategory(id: string, name: string, colorIndex: number, symbol: string) {
    const trimmed = name.trim();
    if (!trimmed) return;
    this.categories = this.categories.map((c) => (c.id === id ? { ...c, name: trimmed, colorIndex, symbol } : c));
  }

  deleteCategory(id: string) {
    this.categories = this.categories.filter((c) => c.id !== id);
    if (this.meetings.some((m) => m.categoryID === id)) this.meetings = this.meetings.map((m) => (m.categoryID === id ? { ...m, categoryID: null } : m));
    if (this.sources.some((s) => s.categoryID === id)) this.sources = this.sources.map((s) => (s.categoryID === id ? { ...s, categoryID: null } : s));
    if (this.filter.kind === "category" && this.filter.id === id) this.filter = { kind: "uncategorized" };
  }

  commitSources(staged: KnowledgeSource[]) {
    if (staged.length) this.sources = [...staged, ...this.sources];
  }

  assignSources(ids: Set<string>, categoryID: string | null) {
    if (!ids.size) return;
    let changed = false;
    const updated = this.sources.map((s) => {
      if (!ids.has(s.id) || (s.categoryID ?? null) === categoryID) return s;
      changed = true;
      return { ...s, categoryID };
    });
    if (changed) this.sources = updated;
  }

  renameSource(id: string, title: string) {
    const trimmed = title.trim();
    if (!trimmed) return;
    this.sources = this.sources.map((s) => (s.id === id ? { ...s, title: trimmed } : s));
  }

  deleteSources(ids: Set<string>) {
    const removing = this.sources.filter((s) => ids.has(s.id));
    if (!removing.length) return;
    for (const s of removing) void SourceStore.remove(s);
    this.sources = this.sources.filter((s) => !ids.has(s.id));
    const links: Record<string, string[]> = {};
    for (const [key, value] of Object.entries(this.meetingLinks)) {
      const kept = value.filter((id) => !ids.has(id));
      if (kept.length) links[key] = kept;
    }
    this.meetingLinks = links;
  }

  async downloadSourcesByCategory(ids: Set<string> | null = null) {
    const chosen = ids ? this.sources.filter((s) => ids.has(s.id)) : this.sources;
    const files = chosen.map((s) => ({ sourceURL: SourceStore.fileURL(s), folder: this.category(s.categoryID)?.name ?? tr("未分类"), fileName: s.fileName }));
    if (!files.length) return;
    const folder = await dialogs.openFolder();
    if (!folder) return;
    try {
      await SourceStore.exportGrouped(files, folder);
      void shell.reveal(folder);
    } catch (error) {
      this.sourceError = error instanceof Error ? error.message : String(error);
      this.changed();
    }
  }

  discardSources(staged: KnowledgeSource[]) {
    for (const s of staged) void SourceStore.remove(s);
  }

  requestSearch() {
    this.page = "meetings";
    this.openMeetingID = null;
    this.searchRequest++;
    this.changed();
  }

  async copyTranscript(meeting: Meeting) {
    const text = meeting.paragraphs
      .map((p) => {
        const source = renderedSource(p, meeting.sourceLanguage);
        const translation = renderedTranslation(p, meeting.targetLanguage);
        return translation ? `${source}\n${translation}` : source;
      })
      .filter(Boolean)
      .join("\n\n");
    await navigator.clipboard.writeText(text);
  }

  async export(items: Meeting[]) {
    if (!items.length) return;
    const markdown = items.map((m) => meetingMarkdown(m, this.categoryName(m))).join("\n");
    const target = await dialogs.save(this.exportFilename(items), [{ name: "Markdown", extensions: ["md"] }]);
    if (!target) return;
    try {
      await fs.writeText(target, markdown);
    } catch (error) {
      this.exportError = error instanceof Error ? error.message : String(error);
      this.changed();
    }
  }

  get activeFilter(): CategoryFilter {
    if (this.filter.kind === "category" && !this.category(this.filter.id)) return { kind: "all" };
    return this.filter;
  }

  private matches(meeting: Meeting): boolean {
    if (!categoryMatches(meeting.categoryID, this.activeFilter)) return false;
    const q = this.appliedQuery.trim().toLowerCase();
    if (!q) return true;
    if (meeting.title.toLowerCase().includes(q)) return true;
    const name = this.categoryName(meeting);
    if (name && name.toLowerCase().includes(q)) return true;
    return meeting.paragraphs.some((p) => renderedSource(p, meeting.sourceLanguage).toLowerCase().includes(q) || renderedTranslation(p, meeting.targetLanguage).toLowerCase().includes(q));
  }

  private exportFilename(items: Meeting[]): string {
    let raw: string;
    if (items.length === 1) raw = items[0].title;
    else if (this.activeFilter.kind === "category") raw = this.category(this.activeFilter.id)?.name ?? tr("会议记录");
    else raw = tr("会议记录");
    const cleaned = raw.replace(/[\\/:*?"<>|]/g, " ").trim();
    return (cleaned || tr("会议记录")) + ".md";
  }

  private finishLiveMeeting(paragraphs: Paragraph[], duration: number) {
    const id = this.liveMeetingID;
    const index = this.meetings.findIndex((m) => m.id === id);
    if (!id || index < 0) return;
    const meeting = this.meetings[index];
    const hasText = paragraphs.some((p) => renderedSource(p, meeting.sourceLanguage));
    this.engine.recordingURL = null;
    const saved = this.resumedMeetingSnapshot;
    if (!paragraphs.length && saved) {
      void this.removeAudio(meeting, saved.audioFiles ?? []);
      this._meetings = this.meetings.map((m) => (m.id === id ? { ...m, audioFiles: saved.audioFiles, paragraphs: saved.paragraphs, duration: saved.duration, sourceLanguage: saved.sourceLanguage, targetLanguage: saved.targetLanguage, inputDeviceName: saved.inputDeviceName, isLive: false } : m));
    } else if (!hasText && duration <= 0) {
      void this.removeAudio(meeting);
      this._meetings = this.meetings.filter((m) => m.id !== id);
      if (this.openMeetingID === id) this.openMeetingID = null;
    } else {
      this._meetings = this.meetings.map((m) => (m.id === id ? { ...m, paragraphs, duration: Math.max(duration, transcriptEnd(paragraphs)), isLive: false } : m));
    }
    this.liveMeetingID = null;
    this.resumedMeetingSnapshot = null;
    void this.persistMeetings();
    this.finishQuestionScan(id);
    this.finishLiveSpeakers(id);
    this.checkVoicesAfterRecording(id);
    this.changed();
  }

  get recordingMeetingID() {
    return this.liveMeetingID;
  }

  /** A meeting as it reads right now: while recording, its transcript lives in the engine. */
  current(meeting: Meeting): Meeting {
    if (meeting.id !== this.recordingMeetingID) return meeting;
    return { ...meeting, paragraphs: this.engine.transcript.snapshot(this.engine.session.elapsed) };
  }

  /** The time a meeting started, as a Date. */
  startDate(meeting: Meeting) {
    return toDate(meeting.startedAt);
  }

  meetingTimeTitle(meeting: Meeting) {
    return formatMeetingTime(toDate(meeting.startedAt));
  }

  get assistantModelName(): string {
    if (this.llmConfiguration.mode === "api") {
      const p = this.llmConfiguration.activeProfile;
      return p ? `${p.name} · ${p.modelID}` : tr("未配置 API");
    }
    return selectedModel("assistant").name;
  }

  noteError(field: "chatError" | "sourceError" | "exportError" | "storageError", error: unknown) {
    this[field] = error instanceof Error ? error.message : String(error);
    this.changed();
  }

  trfStatus = trf;
  now = nowReference;
}

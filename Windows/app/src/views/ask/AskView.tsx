// Pages/AskView.swift, AskComposer.swift and ChatFollow.swift: the chat page, also embedded in a meeting.
import { memo, useEffect, useLayoutEffect, useRef, useState } from "react";
import { tr, trf } from "../../i18n";
import { renderedSource } from "../../models/transcript";
import { catalog, selectedModel, supports, type LocalModelDefinition } from "../../models/localModels";
import { ChatImages, isDraftFile, type ChatImageDraft } from "../../models/chatImage";
import { displayTitle, Scope, type ChatSession, type ChatTurn } from "../../models/chatSession";
import { Profiles } from "../../models/llmConfiguration";
import { isRunning } from "../../models/answerSteps";
import { BusySend, type BusySendMode } from "../../app/chatQueue";
import type { ChatRun, QueuedPrompt } from "../../app/model";
import { useModel } from "../../app";
import { dialogs } from "../../platform";
import { AnswerBody } from "../answer/AnswerBody";
import { DotLoader } from "../ui/DotLoader";
import { Icon } from "../ui/Icon";
import { Alert, Menu, PromptAlert, PushButton, Scroll, type MenuEntry } from "../ui/controls";
import { sourceFilters, useFileDrop } from "../ui/fileDrop";
import { AnswerStepsFold, AnswerStepsView } from "./AnswerSteps";
import { ChatImageStrip, StoredImageStrip } from "./ChatImages";
import { ChatQueueList } from "./ChatQueueList";
import { AskHistoryPopover } from "./HistoryPopover";
import { AskScopePopover } from "./ScopePopover";

const examples = ["这门课的重点是什么？", "有哪些需要记住的术语？", "作业或下一步是什么？"];
const changed = (a: string, b: string) => !!a && !!b && a !== b;

function ModelChangeNote({ from, to }: { from: string; to: string }) {
  return (
    <div className="font-caption flex items-center gap-3 text-[var(--text-2)]">
      <div className="h-px flex-1 bg-[var(--separator)]" />
      <span className="flex items-center gap-1.5 text-center">
        <Icon name="cube" size={12} />
        {trf("模型已从 %@ 换成 %@", from, to)}
      </span>
      <div className="h-px flex-1 bg-[var(--separator)]" />
    </div>
  );
}

function IconButton({ symbol, help, onClick }: { symbol: string; help: string; onClick: () => void }) {
  return (
    <button onClick={onClick} title={help} aria-label={help} className="press flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-[var(--surface)] hover:bg-[var(--surface-inset)]">
      <Icon name={symbol} size={16} />
    </button>
  );
}

function Bubble({ children }: { children: React.ReactNode }) {
  return <div className="font-body selectable rounded-[18px] bg-[var(--accent-soft)] px-3.5 py-2.5 whitespace-pre-wrap">{children}</div>;
}

const TurnRow = memo(function TurnRow({ turn, onOpenMemory }: { turn: ChatTurn; onOpenMemory: () => void }) {
  return (
    <div className="flex flex-col gap-3">
      <div className="flex justify-end pl-20">
        <div className="flex min-w-0 flex-col items-end gap-2">
          {(turn.images.length > 0 || (turn.files ?? []).length > 0) && <StoredImageStrip images={turn.images} files={turn.files ?? []} />}
          {turn.question && <Bubble>{turn.question}</Bubble>}
        </div>
      </div>
      {turn.error ? (
        <div className="font-secondary selectable text-[var(--danger)]">{turn.error}</div>
      ) : (
        (turn.answer || turn.interrupted) && (
          <>
            {(turn.steps || turn.answerSeconds != null) && <AnswerStepsFold steps={turn.steps ?? []} seconds={turn.answerSeconds} />}
            {turn.answer && (
              <div className="max-w-[680px]">
                <AnswerBody source={turn.answer} citations={turn.citations} />
              </div>
            )}
          </>
        )
      )}
      {turn.interrupted && (
        <div className="font-caption flex items-center gap-1 text-[var(--text-2)]">
          <Icon name="arrow.uturn.right" size={12} />
          {tr("已打断")}
        </div>
      )}
      {turn.memoryNote && turn.memoryNote.length > 0 && (
        <div className="font-caption flex max-w-[680px] items-baseline gap-2">
          <span className="text-[var(--accent)]">
            <Icon name="brain" size={12} />
          </span>
          <span className="line-clamp-2 text-[var(--text-2)]">{trf("已记住：%@", turn.memoryNote.join(tr("；")))}</span>
          <button onClick={onOpenMemory} className="shrink-0 text-[var(--accent)]">
            {tr("管理")}
          </button>
        </div>
      )}
    </div>
  );
});

function PendingView({ run }: { run: ChatRun }) {
  return (
    <div className="flex flex-col gap-3">
      <div className="flex justify-end pl-20">
        <div className="flex min-w-0 flex-col items-end gap-2">
          {run.images.length > 0 && <ChatImageStrip items={run.images} trailing />}
          {run.question && <Bubble>{run.question}</Bubble>}
        </div>
      </div>
      <div className="max-w-[680px]">
        <AnswerStepsView steps={run.steps} thinking={run.thinking} />
      </div>
      {!run.answer ? (
        !run.steps.some(isRunning) && (
          <div className="flex items-center gap-2">
            <DotLoader style="circle" />
            <span className="font-secondary shimmer">{tr("正在回答…")}</span>
          </div>
        )
      ) : (
        <div className="max-w-[680px]">
          <AnswerBody source={run.answer} streaming citations={run.citations} />
        </div>
      )}
    </div>
  );
}

/** AskComposerField: grows with its text up to eight lines; Enter sends, Shift+Enter breaks a line. */
function ComposerField({ value, onChange, placeholder, focusToken, onSubmit, onSubmitAlternate, onPasteImage, onRemoveLastImage }: { value: string; onChange: (v: string) => void; placeholder: string; focusToken: unknown; onSubmit: () => void; onSubmitAlternate: () => void; onPasteImage: (b64: string, name: string) => void; onRemoveLastImage: () => boolean }) {
  const ref = useRef<HTMLTextAreaElement>(null);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    el.style.height = "0px";
    const line = 22;
    el.style.height = `${Math.max(36, Math.min(el.scrollHeight, line * 8 + 16))}px`;
  }, [value]);
  useEffect(() => {
    ref.current?.focus();
  }, [focusToken]);
  return (
    <textarea
      ref={ref}
      value={value}
      rows={1}
      placeholder={placeholder}
      onChange={(e) => onChange(e.target.value)}
      onKeyDown={(e) => {
        if (e.nativeEvent.isComposing || e.keyCode === 229) return;
        if (e.key === "Backspace" && !value && onRemoveLastImage()) {
          e.preventDefault();
          return;
        }
        if (e.key !== "Enter" || e.shiftKey) return;
        e.preventDefault();
        if (e.ctrlKey || e.metaKey) onSubmitAlternate();
        else onSubmit();
      }}
      onPaste={(e) => {
        const files = [...e.clipboardData.items].filter((i) => i.kind === "file" && i.type.startsWith("image/")).map((i) => i.getAsFile()).filter((f): f is File => !!f);
        if (!files.length) return;
        e.preventDefault();
        for (const file of files) {
          const reader = new FileReader();
          reader.onload = () => onPasteImage(String(reader.result).split(",")[1] ?? "", file.name && file.name !== "image.png" ? file.name : `image-${Date.now()}.${file.type.split("/")[1] || "png"}`);
          reader.readAsDataURL(file);
        }
      }}
      className="scroll min-w-0 flex-1 resize-none bg-transparent px-0.5 py-2 text-[15px] leading-[22px] outline-none"
    />
  );
}

function JumpToEndButton({ unseen, onClick }: { unseen: boolean; onClick: () => void }) {
  return (
    <button onClick={onClick} title={tr("跳到最新")} aria-label={unseen ? tr("跳到新回答") : tr("跳到最新")} className="pop-in press flex min-h-8 min-w-8 items-center justify-center gap-[5px] rounded-full shadow-[0_3px_16px_rgba(0,0,0,0.18)]" style={{ background: unseen ? "var(--accent)" : "var(--surface)", color: unseen ? "#fff" : "var(--text)", padding: unseen ? "0 12px" : 0, border: unseen ? "none" : "1px solid var(--separator)" }}>
      <Icon name="arrow.down" size={13} weight={2.6} />
      {unseen && <span className="font-caption font-semibold">{tr("新回答")}</span>}
    </button>
  );
}

export function AskView({ anchorMeetingID = null }: { anchorMeetingID?: string | null }) {
  const m = useModel();
  const embedded = anchorMeetingID != null;
  const session: ChatSession | null = m.chatAnchored(anchorMeetingID);
  const [draft, setDraft] = useState("");
  const [focusToken, setFocusToken] = useState(0);
  const [scopeOpen, setScopeOpen] = useState(false);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [renaming, setRenaming] = useState<ChatSession | null>(null);
  const [deleting, setDeleting] = useState<ChatSession | null>(null);
  const [imageNotice, setImageNotice] = useState<string | null>(null);
  const [modelMenu, setModelMenu] = useState<HTMLElement | null>(null);
  const [follow, setFollow] = useState({ following: true, unseen: false });
  const scroller = useRef<HTMLDivElement>(null);
  const followRef = useRef(follow);
  followRef.current = follow;
  const lastHeight = useRef(0);
  const active = embedded || m.page === "ask";

  const composerChatID = () => {
    if (anchorMeetingID) {
      m.ensureMeetingChat(anchorMeetingID);
      return m.meetingChatID[anchorMeetingID] ?? null;
    }
    m.ensureChat();
    return m.currentChatID;
  };
  const restoreDraft = () => {
    const text = m.chatDraftRestore;
    if (text == null) return;
    setDraft(text);
    m.chatDraftRestore = null;
    setFocusToken((n) => n + 1);
  };
  useEffect(() => {
    if (!active) return;
    if (anchorMeetingID) m.ensureMeetingChat(anchorMeetingID);
    else m.ensureChat();
    m.localModels.refreshInBackground();
    setFocusToken((n) => n + 1);
    restoreDraft();
  }, [active]);
  useEffect(() => {
    void m.refreshActiveAPIModels();
  }, [m.llmConfiguration.mode, m.llmConfiguration.activeID]);
  useEffect(() => {
    if (m.chatFocusRequest) setFocusToken((n) => n + 1);
  }, [m.chatFocusRequest]);
  useEffect(restoreDraft, [m.chatDraftRestore]);

  // ChatFollow: stay pinned to the end while text arrives, unless the student scrolled up.
  const toEnd = (smooth: boolean) => {
    const el = scroller.current;
    if (el) el.scrollTo({ top: el.scrollHeight, behavior: smooth ? "smooth" : "auto" });
  };
  const jumpToEnd = (smooth: boolean) => {
    setFollow({ following: true, unseen: false });
    toEnd(smooth);
  };
  useEffect(() => {
    const el = scroller.current?.firstElementChild as HTMLElement | null;
    if (!el) return;
    const ro = new ResizeObserver(() => {
      const h = el.offsetHeight;
      if (h > lastHeight.current + 0.5) {
        if (followRef.current.following) toEnd(false);
        else setFollow((f) => ({ ...f, unseen: true }));
      }
      lastHeight.current = h;
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, [session?.id, !!session]);
  useEffect(() => {
    lastHeight.current = 0;
    jumpToEnd(false);
  }, [session?.id]);
  const onScroll = (el: HTMLDivElement) => {
    const following = el.scrollHeight - el.scrollTop - el.clientHeight <= 48;
    if (following !== followRef.current.following) setFollow({ following, unseen: following ? false : followRef.current.unseen });
  };

  const attached: ChatImageDraft[] = session ? (m.composerImages[session.id] ?? []) : [];
  const answeringHere = m.isAnswering(session?.id ?? null);
  const showEmpty = (session?.turns.length ?? 0) === 0 && !answeringHere;
  const hasDraft = draft.trim().length > 0 || attached.length > 0;
  const busyAction: BusySendMode | null = answeringHere ? (BusySend.current === "steer" ? "steer" : "queue") : m.canStartAnotherAnswer ? null : "queue";
  const canSend = hasDraft && (busyAction !== null || m.canGenerateAssistant);
  const sendSymbol = busyAction === null ? "arrow.up" : busyAction === "queue" ? "text.line.last.and.arrowtriangle.forward" : "arrow.uturn.right";
  const sendLabel = busyAction === null ? tr("发送") : busyAction === "queue" ? tr("加入队列") : tr("打断并发送");
  const busyHint = !answeringHere ? (m.canStartAnotherAnswer ? null : tr("本地模型正在回答其他几段对话，新消息会排队。")) : BusySend.current === "queue" ? tr("Enter 排队 · ⌘Enter 立即打断").replace("⌘", "Ctrl+") : tr("Enter 立即打断 · ⌘Enter 排队").replace("⌘", "Ctrl+");
  const hasScope = (() => {
    if (anchorMeetingID) {
      const meeting = m.meetings.find((x) => x.id === anchorMeetingID);
      return !!meeting?.paragraphs.some((p) => renderedSource(p, meeting.sourceLanguage).length > 0) || m.linkedSources(anchorMeetingID).length > 0;
    }
    const s = session?.scope;
    return !!s && (s.includeAll || s.categoryIDs.length > 0 || s.includesUncategorized || s.meetingIDs.length > 0 || s.sourceIDs.length > 0);
  })();
  const profile = m.llmConfiguration.activeProfile;
  const showsCloudNotice = m.llmConfiguration.mode === "api" && !!profile && !Profiles.isLoopback(profile) && (session?.turns.length ?? 0) === 0 && !answeringHere;
  const showsSearchGuide = !embedded && !m.webSearch.hasReadyProvider && !m.webSearch.guideDismissed;
  const modelSeesImages = ChatImages.seesImages(m.llmConfiguration.mode, profile?.modelID ?? "");

  const send = (mode: BusySendMode) => {
    const id = composerChatID();
    if (!id) return;
    const images = m.composerImages[id] ?? [];
    if (!m.submit(draft, images, anchorMeetingID, mode)) return;
    jumpToEnd(true);
    setDraft("");
    m.composerImages[id] = [];
    setImageNotice(null);
    setFocusToken((n) => n + 1);
    m.changed();
  };
  const accept = (intake: { drafts: ChatImageDraft[]; notice: string | null }, id: string) => {
    m.composerImages[id] = [...(m.composerImages[id] ?? []), ...intake.drafts];
    setImageNotice(intake.notice);
    m.changed();
  };
  const addFiles = async (files: string[]) => {
    const id = composerChatID();
    if (!id || !files.length) return;
    accept(await ChatImages.intake(files, m.composerImages[id]?.length ?? 0), id);
  };
  const addPasted = async (b64: string, name: string) => {
    const id = composerChatID();
    if (!id) return;
    accept(await ChatImages.intakeBytes(b64, name, m.composerImages[id]?.length ?? 0), id);
  };
  const removeImage = (d: ChatImageDraft) => {
    if (!session) return;
    void ChatImages.discard(d);
    m.composerImages[session.id] = (m.composerImages[session.id] ?? []).filter((x) => x.id !== d.id);
    setImageNotice(null);
    m.changed();
  };
  const editQueued = (item: QueuedPrompt) => {
    const taken = m.takeQueued(item.id);
    if (!taken) return;
    const current = draft.trim();
    setDraft(current ? current + "\n" + taken.text : taken.text);
    m.composerImages[taken.chatID] = [...(m.composerImages[taken.chatID] ?? []), ...taken.images];
    setFocusToken((n) => n + 1);
    m.changed();
  };
  const { ref: dropRef } = useFileDrop((p) => void addFiles(p));

  const local = m.llmConfiguration.mode === "local";
  const loaded = selectedModel("assistant").id;
  const installed = catalog.filter((x) => supports(x, "assistant") && m.localModels.installed.has(x.id));
  const localChatModels: LocalModelDefinition[] = installed.some((x) => x.id === loaded) ? installed : [selectedModel("assistant"), ...installed];
  const modelMenuEmpty = !localChatModels.length && (!profile || !m.apiModelChoices.length);
  const useLocal = async (item: LocalModelDefinition) => {
    if (item.id === selectedModel("assistant").id) return m.useLocalChatModel();
    await m.selectLocalModel(item, "assistant");
    if (selectedModel("assistant").id === item.id) m.useLocalChatModel();
  };
  const modelItems = (): MenuEntry[] => {
    const items: MenuEntry[] = [];
    if (localChatModels.length) {
      items.push({ kind: "header", title: tr("本地模型") });
      for (const item of localChatModels) items.push({ kind: "item", title: item.name, checked: local && item.id === loaded, disabled: item.id !== loaded && !m.canSwitchModels, onSelect: () => void useLocal(item) });
    }
    if (profile && m.apiModelChoices.length) {
      if (items.length) items.push({ kind: "divider" });
      items.push({ kind: "header", title: "API" });
      for (const id of m.apiModelChoices) items.push({ kind: "item", title: id, checked: !local && id === profile.modelID, onSelect: () => m.useAPIModel(id) });
    }
    return items;
  };

  const turns = session?.turns ?? [];
  const run = session ? m.chatRuns[session.id] : undefined;
  const conversation = (
    <div className="relative flex min-h-0 flex-1 flex-col">
      <div className="relative min-h-0 flex-1" onMouseDown={() => scopeOpen && setScopeOpen(false)}>
        {showEmpty ? (
          <div className="flex h-full flex-col items-center justify-center gap-4 px-8 text-center">
            <span className="flex h-14 w-14 items-center justify-center rounded-full bg-[var(--accent-soft)] text-[var(--accent)]">
              <Icon name="text.bubble" size={22} />
            </span>
            <div className={embedded ? "font-secondary text-[var(--text-2)]" : "font-section-title"}>{embedded ? tr("根据这场会议的转写和资料回答。") : tr("根据你的会议和资料回答。")}</div>
            {!embedded && (
              <div className="flex flex-wrap justify-center gap-2">
                {examples.map((e) => (
                  <button
                    key={e}
                    onClick={() => {
                      setDraft(tr(e));
                      setFocusToken((n) => n + 1);
                    }}
                    className="press font-secondary truncate rounded-full bg-[var(--surface-inset)] px-3 py-2"
                  >
                    {tr(e)}
                  </button>
                ))}
              </div>
            )}
          </div>
        ) : (
          session && (
            <Scroll innerRef={scroller} className="h-full" onScroll={onScroll}>
              <div className="flex flex-col gap-6 p-6">
                {turns.map((turn, i) => (
                  <div key={turn.id} className="flex flex-col gap-6">
                    {i > 0 && changed(turns[i - 1].modelName, turn.modelName) && <ModelChangeNote from={turns[i - 1].modelName} to={turn.modelName} />}
                    <TurnRow turn={turn} onOpenMemory={() => m.showMemorySettings()} />
                    {m.preparingVisualTurnIDs.has(turn.id) && (
                      <div className="flex items-center gap-2">
                        <DotLoader style="breeze" />
                        <span className="font-secondary shimmer">{tr("正在准备图示…")}</span>
                      </div>
                    )}
                  </div>
                ))}
                {turns.length > 0 && changed(turns.at(-1)!.modelName, m.assistantModelName) && <ModelChangeNote from={turns.at(-1)!.modelName} to={m.assistantModelName} />}
                {run && <PendingView run={run} />}
              </div>
            </Scroll>
          )
        )}
        {!follow.following && !showEmpty && (
          <div className="absolute inset-x-0 bottom-3 flex justify-center">
            <JumpToEndButton unseen={follow.unseen} onClick={() => jumpToEnd(true)} />
          </div>
        )}
        {scopeOpen && !embedded && (
          <div className="absolute bottom-3 left-4 z-20" onMouseDown={(e) => e.stopPropagation()}>
            <AskScopePopover onClose={() => setScopeOpen(false)} />
          </div>
        )}
        {historyOpen && <HistoryLayer anchorMeetingID={anchorMeetingID} currentID={session?.id ?? null} onRename={setRenaming} onDelete={setDeleting} onClose={() => setHistoryOpen(false)} />}
      </div>
      {m.chatError && !answeringHere && <div className="font-secondary px-4 pb-2 text-[var(--danger)]">{m.chatError}</div>}
      <div className="p-4">
        <div ref={dropRef} className="flex flex-col gap-3 rounded-[22px] bg-[var(--surface-inset)] p-4">
          {session && m.queued(session.id).length > 0 && <ChatQueueList chatID={session.id} onEdit={editQueued} />}
          {showsCloudNotice && profile && <div className="font-caption text-[var(--text-2)]">{attached.some(isDraftFile) ? trf("会把附加文件里的相关文字发给 %@。", profile.name) : hasScope ? trf("会把所选会议和资料的文字发给 %@。", profile.name) : trf("这次只把问题发给 %@，不附带会议和资料。", profile.name)}</div>}
          <div className="flex items-center gap-2">
            {!embedded && (
              <button
                onClick={() => {
                  setHistoryOpen(false);
                  setScopeOpen(!scopeOpen);
                }}
                title={tr("选择范围")}
                className="press font-secondary flex min-w-0 shrink items-center gap-1.5 rounded-full px-3 py-1.5 font-medium"
                style={{ color: hasScope || scopeOpen ? "var(--accent)" : "var(--text)", background: hasScope || scopeOpen ? "var(--accent-soft)" : "var(--surface)", boxShadow: hasScope || scopeOpen ? "none" : "inset 0 0 0 1px var(--separator)" }}
              >
                <Icon name="folder" size={13} />
                <span className="truncate">{session ? Scope.chipTitle(session.scope, m.chatMeetingItems(), m.chatSourceItems(), m.chatCategoryNames()) : tr("选择范围")}</span>
                <Icon name="chevron.down" size={10} weight={3} />
              </button>
            )}
            <WebChip anchor={anchorMeetingID} session={session} />
            <div className="min-w-2 flex-1" />
            <button onClick={(e) => setModelMenu(e.currentTarget)} disabled={answeringHere || modelMenuEmpty} className="font-secondary flex min-w-0 items-center gap-1.5 text-[var(--text-2)] disabled:opacity-50">
              <span className="truncate">{m.assistantModelName}</span>
              <Icon name="chevron.down" size={10} weight={3} />
            </button>
          </div>
          {imageNotice && <div className="font-caption text-[var(--text-2)]">{imageNotice}</div>}
          {attached.length > 0 && !modelSeesImages && <div className="font-caption text-[var(--text-2)]">{tr("当前模型看不到图片，图片只会留在对话里。")}</div>}
          <div className="flex items-end gap-2">
            <button
              onClick={async () => void addFiles(await dialogs.openFiles([{ name: tr("图片或文件"), extensions: ["png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", ...sourceFilters()[0].extensions] }]))}
              title={tr("添加图片或文件")}
              aria-label={tr("添加图片或文件")}
              className="flex h-8 w-8 shrink-0 items-center justify-center text-[var(--text-2)]"
            >
              <Icon name="paperclip" size={15} weight={2.4} />
            </button>
            <div className="flex min-w-0 flex-1 flex-col gap-2">
              {attached.length > 0 && <ChatImageStrip items={attached} onRemove={removeImage} />}
              <ComposerField
                value={draft}
                onChange={setDraft}
                placeholder={tr("问点什么…")}
                focusToken={focusToken}
                onSubmit={() => send(BusySend.current)}
                onSubmitAlternate={() => send(BusySend.other(BusySend.current))}
                onPasteImage={(b, n) => void addPasted(b, n)}
                onRemoveLastImage={() => {
                  const last = attached.at(-1);
                  if (draft || !last) return false;
                  removeImage(last);
                  return true;
                }}
              />
            </div>
            <div className="flex gap-1.5">
              {answeringHere && session && <RoundButton symbol="stop.fill" label={tr("停止")} active onClick={() => m.stopChat(session.id)} />}
              {(!answeringHere || hasDraft) && <RoundButton symbol={sendSymbol} label={sendLabel} active={canSend} disabled={!canSend} onClick={() => send(BusySend.current)} />}
            </div>
          </div>
          {busyHint && <div className="font-caption text-[var(--text-2)]">{busyHint}</div>}
        </div>
      </div>
    </div>
  );

  const headerButtons = (
    <>
      <IconButton
        symbol="clock.arrow.circlepath"
        help={tr("历史会话")}
        onClick={() => {
          setScopeOpen(false);
          setHistoryOpen(!historyOpen);
        }}
      />
      <IconButton
        symbol="plus"
        help={tr("新会话")}
        onClick={() => {
          setScopeOpen(false);
          setHistoryOpen(false);
          m.beginNewChat(anchorMeetingID);
        }}
      />
    </>
  );

  return (
    <>
      {embedded ? (
        <div className="flex h-full min-h-0 flex-col">
          <div className="flex justify-end gap-2 px-3 pt-2" data-history-anchor>
            {headerButtons}
          </div>
          {conversation}
        </div>
      ) : (
        <div className="mx-auto flex h-full max-w-[1200px] flex-col pr-8 pl-12">
          <div className="flex items-center gap-3 pt-7 pb-4" data-history-anchor>
            <h1 className="font-page-title">{tr("提问")}</h1>
            <div className="flex-1" />
            {headerButtons}
          </div>
          {showsSearchGuide && (
            <div className="surface mb-4 flex items-center gap-3 p-4">
              <div className="font-secondary flex-1">{tr("联网搜索需要你自己的搜索密钥。个人使用可以先用 Tavily，每月有免费额度，不用绑卡。")}</div>
              <PushButton title={tr("以后再说")} onClick={() => m.webSearch.dismissGuide()} />
              <PushButton
                prominent
                title={tr("去设置")}
                onClick={() => {
                  m.revealSearchSettings = true;
                  m.select("settings");
                }}
              />
            </div>
          )}
          <div className="surface mb-6 flex min-h-0 flex-1 flex-col overflow-hidden">{conversation}</div>
        </div>
      )}
      {modelMenu && <Menu anchor={modelMenu} align="end" items={modelItems()} onClose={() => setModelMenu(null)} width={240} />}
      {renaming && (
        <PromptAlert
          title={tr("重命名对话")}
          value={displayTitle(renaming)}
          placeholder={tr("名称")}
          confirm={tr("保存")}
          onCancel={() => setRenaming(null)}
          onConfirm={(v) => {
            m.renameChat(renaming.id, v);
            setRenaming(null);
          }}
        />
      )}
      {deleting && (
        <Alert
          title={tr("删除这场对话？")}
          message={tr("这场对话会从历史里去掉。")}
          actions={[
            { title: tr("取消"), role: "cancel", onClick: () => setDeleting(null) },
            {
              title: tr("删除"),
              role: "destructive",
              onClick: () => {
                m.deleteChat(deleting.id);
                setDeleting(null);
              },
            },
          ]}
        />
      )}
    </>
  );
}

function HistoryLayer(props: { anchorMeetingID: string | null; currentID: string | null; onRename: (s: ChatSession) => void; onDelete: (s: ChatSession) => void; onClose: () => void }) {
  const box = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const down = (e: MouseEvent) => {
      const t = e.target as HTMLElement;
      if (box.current?.contains(t) || t.closest("[data-history-anchor]") || t.closest("[data-popover]") || t.closest(".fixed")) return;
      props.onClose();
    };
    window.addEventListener("mousedown", down, true);
    return () => window.removeEventListener("mousedown", down, true);
  }, []);
  return (
    <div ref={box} className="absolute top-3 right-4 z-20">
      <AskHistoryPopover {...props} />
    </div>
  );
}

function WebChip({ anchor, session }: { anchor: string | null; session: ChatSession | null }) {
  const m = useModel();
  const available = m.webSearch.isActiveReady;
  const on = available && session?.allowsWeb === true;
  return (
    <button
      onClick={() => m.setChatWeb(!on, anchor)}
      disabled={!available}
      title={available ? tr("允许模型上网查资料。") : tr("先在设置里配置一个搜索服务")}
      className="press font-secondary flex shrink-0 items-center gap-1.5 rounded-full px-3 py-1.5 font-medium"
      style={{ color: on ? "var(--accent)" : available ? "var(--text)" : "var(--text-2)", background: on ? "var(--accent-soft)" : "var(--surface)", boxShadow: on ? "none" : "inset 0 0 0 1px var(--separator)" }}
    >
      <Icon name="globe" size={13} />
      {tr("联网")}
    </button>
  );
}

function RoundButton({ symbol, label, active, disabled, onClick }: { symbol: string; label: string; active: boolean; disabled?: boolean; onClick: () => void }) {
  return (
    <button onClick={onClick} disabled={disabled} title={label} aria-label={label} className="press flex h-8 w-8 items-center justify-center rounded-full" style={{ background: active ? "var(--accent)" : "var(--surface)", color: active ? "var(--on-accent)" : "var(--text-2)", boxShadow: active ? "none" : "inset 0 0 0 1px var(--separator)" }}>
      <Icon name={symbol} size={14} weight={2.8} />
    </button>
  );
}

// Pages/ChatQueueList.swift: messages waiting for the current answer to finish.
import { tr, trf } from "../../i18n";
import type { QueuedPrompt } from "../../app/model";
import { useModel } from "../../app";
import { Icon } from "../ui/Icon";

export function ChatQueueList({ chatID, onEdit }: { chatID: string; onEdit: (q: QueuedPrompt) => void }) {
  const m = useModel();
  const items = m.queued(chatID);
  const paused = m.queuePaused.has(chatID);
  const icon = (name: string, help: string, action: () => void) => (
    <button onClick={action} title={help} aria-label={help} className="flex h-[22px] w-[22px] items-center justify-center text-[var(--text-2)]">
      <Icon name={name} size={12} weight={2.6} />
    </button>
  );
  return (
    <div className="flex flex-col gap-1">
      <div className="font-caption flex items-center gap-2">
        <span className="font-semibold text-[var(--text-2)]">{paused ? trf("已暂停 · %d 条", items.length) : trf("排队中 %d 条", items.length)}</span>
        {paused && (
          <button onClick={() => m.resumeQueue(chatID)} className="text-[var(--accent)]">
            {tr("继续")}
          </button>
        )}
        <div className="flex-1" />
        <button onClick={() => m.clearQueue(chatID)} className="text-[var(--text-2)]">
          {tr("全部清除")}
        </button>
      </div>
      <div className="scroll flex flex-col gap-0.5" style={{ maxHeight: Math.min(items.length, 3) * 30 }}>
        {items.map((item, offset) => (
          <div
            key={item.id}
            draggable
            onDragStart={(e) => e.dataTransfer.setData("text/nomi-queued", item.id)}
            onDragOver={(e) => e.dataTransfer.types.includes("text/nomi-queued") && e.preventDefault()}
            onDrop={(e) => {
              const id = e.dataTransfer.getData("text/nomi-queued");
              if (id) m.moveQueued(id, offset);
            }}
            className="flex h-7 shrink-0 items-center gap-2 rounded-[8px] bg-[var(--surface)] px-2"
          >
            <span className="font-caption w-3.5 text-right tabular-nums text-[var(--text-2)]">{offset + 1}</span>
            {item.images.length > 0 && (
              <span className="font-caption flex items-center gap-0.5 text-[var(--text-2)]">
                <Icon name="photo" size={11} />
                {item.images.length}
              </span>
            )}
            <span className="font-secondary min-w-0 flex-1 truncate">{item.text || tr("图片")}</span>
            {icon("pencil", tr("编辑"), () => onEdit(item))}
            {icon("arrow.uturn.right", tr("立即发送"), () => m.sendQueuedNow(item.id))}
            {icon("xmark", tr("移除"), () => m.removeQueued(item.id))}
          </div>
        ))}
      </div>
    </div>
  );
}

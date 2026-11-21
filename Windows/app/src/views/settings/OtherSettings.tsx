// Pages/SearchSettingsSection.swift, PromptSettingsSection.swift and MemorySettingsSection.swift.
import { useEffect, useState } from "react";
import { tr, trf } from "../../i18n";
import { prefs } from "../../support/prefs";
import { accountURL, needsBaseURL, SearchKeys, searchVendors, vendorLogo, vendorTitle, type SearchVendor } from "../../engine/search";
import type { PromptSkill } from "../../models/promptPreferences";
import { memoryKindTitle, type MemoryItem } from "../../models/userMemory";
import { newID } from "../../support/format";
import { useModel } from "../../app";
import { shell } from "../../platform";
import { WebPreviews } from "../answer/CitationCard";
import { Icon } from "../ui/Icon";
import { ProviderLogo } from "../ui/Logos";
import { Alert, LinkButton, PushButton, SettingsAddRow, SettingsRow, SettingsSection, Sheet, Switch } from "../ui/controls";

export function SearchSettingsSection({ id }: { id?: string }) {
  const m = useModel();
  const [editing, setEditing] = useState<SearchVendor | null>(null);
  const [previews, setPreviews] = useState(WebPreviews.enabled);
  const ws = m.webSearch;
  return (
    <SettingsSection id={id} title={tr("联网搜索")} footer={tr("选择一个已配置的服务用于联网搜索。密钥只保存在这台 Mac 上。").replace("这台 Mac", "这台电脑").replace("this Mac", "this PC")}>
      {searchVendors.map((v) => {
        const ready = ws.isReady(v);
        const selected = ws.selected === v;
        return (
          <div key={v} className="flex min-h-[50px] items-center gap-3 px-4 py-2.5">
            <button onClick={() => ws.select(v)} disabled={!ready} className="flex min-w-0 flex-1 items-center gap-3 text-left">
              <span style={{ color: selected ? "var(--accent)" : "var(--text-2)", opacity: ready || selected ? 1 : 0.4 }}>
                <Icon name={selected ? "checkmark.circle.fill" : "circle"} size={16} />
              </span>
              <ProviderLogo file={vendorLogo(v)} />
              <span className="flex min-w-0 flex-col gap-[3px]">
                <span className="font-body flex items-center gap-1.5">
                  {vendorTitle(v)}
                  {v === "tavily" && <span className="font-caption rounded-full bg-[var(--accent-soft)] px-1.5 py-[1px] text-[var(--accent)]">{tr("推荐")}</span>}
                </span>
                <span className="font-caption truncate text-[var(--text-2)]">{ws.status(v)}</span>
              </span>
            </button>
            <PushButton small title={ready ? tr("编辑") : tr("配置")} onClick={() => setEditing(v)} />
          </div>
        );
      })}
      <SettingsRow title={tr("引用预览显示网站图标和配图")} detail={tr("鼠标停在网页引用上时，从该网站获取图标和配图。关闭后只显示标题和摘录。")}>
        <Switch
          label={tr("引用预览显示网站图标和配图")}
          on={previews}
          onChange={(v) => {
            prefs.set(WebPreviews.settingKey, v);
            setPreviews(v);
          }}
        />
      </SettingsRow>
      {editing && <SearchProviderEditor vendor={editing} onClose={() => setEditing(null)} />}
    </SettingsSection>
  );
}

function SearchProviderEditor({ vendor, onClose }: { vendor: SearchVendor; onClose: () => void }) {
  const m = useModel();
  const [key, setKey] = useState("");
  const [baseURL, setBaseURL] = useState(m.webSearch.endpoint(vendor));
  const [testing, setTesting] = useState(false);
  const [note, setNote] = useState<{ text: string; error: boolean } | null>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);
  useEffect(() => {
    void SearchKeys.read(vendor).then(setKey, () => {});
  }, []);
  const field = "font-secondary h-7 min-w-0 flex-1 rounded-[6px] border border-[var(--separator)] bg-[var(--surface)] px-2 outline-none focus:border-[var(--accent)]";
  const fail = (e: unknown) => setNote({ text: e instanceof Error ? e.message : String(e), error: true });
  return (
    <Sheet width={640} onClose={onClose}>
      <div className="flex flex-col gap-4 p-6">
        <div className="flex items-center gap-3">
          <ProviderLogo file={vendorLogo(vendor)} side={22} />
          <span className="font-section-title">{vendorTitle(vendor)}</span>
        </div>
        <div className="flex flex-col gap-3">
          <div className="flex flex-col gap-1">
            <span className="font-caption text-[var(--text-2)]">{needsBaseURL(vendor) ? tr("SearXNG 没有统一账号。按文档搭好自己的服务，把地址填在下面。") : tr("先在这个页面注册账号，创建 API 密钥，再粘贴到下面。")}</span>
            <button onClick={() => void shell.openURL(accountURL(vendor))} className="font-caption self-start text-[var(--accent)]">
              {accountURL(vendor)}
            </button>
          </div>
          {needsBaseURL(vendor) && (
            <label className="font-secondary flex items-center gap-3">
              {tr("搜索地址")}
              <input value={baseURL} onChange={(e) => setBaseURL(e.target.value)} placeholder="http://127.0.0.1:8080" className={field} />
            </label>
          )}
          <label className="font-secondary flex items-center gap-3">
            {tr("API 密钥")}
            <input type="password" value={key} onChange={(e) => setKey(e.target.value)} placeholder={tr("API 密钥")} className={field} />
          </label>
          {needsBaseURL(vendor) && <span className="font-caption text-[var(--text-2)]">{tr("密钥可留空。")}</span>}
        </div>
        {note && <div className="font-caption selectable" style={{ color: note.error ? "var(--danger)" : "var(--text-2)" }}>{note.text}</div>}
        <div className="flex items-center gap-2">
          <PushButton
            title={tr("测试连接")}
            disabled={testing}
            onClick={async () => {
              setTesting(true);
              try {
                const count = await m.webSearch.test(vendor, key, baseURL);
                setNote({ text: trf("连上了，返回了 %d 条结果", count), error: false });
              } catch (e) {
                fail(e);
              } finally {
                setTesting(false);
              }
            }}
          />
          {m.webSearch.isReady(vendor) && <PushButton destructive title={tr("删除")} onClick={() => setConfirmDelete(true)} />}
          {testing && <span className="spinner" />}
          <div className="flex-1" />
          <PushButton title={tr("取消")} onClick={onClose} />
          <PushButton
            prominent
            title={tr("保存")}
            disabled={testing}
            onClick={async () => {
              try {
                await m.webSearch.save(vendor, key, baseURL);
                onClose();
              } catch (e) {
                fail(e);
              }
            }}
          />
        </div>
      </div>
      {confirmDelete && (
        <Alert
          title={trf("删除 %@ 的搜索配置？", vendorTitle(vendor))}
          message={tr("保存的密钥和地址会被清掉。")}
          actions={[
            { title: tr("取消"), role: "cancel", onClick: () => setConfirmDelete(false) },
            {
              title: tr("删除"),
              role: "destructive",
              onClick: async () => {
                setConfirmDelete(false);
                try {
                  await m.removeSearch(vendor);
                  onClose();
                } catch (e) {
                  fail(e);
                }
              },
            },
          ]}
        />
      )}
    </Sheet>
  );
}

export function PromptSettingsSection() {
  const m = useModel();
  const [editing, setEditing] = useState<PromptSkill | null>(null);
  return (
    <SettingsSection title={tr("技能")} footer={tr("启用的技能会和系统提示词一起发给模型。")}>
      {m.prompts.skills.map((s) => (
        <div key={s.id} className="flex min-h-[50px] items-center gap-3 px-4 py-2.5">
          <button onClick={() => setEditing(s)} className="flex min-w-0 flex-1 flex-col gap-[3px] text-left">
            <span className="font-body">{s.name}</span>
            <span className="font-caption truncate text-[var(--text-2)]">{s.body}</span>
          </button>
          <Switch label={trf("启用 %@", s.name)} on={s.enabled} onChange={(v) => m.prompts.setEnabled(v, s.id)} />
        </div>
      ))}
      <SettingsAddRow title={tr("添加技能")} onClick={() => setEditing({ id: newID(), name: "", body: "", enabled: true })} />
      {editing && <SkillEditor skill={editing} onClose={() => setEditing(null)} />}
    </SettingsSection>
  );
}

function SkillEditor({ skill, onClose }: { skill: PromptSkill; onClose: () => void }) {
  const m = useModel();
  const [draft, setDraft] = useState(skill);
  const [error, setError] = useState<string | null>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const isNew = !m.prompts.skills.some((s) => s.id === skill.id);
  const save = () => {
    const name = draft.name.trim(), body = draft.body.trim();
    if (!name || !body) return setError(tr("请填写技能名称和内容。"));
    m.prompts.upsert({ ...draft, name, body });
    onClose();
  };
  return (
    <Sheet width={520} onClose={onClose}>
      <div className="flex flex-col gap-4 p-6">
        <div className="font-section-title">{isNew ? tr("添加技能") : tr("编辑技能")}</div>
        <input autoFocus value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} placeholder={tr("技能名称")} className="font-body h-8 rounded-[6px] border border-[var(--separator)] bg-[var(--surface)] px-2 outline-none focus:border-[var(--accent)]" />
        <textarea value={draft.body} onChange={(e) => setDraft({ ...draft, body: e.target.value })} placeholder={tr("写下这段技能要模型怎么做。")} className="font-secondary h-[180px] resize-none rounded-[var(--r-field)] bg-[var(--surface-inset)] px-3 py-2.5 outline-none" />
        {error && <div className="font-caption text-[var(--danger)]">{error}</div>}
        <div className="flex items-center gap-2">
          {!isNew && <PushButton destructive title={tr("删除")} onClick={() => setConfirmDelete(true)} />}
          <div className="flex-1" />
          <PushButton title={tr("取消")} onClick={onClose} />
          <PushButton prominent title={tr("保存")} onClick={save} />
        </div>
      </div>
      {confirmDelete && (
        <Alert
          title={tr("删除技能？")}
          message={tr("删除后，提问和摘要不会再使用这段说明。")}
          actions={[
            { title: tr("取消"), role: "cancel", onClick: () => setConfirmDelete(false) },
            {
              title: tr("删除"),
              role: "destructive",
              onClick: () => {
                m.prompts.delete(draft.id);
                onClose();
              },
            },
          ]}
        />
      )}
    </Sheet>
  );
}

function MemoryRow({ item }: { item: MemoryItem }) {
  const m = useModel();
  const [draft, setDraft] = useState(item.text);
  const [focused, setFocused] = useState(false);
  useEffect(() => {
    if (!focused) setDraft(item.text);
  }, [item.text]);
  const commit = () => draft !== item.text && m.memory.update(item.id, draft);
  return (
    <div className="flex min-h-[50px] items-center gap-3 px-4 py-2.5">
      <span className="font-caption shrink-0 rounded-full bg-[var(--accent-soft)] px-2 py-[3px] font-semibold text-[var(--accent)]">{memoryKindTitle(item.kind)}</span>
      <textarea
        value={draft}
        rows={1}
        onChange={(e) => setDraft(e.target.value)}
        onFocus={() => setFocused(true)}
        onBlur={() => {
          setFocused(false);
          commit();
        }}
        onKeyDown={(e) => e.key === "Enter" && !e.shiftKey && (e.preventDefault(), e.currentTarget.blur())}
        placeholder={tr("记忆内容")}
        className="font-body min-w-0 flex-1 resize-none bg-transparent outline-none [field-sizing:content]"
      />
      <button onClick={() => m.memory.togglePin(item.id)} title={item.pinned ? tr("取消置顶") : tr("置顶：每次都告诉模型")} style={{ color: item.pinned ? "var(--accent)" : "var(--text-2)" }}>
        <Icon name={item.pinned ? "pin.fill" : "pin"} size={14} />
      </button>
      <button onClick={() => m.memory.delete(item.id)} title={tr("删除这条记忆")} className="text-[var(--text-2)]">
        <Icon name="trash" size={14} />
      </button>
    </div>
  );
}

export function MemorySettingsSection({ id }: { id?: string }) {
  const m = useModel();
  const [confirm, setConfirm] = useState(false);
  const items = [...m.memory.items].sort((a, b) => (a.pinned !== b.pinned ? (a.pinned ? -1 : 1) : b.updatedAt.localeCompare(a.updatedAt)));
  return (
    <SettingsSection
      id={id}
      title={tr("记忆")}
      footer={
        <div className="flex items-baseline gap-3">
          <span className="flex-1">{tr("Nomi 会从对话里记下你的偏好、课程和目标，只存在这台 Mac 上。使用 API 模型时，相关记忆会随问题发送。").replace("这台 Mac", "这台电脑").replace("this Mac", "this PC")}</span>
          {items.length > 0 && <LinkButton danger title={tr("清空记忆")} onClick={() => setConfirm(true)} />}
        </div>
      }
    >
      <SettingsRow title={tr("自动记忆")}>
        <Switch label={tr("自动记忆")} on={m.memoryEnabled} onChange={(v) => m.memory.setEnabled(v)} />
      </SettingsRow>
      {items.length === 0 ? <div className="font-secondary px-4 py-3 text-[var(--text-2)]">{m.memoryEnabled ? tr("还没有记忆。多聊几次，Nomi 会慢慢了解你的习惯。") : tr("自动记忆已关闭。")}</div> : items.map((i) => <MemoryRow key={i.id} item={i} />)}
      {confirm && (
        <Alert
          title={tr("清空所有记忆？")}
          message={tr("Nomi 会忘记目前学到的内容，之后从新的对话重新学习。")}
          actions={[
            { title: tr("取消"), role: "cancel", onClick: () => setConfirm(false) },
            {
              title: tr("清空"),
              role: "destructive",
              onClick: () => {
                m.memory.clear();
                setConfirm(false);
              },
            },
          ]}
        />
      )}
    </SettingsSection>
  );
}

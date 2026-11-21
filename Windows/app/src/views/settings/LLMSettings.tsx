// Pages/LLMSettingsSection.swift: reply language, busy-send mode, pop-ups, the local model, API profiles.
import { useEffect, useState } from "react";
import { tr, trf } from "../../i18n";
import { languageName } from "../../support/format";
import { LectureLanguages } from "../../support/languages";
import { prefs } from "../../support/prefs";
import { PromptPreferences } from "../../models/promptPreferences";
import { apiModeTitle, formatTitle, LLMKeys, logoFile, newProfile, Profiles, providerPresets, thinkingTitle, type LLMAPIProfile } from "../../models/llmConfiguration";
import { RemoteLLM } from "../../engine/remoteLLM";
import { BusySend, busySendTitle, type BusySendMode } from "../../app/chatQueue";
import { QuestionPopupPreference } from "../../app/qa";
import { useModel } from "../../app";
import { Icon } from "../ui/Icon";
import { ProviderLogo } from "../ui/Logos";
import { Alert, Menu, PopUp, PushButton, Segmented, SettingsAddRow, SettingsRow, SettingsSection, Sheet, Switch } from "../ui/controls";
import { LocalModelPicker } from "./LocalModels";

export function LLMSettingsSection() {
  const m = useModel();
  const [editing, setEditing] = useState<LLMAPIProfile | null>(null);
  const [confirming, setConfirming] = useState<LLMAPIProfile | null>(null);
  const [busySend, setBusySend] = useState<BusySendMode>(BusySend.current);
  const [popups, setPopups] = useState(QuestionPopupPreference.isOn);
  const busy = m.assistantIsBusy;
  return (
    <>
      <SettingsSection title={tr("提问与摘要大模型")} footer={tr("排队：等这条回答结束后依次发送。打断并引导：立即停下当前回答，保留已写的部分，按新消息继续。⌘Enter 使用另一种方式。").replace("⌘", "Ctrl+")}>
        <SettingsRow title={tr("默认回复语言")}>
          <PopUp value={m.prompts.replyLanguage} onChange={(v) => m.prompts.setReplyLanguage(v)} options={[{ value: PromptPreferences.followInterface, title: tr("跟随界面") }, ...LectureLanguages.supported.map((c) => ({ value: c, title: languageName(c) }))]} />
        </SettingsRow>
        <SettingsRow title={tr("回答中发送新消息")}>
          <Segmented
            value={busySend}
            onChange={(v) => {
              BusySend.current = v;
              setBusySend(v);
            }}
            options={(["queue", "steer"] as BusySendMode[]).map((v) => ({ value: v, title: busySendTitle(v) }))}
          />
        </SettingsRow>
        <SettingsRow title={tr("录音时弹出老师的提问")} detail={tr("老师问了真正的问题时，它会在窗口上浮出几秒，你可以马上回答或稍后再看。")}>
          <Switch
            label={tr("录音时弹出老师的提问")}
            on={popups}
            onChange={(v) => {
              prefs.set(QuestionPopupPreference.key, v);
              setPopups(v);
            }}
          />
        </SettingsRow>
      </SettingsSection>
      <SettingsSection title={tr("本地大模型")} footer={tr("在提问框的模型菜单里选择用本地模型还是 API，提问、摘要和 Q&A 都会跟随。")}>
        <LocalModelPicker role="assistant" />
      </SettingsSection>
      <SettingsSection title="API" footer={m.llmConfiguration.activeProfile ? undefined : tr("添加并选择一个 API 配置后，即可使用提问和摘要。")}>
        {m.llmConfiguration.profiles.map((p) => {
          const active = m.llmConfiguration.activeID === p.id;
          return (
            <div key={p.id} className="flex min-h-[50px] items-center gap-3 px-4 py-2.5" style={{ opacity: busy ? 0.5 : 1, pointerEvents: busy ? "none" : "auto" }}>
              <button onClick={() => !active && setConfirming(p)} className="flex min-w-0 flex-1 items-center gap-3 text-left">
                <span style={{ color: active ? "var(--accent)" : "var(--text-2)" }}>
                  <Icon name={active ? "checkmark.circle.fill" : "circle"} size={16} />
                </span>
                <ProviderLogo file={logoFile(p.providerID)} />
                <span className="flex min-w-0 flex-col gap-[3px]">
                  <span className="font-body truncate">{p.name}</span>
                  <span className="font-caption truncate text-[var(--text-2)]">{p.modelID}</span>
                </span>
              </button>
              <PushButton small title={tr("编辑")} onClick={() => setEditing(p)} />
            </div>
          );
        })}
        <div style={{ opacity: busy ? 0.5 : 1, pointerEvents: busy ? "none" : "auto" }}>
          <SettingsAddRow title={tr("添加 API 配置")} onClick={() => setEditing(newProfile({ providerID: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1" }))} />
        </div>
      </SettingsSection>
      {editing && <APIProfileEditor profile={editing} onClose={() => setEditing(null)} />}
      {confirming && (
        <Alert
          title={tr("使用此 API 配置？")}
          message={trf("后续提问和摘要将使用 %@（%@），相关会议文字会发送到此地址。", confirming.name, confirming.baseURL)}
          actions={[
            { title: tr("取消"), role: "cancel", onClick: () => setConfirming(null) },
            {
              title: tr("确认"),
              onClick: () => {
                m.llmConfiguration.activate(confirming.id);
                m.llmConfiguration.setMode("api");
                setConfirming(null);
              },
            },
          ]}
        />
      )}
    </>
  );
}

function FieldRow({ title, children, top }: { title: string; children: React.ReactNode; top?: boolean }) {
  return (
    <div className={`flex gap-3 ${top ? "items-start" : "items-center"}`}>
      <span className={`font-secondary w-[148px] shrink-0 text-right ${top ? "pt-1.5" : ""}`}>{title}</span>
      <div className="min-w-0 flex-1">{children}</div>
    </div>
  );
}

const input = "font-secondary h-7 w-full rounded-[6px] border border-[var(--separator)] bg-[var(--surface)] px-2 outline-none focus:border-[var(--accent)]";

export function APIProfileEditor({ profile, onClose }: { profile: LLMAPIProfile; onClose: () => void }) {
  const m = useModel();
  const config = m.llmConfiguration;
  const [draft, setDraft] = useState<LLMAPIProfile>(() => (profile.modelID && !profile.savedModelIDs.includes(profile.modelID) ? { ...profile, savedModelIDs: [profile.modelID, ...profile.savedModelIDs] } : profile));
  const [key, setKey] = useState("");
  const [entry, setEntry] = useState("");
  const [available, setAvailable] = useState<string[]>([]);
  const [fetching, setFetching] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [confirmSave, setConfirmSave] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [presetMenu, setPresetMenu] = useState<HTMLElement | null>(null);
  const isSaved = config.profiles.some((p) => p.id === draft.id);
  useEffect(() => {
    void LLMKeys.read(draft).then(setKey, () => {});
  }, []);
  const choices = [...draft.savedModelIDs, ...available.filter((id) => !draft.savedModelIDs.includes(id))];
  const addEntered = (d = draft): LLMAPIProfile => {
    const id = entry.trim();
    if (!id) return d;
    const next = { ...d, savedModelIDs: d.savedModelIDs.includes(id) ? d.savedModelIDs : [...d.savedModelIDs, id], modelID: id };
    setDraft(next);
    setEntry("");
    return next;
  };
  const remove = (id: string) => {
    const saved = draft.savedModelIDs.filter((x) => x !== id);
    setAvailable((a) => a.filter((x) => x !== id));
    setDraft({ ...draft, savedModelIDs: saved, modelID: draft.modelID === id ? (saved[0] ?? "") : draft.modelID });
  };
  const apiModeNote = draft.format === "anthropic" ? tr("Anthropic 使用自己的 Messages 接口，不支持 Responses。") : draft.apiMode === "responses" && draft.responsesUnsupported ? tr("这个服务没有 Responses 接口，回答时已改用 Chat Completions。重新选择后会再试一次。") : draft.apiMode === "responses" ? tr("OpenAI 的推理模型只有用 Responses 才会显示思考过程。") : null;
  const preset = providerPresets.find((p) => p.id === draft.providerID);
  const fetchModels = async () => {
    let d = addEntered();
    try {
      d = Profiles.validated(d, false);
      setDraft(d);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      return;
    }
    setFetching(true);
    try {
      let secret = key.trim();
      if (!secret && config.profiles.some((p) => p.id === d.id && p.baseURL === d.baseURL)) secret = await LLMKeys.read(d);
      if (!Profiles.isLoopback(d) && !secret) throw new Error(tr("请输入 API 密钥。"));
      const models = await RemoteLLM.models(d, secret);
      setAvailable(models);
      const saved = [...d.savedModelIDs, ...models.filter((id) => !d.savedModelIDs.includes(id))];
      setDraft({ ...d, savedModelIDs: saved, modelID: d.modelID || saved[0] || "" });
      if (!models.length) setError(tr("服务未返回模型列表，可以手动填写模型 ID。"));
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setFetching(false);
    }
  };
  return (
    <Sheet width={540} onClose={onClose}>
      <div className="scroll flex max-h-[calc(100vh-48px)] flex-col gap-4 p-6">
        <div className="flex items-center gap-3">
          <ProviderLogo file={logoFile(draft.providerID)} side={22} />
          <span className="font-section-title">{tr("API 配置")}</span>
        </div>
        <div className="flex flex-col gap-3" style={{ opacity: fetching ? 0.6 : 1, pointerEvents: fetching ? "none" : "auto" }}>
          <FieldRow title={tr("服务商预设")}>
            <button onClick={(e) => setPresetMenu(e.currentTarget)} className="font-secondary flex items-center gap-1.5 font-medium">
              <ProviderLogo file={logoFile(draft.providerID)} side={16} />
              {tr(preset?.name ?? "自定义")}
              <Icon name="chevron.up.chevron.down" size={11} />
            </button>
          </FieldRow>
          <FieldRow title={tr("配置名称")}>
            <input value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} placeholder={tr("配置名称")} className={input} />
          </FieldRow>
          <FieldRow title="API Base URL">
            <input value={draft.baseURL} onChange={(e) => setDraft({ ...draft, baseURL: e.target.value })} placeholder="API Base URL" className={input} />
          </FieldRow>
          <FieldRow title={tr("接口格式")}>
            <PopUp value={draft.format} onChange={(v) => setDraft({ ...draft, format: v })} options={(["openAI", "anthropic"] as const).map((f) => ({ value: f, title: formatTitle(f) }))} />
          </FieldRow>
          <FieldRow title={tr("接口模式")} top>
            <div className="flex flex-col gap-1">
              <div style={{ opacity: draft.format === "anthropic" ? 0.5 : 1, pointerEvents: draft.format === "anthropic" ? "none" : "auto" }}>
                <Segmented value={draft.apiMode} onChange={(v) => setDraft({ ...draft, apiMode: v })} options={(["chatCompletions", "responses"] as const).map((v) => ({ value: v, title: apiModeTitle(v) }))} />
              </div>
              {apiModeNote && <span className="text-[11px] text-[var(--text-2)]">{apiModeNote}</span>}
            </div>
          </FieldRow>
          <FieldRow title={tr("深入思考")} top>
            <div className="flex flex-col gap-1">
              <Segmented value={draft.thinking} onChange={(v) => setDraft({ ...draft, thinking: v })} options={(["off", "low", "medium", "high"] as const).map((v) => ({ value: v, title: thinkingTitle(v) }))} />
              <span className="text-[11px] text-[var(--text-2)]">{Profiles.thinkingUnsupported(draft) && draft.thinking !== "off" ? tr("这个模型不接受思考参数，回答时会自动不带它。重新选择后会再试一次。") : tr("模型先思考再回答，思考过程会在聊天里实时显示。级别越高越慢，也越费 token。")}</span>
            </div>
          </FieldRow>
          <FieldRow title={tr("API 密钥")}>
            <input type="password" value={key} onChange={(e) => setKey(e.target.value)} placeholder={tr("API 密钥")} className={input} />
          </FieldRow>
          <FieldRow title={tr("模型列表")} top>
            <div className="flex flex-col gap-2">
              <div className="flex items-center gap-1.5">
                <input value={entry} onChange={(e) => setEntry(e.target.value)} onKeyDown={(e) => e.key === "Enter" && addEntered()} placeholder={tr("模型 ID")} className={input} />
                <button onClick={() => addEntered()} disabled={!entry.trim()} title={tr("添加模型")} className="flex h-[22px] w-[22px] shrink-0 items-center justify-center disabled:opacity-40">
                  <Icon name="plus" size={13} weight={2.6} />
                </button>
              </div>
              {choices.map((id) => (
                <div key={id} className="flex items-center gap-1.5">
                  <button onClick={() => setDraft({ ...draft, modelID: id })} className="flex min-w-0 flex-1 items-center gap-1.5 text-left">
                    <span className="text-[var(--accent)]">
                      <Icon name={draft.modelID === id ? "checkmark.circle.fill" : "circle"} size={14} />
                    </span>
                    <span className="font-secondary truncate">{id}</span>
                  </button>
                  <button onClick={() => remove(id)} className="flex h-[22px] w-[22px] items-center justify-center text-[var(--text-2)]">
                    <Icon name="xmark" size={12} weight={2.6} />
                  </button>
                </div>
              ))}
            </div>
          </FieldRow>
        </div>
        {error && <div className="font-caption selectable text-[var(--danger)]">{error}</div>}
        <div className="flex items-center gap-2">
          <PushButton title={tr("获取模型列表")} disabled={fetching} onClick={() => void fetchModels()} />
          {isSaved && <PushButton destructive title={tr("删除")} onClick={() => setConfirmDelete(true)} />}
          {fetching && <span className="spinner" />}
          <div className="flex-1" />
          <PushButton title={tr("取消")} onClick={onClose} />
          <PushButton
            prominent
            title={tr("保存")}
            disabled={fetching}
            onClick={() => {
              const d = addEntered();
              try {
                setDraft(Profiles.validated(d, true));
                setError(null);
                setConfirmSave(true);
              } catch (e) {
                setError(e instanceof Error ? e.message : String(e));
              }
            }}
          />
        </div>
      </div>
      {presetMenu && (
        <Menu
          anchor={presetMenu}
          onClose={() => setPresetMenu(null)}
          items={providerPresets.map((p) => ({
            kind: "item" as const,
            title: tr(p.name),
            checked: draft.providerID === p.id,
            onSelect: () => {
              setDraft({ ...draft, providerID: p.id, name: tr(p.name), baseURL: p.baseURL, format: p.format, modelID: "", savedModelIDs: [] });
              setKey("");
              setEntry("");
              setAvailable([]);
            },
          }))}
        />
      )}
      {confirmSave && (
        <Alert
          title={tr("保存 API 配置？")}
          message={trf("保存 %@（%@）及所选模型。使用 API 提问和摘要时，相关会议文字将发送到此地址。", draft.name, draft.baseURL)}
          actions={[
            { title: tr("取消"), role: "cancel", onClick: () => setConfirmSave(false) },
            {
              title: tr("确认"),
              onClick: async () => {
                setConfirmSave(false);
                try {
                  await config.save(draft, key);
                  onClose();
                } catch (e) {
                  setError(e instanceof Error ? e.message : String(e));
                }
              },
            },
          ]}
        />
      )}
      {confirmDelete && (
        <Alert
          title={tr("删除 API 配置？")}
          message={trf("删除 %@ 的地址、模型选择和已保存的 API 密钥。此操作不会删除会议。", draft.name)}
          actions={[
            { title: tr("取消"), role: "cancel", onClick: () => setConfirmDelete(false) },
            {
              title: tr("删除"),
              role: "destructive",
              onClick: async () => {
                setConfirmDelete(false);
                const saved = config.profiles.find((p) => p.id === draft.id);
                try {
                  if (saved) await config.delete(saved);
                  onClose();
                } catch (e) {
                  setError(e instanceof Error ? e.message : String(e));
                }
              },
            },
          ]}
        />
      )}
    </Sheet>
  );
}

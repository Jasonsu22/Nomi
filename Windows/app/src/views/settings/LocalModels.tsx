// Pages/LocalModelsSection.swift and SpeakerModelsSection.swift, plus the Windows engine options.
import { useState } from "react";
import { tr, trf } from "../../i18n";
import { formatBytes } from "../../support/format";
import { prefs } from "../../support/prefs";
import { catalog, findModel, modelBytes, roleTitle, selectedModel, supports, type LocalModelDefinition, type LocalModelRole } from "../../models/localModels";
import { modelPath } from "../../engine/localEngine";
import { SpeakerModels, speakerModelKinds, type SpeakerModelKind } from "../../app/voices";
import { useModel } from "../../app";
import { paths, shell } from "../../platform";
import { Icon } from "../ui/Icon";
import { Alert, LinkButton, Popover, PopUp, SettingsRow, SettingsSection, Switch } from "../ui/controls";

const repoPage = (m: LocalModelDefinition) => "https://huggingface.co/" + m.files.at(-1)!.path.split("/").slice(0, 2).join("/");
const same = (a: string | undefined, b: string) => !!a && a.replace(/\//g, "\\").toLowerCase() === b.replace(/\//g, "\\").toLowerCase();

export function PopUpLabel({ title, detail, onClick, label }: { title: string; detail: string; onClick: (e: React.MouseEvent<HTMLButtonElement>) => void; label: string }) {
  return (
    <button onClick={onClick} aria-label={label} className="group flex items-center gap-2 rounded-[7px] py-1 pr-[3px] pl-2 hover:bg-[var(--surface-inset)]">
      <span className="flex flex-col items-end gap-1">
        <span className="font-secondary font-medium">{title}</span>
        <span className="font-caption text-[var(--text-2)]">{detail}</span>
      </span>
      <span className="flex h-5 w-5 items-center justify-center rounded-[5px] bg-[var(--surface-inset)] group-hover:bg-[color-mix(in_srgb,var(--text)_10%,transparent)]">
        <Icon name="chevron.up.chevron.down" size={11} weight={2.4} />
      </span>
    </button>
  );
}

export function SmallButton({ title, icon, onClick, disabled, danger, tint }: { title: string; icon?: string; onClick: () => void; disabled?: boolean; danger?: boolean; tint?: boolean }) {
  return (
    <button onClick={onClick} disabled={disabled} className="press font-caption inline-flex min-w-[72px] items-center justify-center gap-1 rounded-[6px] bg-[var(--surface-inset)] px-2 py-1 disabled:opacity-40" style={{ color: danger ? "var(--danger)" : tint ? "var(--accent)" : "var(--text)" }}>
      {icon && <Icon name={icon} size={12} />}
      {title}
    </button>
  );
}

function Progress({ fraction }: { fraction: number }) {
  return (
    <div className="h-1 overflow-hidden rounded-full bg-[var(--surface-inset)]">
      <div className="h-full rounded-full bg-[var(--accent)] transition-[width] duration-300" style={{ width: `${Math.round(fraction * 100)}%` }} />
    </div>
  );
}

export function LocalModelPicker({ role }: { role: LocalModelRole }) {
  const m = useModel();
  const [anchor, setAnchor] = useState<HTMLElement | null>(null);
  const [deleting, setDeleting] = useState<LocalModelDefinition | null>(null);
  const engineStatus = m.engine.modelStatus;
  // The local language model shares the translator's worker when they are the same file.
  const sharedAssistant = engineStatus?.assistant && !engineStatus.assistant.loaded && engineStatus.translator.loaded && same(engineStatus.assistant.path, engineStatus.translator.path) ? engineStatus.translator : engineStatus?.assistant;
  const runtime = role === "asr" ? engineStatus?.asr : role === "translator" ? engineStatus?.translator : (sharedAssistant ?? undefined);
  const current = catalog.find((x) => supports(x, role) && same(runtime?.path, modelPath(x))) ?? selectedModel(role);
  const switchingRole = m.localModels.switchingID !== null && m.localModels.switchingRole === role;
  const status = m.localModels.deletingID === current.id ? tr("正在删除…") : switchingRole || m.engine.readiness === "preparing" ? tr("正在加载…") : runtime?.loaded ? tr("使用中") : runtime?.error ? tr("加载失败") : m.localModels.installed.has(current.id) ? tr("未加载") : tr("未下载");
  const option = (item: LocalModelDefinition) => {
    const installed = m.localModels.installed.has(item.id);
    const active = !switchingRole && !!runtime?.loaded && same(runtime.path, modelPath(item));
    const progress = m.localModels.downloads[item.id];
    const switching = m.localModels.switchingID === item.id;
    const error = m.localModels.errors[item.id] ?? (same(runtime?.path, modelPath(item)) ? runtime?.error : null);
    return (
      <div key={item.id} className="flex flex-col gap-2 px-4 py-3">
        <div className="flex items-center gap-3">
          <div className="flex min-w-0 flex-1 flex-col gap-1">
            <span className="font-body font-medium">{item.name}</span>
            <span className="font-caption text-[var(--text-2)]">{`${item.quantization} · ${formatBytes(modelBytes(item))}`}</span>
            <button onClick={() => void shell.openURL(repoPage(item))} className="font-caption self-start text-[var(--accent)]">
              {tr("查看模型")}
            </button>
          </div>
          <div className="flex flex-col items-center gap-2">
            {switching ? (
              <span className="spinner" aria-label={tr("正在加载…")} />
            ) : progress ? (
              <SmallButton title={tr("取消")} onClick={() => m.localModels.cancel(item)} />
            ) : active ? (
              <span className="font-caption flex min-w-[72px] items-center justify-center gap-1 text-[var(--accent)]">
                <Icon name="checkmark.circle.fill" size={13} />
                {tr("使用中")}
              </span>
            ) : installed ? (
              <SmallButton title={tr("使用")} disabled={!m.canSwitchModels} onClick={() => void m.selectLocalModel(item, role)} />
            ) : (
              <SmallButton title={m.localModels.errors[item.id] ? tr("重试") : tr("下载")} icon="arrow.down.circle" onClick={() => m.localModels.download(item)} />
            )}
            {installed && (
              <SmallButton
                danger
                title={tr("删除")}
                icon="trash"
                disabled={!m.canSwitchModels}
                onClick={() => {
                  setAnchor(null);
                  setDeleting(item);
                }}
              />
            )}
          </div>
        </div>
        {progress && (
          <>
            <Progress fraction={progress.total ? progress.received / progress.total : 0} />
            <span className="font-caption text-[var(--text-2)]">
              {`${formatBytes(progress.received)} / ${formatBytes(progress.total)}`}
              {progress.bytesPerSecond > 0 ? ` · ${formatBytes(progress.bytesPerSecond)}/s` : ""}
            </span>
          </>
        )}
        {error && <span className="font-caption selectable text-[var(--danger)]">{error}</span>}
      </div>
    );
  };
  return (
    <SettingsRow title={roleTitle(role)}>
      <PopUpLabel
        title={current.name}
        detail={status}
        label={trf("选择%@", roleTitle(role))}
        onClick={(e) => {
          m.localModels.refreshInBackground();
          setAnchor(e.currentTarget);
        }}
      />
      {anchor && (
        <Popover anchor={anchor} onClose={() => setAnchor(null)} align="end">
          <div className="menu flex w-[440px] flex-col">
            <div className="font-section-title p-4">{roleTitle(role)}</div>
            <div className="scroll max-h-[400px]">{catalog.filter((x) => supports(x, role)).map(option)}</div>
            <div className="font-caption p-4 text-[var(--text-2)]">{tr("来源：Hugging Face。下载完成后点击「使用」切换。")}</div>
          </div>
        </Popover>
      )}
      {deleting && (
        <Alert
          title={tr("删除本地模型？")}
          message={trf("将卸载 %@ 并移到废纸篓。使用此模型的功能会暂停，可重新下载或从废纸篓恢复。", deleting.name).replace("废纸篓", "回收站").replace("Trash", "Recycle Bin")}
          actions={[
            { title: tr("取消"), role: "cancel", onClick: () => setDeleting(null) },
            {
              title: tr("删除"),
              role: "destructive",
              onClick: () => {
                void m.deleteLocalModel(deleting);
                setDeleting(null);
              },
            },
          ]}
        />
      )}
    </SettingsRow>
  );
}

export function LocalModelsSection({ children }: { children: React.ReactNode }) {
  const m = useModel();
  return (
    <SettingsSection
      title={tr("录音与翻译")}
      footer={
        <div className="flex flex-col gap-1">
          <div className="flex items-center">
            <span className="flex-1">{tr("下载一次，即可在本机离线使用。")}</span>
            <LinkButton title={tr("打开模型文件夹")} onClick={() => void shell.openPath(paths.join(paths.root, "models"))} />
          </div>
          {m.engine.session.phase !== "idle" && <span>{tr("录制结束后可以切换模型。")}</span>}
        </div>
      }
    >
      {children}
      <LocalModelPicker role="asr" />
      <LocalModelPicker role="translator" />
    </SettingsSection>
  );
}

/** Windows: how the workers run. The Mac uses Apple silicon and needs none of these. */
export function EngineSection() {
  const m = useModel();
  const [, redraw] = useState(0);
  const set = (key: string, value: string | number) => {
    prefs.set(key, value);
    redraw((n) => n + 1);
  };
  const devices = [
    { value: "auto", title: tr("自动") },
    { value: "gpu", title: tr("显卡（Vulkan）") },
    { value: "cpu", title: "CPU" },
  ];
  return (
    <SettingsSection title={tr("运行方式")} footer={<div className="flex items-center"><span className="flex-1">{tr("没有独立显卡时用 CPU 也能实时转写，选小一点的模型会更流畅。修改后会重新启动转录服务。")}</span><LinkButton title={tr("重新启动")} disabled={m.engine.session.phase !== "idle"} onClick={() => void m.engine.relaunch()} /></div>}>
      <SettingsRow title={tr("语音识别使用")}>
        <PopUp value={prefs.string("nomi.windows.asrDevice") ?? "auto"} onChange={(v) => set("nomi.windows.asrDevice", v)} options={devices} />
      </SettingsRow>
      <SettingsRow title={tr("翻译和本地大模型使用")}>
        <PopUp value={prefs.string("nomi.windows.llmDevice") ?? "cpu"} onChange={(v) => set("nomi.windows.llmDevice", v)} options={devices} />
      </SettingsRow>
      <SettingsRow title={tr("实时预览")} detail={tr("说话时先显示灰色的预览文字。电脑跟不上时会跳过一些预览，不影响最终的转写。")}>
        <PopUp
          value={prefs.string("nomi.windows.interim") ?? "skip-busy"}
          onChange={(v) => set("nomi.windows.interim", v)}
          options={[
            { value: "all", title: tr("每次都显示") },
            { value: "skip-busy", title: tr("忙时跳过") },
            { value: "off", title: tr("关闭") },
          ]}
        />
      </SettingsRow>
    </SettingsSection>
  );
}

function SpeakerModelPicker() {
  const m = useModel();
  const [anchor, setAnchor] = useState<HTMLElement | null>(null);
  const [deleting, setDeleting] = useState<SpeakerModelKind | null>(null);
  const [, redraw] = useState(0);
  const current = SpeakerModels.chosen;
  const def = (k: SpeakerModelKind) => findModel(SpeakerModels.modelID(k))!;
  const isDownloading = (k: SpeakerModelKind) => m.localModels.isDownloading(def(k).id);
  const installed = (k: SpeakerModelKind) => m.localModels.installed.has(def(k).id);
  const status = isDownloading(current) ? tr("正在下载…") : installed(current) ? tr("使用中") : tr("未下载");
  return (
    <SettingsRow title={tr("说话人模型")}>
      <PopUpLabel title={SpeakerModels.title(current)} detail={status} label={tr("选择说话人模型")} onClick={(e) => setAnchor(e.currentTarget)} />
      {anchor && (
        <Popover anchor={anchor} onClose={() => setAnchor(null)} align="end">
          <div className="menu flex w-[440px] flex-col">
            <div className="font-section-title p-4">{tr("说话人模型")}</div>
            {speakerModelKinds.map((k) => {
              const d = def(k);
              const on = installed(k);
              const active = current === k && on;
              const progress = m.localModels.downloads[d.id];
              return (
                <div key={k} className="flex flex-col gap-2 px-4 py-3">
                  <div className="flex items-center gap-3">
                    <div className="flex min-w-0 flex-1 flex-col gap-1">
                      <span className="font-body font-medium">{SpeakerModels.title(k)}</span>
                      <span className="font-caption text-[var(--text-2)]">{`${SpeakerModels.detail(k)} · ${formatBytes(modelBytes(d))}`}</span>
                      <button onClick={() => void shell.openURL(SpeakerModels.page(k))} className="font-caption self-start text-[var(--accent)]">
                        {tr("查看模型")}
                      </button>
                    </div>
                    <div className="flex flex-col items-center gap-2">
                      {progress ? (
                        <span className="spinner" aria-label={tr("正在下载…")} />
                      ) : active ? (
                        <span className="font-caption flex min-w-[72px] items-center justify-center gap-1 text-[var(--accent)]">
                          <Icon name="checkmark.circle.fill" size={13} />
                          {tr("使用中")}
                        </span>
                      ) : on ? (
                        <SmallButton
                          title={tr("使用")}
                          onClick={() => {
                            prefs.set(SpeakerModels.choiceKey, k);
                            redraw((n) => n + 1);
                          }}
                        />
                      ) : (
                        <SmallButton title={m.localModels.errors[d.id] ? tr("重试") : tr("下载")} icon="arrow.down.circle" onClick={() => m.localModels.download(d)} />
                      )}
                      {on && !progress && (
                        <SmallButton
                          danger
                          title={tr("删除")}
                          icon="trash"
                          onClick={() => {
                            setAnchor(null);
                            setDeleting(k);
                          }}
                        />
                      )}
                    </div>
                  </div>
                  {progress && <Progress fraction={progress.total ? progress.received / progress.total : 0} />}
                  {m.localModels.errors[d.id] && <span className="font-caption text-[var(--danger)]">{m.localModels.errors[d.id]}</span>}
                </div>
              );
            })}
            <div className="font-caption p-4 text-[var(--text-2)]">{tr("来源：Hugging Face。下载完成后点击「使用」切换，下一次开始录音时生效。")}</div>
          </div>
        </Popover>
      )}
      {deleting && (
        <Alert
          title={tr("删除说话人模型？")}
          message={trf("将删除 %@。之后录音时用它区分说话人需要重新下载。", SpeakerModels.title(deleting))}
          actions={[
            { title: tr("取消"), role: "cancel", onClick: () => setDeleting(null) },
            {
              title: tr("删除"),
              role: "destructive",
              onClick: () => {
                void m.localModels.trash(def(deleting));
                setDeleting(null);
              },
            },
          ]}
        />
      )}
    </SettingsRow>
  );
}

export function SpeakerModelsSection() {
  const [enabled, setEnabled] = useState(SpeakerModels.isEnabled);
  return (
    <SettingsSection title={tr("实时区分说话人（实验）")} footer={tr("三个模型都在两节真实课堂录音上测过，和录音结束后的分析结果一致率在 92%–100%。").replace("三个", "两个").replace("All three", "Both")}>
      <SettingsRow title={tr("录音时标出说话人")} detail={tr("在这台 Mac 上边录边分出每个人的声音，转写里每段话前会标出说话人 1、2、3…（你标出自己后会显示“我”），可以右键改名。下一次开始录音时生效。").replace("这台 Mac", "这台电脑").replace("this Mac", "this PC")}>
        <Switch
          label={tr("录音时标出说话人")}
          on={enabled}
          onChange={(v) => {
            prefs.set(SpeakerModels.enabledKey, v);
            setEnabled(v);
          }}
        />
      </SettingsRow>
      <SpeakerModelPicker />
    </SettingsSection>
  );
}

// Shell/OnboardingView.swift: welcome, download the models, speakers, microphone, an API, then start.
import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { tr, trf } from "../../i18n";
import { formatBytes } from "../../support/format";
import { prefs } from "../../support/prefs";
import { findModel, modelBytes, type LocalModelDefinition, type LocalModelRole } from "../../models/localModels";
import { logoFile, newProfile, providerPresets, type LLMAPIProfile } from "../../models/llmConfiguration";
import { SpeakerModels, speakerModelKinds, type SpeakerModelKind } from "../../app/voices";
import { OnboardingPreference } from "../../app/onboarding";
import { useModel } from "../../app";
import { paths, shell } from "../../platform";
import { BrandLogo, ProviderLogo } from "../ui/Logos";
import { Icon } from "../ui/Icon";
import { PushButton, Sheet } from "../ui/controls";
import { APIProfileEditor } from "../settings/LLMSettings";

const steps = 6;
const quickProviders = ["openai", "anthropic", "gemini", "deepseek", "kimi", "custom"];
type Mic = "granted" | "denied" | "unknown";
const pc = (s: string) => s.replace(/这台 Mac/g, "这台电脑").replace(/this Mac/g, "this PC").replace(/macOS/g, "Windows");

function Footer({ children }: { children: React.ReactNode }) {
  return <div className="flex items-center gap-2 pt-6">{children}</div>;
}
function Back({ onClick }: { onClick: () => void }) {
  return (
    <button onClick={onClick} className="font-secondary text-[var(--text-2)]">
      {tr("返回")}
    </button>
  );
}
function Title({ children }: { children: React.ReactNode }) {
  return <div className="text-[22px] font-bold">{children}</div>;
}
function Lead({ children }: { children: React.ReactNode }) {
  return <div className="font-body pt-1 pb-4 text-[var(--text-2)]">{children}</div>;
}
function Badge({ children }: { children: React.ReactNode }) {
  return <span className="font-caption rounded-[6px] bg-[color-mix(in_srgb,var(--accent-green)_12%,transparent)] px-[7px] py-[1px] font-bold text-[var(--accent-green)]">{children}</span>;
}
function Bar({ fraction }: { fraction: number }) {
  return (
    <div className="mt-1 h-1 overflow-hidden rounded-full bg-[var(--surface-inset)]">
      <div className="h-full rounded-full bg-[var(--accent-green)] transition-[width] duration-300" style={{ width: `${Math.round(fraction * 100)}%` }} />
    </div>
  );
}

export function OnboardingView() {
  const m = useModel();
  const [step, setStep] = useState(OnboardingPreference.done ? 1 : 0);
  const [asr, setAsr] = useState<LocalModelDefinition>(() => m.recommendedModel("asr"));
  const [translator, setTranslator] = useState<LocalModelDefinition>(() => m.recommendedModel("translator"));
  const [started, setStarted] = useState(false);
  const [mic, setMic] = useState<Mic>("unknown");
  const [binding, setBinding] = useState<LLMAPIProfile | null>(null);
  const [speakerChoice, setSpeakerChoice] = useState<SpeakerModelKind>(SpeakerModels.chosen);
  useEffect(() => {
    void m.localModels.refresh();
  }, []);
  const checkMic = () => void invoke<Mic>("microphone_access").then(setMic, () => setMic("unknown"));
  useEffect(checkMic, [step]);
  const go = (n: number) => setStep(Math.max(0, Math.min(steps - 1, n)));
  const fraction = (id: string) => {
    const p = m.localModels.downloads[id];
    return p && p.total ? p.received / p.total : 0;
  };

  const modelCard = (title: string, detail: string, role: LocalModelRole, item: LocalModelDefinition, choose: (d: LocalModelDefinition) => void) => {
    const installed = m.localModels.installed.has(item.id);
    const progress = m.localModels.downloads[item.id];
    const error = m.localModels.errors[item.id];
    const recommended = item.id === m.recommendedModel(role).id;
    const alt = m.alternativeModel(role);
    return (
      <div className="mb-2 flex flex-col gap-1 rounded-[14px] border border-[var(--separator)] px-4 py-3">
        <div className="flex items-center gap-2">
          <span className="font-body font-semibold">{title}</span>
          {recommended && <Badge>{pc(tr("推荐这台 Mac 使用"))}</Badge>}
          <div className="flex-1" />
          <span className="font-secondary font-semibold tabular-nums" style={{ color: installed ? "var(--accent-green)" : "var(--text-2)" }}>{installed ? tr("已下载 ✓") : progress ? `${Math.round(fraction(item.id) * 100)}%` : formatBytes(modelBytes(item))}</span>
        </div>
        <div className="font-secondary text-[var(--text-2)]">{`${item.name} · ${detail}`}</div>
        {progress && <Bar fraction={fraction(item.id)} />}
        {error ? (
          <div className="flex items-center gap-2">
            <span className="font-caption line-clamp-2 flex-1 text-[var(--danger)]">{error}</span>
            <PushButton small title={tr("重试")} onClick={() => m.downloadAndUse(item, role)} />
          </div>
        ) : (
          !started &&
          !installed &&
          !progress &&
          alt && (
            <button onClick={() => choose(item.id === alt.id ? m.recommendedModel(role) : alt)} className="font-caption self-start text-[var(--accent)]">
              {item.id === alt.id ? trf("改用推荐的 %@", m.recommendedModel(role).name) : trf("改用更轻的 %@（%@）", alt.name, formatBytes(modelBytes(alt)))}
            </button>
          )
        )}
      </div>
    );
  };

  let body: React.ReactNode;
  if (step === 0) {
    const feature = (symbol: string, title: string, detail: string) => (
      <div className="flex items-start gap-3 py-[7px]">
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-[10px] bg-[var(--accent-soft)] text-[var(--accent)]">
          <Icon name={symbol} size={16} />
        </span>
        <span className="flex flex-col gap-0.5">
          <span className="font-body font-semibold">{title}</span>
          <span className="font-secondary text-[var(--text-2)]">{detail}</span>
        </span>
      </div>
    );
    body = (
      <>
        <BrandLogo side={64} />
        <div className="pt-3 text-[26px] font-bold">{tr("欢迎使用 Nomi")}</div>
        <Lead>{tr("用母语听懂每一节课。")}</Lead>
        {feature("waveform", tr("实时转写"), tr("老师说话时，文字随之出现。"))}
        {feature("character.bubble", tr("每一句下面都有翻译"), tr("支持中文、英文等九种语言。"))}
        {feature("bubble.left.and.text.bubble.right", tr("针对任何一节课提问"), tr("提问、摘要，还会回答老师在课上提的问题。"))}
        <Footer>
          <button onClick={() => m.finishOnboarding(false)} className="font-secondary text-[var(--text-2)]">
            {tr("稍后设置")}
          </button>
          <div className="flex-1" />
          <PushButton prominent title={tr("开始")} onClick={() => go(1)} />
        </Footer>
      </>
    );
  } else if (step === 1) {
    const items = [asr, translator];
    const allInstalled = items.every((i) => m.localModels.installed.has(i.id));
    const downloading = items.some((i) => m.localModels.downloads[i.id]);
    const missing = items.filter((i) => !m.localModels.installed.has(i.id)).reduce((n, i) => n + modelBytes(i), 0);
    const begin = () => {
      setStarted(true);
      m.downloadAndUse(asr, "asr");
      m.downloadAndUse(translator, "translator");
    };
    body = (
      <>
        <Title>{tr("下载模型")}</Title>
        <Lead>{pc(tr("Nomi 在这台 Mac 上听写和翻译。两个模型只需下载一次，之后可以离线使用。"))}</Lead>
        {modelCard(tr("语音识别"), tr("把讲课变成文字"), "asr", asr, setAsr)}
        {modelCard(tr("翻译"), tr("翻译每一段，也能离线回答问题"), "translator", translator, setTranslator)}
        <div className="font-caption flex items-center gap-1.5 pt-2 text-[var(--text-2)]">
          <Icon name="lock" size={12} />
          {pc(tr("录音不会离开这台 Mac。模型保存在 ~/.OminiX/models。")).replace("~/.OminiX/models", paths.join(paths.root, "models"))}
        </div>
        <Footer>
          <Back onClick={() => go(0)} />
          <div className="flex-1" />
          {allInstalled ? (
            <PushButton
              prominent
              title={tr("下一步")}
              onClick={() => {
                if (!started) begin();
                go(2);
              }}
            />
          ) : started || downloading ? (
            <PushButton title={tr("下载时继续")} onClick={() => go(2)} />
          ) : (
            <PushButton prominent title={trf("下载两个模型 · %@", formatBytes(missing))} onClick={begin} />
          )}
        </Footer>
      </>
    );
  } else if (step === 2) {
    const def = (k: SpeakerModelKind) => findModel(SpeakerModels.modelID(k))!;
    const ready = m.localModels.installed.has(def(speakerChoice).id);
    const busy = m.localModels.isDownloading(def(speakerChoice).id);
    const setOn = (on: boolean) => prefs.set(SpeakerModels.enabledKey, on);
    body = (
      <>
        <Title>{tr("区分说话人（可选）")}</Title>
        <Lead>{pc(tr("录音时，Nomi 可以在这台 Mac 上分出不同的人，转写里每段话前标出说话人 1、2、3…，还能只看某些人说的话。选一个说话人模型下载，之后可以在设置里更换。"))}</Lead>
        {speakerModelKinds.map((k) => {
          const d = def(k);
          const selected = k === speakerChoice;
          const installed = m.localModels.installed.has(d.id);
          const downloading = m.localModels.isDownloading(d.id);
          return (
            <button
              key={k}
              onClick={() => {
                setSpeakerChoice(k);
                prefs.set(SpeakerModels.choiceKey, k);
              }}
              className="mb-2 flex w-full flex-col gap-1 rounded-[14px] px-4 py-3 text-left"
              style={{ boxShadow: `inset 0 0 0 ${selected ? 1.5 : 1}px ${selected ? "var(--accent)" : "var(--separator)"}` }}
            >
              <span className="flex items-center gap-2">
                <span style={{ color: selected ? "var(--accent)" : "var(--text-2)" }}>
                  <Icon name={selected ? "largecircle.fill.circle" : "circle"} size={16} />
                </span>
                <span className="font-body font-semibold">{SpeakerModels.title(k)}</span>
                {k === "standard" && <Badge>{tr("推荐")}</Badge>}
                <span className="flex-1" />
                {downloading ? <span className="spinner" /> : <span className="font-secondary font-semibold" style={{ color: installed ? "var(--accent-green)" : "var(--text-2)" }}>{installed ? tr("已下载 ✓") : formatBytes(modelBytes(d))}</span>}
              </span>
              <span className="font-secondary pl-[26px] text-[var(--text-2)]">{SpeakerModels.detail(k)}</span>
              {m.localModels.errors[d.id] && <span className="font-caption line-clamp-2 pl-[26px] text-[var(--danger)]">{m.localModels.errors[d.id]}</span>}
            </button>
          );
        })}
        <Footer>
          <Back onClick={() => go(1)} />
          <div className="flex-1" />
          {ready ? (
            <PushButton
              prominent
              title={tr("下一步")}
              onClick={() => {
                setOn(true);
                go(3);
              }}
            />
          ) : busy ? (
            <PushButton
              title={tr("下载时继续")}
              onClick={() => {
                setOn(true);
                go(3);
              }}
            />
          ) : (
            <>
              <PushButton
                title={tr("跳过")}
                onClick={() => {
                  setOn(false);
                  go(3);
                }}
              />
              <PushButton
                prominent
                title={trf("下载 %@ · %@", SpeakerModels.title(speakerChoice), formatBytes(modelBytes(def(speakerChoice))))}
                onClick={() => {
                  setOn(true);
                  m.localModels.download(def(speakerChoice));
                }}
              />
            </>
          )}
        </Footer>
      </>
    );
  } else if (step === 3) {
    body = (
      <>
        <Title>{tr("允许使用麦克风")}</Title>
        <Lead>{pc(tr("Nomi 需要麦克风才能听到课堂。声音只在这台 Mac 上处理。"))}</Lead>
        <div className="flex items-center gap-4 rounded-[14px] bg-[color-mix(in_srgb,var(--surface-inset)_50%,transparent)] p-4">
          <span className="flex h-[54px] w-[54px] items-center justify-center rounded-full bg-[var(--accent-soft)] text-[var(--accent)]">
            <Icon name="mic.fill" size={22} />
          </span>
          <span className="flex flex-1 flex-col gap-0.5">
            <span className="font-body font-semibold">{tr("麦克风")}</span>
            <span className="font-secondary text-[var(--text-2)]">{tr("在 Windows 设置 › 隐私和安全性 › 麦克风 中，允许桌面应用访问麦克风。")}</span>
          </span>
          <span className="font-secondary font-semibold" style={{ color: mic === "granted" ? "var(--accent-green)" : mic === "denied" ? "var(--danger)" : "var(--text-2)" }}>{mic === "granted" ? tr("已允许 ✓") : mic === "denied" ? tr("已拒绝") : tr("还没允许")}</span>
        </div>
        <Footer>
          <Back onClick={() => go(2)} />
          <div className="flex-1" />
          {mic === "granted" ? (
            <PushButton prominent title={tr("下一步")} onClick={() => go(4)} />
          ) : (
            <>
              <PushButton title={tr("跳过")} onClick={() => go(4)} />
              <PushButton
                prominent
                title={tr("打开系统设置")}
                onClick={() => {
                  void shell.openURL("ms-settings:privacy-microphone");
                  window.addEventListener("focus", checkMic, { once: true });
                }}
              />
            </>
          )}
        </Footer>
      </>
    );
  } else if (step === 4) {
    const bound = m.llmConfiguration.activeProfile;
    body = (
      <>
        <Title>{tr("绑定大模型 API（推荐）")}</Title>
        <Lead>{tr("Nomi 自带的本地模型可以离线回答问题，但模型较小。绑定你自己的 API 后，提问、摘要和图示都会好很多。")}</Lead>
        {bound ? (
          <div className="flex items-center gap-3 rounded-[14px] bg-[color-mix(in_srgb,var(--surface-inset)_50%,transparent)] p-4">
            <ProviderLogo file={logoFile(bound.providerID)} side={22} />
            <span className="flex min-w-0 flex-1 flex-col gap-0.5">
              <span className="font-body font-semibold">{bound.name}</span>
              <span className="font-secondary truncate text-[var(--text-2)]">{bound.modelID}</span>
            </span>
            <span className="font-secondary font-semibold text-[var(--accent-green)]">{tr("已绑定 ✓")}</span>
          </div>
        ) : (
          <>
            <div className="grid grid-cols-3 gap-2">
              {quickProviders.map((id) => {
                const p = providerPresets.find((x) => x.id === id)!;
                return (
                  <button key={id} onClick={() => setBinding(newProfile({ providerID: p.id, name: tr(p.name), baseURL: p.baseURL, format: p.format }))} className="press flex h-11 items-center gap-2 rounded-[12px] px-3 text-left shadow-[inset_0_0_0_1px_var(--separator)]">
                    <ProviderLogo file={logoFile(p.id)} side={18} />
                    <span className="font-secondary truncate font-medium">{id === "custom" ? tr("其他服务") : tr(p.name)}</span>
                  </button>
                );
              })}
            </div>
            <div className="font-caption pt-3 text-[var(--text-2)]">{tr("需要你自己的 API 密钥，费用由服务商收取。")}</div>
          </>
        )}
        <div className="font-caption flex items-start gap-1.5 pt-2 text-[var(--text-2)]">
          <Icon name="lock" size={12} />
          {pc(tr("录音和转写都留在这台 Mac 上。提问时，只有相关的文字会发送给你选择的服务。密钥只保存在这台 Mac 上。"))}
        </div>
        {!bound && <div className="font-caption pt-1.5 text-[var(--text-2)]">{tr("跳过也能用：Nomi 会用本地模型回答。之后可以在 设置 › API 里绑定。")}</div>}
        <Footer>
          <Back onClick={() => go(3)} />
          <div className="flex-1" />
          {bound ? <PushButton prominent title={tr("下一步")} onClick={() => go(5)} /> : <PushButton title={tr("跳过")} onClick={() => go(5)} />}
        </Footer>
      </>
    );
  } else {
    const chosen = asr;
    const waiting = !m.localModels.installed.has(chosen.id);
    const progress = m.localModels.downloads[chosen.id];
    body = (
      <div className="flex flex-col items-center text-center">
        <span className="flex h-16 w-16 items-center justify-center rounded-full bg-[color-mix(in_srgb,var(--accent-green)_14%,transparent)] text-[var(--accent-green)]">
          <Icon name="checkmark" size={28} weight={3} />
        </span>
        <div className="pt-3 text-[22px] font-bold">{tr("准备好了")}</div>
        <div className="font-body pt-1 text-[var(--text-2)]">{tr("上课时点右上角的「开始转录」，在那里选择课堂语言和翻译语言。")}</div>
        {waiting && (
          <>
            <div className="font-secondary mt-4 flex w-full items-center gap-2 rounded-[12px] bg-[var(--accent-soft)] p-3 text-left text-[var(--accent)]">
              <span className="spinner" />
              {progress ? trf("正在下载语音识别模型 · %d%%", Math.round(fraction(chosen.id) * 100)) : tr("语音识别模型还没下载。")}
            </div>
            <div className="font-caption pt-1.5 text-[var(--text-2)]">{tr("模型下载好后就能开始录音，在这之前可以先看看 Nomi。")}</div>
          </>
        )}
        <div className="flex w-full items-center gap-2 pt-6">
          <Back onClick={() => go(4)} />
          <div className="flex-1" />
          <PushButton title={tr("快速导览")} onClick={() => m.finishOnboarding(true)} />
          <PushButton prominent title={tr("开始使用 Nomi")} onClick={() => m.finishOnboarding(false)} />
        </div>
      </div>
    );
  }

  return (
    <Sheet width={600}>
      <div className="flex flex-col px-10 pt-8 pb-[26px]">
        <div className="flex justify-center gap-1.5 pb-6">
          {Array.from({ length: steps }, (_, i) => (
            <span key={i} className="h-[7px] rounded-full transition-all duration-300" style={{ width: i === step ? 22 : 7, background: i === step ? "var(--accent)" : "var(--separator)" }} />
          ))}
        </div>
        <div key={step} className="slide-from-right flex flex-col" onKeyDown={(e) => e.key === "Enter" && (e.target as HTMLElement).tagName !== "INPUT" && (document.querySelector(".slide-from-right button[style*='--accent']") as HTMLButtonElement | null)?.click()}>
          {body}
        </div>
      </div>
      {binding && (
        <APIProfileEditor
          profile={binding}
          onClose={() => {
            m.useProfileFromOnboarding(binding.id);
            setBinding(null);
          }}
        />
      )}
    </Sheet>
  );
}

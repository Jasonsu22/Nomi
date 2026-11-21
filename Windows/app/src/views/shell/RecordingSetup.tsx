// Meetings/RecordingSetupView.swift: title, category, input, languages, then record.
import { useState } from "react";
import { tr } from "../../i18n";
import { languageName } from "../../support/format";
import { LectureLanguages } from "../../support/languages";
import { useModel } from "../../app";
import { AudioInputs } from "../../engine/audioInputs";
import { PopUp, PushButton, Sheet } from "../ui/controls";

export function RecordingSetupView() {
  const m = useModel();
  const resume = m.recordingSetupMeeting;
  const [title, setTitle] = useState(resume?.title ?? tr("未命名会议"));
  const [categoryID, setCategoryID] = useState<string>(resume?.categoryID ?? "");
  const inputs = m.audioInputs;
  const row = (label: string, control: React.ReactNode) => (
    <div className="flex items-center gap-3 px-4 py-3">
      <span className="font-body">{label}</span>
      <div className="flex-1" />
      <div className="font-secondary">{control}</div>
    </div>
  );
  const divider = <div className="mx-4 h-px bg-[var(--separator)]" />;
  const inputOptions = [{ value: AudioInputs.systemDefault, title: tr("系统默认") }, ...inputs.devices.map((d) => ({ value: d.id, title: d.name }))];
  if (inputs.selectedUID !== AudioInputs.systemDefault && !inputs.selectedDevice) inputOptions.push({ value: inputs.selectedUID, title: tr("设备已断开") });
  return (
    <Sheet width={440} onClose={() => m.cancelRecordingSetup()}>
      <div className="flex flex-col gap-6 bg-[var(--canvas)] p-6">
        <div className="font-detail-title">{m.recordingResumeID ? tr("继续录制") : tr("录制会议")}</div>
        <div className="surface overflow-hidden">
          {row(tr("会议标题"), <input autoFocus value={title} onChange={(e) => setTitle(e.target.value)} onKeyDown={(e) => e.key === "Enter" && m.canRecord && m.startTranscription(title, categoryID || null)} placeholder={tr("未命名会议")} className="w-[240px] rounded-[8px] bg-[var(--surface-inset)] px-2.5 py-1.5 outline-none" />)}
          {divider}
          {row(tr("分类"), <PopUp value={categoryID} onChange={setCategoryID} options={[{ value: "", title: tr("未分类") }, ...m.categories.map((c) => ({ value: c.id, title: c.name }))]} />)}
          {divider}
          {row(tr("输入源"), <PopUp value={inputs.selectedUID} onChange={(v) => (inputs.selectedUID = v)} options={inputOptions} />)}
          {divider}
          {row(tr("输入语言"), <PopUp value={m.recordingSourceLanguage} onChange={(v) => (m.recordingSourceLanguage = v)} options={["auto", ...LectureLanguages.supported].map((c) => ({ value: c, title: languageName(c) }))} />)}
          {divider}
          {row(tr("目标翻译语言"), <PopUp value={m.recordingTargetLanguage} onChange={(v) => (m.recordingTargetLanguage = v)} options={[{ value: "none", title: tr("不翻译") }, ...LectureLanguages.supported.map((c) => ({ value: c, title: languageName(c) }))]} />)}
        </div>
        {!inputs.devices.length && <div className="font-secondary text-[var(--danger)]">{tr("请选择可用的音频输入设备。")}</div>}
        <div className="flex items-center">
          <PushButton title={tr("取消")} onClick={() => m.cancelRecordingSetup()} />
          <div className="flex-1" />
          <PushButton prominent title={m.recordingResumeID ? tr("继续录制") : tr("开始录制")} disabled={!m.canRecord} onClick={() => m.startTranscription(title, categoryID || null)} />
        </div>
      </div>
    </Sheet>
  );
}

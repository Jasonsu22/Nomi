// Meetings: the list on the left, the chosen meeting on the right with its audio, its speakers
// (rename, "This is me", Speaker 1, hide) and its transcript. Speakers work as in Mac 0.10.
import { convertFileSrc } from "@tauri-apps/api/core";
import { Check, Eye, EyeOff, Pencil, Search, Trash2, User, Users } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { SpeakerChip, Transcript } from "../components/Transcript";
import { Button, Card, Scroll } from "../components/ui";
import { api, type Meeting } from "../lib/api";
import { clock, fromReference, voiceLabel } from "../lib/format";
import { useT } from "../lib/i18n";
import { useApp } from "../store";

function dayLabel(date: Date, t: (k: string) => string, lang: string) {
  const today = new Date();
  const yesterday = new Date(Date.now() - 86_400_000);
  if (date.toDateString() === today.toDateString()) return t("今天");
  if (date.toDateString() === yesterday.toDateString()) return t("昨天");
  return date.toLocaleDateString(lang === "zh" ? "zh-CN" : "en-GB", { month: "short", day: "numeric", weekday: "short" });
}

function MeetingList({ selected, onSelect }: { selected: string | null; onSelect: (id: string) => void }) {
  const t = useT();
  const lang = useApp((s) => s.lang);
  const meetings = useApp((s) => s.meetings);
  const [query, setQuery] = useState("");
  const shown = meetings.filter((m) => !query || (m.title + m.preview).toLowerCase().includes(query.toLowerCase()));
  return (
    <Card className="m-2 mr-0 flex w-[300px] shrink-0 flex-col overflow-hidden">
      <div className="p-3">
        <div className="glass flex h-9 items-center gap-2 rounded-[12px] px-3">
          <Search size={15} className="text-[var(--text-2)]" />
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder={t("搜索会议")} className="min-w-0 flex-1 bg-transparent text-sm outline-none" />
        </div>
      </div>
      <Scroll className="flex-1 px-2 pb-2">
        {shown.length === 0 && (
          <div className="px-4 py-12 text-center text-[13px] text-[var(--text-2)]">
            <div className="mb-1 font-medium text-[var(--text)]">{t("还没有会议")}</div>
            {t("录一节课，它会出现在这里。")}
          </div>
        )}
        {shown.map((m) => {
          const date = fromReference(m.startedAt);
          const active = m.id === selected;
          return (
            <button
              key={m.id}
              onClick={() => onSelect(m.id)}
              className={`press relative mb-1 w-full rounded-[14px] px-3 py-2.5 text-left transition-colors duration-[var(--t-tap)] ${
                active ? "bg-[var(--selection)] text-[var(--on-selection)]" : "hover:bg-[color-mix(in_srgb,var(--text)_6%,transparent)]"
              }`}
            >
              <div className="flex items-center gap-2">
                <div className="min-w-0 flex-1 truncate text-[14px] font-semibold">{m.title}</div>
                {m.isLive && <span className="h-2 w-2 rounded-full bg-[#e5484d]" />}
              </div>
              <div className={`mt-0.5 flex gap-2 text-[12px] ${active ? "opacity-80" : "text-[var(--text-2)]"}`}>
                <span>{dayLabel(date, t, lang)} {date.toLocaleTimeString(lang === "zh" ? "zh-CN" : "en-GB", { hour: "2-digit", minute: "2-digit" })}</span>
                <span>·</span>
                <span className="tabular-nums">{clock(m.duration)}</span>
                {m.speakers > 1 && (
                  <>
                    <span>·</span>
                    <span className="inline-flex items-center gap-1"><Users size={12} />{m.speakers}</span>
                  </>
                )}
              </div>
              {m.preview && <div className={`mt-1 line-clamp-2 text-[12.5px] ${active ? "opacity-75" : "text-[var(--text-2)]"}`}>{m.preview}</div>}
            </button>
          );
        })}
      </Scroll>
    </Card>
  );
}

/** One voice: rename it, hide it, mark it as you, or make it Speaker 1. */
function SpeakerMenu({ meeting, speaker, onChange, onClose }: { meeting: Meeting; speaker: string; onChange: (m: Meeting) => void; onClose: () => void }) {
  const t = useT();
  const name = meeting.speakerNames[speaker];
  const [editing, setEditing] = useState(name?.kind === "named" ? name.name : "");
  const hidden = meeting.hiddenSpeakers ?? [];
  const isHidden = hidden.includes(speaker);
  const isMe = meeting.voices?.me === speaker;
  const act = async (call: Promise<Meeting>) => {
    onChange(await call);
    onClose();
  };
  return (
    <div className="glass-strong enter absolute top-full left-0 z-30 mt-2 w-64 space-y-1 rounded-[14px] p-2">
      <div className="flex items-center gap-2 p-1">
        <input
          autoFocus
          value={editing}
          onChange={(e) => setEditing(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && void act(api.renameSpeaker(meeting.id, speaker, editing))}
          placeholder={t("给说话人起名")}
          className="glass h-8 min-w-0 flex-1 rounded-[9px] px-2.5 text-[13px] outline-none"
        />
        <Button size="sm" tone="primary" onClick={() => void act(api.renameSpeaker(meeting.id, speaker, editing))}>
          <Check size={14} />
        </Button>
      </div>
      <Button tone="quiet" size="sm" className="w-full justify-start" onClick={() => void act(api.setMe(meeting.id, isMe ? null : speaker))}>
        <User size={14} />
        {isMe ? t("这不是我") : t("这是我")}
      </Button>
      {meeting.voices?.teacher !== speaker && (
        <Button tone="quiet" size="sm" className="w-full justify-start" onClick={() => void act(api.setTeacher(meeting.id, speaker))}>
          <Users size={14} />
          {t("设为说话人1")}
        </Button>
      )}
      <Button
        tone="quiet"
        size="sm"
        className="w-full justify-start"
        onClick={() => void act(api.setHiddenSpeakers(meeting.id, isHidden ? hidden.filter((s) => s !== speaker) : [...hidden, speaker]))}
      >
        {isHidden ? <Eye size={14} /> : <EyeOff size={14} />}
        {isHidden ? t("显示") : t("隐藏")}
      </Button>
    </div>
  );
}

function MeetingDetail({ id }: { id: string }) {
  const t = useT();
  const lang = useApp((s) => s.lang);
  const refreshMeetings = useApp((s) => s.refreshMeetings);
  const [meeting, setMeeting] = useState<Meeting | null>(null);
  const [renaming, setRenaming] = useState(false);
  const [title, setTitle] = useState("");
  const [menu, setMenu] = useState<string | null>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);

  useEffect(() => {
    setMeeting(null);
    setMenu(null);
    setConfirmDelete(false);
    void api.getMeeting(id).then((m) => {
      setMeeting(m);
      setTitle(m.title);
    });
  }, [id]);

  const speakers = useMemo(() => {
    if (!meeting?.voices) return [];
    return Object.keys(meeting.voices.seconds).sort((a, b) => {
      const na = meeting.speakerNames[a];
      const nb = meeting.speakerNames[b];
      const rank = (n: typeof na) => (n?.kind === "number" ? n.number : n?.kind === "me" ? 0.5 : 99);
      return rank(na) - rank(nb);
    });
  }, [meeting]);

  if (!meeting) return <div className="flex-1" />;
  const update = (m: Meeting) => {
    setMeeting(m);
    void refreshMeetings();
  };
  const date = fromReference(meeting.startedAt);
  const hidden = meeting.hiddenSpeakers ?? [];

  return (
    <div key={id} className="enter flex min-w-0 flex-1 flex-col">
      <Card className="m-2 mb-0 space-y-3 px-5 py-4">
        <div className="flex items-start gap-3">
          <div className="min-w-0 flex-1">
            {renaming ? (
              <input
                autoFocus
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                onBlur={() => {
                  setRenaming(false);
                  if (title.trim() && title !== meeting.title) void api.renameMeeting(meeting.id, title).then(update);
                }}
                onKeyDown={(e) => e.key === "Enter" && (e.target as HTMLInputElement).blur()}
                className="glass h-9 w-full rounded-[10px] px-2.5 text-[19px] font-semibold outline-none"
              />
            ) : (
              <button className="group flex max-w-full items-center gap-2 text-left" onClick={() => setRenaming(true)}>
                <h1 className="truncate text-[20px] font-semibold">{meeting.title}</h1>
                <Pencil size={14} className="shrink-0 opacity-0 transition-opacity group-hover:opacity-60" />
              </button>
            )}
            <div className="mt-0.5 text-[12.5px] text-[var(--text-2)]">
              {date.toLocaleString(lang === "zh" ? "zh-CN" : "en-GB", { dateStyle: "medium", timeStyle: "short" })} · {clock(meeting.duration)}
              {meeting.inputDeviceName && ` · ${meeting.inputDeviceName}`}
            </div>
          </div>
          {confirmDelete ? (
            <div className="enter flex items-center gap-2">
              <span className="max-w-[220px] text-[12px] text-[var(--text-2)]">{t("删除这个会议？录音和文字都会删掉。")}</span>
              <Button size="sm" onClick={() => setConfirmDelete(false)}>{t("取消")}</Button>
              <Button
                size="sm"
                tone="danger"
                onClick={() => void api.deleteMeeting(meeting.id).then(() => {
                  useApp.setState({ openMeeting: null });
                  void refreshMeetings();
                })}
              >
                {t("删除")}
              </Button>
            </div>
          ) : (
            <Button size="sm" tone="quiet" onClick={() => setConfirmDelete(true)} aria-label={t("删除")}>
              <Trash2 size={15} />
            </Button>
          )}
        </div>
        {meeting.audioPath && <audio controls preload="metadata" src={convertFileSrc(meeting.audioPath)} className="h-9 w-full" />}
        {speakers.length > 0 && (
          <div className="flex flex-wrap items-center gap-1.5">
            <span className="mr-1 text-[12px] font-medium text-[var(--text-2)]">{t("说话人")}</span>
            {speakers.map((speaker) => (
              <div key={speaker} className="relative">
                <button
                  onClick={() => setMenu(menu === speaker ? null : speaker)}
                  className={`press rounded-full transition-opacity ${hidden.includes(speaker) ? "opacity-40" : ""}`}
                  title={voiceLabel(meeting.speakerNames[speaker], t)}
                >
                  <SpeakerChip name={meeting.speakerNames[speaker]} speaker={speaker} />
                </button>
                {menu === speaker && <SpeakerMenu meeting={meeting} speaker={speaker} onChange={update} onClose={() => setMenu(null)} />}
              </div>
            ))}
          </div>
        )}
      </Card>
      <Card className="m-2 flex min-h-0 flex-1 flex-col overflow-hidden">
        <Transcript
          paragraphs={meeting.paragraphs}
          sourceLanguage={meeting.sourceLanguage}
          targetLanguage={meeting.targetLanguage}
          names={meeting.speakerNames}
          hidden={hidden}
          onSpeaker={(speaker) => setMenu(speaker)}
        />
      </Card>
    </div>
  );
}

export function MeetingsPage() {
  const openMeeting = useApp((s) => s.openMeeting);
  const meetings = useApp((s) => s.meetings);
  const refreshMeetings = useApp((s) => s.refreshMeetings);
  const selected = openMeeting ?? meetings[0]?.id ?? null;
  useEffect(() => {
    void refreshMeetings();
  }, [refreshMeetings]);
  return (
    <div className="flex min-h-0 flex-1">
      <MeetingList selected={selected} onSelect={(id) => useApp.setState({ openMeeting: id })} />
      {selected ? <MeetingDetail id={selected} /> : <div className="flex-1" />}
    </div>
  );
}

import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
// Meetings: the list on the left, the chosen meeting on the right with its audio, its speakers
// (rename, "This is me", Speaker 1, hide) and its transcript. Speakers work as in Mac 0.10.
import { convertFileSrc } from "@tauri-apps/api/core";
import { Check, Eye, EyeOff, Pencil, Search, Trash2, User, Users } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { SpeakerChip, Transcript } from "../components/Transcript";
import { Button, Card, Scroll } from "../components/ui";
import { api } from "../lib/api";
import { clock, fromReference, voiceLabel } from "../lib/format";
import { useT } from "../lib/i18n";
import { useApp } from "../store";
function dayLabel(date, t, lang) {
    const today = new Date();
    const yesterday = new Date(Date.now() - 86_400_000);
    if (date.toDateString() === today.toDateString())
        return t("今天");
    if (date.toDateString() === yesterday.toDateString())
        return t("昨天");
    return date.toLocaleDateString(lang === "zh" ? "zh-CN" : "en-GB", { month: "short", day: "numeric", weekday: "short" });
}
function MeetingList({ selected, onSelect }) {
    const t = useT();
    const lang = useApp((s) => s.lang);
    const meetings = useApp((s) => s.meetings);
    const [query, setQuery] = useState("");
    const shown = meetings.filter((m) => !query || (m.title + m.preview).toLowerCase().includes(query.toLowerCase()));
    return (_jsxs(Card, { className: "m-2 mr-0 flex w-[300px] shrink-0 flex-col overflow-hidden", children: [_jsx("div", { className: "p-3", children: _jsxs("div", { className: "glass flex h-9 items-center gap-2 rounded-[12px] px-3", children: [_jsx(Search, { size: 15, className: "text-[var(--text-2)]" }), _jsx("input", { value: query, onChange: (e) => setQuery(e.target.value), placeholder: t("搜索会议"), className: "min-w-0 flex-1 bg-transparent text-sm outline-none" })] }) }), _jsxs(Scroll, { className: "flex-1 px-2 pb-2", children: [shown.length === 0 && (_jsxs("div", { className: "px-4 py-12 text-center text-[13px] text-[var(--text-2)]", children: [_jsx("div", { className: "mb-1 font-medium text-[var(--text)]", children: t("还没有会议") }), t("录一节课，它会出现在这里。")] })), shown.map((m) => {
                        const date = fromReference(m.startedAt);
                        const active = m.id === selected;
                        return (_jsxs("button", { onClick: () => onSelect(m.id), className: `press relative mb-1 w-full rounded-[14px] px-3 py-2.5 text-left transition-colors duration-[var(--t-tap)] ${active ? "bg-[var(--selection)] text-[var(--on-selection)]" : "hover:bg-[color-mix(in_srgb,var(--text)_6%,transparent)]"}`, children: [_jsxs("div", { className: "flex items-center gap-2", children: [_jsx("div", { className: "min-w-0 flex-1 truncate text-[14px] font-semibold", children: m.title }), m.isLive && _jsx("span", { className: "h-2 w-2 rounded-full bg-[#e5484d]" })] }), _jsxs("div", { className: `mt-0.5 flex gap-2 text-[12px] ${active ? "opacity-80" : "text-[var(--text-2)]"}`, children: [_jsxs("span", { children: [dayLabel(date, t, lang), " ", date.toLocaleTimeString(lang === "zh" ? "zh-CN" : "en-GB", { hour: "2-digit", minute: "2-digit" })] }), _jsx("span", { children: "\u00B7" }), _jsx("span", { className: "tabular-nums", children: clock(m.duration) }), m.speakers > 1 && (_jsxs(_Fragment, { children: [_jsx("span", { children: "\u00B7" }), _jsxs("span", { className: "inline-flex items-center gap-1", children: [_jsx(Users, { size: 12 }), m.speakers] })] }))] }), m.preview && _jsx("div", { className: `mt-1 line-clamp-2 text-[12.5px] ${active ? "opacity-75" : "text-[var(--text-2)]"}`, children: m.preview })] }, m.id));
                    })] })] }));
}
/** One voice: rename it, hide it, mark it as you, or make it Speaker 1. */
function SpeakerMenu({ meeting, speaker, onChange, onClose }) {
    const t = useT();
    const name = meeting.speakerNames[speaker];
    const [editing, setEditing] = useState(name?.kind === "named" ? name.name : "");
    const hidden = meeting.hiddenSpeakers ?? [];
    const isHidden = hidden.includes(speaker);
    const isMe = meeting.voices?.me === speaker;
    const act = async (call) => {
        onChange(await call);
        onClose();
    };
    return (_jsxs("div", { className: "glass-strong enter absolute top-full left-0 z-30 mt-2 w-64 space-y-1 rounded-[14px] p-2", children: [_jsxs("div", { className: "flex items-center gap-2 p-1", children: [_jsx("input", { autoFocus: true, value: editing, onChange: (e) => setEditing(e.target.value), onKeyDown: (e) => e.key === "Enter" && void act(api.renameSpeaker(meeting.id, speaker, editing)), placeholder: t("给说话人起名"), className: "glass h-8 min-w-0 flex-1 rounded-[9px] px-2.5 text-[13px] outline-none" }), _jsx(Button, { size: "sm", tone: "primary", onClick: () => void act(api.renameSpeaker(meeting.id, speaker, editing)), children: _jsx(Check, { size: 14 }) })] }), _jsxs(Button, { tone: "quiet", size: "sm", className: "w-full justify-start", onClick: () => void act(api.setMe(meeting.id, isMe ? null : speaker)), children: [_jsx(User, { size: 14 }), isMe ? t("这不是我") : t("这是我")] }), meeting.voices?.teacher !== speaker && (_jsxs(Button, { tone: "quiet", size: "sm", className: "w-full justify-start", onClick: () => void act(api.setTeacher(meeting.id, speaker)), children: [_jsx(Users, { size: 14 }), t("设为说话人1")] })), _jsxs(Button, { tone: "quiet", size: "sm", className: "w-full justify-start", onClick: () => void act(api.setHiddenSpeakers(meeting.id, isHidden ? hidden.filter((s) => s !== speaker) : [...hidden, speaker])), children: [isHidden ? _jsx(Eye, { size: 14 }) : _jsx(EyeOff, { size: 14 }), isHidden ? t("显示") : t("隐藏")] })] }));
}
function MeetingDetail({ id }) {
    const t = useT();
    const lang = useApp((s) => s.lang);
    const refreshMeetings = useApp((s) => s.refreshMeetings);
    const [meeting, setMeeting] = useState(null);
    const [renaming, setRenaming] = useState(false);
    const [title, setTitle] = useState("");
    const [menu, setMenu] = useState(null);
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
        if (!meeting?.voices)
            return [];
        return Object.keys(meeting.voices.seconds).sort((a, b) => {
            const na = meeting.speakerNames[a];
            const nb = meeting.speakerNames[b];
            const rank = (n) => (n?.kind === "number" ? n.number : n?.kind === "me" ? 0.5 : 99);
            return rank(na) - rank(nb);
        });
    }, [meeting]);
    if (!meeting)
        return _jsx("div", { className: "flex-1" });
    const update = (m) => {
        setMeeting(m);
        void refreshMeetings();
    };
    const date = fromReference(meeting.startedAt);
    const hidden = meeting.hiddenSpeakers ?? [];
    return (_jsxs("div", { className: "enter flex min-w-0 flex-1 flex-col", children: [_jsxs(Card, { className: "m-2 mb-0 space-y-3 px-5 py-4", children: [_jsxs("div", { className: "flex items-start gap-3", children: [_jsxs("div", { className: "min-w-0 flex-1", children: [renaming ? (_jsx("input", { autoFocus: true, value: title, onChange: (e) => setTitle(e.target.value), onBlur: () => {
                                            setRenaming(false);
                                            if (title.trim() && title !== meeting.title)
                                                void api.renameMeeting(meeting.id, title).then(update);
                                        }, onKeyDown: (e) => e.key === "Enter" && e.target.blur(), className: "glass h-9 w-full rounded-[10px] px-2.5 text-[19px] font-semibold outline-none" })) : (_jsxs("button", { className: "group flex max-w-full items-center gap-2 text-left", onClick: () => setRenaming(true), children: [_jsx("h1", { className: "truncate text-[20px] font-semibold", children: meeting.title }), _jsx(Pencil, { size: 14, className: "shrink-0 opacity-0 transition-opacity group-hover:opacity-60" })] })), _jsxs("div", { className: "mt-0.5 text-[12.5px] text-[var(--text-2)]", children: [date.toLocaleString(lang === "zh" ? "zh-CN" : "en-GB", { dateStyle: "medium", timeStyle: "short" }), " \u00B7 ", clock(meeting.duration), meeting.inputDeviceName && ` · ${meeting.inputDeviceName}`] })] }), confirmDelete ? (_jsxs("div", { className: "enter flex items-center gap-2", children: [_jsx("span", { className: "max-w-[220px] text-[12px] text-[var(--text-2)]", children: t("删除这个会议？录音和文字都会删掉。") }), _jsx(Button, { size: "sm", onClick: () => setConfirmDelete(false), children: t("取消") }), _jsx(Button, { size: "sm", tone: "danger", onClick: () => void api.deleteMeeting(meeting.id).then(() => {
                                            useApp.setState({ openMeeting: null });
                                            void refreshMeetings();
                                        }), children: t("删除") })] })) : (_jsx(Button, { size: "sm", tone: "quiet", onClick: () => setConfirmDelete(true), "aria-label": t("删除"), children: _jsx(Trash2, { size: 15 }) }))] }), meeting.audioPath && _jsx("audio", { controls: true, preload: "metadata", src: convertFileSrc(meeting.audioPath), className: "h-9 w-full" }), speakers.length > 0 && (_jsxs("div", { className: "flex flex-wrap items-center gap-1.5", children: [_jsx("span", { className: "mr-1 text-[12px] font-medium text-[var(--text-2)]", children: t("说话人") }), speakers.map((speaker) => (_jsxs("div", { className: "relative", children: [_jsx("button", { onClick: () => setMenu(menu === speaker ? null : speaker), className: `press rounded-full transition-opacity ${hidden.includes(speaker) ? "opacity-40" : ""}`, title: voiceLabel(meeting.speakerNames[speaker], t), children: _jsx(SpeakerChip, { name: meeting.speakerNames[speaker], speaker: speaker }) }), menu === speaker && _jsx(SpeakerMenu, { meeting: meeting, speaker: speaker, onChange: update, onClose: () => setMenu(null) })] }, speaker)))] }))] }), _jsx(Card, { className: "m-2 flex min-h-0 flex-1 flex-col overflow-hidden", children: _jsx(Transcript, { paragraphs: meeting.paragraphs, sourceLanguage: meeting.sourceLanguage, targetLanguage: meeting.targetLanguage, names: meeting.speakerNames, hidden: hidden, onSpeaker: (speaker) => setMenu(speaker) }) })] }, id));
}
export function MeetingsPage() {
    const openMeeting = useApp((s) => s.openMeeting);
    const meetings = useApp((s) => s.meetings);
    const refreshMeetings = useApp((s) => s.refreshMeetings);
    const selected = openMeeting ?? meetings[0]?.id ?? null;
    useEffect(() => {
        void refreshMeetings();
    }, [refreshMeetings]);
    return (_jsxs("div", { className: "flex min-h-0 flex-1", children: [_jsx(MeetingList, { selected: selected, onSelect: (id) => useApp.setState({ openMeeting: id }) }), selected ? _jsx(MeetingDetail, { id: selected }) : _jsx("div", { className: "flex-1" })] }));
}

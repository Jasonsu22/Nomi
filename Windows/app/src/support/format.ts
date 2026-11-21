// Support/Format.swift
import { isEnglish, locale, tr, trf } from "../i18n";

export function formatClock(seconds: number): string {
  const total = Math.max(0, Math.floor(seconds));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const two = (n: number) => String(n).padStart(2, "0");
  return h > 0 ? `${h}:${two(m)}:${two(s)}` : `${m}:${two(s)}`;
}

export function formatDuration(seconds: number): string {
  const total = Math.max(0, Math.round(seconds));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  if (h > 0) return trf("%d 小时 %d 分", h, m);
  if (m > 0) return trf("%d 分钟", m);
  return trf("%d 秒", total);
}

export function languageName(code: string): string {
  const names: Record<string, string> = {
    auto: "自动检测", zh: "中文", en: "英文", ja: "日文", ko: "韩文", de: "德文", fr: "法文", es: "西班牙文", ru: "俄文", ar: "阿拉伯文", none: "不翻译",
  };
  return tr(names[code] ?? code);
}

export function formatClockTime(date: Date): string {
  const two = (n: number) => String(n).padStart(2, "0");
  return `${two(date.getHours())}:${two(date.getMinutes())}`;
}

export function formatMonthDay(date: Date): string {
  if (!isEnglish()) return `${date.getMonth() + 1}月${date.getDate()}日`;
  return date.toLocaleDateString("en", { month: "short", day: "numeric" });
}

export function formatWeekday(date: Date): string {
  return date.toLocaleDateString(locale(), { weekday: "short" });
}

export function formatStartStamp(date: Date): string {
  return `${formatMonthDay(date)} ${formatWeekday(date)} ${formatClockTime(date)}`;
}

function sameDay(a: Date, b: Date) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

export function formatMeetingTime(date: Date, now = new Date()): string {
  const time = formatClockTime(date);
  if (sameDay(date, now)) return trf("今天 %@", time);
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (sameDay(date, yesterday)) return trf("昨天 %@", time);
  return `${formatMonthDay(date)} ${time}`;
}

export function formatRelativeTime(date: Date, now = new Date()): string {
  const diff = (date.getTime() - now.getTime()) / 1000;
  if (Math.abs(diff) < 45) return tr("刚刚");
  const rtf = new Intl.RelativeTimeFormat(locale(), { numeric: "always", style: "long" });
  const abs = Math.abs(diff);
  if (abs < 3600) return rtf.format(Math.round(diff / 60), "minute");
  if (abs < 86400) return rtf.format(Math.round(diff / 3600), "hour");
  if (abs < 86400 * 30) return rtf.format(Math.round(diff / 86400), "day");
  if (abs < 86400 * 365) return rtf.format(Math.round(diff / (86400 * 30)), "month");
  return rtf.format(Math.round(diff / (86400 * 365)), "year");
}

export function formatTimeRange(start: Date, duration: number, liveElapsed?: number): string {
  const startText = formatClockTime(start);
  if (liveElapsed !== undefined) return `${startText} · ${formatClock(liveElapsed)}`;
  return `${startText}–${formatClockTime(new Date(start.getTime() + duration * 1000))}`;
}

export function formatBytes(n: number): string {
  if (n >= 1e9) return `${(n / 1e9).toFixed(1)} GB`;
  if (n >= 1e6) return `${Math.round(n / 1e6)} MB`;
  if (n >= 1e3) return `${Math.round(n / 1e3)} KB`;
  return `${n} B`;
}

/** Swift's JSONEncoder writes Date as seconds since 2001-01-01. */
export const referenceOffset = 978_307_200;
export const toDate = (reference: number) => new Date((reference + referenceOffset) * 1000);
export const toReference = (date: Date = new Date()) => date.getTime() / 1000 - referenceOffset;
export const nowReference = () => toReference(new Date());
export const newID = () => crypto.randomUUID().toUpperCase();

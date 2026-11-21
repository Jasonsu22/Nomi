// Categories/Category.swift (data and rules; the views live in views/categories)
import { prefs } from "../support/prefs";

export type MeetingCategory = { id: string; name: string; colorIndex: number; symbol: string; sortOrder: number };

/** Moves `id` into the slot `targetID` occupies; sortOrder becomes 0, 1, 2… in the new order. */
export function placing(categories: MeetingCategory[], id: string, targetID: string): MeetingCategory[] | null {
  const ordered = [...categories].sort((a, b) => a.sortOrder - b.sortOrder);
  const from = ordered.findIndex((c) => c.id === id);
  const to = ordered.findIndex((c) => c.id === targetID);
  if (from < 0 || to < 0 || from === to) return null;
  const [moving] = ordered.splice(from, 1);
  ordered.splice(to, 0, moving);
  return ordered.map((c, i) => ({ ...c, sortOrder: i }));
}

export type CategoryFilter = { kind: "all" } | { kind: "uncategorized" } | { kind: "category"; id: string };

const filterKey = "lecturenote.categoryFilter";

export const CategoryFilterStore = {
  save(filter: CategoryFilter) {
    prefs.set(filterKey, filter.kind === "all" ? "all" : filter.kind === "uncategorized" ? "none" : filter.id);
  },
  load(): CategoryFilter {
    const raw = prefs.string(filterKey);
    if (raw === "none") return { kind: "uncategorized" };
    if (raw && raw !== "all") return { kind: "category", id: raw };
    return { kind: "all" };
  },
};

export const sameFilter = (a: CategoryFilter, b: CategoryFilter) =>
  a.kind === b.kind && (a.kind !== "category" || a.id === (b as { id: string }).id);

export type MeetingGrouping = "time" | "category";
const groupingKey = "lecturenote.grouping";
export const MeetingGroupingStore = {
  save: (g: MeetingGrouping) => prefs.set(groupingKey, g),
  load: (): MeetingGrouping => (prefs.string(groupingKey) === "category" ? "category" : "time"),
};

/** SF Symbol names, as the Mac stores them. */
export const CategorySymbols = ["character.book.closed", "function", "atom", "flask", "globe.asia.australia", "laptopcomputer", "music.note", "book.closed"];

export const CategoryPalette = {
  uncategorizedSymbol: "tray",
  swatches: [
    { light: "#2F6FDE", dark: "#7FA8F5" },
    { light: "#2E9D5B", dark: "#6CCB92" },
    { light: "#E07B24", dark: "#F2A65E" },
    { light: "#7B5CD6", dark: "#A99AF0" },
    { light: "#D6497C", dark: "#F08CB0" },
    { light: "#1F9AA6", dark: "#6CCBD3" },
    { light: "#C99A06", dark: "#E8C34A" },
    { light: "#6B717B", dark: "#9AA3AD" },
  ],
  get uncategorizedIndex() {
    return this.swatches.length - 1;
  },
  clamp(index: number) {
    return Math.min(Math.max(0, index), this.swatches.length - 1);
  },
  /** CSS colour that follows light and dark mode. */
  ink(index: number) {
    return `var(--swatch-${this.clamp(index)})`;
  },
  fill(index: number) {
    return `var(--swatch-${this.clamp(index)}-fill)`;
  },
};

export function categoryMatches(categoryID: string | null | undefined, filter: CategoryFilter): boolean {
  if (filter.kind === "all") return true;
  if (filter.kind === "uncategorized") return categoryID == null;
  return categoryID === filter.id;
}

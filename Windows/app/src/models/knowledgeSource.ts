// Models/KnowledgeSource.swift
import { categoryMatches, type CategoryFilter } from "./category";

export type KnowledgeSource = {
  id: string;
  title: string;
  fileName: string;
  categoryID?: string | null;
  importedAt: number;
  fileModifiedAt: number;
  byteCount: number;
};

export function matchingSources(sources: KnowledgeSource[], query: string, filter: CategoryFilter): KnowledgeSource[] {
  const needle = query.trim().toLowerCase();
  return sources.filter((s) => categoryMatches(s.categoryID, filter) && (!needle || s.title.toLowerCase().includes(needle)));
}

export function fileExtension(name: string): string {
  const dot = name.lastIndexOf(".");
  return dot < 0 ? "" : name.slice(dot + 1).toLowerCase();
}

export function safeFileName(name: string): string {
  const cleaned = name.replace(/\//g, "-").replace(/:/g, "-").replace(/[\\*?"<>|]/g, "-").trim();
  return cleaned || "file";
}

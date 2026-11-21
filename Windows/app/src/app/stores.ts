// MeetingStore, SourceStore, MeetingSourceLinkStore and ChatStore: the Mac's files, same names and JSON.
import { fs, paths } from "../platform";
import { tr } from "../i18n";
import { newID, nowReference } from "../support/format";
import type { Meeting } from "../models/meeting";
import type { MeetingCategory } from "../models/category";
import { safeFileName, type KnowledgeSource } from "../models/knowledgeSource";
import { decodeChat, type ChatSession } from "../models/chatSession";
import { SourceText } from "../models/sourceText";

const chain = () => {
  let queue = Promise.resolve();
  return (job: () => Promise<void>) => {
    const next = queue.then(job, job);
    queue = next.catch(() => {});
    return next;
  };
};

export type Snapshot = { meetings: Meeting[]; categories: MeetingCategory[] };

const meetingQueue = chain();
export const MeetingStore = {
  get file() {
    return paths.join(paths.root, "meetings.json");
  },
  audioDirectory(id: string) {
    return paths.join(paths.root, "meetings", id);
  },
  async load(): Promise<Snapshot | null> {
    const text = await fs.readText(this.file);
    if (text === null) return null;
    return JSON.parse(text) as Snapshot;
  },
  save(snapshot: Snapshot): Promise<void> {
    const text = JSON.stringify(snapshot);
    return meetingQueue(() => fs.writeText(this.file, text));
  },
  flush() {
    return meetingQueue(async () => {});
  },
};

export const MeetingSourceLinkStore = {
  get file() {
    return paths.join(paths.root, "meeting-links.json");
  },
  async load(): Promise<Record<string, string[]>> {
    const text = await fs.readText(this.file).catch(() => null);
    if (!text) return {};
    try {
      return JSON.parse(text);
    } catch {
      return {};
    }
  },
  save(links: Record<string, string[]>) {
    return fs.writeText(this.file, JSON.stringify(links));
  },
};

export const SourceStore = {
  get file() {
    return paths.join(paths.root, "sources.json");
  },
  get sourcesRoot() {
    return paths.join(paths.root, "sources");
  },
  directory(id: string) {
    return paths.join(this.sourcesRoot, id);
  },
  fileURL(source: KnowledgeSource) {
    return paths.join(this.directory(source.id), source.fileName);
  },
  /** The source a file belongs to, when it is one of Nomi's own copies. */
  sourceID(path: string): string | null {
    const folder = paths.dir(path);
    if (paths.dir(folder).toLowerCase() !== this.sourcesRoot.toLowerCase()) return null;
    return paths.name(folder).toUpperCase();
  },
  accepts(path: string) {
    return SourceText.canRead(path);
  },
  async load(): Promise<KnowledgeSource[]> {
    const text = await fs.readText(this.file);
    if (text === null) return [];
    return JSON.parse(text) as KnowledgeSource[];
  },
  save(sources: KnowledgeSource[]) {
    return fs.writeText(this.file, JSON.stringify(sources));
  },
  async stage(path: string, categoryID: string | null | undefined): Promise<KnowledgeSource> {
    if (!this.accepts(path)) throw new Error(SourceText.refusal(path));
    const stat = await fs.stat(path);
    if (!stat) throw new Error(tr("这个文件无法读取。"));
    const id = newID();
    const name = safeFileName(paths.name(path));
    const destination = paths.join(this.directory(id), name);
    try {
      await fs.copy(path, destination);
    } catch (error) {
      await fs.remove(this.directory(id)).catch(() => {});
      throw error;
    }
    return { id, title: name, fileName: name, categoryID: categoryID ?? null, importedAt: nowReference(), fileModifiedAt: stat.modified, byteCount: stat.size };
  },
  remove(source: KnowledgeSource) {
    return fs.remove(this.directory(source.id)).catch(() => {});
  },
  /** Copies each file into a category folder; the same name in one folder gets a number. */
  async exportGrouped(files: { sourceURL: string; folder: string; fileName: string }[], into: string) {
    const used = new Set<string>();
    for (const file of files) {
      const folder = safeFileName(file.folder);
      const dir = paths.join(into, folder);
      const name = safeFileName(file.fileName);
      const dot = name.lastIndexOf(".");
      const base = dot < 0 ? name : name.slice(0, dot);
      const ext = dot < 0 ? "" : name.slice(dot + 1);
      let candidate = name;
      let n = 2;
      while (used.has(`${folder}/${candidate.toLowerCase()}`) || (await fs.exists(paths.join(dir, candidate)))) {
        candidate = ext ? `${base} ${n}.${ext}` : `${base} ${n}`;
        n++;
      }
      used.add(`${folder}/${candidate.toLowerCase()}`);
      await fs.copy(file.sourceURL, paths.join(dir, candidate));
    }
  },
};

const chatQueue = chain();
export const ChatStore = {
  get directory() {
    return paths.join(paths.root, "chats");
  },
  async load(): Promise<ChatSession[]> {
    if (!(await fs.exists(this.directory))) return [];
    const names = await fs.list(this.directory);
    const chats: ChatSession[] = [];
    for (const name of names.filter((n) => n.endsWith(".json"))) {
      const text = await fs.readText(paths.join(this.directory, name)).catch(() => null);
      if (!text) continue;
      try {
        chats.push(decodeChat(JSON.parse(text)));
      } catch {
        /* skip a damaged chat */
      }
    }
    return chats;
  },
  save(session: ChatSession): Promise<void> {
    const text = JSON.stringify(session);
    return chatQueue(() => fs.writeText(paths.join(this.directory, `${session.id}.json`), text));
  },
  delete(id: string) {
    return chatQueue(() => fs.remove(paths.join(this.directory, `${id}.json`)).catch(() => {}));
  },
  flush() {
    return chatQueue(async () => {});
  },
};

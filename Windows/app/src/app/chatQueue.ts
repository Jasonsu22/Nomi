// App/AppModel+ChatQueue.swift and Models/ChatQueue.swift: messages sent while an answer is coming.
import { tr } from "../i18n";
import { newID } from "../support/format";
import { prefs } from "../support/prefs";
import { ChatImages, type ChatImageDraft } from "../models/chatImage";
import { LocalEngine } from "../engine/localEngine";
import { AppModel, type QueuedPrompt } from "./model";

export type BusySendMode = "queue" | "steer";
export const busySendTitle = (m: BusySendMode) => (m === "queue" ? tr("排队") : tr("打断并引导"));
export const BusySend = {
  key: "nomi.chat.busySend",
  get current(): BusySendMode {
    return prefs.string(this.key) === "steer" ? "steer" : "queue";
  },
  set current(value: BusySendMode) {
    prefs.set(this.key, value);
  },
  other: (m: BusySendMode): BusySendMode => (m === "queue" ? "steer" : "queue"),
};

export const ChatQueueRules = {
  next(queue: QueuedPrompt[], paused: Set<string>, after: string | null): QueuedPrompt | null {
    const ready = queue.filter((q) => !paused.has(q.chatID));
    if (after) {
      const same = ready.find((q) => q.chatID === after);
      if (same) return same;
    }
    return ready.reduce<QueuedPrompt | null>((best, q) => (!best || q.createdAt < best.createdAt ? q : best), null);
  },
  moving(queue: QueuedPrompt[], id: string, offset: number): QueuedPrompt[] {
    const item = queue.find((q) => q.id === id);
    if (!item) return queue;
    const own = queue.filter((q) => q.chatID === item.chatID && q.id !== id);
    own.splice(Math.min(Math.max(0, offset), own.length), 0, item);
    const positions = queue.map((q, i) => (q.chatID === item.chatID ? i : -1)).filter((i) => i >= 0);
    const result = [...queue];
    positions.forEach((p, k) => (result[p] = own[k]));
    return result;
  },
};

declare module "./model" {
  interface AppModel {
    readonly isChatAnswering: boolean;
    isAnswering(chatID: string | null): boolean;
    readonly canStartAnotherAnswer: boolean;
    submit(question: string, images: ChatImageDraft[], anchor: string | null, mode: BusySendMode): boolean;
    enqueue(text: string, images: ChatImageDraft[], chatID: string): void;
    queued(chatID: string | null): QueuedPrompt[];
    advanceQueue(after: string | null): void;
    chatDidEnd(chatID: string, succeeded: boolean): void;
    resumeQueue(chatID: string): void;
    removeQueued(id: string): void;
    clearQueue(chatID: string): void;
    takeQueued(id: string): QueuedPrompt | null;
    moveQueued(id: string, offset: number): void;
    sendQueuedNow(id: string): void;
    steer(text: string, images: ChatImageDraft[], chatID: string): boolean;
  }
}

const P = AppModel.prototype;

Object.defineProperty(P, "isChatAnswering", { get(this: AppModel) { return Object.keys(this.chatRuns).length > 0; } });
P.isAnswering = function (chatID) {
  return !!chatID && !!this.chatRuns[chatID];
};
Object.defineProperty(P, "canStartAnotherAnswer", {
  get(this: AppModel) {
    return this.llmConfiguration.mode === "api" || Object.values(this.chatRuns).filter((r) => r.mode === "local").length < LocalEngine.maxReplies;
  },
});

P.submit = function (question, images, anchor, mode) {
  const trimmed = question.trim();
  if (!trimmed && !images.length) return false;
  if (anchor) this.ensureMeetingChat(anchor);
  else this.ensureChat();
  const chatID = (anchor ? this.meetingChatID[anchor] : null) ?? this.currentChatID;
  if (!chatID) return false;
  if (this.isAnswering(chatID)) {
    if (mode === "steer") return this.steer(trimmed, images, chatID);
    this.enqueue(trimmed, images, chatID);
    return true;
  }
  if (!this.canStartAnotherAnswer) {
    this.enqueue(trimmed, images, chatID);
    return true;
  }
  return this.ask(trimmed, { images, chatID });
};

P.enqueue = function (text, images, chatID) {
  this.chatQueue = [...this.chatQueue, { id: newID(), chatID, text, images, createdAt: Date.now() }];
  this.queuePaused.delete(chatID);
  this.changed();
};

P.queued = function (chatID) {
  return chatID ? this.chatQueue.filter((q) => q.chatID === chatID) : [];
};

P.advanceQueue = function (after) {
  while (this.canStartAnotherAnswer) {
    const next = ChatQueueRules.next(this.chatQueue.filter((q) => !this.isAnswering(q.chatID)), this.queuePaused, after);
    if (!next) break;
    if (!this.canGenerateAssistant) {
      this.queuePaused.add(next.chatID);
      break;
    }
    this.chatQueue = this.chatQueue.filter((q) => q.id !== next.id);
    if (!this.ask(next.text, { images: next.images, chatID: next.chatID })) {
      this.chatQueue = [next, ...this.chatQueue];
      this.queuePaused.add(next.chatID);
    }
  }
  this.changed();
};

P.chatDidEnd = function (chatID, succeeded) {
  const steer = this.pendingSteers[chatID];
  if (steer) {
    delete this.pendingSteers[chatID];
    this.chatQueue = [steer, ...this.chatQueue];
    this.queuePaused.delete(chatID);
  }
  if (!succeeded && this.chatQueue.some((q) => q.chatID === chatID)) this.queuePaused.add(chatID);
  setTimeout(() => this.advanceQueue(chatID), 0);
  this.changed();
};

P.resumeQueue = function (chatID) {
  this.queuePaused.delete(chatID);
  this.advanceQueue(chatID);
};

P.removeQueued = function (id) {
  const item = this.chatQueue.find((q) => q.id === id);
  if (!item) return;
  this.chatQueue = this.chatQueue.filter((q) => q.id !== id);
  item.images.forEach((d) => void ChatImages.discard(d));
  if (!this.chatQueue.some((q) => q.chatID === item.chatID)) this.queuePaused.delete(item.chatID);
  this.changed();
};

P.clearQueue = function (chatID) {
  for (const item of this.chatQueue.filter((q) => q.chatID === chatID)) item.images.forEach((d) => void ChatImages.discard(d));
  this.chatQueue = this.chatQueue.filter((q) => q.chatID !== chatID);
  this.queuePaused.delete(chatID);
  this.changed();
};

P.takeQueued = function (id) {
  const item = this.chatQueue.find((q) => q.id === id);
  if (!item) return null;
  this.chatQueue = this.chatQueue.filter((q) => q.id !== id);
  if (!this.chatQueue.some((q) => q.chatID === item.chatID)) this.queuePaused.delete(item.chatID);
  this.changed();
  return item;
};

P.moveQueued = function (id, offset) {
  this.chatQueue = ChatQueueRules.moving(this.chatQueue, id, offset);
  this.changed();
};

P.sendQueuedNow = function (id) {
  const item = this.takeQueued(id);
  if (!item) return;
  if (this.isAnswering(item.chatID)) this.steer(item.text, item.images, item.chatID);
  else if (this.canStartAnotherAnswer) {
    if (!this.ask(item.text, { images: item.images, chatID: item.chatID })) this.chatQueue = [item, ...this.chatQueue];
  } else this.chatQueue = [item, ...this.chatQueue];
  this.changed();
};

P.steer = function (text, images, chatID) {
  if (!this.isAnswering(chatID) || this.pendingSteers[chatID]) {
    if (!this.isAnswering(chatID) && this.canStartAnotherAnswer) return this.ask(text, { images, chatID });
    this.enqueue(text, images, chatID);
    return true;
  }
  this.pendingSteers[chatID] = { id: newID(), chatID, text, images, createdAt: Date.now() };
  this.stopChat(chatID);
  return true;
};

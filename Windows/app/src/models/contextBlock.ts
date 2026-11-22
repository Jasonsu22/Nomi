// ContextBlock from Models/ChatContext.swift: one passage given to the model.
export type ContextBlock = {
  title: string;
  detail: string;
  body: string;
  meetingID?: string | null;
  sourceID?: string | null;
  url?: string | null;
  /** Set on a passage from an earlier chat, so its citation opens that chat. */
  chatID?: string | null;
  /** Always kept by `pack`, ahead of ranked passages. */
  pinned?: boolean;
  /** Seconds into the meeting where this passage starts. */
  at?: number | null;
  /** The page or slide of a file. */
  page?: number | null;
};

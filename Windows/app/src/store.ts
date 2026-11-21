// The app's state. Rust events land here; pages read from here.
import { create } from "zustand";
import { api, events, type EngineState, type LiveUpdate, type MeetingSummary, type Overview, type Progress, type Settings } from "./lib/api";
import { systemLang, type Lang } from "./lib/i18n";

export type Page = "live" | "meetings" | "settings" | "setup";

type AppStore = {
  page: Page;
  lang: Lang;
  overview: Overview | null;
  engine: EngineState;
  downloads: Record<string, Progress>;
  live: LiveUpdate | null;
  level: number;
  notice: { code: string; message: string } | null;
  meetings: MeetingSummary[];
  openMeeting: string | null;
  go: (page: Page) => void;
  open: (id: string | null) => void;
  refresh: () => Promise<void>;
  refreshMeetings: () => Promise<void>;
  saveSettings: (change: Partial<Settings>) => Promise<void>;
  clearNotice: () => void;
};

function langOf(settings: Settings | undefined): Lang {
  return settings?.uiLanguage === "zh" || settings?.uiLanguage === "en" ? settings.uiLanguage : systemLang();
}

export const useApp = create<AppStore>((set, get) => ({
  page: "live",
  lang: systemLang(),
  overview: null,
  engine: { state: "", message: null, status: null },
  downloads: {},
  live: null,
  level: 0,
  notice: null,
  meetings: [],
  openMeeting: null,
  go: (page) => set({ page }),
  open: (id) => set({ openMeeting: id, page: "meetings" }),
  refresh: async () => {
    const overview = await api.overview();
    set({ overview, engine: overview.engine, lang: langOf(overview.settings) });
  },
  refreshMeetings: async () => set({ meetings: await api.listMeetings() }),
  saveSettings: async (change) => {
    const current = get().overview?.settings;
    if (!current) return;
    const settings = { ...current, ...change };
    set({ overview: { ...get().overview!, settings }, lang: langOf(settings) });
    await api.saveSettings(settings);
  },
  clearNotice: () => set({ notice: null }),
}));

/** Connects Rust's events to the store once, at start. */
export async function connect() {
  const store = useApp;
  await events.engineState((engine) => {
    store.setState({ engine });
    void store.getState().refresh();
  });
  await events.liveUpdate((live) => {
    store.setState({ live });
    if (live.state === "done") void store.getState().refreshMeetings();
  });
  let levelFrame = 0;
  let pendingLevel = 0;
  await events.liveLevel((rms) => {
    // One update per frame, so the meter moves smoothly without re-rendering 20 times a second.
    pendingLevel = rms;
    if (!levelFrame) {
      levelFrame = requestAnimationFrame(() => {
        levelFrame = 0;
        store.setState({ level: pendingLevel });
      });
    }
  });
  await events.liveNotice((notice) => store.setState({ notice }));
  await events.download((progress) => {
    store.setState({ downloads: { ...store.getState().downloads, [progress.id]: progress } });
    if (progress.state !== "downloading") void store.getState().refresh();
  });
  await store.getState().refresh();
  await store.getState().refreshMeetings();
  const live = await api.liveSnapshot();
  if (live) store.setState({ live });
  const overview = store.getState().overview;
  if (overview && !overview.settings.setUp) store.setState({ page: "setup" });
}

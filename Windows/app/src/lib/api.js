// The Rust core's commands and events, typed. Names match src-tauri/src/lib.rs.
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
export const api = {
    overview: () => invoke("overview"),
    deviceReport: () => invoke("device_report"),
    saveSettings: (settings) => invoke("save_settings", { settings }),
    downloadModel: (id) => invoke("download_model", { id }),
    cancelDownload: (id) => invoke("cancel_download", { id }),
    deleteModel: (id) => invoke("delete_model", { id }),
    startEngine: () => invoke("start_engine"),
    inputDevices: () => invoke("input_devices"),
    startRecording: (options) => invoke("start_recording", { options }),
    liveSnapshot: () => invoke("live_snapshot"),
    stopRecording: () => invoke("stop_recording"),
    listMeetings: () => invoke("list_meetings"),
    getMeeting: (id) => invoke("get_meeting", { id }),
    renameMeeting: (id, title) => invoke("rename_meeting", { id, title }),
    deleteMeeting: (id) => invoke("delete_meeting", { id }),
    setHiddenSpeakers: (id, hidden) => invoke("set_hidden_speakers", { id, hidden }),
    renameSpeaker: (id, speaker, name) => invoke("rename_speaker", { id, speaker, name }),
    setMe: (id, speaker) => invoke("set_me", { id, speaker }),
    setTeacher: (id, speaker) => invoke("set_teacher", { id, speaker }),
    openFolder: (path) => invoke("open_folder", { path }),
};
export const events = {
    engineState: (f) => listen("engine-state", (e) => f(e.payload)),
    liveUpdate: (f) => listen("live-update", (e) => f(e.payload)),
    liveLevel: (f) => listen("live-level", (e) => f(e.payload)),
    liveNotice: (f) => listen("live-notice", (e) => f(e.payload)),
    download: (f) => listen("download-progress", (e) => f(e.payload)),
};

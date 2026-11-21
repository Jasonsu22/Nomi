// App/AppUpdater.swift, for Windows: checks the GitHub releases for a newer Windows build and
// offers its download. (The Mac uses Sparkle; signed in-place updates come with the Windows 1.0.)
import { fetch } from "@tauri-apps/plugin-http";
import { app as platformApp, shell } from "../platform";
import { prefs } from "../support/prefs";

const releases = "https://api.github.com/repos/Jasonsu22/Nomi/releases?per_page=20";

export type AvailableUpdate = { version: string; url: string; notes: string };

function compare(a: string, b: string): number {
  const pa = a.split(/[.\-]/).map((x) => parseInt(x, 10) || 0);
  const pb = b.split(/[.\-]/).map((x) => parseInt(x, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d) return d;
  }
  return 0;
}

export class AppUpdater {
  version = "";
  canCheck = true;
  checking = false;
  available: AvailableUpdate | null = null;
  lastResult: "none" | "upToDate" | "failed" = "none";
  onChange?: () => void;

  get isAvailable() {
    return true;
  }

  get automaticallyChecks() {
    return prefs.bool("nomi.updates.automatic") ?? true;
  }
  set automaticallyChecks(value: boolean) {
    prefs.set("nomi.updates.automatic", value);
    this.onChange?.();
  }

  async start() {
    this.version = await platformApp.version().catch(() => "");
    this.onChange?.();
    const last = prefs.number("nomi.updates.lastCheck") ?? 0;
    if (this.automaticallyChecks && Date.now() - last > 24 * 3600 * 1000) void this.checkForUpdates(true);
  }

  async checkForUpdates(quiet = false) {
    if (this.checking) return;
    this.checking = true;
    this.canCheck = false;
    this.onChange?.();
    try {
      const response = await fetch(releases, { headers: { Accept: "application/vnd.github+json", "User-Agent": "Nomi" } });
      const list = (await response.json()) as { tag_name: string; html_url: string; body: string; assets: { name: string; browser_download_url: string }[] }[];
      prefs.set("nomi.updates.lastCheck", Date.now());
      const windows = list
        .filter((r) => r.tag_name.startsWith("windows-") && r.assets.some((a) => a.name.toLowerCase().endsWith(".exe")))
        .map((r) => ({ version: r.tag_name.replace(/^windows-v?/, ""), url: r.assets.find((a) => a.name.toLowerCase().endsWith(".exe"))!.browser_download_url, notes: r.body ?? "", page: r.html_url }));
      const newest = windows.sort((a, b) => compare(b.version, a.version))[0];
      if (newest && compare(newest.version, this.version) > 0) {
        this.available = { version: newest.version, url: newest.url, notes: newest.notes };
        this.lastResult = "none";
      } else {
        this.available = null;
        this.lastResult = quiet ? "none" : "upToDate";
      }
    } catch {
      this.lastResult = quiet ? "none" : "failed";
    } finally {
      this.checking = false;
      this.canCheck = true;
      this.onChange?.();
    }
  }

  install() {
    if (this.available) void shell.openURL(this.available.url);
  }
}

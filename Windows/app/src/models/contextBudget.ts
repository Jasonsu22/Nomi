// Models/ContextBudget.swift
export type ContextBudget = { history: number; turnAnswer: number; scope: number; library: number; sidePanelTranscript: number };

export const ContextBudgets = {
  local: { history: 6_000, turnAnswer: 1_500, scope: 16_000, library: 9_000, sidePanelTranscript: 18_000 } as ContextBudget,
  api: { history: 24_000, turnAnswer: 6_000, scope: 60_000, library: 24_000, sidePanelTranscript: 90_000 } as ContextBudget,
  apiReference: 120_000,

  current(mode: "local" | "api", profile?: { contextCharacters?: number | null } | null): ContextBudget {
    if (mode !== "api") return this.local;
    const size = profile?.contextCharacters;
    if (!size || size <= 0) return this.api;
    return this.scaled(this.api, size / this.apiReference);
  },

  scaled(b: ContextBudget, factor: number): ContextBudget {
    const part = (value: number, floor: number) => Math.max(Math.floor(floor / 4), Math.floor(value * factor));
    const l = this.local;
    return {
      history: part(b.history, l.history),
      turnAnswer: part(b.turnAnswer, l.turnAnswer),
      scope: part(b.scope, l.scope),
      library: part(b.library, l.library),
      sidePanelTranscript: part(b.sidePanelTranscript, l.sidePanelTranscript),
    };
  },
};

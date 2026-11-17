// Server-only. Each account's Forever Gold data (sent by the tray app from
// the addon's webExport table - see addon/ForeverGold/Web.lua): their
// auctions, each character's gold over time, and saved farming trips.
// One private file per account in the market bucket: user/<user id>.json.

import { getJson, putJson } from "./marketStore";

export type OwnedAuction = { id: number; item: number; q: number; b: number; st: number; tl?: number };
export type CharInfo = {
  name: string;
  faction?: string;
  level?: number;
  class?: string;
  money: number;
  seen: number;
  house?: number;
  auctions?: { t: number; list: OwnedAuction[] };
};
export type Session = {
  t: number; // when it started
  secs: number;
  v: number; // value made (copper)
  cash?: number; // coin actually gained
  zone?: string;
  who?: string;
  kills?: number;
  top?: [number, number][]; // [item id, count]
};
export type UserFile = {
  v: 1;
  updated: number;
  chars: Record<string, CharInfo>;
  gold: Record<string, [number, number][]>; // name -> [time, copper]
  sessions: Session[];
};

const MAX_GOLD_POINTS = 2000;
const MAX_SESSIONS = 300;
const GOLD_EVERY = 6 * 3600; // keep an unchanged balance at most every 6 hours

const fileName = (userId: string) => `user/${userId}.json`;

export async function readUser(userId: string): Promise<UserFile | null> {
  return getJson<UserFile>(fileName(userId));
}

// ---- cleaning what the tray sends (it's user-controlled input) ----
const num = (v: unknown, lo = -1e15, hi = 1e15) => (typeof v === "number" && Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : 0);
const text = (v: unknown, max = 60) => (typeof v === "string" ? v.slice(0, max) : undefined);
const list = (v: unknown): unknown[] => (Array.isArray(v) ? v : v && typeof v === "object" ? Object.values(v) : []);

function cleanAuctions(v: unknown): CharInfo["auctions"] {
  if (!v || typeof v !== "object") return undefined;
  const a = v as { t?: unknown; list?: unknown };
  const out: OwnedAuction[] = [];
  for (const raw of list(a.list).slice(0, 300)) {
    const r = raw as Record<string, unknown>;
    const item = num(r.item, 0, 1e7);
    if (!item) continue;
    out.push({ id: num(r.id, 0, 1e13), item, q: num(r.q, 1, 1e6) || 1, b: num(r.b, 0, 1e12), st: num(r.st, 0, 10), tl: num(r.tl, 0, 1e7) || undefined });
  }
  return { t: num(a.t, 0, 4e9), list: out };
}

function cleanChar(raw: unknown): CharInfo | null {
  const c = raw as Record<string, unknown>;
  const name = text(c?.name);
  if (!name) return null;
  return {
    name,
    faction: text(c.faction, 20),
    level: num(c.level, 0, 200) || undefined,
    class: text(c.class, 20),
    money: num(c.money, 0, 1e13),
    seen: num(c.seen, 0, 4e9),
    house: num(c.house, 0, 1000) || undefined,
    auctions: cleanAuctions(c.auctions),
  };
}

function cleanSession(raw: unknown): Session | null {
  const s = raw as Record<string, unknown>;
  const t = num(s?.t, 0, 4e9);
  if (!t) return null;
  return {
    t,
    secs: num(s.secs, 0, 1e7),
    v: num(s.v, -1e13, 1e13),
    cash: num(s.cash, -1e13, 1e13),
    zone: text(s.zone),
    who: text(s.who),
    kills: num(s.kills, 0, 1e7),
    top: list(s.top)
      .slice(0, 6)
      .map((x) => list(x))
      .filter((x) => x.length >= 2)
      .map((x) => [num(x[0], 0, 1e7), num(x[1], 0, 1e7)] as [number, number]),
  };
}

// Folds one upload into the account's file and saves it.
export async function mergeUpload(userId: string, data: unknown): Promise<UserFile> {
  const d = (data ?? {}) as Record<string, unknown>;
  const f: UserFile = (await readUser(userId)) ?? { v: 1, updated: 0, chars: {}, gold: {}, sessions: [] };

  for (const raw of list(d.chars).slice(0, 50)) {
    const c = cleanChar(raw);
    if (!c) continue;
    const had = f.chars[c.name];
    if (!had || c.seen >= had.seen) {
      // Keep whichever auction list was read more recently.
      const auctions = had?.auctions && (!c.auctions || had.auctions.t > c.auctions.t) ? had.auctions : c.auctions;
      f.chars[c.name] = { ...c, auctions };
    } else if (c.auctions && (!had.auctions || c.auctions.t > had.auctions.t)) {
      had.auctions = c.auctions;
    }
    if (c.seen > 0) {
      const pts = (f.gold[c.name] ??= []);
      const last = pts[pts.length - 1];
      if (!last || (c.seen > last[0] && (c.money !== last[1] || c.seen - last[0] >= GOLD_EVERY))) {
        pts.push([c.seen, c.money]);
        if (pts.length > MAX_GOLD_POINTS) pts.splice(0, pts.length - MAX_GOLD_POINTS);
      }
    }
  }

  const seen = new Set(f.sessions.map((s) => `${s.t}|${s.who ?? ""}`));
  for (const raw of list(d.sessions).slice(0, 30)) {
    const s = cleanSession(raw);
    if (!s) continue;
    const k = `${s.t}|${s.who ?? ""}`;
    if (seen.has(k)) continue;
    seen.add(k);
    f.sessions.push(s);
  }
  f.sessions.sort((a, b) => b.t - a.t);
  f.sessions = f.sessions.slice(0, MAX_SESSIONS);

  f.updated = Math.floor(Date.now() / 1000);
  await putJson(fileName(userId), f);
  return f;
}

// Total gold across all characters over time: at every recorded point, the
// sum of each character's latest known balance.
export function totalGoldSeries(f: UserFile): [number, number][] {
  const events: [number, string, number][] = [];
  for (const [name, pts] of Object.entries(f.gold)) for (const [t, m] of pts) events.push([t, name, m]);
  events.sort((a, b) => a[0] - b[0]);
  const latest = new Map<string, number>();
  const out: [number, number][] = [];
  for (const [t, name, m] of events) {
    latest.set(name, m);
    let total = 0;
    for (const v of latest.values()) total += v;
    if (out.length && out[out.length - 1][0] === t) out[out.length - 1][1] = total;
    else out.push([t, total]);
  }
  return out;
}

// Server-only. Friends' gathering spots (2026-11-26, "have it so gathered
// nodes are shared between all my friends, like on the map").
//
// Each account's Forever Gold upload (/api/market/upload) carries its own
// recorded spots; they're kept one file per account in the private market
// bucket (nodes/<userId>.json). /api/nodes puts everyone else's together for
// the tray app, which writes them into Forever Gold's SharedNodes.lua.

import { supabaseAdmin } from "./supabaseAdmin";
import { getJson, putJson } from "./marketStore";

// One spot: [x, y, kind, name, times gathered, last gathered (unix)]
export type Spot = [number, number, string, string, number, number];
// With who found it, once merged: [..., "Danny" or "Danny, Bob"]
export type SharedSpot = [number, number, string, string, number, number, string];
type UserNodes = { v: 1; updated: number; who: string; maps: Record<string, Spot[]> };

const KINDS = new Set(["ore", "herb", "fish", "chest"]);
const MAX_PER_MAP = 3000;
const MAX_TOTAL = 20000;
const PREFIX = process.env.MARKET_STORE_PREFIX ?? "";
const fileName = (userId: string) => `nodes/${userId}.json`;

const num = (v: unknown, lo: number, hi: number) =>
  typeof v === "number" && Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : null;
const list = (v: unknown): unknown[] => (Array.isArray(v) ? v : v && typeof v === "object" ? Object.values(v) : []);

// What the tray sent (user-controlled input) -> clean spots per map.
export function cleanNodes(raw: unknown): Record<string, Spot[]> | null {
  if (!raw || typeof raw !== "object") return null;
  const out: Record<string, Spot[]> = {};
  let total = 0;
  for (const [key, spots] of Object.entries(raw as Record<string, unknown>)) {
    const mapID = Number(key);
    if (!Number.isInteger(mapID) || mapID <= 0 || mapID > 100000) continue;
    const clean: Spot[] = [];
    for (const s of list(spots).slice(0, MAX_PER_MAP)) {
      const a = list(s);
      const x = num(a[0], 0, 1);
      const y = num(a[1], 0, 1);
      const kind = typeof a[2] === "string" ? a[2] : "";
      if (x === null || y === null || !KINDS.has(kind)) continue;
      const name = typeof a[3] === "string" ? a[3].slice(0, 60) : "";
      clean.push([x, y, kind, name, num(a[4], 1, 1e6) ?? 1, num(a[5], 0, 4e9) ?? 0]);
      if (++total >= MAX_TOTAL) break;
    }
    if (clean.length) out[String(mapID)] = clean;
    if (total >= MAX_TOTAL) break;
  }
  return out;
}

export async function saveUserNodes(userId: string, raw: unknown): Promise<void> {
  const maps = cleanNodes(raw);
  if (!maps) return;
  const { data: profile } = await supabaseAdmin.from("profiles").select("display_name").eq("id", userId).maybeSingle();
  const file: UserNodes = { v: 1, updated: Math.floor(Date.now() / 1000), who: profile?.display_name ?? "", maps };
  await putJson(fileName(userId), file);
}

// Everyone's spots but exceptUserId's, with spots several people found
// merged into one (same kind, close together).
export async function loadSharedNodes(exceptUserId: string): Promise<Record<string, SharedSpot[]>> {
  const { data: files } = await supabaseAdmin.storage.from("market").list(`${PREFIX}nodes`, { limit: 1000 });
  const ids = (files ?? [])
    .map((f) => f.name.replace(/\.json$/, ""))
    .filter((id) => id && id !== exceptUserId);
  const all = await Promise.all(ids.map((id) => getJson<UserNodes>(fileName(id))));
  const out: Record<string, SharedSpot[]> = {};
  for (const file of all) {
    if (!file || typeof file.maps !== "object") continue;
    const who = file.who || "a friend";
    for (const [mapID, spots] of Object.entries(file.maps)) {
      const merged = (out[mapID] ??= []);
      for (const s of spots) {
        const radius = s[2] === "fish" ? 0.02 : 0.008;
        const same = merged.find(
          (m) => m[2] === s[2] && Math.abs(m[0] - s[0]) < radius && Math.abs(m[1] - s[1]) < radius
        );
        if (same) {
          same[4] += s[4];
          same[5] = Math.max(same[5], s[5]);
          if (!same[3] && s[3]) same[3] = s[3];
          if (!same[6].split(", ").includes(who)) same[6] = `${same[6]}, ${who}`;
        } else {
          merged.push([s[0], s[1], s[2], s[3], s[4], s[5], who]);
        }
      }
    }
  }
  return out;
}

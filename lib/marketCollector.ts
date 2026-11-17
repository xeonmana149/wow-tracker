// Server-only. Keeps the auction sale-rate data (lib/market.ts) up to date
// and stored in a private Supabase Storage bucket, one set of files per
// auction house:
//
//   meta-<house>.json        tiny: which snapshot we have, when we last checked
//   state-<house>.json.gz    every auction from the last snapshot + 14 days of counts and prices
//   rates-<house>.json       what the tray app hands the game
//   site-<house>.json.gz     what the website's Auction House pages show (history per item)
//   ladder-<house>.json.gz   everything listed right now, grouped by price
//
// There's no scheduler: every tray app asks /api/market for the rates about
// every 20 minutes, and that request also does the collecting when it's due.
// Checking costs nothing when Blizzard has no new snapshot (it answers 304),
// and a new snapshot appears about once an hour.

import { blizzardFetch } from "./blizzard";
import {
  applySnapshot,
  buildLadder,
  computeRates,
  computeSite,
  parseSnapshot,
  type HouseRates,
  type HouseState,
  type Ladder,
  type SiteData,
} from "./market";
import { topUpItemInfo } from "./marketItems";
import { getGzJson, getJson, putGzJson, putJson } from "./marketStore";

export const MARKET_REGION = "us";
const NAMESPACE = `dynamic-forever-${MARKET_REGION}`;
// Blizzard's ruleset id doesn't filter anything (every ruleset lists the
// same houses), so 1 is as good as any.
const RULESET = 1;
// Don't even ask Blizzard more often than this.
const CHECK_EVERY = 5 * 60;

// Which auction houses to track. 113 is the US Horde house the owner's
// characters use (matched against their in-game scan 2026-11-17). Add a
// friend's house by setting MARKET_HOUSES="113,110" in Vercel - each one
// costs a ~25 MB download an hour. Valid ids come from
// /data/wow/ruleset/1/auctions/ (110-125).
export function marketHouses(): number[] {
  const raw = process.env.MARKET_HOUSES ?? "113";
  const ids = raw
    .split(",")
    .map((s) => parseInt(s.trim(), 10))
    .filter((n) => n >= 100 && n <= 200);
  return [...new Set(ids)].slice(0, 4);
}

// What to call a house on the website. Only 113 has been matched to a
// faction so far; MARKET_HOUSE_NAMES="113:Horde,110:Alliance" adds more.
export function houseName(house: number): string {
  const names: Record<number, string> = { 113: "Horde" };
  for (const part of (process.env.MARKET_HOUSE_NAMES ?? "").split(",")) {
    const [id, name] = part.split(":");
    if (Number(id) && name?.trim()) names[Number(id)] = name.trim();
  }
  return names[house] ? `${names[house]} auction house` : `Auction house ${house}`;
}

type Meta = { snapT?: number; checkedAt?: number; last?: HouseState["last"]; error?: string };

const lastModified = (res: Response) => {
  const h = res.headers.get("last-modified");
  const t = h ? Math.floor(new Date(h).getTime() / 1000) : NaN;
  return Number.isFinite(t) ? t : 0;
};

export type CollectResult = {
  house: number;
  did: "skipped" | "unchanged" | "updated" | "error";
  snapT?: number;
  detail?: string;
  named?: number;
};

// Brings one house up to date if a new snapshot is out. Safe to call as
// often as you like, and safe if two calls overlap.
export async function collectHouse(house: number, now = Math.floor(Date.now() / 1000)): Promise<CollectResult> {
  const meta = (await getJson<Meta>(`meta-${house}.json`)) ?? {};
  if (meta.checkedAt && now - meta.checkedAt < CHECK_EVERY) {
    return { house, did: "skipped", snapT: meta.snapT };
  }
  // Claim this check first so overlapping requests mostly skip it.
  await putJson(`meta-${house}.json`, { ...meta, checkedAt: now });

  try {
    const path = `/data/wow/ruleset/${RULESET}/auctions/${house}`;
    const params = { namespace: NAMESPACE };
    const ims: Record<string, string> = meta.snapT ? { "If-Modified-Since": new Date(meta.snapT * 1000).toUTCString() } : {};
    const gearRes = await blizzardFetch(MARKET_REGION, path, params, ims);
    if (gearRes.status === 304) {
      return { house, did: "unchanged", snapT: meta.snapT, named: await nameSome(house) };
    }
    if (!gearRes.ok) throw new Error(`auctions HTTP ${gearRes.status}`);
    const snapT = lastModified(gearRes);
    if (!snapT || (meta.snapT && snapT <= meta.snapT)) {
      await gearRes.body?.cancel();
      return { house, did: "unchanged", snapT: meta.snapT };
    }
    const gear = await gearRes.json();

    const comRes = await blizzardFetch(MARKET_REGION, `${path}/commodities`, params);
    if (!comRes.ok) throw new Error(`commodities HTTP ${comRes.status}`);
    if (lastModified(comRes) !== snapT) {
      // Caught Blizzard mid-update - the two halves are from different
      // hours. Try again on the next request.
      await comRes.body?.cancel();
      await putJson(`meta-${house}.json`, { ...meta, checkedAt: now - CHECK_EVERY + 60 });
      return { house, did: "skipped", snapT: meta.snapT, detail: "snapshot halves out of step" };
    }
    const com = await comRes.json();

    const prev = await getGzJson<HouseState>(`state-${house}.json.gz`);
    const state = applySnapshot(prev, house, snapT, parseSnapshot(gear, com));
    const rates = computeRates(state);

    // State first: if anything after it fails, the next run just finds
    // the snapshot already applied and carries on.
    await putGzJson(`state-${house}.json.gz`, state);
    await putJson(`rates-${house}.json`, rates);
    await putGzJson(`site-${house}.json.gz`, computeSite(state, rates));
    await putGzJson(`ladder-${house}.json.gz`, buildLadder(state.a));
    await putJson(`meta-${house}.json`, { snapT, checkedAt: now, last: state.last });
    return { house, did: "updated", snapT };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await putJson(`meta-${house}.json`, { ...meta, checkedAt: now, error: msg }).catch(() => {});
    return { house, did: "error", detail: msg };
  }
}

// On a quiet check (no new snapshot), look up a few item names we don't
// have yet, so the Auction House pages fill in over time.
async function nameSome(house: number): Promise<number> {
  try {
    const rates = await readRates(house);
    if (!rates) return 0;
    return await topUpItemInfo(Object.keys(rates.items).map(Number), 120);
  } catch {
    return 0;
  }
}

export async function readRates(house: number): Promise<HouseRates | null> {
  return getJson<HouseRates>(`rates-${house}.json`);
}

// ---------------------------------------------------------------------
// Reading for the website. Each server instance keeps the last copy in
// memory and only re-downloads when a newer snapshot has been stored.
// ---------------------------------------------------------------------

type Cached<T> = { snapT: number; value: T; checkedAt: number };
const siteCache = new Map<number, Cached<SiteData>>();
const ladderCache = new Map<number, Cached<Ladder>>();
const META_TTL = 60 * 1000;

async function cachedRead<T>(cache: Map<number, Cached<T>>, house: number, file: string): Promise<T | null> {
  const hit = cache.get(house);
  if (hit && Date.now() - hit.checkedAt < META_TTL) return hit.value;
  const meta = await getJson<Meta>(`meta-${house}.json`);
  const snapT = meta?.snapT ?? 0;
  if (hit && hit.snapT === snapT) {
    hit.checkedAt = Date.now();
    return hit.value;
  }
  const value = await getGzJson<T>(file);
  if (!value) return hit?.value ?? null;
  cache.set(house, { snapT, value, checkedAt: Date.now() });
  return value;
}

// Houses collected before the website files existed only have the state:
// build both from it once, and save them for everyone else.
const rebuilding = new Map<number, Promise<boolean>>();
function rebuildFromState(house: number): Promise<boolean> {
  let p = rebuilding.get(house);
  if (!p) {
    p = doRebuild(house).finally(() => rebuilding.delete(house));
    rebuilding.set(house, p);
  }
  return p;
}

async function doRebuild(house: number): Promise<boolean> {
  const state = await getGzJson<HouseState>(`state-${house}.json.gz`);
  if (!state) return false;
  const rates = computeRates(state);
  await putGzJson(`site-${house}.json.gz`, computeSite(state, rates));
  await putGzJson(`ladder-${house}.json.gz`, buildLadder(state.a));
  return true;
}

async function readOrRebuild<T>(cache: Map<number, Cached<T>>, house: number, file: string): Promise<T | null> {
  const value = await cachedRead(cache, house, file);
  if (value) return value;
  if (!(await rebuildFromState(house))) return null;
  return cachedRead(cache, house, file);
}

// Every auction id in the latest snapshot -> [price each, quantity], for
// checking a player's own auctions. Built from the (big) state file, so it's
// kept in memory per snapshot.
const indexCache = new Map<number, Cached<Map<number, [number, number]>>>();
export async function readAuctionIndex(house: number): Promise<{ snapT: number; ids: Map<number, [number, number]> } | null> {
  const hit = indexCache.get(house);
  const meta = hit && Date.now() - hit.checkedAt < META_TTL ? null : await getJson<Meta>(`meta-${house}.json`);
  if (hit && (!meta || meta.snapT === hit.snapT)) {
    hit.checkedAt = Date.now();
    return { snapT: hit.snapT, ids: hit.value };
  }
  const state = await getGzJson<HouseState>(`state-${house}.json.gz`);
  if (!state) return null;
  const ids = new Map<number, [number, number]>();
  for (let i = 0; i < state.a.id.length; i++) ids.set(state.a.id[i], [state.a.price[i], state.a.qty[i]]);
  indexCache.set(house, { snapT: state.snapT, value: ids, checkedAt: Date.now() });
  return { snapT: state.snapT, ids };
}

export const readSite = (house: number) => readOrRebuild(siteCache, house, `site-${house}.json.gz`);
export const readLadder = (house: number) => readOrRebuild(ladderCache, house, `ladder-${house}.json.gz`);

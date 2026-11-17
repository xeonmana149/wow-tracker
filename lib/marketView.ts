// Server-only. Everything the Auction House pages show, worked out from the
// collector's files (lib/marketCollector.ts), item info (lib/marketItems.ts)
// and every crafting recipe in Forever (lib/data/forever-recipes.json, from
// scripts/build-forever-recipes.mjs).

import recipeData from "./data/forever-recipes.json";
import {
  H_DAY,
  H_MKT,
  H_SOLD,
  type HistDay,
  type LadderRow,
  type SiteData,
  type Ladder,
} from "./market";
import { houseName, marketHouses, readLadder, readSite } from "./marketCollector";
import { iconUrl, loadItemInfo, QUALITY_COLOR, type ItemInfo } from "./marketItems";
import { VENDOR_SUPPLIES } from "./marketVendor";
import { supabase } from "./supabase";

export const AH_CUT = 0.05;

export type Speed = "fast" | "steady" | "slow" | "rarely";

export const SPEED_TEXT: Record<Speed, string> = {
  fast: "Sells fast",
  steady: "Sells steadily",
  slow: "Sells slowly",
  rarely: "Rarely sells",
};

export type Row = {
  id: number;
  name: string;
  quality: string;
  color: string;
  icon: string | null;
  cls: string;
  sub: string;
  vendor: number; // what a vendor pays for one (0 = nothing)
  vendorSure: boolean; // vendor price is from Forever's own data
  perDay: number; // sold per day (an upper estimate)
  through: number; // % of listings that sell, -1 = not enough data
  avgSold: number; // average price it actually sold for, each
  min: number; // cheapest buyout now
  listed: number;
  posts: number; // new listings per day
  mkt: number; // market price now (cheapest 15% of what's listed)
  speed: Speed | null;
  goldPerDay: number; // perDay * avgSold
};

export type Market = {
  house: number;
  houseName: string;
  houses: { id: number; name: string }[];
  snapT: number;
  hours: number;
  site: SiteData;
  ladder: Ladder;
  info: Record<string, ItemInfo>;
};

export async function getMarket(houseParam?: string | number | null): Promise<Market | null> {
  const houses = marketHouses();
  const want = Number(houseParam);
  const house = houses.includes(want) ? want : houses[0];
  if (!house) return null;
  const [site, ladder, info] = await Promise.all([readSite(house), readLadder(house), loadItemInfo()]);
  if (!site) return null;
  return {
    house,
    houseName: houseName(house),
    houses: houses.map((id) => ({ id, name: houseName(id) })),
    snapT: site.snapT,
    hours: site.hours,
    site,
    ladder: ladder ?? {},
    info: info.items,
  };
}

// Same thresholds as the addon's ns.SaleSpeed (addon/ForeverGold/Market.lua):
// fast sellers show within hours; calling something slow needs days.
export function saleSpeed(through: number, perDay: number, listed: number, hours: number): Speed | null {
  if (hours < 6) return null;
  if (through >= 60 || perDay >= 25) return "fast";
  if (hours < 24) return null;
  if (through >= 35 || perDay >= 5) return "steady";
  if (through >= 15 || perDay >= 0.5) return "slow";
  if (hours >= 48 && (through >= 0 || (perDay === 0 && listed > 0 && hours >= 72))) return "rarely";
  return null;
}

export function itemBasics(m: Market, id: number) {
  const inf = m.info[id];
  const quality = inf?.[1] || "COMMON";
  return {
    id,
    name: (inf?.[0] && !/^Item \d+$/.test(inf[0]) ? inf[0] : madeBy.get(id)?.[0]?.name) || `Item ${id}`,
    quality,
    color: QUALITY_COLOR[quality] ?? "#ffffff",
    icon: iconUrl(inf?.[5]),
    cls: inf?.[2] ?? "",
    sub: inf?.[3] ?? "",
    vendor: inf?.[4] ?? 0,
    vendorSure: inf?.[6] === 1,
  };
}

export function rowFor(m: Market, id: number): Row {
  const s = m.site.items[id];
  const r = s?.r ?? [0, -1, 0, 0, 0, 0];
  const [perDay, through, avgSold, min, listed, posts] = r;
  return {
    ...itemBasics(m, id),
    perDay,
    through,
    avgSold,
    min,
    listed,
    posts,
    mkt: s?.mkt ?? 0,
    speed: saleSpeed(through, perDay, listed, m.hours),
    goldPerDay: Math.round(perDay * avgSold),
  };
}

function allRows(m: Market): Row[] {
  return Object.keys(m.site.items).map((id) => rowFor(m, Number(id)));
}

// Item classes that are on the auction house right now, most items first.
export function categories(m: Market): { name: string; count: number }[] {
  const counts = new Map<string, number>();
  for (const id of Object.keys(m.site.items)) {
    const cls = m.info[id]?.[2] || "Other";
    counts.set(cls, (counts.get(cls) ?? 0) + 1);
  }
  return [...counts].map(([name, count]) => ({ name, count })).sort((a, b) => b.count - a.count);
}

const matchesCls = (row: Row, cls?: string | null) => !cls || (row.cls || "Other") === cls;

export function searchItems(m: Market, q: string, cls?: string | null, limit = 60): Row[] {
  const needle = q.trim().toLowerCase();
  const rows = allRows(m).filter((r) => matchesCls(r, cls) && (!needle || r.name.toLowerCase().includes(needle)));
  rows.sort((a, b) => {
    if (needle) {
      // Exact and starts-with matches first.
      const ra = a.name.toLowerCase() === needle ? 0 : a.name.toLowerCase().startsWith(needle) ? 1 : 2;
      const rb = b.name.toLowerCase() === needle ? 0 : b.name.toLowerCase().startsWith(needle) ? 1 : 2;
      if (ra !== rb) return ra - rb;
    }
    return b.goldPerDay - a.goldPerDay || b.listed - a.listed;
  });
  return rows.slice(0, limit);
}

export type BestSort = "gold" | "units" | "through";

export function bestSellers(m: Market, cls?: string | null, sort: BestSort = "gold", limit = 100): Row[] {
  const rows = allRows(m).filter((r) => matchesCls(r, cls) && r.perDay > 0 && r.avgSold > 0);
  const key: Record<BestSort, (r: Row) => number> = {
    gold: (r) => r.goldPerDay,
    units: (r) => r.perDay,
    through: (r) => (r.through < 0 ? -1 : r.through * 1e6 + r.goldPerDay),
  };
  rows.sort((a, b) => key[sort](b) - key[sort](a));
  return rows.slice(0, limit);
}

// ---------------------------------------------------------------------
// Deals
// ---------------------------------------------------------------------

export type FlipDeal = {
  row: Row;
  qty: number; // how many to buy
  cost: number; // what they cost together
  maxEach: number; // the dearest one you'd be buying
  resellEach: number; // what it usually sells for
  profit: number; // after the 5% cut
};

export type VendorDeal = { row: Row; qty: number; cost: number; vendorTotal: number; profit: number };

// Listings priced well under what an item usually sells for. Only items
// that sell fast or steadily, and never more than about a day's worth of
// sales, so you're not left holding a pile.
const FLIP_SHARE = 0.7;
const FLIP_MIN_PROFIT = 5000; // 50 silver

export function flipDeals(m: Market, limit = 60): FlipDeal[] {
  if (m.hours < 12) return [];
  const out: FlipDeal[] = [];
  for (const id of Object.keys(m.site.items)) {
    const row = rowFor(m, Number(id));
    if (!(row.speed === "fast" || row.speed === "steady") || row.avgSold <= 0) continue;
    const limitQty = Math.max(1, Math.floor(row.perDay));
    const ceiling = row.avgSold * FLIP_SHARE;
    let qty = 0;
    let cost = 0;
    let maxEach = 0;
    for (const [price, q] of m.ladder[id] ?? []) {
      if (price <= 0 || price > ceiling || qty >= limitQty) break;
      const take = Math.min(q, limitQty - qty);
      qty += take;
      cost += take * price;
      maxEach = price;
    }
    if (qty === 0) continue;
    const profit = Math.round(qty * row.avgSold * (1 - AH_CUT) - cost);
    if (profit < FLIP_MIN_PROFIT) continue;
    out.push({ row, qty, cost, maxEach, resellEach: row.avgSold, profit });
  }
  return out.sort((a, b) => b.profit - a.profit).slice(0, limit);
}

// Listings cheaper than a vendor pays for them: buy, walk to a vendor, sell.
export function vendorDeals(m: Market, limit = 60): VendorDeal[] {
  const out: VendorDeal[] = [];
  for (const id of Object.keys(m.ladder)) {
    const b = itemBasics(m, Number(id));
    if (b.vendor <= 0) continue;
    let qty = 0;
    let cost = 0;
    for (const [price, q] of m.ladder[id]) {
      if (price <= 0 || price >= b.vendor) break;
      qty += q;
      cost += price * q;
    }
    if (qty === 0) continue;
    const vendorTotal = qty * b.vendor;
    const profit = vendorTotal - cost;
    if (profit < 100) continue;
    out.push({ row: rowFor(m, Number(id)), qty, cost, vendorTotal, profit });
  }
  return out.sort((a, b) => b.profit - a.profit).slice(0, limit);
}

// ---------------------------------------------------------------------
// Movers: price now against the item's own recent average
// ---------------------------------------------------------------------

export type Mover = { row: Row; now: number; usual: number; change: number; days: number };
export type VolumeMover = { row: Row; lastDay: number; usual: number; ratio: number };

const today = () => Math.floor(Date.now() / 86400000);

export function moverDays(m: Market): number {
  return m.site.days.filter((d) => d < today()).length;
}

export function priceMovers(m: Market, limit = 25): { up: Mover[]; down: Mover[] } {
  const up: Mover[] = [];
  const down: Mover[] = [];
  const t = today();
  for (const [id, s] of Object.entries(m.site.items)) {
    if (!s.mkt) continue;
    const past = s.h.filter((h) => h[H_DAY] < t && h[H_MKT] > 0);
    if (past.length < 2) continue;
    const usual = past.reduce((n, h) => n + h[H_MKT], 0) / past.length;
    if (usual < 50) continue;
    const row = rowFor(m, Number(id));
    // Ignore things nobody really trades - one listing can swing those.
    if (row.listed < 5 && row.perDay < 3) continue;
    const change = s.mkt / usual - 1;
    const mv = { row, now: s.mkt, usual: Math.round(usual), change, days: past.length };
    if (change >= 0.2) up.push(mv);
    else if (change <= -0.2) down.push(mv);
  }
  up.sort((a, b) => b.change - a.change);
  down.sort((a, b) => a.change - b.change);
  return { up: up.slice(0, limit), down: down.slice(0, limit) };
}

export function volumeMovers(m: Market, limit = 25): VolumeMover[] {
  const t = today();
  const days = m.site.days;
  const cover = new Map(days.map((d, i) => [d, m.site.cover[i]]));
  const out: VolumeMover[] = [];
  for (const [id, s] of Object.entries(m.site.items)) {
    // Whole days that were watched for most of the day only.
    const full = s.h.filter((h) => h[H_DAY] < t && (cover.get(h[H_DAY]) ?? 0) >= 0.75);
    if (full.length < 3) continue;
    const last = full[full.length - 1];
    const before = full.slice(0, -1);
    const usual = before.reduce((n, h) => n + h[H_SOLD], 0) / before.length;
    if (usual < 5) continue;
    const ratio = last[H_SOLD] / usual;
    if (ratio < 2) continue;
    out.push({ row: rowFor(m, Number(id)), lastDay: last[H_SOLD], usual: Math.round(usual), ratio });
  }
  return out.sort((a, b) => b.ratio - a.ratio).slice(0, limit);
}

// ---------------------------------------------------------------------
// Recipes and crafting
// ---------------------------------------------------------------------

export type Recipe = {
  id: number;
  name: string;
  prof: string;
  category: string;
  item: number | null;
  qty: [number, number];
  reagents: [number, number][];
};

const RECIPES = (recipeData as unknown as { recipes: Recipe[] }).recipes;
export const PROFESSIONS = (recipeData as unknown as { professions: string[] }).professions;

const usedIn = new Map<number, Recipe[]>();
const madeBy = new Map<number, Recipe[]>();
for (const r of RECIPES) {
  for (const [rid] of r.reagents) {
    const l = usedIn.get(rid);
    if (l) l.push(r);
    else usedIn.set(rid, [r]);
  }
  if (r.item) {
    const l = madeBy.get(r.item);
    if (l) l.push(r);
    else madeBy.set(r.item, [r]);
  }
}

export const recipesUsing = (id: number) => usedIn.get(id) ?? [];
export const recipesMaking = (id: number) => madeBy.get(id) ?? [];
export const recipeById = (id: number) => RECIPES.find((r) => r.id === id) ?? null;

// Who among the site's (non-hidden) characters knows each recipe, by
// "Profession|Recipe name" - the game's recipe ids aren't the web API's.
export type Crafter = { character: string; owner: string | null };
let crafterCache: { at: number; map: Map<string, Crafter[]> } | null = null;

type ProfRow = { profession: string; recipes: (string | { name?: string })[] | null };
type CharRow = {
  name: string;
  profiles: { display_name?: string } | null;
  character_professions: ProfRow[] | null;
};

export async function crafters(): Promise<Map<string, Crafter[]>> {
  if (crafterCache && Date.now() - crafterCache.at < 5 * 60 * 1000) return crafterCache.map;
  const map = new Map<string, Crafter[]>();
  const { data } = await supabase
    .from("characters")
    .select("name, profiles!user_id(display_name), character_professions(profession, recipes)")
    .eq("hidden", false);
  for (const c of (data ?? []) as unknown as CharRow[]) {
    for (const p of c.character_professions ?? []) {
      for (const r of p.recipes ?? []) {
        const name = typeof r === "string" ? r : r?.name;
        if (!name) continue;
        const key = `${p.profession}|${name}`.toLowerCase();
        const list = map.get(key) ?? [];
        if (!list.some((x) => x.character === c.name)) list.push({ character: c.name, owner: c.profiles?.display_name ?? null });
        map.set(key, list);
      }
    }
  }
  crafterCache = { at: Date.now(), map };
  return map;
}

export const crafterKey = (r: Recipe) => `${r.prof}|${r.name}`.toLowerCase();

// Cheapest way to buy one of something right now.
export type Buy = { each: number; from: "vendor" | "ah" | null };

export function buyPrice(m: Market, id: number): Buy {
  const vendor = VENDOR_SUPPLIES[id];
  const s = m.site.items[id];
  const ah = s ? s.mkt || s.r[3] : 0;
  if (vendor && (!ah || vendor <= ah)) return { each: vendor, from: "vendor" };
  if (ah) return { each: ah, from: "ah" };
  return { each: 0, from: null };
}

export type CraftLine = {
  recipe: Recipe;
  made: Row;
  yieldAvg: number;
  cost: number | null; // materials for ONE crafted item (null = something can't be bought)
  missing: number[]; // reagent ids with no price
  parts: { id: number; qty: number; each: number; from: Buy["from"] }[];
  sellEach: number; // what one sells for
  sellFrom: "sold" | "listed" | null;
  profit: number | null; // per item, after the 5% cut
  crafters: Crafter[];
};

export function craftLine(m: Market, r: Recipe, who: Map<string, Crafter[]>): CraftLine | null {
  if (!r.item) return null;
  const made = rowFor(m, r.item);
  const yieldAvg = Math.max(1, (r.qty[0] + r.qty[1]) / 2);
  let total = 0;
  const missing: number[] = [];
  const parts: CraftLine["parts"] = [];
  for (const [id, qty] of r.reagents) {
    const b = buyPrice(m, id);
    if (!b.from) missing.push(id);
    total += b.each * qty;
    parts.push({ id, qty, each: b.each, from: b.from });
  }
  const cost = missing.length ? null : total / yieldAvg;
  const sellEach = made.avgSold > 0 && made.speed !== "rarely" ? Math.min(made.avgSold, made.mkt || made.avgSold) : made.mkt;
  const sellFrom = made.avgSold > 0 && made.speed !== "rarely" ? "sold" : made.mkt ? "listed" : null;
  const profit = cost !== null && sellEach > 0 ? Math.round(sellEach * (1 - AH_CUT) - cost) : null;
  return { recipe: r, made, yieldAvg, cost, missing, parts, sellEach, sellFrom, profit, crafters: who.get(crafterKey(r)) ?? [] };
}

export type CraftSort = "profit" | "gold";

export async function craftProfits(
  m: Market,
  opts: { prof?: string | null; known?: boolean; sort?: CraftSort; limit?: number } = {}
): Promise<CraftLine[]> {
  const who = await crafters();
  const out: CraftLine[] = [];
  for (const r of RECIPES) {
    if (opts.prof && r.prof !== opts.prof) continue;
    const line = craftLine(m, r, who);
    if (!line || line.profit === null || line.sellFrom === null) continue;
    if (opts.known && line.crafters.length === 0) continue;
    out.push(line);
  }
  // "gold": profit you could realistically make in a day = profit x how
  // many sell a day (capped), which favours things that actually move.
  const daily = (l: CraftLine) => (l.profit ?? 0) * Math.min(20, Math.max(0.2, l.made.perDay));
  out.sort((a, b) => (opts.sort === "gold" ? daily(b) - daily(a) : (b.profit ?? 0) - (a.profit ?? 0)));
  return out.slice(0, opts.limit ?? 150);
}

// ---------------------------------------------------------------------
// One item
// ---------------------------------------------------------------------

export type ItemDetail = {
  row: Row;
  history: HistDay[];
  ladder: LadderRow[];
  usedIn: Recipe[];
  makes: CraftLine[];
};

export async function itemDetail(m: Market, id: number): Promise<ItemDetail> {
  const who = await crafters();
  return {
    row: rowFor(m, id),
    history: m.site.items[id]?.h ?? [],
    ladder: m.ladder[id] ?? [],
    usedIn: recipesUsing(id),
    makes: recipesMaking(id)
      .map((r) => craftLine(m, r, who))
      .filter((l): l is CraftLine => l !== null),
  };
}

// For the shopping list: how much `qty` of an item costs bought from the
// cheapest listings up, or from a vendor.
export function costToBuy(m: Market, id: number, qty: number): { cost: number; got: number; from: "vendor" | "ah" | "mixed" | null; dearest: number } {
  const vendor = VENDOR_SUPPLIES[id];
  let got = 0;
  let cost = 0;
  let dearest = 0;
  for (const [price, q] of m.ladder[id] ?? []) {
    if (price <= 0 || got >= qty) break;
    if (vendor && price >= vendor) break;
    const take = Math.min(q, qty - got);
    got += take;
    cost += take * price;
    dearest = price;
  }
  if (got < qty && vendor) {
    cost += (qty - got) * vendor;
    return { cost, got: qty, from: got > 0 ? "mixed" : "vendor", dearest: vendor };
  }
  return { cost, got, from: got > 0 ? "ah" : null, dearest };
}

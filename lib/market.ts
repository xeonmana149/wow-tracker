// Auction house sale-rate tracking for WoW Forever, built from Blizzard's
// hourly auction snapshots (Game Data API, dynamic-forever namespace).
//
// The snapshots only show what is listed right now - never what sold - so
// sales are worked out by comparing each snapshot with the one before it,
// auction by auction (every auction has a stable id):
//
//   * gone while it still had plenty of time left  -> bought (or cancelled)
//   * gone from the "under 30 minutes left" bucket   -> expired unsold
//   * same id, smaller quantity                      -> part of it was bought
//   * gone early, but an identical stack of the same item appeared at the
//     same or a lower price                         -> cancelled and reposted
//     (an undercut), so it is NOT counted as a sale
//
// Anything that can't be told apart (gone while in the 30min-2h bucket, or
// after a long gap between snapshots) is left out rather than guessed.
//
// This file is pure logic with no imports, so the same code runs in the
// /api/market route and in the offline test script.

export const KEEP_DAYS = 14;
// Snapshots further apart than this (the collector was idle, or Blizzard
// skipped an hour) only resync the auction list - nothing is counted, and
// the gap isn't added to the time the rates are based on.
export const MAX_GAP = 150 * 60;

// time_left buckets, smallest first, and the least time each one can mean.
const TIME_LEFT = ["SHORT", "MEDIUM", "LONG", "VERY_LONG"];
const MIN_REMAINING = [0, 30 * 60, 2 * 3600, 12 * 3600];

// Per item per day:
// [posted auctions, posted qty, sold auctions, sold qty, sold value (copper),
//  expired auctions, expired qty, cancelled-and-reposted auctions]
export type DayCounts = number[];
const POST_N = 0, POST_Q = 1, SOLD_N = 2, SOLD_Q = 3, SOLD_V = 4, EXP_N = 5, EXP_Q = 6, CANC_N = 7;

export type Listing = {
  id: number;
  item: number;
  qty: number;
  price: number; // copper for ONE item; 0 = bid-only, no buyout
  tl: number; // index into TIME_LEFT
};

// Column arrays keep the saved state small (it's ~250k auctions per house).
export type AuctionColumns = {
  id: number[];
  item: number[];
  qty: number[];
  price: number[];
  tl: number[];
};

// Per item per day, from every snapshot seen that day (sales or not):
// [snapshots, sum of cheapest buyout, lowest buyout seen, sum of market
//  price, sum of quantity listed]. Averages = sum / snapshots.
export type PriceDay = number[];
const PX_N = 0, PX_MIN = 1, PX_LOW = 2, PX_MKT = 3, PX_QTY = 4;

export type HouseDay = { cov: number; items: Record<string, DayCounts>; px?: Record<string, PriceDay> };

export type HouseState = {
  v: 1;
  house: number;
  snapT: number; // unix seconds of the snapshot this state was built from
  a: AuctionColumns;
  // day number (unix days) -> covered seconds + per-item counts + prices
  days: Record<string, HouseDay>;
  last?: { gap: number; counted: boolean; posted: number; sold: number; expired: number; cancelled: number };
};

type RawAuction = {
  id: number;
  item?: { id?: number };
  quantity?: number;
  unit_price?: number;
  buyout?: number;
  time_left?: string;
};

// Turns the two API responses (gear + commodities) into one flat list.
export function parseSnapshot(gear: { auctions?: RawAuction[] } | null, commodities: { auctions?: RawAuction[] } | null): Listing[] {
  const out: Listing[] = [];
  for (const body of [gear, commodities]) {
    for (const a of body?.auctions ?? []) {
      const item = a.item?.id;
      if (!item || !a.id) continue;
      const qty = Math.max(1, a.quantity ?? 1);
      let price = 0;
      if (typeof a.unit_price === "number") price = a.unit_price;
      else if (typeof a.buyout === "number") price = Math.round(a.buyout / qty);
      const tl = Math.max(0, TIME_LEFT.indexOf(a.time_left ?? ""));
      out.push({ id: a.id, item, qty, price, tl });
    }
  }
  return out;
}

function toColumns(list: Listing[]): AuctionColumns {
  const c: AuctionColumns = { id: [], item: [], qty: [], price: [], tl: [] };
  for (const l of list) {
    c.id.push(l.id);
    c.item.push(l.item);
    c.qty.push(l.qty);
    c.price.push(l.price);
    c.tl.push(l.tl);
  }
  return c;
}

function bump(day: { items: Record<string, DayCounts> }, item: number, field: number, by: number) {
  let row = day.items[item];
  if (!row) {
    row = [0, 0, 0, 0, 0, 0, 0, 0];
    day.items[item] = row;
  }
  row[field] += by;
}

// "Market price" of one snapshot: the average price of the cheapest 15% of
// what's listed (at least one item). Steadier than the single cheapest
// listing, which one silly undercut can drag around.
const MARKET_SHARE = 0.15;

type ItemNow = { min: number; qty: number; mkt: number };

// Cheapest buyout, quantity listed and market price for every item in a
// snapshot. Bid-only auctions (price 0) count toward quantity only.
export function summarizeListings(a: AuctionColumns): Map<number, ItemNow> {
  const levels = new Map<number, [number, number][]>(); // item -> [price, qty][]
  const out = new Map<number, ItemNow>();
  for (let i = 0; i < a.id.length; i++) {
    const item = a.item[i];
    let n = out.get(item);
    if (!n) {
      n = { min: 0, qty: 0, mkt: 0 };
      out.set(item, n);
    }
    n.qty += a.qty[i];
    const price = a.price[i];
    if (price > 0) {
      if (n.min === 0 || price < n.min) n.min = price;
      const l = levels.get(item);
      if (l) l.push([price, a.qty[i]]);
      else levels.set(item, [[price, a.qty[i]]]);
    }
  }
  for (const [item, l] of levels) {
    l.sort((x, y) => x[0] - y[0]);
    let total = 0;
    for (const [, q] of l) total += q;
    const want = Math.max(1, Math.ceil(total * MARKET_SHARE));
    let got = 0;
    let value = 0;
    for (const [price, q] of l) {
      const take = Math.min(q, want - got);
      got += take;
      value += take * price;
      if (got >= want) break;
    }
    out.get(item)!.mkt = Math.round(value / got);
  }
  return out;
}

function recordPrices(day: HouseDay, a: AuctionColumns) {
  const px = day.px ?? (day.px = {});
  for (const [item, n] of summarizeListings(a)) {
    let row = px[item];
    if (!row) {
      row = [0, 0, 0, 0, 0];
      px[item] = row;
    }
    row[PX_N] += 1;
    row[PX_QTY] += n.qty;
    if (n.min > 0) {
      row[PX_MIN] += n.min;
      row[PX_MKT] += n.mkt;
      if (row[PX_LOW] === 0 || n.min < row[PX_LOW]) row[PX_LOW] = n.min;
    }
  }
}

// Folds one new snapshot into the house's state. Deterministic: the same
// (state, snapshot) always gives the same result, so two callers racing on
// the same snapshot just write identical files.
export function applySnapshot(prev: HouseState | null, house: number, snapT: number, list: Listing[]): HouseState {
  if (!prev || prev.house !== house) {
    const a = toColumns(list);
    const day: HouseDay = { cov: 0, items: {} };
    recordPrices(day, a);
    return {
      v: 1,
      house,
      snapT,
      a,
      days: { [String(Math.floor(snapT / 86400))]: day },
      last: { gap: 0, counted: false, posted: 0, sold: 0, expired: 0, cancelled: 0 },
    };
  }
  if (snapT <= prev.snapT) return prev;

  const gap = snapT - prev.snapT;
  const days = prev.days;
  const counted = gap <= MAX_GAP;
  const stats = { gap, counted, posted: 0, sold: 0, expired: 0, cancelled: 0 };

  if (counted) {
    const dayKey = String(Math.floor(snapT / 86400));
    const day = days[dayKey] ?? (days[dayKey] = { cov: 0, items: {} });
    day.cov += gap;

    const p = prev.a;
    const prevIndex = new Map<number, number>();
    for (let i = 0; i < p.id.length; i++) prevIndex.set(p.id[i], i);

    // New auctions this hour, by item, for spotting cancel-and-repost.
    const fresh = new Map<number, Listing[]>();
    const stillHere = new Set<number>();
    for (const l of list) {
      const i = prevIndex.get(l.id);
      if (i === undefined) {
        bump(day, l.item, POST_N, 1);
        bump(day, l.item, POST_Q, l.qty);
        stats.posted++;
        const arr = fresh.get(l.item);
        if (arr) arr.push(l);
        else fresh.set(l.item, [l]);
      } else {
        stillHere.add(l.id);
        const boughtPart = p.qty[i] - l.qty;
        if (boughtPart > 0 && p.price[i] > 0) {
          bump(day, l.item, SOLD_Q, boughtPart);
          bump(day, l.item, SOLD_V, boughtPart * p.price[i]);
        }
      }
    }
    // Same order every time, so reposts are matched deterministically.
    for (const arr of fresh.values()) arr.sort((x, y) => x.price - y.price || x.id - y.id);

    for (let i = 0; i < p.id.length; i++) {
      if (stillHere.has(p.id[i])) continue;
      const item = p.item[i], qty = p.qty[i], price = p.price[i], tl = p.tl[i];
      if (gap < MIN_REMAINING[tl]) {
        // Left early. A fresh identical stack at the same or lower price
        // is almost always the same seller undercutting.
        const arr = fresh.get(item);
        const k = arr ? arr.findIndex((l) => l.qty === qty && l.price <= price) : -1;
        if (arr && k >= 0) {
          arr.splice(k, 1);
          bump(day, item, CANC_N, 1);
          stats.cancelled++;
        } else if (price > 0) {
          bump(day, item, SOLD_N, 1);
          bump(day, item, SOLD_Q, qty);
          bump(day, item, SOLD_V, qty * price);
          stats.sold++;
        }
      } else if (tl === 0) {
        bump(day, item, EXP_N, 1);
        bump(day, item, EXP_Q, qty);
        stats.expired++;
      }
      // else: can't tell whether it sold or ran out - leave it out.
    }
  }

  // Prices are recorded for every snapshot, even one after a long gap.
  const a = toColumns(list);
  const todayKey = String(Math.floor(snapT / 86400));
  const today = days[todayKey] ?? (days[todayKey] = { cov: 0, items: {} });
  recordPrices(today, a);

  const oldest = Math.floor(snapT / 86400) - KEEP_DAYS;
  for (const k of Object.keys(days)) {
    if (Number(k) < oldest) delete days[k];
  }
  return { v: 1, house, snapT, a, days, last: stats };
}

// What the game gets, per item:
// [sold per day (qty), sell-through % (-1 = not enough data),
//  average price it actually sold at (copper each, 0 = none sold),
//  cheapest buyout right now (0 = none), quantity listed now,
//  new listings per day]
export type ItemRate = [number, number, number, number, number, number];

export type HouseRates = {
  house: number;
  snapT: number;
  hours: number; // how many hours of snapshots the rates are based on
  items: Record<string, ItemRate>;
};

const round1 = (n: number) => Math.round(n * 10) / 10;

export function computeRates(state: HouseState): HouseRates {
  let cov = 0;
  const tot = new Map<string, DayCounts>();
  for (const day of Object.values(state.days)) {
    cov += day.cov;
    for (const [item, row] of Object.entries(day.items)) {
      const t = tot.get(item);
      if (!t) tot.set(item, row.slice());
      else for (let f = 0; f < row.length; f++) t[f] += row[f];
    }
  }
  const covDays = cov / 86400;

  const now = new Map<string, { min: number; qty: number }>();
  const a = state.a;
  for (let i = 0; i < a.id.length; i++) {
    const key = String(a.item[i]);
    let n = now.get(key);
    if (!n) {
      n = { min: 0, qty: 0 };
      now.set(key, n);
    }
    n.qty += a.qty[i];
    if (a.price[i] > 0 && (n.min === 0 || a.price[i] < n.min)) n.min = a.price[i];
  }

  const items: Record<string, ItemRate> = {};
  const keys = new Set<string>([...tot.keys(), ...now.keys()]);
  for (const key of keys) {
    const t = tot.get(key) ?? [0, 0, 0, 0, 0, 0, 0, 0];
    const n = now.get(key) ?? { min: 0, qty: 0 };
    const finished = t[SOLD_Q] + t[EXP_Q];
    const through = finished >= 3 && t[SOLD_N] + t[EXP_N] >= 2 ? Math.round((100 * t[SOLD_Q]) / finished) : -1;
    items[key] = [
      covDays > 0 ? round1(t[SOLD_Q] / covDays) : 0,
      through,
      t[SOLD_Q] > 0 ? Math.round(t[SOLD_V] / t[SOLD_Q]) : 0,
      n.min,
      n.qty,
      covDays > 0 ? round1(t[POST_N] / covDays) : 0,
    ];
  }
  return { house: state.house, snapT: state.snapT, hours: Math.round(cov / 360) / 10, items };
}

// ---------------------------------------------------------------------
// What the website shows
// ---------------------------------------------------------------------

// One day of one item:
// [unix day, sold qty, avg sold price, avg cheapest buyout, lowest buyout,
//  avg market price, avg qty listed, new auctions, expired qty, reposts]
export type HistDay = number[];
export const H_DAY = 0;
export const H_SOLD = 1;
export const H_SOLDP = 2;
export const H_MIN = 3;
export const H_LOW = 4;
export const H_MKT = 5;
export const H_QTY = 6;
export const H_POSTS = 7;
export const H_EXP = 8;
export const H_REPOST = 9;

export type SiteItem = {
  r: ItemRate;
  mkt: number; // market price in the latest snapshot (0 = no buyouts listed)
  h: HistDay[]; // oldest first
};

export type SiteData = {
  v: 1;
  house: number;
  snapT: number;
  hours: number;
  days: number[]; // unix days covered, oldest first
  cover: number[]; // share of each day that was watched for sales (0..1)
  items: Record<string, SiteItem>;
};

export function computeSite(state: HouseState, rates: HouseRates = computeRates(state)): SiteData {
  const dayKeys = Object.keys(state.days).map(Number).sort((x, y) => x - y);
  const now = summarizeListings(state.a);
  const items: Record<string, SiteItem> = {};
  for (const [key, r] of Object.entries(rates.items)) {
    const h: HistDay[] = [];
    for (const d of dayKeys) {
      const day = state.days[String(d)];
      const c = day.items[key];
      const p = day.px?.[key];
      if (!c && !p) continue;
      const n = p ? p[PX_N] : 0;
      h.push([
        d,
        c ? c[SOLD_Q] : 0,
        c && c[SOLD_Q] > 0 ? Math.round(c[SOLD_V] / c[SOLD_Q]) : 0,
        p && n > 0 ? Math.round(p[PX_MIN] / n) : 0,
        p ? p[PX_LOW] : 0,
        p && n > 0 ? Math.round(p[PX_MKT] / n) : 0,
        p && n > 0 ? Math.round(p[PX_QTY] / n) : 0,
        c ? c[POST_N] : 0,
        c ? c[EXP_Q] : 0,
        c ? c[CANC_N] : 0,
      ]);
    }
    items[key] = { r, mkt: now.get(Number(key))?.mkt ?? 0, h };
  }
  return {
    v: 1,
    house: state.house,
    snapT: state.snapT,
    hours: rates.hours,
    days: dayKeys,
    cover: dayKeys.map((d) => Math.min(1, state.days[String(d)].cov / 86400)),
    items,
  };
}

// Everything listed right now, grouped by price, cheapest first:
// item -> [[price each, quantity, auctions], ...]. Price 0 = bid only (last).
export type LadderRow = [number, number, number];
export type Ladder = Record<string, LadderRow[]>;
export const LADDER_LEVELS = 40;

export function buildLadder(a: AuctionColumns, levels = LADDER_LEVELS): Ladder {
  const by = new Map<number, Map<number, LadderRow>>();
  for (let i = 0; i < a.id.length; i++) {
    let m = by.get(a.item[i]);
    if (!m) {
      m = new Map();
      by.set(a.item[i], m);
    }
    const price = a.price[i];
    const row = m.get(price);
    if (row) {
      row[1] += a.qty[i];
      row[2] += 1;
    } else m.set(price, [price, a.qty[i], 1]);
  }
  const out: Ladder = {};
  for (const [item, m] of by) {
    const rows = [...m.values()].sort((x, y) => (x[0] === 0 ? 1 : y[0] === 0 ? -1 : x[0] - y[0]));
    out[item] = rows.slice(0, levels);
  }
  return out;
}

import { NextRequest, NextResponse } from "next/server";
import { marketHouses, readAuctionIndex } from "../../../../lib/marketCollector";
import { getMarket, itemBasics, type Market } from "../../../../lib/marketView";
import { readUser, totalGoldSeries, type CharInfo } from "../../../../lib/marketUser";
import { supabaseAdmin } from "../../../../lib/supabaseAdmin";

// The signed-in visitor's own Forever Gold data, checked against the latest
// auction snapshot: which of their auctions have been undercut, their gold
// over time, and their farming trips. Needs the visitor's Supabase session
// token (Authorization: Bearer <access token>).

type Status = "sold" | "gone" | "undercut" | "tied" | "cheapest" | "unknown";

export async function GET(req: NextRequest) {
  const jwt = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!jwt) return NextResponse.json({ error: "Not signed in" }, { status: 401 });
  const { data: auth } = await supabaseAdmin.auth.getUser(jwt);
  const userId = auth?.user?.id;
  if (!userId) return NextResponse.json({ error: "Not signed in" }, { status: 401 });

  const f = await readUser(userId);
  if (!f) return NextResponse.json({ empty: true }, { headers: { "Cache-Control": "no-store" } });

  const markets = new Map<number, Market | null>();
  const indexes = new Map<number, Awaited<ReturnType<typeof readAuctionIndex>>>();
  const houseFor = (c: CharInfo) => (c.house && marketHouses().includes(c.house) ? c.house : marketHouses()[0]);

  const auctions = [];
  for (const c of Object.values(f.chars)) {
    const list = c.auctions?.list ?? [];
    if (list.length === 0) continue;
    const house = houseFor(c);
    if (!markets.has(house)) markets.set(house, await getMarket(house));
    if (!indexes.has(house)) indexes.set(house, await readAuctionIndex(house));
    const m = markets.get(house);
    const idx = indexes.get(house);
    if (!m) continue;
    const snapNewer = (idx?.snapT ?? m.snapT) > (c.auctions?.t ?? 0);
    // Do the game's auction ids line up with Blizzard's web data? If none
    // of this character's active auctions can be found, don't call them gone.
    const active = list.filter((a) => a.st === 0);
    const anyFound = active.some((a) => idx?.ids.has(a.id));

    for (const a of list) {
      const inSnap = idx?.ids.get(a.id);
      // Exact price from the snapshot when we can find the auction;
      // otherwise the addon's buyout, treated as the price of one item
      // (and of the whole stack if that matches a listing better).
      let each = inSnap ? inSnap[0] : a.b;
      if (!inSnap && a.q > 1 && a.b > 0) {
        const perItem = Math.round(a.b / a.q);
        if ((m.ladder[a.item] ?? []).some(([p]) => p === perItem)) each = perItem;
      }
      let status: Status;
      let cheaperQty = 0;
      let cheaperAuctions = 0;
      let cheapest = 0;
      for (const [p, q, n] of m.ladder[a.item] ?? []) {
        if (p <= 0) continue;
        if (!cheapest) cheapest = p;
        if (p < each) {
          cheaperQty += q;
          cheaperAuctions += n;
        }
      }
      if (a.st === 1) status = "sold";
      else if (snapNewer && anyFound && !inSnap) status = "gone";
      else if (!each) status = "unknown";
      else if (cheaperQty > 0) status = "undercut";
      else {
        const same = (m.ladder[a.item] ?? []).find(([p]) => p === each);
        const others = same ? same[2] - (inSnap ? 1 : 0) : 0;
        status = others > 0 ? "tied" : "cheapest";
      }
      auctions.push({
        char: c.name,
        house,
        at: c.auctions?.t ?? 0,
        snapT: idx?.snapT ?? m.snapT,
        id: a.id,
        item: itemBasics(m, a.item),
        qty: a.q,
        each,
        status,
        cheapest,
        cheaperQty,
        cheaperAuctions,
        matched: Boolean(inSnap),
      });
    }
  }
  const order: Record<Status, number> = { undercut: 0, tied: 1, sold: 2, gone: 3, cheapest: 4, unknown: 5 };
  auctions.sort((a, b) => order[a.status] - order[b.status] || a.item.name.localeCompare(b.item.name));

  // Farming trips, plus totals by zone.
  const anyMarket = markets.values().next().value ?? (await getMarket(marketHouses()[0]));
  const sessions = f.sessions.slice(0, 100).map((s) => ({
    ...s,
    top: (s.top ?? []).map(([id, n]) => ({ n, item: anyMarket ? itemBasics(anyMarket, id) : { id, name: `Item ${id}`, color: "#fff", icon: null } })),
  }));
  const zones = new Map<string, { zone: string; trips: number; secs: number; made: number }>();
  for (const s of f.sessions) {
    const z = s.zone || "Unknown";
    const e = zones.get(z) ?? { zone: z, trips: 0, secs: 0, made: 0 };
    e.trips++;
    e.secs += s.secs;
    e.made += s.v;
    zones.set(z, e);
  }
  const byZone = [...zones.values()]
    .map((z) => ({ ...z, perHour: z.secs > 0 ? Math.round((z.made / z.secs) * 3600) : 0 }))
    .sort((a, b) => b.perHour - a.perHour);

  const chars = Object.values(f.chars)
    .map((c) => ({ name: c.name, faction: c.faction, level: c.level, class: c.class, money: c.money, seen: c.seen }))
    .sort((a, b) => b.money - a.money);

  return NextResponse.json(
    {
      updated: f.updated,
      chars,
      auctions,
      gold: totalGoldSeries(f),
      // Each character's own series, for the chart's per-character views.
      goldByChar: Object.fromEntries(chars.map((c) => [c.name, f.gold[c.name] ?? []])),
      sessions,
      byZone,
    },
    { headers: { "Cache-Control": "no-store" } }
  );
}

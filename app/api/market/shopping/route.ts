import { NextRequest, NextResponse } from "next/server";
import { AH_CUT, costToBuy, getMarket, itemBasics, recipeById, rowFor } from "../../../../lib/marketView";

// Prices a shopping list: crafts (recipe x how many times) and plain items.
// The list itself lives in the visitor's browser; this only does the maths
// against the latest snapshot, buying from the cheapest listings up.
//
// POST { house?, list: [{ kind: "recipe" | "item", id, n }] }

type Entry = { kind: "recipe" | "item"; id: number; n: number };

export async function POST(req: NextRequest) {
  let body: { house?: number; list?: Entry[] };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON" }, { status: 400 });
  }
  const m = await getMarket(body.house);
  if (!m) return NextResponse.json({ error: "No auction data yet" }, { status: 503 });

  const list = (Array.isArray(body.list) ? body.list : [])
    .filter((e) => e && (e.kind === "recipe" || e.kind === "item") && Number.isInteger(e.id) && e.n > 0)
    .slice(0, 100)
    .map((e) => ({ ...e, n: Math.min(1000, Math.floor(e.n)) }));

  const need = new Map<number, number>(); // item id -> quantity to buy
  const entries = list.map((e) => {
    if (e.kind === "recipe") {
      const r = recipeById(e.id);
      if (!r) return { ...e, name: `Recipe ${e.id}`, missing: true };
      for (const [rid, q] of r.reagents) need.set(rid, (need.get(rid) ?? 0) + q * e.n);
      const made = r.item ? rowFor(m, r.item) : null;
      const yieldAvg = Math.max(1, (r.qty[0] + r.qty[1]) / 2);
      const sellEach = made ? (made.avgSold > 0 && made.speed !== "rarely" ? Math.min(made.avgSold, made.mkt || made.avgSold) : made.mkt) : 0;
      return {
        ...e,
        name: r.name,
        prof: r.prof,
        made: made ? { id: made.id, name: made.name, color: made.color, icon: made.icon } : null,
        makes: Math.round(yieldAvg * e.n * 10) / 10,
        worth: Math.round(sellEach * (1 - AH_CUT) * yieldAvg * e.n),
      };
    }
    need.set(e.id, (need.get(e.id) ?? 0) + e.n);
    const b = itemBasics(m, e.id);
    return { ...e, name: b.name, made: { id: b.id, name: b.name, color: b.color, icon: b.icon } };
  });

  let total = 0;
  const buy = [...need].map(([id, qty]) => {
    const b = itemBasics(m, id);
    const c = costToBuy(m, id, qty);
    total += c.cost;
    return { id, name: b.name, color: b.color, icon: b.icon, qty, cost: c.cost, got: c.got, from: c.from, dearest: c.dearest };
  });
  buy.sort((a, b) => b.cost - a.cost);

  const worth = entries.reduce((n, e) => n + ("worth" in e && typeof e.worth === "number" ? e.worth : 0), 0);
  return NextResponse.json({ snapT: m.snapT, entries, buy, total, worth }, { headers: { "Cache-Control": "no-store" } });
}

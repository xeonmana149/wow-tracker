import { NextRequest, NextResponse } from "next/server";
import { collectHouse, marketHouses, readRates, MARKET_REGION, type CollectResult } from "../../../lib/marketCollector";
import { topUpItemInfo } from "../../../lib/marketItems";

// Auction house sale rates for the Forever Gold addon. Public on purpose:
// it's only auction data anyone can see in game, nothing account-specific.
//
// The tray app calls this about every 20 minutes and writes the answer
// into the addon's folder. Each call also collects Blizzard's newest
// snapshot when one is due (see lib/marketCollector.ts), so as long as
// anyone's tray app is running, the data keeps growing.
//
//   /api/market             collect if due, then return every tracked house
//   /api/market?collect=0   just return what's stored
export const maxDuration = 60;

export async function GET(req: NextRequest) {
  const collect = req.nextUrl.searchParams.get("collect") !== "0";
  const houses = marketHouses();

  const collected: CollectResult[] = [];
  if (collect) {
    // One at a time - each is a ~25 MB download and a big JSON parse.
    for (const h of houses) collected.push(await collectHouse(h));
  }

  const out = [];
  for (const h of houses) {
    const r = await readRates(h);
    if (r) out.push(r);
  }

  // ?names=500 looks up that many missing item names in one go (the
  // collector otherwise adds ~120 an hour). Only ever fills in public data.
  let named: number | undefined;
  const names = Number(req.nextUrl.searchParams.get("names"));
  if (names > 0) {
    const ids = [...new Set(out.flatMap((r) => Object.keys(r.items).map(Number)))];
    named = await topUpItemInfo(ids, Math.min(600, names), 12);
  }

  return NextResponse.json(
    { v: 1, region: MARKET_REGION, made: Math.floor(Date.now() / 1000), houses: out, collected, named },
    { headers: { "Cache-Control": "no-store" } }
  );
}

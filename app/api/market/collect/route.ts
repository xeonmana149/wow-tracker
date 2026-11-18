import { NextRequest, NextResponse } from "next/server";
import { collectHouse, marketHouses, type CollectResult } from "../../../../lib/marketCollector";

// Collects Blizzard's newest auction snapshot for every tracked house.
//
// Vercel's scheduler calls this every 20 minutes (the "market-collect"
// schedule in vercel.json), so the data keeps growing around the clock -
// not only while someone's tray app happens to be running. Blizzard puts
// out a snapshot about once an hour; most calls find nothing new and cost
// one 304 from Blizzard (see collectHouse).
//
// Collecting is harmless to repeat, and /api/market already does it for
// anyone, so this stays callable without a secret unless CRON_SECRET is
// set, in which case only Vercel's scheduler gets in.
export const maxDuration = 60;

export async function GET(req: NextRequest) {
  const secret = process.env.CRON_SECRET;
  if (secret && req.headers.get("authorization") !== `Bearer ${secret}`) {
    return new NextResponse("Unauthorized", { status: 401 });
  }

  const collected: CollectResult[] = [];
  // One at a time - each is a ~25 MB download and a big JSON parse.
  for (const h of marketHouses()) collected.push(await collectHouse(h));

  return NextResponse.json({ collected }, { headers: { "Cache-Control": "no-store" } });
}

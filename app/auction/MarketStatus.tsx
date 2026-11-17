import Link from "next/link";
import type { Market } from "../../lib/marketView";
import { ago, Empty } from "./ui";

// The "which house, how fresh, how much history" line at the top of every
// Auction House tab, plus a house picker when more than one is tracked.
export default function MarketStatus({ m, path }: { m: Market; path: string }) {
  const days = m.hours / 24;
  const span = days >= 2 ? `${Math.round(days)} days` : `${Math.round(m.hours)} hours`;
  return (
    <div className="mb-4 flex flex-wrap items-center gap-x-4 gap-y-2 text-sm text-gray-400">
      {m.houses.length > 1 ? (
        <span className="flex flex-wrap gap-1">
          {m.houses.map((h) => (
            <Link
              key={h.id}
              href={`${path}?house=${h.id}`}
              className={`rounded border px-2 py-0.5 text-xs ${h.id === m.house ? "border-amber-500/60 text-amber-200" : "border-neutral-700 text-gray-400 hover:text-gray-200"}`}
            >
              {h.name}
            </Link>
          ))}
        </span>
      ) : (
        <span className="font-semibold text-gray-300">{m.houseName}</span>
      )}
      <span>Snapshot {ago(m.snapT)}</span>
      <span>Sales watched for {span}</span>
      {m.hours < 24 && <span className="text-amber-300/80">Still collecting: speeds and deals get more reliable after a day or two.</span>}
    </div>
  );
}

export function NoMarket() {
  return (
    <Empty>
      No auction data yet. It starts collecting as soon as anyone&apos;s WoW Forever Tracker app is running
      (it checks for Blizzard&apos;s new snapshot about every 20 minutes).
    </Empty>
  );
}

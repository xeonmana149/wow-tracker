import Link from "next/link";
import { bestSellers, categories, getMarket, suspiciousPrice, type BestSort } from "../../../lib/marketView";
import MarketStatus, { NoMarket } from "../MarketStatus";
import { Empty, ItemLink, Money, perDayText, SpeedBadge, TD, TH, TR } from "../ui";

export const dynamic = "force-dynamic";

const SORTS: { id: BestSort; label: string }[] = [
  { id: "gold", label: "Most gold traded" },
  { id: "units", label: "Most sold" },
  { id: "through", label: "Highest sell-through" },
];

export default async function BestSellersPage({ searchParams }: { searchParams: Promise<{ house?: string; cls?: string; sort?: string }> }) {
  const sp = await searchParams;
  const m = await getMarket(sp.house);
  if (!m) return <NoMarket />;
  const house = sp.house;
  const sort = (SORTS.find((s) => s.id === sp.sort)?.id ?? "gold") as BestSort;
  const cls = sp.cls || null;
  const rows = bestSellers(m, cls, sort, 100);
  const cats = categories(m).slice(0, 12);
  const href = (o: { cls?: string | null; sort?: string }) => {
    const p = new URLSearchParams();
    if (house) p.set("house", house);
    const c = o.cls === undefined ? cls : o.cls;
    if (c) p.set("cls", c);
    const s = o.sort ?? sort;
    if (s !== "gold") p.set("sort", s);
    const q = p.toString();
    return `/auction/best${q ? `?${q}` : ""}`;
  };

  return (
    <div>
      <MarketStatus m={m} path="/auction/best" />
      <p className="mb-3 max-w-3xl text-sm text-gray-400">
        What actually sells, and for how much - handy for deciding what to farm or craft. &quot;Gold traded&quot; is how many sell a
        day times what they sell for.
      </p>

      <div className="mb-2 flex flex-wrap gap-2">
        {SORTS.map((s) => (
          <Link key={s.id} href={href({ sort: s.id })} className={`tab-btn ${sort === s.id ? "tab-btn-active" : ""}`}>
            {s.label}
          </Link>
        ))}
      </div>
      <div className="mb-3 flex flex-wrap gap-1.5 text-xs">
        <Link href={href({ cls: null })} className={`rounded border px-2 py-0.5 ${!cls ? "border-amber-500/60 text-amber-200" : "border-neutral-700 text-gray-400 hover:text-gray-200"}`}>
          Everything
        </Link>
        {cats.map((c) => (
          <Link
            key={c.name}
            href={href({ cls: c.name })}
            className={`rounded border px-2 py-0.5 ${cls === c.name ? "border-amber-500/60 text-amber-200" : "border-neutral-700 text-gray-400 hover:text-gray-200"}`}
          >
            {c.name}
          </Link>
        ))}
      </div>

      {rows.length === 0 ? (
        <Empty>No sales recorded yet{cls ? ` in ${cls}` : ""}.</Empty>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-neutral-700 bg-neutral-900/40">
          <table className="w-full min-w-[780px] text-sm">
            <thead>
              <tr>
                <th className={`${TH} w-10 text-right`}>#</th>
                <th className={TH}>Item</th>
                <th className={`${TH} text-right`}>Gold traded / day</th>
                <th className={`${TH} text-right`}>Sold / day</th>
                <th className={`${TH} text-right`}>Sells for</th>
                <th className={`${TH} text-right`}>Sell-through</th>
                <th className={`${TH} text-right`}>Cheapest now</th>
                <th className={TH}>Speed</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => (
                <tr key={r.id} className={TR}>
                  <td className={`${TD} text-right tabular-nums text-gray-500`}>{i + 1}</td>
                  <td className={`${TD} max-w-[280px]`}>
                    <ItemLink row={r} house={house} />
                  </td>
                  <td className={`${TD} text-right`}>
                    <Money c={r.goldPerDay} />
                  </td>
                  <td className={`${TD} text-right tabular-nums`}>{perDayText(r.perDay)}</td>
                  <td className={`${TD} text-right`}>
                    <Money c={r.avgSold} />
                  </td>
                  <td className={`${TD} text-right tabular-nums`}>{r.through >= 0 ? `${r.through}%` : "-"}</td>
                  <td className={`${TD} text-right`}>
                    {r.min ? <Money c={r.min} /> : <span className="text-gray-500">none</span>}
                    {r.min > 0 && suspiciousPrice(m, r.id, r.min) && (
                      <div className="text-xs font-semibold text-red-400" title="Priced like gold changing hands between accounts, not a real price.">
                        Suspicious
                      </div>
                    )}
                  </td>
                  <td className={TD}>
                    <SpeedBadge speed={r.speed} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

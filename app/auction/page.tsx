import Link from "next/link";
import { bestSellers, categories, getMarket, searchItems, suspiciousPrice } from "../../lib/marketView";
import MarketStatus, { NoMarket } from "./MarketStatus";
import { Empty, ItemLink, Money, perDayText, SpeedBadge, TD, TH, TR } from "./ui";

export const dynamic = "force-dynamic";

type SP = Promise<{ q?: string; cls?: string; house?: string }>;

export default async function AuctionSearchPage({ searchParams }: { searchParams: SP }) {
  const sp = await searchParams;
  const m = await getMarket(sp.house);
  if (!m) return <NoMarket />;

  const q = (sp.q ?? "").slice(0, 80);
  const cls = sp.cls || null;
  const rows = q ? searchItems(m, q, cls, 80) : bestSellers(m, cls, "gold", 40);
  const cats = categories(m);
  const house = sp.house;

  return (
    <div>
      <MarketStatus m={m} path="/auction" />

      <form className="mb-3 flex flex-wrap items-center gap-2" action="/auction">
        {house && <input type="hidden" name="house" value={house} />}
        <input
          name="q"
          defaultValue={q}
          placeholder="Search any item on the auction house..."
          className="min-w-0 flex-1 rounded border border-neutral-700 bg-neutral-900 px-3 py-2 text-sm text-gray-100 placeholder:text-gray-500 sm:max-w-md"
          autoComplete="off"
        />
        <select
          name="cls"
          defaultValue={cls ?? ""}
          className="rounded border border-neutral-700 bg-neutral-900 px-2 py-2 text-sm text-gray-200"
        >
          <option value="">All categories</option>
          {cats.map((c) => (
            <option key={c.name} value={c.name}>
              {c.name} ({c.count})
            </option>
          ))}
        </select>
        <button type="submit" className="tab-btn tab-btn-active">
          Search
        </button>
      </form>

      <p className="mb-2 text-xs text-gray-500">
        {q ? `${rows.length} result${rows.length === 1 ? "" : "s"} for "${q}"` : "Most gold traded per day"}
        {cls ? ` in ${cls}` : ""}. Click an item for its price history and everything listed right now.
      </p>

      {rows.length === 0 ? (
        <Empty>Nothing on the auction house matches that.</Empty>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-neutral-700 bg-neutral-900/40">
          <table className="w-full min-w-[760px] text-sm">
            <thead>
              <tr>
                <th className={TH}>Item</th>
                <th className={`${TH} text-right`}>Cheapest now</th>
                <th className={`${TH} text-right`}>Listed</th>
                <th className={`${TH} text-right`}>Sells for</th>
                <th className={`${TH} text-right`}>Sold / day</th>
                <th className={`${TH} text-right`}>Sell-through</th>
                <th className={TH}>Speed</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id} className={TR}>
                  <td className={`${TD} max-w-[320px]`}>
                    <ItemLink row={r} house={house} />
                  </td>
                  <td className={`${TD} text-right`}>
                    {r.min ? <Money c={r.min} /> : <span className="text-gray-500">none</span>}
                    {r.min > 0 && suspiciousPrice(m, r.id, r.min) && (
                      <div className="text-xs font-semibold text-red-400" title="Priced like gold changing hands between accounts, not a real price.">
                        Suspicious
                      </div>
                    )}
                  </td>
                  <td className={`${TD} text-right tabular-nums`}>{r.listed.toLocaleString()}</td>
                  <td className={`${TD} text-right`}>{r.avgSold ? <Money c={r.avgSold} /> : <span className="text-gray-500">-</span>}</td>
                  <td className={`${TD} text-right tabular-nums`}>{perDayText(r.perDay)}</td>
                  <td className={`${TD} text-right tabular-nums`}>{r.through >= 0 ? `${r.through}%` : "-"}</td>
                  <td className={TD}>
                    <SpeedBadge speed={r.speed} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {!q && (
        <p className="mt-3 text-xs text-gray-500">
          Looking for bargains? See <Link className="text-amber-300 hover:underline" href={`/auction/deals${house ? `?house=${house}` : ""}`}>Deals</Link>.
        </p>
      )}
    </div>
  );
}

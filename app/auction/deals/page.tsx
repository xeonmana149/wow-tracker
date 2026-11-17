import { flipDeals, getMarket, vendorDeals } from "../../../lib/marketView";
import MarketStatus, { NoMarket } from "../MarketStatus";
import { ago, Empty, ItemLink, Money, perDayText, SpeedBadge, TD, TH, TR } from "../ui";

export const dynamic = "force-dynamic";

export default async function DealsPage({ searchParams }: { searchParams: Promise<{ house?: string }> }) {
  const sp = await searchParams;
  const m = await getMarket(sp.house);
  if (!m) return <NoMarket />;
  const house = sp.house;
  const flips = flipDeals(m);
  const vendor = vendorDeals(m);

  return (
    <div className="space-y-6">
      <MarketStatus m={m} path="/auction/deals" />
      <p className="text-xs text-gray-500">
        From the snapshot {ago(m.snapT)} - someone may have bought a deal since.
        Check the price in game before you buy.
      </p>

      <section>
        <h2 className="text-lg font-semibold text-gray-100">Buy low, sell again</h2>
        <p className="mb-2 max-w-3xl text-sm text-gray-400">
          Listings at 70% or less of what the item has actually been selling for. Only items that sell fast or steadily, and no more
          than about a day&apos;s sales, so you&apos;re not stuck with a pile.
        </p>
        {m.hours < 12 ? (
          <Empty>Needs about 12 hours of sales data first - check back later today.</Empty>
        ) : flips.length === 0 ? (
          <Empty>No flips worth 50 silver or more right now.</Empty>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-neutral-700 bg-neutral-900/40">
            <table className="w-full min-w-[820px] text-sm">
              <thead>
                <tr>
                  <th className={TH}>Item</th>
                  <th className={`${TH} text-right`}>Buy</th>
                  <th className={`${TH} text-right`}>Up to</th>
                  <th className={`${TH} text-right`}>Costs</th>
                  <th className={`${TH} text-right`}>Usually sells for</th>
                  <th className={`${TH} text-right`}>Sold / day</th>
                  <th className={`${TH} text-right`}>Profit</th>
                  <th className={TH}>Speed</th>
                </tr>
              </thead>
              <tbody>
                {flips.map((f) => (
                  <tr key={f.row.id} className={TR}>
                    <td className={`${TD} max-w-[280px]`}>
                      <ItemLink row={f.row} house={house} />
                    </td>
                    <td className={`${TD} text-right tabular-nums`}>{f.qty.toLocaleString()}</td>
                    <td className={`${TD} text-right`}>
                      <Money c={f.maxEach} /> <span className="text-xs text-gray-500">each</span>
                    </td>
                    <td className={`${TD} text-right`}>
                      <Money c={f.cost} />
                    </td>
                    <td className={`${TD} text-right`}>
                      <Money c={f.resellEach} />
                    </td>
                    <td className={`${TD} text-right tabular-nums`}>{perDayText(f.row.perDay)}</td>
                    <td className={`${TD} text-right font-semibold text-emerald-300`}>
                      <Money c={f.profit} sign />
                    </td>
                    <td className={TD}>
                      <SpeedBadge speed={f.row.speed} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section>
        <h2 className="text-lg font-semibold text-gray-100">Cheaper than a vendor pays</h2>
        <p className="mb-2 max-w-3xl text-sm text-gray-400">
          Buy these and sell them straight to any vendor. No risk, as long as the vendor price is right. Prices marked
          &quot;check&quot; come from old classic data, so look at the tooltip in game first.
        </p>
        {vendor.length === 0 ? (
          <Empty>Nothing listed below vendor price right now.</Empty>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-neutral-700 bg-neutral-900/40">
            <table className="w-full min-w-[720px] text-sm">
              <thead>
                <tr>
                  <th className={TH}>Item</th>
                  <th className={`${TH} text-right`}>Buy</th>
                  <th className={`${TH} text-right`}>Costs</th>
                  <th className={`${TH} text-right`}>Vendor pays</th>
                  <th className={`${TH} text-right`}>Profit</th>
                </tr>
              </thead>
              <tbody>
                {vendor.map((v) => (
                  <tr key={v.row.id} className={TR}>
                    <td className={`${TD} max-w-[300px]`}>
                      <ItemLink row={v.row} house={house} />
                    </td>
                    <td className={`${TD} text-right tabular-nums`}>{v.qty.toLocaleString()}</td>
                    <td className={`${TD} text-right`}>
                      <Money c={v.cost} />
                    </td>
                    <td className={`${TD} text-right`}>
                      <Money c={v.vendorTotal} />{" "}
                      <span className="text-xs text-gray-500">
                        (<Money c={v.row.vendor} /> each{v.row.vendorSure ? "" : ", check"})
                      </span>
                    </td>
                    <td className={`${TD} text-right font-semibold text-emerald-300`}>
                      <Money c={v.profit} sign />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}

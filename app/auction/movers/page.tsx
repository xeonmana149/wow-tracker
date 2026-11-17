import { getMarket, moverDays, priceMovers, volumeMovers, type Mover } from "../../../lib/marketView";
import MarketStatus, { NoMarket } from "../MarketStatus";
import { Empty, ItemLink, Money, perDayText, TD, TH, TR } from "../ui";

export const dynamic = "force-dynamic";

function MoverTable({ rows, house }: { rows: Mover[]; house?: string }) {
  return (
    <div className="overflow-x-auto rounded-lg border border-neutral-700 bg-neutral-900/40">
      <table className="w-full min-w-[560px] text-sm">
        <thead>
          <tr>
            <th className={TH}>Item</th>
            <th className={`${TH} text-right`}>Now</th>
            <th className={`${TH} text-right`}>Usually</th>
            <th className={`${TH} text-right`}>Change</th>
            <th className={`${TH} text-right`}>Sold / day</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.row.id} className={TR}>
              <td className={`${TD} max-w-[260px]`}>
                <ItemLink row={r.row} house={house} />
              </td>
              <td className={`${TD} text-right`}>
                <Money c={r.now} />
              </td>
              <td className={`${TD} text-right`}>
                <Money c={r.usual} />
              </td>
              <td className={`${TD} text-right font-semibold tabular-nums ${r.change > 0 ? "text-emerald-300" : "text-red-300"}`}>
                {r.change > 0 ? "▲ +" : "▼ "}
                {Math.round(r.change * 100)}%
              </td>
              <td className={`${TD} text-right tabular-nums`}>{perDayText(r.row.perDay)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export default async function MoversPage({ searchParams }: { searchParams: Promise<{ house?: string }> }) {
  const sp = await searchParams;
  const m = await getMarket(sp.house);
  if (!m) return <NoMarket />;
  const house = sp.house;
  const days = moverDays(m);
  const { up, down } = priceMovers(m);
  const volume = volumeMovers(m);
  const need = Math.max(0, 2 - days);

  return (
    <div className="space-y-6">
      <MarketStatus m={m} path="/auction/movers" />
      <p className="max-w-3xl text-sm text-gray-400">
        Today&apos;s market price against the item&apos;s own average over the days before (up to two weeks). Only items that
        trade enough for one listing not to swing it.
      </p>
      {need > 0 ? (
        <Empty>
          Movers need at least two finished days of prices to compare with - {need === 2 ? "check back in two days" : "check back tomorrow"}.
        </Empty>
      ) : (
        <div className="grid gap-6 xl:grid-cols-2">
          <section>
            <h2 className="mb-2 text-lg font-semibold text-gray-100">Gone up</h2>
            {up.length ? <MoverTable rows={up} house={house} /> : <Empty>Nothing is more than 20% above its usual price.</Empty>}
          </section>
          <section>
            <h2 className="mb-2 text-lg font-semibold text-gray-100">Gone down</h2>
            {down.length ? <MoverTable rows={down} house={house} /> : <Empty>Nothing is more than 20% below its usual price.</Empty>}
          </section>
        </div>
      )}

      <section>
        <h2 className="mb-1 text-lg font-semibold text-gray-100">Suddenly selling more</h2>
        <p className="mb-2 text-sm text-gray-400">Yesterday&apos;s sales at least twice the usual - often a new recipe or a change in Forever.</p>
        {volume.length === 0 ? (
          <Empty>{days < 3 ? "Needs three full days of sales to compare." : "No unusual jumps in sales yesterday."}</Empty>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-neutral-700 bg-neutral-900/40">
            <table className="w-full min-w-[520px] text-sm">
              <thead>
                <tr>
                  <th className={TH}>Item</th>
                  <th className={`${TH} text-right`}>Sold yesterday</th>
                  <th className={`${TH} text-right`}>Usually</th>
                  <th className={`${TH} text-right`}>Times usual</th>
                </tr>
              </thead>
              <tbody>
                {volume.map((v) => (
                  <tr key={v.row.id} className={TR}>
                    <td className={`${TD} max-w-[300px]`}>
                      <ItemLink row={v.row} house={house} />
                    </td>
                    <td className={`${TD} text-right tabular-nums`}>{v.lastDay.toLocaleString()}</td>
                    <td className={`${TD} text-right tabular-nums`}>{v.usual.toLocaleString()}</td>
                    <td className={`${TD} text-right font-semibold tabular-nums text-emerald-300`}>{Math.round(v.ratio * 10) / 10}x</td>
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

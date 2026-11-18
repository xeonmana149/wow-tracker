import Link from "next/link";
import { notFound } from "next/navigation";
import { H_DAY, H_EXP, H_LOW, H_MIN, H_MKT, H_POSTS, H_QTY, H_SOLD, H_SOLDP } from "../../../../lib/market";
import { AH_CUT, getMarket, itemBasics, itemDetail, SPEED_TEXT, type CraftLine, type Market } from "../../../../lib/marketView";
import AddToList from "../../AddToList";
import MarketStatus, { NoMarket } from "../../MarketStatus";
import { dayNumber, Empty, ItemIcon, ItemLink, Money, Panel, perDayText, SpeedBadge, TD, TH, TR } from "../../ui";
import HistoryCharts from "./HistoryCharts";

export const dynamic = "force-dynamic";

function Stat({ label, children, note }: { label: string; children: React.ReactNode; note?: string }) {
  return (
    <div className="rounded-lg border border-neutral-700 bg-neutral-900/40 px-3 py-2">
      <div className="text-xs text-gray-500">{label}</div>
      <div className="mt-0.5 text-lg font-semibold text-gray-100">{children}</div>
      {note && <div className="text-xs text-gray-500">{note}</div>}
    </div>
  );
}

function CraftCard({ line, m, house }: { line: CraftLine; m: Market; house?: string }) {
  return (
    <div className="rounded border border-neutral-800 p-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-semibold text-gray-200">{line.recipe.prof}</span>
        <span className="text-xs text-gray-500">{line.recipe.category}</span>
        {line.yieldAvg > 1 && <span className="text-xs text-gray-400">makes {line.yieldAvg} at a time</span>}
        <span className="ml-auto">
          <AddToList kind="recipe" id={line.recipe.id} label="Add craft to shopping list" />
        </span>
      </div>
      <ul className="mt-2 space-y-1 text-sm">
        {line.parts.map((p) => {
          const b = itemBasics(m, p.id);
          return (
            <li key={p.id} className="flex flex-wrap items-center gap-2">
              <span className="w-8 text-right tabular-nums text-gray-400">{p.qty}x</span>
              <ItemLink row={b} house={house} size={20} />
              <span className="ml-auto text-gray-300">
                {p.from ? (
                  <>
                    <Money c={p.each * p.qty} />{" "}
                    <span className="text-xs text-gray-500">{p.from === "vendor" ? "from a vendor" : "auction"}</span>
                  </>
                ) : (
                  <span className="text-xs text-amber-300">not on the auction house</span>
                )}
              </span>
            </li>
          );
        })}
      </ul>
      <div className="mt-2 flex flex-wrap gap-x-5 gap-y-1 border-t border-neutral-800 pt-2 text-sm">
        <span className="text-gray-400">
          Materials per item: {line.cost !== null ? <Money c={line.cost} /> : <span className="text-amber-300">unknown</span>}
        </span>
        {line.profit !== null && (
          <span className="text-gray-400">
            Profit per item after the cut: <Money c={line.profit} sign />
          </span>
        )}
      </div>
      <div className="mt-1 text-xs text-gray-500">
        {line.crafters.length
          ? `Known by ${line.crafters.map((c) => c.character + (c.owner ? ` (${c.owner})` : "")).join(", ")}`
          : "Nobody on the site has synced this recipe yet."}
      </div>
    </div>
  );
}

export default async function AuctionItemPage({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<{ house?: string }> }) {
  const [{ id: raw }, sp] = await Promise.all([params, searchParams]);
  const id = Number(raw);
  if (!Number.isInteger(id) || id <= 0) notFound();
  const m = await getMarket(sp.house);
  if (!m) return <NoMarket />;
  const house = sp.house;
  const d = await itemDetail(m, id);
  const r = d.row;

  const points = d.history.map((h) => ({
    day: h[H_DAY],
    sold: h[H_SOLD] ?? 0,
    soldP: h[H_SOLDP] ?? 0,
    min: h[H_MIN] ?? 0,
    low: h[H_LOW] ?? 0,
    mkt: h[H_MKT] ?? 0,
    listed: h[H_QTY] ?? 0,
    posts: h[H_POSTS] ?? 0,
    exp: h[H_EXP] ?? 0,
  }));
  const sellEach = r.avgSold > 0 && r.speed !== "rarely" ? Math.min(r.avgSold, r.mkt || r.avgSold) : r.mkt;
  const net = sellEach ? Math.round(sellEach * (1 - AH_CUT)) : 0;

  let verdict: React.ReactNode = null;
  if (r.vendor > 0 && (!net || net <= r.vendor)) {
    verdict = <>Sell it to a vendor: they pay <Money c={r.vendor} />{net ? <> and the auction house would only net you <Money c={net} /></> : null}.</>;
  } else if (net && r.speed === "rarely") {
    verdict = <>It&apos;s listed at <Money c={sellEach} />, but it rarely sells. {r.vendor > 0 ? <>A vendor pays <Money c={r.vendor} />.</> : null}</>;
  } else if (net) {
    verdict = (
      <>
        Auction it: you&apos;d get about <Money c={net} /> each after the 5% cut
        {r.vendor > 0 ? <> (a vendor pays <Money c={r.vendor} />)</> : null}.
        {r.speed ? ` ${SPEED_TEXT[r.speed]}.` : ""}
      </>
    );
  }

  const ladder: { price: number; qty: number; n: number; running: number; spent: number }[] = [];
  for (const [price, qty, n] of d.ladder) {
    const prev = ladder[ladder.length - 1];
    ladder.push({ price, qty, n, running: (prev?.running ?? 0) + qty, spent: (prev?.spent ?? 0) + (price > 0 ? price * qty : 0) });
  }

  const byProf = new Map<string, typeof d.usedIn>();
  for (const rec of d.usedIn) byProf.set(rec.prof, [...(byProf.get(rec.prof) ?? []), rec]);

  return (
    <div className="space-y-4">
      <MarketStatus m={m} path={`/auction/item/${id}`} />

      <div className="flex flex-wrap items-center gap-3">
        <ItemIcon src={r.icon} size={48} />
        <div className="min-w-0">
          <h2 className="text-xl font-bold" style={{ color: r.color }}>
            {r.name}
          </h2>
          <div className="text-xs text-gray-500">
            {[r.cls, r.sub].filter(Boolean).join(" / ") || "Item"} · id {id}
          </div>
        </div>
        <SpeedBadge speed={r.speed} />
        <span className="ml-auto">
          <AddToList kind="item" id={id} />
        </span>
      </div>

      {!m.site.items[id] && <Empty>Nobody has listed this item since the data started. Nothing to show yet.</Empty>}

      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
        <Stat label="Cheapest now">{r.min ? <Money c={r.min} /> : "none"}</Stat>
        <Stat label="Market price" note="cheapest 15% listed">{r.mkt ? <Money c={r.mkt} /> : "-"}</Stat>
        <Stat label="Sells for" note="average actually sold">{r.avgSold ? <Money c={r.avgSold} /> : "-"}</Stat>
        <Stat label="Sold per day" note="upper estimate">{perDayText(r.perDay)}</Stat>
        <Stat label="Sell-through" note="share of listings that sell">{r.through >= 0 ? `${r.through}%` : "-"}</Stat>
        <Stat label="Listed now" note={`${perDayText(r.posts)} new auctions a day`}>{r.listed.toLocaleString()}</Stat>
      </div>

      {verdict && <Panel className="text-sm text-gray-200">{verdict}</Panel>}

      <Panel>
        {points.length >= 2 ? (
          <HistoryCharts points={points} today={dayNumber()} itemName={r.name} />
        ) : (
          <p className="text-sm text-gray-400">
            Price history builds up a day at a time (it started {points.length ? "today" : "recently"}). Come back tomorrow for a chart.
          </p>
        )}
      </Panel>

      <div className="grid gap-4 lg:grid-cols-2">
        <Panel>
          <h3 className="mb-2 font-semibold text-gray-200">Listed right now</h3>
          {ladder.length === 0 ? (
            <p className="text-sm text-gray-400">Nothing listed in the latest snapshot.</p>
          ) : (
            <div className="max-h-[420px] overflow-y-auto">
              <table className="w-full text-sm">
                <thead className="sticky top-0 bg-neutral-950">
                  <tr>
                    <th className={TH}>Price each</th>
                    <th className={`${TH} text-right`}>How many</th>
                    <th className={`${TH} text-right`}>Auctions</th>
                    <th className={`${TH} text-right`}>Buy all to here</th>
                  </tr>
                </thead>
                <tbody>
                  {ladder.map((l) => (
                    <tr key={l.price} className={TR}>
                      <td className={TD}>{l.price ? <Money c={l.price} /> : <span className="text-gray-500">bid only</span>}</td>
                      <td className={`${TD} text-right tabular-nums`}>{l.qty.toLocaleString()}</td>
                      <td className={`${TD} text-right tabular-nums`}>{l.n}</td>
                      <td className={`${TD} text-right`}>
                        {l.price ? (
                          <span className="text-gray-400">
                            {l.running.toLocaleString()} for <Money c={l.spent} />
                          </span>
                        ) : null}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {d.ladder.length >= 40 && <p className="mt-2 text-xs text-gray-500">Showing the 40 cheapest prices.</p>}
            </div>
          )}
        </Panel>

        <Panel>
          <h3 className="mb-2 font-semibold text-gray-200">
            Used in {d.usedIn.length} recipe{d.usedIn.length === 1 ? "" : "s"}
          </h3>
          {d.usedIn.length === 0 ? (
            <p className="text-sm text-gray-400">No crafting recipe uses this.</p>
          ) : (
            <div className="max-h-[420px] space-y-3 overflow-y-auto">
              {[...byProf].sort((a, b) => b[1].length - a[1].length).map(([prof, recs]) => (
                <div key={prof}>
                  <div className="mb-1 text-xs font-semibold uppercase tracking-wide text-gray-500">
                    {prof} · {recs.length}
                  </div>
                  <ul className="space-y-1 text-sm">
                    {recs.map((rec) => {
                      const qty = rec.reagents.find(([rid]) => rid === id)?.[1] ?? 1;
                      return (
                        <li key={rec.id} className="flex items-center gap-2">
                          {rec.item ? <ItemLink row={itemBasics(m, rec.item)} house={house} size={20} /> : <span className="text-gray-300">{rec.name}</span>}
                          <span className="ml-auto text-xs text-gray-500">needs {qty}</span>
                        </li>
                      );
                    })}
                  </ul>
                </div>
              ))}
            </div>
          )}
        </Panel>
      </div>

      {d.makes.length > 0 && (
        <Panel>
          <h3 className="mb-2 font-semibold text-gray-200">How to make it</h3>
          <div className="grid gap-3 md:grid-cols-2">
            {d.makes.map((line) => (
              <CraftCard key={line.recipe.id} line={line} m={m} house={house} />
            ))}
          </div>
        </Panel>
      )}

      <p className="text-xs text-gray-500">
        <Link href={`/auction${house ? `?house=${house}` : ""}`} className="text-amber-300 hover:underline">
          Back to search
        </Link>
      </p>
    </div>
  );
}

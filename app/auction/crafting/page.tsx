import Link from "next/link";
import { craftProfits, getMarket, PROFESSIONS, type CraftSort } from "../../../lib/marketView";
import AddToList from "../AddToList";
import MarketStatus, { NoMarket } from "../MarketStatus";
import { Empty, ItemLink, Money, perDayText, SpeedBadge, TD, TH, TR } from "../ui";

export const dynamic = "force-dynamic";

const CRAFTING = PROFESSIONS.filter((p) => !["Fishing", "Herbalism", "Skinning", "Mining"].includes(p)).concat("Mining");

export default async function CraftingProfitsPage({
  searchParams,
}: {
  searchParams: Promise<{ house?: string; prof?: string; known?: string; sort?: string }>;
}) {
  const sp = await searchParams;
  const m = await getMarket(sp.house);
  if (!m) return <NoMarket />;
  const house = sp.house;
  const prof = sp.prof && PROFESSIONS.includes(sp.prof) ? sp.prof : null;
  const known = sp.known === "1";
  const sort: CraftSort = sp.sort === "gold" ? "gold" : "profit";
  const lines = (await craftProfits(m, { prof, known, sort, limit: 150 })).filter((l) => (l.profit ?? 0) > 0);

  const href = (o: { prof?: string | null; known?: boolean; sort?: CraftSort }) => {
    const p = new URLSearchParams();
    if (house) p.set("house", house);
    const pr = o.prof === undefined ? prof : o.prof;
    if (pr) p.set("prof", pr);
    if (o.known ?? known) p.set("known", "1");
    const s = o.sort ?? sort;
    if (s !== "profit") p.set("sort", s);
    const q = p.toString();
    return `/auction/crafting${q ? `?${q}` : ""}`;
  };
  const chip = (active: boolean) =>
    `rounded border px-2 py-0.5 ${active ? "border-amber-500/60 text-amber-200" : "border-neutral-700 text-gray-400 hover:text-gray-200"}`;

  return (
    <div>
      <MarketStatus m={m} path="/auction/crafting" />
      <p className="mb-3 max-w-3xl text-sm text-gray-400">
        Every recipe in WoW Forever, costed at today&apos;s prices: materials bought from the cheapest of the auction house or a
        vendor, sold at what the item has actually been selling for, after the 5% cut. &quot;Known by&quot; lists characters on
        this site whose recipes have synced.
      </p>

      <div className="mb-2 flex flex-wrap gap-2">
        <Link href={href({ sort: "profit" })} className={`tab-btn ${sort === "profit" ? "tab-btn-active" : ""}`}>
          Most profit each
        </Link>
        <Link href={href({ sort: "gold" })} className={`tab-btn ${sort === "gold" ? "tab-btn-active" : ""}`}>
          Most profit a day
        </Link>
        <Link href={href({ known: !known })} className={`tab-btn ${known ? "tab-btn-active" : ""}`}>
          {known ? "Only recipes someone here knows" : "All recipes"}
        </Link>
      </div>
      <div className="mb-3 flex flex-wrap gap-1.5 text-xs">
        <Link href={href({ prof: null })} className={chip(!prof)}>
          Every profession
        </Link>
        {CRAFTING.map((p) => (
          <Link key={p} href={href({ prof: p })} className={chip(prof === p)}>
            {p}
          </Link>
        ))}
      </div>
      {sort === "gold" && (
        <p className="mb-2 text-xs text-gray-500">&quot;A day&quot; = profit each x how many sell a day (counted up to 20), so it favours things that actually move.</p>
      )}

      {lines.length === 0 ? (
        <Empty>No profitable crafts found{prof ? ` for ${prof}` : ""}{known ? " among recipes people here know" : ""}.</Empty>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-neutral-700 bg-neutral-900/40">
          <table className="w-full min-w-[980px] text-sm">
            <thead>
              <tr>
                <th className={TH}>Makes</th>
                <th className={TH}>Profession</th>
                <th className={`${TH} text-right`}>Materials</th>
                <th className={`${TH} text-right`}>Sells for</th>
                <th className={`${TH} text-right`}>Profit each</th>
                <th className={`${TH} text-right`}>Sold / day</th>
                <th className={TH}>Speed</th>
                <th className={TH}>Known by</th>
                <th className={TH} />
              </tr>
            </thead>
            <tbody>
              {lines.map((l) => (
                <tr key={l.recipe.id} className={TR}>
                  <td className={`${TD} max-w-[240px]`}>
                    <ItemLink row={l.made} house={house} />
                    {l.yieldAvg > 1 && <div className="text-xs text-gray-500">makes {l.yieldAvg} at a time</div>}
                  </td>
                  <td className={`${TD} text-gray-300`}>{l.recipe.prof}</td>
                  <td className={`${TD} text-right`}>
                    <Money c={l.cost ?? 0} />
                  </td>
                  <td className={`${TD} text-right`}>
                    <Money c={l.sellEach} />
                    {l.sellFrom === "listed" && <div className="text-xs text-amber-300/80">listed, no sales yet</div>}
                  </td>
                  <td className={`${TD} text-right font-semibold text-emerald-300`}>
                    <Money c={l.profit ?? 0} sign />
                  </td>
                  <td className={`${TD} text-right tabular-nums`}>{perDayText(l.made.perDay)}</td>
                  <td className={TD}>
                    <SpeedBadge speed={l.made.speed} />
                  </td>
                  <td className={`${TD} max-w-[200px] text-xs text-gray-400`}>
                    {l.crafters.length ? (
                      <span title={l.crafters.map((c) => c.character + (c.owner ? ` (${c.owner})` : "")).join(", ")}>
                        {l.crafters
                          .slice(0, 2)
                          .map((c) => c.character)
                          .join(", ")}
                        {l.crafters.length > 2 ? ` +${l.crafters.length - 2}` : ""}
                      </span>
                    ) : (
                      <span className="text-gray-600">-</span>
                    )}
                  </td>
                  <td className={TD}>
                    <AddToList kind="recipe" id={l.recipe.id} label="+ list" />
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

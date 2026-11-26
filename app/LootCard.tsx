import {
  GATHER_KINDS,
  GATHER_LABEL,
  LOOT_QUALITY,
  LOOT_WHERE,
  QUALITY_COLOR,
  QUALITY_LABEL,
  WHERE_LABEL,
  addLootStats,
  emptyLootStats,
  hasAnyLoot,
  totalDrops,
  type LootStats,
} from "../lib/lootStats";

// Loot & gathering (2026-11-26) - the tracker addon's lifetime counters
// (addon 1.9.20+, lib/lootStats.ts). One character on its page; on an
// account page, the account's total plus a row per character.

function n(v: number) {
  return v.toLocaleString();
}

function since(ts: number | null) {
  if (!ts) return null;
  return new Date(ts * 1000).toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}

function Totals({ s }: { s: LootStats }) {
  return (
    <div className="mt-2 grid grid-cols-1 gap-4 sm:grid-cols-2">
      <dl className="grid grid-cols-[1fr_auto] content-start gap-x-4 gap-y-1 text-sm">
        {GATHER_KINDS.map((k) => (
          <div key={k} className="contents">
            <dt className="text-gray-400">{GATHER_LABEL[k]}</dt>
            <dd className="text-right">
              {n(s.gather[k].n)}
              {s.gather[k].items > 0 && (
                <span className="ml-1 text-xs text-gray-500">({n(s.gather[k].items)} items)</span>
              )}
            </dd>
          </div>
        ))}
        <dt className="text-gray-400">Chests opened</dt>
        <dd className="text-right">{n(s.chests)}</dd>
        <dt className="text-gray-400">Clams, lockboxes &amp; bags</dt>
        <dd className="text-right">{n(s.opened)}</dd>
      </dl>
      <table className="w-full text-sm">
        <thead>
          <tr className="text-xs text-gray-500">
            <th className="text-left font-normal">Loot</th>
            {LOOT_WHERE.map((w) => (
              <th key={w} className="text-right font-normal">
                {WHERE_LABEL[w]}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {LOOT_QUALITY.map((q) => (
            <tr key={q}>
              <td style={{ color: QUALITY_COLOR[q] }}>{QUALITY_LABEL[q]}</td>
              {LOOT_WHERE.map((w) => (
                <td key={w} className="text-right">
                  {n(s.drops[w][q])}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function Recent({ s }: { s: LootStats }) {
  const finds = [...s.recent].sort((a, b) => b.at - a.at).slice(0, 6);
  if (finds.length === 0) return null;
  return (
    <div className="mt-3">
      <h3 className="text-xs uppercase tracking-wide text-gray-500">Latest finds</h3>
      <ul className="mt-1 space-y-0.5 text-sm">
        {finds.map((f, i) => (
          <li key={i} className="flex justify-between gap-2">
            <span style={{ color: QUALITY_COLOR[f.q] }}>[{f.name}]</span>
            <span className="shrink-0 text-xs text-gray-500">
              {f.where !== "world" ? `${WHERE_LABEL[f.where]} · ` : ""}
              {since(f.at)}
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}

const EMPTY = (
  <p className="mt-2 text-sm text-gray-400">
    Nothing counted yet. The tracker addon (1.9.20 or newer) counts herbs, ore, skins, fish, chests and every green or
    better item looted from the next time it loads.
  </p>
);

export function CharacterLootCard({ stats }: { stats: LootStats | null }) {
  return (
    <section className="rounded bg-neutral-800 p-4">
      <h2 className="font-bold">Loot &amp; gathering</h2>
      {!hasAnyLoot(stats) || !stats ? (
        EMPTY
      ) : (
        <>
          {since(stats.since) && <p className="text-xs text-gray-500">Counting since {since(stats.since)}</p>}
          <Totals s={stats} />
          <Recent s={stats} />
        </>
      )}
    </section>
  );
}

export function AccountLootCard({ characters }: { characters: { id: string; name: string; stats: LootStats }[] }) {
  const counted = characters.filter((c) => hasAnyLoot(c.stats));
  const total = counted.reduce((acc, c) => addLootStats(acc, c.stats), emptyLootStats());
  const blueUp = (s: LootStats) => totalDrops(s, "blue") + totalDrops(s, "epic") + totalDrops(s, "legendary");
  return (
    <div className="rounded-md border border-neutral-700 bg-neutral-800 p-4">
      <h2 className="text-lg">Loot &amp; gathering</h2>
      {counted.length === 0 ? (
        EMPTY
      ) : (
        <>
          <p className="text-xs text-gray-500">
            All {counted.length} {counted.length === 1 ? "character" : "characters"} together
            {since(total.since) ? `, counting since ${since(total.since)}` : ""}
          </p>
          <Totals s={total} />
          {counted.length > 1 && (
            <div className="mt-3 overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-xs text-gray-500">
                    <th className="text-left font-normal">Character</th>
                    <th className="text-right font-normal">Herbs</th>
                    <th className="text-right font-normal">Ore</th>
                    <th className="text-right font-normal">Skins</th>
                    <th className="text-right font-normal">Fish</th>
                    <th className="text-right font-normal">Chests</th>
                    <th className="text-right font-normal" style={{ color: QUALITY_COLOR.green }}>
                      Greens
                    </th>
                    <th className="text-right font-normal" style={{ color: QUALITY_COLOR.blue }}>
                      Blue+
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {[...counted]
                    .sort((a, b) => a.name.localeCompare(b.name))
                    .map((c) => (
                      <tr key={c.id}>
                        <td className="truncate pr-2">{c.name}</td>
                        <td className="text-right">{n(c.stats.gather.herb.n)}</td>
                        <td className="text-right">{n(c.stats.gather.ore.n)}</td>
                        <td className="text-right">{n(c.stats.gather.skin.n)}</td>
                        <td className="text-right">{n(c.stats.gather.fish.n)}</td>
                        <td className="text-right">{n(c.stats.chests)}</td>
                        <td className="text-right">{n(totalDrops(c.stats, "green"))}</td>
                        <td className="text-right">{n(blueUp(c.stats))}</td>
                      </tr>
                    ))}
                </tbody>
              </table>
            </div>
          )}
          <Recent s={total} />
        </>
      )}
    </div>
  );
}

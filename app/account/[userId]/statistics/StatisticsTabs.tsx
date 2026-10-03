"use client";

import { useMemo, useState } from "react";
import StatisticsCard, { type StatisticRow } from "../../../character/[id]/StatisticsCard";
import type { AggregatedStat } from "../../../../lib/accountStatistics";

// 2026-10-03 ("account-wide statistics plus an area with all character
// statistics but they are like in their own tab to not overload info") -
// the account-wide totals sit in their own section up top (a flat searchable
// list - see AggregatedStat's own comment on why it's numeric-only), and
// each character gets its OWN tab below reusing the exact StatisticsCard
// component the character page itself already uses, rather than cramming
// every character's full statistics onto the page at once.
export default function StatisticsTabs({
  characters,
  statsByCharacter,
  aggregated,
}: {
  characters: { id: string; name: string }[];
  statsByCharacter: Record<string, StatisticRow[]>;
  aggregated: AggregatedStat[];
}) {
  const [query, setQuery] = useState("");
  const [activeCharacterId, setActiveCharacterId] = useState(characters[0]?.id ?? "");

  const filteredAggregated = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return aggregated;
    return aggregated.filter((s) => s.name.toLowerCase().includes(q) || s.category.toLowerCase().includes(q));
  }, [aggregated, query]);

  return (
    <div className="mt-4 flex flex-col gap-4">
      {/* Account-wide */}
      <section className="rounded-md border border-neutral-700 bg-neutral-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-lg">Account-Wide Statistics</h2>
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search statistics..."
            className="min-w-[180px] rounded border border-neutral-700 bg-neutral-900 px-3 py-1.5 text-sm text-gray-200 placeholder:text-gray-500"
          />
        </div>
        <p className="mt-1 text-xs text-gray-500">
          Numeric stats summed across every character on the account. Stats that aren&apos;t plain numbers (money,
          named zones/battlegrounds) only make sense per-character, so they show up below instead.
        </p>
        {filteredAggregated.length === 0 ? (
          <p className="mt-3 text-sm text-gray-500">
            {aggregated.length === 0 ? "No statistics recorded yet." : `No stats match "${query}".`}
          </p>
        ) : (
          <div className="mt-3 grid grid-cols-1 gap-1.5 sm:grid-cols-2 lg:grid-cols-3">
            {filteredAggregated.map((s) => (
              <div
                key={`${s.category}|||${s.name}`}
                className="flex items-center justify-between gap-2 rounded border border-neutral-700 bg-neutral-900/40 px-3 py-1.5 text-sm"
              >
                <span className="truncate text-gray-300">{s.name}</span>
                <span className="shrink-0 font-semibold text-[#c9a566]">{s.total.toLocaleString()}</span>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* Per-character */}
      <section>
        <h2 className="text-lg">Character Statistics</h2>
        <div className="mt-2 flex flex-wrap gap-1.5">
          {characters.map((c) => (
            <button
              key={c.id}
              type="button"
              onClick={() => setActiveCharacterId(c.id)}
              className={`tab-btn px-3 py-1.5 text-sm ${activeCharacterId === c.id ? "tab-btn-active" : ""}`}
            >
              {c.name}
            </button>
          ))}
        </div>
        <div className="mt-3">
          <StatisticsCard stats={statsByCharacter[activeCharacterId] ?? []} />
        </div>
      </section>
    </div>
  );
}

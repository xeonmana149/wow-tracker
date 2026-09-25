"use client";

import { useState } from "react";

export type StatisticRow = {
  category: string;
  name: string;
  value: string;
};

function isTracked(value: string) {
  return value.trim() !== "" && value.trim() !== "--";
}

// Phase 1 of the Statistics pane feature (2026-09-25) - just displays every
// stat the addon reported, grouped by the same category names the in-game
// Statistics tab uses. Badges/leaderboards built from this data are a
// deliberate, separate later phase - this is only the raw numbers.
export default function StatisticsCard({ stats }: { stats: StatisticRow[] }) {
  const [showAll, setShowAll] = useState(false);

  if (stats.length === 0) {
    return (
      <section className="rounded bg-neutral-800 p-4">
        <h2 className="font-bold">Statistics</h2>
        <p className="mt-2 text-sm text-gray-500">
          No statistics recorded yet - sync with an addon version that reports them.
        </p>
      </section>
    );
  }

  const byCategory = new Map<string, StatisticRow[]>();
  for (const s of stats) {
    const list = byCategory.get(s.category) ?? [];
    list.push(s);
    byCategory.set(s.category, list);
  }
  const categories = Array.from(byCategory.keys()).sort((a, b) => a.localeCompare(b));
  const trackedTotal = stats.filter((s) => isTracked(s.value)).length;

  return (
    <section className="rounded bg-neutral-800 p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="font-bold">Statistics</h2>
        <button type="button" onClick={() => setShowAll((v) => !v)} className="tab-btn text-xs">
          {showAll ? "Hide untouched" : "Show all"}
        </button>
      </div>
      <p className="mt-1 text-xs text-gray-500">
        {trackedTotal} of {stats.length} tracked stats have a real value so far.
      </p>
      <div className="mt-3 flex flex-col gap-2">
        {categories.map((category) => {
          const rows = (byCategory.get(category) ?? [])
            .filter((r) => showAll || isTracked(r.value))
            .sort((a, b) => a.name.localeCompare(b.name));
          if (rows.length === 0) return null;
          return (
            <details
              key={category}
              className="group rounded border border-neutral-700 bg-neutral-900/40 p-2"
            >
              <summary className="flex cursor-pointer list-none items-center justify-between text-sm font-semibold">
                <span>{category}</span>
                <span className="text-xs text-gray-500 group-open:hidden">{rows.length}</span>
              </summary>
              <ul className="mt-2 flex flex-col gap-1 text-sm">
                {rows.map((r) => (
                  <li key={r.name} className="flex items-center justify-between gap-3">
                    <span className="text-gray-300">{r.name}</span>
                    <span className="font-semibold text-[#c9a566]">{r.value}</span>
                  </li>
                ))}
              </ul>
            </details>
          );
        })}
      </div>
    </section>
  );
}
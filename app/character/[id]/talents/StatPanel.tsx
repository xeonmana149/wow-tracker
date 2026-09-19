"use client";

import Link from "next/link";
import { STAT_GROUPS, type StatDef } from "../../../../lib/stats";

function fmt(n: number) {
  return String(Number(n.toFixed(2)));
}

export default function StatPanel({
  shown,
  saved,
  estimated,
  hasStats,
  characterId,
  isPlan,
}: {
  shown: Record<string, number>; // the stats with the build you're looking at
  saved: Record<string, number>; // your saved stats (applied build)
  estimated: Set<string>;
  hasStats: boolean;
  characterId: string;
  isPlan: boolean;
}) {
  function renderRow(def: StatDef) {
    const isRange = def.keys.length === 2;
    const key = def.keys[0];
    const delta = isRange ? 0 : shown[key] - saved[key];
    const changed = Math.abs(delta) >= 0.005;
    const color = !changed ? "text-white" : delta > 0 ? "text-green-400" : "text-red-400";
    const suffix = def.suffix ?? "";

    return (
      <div
        key={def.label}
        className="flex items-baseline justify-between gap-2 px-2 py-1 text-[13px] odd:bg-neutral-900/70"
      >
        <span className="text-amber-400">{def.label}:</span>
        <span className={`text-right ${color}`}>
          {isRange
            ? `${fmt(shown[def.keys[0]])} - ${fmt(shown[def.keys[1]])}`
            : `${fmt(shown[key])}${suffix}`}
          {changed && (
            <span className="ml-1 text-[11px]">
              ({estimated.has(key) ? "≈" : ""}
              {delta > 0 ? "+" : ""}
              {fmt(delta)}
              {suffix})
            </span>
          )}
        </span>
      </div>
    );
  }

  function renderGroup(group: (typeof STAT_GROUPS)[number]) {
    return (
      <div key={group.title} className="flex flex-col gap-0.5">
        <h3
          className="rounded border border-amber-900/70 py-1 text-center text-[13px] font-bold"
          style={{ background: "linear-gradient(180deg, #4a3b22, #241b0f)" }}
        >
          {group.title}
        </h3>
        {group.stats.map(renderRow)}
      </div>
    );
  }

  return (
    <aside className="rounded bg-neutral-800 p-3">
      <h2 className="font-bold">{isPlan ? "Stats with this plan" : "Stats"}</h2>

      {!hasStats && (
        <p className="mt-2 rounded bg-yellow-950 px-2 py-1.5 text-xs text-yellow-300">
          No stats saved yet, so percentage talents have nothing to work on.{" "}
          <Link href={`/character/${characterId}`} className="underline">
            Enter your stats
          </Link>{" "}
          on the character page first.
        </p>
      )}

      <div className="mt-2 grid gap-3 sm:grid-cols-2">
        <div className="flex flex-col gap-2">{STAT_GROUPS.slice(0, 3).map(renderGroup)}</div>
        <div className="flex flex-col gap-2">{STAT_GROUPS.slice(3).map(renderGroup)}</div>
      </div>

      <p className="mt-2 text-[11px] leading-snug text-gray-500">
        Green and red: change compared with your applied build. ≈ means estimated from another
        rank. Strength, Agility, Intellect and Stamina don&apos;t change health, mana, attack
        power or crit yet, because those formulas aren&apos;t known.
      </p>
    </aside>
  );
}
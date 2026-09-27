"use client";

import { useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";
import { iconUrlForFileId } from "../lib/icons";

// The actual browser UI for "Legacy Challenges" - the REAL Blizzard-server
// Achievements pane (GetCategoryList/GetAchievementInfo/
// GetAchievementCriteriaInfo), synced via character_legacy_achievements
// (sql/items-migration-22.sql + -23.sql for icons). Pulled out into its own
// component (2026-09-27) so it can be dropped into BOTH the main
// Achievements page (as a "Legacy Challenges" family, so it feels like part
// of the same achievement system rather than a separate hidden page) and
// its own standalone /character/[id]/legacy route (for anyone who
// bookmarked or linked directly to it) without keeping two copies of the
// same logic in sync by hand.
type CriteriaRow = { text: string; completed: boolean };
type LegacyRow = {
  achievement_id: number;
  category: string;
  name: string;
  description: string | null;
  completed: boolean;
  criteria: CriteriaRow[] | null;
  icon: number | null;
};

// Blizzard's own top-level "completed" flag isn't reliable for a
// multi-criteria achievement on this server (e.g. a zone-exploration
// achievement showing 3/10 sub-areas checked off can still come back
// completed=false, which is correct, but there's no equivalent
// "in progress" signal from the game at all) - so the status shown here is
// derived from the criteria checklist itself whenever one exists, and only
// falls back to the bare completed flag for achievements with no criteria
// (a plain one-shot "reach level 60", say).
type LegacyStatus = "done" | "inProgress" | "notStarted";

function legacyStatus(item: LegacyRow): LegacyStatus {
  const total = item.criteria?.length ?? 0;
  if (total === 0) return item.completed ? "done" : "notStarted";
  const done = item.criteria!.filter((c) => c.completed).length;
  if (done >= total) return "done";
  if (done > 0) return "inProgress";
  return "notStarted";
}

const STATUS_LABEL: Record<LegacyStatus, string> = {
  done: "Done",
  inProgress: "In Progress",
  notStarted: "Not Started",
};

const STATUS_CLASS: Record<LegacyStatus, string> = {
  done: "bg-emerald-900/50 text-emerald-300",
  inProgress: "bg-amber-900/50 text-amber-300",
  notStarted: "bg-neutral-800 text-gray-500",
};

export default function LegacyChallengesSection({ characterId }: { characterId: string }) {
  const [loading, setLoading] = useState(true);
  const [rows, setRows] = useState<LegacyRow[]>([]);
  const [category, setCategory] = useState<string | "all">("all");
  const [hideCompleted, setHideCompleted] = useState(false);

  useEffect(() => {
    async function load() {
      const { data: legacyRows } = await supabase
        .from("character_legacy_achievements")
        .select("achievement_id, category, name, description, completed, criteria, icon")
        .eq("character_id", characterId);
      setRows((legacyRows ?? []) as LegacyRow[]);
      setLoading(false);
    }
    load();
  }, [characterId]);

  const categories = useMemo(() => {
    const set = new Set<string>();
    for (const r of rows) set.add(r.category);
    return Array.from(set).sort();
  }, [rows]);

  const completedCount = rows.filter((r) => legacyStatus(r) === "done").length;

  const filtered = useMemo(() => {
    return rows
      .filter((r) => category === "all" || r.category === category)
      .filter((r) => !hideCompleted || legacyStatus(r) !== "done");
  }, [rows, category, hideCompleted]);

  const grouped = useMemo(() => {
    const map = new Map<string, LegacyRow[]>();
    for (const r of filtered) {
      const list = map.get(r.category) ?? [];
      list.push(r);
      map.set(r.category, list);
    }
    return Array.from(map.entries())
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([cat, list]) => ({
        category: cat,
        items: list.sort((a, b) => a.name.localeCompare(b.name)),
      }));
  }, [filtered]);

  if (loading) {
    return <p className="mt-4 text-sm text-gray-400">Loading legacy challenges...</p>;
  }

  if (rows.length === 0) {
    return (
      <p className="mt-4 text-sm text-gray-400">
        Nothing synced yet - run the addon (v1.8.6+) at least once with the Achievements panel open in-game, then
        sync again.
      </p>
    );
  }

  return (
    <div className="mt-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-xs text-gray-500">
          Blizzard&apos;s own Achievements pane - dungeons, raids, exploration and profession/class milestones.
        </p>
        <div className="text-sm font-bold text-[#c9a566]">
          {completedCount} / {rows.length} completed
        </div>
      </div>

      <div className="mt-3 flex flex-wrap items-center gap-2">
        <button
          type="button"
          onClick={() => setCategory("all")}
          className={`rounded px-3 py-1.5 text-sm font-semibold ${
            category === "all" ? "bg-red-700 text-white" : "bg-neutral-800 text-gray-300 hover:bg-neutral-700"
          }`}
        >
          All
        </button>
        {categories.map((c) => (
          <button
            key={c}
            type="button"
            onClick={() => setCategory(c)}
            className={`rounded px-3 py-1.5 text-sm font-semibold ${
              category === c ? "bg-red-700 text-white" : "bg-neutral-800 text-gray-300 hover:bg-neutral-700"
            }`}
          >
            {c}
          </button>
        ))}

        <span className="mx-1 h-5 w-px bg-neutral-700" />

        <label className="flex items-center gap-1.5 text-sm text-gray-400">
          <input
            type="checkbox"
            checked={hideCompleted}
            onChange={(e) => setHideCompleted(e.target.checked)}
            className="accent-red-700"
          />
          Hide completed
        </label>
      </div>

      <div className="mt-4 flex flex-col gap-6">
        {grouped.map((group) => (
          <div key={group.category}>
            <h2 className="mb-2 text-sm font-bold uppercase tracking-wide text-gray-400">{group.category}</h2>
            <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
              {group.items.map((item) => (
                <LegacyRowCard key={item.achievement_id} item={item} />
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function LegacyRowCard({ item }: { item: LegacyRow }) {
  const criteriaDone = (item.criteria ?? []).filter((c) => c.completed).length;
  const criteriaTotal = item.criteria?.length ?? 0;
  const status = legacyStatus(item);
  const iconSrc = item.icon ? iconUrlForFileId(item.icon) : null;

  return (
    <div
      className={`flex gap-3 rounded-lg border p-3 ${
        status === "done" ? "border-neutral-700 bg-neutral-900/40" : "border-neutral-800 bg-neutral-900/20"
      }`}
    >
      {/* Same rounded-square treatment as the site's other WoW icons (item/
          gear icons via lib/icons.ts) - keeps this reading as "one of our
          achievement icons", not a bespoke Legacy-only look. Falls back to
          a plain slot for achievements exported before the addon captured
          icons (pre-1.8.6). */}
      <span className="h-12 w-12 shrink-0 overflow-hidden rounded-md border border-neutral-700 bg-neutral-950">
        {iconSrc ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={iconSrc}
            alt=""
            draggable={false}
            className={`h-full w-full object-cover ${status === "notStarted" ? "grayscale opacity-70" : ""}`}
          />
        ) : null}
      </span>

      <div className="min-w-0 flex-1">
        <div className="flex items-start justify-between gap-2">
          <span className={`font-bold ${status === "done" ? "text-white" : "text-gray-400"}`}>{item.name}</span>
          <span className={`shrink-0 rounded px-2 py-0.5 text-[11px] font-bold ${STATUS_CLASS[status]}`}>
            {STATUS_LABEL[status]}
          </span>
        </div>
        {item.description && <div className="mt-0.5 text-xs text-gray-500">{item.description}</div>}

        {criteriaTotal > 0 && (
          <div className="mt-2">
            <div className="h-1.5 w-full overflow-hidden rounded-full bg-neutral-800">
              <div
                className="h-full rounded-full bg-[#c9a566]"
                style={{ width: `${Math.round((criteriaDone / criteriaTotal) * 100)}%` }}
              />
            </div>
            <ul className="mt-1.5 space-y-0.5 text-[11px]">
              {item.criteria!.map((c, i) => (
                <li key={i} className={c.completed ? "text-gray-300" : "text-gray-600"}>
                  {c.completed ? "✓" : "○"} {c.text}
                </li>
              ))}
            </ul>
          </div>
        )}
      </div>
    </div>
  );
}
"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { supabase } from "../lib/supabase";
import {
  buildLegacyAchievementItems,
  groupByLegacyCategory,
  legacyCategoryGroup,
  LEGACY_CATEGORY_GROUP_ORDER,
  type AchievementBoardItem,
  type LegacyAchievementRow,
} from "./achievementBoard";
import AchievementRow from "./AchievementRow";

// Account-wide Legacy Challenges browser (2026-09-27 rework) - the real
// Blizzard Achievements pane, synced into account_legacy_achievements
// (sql/items-migration-25.sql). This used to live on each character's own
// /achievements page, but completion here is the same no matter which
// character on the account is logged in when you sync (confirmed in-game),
// so it moved to its own top-level tab instead of being duplicated per
// character. Same card format as the community achievements page (borders,
// tier frames, milestone bars, collapsible checklists via AchievementRow) -
// the one real difference is these points are shown for flavor only and
// never feed the leaderboards' Overall score.
export default function AccountLegacyPage() {
  const [loading, setLoading] = useState(true);
  const [signedIn, setSignedIn] = useState(false);
  const [items, setItems] = useState<AchievementBoardItem[]>([]);
  const [category, setCategory] = useState<string | "all">("all");
  const [hideCompleted, setHideCompleted] = useState(false);
  // "show which ones earn you legacy points and which give nothing"
  // (2026-09-27) - most of the 111 are worth 0 (class/profession-only, not
  // part of the game's own 65-point Legacy Points total), so this lets
  // Jordan isolate just the ones that actually count.
  const [pointFilter, setPointFilter] = useState<"all" | "earns" | "none">("all");
  // Collapsible group sections (2026-09-28, Jordan's request) - the full
  // list was one long page you had to scroll through to reach e.g. Raids at
  // the bottom. Collapsed by default so switching "All categories" back on
  // doesn't dump every achievement back onto the page at once; picking a
  // single category pill auto-expands just that one group below (see the
  // effect right after this), since there's nothing else to collapse it
  // against at that point.
  const [expandedGroups, setExpandedGroups] = useState<Set<string>>(new Set());

  function toggleGroup(cat: string) {
    setExpandedGroups((prev) => {
      const next = new Set(prev);
      if (next.has(cat)) {
        next.delete(cat);
      } else {
        next.add(cat);
      }
      return next;
    });
  }

  useEffect(() => {
    async function load() {
      const { data: userData } = await supabase.auth.getUser();
      if (!userData.user) {
        setSignedIn(false);
        setLoading(false);
        return;
      }
      setSignedIn(true);

      const { data: legacyRows } = await supabase
        .from("account_legacy_achievements")
        .select("achievement_id, category, name, description, completed, criteria, icon, points, ui_points")
        .eq("user_id", userData.user.id);

      setItems(buildLegacyAchievementItems((legacyRows ?? []) as LegacyAchievementRow[]));
      setLoading(false);
    }
    load();
  }, []);

  const totalPoints = useMemo(() => items.reduce((sum, i) => sum + i.points, 0), [items]);
  // "Completed" means fully done (points > 0), not just showing some tier
  // progress - item.earned goes true the moment a multi-criteria challenge
  // reaches its first tier (e.g. Copper), which isn't the same as actually
  // finishing it. Points only pay out at full completion (see
  // achievementBoard.ts), so they're the right signal for "done" here too.
  const completedCount = items.filter((i) => i.points > 0).length;

  // How many of the 111 actually count toward the game's 65-point total,
  // vs. how many are just regular achievements sharing this panel.
  const earnsPointsCount = items.filter((i) => (i.legacyPointValue ?? 0) > 0).length;
  const noPointsCount = items.length - earnsPointsCount;

  // Condensed groups (2026-09-28) instead of Blizzard's ~24 raw category
  // names - only shows groups that actually have at least one item, in the
  // fixed LEGACY_CATEGORY_GROUP_ORDER order rather than alphabetically.
  const categories = useMemo(() => {
    const present = new Set<string>();
    for (const i of items) present.add(legacyCategoryGroup(i.legacyCategory));
    return LEGACY_CATEGORY_GROUP_ORDER.filter((g) => present.has(g));
  }, [items]);

  const filtered = useMemo(() => {
    return items
      .filter((i) => category === "all" || legacyCategoryGroup(i.legacyCategory) === category)
      .filter((i) => !hideCompleted || i.points === 0)
      .filter((i) => {
        if (pointFilter === "all") return true;
        const earnsPoints = (i.legacyPointValue ?? 0) > 0;
        return pointFilter === "earns" ? earnsPoints : !earnsPoints;
      });
  }, [items, category, hideCompleted, pointFilter]);

  const grouped = useMemo(() => groupByLegacyCategory(filtered), [filtered]);

  // Auto-expand a single picked category (nothing else to collapse against);
  // switching back to "All categories" collapses everything again rather
  // than leaving whatever was open still open and dumping the rest back in.
  useEffect(() => {
    if (category === "all") {
      setExpandedGroups(new Set());
    } else {
      setExpandedGroups(new Set([category]));
    }
  }, [category]);

  if (loading) {
    return <main className="mx-auto max-w-6xl p-4 text-white md:p-6">Loading legacy challenges...</main>;
  }

  if (!signedIn) {
    return (
      <main className="mx-auto max-w-6xl p-4 text-white md:p-6">
        <h1 className="text-3xl font-bold">Legacy Challenges</h1>
        <p className="mt-4 text-sm text-gray-400">
          <Link href="/login" className="text-amber-400 hover:underline">
            Sign in
          </Link>{" "}
          to see your account&apos;s Legacy Challenges.
        </p>
      </main>
    );
  }

  if (items.length === 0) {
    return (
      <main className="mx-auto max-w-6xl p-4 text-white md:p-6">
        <h1 className="text-3xl font-bold">Legacy Challenges</h1>
        <p className="mt-4 text-sm text-gray-400">
          Nothing synced yet - run the addon (v1.8.7+) at least once with the Achievements panel open in-game on any
          character, then sync.
        </p>
      </main>
    );
  }

  return (
    <main className="mx-auto max-w-6xl p-4 text-white md:p-6">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <div>
          <h1 className="text-3xl font-bold">🏆 Legacy Challenges</h1>
          <p className="text-xs text-gray-500">
            Blizzard&apos;s own Achievements pane - account-wide, the same for every character. Dungeons, raids,
            exploration and profession/class milestones.
          </p>
        </div>
        <div className="text-lg font-bold text-amber-400">{totalPoints.toLocaleString()} Legacy Points</div>
      </div>

      <div className="mt-4 rounded-lg border border-neutral-700 bg-neutral-900/40 p-4">
        <span className="text-sm text-gray-400">
          {completedCount} / {items.length} completed
        </span>
        <span className="mx-2 text-neutral-700">·</span>
        <span className="text-sm text-gray-400">
          <span className="font-semibold text-amber-400">{earnsPointsCount}</span> earn Legacy Points,{" "}
          <span className="font-semibold text-gray-500">{noPointsCount}</span> don&apos;t
        </span>
      </div>

      <div className="mt-4 flex flex-wrap items-center gap-2">
        <button
          type="button"
          onClick={() => setPointFilter("all")}
          className={`rounded px-3 py-1.5 text-sm font-semibold ${
            pointFilter === "all" ? "bg-amber-700 text-white" : "bg-neutral-800 text-gray-300 hover:bg-neutral-700"
          }`}
        >
          All
        </button>
        <button
          type="button"
          onClick={() => setPointFilter("earns")}
          className={`rounded px-3 py-1.5 text-sm font-semibold ${
            pointFilter === "earns" ? "bg-amber-700 text-white" : "bg-neutral-800 text-gray-300 hover:bg-neutral-700"
          }`}
        >
          👑 Earns points
        </button>
        <button
          type="button"
          onClick={() => setPointFilter("none")}
          className={`rounded px-3 py-1.5 text-sm font-semibold ${
            pointFilter === "none" ? "bg-amber-700 text-white" : "bg-neutral-800 text-gray-300 hover:bg-neutral-700"
          }`}
        >
          No points
        </button>
      </div>

      <div className="mt-2 flex flex-wrap items-center gap-2">
        <button
          type="button"
          onClick={() => setCategory("all")}
          className={`rounded px-3 py-1.5 text-sm font-semibold ${
            category === "all" ? "bg-red-700 text-white" : "bg-neutral-800 text-gray-300 hover:bg-neutral-700"
          }`}
        >
          All categories
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

        <span className="mx-1 h-5 w-px bg-neutral-700" />

        <button
          type="button"
          onClick={() => setExpandedGroups(new Set(grouped.map(([cat]) => cat)))}
          className="text-sm font-semibold text-gray-400 hover:text-gray-200"
        >
          Expand all
        </button>
        <button
          type="button"
          onClick={() => setExpandedGroups(new Set())}
          className="text-sm font-semibold text-gray-400 hover:text-gray-200"
        >
          Collapse all
        </button>
      </div>

      <div className="mt-4 flex flex-col gap-2">
        {grouped.map(([cat, catItems]) => {
          const isOpen = expandedGroups.has(cat);
          const doneInGroup = catItems.filter((i) => i.points > 0).length;
          return (
            <div key={cat} className="rounded border border-neutral-800 bg-neutral-900/40">
              <button
                type="button"
                onClick={() => toggleGroup(cat)}
                className="flex w-full items-center justify-between px-3 py-2.5 text-left"
              >
                <span className="text-xs font-bold uppercase tracking-wide text-amber-400/70">
                  {cat}{" "}
                  <span className="ml-1.5 text-[11px] font-normal normal-case tracking-normal text-gray-500">
                    ({doneInGroup}/{catItems.length} done)
                  </span>
                </span>
                <span
                  className={`text-gray-400 transition-transform duration-150 ${isOpen ? "rotate-180" : ""}`}
                  aria-hidden="true"
                >
                  ▾
                </span>
              </button>
              {isOpen && (
                <div className="grid grid-cols-1 gap-3 border-t border-neutral-800 p-3 lg:grid-cols-2">
                  {catItems.map((item) => (
                    <AchievementRow key={item.key} item={item} isOwner={false} pinned={false} onTogglePin={() => {}} />
                  ))}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </main>
  );
}
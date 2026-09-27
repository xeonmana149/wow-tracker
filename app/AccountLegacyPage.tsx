"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { supabase } from "../lib/supabase";
import {
  buildLegacyAchievementItems,
  groupByLegacyCategory,
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

  const categories = useMemo(() => {
    const set = new Set<string>();
    for (const i of items) set.add(i.legacyCategory ?? "Other");
    return Array.from(set).sort();
  }, [items]);

  const filtered = useMemo(() => {
    return items
      .filter((i) => category === "all" || (i.legacyCategory ?? "Other") === category)
      .filter((i) => !hideCompleted || i.points === 0)
      .filter((i) => {
        if (pointFilter === "all") return true;
        const earnsPoints = (i.legacyPointValue ?? 0) > 0;
        return pointFilter === "earns" ? earnsPoints : !earnsPoints;
      });
  }, [items, category, hideCompleted, pointFilter]);

  const grouped = useMemo(() => groupByLegacyCategory(filtered), [filtered]);

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
      </div>

      <div className="mt-4 flex flex-col gap-4">
        {grouped.map(([cat, catItems]) => (
          <div key={cat}>
            <h2 className="mb-1.5 text-xs font-bold uppercase tracking-wide text-amber-400/70">{cat}</h2>
            <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
              {catItems.map((item) => (
                <AchievementRow key={item.key} item={item} isOwner={false} pinned={false} onTogglePin={() => {}} />
              ))}
            </div>
          </div>
        ))}
      </div>
    </main>
  );
}
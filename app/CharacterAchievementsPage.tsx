"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { supabase } from "../lib/supabase";
import { localBadgeIconSrc, TIER_FRAME_SRC, FRAME_HOLE_RATIO, TIER_MEDAL_SRC } from "../lib/badgeFrames";
import { iconUrlForFileId } from "../lib/icons";
import { FAMILY_META, type AchievementFamily, type AchievementTier } from "../lib/achievements";
import {
  buildAchievementItems,
  buildLegacyAchievementItems,
  SHOWCASE_LIMIT,
  type AchievementBoardItem,
  type LegacyAchievementRow,
} from "./achievementBoard";
import MilestoneBar from "./MilestoneBar";
import BadgePlaceholder from "./BadgePlaceholder";

// The full achievement browser for one character - everything the compact
// header showcase (AchievementShowcase.tsx) deliberately leaves out:
// categories, sorting, progress bars and points for every achievement,
// earned or not. Reached via that showcase's "View All" link, at
// /character/[id]/achievements.

type SortMode = "category" | "alphabetical" | "closest" | "highestTier" | "recent";

const TIER_ORDER: AchievementTier[] = ["Platinum", "Gold", "Silver", "Copper"];
const TIER_RANK: Record<AchievementTier, number> = { Platinum: 3, Gold: 2, Silver: 1, Copper: 0 };

export default function CharacterAchievementsPage({ characterId }: { characterId: string }) {
  const [loading, setLoading] = useState(true);
  const [characterName, setCharacterName] = useState("");
  const [items, setItems] = useState<AchievementBoardItem[]>([]);
  // "oneOff" is a filter dimension separate from family (2026-09-25) - the
  // one-off/flat achievements (max_level, level milestones, personality
  // badges, etc.) are already scattered across several families (character,
  // social, pvp, professions) rather than having one of their own, so this
  // is a cross-cutting filter ("show me every non-tiered achievement")
  // rather than another entry in the family list.
  const [family, setFamily] = useState<AchievementFamily | "all" | "oneOff">("all");
  const [sort, setSort] = useState<SortMode>("category");

  // Showcase pinning - which earned achievements show up in the compact
  // strip on the character page (AchievementShowcase.tsx / pickShowcaseItems
  // in achievementBoard.ts). Lives on characters.showcase_kinds as a plain
  // array of kind strings, in display order; empty/null falls back to the
  // automatic highest-tier-first pick there.
  const [isOwner, setIsOwner] = useState(false);
  const [pinned, setPinned] = useState<string[]>([]);
  const [pinMessage, setPinMessage] = useState("");

  useEffect(() => {
    async function load() {
      const [
        { data: character },
        { data: achievementRows },
        { data: statRows },
        { data: professionRows },
        { data: userData },
        { data: legacyRows },
      ] = await Promise.all([
        supabase.from("characters").select("name, user_id, showcase_kinds").eq("id", characterId).single(),
        supabase.from("achievements").select("kind, tier, earned_at").eq("character_id", characterId),
        supabase.from("character_statistics").select("category, name, value").eq("character_id", characterId),
        supabase.from("character_professions").select("recipes").eq("character_id", characterId),
        supabase.auth.getUser(),
        // Legacy Challenges - the real Blizzard Achievements pane, merged
        // into the exact same list below via buildLegacyAchievementItems
        // rather than shown as a separate section, so they feel like part
        // of this one achievement system.
        supabase
          .from("character_legacy_achievements")
          .select("achievement_id, name, description, completed, criteria, icon, points")
          .eq("character_id", characterId),
      ]);

      setCharacterName(character?.name ?? "");
      setIsOwner(!!character?.user_id && userData.user?.id === character.user_id);
      setPinned((character?.showcase_kinds as string[] | null) ?? []);

      const recipesCount = (professionRows ?? []).reduce(
        (sum: number, p: { recipes: unknown[] | null }) => sum + (Array.isArray(p.recipes) ? p.recipes.length : 0),
        0
      );

      setItems([
        ...buildAchievementItems({
          achievementRows: (achievementRows ?? []) as {
            kind: string;
            tier: AchievementTier | null;
            earned_at: string | null;
          }[],
          statRows: (statRows ?? []) as { category: string; name: string; value: string }[],
          recipesCount,
        }),
        ...buildLegacyAchievementItems((legacyRows ?? []) as LegacyAchievementRow[]),
      ]);
      setLoading(false);
    }
    load();
  }, [characterId]);

  async function togglePin(kind: string) {
    const isPinned = pinned.includes(kind);
    if (!isPinned && pinned.length >= SHOWCASE_LIMIT) {
      setPinMessage(`Showcase is full - unpin one first (max ${SHOWCASE_LIMIT}).`);
      return;
    }

    const next = isPinned ? pinned.filter((k) => k !== kind) : [...pinned, kind];
    setPinned(next);
    setPinMessage("Saving...");

    const { error } = await supabase.from("characters").update({ showcase_kinds: next }).eq("id", characterId);

    if (error) {
      setPinMessage(error.message);
      setPinned(pinned); // roll back the optimistic update
    } else {
      setPinMessage("Saved");
      setTimeout(() => setPinMessage(""), 1500);
    }
  }

  // Legacy Challenges award their own separate "Legacy Points" tally rather
  // than folding into Achievement Points - the one deliberate difference
  // from a normal community achievement, per 2026-09-27 ("the only
  // difference is they also give legacy points"). Everything else about
  // how they render (borders, tier frames, milestone bars) is identical.
  const totalPoints = useMemo(
    () => items.filter((i) => i.family !== "legacy").reduce((sum, i) => sum + i.points, 0),
    [items]
  );
  const legacyPoints = useMemo(
    () => items.filter((i) => i.family === "legacy").reduce((sum, i) => sum + i.points, 0),
    [items]
  );
  const tierCounts = useMemo(() => {
    const counts: Record<AchievementTier, number> = { Platinum: 0, Gold: 0, Silver: 0, Copper: 0 };
    for (const i of items) if (i.tier) counts[i.tier] += 1;
    return counts;
  }, [items]);
  const earnedCount = items.filter((i) => i.earned).length;

  const familiesPresent = useMemo(() => {
    const set = new Set<AchievementFamily>();
    for (const i of items) set.add(i.family);
    return Array.from(set);
  }, [items]);

  const oneOffCount = useMemo(() => items.filter((i) => !i.tiered).length, [items]);

  const filtered = useMemo(() => {
    if (family === "all") return items;
    if (family === "oneOff") return items.filter((i) => !i.tiered);
    return items.filter((i) => i.family === family);
  }, [items, family]);

  const sorted = useMemo(() => {
    const list = [...filtered];
    switch (sort) {
      case "alphabetical":
        return list.sort((a, b) => a.name.localeCompare(b.name));
      case "highestTier":
        return list.sort((a, b) => {
          const rankA = a.tier ? TIER_RANK[a.tier] : a.earned ? -0.5 : -1;
          const rankB = b.tier ? TIER_RANK[b.tier] : b.earned ? -0.5 : -1;
          return rankB - rankA;
        });
      case "closest":
        return list.sort((a, b) => {
          const pctA = a.tiered && a.nextThreshold ? (a.value ?? 0) / a.nextThreshold : a.earned ? 1 : 0;
          const pctB = b.tiered && b.nextThreshold ? (b.value ?? 0) / b.nextThreshold : b.earned ? 1 : 0;
          return pctB - pctA;
        });
      case "recent":
        return list.sort((a, b) => {
          const timeA = a.earnedAt ? new Date(a.earnedAt).getTime() : 0;
          const timeB = b.earnedAt ? new Date(b.earnedAt).getTime() : 0;
          return timeB - timeA;
        });
      case "category":
      default:
        return list.sort(
          (a, b) => a.family.localeCompare(b.family) || FAMILY_META[a.family].label.localeCompare(FAMILY_META[b.family].label)
        );
    }
  }, [filtered, sort]);

  const grouped = useMemo(() => {
    if (sort !== "category") return [{ family: null as AchievementFamily | null, items: sorted }];
    const map = new Map<AchievementFamily, AchievementBoardItem[]>();
    for (const i of sorted) {
      const list = map.get(i.family) ?? [];
      list.push(i);
      map.set(i.family, list);
    }
    return Array.from(map.entries()).map(([fam, list]) => ({ family: fam, items: list }));
  }, [sorted, sort]);

  if (loading) {
    return <main className="mx-auto max-w-6xl p-4 text-white md:p-6">Loading achievements...</main>;
  }

  return (
    <main className="mx-auto max-w-6xl p-4 text-white md:p-6">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <div>
          <Link href={`/character/${characterId}`} className="text-xs text-gray-500 hover:underline">
            ← Back to {characterName || "character"}
          </Link>
          <h1 className="text-3xl font-bold">Achievements</h1>
        </div>
        <div className="flex items-baseline gap-3">
          <div className="text-lg font-bold text-[#c9a566]">{totalPoints.toLocaleString()} Achievement Points</div>
          {legacyPoints > 0 && (
            <div className="text-sm font-bold text-amber-400">{legacyPoints.toLocaleString()} Legacy Points</div>
          )}
        </div>
      </div>

      <div className="mt-4 rounded-lg border border-neutral-700 bg-neutral-900/40 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <span className="text-sm text-gray-400">
            {earnedCount} / {items.length} earned
          </span>
          <div className="flex gap-4 text-sm">
            {TIER_ORDER.map((t) => (
              <span key={t} className="flex items-center gap-1.5 text-gray-300">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={TIER_MEDAL_SRC[t]} alt={t} draggable={false} className="h-6 w-6 object-contain" />
                {t} <span className="font-bold text-white">{tierCounts[t]}</span>
              </span>
            ))}
          </div>
        </div>
      </div>

      {isOwner && (
        <div className="mt-4 flex flex-wrap items-center justify-between gap-2 rounded-lg border border-amber-700/40 bg-amber-950/20 p-3 text-sm">
          <span className="text-amber-200">
            ⭐ Click the star on any earned achievement to pin it to your character page showcase.
            <span className="ml-2 text-amber-400/80">
              {pinned.length} / {SHOWCASE_LIMIT} pinned
            </span>
          </span>
          {pinMessage && <span className="text-xs text-gray-400">{pinMessage}</span>}
        </div>
      )}

      <div className="mt-4 flex flex-wrap items-center gap-2">
        <button
          type="button"
          onClick={() => setFamily("all")}
          className={`rounded px-3 py-1.5 text-sm font-semibold ${
            family === "all" ? "bg-red-700 text-white" : "bg-neutral-800 text-gray-300 hover:bg-neutral-700"
          }`}
        >
          All
        </button>
        <button
          type="button"
          onClick={() => setFamily("oneOff")}
          title="Achievements that are earned once, with no Copper/Silver/Gold/Platinum tiers"
          className={`rounded px-3 py-1.5 text-sm font-semibold ${
            family === "oneOff" ? "bg-red-700 text-white" : "bg-neutral-800 text-gray-300 hover:bg-neutral-700"
          }`}
        >
          🎖️ One-Off <span className="font-normal text-gray-400">({oneOffCount})</span>
        </button>
        {familiesPresent.map((f) => (
          <button
            key={f}
            type="button"
            onClick={() => setFamily(f)}
            className={`rounded px-3 py-1.5 text-sm font-semibold ${
              family === f ? "bg-red-700 text-white" : "bg-neutral-800 text-gray-300 hover:bg-neutral-700"
            }`}
          >
            {FAMILY_META[f].icon} {FAMILY_META[f].label}
          </button>
        ))}

        <span className="mx-1 h-5 w-px bg-neutral-700" />

        <label className="flex items-center gap-1.5 text-sm text-gray-400">
          Sort by
          <select
            value={sort}
            onChange={(e) => setSort(e.target.value as SortMode)}
            className="rounded border border-neutral-700 bg-neutral-900 px-2 py-1 text-sm text-gray-200"
          >
            <option value="category">Category</option>
            <option value="alphabetical">Alphabetical</option>
            <option value="closest">Closest to completion</option>
            <option value="highestTier">Highest tier</option>
            <option value="recent">Recently progressed</option>
          </select>
        </label>
      </div>

      <div className="mt-4 flex flex-col gap-6">
        {grouped.map((group) => (
          <div key={group.family ?? "flat"}>
            {group.family && (
              <h2 className="mb-2 text-sm font-bold uppercase tracking-wide text-gray-400">
                {FAMILY_META[group.family].icon} {FAMILY_META[group.family].label}
              </h2>
            )}
            <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
              {group.items.map((item) => (
                <AchievementRow
                  key={item.key}
                  item={item}
                  isOwner={isOwner}
                  pinned={pinned.includes(item.key)}
                  onTogglePin={() => togglePin(item.key)}
                />
              ))}
            </div>
          </div>
        ))}
      </div>
    </main>
  );
}

function AchievementRow({
  item,
  isOwner,
  pinned,
  onTogglePin,
}: {
  item: AchievementBoardItem;
  isOwner: boolean;
  pinned: boolean;
  onTogglePin: () => void;
}) {
  // Bumped again (2026-09-25) - 48px -> 64px -> 80px, now that the badges
  // have proper hand-picked art instead of generic WoW CDN icons. Worth the
  // extra room to actually read the artwork here, where it's the main
  // visual on the row.
  const size = 80;
  const innerSize = Math.round(size * FRAME_HOLE_RATIO);
  const inset = Math.round((size - innerSize) / 2);

  // The bar now runs the FULL Copper -> Platinum range (previously it reset
  // to 0-100% of just "progress toward the next tier"), so the milestone
  // dots for every tier can sit at their real position along one bar.
  const maxThreshold = item.thresholds?.[item.thresholds.length - 1]?.value ?? 1;

  // Hover preview - blows the same art up big enough to actually see the
  // detail in it, since even at 80px a hand-painted badge icon is still
  // pretty small.
  const previewSize = 220;
  const previewInner = Math.round(previewSize * FRAME_HOLE_RATIO);
  const previewInset = Math.round((previewSize - previewInner) / 2);

  // Legacy Challenges (2026-09-27) have no hand-picked local art - there
  // are 111 of them, straight from Blizzard - so they fall back to the
  // real WoW icon via remoteIcon/iconUrlForFileId instead. Framed with the
  // exact same tier-frame/greyed-border treatment as a localIcon below, so
  // they're visually indistinguishable from a community achievement except
  // for which icon shows through the frame.
  const iconSrc = item.localIcon ? localBadgeIconSrc(item.localIcon) : iconUrlForFileId(item.remoteIcon);

  return (
    <div
      id={item.key}
      className={`flex items-center gap-3 rounded-lg border p-3 ${
        item.earned ? "border-neutral-700 bg-neutral-900/40" : "border-neutral-800 bg-neutral-900/20"
      }`}
    >
      <span className="group/rowicon relative inline-block shrink-0" style={{ width: size, height: size }}>
        {iconSrc ? (
          <>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={iconSrc}
              alt=""
              draggable={false}
              className={`absolute rounded-sm object-cover ${!item.earned ? "grayscale" : ""}`}
              style={
                item.tier || !item.earned
                  ? { width: innerSize, height: innerSize, top: inset, left: inset }
                  : { width: size, height: size, top: 0, left: 0 }
              }
            />
            {item.earned && item.tier && (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={TIER_FRAME_SRC[item.tier]}
                alt=""
                aria-hidden="true"
                draggable={false}
                className="pointer-events-none absolute inset-0 h-full w-full"
              />
            )}
            {!item.earned && (
              // Locked/not-yet-earned border (2026-09-26) - reuses the
              // Copper tier frame art, desaturated to grey via CSS filter
              // rather than a separate asset, so every un-earned badge
              // (tiered or flat/one-off) reads as "locked" at a glance
              // instead of just floating with no border at all.
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={TIER_FRAME_SRC.Copper}
                alt=""
                aria-hidden="true"
                draggable={false}
                className="pointer-events-none absolute inset-0 h-full w-full"
                style={{ filter: "grayscale(1) brightness(1.15)" }}
              />
            )}
          </>
        ) : (
          <BadgePlaceholder tier={item.tier} label={item.name} size={size} dim={!item.earned} />
        )}

        {/* Hover-to-enlarge preview of the badge art. */}
        <span
          role="tooltip"
          className="pointer-events-none absolute left-0 top-full z-30 mt-2 scale-95 rounded-lg border border-amber-700/70 bg-neutral-950 p-2 opacity-0 shadow-lg shadow-black/60 transition-all duration-100 group-hover/rowicon:scale-100 group-hover/rowicon:opacity-100"
        >
          <span className="relative block" style={{ width: previewSize, height: previewSize }}>
            {iconSrc ? (
              <>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={iconSrc}
                  alt=""
                  draggable={false}
                  className={`absolute rounded object-cover ${!item.earned ? "grayscale" : ""}`}
                  style={
                    item.tier || !item.earned
                      ? { width: previewInner, height: previewInner, top: previewInset, left: previewInset }
                      : { width: previewSize, height: previewSize, top: 0, left: 0 }
                  }
                />
                {item.earned && item.tier && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={TIER_FRAME_SRC[item.tier]}
                    alt=""
                    aria-hidden="true"
                    draggable={false}
                    className="pointer-events-none absolute inset-0 h-full w-full"
                  />
                )}
                {!item.earned && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={TIER_FRAME_SRC.Copper}
                    alt=""
                    aria-hidden="true"
                    draggable={false}
                    className="pointer-events-none absolute inset-0 h-full w-full"
                    style={{ filter: "grayscale(1) brightness(1.15)" }}
                  />
                )}
              </>
            ) : (
              <BadgePlaceholder tier={item.tier} label={item.name} size={previewSize} dim={!item.earned} />
            )}
          </span>
        </span>
      </span>

      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-baseline gap-2">
          <span className={`font-bold ${item.earned ? "text-white" : "text-gray-500"}`}>{item.name}</span>
          {item.tier && (
            <span
              className={`flex items-center gap-1 text-xs font-semibold ${
                item.earned ? "text-amber-400" : "text-gray-500"
              }`}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={TIER_MEDAL_SRC[item.tier]}
                alt=""
                draggable={false}
                className={`h-5 w-5 object-contain ${item.earned ? "" : "grayscale opacity-70"}`}
              />
              {item.tier}
            </span>
          )}
        </div>
        <div className="text-xs text-gray-500">{item.description}</div>

        {item.tiered ? (
          <>
            <MilestoneBar
              value={item.value ?? 0}
              maxValue={maxThreshold}
              thresholds={item.thresholds ?? []}
              className="w-full max-w-sm"
            />
            <div className="mt-1 text-[11px] text-gray-500">
              {(item.value ?? 0).toLocaleString()}
              {item.nextThreshold !== null ? ` / ${item.nextThreshold.toLocaleString()}` : " (maxed)"}
              {item.thresholds && (
                <span className="ml-2">
                  {item.thresholds.map((t) => `${t.tier} ${t.value.toLocaleString()}`).join(" · ")}
                </span>
              )}
            </div>
          </>
        ) : (
          <div className="mt-1 text-[11px] text-gray-500">{item.earned ? "Earned" : "Not yet earned"}</div>
        )}
      </div>

      {isOwner && item.earned && (
        <button
          type="button"
          onClick={onTogglePin}
          title={pinned ? "Remove from character page showcase" : "Pin to character page showcase"}
          className={`shrink-0 text-xl leading-none transition-colors ${
            pinned ? "text-amber-400" : "text-neutral-600 hover:text-amber-300"
          }`}
        >
          {pinned ? "★" : "☆"}
        </button>
      )}

      <span className={`shrink-0 text-sm font-bold ${item.earned ? "text-[#c9a566]" : "text-gray-600"}`}>
        {item.earned ? `+${item.points}` : "—"} pts
      </span>
    </div>
  );
}
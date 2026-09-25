import {
  TIERED_ACHIEVEMENT_KINDS,
  TIER_POINTS,
  tierLabel,
  tierDescription,
  tierFamily,
  tierThresholds,
  computeCounter,
  type AchievementTier,
  type TieredAchievementKind,
  type AchievementFamily,
} from "../lib/achievements";
import { FLAT_ACHIEVEMENT_FAMILY, FLAT_ACHIEVEMENT_NAME, FLAT_ACHIEVEMENT_POINTS } from "../lib/achievementCategories";
import type { AchievementKind } from "../lib/achievements";
import {
  ACHIEVEMENT_BADGES,
  RING_TIER_BADGES,
  TIERED_LOCAL_ICONS,
  FLAT_LOCAL_ICONS,
} from "../lib/achievementBadges";

// One shared shape covering BOTH flat and tiered achievements, built fresh
// from a character's achievement rows + live stats - used by both the
// character-page showcase (top few picks) and the full /achievements page
// (everything, filterable/sortable), so the two views can never disagree
// about what a character has earned or how close they are to the next
// tier. This is the single place that merges "what's earned" (the
// achievements table) with "what's the live progress" (character_statistics
// via computeCounter, same as the leaderboards page) and "what does it look
// like" (CharacterCard's icon/label tables).
export type AchievementBoardItem = {
  key: string; // the raw kind string - stable, used for links/anchors
  tiered: boolean;
  name: string;
  description: string;
  family: AchievementFamily;
  localIcon: string | null; // slug for /public/badge-icons/<slug>.png, if any
  cdnIcon: string; // WoW CDN icon name fallback for anything without local art yet
  earned: boolean;
  tier: AchievementTier | null; // tiered only
  points: number; // points earned so far from this one item (0 if unearned)
  value: number | null; // current live counter value, tiered only
  nextThreshold: number | null; // next uncleared threshold, tiered only (null once maxed)
  thresholds: { tier: AchievementTier; value: number }[] | null; // Copper-first, tiered only
  earnedAt: string | null;
};

export function buildAchievementItems({
  achievementRows,
  statRows,
  recipesCount,
}: {
  achievementRows: { kind: string; tier: AchievementTier | null; earned_at?: string | null }[];
  statRows: { category: string; name: string; value: string }[];
  recipesCount: number;
}): AchievementBoardItem[] {
  const byKind = new Map(achievementRows.map((a) => [a.kind, a]));
  const items: AchievementBoardItem[] = [];

  for (const kind of TIERED_ACHIEVEMENT_KINDS) {
    const row = byKind.get(kind);
    const tier = (row?.tier as AchievementTier | null | undefined) ?? null;
    const value = kind === "recipes" ? recipesCount : computeCounter(kind, statRows);
    const thresholds = tierThresholds(kind);
    const nextThreshold = thresholds.find((t) => t.value > value)?.value ?? null;
    const ring = RING_TIER_BADGES[kind as TieredAchievementKind];

    items.push({
      key: kind,
      tiered: true,
      name: tierLabel(kind),
      description: tierDescription(kind),
      family: tierFamily(kind),
      localIcon: TIERED_LOCAL_ICONS[kind] ?? null,
      cdnIcon: ring?.Copper.icon ?? "inv_misc_questionmark",
      earned: tier !== null,
      tier,
      points: tier ? TIER_POINTS[tier] : 0,
      value,
      nextThreshold,
      thresholds,
      earnedAt: row?.earned_at ?? null,
    });
  }

  for (const kind of Object.keys(ACHIEVEMENT_BADGES) as AchievementKind[]) {
    const row = byKind.get(kind);
    const badge = ACHIEVEMENT_BADGES[kind];
    items.push({
      key: kind,
      tiered: false,
      name: FLAT_ACHIEVEMENT_NAME[kind],
      description: badge.label,
      family: FLAT_ACHIEVEMENT_FAMILY[kind],
      localIcon: FLAT_LOCAL_ICONS[kind] ?? null,
      cdnIcon: badge.icon,
      earned: !!row,
      tier: null,
      points: row ? FLAT_ACHIEVEMENT_POINTS : 0,
      value: null,
      nextThreshold: null,
      thresholds: null,
      earnedAt: row?.earned_at ?? null,
    });
  }

  return items;
}

// How many achievements the character-page showcase can hold - shared by
// the auto-pick fallback below and by CharacterAchievementsPage's pin UI, so
// the cap can never drift between "what the player picked" and "how many
// the showcase strip actually has room for".
export const SHOWCASE_LIMIT = 8;

// Picks what the character-page showcase should feature.
//
// If the player has pinned specific achievements (characters.showcase_kinds,
// set from the "Choose showcase" picker on the full achievements page),
// those are shown, in the order the player pinned them - a pin that's no
// longer earned (e.g. a stat category got reset) is silently dropped rather
// than shown as a hole.
//
// Otherwise, falls back to the old automatic pick: earned items only,
// highest tier first (Platinum > Gold > Silver > Copper > flat), ties
// broken by most-recently-earned/progressed. No player input needed.
const TIER_RANK: Record<AchievementTier, number> = { Platinum: 3, Gold: 2, Silver: 1, Copper: 0 };

export function pickShowcaseItems(
  items: AchievementBoardItem[],
  options?: { pinnedKinds?: string[] | null; limit?: number }
): AchievementBoardItem[] {
  const limit = options?.limit ?? SHOWCASE_LIMIT;
  const pinnedKinds = options?.pinnedKinds;

  if (pinnedKinds && pinnedKinds.length > 0) {
    const byKey = new Map(items.map((i) => [i.key, i]));
    return pinnedKinds
      .map((kind) => byKey.get(kind))
      .filter((i): i is AchievementBoardItem => !!i && i.earned)
      .slice(0, limit);
  }

  return items
    .filter((i) => i.earned)
    .sort((a, b) => {
      const rankA = a.tier ? TIER_RANK[a.tier] : -1;
      const rankB = b.tier ? TIER_RANK[b.tier] : -1;
      if (rankA !== rankB) return rankB - rankA;
      const timeA = a.earnedAt ? new Date(a.earnedAt).getTime() : 0;
      const timeB = b.earnedAt ? new Date(b.earnedAt).getTime() : 0;
      return timeB - timeA;
    })
    .slice(0, limit);
}
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
  // slug for /public/badge-icons/<slug>.png, if any - null means this
  // achievement has no uploaded art yet, and every renderer now shows
  // BadgePlaceholder instead of falling back to a WoW CDN icon for it
  // (2026-09-25, "remove the old wow icon badges and only use the ones I
  // upload" - there used to be a `cdnIcon` field here for exactly that
  // fallback, removed along with the fallback itself).
  localIcon: string | null;
  // Blizzard's own icon fileID for a Legacy Challenge (2026-09-27) - used
  // instead of localIcon when there's no hand-picked art for this item
  // (every legacy achievement, since there are 111 of them and they're
  // Blizzard's own content, not something to commission art for). null for
  // every non-legacy item, which always has localIcon or BadgePlaceholder
  // instead.
  remoteIcon: number | null;
  earned: boolean;
  tier: AchievementTier | null; // tiered only
  points: number; // points earned so far from this one item (0 if unearned)
  value: number | null; // current live counter value, tiered only
  nextThreshold: number | null; // next uncleared threshold, tiered only (null once maxed)
  thresholds: { tier: AchievementTier; value: number }[] | null; // Copper-first, tiered only
  earnedAt: string | null;
  // Legacy Challenges only (2026-09-27) - Blizzard's own sub-category for
  // this achievement (e.g. "Dungeons", "Explorer", "Eastern Kingdoms"),
  // used to draw the same mini category headers the in-game Legacy
  // Challenges panel uses, nested under the single "Legacy Challenges"
  // family header. null for every non-legacy item.
  legacyCategory: string | null;
  // Legacy Challenges only - the full per-criteria checklist (e.g. one
  // entry per dungeon/zone required), collapsed by default and toggled
  // open the same way the in-game achievement pane's own +/- does. null
  // when there's nothing to expand (no criteria, or a non-legacy item).
  criteria: { text: string; completed: boolean }[] | null;
  // Legacy Challenges only (2026-09-27, "show which ones earn you legacy
  // points and which give nothing") - Blizzard's own row.points value,
  // shown regardless of whether this item is earned yet, so the UI can
  // flag "this one's worth nothing" up front rather than only after you've
  // completed it and gotten 0. null for non-legacy items (points there
  // always equal the achievement's fixed value once earned, no separate
  // "is this even eligible" question to answer).
  legacyPointValue: number | null;
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

    items.push({
      key: kind,
      tiered: true,
      name: tierLabel(kind),
      description: tierDescription(kind),
      family: tierFamily(kind),
      localIcon: TIERED_LOCAL_ICONS[kind] ?? null,
      remoteIcon: null,
      earned: tier !== null,
      tier,
      points: tier ? TIER_POINTS[tier] : 0,
      value,
      nextThreshold,
      thresholds,
      earnedAt: row?.earned_at ?? null,
      legacyCategory: null,
      criteria: null,
      legacyPointValue: null,
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
      remoteIcon: null,
      earned: !!row,
      tier: null,
      points: row ? FLAT_ACHIEVEMENT_POINTS : 0,
      value: null,
      nextThreshold: null,
      thresholds: null,
      earnedAt: row?.earned_at ?? null,
      legacyCategory: null,
      criteria: null,
      legacyPointValue: null,
    });
  }

  return items;
}

// Legacy Challenges (2026-09-27) - the real Blizzard-server Achievements
// pane (character_legacy_achievements, synced via the addon's
// collectLegacyAchievements()), turned into the exact same
// AchievementBoardItem shape as everything above so they render with
// identical borders, tier frames and milestone bars instead of a
// separately-styled section. The only real difference from a community
// achievement is where the points/tiers come from:
//   - A Legacy Challenge with 0 or 1 criteria (a plain "reach level 60")
//     becomes a flat item, same as a one-off site achievement - earned or
//     not, worth its own Blizzard achievement points (or
//     FLAT_ACHIEVEMENT_POINTS if Blizzard didn't report any).
//   - A Legacy Challenge with more than 1 criterion (e.g. "Explore
//     Durotar" - several zones to visit) becomes a tiered item, with
//     Copper/Silver/Gold/Platinum thresholds set at roughly 25/50/75/100%
//     of ITS OWN criteria count (see legacyThresholds below) - Blizzard
//     doesn't tier these itself, this site's cards do, for every
//     achievement, always.
export type LegacyAchievementRow = {
  achievement_id: number;
  category: string;
  name: string;
  description: string | null;
  completed: boolean;
  criteria: { text: string; completed: boolean }[] | null;
  icon: number | null;
  points: number | null;
};

// Copper/Silver/Gold/Platinum at ~25/50/75/100% of a legacy achievement's
// own criteria count. Fractions are rounded and deduped (Set) so a short
// checklist doesn't get several tiers landing on the same number; if
// dedup leaves fewer than 4 distinct values, the tier NAMES are
// right-aligned to the list (a 2-criteria achievement gets Gold at 1/2 and
// Platinum at 2/2, not Copper/Silver) so the achievement is never
// "maxed out" at anything less than Platinum.
const LEGACY_TIER_NAMES: AchievementTier[] = ["Copper", "Silver", "Gold", "Platinum"];

function legacyThresholds(total: number): { tier: AchievementTier; value: number }[] {
  const values = Array.from(
    new Set([0.25, 0.5, 0.75, 1].map((f) => Math.min(total, Math.max(1, Math.round(total * f)))))
  ).sort((a, b) => a - b);
  // Force the top threshold to exactly the full criteria count - rounding
  // above can otherwise leave Platinum one short of "everything done".
  values[values.length - 1] = total;
  const names = LEGACY_TIER_NAMES.slice(LEGACY_TIER_NAMES.length - values.length);
  return values.map((value, i) => ({ tier: names[i], value }));
}

// Legacy Points (2026-09-27, corrected same day after Jordan found the
// in-game "Legacy Points 0/65" header + each achievement's own shield badge
// tooltip, "Earn 1 Legacy Point") - that badge IS Blizzard's own
// GetAchievementInfo `points` field, just repurposed by this server as the
// Legacy Point value instead of the usual 5/10/25 achievement-point scale.
// Confirmed: only some achievements (e.g. the ones under "Adventure") carry
// a nonzero points value at all - the other ~46 (class-only, profession-only,
// etc.) are just regular achievements sharing this same panel and report 0.
// So this is NOT a flat 1-per-challenge award (that was wrong - it would
// total 111 once everything's done, not 65) - it pays out row.points itself,
// which is already captured by the addon and naturally sums to 65 across the
// account once every legacy-point-eligible achievement is completed.
export function buildLegacyAchievementItems(rows: LegacyAchievementRow[]): AchievementBoardItem[] {
  return rows.map((row) => {
    const criteria = row.criteria ?? [];
    const total = criteria.length;
    const done = criteria.filter((c) => c.completed).length;
    const key = `legacy_${row.achievement_id}`;
    const pointValue = row.points ?? 0;

    if (total <= 1) {
      return {
        key,
        tiered: false,
        name: row.name,
        description: row.description ?? "",
        family: "legacy",
        localIcon: null,
        remoteIcon: row.icon ?? null,
        earned: row.completed,
        tier: null,
        points: row.completed ? pointValue : 0,
        value: null,
        nextThreshold: null,
        thresholds: null,
        earnedAt: null,
        legacyCategory: row.category,
        // 0-1 criteria means there's nothing worth collapsing/expanding -
        // the description line above already says everything there is.
        criteria: null,
        legacyPointValue: pointValue,
      };
    }

    const thresholds = legacyThresholds(total);
    const tier = [...thresholds].reverse().find((t) => done >= t.value)?.tier ?? null;
    const nextThreshold = thresholds.find((t) => t.value > done)?.value ?? null;
    const fullyDone = done >= total;

    return {
      key,
      tiered: true,
      name: row.name,
      description: row.description ?? "",
      family: "legacy",
      localIcon: null,
      remoteIcon: row.icon ?? null,
      earned: tier !== null,
      tier,
      points: fullyDone ? pointValue : 0,
      value: done,
      nextThreshold,
      thresholds,
      earnedAt: null,
      legacyCategory: row.category,
      criteria,
      legacyPointValue: pointValue,
    };
  });
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

// Splits a set of Legacy Challenge items into Blizzard's own sub-categories
// (e.g. "Dungeons", "Explorer", "Eastern Kingdoms") for the mini-header
// layout on AccountLegacyPage - alphabetical, "Other" (achievements synced
// before the addon captured a category) sorted last rather than wherever
// "O" happens to land.
export function groupByLegacyCategory(items: AchievementBoardItem[]): [string, AchievementBoardItem[]][] {
  const map = new Map<string, AchievementBoardItem[]>();
  for (const item of items) {
    const category = item.legacyCategory ?? "Other";
    const list = map.get(category) ?? [];
    list.push(item);
    map.set(category, list);
  }
  return Array.from(map.entries()).sort(([a], [b]) => {
    if (a === "Other") return 1;
    if (b === "Other") return -1;
    return a.localeCompare(b);
  });
}
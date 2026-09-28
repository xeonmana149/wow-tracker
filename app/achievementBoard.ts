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
  hoursPlayed,
}: {
  achievementRows: { kind: string; tier: AchievementTier | null; earned_at?: string | null }[];
  statRows: { category: string; name: string; value: string }[];
  recipesCount: number;
  // "addicted"'s live value (2026-09-27 fix) - not sourced from statRows
  // like every other tiered kind (TIER_COUNTERS.addicted is intentionally
  // empty - see achievements.ts), so computeCounter() always returned 0 for
  // it, leaving the achievement correctly tiered but showing a stuck "0" on
  // its progress bar. Optional/defaults to 0 so callers that haven't been
  // updated yet don't break, just show 0 same as before.
  hoursPlayed?: number;
}): AchievementBoardItem[] {
  const byKind = new Map(achievementRows.map((a) => [a.kind, a]));
  const items: AchievementBoardItem[] = [];

  for (const kind of TIERED_ACHIEVEMENT_KINDS) {
    const row = byKind.get(kind);
    const tier = (row?.tier as AchievementTier | null | undefined) ?? null;
    const value =
      kind === "recipes" ? recipesCount : kind === "addicted" ? hoursPlayed ?? 0 : computeCounter(kind, statRows);
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
  // Blizzard's own GetAchievementInfo points value - CONFIRMED WRONG/
  // UNRELATED as of 2026-09-27 (0 for achievements that genuinely award real
  // Legacy Points in game). Kept only for reference/debugging. See
  // ui_points below for the real value.
  points: number | null;
  // The REAL Legacy Point value (addon 1.8.8+), scraped straight off the
  // rendered Legacy Challenges panel by the addon since no API exposes it -
  // see scanLegacyPointsFromUI() in the addon. null until that achievement's
  // row has been seen on screen at least once.
  ui_points: number | null;
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

// Legacy Points (2026-09-27, corrected TWICE the same day) - first guess was
// a flat 1-per-challenge (wrong - totals 111, not 65). Second guess was that
// Blizzard's own GetAchievementInfo `points` field was secretly the Legacy
// Point value (also wrong - confirmed via manual in-game frame inspection
// that it comes back 0 for achievements that genuinely award real points,
// like "Explorer" and "Lord Valthalak Laid to Rest"). The real number turned
// out not to be exposed through ANY API at all - it only exists as rendered
// text in the Legacy Challenges panel's own UI (a small "shield" button next
// to each achievement showing just its point value), which the addon
// (v1.8.8+) now scrapes directly off screen as the panel gets browsed - see
// scanLegacyPointsFromUI() in the addon. This uses THAT value (row.ui_points)
// - not row.points, which stays around for reference only. Someone browsing
// every category tab at least once will naturally fill in the real 65-point
// total; anything not yet seen shows as 0 until then.
export function buildLegacyAchievementItems(rows: LegacyAchievementRow[]): AchievementBoardItem[] {
  return rows.map((row) => {
    const criteria = row.criteria ?? [];
    const total = criteria.length;
    const done = criteria.filter((c) => c.completed).length;
    const key = `legacy_${row.achievement_id}`;
    const pointValue = row.ui_points ?? 0;

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

// Condenses Blizzard's ~24 raw Legacy Challenge categories (its own class,
// profession, PvP-rank and zone names) down into 6 broad groups for
// AccountLegacyPage's filter pills and section headers (2026-09-28, Jordan's
// request - the raw list ("Adventure", "Alchemy", "Blacksmithing", "Druid",
// "Dungeons", "Eastern Kingdoms", "Enchanting", "Engineering", "Explorer",
// "Hunter", "Kalimdor", "Leatherworking", "Mage", "Paladin", "Priest",
// "Raids", "Ranks", "Reputations", "Rogue", "Season Journey", "Shaman",
// "Tailoring", "Warlock", "Warrior") was too long to scan at a glance).
// Anything not explicitly mapped falls back to "Adventure" rather than an
// awkward extra "Other" bucket - every raw category seen so far that isn't a
// class, a profession, a PvP rank, Dungeons or Raids (Adventure, Explorer,
// Eastern Kingdoms, Kalimdor, Reputations, Season Journey) is
// exploration/world content anyway, so that's the natural catch-all.
const LEGACY_CATEGORY_GROUPS: Record<string, string> = {
  Druid: "Classes",
  Hunter: "Classes",
  Mage: "Classes",
  Paladin: "Classes",
  Priest: "Classes",
  Rogue: "Classes",
  Shaman: "Classes",
  Warlock: "Classes",
  Warrior: "Classes",
  Alchemy: "Tradeskills",
  Blacksmithing: "Tradeskills",
  Enchanting: "Tradeskills",
  Engineering: "Tradeskills",
  Leatherworking: "Tradeskills",
  Tailoring: "Tradeskills",
  Ranks: "Player vs. Player",
  Dungeons: "Dungeons",
  Raids: "Raids",
};

// Fixed display order for the 6 groups - not alphabetical, matches how
// Jordan actually thinks about them (Classes/Tradeskills/PvP first as the
// "systems", then the 3 content buckets).
export const LEGACY_CATEGORY_GROUP_ORDER = [
  "Classes",
  "Tradeskills",
  "Player vs. Player",
  "Adventure",
  "Dungeons",
  "Raids",
];

export function legacyCategoryGroup(rawCategory: string | null): string {
  if (!rawCategory) return "Adventure";
  return LEGACY_CATEGORY_GROUPS[rawCategory] ?? "Adventure";
}

// Splits a set of Legacy Challenge items into the 6 condensed groups above
// for the mini-header layout on AccountLegacyPage - fixed order (see
// LEGACY_CATEGORY_GROUP_ORDER), not alphabetical.
export function groupByLegacyCategory(items: AchievementBoardItem[]): [string, AchievementBoardItem[]][] {
  const map = new Map<string, AchievementBoardItem[]>();
  for (const item of items) {
    const group = legacyCategoryGroup(item.legacyCategory);
    const list = map.get(group) ?? [];
    list.push(item);
    map.set(group, list);
  }
  return Array.from(map.entries()).sort(([a], [b]) => {
    const ai = LEGACY_CATEGORY_GROUP_ORDER.indexOf(a);
    const bi = LEGACY_CATEGORY_GROUP_ORDER.indexOf(b);
    return (ai === -1 ? 99 : ai) - (bi === -1 ? 99 : bi);
  });
}
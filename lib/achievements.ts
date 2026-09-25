import type { SupabaseClient } from "@supabase/supabase-js";
import { LAUNCH_TIME } from "./roadmap";

// Plain yes/no achievements - anyone can earn any of these, as many times
// as it takes across the group. Includes both the original flat badges and
// the 2026-09-25 "personality badge" additions (single-threshold, sourced
// from combined Social-pane stats) - those don't need a 4-tier ladder, just
// a nice one-off callout.
export type AchievementKind =
  | "max_level"
  | "legendary_item"
  | "maxed_profession"
  | "renaissance"
  | "maxed_legacy"
  | "top_pvp_rank"
  | "founding_member"
  | "hugger"
  | "comedian"
  | "drama_queen"
  | "tiny_violinist"
  | "greeter";

// The tiered (Copper/Silver/Gold/Platinum) achievements - the "curated ~30
// counters on top of 159 raw stats" system from the 2026-09-25 leaderboards
// rework. Kind strings are UNCHANGED from the previous 3-tier system for
// the 8 that already existed (gold, epic_gear, recipes, honorable_kills,
// creatures_killed, quests_completed, killing_blows, boss_kills) so
// existing earned rows in the database stay valid - only their tier
// thresholds and display names changed. consumables/travel/social are new.
//
// Display name per kind (what shows up in the UI) lives in ACHIEVEMENT_META
// below, not in the kind string itself - kind strings stay stable/internal.
export type TieredAchievementKind =
  | "gold" // "Deep Pockets"
  | "epic_gear" // "Well-Equipped"
  | "recipes" // "Artisan"
  | "honorable_kills" // "Gladiator"
  | "creatures_killed" // "Monster Hunter"
  | "quests_completed" // "Adventurer"
  | "killing_blows" // "Executioner"
  | "boss_kills" // "Slayer"
  | "consumables" // "Well Supplied"
  | "travel" // "Wayfarer"
  | "social"; // "Social Butterfly"

export type AchievementTier = "Copper" | "Silver" | "Gold" | "Platinum";
// Kept as an alias so older code that still says GoldTier keeps working -
// same type, just also exported under its original name.
export type GoldTier = AchievementTier;

const TIER_RANK: Record<AchievementTier, number> = { Copper: 0, Silver: 1, Gold: 2, Platinum: 3 };

// Non-stacking points toward the leaderboards "Overall" score - reaching
// Platinum is worth 50 points total, not 5+15+30+50. Easy to retune later,
// this is just one small table.
export const TIER_POINTS: Record<AchievementTier, number> = {
  Copper: 5,
  Silver: 15,
  Gold: 30,
  Platinum: 50,
};

type TierThreshold = { tier: AchievementTier; value: number };

type TierDef = {
  // The display name used everywhere in the UI (leaderboards, badge
  // tooltips) - the kind string itself never changes, this can.
  label: string;
  description: string;
  family: AchievementFamily;
  thresholds: TierThreshold[];
  // format() renders the "reached a tier" activity-feed message.
  format: (name: string, tier: AchievementTier, value: number) => string;
};

export type AchievementFamily =
  | "combat"
  | "pvp"
  | "adventure"
  | "professions"
  | "wealth"
  | "character"
  | "social";

export const FAMILY_META: Record<AchievementFamily, { label: string; icon: string }> = {
  combat: { label: "Combat", icon: "⚔️" },
  pvp: { label: "PvP", icon: "🏆" },
  adventure: { label: "Adventure", icon: "📜" },
  professions: { label: "Professions", icon: "🔨" },
  wealth: { label: "Wealth", icon: "💰" },
  character: { label: "Character", icon: "🧝" },
  social: { label: "Social", icon: "🎭" },
};

// Each threshold table is ordered Platinum-first so `.find()` picks the
// highest tier the current value already qualifies for. These starting
// numbers are estimates, not tuned against real group data yet - expect to
// adjust them once a few characters have real Statistics history built up.
const TIER_DEFS: Record<TieredAchievementKind, TierDef> = {
  gold: {
    label: "Deep Pockets",
    description: "Lifetime gold acquired.",
    family: "wealth",
    thresholds: [
      { tier: "Platinum", value: 25000 },
      { tier: "Gold", value: 5000 },
      { tier: "Silver", value: 500 },
      { tier: "Copper", value: 50 },
    ],
    format: (name, tier, value) => `${name} has acquired ${value.toLocaleString()}+ gold - ${tier} tier!`,
  },
  epic_gear: {
    label: "Well-Equipped",
    description: "Distinct Epic items acquired, lifetime.",
    family: "character",
    thresholds: [
      { tier: "Platinum", value: 10 },
      { tier: "Gold", value: 5 },
      { tier: "Silver", value: 3 },
      { tier: "Copper", value: 1 },
    ],
    format: (name, tier, value) => `${name} has acquired ${value}+ Epic items - ${tier} tier!`,
  },
  recipes: {
    label: "Artisan",
    description: "Total recipes known across every profession.",
    family: "professions",
    thresholds: [
      { tier: "Platinum", value: 750 },
      { tier: "Gold", value: 350 },
      { tier: "Silver", value: 150 },
      { tier: "Copper", value: 50 },
    ],
    format: (name, tier, value) => `${name} knows ${value}+ recipes - ${tier} tier!`,
  },
  honorable_kills: {
    label: "Gladiator",
    description: "Honorable Kills earned in PvP.",
    family: "pvp",
    thresholds: [
      { tier: "Platinum", value: 1000 },
      { tier: "Gold", value: 200 },
      { tier: "Silver", value: 50 },
      { tier: "Copper", value: 10 },
    ],
    format: (name, tier, value) => `${name} has ${value}+ Honorable Kills - ${tier} tier!`,
  },
  creatures_killed: {
    label: "Monster Hunter",
    description: "Creatures killed across Azeroth.",
    family: "combat",
    thresholds: [
      { tier: "Platinum", value: 20000 },
      { tier: "Gold", value: 5000 },
      { tier: "Silver", value: 1000 },
      { tier: "Copper", value: 250 },
    ],
    format: (name, tier, value) => `${name} has slain ${value.toLocaleString()}+ creatures - ${tier} tier!`,
  },
  quests_completed: {
    label: "Adventurer",
    description: "Quests completed throughout Azeroth.",
    family: "adventure",
    thresholds: [
      { tier: "Platinum", value: 1000 },
      { tier: "Gold", value: 500 },
      { tier: "Silver", value: 200 },
      { tier: "Copper", value: 50 },
    ],
    format: (name, tier, value) => `${name} has completed ${value}+ quests - ${tier} tier!`,
  },
  killing_blows: {
    label: "Executioner",
    description: "Killing Blows landed in combat.",
    family: "combat",
    thresholds: [
      { tier: "Platinum", value: 1500 },
      { tier: "Gold", value: 500 },
      { tier: "Silver", value: 150 },
      { tier: "Copper", value: 25 },
    ],
    format: (name, tier, value) => `${name} has ${value}+ Killing Blows - ${tier} tier!`,
  },
  boss_kills: {
    label: "Slayer",
    description: "Dungeon and raid bosses defeated (every boss counter added together).",
    family: "combat",
    thresholds: [
      { tier: "Platinum", value: 500 },
      { tier: "Gold", value: 150 },
      { tier: "Silver", value: 50 },
      { tier: "Copper", value: 10 },
    ],
    format: (name, tier, value) => `${name} has ${value}+ boss kills - ${tier} tier!`,
  },
  consumables: {
    label: "Well Supplied",
    description: "Food, drinks, potions, bandages and other consumables used, combined.",
    family: "character",
    thresholds: [
      { tier: "Platinum", value: 8000 },
      { tier: "Gold", value: 2000 },
      { tier: "Silver", value: 500 },
      { tier: "Copper", value: 100 },
    ],
    format: (name, tier, value) => `${name} has used ${value.toLocaleString()}+ consumables - ${tier} tier!`,
  },
  travel: {
    label: "Wayfarer",
    description: "Flight paths, mage portals, hearths and summons used, combined.",
    family: "adventure",
    thresholds: [
      { tier: "Platinum", value: 4000 },
      { tier: "Gold", value: 1000 },
      { tier: "Silver", value: 250 },
      { tier: "Copper", value: 50 },
    ],
    format: (name, tier, value) => `${name} has used fast travel ${value.toLocaleString()}+ times - ${tier} tier!`,
  },
  social: {
    label: "Social Butterfly",
    description: "Hugs, cheers, facepalms, LOLs, violins and waves, combined.",
    family: "social",
    thresholds: [
      { tier: "Platinum", value: 4000 },
      { tier: "Gold", value: 1000 },
      { tier: "Silver", value: 250 },
      { tier: "Copper", value: 50 },
    ],
    format: (name, tier, value) => `${name} has performed ${value.toLocaleString()}+ social emotes - ${tier} tier!`,
  },
};

export const ACHIEVEMENT_MESSAGE: Record<AchievementKind, (name: string) => string> = {
  max_level: (name) => `${name} reached the level cap!`,
  legendary_item: (name) => `${name} obtained a Legendary item!`,
  maxed_profession: (name) => `${name} maxed a profession!`,
  renaissance: (name) => `${name} maxed every profession - a true Renaissance character!`,
  maxed_legacy: (name) => `${name} maxed the account's Legacy points!`,
  top_pvp_rank: (name) => `${name} reached the top PvP rank!`,
  founding_member: (name) => `${name} earned the Founding Member badge!`,
  hugger: (name) => `${name} has given 100+ hugs - Hugger!`,
  comedian: (name) => `${name} has LOL'd 100+ times - Comedian!`,
  drama_queen: (name) => `${name} has facepalmed 100+ times - Drama Queen!`,
  tiny_violinist: (name) => `${name} has played the world's smallest violin 100+ times - Tiny Violinist!`,
  greeter: (name) => `${name} has waved 250+ times - Greeter!`,
};

// One-off "personality badges" - single threshold, no tiers, sourced from
// individual Social-pane stats (not the combined "social" counter above,
// which feeds Social Butterfly instead). Exported so importLogic.ts can
// loop over them generically instead of one hardcoded if-block per badge.
export const PERSONALITY_BADGES: {
  kind: AchievementKind;
  category: string;
  name: string;
  threshold: number;
}[] = [
  { kind: "hugger", category: "Social", name: "Number of hugs", threshold: 100 },
  { kind: "comedian", category: "Social", name: "Total times LOL'd", threshold: 100 },
  { kind: "drama_queen", category: "Social", name: "Total facepalms", threshold: 100 },
  {
    kind: "tiny_violinist",
    category: "Social",
    name: "Total times playing world's smallest violin",
    threshold: 100,
  },
  { kind: "greeter", category: "Social", name: "Total waves", threshold: 250 },
];

// Which character_statistics rows feed each tiered achievement's counter.
// A plain {category,name} sums that one stat; {categoryOnly} sums EVERY
// stat under that raw category (used for boss_kills, where Blizzard tracks
// one counter per boss rather than a single aggregate). "recipes" is left
// as an empty list on purpose - it's computed from character_professions,
// not character_statistics, so importLogic.ts special-cases it instead.
//
// This is the single source of truth for "what feeds what" - both the
// sync route (importLogic.ts, via computeCounter below) and the
// leaderboards page use it, so the award logic and the display can never
// drift apart.
export type StatSelector = { category: string; name: string } | { categoryOnly: string };

export const TIER_COUNTERS: Record<TieredAchievementKind, StatSelector[]> = {
  gold: [{ category: "Wealth", name: "Total gold acquired" }],
  epic_gear: [{ category: "Gear", name: "Epic items acquired" }],
  recipes: [],
  honorable_kills: [{ category: "Honorable Kills", name: "Total Honorable Kills" }],
  creatures_killed: [{ category: "Creatures", name: "Creatures killed" }],
  quests_completed: [{ category: "Quests", name: "Quests completed" }],
  killing_blows: [{ category: "Killing Blows", name: "Total Killing Blows" }],
  boss_kills: [{ categoryOnly: "Boss Kills" }],
  consumables: [
    { category: "Consumables", name: "Bandages used" },
    { category: "Consumables", name: "Beverages consumed" },
    { category: "Consumables", name: "Elixirs consumed" },
    { category: "Consumables", name: "Flasks consumed" },
    { category: "Consumables", name: "Food eaten" },
    { category: "Consumables", name: "Health potions consumed" },
    { category: "Consumables", name: "Healthstones used" },
    { category: "Consumables", name: "Mana potions consumed" },
  ],
  travel: [
    { category: "Travel", name: "Flight paths taken" },
    { category: "Travel", name: "Mage Portals taken" },
    { category: "Travel", name: "Number of times hearthed" },
    { category: "Travel", name: "Summons accepted" },
  ],
  social: [
    { category: "Social", name: "Number of hugs" },
    { category: "Social", name: "Total cheers" },
    { category: "Social", name: "Total facepalms" },
    { category: "Social", name: "Total times LOL'd" },
    { category: "Social", name: "Total times playing world's smallest violin" },
    { category: "Social", name: "Total waves" },
  ],
};

// Sums whichever raw stats feed a given tiered kind, out of an arbitrary
// list of {category, name, value} rows (value as the client formats it,
// e.g. "1,502" or "--"). Shared by importLogic.ts (fed one character's
// freshly-parsed export) and the leaderboards page (fed one character's
// full character_statistics rows).
export function computeCounter(
  kind: TieredAchievementKind,
  stats: { category: string; name: string; value: string }[]
): number {
  const selectors = TIER_COUNTERS[kind];
  let total = 0;
  for (const sel of selectors) {
    if ("categoryOnly" in sel) {
      for (const s of stats) {
        if (s.category === sel.categoryOnly) {
          const n = Number(s.value.replace(/,/g, ""));
          if (Number.isFinite(n)) total += n;
        }
      }
    } else {
      const row = stats.find((s) => s.category === sel.category && s.name === sel.name);
      if (row) {
        const n = Number(row.value.replace(/,/g, ""));
        if (Number.isFinite(n)) total += n;
      }
    }
  }
  return total;
}

// Awards a plain (non-tiered) achievement to a character. Safe to call
// every time the underlying condition is true, not just the first moment
// it becomes true - (character_id, kind) is a unique constraint, so a
// repeat call just hits the conflict and is quietly ignored.
// Returns true only when this call is the one that actually earned it.
export async function awardAchievement(
  supabase: SupabaseClient,
  characterId: string,
  kind: AchievementKind
): Promise<boolean> {
  const { data, error } = await supabase
    .from("achievements")
    .upsert(
      { character_id: characterId, kind },
      { onConflict: "character_id,kind", ignoreDuplicates: true }
    )
    .select("kind");
  if (error) return false;
  return (data?.length ?? 0) > 0;
}

// Generic snapshot-based tier upgrade: every tiered achievement is "does
// the character's CURRENT value for this thing clear a threshold", derived
// fresh each sync rather than incrementally tracked. Returns the newly
// reached tier only when this call is what pushed the character into a
// HIGHER tier than it already held, so the activity feed doesn't repeat
// itself every sync.
export async function awardTier(
  supabase: SupabaseClient,
  characterId: string,
  kind: TieredAchievementKind,
  currentValue: number
): Promise<AchievementTier | null> {
  const def = TIER_DEFS[kind];
  const reached = def.thresholds.find((t) => currentValue >= t.value);
  if (!reached) return null;

  const { data: existing } = await supabase
    .from("achievements")
    .select("tier")
    .eq("character_id", characterId)
    .eq("kind", kind)
    .maybeSingle();

  const existingRank = existing?.tier ? TIER_RANK[existing.tier as AchievementTier] : -1;
  if (TIER_RANK[reached.tier] <= existingRank) return null;

  const { error } = await supabase
    .from("achievements")
    .upsert(
      { character_id: characterId, kind, tier: reached.tier },
      { onConflict: "character_id,kind" }
    );
  if (error) return null;
  return reached.tier;
}

export const TIERED_ACHIEVEMENT_KINDS: TieredAchievementKind[] = [
  "gold",
  "epic_gear",
  "recipes",
  "honorable_kills",
  "creatures_killed",
  "quests_completed",
  "killing_blows",
  "boss_kills",
  "consumables",
  "travel",
  "social",
];

export function tierLabel(kind: TieredAchievementKind): string {
  return TIER_DEFS[kind].label;
}

export function tierDescription(kind: TieredAchievementKind): string {
  return TIER_DEFS[kind].description;
}

export function tierFamily(kind: TieredAchievementKind): AchievementFamily {
  return TIER_DEFS[kind].family;
}

// Thresholds in tier order, Copper first - the natural reading order for a
// progress bar ("Copper 50 - Silver 500 - Gold 5000 - Platinum 25000"),
// the reverse of how TIER_DEFS stores them (Platinum-first, for the
// "highest tier already reached" lookup in awardTier above).
export function tierThresholds(kind: TieredAchievementKind): TierThreshold[] {
  return [...TIER_DEFS[kind].thresholds].reverse();
}

export function tierMessage(
  kind: TieredAchievementKind,
  name: string,
  tier: AchievementTier
): string {
  const def = TIER_DEFS[kind];
  const threshold = def.thresholds.find((t) => t.tier === tier);
  return def.format(name, tier, threshold?.value ?? 0);
}

// When the server goes live - characters created from that moment through
// one week after count as Founding Members. Reuses the exact same
// constant the countdown banner counts down to, so this never drifts out
// of sync with it.
const LAUNCH_DATE = new Date(LAUNCH_TIME);
const FOUNDING_MEMBER_CUTOFF = new Date(LAUNCH_DATE.getTime() + 7 * 24 * 60 * 60 * 1000);

export function isWithinFoundingWindow(createdAt: string): boolean {
  const created = new Date(createdAt);
  return created >= LAUNCH_DATE && created <= FOUNDING_MEMBER_CUTOFF;
}
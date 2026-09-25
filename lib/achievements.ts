import type { SupabaseClient } from "@supabase/supabase-js";
import { LAUNCH_TIME } from "./roadmap";

// Casual, per-character achievements - anyone can earn any of these, as
// many times as it takes across the group (this replaced an earlier
// "first to..." design where only one character server-wide could ever
// hold a given badge - these are meant to be collectible, not competed
// over).
export type AchievementKind =
  | "max_level"
  | "legendary_item"
  | "maxed_profession"
  | "renaissance"
  | "maxed_legacy"
  | "top_pvp_rank"
  | "founding_member";

// The tiered (Bronze/Silver/Gold) achievements. As of 2026-09-25 these are
// all driven off the real in-game Statistics pane data the addon now
// reports (character_statistics / parsed.statistics), rather than fields
// this site was tracking itself:
//  - "gold" used to be a snapshot of the character's CURRENT bank balance
//    (money_copper) - now it's "Total gold acquired", a lifetime total, so
//    spending gold never takes the badge away.
//  - "epic_gear" used to be our own running count, incremented every time
//    a new Epic item was seen equipped (missed anything equipped before
//    this feature existed) - now it's the game's own "Epic items acquired"
//    stat, which is authoritative and already accounts for your whole
//    history.
//  - "recipes" was already snapshot-based (total known recipes across
//    professions) and isn't a Statistics-pane stat, so it's unchanged.
//  - honorable_kills/creatures_killed/quests_completed/killing_blows/
//    boss_kills are new, made possible by the richer data.
export type TieredAchievementKind =
  | "gold"
  | "epic_gear"
  | "recipes"
  | "honorable_kills"
  | "creatures_killed"
  | "quests_completed"
  | "killing_blows"
  | "boss_kills";

export type GoldTier = "Bronze" | "Silver" | "Gold";

const TIER_RANK: Record<GoldTier, number> = { Bronze: 0, Silver: 1, Gold: 2 };

type TierThreshold = { tier: GoldTier; value: number };

type TierDef = {
  thresholds: TierThreshold[];
  // format() renders the "reached a tier" activity-feed message. Takes the
  // character name, the tier reached, and the threshold value that earned
  // it (thresholds are in whatever unit that kind's caller passes in - see
  // the comment on each threshold table below).
  format: (name: string, tier: GoldTier, value: number) => string;
};

// Each threshold table is ordered Gold-first so `.find()` picks the
// highest tier the current value already qualifies for.
const TIER_DEFS: Record<TieredAchievementKind, TierDef> = {
  // Values in whole gold (not copper) - matches how the Statistics pane's
  // own "Total gold acquired" stat is already formatted, so the numbers
  // here are exactly what you'd see in-game.
  gold: {
    thresholds: [
      { tier: "Gold", value: 5000 },
      { tier: "Silver", value: 500 },
      { tier: "Bronze", value: 50 },
    ],
    format: (name, tier, value) => `${name} has acquired ${value.toLocaleString()}+ gold - ${tier} tier!`,
  },
  // Distinct Epic items acquired, lifetime - the game's own count now, not
  // ours (see the type comment above).
  epic_gear: {
    thresholds: [
      { tier: "Gold", value: 5 },
      { tier: "Silver", value: 3 },
      { tier: "Bronze", value: 1 },
    ],
    format: (name, tier, value) => `${name} has acquired ${value}+ Epic items - ${tier} tier!`,
  },
  // Total known recipes across every profession - not a Statistics-pane
  // stat, still computed the same way it always was (see importLogic.ts).
  recipes: {
    thresholds: [
      { tier: "Gold", value: 500 },
      { tier: "Silver", value: 250 },
      { tier: "Bronze", value: 50 },
    ],
    format: (name, tier, value) => `${name} knows ${value}+ recipes - ${tier} tier!`,
  },
  honorable_kills: {
    thresholds: [
      { tier: "Gold", value: 200 },
      { tier: "Silver", value: 50 },
      { tier: "Bronze", value: 10 },
    ],
    format: (name, tier, value) =>
      `${name} has ${value}+ Honorable Kills - ${tier} tier!`,
  },
  creatures_killed: {
    thresholds: [
      { tier: "Gold", value: 5000 },
      { tier: "Silver", value: 1000 },
      { tier: "Bronze", value: 250 },
    ],
    format: (name, tier, value) =>
      `${name} has slain ${value.toLocaleString()}+ creatures - ${tier} tier!`,
  },
  quests_completed: {
    thresholds: [
      { tier: "Gold", value: 150 },
      { tier: "Silver", value: 75 },
      { tier: "Bronze", value: 25 },
    ],
    format: (name, tier, value) => `${name} has completed ${value}+ quests - ${tier} tier!`,
  },
  killing_blows: {
    thresholds: [
      { tier: "Gold", value: 500 },
      { tier: "Silver", value: 150 },
      { tier: "Bronze", value: 25 },
    ],
    format: (name, tier, value) => `${name} has ${value}+ Killing Blows - ${tier} tier!`,
  },
  // Not a single Blizzard stat - summed by importLogic.ts across every
  // individual boss entry under the Boss Kills category (there's no
  // aggregate "total boss kills" stat, just one counter per boss).
  boss_kills: {
    thresholds: [
      { tier: "Gold", value: 150 },
      { tier: "Silver", value: 50 },
      { tier: "Bronze", value: 10 },
    ],
    format: (name, tier, value) => `${name} has ${value}+ boss kills - ${tier} tier!`,
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
};

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
// fresh each sync rather than incrementally tracked - so a badge is never
// missed for something that was already true before this feature existed
// (unlike the old hand-rolled epic_gear counter, which only ever counted
// NEW equips going forward). Returns the newly-reached tier only when this
// call is what pushed the character into a HIGHER tier than it already
// held, so the activity feed doesn't repeat itself every sync.
export async function awardTier(
  supabase: SupabaseClient,
  characterId: string,
  kind: TieredAchievementKind,
  currentValue: number
): Promise<GoldTier | null> {
  const def = TIER_DEFS[kind];
  const reached = def.thresholds.find((t) => currentValue >= t.value);
  if (!reached) return null;

  const { data: existing } = await supabase
    .from("achievements")
    .select("tier")
    .eq("character_id", characterId)
    .eq("kind", kind)
    .maybeSingle();

  const existingRank = existing?.tier ? TIER_RANK[existing.tier as GoldTier] : -1;
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
];

export function tierMessage(
  kind: TieredAchievementKind,
  name: string,
  tier: GoldTier
): string {
  const def = TIER_DEFS[kind];
  const threshold = def.thresholds.find((t) => t.tier === tier);
  return def.format(name, tier, threshold?.value ?? 0);
}

// When the server goes live - characters created from that moment through
// one week after count as Founding Members. Reuses the exact same
// constant the countdown banner counts down to, so this never drifts out
// of sync with it.
//
// Both ends of the window matter: without the lower bound, any character
// created at any point BEFORE the cutoff (including right now, during
// beta, since LAUNCH_TIME is still in the future) would satisfy
// "createdAt <= cutoff" and wrongly earn this - which is exactly what was
// happening. A character only counts once it's created on or after the
// actual launch moment.
const LAUNCH_DATE = new Date(LAUNCH_TIME);
const FOUNDING_MEMBER_CUTOFF = new Date(LAUNCH_DATE.getTime() + 7 * 24 * 60 * 60 * 1000);

export function isWithinFoundingWindow(createdAt: string): boolean {
  const created = new Date(createdAt);
  return created >= LAUNCH_DATE && created <= FOUNDING_MEMBER_CUTOFF;
}
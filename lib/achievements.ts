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
  | "founding_member"
  | "well_rounded";

// The two achievements that upgrade through Bronze/Silver/Gold instead of
// being a flat yes/no: "gold" (account gold on this character) and
// "epic_gear" (how many distinct Epic items this character has equipped
// over time - a running count, not a snapshot of what's worn right now).
export type TieredAchievementKind = "gold" | "epic_gear";

export type GoldTier = "Bronze" | "Silver" | "Gold";

const TIER_RANK: Record<GoldTier, number> = { Bronze: 0, Silver: 1, Gold: 2 };

// Gold thresholds (in real gold) for the wealth achievement's three tiers.
// Deliberately separate from the activity feed's own gold_milestone
// thresholds (100/500/1000/5000) - those just narrate crossing a number,
// this is what the badge tiers upgrade on.
const GOLD_TIER_THRESHOLDS: { tier: GoldTier; gold: number }[] = [
  { tier: "Gold", gold: 5000 },
  { tier: "Silver", gold: 500 },
  { tier: "Bronze", gold: 50 },
];

// How many distinct Epic items equipped (cumulative, counted every time a
// *new* Epic item goes into a slot - swapping a worse Epic for a better
// one still counts) each tier needs. Adjust these if 1/3/5 feels off for
// your group.
const EPIC_TIER_THRESHOLDS: { tier: GoldTier; count: number }[] = [
  { tier: "Gold", count: 5 },
  { tier: "Silver", count: 3 },
  { tier: "Bronze", count: 1 },
];

export const ACHIEVEMENT_MESSAGE: Record<AchievementKind, (name: string) => string> = {
  max_level: (name) => `${name} reached the level cap!`,
  legendary_item: (name) => `${name} obtained a Legendary item!`,
  maxed_profession: (name) => `${name} maxed a profession!`,
  renaissance: (name) => `${name} maxed every profession - a true Renaissance character!`,
  maxed_legacy: (name) => `${name} maxed the account's Legacy points!`,
  top_pvp_rank: (name) => `${name} reached the top PvP rank!`,
  founding_member: (name) => `${name} earned the Founding Member badge!`,
  well_rounded: (name) => `${name} filled out both a main and an off spec - Well-Rounded!`,
};

export function goldTierMessage(name: string, tier: GoldTier): string {
  const gold = GOLD_TIER_THRESHOLDS.find((t) => t.tier === tier)?.gold ?? "?";
  return `${name} reached the ${tier} wealth tier (${gold}g)!`;
}

export function epicTierMessage(name: string, tier: GoldTier): string {
  const count = EPIC_TIER_THRESHOLDS.find((t) => t.tier === tier)?.count ?? "?";
  return `${name} has equipped ${count}+ Epic items - ${tier} tier!`;
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

// The wealth achievement upgrades in place based on the character's
// current gold - returns the new tier if this call improved on whatever
// tier (if any) the character already held, or null otherwise.
export async function awardGoldTier(
  supabase: SupabaseClient,
  characterId: string,
  copper: number
): Promise<GoldTier | null> {
  const reached = GOLD_TIER_THRESHOLDS.find((t) => copper >= t.gold * 10000);
  if (!reached) return null;

  const { data: existing } = await supabase
    .from("achievements")
    .select("tier")
    .eq("character_id", characterId)
    .eq("kind", "gold")
    .maybeSingle();

  const existingRank = existing?.tier ? TIER_RANK[existing.tier as GoldTier] : -1;
  if (TIER_RANK[reached.tier] <= existingRank) return null;

  const { error } = await supabase
    .from("achievements")
    .upsert(
      { character_id: characterId, kind: "gold", tier: reached.tier },
      { onConflict: "character_id,kind" }
    );
  if (error) return null;
  return reached.tier;
}

// The Epic-gear achievement instead accumulates a running count (stored in
// the `progress` column) every time this is called with newEpicsThisSync
// > 0, and its tier is derived from the running total. Returns the new
// tier only when this call is what pushed it into a HIGHER tier than it
// already held - a count going from 1 to 2 still keeps it at Bronze, so
// that's not reported as a fresh achievement.
export async function awardEpicTier(
  supabase: SupabaseClient,
  characterId: string,
  newEpicsThisSync: number
): Promise<GoldTier | null> {
  if (newEpicsThisSync <= 0) return null;

  const { data: existing } = await supabase
    .from("achievements")
    .select("tier, progress")
    .eq("character_id", characterId)
    .eq("kind", "epic_gear")
    .maybeSingle();

  const newProgress = (existing?.progress ?? 0) + newEpicsThisSync;
  const newTier = EPIC_TIER_THRESHOLDS.find((t) => newProgress >= t.count)?.tier ?? null;
  const existingRank = existing?.tier ? TIER_RANK[existing.tier as GoldTier] : -1;
  const newRank = newTier ? TIER_RANK[newTier] : -1;

  const { error } = await supabase
    .from("achievements")
    .upsert(
      { character_id: characterId, kind: "epic_gear", tier: newTier, progress: newProgress },
      { onConflict: "character_id,kind" }
    );
  if (error) return null;

  return newRank > existingRank ? newTier : null;
}

// When the server goes live - characters created up through one week
// after this count as Founding Members. Reuses the exact same constant
// the countdown banner counts down to, so this never drifts out of sync
// with it.
const LAUNCH_DATE = new Date(LAUNCH_TIME);
const FOUNDING_MEMBER_CUTOFF = new Date(LAUNCH_DATE.getTime() + 7 * 24 * 60 * 60 * 1000);

export function isWithinFoundingWindow(createdAt: string): boolean {
  return new Date(createdAt) <= FOUNDING_MEMBER_CUTOFF;
}

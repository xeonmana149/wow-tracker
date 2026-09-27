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
  | "greeter"
  // "Feats" (2026-09-25 batch 2) - fun, one-off, sourced from a single
  // real Statistics-pane stat each, same pattern as the personality
  // badges above (grouped separately below in FEAT_THRESHOLDS since they
  // came from a different brainstorm, but mechanically identical).
  // "hoggers_plaything" (Deaths from Hogger) was removed 2026-09-27 - it's
  // a real Blizzard-tracked stat, but Blizzard only special-cased Hogger
  // specifically as an easter egg, with no equivalent stat for any
  // Horde-side rare, making it structurally unfair to Horde characters.
  // Any earned rows for it stay in the database untouched (harmless, just
  // no longer read by anything) rather than being migrated/deleted.
  | "standing_in_fire"
  | "cant_swim"
  | "gravity_challenged"
  | "identity_crisis"
  // Quitter (2026-09-27) - same one-stat-crosses-threshold personality-
  // badge mechanism as the others, sourced from the real "Quests abandoned"
  // stat (confirmed against a live character_statistics dump).
  | "quitter"
  // Level milestones (2026-09-25) - one-off callouts every 10 levels on
  // the way to the cap, so leveling up feels like it's earning something
  // the whole way rather than only at max_level (60). Awarded the same way
  // as every other flat achievement - see MAX_CHARACTER_LEVEL/LEVEL_MILESTONES
  // in importLogic.ts for where these actually get checked.
  | "level_10"
  | "level_20"
  | "level_30"
  | "level_40"
  | "level_50"
  // Character Created (2026-09-25) - a proper one-off achievement now,
  // replacing the old always-shown "Created <date>" decorative badge that
  // lived only in CharacterCard.tsx (hardcoded WoW CDN pocketwatch icon,
  // no achievements-table row, no points, couldn't be filtered/pinned).
  // Every character earns this automatically - see the retroactive award
  // in importLogic.ts.
  | "character_created";

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
  | "social" // "Social Butterfly"
  // Batch 2 (2026-09-25), added after getting the real distinct
  // (category, name) list from character_statistics - every one of these
  // is a confirmed real stat, not a guess.
  | "bg_wins" // "Battlemaster"
  | "duels_won" // "Duelist"
  | "damage_done" // "Juggernaut"
  | "healing_done" // "Lifebringer"
  | "dungeons_entered" // "Dungeon Delver"
  | "raids_entered" // "Raider"
  | "exalted_factions" // "Diplomat"
  | "mounts_owned" // "Stablemaster"
  | "pets_owned" // "Pet Collector"
  | "loot_rolls" // "Loot Goblin"
  | "fish_caught" // "Angler"
  | "auctions_posted" // "Auctioneer"
  | "auction_gold" // "Trader"
  // Master Chef (2026-09-26) - same "computed from character_professions,
  // not character_statistics" special case as "recipes" (Artisan), except
  // scoped to ONLY the Cooking profession's known recipes rather than
  // every profession summed together. See TIER_COUNTERS below (also left
  // empty, same reason) and importLogic.ts's dedicated Cooking-only query.
  | "master_chef" // "Master Chef"
  // Addicted (2026-09-27) - total time played. Not sourced from
  // character_statistics at all (classic /played data isn't part of the
  // Statistics-pane sweep the addon does) - the addon fetches it
  // separately via RequestTimePlayed()/TIME_PLAYED_MSG and sends it as
  // parsed.basic.timePlayedSeconds instead, so this is a third
  // "computed outside character_statistics" special case alongside
  // recipes/master_chef (see TIER_COUNTERS below and importLogic.ts's
  // dedicated handling). Thresholds are in whole HOURS played, not
  // seconds - importLogic.ts converts before calling awardTier.
  | "addicted"; // "Addicted"

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
  bg_wins: {
    label: "Battlemaster",
    description: "Battlegrounds won.",
    family: "pvp",
    thresholds: [
      { tier: "Platinum", value: 300 },
      { tier: "Gold", value: 100 },
      { tier: "Silver", value: 25 },
      { tier: "Copper", value: 5 },
    ],
    format: (name, tier, value) => `${name} has won ${value}+ battlegrounds - ${tier} tier!`,
  },
  duels_won: {
    label: "Duelist",
    description: "Duels won against other players.",
    family: "pvp",
    thresholds: [
      { tier: "Platinum", value: 500 },
      { tier: "Gold", value: 200 },
      { tier: "Silver", value: 50 },
      { tier: "Copper", value: 10 },
    ],
    format: (name, tier, value) => `${name} has won ${value}+ duels - ${tier} tier!`,
  },
  damage_done: {
    label: "Juggernaut",
    description: "Total damage done, lifetime.",
    family: "combat",
    thresholds: [
      { tier: "Platinum", value: 50000000 },
      { tier: "Gold", value: 10000000 },
      { tier: "Silver", value: 1000000 },
      { tier: "Copper", value: 100000 },
    ],
    format: (name, tier, value) => `${name} has done ${value.toLocaleString()}+ damage - ${tier} tier!`,
  },
  healing_done: {
    label: "Lifebringer",
    description: "Total healing done, lifetime.",
    family: "combat",
    thresholds: [
      { tier: "Platinum", value: 25000000 },
      { tier: "Gold", value: 5000000 },
      { tier: "Silver", value: 500000 },
      { tier: "Copper", value: 50000 },
    ],
    format: (name, tier, value) => `${name} has healed ${value.toLocaleString()}+ - ${tier} tier!`,
  },
  dungeons_entered: {
    label: "Dungeon Delver",
    description: "5-player dungeons entered.",
    family: "adventure",
    thresholds: [
      { tier: "Platinum", value: 400 },
      { tier: "Gold", value: 150 },
      { tier: "Silver", value: 50 },
      { tier: "Copper", value: 10 },
    ],
    format: (name, tier, value) => `${name} has entered ${value}+ dungeons - ${tier} tier!`,
  },
  raids_entered: {
    label: "Raider",
    description: "10, 20 and 40-player raids entered, combined.",
    family: "adventure",
    thresholds: [
      { tier: "Platinum", value: 200 },
      { tier: "Gold", value: 75 },
      { tier: "Silver", value: 25 },
      { tier: "Copper", value: 5 },
    ],
    format: (name, tier, value) => `${name} has entered ${value}+ raids - ${tier} tier!`,
  },
  exalted_factions: {
    label: "Diplomat",
    description: "Factions reached Exalted reputation.",
    family: "character",
    thresholds: [
      { tier: "Platinum", value: 20 },
      { tier: "Gold", value: 10 },
      { tier: "Silver", value: 5 },
      { tier: "Copper", value: 1 },
    ],
    format: (name, tier, value) => `${name} has ${value}+ Exalted factions - ${tier} tier!`,
  },
  mounts_owned: {
    label: "Stablemaster",
    description: "Mounts owned.",
    family: "character",
    thresholds: [
      { tier: "Platinum", value: 10 },
      { tier: "Gold", value: 6 },
      { tier: "Silver", value: 3 },
      { tier: "Copper", value: 1 },
    ],
    format: (name, tier, value) => `${name} owns ${value}+ mounts - ${tier} tier!`,
  },
  pets_owned: {
    label: "Pet Collector",
    description: "Vanity pets owned.",
    family: "character",
    thresholds: [
      { tier: "Platinum", value: 10 },
      { tier: "Gold", value: 6 },
      { tier: "Silver", value: 3 },
      { tier: "Copper", value: 1 },
    ],
    format: (name, tier, value) => `${name} owns ${value}+ vanity pets - ${tier} tier!`,
  },
  loot_rolls: {
    label: "Loot Goblin",
    description: "Need and Greed rolls made on loot, combined.",
    family: "character",
    thresholds: [
      { tier: "Platinum", value: 2500 },
      { tier: "Gold", value: 1000 },
      { tier: "Silver", value: 500 },
      { tier: "Copper", value: 100 },
    ],
    format: (name, tier, value) => `${name} has made ${value.toLocaleString()}+ loot rolls - ${tier} tier!`,
  },
  fish_caught: {
    label: "Angler",
    description: "Fish caught.",
    family: "professions",
    thresholds: [
      { tier: "Platinum", value: 2000 },
      { tier: "Gold", value: 750 },
      { tier: "Silver", value: 250 },
      { tier: "Copper", value: 50 },
    ],
    format: (name, tier, value) => `${name} has caught ${value.toLocaleString()}+ fish - ${tier} tier!`,
  },
  auctions_posted: {
    label: "Auctioneer",
    description: "Auctions posted.",
    family: "wealth",
    thresholds: [
      { tier: "Platinum", value: 300 },
      { tier: "Gold", value: 100 },
      { tier: "Silver", value: 25 },
      { tier: "Copper", value: 5 },
    ],
    format: (name, tier, value) => `${name} has posted ${value}+ auctions - ${tier} tier!`,
  },
  auction_gold: {
    label: "Trader",
    description: "Gold earned from auctions, lifetime.",
    family: "wealth",
    thresholds: [
      { tier: "Platinum", value: 50000 },
      { tier: "Gold", value: 10000 },
      { tier: "Silver", value: 1000 },
      { tier: "Copper", value: 100 },
    ],
    format: (name, tier, value) => `${name} has earned ${value.toLocaleString()}+ gold from auctions - ${tier} tier!`,
  },
  master_chef: {
    label: "Master Chef",
    description: "Cooking recipes known.",
    family: "professions",
    // Scoped to ONE profession's recipe count rather than all of them
    // combined (unlike Artisan/"recipes"), so these are deliberately much
    // smaller than that achievement's 50/150/350/750 ladder - starting
    // estimates, not tuned against real Cooking recipe counts yet.
    thresholds: [
      { tier: "Platinum", value: 100 },
      { tier: "Gold", value: 60 },
      { tier: "Silver", value: 30 },
      { tier: "Copper", value: 15 },
    ],
    format: (name, tier, value) => `${name} knows ${value}+ Cooking recipes - ${tier} tier!`,
  },
  addicted: {
    label: "Addicted",
    description: "Total time played.",
    family: "character",
    // In HOURS, not seconds - see the TieredAchievementKind comment above.
    // Starting estimates, not tuned against real playtime data yet.
    thresholds: [
      { tier: "Platinum", value: 750 },
      { tier: "Gold", value: 300 },
      { tier: "Silver", value: 100 },
      { tier: "Copper", value: 24 },
    ],
    format: (name, tier, value) => `${name} has played ${value.toLocaleString()}+ hours - ${tier} tier!`,
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
  standing_in_fire: (name) => `${name} has died to fire or lava 10+ times - Standing in Fire!`,
  cant_swim: (name) => `${name} has drowned 10+ times - Can't Swim!`,
  gravity_challenged: (name) => `${name} has died from falling 10+ times - Gravity Challenged!`,
  identity_crisis: (name) => `${name} has respec'd 10+ times - Identity Crisis!`,
  quitter: (name) => `${name} has abandoned 25+ quests - Quitter!`,
  level_10: (name) => `${name} reached level 10!`,
  level_20: (name) => `${name} reached level 20!`,
  level_30: (name) => `${name} reached level 30!`,
  level_40: (name) => `${name} reached level 40!`,
  level_50: (name) => `${name} reached level 50!`,
  character_created: (name) => `${name} was created!`,
};

// Level milestones (2026-09-25) - awarded in applyImport (lib/importLogic.ts)
// alongside the existing level-up event and the level-cap max_level check.
// Kept here (not just inline in importLogic.ts) so the kind<->level mapping
// has one home other code can read too if it ever needs it. Deliberately
// stops short of MAX_CHARACTER_LEVEL (60) - that's what max_level is for.
export const LEVEL_MILESTONES: { level: number; kind: AchievementKind }[] = [
  { level: 10, kind: "level_10" },
  { level: 20, kind: "level_20" },
  { level: 30, kind: "level_30" },
  { level: 40, kind: "level_40" },
  { level: 50, kind: "level_50" },
];

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
  // Batch 2 "feats" - same one-stat-crosses-threshold mechanism, just
  // sourced from World/Character categories instead of Social.
  { kind: "standing_in_fire", category: "World", name: "Deaths from fire and lava", threshold: 10 },
  { kind: "cant_swim", category: "World", name: "Deaths from drowning", threshold: 10 },
  { kind: "gravity_challenged", category: "World", name: "Deaths from falling", threshold: 10 },
  { kind: "identity_crisis", category: "Character", name: "Talent tree respecs", threshold: 10 },
  // Quitter (2026-09-27) - confirmed against a real character_statistics
  // dump: category "Quests", name "Quests abandoned".
  { kind: "quitter", category: "Quests", name: "Quests abandoned", threshold: 25 },
];

// Which character_statistics rows feed each tiered achievement's counter.
// A plain {category,name} sums that one stat; {categoryOnly} sums EVERY
// stat under that raw category (used for boss_kills, where Blizzard tracks
// one counter per boss rather than a single aggregate). "recipes" and
// "master_chef" are left as empty lists on purpose - both are computed from
// character_professions, not character_statistics, so importLogic.ts
// special-cases them instead (master_chef the same way as recipes, just
// filtered down to the Cooking profession only).
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
  bg_wins: [{ category: "Battlegrounds", name: "Battlegrounds won" }],
  duels_won: [{ category: "World", name: "Duels won" }],
  damage_done: [{ category: "Combat", name: "Total damage done" }],
  healing_done: [{ category: "Combat", name: "Total healing done" }],
  dungeons_entered: [{ category: "Dungeons & Raids", name: "Total 5-player dungeons entered" }],
  raids_entered: [
    { category: "Dungeons & Raids", name: "Total 10-player raids entered" },
    { category: "Dungeons & Raids", name: "Total 20-player raids entered" },
    { category: "Dungeons & Raids", name: "Total 40-player raids entered" },
  ],
  exalted_factions: [{ category: "Reputation", name: "Most factions at Exalted" }],
  mounts_owned: [{ category: "Gear", name: "Mounts owned" }],
  pets_owned: [{ category: "Gear", name: "Vanity pets owned" }],
  loot_rolls: [
    { category: "Gear", name: "Need rolls made on loot" },
    { category: "Gear", name: "Greed rolls made on loot" },
  ],
  fish_caught: [{ category: "Secondary Skills", name: "Fish caught" }],
  auctions_posted: [{ category: "Wealth", name: "Auctions posted" }],
  auction_gold: [{ category: "Wealth", name: "Gold earned from auctions" }],
  master_chef: [],
  // "addicted" is computed from parsed.basic.timePlayedSeconds, not from
  // character_statistics - see the TieredAchievementKind comment above.
  addicted: [],
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
  kind: AchievementKind,
  // Defaults to now, same as always - only ever overridden by
  // "character_created" (2026-09-25), which backdates this to the
  // character's real creation date instead of whenever it happened to get
  // backfilled, so sorting/showing "when earned" for it stays meaningful.
  earnedAt?: string
): Promise<boolean> {
  const { data, error } = await supabase
    .from("achievements")
    .upsert(
      { character_id: characterId, kind, earned_at: earnedAt ?? new Date().toISOString() },
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
      { character_id: characterId, kind, tier: reached.tier, earned_at: new Date().toISOString() },
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
  "bg_wins",
  "duels_won",
  "damage_done",
  "healing_done",
  "dungeons_entered",
  "raids_entered",
  "exalted_factions",
  "mounts_owned",
  "pets_owned",
  "loot_rolls",
  "fish_caught",
  "auctions_posted",
  "auction_gold",
  "master_chef",
  "addicted",
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
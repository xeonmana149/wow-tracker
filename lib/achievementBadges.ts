// Plain (non-"use client") home for the achievement badge/icon lookup
// tables. These used to live inside CharacterCard.tsx, but that file starts
// with "use client" - fine for client components importing it (CharacterRow,
// Dashboard, dev-badges-page), but broken for the *server* component
// app/character/[id]/page.tsx, which pulls them in transitively through
// app/achievementBoard.ts. When a server component reads a plain data
// export out of a "use client" module, Next's RSC bundler swaps in a
// client-reference stub instead of the real object, so every lookup here
// (e.g. TIERED_LOCAL_ICONS[kind]) silently comes back `undefined` on the
// character page - which is exactly the fallback path that produced the
// inv_misc_questionmark icon.
//
// Fix: keep the data here, in a module with no "use client" directive, so
// both server and client code can read it safely. CharacterCard.tsx
// re-exports everything below for existing client-side imports.
import type { AchievementKind, GoldTier, TieredAchievementKind } from "./achievements";

// Plain yes/no achievements - anyone can earn each of these independently
// (see lib/achievements.ts). Doesn't cover "gold" or "epic_gear", which
// are tiered instead and rendered separately below.
// Icon names are real WoW icon names, resolved to actual game art through
// wowIconUrl() - the same live icon CDN used for gear icons elsewhere on
// the site (see lib/icons.ts). If a name is ever wrong, GameIcon quietly
// falls back to a text tile instead of breaking.
export const ACHIEVEMENT_BADGES: Record<AchievementKind, { icon: string; label: string }> = {
  max_level: { icon: "achievement_level_60", label: "Reached the level cap" },
  legendary_item: { icon: "inv_hammer_unique_sulfuras", label: "Obtained a Legendary item" },
  maxed_profession: { icon: "inv_misc_wrench_01", label: "Maxed a profession" },
  renaissance: { icon: "inv_misc_book_09", label: "Maxed every profession (2 primary + all 3 secondary)" },
  maxed_legacy: { icon: "inv_misc_rune_01", label: "Maxed the account's Legacy points" },
  top_pvp_rank: { icon: "achievement_pvp_rank_grandmarshal", label: "Reached the top PvP rank" },
  founding_member: { icon: "inv_misc_map_01", label: "Founding Member - created during launch week" },
  // Personality badges (2026-09-25) - one-off, no tiers, sourced from a
  // single Social-pane stat each. Icons are close-enough stand-ins (can be
  // swapped from the /dev/badges tester with no code change).
  hugger: { icon: "spell_holy_layonhands", label: "Hugger - given 100+ hugs" },
  comedian: { icon: "spell_shadow_charm", label: "Comedian - LOL'd 100+ times" },
  drama_queen: { icon: "spell_shadow_possession", label: "Drama Queen - facepalmed 100+ times" },
  tiny_violinist: {
    icon: "inv_misc_idol_04",
    label: "Tiny Violinist - played the world's smallest violin 100+ times",
  },
  greeter: { icon: "ability_hunter_beastcall", label: "Greeter - waved 250+ times" },
  // Batch 2 feats (2026-09-25) - one-off, sourced from real death/character
  // stats. Icons are close-enough stand-ins, swappable from /dev/badges.
  standing_in_fire: { icon: "spell_fire_selfdestruct", label: "Standing in Fire - died to fire or lava 10+ times" },
  hoggers_plaything: { icon: "inv_misc_head_dog_01", label: "Hogger's Plaything - died to Hogger" },
  cant_swim: { icon: "spell_frost_frostbolt02", label: "Can't Swim - drowned 10+ times" },
  gravity_challenged: { icon: "spell_magic_featherfall", label: "Gravity Challenged - died from falling 10+ times" },
  identity_crisis: { icon: "spell_nature_polymorph", label: "Identity Crisis - respec'd 10+ times" },
  // Level milestones (2026-09-25) - one-off callouts every 10 levels short
  // of the cap. `icon` is legacy/unused now that badge rendering no longer
  // falls back to a WoW CDN icon (see the 2026-09-25 "remove the old wow
  // icon badges" change) - kept filled in for documentation, not display.
  level_10: { icon: "achievement_level_10", label: "Novice - reached level 10" },
  level_20: { icon: "achievement_level_20", label: "Apprentice - reached level 20" },
  level_30: { icon: "achievement_level_30", label: "Journeyman - reached level 30" },
  level_40: { icon: "achievement_level_40", label: "Veteran - reached level 40" },
  level_50: { icon: "achievement_level_50", label: "Elite - reached level 50" },
  // Character Created (2026-09-25) - was a decorative, always-shown badge
  // hardcoded directly in CharacterCard.tsx (see the removed
  // CREATED_DATE_ICON/CREATED_DATE_ICON_KEY constants above); now a real
  // one-off achievement every character earns automatically, so it shows
  // up on the achievements page, counts for points, and can be pinned.
  // `icon` is legacy/unused, same as everything else here now.
  character_created: { icon: "inv_misc_pocketwatch_01", label: "Marks when this character was created" },
};

// Deep Pockets labels per tier. Used to be a set of 4 different coin icons
// (the old per-tier-icon "gold badge" system, from before border frames
// existed) - now the actual art comes from TIERED_LOCAL_ICONS.gold
// ("deep-pockets") + the matching tier frame via TierFramedIcon, so this is
// just the label text.
export const GOLD_TIER_LABEL: Record<GoldTier, string> = {
  Copper: "Deep Pockets - Copper tier - 50g+",
  Silver: "Deep Pockets - Silver tier - 500g+",
  Gold: "Deep Pockets - Gold tier - 5,000g+",
  Platinum: "Deep Pockets - Platinum tier - 25,000g+",
};

// Epic-gear (Well-Equipped) tier reuses one gem icon for every tier (there's
// no great distinct 4-tier gem set in the game's icon set) and shows the
// tier via a colored ring around it instead.
export const EPIC_TIER_META: Record<GoldTier, { icon: string; ring: string; label: string }> = {
  Copper: {
    icon: "inv_misc_gem_amethyst_02",
    ring: "ring-2 ring-amber-700",
    label: "Well-Equipped - Copper tier - 1+ Epic items",
  },
  Silver: {
    icon: "inv_misc_gem_amethyst_02",
    ring: "ring-2 ring-gray-300",
    label: "Well-Equipped - Silver tier - 3+ Epic items",
  },
  Gold: {
    icon: "inv_misc_gem_amethyst_02",
    ring: "ring-2 ring-yellow-400",
    label: "Well-Equipped - Gold tier - 5+ Epic items",
  },
  Platinum: {
    icon: "inv_misc_gem_amethyst_02",
    ring: "ring-2 ring-cyan-300",
    label: "Well-Equipped - Platinum tier - 10+ Epic items",
  },
};

// Recipes-known (Artisan) tier uses a recipe/schematic-styled icon for
// every tier (mirroring epic_gear's one-icon-plus-ring approach), so it
// reads as a different achievement family from the coin icons used for
// wealth.
export const RECIPE_TIER_BADGE: Record<GoldTier, { icon: string; ring: string; label: string }> = {
  Copper: {
    icon: "inv_scroll_03",
    ring: "ring-2 ring-amber-700",
    label: "Artisan - Copper tier - 50+ recipes known",
  },
  Silver: {
    icon: "inv_scroll_03",
    ring: "ring-2 ring-gray-300",
    label: "Artisan - Silver tier - 150+ recipes known",
  },
  Gold: {
    icon: "inv_scroll_03",
    ring: "ring-2 ring-yellow-400",
    label: "Artisan - Gold tier - 350+ recipes known",
  },
  Platinum: {
    icon: "inv_scroll_03",
    ring: "ring-2 ring-cyan-300",
    label: "Artisan - Platinum tier - 750+ recipes known",
  },
};

// Every other tiered badge added since the 2026-09-25 Statistics-based
// rework - one fixed icon per kind, with the tier communicated by a
// colored ring, same convention as epic_gear/recipes above rather than
// needing a distinct icon per tier for each one.
type TierRingBadge = Record<GoldTier, { icon: string; ring: string; label: string }>;

const RING_BY_TIER: Record<GoldTier, string> = {
  Copper: "ring-2 ring-amber-700",
  Silver: "ring-2 ring-gray-300",
  Gold: "ring-2 ring-yellow-400",
  Platinum: "ring-2 ring-cyan-300",
};

function ringBadge(icon: string, labelFor: (tier: GoldTier) => string): TierRingBadge {
  return {
    Copper: { icon, ring: RING_BY_TIER.Copper, label: labelFor("Copper") },
    Silver: { icon, ring: RING_BY_TIER.Silver, label: labelFor("Silver") },
    Gold: { icon, ring: RING_BY_TIER.Gold, label: labelFor("Gold") },
    Platinum: { icon, ring: RING_BY_TIER.Platinum, label: labelFor("Platinum") },
  };
}

export const HONORABLE_KILLS_TIER_BADGE = ringBadge(
  "ability_warrior_savageblow",
  (tier) =>
    `Gladiator - ${tier} tier - ${{ Copper: 10, Silver: 50, Gold: 200, Platinum: 1000 }[tier]}+ Honorable Kills`
);
export const CREATURES_KILLED_TIER_BADGE = ringBadge(
  "inv_misc_monsterclaw_04",
  (tier) =>
    `Monster Hunter - ${tier} tier - ${{ Copper: 250, Silver: 1000, Gold: 5000, Platinum: 20000 }[tier]}+ creatures killed`
);
export const QUESTS_COMPLETED_TIER_BADGE = ringBadge(
  "achievement_quests_completed_08",
  (tier) =>
    `Adventurer - ${tier} tier - ${{ Copper: 50, Silver: 200, Gold: 500, Platinum: 1000 }[tier]}+ quests completed`
);
export const KILLING_BLOWS_TIER_BADGE = ringBadge(
  "ability_rogue_ambush",
  (tier) =>
    `Executioner - ${tier} tier - ${{ Copper: 25, Silver: 150, Gold: 500, Platinum: 1500 }[tier]}+ Killing Blows`
);
export const BOSS_KILLS_TIER_BADGE = ringBadge(
  "achievement_boss_ragnaros",
  (tier) =>
    `Slayer - ${tier} tier - ${{ Copper: 10, Silver: 50, Gold: 150, Platinum: 500 }[tier]}+ boss kills`
);
export const CONSUMABLES_TIER_BADGE = ringBadge(
  "inv_misc_food_15",
  (tier) =>
    `Well Supplied - ${tier} tier - ${{ Copper: 100, Silver: 500, Gold: 2000, Platinum: 8000 }[tier]}+ consumables used`
);
export const TRAVEL_TIER_BADGE = ringBadge(
  "ability_hunter_pathfinding",
  (tier) =>
    `Wayfarer - ${tier} tier - ${{ Copper: 50, Silver: 250, Gold: 1000, Platinum: 4000 }[tier]}+ fast travels`
);
export const SOCIAL_TIER_BADGE = ringBadge(
  "inv_misc_horn_04",
  (tier) =>
    `Social Butterfly - ${tier} tier - ${{ Copper: 50, Silver: 250, Gold: 1000, Platinum: 4000 }[tier]}+ social emotes`
);
export const BG_WINS_TIER_BADGE = ringBadge(
  "achievement_bg_winwsg",
  (tier) => `Battlemaster - ${tier} tier - ${{ Copper: 5, Silver: 25, Gold: 100, Platinum: 300 }[tier]}+ battlegrounds won`
);
export const DUELS_WON_TIER_BADGE = ringBadge(
  "ability_warrior_challange",
  (tier) => `Duelist - ${tier} tier - ${{ Copper: 10, Silver: 50, Gold: 200, Platinum: 500 }[tier]}+ duels won`
);
export const DAMAGE_DONE_TIER_BADGE = ringBadge(
  "ability_warrior_savageblow",
  (tier) =>
    `Juggernaut - ${tier} tier - ${{ Copper: 100000, Silver: 1000000, Gold: 10000000, Platinum: 50000000 }[tier].toLocaleString()}+ damage done`
);
export const HEALING_DONE_TIER_BADGE = ringBadge(
  "spell_holy_flashheal",
  (tier) =>
    `Lifebringer - ${tier} tier - ${{ Copper: 50000, Silver: 500000, Gold: 5000000, Platinum: 25000000 }[tier].toLocaleString()}+ healing done`
);
export const DUNGEONS_ENTERED_TIER_BADGE = ringBadge(
  "inv_misc_key_03",
  (tier) => `Dungeon Delver - ${tier} tier - ${{ Copper: 10, Silver: 50, Gold: 150, Platinum: 400 }[tier]}+ dungeons entered`
);
export const RAIDS_ENTERED_TIER_BADGE = ringBadge(
  "achievement_boss_illidan",
  (tier) => `Raider - ${tier} tier - ${{ Copper: 5, Silver: 25, Gold: 75, Platinum: 200 }[tier]}+ raids entered`
);
export const EXALTED_FACTIONS_TIER_BADGE = ringBadge(
  "inv_misc_tournaments_banner_orc",
  (tier) => `Diplomat - ${tier} tier - ${{ Copper: 1, Silver: 5, Gold: 10, Platinum: 20 }[tier]}+ Exalted factions`
);
export const MOUNTS_OWNED_TIER_BADGE = ringBadge(
  "ability_mount_ridinghorse",
  (tier) => `Stablemaster - ${tier} tier - ${{ Copper: 1, Silver: 3, Gold: 6, Platinum: 10 }[tier]}+ mounts owned`
);
export const PETS_OWNED_TIER_BADGE = ringBadge(
  "inv_box_petcarrier_01",
  (tier) => `Pet Collector - ${tier} tier - ${{ Copper: 1, Silver: 3, Gold: 6, Platinum: 10 }[tier]}+ vanity pets owned`
);
export const LOOT_ROLLS_TIER_BADGE = ringBadge(
  "inv_misc_bag_10",
  (tier) =>
    `Loot Goblin - ${tier} tier - ${{ Copper: 100, Silver: 500, Gold: 1000, Platinum: 2500 }[tier].toLocaleString()}+ loot rolls`
);
export const FISH_CAUGHT_TIER_BADGE = ringBadge(
  "trade_fishing",
  (tier) =>
    `Angler - ${tier} tier - ${{ Copper: 50, Silver: 250, Gold: 750, Platinum: 2000 }[tier].toLocaleString()}+ fish caught`
);
export const AUCTIONS_POSTED_TIER_BADGE = ringBadge(
  "inv_misc_note_01",
  (tier) => `Auctioneer - ${tier} tier - ${{ Copper: 5, Silver: 25, Gold: 100, Platinum: 300 }[tier]}+ auctions posted`
);
export const AUCTION_GOLD_TIER_BADGE = ringBadge(
  "inv_misc_coin_02",
  (tier) =>
    `Trader - ${tier} tier - ${{ Copper: 100, Silver: 1000, Gold: 10000, Platinum: 50000 }[tier].toLocaleString()}+ gold from auctions`
);

// One lookup covering every ring-style tiered badge (everything except
// "gold", which is handled separately above via GOLD_TIER_LABEL) so the
// render below doesn't need a growing if/else chain every time a new
// tiered badge is added.
export const RING_TIER_BADGES: Partial<Record<TieredAchievementKind, TierRingBadge>> = {
  epic_gear: EPIC_TIER_META,
  recipes: RECIPE_TIER_BADGE,
  honorable_kills: HONORABLE_KILLS_TIER_BADGE,
  creatures_killed: CREATURES_KILLED_TIER_BADGE,
  quests_completed: QUESTS_COMPLETED_TIER_BADGE,
  killing_blows: KILLING_BLOWS_TIER_BADGE,
  boss_kills: BOSS_KILLS_TIER_BADGE,
  consumables: CONSUMABLES_TIER_BADGE,
  travel: TRAVEL_TIER_BADGE,
  social: SOCIAL_TIER_BADGE,
  bg_wins: BG_WINS_TIER_BADGE,
  duels_won: DUELS_WON_TIER_BADGE,
  damage_done: DAMAGE_DONE_TIER_BADGE,
  healing_done: HEALING_DONE_TIER_BADGE,
  dungeons_entered: DUNGEONS_ENTERED_TIER_BADGE,
  raids_entered: RAIDS_ENTERED_TIER_BADGE,
  exalted_factions: EXALTED_FACTIONS_TIER_BADGE,
  mounts_owned: MOUNTS_OWNED_TIER_BADGE,
  pets_owned: PETS_OWNED_TIER_BADGE,
  loot_rolls: LOOT_ROLLS_TIER_BADGE,
  fish_caught: FISH_CAUGHT_TIER_BADGE,
  auctions_posted: AUCTIONS_POSTED_TIER_BADGE,
  auction_gold: AUCTION_GOLD_TIER_BADGE,
};

// Local custom artwork (2026-09-25) - icon slugs live at
// /public/badge-icons/<slug>.png and get layered with the matching tier's
// border frame via TierFramedIcon, instead of a WoW CDN icon + colored
// ring. Only badges the user has actually picked art for are listed here;
// everything else in RING_TIER_BADGES/ACHIEVEMENT_BADGES keeps using its
// CDN icon + ring/plain treatment until it gets a local icon too - so
// adding one is just: drop the file, add one line below.
export const TIERED_LOCAL_ICONS: Partial<Record<TieredAchievementKind, string>> = {
  gold: "deep-pockets",
  epic_gear: "well-equipped",
  recipes: "artisan",
  honorable_kills: "gladiator",
  creatures_killed: "monster-hunter",
  quests_completed: "adventurer",
  killing_blows: "executioner",
  boss_kills: "slayer",
  consumables: "well-supplied",
  travel: "wayfarer",
  social: "social-butterfly",
  bg_wins: "battlemaster",
  duels_won: "duelist",
  dungeons_entered: "dungeon-delver",
  raids_entered: "raider",
  exalted_factions: "diplomat",
  mounts_owned: "stablemaster",
  pets_owned: "pet-collector",
  fish_caught: "angler",
  auctions_posted: "auctioneer",
};

// Same idea for the flat (no-tier) achievement badges that got local art -
// these render as a plain local icon with no border frame, same shape as
// the CDN-icon versions they replace.
export const FLAT_LOCAL_ICONS: Partial<Record<AchievementKind, string>> = {
  max_level: "max-level",
  maxed_legacy: "maxed-legacy",
  top_pvp_rank: "top-pvp-rank",
  founding_member: "founding-member",
  greeter: "greeter",
};
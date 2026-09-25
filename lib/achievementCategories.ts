import type { AchievementFamily } from "./achievements";
import type { AchievementKind } from "./achievements";

// Tiered achievements already carry a family (see TIER_DEFS in
// achievements.ts), used to group the leaderboards' Achievement dropdown.
// The flat (one-off, no-tier) achievements never needed that until the
// full /achievements page (2026-09-25) wanted to group and filter EVERY
// achievement the same way - this fills that gap without touching the
// award-logic file itself, since this is purely UI grouping data.
export const FLAT_ACHIEVEMENT_FAMILY: Record<AchievementKind, AchievementFamily> = {
  max_level: "character",
  legendary_item: "character",
  maxed_profession: "professions",
  renaissance: "professions",
  maxed_legacy: "character",
  top_pvp_rank: "pvp",
  founding_member: "character",
  hugger: "social",
  comedian: "social",
  drama_queen: "social",
  tiny_violinist: "social",
  greeter: "social",
  standing_in_fire: "character",
  hoggers_plaything: "character",
  cant_swim: "character",
  gravity_challenged: "character",
  identity_crisis: "character",
  level_10: "character",
  level_20: "character",
  level_30: "character",
  level_40: "character",
  level_50: "character",
  character_created: "character",
};

// ACHIEVEMENT_BADGES' "label" field (in CharacterCard.tsx) is really a
// tooltip sentence ("Reached the level cap"), not a short display name -
// fine for a hover tooltip, too long for a page that wants "ARTISAN" /
// "Recipes known..." as two separate lines. This is that short name.
export const FLAT_ACHIEVEMENT_NAME: Record<AchievementKind, string> = {
  max_level: "Max Level",
  legendary_item: "Legendary",
  maxed_profession: "Master Crafter",
  renaissance: "Renaissance",
  maxed_legacy: "Legacy Complete",
  top_pvp_rank: "Grand Marshal",
  founding_member: "Founding Member",
  hugger: "Hugger",
  comedian: "Comedian",
  drama_queen: "Drama Queen",
  tiny_violinist: "Tiny Violinist",
  greeter: "Greeter",
  standing_in_fire: "Standing in Fire",
  hoggers_plaything: "Hogger's Plaything",
  cant_swim: "Can't Swim",
  gravity_challenged: "Gravity Challenged",
  identity_crisis: "Identity Crisis",
  level_10: "Novice",
  level_20: "Apprentice",
  level_30: "Journeyman",
  level_40: "Veteran",
  level_50: "Elite",
  character_created: "Character Created",
};

// Flat achievements are one-off, not leveled like the tiered ones (no
// Copper/Silver/Gold/Platinum split to hang a point value off), so each is
// just worth this flat amount toward the same points pool the tiered
// achievements' TIER_POINTS feeds - easy to retune later, this is just one
// number.
export const FLAT_ACHIEVEMENT_POINTS = 20;
"use client";

import { useState } from "react";
import Link from "next/link";
import { RACE_FACTION } from "../lib/options";
import {
  PRIMARY_PROFESSIONS,
  PROFESSION_ICONS,
  RACE_ICONS,
  classIcon,
  wowIconUrl,
} from "../lib/icons";
import { characterBars } from "../lib/progress";
import type { AchievementKind, GoldTier, TieredAchievementKind } from "../lib/achievements";
import { resolvedIcon, type BadgeIconOverrides } from "../lib/badgeIconOverrides";
import GameIcon from "./GameIcon";
import ProgressBars from "./ProgressBars";

export type { AchievementKind, GoldTier };

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
};

export const GOLD_TIER_BADGE: Record<GoldTier, { icon: string; label: string }> = {
  Copper: { icon: "inv_misc_coin_01", label: "Deep Pockets - Copper tier - 50g+" },
  Silver: { icon: "inv_misc_coin_03", label: "Deep Pockets - Silver tier - 500g+" },
  Gold: { icon: "inv_misc_coin_05", label: "Deep Pockets - Gold tier - 5,000g+" },
  Platinum: { icon: "inv_misc_coin_06", label: "Deep Pockets - Platinum tier - 25,000g+" },
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
// "gold", which uses a different icon per tier instead of a ring - see
// GOLD_TIER_BADGE above) so the render below doesn't need a growing
// if/else chain every time a new tiered badge is added.
const RING_TIER_BADGES: Partial<Record<TieredAchievementKind, TierRingBadge>> = {
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

// The 📅 created-date badge isn't a real achievement, but gets the same
// icon treatment for visual consistency with the ones that are.
export const CREATED_DATE_ICON = "inv_misc_pocketwatch_01";
export const CREATED_DATE_ICON_KEY = "created_date";

type CardAchievement = {
  kind: AchievementKind | TieredAchievementKind;
  tier?: GoldTier | null;
};

export type CardCharacter = {
  id: string;
  name: string;
  race: string;
  class: string;
  level: number;
  guild: string | null;
  character_type: string;
  ruleset: string | null;
  main_spec: string | null;
  main_role: string;
  off_spec: string | null;
  off_role: string | null;
  active_spec?: number | null;
  money_copper?: number;
  pvp_rank?: number;
  honor_points?: number;
  // XP within the CURRENT level (not toward the level cap) - null/undefined
  // on a character that hasn't synced since addon v1.5.0, and xp_max is
  // legitimately 0 at the level cap (no bar left to fill).
  xp?: number | null;
  xp_max?: number | null;
  needs_setup?: boolean;
  created_at?: string | null;
  achievements?: CardAchievement[];
  profiles?: { display_name?: string; legacy_points?: number } | null;
  character_professions: {
    profession: string;
    skill: number;
    // A recipe entry is a bare string on an old addon build, or a richer
    // object on newer ones - reagents/tooltip/color were added after icon/id.
    // color is a bare "rrggbb" hex string read off the item's rendered
    // tooltip color in-game (no reliable quality field on this server).
    recipes?: (
      | string
      | {
          name: string;
          icon?: number | string | null;
          id?: number;
          reagents?: {
            itemID: number;
            name: string;
            icon?: number | string | null;
            quantity: number;
            color?: string | null;
          }[];
          tooltip?: string[];
          color?: string | null;
        }
    )[];
  }[];
  character_talents: { slot: number; tree: string; rank: number }[];
  character_legacy?: { rank: number }[];
  // The card only ever shows the first couple still-wanted items, with a
  // "+N more" for the rest - the full list (with priority and the
  // obtained checkbox) lives on the character's own page.
  character_wishlist?: { item_name: string; priority: "High" | "Medium" | "Low"; obtained: boolean }[];
  // For the Dashboard's "weakest gear" What's Next suggestion (see
  // lib/progress.ts's gearTodos) - `items` comes back as an object or a
  // one-element array depending on how Supabase infers the to-one join,
  // so callers need to handle both.
  equipped_gear?: {
    slot: string;
    item_id: number | null;
    items?:
      | { required_level: number | null; required_level_scanned: boolean | null }
      | { required_level: number | null; required_level_scanned: boolean | null }[]
      | null;
  }[];
};

const WISHLIST_PRIORITY_ORDER: Record<"High" | "Medium" | "Low", number> = {
  High: 0,
  Medium: 1,
  Low: 2,
};

// Colors the character-type tag AND gives the whole card a matching
// left-edge accent, so the type is readable at a glance across a long
// list without having to read every tag - color plus the text label
// together, never color alone. Matched case-insensitively since the
// database's exact casing ("PvPer" vs "Pvper") isn't guaranteed.
const CHARACTER_TYPE_STYLES: Record<string, { pill: string; border: string }> = {
  main: { pill: "bg-amber-500/20 text-amber-300 ring-1 ring-amber-500/50", border: "#d9a441" },
  alt: { pill: "bg-sky-500/20 text-sky-300 ring-1 ring-sky-500/50", border: "#4d8fd6" },
  pvper: { pill: "bg-rose-500/20 text-rose-300 ring-1 ring-rose-500/50", border: "#c9574a" },
  gathering: { pill: "bg-emerald-500/20 text-emerald-300 ring-1 ring-emerald-500/50", border: "#3f9a68" },
};
const DEFAULT_TYPE_STYLE = { pill: "bg-neutral-600 text-white", border: "transparent" };

export function characterTypeStyle(type: string) {
  return CHARACTER_TYPE_STYLES[type.toLowerCase()] ?? DEFAULT_TYPE_STYLE;
}

// Points in each tree for one spec, like 0/32/10
function talentSplit(c: CardCharacter, slot: number, treeNames: string[] | undefined) {
  const per: Record<string, number> = {};
  for (const r of c.character_talents ?? []) {
    if (r.slot === slot) per[r.tree] = (per[r.tree] ?? 0) + r.rank;
  }
  const names = treeNames && treeNames.length > 0 ? treeNames : Object.keys(per);
  return names.length > 0 ? names.map((n) => per[n] ?? 0).join("/") : "-";
}

function ChevronIcon({ open }: { open: boolean }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width="18"
      height="18"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      className={`transition-transform duration-150 ${open ? "rotate-180" : ""}`}
      aria-hidden="true"
    >
      <path d="M6 9l6 6 6-6" />
    </svg>
  );
}

export default function CharacterCard({
  c,
  treeNames,
  specIcons,
  compact = false,
  iconOverrides = {},
  defaultExpanded = false,
  showNeedsAttention = true,
}: {
  c: CardCharacter;
  treeNames: string[] | undefined;
  specIcons: Record<string, string>;
  compact?: boolean;
  // Lets any badge icon be swapped at runtime via the badge_icons table
  // (edited from the /dev/badges tester page) instead of needing a code
  // change. Defaults to {} so passing nothing just uses every default.
  iconOverrides?: BadgeIconOverrides;
  // Starts a card already open. Used on the character's own page, where
  // there's only ever one card and hiding its details would be pointless.
  defaultExpanded?: boolean;
  // The "Needs attention" banner is a nudge for the character's own owner
  // to finish setting it up - not useful (and a bit odd-looking) on
  // someone else's character, so the Friends page turns it off.
  showNeedsAttention?: boolean;
}) {
  const [expanded, setExpanded] = useState(defaultExpanded);

  const faction = RACE_FACTION[c.race];
  const professions = (c.character_professions ?? [])
    .filter((p) => PRIMARY_PROFESSIONS.includes(p.profession))
    .sort((a, b) => b.skill - a.skill)
    .slice(0, 2);

  const createdLabel = c.created_at
    ? new Date(c.created_at).toLocaleDateString(undefined, {
        year: "numeric",
        month: "short",
        day: "numeric",
      })
    : null;

  const stillWanted = (c.character_wishlist ?? [])
    .filter((w) => !w.obtained)
    .sort((a, b) => WISHLIST_PRIORITY_ORDER[a.priority] - WISHLIST_PRIORITY_ORDER[b.priority]);
  const wishlistPreview = stillWanted.slice(0, 2);
  const wishlistMore = stillWanted.length - wishlistPreview.length;

  const pad = compact ? "p-3" : "p-4";
  const gap = compact ? "mt-2" : "mt-3";
  const typeStyle = characterTypeStyle(c.character_type);

  return (
    <div
      className={`character-card rounded border-l-4 bg-neutral-800 ${pad} ${
        c.needs_setup && showNeedsAttention ? "ring-2 ring-amber-400" : ""
      }`}
      style={{ borderLeftColor: typeStyle.border }}
    >
      {c.needs_setup && showNeedsAttention && (
        <div className="mb-2 flex items-center gap-1.5 rounded bg-amber-500/15 px-2 py-1 text-xs font-bold text-amber-300">
          <span className="text-sm">⚠</span> Needs attention
        </div>
      )}

      {/* Bare-minimum header: portrait, name, badges, level/race/class.
          This is everything visible when the card is collapsed, so it's
          also what keeps every card the same height at a glance - the
          arrow on the right reveals the rest. */}
      <div className="flex items-start gap-3">
        <Link href={`/character/${c.id}`} className="flex min-w-0 flex-1 items-start gap-3">
          <GameIcon name={classIcon(c.class)} label={c.class} size={compact ? 44 : 52} round />
          <div className="min-w-0 flex-1">
            {/* Just the name and its type tag here - badges used to share
                this line too, and a long name would wrap them down onto
                their own row anyway (inconsistently, depending on name
                length). They now always start on their own line below,
                same as account badges elsewhere on the site. */}
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-lg font-bold text-white hover:underline">{c.name}</span>
              <span className={`rounded px-2 py-0.5 text-xs font-semibold ${typeStyle.pill}`}>
                {c.character_type}
              </span>
            </div>
            <div className="mt-1 flex items-center gap-2 text-sm text-gray-400">
              <GameIcon name={RACE_ICONS[c.race]} label={c.race} size={20} round />
              <span>
                Level {c.level} {c.race} {c.class}
              </span>
            </div>
            {((c.achievements ?? []).length > 0 || createdLabel) && (
              <div className="mt-1.5 flex flex-wrap items-center gap-2">
                {(c.achievements ?? []).map((a) => {
                  if (a.kind === "gold" && a.tier) {
                    const badge = GOLD_TIER_BADGE[a.tier];
                    const icon = resolvedIcon(iconOverrides, `gold:${a.tier}`, badge.icon);
                    return (
                      <span key="gold" className="inline-block rounded-full ring-2 ring-amber-500/70">
                        <GameIcon src={wowIconUrl(icon)} label={badge.label} size={28} round />
                      </span>
                    );
                  }
                  const ringBadge = RING_TIER_BADGES[a.kind as TieredAchievementKind];
                  if (ringBadge && a.tier) {
                    const meta = ringBadge[a.tier];
                    const icon = resolvedIcon(iconOverrides, `${a.kind}:${a.tier}`, meta.icon);
                    return (
                      <span key={a.kind} className={`inline-block rounded-full ${meta.ring}`}>
                        <GameIcon src={wowIconUrl(icon)} label={meta.label} size={28} round />
                      </span>
                    );
                  }
                  const badge = ACHIEVEMENT_BADGES[a.kind as AchievementKind];
                  if (!badge) return null;
                  const icon = resolvedIcon(iconOverrides, a.kind, badge.icon);
                  return <GameIcon key={a.kind} src={wowIconUrl(icon)} label={badge.label} size={28} round />;
                })}
                {createdLabel && (
                  <GameIcon
                    src={wowIconUrl(resolvedIcon(iconOverrides, CREATED_DATE_ICON_KEY, CREATED_DATE_ICON))}
                    label={`Created ${createdLabel}`}
                    size={28}
                    round
                  />
                )}
              </div>
            )}
          </div>
        </Link>

        <button
          type="button"
          onClick={() => setExpanded((v) => !v)}
          aria-expanded={expanded}
          aria-label={expanded ? "Show less detail" : "Show more detail"}
          className="shrink-0 rounded p-1.5 text-gray-400 hover:bg-neutral-700 hover:text-white"
        >
          <ChevronIcon open={expanded} />
        </button>
      </div>

      {expanded && (
        <>
          <div className={`${gap} flex flex-wrap gap-2`}>
            {faction && (
              <span className={`chip ${faction === "Alliance" ? "chip-alliance" : "chip-horde"}`}>
                {faction}
              </span>
            )}
            {c.ruleset && <span className="chip">{c.ruleset}</span>}
            {c.guild && <span className="chip">{`<${c.guild}>`}</span>}
            {typeof c.honor_points === "number" && c.honor_points > 0 && (
              <span className="chip" title="Honor points">
                Honor: {c.honor_points.toLocaleString()}
              </span>
            )}
          </div>

          <div className={`${gap} flex flex-col gap-2 text-sm`}>
            <div className="flex items-center gap-2">
              <GameIcon
                name={c.main_spec ? specIcons[`${c.class}|${c.main_spec}`] : null}
                label={c.main_spec ?? "Spec"}
                size={28}
              />
              <span>
                {c.main_spec || "No spec"}{" "}
                <span className="text-gray-400">({c.main_role})</span>
              </span>
              <span className="ml-auto font-bold text-amber-400" title="Talent points in each tree">
                {talentSplit(c, 1, treeNames)}
              </span>
            </div>

            {c.off_spec && (
              <div className="flex items-center gap-2">
                <GameIcon
                  name={specIcons[`${c.class}|${c.off_spec}`]}
                  label={c.off_spec}
                  size={28}
                />
                <span>
                  {c.off_spec}
                  {c.off_role && <span className="text-gray-400"> ({c.off_role})</span>}
                </span>
                <span className="ml-auto font-bold text-amber-400/80" title="Off spec talent points">
                  {talentSplit(c, 2, treeNames)}
                </span>
              </div>
            )}

            <div className="mt-1 flex flex-wrap gap-x-4 gap-y-1 border-t border-neutral-700 pt-2">
              {professions.length > 0 ? (
                professions.map((p) => (
                  <span key={p.profession} className="flex items-center gap-1.5">
                    <GameIcon name={PROFESSION_ICONS[p.profession]} label={p.profession} size={22} />
                    {p.profession}
                    <span className="text-gray-400">{p.skill}</span>
                  </span>
                ))
              ) : (
                <span className="text-gray-500">No professions yet</span>
              )}
            </div>

            {wishlistPreview.length > 0 && (
              <div className="flex flex-wrap items-center gap-x-2 gap-y-1 border-t border-neutral-700 pt-2 text-xs">
                <span className="text-gray-500">Wants:</span>
                {wishlistPreview.map((w) => (
                  <span key={w.item_name} className="text-gray-300">
                    {w.item_name}
                  </span>
                ))}
                {wishlistMore > 0 && <span className="text-gray-500">+{wishlistMore} more</span>}
              </div>
            )}
          </div>

          <div className={`${gap} border-t border-neutral-700 pt-3`}>
            <ProgressBars bars={characterBars(c)} compact />
          </div>
        </>
      )}
    </div>
  );
}
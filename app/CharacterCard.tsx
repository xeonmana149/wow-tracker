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
import type { AchievementKind, GoldTier } from "../lib/achievements";
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
  well_rounded: { icon: "ability_dualwield", label: "Well-Rounded - has both a main and an off spec" },
};

export const GOLD_TIER_BADGE: Record<GoldTier, { icon: string; label: string }> = {
  Bronze: { icon: "inv_misc_coin_01", label: "Bronze wealth tier - 50g+" },
  Silver: { icon: "inv_misc_coin_03", label: "Silver wealth tier - 500g+" },
  Gold: { icon: "inv_misc_coin_05", label: "Gold wealth tier - 5000g+" },
};

// Epic-gear tier reuses one gem icon for all three tiers (there's no great
// distinct bronze/silver/gold gem in the game's icon set) and shows the
// tier via a colored ring around it instead.
export const EPIC_TIER_META: Record<GoldTier, { icon: string; ring: string; label: string }> = {
  Bronze: {
    icon: "inv_misc_gem_amethyst_02",
    ring: "ring-2 ring-amber-700",
    label: "Equipped 1+ Epic items - Bronze tier",
  },
  Silver: {
    icon: "inv_misc_gem_amethyst_02",
    ring: "ring-2 ring-gray-300",
    label: "Equipped 3+ Epic items - Silver tier",
  },
  Gold: {
    icon: "inv_misc_gem_amethyst_02",
    ring: "ring-2 ring-yellow-400",
    label: "Equipped 5+ Epic items - Gold tier",
  },
};

// The 📅 created-date badge isn't a real achievement, but gets the same
// icon treatment for visual consistency with the ones that are.
export const CREATED_DATE_ICON = "inv_misc_pocketwatch_01";
export const CREATED_DATE_ICON_KEY = "created_date";

type CardAchievement = {
  kind: AchievementKind | "gold" | "epic_gear";
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
  needs_setup?: boolean;
  created_at?: string | null;
  achievements?: CardAchievement[];
  profiles?: { display_name?: string; legacy_points?: number } | null;
  character_professions: { profession: string; skill: number }[];
  character_talents: { slot: number; tree: string; rank: number }[];
  character_legacy?: { rank: number }[];
  // The card only ever shows the first couple still-wanted items, with a
  // "+N more" for the rest - the full list (with priority and the
  // obtained checkbox) lives on the character's own page.
  character_wishlist?: { item_name: string; priority: "High" | "Medium" | "Low"; obtained: boolean }[];

};

const WISHLIST_PRIORITY_ORDER: Record<"High" | "Medium" | "Low", number> = {
  High: 0,
  Medium: 1,
  Low: 2,
};

// Points in each tree for one spec, like 0/32/10
function talentSplit(c: CardCharacter, slot: number, treeNames: string[] | undefined) {
  const per: Record<string, number> = {};
  for (const r of c.character_talents ?? []) {
    if (r.slot === slot) per[r.tree] = (per[r.tree] ?? 0) + r.rank;
  }
  const names = treeNames && treeNames.length > 0 ? treeNames : Object.keys(per);
  return names.length > 0 ? names.map((n) => per[n] ?? 0).join("/") : "-";
}

export default function CharacterCard({
  c,
  treeNames,
  specIcons,
  compact = false,
  iconOverrides = {},
}: {
  c: CardCharacter;
  treeNames: string[] | undefined;
  specIcons: Record<string, string>;
  compact?: boolean;
  // Lets any badge icon be swapped at runtime via the badge_icons table
  // (edited from the /dev/badges tester page) instead of needing a code
  // change. Defaults to {} so passing nothing just uses every default.
  iconOverrides?: BadgeIconOverrides;
}) {
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

  return (
    <Link
      href={`/character/${c.id}`}
      className={`block rounded bg-neutral-800 ${pad} hover:bg-neutral-700 ${
        c.needs_setup ? "ring-2 ring-amber-400" : ""
      }`}
    >
      {c.needs_setup && (
        <div className="mb-2 flex items-center gap-1.5 rounded bg-amber-500/15 px-2 py-1 text-xs font-bold text-amber-300">
          <span className="text-sm">⚠</span> Needs attention
        </div>
      )}
      <div className="flex items-start gap-3">
        <GameIcon name={classIcon(c.class)} label={c.class} size={compact ? 44 : 52} round />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-lg font-bold text-white">{c.name}</span>
            <span className="rounded bg-neutral-600 px-2 py-0.5 text-xs">{c.character_type}</span>
            {(c.achievements ?? []).map((a) => {
              if (a.kind === "gold" && a.tier) {
                const badge = GOLD_TIER_BADGE[a.tier];
                const icon = resolvedIcon(iconOverrides, `gold:${a.tier}`, badge.icon);
                return (
                  <span key="gold" className="inline-block rounded-full ring-2 ring-amber-500/70">
                    <GameIcon src={wowIconUrl(icon)} label={badge.label} size={22} round />
                  </span>
                );
              }
              if (a.kind === "epic_gear" && a.tier) {
                const meta = EPIC_TIER_META[a.tier];
                const icon = resolvedIcon(iconOverrides, "epic_gear", meta.icon);
                return (
                  <span key="epic_gear" className={`inline-block rounded-full ${meta.ring}`}>
                    <GameIcon src={wowIconUrl(icon)} label={meta.label} size={22} round />
                  </span>
                );
              }
              const badge = ACHIEVEMENT_BADGES[a.kind as AchievementKind];
              if (!badge) return null;
              const icon = resolvedIcon(iconOverrides, a.kind, badge.icon);
              return <GameIcon key={a.kind} src={wowIconUrl(icon)} label={badge.label} size={22} round />;
            })}
            {createdLabel && (
              <GameIcon
                src={wowIconUrl(resolvedIcon(iconOverrides, CREATED_DATE_ICON_KEY, CREATED_DATE_ICON))}
                label={`Created ${createdLabel}`}
                size={22}
                round
              />
            )}
          </div>
          <div className="mt-1 flex items-center gap-2 text-sm text-gray-400">
            <GameIcon name={RACE_ICONS[c.race]} label={c.race} size={20} round />
            <span>
              Level {c.level} {c.race} {c.class}
            </span>
          </div>
        </div>
      </div>

      <div className={`${gap} flex flex-wrap gap-2`}>
        {faction && (
          <span className={`chip ${faction === "Alliance" ? "chip-alliance" : "chip-horde"}`}>
            {faction}
          </span>
        )}
        {c.ruleset && <span className="chip">{c.ruleset}</span>}
        {c.guild && <span className="chip">{`<${c.guild}>`}</span>}
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
    </Link>
  );
}
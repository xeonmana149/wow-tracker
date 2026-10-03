"use client";

import { useState } from "react";
import Link from "next/link";
import { RACE_FACTION } from "../lib/options";
import { PRIMARY_PROFESSIONS, PROFESSION_ICONS, RACE_ICONS, classIcon } from "../lib/icons";
import { characterBars } from "../lib/progress";
import type { AchievementKind, GoldTier, TieredAchievementKind } from "../lib/achievements";
import { localBadgeIconSrc } from "../lib/badgeFrames";
import GameIcon from "./GameIcon";
import TierFramedIcon from "./TierFramedIcon";
import BadgePlaceholder from "./BadgePlaceholder";
import ProgressBars from "./ProgressBars";

export type { AchievementKind, GoldTier };

// The badge/icon lookup tables (ACHIEVEMENT_BADGES, RING_TIER_BADGES,
// TIERED_LOCAL_ICONS, FLAT_LOCAL_ICONS, etc.) used to be defined directly in
// this file. They've moved to lib/achievementBadges.ts, a plain module with
// no "use client" directive, because app/achievementBoard.ts - which feeds
// the *server* component app/character/[id]/page.tsx - was importing them
// from here. Next's RSC bundler replaces plain data exports of a "use
// client" module with client-reference stubs when a server component reads
// them, so every lookup (e.g. TIERED_LOCAL_ICONS[kind]) silently came back
// `undefined` on the character page, falling back to inv_misc_questionmark.
// Imported here (not just re-exported) because this file's own render code
// below still uses these tables directly, and `export { X } from "module"`
// only re-exports X - it does not bind X into this module's local scope.
import {
  ACHIEVEMENT_BADGES,
  GOLD_TIER_LABEL,
  EPIC_TIER_META,
  RECIPE_TIER_BADGE,
  HONORABLE_KILLS_TIER_BADGE,
  CREATURES_KILLED_TIER_BADGE,
  QUESTS_COMPLETED_TIER_BADGE,
  KILLING_BLOWS_TIER_BADGE,
  BOSS_KILLS_TIER_BADGE,
  CONSUMABLES_TIER_BADGE,
  TRAVEL_TIER_BADGE,
  SOCIAL_TIER_BADGE,
  BG_WINS_TIER_BADGE,
  DUELS_WON_TIER_BADGE,
  DAMAGE_DONE_TIER_BADGE,
  HEALING_DONE_TIER_BADGE,
  DUNGEONS_ENTERED_TIER_BADGE,
  RAIDS_ENTERED_TIER_BADGE,
  EXALTED_FACTIONS_TIER_BADGE,
  MOUNTS_OWNED_TIER_BADGE,
  PETS_OWNED_TIER_BADGE,
  LOOT_ROLLS_TIER_BADGE,
  FISH_CAUGHT_TIER_BADGE,
  AUCTIONS_POSTED_TIER_BADGE,
  AUCTION_GOLD_TIER_BADGE,
  RING_TIER_BADGES,
  TIERED_LOCAL_ICONS,
  FLAT_LOCAL_ICONS,
} from "../lib/achievementBadges";

// Re-exported so existing client-side imports (CharacterRow, Dashboard,
// dev-badges-page) that pull these names from "./CharacterCard" keep
// working unchanged.
export {
  ACHIEVEMENT_BADGES,
  GOLD_TIER_LABEL,
  EPIC_TIER_META,
  RECIPE_TIER_BADGE,
  HONORABLE_KILLS_TIER_BADGE,
  CREATURES_KILLED_TIER_BADGE,
  QUESTS_COMPLETED_TIER_BADGE,
  KILLING_BLOWS_TIER_BADGE,
  BOSS_KILLS_TIER_BADGE,
  CONSUMABLES_TIER_BADGE,
  TRAVEL_TIER_BADGE,
  SOCIAL_TIER_BADGE,
  BG_WINS_TIER_BADGE,
  DUELS_WON_TIER_BADGE,
  DAMAGE_DONE_TIER_BADGE,
  HEALING_DONE_TIER_BADGE,
  DUNGEONS_ENTERED_TIER_BADGE,
  RAIDS_ENTERED_TIER_BADGE,
  EXALTED_FACTIONS_TIER_BADGE,
  MOUNTS_OWNED_TIER_BADGE,
  PETS_OWNED_TIER_BADGE,
  LOOT_ROLLS_TIER_BADGE,
  FISH_CAUGHT_TIER_BADGE,
  AUCTIONS_POSTED_TIER_BADGE,
  AUCTION_GOLD_TIER_BADGE,
  RING_TIER_BADGES,
  TIERED_LOCAL_ICONS,
  FLAT_LOCAL_ICONS,
};

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
  defaultExpanded = false,
  showNeedsAttention = true,
}: {
  c: CardCharacter;
  treeNames: string[] | undefined;
  specIcons: Record<string, string>;
  compact?: boolean;
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
            {(c.achievements ?? []).length > 0 && (
              // Capped height + its own scrollbar (2026-10-03, "character
              // achievements endlessly scroll over all the other text and
              // should stay bound to the character box") - with enough
              // earned badges this row used to just keep wrapping onto more
              // and more lines with nothing capping it, growing the card
              // taller than its neighbors (the "Other Characters" column,
              // the page content below) instead of staying contained.
              <div className="mt-1.5 flex max-h-28 flex-wrap items-center gap-2 overflow-y-auto">
                {(c.achievements ?? []).map((a) => {
                  if (a.kind === "gold" && a.tier) {
                    const localIcon = TIERED_LOCAL_ICONS.gold;
                    if (!localIcon) return null;
                    return (
                      <TierFramedIcon
                        key="gold"
                        icon={localIcon}
                        tier={a.tier}
                        label={GOLD_TIER_LABEL[a.tier]}
                        size={46}
                      />
                    );
                  }
                  const ringBadge = RING_TIER_BADGES[a.kind as TieredAchievementKind];
                  if (ringBadge && a.tier) {
                    const meta = ringBadge[a.tier];
                    const localIcon = TIERED_LOCAL_ICONS[a.kind as TieredAchievementKind];
                    if (localIcon) {
                      return <TierFramedIcon key={a.kind} icon={localIcon} tier={a.tier} label={meta.label} size={46} />;
                    }
                    return <BadgePlaceholder key={a.kind} tier={a.tier} label={meta.label} size={46} round />;
                  }
                  const badge = ACHIEVEMENT_BADGES[a.kind as AchievementKind];
                  if (!badge) return null;
                  // "character_created" shows the real creation date in its
                  // tooltip (kept from the old decorative badge this
                  // replaced) rather than the generic label every other
                  // flat badge uses - the achievements table doesn't need
                  // to carry that text, c.created_at already has it.
                  const label =
                    a.kind === "character_created" && createdLabel
                      ? `Created ${createdLabel}`
                      : badge.label;
                  const flatLocalIcon = FLAT_LOCAL_ICONS[a.kind as AchievementKind];
                  if (flatLocalIcon) {
                    return (
                      <GameIcon
                        key={a.kind}
                        src={localBadgeIconSrc(flatLocalIcon)}
                        label={label}
                        size={46}
                        round
                      />
                    );
                  }
                  return <BadgePlaceholder key={a.kind} label={label} size={46} round />;
                })}
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
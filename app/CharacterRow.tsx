"use client";

import Link from "next/link";
import { PRIMARY_PROFESSIONS, PROFESSION_ICONS, RACE_ICONS, classIcon, wowIconUrl } from "../lib/icons";
import { characterBars } from "../lib/progress";
import { resolvedIcon, type BadgeIconOverrides } from "../lib/badgeIconOverrides";
import GameIcon from "./GameIcon";
import {
  ACHIEVEMENT_BADGES,
  GOLD_TIER_BADGE,
  EPIC_TIER_META,
  RECIPE_TIER_BADGE,
  characterTypeStyle,
  type AchievementKind,
  type CardCharacter,
} from "./CharacterCard";

// The game's own class-name colors, used for the ring around each
// character's portrait icon here - not used anywhere else on the site, so
// kept local rather than added to lib/icons.ts.
const CLASS_COLORS: Record<string, string> = {
  Warrior: "#C79C6E",
  Paladin: "#F58CBA",
  Hunter: "#ABD473",
  Rogue: "#FFF569",
  Priest: "#FFFFFF",
  Shaman: "#0070DE",
  Mage: "#69CCF0",
  Warlock: "#9482C9",
  Druid: "#FF7D0A",
};

function ChevronRight() {
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
      className="shrink-0 text-gray-500"
      aria-hidden="true"
    >
      <path d="M9 6l6 6-6 6" />
    </svg>
  );
}

// A single wide row per character - portrait, name/type/level/guild,
// profession + achievement icons, a level progress bar, and a chevron to
// open the full character page. Compact alternative to the full
// CharacterCard grid, for places (like the Dashboard) where scanning a
// longer character list at a glance matters more than seeing every detail
// inline - talents, gear and wishlist are a click away on the character's
// own page either way.
export default function CharacterRow({
  c,
  iconOverrides = {},
}: {
  c: CardCharacter;
  iconOverrides?: BadgeIconOverrides;
}) {
  const typeStyle = characterTypeStyle(c.character_type);

  // Live XP within the CURRENT level, from the addon (v1.5.0+) via
  // UnitXP/UnitXPMax - real progress toward the next level, not just how
  // close the character is to the level cap. xp_max comes back 0 at the
  // level cap (no bar left to fill) and on anything that hasn't synced
  // since this was added, so those fall back to the same level-out-of-60
  // bar the expanded CharacterCard shows elsewhere.
  const hasLiveXp = typeof c.xp === "number" && typeof c.xp_max === "number" && c.xp_max > 0;

  let percent: number;
  let barCaption: string;
  let barText: string;
  if (hasLiveXp) {
    const xp = c.xp as number;
    const xpMax = c.xp_max as number;
    percent = Math.min(100, Math.round((xp / xpMax) * 100));
    const remaining = Math.max(0, xpMax - xp);
    barCaption = "XP to next level";
    barText = `${remaining.toLocaleString()} XP to go`;
  } else {
    const levelBar = characterBars(c).find((b) => b.key === "level")!;
    percent = Math.min(100, Math.round((levelBar.value / levelBar.max) * 100));
    barCaption = c.level >= levelBar.max ? "Max level" : "Level";
    barText = levelBar.text;
  }

  const professions = (c.character_professions ?? [])
    .filter((p) => PRIMARY_PROFESSIONS.includes(p.profession))
    .sort((a, b) => b.skill - a.skill);

  return (
    <Link
      href={`/character/${c.id}`}
      className="character-card flex items-center gap-3 rounded-lg border-l-4 bg-neutral-800 p-3"
      style={{ borderLeftColor: typeStyle.border }}
    >
      <span
        className="inline-block shrink-0 rounded-full"
        style={{ boxShadow: `0 0 0 2px ${CLASS_COLORS[c.class] ?? "#6b7280"}` }}
      >
        <GameIcon name={classIcon(c.class)} label={c.class} size={52} round />
      </span>

      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-2">
          <span className="font-bold text-white">{c.name}</span>
          <span className={`rounded px-2 py-0.5 text-xs font-semibold ${typeStyle.pill}`}>
            {c.character_type}
          </span>
        </div>

        <div className="mt-0.5 flex items-center gap-1.5 text-sm text-gray-400">
          <GameIcon name={RACE_ICONS[c.race]} label={c.race} size={16} round />
          <span>
            Level {c.level} {c.race} {c.class}
          </span>
        </div>

        <div className="mt-1 flex flex-wrap items-center gap-3 text-xs text-gray-500">
          <span>{c.guild ? `<${c.guild}>` : "No guild"}</span>

          {professions.length > 0 && (
            <span className="flex items-center gap-1">
              {professions.map((p) => (
                <GameIcon
                  key={p.profession}
                  name={PROFESSION_ICONS[p.profession]}
                  label={p.profession}
                  size={16}
                />
              ))}
            </span>
          )}

          {(c.achievements ?? []).length > 0 && (
            <span className="flex items-center gap-1">
              {(c.achievements ?? []).map((a) => {
                if (a.kind === "gold" && a.tier) {
                  const badge = GOLD_TIER_BADGE[a.tier];
                  const icon = resolvedIcon(iconOverrides, `gold:${a.tier}`, badge.icon);
                  return <GameIcon key="gold" src={wowIconUrl(icon)} label={badge.label} size={18} round />;
                }
                if (a.kind === "epic_gear" && a.tier) {
                  const meta = EPIC_TIER_META[a.tier];
                  const icon = resolvedIcon(iconOverrides, "epic_gear", meta.icon);
                  return <GameIcon key="epic_gear" src={wowIconUrl(icon)} label={meta.label} size={18} round />;
                }
                if (a.kind === "recipes" && a.tier) {
                  const meta = RECIPE_TIER_BADGE[a.tier];
                  const icon = resolvedIcon(iconOverrides, `recipes:${a.tier}`, meta.icon);
                  return <GameIcon key="recipes" src={wowIconUrl(icon)} label={meta.label} size={18} round />;
                }
                const badge = ACHIEVEMENT_BADGES[a.kind as AchievementKind];
                if (!badge) return null;
                const icon = resolvedIcon(iconOverrides, a.kind, badge.icon);
                return <GameIcon key={a.kind} src={wowIconUrl(icon)} label={badge.label} size={18} round />;
              })}
            </span>
          )}
        </div>
      </div>

      <div className="hidden w-40 shrink-0 sm:block">
        <div className="flex items-center justify-between text-xs text-gray-400">
          <span>{barCaption}</span>
          <span>{percent}%</span>
        </div>
        <div className="mt-1 h-2 rounded bg-neutral-700">
          <div
            className={`h-2 rounded ${percent >= 100 ? "bg-yellow-500" : "bg-blue-500"}`}
            style={{ width: `${percent}%` }}
          />
        </div>
        <div className="mt-0.5 text-xs text-gray-500">{barText}</div>
      </div>

      <ChevronRight />
    </Link>
  );
}
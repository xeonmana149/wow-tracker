import Link from "next/link";
import { RACE_FACTION } from "../lib/options";
import {
  PRIMARY_PROFESSIONS,
  PROFESSION_ICONS,
  RACE_ICONS,
  classIcon,
} from "../lib/icons";
import { characterBars } from "../lib/progress";
import type { AchievementKind, GoldTier } from "../lib/achievements";
import GameIcon from "./GameIcon";
import ProgressBars from "./ProgressBars";

export type { AchievementKind, GoldTier };

// Plain yes/no achievements - anyone can earn each of these independently
// (see lib/achievements.ts). Doesn't cover "gold" or "epic_gear", which
// are tiered instead and rendered separately below.
const ACHIEVEMENT_BADGES: Record<AchievementKind, { icon: string; label: string }> = {
  max_level: { icon: "👑", label: "Reached the level cap" },
  legendary_item: { icon: "🟠", label: "Obtained a Legendary item" },
  maxed_profession: { icon: "⭐", label: "Maxed a profession" },
  renaissance: { icon: "🎓", label: "Maxed every profession (2 primary + all 3 secondary)" },
  maxed_legacy: { icon: "🏵️", label: "Maxed the account's Legacy points" },
  top_pvp_rank: { icon: "⚔️", label: "Reached the top PvP rank" },
  founding_member: { icon: "🏛️", label: "Founding Member - created during launch week" },
  well_rounded: { icon: "🧭", label: "Well-Rounded - has both a main and an off spec" },
};

const GOLD_TIER_BADGE: Record<GoldTier, { icon: string; label: string }> = {
  Bronze: { icon: "🥉", label: "Bronze wealth tier - 50g+" },
  Silver: { icon: "🥈", label: "Silver wealth tier - 500g+" },
  Gold: { icon: "🥇", label: "Gold wealth tier - 5000g+" },
};

// Epic-gear tier reuses one gem icon for all three tiers (there's no great
// bronze/silver/gold gem emoji set) and shows the tier via a colored ring
// instead.
const EPIC_TIER_META: Record<GoldTier, { ring: string; label: string }> = {
  Bronze: { ring: "ring-2 ring-amber-700", label: "Equipped 1+ Epic items - Bronze tier" },
  Silver: { ring: "ring-2 ring-gray-300", label: "Equipped 3+ Epic items - Silver tier" },
  Gold: { ring: "ring-2 ring-yellow-400", label: "Equipped 5+ Epic items - Gold tier" },
};

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
}: {
  c: CardCharacter;
  treeNames: string[] | undefined;
  specIcons: Record<string, string>;
  compact?: boolean;
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
                return (
                  <span
                    key="gold"
                    title={badge.label}
                    className="grid h-5 w-5 place-items-center rounded-full bg-amber-500/20 text-xs"
                  >
                    {badge.icon}
                  </span>
                );
              }
              if (a.kind === "epic_gear" && a.tier) {
                const meta = EPIC_TIER_META[a.tier];
                return (
                  <span
                    key="epic_gear"
                    title={meta.label}
                    className={`grid h-5 w-5 place-items-center rounded-full bg-purple-500/20 text-xs ${meta.ring}`}
                  >
                    🟣
                  </span>
                );
              }
              const badge = ACHIEVEMENT_BADGES[a.kind as AchievementKind];
              if (!badge) return null;
              return (
                <span
                  key={a.kind}
                  title={badge.label}
                  className="grid h-5 w-5 place-items-center rounded-full bg-amber-500/20 text-xs"
                >
                  {badge.icon}
                </span>
              );
            })}
            {createdLabel && (
              <span
                title={`Created ${createdLabel}`}
                className="grid h-5 w-5 place-items-center rounded-full bg-neutral-600/40 text-xs"
              >
                📅
              </span>
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
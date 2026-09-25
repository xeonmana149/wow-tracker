"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { supabase } from "../../lib/supabase";
import { classIcon, wowIconUrl } from "../../lib/icons";
import { localBadgeIconSrc, TIER_FRAME_SRC, FRAME_HOLE_RATIO, TIER_MEDAL_SRC, RANK_ICON_SRC } from "../../lib/badgeFrames";
import { TIERED_LOCAL_ICONS, RING_TIER_BADGES } from "../../lib/achievementBadges";
import GameIcon from "../GameIcon";
import TierFramedIcon from "../TierFramedIcon";
import MilestoneBar from "../MilestoneBar";
import {
  TIERED_ACHIEVEMENT_KINDS,
  tierLabel,
  tierDescription,
  tierFamily,
  tierThresholds,
  FAMILY_META,
  TIER_POINTS,
  computeCounter,
  type AchievementTier,
  type TieredAchievementKind,
  type AchievementFamily,
} from "../../lib/achievements";

// The 2026-09-25 leaderboards rework - three modes built on top of the
// same Statistics-based achievement system as the character page and
// badges: Overall (achievement points), Achievements (one badge at a
// time, ranked by progress), and Statistics (any raw stat, searched
// straight out of character_statistics - nothing hardcoded, so this board
// never needs an update just because a new stat gets tracked). A
// head-to-head Compare view is a planned follow-up, not part of this pass.

type Mode = "overall" | "achievements" | "statistics";
type Scope = "characters" | "accounts";

type CharacterRow = {
  id: string;
  name: string;
  level: number;
  class: string;
  character_type: string;
  user_id: string;
};

type AchievementRow = {
  character_id: string;
  kind: string;
  tier: AchievementTier | null;
};

type StatRow = {
  character_id: string;
  category: string;
  name: string;
  value: string;
};

type ProfessionRow = {
  character_id: string;
  recipes: unknown[] | null;
};

const TIER_ORDER: AchievementTier[] = ["Platinum", "Gold", "Silver", "Copper"];

function parseStatValue(value: string): number | null {
  const n = Number(value.replace(/,/g, ""));
  return Number.isFinite(n) ? n : null;
}

export default function LeaderboardsPage() {
  const [loading, setLoading] = useState(true);
  const [characters, setCharacters] = useState<CharacterRow[]>([]);
  const [displayNames, setDisplayNames] = useState<Record<string, string>>({});
  const [achievements, setAchievements] = useState<AchievementRow[]>([]);
  const [stats, setStats] = useState<StatRow[]>([]);
  const [totalRecipes, setTotalRecipes] = useState<Record<string, number>>({});

  const [mode, setMode] = useState<Mode>("overall");
  const [scope, setScope] = useState<Scope>("characters");
  const [mainsOnly, setMainsOnly] = useState(false);
  const [achievementKind, setAchievementKind] = useState<TieredAchievementKind>(
    TIERED_ACHIEVEMENT_KINDS[0]
  );
  const [statQuery, setStatQuery] = useState("");
  const [selectedStat, setSelectedStat] = useState<{ category: string; name: string } | null>(null);

  useEffect(() => {
    async function load() {
      // Group-wide, not scoped to the logged-in user - same visibility as
      // the achievements/character_statistics RLS policies ("viewable by
      // everyone"), since the whole point is comparing across the group.
      const [
        { data: characterRows },
        { data: profileRows },
        { data: achievementRows },
        { data: statRows },
        { data: professionRows },
      ] = await Promise.all([
        supabase.from("characters").select("id, name, level, class, character_type, user_id"),
        supabase.from("profiles").select("id, display_name"),
        supabase.from("achievements").select("character_id, kind, tier"),
        supabase.from("character_statistics").select("character_id, category, name, value"),
        supabase.from("character_professions").select("character_id, recipes"),
      ]);

      setCharacters((characterRows ?? []) as CharacterRow[]);

      const names: Record<string, string> = {};
      for (const p of (profileRows ?? []) as { id: string; display_name: string | null }[]) {
        if (p.display_name) names[p.id] = p.display_name;
      }
      setDisplayNames(names);

      setAchievements((achievementRows ?? []) as AchievementRow[]);
      setStats((statRows ?? []) as StatRow[]);

      const recipeTotals: Record<string, number> = {};
      for (const p of (professionRows ?? []) as ProfessionRow[]) {
        const count = Array.isArray(p.recipes) ? p.recipes.length : 0;
        recipeTotals[p.character_id] = (recipeTotals[p.character_id] ?? 0) + count;
      }
      setTotalRecipes(recipeTotals);

      setLoading(false);
    }
    load();
  }, []);

  const statsByCharacter = useMemo(() => {
    const map = new Map<string, StatRow[]>();
    for (const s of stats) {
      const list = map.get(s.character_id) ?? [];
      list.push(s);
      map.set(s.character_id, list);
    }
    return map;
  }, [stats]);

  const achievementsByCharacter = useMemo(() => {
    const map = new Map<string, AchievementRow[]>();
    for (const a of achievements) {
      const list = map.get(a.character_id) ?? [];
      list.push(a);
      map.set(a.character_id, list);
    }
    return map;
  }, [achievements]);

  // Every tiered badge's current counter value for one character - recipes
  // comes from character_professions (fetched separately, see above),
  // everything else from character_statistics via the same computeCounter
  // helper importLogic.ts uses to actually award the badges, so this page
  // can never disagree with what got awarded.
  function counterFor(characterId: string, kind: TieredAchievementKind): number {
    if (kind === "recipes") return totalRecipes[characterId] ?? 0;
    return computeCounter(kind, statsByCharacter.get(characterId) ?? []);
  }

  function pointsFor(characterId: string): number {
    let total = 0;
    for (const a of achievementsByCharacter.get(characterId) ?? []) {
      if (a.tier) total += TIER_POINTS[a.tier];
    }
    return total;
  }

  function tierCountsFor(characterId: string): Record<AchievementTier, number> {
    const counts: Record<AchievementTier, number> = { Platinum: 0, Gold: 0, Silver: 0, Copper: 0 };
    for (const a of achievementsByCharacter.get(characterId) ?? []) {
      if (a.tier) counts[a.tier] += 1;
    }
    return counts;
  }

  const filteredCharacters = useMemo(
    () => (mainsOnly ? characters.filter((c) => c.character_type === "Main") : characters),
    [characters, mainsOnly]
  );

  // Groups the filtered characters by account (user_id) - used whenever
  // scope is "accounts", for every mode.
  const accountGroups = useMemo(() => {
    const map = new Map<string, CharacterRow[]>();
    for (const c of filteredCharacters) {
      const list = map.get(c.user_id) ?? [];
      list.push(c);
      map.set(c.user_id, list);
    }
    return Array.from(map.entries()).map(([userId, chars]) => ({
      userId,
      label: displayNames[userId] ?? chars[0]?.name ?? "Unknown account",
      characters: chars,
    }));
  }, [filteredCharacters, displayNames]);

  if (loading) {
    return <main className="mx-auto max-w-[1200px] p-4 md:p-6">Loading leaderboards...</main>;
  }

  return (
    <main className="mx-auto max-w-[1200px] p-4 md:p-6">
      <h1 className="text-4xl font-bold">Leaderboards</h1>
      <p className="mt-1 text-gray-400">See how everyone stacks up - overall, by badge, or by any raw stat.</p>

      <div className="mt-4 flex flex-wrap items-center gap-2">
        {(["overall", "achievements", "statistics"] as Mode[]).map((m) => (
          <button
            key={m}
            type="button"
            onClick={() => setMode(m)}
            className={`rounded px-3 py-1.5 text-sm font-semibold capitalize ${
              mode === m ? "bg-red-700 text-white" : "bg-neutral-800 text-gray-300 hover:bg-neutral-700"
            }`}
          >
            {m}
          </button>
        ))}

        <span className="mx-2 h-5 w-px bg-neutral-700" />

        <div className="flex overflow-hidden rounded border border-neutral-700">
          {(["characters", "accounts"] as Scope[]).map((s) => (
            <button
              key={s}
              type="button"
              onClick={() => setScope(s)}
              className={`px-3 py-1.5 text-sm capitalize ${
                scope === s ? "bg-neutral-700 text-white" : "bg-neutral-900 text-gray-400 hover:bg-neutral-800"
              }`}
            >
              By {s === "characters" ? "character" : "account"}
            </button>
          ))}
        </div>

        <label className="flex items-center gap-1.5 text-sm text-gray-400">
          <input type="checkbox" checked={mainsOnly} onChange={(e) => setMainsOnly(e.target.checked)} />
          Mains only
        </label>
      </div>

      {mode === "overall" && (
        <OverallBoard
          characters={filteredCharacters}
          accountGroups={accountGroups}
          scope={scope}
          pointsFor={pointsFor}
          tierCountsFor={tierCountsFor}
        />
      )}

      {mode === "achievements" && (
        <AchievementsBoard
          characters={filteredCharacters}
          accountGroups={accountGroups}
          scope={scope}
          achievementKind={achievementKind}
          setAchievementKind={setAchievementKind}
          counterFor={counterFor}
          achievementsByCharacter={achievementsByCharacter}
        />
      )}

      {mode === "statistics" && (
        <StatisticsBoard
          characters={filteredCharacters}
          accountGroups={accountGroups}
          scope={scope}
          stats={stats}
          statQuery={statQuery}
          setStatQuery={setStatQuery}
          selectedStat={selectedStat}
          setSelectedStat={setSelectedStat}
        />
      )}
    </main>
  );
}

function RankBadge({ rank }: { rank: number }) {
  const medalSrc = rank === 1 || rank === 2 || rank === 3 ? RANK_ICON_SRC[rank] : null;
  if (medalSrc) {
    return (
      // eslint-disable-next-line @next/next/no-img-element
      <img
        src={medalSrc}
        alt={`Rank ${rank}`}
        draggable={false}
        className="w-8 shrink-0 object-contain"
      />
    );
  }
  return (
    <span className="w-8 shrink-0 text-center text-lg font-bold text-gray-400">{rank}</span>
  );
}

function OverallBoard({
  characters,
  accountGroups,
  scope,
  pointsFor,
  tierCountsFor,
}: {
  characters: CharacterRow[];
  accountGroups: { userId: string; label: string; characters: CharacterRow[] }[];
  scope: Scope;
  pointsFor: (characterId: string) => number;
  tierCountsFor: (characterId: string) => Record<AchievementTier, number>;
}) {
  if (scope === "characters") {
    const ranked = characters
      .map((c) => ({ c, points: pointsFor(c.id), counts: tierCountsFor(c.id) }))
      .sort((a, b) => b.points - a.points);

    return (
      <section className="mt-4 flex flex-col gap-2">
        {ranked.length === 0 && <EmptyState />}
        {ranked.map((row, i) => (
          <div
            key={row.c.id}
            className="flex flex-wrap items-center gap-3 rounded-lg border border-neutral-700 bg-neutral-900/40 p-3"
          >
            <RankBadge rank={i + 1} />
            <GameIcon name={classIcon(row.c.class)} label={row.c.class} size={36} round />
            <div className="min-w-0 flex-1">
              <Link href={`/character/${row.c.id}`} className="font-semibold text-white hover:underline">
                {row.c.name}
              </Link>
              <div className="text-xs text-gray-500">
                Level {row.c.level} {row.c.class} · {row.c.character_type}
              </div>
            </div>
            <TierCountsRow counts={row.counts} />
            <span className="ml-auto shrink-0 text-lg font-bold text-[#c9a566]">
              {row.points.toLocaleString()} pts
            </span>
          </div>
        ))}
      </section>
    );
  }

  const ranked = accountGroups
    .map((g) => {
      const points = g.characters.reduce((sum, c) => sum + pointsFor(c.id), 0);
      const counts: Record<AchievementTier, number> = { Platinum: 0, Gold: 0, Silver: 0, Copper: 0 };
      for (const c of g.characters) {
        const cCounts = tierCountsFor(c.id);
        for (const t of TIER_ORDER) counts[t] += cCounts[t];
      }
      return { ...g, points, counts };
    })
    .sort((a, b) => b.points - a.points);

  return (
    <section className="mt-4 flex flex-col gap-2">
      {ranked.length === 0 && <EmptyState />}
      {ranked.map((row, i) => (
        <div
          key={row.userId}
          className="flex flex-wrap items-center gap-3 rounded-lg border border-neutral-700 bg-neutral-900/40 p-3"
        >
          <RankBadge rank={i + 1} />
          <div className="min-w-0 flex-1">
            <div className="font-semibold text-white">{row.label}</div>
            <div className="text-xs text-gray-500">
              {row.characters.length} character{row.characters.length === 1 ? "" : "s"}
            </div>
          </div>
          <TierCountsRow counts={row.counts} />
          <span className="ml-auto shrink-0 text-lg font-bold text-[#c9a566]">
            {row.points.toLocaleString()} pts
          </span>
        </div>
      ))}
    </section>
  );
}

function TierCountsRow({ counts }: { counts: Record<AchievementTier, number> }) {
  return (
    <div className="flex shrink-0 items-center gap-1.5 text-sm text-gray-300">
      {TIER_ORDER.map((t) => (
        <span key={t} title={`${t} tier badges`} className="flex items-center gap-1">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={TIER_MEDAL_SRC[t]} alt={t} draggable={false} className="h-5 w-5 object-contain" />
          {counts[t]}
        </span>
      ))}
    </div>
  );
}

// Renders one tiered achievement's actual badge art - the same
// TIERED_LOCAL_ICONS/RING_TIER_BADGES lookup and TierFramedIcon component
// the character page, achievement browser and character rows all use now
// (2026-09-25 badge-art rework), instead of this board's old generic medal
// emoji. Falls back to the ring-and-CDN-icon treatment for any kind that
// hasn't gotten local art yet, same as everywhere else.
function AchievementKindIcon({
  kind,
  tier,
  size = 32,
  dim = false,
}: {
  kind: TieredAchievementKind;
  tier: AchievementTier | null;
  size?: number;
  dim?: boolean;
}) {
  const localIcon = TIERED_LOCAL_ICONS[kind];
  const ring = RING_TIER_BADGES[kind];
  const label = tierLabel(kind);

  if (tier) {
    if (localIcon) {
      return <TierFramedIcon icon={localIcon} tier={tier} label={label} size={size} />;
    }
    const meta = ring?.[tier];
    return (
      <span className={`inline-block shrink-0 rounded-full ${meta?.ring ?? ""}`}>
        <GameIcon src={wowIconUrl(meta?.icon ?? "inv_misc_questionmark")} label={label} size={size} round />
      </span>
    );
  }

  // No tier - either this row hasn't earned one yet, or this is the
  // header's plain preview icon for whatever achievement is selected.
  const cdnIcon = ring?.Copper.icon ?? "inv_misc_questionmark";
  const src = localIcon ? localBadgeIconSrc(localIcon) : wowIconUrl(cdnIcon);
  return (
    <span
      className={`relative inline-block shrink-0 overflow-hidden rounded-sm ${dim ? "opacity-50 grayscale" : ""}`}
      style={{ width: size, height: size }}
    >
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={src} alt="" draggable={false} className="h-full w-full object-cover" />
    </span>
  );
}

function AchievementsBoard({
  characters,
  accountGroups,
  scope,
  achievementKind,
  setAchievementKind,
  counterFor,
  achievementsByCharacter,
}: {
  characters: CharacterRow[];
  accountGroups: { userId: string; label: string; characters: CharacterRow[] }[];
  scope: Scope;
  achievementKind: TieredAchievementKind;
  setAchievementKind: (k: TieredAchievementKind) => void;
  counterFor: (characterId: string, kind: TieredAchievementKind) => number;
  achievementsByCharacter: Map<string, AchievementRow[]>;
}) {
  const byFamily = useMemo(() => {
    const map = new Map<AchievementFamily, TieredAchievementKind[]>();
    for (const kind of TIERED_ACHIEVEMENT_KINDS) {
      const fam = tierFamily(kind);
      const list = map.get(fam) ?? [];
      list.push(kind);
      map.set(fam, list);
    }
    return map;
  }, []);

  const thresholds = tierThresholds(achievementKind);
  const maxThreshold = thresholds[thresholds.length - 1]?.value ?? 1;

  function tierOf(characterId: string): AchievementTier | null {
    const row = (achievementsByCharacter.get(characterId) ?? []).find((a) => a.kind === achievementKind);
    return row?.tier ?? null;
  }

  const rankedCharacters = characters
    .map((c) => ({ c, value: counterFor(c.id, achievementKind), tier: tierOf(c.id) }))
    .filter((r) => r.value > 0)
    .sort((a, b) => b.value - a.value);

  const rankedAccounts = accountGroups
    .map((g) => {
      const value = g.characters.reduce((sum, c) => sum + counterFor(c.id, achievementKind), 0);
      const bestTierRank = g.characters.reduce((best, c) => {
        const t = tierOf(c.id);
        if (!t) return best;
        const rank = TIER_ORDER.indexOf(t);
        return best === -1 ? rank : Math.min(best, rank);
      }, -1);
      return { ...g, value, tier: bestTierRank === -1 ? null : TIER_ORDER[bestTierRank] };
    })
    .filter((r) => r.value > 0)
    .sort((a, b) => b.value - a.value);

  return (
    <section className="mt-4">
      <div className="flex flex-wrap items-start gap-4">
        <div className="min-w-[220px]">
          <label className="text-xs uppercase tracking-wide text-gray-500">Achievement</label>
          <select
            value={achievementKind}
            onChange={(e) => setAchievementKind(e.target.value as TieredAchievementKind)}
            className="mt-1 block w-full rounded border border-neutral-700 bg-neutral-900 px-3 py-1.5 text-sm text-gray-200"
          >
            {Array.from(byFamily.entries()).map(([fam, kinds]) => (
              <optgroup key={fam} label={`${FAMILY_META[fam].icon} ${FAMILY_META[fam].label}`}>
                {kinds.map((k) => (
                  <option key={k} value={k}>
                    {tierLabel(k)}
                  </option>
                ))}
              </optgroup>
            ))}
          </select>
        </div>
        <div className="flex flex-1 items-start gap-3">
          <AchievementKindIcon kind={achievementKind} tier={null} size={44} />
          <div>
            <p className="text-sm font-semibold text-gray-200">{tierLabel(achievementKind)}</p>
            <p className="text-xs text-gray-500">{tierDescription(achievementKind)}</p>
            <div className="mt-2 flex flex-wrap gap-3">
              {thresholds.map((t) => (
                <span key={t.tier} className="flex items-center gap-1.5 text-xs text-gray-400">
                  <AchievementKindIcon kind={achievementKind} tier={t.tier} size={24} />
                  {t.tier} {t.value.toLocaleString()}
                </span>
              ))}
            </div>
          </div>
        </div>
      </div>

      <div className="mt-4 flex flex-col gap-2">
        {scope === "characters" &&
          (rankedCharacters.length === 0 ? (
            <EmptyState />
          ) : (
            rankedCharacters.map((row, i) => (
              <ProgressRow
                key={row.c.id}
                rank={i + 1}
                label={row.c.name}
                sublabel={`Level ${row.c.level} ${row.c.class}`}
                value={row.value}
                tier={row.tier}
                achievementKind={achievementKind}
                maxThreshold={maxThreshold}
                thresholds={thresholds}
                href={`/character/${row.c.id}`}
              />
            ))
          ))}
        {scope === "accounts" &&
          (rankedAccounts.length === 0 ? (
            <EmptyState />
          ) : (
            rankedAccounts.map((row, i) => (
              <ProgressRow
                key={row.userId}
                rank={i + 1}
                label={row.label}
                sublabel={`${row.characters.length} character${row.characters.length === 1 ? "" : "s"}`}
                value={row.value}
                tier={row.tier}
                achievementKind={achievementKind}
                maxThreshold={maxThreshold}
                thresholds={thresholds}
              />
            ))
          ))}
      </div>
    </section>
  );
}

function ProgressRow({
  rank,
  label,
  sublabel,
  value,
  tier,
  achievementKind,
  maxThreshold,
  thresholds,
  href,
}: {
  rank: number;
  label: string;
  sublabel: string;
  value: number;
  tier: AchievementTier | null;
  achievementKind: TieredAchievementKind;
  maxThreshold: number;
  thresholds: { tier: AchievementTier; value: number }[];
  href?: string;
}) {
  return (
    <div className="rounded-lg border border-neutral-700 bg-neutral-900/40 p-3">
      <div className="flex flex-wrap items-center gap-3">
        <RankBadge rank={rank} />
        <AchievementKindIcon kind={achievementKind} tier={tier} size={40} dim={!tier} />
        <div className="min-w-0 flex-1">
          {href ? (
            <Link href={href} className="font-semibold text-white hover:underline">
              {label}
            </Link>
          ) : (
            <span className="font-semibold text-white">{label}</span>
          )}
          <div className="text-xs text-gray-500">{sublabel}</div>
        </div>
        <span className="shrink-0 text-sm font-semibold text-gray-300">{tier ?? "Untiered"}</span>
        <span className="shrink-0 text-lg font-bold text-[#c9a566]">{value.toLocaleString()}</span>
      </div>
      <MilestoneBar value={value} maxValue={maxThreshold} thresholds={thresholds} />
      <div className="mt-1 flex justify-between text-[10px] text-gray-600">
        {thresholds.map((t) => (
          <span key={t.tier}>
            {t.tier} {t.value.toLocaleString()}
          </span>
        ))}
      </div>
    </div>
  );
}

function StatisticsBoard({
  characters,
  accountGroups,
  scope,
  stats,
  statQuery,
  setStatQuery,
  selectedStat,
  setSelectedStat,
}: {
  characters: CharacterRow[];
  accountGroups: { userId: string; label: string; characters: CharacterRow[] }[];
  scope: Scope;
  stats: StatRow[];
  statQuery: string;
  setStatQuery: (q: string) => void;
  selectedStat: { category: string; name: string } | null;
  setSelectedStat: (s: { category: string; name: string } | null) => void;
}) {
  // Built entirely from whatever's actually in character_statistics right
  // now - nothing hardcoded, so this board works for any stat the addon
  // reports without ever needing a code change. A pair only qualifies if
  // at least one character has a real (parseable, non "--") value for it.
  const availableStats = useMemo(() => {
    const seen = new Map<string, { category: string; name: string }>();
    for (const s of stats) {
      if (parseStatValue(s.value) == null) continue;
      const key = `${s.category}\u0000${s.name}`;
      if (!seen.has(key)) seen.set(key, { category: s.category, name: s.name });
    }
    return Array.from(seen.values()).sort(
      (a, b) => a.category.localeCompare(b.category) || a.name.localeCompare(b.name)
    );
  }, [stats]);

  const filteredStats = useMemo(() => {
    const q = statQuery.trim().toLowerCase();
    if (!q) return availableStats;
    return availableStats.filter(
      (s) => s.name.toLowerCase().includes(q) || s.category.toLowerCase().includes(q)
    );
  }, [availableStats, statQuery]);

  const valueByCharacter = useMemo(() => {
    if (!selectedStat) return new Map<string, number>();
    const map = new Map<string, number>();
    for (const s of stats) {
      if (s.category !== selectedStat.category || s.name !== selectedStat.name) continue;
      const n = parseStatValue(s.value);
      if (n != null) map.set(s.character_id, n);
    }
    return map;
  }, [stats, selectedStat]);

  const rankedCharacters = characters
    .map((c) => ({ c, value: valueByCharacter.get(c.id) ?? 0 }))
    .filter((r) => r.value > 0)
    .sort((a, b) => b.value - a.value);

  const rankedAccounts = accountGroups
    .map((g) => ({
      ...g,
      value: g.characters.reduce((sum, c) => sum + (valueByCharacter.get(c.id) ?? 0), 0),
    }))
    .filter((r) => r.value > 0)
    .sort((a, b) => b.value - a.value);

  return (
    <section className="mt-4">
      <input
        type="text"
        value={statQuery}
        onChange={(e) => setStatQuery(e.target.value)}
        placeholder="Search any tracked statistic (e.g. deaths, hugs, gold, quests)..."
        className="w-full max-w-md rounded border border-neutral-700 bg-neutral-900 px-3 py-1.5 text-sm text-gray-200 placeholder:text-gray-500"
      />

      {!selectedStat ? (
        <div className="mt-3 flex max-h-[420px] flex-col gap-1 overflow-y-auto">
          {filteredStats.length === 0 && (
            <p className="text-sm text-gray-500">
              No tracked statistics match "{statQuery}" yet - sync a character first.
            </p>
          )}
          {filteredStats.map((s) => (
            <button
              key={`${s.category}-${s.name}`}
              type="button"
              onClick={() => setSelectedStat(s)}
              className="flex items-center justify-between gap-3 rounded border border-neutral-700 bg-neutral-900/40 px-3 py-1.5 text-left text-sm hover:border-[#c9a566]"
            >
              <span className="text-gray-200">{s.name}</span>
              <span className="text-xs text-gray-500">{s.category}</span>
            </button>
          ))}
        </div>
      ) : (
        <div className="mt-4">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-bold text-gray-200">
              {selectedStat.name} <span className="font-normal text-gray-500">({selectedStat.category})</span>
            </h3>
            <button
              type="button"
              onClick={() => setSelectedStat(null)}
              className="text-xs text-gray-500 hover:text-gray-300"
            >
              ← Choose a different stat
            </button>
          </div>

          <div className="mt-3 flex flex-col gap-2">
            {scope === "characters" &&
              (rankedCharacters.length === 0 ? (
                <EmptyState />
              ) : (
                rankedCharacters.map((row, i) => (
                  <div
                    key={row.c.id}
                    className="flex items-center gap-3 rounded-lg border border-neutral-700 bg-neutral-900/40 p-3"
                  >
                    <RankBadge rank={i + 1} />
                    <Link href={`/character/${row.c.id}`} className="min-w-0 flex-1 font-semibold text-white hover:underline">
                      {row.c.name}
                    </Link>
                    <span className="shrink-0 text-lg font-bold text-[#c9a566]">
                      {row.value.toLocaleString()}
                    </span>
                  </div>
                ))
              ))}
            {scope === "accounts" &&
              (rankedAccounts.length === 0 ? (
                <EmptyState />
              ) : (
                rankedAccounts.map((row, i) => (
                  <div
                    key={row.userId}
                    className="flex items-center gap-3 rounded-lg border border-neutral-700 bg-neutral-900/40 p-3"
                  >
                    <RankBadge rank={i + 1} />
                    <span className="min-w-0 flex-1 font-semibold text-white">{row.label}</span>
                    <span className="shrink-0 text-lg font-bold text-[#c9a566]">
                      {row.value.toLocaleString()}
                    </span>
                  </div>
                ))
              ))}
          </div>
        </div>
      )}
    </section>
  );
}

function EmptyState() {
  return (
    <p className="rounded-lg border border-dashed border-neutral-700 p-6 text-center text-sm text-gray-500">
      Nobody has a recorded value here yet - sync a character to get on the board.
    </p>
  );
}
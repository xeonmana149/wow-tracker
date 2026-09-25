"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { classIcon } from "../../lib/icons";
import type { CardCharacter } from "../CharacterCard";
import {
  ACHIEVEMENT_BADGES,
  GOLD_TIER_LABEL,
  RING_TIER_BADGES,
  TIERED_LOCAL_ICONS,
  FLAT_LOCAL_ICONS,
} from "../CharacterCard";
import GameIcon from "../GameIcon";
import TierFramedIcon from "../TierFramedIcon";
import BadgePlaceholder from "../BadgePlaceholder";
import { localBadgeIconSrc } from "../../lib/badgeFrames";
import type { AchievementKind, GoldTier, TieredAchievementKind } from "../../lib/achievements";
import type { AccountAchievementKind } from "../../lib/accountAchievements";

export type FriendPlayer = {
  id: string;
  name: string;
  characters: CardCharacter[];
  // Kept on the type (populated or not) so callers that still fetch this
  // don't need changing - the account-wide achievements DISPLAY is what's
  // off for now (2026-09-25), via the removed <AccountBadges> below. May
  // come back later.
  accountAchievements?: AccountAchievementKind[];
};

function isMain(c: CardCharacter) {
  return c.character_type.toLowerCase() === "main";
}

// Copper -> "Ng Ss Cc". Characters that have never synced money_copper
// (older addon builds) come back undefined, so this returns null rather
// than a misleading "0g 0s 0c".
function formatGold(copper: number | undefined) {
  if (typeof copper !== "number") return null;
  const gold = Math.floor(copper / 10000);
  const silver = Math.floor((copper % 10000) / 100);
  const cop = copper % 100;
  return `${gold.toLocaleString()}g ${silver}s ${cop}c`;
}

type SortMode = "player" | "level" | "achievements";
type FilterMode = "all" | "main" | "alt";

function achievementCount(c: CardCharacter) {
  return (c.achievements ?? []).length;
}

// The row of real achievement badge art for one character - same lookup
// chain CharacterCard.tsx uses for its own (collapsed) badge row, just
// pulled out so the detail drawer here can show it without duplicating a
// second copy of CharacterCard's expanded layout.
function AchievementRow({ c, size = 40 }: { c: CardCharacter; size?: number }) {
  const achievements = c.achievements ?? [];
  if (achievements.length === 0) return <p className="text-sm text-gray-500">No achievements yet.</p>;

  const createdLabel = c.created_at
    ? new Date(c.created_at).toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" })
    : null;

  return (
    <div className="flex flex-wrap items-center gap-2">
      {achievements.map((a) => {
        if (a.kind === "gold" && a.tier) {
          const localIcon = TIERED_LOCAL_ICONS.gold;
          if (!localIcon) return null;
          return <TierFramedIcon key="gold" icon={localIcon} tier={a.tier} label={GOLD_TIER_LABEL[a.tier]} size={size} />;
        }
        const ringBadge = RING_TIER_BADGES[a.kind as TieredAchievementKind];
        if (ringBadge && a.tier) {
          const meta = ringBadge[a.tier as GoldTier];
          const localIcon = TIERED_LOCAL_ICONS[a.kind as TieredAchievementKind];
          if (localIcon) {
            return <TierFramedIcon key={a.kind} icon={localIcon} tier={a.tier} label={meta.label} size={size} />;
          }
          return <BadgePlaceholder key={a.kind} tier={a.tier} label={meta.label} size={size} round />;
        }
        const badge = ACHIEVEMENT_BADGES[a.kind as AchievementKind];
        if (!badge) return null;
        const label = a.kind === "character_created" && createdLabel ? `Created ${createdLabel}` : badge.label;
        const flatLocalIcon = FLAT_LOCAL_ICONS[a.kind as AchievementKind];
        if (flatLocalIcon) {
          return <GameIcon key={a.kind} src={localBadgeIconSrc(flatLocalIcon)} label={label} size={size} round />;
        }
        return <BadgePlaceholder key={a.kind} label={label} size={size} round />;
      })}
    </div>
  );
}

// The detail drawer that opens beneath a player's row of character chips
// when one is clicked - this is where all the "stuff that used to make the
// card balloon to 220px" (achievements, professions, gold, etc.) now lives,
// instead of being crammed into the grid itself.
function CharacterDetail({ c }: { c: CardCharacter }) {
  const professions = (c.character_professions ?? []).slice().sort((a, b) => b.skill - a.skill);
  const gold = formatGold(c.money_copper);

  return (
    <div className="rounded-lg border border-neutral-700 bg-neutral-900/60 p-4">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <div className="flex items-center gap-2">
            <span className="text-lg font-bold uppercase tracking-wide text-white">{c.name}</span>
            {isMain(c) && (
              <span className="rounded bg-amber-500/20 px-2 py-0.5 text-xs font-bold text-amber-300 ring-1 ring-amber-500/50">
                MAIN
              </span>
            )}
          </div>
          <p className="text-sm text-gray-400">
            Level {c.level} {c.class}
          </p>
        </div>
        <Link
          href={`/character/${c.id}`}
          className="rounded border border-amber-700/60 px-3 py-1.5 text-sm font-semibold text-amber-300 hover:bg-amber-500/10"
        >
          View Full Character →
        </Link>
      </div>

      <div className="mt-3 flex items-center gap-3">
        <GameIcon name={classIcon(c.class)} label={c.class} size={56} round />
        <p className="text-sm text-gray-400">
          {c.race} · {c.character_type}
          {c.guild && <> · {`<${c.guild}>`}</>}
        </p>
      </div>

      <div className="mt-4">
        <p className="mb-1.5 text-xs font-bold uppercase tracking-wide text-gray-500">Achievements</p>
        <AchievementRow c={c} />
      </div>

      <div className="mt-4 grid grid-cols-2 gap-3 border-t border-neutral-700 pt-3 text-sm sm:grid-cols-4">
        <div>
          <p className="text-xs uppercase tracking-wide text-gray-500">Spec</p>
          <p className="font-semibold text-gray-200">{c.main_spec || "—"}</p>
        </div>
        <div>
          <p className="text-xs uppercase tracking-wide text-gray-500">Professions</p>
          {professions.length > 0 ? (
            professions.map((p) => (
              <p key={p.profession} className="font-semibold text-gray-200">
                {p.profession} <span className="text-gray-400">{p.skill}</span>
              </p>
            ))
          ) : (
            <p className="text-gray-500">—</p>
          )}
        </div>
        <div>
          <p className="text-xs uppercase tracking-wide text-gray-500">PvP Rank</p>
          <p className="font-semibold text-gray-200">{c.pvp_rank ? c.pvp_rank : "—"}</p>
        </div>
        <div>
          <p className="text-xs uppercase tracking-wide text-gray-500">Gold</p>
          <p className="font-semibold text-gray-200">{gold ?? "—"}</p>
        </div>
      </div>
    </div>
  );
}

// One mini character chip inside a player's row. Mains render larger and
// with a gold-tinted border - everything else stays a plain dark/grey
// border, so gold reads as "this one's important" instead of "everything
// on this page has a gold border."
function CharacterChip({
  c,
  active,
  onClick,
}: {
  c: CardCharacter;
  active: boolean;
  onClick: () => void;
}) {
  const main = isMain(c);
  return (
    <button
      type="button"
      onClick={onClick}
      className={`flex shrink-0 items-center gap-2 rounded-lg border text-left transition-colors ${
        main ? "px-3 py-2" : "px-2 py-1.5"
      } ${
        active
          ? "border-amber-500 bg-amber-500/10"
          : main
            ? "border-amber-700/50 bg-neutral-800 hover:border-amber-600"
            : "border-neutral-700 bg-neutral-800 hover:border-neutral-500"
      }`}
    >
      <GameIcon name={classIcon(c.class)} label={c.class} size={main ? 40 : 28} round />
      <span className="min-w-0">
        <span className="flex items-center gap-1.5">
          <span className={`truncate font-semibold ${main ? "text-white" : "text-gray-200"}`}>{c.name}</span>
          {main && (
            <span className="shrink-0 rounded bg-amber-500/20 px-1.5 py-0.5 text-[10px] font-bold text-amber-300">
              MAIN
            </span>
          )}
        </span>
        <span className="block text-xs text-gray-400">
          Lv {c.level} {c.class}
        </span>
      </span>
    </button>
  );
}

// One player's whole section in the main view - their name/count header,
// the row of character chips, and (if one's selected) the detail drawer
// underneath. Replaces the old approach of listing every character as its
// own independent grid card: rows now line up because every player's
// section is exactly as tall as its own content, not at the mercy of
// whichever card elsewhere in the grid happens to be expanded.
function PlayerSection({
  player,
  showOwnerHeader,
  expandedCharId,
  onToggleChar,
}: {
  player: FriendPlayer;
  showOwnerHeader: boolean;
  expandedCharId: string | null;
  onToggleChar: (id: string) => void;
}) {
  const ordered = player.characters
    .slice()
    .sort((a, b) => (isMain(b) ? 1 : 0) - (isMain(a) ? 1 : 0) || b.level - a.level);
  const expandedChar = ordered.find((c) => c.id === expandedCharId) ?? null;

  return (
    <div className="rounded-lg border border-neutral-700 bg-neutral-800/60 p-3">
      {showOwnerHeader && (
        <div className="mb-2 flex items-baseline justify-between">
          <h3 className="font-bold text-white">{player.name}</h3>
          <span className="text-xs text-gray-400">
            {player.characters.length} {player.characters.length === 1 ? "character" : "characters"}
          </span>
        </div>
      )}

      <div className="flex flex-wrap gap-2">
        {ordered.map((c) => (
          <CharacterChip key={c.id} c={c} active={expandedCharId === c.id} onClick={() => onToggleChar(c.id)} />
        ))}
      </div>

      {expandedChar && (
        <div className="mt-3">
          <CharacterDetail c={expandedChar} />
        </div>
      )}
    </div>
  );
}

export default function FriendsBrowser({
  players,
  treeNames: _treeNames,
  specIcons: _specIcons,
}: {
  players: FriendPlayer[];
  treeNames: Record<string, string[]>;
  specIcons: Record<string, string>;
}) {
  const [selected, setSelected] = useState("all");
  const [expandedCharId, setExpandedCharId] = useState<string | null>(null);
  const [sortBy, setSortBy] = useState<SortMode>("player");
  const [filterBy, setFilterBy] = useState<FilterMode>("all");
  const [search, setSearch] = useState("");

  const allCharacters = players.flatMap((p) => p.characters);
  const totalMains = allCharacters.filter(isMain).length;
  const totalAlts = allCharacters.length - totalMains;

  const current = players.find((p) => p.id === selected) ?? null;
  const basePlayers = current ? [current] : players;

  function toggleChar(id: string) {
    setExpandedCharId((prev) => (prev === id ? null : id));
  }

  const visiblePlayers = useMemo(() => {
    const q = search.trim().toLowerCase();
    const filtered = basePlayers
      .map((p) => ({
        ...p,
        characters: p.characters.filter((c) => {
          if (filterBy === "main" && !isMain(c)) return false;
          if (filterBy === "alt" && isMain(c)) return false;
          if (q && !c.name.toLowerCase().includes(q)) return false;
          return true;
        }),
      }))
      .filter((p) => p.characters.length > 0);

    const sorted = filtered.slice().sort((a, b) => {
      if (sortBy === "level") {
        const aMax = Math.max(...a.characters.map((c) => c.level));
        const bMax = Math.max(...b.characters.map((c) => c.level));
        return bMax - aMax;
      }
      if (sortBy === "achievements") {
        const aTotal = a.characters.reduce((sum, c) => sum + achievementCount(c), 0);
        const bTotal = b.characters.reduce((sum, c) => sum + achievementCount(c), 0);
        return bTotal - aTotal;
      }
      return a.name.localeCompare(b.name);
    });

    return sorted;
  }, [basePlayers, filterBy, search, sortBy]);

  const visibleCount = visiblePlayers.reduce((sum, p) => sum + p.characters.length, 0);

  return (
    <div className="mt-6 flex flex-col gap-4">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start">
        {/* The list of friends. It never moves, only what's on the right changes. */}
        <aside className="lg:sticky lg:top-4 lg:w-72 lg:shrink-0">
          <div className="flex gap-2 overflow-x-auto pb-1 lg:max-h-[calc(100vh-2rem)] lg:flex-col lg:overflow-y-auto lg:overflow-x-visible">
            <button
              type="button"
              onClick={() => setSelected("all")}
              aria-pressed={selected === "all"}
              className={`friend-tab ${selected === "all" ? "friend-tab-active" : ""}`}
            >
              <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full border border-amber-900/70 bg-neutral-900 text-amber-200">
                <svg
                  viewBox="0 0 24 24"
                  width="18"
                  height="18"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  aria-hidden="true"
                >
                  <circle cx="9" cy="8" r="3.5" />
                  <path d="M2.5 20a6.5 6.5 0 0 1 13 0" />
                  <circle cx="17.5" cy="9" r="2.5" />
                  <path d="M17 14.5a5 5 0 0 1 4.5 5" />
                </svg>
              </span>
              <span className="min-w-0 flex-1">
                <span className="block truncate font-bold">Everyone</span>
                <span className="sub block truncate text-xs text-gray-400">
                  {allCharacters.length} characters · {players.length}{" "}
                  {players.length === 1 ? "player" : "players"}
                </span>
              </span>
            </button>

            {players.map((p) => {
              const active = selected === p.id;
              const highest = Math.max(...p.characters.map((c) => c.level));
              return (
                <button
                  key={p.id}
                  type="button"
                  onClick={() => setSelected(p.id)}
                  aria-pressed={active}
                  className={`friend-tab ${active ? "friend-tab-active" : ""}`}
                  style={{ alignItems: "flex-start" }}
                >
                  <span className="flex shrink-0 -space-x-3 pt-0.5">
                    {p.characters.slice(0, 3).map((c) => (
                      <GameIcon key={c.id} name={classIcon(c.class)} label={c.class} size={32} round />
                    ))}
                  </span>
                  <span className="min-w-0 flex-1 text-left">
                    <span className="block truncate font-bold">{p.name}</span>
                    <span className="sub mt-1 block truncate text-xs text-gray-400">
                      {p.characters.length} {p.characters.length === 1 ? "character" : "characters"} · highest
                      level {highest}
                    </span>
                  </span>
                </button>
              );
            })}
          </div>
        </aside>

        <section className="min-w-0 flex-1">
          <div className="mb-3 flex flex-wrap items-baseline gap-x-3">
            <h2 className="text-xl font-bold">{current ? current.name : "Everyone"}</h2>
            <p className="text-sm text-gray-400">
              {visibleCount} {visibleCount === 1 ? "character" : "characters"}
            </p>
          </div>

          {!current && (
            <p className="mb-3 text-sm text-gray-400">
              {allCharacters.length} Characters · {players.length} Players · {totalMains} Mains · {totalAlts} Alts
            </p>
          )}

          <div className="mb-4 flex flex-wrap items-center gap-3">
            <div className="flex items-center gap-1.5 text-sm">
              <span className="text-gray-500">Sort by</span>
              {(
                [
                  ["player", "Player"],
                  ["level", "Level"],
                  ["achievements", "Achievements"],
                ] as [SortMode, string][]
              ).map(([mode, label]) => (
                <button
                  key={mode}
                  type="button"
                  onClick={() => setSortBy(mode)}
                  className={`rounded px-2 py-1 text-xs font-semibold ${
                    sortBy === mode ? "bg-amber-500/20 text-amber-300 ring-1 ring-amber-500/50" : "text-gray-400 hover:text-white"
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>

            <div className="flex items-center gap-1.5 text-sm">
              <span className="text-gray-500">Filter</span>
              {(
                [
                  ["all", "All"],
                  ["main", "Mains"],
                  ["alt", "Alts"],
                ] as [FilterMode, string][]
              ).map(([mode, label]) => (
                <button
                  key={mode}
                  type="button"
                  onClick={() => setFilterBy(mode)}
                  className={`rounded px-2 py-1 text-xs font-semibold ${
                    filterBy === mode ? "bg-amber-500/20 text-amber-300 ring-1 ring-amber-500/50" : "text-gray-400 hover:text-white"
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>

            <input
              type="search"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search characters..."
              className="ml-auto min-w-0 rounded border border-neutral-700 bg-neutral-900 px-2 py-1 text-sm text-gray-200 placeholder:text-gray-500 focus:border-amber-600 focus:outline-none"
            />
          </div>

          <div className="flex flex-col gap-3">
            {visiblePlayers.length === 0 && (
              <p className="text-sm text-gray-500">No characters match that filter.</p>
            )}
            {visiblePlayers.map((p) => (
              <PlayerSection
                key={p.id}
                player={p}
                showOwnerHeader={!current}
                expandedCharId={expandedCharId}
                onToggleChar={toggleChar}
              />
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}
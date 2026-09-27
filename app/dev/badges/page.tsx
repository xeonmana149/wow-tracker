"use client";

// A dev-only page for forcing badges onto your own characters so you can
// see how they look without actually grinding to max level, 25,000 gold,
// etc. Only ever touches the achievements table directly - it doesn't fake
// any of the underlying game data (level, gold, professions), so this is
// purely a "what does the badge look like" tool, not a way to cheat your
// actual tracked progress.
//
// Nothing links to this page from the main nav on purpose - it's meant to
// be visited directly at /dev/badges. Anyone logged in can use it, but only
// ever on their own characters (RLS on the achievements table makes sure
// of that).
//
// 2026-09-25: generalized to the 4-tier (Copper/Silver/Gold/Platinum)
// system and every tiered achievement (not just gold/epic_gear) - one
// section per TIERED_ACHIEVEMENT_KINDS entry instead of two hand-written
// blocks, so a future new tiered badge doesn't need this page touched too.
//
// 2026-09-25: dropped the account-wide achievements section (may come back
// later) and the per-icon "customize icons" editor - badges with local art
// now get that art straight from lib/badgeFrames.ts's icon-slug files, and
// the WoW-icon-name override system it replaced isn't used any more.
//
// 2026-09-25: added a Statistics section below the badge forcer. The
// section above force-sets the `achievements` table directly, which is
// great for "what does this badge look like" but never touches
// character_statistics, so it can't test the REAL pipeline (computeCounter
// -> awardTier/awardAchievement -> activity_events) that a live sync
// actually runs. This section instead writes fake character_statistics
// rows for whichever raw stat feeds each achievement, then runs the exact
// same award functions importLogic.ts calls on every sync - so you can
// confirm a tier upgrade fires, points update, and the activity feed/
// sidebar pick it up, without grinding the real stat in-game.

import { useEffect, useState } from "react";
import { supabase } from "../../../lib/supabase";
import { localBadgeIconSrc } from "../../../lib/badgeFrames";
import GameIcon from "../../GameIcon";
import TierFramedIcon from "../../TierFramedIcon";
import BadgePlaceholder from "../../BadgePlaceholder";
import {
  ACHIEVEMENT_BADGES,
  TIERED_LOCAL_ICONS,
  FLAT_LOCAL_ICONS,
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
  type AchievementKind,
  type GoldTier as AchievementTier,
} from "../../CharacterCard";
import {
  TIERED_ACHIEVEMENT_KINDS,
  PERSONALITY_BADGES,
  TIER_COUNTERS,
  ACHIEVEMENT_MESSAGE,
  tierLabel,
  tierThresholds,
  tierMessage,
  computeCounter,
  awardTier,
  awardAchievement,
  type TieredAchievementKind,
} from "../../../lib/achievements";

type Character = { id: string; name: string; class: string };

// Plain yes/no achievements (everything except the tiered ones, which get
// their own generic tier-picker section below).
const PLAIN_KINDS = Object.keys(ACHIEVEMENT_BADGES) as AchievementKind[];
const TIERS: AchievementTier[] = ["Copper", "Silver", "Gold", "Platinum"];

// The epic_gear tier is derived from a running `progress` count in the real
// system - when forcing a tier here for testing, this just sets progress
// to a value guaranteed to land on that tier so nothing looks inconsistent
// if you ever look at the raw row. No other tiered kind uses `progress`.
const EPIC_TIER_PROGRESS: Record<AchievementTier, number> = {
  Copper: 1,
  Silver: 3,
  Gold: 5,
  Platinum: 10,
};

// Label lookup for every tiered badge, keyed the same way CharacterCard's
// own RING_TIER_BADGES map is (that map isn't exported, so this page keeps
// a copy built from the same exported pieces) - used for the button title
// and the fallback (non-local-icon) badges' tooltip text. "gold" isn't
// here since it has its own GOLD_TIER_LABEL, not a full icon/ring set.
const TIER_BADGE_SETS: Partial<Record<TieredAchievementKind, Record<AchievementTier, { icon: string; ring?: string; label: string }>>> = {
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

function labelFor(kind: TieredAchievementKind, tier: AchievementTier): string {
  if (kind === "gold") return GOLD_TIER_LABEL[tier];
  return TIER_BADGE_SETS[kind]?.[tier].label ?? tierLabel(kind);
}

// --- Statistics section -----------------------------------------------
// "recipes" is computed from character_professions, not
// character_statistics (see TIER_COUNTERS.recipes = []) - there's no stat
// to fake for it, so it's excluded here. Use the badge-forcer section
// above to test it instead.
// Explicitly typed (rather than left to inference) because TypeScript's
// filter-predicate narrowing would otherwise infer this as "every tiered
// kind except recipes" specifically, which then rejects passing a plain
// TieredAchievementKind (which still includes "recipes" as a possibility)
// into .indexOf() below.
const STAT_TESTABLE_KINDS: TieredAchievementKind[] = TIERED_ACHIEVEMENT_KINDS.filter(
  (k) => k !== "recipes" && k !== "master_chef" && k !== "addicted"
);

type StatRow = { category: string; name: string; value: string };

// Which single {category, name} this dev tool writes to for a given kind.
// Most tiered kinds sum several real stats together (e.g. consumables adds
// up 8 different counters) - rather than needing all of them filled in to
// hit a threshold, this just points at the FIRST one, so setting a value
// here sets the achievement's whole counter by itself (the others stay at
// 0 unless you've also synced real data for them). boss_kills is the one
// kind that sums an entire CATEGORY rather than named stats, so it gets a
// dedicated synthetic stat name under that category instead.
function primaryStatTarget(kind: TieredAchievementKind): { category: string; name: string } {
  const selectors = TIER_COUNTERS[kind];
  const first = selectors[0];
  if (!first) return { category: "Dev Test", name: `${kind} (dev)` };
  if ("categoryOnly" in first) return { category: first.categoryOnly, name: "Dev test value" };
  return { category: first.category, name: first.name };
}

// Fixed, negative stat_ids reserved for this dev tool - real Blizzard
// stat IDs (from GetStatistic()) are always positive, so these can never
// collide with a real synced row, and staying fixed per kind/badge means
// re-setting a value updates the same row instead of piling up duplicates.
function tierStatId(kind: TieredAchievementKind): number {
  return -9000 - STAT_TESTABLE_KINDS.indexOf(kind);
}
function personalityStatId(kind: AchievementKind): number {
  return -8000 - PERSONALITY_BADGES.findIndex((b) => b.kind === kind);
}
const ALL_DEV_STAT_IDS = [
  ...STAT_TESTABLE_KINDS.map(tierStatId),
  ...PERSONALITY_BADGES.map((b) => personalityStatId(b.kind)),
];

export default function BadgeTesterPage() {
  const [characters, setCharacters] = useState<Character[]>([]);
  const [selectedCharacter, setSelectedCharacter] = useState("");
  const [earnedPlain, setEarnedPlain] = useState<Set<AchievementKind>>(new Set());
  const [tiers, setTiers] = useState<Partial<Record<TieredAchievementKind, AchievementTier>>>({});
  const [status, setStatus] = useState("Loading...");
  const [busy, setBusy] = useState(false);

  // Statistics section state - statRows is the character's real
  // character_statistics rows (including whatever this tool has written),
  // used to compute each achievement's live counter the same way the
  // leaderboards page and importLogic.ts do. statInputs/personalityInputs
  // hold the text box contents before you hit Set.
  const [statRows, setStatRows] = useState<StatRow[]>([]);
  const [statInputs, setStatInputs] = useState<Partial<Record<TieredAchievementKind, string>>>({});
  const [personalityInputs, setPersonalityInputs] = useState<Partial<Record<AchievementKind, string>>>({});
  const [checkStatus, setCheckStatus] = useState("");

  async function loadCharacterBadges(characterId: string) {
    const { data } = await supabase
      .from("achievements")
      .select("kind, tier")
      .eq("character_id", characterId);
    const plain = new Set<AchievementKind>();
    const nextTiers: Partial<Record<TieredAchievementKind, AchievementTier>> = {};
    for (const row of data ?? []) {
      if ((TIERED_ACHIEVEMENT_KINDS as string[]).includes(row.kind)) {
        if (row.tier) nextTiers[row.kind as TieredAchievementKind] = row.tier as AchievementTier;
      } else {
        plain.add(row.kind as AchievementKind);
      }
    }
    setEarnedPlain(plain);
    setTiers(nextTiers);
  }

  async function loadStats(characterId: string) {
    const { data } = await supabase
      .from("character_statistics")
      .select("category, name, value")
      .eq("character_id", characterId);
    setStatRows((data ?? []) as StatRow[]);
  }

  useEffect(() => {
    async function init() {
      const { data: userData } = await supabase.auth.getUser();
      if (!userData.user) {
        setStatus("You need to be logged in to use this page.");
        return;
      }

      const { data: chars } = await supabase
        .from("characters")
        .select("id, name, class")
        .eq("user_id", userData.user.id)
        .order("name");
      setCharacters(chars ?? []);
      if (chars && chars.length > 0) {
        setSelectedCharacter(chars[0].id);
        await Promise.all([loadCharacterBadges(chars[0].id), loadStats(chars[0].id)]);
      }
      setStatus("");
    }
    init();
  }, []);

  async function selectCharacter(id: string) {
    setSelectedCharacter(id);
    setCheckStatus("");
    await Promise.all([loadCharacterBadges(id), loadStats(id)]);
  }

  async function togglePlain(kind: AchievementKind) {
    if (!selectedCharacter) return;
    setBusy(true);
    if (earnedPlain.has(kind)) {
      await supabase.from("achievements").delete().eq("character_id", selectedCharacter).eq("kind", kind);
    } else {
      await supabase
        .from("achievements")
        .upsert({ character_id: selectedCharacter, kind }, { onConflict: "character_id,kind" });
    }
    await loadCharacterBadges(selectedCharacter);
    setBusy(false);
  }

  async function setTier(kind: TieredAchievementKind, tier: AchievementTier | null) {
    if (!selectedCharacter) return;
    setBusy(true);
    if (tier === null) {
      await supabase.from("achievements").delete().eq("character_id", selectedCharacter).eq("kind", kind);
    } else {
      await supabase.from("achievements").upsert(
        {
          character_id: selectedCharacter,
          kind,
          tier,
          ...(kind === "epic_gear" ? { progress: EPIC_TIER_PROGRESS[tier] } : {}),
        },
        { onConflict: "character_id,kind" }
      );
    }
    await loadCharacterBadges(selectedCharacter);
    setBusy(false);
  }

  async function clearCharacterBadges() {
    if (!selectedCharacter) return;
    setBusy(true);
    await supabase.from("achievements").delete().eq("character_id", selectedCharacter);
    await loadCharacterBadges(selectedCharacter);
    setBusy(false);
  }

  // Writes one fake stat value that feeds a tiered achievement's counter.
  // For every kind except boss_kills, this also clears out any OTHER row
  // under the same {category, name} first - otherwise a character that's
  // already been synced for real would end up with two rows for the same
  // stat (this tool's and the real one), and computeCounter would just
  // pick whichever one the query happens to return first. boss_kills sums
  // an entire category of per-boss stats together, so a dev row there adds
  // on top of any real boss kills already on file instead of replacing
  // them - same as how two different real bosses would combine.
  async function setTierStat(kind: TieredAchievementKind, rawValue: string) {
    if (!selectedCharacter) return;
    const n = Number(rawValue);
    if (!Number.isFinite(n) || n < 0) return;
    setBusy(true);
    setCheckStatus("");

    const { data: userData } = await supabase.auth.getUser();
    const userId = userData.user?.id;
    if (!userId) {
      setBusy(false);
      return;
    }

    const target = primaryStatTarget(kind);
    const selectors = TIER_COUNTERS[kind];
    const isCategoryOnly = selectors.length > 0 && "categoryOnly" in selectors[0];
    if (!isCategoryOnly) {
      await supabase
        .from("character_statistics")
        .delete()
        .eq("character_id", selectedCharacter)
        .eq("category", target.category)
        .eq("name", target.name)
        .neq("stat_id", tierStatId(kind));
    }

    await supabase.from("character_statistics").upsert(
      {
        character_id: selectedCharacter,
        user_id: userId,
        stat_id: tierStatId(kind),
        category: target.category,
        name: target.name,
        value: String(Math.round(n)),
        updated_at: new Date().toISOString(),
      },
      { onConflict: "character_id,stat_id" }
    );

    await loadStats(selectedCharacter);
    setBusy(false);
  }

  // Same idea for the one-off personality/feat badges - each reads a
  // single named stat directly (no summing), so no delete-first dance is
  // needed beyond the usual "same stat_id upserts in place" behavior.
  async function setPersonalityStat(kind: AchievementKind, rawValue: string) {
    if (!selectedCharacter) return;
    const n = Number(rawValue);
    if (!Number.isFinite(n) || n < 0) return;
    const badge = PERSONALITY_BADGES.find((b) => b.kind === kind);
    if (!badge) return;
    setBusy(true);
    setCheckStatus("");

    const { data: userData } = await supabase.auth.getUser();
    const userId = userData.user?.id;
    if (!userId) {
      setBusy(false);
      return;
    }

    await supabase
      .from("character_statistics")
      .delete()
      .eq("character_id", selectedCharacter)
      .eq("category", badge.category)
      .eq("name", badge.name)
      .neq("stat_id", personalityStatId(kind));

    await supabase.from("character_statistics").upsert(
      {
        character_id: selectedCharacter,
        user_id: userId,
        stat_id: personalityStatId(kind),
        category: badge.category,
        name: badge.name,
        value: String(Math.round(n)),
        updated_at: new Date().toISOString(),
      },
      { onConflict: "character_id,stat_id" }
    );

    await loadStats(selectedCharacter);
    setBusy(false);
  }

  // Runs the EXACT same award logic importLogic.ts runs on every real sync
  // (awardTier/awardAchievement off computeCounter over the current stat
  // rows), then logs the same activity_events row a real sync would - so a
  // tier upgrade here shows up in Recent Activity and the floating
  // Activity sidebar exactly like the real thing, letting you test the
  // whole pipeline instead of just the badge art.
  async function runAchievementCheck() {
    if (!selectedCharacter) return;
    setBusy(true);
    setCheckStatus("Checking...");

    const { data: userData } = await supabase.auth.getUser();
    const userId = userData.user?.id;
    const character = characters.find((c) => c.id === selectedCharacter);
    if (!userId || !character) {
      setCheckStatus("Could not identify the logged-in user.");
      setBusy(false);
      return;
    }

    const earnedMessages: string[] = [];

    for (const kind of STAT_TESTABLE_KINDS) {
      const value = computeCounter(kind, statRows);
      if (value <= 0) continue;
      const tier = await awardTier(supabase, selectedCharacter, kind, value);
      if (tier) {
        const message = tierMessage(kind, character.name, tier);
        earnedMessages.push(message);
        await supabase.from("activity_events").insert({
          character_id: selectedCharacter,
          user_id: userId,
          kind: "achievement_earned",
          achievement_kind: kind,
          achievement_tier: tier,
          message,
        });
      }
    }

    for (const badge of PERSONALITY_BADGES) {
      const row = statRows.find((s) => s.category === badge.category && s.name === badge.name);
      if (!row) continue;
      const n = Number(row.value.replace(/,/g, ""));
      if (!Number.isFinite(n) || n < badge.threshold) continue;
      const earned = await awardAchievement(supabase, selectedCharacter, badge.kind);
      if (earned) {
        const message = ACHIEVEMENT_MESSAGE[badge.kind](character.name);
        earnedMessages.push(message);
        await supabase.from("activity_events").insert({
          character_id: selectedCharacter,
          user_id: userId,
          kind: "achievement_earned",
          achievement_kind: badge.kind,
          achievement_tier: null,
          message,
        });
      }
    }

    await loadCharacterBadges(selectedCharacter);
    setCheckStatus(
      earnedMessages.length > 0
        ? `Earned: ${earnedMessages.join(" · ")}`
        : "No new tiers or badges at the current stat values - already earned, or not high enough yet."
    );
    setBusy(false);
  }

  // Removes only the synthetic rows THIS tool wrote (the fixed negative
  // stat_ids), leaving any real synced stats on the character untouched.
  async function clearDevStats() {
    if (!selectedCharacter) return;
    setBusy(true);
    await supabase
      .from("character_statistics")
      .delete()
      .eq("character_id", selectedCharacter)
      .in("stat_id", ALL_DEV_STAT_IDS);
    await loadStats(selectedCharacter);
    setCheckStatus("");
    setBusy(false);
  }

  if (status) {
    return <main className="mx-auto max-w-3xl p-6 text-white">{status}</main>;
  }

  return (
    <main className="mx-auto max-w-3xl p-4 text-white md:p-6">
      <h1 className="text-3xl font-bold">Badge Tester</h1>
      <p className="mt-2 text-sm text-gray-400">
        Dev-only page for forcing badges on/off so you can see how they render. This only writes
        to the achievements table - it never touches level, gold, professions or anything else, so
        nothing here affects your actual tracked progress.
      </p>

      {characters.length === 0 ? (
        <p className="mt-6 text-gray-400">You have no characters yet - create one first.</p>
      ) : (
        <>
          <section className="mt-6 rounded-lg border border-neutral-700 bg-neutral-900/40 p-4">
            <label className="block text-sm font-semibold uppercase tracking-wide text-gray-400">
              Character
            </label>
            <select
              value={selectedCharacter}
              onChange={(e) => selectCharacter(e.target.value)}
              className="mt-2 w-full rounded bg-white p-2 text-black"
            >
              {characters.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name} ({c.class})
                </option>
              ))}
            </select>

            <h2 className="mt-5 text-sm font-semibold uppercase tracking-wide text-gray-400">
              Achievements
            </h2>
            <div className="mt-2 flex flex-wrap gap-2">
              {PLAIN_KINDS.map((kind) => {
                const badge = ACHIEVEMENT_BADGES[kind];
                const on = earnedPlain.has(kind);
                const localIcon = FLAT_LOCAL_ICONS[kind];
                return (
                  <button
                    key={kind}
                    disabled={busy}
                    onClick={() => togglePlain(kind)}
                    title={badge.label}
                    className={`flex items-center gap-1.5 rounded-full py-1.5 pl-1.5 pr-3 text-sm disabled:opacity-50 ${
                      on ? "bg-amber-500 text-neutral-950" : "bg-neutral-800 text-gray-300"
                    }`}
                  >
                    {localIcon ? (
                      <GameIcon src={localBadgeIconSrc(localIcon)} label={badge.label} size={32} round />
                    ) : (
                      <BadgePlaceholder label={badge.label} size={32} round />
                    )}
                    {kind}
                  </button>
                );
              })}
            </div>

            {TIERED_ACHIEVEMENT_KINDS.map((kind) => {
              const current = tiers[kind] ?? null;
              const localIcon = TIERED_LOCAL_ICONS[kind];
              return (
                <div key={kind}>
                  <h3 className="mt-4 text-xs font-semibold uppercase tracking-wide text-gray-500">
                    {tierLabel(kind)}
                  </h3>
                  <div className="mt-2 flex flex-wrap gap-2">
                    <button
                      disabled={busy}
                      onClick={() => setTier(kind, null)}
                      className={`rounded-full px-3 py-1.5 text-sm disabled:opacity-50 ${
                        current === null ? "bg-amber-500 text-neutral-950" : "bg-neutral-800 text-gray-300"
                      }`}
                    >
                      None
                    </button>
                    {TIERS.map((tier) => {
                      const label = labelFor(kind, tier);
                      return (
                        <button
                          key={tier}
                          disabled={busy}
                          onClick={() => setTier(kind, tier)}
                          title={label}
                          className={`flex items-center gap-1.5 rounded-full py-1.5 pl-1.5 pr-3 text-sm disabled:opacity-50 ${
                            current === tier ? "bg-amber-500 text-neutral-950" : "bg-neutral-800 text-gray-300"
                          }`}
                        >
                          {localIcon ? (
                            <TierFramedIcon icon={localIcon} tier={tier} label={label} size={32} />
                          ) : (
                            <BadgePlaceholder tier={tier} label={label} size={32} round />
                          )}
                          {tier}
                        </button>
                      );
                    })}
                  </div>
                </div>
              );
            })}

            <button
              disabled={busy}
              onClick={clearCharacterBadges}
              className="mt-4 rounded bg-neutral-700 px-3 py-1.5 text-sm text-white disabled:opacity-50"
            >
              Clear all badges on this character
            </button>
          </section>

          <section className="mt-6 rounded-lg border border-neutral-700 bg-neutral-900/40 p-4">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
              Statistics (test the real pipeline)
            </h2>
            <p className="mt-1 text-xs text-gray-500">
              The section above forces badges directly and never touches real progress. This one
              instead fakes the underlying character_statistics counter each achievement reads,
              then runs the actual award logic a real sync uses - so you can confirm a tier
              upgrade, its points, and the activity feed all fire correctly. Setting a stat here
              overwrites whatever real value that stat currently has on this character, so use a
              test character, not one you're tracking for real.
            </p>

            <h3 className="mt-4 text-xs font-semibold uppercase tracking-wide text-gray-500">
              Tiered achievement counters
            </h3>
            <div className="mt-2 flex flex-col gap-2">
              {STAT_TESTABLE_KINDS.map((kind) => {
                const localIcon = TIERED_LOCAL_ICONS[kind];
                const currentTier = tiers[kind] ?? null;
                const liveValue = computeCounter(kind, statRows);
                const thresholds = tierThresholds(kind);
                return (
                  <div
                    key={kind}
                    className="flex flex-wrap items-center gap-3 rounded border border-neutral-800 bg-neutral-900/60 px-3 py-2"
                  >
                    {localIcon ? (
                      <TierFramedIcon icon={localIcon} tier={currentTier ?? "Copper"} label={tierLabel(kind)} size={32} />
                    ) : (
                      <BadgePlaceholder tier={currentTier} label={tierLabel(kind)} size={32} round />
                    )}
                    <div className="min-w-[160px]">
                      <div className="text-sm font-semibold text-white">{tierLabel(kind)}</div>
                      <div className="text-[11px] text-gray-500">
                        Current: {liveValue.toLocaleString()} · Tier on file: {currentTier ?? "None"}
                      </div>
                      <div className="text-[11px] text-gray-600">
                        {thresholds.map((t) => `${t.tier} ${t.value.toLocaleString()}`).join(" · ")}
                      </div>
                    </div>
                    <input
                      type="number"
                      min={0}
                      disabled={busy}
                      value={statInputs[kind] ?? ""}
                      onChange={(e) => setStatInputs((prev) => ({ ...prev, [kind]: e.target.value }))}
                      placeholder={String(liveValue)}
                      className="ml-auto w-28 rounded border border-neutral-700 bg-neutral-900 px-2 py-1 text-sm text-gray-200"
                    />
                    <button
                      type="button"
                      disabled={busy || !statInputs[kind]}
                      onClick={() => setTierStat(kind, statInputs[kind] ?? "")}
                      className="rounded bg-neutral-700 px-3 py-1.5 text-sm text-white disabled:opacity-50"
                    >
                      Set
                    </button>
                  </div>
                );
              })}
            </div>

            <h3 className="mt-5 text-xs font-semibold uppercase tracking-wide text-gray-500">
              Personality &amp; feat badge stats
            </h3>
            <div className="mt-2 flex flex-col gap-2">
              {PERSONALITY_BADGES.map((badge) => {
                const badgeInfo = ACHIEVEMENT_BADGES[badge.kind];
                const localIcon = FLAT_LOCAL_ICONS[badge.kind];
                const on = earnedPlain.has(badge.kind);
                const row = statRows.find((s) => s.category === badge.category && s.name === badge.name);
                const liveValue = row ? Number(row.value.replace(/,/g, "")) || 0 : 0;
                return (
                  <div
                    key={badge.kind}
                    className="flex flex-wrap items-center gap-3 rounded border border-neutral-800 bg-neutral-900/60 px-3 py-2"
                  >
                    {localIcon ? (
                      <GameIcon src={localBadgeIconSrc(localIcon)} label={badgeInfo.label} size={32} round />
                    ) : (
                      <BadgePlaceholder label={badgeInfo.label} size={32} round />
                    )}
                    <div className="min-w-[160px]">
                      <div className="text-sm font-semibold text-white">{badgeInfo.label}</div>
                      <div className="text-[11px] text-gray-500">
                        Current: {liveValue.toLocaleString()} / {badge.threshold.toLocaleString()} ·{" "}
                        {on ? "Earned" : "Not earned"}
                      </div>
                    </div>
                    <input
                      type="number"
                      min={0}
                      disabled={busy}
                      value={personalityInputs[badge.kind] ?? ""}
                      onChange={(e) =>
                        setPersonalityInputs((prev) => ({ ...prev, [badge.kind]: e.target.value }))
                      }
                      placeholder={String(liveValue)}
                      className="ml-auto w-28 rounded border border-neutral-700 bg-neutral-900 px-2 py-1 text-sm text-gray-200"
                    />
                    <button
                      type="button"
                      disabled={busy || !personalityInputs[badge.kind]}
                      onClick={() => setPersonalityStat(badge.kind, personalityInputs[badge.kind] ?? "")}
                      className="rounded bg-neutral-700 px-3 py-1.5 text-sm text-white disabled:opacity-50"
                    >
                      Set
                    </button>
                  </div>
                );
              })}
            </div>

            <div className="mt-4 flex flex-wrap items-center gap-3">
              <button
                type="button"
                disabled={busy}
                onClick={runAchievementCheck}
                className="rounded bg-amber-500 px-3 py-1.5 text-sm font-semibold text-neutral-950 disabled:opacity-50"
              >
                Run achievement check
              </button>
              <button
                type="button"
                disabled={busy}
                onClick={clearDevStats}
                className="rounded bg-neutral-700 px-3 py-1.5 text-sm text-white disabled:opacity-50"
              >
                Clear dev test stats
              </button>
              {checkStatus && <span className="text-xs text-gray-400">{checkStatus}</span>}
            </div>
          </section>

          <p className="mt-4 text-xs text-gray-500">
            Go check the character page, Dashboard or Friends page in another tab to see how
            whatever you just toggled actually looks.
          </p>
        </>
      )}
    </main>
  );
}
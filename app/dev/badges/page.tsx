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

import { useEffect, useState } from "react";
import { supabase } from "../../../lib/supabase";
import { wowIconUrl } from "../../../lib/icons";
import { localBadgeIconSrc } from "../../../lib/badgeFrames";
import GameIcon from "../../GameIcon";
import TierFramedIcon from "../../TierFramedIcon";
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
  tierLabel,
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

export default function BadgeTesterPage() {
  const [characters, setCharacters] = useState<Character[]>([]);
  const [selectedCharacter, setSelectedCharacter] = useState("");
  const [earnedPlain, setEarnedPlain] = useState<Set<AchievementKind>>(new Set());
  const [tiers, setTiers] = useState<Partial<Record<TieredAchievementKind, AchievementTier>>>({});
  const [status, setStatus] = useState("Loading...");
  const [busy, setBusy] = useState(false);

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
        await loadCharacterBadges(chars[0].id);
      }
      setStatus("");
    }
    init();
  }, []);

  async function selectCharacter(id: string) {
    setSelectedCharacter(id);
    await loadCharacterBadges(id);
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
                      <GameIcon src={wowIconUrl(badge.icon)} label={badge.label} size={32} round />
                    )}
                    {kind}
                  </button>
                );
              })}
            </div>

            {TIERED_ACHIEVEMENT_KINDS.map((kind) => {
              const current = tiers[kind] ?? null;
              const localIcon = TIERED_LOCAL_ICONS[kind];
              const fallbackSet = kind === "gold" ? null : TIER_BADGE_SETS[kind];
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
                          } ${localIcon ? "" : fallbackSet?.[tier].ring ?? ""}`}
                        >
                          {localIcon ? (
                            <TierFramedIcon icon={localIcon} tier={tier} label={label} size={32} />
                          ) : (
                            <GameIcon
                              src={wowIconUrl(fallbackSet?.[tier].icon ?? "inv_misc_questionmark")}
                              label={label}
                              size={32}
                              round
                            />
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

          <p className="mt-4 text-xs text-gray-500">
            Go check the character page, Dashboard or Friends page in another tab to see how
            whatever you just toggled actually looks.
          </p>
        </>
      )}
    </main>
  );
}
"use client";

// A dev-only page for forcing badges onto your own characters/account so
// you can see how they look without actually grinding to max level, 25,000
// gold, etc. Only ever touches the achievements/account_achievements
// tables directly - it doesn't fake any of the underlying game data
// (level, gold, professions), so this is purely a "what does the badge
// look like" tool, not a way to cheat your actual tracked progress.
//
// Nothing links to this page from the main nav on purpose - it's meant to
// be visited directly at /dev/badges. Anyone logged in can use it, but
// only ever on their own characters/account (RLS on the two tables makes
// characters and profiles readable by everyone, but this page only ever
// writes character_id/user_id values that came from your own query).
//
// 2026-09-25: generalized to the new 4-tier (Copper/Silver/Gold/Platinum)
// system and every tiered achievement (not just gold/epic_gear) - one
// section per TIERED_ACHIEVEMENT_KINDS entry instead of two hand-written
// blocks, so a future new tiered badge doesn't need this page touched too.

import { useEffect, useState } from "react";
import { supabase } from "../../../lib/supabase";
import { wowIconUrl } from "../../../lib/icons";
import GameIcon from "../../GameIcon";
import {
  ACHIEVEMENT_BADGES,
  GOLD_TIER_BADGE,
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
  CREATED_DATE_ICON,
  CREATED_DATE_ICON_KEY,
  type AchievementKind,
  type GoldTier as AchievementTier,
} from "../../CharacterCard";
import {
  TIERED_ACHIEVEMENT_KINDS,
  tierLabel,
  type TieredAchievementKind,
} from "../../../lib/achievements";
import { ACCOUNT_ACHIEVEMENT_BADGES, type AccountAchievementKind } from "../../../lib/accountAchievements";
import {
  loadBadgeIconOverrides,
  resolvedIcon,
  type BadgeIconOverrides,
} from "../../../lib/badgeIconOverrides";

type Character = { id: string; name: string; class: string };

// Plain yes/no achievements (everything except the tiered ones, which get
// their own generic tier-picker section below).
const PLAIN_KINDS = Object.keys(ACHIEVEMENT_BADGES) as AchievementKind[];
const ACCOUNT_KINDS = Object.keys(ACCOUNT_ACHIEVEMENT_BADGES) as AccountAchievementKind[];
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

// Every tiered badge's per-tier icon/ring/label set, keyed the same way
// CharacterCard's own RING_TIER_BADGES map is (that map isn't exported, so
// this page keeps its own copy built from the same exported pieces).
const TIER_BADGE_SETS: Record<TieredAchievementKind, Record<AchievementTier, { icon: string; ring?: string; label: string }>> = {
  gold: GOLD_TIER_BADGE,
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

// Every badge that can have its icon overridden, for the icon-editor
// section below. Keys match what CharacterCard/AccountBadges look up via
// resolvedIcon() - see lib/badgeIconOverrides.ts.
type IconEntry = { key: string; label: string; defaultIcon: string };

function buildIconEntries(): IconEntry[] {
  const entries: IconEntry[] = [];
  for (const kind of PLAIN_KINDS) {
    entries.push({ key: kind, label: ACHIEVEMENT_BADGES[kind].label, defaultIcon: ACHIEVEMENT_BADGES[kind].icon });
  }
  for (const kind of TIERED_ACHIEVEMENT_KINDS) {
    const set = TIER_BADGE_SETS[kind];
    if (kind === "gold") {
      // gold is the one tiered badge with a distinct icon PER tier, rather
      // than one shared icon plus a ring - so it needs one entry per tier.
      for (const tier of TIERS) {
        entries.push({ key: `gold:${tier}`, label: set[tier].label, defaultIcon: set[tier].icon });
      }
    } else {
      entries.push({
        key: kind,
        label: `${tierLabel(kind)} (every tier shares this one icon - only the ring color differs)`,
        defaultIcon: set.Copper.icon,
      });
    }
  }
  entries.push({
    key: CREATED_DATE_ICON_KEY,
    label: "Character creation-date badge",
    defaultIcon: CREATED_DATE_ICON,
  });
  for (const kind of ACCOUNT_KINDS) {
    entries.push({
      key: kind,
      label: ACCOUNT_ACHIEVEMENT_BADGES[kind].label,
      defaultIcon: ACCOUNT_ACHIEVEMENT_BADGES[kind].icon,
    });
  }
  return entries;
}

const ICON_ENTRIES = buildIconEntries();

export default function BadgeTesterPage() {
  const [userId, setUserId] = useState("");
  const [characters, setCharacters] = useState<Character[]>([]);
  const [selectedCharacter, setSelectedCharacter] = useState("");
  const [earnedPlain, setEarnedPlain] = useState<Set<AchievementKind>>(new Set());
  const [tiers, setTiers] = useState<Partial<Record<TieredAchievementKind, AchievementTier>>>({});
  const [accountEarned, setAccountEarned] = useState<Set<AccountAchievementKind>>(new Set());
  const [iconOverrides, setIconOverrides] = useState<BadgeIconOverrides>({});
  const [iconDrafts, setIconDrafts] = useState<Record<string, string>>({});
  const [iconSaving, setIconSaving] = useState<string | null>(null);
  const [status, setStatus] = useState("Loading...");
  const [busy, setBusy] = useState(false);

  async function refreshIconOverrides() {
    const overrides = await loadBadgeIconOverrides(supabase);
    setIconOverrides(overrides);
    const drafts: Record<string, string> = {};
    for (const entry of ICON_ENTRIES) {
      drafts[entry.key] = resolvedIcon(overrides, entry.key, entry.defaultIcon);
    }
    setIconDrafts(drafts);
  }

  async function saveIcon(key: string) {
    const icon = (iconDrafts[key] ?? "").trim();
    if (!icon) return;
    setIconSaving(key);
    await supabase.from("badge_icons").upsert({ key, icon }, { onConflict: "key" });
    await refreshIconOverrides();
    setIconSaving(null);
  }

  async function resetIcon(key: string, defaultIcon: string) {
    setIconSaving(key);
    await supabase.from("badge_icons").delete().eq("key", key);
    setIconDrafts((prev) => ({ ...prev, [key]: defaultIcon }));
    await refreshIconOverrides();
    setIconSaving(null);
  }

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

  async function loadAccountBadges(uid: string) {
    const { data } = await supabase.from("account_achievements").select("kind").eq("user_id", uid);
    setAccountEarned(new Set((data ?? []).map((r) => r.kind as AccountAchievementKind)));
  }

  useEffect(() => {
    async function init() {
      const { data: userData } = await supabase.auth.getUser();
      if (!userData.user) {
        setStatus("You need to be logged in to use this page.");
        return;
      }
      setUserId(userData.user.id);

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
      await loadAccountBadges(userData.user.id);
      await refreshIconOverrides();
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

  async function toggleAccount(kind: AccountAchievementKind) {
    if (!userId) return;
    setBusy(true);
    if (accountEarned.has(kind)) {
      await supabase.from("account_achievements").delete().eq("user_id", userId).eq("kind", kind);
    } else {
      await supabase
        .from("account_achievements")
        .upsert({ user_id: userId, kind }, { onConflict: "user_id,kind" });
    }
    await loadAccountBadges(userId);
    setBusy(false);
  }

  async function clearCharacterBadges() {
    if (!selectedCharacter) return;
    setBusy(true);
    await supabase.from("achievements").delete().eq("character_id", selectedCharacter);
    await loadCharacterBadges(selectedCharacter);
    setBusy(false);
  }

  async function clearAccountBadges() {
    if (!userId) return;
    setBusy(true);
    await supabase.from("account_achievements").delete().eq("user_id", userId);
    await loadAccountBadges(userId);
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
        to the achievements tables - it never touches level, gold, professions or anything else,
        so nothing here affects your actual tracked progress.
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
              Per-character achievements
            </h2>
            <div className="mt-2 flex flex-wrap gap-2">
              {PLAIN_KINDS.map((kind) => {
                const badge = ACHIEVEMENT_BADGES[kind];
                const on = earnedPlain.has(kind);
                const icon = resolvedIcon(iconOverrides, kind, badge.icon);
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
                    <GameIcon src={wowIconUrl(icon)} label={badge.label} size={22} round />
                    {kind}
                  </button>
                );
              })}
            </div>

            {TIERED_ACHIEVEMENT_KINDS.map((kind) => {
              const set = TIER_BADGE_SETS[kind];
              const current = tiers[kind] ?? null;
              const overrideKey = (tier: AchievementTier) => (kind === "gold" ? `gold:${tier}` : kind);
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
                    {TIERS.map((tier) => (
                      <button
                        key={tier}
                        disabled={busy}
                        onClick={() => setTier(kind, tier)}
                        title={set[tier].label}
                        className={`flex items-center gap-1.5 rounded-full py-1.5 pl-1.5 pr-3 text-sm disabled:opacity-50 ${
                          current === tier ? "bg-amber-500 text-neutral-950" : "bg-neutral-800 text-gray-300"
                        } ${set[tier].ring ?? ""}`}
                      >
                        <GameIcon
                          src={wowIconUrl(resolvedIcon(iconOverrides, overrideKey(tier), set[tier].icon))}
                          label={set[tier].label}
                          size={22}
                          round
                        />
                        {tier}
                      </button>
                    ))}
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

          <section className="mt-4 rounded-lg border border-neutral-700 bg-neutral-900/40 p-4">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
              Account-wide achievements
            </h2>
            <p className="mt-1 text-xs text-gray-500">
              These belong to your account (logged-in user), not any one character.
            </p>
            <div className="mt-2 flex flex-wrap gap-2">
              {ACCOUNT_KINDS.map((kind) => {
                const badge = ACCOUNT_ACHIEVEMENT_BADGES[kind];
                const on = accountEarned.has(kind);
                const icon = resolvedIcon(iconOverrides, kind, badge.icon);
                return (
                  <button
                    key={kind}
                    disabled={busy}
                    onClick={() => toggleAccount(kind)}
                    title={badge.label}
                    className={`flex items-center gap-1.5 rounded-full py-1.5 pl-1.5 pr-3 text-sm disabled:opacity-50 ${
                      on ? "bg-sky-500 text-neutral-950" : "bg-neutral-800 text-gray-300"
                    }`}
                  >
                    <GameIcon src={wowIconUrl(icon)} label={badge.label} size={22} round />
                    {kind}
                  </button>
                );
              })}
            </div>

            <button
              disabled={busy}
              onClick={clearAccountBadges}
              className="mt-4 rounded bg-neutral-700 px-3 py-1.5 text-sm text-white disabled:opacity-50"
            >
              Clear all account badges
            </button>
          </section>

          <section className="mt-4 rounded-lg border border-neutral-700 bg-neutral-900/40 p-4">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
              Customize icons
            </h2>
            <p className="mt-1 text-xs text-gray-500">
              Type any WoW icon name (as it appears in the URL on{" "}
              <a
                href="https://www.wowhead.com/classic/icons"
                target="_blank"
                rel="noreferrer"
                className="text-sky-400 underline"
              >
                Wowhead&apos;s icon browser
              </a>{" "}
              or in a tooltip on{" "}
              <a
                href="https://www.wowhead.com"
                target="_blank"
                rel="noreferrer"
                className="text-sky-400 underline"
              >
                Wowhead
              </a>
              , e.g. &quot;inv_sword_04&quot;) and hit Save. This changes it site-wide for
              everyone, immediately - no code change or redeploy needed.
            </p>

            <div className="mt-3 flex flex-col gap-2">
              {ICON_ENTRIES.map((entry) => {
                const draft = iconDrafts[entry.key] ?? entry.defaultIcon;
                const isOverridden = iconOverrides[entry.key] !== undefined;
                return (
                  <div
                    key={entry.key}
                    className="flex flex-wrap items-center gap-3 rounded bg-neutral-800 p-2.5"
                  >
                    <GameIcon src={wowIconUrl(draft)} label={entry.label} size={32} round />
                    <div className="min-w-[10rem] flex-1">
                      <div className="text-sm text-gray-200">{entry.label}</div>
                      <div className="text-xs text-gray-500">
                        {entry.key}
                        {isOverridden && <span className="ml-1.5 text-sky-400">(customized)</span>}
                      </div>
                    </div>
                    <input
                      value={draft}
                      onChange={(e) =>
                        setIconDrafts((prev) => ({ ...prev, [entry.key]: e.target.value }))
                      }
                      placeholder="icon_name"
                      className="w-48 rounded bg-white p-1.5 text-sm text-black"
                    />
                    <button
                      disabled={iconSaving === entry.key}
                      onClick={() => saveIcon(entry.key)}
                      className="rounded bg-blue-600 px-3 py-1.5 text-sm text-white disabled:opacity-50"
                    >
                      Save
                    </button>
                    {isOverridden && (
                      <button
                        disabled={iconSaving === entry.key}
                        onClick={() => resetIcon(entry.key, entry.defaultIcon)}
                        className="rounded bg-neutral-700 px-3 py-1.5 text-sm text-white disabled:opacity-50"
                      >
                        Reset to default
                      </button>
                    )}
                  </div>
                );
              })}
            </div>
          </section>

          <p className="mt-4 text-xs text-gray-500">
            Go check the character page, Dashboard or Friends page in another tab to see how
            whatever you just toggled or re-iconned actually looks.
          </p>
        </>
      )}
    </main>
  );
}
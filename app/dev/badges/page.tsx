"use client";

// A dev-only page for forcing badges onto your own characters/account so
// you can see how they look without actually grinding to max level, 5000
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

import { useEffect, useState } from "react";
import { supabase } from "../../../lib/supabase";
import { wowIconUrl } from "../../../lib/icons";
import GameIcon from "../../GameIcon";
import {
  ACHIEVEMENT_BADGES,
  GOLD_TIER_BADGE,
  EPIC_TIER_META,
  CREATED_DATE_ICON,
  CREATED_DATE_ICON_KEY,
  type AchievementKind,
  type GoldTier,
} from "../../CharacterCard";
import { ACCOUNT_ACHIEVEMENT_BADGES, type AccountAchievementKind } from "../../../lib/accountAchievements";
import {
  loadBadgeIconOverrides,
  resolvedIcon,
  type BadgeIconOverrides,
} from "../../../lib/badgeIconOverrides";

type Character = { id: string; name: string; class: string };

// Plain yes/no achievements (everything except the two tiered ones, which
// get their own tier-picker UI below).
const PLAIN_KINDS = Object.keys(ACHIEVEMENT_BADGES) as AchievementKind[];
const ACCOUNT_KINDS = Object.keys(ACCOUNT_ACHIEVEMENT_BADGES) as AccountAchievementKind[];
const TIERS: GoldTier[] = ["Bronze", "Silver", "Gold"];

// The epic_gear tier is derived from a running `progress` count in the
// real system - when forcing a tier here for testing, this just sets
// progress to a value guaranteed to land on that tier so nothing looks
// inconsistent if you ever look at the raw row.
const EPIC_TIER_PROGRESS: Record<GoldTier, number> = { Bronze: 1, Silver: 3, Gold: 5 };

// Every badge that can have its icon overridden, for the icon-editor
// section below. Keys match what CharacterCard/AccountBadges look up via
// resolvedIcon() - see lib/badgeIconOverrides.ts.
type IconEntry = { key: string; label: string; defaultIcon: string };

function buildIconEntries(): IconEntry[] {
  const entries: IconEntry[] = [];
  for (const kind of PLAIN_KINDS) {
    entries.push({ key: kind, label: ACHIEVEMENT_BADGES[kind].label, defaultIcon: ACHIEVEMENT_BADGES[kind].icon });
  }
  for (const tier of TIERS) {
    entries.push({
      key: `gold:${tier}`,
      label: GOLD_TIER_BADGE[tier].label,
      defaultIcon: GOLD_TIER_BADGE[tier].icon,
    });
  }
  entries.push({
    key: "epic_gear",
    label: "Epic gear tier (Bronze/Silver/Gold all share this one icon - only the ring color differs)",
    defaultIcon: EPIC_TIER_META.Bronze.icon,
  });
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
  const [goldTier, setGoldTierState] = useState<GoldTier | null>(null);
  const [epicTier, setEpicTierState] = useState<GoldTier | null>(null);
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
    let gold: GoldTier | null = null;
    let epic: GoldTier | null = null;
    for (const row of data ?? []) {
      if (row.kind === "gold") gold = row.tier as GoldTier | null;
      else if (row.kind === "epic_gear") epic = row.tier as GoldTier | null;
      else plain.add(row.kind as AchievementKind);
    }
    setEarnedPlain(plain);
    setGoldTierState(gold);
    setEpicTierState(epic);
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

  async function setGoldTier(tier: GoldTier | null) {
    if (!selectedCharacter) return;
    setBusy(true);
    if (tier === null) {
      await supabase.from("achievements").delete().eq("character_id", selectedCharacter).eq("kind", "gold");
    } else {
      await supabase
        .from("achievements")
        .upsert(
          { character_id: selectedCharacter, kind: "gold", tier },
          { onConflict: "character_id,kind" }
        );
    }
    await loadCharacterBadges(selectedCharacter);
    setBusy(false);
  }

  async function setEpicTier(tier: GoldTier | null) {
    if (!selectedCharacter) return;
    setBusy(true);
    if (tier === null) {
      await supabase
        .from("achievements")
        .delete()
        .eq("character_id", selectedCharacter)
        .eq("kind", "epic_gear");
    } else {
      await supabase.from("achievements").upsert(
        {
          character_id: selectedCharacter,
          kind: "epic_gear",
          tier,
          progress: EPIC_TIER_PROGRESS[tier],
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

            <h3 className="mt-4 text-xs font-semibold uppercase tracking-wide text-gray-500">
              Wealth tier (gold)
            </h3>
            <div className="mt-2 flex flex-wrap gap-2">
              <button
                disabled={busy}
                onClick={() => setGoldTier(null)}
                className={`rounded-full px-3 py-1.5 text-sm disabled:opacity-50 ${
                  goldTier === null ? "bg-amber-500 text-neutral-950" : "bg-neutral-800 text-gray-300"
                }`}
              >
                None
              </button>
              {TIERS.map((tier) => (
                <button
                  key={tier}
                  disabled={busy}
                  onClick={() => setGoldTier(tier)}
                  title={GOLD_TIER_BADGE[tier].label}
                  className={`flex items-center gap-1.5 rounded-full py-1.5 pl-1.5 pr-3 text-sm disabled:opacity-50 ${
                    goldTier === tier ? "bg-amber-500 text-neutral-950" : "bg-neutral-800 text-gray-300"
                  }`}
                >
                  <GameIcon
                    src={wowIconUrl(resolvedIcon(iconOverrides, `gold:${tier}`, GOLD_TIER_BADGE[tier].icon))}
                    label={GOLD_TIER_BADGE[tier].label}
                    size={22}
                    round
                  />
                  {tier}
                </button>
              ))}
            </div>

            <h3 className="mt-4 text-xs font-semibold uppercase tracking-wide text-gray-500">
              Epic gear tier
            </h3>
            <div className="mt-2 flex flex-wrap gap-2">
              <button
                disabled={busy}
                onClick={() => setEpicTier(null)}
                className={`rounded-full px-3 py-1.5 text-sm disabled:opacity-50 ${
                  epicTier === null ? "bg-purple-500 text-neutral-950" : "bg-neutral-800 text-gray-300"
                }`}
              >
                None
              </button>
              {TIERS.map((tier) => (
                <button
                  key={tier}
                  disabled={busy}
                  onClick={() => setEpicTier(tier)}
                  title={EPIC_TIER_META[tier].label}
                  className={`flex items-center gap-1.5 rounded-full py-1.5 pl-1.5 pr-3 text-sm disabled:opacity-50 ${
                    epicTier === tier ? "bg-purple-500 text-neutral-950" : "bg-neutral-800 text-gray-300"
                  } ${EPIC_TIER_META[tier].ring}`}
                >
                  <GameIcon
                    src={wowIconUrl(resolvedIcon(iconOverrides, "epic_gear", EPIC_TIER_META[tier].icon))}
                    label={EPIC_TIER_META[tier].label}
                    size={22}
                    round
                  />
                  {tier}
                </button>
              ))}
            </div>

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

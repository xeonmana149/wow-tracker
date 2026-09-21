"use client";

import { useEffect, useState, type ReactNode } from "react";
import Link from "next/link";
import { supabase } from "../lib/supabase";
import { LEGACY_CAP } from "../lib/legacy";
import { PROFESSION_ICONS, classIcon } from "../lib/icons";
import { SUPPLIED_BY } from "../lib/professions";
import { missingProfessions, whatsNext, type Todo } from "../lib/progress";
import type { CardCharacter, AchievementKind, GoldTier } from "./CharacterCard";
import CharacterRow from "./CharacterRow";
import GameIcon from "./GameIcon";
import NextList from "./NextList";
import { MoneyDisplay } from "./MoneyIcons";
import AccountSyncSetup from "./AccountSyncSetup";
import AccountBadges from "./AccountBadges";
import { awardAchievement, ACHIEVEMENT_MESSAGE } from "../lib/achievements";
import type { AccountAchievementKind } from "../lib/accountAchievements";
import { loadBadgeIconOverrides, type BadgeIconOverrides } from "../lib/badgeIconOverrides";
import { LATEST_VERSIONS } from "../lib/versions";

const PRIMARY = [
  "Alchemy",
  "Blacksmithing",
  "Enchanting",
  "Engineering",
  "Herbalism",
  "Leatherworking",
  "Mining",
  "Skinning",
  "Tailoring",
];

type ActivityEvent = {
  id: string;
  character_id: string | null;
  kind: string;
  message: string;
  created_at: string;
};

// Small stroke-only icon set for the Account Overview strip, matching the
// nav bar's icon style (a plain svg wrapper, a handful of line paths) so
// this stat row and the top nav read as one visual language.
function StatIcon({ children }: { children: ReactNode }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width="20"
      height="20"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      className="shrink-0 text-amber-400"
    >
      {children}
    </svg>
  );
}
const ICON_PERSON = (
  <StatIcon>
    <circle cx="12" cy="8" r="4" />
    <path d="M4 20a8 8 0 0 1 16 0" />
  </StatIcon>
);
const ICON_CHART = (
  <StatIcon>
    <path d="M4 20V10" />
    <path d="M11 20V4" />
    <path d="M18 20v-7" />
  </StatIcon>
);
const ICON_HAMMER = (
  <StatIcon>
    <path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94z" />
  </StatIcon>
);
const ICON_BOOK = (
  <StatIcon>
    <path d="M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2z" />
    <path d="M19 17H6a2 2 0 0 0-2 2" />
  </StatIcon>
);
const ICON_STAR = (
  <StatIcon>
    <path d="M12 3l2.6 5.7 6.2.6-4.7 4.2 1.4 6.2L12 16.9l-5.5 2.8 1.4-6.2-4.7-4.2 6.2-.6z" />
  </StatIcon>
);
const ICON_INFO = (
  <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className="shrink-0">
    <circle cx="12" cy="12" r="9" />
    <path d="M12 11v5" />
    <path d="M12 8v.01" />
  </svg>
);

// A minute-scale "2 hours ago" / "3 days ago" label for the Recent Activity
// list - coarse on purpose, this is a glance-at list, not a precise clock.
function timeAgo(iso: string): string {
  const minutes = Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 60000));
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes} minute${minutes === 1 ? "" : "s"} ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} hour${hours === 1 ? "" : "s"} ago`;
  const days = Math.floor(hours / 24);
  return `${days} day${days === 1 ? "" : "s"} ago`;
}

export default function Dashboard({
  specIcons,
  treeNames,
}: {
  specIcons: Record<string, string>;
  treeNames: Record<string, string[]>;
}) {
  const [status, setStatus] = useState<"loading" | "loggedOut" | "ready">("loading");
  const [characters, setCharacters] = useState<CardCharacter[]>([]);
  const [error, setError] = useState("");
  const [userId, setUserId] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [legacy, setLegacy] = useState(0);
  const [editingLegacy, setEditingLegacy] = useState(false);
  const [legacyDraft, setLegacyDraft] = useState("0");
  const [legacyMessage, setLegacyMessage] = useState("");
  const [accountAchievements, setAccountAchievements] = useState<AccountAchievementKind[]>([]);
  const [iconOverrides, setIconOverrides] = useState<BadgeIconOverrides>({});
  const [recentActivity, setRecentActivity] = useState<ActivityEvent[]>([]);
  const [syncOpenSignal, setSyncOpenSignal] = useState(0);
  const [myVersions, setMyVersions] = useState<{ addon: string | null; tray: string | null }>({
    addon: null,
    tray: null,
  });

  useEffect(() => {
    async function load() {
      const { data: userData } = await supabase.auth.getUser();

      if (!userData.user) {
        setStatus("loggedOut");
        return;
      }
      setUserId(userData.user.id);

      // None of these six requests depend on each other's results - they
      // all just need the user id we already have - so they're fired off
      // together with Promise.all instead of one at a time. Sequentially,
      // each await sits and waits on its own round-trip before the next one
      // even starts; six round-trips stacked up before this page could
      // even render is the main reason every click into the dashboard felt
      // slow. Run together, the wait is roughly whichever single request is
      // slowest, not the sum of all six.
      const [
        { data, error },
        { data: achievementRows },
        { data: profile },
        { data: accountAchievementRows },
        { data: activityRows },
        overrides,
      ] = await Promise.all([
        supabase
          .from("characters")
          .select(
            "*, character_professions(profession, skill, recipes), character_talents(slot, tree, rank), character_legacy(rank), character_wishlist(item_name, priority, obtained)"
          )
          .eq("user_id", userData.user.id)
          .order("level", { ascending: false }),
        // Achievements are per-character now (not a server-wide "first"),
        // but there still aren't many rows total for a small friend group,
        // so it's simplest to just grab them all and match them up.
        supabase.from("achievements").select("kind, tier, character_id"),
        supabase
          .from("profiles")
          .select("display_name, legacy_points, addon_version, tray_version")
          .eq("id", userData.user.id)
          .single(),
        supabase
          .from("account_achievements")
          .select("kind")
          .eq("user_id", userData.user.id),
        // Recent Activity panel - the same activity_events rows the sync
        // route and this page's own Legacy save already write to, just
        // read back here instead of only ever appearing in the floating
        // activity sidebar.
        supabase
          .from("activity_events")
          .select("id, character_id, kind, message, created_at")
          .eq("user_id", userData.user.id)
          .order("created_at", { ascending: false })
          .limit(6),
        loadBadgeIconOverrides(supabase),
      ]);

      if (error) {
        setError(error.message);
      } else {
        type Row = { kind: AchievementKind | "gold" | "epic_gear"; tier: GoldTier | null; character_id: string };
        const achievementsByCharacter = new Map<
          string,
          { kind: AchievementKind | "gold" | "epic_gear"; tier?: GoldTier | null }[]
        >();
        for (const a of (achievementRows ?? []) as Row[]) {
          const list = achievementsByCharacter.get(a.character_id) ?? [];
          list.push({ kind: a.kind, tier: a.tier });
          achievementsByCharacter.set(a.character_id, list);
        }

        const withAchievements = (data ?? []).map((c) => ({
          ...c,
          achievements: achievementsByCharacter.get(c.id) ?? [],
        }));
        setCharacters(withAchievements as CardCharacter[]);
      }

      setDisplayName(profile?.display_name ?? "");
      setLegacy(Math.min(LEGACY_CAP, profile?.legacy_points ?? 0));
      setMyVersions({
        addon: profile?.addon_version ?? null,
        tray: profile?.tray_version ?? null,
      });

      setAccountAchievements(
        (accountAchievementRows ?? []).map((r) => r.kind as AccountAchievementKind)
      );

      setRecentActivity((activityRows ?? []) as ActivityEvent[]);

      setIconOverrides(overrides);

      setStatus("ready");
    }

    load();
  }, []);

  async function saveLegacy() {
    const points = Math.min(LEGACY_CAP, Math.max(0, Math.round(Number(legacyDraft) || 0)));
    const { error } = await supabase
      .from("profiles")
      .update({ legacy_points: points })
      .eq("id", userId);

    if (error) {
      setLegacyMessage(error.message);
      return;
    }

    // Legacy points live on the profile, not on a character, so this event
    // has no character_id - just a message and whoever gained the point.
    // Best-effort only, same as the sync-route events: never blocks saving.
    if (points > legacy) {
      try {
        await supabase.from("activity_events").insert({
          user_id: userId,
          kind: "legacy_point",
          message: `Reached ${points} Legacy point${points === 1 ? "" : "s"}`,
        });

        // The "maxed Legacy" achievement is a character badge, but Legacy
        // points are account-wide - awarded to whichever character is
        // marked as your Main, since that's the natural "face" of the
        // account. Skipped quietly if you don't have one set.
        if (points >= LEGACY_CAP) {
          const mainCharacter = characters.find((c) => c.character_type === "Main");
          if (mainCharacter) {
            const earned = await awardAchievement(supabase, mainCharacter.id, "maxed_legacy");
            if (earned) {
              await supabase.from("activity_events").insert({
                character_id: mainCharacter.id,
                user_id: userId,
                kind: "achievement_earned",
                message: ACHIEVEMENT_MESSAGE.maxed_legacy(mainCharacter.name),
              });
            }
          }
        }
      } catch {
        // ignored on purpose
      }
    }

    setLegacy(points);
    setLegacyMessage("");
    setEditingLegacy(false);
  }

  if (status === "loading") {
    return <main className="mx-auto max-w-[1500px] p-4 md:p-6">Loading...</main>;
  }

  if (status === "loggedOut") {
    return (
      <main className="mx-auto max-w-[1500px] p-4 md:p-6">
        <h1 className="text-4xl font-bold">WoW Forever Tracker</h1>
        <p className="mt-4">Track your characters, gear and talents with your friends.</p>
        <Link
          href="/login"
          className="mt-6 inline-block rounded bg-blue-600 px-4 py-2 text-white"
        >
          Log in / Sign up
        </Link>
      </main>
    );
  }

  const highestLevel = characters.length
    ? Math.max(...characters.map((c) => c.level))
    : 0;
  const totalCopper = characters.reduce((sum, c) => sum + (c.money_copper ?? 0), 0);

  // Best skill for each profession across every character on the account
  const best: Record<string, { skill: number; character: string }> = {};
  for (const c of characters) {
    for (const p of c.character_professions ?? []) {
      if (!best[p.profession] || p.skill > best[p.profession].skill) {
        best[p.profession] = { skill: p.skill, character: c.name };
      }
    }
  }

  const coveredCount = PRIMARY.filter((p) => best[p]).length;

  // Every recipe known by every character on the account, added together -
  // not deduped, so two characters both knowing First Aid still count as 2.
  // It's meant as "how much of the shared library did I personally build up",
  // not "how many distinct recipes".
  const totalRecipesKnown = characters.reduce(
    (sum, c) =>
      sum +
      (c.character_professions ?? []).reduce(
        (n, p) => n + (Array.isArray(p.recipes) ? p.recipes.length : 0),
        0
      ),
    0
  );

  // What's next: account-wide, then character by character
  const missing = missingProfessions(characters);
  const accountTodos: Todo[] = [];
  if (missing.length > 0) {
    const names = missing.slice(0, 4).join(", ");
    const more = missing.length > 4 ? ` and ${missing.length - 4} more` : "";
    accountTodos.push({ kind: "profession", text: `No ${names}${more} on your account` });
  }
  const perCharacter = characters.map((c) => ({ c, todos: whatsNext(c, legacy) }));
  const charById = new Map<string, CardCharacter>(characters.map((c) => [c.id, c]));

  // Only fires once this account has actually synced at least once (an
  // empty/never-synced profile has null versions, which isn't "outdated" -
  // just "haven't heard from you yet"). Compared against whatever this
  // deploy of the site itself considers current, from lib/versions.ts.
  const addonOutdated = !!myVersions.addon && myVersions.addon !== LATEST_VERSIONS.addon;
  const trayOutdated = !!myVersions.tray && myVersions.tray !== LATEST_VERSIONS.tray;

  return (
    <main className="mx-auto max-w-[1500px] p-4 md:p-6">
      {/* Hero - who's looking at this, and a reminder of what the site's
          for. Doesn't need to do anything, just set the tone before the
          data-dense sections below. */}
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-4xl font-bold">
            Welcome back{displayName ? `, ${displayName}` : ""}
          </h1>
          <p className="mt-1 text-gray-400">Track your progress. Plan your next steps. Play together.</p>
        </div>
        <p className="max-w-xs text-right text-sm italic text-gray-500">
          "A great adventure is better with friends."
        </p>
      </div>

      {(addonOutdated || trayOutdated) && (
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-purple-700 bg-purple-950/40 p-3 text-sm text-purple-200">
          <div className="flex items-start gap-2">
            {ICON_INFO}
            <div>
              {addonOutdated && (
                <p>
                  A new version of the WoWForeverTracker addon ({LATEST_VERSIONS.addon}) is out.
                  You have {myVersions.addon} installed. Download it and replace the addon folder in
                  WoW.
                </p>
              )}
              {trayOutdated && (
                <p className={addonOutdated ? "mt-1" : undefined}>
                  A new version of the background sync app ({LATEST_VERSIONS.tray}) is out. You
                  have {myVersions.tray} installed. Download it and reinstall over the old folder.
                </p>
              )}
            </div>
          </div>
          <Link
            href="/download"
            className="shrink-0 rounded bg-purple-700 px-3 py-1.5 text-xs font-semibold text-white hover:bg-purple-600"
          >
            View Instructions →
          </Link>
        </div>
      )}

      {/* Account Overview - one glanceable strip instead of a boxed grid,
          with Auto-Sync setup folded into a button here rather than its
          own always-visible section; the panel it opens still renders
          right below, it just starts collapsed until asked for. */}
      <section className="mt-4 rounded-lg border border-neutral-700 bg-neutral-900/40 p-4">
        <div className="flex flex-wrap items-center gap-x-8 gap-y-4">
          <div className="flex items-center gap-2">
            {ICON_PERSON}
            <div>
              <div className="text-xl font-bold leading-tight">{characters.length}</div>
              <div className="text-xs text-gray-400">Characters</div>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {ICON_CHART}
            <div>
              <div className="text-xl font-bold leading-tight">{highestLevel}</div>
              <div className="text-xs text-gray-400">Highest level</div>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {ICON_HAMMER}
            <div>
              <div className="text-xl font-bold leading-tight">
                {coveredCount}/{PRIMARY.length}
              </div>
              <div className="text-xs text-gray-400">Professions</div>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {ICON_BOOK}
            <div>
              <div className="text-xl font-bold leading-tight">{totalRecipesKnown}</div>
              <div className="text-xs text-gray-400">Recipes known</div>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <div className="text-xl font-bold leading-tight"><MoneyDisplay copper={totalCopper} /></div>
            <div className="text-xs text-gray-400">Total gold</div>
          </div>
          <div className="flex items-center gap-2">
            {ICON_STAR}
            {editingLegacy ? (
              <div className="flex flex-col gap-2">
                <div className="flex items-center gap-2">
                  <input
                    type="number"
                    min={0}
                    max={LEGACY_CAP}
                    value={legacyDraft}
                    onChange={(e) => setLegacyDraft(e.target.value)}
                    aria-label="Legacy points"
                    className="w-16 rounded bg-white p-1 text-black"
                  />
                  <span className="text-xs text-gray-400">/ {LEGACY_CAP}</span>
                </div>
                <div className="flex gap-2">
                  <button
                    onClick={saveLegacy}
                    className="rounded bg-blue-600 px-3 py-1 text-xs text-white"
                  >
                    Save
                  </button>
                  <button
                    onClick={() => {
                      setEditingLegacy(false);
                      setLegacyMessage("");
                    }}
                    className="rounded bg-neutral-700 px-3 py-1 text-xs text-white"
                  >
                    Cancel
                  </button>
                </div>
                {legacyMessage && <p className="text-xs text-red-400">{legacyMessage}</p>}
              </div>
            ) : (
              <div>
                <div className="text-xl font-bold leading-tight">
                  {legacy}/{LEGACY_CAP}
                </div>
                <div className="text-xs text-gray-400">
                  Legacy points{" "}
                  <button
                    onClick={() => {
                      setLegacyDraft(String(legacy));
                      setEditingLegacy(true);
                    }}
                    className="text-blue-400 underline"
                  >
                    edit
                  </button>
                </div>
              </div>
            )}
          </div>

          <button
            onClick={() => setSyncOpenSignal((n) => n + 1)}
            className="ml-auto shrink-0 rounded-lg bg-amber-500 px-4 py-2 text-sm font-semibold text-neutral-950 hover:bg-amber-400"
          >
            ⚙ Set Up Auto-Sync
          </button>
        </div>
      </section>

      <AccountSyncSetup openSignal={syncOpenSignal} />

      {accountAchievements.length > 0 && (
        <section className="mt-4 rounded-lg border border-neutral-700 bg-neutral-900/40 p-4">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
            Account achievements
          </h2>
          <p className="mt-1 text-xs text-gray-500">
            Earned by your account as a whole, not any one character. Hover a badge to see what
            it's for.
          </p>
          <div className="mt-3">
            <AccountBadges kinds={accountAchievements} size="md" iconOverrides={iconOverrides} />
          </div>
        </section>
      )}

      {error && <p className="mt-4 text-red-400">{error}</p>}

      <div className="mt-6 grid gap-4 xl:grid-cols-3">
        <section className="rounded-lg border border-neutral-700 bg-neutral-900/40 p-4 xl:col-span-2">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
              My Characters
            </h2>
            <Link
              href="/create"
              className="rounded bg-amber-500 px-3 py-1.5 text-sm font-semibold text-neutral-950 hover:bg-amber-400"
            >
              + Create Character
            </Link>
          </div>

          {characters.length === 0 && !error && (
            <p className="mt-3 text-gray-400">You have no characters yet.</p>
          )}

          {(() => {
            // Grouped by type rather than linked to a specific Main - there's
            // no "this Alt belongs to that Main" relationship in the schema,
            // just an independent type per character. Mains first, Alts
            // right under them (visually nested, so they read as "belonging"
            // to the Mains above even without an actual link), then
            // anything else. Order within each group is whatever the
            // characters were already sorted in (level, descending).
            const mains = characters.filter((c) => c.character_type === "Main");
            const alts = characters.filter((c) => c.character_type === "Alt");
            const others = characters.filter(
              (c) => c.character_type !== "Main" && c.character_type !== "Alt"
            );

            const group = (
              list: CardCharacter[],
              label: string,
              headingClass: string,
              nested: boolean
            ) =>
              list.length > 0 && (
                <div className={nested ? "border-l-2 border-neutral-700 pl-4" : undefined}>
                  <h3 className={`mb-2 text-xs font-semibold uppercase tracking-wide ${headingClass}`}>
                    {label}
                  </h3>
                  <div className="flex flex-col gap-2">
                    {list.map((c) => (
                      <CharacterRow key={c.id} c={c} iconOverrides={iconOverrides} />
                    ))}
                  </div>
                </div>
              );

            return (
              <div className="mt-3 flex flex-col gap-4">
                {group(mains, mains.length > 1 ? "Mains" : "Main", "text-amber-400", false)}
                {group(alts, "Alts", "text-sky-400", true)}
                {group(others, "Other characters", "text-gray-400", false)}
              </div>
            );
          })()}
        </section>

        <div className="flex flex-col gap-4">
          <section className="rounded bg-neutral-800 p-4">
            <h2 className="text-xl font-bold">What&apos;s next</h2>
            <p className="mt-1 text-xs text-gray-500">
              Worked out from your Pre-BiS lists, talents, Legacy and professions.
            </p>

            {accountTodos.length > 0 && (
              <div className="mt-3">
                <h3 className="text-sm">Account</h3>
                <div className="mt-1.5">
                  <NextList todos={accountTodos} />
                </div>
              </div>
            )}

            {characters.length === 0 ? (
              <p className="mt-3 text-sm text-gray-500">Create a character to get started.</p>
            ) : (
              <div className="mt-4 flex flex-col gap-4">
                {perCharacter.map(({ c, todos }) => (
                  <div key={c.id}>
                    <Link href={`/character/${c.id}`} className="flex items-center gap-2">
                      <GameIcon name={classIcon(c.class)} label={c.class} size={26} round />
                      <span className="font-bold text-white">{c.name}</span>
                      <span className="text-xs text-gray-500">Level {c.level}</span>
                    </Link>
                    <div className="mt-1.5 pl-9">
                      <NextList todos={todos} limit={4} empty="All caught up." />
                    </div>
                  </div>
                ))}
              </div>
            )}
          </section>

          <section>
            <h2 className="text-xl font-bold">Profession Coverage</h2>
            <p className="mt-1 text-sm text-gray-400">
              ✓ covered · ✗ missing · ⚠ covered, but nobody gathers the materials
            </p>

            <ul className="mt-3 flex flex-col gap-2">
              {PRIMARY.map((profession) => {
                const found = best[profession];
                const supplier = SUPPLIED_BY[profession];
                const unsupplied = found && supplier && !best[supplier];

                return (
                  <li
                    key={profession}
                    className="flex items-center justify-between gap-3 rounded bg-neutral-800 p-3"
                  >
                    <span className="flex items-center gap-2">
                      <GameIcon
                        name={PROFESSION_ICONS[profession]}
                        label={profession}
                        size={28}
                      />
                      <span>
                        <span
                          className={
                            !found
                              ? "text-red-400"
                              : unsupplied
                              ? "text-yellow-400"
                              : "text-green-400"
                          }
                        >
                          {!found ? "✗" : unsupplied ? "⚠" : "✓"}
                        </span>{" "}
                        {profession}
                        {unsupplied && (
                          <span className="block text-xs text-yellow-500">
                            No {supplier} on your account to supply it
                          </span>
                        )}
                      </span>
                    </span>
                    <span className="text-sm text-gray-400">
                      {found ? `${found.skill} · ${found.character}` : "Missing"}
                    </span>
                  </li>
                );
              })}
            </ul>
          </section>
        </div>
      </div>

      {/* Recent Activity / Quick Actions / Need Help - a bottom row so the
          page doesn't just end after Profession Coverage; Recent Activity
          reads the same activity_events rows the floating sidebar and the
          sync route already write to, Quick Actions are just shortcuts to
          pages that already exist elsewhere in the nav. */}
      <div className="mt-6 grid gap-4 lg:grid-cols-3">
        <section className="rounded-lg border border-neutral-700 bg-neutral-900/40 p-4">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
            Recent Activity
          </h2>
          {recentActivity.length === 0 ? (
            <p className="mt-3 text-sm text-gray-500">Nothing yet - sync a character to get started.</p>
          ) : (
            <ul className="mt-3 flex flex-col gap-3">
              {recentActivity.map((a) => {
                const c = a.character_id ? charById.get(a.character_id) : undefined;
                return (
                  <li key={a.id} className="flex items-start gap-2">
                    {c ? (
                      <GameIcon name={classIcon(c.class)} label={c.class} size={22} round />
                    ) : (
                      <span className="grid h-[22px] w-[22px] shrink-0 place-items-center rounded-full border border-amber-900/70 bg-neutral-900 text-amber-200">
                        {ICON_PERSON}
                      </span>
                    )}
                    <span className="min-w-0 flex-1 text-sm text-gray-300">{a.message}</span>
                    <span className="shrink-0 text-xs text-gray-500">{timeAgo(a.created_at)}</span>
                  </li>
                );
              })}
            </ul>
          )}
        </section>

        <section className="rounded-lg border border-neutral-700 bg-neutral-900/40 p-4">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
            Quick Actions
          </h2>
          <div className="mt-3 grid grid-cols-2 gap-2">
            <Link
              href="/friends"
              className="rounded border border-neutral-700 bg-neutral-800 p-3 text-sm hover:bg-neutral-700"
            >
              View Friends
            </Link>
            <Link
              href="/crafting"
              className="rounded border border-neutral-700 bg-neutral-800 p-3 text-sm hover:bg-neutral-700"
            >
              Open Crafting Directory
            </Link>
            <Link
              href="/leaderboards"
              className="rounded border border-neutral-700 bg-neutral-800 p-3 text-sm hover:bg-neutral-700"
            >
              Check Leaderboards
            </Link>
            <Link
              href="/news"
              className="rounded border border-neutral-700 bg-neutral-800 p-3 text-sm hover:bg-neutral-700"
            >
              Read Latest News
            </Link>
          </div>
        </section>

        <section className="rounded-lg border border-neutral-700 bg-neutral-900/40 p-4">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
            Need Help?
          </h2>
          <p className="mt-2 text-sm text-gray-400">
            Setup guides, addon instructions and more.
          </p>
          <Link
            href="/download"
            className="mt-3 inline-block rounded bg-amber-500 px-4 py-2 text-sm font-semibold text-neutral-950 hover:bg-amber-400"
          >
            View Downloads & Guides →
          </Link>
        </section>
      </div>
    </main>
  );
}
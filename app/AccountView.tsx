import type { ReactNode } from "react";
import Link from "next/link";
import { ShowcaseBadge } from "./AchievementShowcase";
import AccountBadgesGrid from "./AccountBadgesGrid";
import FamilyTileIcon from "./FamilyTileIcon";
import AccountShowcase from "./AccountShowcase";
import { localBadgeIconSrc } from "../lib/badgeFrames";
import BadgePlaceholder from "./BadgePlaceholder";
import {
  ACCOUNT_ACHIEVEMENT_BADGES,
  accountBadgeIconSrc,
  type AccountAchievementKind,
} from "../lib/accountAchievements";
import { avatarIconSrc, bannerImageSrc, findAvatarIconOption, findBannerOption, bannerClassName } from "../lib/profileCustomization";
import { formatDate, type AccountViewData } from "../lib/accountView";

// The read-only account-overview display (2026-09-30, split out of
// app/account/page.tsx so the same view can be reused by:
//  - app/account/page.tsx - your own account, with an Edit Profile button
//    and panel passed in via `headerActions`/`belowHeader`.
//  - app/account/[userId]/page.tsx - someone else's account (new, answering
//    "how do we see other players account pages?") - read-only, so it's
//    just this component with no header slots filled in.
// No hooks, no state, no fetching - everything it needs comes in as props,
// which is what lets it be rendered from either a "use client" page or a
// plain server component page without caring which.
//
// 2026-10-03 layout rework ("the current Account Progress area is
// confusing... make the Overview page answer three questions immediately:
// how far have I progressed, what have I accomplished, what should I work
// toward next") - replaced the old "Account Progress" category-grid + plain
// Playtime box with a 5-card ACCOUNT OVERVIEW strip, added a new CONTINUE
// YOUR JOURNEY strip of next-milestone cards, moved Showcase to full width
// right under that, and regrouped the lower half into two columns
// (Characters + Recent Achievements | Featured Character Achievements +
// Account Achievements). "Account Badges" is renamed "Account Achievements"
// here (display-only - the data/type names underneath are untouched) since
// it's the exact same system, just badly named before.
//
// The old per-family (Wealth/Combat/Social/etc.) breakdown grid is
// deliberately NOT rendered here anymore - Jordan's call was that it doesn't
// need prime real estate on the Overview, it belongs on the (still
// "Coming soon") Achievements tab instead, once that gets built. Nothing
// about that data was deleted: `mergedItems`, `FAMILY_META` and the
// per-family grouping this file used to do are all still intact in
// lib/achievements.ts/lib/accountView.ts for whenever that tab happens -
// this file just stopped being the one place it's always shown.
export function AccountView({
  data,
  headerActions,
  belowHeader,
  onEditShowcase,
}: {
  data: AccountViewData;
  headerActions?: ReactNode;
  belowHeader?: ReactNode;
  // 2026-10-03 ("Showcase should have an edit button in top right corner") -
  // only passed by app/account/page.tsx (your own account), see
  // AccountShowcase.tsx's own comment on the `onEdit` prop this threads
  // through to.
  onEditShowcase?: () => void;
}) {
  const {
    userId,
    displayName,
    memberSince,
    avatarIcon,
    bannerStyle,
    motto,
    characters,
    recent,
    accountBadges,
    accountBadgeProgress,
    accountBadgeBreakdown,
    legacyEarned,
    legacyPoints,
    iconOverrides,
    favoriteCharacter,
    favoriteStatistic,
    favoriteAchievement,
    favoriteItem,
    mainCharacter,
    mainCharacterItems,
  } = data;

  // Main Character Achievements (2026-10-03, "for character achievements tab
  // it should only track the character set as main") - every achievement
  // count/card on this page that used to read the account-wide MERGED view
  // (mergedItems - highest tier reached by any character) now reads
  // mainCharacterItems instead - one character's own achievements, whichever
  // one is flagged character_type "Main". `mergedItems`/`itemOwner` are kept
  // around (still returned by lib/accountView.ts) for anything else that
  // might want the old account-wide view later - this page just doesn't use
  // them for the "Character Achievements" sections anymore.
  const earnedCount = mainCharacterItems.filter((i) => i.earned).length;
  const totalCount = mainCharacterItems.length;
  const achievementPct = totalCount > 0 ? Math.round((earnedCount / totalCount) * 100) : 0;
  const achievementsRemaining = totalCount - earnedCount;

  const accountBadgeTotal = Object.keys(ACCOUNT_ACHIEVEMENT_BADGES).length;
  const accountBadgePct = accountBadgeTotal > 0 ? Math.round((accountBadges.length / accountBadgeTotal) * 100) : 0;

  const legacyPct = Math.round((legacyPoints / 65) * 100);

  const totalHours = characters.reduce((sum, c) => sum + (c.time_played_hours ?? 0), 0);
  const totalMinutesAll = Math.round(totalHours * 60);
  const playHours = Math.floor(totalMinutesAll / 60);
  const playMinutes = totalMinutesAll % 60;

  // Per-character playtime breakdown (2026-10-03, replacing the old
  // Horde/Alliance split - "show a compact breakdown of playtime by
  // character with small bars/percentages") - sorted by hours played so the
  // segment order in the bar matches the legend order beneath it.
  const PLAYTIME_COLORS = ["#f59e0b", "#fb923c", "#ef4444", "#a855f7", "#38bdf8", "#4ade80"];
  const playtimeByCharacter = characters
    .map((c) => ({
      id: c.id,
      name: c.name,
      hours: c.time_played_hours ?? 0,
      pct: totalHours > 0 ? Math.round(((c.time_played_hours ?? 0) / totalHours) * 100) : 0,
    }))
    .sort((a, b) => b.hours - a.hours);

  // "Continue Your Journey" - the single closest unearned Main-character
  // achievement, the closest unearned account achievement (from
  // accountBadgeProgress, filtered down to badges not already in
  // `accountBadges`), and a Legacy Challenges nudge. All three fall back to
  // a "you're done" state rather than ever showing stale/hardcoded example
  // content.
  const closestUnearnedAchievement = mainCharacterItems
    .filter((i) => !i.earned && i.tiered && i.value !== null && i.nextThreshold)
    .sort((a, b) => (b.value as number) / (b.nextThreshold as number) - (a.value as number) / (a.nextThreshold as number))[0];

  // Excludes badges that just mirror a fraction ALREADY shown in its own
  // dedicated card elsewhere on this page ("the_completionist" is literally
  // earnedAchievementCount/totalAchievementCount - the same ratio the
  // Character Achievements card already shows; "legacy_complete" is the same
  // 65-point Legacy Challenges total the Legacy card already shows) -
  // 2026-10-03, "the completionist doesn't make sense for being the closest
  // to done does it?" - showing one of these as the "next account
  // achievement to chase" was just restating a number already on the page,
  // not a genuinely different thing to go work on.
  const ACCOUNT_BADGE_GOAL_EXCLUDE = new Set<AccountAchievementKind>(["the_completionist", "legacy_complete"]);
  const closestAccountBadge = (() => {
    const entries = (Object.keys(accountBadgeProgress) as AccountAchievementKind[])
      .filter((kind) => !accountBadges.includes(kind) && !ACCOUNT_BADGE_GOAL_EXCLUDE.has(kind))
      .map((kind) => ({ kind, ...(accountBadgeProgress[kind] as { value: number; target: number }) }))
      .filter((e) => e.target > 0);
    entries.sort((a, b) => b.value / b.target - a.value / a.target);
    return entries[0] ?? null;
  })();

  const avatarOption = findAvatarIconOption(avatarIcon);
  const bannerOption = findBannerOption(bannerStyle);
  const bannerImgSrc = bannerImageSrc(bannerOption);

  return (
    <main className="mx-auto max-w-6xl p-4 text-white md:p-6">
      {/* Profile header - a crest showing the chosen avatar option's art
          (falling back to the lettered .crest-fallback when none is
          picked), and a banner that's either a custom-art option (rendered
          via .profile-banner-custom with a readability overlay) or one of
          the named gradient presets - see lib/profileCustomization.ts for
          how options resolve to art. `.account-banner` gives this a real,
          fixed height (220px desktop / 160px mobile, see theme.css). */}
      <div
        className={`account-banner ${bannerClassName(bannerStyle)}`}
        style={bannerImgSrc ? { backgroundImage: `url(${bannerImgSrc})` } : undefined}
      >
        <div className="profile-banner-content flex items-center gap-4 p-4 md:p-6">
          <div className="crest">
            {avatarOption ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={avatarIconSrc(avatarOption)} alt="" />
            ) : (
              <span className="crest-fallback">{displayName.charAt(0).toUpperCase()}</span>
            )}
          </div>
          <div className="flex-1">
            <h1>{displayName}</h1>
            {memberSince && <p className="text-sm text-gray-600">Member since {formatDate(memberSince)}</p>}
            {motto && <p className="mt-1 text-sm italic opacity-90">&ldquo;{motto}&rdquo;</p>}
          </div>
          {headerActions && <div className="hero-actions">{headerActions}</div>}
        </div>
      </div>

      {belowHeader}

      {/* Achievements/Settings are still staged follow-ups rather than dead
          links. Statistics and Activity (2026-10-03) now go to their own
          pages - see app/account/[userId]/statistics and .../activity. Both
          work for any account (not just your own), same as the rest of this
          page, so they link by `userId` rather than assuming "your own
          account". */}
      <div className="mt-4 flex flex-wrap gap-2">
        <span className="tab-btn tab-btn-active">Overview</span>
        <span className="tab-btn cursor-not-allowed opacity-50" title="Coming soon">
          Achievements
        </span>
        <Link href={`/account/${userId}/statistics`} className="tab-btn">
          Statistics
        </Link>
        <Link href={`/account/${userId}/activity`} className="tab-btn">
          Activity
        </Link>
        <span className="tab-btn cursor-not-allowed opacity-50" title="Coming soon">
          Settings
        </span>
      </div>

      {/* ACCOUNT OVERVIEW - 5 horizontal summary cards, replacing the old
          "Account Progress" category grid + separate Playtime box. Each
          card's "View All" jumps to the fuller section further down THIS
          page (there's no separate dedicated page for these yet beyond
          /legacy, which already exists) rather than linking somewhere new. */}
      <div className="mt-4 rounded-md border border-neutral-700 bg-neutral-800 p-4">
        <h2 className="text-lg">Account Overview</h2>
        <p className="mt-1 text-sm text-gray-400">Your overall WoW Forever progress across all characters.</p>

        <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-5">
          {/* Characters */}
          <div className="rounded border border-neutral-700 bg-neutral-900 p-3">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-amber-400/70">Characters</p>
            <p className="mt-1 text-3xl font-bold text-white">{characters.length}</p>
            <a href="#characters-section" className="mt-1 inline-block text-xs text-amber-400 hover:underline">
              View All →
            </a>
          </div>

          {/* Main Character Achievements (2026-10-03, "for character
              achievements tab it should only track the character set as
              main") - was the account-wide merged count, now mirrors
              mainCharacterItems exactly like Featured Achievements below. No
              Main character set at all shows a prompt instead of a 0/0. */}
          <div className="rounded border border-neutral-700 bg-neutral-900 p-3">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-amber-400/70">
              Main Character Achievements
            </p>
            {mainCharacter ? (
              <>
                <p className="mt-1 text-xl font-bold text-white">
                  {earnedCount} / {totalCount}
                </p>
                <div className="mt-2 h-2 w-full overflow-hidden rounded-full bg-neutral-700">
                  <div className="h-full rounded-full bg-yellow-500" style={{ width: `${achievementPct}%` }} />
                </div>
                <p className="mt-1 text-xs text-gray-500">{achievementPct}%</p>
                {achievementsRemaining > 0 && (
                  <a href="#featured-achievements" className="mt-1 inline-block text-xs text-amber-400 hover:underline">
                    {achievementsRemaining} remaining →
                  </a>
                )}
              </>
            ) : (
              <p className="mt-1 text-xs text-gray-500">No Main character set yet.</p>
            )}
          </div>

          {/* Account Achievements (formerly "Account Badges" - same system,
              just a clearer name shown to players; the underlying type/data
              naming is untouched). */}
          <div className="rounded border border-neutral-700 bg-neutral-900 p-3">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-amber-400/70">Account Achievements</p>
            <p className="mt-1 text-xl font-bold text-white">
              {accountBadges.length} / {accountBadgeTotal}
            </p>
            <div className="mt-2 h-2 w-full overflow-hidden rounded-full bg-neutral-700">
              <div className="h-full rounded-full bg-yellow-500" style={{ width: `${accountBadgePct}%` }} />
            </div>
            <p className="mt-1 text-xs text-gray-500">{accountBadgePct}%</p>
            <a href="#account-achievements" className="mt-1 inline-block text-xs text-amber-400 hover:underline">
              View All →
            </a>
          </div>

          {/* Legacy Challenges */}
          <div className="rounded border border-neutral-700 bg-neutral-900 p-3">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-amber-400/70">Legacy Challenges</p>
            <p className="mt-1 text-xl font-bold text-white">{legacyPoints} / 65</p>
            <div className="mt-2 h-2 w-full overflow-hidden rounded-full bg-neutral-700">
              <div className="h-full rounded-full bg-green-600" style={{ width: `${legacyPct}%` }} />
            </div>
            <p className="mt-1 text-xs text-gray-500">{legacyPct}%</p>
            <Link href="/legacy" className="mt-1 inline-block text-xs text-amber-400 hover:underline">
              View All →
            </Link>
          </div>

          {/* Total Playtime */}
          <div className="rounded border border-neutral-700 bg-neutral-900 p-3">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-amber-400/70">Total Playtime</p>
            <p className="mt-1 text-xl font-bold text-amber-300">
              {playHours}h {playMinutes}m
            </p>
            {totalHours > 0 && (
              <>
                <div className="mt-2 flex h-2 overflow-hidden rounded-full bg-neutral-700">
                  {playtimeByCharacter.map((c, i) => (
                    <div
                      key={c.id}
                      className="h-full"
                      style={{ width: `${c.pct}%`, backgroundColor: PLAYTIME_COLORS[i % PLAYTIME_COLORS.length] }}
                    />
                  ))}
                </div>
                <div className="mt-1.5 flex flex-col gap-0.5">
                  {playtimeByCharacter.map((c, i) => {
                    const h = Math.floor(c.hours);
                    const m = Math.round((c.hours - h) * 60);
                    return (
                      <div key={c.id} className="flex items-center gap-1 text-[11px] text-gray-500">
                        <span
                          className="h-1.5 w-1.5 shrink-0 rounded-full"
                          style={{ backgroundColor: PLAYTIME_COLORS[i % PLAYTIME_COLORS.length] }}
                        />
                        <span className="truncate">
                          {c.name} {h}h {m}m ({c.pct}%)
                        </span>
                      </div>
                    );
                  })}
                </div>
              </>
            )}
          </div>
        </div>
      </div>

      {/* CONTINUE YOUR JOURNEY - the closest milestone in each of the three
          progression systems, generated from real progress each time
          (never hardcoded placeholders) - falls back to a "complete" state
          per card once there's genuinely nothing left to chase. */}
      <div className="mt-4 rounded-md border border-neutral-700 bg-neutral-800 p-4">
        <h2 className="text-lg">Continue Your Journey</h2>
        <p className="mt-1 text-sm text-gray-400">Closest milestones across your account.</p>

        <div className="mt-3 grid grid-cols-1 gap-3 lg:grid-cols-3">
          {/* Main Character Achievements goal - owner is always
              mainCharacter now (not itemOwner, which maps the account-wide
              MERGED view's owners - not what this card tracks anymore). */}
          <div className="rounded border border-neutral-700 bg-neutral-900 p-3">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-amber-400/70">
              Main Character Achievements
            </p>
            {!mainCharacter ? (
              <p className="mt-1 text-sm text-gray-400">Set a Main character to track this.</p>
            ) : achievementsRemaining > 0 ? (
              <>
                <p className="mt-1 text-sm font-semibold text-white">{achievementsRemaining} remaining</p>
                <p className="mt-0.5 text-xs text-gray-400">
                  {mainCharacter.name} has discovered {earnedCount} of {totalCount} character achievements.
                </p>
                {closestUnearnedAchievement && (
                  <Link
                    href={`/character/${mainCharacter.id}/achievements#${closestUnearnedAchievement.key}`}
                    className="mt-2 flex items-center gap-2 rounded border border-neutral-700 bg-neutral-950/60 p-2 hover:border-amber-500/60"
                  >
                    <span className="relative h-9 w-9 shrink-0 overflow-hidden rounded-sm">
                      {closestUnearnedAchievement.localIcon ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={localBadgeIconSrc(closestUnearnedAchievement.localIcon)}
                          alt=""
                          draggable={false}
                          className="h-full w-full object-cover opacity-70 grayscale"
                        />
                      ) : (
                        <BadgePlaceholder tier={null} label={closestUnearnedAchievement.name} size={36} />
                      )}
                    </span>
                    <span className="min-w-0">
                      <span className="block truncate text-xs font-semibold text-white">
                        {closestUnearnedAchievement.name}
                      </span>
                      {closestUnearnedAchievement.value !== null && closestUnearnedAchievement.nextThreshold !== null && (
                        <span className="block text-[11px] text-gray-500">
                          {closestUnearnedAchievement.value.toLocaleString()} /{" "}
                          {closestUnearnedAchievement.nextThreshold.toLocaleString()}
                        </span>
                      )}
                    </span>
                  </Link>
                )}
              </>
            ) : (
              <p className="mt-1 text-sm text-gray-400">{mainCharacter.name} has earned every character achievement!</p>
            )}
          </div>

          {/* Account Achievement goal */}
          <div className="rounded border border-neutral-700 bg-neutral-900 p-3">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-amber-400/70">Account Achievement</p>
            {closestAccountBadge ? (
              <Link href="#account-achievements" className="mt-1 flex items-center gap-2 hover:opacity-90">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={accountBadgeIconSrc(closestAccountBadge.kind, iconOverrides)}
                  alt=""
                  className="h-9 w-9 shrink-0 rounded-sm border border-amber-900/70"
                />
                <span className="min-w-0">
                  <span className="block truncate text-sm font-semibold text-white">
                    {ACCOUNT_ACHIEVEMENT_BADGES[closestAccountBadge.kind].label.split(" - ")[0]}
                  </span>
                  <span className="block text-[11px] text-gray-500">
                    {closestAccountBadge.value.toLocaleString()} / {closestAccountBadge.target.toLocaleString()}
                  </span>
                </span>
              </Link>
            ) : (
              <p className="mt-1 text-sm text-gray-400">Every account achievement has been earned!</p>
            )}
            {closestAccountBadge && (
              <div className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-neutral-800">
                <div
                  className="h-full rounded-full bg-[#c9a566]"
                  style={{
                    width: `${Math.min(100, Math.round((closestAccountBadge.value / closestAccountBadge.target) * 100))}%`,
                  }}
                />
              </div>
            )}
          </div>

          {/* Legacy Challenges goal - a simple two-state nudge (just
              starting vs. already underway) rather than naming a specific
              next achievement, since the data this page loads is the
              65-point aggregate only (legacyEarned/legacyPoints), not the
              individual Legacy Challenge rows themselves - /legacy already
              covers that level of detail. */}
          <div className="rounded border border-neutral-700 bg-neutral-900 p-3">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-amber-400/70">Legacy Challenges</p>
            <Link href="/legacy" className="mt-1 flex items-center gap-2 hover:opacity-90">
              <span className="h-9 w-9 shrink-0">
                <FamilyTileIcon family="legacy" />
              </span>
              <span>
                <span className="block text-sm font-semibold text-white">
                  {legacyPoints === 0 ? "Begin your legacy" : "Keep going"}
                </span>
                <span className="block text-[11px] text-gray-500">{legacyPoints} of 65 Legacy Points</span>
              </span>
            </Link>
            <div className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-neutral-800">
              <div className="h-full rounded-full bg-green-600" style={{ width: `${legacyPct}%` }} />
            </div>
          </div>
        </div>
      </div>

      {/* SHOWCASE - full width, directly under Continue Your Journey. This
          is the real, owner-picked Favourite Character/Statistic/
          Achievement/Item system (see AccountShowcase.tsx) - deliberately
          NOT swapped out for generated stats like "Highest Level" or "Most
          Honorable Kills" (an earlier mockup of this layout did that by
          mistake; Jordan's call was explicitly to keep the real pick-your-
          own system here, it's the more interesting of the two). */}
      <div className="mt-4">
        <AccountShowcase
          favoriteCharacter={favoriteCharacter}
          favoriteStatistic={favoriteStatistic}
          favoriteAchievement={favoriteAchievement}
          favoriteItem={favoriteItem}
          iconOverrides={iconOverrides}
          onEdit={onEditShowcase}
        />
      </div>

      {/* Two-column area: Characters + Recent Achievements on the left,
          Featured Character Achievements + Account Achievements on the
          right. */}
      <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-2">
        {/* Left column */}
        <div className="flex flex-col gap-4">
          <div id="characters-section" className="scroll-mt-4 rounded-md border border-neutral-700 bg-neutral-800 p-4">
            <h2 className="text-lg">Characters ({characters.length})</h2>
            <div className="mt-2 flex flex-col gap-1.5">
              {characters
                .slice()
                .sort((a, b) => b.level - a.level)
                .map((c) => (
                  <Link
                    key={c.id}
                    href={`/character/${c.id}`}
                    className="character-card flex items-center justify-between rounded border border-neutral-700 bg-neutral-900 px-3 py-2 text-sm"
                  >
                    <span>
                      {c.name}
                      {c.character_type === "Main" && <span className="ml-1 text-[10px] text-amber-400">★ Main</span>}{" "}
                      <span className="text-gray-500">
                        Lv.{c.level} {c.race} {c.class}
                      </span>
                    </span>
                    <span className="text-xs text-gray-500">{(c.time_played_hours ?? 0).toLocaleString()}h</span>
                  </Link>
                ))}
              {characters.length === 0 && <p className="text-sm text-gray-500">No characters synced yet.</p>}
            </div>
          </div>

          <div className="rounded-md border border-neutral-700 bg-neutral-800 p-4">
            <h2 className="text-lg">Recent Achievements</h2>
            <div className="mt-2 flex flex-col gap-2">
              {recent.length === 0 && <p className="text-sm text-gray-500">Nothing earned yet.</p>}
              {recent.map((r, i) => (
                <Link
                  key={i}
                  href={`/character/${r.characterId}/achievements#${r.kind}`}
                  className="flex items-center justify-between rounded border border-neutral-700 bg-neutral-900 px-3 py-2 text-sm hover:border-amber-500/60"
                >
                  <span>
                    <span className="font-semibold text-amber-200">{r.characterName}</span> earned{" "}
                    <span className="text-white">{r.label}</span>
                    {r.tier && <span className="text-gray-400"> ({r.tier})</span>}
                  </span>
                  <span className="shrink-0 text-xs text-gray-500">{formatDate(r.earnedAt)}</span>
                </Link>
              ))}
            </div>
          </div>
        </div>

        {/* Right column */}
        <div className="flex flex-col gap-4">
          <div id="featured-achievements" className="scroll-mt-4 rounded-md border border-neutral-700 bg-neutral-800 p-4">
            <div className="flex items-start justify-between gap-2">
              <div>
                <h2 className="text-lg">Featured Main Character Achievements</h2>
                <p className="mt-1 text-xs text-gray-500">
                  {mainCharacter ? mainCharacter.name : "No Main character set"} - top achievements, plus
                  what&apos;s closest to unlocking. Manually choosing which ones show here is a planned follow-up
                  (needs a new column to store the pick).
                </p>
              </div>
              {/* 2026-10-03, "Clicking this achievements button should take
                  you to your main character achievements" - straight to the
                  real achievement browser/pinning page for whichever
                  character is Main, same page AchievementShowcase's own
                  "View Achievements" button already links to. */}
              {mainCharacter && (
                <Link
                  href={`/character/${mainCharacter.id}/achievements`}
                  className="shrink-0 rounded bg-blue-600 px-3 py-1.5 text-xs font-semibold text-white"
                >
                  Edit
                </Link>
              )}
            </div>
            {!mainCharacter ? (
              <p className="mt-2 text-sm text-gray-500">Set a Main character to feature their achievements here.</p>
            ) : (
              (() => {
                const earned = mainCharacterItems
                  .filter((i) => i.earned)
                  .sort((a, b) => {
                    if (b.points !== a.points) return b.points - a.points;
                    const ta = a.earnedAt ? new Date(a.earnedAt).getTime() : 0;
                    const tb = b.earnedAt ? new Date(b.earnedAt).getTime() : 0;
                    return tb - ta;
                  });
                const closeUnearned = mainCharacterItems
                  .filter((i) => !i.earned && i.tiered && i.value !== null && i.nextThreshold)
                  .sort(
                    (a, b) => (b.value as number) / (b.nextThreshold as number) - (a.value as number) / (a.nextThreshold as number)
                  );
                const featured = [...earned, ...closeUnearned].slice(0, 6);
                return featured.length === 0 ? (
                  <p className="mt-2 text-sm text-gray-500">Nothing earned yet.</p>
                ) : (
                  <div className="mt-3 flex flex-wrap gap-3">
                    {featured.map((item) => (
                      <ShowcaseBadge key={item.key} characterId={mainCharacter.id} item={item} dimmed={!item.earned} />
                    ))}
                  </div>
                );
              })()
            )}
          </div>

          {/* Account-wide badges - a genuinely separate system from the
              character achievements above (see lib/accountAchievements.ts),
              shown here as "Account Achievements" (its clearer player-facing
              name - same system, same data, same AccountBadgesGrid tiles as
              before). */}
          <div id="account-achievements" className="scroll-mt-4 rounded-md border border-neutral-700 bg-neutral-800 p-4">
            <h2 className="text-lg">
              Account Achievements ({accountBadges.length} / {accountBadgeTotal})
            </h2>
            <p className="mt-1 text-xs text-gray-500">
              Special achievements earned through major accomplishments across your entire roster.
            </p>
            <AccountBadgesGrid
              accountBadges={accountBadges}
              accountBadgeProgress={accountBadgeProgress}
              accountBadgeBreakdown={accountBadgeBreakdown}
              iconOverrides={iconOverrides}
            />
          </div>
        </div>
      </div>

      {/* Legacy Challenges already has its own top-level page - summarized
          here with a link out, not duplicated. */}
      <div className="mt-4 rounded-md border border-neutral-700 bg-neutral-800 p-4">
        <div className="flex items-center justify-between">
          <h2 className="text-lg">Legacy Challenges</h2>
          <Link href="/legacy" className="text-xs text-amber-400 hover:underline">
            View all →
          </Link>
        </div>
        <p className="mt-1 text-sm text-gray-400">
          {legacyEarned} completed · {legacyPoints} / 65 Legacy Points
        </p>
      </div>
    </main>
  );
}
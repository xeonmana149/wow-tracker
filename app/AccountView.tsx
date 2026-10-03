import type { ReactNode } from "react";
import Link from "next/link";
import { ShowcaseBadge } from "./AchievementShowcase";
import AccountBadgesGrid from "./AccountBadgesGrid";
import FamilyTileIcon from "./FamilyTileIcon";
import { FAMILY_META, type AchievementFamily } from "../lib/achievements";
import { RACE_FACTION } from "../lib/options";
import { ACCOUNT_ACHIEVEMENT_BADGES } from "../lib/accountAchievements";
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

export function AccountView({
  data,
  headerActions,
  belowHeader,
}: {
  data: AccountViewData;
  headerActions?: ReactNode;
  belowHeader?: ReactNode;
}) {
  const {
    displayName,
    memberSince,
    avatarIcon,
    bannerStyle,
    motto,
    characters,
    mergedItems,
    itemOwner,
    recent,
    accountBadges,
    accountBadgeProgress,
    accountBadgeBreakdown,
    legacyEarned,
    legacyPoints,
    iconOverrides,
  } = data;

  const earnedCount = mergedItems.filter((i) => i.earned).length;
  const totalCount = mergedItems.length;
  const progressPct = totalCount > 0 ? Math.round((earnedCount / totalCount) * 100) : 0;

  const categories = (() => {
    const map = new Map<AchievementFamily, { earned: number; total: number }>();
    for (const item of mergedItems) {
      const entry = map.get(item.family) ?? { earned: 0, total: 0 };
      entry.total += 1;
      if (item.earned) entry.earned += 1;
      map.set(item.family, entry);
    }
    return Array.from(map.entries());
  })();

  const totalHours = characters.reduce((sum, c) => sum + (c.time_played_hours ?? 0), 0);
  const hordeHours = characters
    .filter((c) => RACE_FACTION[c.race] === "Horde")
    .reduce((sum, c) => sum + (c.time_played_hours ?? 0), 0);
  const allianceHours = characters
    .filter((c) => RACE_FACTION[c.race] === "Alliance")
    .reduce((sum, c) => sum + (c.time_played_hours ?? 0), 0);
  const hordePct = totalHours > 0 ? Math.round((hordeHours / totalHours) * 100) : 0;
  const alliancePct = totalHours > 0 ? Math.round((allianceHours / totalHours) * 100) : 0;

  const featured = (() => {
    const earned = mergedItems
      .filter((i) => i.earned)
      .sort((a, b) => {
        if (b.points !== a.points) return b.points - a.points;
        const ta = a.earnedAt ? new Date(a.earnedAt).getTime() : 0;
        const tb = b.earnedAt ? new Date(b.earnedAt).getTime() : 0;
        return tb - ta;
      });
    const closeUnearned = mergedItems
      .filter((i) => !i.earned && i.tiered && i.value !== null && i.nextThreshold)
      .sort((a, b) => (b.value as number) / (b.nextThreshold as number) - (a.value as number) / (a.nextThreshold as number));
    return [...earned, ...closeUnearned].slice(0, 6);
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

      {/* Only Overview is built - the rest are staged follow-ups rather than
          dead links or empty promises. */}
      <div className="mt-4 flex flex-wrap gap-2">
        <span className="tab-btn tab-btn-active">Overview</span>
        <span className="tab-btn cursor-not-allowed opacity-50" title="Coming soon">
          Achievements
        </span>
        <span className="tab-btn cursor-not-allowed opacity-50" title="Coming soon">
          Statistics
        </span>
        <span className="tab-btn cursor-not-allowed opacity-50" title="Coming soon">
          Activity
        </span>
        <span className="tab-btn cursor-not-allowed opacity-50" title="Coming soon">
          Settings
        </span>
      </div>

      <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-3">
        {/* Account Progress */}
        <div className="rounded-md border border-neutral-700 bg-neutral-800 p-4 lg:col-span-2">
          <h2 className="text-lg">Account Progress</h2>
          <p className="mt-1 text-sm text-gray-400">
            {earnedCount} / {totalCount} character achievements unlocked account-wide (highest tier any one character
            has reached, not summed across characters)
          </p>
          <div className="mt-2 h-2.5 w-full overflow-hidden rounded-full bg-neutral-700">
            <div className="h-full rounded-full bg-yellow-500" style={{ width: `${progressPct}%` }} />
          </div>

          <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
            {categories.map(([family, { earned, total }]) => (
              <div key={family} className="rounded border border-neutral-700 bg-neutral-900 p-2 text-center">
                <div className="text-lg">
                  <FamilyTileIcon family={family} />
                </div>
                <div className="text-xs text-gray-300">{FAMILY_META[family].label}</div>
                <div className="text-xs text-gray-500">
                  {earned} / {total}
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Playtime */}
        <div className="rounded-md border border-neutral-700 bg-neutral-800 p-4">
          <h2 className="text-lg">Playtime</h2>
          <p className="mt-1 text-3xl font-bold text-amber-300">{totalHours.toLocaleString()}h</p>
          <p className="text-xs text-gray-500">Total time played, across all characters</p>
          {totalHours > 0 && (hordeHours > 0 || allianceHours > 0) && (
            <div className="mt-3">
              <div className="flex h-2 overflow-hidden rounded-full bg-neutral-700">
                <div className="h-full bg-red-600" style={{ width: `${hordePct}%` }} />
                <div className="h-full bg-blue-500" style={{ width: `${alliancePct}%` }} />
              </div>
              <div className="mt-1 flex justify-between text-[11px] text-gray-500">
                <span>
                  Horde {hordeHours.toLocaleString()}h ({hordePct}%)
                </span>
                <span>
                  Alliance {allianceHours.toLocaleString()}h ({alliancePct}%)
                </span>
              </div>
            </div>
          )}
        </div>
      </div>

      <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-3">
        {/* Characters */}
        <div className="rounded-md border border-neutral-700 bg-neutral-800 p-4">
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

        {/* Featured Achievements */}
        <div className="rounded-md border border-neutral-700 bg-neutral-800 p-4 lg:col-span-2">
          <h2 className="text-lg">Featured Achievements</h2>
          <p className="mt-1 text-xs text-gray-500">
            Automatically picked - top achievements, plus what&apos;s closest to unlocking. Manually choosing which
            ones show here is a planned follow-up (needs a new column to store the pick).
          </p>
          {featured.length === 0 ? (
            <p className="mt-2 text-sm text-gray-500">Nothing earned yet.</p>
          ) : (
            <div className="mt-3 flex flex-wrap gap-3">
              {featured.map((item) => (
                <ShowcaseBadge
                  key={item.key}
                  characterId={itemOwner.get(item.key) ?? characters[0]?.id ?? ""}
                  item={item}
                  dimmed={!item.earned}
                />
              ))}
            </div>
          )}
        </div>
      </div>

      <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-2">
        {/* Recent Achievements */}
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

        {/* Account-wide badges - a genuinely separate system from the
            character achievements above (see lib/accountAchievements.ts) -
            shown in its own section rather than folded into the counts/
            categories above. */}
        <div className="rounded-md border border-neutral-700 bg-neutral-800 p-4">
          <h2 className="text-lg">
            Account Badges ({accountBadges.length} / {Object.keys(ACCOUNT_ACHIEVEMENT_BADGES).length})
          </h2>
          <p className="mt-1 text-xs text-gray-500">
            Earned by looking across the whole roster at once (e.g. one of every class at max level) - distinct from
            the per-character achievements above.
          </p>
          {/* 2026-09-30, Jordan: "the account badges system needs to the
              icon styles to look like character achievements just maybe
              without the border", then "now I want the hover system that
              achievements get ... implement for account badges" - each
              tile is AccountBadgeTile, giving the same hover-to-enlarge
              card ShowcaseBadge uses for character achievements. Every
              badge (local custom art included) gets the shared ornate
              frame - Jordan's call, "no I want the ornate frame ... just
              scaled properly" (see lib/badgeFrames.ts's
              ACCOUNT_BADGE_FRAME_*).
              AccountBadgesGrid (its own "use client" component, since this
              component has no hooks/state on purpose - see this file's own
              header comment) owns which single tile is pinned open at a
              time (2026-10-03, "shouldn't be able to open multiple
              breakdowns ... should close the other"). */}
          <AccountBadgesGrid
            accountBadges={accountBadges}
            accountBadgeProgress={accountBadgeProgress}
            accountBadgeBreakdown={accountBadgeBreakdown}
            iconOverrides={iconOverrides}
          />
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
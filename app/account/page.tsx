"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { supabase } from "../../lib/supabase";
import { buildAchievementItems, type AchievementBoardItem } from "../achievementBoard";
import { ShowcaseBadge } from "../AchievementShowcase";
import {
  TIERED_ACHIEVEMENT_KINDS,
  tierLabel,
  FAMILY_META,
  type AchievementTier,
  type TieredAchievementKind,
  type AchievementFamily,
} from "../../lib/achievements";
import { FLAT_ACHIEVEMENT_NAME } from "../../lib/achievementCategories";
import { RACE_FACTION } from "../../lib/options";
import { ACCOUNT_ACHIEVEMENT_BADGES, type AccountAchievementKind } from "../../lib/accountAchievements";
import { wowIconUrl } from "../../lib/icons";
import {
  AVATAR_ICON_OPTIONS,
  BANNER_STYLE_OPTIONS,
  avatarIconSrc,
  bannerImageSrc,
  findAvatarIconOption,
  findBannerOption,
  bannerClassName,
  MOTTO_MAX_LENGTH,
} from "../../lib/profileCustomization";

// Account Overview (2026-09-28 layout rework, Stage 3) - the account-wide
// page the reference screenshot called for. Deliberately reuses real
// machinery rather than inventing a parallel display system:
//  - buildAchievementItems() is the SAME function the character page uses
//    for its own achievement board, called once per character and merged
//    here (see mergeAccountItems below) rather than re-deriving thresholds/
//    labels/icons a second time.
//  - ShowcaseBadge is the exact tile component the character page's
//    trophy-cabinet strip already uses (exported from AchievementShowcase.tsx
//    for this purpose).
//  - Account-wide badges (Class Collector, Tycoon, etc.) are a genuinely
//    separate system (lib/accountAchievements.ts) and are shown in their
//    own section rather than folded into the character-achievement counts
//    above them, per the "these are two distinct systems" instruction.
//  - Legacy Challenges already has its own top-level page (/legacy) - this
//    just summarizes and links out, rather than duplicating that page.
//
// Only the Overview tab is built so far (Stage 3); Achievements/Statistics/
// Activity/Settings are staged follow-ups (Stage 5 in the original doc),
// shown as disabled tabs rather than dead links or empty promises.

type CharacterRow = {
  id: string;
  name: string;
  level: number;
  class: string;
  race: string;
  character_type: string;
  time_played_hours: number | null;
  money_copper: number | null;
};

type AchievementRowDB = { character_id: string; kind: string; tier: AchievementTier | null; earned_at: string | null };
type StatRow = { character_id: string; category: string; name: string; value: string };
type ProfessionRow = { character_id: string; recipes: unknown[] | null };
type LegacyRow = { completed: boolean; ui_points: number | null };

type RecentAchievement = {
  characterId: string;
  characterName: string;
  kind: string;
  tier: AchievementTier | null;
  earnedAt: string;
  label: string;
};

const TIERED_SET = new Set<string>(TIERED_ACHIEVEMENT_KINDS);

function labelFor(kind: string): string {
  if (TIERED_SET.has(kind)) return tierLabel(kind as TieredAchievementKind);
  return FLAT_ACHIEVEMENT_NAME[kind as keyof typeof FLAT_ACHIEVEMENT_NAME] ?? kind;
}

// Rolls per-character AchievementBoardItem[] arrays up into one account-wide
// view: earned if ANY character has earned it, keeping whichever character's
// copy has the highest points (i.e. the highest tier reached) rather than
// summing across characters - "unique collections should avoid counting
// duplicates" per the layout doc. ownerByKey remembers which character each
// merged item actually came from, so Featured Achievements can link to a
// character page where that achievement/progress genuinely exists.
function mergeAccountItems(
  perCharacter: { characterId: string; items: AchievementBoardItem[] }[]
): { items: AchievementBoardItem[]; ownerByKey: Map<string, string> } {
  const byKey = new Map<string, AchievementBoardItem>();
  const ownerByKey = new Map<string, string>();
  for (const { characterId, items } of perCharacter) {
    for (const item of items) {
      const existing = byKey.get(item.key);
      if (!existing) {
        byKey.set(item.key, item);
        ownerByKey.set(item.key, characterId);
        continue;
      }
      const existingRatio =
        !existing.earned && existing.tiered && existing.nextThreshold
          ? (existing.value ?? 0) / existing.nextThreshold
          : -1;
      const ratio =
        !item.earned && item.tiered && item.nextThreshold ? (item.value ?? 0) / item.nextThreshold : -1;
      const better =
        item.points > existing.points || (item.points === existing.points && !item.earned && ratio > existingRatio);
      if (better) {
        byKey.set(item.key, item);
        ownerByKey.set(item.key, characterId);
      }
    }
  }
  return { items: Array.from(byKey.values()), ownerByKey };
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}

export default function AccountOverviewPage() {
  const [loading, setLoading] = useState(true);
  const [signedIn, setSignedIn] = useState(false);
  const [userId, setUserId] = useState<string | null>(null);
  const [displayName, setDisplayName] = useState<string>("");
  const [memberSince, setMemberSince] = useState<string | null>(null);
  const [avatarIcon, setAvatarIcon] = useState<string | null>(null);
  const [bannerStyle, setBannerStyle] = useState<string | null>(null);
  const [motto, setMotto] = useState<string | null>(null);

  // Edit Profile panel (2026-09-29, Jordan's request; extended same day to
  // add display-name editing, then switched same day from pasted image URLs
  // to a fixed picker - "like with achievements im gonna make custom art for
  // those things that website users can choose between", see
  // lib/profileCustomization.ts) - draft values are separate from the saved
  // ones above so Cancel can discard changes without a refetch, and so the
  // header updates immediately on Save without waiting on a round trip.
  const [editingProfile, setEditingProfile] = useState(false);
  const [savingProfile, setSavingProfile] = useState(false);
  const [profileSaveError, setProfileSaveError] = useState<string | null>(null);
  const [draftDisplayName, setDraftDisplayName] = useState("");
  const [draftAvatarIcon, setDraftAvatarIcon] = useState<string | null>(null);
  const [draftBannerStyle, setDraftBannerStyle] = useState<string | null>("parchment");
  const [draftMotto, setDraftMotto] = useState("");
  const [characters, setCharacters] = useState<CharacterRow[]>([]);
  const [mergedItems, setMergedItems] = useState<AchievementBoardItem[]>([]);
  const [itemOwner, setItemOwner] = useState<Map<string, string>>(new Map());
  const [recent, setRecent] = useState<RecentAchievement[]>([]);
  const [accountBadges, setAccountBadges] = useState<AccountAchievementKind[]>([]);
  const [legacyEarned, setLegacyEarned] = useState(0);
  const [legacyPoints, setLegacyPoints] = useState(0);

  useEffect(() => {
    async function load() {
      const { data: userData } = await supabase.auth.getUser();
      if (!userData.user) {
        setSignedIn(false);
        setLoading(false);
        return;
      }
      setSignedIn(true);
      const userId = userData.user.id;
      setUserId(userId);
      setMemberSince(userData.user.created_at ?? null);

      const [{ data: profileRow }, { data: characterRows }, { data: accountAchievementRows }, { data: legacyRows }] =
        await Promise.all([
          supabase
            .from("profiles")
            .select("display_name, avatar_icon, banner_style, motto")
            .eq("id", userId)
            .maybeSingle(),
          supabase
            .from("characters")
            .select("id, name, level, class, race, character_type, time_played_hours, money_copper")
            .eq("user_id", userId),
          supabase.from("account_achievements").select("kind").eq("user_id", userId),
          supabase.from("account_legacy_achievements").select("completed, ui_points").eq("user_id", userId),
        ]);

      const resolvedName = profileRow?.display_name ?? "Adventurer";
      setDisplayName(resolvedName);
      setAvatarIcon(profileRow?.avatar_icon ?? null);
      setBannerStyle(profileRow?.banner_style ?? null);
      setMotto(profileRow?.motto ?? null);
      setDraftDisplayName(resolvedName);
      setDraftAvatarIcon(profileRow?.avatar_icon ?? null);
      setDraftBannerStyle(profileRow?.banner_style ?? "parchment");
      setDraftMotto(profileRow?.motto ?? "");
      setAccountBadges(((accountAchievementRows ?? []) as { kind: AccountAchievementKind }[]).map((r) => r.kind));

      const legacy = (legacyRows ?? []) as LegacyRow[];
      setLegacyEarned(legacy.filter((r) => r.completed).length);
      setLegacyPoints(legacy.filter((r) => r.completed).reduce((sum, r) => sum + (r.ui_points ?? 0), 0));

      const chars = (characterRows ?? []) as CharacterRow[];
      setCharacters(chars);
      const characterIds = chars.map((c) => c.id);

      if (characterIds.length === 0) {
        setMergedItems([]);
        setRecent([]);
        setLoading(false);
        return;
      }

      const [{ data: achievementRows }, { data: statRows }, { data: professionRows }] = await Promise.all([
        supabase.from("achievements").select("character_id, kind, tier, earned_at").in("character_id", characterIds),
        supabase
          .from("character_statistics")
          .select("character_id, category, name, value")
          .in("character_id", characterIds),
        supabase.from("character_professions").select("character_id, recipes").in("character_id", characterIds),
      ]);

      const achRows = (achievementRows ?? []) as AchievementRowDB[];
      const stRows = (statRows ?? []) as StatRow[];
      const profRows = (professionRows ?? []) as ProfessionRow[];

      const achByChar = new Map<string, AchievementRowDB[]>();
      for (const a of achRows) {
        const list = achByChar.get(a.character_id) ?? [];
        list.push(a);
        achByChar.set(a.character_id, list);
      }
      const statsByChar = new Map<string, StatRow[]>();
      for (const s of stRows) {
        const list = statsByChar.get(s.character_id) ?? [];
        list.push(s);
        statsByChar.set(s.character_id, list);
      }
      const recipesByChar = new Map<string, number>();
      for (const p of profRows) {
        const count = Array.isArray(p.recipes) ? p.recipes.length : 0;
        recipesByChar.set(p.character_id, (recipesByChar.get(p.character_id) ?? 0) + count);
      }

      const perCharacterItems = chars.map((c) => ({
        characterId: c.id,
        items: buildAchievementItems({
          achievementRows: achByChar.get(c.id) ?? [],
          statRows: statsByChar.get(c.id) ?? [],
          recipesCount: recipesByChar.get(c.id) ?? 0,
          hoursPlayed: c.time_played_hours ?? 0,
        }),
      }));
      const { items, ownerByKey } = mergeAccountItems(perCharacterItems);
      setMergedItems(items);
      setItemOwner(ownerByKey);

      const charName = new Map(chars.map((c) => [c.id, c.name]));
      const recentList: RecentAchievement[] = achRows
        .filter((a) => !!a.earned_at)
        .sort((a, b) => new Date(b.earned_at as string).getTime() - new Date(a.earned_at as string).getTime())
        .slice(0, 8)
        .map((a) => ({
          characterId: a.character_id,
          characterName: charName.get(a.character_id) ?? "Unknown",
          kind: a.kind,
          tier: a.tier,
          earnedAt: a.earned_at as string,
          label: labelFor(a.kind),
        }));
      setRecent(recentList);

      setLoading(false);
    }
    load();
  }, []);

  function openEditProfile() {
    setDraftDisplayName(displayName);
    setDraftAvatarIcon(avatarIcon);
    setDraftBannerStyle(bannerStyle ?? "parchment");
    setDraftMotto(motto ?? "");
    setProfileSaveError(null);
    setEditingProfile(true);
  }

  async function saveProfile() {
    if (!userId) return;
    const trimmedName = draftDisplayName.trim();
    if (trimmedName.length === 0) {
      setProfileSaveError("Display name can't be empty.");
      return;
    }
    setSavingProfile(true);
    setProfileSaveError(null);
    const trimmedMotto = draftMotto.trim().slice(0, MOTTO_MAX_LENGTH);
    const { error } = await supabase
      .from("profiles")
      .update({
        display_name: trimmedName,
        avatar_icon: draftAvatarIcon,
        banner_style: draftBannerStyle,
        motto: trimmedMotto.length > 0 ? trimmedMotto : null,
      })
      .eq("id", userId);
    setSavingProfile(false);
    if (error) {
      setProfileSaveError(error.message);
      return;
    }
    setDisplayName(trimmedName);
    setAvatarIcon(draftAvatarIcon);
    setBannerStyle(draftBannerStyle);
    setMotto(trimmedMotto.length > 0 ? trimmedMotto : null);
    setEditingProfile(false);
  }

  const earnedCount = mergedItems.filter((i) => i.earned).length;
  const totalCount = mergedItems.length;
  const progressPct = totalCount > 0 ? Math.round((earnedCount / totalCount) * 100) : 0;

  const categories = useMemo(() => {
    const map = new Map<AchievementFamily, { earned: number; total: number }>();
    for (const item of mergedItems) {
      const entry = map.get(item.family) ?? { earned: 0, total: 0 };
      entry.total += 1;
      if (item.earned) entry.earned += 1;
      map.set(item.family, entry);
    }
    return Array.from(map.entries());
  }, [mergedItems]);

  const totalHours = characters.reduce((sum, c) => sum + (c.time_played_hours ?? 0), 0);
  const hordeHours = characters
    .filter((c) => RACE_FACTION[c.race] === "Horde")
    .reduce((sum, c) => sum + (c.time_played_hours ?? 0), 0);
  const allianceHours = characters
    .filter((c) => RACE_FACTION[c.race] === "Alliance")
    .reduce((sum, c) => sum + (c.time_played_hours ?? 0), 0);
  const hordePct = totalHours > 0 ? Math.round((hordeHours / totalHours) * 100) : 0;
  const alliancePct = totalHours > 0 ? Math.round((allianceHours / totalHours) * 100) : 0;

  const featured = useMemo(() => {
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
  }, [mergedItems]);

  if (loading) {
    return <main className="mx-auto max-w-6xl p-4 text-white md:p-6">Loading account...</main>;
  }

  if (!signedIn) {
    return (
      <main className="mx-auto max-w-6xl p-4 text-white md:p-6">
        <h1 className="text-3xl font-bold">Account</h1>
        <p className="mt-4 text-sm text-gray-400">
          <Link href="/login" className="text-amber-400 hover:underline">
            Sign in
          </Link>{" "}
          to see your account overview.
        </p>
      </main>
    );
  }

  return (
    <main className="mx-auto max-w-6xl p-4 text-white md:p-6">
      {/* Profile header - a real "member since" from the auth account's own
          created_at (always present, unlike anything on `profiles`), a
          crest showing the chosen avatar option's art (falling back to the
          lettered .crest-fallback when none is picked), and a banner that's
          either a custom-art option (rendered via .profile-banner-custom
          with a readability overlay) or one of the named gradient presets -
          see lib/profileCustomization.ts for how options resolve to art.
          `.account-banner` gives this a real, fixed height (300px desktop /
          180px mobile, see theme.css) - previously this box was only ever
          as tall as the crest+padding (~140px), so any banner art sized to
          the recommended 1200x300 ratio was getting cropped far more than
          intended. */}
      {(() => {
        const avatarOption = findAvatarIconOption(avatarIcon);
        const bannerOption = findBannerOption(bannerStyle);
        const bannerImgSrc = bannerImageSrc(bannerOption);
        return (
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
              <div className="hero-actions">
                <button
                  type="button"
                  onClick={openEditProfile}
                  className="rounded bg-blue-600 px-3 py-1.5 text-sm font-semibold"
                >
                  Edit Profile
                </button>
              </div>
            </div>
          </div>
        );
      })()}

      {/* Edit Profile panel - opens inline right under the header rather than
          a modal, so it reads as part of the same page. */}
      {editingProfile && (
        <div className="mt-4 rounded-md border border-neutral-700 bg-neutral-800 p-4">
          <h2 className="text-lg">Edit Profile</h2>

          <div className="mt-3">
            <label className="text-sm text-gray-300" htmlFor="display-name-input">
              Display name
            </label>
            <input
              id="display-name-input"
              type="text"
              value={draftDisplayName}
              onChange={(e) => setDraftDisplayName(e.target.value)}
              maxLength={40}
              className="mt-1 w-full max-w-sm rounded border border-neutral-700 bg-neutral-900 p-2 text-sm text-white"
            />
          </div>

          <div className="mt-4">
            <p className="text-sm text-gray-300">Account icon</p>
            <div className="mt-2 flex flex-wrap gap-2">
              <button
                type="button"
                onClick={() => setDraftAvatarIcon(null)}
                className={`flex h-12 w-12 items-center justify-center rounded border text-[10px] text-gray-400 ${
                  draftAvatarIcon === null ? "border-amber-400" : "border-neutral-700"
                }`}
                title="No icon (use initial)"
              >
                {displayName.charAt(0).toUpperCase()}
              </button>
              {AVATAR_ICON_OPTIONS.map((icon) => (
                <button
                  key={icon.key}
                  type="button"
                  onClick={() => setDraftAvatarIcon(icon.key)}
                  className={`h-12 w-12 overflow-hidden rounded border ${
                    draftAvatarIcon === icon.key ? "border-amber-400" : "border-neutral-700"
                  }`}
                  title={icon.label}
                >
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={avatarIconSrc(icon)} alt="" className="h-full w-full" />
                </button>
              ))}
            </div>
          </div>

          <div className="mt-4">
            <p className="text-sm text-gray-300">Banner</p>
            <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-3">
              {BANNER_STYLE_OPTIONS.map((opt) => {
                const swatchImgSrc = bannerImageSrc(opt);
                return (
                  <button
                    key={opt.key}
                    type="button"
                    onClick={() => setDraftBannerStyle(opt.key)}
                    className={`banner-swatch ${bannerClassName(opt.key)} ${
                      draftBannerStyle === opt.key ? "banner-swatch-active" : ""
                    }`}
                    style={
                      swatchImgSrc
                        ? { backgroundImage: `url(${swatchImgSrc})`, backgroundSize: "cover", backgroundPosition: "center" }
                        : undefined
                    }
                  >
                    <span className="text-xs">{opt.label}</span>
                  </button>
                );
              })}
            </div>
          </div>

          <div className="mt-4">
            <label className="text-sm text-gray-300" htmlFor="motto-input">
              Motto
            </label>
            <textarea
              id="motto-input"
              value={draftMotto}
              onChange={(e) => setDraftMotto(e.target.value.slice(0, MOTTO_MAX_LENGTH))}
              rows={2}
              placeholder="Say something about yourself..."
              className="mt-1 w-full rounded border border-neutral-700 bg-neutral-900 p-2 text-sm text-white"
            />
            <p className="mt-1 text-right text-xs text-gray-500">
              {draftMotto.length} / {MOTTO_MAX_LENGTH}
            </p>
          </div>

          {profileSaveError && <p className="mt-2 text-sm text-red-400">{profileSaveError}</p>}

          <div className="hero-actions mt-4 flex gap-2">
            <button
              type="button"
              onClick={saveProfile}
              disabled={savingProfile}
              className="rounded bg-blue-600 px-3 py-1.5 text-sm font-semibold disabled:opacity-50"
            >
              {savingProfile ? "Saving..." : "Save"}
            </button>
            <button
              type="button"
              onClick={() => setEditingProfile(false)}
              disabled={savingProfile}
              className="rounded bg-red-700 px-3 py-1.5 text-sm font-semibold disabled:opacity-50"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

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
                <div className="text-lg">{FAMILY_META[family].icon}</div>
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
            Automatically picked - your top achievements, plus what&apos;s closest to unlocking. Manually choosing
            which ones show here is a planned follow-up (needs a new column to store the pick).
          </p>
          {featured.length === 0 ? (
            <p className="mt-2 text-sm text-gray-500">Nothing earned yet - sync a character to get started.</p>
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
            categories above, per "these are two distinct systems". */}
        <div className="rounded-md border border-neutral-700 bg-neutral-800 p-4">
          <h2 className="text-lg">
            Account Badges ({accountBadges.length} / {Object.keys(ACCOUNT_ACHIEVEMENT_BADGES).length})
          </h2>
          <p className="mt-1 text-xs text-gray-500">
            Earned by looking across your whole roster at once (e.g. one of every class at max level) - distinct
            from the per-character achievements above.
          </p>
          <div className="mt-2 flex flex-wrap gap-2">
            {(Object.keys(ACCOUNT_ACHIEVEMENT_BADGES) as AccountAchievementKind[]).map((kind) => {
              const earned = accountBadges.includes(kind);
              const badge = ACCOUNT_ACHIEVEMENT_BADGES[kind];
              return (
                <span
                  key={kind}
                  title={badge.label}
                  className={`flex items-center gap-1.5 rounded border border-neutral-700 bg-neutral-900 px-2 py-1 text-xs ${
                    earned ? "" : "opacity-40 grayscale"
                  }`}
                >
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={wowIconUrl(badge.icon)} alt="" className="h-5 w-5 rounded" />
                  {badge.label.split(" - ")[0]}
                </span>
              );
            })}
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
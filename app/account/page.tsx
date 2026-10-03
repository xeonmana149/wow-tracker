"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { supabase } from "../../lib/supabase";
import { AccountView } from "../AccountView";
import { loadAccountViewData, loadShowcasePickerData, type AccountViewData, type ShowcasePickerData } from "../../lib/accountView";
import {
  AVATAR_ICON_OPTIONS,
  BANNER_STYLE_OPTIONS,
  avatarIconSrc,
  findAvatarIconOption,
  bannerImageSrc,
  bannerClassName,
  MOTTO_MAX_LENGTH,
} from "../../lib/profileCustomization";

// Account Overview (2026-09-28 layout rework, Stage 3; refactored 2026-09-30
// when "how do we see other players account pages?" led to splitting the
// data-loading and read-only display out into lib/accountView.ts and
// AccountView.tsx, shared with the new /account/[userId] public page). This
// file now only owns: fetching YOUR OWN data via the browser's RLS-scoped
// client, and the Edit Profile button/panel (which only makes sense for
// your own account, so it stays here rather than in the shared view).

export default function AccountOverviewPage() {
  const [loading, setLoading] = useState(true);
  const [signedIn, setSignedIn] = useState(false);
  const [userId, setUserId] = useState<string | null>(null);
  const [data, setData] = useState<AccountViewData | null>(null);

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
  // Hovered banner option, for the enlarged preview above the swatch grid
  // (2026-09-29: "add a image enlarge when you hover so user can see the
  // banner properly before deciding"). null means nothing's hovered right
  // now, in which case the preview falls back to showing whatever's
  // currently selected, so something useful is always visible there.
  const [previewBannerKey, setPreviewBannerKey] = useState<string | null>(null);
  // Same idea, for the account icon grid (2026-09-30, "The profile icons
  // need a hover too to see a closeup like banner and also maybe a name so
  // you can see what they are like Orc Shaman Female for example"). Only
  // ever set to a real AVATAR_ICON_OPTIONS key - the "no icon" swatch
  // doesn't have art worth zooming in on, so it doesn't touch this.
  const [previewAvatarKey, setPreviewAvatarKey] = useState<string | null>(null);

  // Showcase pickers (2026-10-03) - draft state follows the exact same
  // "separate draft, Cancel discards it" pattern as the avatar/banner/motto
  // fields above. pickerData is lazy-loaded (loadShowcasePickerData only
  // fires the first time the Edit Profile panel opens, not on initial page
  // load) since it needs its own fetch of every character's stats/gear/
  // earned achievements - data the read-only AccountView never needs in
  // bulk, only the picker UI does.
  const [pickerData, setPickerData] = useState<ShowcasePickerData | null>(null);
  const [loadingPickerData, setLoadingPickerData] = useState(false);
  const [draftFavoriteCharacterId, setDraftFavoriteCharacterId] = useState<string | null>(null);
  const [draftStatCharacterId, setDraftStatCharacterId] = useState<string | null>(null);
  const [draftStatKey, setDraftStatKey] = useState<string | null>(null); // "category|||name" combined, split on save
  const [draftAchievementType, setDraftAchievementType] = useState<"character" | "account" | null>(null);
  const [draftAchievementCharacterId, setDraftAchievementCharacterId] = useState<string | null>(null);
  const [draftAchievementKind, setDraftAchievementKind] = useState<string | null>(null);
  const [draftItemCharacterId, setDraftItemCharacterId] = useState<string | null>(null);
  const [draftItemSlot, setDraftItemSlot] = useState<string | null>(null);

  useEffect(() => {
    async function load() {
      const { data: userData } = await supabase.auth.getUser();
      if (!userData.user) {
        setSignedIn(false);
        setLoading(false);
        return;
      }
      setSignedIn(true);
      setUserId(userData.user.id);
      const loaded = await loadAccountViewData(supabase, userData.user.id, userData.user.created_at ?? null);
      setData(loaded);
      setDraftDisplayName(loaded.displayName);
      setDraftAvatarIcon(loaded.avatarIcon);
      setDraftBannerStyle(loaded.bannerStyle ?? "parchment");
      setDraftMotto(loaded.motto ?? "");
      setLoading(false);
    }
    load();
  }, []);

  function openEditProfile() {
    if (!data) return;
    setDraftDisplayName(data.displayName);
    setDraftAvatarIcon(data.avatarIcon);
    setDraftBannerStyle(data.bannerStyle ?? "parchment");
    setDraftMotto(data.motto ?? "");
    setDraftFavoriteCharacterId(data.favoriteCharacter?.id ?? null);
    setDraftStatCharacterId(data.favoriteStatistic?.characterId ?? null);
    setDraftStatKey(
      data.favoriteStatistic ? `${data.favoriteStatistic.category}|||${data.favoriteStatistic.name}` : null
    );
    setDraftAchievementType(data.favoriteAchievement?.type ?? null);
    setDraftAchievementCharacterId(
      data.favoriteAchievement?.type === "character" ? data.favoriteAchievement.characterId : null
    );
    setDraftAchievementKind(
      data.favoriteAchievement?.type === "character"
        ? data.favoriteAchievement.item.key
        : data.favoriteAchievement?.type === "account"
          ? data.favoriteAchievement.kind
          : null
    );
    setDraftItemCharacterId(data.favoriteItem?.characterId ?? null);
    setDraftItemSlot(data.favoriteItem?.entry.slot ?? null);
    setProfileSaveError(null);
    setEditingProfile(true);
    if (!pickerData && userId) {
      setLoadingPickerData(true);
      loadShowcasePickerData(supabase, userId)
        .then(setPickerData)
        .finally(() => setLoadingPickerData(false));
    }
  }

  async function saveProfile() {
    if (!userId || !data) return;
    const trimmedName = draftDisplayName.trim();
    if (trimmedName.length === 0) {
      setProfileSaveError("Display name can't be empty.");
      return;
    }
    setSavingProfile(true);
    setProfileSaveError(null);
    const trimmedMotto = draftMotto.trim().slice(0, MOTTO_MAX_LENGTH);
    const [draftStatCategory, draftStatName] = draftStatKey ? draftStatKey.split("|||") : [null, null];
    const { error } = await supabase
      .from("profiles")
      .update({
        display_name: trimmedName,
        avatar_icon: draftAvatarIcon,
        banner_style: draftBannerStyle,
        motto: trimmedMotto.length > 0 ? trimmedMotto : null,
        favorite_character_id: draftFavoriteCharacterId,
        favorite_statistic_character_id: draftStatCharacterId,
        favorite_statistic_category: draftStatCategory,
        favorite_statistic_name: draftStatName,
        favorite_achievement_type: draftAchievementType,
        favorite_achievement_character_id: draftAchievementType === "character" ? draftAchievementCharacterId : null,
        favorite_achievement_kind: draftAchievementKind,
        favorite_item_character_id: draftItemCharacterId,
        favorite_item_slot: draftItemSlot,
      })
      .eq("id", userId);
    setSavingProfile(false);
    if (error) {
      setProfileSaveError(error.message);
      return;
    }

    // Reload the whole account view rather than hand-reconstructing the four
    // showcase picks locally. A local reconstruction of favoriteAchievement
    // (character type) would need to find the SPECIFIC tier the picked
    // character has earned, not just any tier of that kind - data.mergedItems
    // is the account-wide best tier across every character, which can belong
    // to a different character than the one just picked. lib/accountView.ts's
    // real per-character resolution (perCharacterItems) gets this right, so
    // it's simpler and safer to just re-run it than to duplicate its logic
    // here for an optimistic update.
    const refreshed = await loadAccountViewData(supabase, userId, data.memberSince);
    setData(refreshed);
    setEditingProfile(false);
  }

  if (loading) {
    return <main className="mx-auto max-w-6xl p-4 text-white md:p-6">Loading account...</main>;
  }

  if (!signedIn || !data) {
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
    <AccountView
      data={data}
      // 2026-10-03 ("Showcase should have an edit button in top right
      // corner") - same openEditProfile() the header's own "Edit Profile"
      // button uses; the panel it opens already has the Showcase picker
      // section built into it (see the "Showcase" div further down this
      // file), so there's no separate flow to build here, just another way
      // in.
      onEditShowcase={openEditProfile}
      headerActions={
        <button type="button" onClick={openEditProfile} className="rounded bg-blue-600 px-3 py-1.5 text-sm font-semibold">
          Edit Profile
        </button>
      }
      belowHeader={
        editingProfile && (
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
              {(() => {
                // Same pattern as the banner preview below: whatever's
                // hovered wins, falling back to whatever's actually
                // selected so the box never sits empty.
                const shownKey = previewAvatarKey ?? draftAvatarIcon;
                const shownOption = shownKey ? findAvatarIconOption(shownKey) : undefined;
                return (
                  <div className="mt-2 flex items-center gap-3 rounded border border-neutral-700 bg-neutral-900 p-3">
                    <div className="flex h-20 w-20 shrink-0 items-center justify-center overflow-hidden rounded-full border border-neutral-700 bg-neutral-800">
                      {shownOption ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={avatarIconSrc(shownOption)} alt="" className="h-full w-full object-cover" />
                      ) : (
                        <span className="text-2xl text-gray-400">{data.displayName.charAt(0).toUpperCase()}</span>
                      )}
                    </div>
                    <span className="text-sm font-semibold">
                      {shownOption ? shownOption.label : "No icon (use initial)"}
                    </span>
                  </div>
                );
              })()}
              <div className="mt-2 flex flex-wrap gap-2">
                <button
                  type="button"
                  onClick={() => setDraftAvatarIcon(null)}
                  className={`flex h-12 w-12 items-center justify-center rounded border text-[10px] text-gray-400 ${
                    draftAvatarIcon === null ? "border-amber-400" : "border-neutral-700"
                  }`}
                  title="No icon (use initial)"
                >
                  {data.displayName.charAt(0).toUpperCase()}
                </button>
                {AVATAR_ICON_OPTIONS.map((icon) => (
                  <button
                    key={icon.key}
                    type="button"
                    onClick={() => setDraftAvatarIcon(icon.key)}
                    onMouseEnter={() => setPreviewAvatarKey(icon.key)}
                    onMouseLeave={() => setPreviewAvatarKey(null)}
                    onFocus={() => setPreviewAvatarKey(icon.key)}
                    onBlur={() => setPreviewAvatarKey(null)}
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
              {(() => {
                const shownOption =
                  BANNER_STYLE_OPTIONS.find((o) => o.key === (previewBannerKey ?? draftBannerStyle)) ??
                  BANNER_STYLE_OPTIONS[0];
                const shownImgSrc = bannerImageSrc(shownOption);
                return (
                  <div
                    className={`banner-preview mt-2 ${bannerClassName(shownOption.key)}`}
                    style={
                      shownImgSrc
                        ? { backgroundImage: `url(${shownImgSrc})`, backgroundSize: "cover", backgroundPosition: "center" }
                        : undefined
                    }
                  >
                    <span className="absolute bottom-1 right-2 text-xs font-semibold" style={{ textShadow: "0 1px 3px rgba(0,0,0,0.9)" }}>
                      {shownOption.label}
                    </span>
                  </div>
                );
              })()}
              <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-3">
                {BANNER_STYLE_OPTIONS.map((opt) => {
                  const swatchImgSrc = bannerImageSrc(opt);
                  return (
                    <button
                      key={opt.key}
                      type="button"
                      onClick={() => setDraftBannerStyle(opt.key)}
                      onMouseEnter={() => setPreviewBannerKey(opt.key)}
                      onMouseLeave={() => setPreviewBannerKey(null)}
                      onFocus={() => setPreviewBannerKey(opt.key)}
                      onBlur={() => setPreviewBannerKey(null)}
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

            <div className="mt-4 border-t border-neutral-700 pt-4">
              <h3 className="text-sm font-semibold text-amber-200">Showcase</h3>
              <p className="mt-1 text-xs text-gray-500">
                Pick what shows in the Showcase section on your account page. Leave any of these on "None" to leave
                that card unset.
              </p>

              {loadingPickerData && <p className="mt-2 text-xs text-gray-500">Loading your characters' data...</p>}

              {/* Favourite character */}
              <div className="mt-3">
                <label className="text-sm text-gray-300" htmlFor="fav-character-select">
                  Favourite character
                </label>
                <select
                  id="fav-character-select"
                  value={draftFavoriteCharacterId ?? ""}
                  onChange={(e) => setDraftFavoriteCharacterId(e.target.value || null)}
                  className="mt-1 block w-full max-w-xs rounded border border-neutral-700 bg-neutral-900 p-2 text-sm text-white"
                >
                  <option value="">None</option>
                  {data.characters.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name} (Lv.{c.level} {c.class})
                    </option>
                  ))}
                </select>
              </div>

              {/* Favourite statistic */}
              <div className="mt-3">
                <label className="text-sm text-gray-300" htmlFor="fav-stat-character-select">
                  Favourite statistic
                </label>
                <div className="mt-1 flex flex-wrap gap-2">
                  <select
                    id="fav-stat-character-select"
                    value={draftStatCharacterId ?? ""}
                    onChange={(e) => {
                      setDraftStatCharacterId(e.target.value || null);
                      setDraftStatKey(null); // changing character invalidates whatever stat was picked
                    }}
                    className="rounded border border-neutral-700 bg-neutral-900 p-2 text-sm text-white"
                  >
                    <option value="">Character...</option>
                    {data.characters.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.name}
                      </option>
                    ))}
                  </select>
                  <select
                    value={draftStatKey ?? ""}
                    onChange={(e) => setDraftStatKey(e.target.value || null)}
                    disabled={!draftStatCharacterId}
                    className="flex-1 rounded border border-neutral-700 bg-neutral-900 p-2 text-sm text-white disabled:opacity-50"
                  >
                    <option value="">None</option>
                    {draftStatCharacterId &&
                      (pickerData?.statsByCharacter[draftStatCharacterId] ?? []).map((s) => (
                        <option key={`${s.category}|||${s.name}`} value={`${s.category}|||${s.name}`}>
                          {s.category} - {s.name}: {s.value}
                        </option>
                      ))}
                  </select>
                </div>
              </div>

              {/* Favourite achievement */}
              <div className="mt-3">
                <p className="text-sm text-gray-300">Favourite achievement</p>
                <div className="mt-1 flex flex-wrap gap-2">
                  <select
                    value={draftAchievementType ?? ""}
                    onChange={(e) => {
                      const next = (e.target.value || null) as "character" | "account" | null;
                      setDraftAchievementType(next);
                      setDraftAchievementCharacterId(null);
                      setDraftAchievementKind(null);
                    }}
                    className="rounded border border-neutral-700 bg-neutral-900 p-2 text-sm text-white"
                  >
                    <option value="">None</option>
                    <option value="character">Character achievement</option>
                    <option value="account">Account badge</option>
                  </select>

                  {draftAchievementType === "character" && (
                    <>
                      <select
                        value={draftAchievementCharacterId ?? ""}
                        onChange={(e) => {
                          setDraftAchievementCharacterId(e.target.value || null);
                          setDraftAchievementKind(null);
                        }}
                        className="rounded border border-neutral-700 bg-neutral-900 p-2 text-sm text-white"
                      >
                        <option value="">Character...</option>
                        {data.characters.map((c) => (
                          <option key={c.id} value={c.id}>
                            {c.name}
                          </option>
                        ))}
                      </select>
                      <select
                        value={draftAchievementKind ?? ""}
                        onChange={(e) => setDraftAchievementKind(e.target.value || null)}
                        disabled={!draftAchievementCharacterId}
                        className="flex-1 rounded border border-neutral-700 bg-neutral-900 p-2 text-sm text-white disabled:opacity-50"
                      >
                        <option value="">None (nothing earned yet?)</option>
                        {draftAchievementCharacterId &&
                          (pickerData?.earnedAchievementsByCharacter[draftAchievementCharacterId] ?? []).map((a) => (
                            <option key={a.kind} value={a.kind}>
                              {a.label}
                              {a.tier ? ` (${a.tier})` : ""}
                            </option>
                          ))}
                      </select>
                    </>
                  )}

                  {draftAchievementType === "account" && (
                    <select
                      value={draftAchievementKind ?? ""}
                      onChange={(e) => setDraftAchievementKind(e.target.value || null)}
                      className="flex-1 rounded border border-neutral-700 bg-neutral-900 p-2 text-sm text-white"
                    >
                      <option value="">None</option>
                      {(pickerData?.accountBadges ?? [])
                        .filter((b) => b.earned)
                        .map((b) => (
                          <option key={b.kind} value={b.kind}>
                            {b.label}
                          </option>
                        ))}
                    </select>
                  )}
                </div>
              </div>

              {/* Item showcase */}
              <div className="mt-3">
                <label className="text-sm text-gray-300" htmlFor="fav-item-character-select">
                  Item showcase
                </label>
                <div className="mt-1 flex flex-wrap gap-2">
                  <select
                    id="fav-item-character-select"
                    value={draftItemCharacterId ?? ""}
                    onChange={(e) => {
                      setDraftItemCharacterId(e.target.value || null);
                      setDraftItemSlot(null);
                    }}
                    className="rounded border border-neutral-700 bg-neutral-900 p-2 text-sm text-white"
                  >
                    <option value="">Character...</option>
                    {data.characters.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.name}
                      </option>
                    ))}
                  </select>
                  <select
                    value={draftItemSlot ?? ""}
                    onChange={(e) => setDraftItemSlot(e.target.value || null)}
                    disabled={!draftItemCharacterId}
                    className="flex-1 rounded border border-neutral-700 bg-neutral-900 p-2 text-sm text-white disabled:opacity-50"
                  >
                    <option value="">None (nothing equipped?)</option>
                    {draftItemCharacterId &&
                      (pickerData?.gearByCharacter[draftItemCharacterId] ?? []).map((g) => (
                        <option key={g.slot} value={g.slot}>
                          {g.slot}: {g.item_name}
                        </option>
                      ))}
                  </select>
                </div>
              </div>
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
        )
      }
    />
  );
}
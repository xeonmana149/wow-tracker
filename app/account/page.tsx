"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { supabase } from "../../lib/supabase";
import { AccountView } from "../AccountView";
import { loadAccountViewData, type AccountViewData } from "../../lib/accountView";
import {
  AVATAR_ICON_OPTIONS,
  BANNER_STYLE_OPTIONS,
  avatarIconSrc,
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
    setProfileSaveError(null);
    setEditingProfile(true);
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
    setData({
      ...data,
      displayName: trimmedName,
      avatarIcon: draftAvatarIcon,
      bannerStyle: draftBannerStyle,
      motto: trimmedMotto.length > 0 ? trimmedMotto : null,
    });
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
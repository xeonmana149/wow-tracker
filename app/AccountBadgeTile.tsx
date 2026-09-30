"use client";

import { useState } from "react";
import { ACCOUNT_BADGE_FRAME_SRC, ACCOUNT_BADGE_FRAME_HOLE_RATIO } from "../lib/badgeFrames";

// Hover-preview tile for the Account Badges row (2026-09-30, "now I want
// the hover system that achievements get ... implement for account
// badges", then "They deserve a unique special frame for account badges") -
// same enlarged-preview-on-hover treatment as ShowcaseBadge (see
// AchievementShowcase.tsx), plus its own ornate frame overlay (see
// lib/badgeFrames.ts's ACCOUNT_BADGE_FRAME_SRC) instead of ShowcaseBadge's
// tier frames, since account badges are one-off, not tiered. Pulled into
// its own "use client" component because AccountView.tsx has no hooks/state
// on purpose (it's rendered from both a "use client" page and a plain
// server component page - see its own header comment), and hover needs
// local state somewhere. No Link wrapper since there's nowhere for one of
// these to link to yet.
//
// The ornate frame is ALWAYS shown, local custom art included - Jordan's
// call (2026-09-30, "no I want the ornate frame ... just scaled properly")
// after an in-between version that skipped the frame for local-art badges
// looked wrong instead. Sizing the icon "properly" is handled entirely by
// ACCOUNT_BADGE_FRAME_HOLE_RATIO in lib/badgeFrames.ts (deliberately wider
// than the frame's literal opening so the icon fills almost the whole
// tile) - there's no more unframed rendering path to branch on.
export default function AccountBadgeTile({
  icon,
  name,
  description,
  earned,
}: {
  icon: string; // resolved image URL (e.g. from wowIconUrl() or a local /account-badge-icons/ path)
  name: string;
  description: string;
  earned: boolean;
}) {
  const [hover, setHover] = useState(false);
  const size = 56; // matches the h-14 w-14 tile AccountView used before this
  const innerSize = Math.round(size * ACCOUNT_BADGE_FRAME_HOLE_RATIO);
  const inset = Math.round((size - innerSize) / 2);

  const previewSize = 140;
  const previewInner = Math.round(previewSize * ACCOUNT_BADGE_FRAME_HOLE_RATIO);
  const previewInset = Math.round((previewSize - previewInner) / 2);

  return (
    <span
      className="group/badge relative flex w-16 flex-col items-center gap-1 text-center"
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
    >
      <span
        className={`relative inline-block shrink-0 ${earned ? "" : "opacity-40 grayscale"}`}
        style={{ width: size, height: size }}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={icon}
          alt=""
          draggable={false}
          className="absolute rounded-sm object-cover"
          style={{ width: innerSize, height: innerSize, top: inset, left: inset }}
        />
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={ACCOUNT_BADGE_FRAME_SRC}
          alt=""
          aria-hidden="true"
          draggable={false}
          className="pointer-events-none absolute inset-0 h-full w-full"
        />
      </span>
      <span className="line-clamp-2 rounded bg-neutral-950/70 px-1 py-0.5 text-[10px] font-semibold leading-tight text-white">
        {name}
      </span>

      {hover && (
        <div className="pointer-events-none absolute bottom-full left-1/2 z-30 mb-2 w-52 -translate-x-1/2 rounded-lg border border-amber-700/70 bg-neutral-950 p-2.5 text-left shadow-lg shadow-black/60">
          <span
            className={`relative mx-auto mb-2 block ${earned ? "" : "opacity-40 grayscale"}`}
            style={{ width: previewSize, height: previewSize }}
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={icon}
              alt=""
              draggable={false}
              className="absolute rounded object-cover"
              style={{ width: previewInner, height: previewInner, top: previewInset, left: previewInset }}
            />
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={ACCOUNT_BADGE_FRAME_SRC}
              alt=""
              aria-hidden="true"
              draggable={false}
              className="pointer-events-none absolute inset-0 h-full w-full"
            />
          </span>
          <div className="text-sm font-bold text-amber-100">{name}</div>
          <div className="mt-1 text-xs leading-snug text-gray-300">{description}</div>
          {!earned && <div className="mt-1.5 text-[11px] text-gray-500">Not yet earned</div>}
          <span className="absolute left-1/2 top-full h-2 w-2 -translate-x-1/2 -translate-y-1/2 rotate-45 border-b border-r border-amber-700/70 bg-neutral-950" />
        </div>
      )}
    </span>
  );
}
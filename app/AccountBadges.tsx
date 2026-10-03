"use client";

import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import {
  ACCOUNT_ACHIEVEMENT_BADGES,
  accountBadgeIconSrc,
  type AccountAchievementKind,
} from "../lib/accountAchievements";
import { ACCOUNT_BADGE_FRAME_SRC, ACCOUNT_BADGE_FRAME_HOLE_RATIO } from "../lib/badgeFrames";
import type { BadgeIconOverrides } from "../lib/badgeIconOverrides";

// Small row of account-wide achievement badges - shared between the
// Dashboard (the logged-in user's own badges) and the Friends page (every
// player's badges next to their name), so the two stay visually
// consistent and only need updating in one place.
//
// 2026-10-03 redesign ("why are these showing wow icons and not the
// correct square icon with the hover mechanic and the account.png
// border?") - this used to render a plain round GameIcon with a generic
// blue ring and a text-only tooltip, which fell out of sync when the
// Account Overview page's own account badges (AccountBadgeTile) got the
// ornate ACCOUNT_BADGE_FRAME_SRC border and a big hover-preview. Now both
// places use the exact same square-art-in-an-ornate-frame treatment.

const TOOLTIP_GAP = 8;
const PREVIEW_SIZE = 160;

type TooltipPos = { centerX: number; openAbove: boolean; top: number };

function computeTooltipPos(rect: DOMRect, minSpaceAbove: number): TooltipPos {
  const centerX = rect.left + rect.width / 2;
  const openAbove = rect.top > minSpaceAbove;
  const top = openAbove ? rect.top - TOOLTIP_GAP : rect.bottom + TOOLTIP_GAP;
  return { centerX, openAbove, top };
}

function AccountBadgeIcon({
  kind,
  iconOverrides,
  size,
}: {
  kind: AccountAchievementKind;
  iconOverrides: BadgeIconOverrides;
  size: number;
}) {
  const badge = ACCOUNT_ACHIEVEMENT_BADGES[kind];
  const anchorRef = useRef<HTMLSpanElement>(null);
  const [pos, setPos] = useState<TooltipPos | null>(null);
  const [failed, setFailed] = useState(false);

  // Shared resolution chain (admin override > local art > coded-in CDN
  // icon) - lives in lib/accountAchievements.ts so this panel and the
  // Account Overview page's AccountBadgesGrid can never drift apart again
  // (2026-10-03: they briefly did - see accountBadgeIconSrc's own comment).
  const iconSrc = badge ? accountBadgeIconSrc(kind, iconOverrides) : null;

  useEffect(() => {
    setFailed(false);
  }, [iconSrc]);

  if (!badge) return null;

  const innerSize = Math.round(size * ACCOUNT_BADGE_FRAME_HOLE_RATIO);
  const inset = Math.round((size - innerSize) / 2);
  const previewInner = Math.round(PREVIEW_SIZE * ACCOUNT_BADGE_FRAME_HOLE_RATIO);
  const previewInset = Math.round((PREVIEW_SIZE - previewInner) / 2);

  function showTooltip() {
    if (!anchorRef.current) return;
    // Taller than a plain label tooltip (room for the big art above it),
    // so it needs more headroom before it's willing to open above the icon
    // instead of below it.
    setPos(computeTooltipPos(anchorRef.current.getBoundingClientRect(), PREVIEW_SIZE + 80));
  }
  function hideTooltip() {
    setPos(null);
  }

  return (
    <span
      ref={anchorRef}
      className="relative inline-block shrink-0 align-middle"
      style={{ width: size, height: size }}
      onMouseEnter={showTooltip}
      onMouseLeave={hideTooltip}
    >
      {!iconSrc || failed ? (
        <span
          className="absolute flex items-center justify-center overflow-hidden rounded-sm border border-amber-900/70 bg-neutral-900 text-[9px] font-bold text-amber-200"
          style={{ width: innerSize, height: innerSize, top: inset, left: inset }}
        >
          {badge.label.slice(0, 2).toUpperCase()}
        </span>
      ) : (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={iconSrc}
          alt=""
          draggable={false}
          onError={() => setFailed(true)}
          className="absolute rounded-sm object-cover"
          style={{ width: innerSize, height: innerSize, top: inset, left: inset }}
        />
      )}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={ACCOUNT_BADGE_FRAME_SRC}
        alt=""
        aria-hidden="true"
        draggable={false}
        className="pointer-events-none absolute inset-0 h-full w-full"
      />

      {/* Portal-based tooltip (same convention as GameIcon/TierFramedIcon) -
          rendered into document.body at position: fixed, so this still
          works correctly wherever this row ends up (the Friends page's
          character chip list scrolls, which would otherwise clip an
          in-flow tooltip). */}
      {pos &&
        typeof document !== "undefined" &&
        createPortal(
          <div
            role="tooltip"
            className="pointer-events-none fixed z-[999] flex w-max max-w-[260px] flex-col items-center gap-2 rounded-lg border border-amber-700/70 bg-neutral-950 px-3 py-2.5 text-sm font-medium leading-snug text-amber-100 shadow-lg shadow-black/60"
            style={{
              left: pos.centerX,
              top: pos.top,
              transform: pos.openAbove ? "translate(-50%, -100%)" : "translateX(-50%)",
            }}
          >
            {!failed && iconSrc && (
              <span className="relative block shrink-0" style={{ width: PREVIEW_SIZE, height: PREVIEW_SIZE }}>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={iconSrc}
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
            )}
            <span className="text-center">{badge.label}</span>
            <span
              className={`absolute left-1/2 h-2 w-2 -translate-x-1/2 rotate-45 border-amber-700/70 bg-neutral-950 ${
                pos.openAbove
                  ? "top-full -translate-y-1/2 border-b border-r"
                  : "bottom-full translate-y-1/2 border-l border-t"
              }`}
            />
          </div>,
          document.body
        )}
    </span>
  );
}

export default function AccountBadges({
  kinds,
  size = "sm",
  iconOverrides = {},
}: {
  kinds: AccountAchievementKind[];
  size?: "sm" | "md";
  // Runtime icon overrides from the badge_icons table - see
  // lib/badgeIconOverrides.ts. Defaults to {} so passing nothing just uses
  // every badge's coded-in (or local-art) default icon.
  iconOverrides?: BadgeIconOverrides;
}) {
  if (kinds.length === 0) return null;

  // Bumped up from the old 28/32 round icons (2026-10-03) - the ornate
  // frame needs more room to actually read as a frame instead of a blurry
  // border, same size bump AccountBadgeTile already uses on the Account
  // Overview page (56px there; slightly smaller here since this is a
  // secondary summary row, not the main badge showcase).
  const px = size === "md" ? 44 : 36;

  return (
    <span className="inline-flex flex-wrap items-center gap-2">
      {kinds.map((kind) => (
        <AccountBadgeIcon key={kind} kind={kind} iconOverrides={iconOverrides} size={px} />
      ))}
    </span>
  );
}
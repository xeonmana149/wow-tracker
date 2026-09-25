"use client";

import { useRef, useState } from "react";
import { createPortal } from "react-dom";
import BadgePlaceholder from "./BadgePlaceholder";
import { TIER_FRAME_SRC, FRAME_HOLE_RATIO, localBadgeIconSrc } from "../lib/badgeFrames";
import { TIERED_LOCAL_ICONS, FLAT_LOCAL_ICONS } from "../lib/achievementBadges";
import type { AchievementTier, TieredAchievementKind, AchievementKind } from "../lib/achievements";

// Renders the actual badge art for an "achievement_earned" activity_events
// row (2026-09-25) - the feed used to just show a generic 🏅 emoji or the
// character's class icon for every achievement event, since the row only
// ever stored a free-text message, not which achievement it was. Now that
// activity_events also carries achievement_kind/achievement_tier (see the
// activity_events migration), this looks the real badge up the same way
// TierFramedIcon/BadgePlaceholder do everywhere else.
//
// 2026-09-25 fix: this originally delegated tiered badges to TierFramedIcon
// and hand-rolled the same in-flow "absolute bottom-full" tooltip for flat
// ones - both got clipped inside the Activity feed's scrollable event list,
// because a scrolling ancestor (overflow-y-auto) clips anything that pops
// outside it, including an absolutely positioned tooltip. Rendering the
// enlarged preview through a portal straight onto <body>, positioned from
// the icon's real screen coordinates and clamped to the viewport, fixes
// that - it can no longer be clipped by any scrollable ancestor, wherever
// this component ends up being used.
const PREVIEW_ICON_SIZE = 140;
const PREVIEW_PADDING = 12; // matches the p-3 on the portal box below
const PREVIEW_BOX_WIDTH = PREVIEW_ICON_SIZE + PREVIEW_PADDING * 2;
const PREVIEW_GAP = 8; // gap between the icon and the preview box

export default function ActivityAchievementIcon({
  kind,
  tier,
  label,
  size = 28,
}: {
  // The raw kind string as stored on the row - either a TieredAchievementKind
  // or a flat AchievementKind, disambiguated by whether `tier` is set.
  kind: string;
  tier: AchievementTier | null;
  label: string;
  size?: number;
}) {
  const anchorRef = useRef<HTMLSpanElement>(null);
  const [previewPos, setPreviewPos] = useState<{ top: number; left: number; openAbove: boolean } | null>(
    null
  );

  const localIcon = tier
    ? TIERED_LOCAL_ICONS[kind as TieredAchievementKind]
    : FLAT_LOCAL_ICONS[kind as AchievementKind];

  if (!localIcon) {
    return <BadgePlaceholder tier={tier} label={label} size={size} round />;
  }

  const innerSize = tier ? Math.round(size * FRAME_HOLE_RATIO) : size;
  const inset = tier ? Math.round((size - innerSize) / 2) : 0;
  const previewInner = tier ? Math.round(PREVIEW_ICON_SIZE * FRAME_HOLE_RATIO) : PREVIEW_ICON_SIZE;
  const previewInset = tier ? Math.round((PREVIEW_ICON_SIZE - previewInner) / 2) : 0;

  function showPreview() {
    const el = anchorRef.current;
    if (!el || typeof window === "undefined") return;
    const rect = el.getBoundingClientRect();

    // Prefer opening above the icon (the badge system's usual convention),
    // but drop below when there isn't room - this is what stops it running
    // off the TOP of the screen for an event near the top of the feed.
    const previewHeight = PREVIEW_ICON_SIZE + PREVIEW_PADDING * 2 + 24; // + label line
    const openAbove = rect.top >= previewHeight + PREVIEW_GAP;
    const top = openAbove ? rect.top - previewHeight - PREVIEW_GAP : rect.bottom + PREVIEW_GAP;

    // Centers on the icon, then clamps so it can't run off the LEFT or
    // RIGHT of the screen either - the bug in the screenshot, since the
    // feed panel itself is only 320px wide and the icon sits near its edge.
    let left = rect.left + rect.width / 2 - PREVIEW_BOX_WIDTH / 2;
    const maxLeft = window.innerWidth - PREVIEW_BOX_WIDTH - PREVIEW_GAP;
    left = Math.max(PREVIEW_GAP, Math.min(left, maxLeft));

    setPreviewPos({ top, left, openAbove });
  }

  return (
    <>
      <span
        ref={anchorRef}
        className="relative inline-block shrink-0 align-middle"
        style={{ width: size, height: size }}
        onMouseEnter={showPreview}
        onMouseLeave={() => setPreviewPos(null)}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={localBadgeIconSrc(localIcon)}
          alt=""
          draggable={false}
          className={`absolute object-cover ${tier ? "rounded-sm" : "rounded-full"}`}
          style={{ width: innerSize, height: innerSize, top: inset, left: inset }}
        />
        {tier && (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={TIER_FRAME_SRC[tier]}
            alt=""
            aria-hidden="true"
            draggable={false}
            className="pointer-events-none absolute inset-0 h-full w-full"
          />
        )}
      </span>

      {previewPos &&
        typeof document !== "undefined" &&
        createPortal(
          <div
            className="pointer-events-none fixed z-[999] flex flex-col items-center gap-2 rounded-lg border border-amber-700/70 bg-neutral-950 p-3 shadow-lg shadow-black/60"
            style={{ top: previewPos.top, left: previewPos.left, width: PREVIEW_BOX_WIDTH }}
          >
            <span
              className="relative block shrink-0"
              style={{ width: PREVIEW_ICON_SIZE, height: PREVIEW_ICON_SIZE }}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={localBadgeIconSrc(localIcon)}
                alt=""
                draggable={false}
                className={`absolute object-cover ${tier ? "rounded" : "rounded-full"}`}
                style={{ width: previewInner, height: previewInner, top: previewInset, left: previewInset }}
              />
              {tier && (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={TIER_FRAME_SRC[tier]}
                  alt=""
                  aria-hidden="true"
                  draggable={false}
                  className="pointer-events-none absolute inset-0 h-full w-full"
                />
              )}
            </span>
            <span className="text-center text-sm font-medium leading-snug text-amber-100">{label}</span>
          </div>,
          document.body
        )}
    </>
  );
}
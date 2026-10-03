"use client";

import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { TIER_FRAME_SRC, FRAME_HOLE_RATIO, localBadgeIconSrc } from "../lib/badgeFrames";
import type { GoldTier } from "../lib/achievements";

// Tooltip sizing/positioning - mirrors GameIcon.tsx's approach exactly
// (2026-10-03 fix, see that file's own comment for the history): a
// fixed-position portal rendered into document.body, computed from the
// anchor's own getBoundingClientRect(), instead of the old in-flow
// group-hover tooltip this component used to render. That in-flow version
// worked fine until CharacterCard.tsx's achievement strip got wrapped in a
// `max-h-28 overflow-y-auto` scroll box (2026-10-03, "achievements
// endlessly scroll over all the other text") - after that, every tiered
// badge's hover tooltip got silently clipped by that scrollable ancestor,
// since an absolutely-positioned in-flow tooltip can never escape an
// ancestor with overflow set. A portal tooltip renders outside that
// ancestor entirely, so it can't be clipped by it (same reasoning that
// already fixed this exact bug for GameIcon's own tooltip, and for
// ActivityAchievementIcon.tsx).
const TOOLTIP_GAP = 8;

type TooltipPos = {
  centerX: number;
  openAbove: boolean;
  top: number;
};

function computeTooltipPos(rect: DOMRect): TooltipPos {
  const centerX = rect.left + rect.width / 2;
  const openAbove = rect.top > 220;
  const top = openAbove ? rect.top - TOOLTIP_GAP : rect.bottom + TOOLTIP_GAP;
  return { centerX, openAbove, top };
}

// Renders a local plain icon (from /public/badge-icons/) with the matching
// tier's reusable border frame (from /public/badge-frames/) layered on top
// - the "one icon, swap the border" approach the badge-frame images were
// made for, instead of GameIcon's colored-ring convention used for the
// older/not-yet-iconned tiered badges. Falls back to a text tile if the
// icon file 404s, same behavior as GameIcon.
export default function TierFramedIcon({
  icon,
  tier,
  label,
  size = 28,
}: {
  // Bare icon slug, e.g. "slayer" -> resolves to /badge-icons/slayer.png.
  icon: string;
  tier: GoldTier;
  label: string;
  size?: number;
}) {
  const iconSrc = localBadgeIconSrc(icon);
  const [failed, setFailed] = useState(false);
  const [pos, setPos] = useState<TooltipPos | null>(null);
  const anchorRef = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    setFailed(false);
  }, [iconSrc]);

  function showTooltip() {
    if (!anchorRef.current) return;
    setPos(computeTooltipPos(anchorRef.current.getBoundingClientRect()));
  }

  function hideTooltip() {
    setPos(null);
  }

  const innerSize = Math.round(size * FRAME_HOLE_RATIO);
  const inset = Math.round((size - innerSize) / 2);

  // The hover preview blows the same art up big enough to actually see the
  // detail in it - the badge icons are hand-picked pieces, not generic WoW
  // CDN icons, so at their normal inline size (18-46px depending on where
  // this renders) most of that detail is invisible.
  const previewSize = 160;
  const previewInner = Math.round(previewSize * FRAME_HOLE_RATIO);
  const previewInset = Math.round((previewSize - previewInner) / 2);

  return (
    <span
      ref={anchorRef}
      className="relative inline-block shrink-0 align-middle"
      style={{ width: size, height: size }}
      onMouseEnter={showTooltip}
      onMouseLeave={hideTooltip}
    >
      {failed ? (
        <span
          className="absolute flex items-center justify-center overflow-hidden rounded-sm border border-amber-900/70 bg-neutral-900 text-[9px] font-bold text-amber-200"
          style={{ width: innerSize, height: innerSize, top: inset, left: inset }}
        >
          {label.slice(0, 2).toUpperCase()}
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
        src={TIER_FRAME_SRC[tier]}
        alt=""
        aria-hidden="true"
        draggable={false}
        className="pointer-events-none absolute inset-0 h-full w-full"
      />

      {/* Portal-based tooltip, same convention as GameIcon - rendered into
          document.body at position: fixed so a scrollable or
          opacity-reduced ancestor can't clip or fade it out. Still shows
          the large art preview on top of the label, same as before. */}
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
            {!failed && (
              <span className="relative block shrink-0" style={{ width: previewSize, height: previewSize }}>
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
                  src={TIER_FRAME_SRC[tier]}
                  alt=""
                  aria-hidden="true"
                  draggable={false}
                  className="pointer-events-none absolute inset-0 h-full w-full"
                />
              </span>
            )}
            <span className="text-center">{label}</span>
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
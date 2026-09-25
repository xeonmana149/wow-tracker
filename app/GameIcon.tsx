"use client";

import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { iconUrl } from "../lib/icons";

// Tooltip sizing/positioning constants - mirrors the approach in
// ActivityAchievementIcon.tsx (2026-09-25): a fixed-position portal
// rendered into document.body, computed from the anchor's own
// getBoundingClientRect() and clamped to the viewport, so it can never be
// clipped by a scrollable/opacity-reduced ancestor (e.g. the Activity
// feed's overflow-y-auto list). GameIcon used to render its tooltip
// in-flow via group-hover, which had that exact clipping bug everywhere
// it appeared inside a scrollable container - not just achievement
// badges, but every class/race/profession icon too (reported via a
// clipped "PALADIN" tooltip in the Activity feed).
const TOOLTIP_MAX_WIDTH = 260;
const TOOLTIP_GAP = 8;

type TooltipPos = {
  left: number;
  arrowLeft: number;
  openAbove: boolean;
  top: number;
};

function computeTooltipPos(rect: DOMRect): TooltipPos {
  const centerX = rect.left + rect.width / 2;
  let left = centerX - TOOLTIP_MAX_WIDTH / 2;
  left = Math.max(TOOLTIP_GAP, Math.min(left, window.innerWidth - TOOLTIP_MAX_WIDTH - TOOLTIP_GAP));
  const arrowLeft = centerX - left;

  const openAbove = rect.top > 60;
  const top = openAbove ? rect.top - TOOLTIP_GAP : rect.bottom + TOOLTIP_GAP;

  return { left, arrowLeft, openAbove, top };
}

export default function GameIcon({
  name,
  src,
  label,
  size = 32,
  round = false,
}: {
  // Local icon by name (looked up under /talent-icons/) - used for
  // classes, races and professions, which are bundled locally.
  name?: string | null;
  // A direct image URL - used for achievement badges, which pull from the
  // live Wowhead/zamimg icon CDN instead (see wowIconUrl in lib/icons.ts),
  // since there are far more of those than are worth bundling locally.
  // Takes priority over `name` if both are somehow given.
  src?: string | null;
  label: string;
  size?: number;
  round?: boolean;
}) {
  const [failed, setFailed] = useState(false);
  const [pos, setPos] = useState<TooltipPos | null>(null);
  const anchorRef = useRef<HTMLSpanElement>(null);
  const shape = round ? "rounded-full" : "rounded";
  const resolvedSrc = src ?? (name ? iconUrl(name) : null);

  // Without this, once one icon 404s (setting failed=true), this component
  // instance would show the fallback tile forever - even after `src`/`name`
  // later changes to a working icon (e.g. after saving a new icon override) -
  // because React re-uses the same component instance and `failed` never
  // had a reason to reset. Resetting it whenever the resolved URL changes
  // means a new icon always gets its own fresh attempt to load.
  useEffect(() => {
    setFailed(false);
  }, [resolvedSrc]);

  function showTooltip() {
    if (!anchorRef.current) return;
    setPos(computeTooltipPos(anchorRef.current.getBoundingClientRect()));
  }

  function hideTooltip() {
    setPos(null);
  }

  // The wrapper's size (set here, via inline style) is what's authoritative
  // for the icon's box - the image/fallback tile inside just fills it
  // completely (h-full w-full), rather than trying to size itself. That
  // way nothing about a surrounding flex row (stretch, wrapping, etc.) can
  // squash or stretch the icon into a non-square oval - its box can't move.
  return (
    <span
      ref={anchorRef}
      className="relative inline-block shrink-0 align-middle"
      style={{ width: size, height: size }}
      onMouseEnter={showTooltip}
      onMouseLeave={hideTooltip}
    >
      {!resolvedSrc || failed ? (
        <span
          className={`flex h-full w-full items-center justify-center border border-amber-900/70 bg-neutral-900 text-[10px] font-bold text-amber-200 ${shape}`}
        >
          {label.slice(0, 2).toUpperCase()}
        </span>
      ) : (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={resolvedSrc}
          alt={label}
          draggable={false}
          onError={() => setFailed(true)}
          className={`h-full w-full border border-amber-900/70 object-cover ${shape}`}
        />
      )}

      {/* Portal-based tooltip - rendered into document.body at
          position: fixed instead of in-flow, so a scrollable or
          opacity-reduced ancestor (like the Activity feed's list) can't
          clip or fade it. Positioned from the anchor span's own
          getBoundingClientRect(), recomputed on every hover in case the
          page scrolled since the last time. */}
      {pos &&
        typeof document !== "undefined" &&
        createPortal(
          <div
            role="tooltip"
            className="pointer-events-none fixed z-[999] w-max max-w-[260px] rounded-lg border border-amber-700/70 bg-neutral-950 px-3 py-2 text-sm font-medium leading-snug text-amber-100 shadow-lg shadow-black/60"
            style={{
              left: pos.left,
              top: pos.top,
              transform: pos.openAbove ? "translateY(-100%)" : undefined,
            }}
          >
            {label}
            <span
              className={`absolute h-2 w-2 -translate-x-1/2 rotate-45 border-amber-700/70 bg-neutral-950 ${
                pos.openAbove
                  ? "top-full -translate-y-1/2 border-b border-r"
                  : "bottom-full translate-y-1/2 border-l border-t"
              }`}
              style={{ left: pos.arrowLeft }}
            />
          </div>,
          document.body
        )}
    </span>
  );
}
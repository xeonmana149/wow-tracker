"use client";

import { useEffect, useState } from "react";
import { TIER_FRAME_SRC, FRAME_HOLE_RATIO, localBadgeIconSrc } from "../lib/badgeFrames";
import type { GoldTier } from "../lib/achievements";

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

  useEffect(() => {
    setFailed(false);
  }, [iconSrc]);

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
      className="group/icon relative inline-block shrink-0 align-middle"
      style={{ width: size, height: size }}
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

      {/* Same themed tooltip convention as GameIcon, now with a large
          preview of the actual art on top instead of just the label. */}
      <span
        role="tooltip"
        className="pointer-events-none absolute bottom-full left-1/2 z-30 mb-2 flex w-max max-w-[260px] -translate-x-1/2 scale-95 flex-col items-center gap-2 rounded-lg border border-amber-700/70 bg-neutral-950 px-3 py-2.5 text-sm font-medium leading-snug text-amber-100 opacity-0 shadow-lg shadow-black/60 transition-all duration-100 group-hover/icon:scale-100 group-hover/icon:opacity-100"
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
        <span className="absolute left-1/2 top-full h-2 w-2 -translate-x-1/2 -translate-y-1/2 rotate-45 border-b border-r border-amber-700/70 bg-neutral-950" />
      </span>
    </span>
  );
}
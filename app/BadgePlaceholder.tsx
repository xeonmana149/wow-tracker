import { TIER_FRAME_SRC, FRAME_HOLE_RATIO } from "../lib/badgeFrames";
import type { GoldTier } from "../lib/achievements";

// Generic "no custom art yet" tile (2026-09-25). Replaces every fallback
// that used to reach for a WoW CDN icon (wowIconUrl/GameIcon) whenever an
// achievement didn't have hand-picked local art - per "remove the old wow
// icon badges and only use the ones I upload", nothing on the site renders
// a WoW CDN icon for an achievement badge any more. Deliberately plain (a
// muted question mark, no color, no game art) rather than a generic game
// icon, so it visibly reads as "not customized yet" instead of quietly
// looking like a finished part of the badge set. No "use client" needed -
// no hooks or handlers, just markup.
export default function BadgePlaceholder({
  tier,
  label,
  size = 28,
  round = false,
  dim = false,
}: {
  // Tiered badges still get the matching tier's border frame layered on
  // top, same as TierFramedIcon, so an un-iconned tiered badge still reads
  // as "Silver" etc. at a glance. Omit/null for flat (no-tier) badges.
  tier?: GoldTier | null;
  label: string;
  size?: number;
  round?: boolean;
  dim?: boolean;
}) {
  const innerSize = tier ? Math.round(size * FRAME_HOLE_RATIO) : size;
  const inset = tier ? Math.round((size - innerSize) / 2) : 0;

  return (
    <span className="relative inline-block shrink-0" style={{ width: size, height: size }} title={label}>
      <span
        className={`absolute flex items-center justify-center border border-neutral-700 bg-neutral-800 text-neutral-600 ${
          round ? "rounded-full" : "rounded-sm"
        } ${dim ? "opacity-50 grayscale" : ""}`}
        style={{ width: innerSize, height: innerSize, top: inset, left: inset }}
      >
        <svg
          viewBox="0 0 24 24"
          width={Math.max(10, Math.round(innerSize * 0.5))}
          height={Math.max(10, Math.round(innerSize * 0.5))}
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          aria-hidden="true"
        >
          <path d="M9.5 9a2.5 2.5 0 0 1 4.9.8c0 1.6-2.4 2-2.4 3.7" />
          <circle cx="12" cy="17.3" r="0.6" fill="currentColor" stroke="none" />
        </svg>
      </span>
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
  );
}
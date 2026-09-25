import type { GoldTier } from "./achievements";

// Reusable tier-border overlays (2026-09-25). Instead of baking 4 separate
// icon variants per badge, most tiered badges now use ONE plain icon (from
// /public/badge-icons/) plus one of these 4 swappable border frames (from
// /public/badge-frames/) layered on top - see TierFramedIcon.tsx for how
// they're combined. Adding a new local-icon badge is then just: drop the
// icon file in badge-icons/, add one line to LOCAL_BADGE_ICONS.
export const TIER_FRAME_SRC: Record<GoldTier, string> = {
  Copper: "/badge-frames/copper.png",
  Silver: "/badge-frames/silver.png",
  Gold: "/badge-frames/gold.png",
  Platinum: "/badge-frames/platinum.png",
};

// How much of the frame image's own square is the transparent "hole" in the
// middle - measured directly off the source art (a 110x110 frame with an
// ~93x93 cutout), so the icon underneath is sized to fill the hole exactly
// instead of guessing at padding by eye.
export const FRAME_HOLE_RATIO = 93 / 110;

export function localBadgeIconSrc(slug: string) {
  return `/badge-icons/${slug}.png`;
}
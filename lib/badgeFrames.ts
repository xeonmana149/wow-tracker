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

// The account-wide badges (see lib/accountAchievements.ts) get their own
// distinct frame (2026-09-30, "They deserve a unique special frame for
// account badges") - an ornate gold/blue medallion border, separate from
// the plain Copper/Silver/Gold/Platinum tier frames above since account
// badges are one-off, not tiered. Re-supplied 2026-09-30 with real alpha
// transparency already baked in (an earlier version had to be chroma-keyed
// off a solid black background instead). The opening isn't a clean
// rectangle - a decorative star medallion pokes into the top and bottom
// center - so ACCOUNT_BADGE_FRAME_HOLE_RATIO uses the WIDEST clear span
// (measured off the source art) rather than the full height; the icon
// underneath ends up slightly overlapped by those top/bottom decorations,
// which is the intended look for this style of frame (same idea as a game
// ranked-border overlay sitting on top of a full portrait). This frame is
// only used for badges still on a plain CDN icon (see AccountBadgeTile's
// `framed` prop) - a badge with its own local custom art (see
// ACCOUNT_ACHIEVEMENT_LOCAL_ICONS) already has its own baked-in border and
// renders full-size with no frame layered on top, same rule the character
// achievement badges already follow.
export const ACCOUNT_BADGE_FRAME_SRC = "/badge-frames/account.png";
export const ACCOUNT_BADGE_FRAME_HOLE_RATIO = 900 / 1254;

// Full stand-alone medallion art (2026-09-25) - a complete laurel-and-gem
// medal per tier, from /public/tier-medals/. Distinct from TIER_FRAME_SRC
// above (a thin border that wraps a badge's own icon): these replace the
// plain 💎🥇🥈🥉 emoji wherever a whole *count* of achievements at a tier is
// shown (leaderboards' tier tallies, the achievement browser's summary bar)
// rather than one specific achievement's art.
export const TIER_MEDAL_SRC: Record<GoldTier, string> = {
  Copper: "/tier-medals/copper.png",
  Silver: "/tier-medals/silver.png",
  Gold: "/tier-medals/gold.png",
  Platinum: "/tier-medals/platinum.png",
};

// Leaderboard position medallions (2026-09-25), replacing the plain
// 🥇🥈🥉 emoji RankBadge used to show for the top 3 spots. Only 1st-3rd get
// dedicated art - anything past that still falls back to a plain number.
export const RANK_ICON_SRC: Record<1 | 2 | 3, string> = {
  1: "/rank-icons/rank-1.png",
  2: "/rank-icons/rank-2.png",
  3: "/rank-icons/rank-3.png",
};
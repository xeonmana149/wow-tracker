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

// "Locked" frame for a badge that hasn't reached its first tier yet
// (2026-09-30, Jordan: "these should have a grey border for the locked
// ones too" - a plain CSS border looked too faint once dimmed, then
// "no use this ... but make it grey", supplying the same ornate frame
// style as the tier frames above, desaturated to steel grey) - shown
// instead of a Copper/Silver/Gold/Platinum frame for a tiered badge with
// no tier reached, so a locked slot still reads as "a badge" rather than
// a bare, frameless icon. Its hole isn't quite square (the corner
// ornaments sit slightly differently than the tier frames'), so this uses
// its own measured ratio rather than FRAME_HOLE_RATIO - the smaller of the
// horizontal/vertical clear spans, so the icon never runs under a corner.
export const LOCKED_FRAME_SRC = "/badge-frames/locked.png";
export const LOCKED_FRAME_HOLE_RATIO = 0.74;

// The account-wide badges (see lib/accountAchievements.ts) get their own
// distinct frame (2026-09-30, "They deserve a unique special frame for
// account badges") - an ornate gold/blue medallion border, separate from
// the plain Copper/Silver/Gold/Platinum tier frames above since account
// badges are one-off, not tiered. Re-supplied 2026-09-30 with real alpha
// transparency already baked in (an earlier version had to be chroma-keyed
// off a solid black background instead). Applied to every account badge,
// local custom art included - Jordan's call (2026-09-30, "no I want the
// ornate frame ... just scaled properly") after an in-between version that
// skipped the frame for local-art badges to avoid double-framing looked
// wrong instead.
//
// ACCOUNT_BADGE_FRAME_HOLE_RATIO deliberately ISN'T the frame's literal
// measured opening (that measured ~72% of the canvas and made the icon look
// tiny inside all that ornamentation, per Jordan's "too small for the
// border" complaint) - it's set high enough that the icon fills almost the
// whole tile, with the frame's own thick gold border overlapping its edges
// on top. That's how this style of decorative "portrait ring" frame is
// normally used (icon full-bleed, frame layered over it), not a precise
// icon-fits-inside-the-hole fit like the thin per-tier frames above.
export const ACCOUNT_BADGE_FRAME_SRC = "/badge-frames/account.png";
export const ACCOUNT_BADGE_FRAME_HOLE_RATIO = 0.94;

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
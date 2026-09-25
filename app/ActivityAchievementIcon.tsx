"use client";

import TierFramedIcon from "./TierFramedIcon";
import BadgePlaceholder from "./BadgePlaceholder";
import { localBadgeIconSrc } from "../lib/badgeFrames";
import { TIERED_LOCAL_ICONS, FLAT_LOCAL_ICONS } from "../lib/achievementBadges";
import type { AchievementTier, TieredAchievementKind, AchievementKind } from "../lib/achievements";

// Renders the actual badge art for an "achievement_earned" activity_events
// row (2026-09-25) - the feed used to just show a generic 🏅 emoji or the
// character's class icon for every achievement event, since the row only
// ever stored a free-text message, not which achievement it was. Now that
// activity_events also carries achievement_kind/achievement_tier (see the
// activity_events migration), this looks the real badge up the same way
// TierFramedIcon/BadgePlaceholder do everywhere else, tiered or flat, with
// the same hover-to-enlarge preview - so an achievement event in the
// Activity sidebar or Recent Activity looks exactly like the badge itself,
// not a stand-in icon.
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
  if (tier) {
    const localIcon = TIERED_LOCAL_ICONS[kind as TieredAchievementKind];
    if (localIcon) {
      return <TierFramedIcon icon={localIcon} tier={tier} label={label} size={size} />;
    }
    return <BadgePlaceholder tier={tier} label={label} size={size} round />;
  }

  const localIcon = FLAT_LOCAL_ICONS[kind as AchievementKind];
  if (!localIcon) {
    return <BadgePlaceholder label={label} size={size} round />;
  }

  // Flat badges have no tier frame, but still get the same hover-to-enlarge
  // preview convention as TierFramedIcon/ShowcaseBadge/AchievementRow.
  const previewSize = 140;
  return (
    <span
      className="group/activityicon relative inline-block shrink-0 align-middle"
      style={{ width: size, height: size }}
    >
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={localBadgeIconSrc(localIcon)}
        alt=""
        draggable={false}
        className="absolute inset-0 h-full w-full rounded-full object-cover"
      />

      <span
        role="tooltip"
        className="pointer-events-none absolute bottom-full left-1/2 z-30 mb-2 flex w-max max-w-[220px] -translate-x-1/2 scale-95 flex-col items-center gap-2 rounded-lg border border-amber-700/70 bg-neutral-950 px-3 py-2.5 text-sm font-medium leading-snug text-amber-100 opacity-0 shadow-lg shadow-black/60 transition-all duration-100 group-hover/activityicon:scale-100 group-hover/activityicon:opacity-100"
      >
        <span className="relative block shrink-0" style={{ width: previewSize, height: previewSize }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={localBadgeIconSrc(localIcon)}
            alt=""
            draggable={false}
            className="absolute inset-0 h-full w-full rounded object-cover"
          />
        </span>
        <span className="text-center">{label}</span>
        <span className="absolute left-1/2 top-full h-2 w-2 -translate-x-1/2 -translate-y-1/2 rotate-45 border-b border-r border-amber-700/70 bg-neutral-950" />
      </span>
    </span>
  );
}

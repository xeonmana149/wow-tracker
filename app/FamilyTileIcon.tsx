"use client";

import { useState } from "react";
import { FAMILY_META, FAMILY_ICON_ART, type AchievementFamily } from "../lib/achievements";
import { wowIconUrl } from "../lib/icons";

// Real WoW icon art for the Account Progress panel's category tiles
// (2026-10-03, Jordan: "hate the AI looking icons" - see FAMILY_ICON_ART's
// own comment in lib/achievements.ts for why this is a separate lookup
// rather than changing FAMILY_META.icon itself). "use client" + its own
// file for the same reason AccountBadgesGrid is split out of AccountView -
// AccountView.tsx is intentionally hook-free, and the onError fallback here
// needs a bit of state.
export default function FamilyTileIcon({ family }: { family: AchievementFamily }) {
  const [failed, setFailed] = useState(false);
  const emoji = FAMILY_META[family].icon;

  if (failed) {
    // Falls back to the original emoji rather than a blank tile if the icon
    // name above ever turns out wrong/moves - never worse than what was
    // there before this change.
    return <span className="text-lg">{emoji}</span>;
  }

  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={wowIconUrl(FAMILY_ICON_ART[family])}
      alt=""
      draggable={false}
      onError={() => setFailed(true)}
      className="mx-auto h-6 w-6 rounded-sm"
    />
  );
}

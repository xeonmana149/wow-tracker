"use client";

import { useState } from "react";
import AccountBadgeTile from "./AccountBadgeTile";
import { ACCOUNT_ACHIEVEMENT_BADGES, accountBadgeIconSrc, type AccountAchievementKind } from "../lib/accountAchievements";
import type { BadgeIconOverrides } from "../lib/badgeIconOverrides";

// Pulled out of AccountView.tsx (2026-10-03, "shouldn't be able to open
// multiple breakdowns like this, it should close the other") so there's a
// single place owning "which one badge tile is pinned open" - AccountView
// itself stays hook-free on purpose (see its own header comment: it's
// rendered from both a "use client" page and a plain server component
// page), so that state has to live in its own small client component
// instead of in AccountView directly. Previously each AccountBadgeTile kept
// its own independent `pinned` boolean, so clicking a second tile left the
// first one's breakdown open too - this component hands every tile the
// SAME openKind value and setter, so pinning one always closes whichever
// other one was open.
export default function AccountBadgesGrid({
  accountBadges,
  accountBadgeProgress,
  accountBadgeBreakdown,
  iconOverrides = {},
}: {
  accountBadges: AccountAchievementKind[];
  accountBadgeProgress: Partial<Record<AccountAchievementKind, { value: number; target: number }>>;
  accountBadgeBreakdown: Partial<Record<AccountAchievementKind, { label: string; value: string }[]>>;
  // Admin-set icon overrides (/dev/badges) - 2026-10-03, see
  // accountBadgeIconSrc in lib/accountAchievements.ts for the fallback
  // chain. Defaults to {} so a caller with nothing loaded yet just gets
  // every badge's normal (local art or CDN) icon.
  iconOverrides?: BadgeIconOverrides;
}) {
  const [openKind, setOpenKind] = useState<AccountAchievementKind | null>(null);

  return (
    <div className="mt-2 flex flex-wrap gap-3">
      {(Object.keys(ACCOUNT_ACHIEVEMENT_BADGES) as AccountAchievementKind[]).map((kind) => {
        const earned = accountBadges.includes(kind);
        const badge = ACCOUNT_ACHIEVEMENT_BADGES[kind];
        const [name, ...rest] = badge.label.split(" - ");
        return (
          <AccountBadgeTile
            key={kind}
            icon={accountBadgeIconSrc(kind, iconOverrides)}
            name={name}
            description={rest.join(" - ")}
            earned={earned}
            // "X / Y" + bar for whatever badges reduce to one fraction
            // (2026-10-03) - see computeAccountBadgeProgress. Some kinds
            // have no entry (nothing trackable), in which case
            // AccountBadgeTile just doesn't show one.
            progress={accountBadgeProgress[kind]}
            // Per-character/class/race breakdown of what's feeding this
            // badge's progress (2026-10-03, "shows the info of just where
            // the stats are coming from") - click the tile to pin it open.
            // Undefined for a badge with no natural breakdown (e.g. The
            // Completionist, which would mean listing 100+ achievement
            // kinds).
            breakdown={accountBadgeBreakdown[kind]}
            pinned={openKind === kind}
            onTogglePin={() => setOpenKind((prev) => (prev === kind ? null : kind))}
            onRequestClose={() => setOpenKind((prev) => (prev === kind ? null : prev))}
          />
        );
      })}
    </div>
  );
}
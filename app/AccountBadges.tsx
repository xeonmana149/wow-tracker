import { ACCOUNT_ACHIEVEMENT_BADGES, type AccountAchievementKind } from "../lib/accountAchievements";
import { wowIconUrl } from "../lib/icons";
import GameIcon from "./GameIcon";

// Small row of account-wide achievement badges - shared between the
// Dashboard (the logged-in user's own badges) and the Friends page (every
// player's badges next to their name), so the two stay visually
// consistent and only need updating in one place.
export default function AccountBadges({
  kinds,
  size = "sm",
}: {
  kinds: AccountAchievementKind[];
  size?: "sm" | "md";
}) {
  if (kinds.length === 0) return null;

  const px = size === "md" ? 26 : 22;

  return (
    <span className="inline-flex flex-wrap items-center gap-1">
      {kinds.map((kind) => {
        const badge = ACCOUNT_ACHIEVEMENT_BADGES[kind];
        if (!badge) return null;
        return (
          <span key={kind} className="inline-block rounded-full ring-2 ring-sky-500/60">
            <GameIcon src={wowIconUrl(badge.icon)} label={badge.label} size={px} round />
          </span>
        );
      })}
    </span>
  );
}

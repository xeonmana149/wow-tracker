import { ACCOUNT_ACHIEVEMENT_BADGES, type AccountAchievementKind } from "../lib/accountAchievements";

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

  const dim = size === "md" ? "h-6 w-6 text-sm" : "h-5 w-5 text-xs";

  return (
    <span className="inline-flex flex-wrap items-center gap-1">
      {kinds.map((kind) => {
        const badge = ACCOUNT_ACHIEVEMENT_BADGES[kind];
        if (!badge) return null;
        return (
          <span
            key={kind}
            title={badge.label}
            className={`grid ${dim} place-items-center rounded-full bg-sky-500/20`}
          >
            {badge.icon}
          </span>
        );
      })}
    </span>
  );
}

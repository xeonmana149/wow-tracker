import type { AchievementTier } from "../lib/achievements";

// A progress bar for a tiered achievement that shows WHERE each tier's
// threshold sits along the full Copper -> Platinum range, not just how far
// along the current tier you are - small colored dots sit just above the
// bar at each threshold's position, filled in once reached and hollow
// otherwise, with a hover tooltip giving the exact tier + value. Shared by
// the leaderboards page and the character achievements browser so the two
// can't drift apart visually.
//
// No "use client" here - it has no hooks or event handlers of its own
// (the tooltip is pure CSS group-hover), so it works fine dropped into
// either a client or server tree.

const TIER_DOT_COLOR: Record<AchievementTier, string> = {
  Copper: "#b45309", // matches ring-amber-700, used for Copper elsewhere
  Silver: "#d4d4d8", // matches ring-gray-300
  Gold: "#facc15", // matches ring-yellow-400
  Platinum: "#67e8f9", // matches ring-cyan-300
};

export default function MilestoneBar({
  value,
  maxValue,
  thresholds,
  className = "",
}: {
  value: number;
  maxValue: number;
  thresholds: { tier: AchievementTier; value: number }[];
  className?: string;
}) {
  const percent = maxValue > 0 ? Math.min(100, Math.round((value / maxValue) * 100)) : 0;

  return (
    <div className={`relative mt-4 ${className}`}>
      {/* Milestone dots, floating just above the bar itself. */}
      <div className="pointer-events-none absolute inset-x-0 -top-2.5 h-2.5">
        {thresholds.map((t) => {
          const pct = maxValue > 0 ? Math.min(100, (t.value / maxValue) * 100) : 0;
          const reached = value >= t.value;
          const color = TIER_DOT_COLOR[t.tier];
          return (
            <span
              key={t.tier}
              className="group/milestone pointer-events-auto absolute top-0 -translate-x-1/2"
              style={{ left: `${pct}%` }}
            >
              <span
                className="block h-2 w-2 rounded-full border"
                style={{
                  backgroundColor: reached ? color : "transparent",
                  borderColor: color,
                  opacity: reached ? 1 : 0.55,
                }}
              />
              <span className="pointer-events-none absolute bottom-full left-1/2 z-20 mb-1 hidden -translate-x-1/2 whitespace-nowrap rounded border border-amber-700/70 bg-neutral-950 px-1.5 py-0.5 text-[10px] font-semibold text-amber-100 shadow-lg shadow-black/60 group-hover/milestone:block">
                {t.tier} · {t.value.toLocaleString()}
              </span>
            </span>
          );
        })}
      </div>

      <div className="h-1.5 w-full overflow-hidden rounded-full bg-neutral-800">
        <div className="h-full rounded-full bg-[#c9a566] transition-[width]" style={{ width: `${percent}%` }} />
      </div>
    </div>
  );
}

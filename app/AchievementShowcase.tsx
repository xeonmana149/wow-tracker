"use client";

import { useState } from "react";
import Link from "next/link";
import { wowIconUrl } from "../lib/icons";
import { localBadgeIconSrc } from "../lib/badgeFrames";
import { TIER_FRAME_SRC, FRAME_HOLE_RATIO } from "../lib/badgeFrames";
import type { AchievementBoardItem } from "./achievementBoard";

// The compact "trophy cabinet" strip that sits below a character's header -
// a handful of icon-first badges (highest tier + most recently earned, see
// pickShowcaseItems in achievementBoard.ts), an earned/total count, and a
// "View All" link into the full achievement browser. Deliberately NOT the
// place to browse every achievement or show locked ones - that's the
// dedicated /character/[id]/achievements page this links to. Keeping this
// one small is the whole point: the character page already has Progress,
// Talents, Professions, Gear, Wishlist and Statistics competing for space.
export default function AchievementShowcase({
  characterId,
  items,
  earnedCount,
  totalCount,
  totalPoints,
}: {
  characterId: string;
  items: AchievementBoardItem[]; // already picked down to what should show (see pickShowcaseItems)
  earnedCount: number;
  totalCount: number;
  totalPoints: number;
}) {
  if (items.length === 0) return null;

  return (
    <div className="mt-3 border-t border-neutral-700 pt-3">
      <div className="flex items-center justify-between">
        <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">
          Achievements
          <span className="ml-2 font-normal normal-case text-gray-500">
            {earnedCount} / {totalCount} · {totalPoints.toLocaleString()} pts
          </span>
        </h3>
        <Link
          href={`/character/${characterId}/achievements`}
          className="text-xs font-semibold text-sky-400 hover:underline"
        >
          View All →
        </Link>
      </div>

      <div className="mt-2 flex flex-wrap gap-3">
        {items.map((item) => (
          <ShowcaseBadge key={item.key} characterId={characterId} item={item} />
        ))}
      </div>
    </div>
  );
}

function ShowcaseBadge({ characterId, item }: { characterId: string; item: AchievementBoardItem }) {
  const [hover, setHover] = useState(false);
  const size = 40;
  const innerSize = Math.round(size * FRAME_HOLE_RATIO);
  const inset = Math.round((size - innerSize) / 2);

  const iconSrc = item.localIcon ? localBadgeIconSrc(item.localIcon) : wowIconUrl(item.cdnIcon);

  return (
    <Link
      href={`/character/${characterId}/achievements#${item.key}`}
      className="group/badge relative flex w-16 flex-col items-center gap-1 text-center"
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
    >
      <span className="relative inline-block shrink-0" style={{ width: size, height: size }}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={iconSrc}
          alt=""
          draggable={false}
          className="absolute rounded-sm object-cover"
          style={
            item.tier && item.localIcon
              ? { width: innerSize, height: innerSize, top: inset, left: inset }
              : { width: size, height: size, top: 0, left: 0 }
          }
        />
        {item.tier && (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={TIER_FRAME_SRC[item.tier]}
            alt=""
            aria-hidden="true"
            draggable={false}
            className="pointer-events-none absolute inset-0 h-full w-full"
          />
        )}
      </span>
      <span className="line-clamp-1 text-[11px] font-semibold text-gray-200">{item.name}</span>
      {item.tier && <span className="text-[10px] text-gray-500">{item.tier}</span>}

      {hover && (
        <div className="pointer-events-none absolute bottom-full left-1/2 z-30 mb-2 w-48 -translate-x-1/2 rounded-lg border border-amber-700/70 bg-neutral-950 p-2.5 text-left shadow-lg shadow-black/60">
          <div className="text-sm font-bold text-amber-100">{item.name}</div>
          {item.tier && <div className="text-xs font-semibold text-amber-400">{item.tier}</div>}
          <div className="mt-1 text-xs leading-snug text-gray-300">{item.description}</div>
          {item.tiered && item.value !== null && (
            <>
              <div className="mt-1.5 text-[11px] text-gray-400">
                {item.value.toLocaleString()}
                {item.nextThreshold !== null && ` / ${item.nextThreshold.toLocaleString()}`}
              </div>
              {item.nextThreshold !== null && (
                <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-neutral-800">
                  <div
                    className="h-full rounded-full bg-[#c9a566]"
                    style={{
                      width: `${Math.min(100, Math.round((item.value / item.nextThreshold) * 100))}%`,
                    }}
                  />
                </div>
              )}
            </>
          )}
          <span className="absolute left-1/2 top-full h-2 w-2 -translate-x-1/2 -translate-y-1/2 rotate-45 border-b border-r border-amber-700/70 bg-neutral-950" />
        </div>
      )}
    </Link>
  );
}

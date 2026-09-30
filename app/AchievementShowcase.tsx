"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { supabase } from "../lib/supabase";
import { localBadgeIconSrc } from "../lib/badgeFrames";
import { TIER_FRAME_SRC, FRAME_HOLE_RATIO, LOCKED_FRAME_SRC } from "../lib/badgeFrames";
import BadgePlaceholder from "./BadgePlaceholder";
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
  ownerId,
  items,
  earnedCount,
  totalCount,
  totalPoints,
}: {
  characterId: string;
  ownerId?: string | null;
  items: AchievementBoardItem[]; // already picked down to what should show (see pickShowcaseItems)
  earnedCount: number;
  totalCount: number;
  totalPoints: number;
}) {
  const [isOwner, setIsOwner] = useState(false);

  useEffect(() => {
    if (!ownerId) return;
    supabase.auth.getUser().then(({ data }) => {
      setIsOwner(data.user?.id === ownerId);
    });
  }, [ownerId]);

  // Only the owner gets a reason to visit an empty showcase (to pick
  // something to show off) - everyone else just sees nothing here yet.
  if (items.length === 0 && !isOwner) return null;

  return (
    <div className="mt-3 border-t border-neutral-700 pt-3">
      <div className="flex items-center justify-between">
        <h3 className="rounded bg-neutral-950/70 px-2 py-1 text-xs font-semibold uppercase tracking-wide text-amber-100">
          Achievements
          <span className="ml-2 font-normal normal-case text-gray-300">
            {earnedCount} / {totalCount} · {totalPoints.toLocaleString()} pts
          </span>
        </h3>
        {/* "hero-actions" is the same wrapper class the character page's
            header buttons (Talent planner, Edit Character, Delete
            Character) use - whatever global CSS gives those their
            maroon/gold button look is keyed off this class plus the
            button's own className (the header's "Talent planner" Link is
            styled bg-blue-600 in its own Tailwind classes but still renders
            maroon/gold, so this matches that exact className rather than
            guessing new colors), which keeps this button visually
            identical to "the rest of the site" without hardcoding a color
            that could drift out of sync. Dropped "Choose showcase" per
            Jordan (2026-09-28) - one button into the same achievements
            page is enough.
        */}
        <div className="hero-actions flex items-center gap-2">
          <Link
            href={`/character/${characterId}/achievements`}
            className="rounded bg-blue-600 px-4 py-2 text-white"
          >
            View Achievements
          </Link>
        </div>
      </div>

      {items.length === 0 ? (
        <p className="mt-2 text-xs text-gray-500">
          Nothing pinned yet - pick a few earned achievements to show off here.
        </p>
      ) : (
        <div className="mt-2 flex flex-wrap gap-3">
          {items.map((item) => (
            <ShowcaseBadge key={item.key} characterId={characterId} item={item} />
          ))}
        </div>
      )}
    </div>
  );
}

// Exported (2026-09-28) so the new Account Overview page's "Featured
// Achievements" gallery can reuse this exact tile - icon/frame/placeholder
// rendering, hover preview, everything - instead of a second hand-copied
// version that could drift out of sync with this one. Every existing caller
// here on the character page only ever passes earned items, so the new
// `dimmed` prop below defaults to false and changes nothing for them.
export function ShowcaseBadge({
  characterId,
  item,
  dimmed = false,
}: {
  characterId: string;
  item: AchievementBoardItem;
  // True for an unearned item shown anyway (e.g. "closest to completion" on
  // the Account page) - desaturates the art and swaps the tier line for a
  // live progress fraction instead, per Jordan's "unearned should look
  // visually distinct, earned/unearned" request on the layout rework.
  dimmed?: boolean;
}) {
  const [hover, setHover] = useState(false);
  // Bumped again (2026-09-25) - 40px -> 56px -> 72px, now that the badges
  // have proper hand-picked art instead of generic WoW CDN icons. Worth the
  // extra room to actually read the artwork at a glance.
  const size = 72;
  // LOCKED_FRAME_SRC is copper.png too (just greyed via CSS below), so the
  // locked state reuses this exact sizing - no separate ratio needed.
  const innerSize = Math.round(size * FRAME_HOLE_RATIO);
  const inset = Math.round((size - innerSize) / 2);

  // Hover preview - blows the same art up big enough to actually see the
  // detail in it, since even at 72px a hand-painted badge icon is small.
  const previewSize = 180;
  const previewInner = Math.round(previewSize * FRAME_HOLE_RATIO);
  const previewInset = Math.round((previewSize - previewInner) / 2);

  return (
    <Link
      href={`/character/${characterId}/achievements#${item.key}`}
      className="group/badge relative flex w-24 flex-col items-center gap-1 text-center"
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
    >
      <span
        className={`relative inline-block shrink-0 ${dimmed ? "opacity-50 grayscale" : ""}`}
        style={{ width: size, height: size }}
      >
        {item.localIcon ? (
          <>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={localBadgeIconSrc(item.localIcon)}
              alt=""
              draggable={false}
              className="absolute rounded-sm object-cover"
              style={{ width: innerSize, height: innerSize, top: inset, left: inset }}
            />
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={item.tier ? TIER_FRAME_SRC[item.tier] : LOCKED_FRAME_SRC}
              alt=""
              aria-hidden="true"
              draggable={false}
              className={`pointer-events-none absolute inset-0 h-full w-full ${item.tier ? "" : "grayscale"}`}
            />
          </>
        ) : (
          <BadgePlaceholder tier={item.tier} label={item.name} size={size} />
        )}
      </span>
      <span className="line-clamp-1 rounded bg-neutral-950/70 px-1.5 py-0.5 text-[11px] font-semibold text-white">
        {item.name}
      </span>
      {dimmed && item.tiered && item.value !== null ? (
        <span className="rounded bg-neutral-950/70 px-1.5 py-0.5 text-[10px] text-gray-400">
          {item.value.toLocaleString()}
          {item.nextThreshold !== null && ` / ${item.nextThreshold.toLocaleString()}`}
        </span>
      ) : (
        item.tier && (
          <span className="rounded bg-neutral-950/70 px-1.5 py-0.5 text-[10px] text-gray-300">{item.tier}</span>
        )
      )}

      {hover && (
        <div className="pointer-events-none absolute bottom-full left-1/2 z-30 mb-2 w-56 -translate-x-1/2 rounded-lg border border-amber-700/70 bg-neutral-950 p-2.5 text-left shadow-lg shadow-black/60">
          <span className="relative mx-auto mb-2 block" style={{ width: previewSize, height: previewSize }}>
            {item.localIcon ? (
              <>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={localBadgeIconSrc(item.localIcon)}
                  alt=""
                  draggable={false}
                  className="absolute rounded object-cover"
                  style={{ width: previewInner, height: previewInner, top: previewInset, left: previewInset }}
                />
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={item.tier ? TIER_FRAME_SRC[item.tier] : LOCKED_FRAME_SRC}
                  alt=""
                  aria-hidden="true"
                  draggable={false}
                  className={`pointer-events-none absolute inset-0 h-full w-full ${item.tier ? "" : "grayscale"}`}
                />
              </>
            ) : (
              <BadgePlaceholder tier={item.tier} label={item.name} size={previewSize} />
            )}
          </span>
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
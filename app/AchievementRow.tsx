"use client";

import { useState } from "react";
import { localBadgeIconSrc, TIER_FRAME_SRC, FRAME_HOLE_RATIO, TIER_MEDAL_SRC } from "../lib/badgeFrames";
import { iconUrlForFileId } from "../lib/icons";
import type { AchievementBoardItem } from "./achievementBoard";
import MilestoneBar from "./MilestoneBar";
import BadgePlaceholder from "./BadgePlaceholder";

// Pulled out of CharacterAchievementsPage.tsx (2026-09-27) so the exact
// same achievement card - border, tier frame, milestone bar, collapsible
// Legacy Challenge checklist - can be reused by the account-wide
// AccountLegacyPage without duplicating ~250 lines of JSX. isOwner/pinned/
// onTogglePin are the character-page showcase-pinning affordance; pass
// isOwner={false} (and a no-op onTogglePin) anywhere that concept doesn't
// apply, like the account-wide Legacy Challenges page - there's no single
// character to pin a showcase entry to there.
export default function AchievementRow({
  item,
  isOwner,
  pinned,
  onTogglePin,
}: {
  item: AchievementBoardItem;
  isOwner: boolean;
  pinned: boolean;
  onTogglePin: () => void;
}) {
  // Collapsed by default, same as the in-game Legacy Challenges panel's own
  // +/- toggle (item.criteria only exists at all for a Legacy Challenge
  // with more than one criterion - see achievementBoard.ts).
  const [expanded, setExpanded] = useState(false);

  // Bumped again (2026-09-25) - 48px -> 64px -> 80px, now that the badges
  // have proper hand-picked art instead of generic WoW CDN icons. Worth the
  // extra room to actually read the artwork here, where it's the main
  // visual on the row.
  const size = 80;
  const innerSize = Math.round(size * FRAME_HOLE_RATIO);
  const inset = Math.round((size - innerSize) / 2);

  // The bar now runs the FULL Copper -> Platinum range (previously it reset
  // to 0-100% of just "progress toward the next tier"), so the milestone
  // dots for every tier can sit at their real position along one bar.
  const maxThreshold = item.thresholds?.[item.thresholds.length - 1]?.value ?? 1;

  // Hover preview - blows the same art up big enough to actually see the
  // detail in it, since even at 80px a hand-painted badge icon is still
  // pretty small.
  const previewSize = 220;
  const previewInner = Math.round(previewSize * FRAME_HOLE_RATIO);
  const previewInset = Math.round((previewSize - previewInner) / 2);

  // Legacy Challenges have no hand-picked local art - there are 111 of
  // them, straight from Blizzard - so they fall back to the real WoW icon
  // via remoteIcon/iconUrlForFileId instead. Framed with the exact same
  // tier-frame/greyed-border treatment as a localIcon below, so they're
  // visually indistinguishable from a community achievement except for
  // which icon shows through the frame.
  const iconSrc = item.localIcon ? localBadgeIconSrc(item.localIcon) : iconUrlForFileId(item.remoteIcon);

  return (
    <div
      id={item.key}
      className={`flex items-center gap-3 rounded-lg border p-3 ${
        item.earned ? "border-neutral-700 bg-neutral-900/40" : "border-neutral-800 bg-neutral-900/20"
      }`}
    >
      <span className="group/rowicon relative inline-block shrink-0" style={{ width: size, height: size }}>
        {iconSrc ? (
          <>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={iconSrc}
              alt=""
              draggable={false}
              className={`absolute rounded-sm object-cover ${!item.earned ? "grayscale" : ""}`}
              style={
                item.tier || !item.earned
                  ? { width: innerSize, height: innerSize, top: inset, left: inset }
                  : { width: size, height: size, top: 0, left: 0 }
              }
            />
            {item.earned && item.tier && (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={TIER_FRAME_SRC[item.tier]}
                alt=""
                aria-hidden="true"
                draggable={false}
                className="pointer-events-none absolute inset-0 h-full w-full"
              />
            )}
            {!item.earned && (
              // Locked/not-yet-earned border (2026-09-26) - reuses the
              // Copper tier frame art, desaturated to grey via CSS filter
              // rather than a separate asset, so every un-earned badge
              // (tiered or flat/one-off) reads as "locked" at a glance
              // instead of just floating with no border at all.
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={TIER_FRAME_SRC.Copper}
                alt=""
                aria-hidden="true"
                draggable={false}
                className="pointer-events-none absolute inset-0 h-full w-full"
                style={{ filter: "grayscale(1) brightness(1.15)" }}
              />
            )}
          </>
        ) : (
          <BadgePlaceholder tier={item.tier} label={item.name} size={size} dim={!item.earned} />
        )}

        {/* Hover-to-enlarge preview of the badge art. */}
        <span
          role="tooltip"
          className="pointer-events-none absolute left-0 top-full z-30 mt-2 scale-95 rounded-lg border border-amber-700/70 bg-neutral-950 p-2 opacity-0 shadow-lg shadow-black/60 transition-all duration-100 group-hover/rowicon:scale-100 group-hover/rowicon:opacity-100"
        >
          <span className="relative block" style={{ width: previewSize, height: previewSize }}>
            {iconSrc ? (
              <>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={iconSrc}
                  alt=""
                  draggable={false}
                  className={`absolute rounded object-cover ${!item.earned ? "grayscale" : ""}`}
                  style={
                    item.tier || !item.earned
                      ? { width: previewInner, height: previewInner, top: previewInset, left: previewInset }
                      : { width: previewSize, height: previewSize, top: 0, left: 0 }
                  }
                />
                {item.earned && item.tier && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={TIER_FRAME_SRC[item.tier]}
                    alt=""
                    aria-hidden="true"
                    draggable={false}
                    className="pointer-events-none absolute inset-0 h-full w-full"
                  />
                )}
                {!item.earned && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={TIER_FRAME_SRC.Copper}
                    alt=""
                    aria-hidden="true"
                    draggable={false}
                    className="pointer-events-none absolute inset-0 h-full w-full"
                    style={{ filter: "grayscale(1) brightness(1.15)" }}
                  />
                )}
              </>
            ) : (
              <BadgePlaceholder tier={item.tier} label={item.name} size={previewSize} dim={!item.earned} />
            )}
          </span>
        </span>
      </span>

      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-baseline gap-2">
          <span className={`font-bold ${item.earned ? "text-white" : "text-gray-500"}`}>{item.name}</span>
          {item.tier && (
            <span
              className={`flex items-center gap-1 text-xs font-semibold ${
                item.earned ? "text-amber-400" : "text-gray-500"
              }`}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={TIER_MEDAL_SRC[item.tier]}
                alt=""
                draggable={false}
                className={`h-5 w-5 object-contain ${item.earned ? "" : "grayscale opacity-70"}`}
              />
              {item.tier}
            </span>
          )}
        </div>
        <div className="text-xs text-gray-500">{item.description}</div>

        {item.tiered ? (
          <>
            <MilestoneBar
              value={item.value ?? 0}
              maxValue={maxThreshold}
              thresholds={item.thresholds ?? []}
              className="w-full max-w-sm"
            />
            <div className="mt-1 text-[11px] text-gray-500">
              {(item.value ?? 0).toLocaleString()}
              {item.nextThreshold !== null ? ` / ${item.nextThreshold.toLocaleString()}` : " (maxed)"}
              {item.thresholds && (
                <span className="ml-2">
                  {item.thresholds.map((t) => `${t.tier} ${t.value.toLocaleString()}`).join(" · ")}
                </span>
              )}
            </div>

            {item.criteria && item.criteria.length > 0 && (
              <div className="mt-1.5">
                {/* Same collapse/expand idea as the in-game achievement
                    pane's own +/- square next to the description - hidden
                    by default so 111 Legacy Challenges don't turn into a
                    wall of checklist text. */}
                <button
                  type="button"
                  onClick={() => setExpanded((e) => !e)}
                  className="flex items-center gap-1.5 text-[11px] font-semibold text-amber-400/80 hover:text-amber-300"
                >
                  <span className="flex h-3.5 w-3.5 shrink-0 items-center justify-center rounded-sm border border-amber-700/70 bg-neutral-950 text-[10px] leading-none">
                    {expanded ? "−" : "+"}
                  </span>
                  {expanded ? "Hide checklist" : "Show checklist"}
                </button>
                {expanded && (
                  <ul className="mt-1.5 space-y-0.5 text-[11px]">
                    {item.criteria.map((c, i) => (
                      <li key={i} className={c.completed ? "text-gray-300" : "text-gray-600"}>
                        {c.completed ? "✓" : "○"} {c.text}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            )}
          </>
        ) : (
          <div className="mt-1 text-[11px] text-gray-500">{item.earned ? "Earned" : "Not yet earned"}</div>
        )}
      </div>

      {isOwner && item.earned && (
        <button
          type="button"
          onClick={onTogglePin}
          title={pinned ? "Remove from character page showcase" : "Pin to character page showcase"}
          className={`shrink-0 text-xl leading-none transition-colors ${
            pinned ? "text-amber-400" : "text-neutral-600 hover:text-amber-300"
          }`}
        >
          {pinned ? "★" : "☆"}
        </button>
      )}

      <span className={`shrink-0 text-sm font-bold ${item.earned ? "text-[#c9a566]" : "text-gray-600"}`}>
        {item.earned ? `+${item.points}` : "—"} pts
      </span>
    </div>
  );
}

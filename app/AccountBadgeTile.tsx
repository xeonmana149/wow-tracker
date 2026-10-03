"use client";

import { useEffect, useRef, useState } from "react";
import { ACCOUNT_BADGE_FRAME_SRC, ACCOUNT_BADGE_FRAME_HOLE_RATIO } from "../lib/badgeFrames";

// Hover-preview tile for the Account Badges row (2026-09-30, "now I want
// the hover system that achievements get ... implement for account
// badges", then "They deserve a unique special frame for account badges") -
// same enlarged-preview-on-hover treatment as ShowcaseBadge (see
// AchievementShowcase.tsx), plus its own ornate frame overlay (see
// lib/badgeFrames.ts's ACCOUNT_BADGE_FRAME_SRC) instead of ShowcaseBadge's
// tier frames, since account badges are one-off, not tiered. Pulled into
// its own "use client" component because AccountView.tsx has no hooks/state
// on purpose (it's rendered from both a "use client" page and a plain
// server component page - see its own header comment), and hover needs
// local state somewhere. No Link wrapper since there's nowhere for one of
// these to link to yet.
//
// The ornate frame is ALWAYS shown, local custom art included - Jordan's
// call (2026-09-30, "no I want the ornate frame ... just scaled properly")
// after an in-between version that skipped the frame for local-art badges
// looked wrong instead. Sizing the icon "properly" is handled entirely by
// ACCOUNT_BADGE_FRAME_HOLE_RATIO in lib/badgeFrames.ts (deliberately wider
// than the frame's literal opening so the icon fills almost the whole
// tile) - there's no more unframed rendering path to branch on.
export default function AccountBadgeTile({
  icon,
  name,
  description,
  earned,
  progress,
  breakdown,
  pinned,
  onTogglePin,
  onRequestClose,
}: {
  icon: string; // resolved image URL (e.g. from wowIconUrl() or a local /account-badge-icons/ path)
  name: string;
  description: string;
  earned: boolean;
  // "X / Y" + bar, same treatment ShowcaseBadge gives an unearned tiered
  // character achievement (2026-10-03, "copy that and do exactly the same
  // for the account badges... for all account badges that are trackable") -
  // see computeAccountBadgeProgress in lib/accountAchievements.ts for which
  // badges get one. Undefined for a badge with no single meaningful
  // fraction, which just falls back to the plain "Not yet earned" line.
  progress?: { value: number; target: number };
  // Per-character/class/race breakdown of what's feeding this badge's
  // progress (2026-10-03, "if clicked on it shows the info of just where
  // the stats are coming from... Master Merchant could have a breakdown of
  // where each amount of gold is coming from each character") - see
  // computeAccountBadgeBreakdown in lib/accountAchievements.ts. Undefined
  // for a badge with no natural breakdown, in which case clicking the tile
  // does nothing extra.
  breakdown?: { label: string; value: string }[];
  // Pinned-open state is now CONTROLLED by the parent grid (2026-10-03,
  // "shouldn't be able to open multiple breakdowns like this, it should
  // close the other") rather than each tile keeping its own independent
  // `pinned` boolean - that let every tile pin open at once, since nothing
  // tied them together. The parent keeps a single "which one kind is open"
  // value and only ever lets one tile be pinned at a time.
  pinned: boolean;
  // Click the icon - parent decides whether that opens this tile (and
  // closes whichever other one was open) or closes this one.
  onTogglePin: () => void;
  // Fired when this tile is pinned and a mousedown lands outside it
  // anywhere else on the page - "clicking off on anything on the website
  // should close it as well".
  onRequestClose: () => void;
}) {
  const [hover, setHover] = useState(false);
  const open = hover || pinned;
  const rootRef = useRef<HTMLSpanElement>(null);
  const size = 56; // matches the h-14 w-14 tile AccountView used before this
  const innerSize = Math.round(size * ACCOUNT_BADGE_FRAME_HOLE_RATIO);
  const inset = Math.round((size - innerSize) / 2);

  // Closes this tile's breakdown the moment a click lands anywhere else on
  // the page - the document listener is only attached while this tile is
  // actually pinned open, so unrelated tiles pay no cost for it.
  useEffect(() => {
    if (!pinned) return;
    function handlePointerDown(e: MouseEvent) {
      if (rootRef.current && !rootRef.current.contains(e.target as Node)) {
        onRequestClose();
      }
    }
    document.addEventListener("mousedown", handlePointerDown);
    return () => document.removeEventListener("mousedown", handlePointerDown);
  }, [pinned, onRequestClose]);

  // 190, up from 140 (2026-10-02, "make the icon hover size for account
  // badges a little bigger to better see the artwork") - w-64 below was
  // bumped to match so the frame still has its p-2.5 padding on both sides
  // instead of crowding/overflowing the tooltip box.
  const previewSize = 190;
  const previewInner = Math.round(previewSize * ACCOUNT_BADGE_FRAME_HOLE_RATIO);
  const previewInset = Math.round((previewSize - previewInner) / 2);

  return (
    <span
      ref={rootRef}
      className="group/badge relative flex w-16 flex-col items-center gap-1 text-center"
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
    >
      <button
        type="button"
        onClick={onTogglePin}
        title={breakdown ? "Click for a breakdown" : undefined}
        className={`relative inline-block shrink-0 ${earned ? "" : "opacity-40 grayscale"} ${
          breakdown ? "cursor-pointer" : "cursor-default"
        }`}
        style={{ width: size, height: size }}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={icon}
          alt=""
          draggable={false}
          className="absolute rounded-sm object-cover"
          style={{ width: innerSize, height: innerSize, top: inset, left: inset }}
        />
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={ACCOUNT_BADGE_FRAME_SRC}
          alt=""
          aria-hidden="true"
          draggable={false}
          className="pointer-events-none absolute inset-0 h-full w-full"
        />
      </button>
      <span className="line-clamp-2 rounded bg-neutral-950/70 px-1 py-0.5 text-[10px] font-semibold leading-tight text-white">
        {name}
      </span>

      {open && (
        <div
          className={`absolute bottom-full left-1/2 z-30 mb-2 w-64 -translate-x-1/2 rounded-lg border border-amber-700/70 bg-neutral-950 p-2.5 text-left shadow-lg shadow-black/60 ${
            pinned ? "" : "pointer-events-none"
          }`}
        >
          <span
            className={`relative mx-auto mb-2 block ${earned ? "" : "opacity-40 grayscale"}`}
            style={{ width: previewSize, height: previewSize }}
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={icon}
              alt=""
              draggable={false}
              className="absolute rounded object-cover"
              style={{ width: previewInner, height: previewInner, top: previewInset, left: previewInset }}
            />
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={ACCOUNT_BADGE_FRAME_SRC}
              alt=""
              aria-hidden="true"
              draggable={false}
              className="pointer-events-none absolute inset-0 h-full w-full"
            />
          </span>
          <div className="text-sm font-bold text-amber-100">{name}</div>
          <div className="mt-1 text-xs leading-snug text-gray-300">{description}</div>
          {!earned &&
            (progress ? (
              <>
                <div className="mt-1.5 text-[11px] text-gray-400">
                  {progress.value.toLocaleString()} / {progress.target.toLocaleString()}
                </div>
                <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-neutral-800">
                  <div
                    className="h-full rounded-full bg-[#c9a566]"
                    style={{
                      width: `${
                        progress.target > 0 ? Math.min(100, Math.round((progress.value / progress.target) * 100)) : 0
                      }%`,
                    }}
                  />
                </div>
              </>
            ) : (
              <div className="mt-1.5 text-[11px] text-gray-500">Not yet earned</div>
            ))}

          {/* Per-character/class/race breakdown (2026-10-03) - click the
              tile to pin this open and actually read it; a quick hover
              alone shows it too, but pinning is what lets the mouse move
              away without the tooltip vanishing mid-read. */}
          {breakdown && breakdown.length > 0 && (
            <div className="mt-2 border-t border-neutral-800 pt-2">
              <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-500">
                {pinned ? "Breakdown" : "Click for a breakdown"}
              </div>
              {pinned && (
                <ul className="mt-1 max-h-40 space-y-0.5 overflow-y-auto pr-1 text-[11px]">
                  {breakdown.map((line, i) => (
                    <li key={i} className="flex items-center justify-between gap-2 text-gray-300">
                      <span className="truncate">{line.label}</span>
                      <span className="shrink-0 text-gray-500">{line.value}</span>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          )}
          <span className="absolute left-1/2 top-full h-2 w-2 -translate-x-1/2 -translate-y-1/2 rotate-45 border-b border-r border-amber-700/70 bg-neutral-950" />
        </div>
      )}
    </span>
  );
}
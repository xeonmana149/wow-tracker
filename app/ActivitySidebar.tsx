"use client";

import { useCallback, useRef, useState } from "react";
import ActivityFeed from "./ActivityFeed";

// A slim, always-visible tab docked to the right edge of the screen, on
// every page (it lives in the root layout). Clicking it slides a full
// activity feed panel in over the page; clicking the backdrop or the
// close button slides it back out.
//
// The tab also carries a small badge that lights up when something new
// happens while the panel is closed - otherwise there's no way to tell
// the feed is even there. Opening the panel clears it.
export default function ActivitySidebar() {
  const [open, setOpen] = useState(false);
  const [unseenCount, setUnseenCount] = useState(0);

  // A ref rather than reading `open` directly in the callback, so a live
  // event that arrives while the panel happens to be open doesn't get
  // counted as "missed" once it's closed again.
  const openRef = useRef(open);

  function setOpenState(next: boolean) {
    openRef.current = next;
    setOpen(next);
    if (next) setUnseenCount(0);
  }

  const handleNewEvent = useCallback(() => {
    if (!openRef.current) {
      setUnseenCount((n) => n + 1);
    }
  }, []);

  const badgeText = unseenCount > 9 ? "9+" : String(unseenCount);

  return (
    <>
      {open && (
        <div
          className="fixed inset-0 z-40 bg-black/50"
          onClick={() => setOpenState(false)}
          aria-hidden="true"
        />
      )}

      <div
        className={`fixed right-0 top-0 z-50 h-screen w-80 max-w-[85vw] transform bg-neutral-950 shadow-2xl transition-transform duration-300 ease-out ${
          open ? "translate-x-0" : "translate-x-full"
        }`}
      >
        <div className="flex h-full flex-col p-3">
          <button
            onClick={() => setOpenState(false)}
            className="mb-2 self-end rounded px-2 py-1 text-sm text-gray-400 hover:bg-neutral-800 hover:text-white"
          >
            Close ✕
          </button>
          <div className="min-h-0 flex-1">
            <ActivityFeed onNewEvent={handleNewEvent} />
          </div>
        </div>
      </div>

      {!open && (
        <button
          onClick={() => setOpenState(true)}
          className="fixed right-0 top-1/2 z-40 -translate-y-1/2 rounded-l-lg border border-neutral-700 bg-neutral-900/90 px-2 py-4 text-xs font-semibold uppercase tracking-wide text-gray-300 shadow-lg hover:bg-neutral-800 hover:text-white"
        >
          {unseenCount > 0 && (
            <span
              className="absolute -left-2 -top-2 grid h-5 w-5 place-items-center rounded-full bg-red-600 text-[10px] font-bold text-white shadow"
              aria-label={`${unseenCount} new activity update${unseenCount === 1 ? "" : "s"}`}
            >
              {badgeText}
            </span>
          )}
          <span style={{ writingMode: "vertical-rl" }}>Activity</span>
        </button>
      )}
    </>
  );
}
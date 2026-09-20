"use client";

import { useState } from "react";
import ActivityFeed from "./ActivityFeed";

// A slim, always-visible tab docked to the right edge of the screen, on
// every page (it lives in the root layout). Clicking it slides a full
// activity feed panel in over the page; clicking the backdrop or the
// close button slides it back out. Nothing is ever on screen competing
// with the page's own content unless you've asked for it - solves the
// "floating panel collides with the header" problem the fixed version had.
export default function ActivitySidebar() {
  const [open, setOpen] = useState(false);

  return (
    <>
      {open && (
        <div
          className="fixed inset-0 z-40 bg-black/50"
          onClick={() => setOpen(false)}
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
            onClick={() => setOpen(false)}
            className="mb-2 self-end rounded px-2 py-1 text-sm text-gray-400 hover:bg-neutral-800 hover:text-white"
          >
            Close ✕
          </button>
          <div className="min-h-0 flex-1">
            <ActivityFeed />
          </div>
        </div>
      </div>

      {!open && (
        <button
          onClick={() => setOpen(true)}
          className="fixed right-0 top-1/2 z-40 -translate-y-1/2 rounded-l-lg border border-neutral-700 bg-neutral-900/90 px-2 py-4 text-xs font-semibold uppercase tracking-wide text-gray-300 shadow-lg hover:bg-neutral-800 hover:text-white"
          style={{ writingMode: "vertical-rl" }}
        >
          Activity
        </button>
      )}
    </>
  );
}

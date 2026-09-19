"use client";

import { useEffect, useState } from "react";

// Save Blizzard's roadmap picture as public/roadmap.jpg. If it isn't there, this stays hidden.
const SRC = "/roadmap.jpg";
const ALT = "World of Warcraft: Forever roadmap, 2026 to 2027";

export default function RoadmapImage() {
  const [missing, setMissing] = useState(false);
  const [open, setOpen] = useState(false);

  // While the big picture is open: Esc closes it, and the page behind doesn't scroll
  useEffect(() => {
    if (!open) return;

    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }
    window.addEventListener("keydown", onKey);

    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = previous;
    };
  }, [open]);

  if (missing) return null;

  return (
    <figure className="xl:w-[48%] xl:shrink-0">
      <button
        type="button"
        onClick={() => setOpen(true)}
        title="Click to enlarge"
        style={{ cursor: "zoom-in" }}
        className="block w-full overflow-hidden rounded border border-neutral-700"
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={SRC}
          alt={ALT}
          onError={() => setMissing(true)}
          className="block h-auto w-full"
        />
      </button>
      <figcaption className="mt-2 text-xs text-gray-500">
        Official roadmap picture. Click to enlarge. Image © Blizzard Entertainment.
      </figcaption>

      {open && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Roadmap"
          onClick={() => setOpen(false)}
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/85 p-4"
        >
          <button
            type="button"
            onClick={() => setOpen(false)}
            className="absolute right-4 top-4 rounded bg-neutral-800 px-4 py-2 text-white"
          >
            Close ✕
          </button>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={SRC}
            alt={ALT}
            className="max-h-[90vh] max-w-[95vw] rounded object-contain"
          />
        </div>
      )}
    </figure>
  );
}
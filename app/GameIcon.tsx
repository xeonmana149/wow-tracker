"use client";

import { useEffect, useState } from "react";
import { iconUrl } from "../lib/icons";

export default function GameIcon({
  name,
  src,
  label,
  size = 32,
  round = false,
}: {
  // Local icon by name (looked up under /talent-icons/) - used for
  // classes, races and professions, which are bundled locally.
  name?: string | null;
  // A direct image URL - used for achievement badges, which pull from the
  // live Wowhead/zamimg icon CDN instead (see wowIconUrl in lib/icons.ts),
  // since there are far more of those than are worth bundling locally.
  // Takes priority over `name` if both are somehow given.
  src?: string | null;
  label: string;
  size?: number;
  round?: boolean;
}) {
  const [failed, setFailed] = useState(false);
  const shape = round ? "rounded-full" : "rounded";
  const box = { width: size, height: size };
  const resolvedSrc = src ?? (name ? iconUrl(name) : null);

  // Without this, once one icon 404s (setting failed=true), this component
  // instance would show the fallback tile forever - even after `src`/`name`
  // later changes to a working icon (e.g. after saving a new icon override) -
  // because React re-uses the same component instance and `failed` never
  // had a reason to reset. Resetting it whenever the resolved URL changes
  // means a new icon always gets its own fresh attempt to load.
  useEffect(() => {
    setFailed(false);
  }, [resolvedSrc]);

  const image =
    !resolvedSrc || failed ? (
      <span
        className={`inline-flex shrink-0 items-center justify-center border border-amber-900/70 bg-neutral-900 text-[10px] font-bold text-amber-200 ${shape}`}
        style={box}
      >
        {label.slice(0, 2).toUpperCase()}
      </span>
    ) : (
      // eslint-disable-next-line @next/next/no-img-element
      <img
        src={resolvedSrc}
        alt={label}
        width={size}
        height={size}
        draggable={false}
        onError={() => setFailed(true)}
        className={`shrink-0 border border-amber-900/70 object-cover ${shape}`}
        style={box}
      />
    );

  // A custom themed tooltip instead of the browser's plain title attribute -
  // shown on hover via group-hover, positioned above the icon. `group/icon`
  // is a scoped group name so nested GameIcons (or other hoverable things
  // nearby) don't accidentally trigger each other's tooltips.
  return (
    <span className="group/icon relative inline-flex">
      {image}
      <span
        role="tooltip"
        className="pointer-events-none absolute bottom-full left-1/2 z-30 mb-2 w-max max-w-[260px] -translate-x-1/2 scale-95 rounded-lg border border-amber-700/70 bg-neutral-950 px-3 py-2 text-sm font-medium leading-snug text-amber-100 opacity-0 shadow-lg shadow-black/60 transition-all duration-100 group-hover/icon:scale-100 group-hover/icon:opacity-100"
      >
        {label}
        <span className="absolute left-1/2 top-full h-2 w-2 -translate-x-1/2 -translate-y-1/2 rotate-45 border-b border-r border-amber-700/70 bg-neutral-950" />
      </span>
    </span>
  );
}
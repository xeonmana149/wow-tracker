"use client";

import { useState } from "react";
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

  if (!resolvedSrc || failed) {
    return (
      <span
        title={label}
        className={`inline-flex shrink-0 items-center justify-center border border-amber-900/70 bg-neutral-900 text-[10px] font-bold text-amber-200 ${shape}`}
        style={box}
      >
        {label.slice(0, 2).toUpperCase()}
      </span>
    );
  }

  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={resolvedSrc}
      alt={label}
      title={label}
      width={size}
      height={size}
      draggable={false}
      onError={() => setFailed(true)}
      className={`shrink-0 border border-amber-900/70 object-cover ${shape}`}
      style={box}
    />
  );
}

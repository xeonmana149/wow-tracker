"use client";

import { useState } from "react";
import { iconUrl } from "../lib/icons";

export default function GameIcon({
  name,
  label,
  size = 32,
  round = false,
}: {
  name?: string | null;
  label: string;
  size?: number;
  round?: boolean;
}) {
  const [failed, setFailed] = useState(false);
  const shape = round ? "rounded-full" : "rounded";
  const box = { width: size, height: size };

  if (!name || failed) {
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
      src={iconUrl(name)}
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
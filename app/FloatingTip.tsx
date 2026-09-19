"use client";

import { useEffect, useState, type CSSProperties, type ReactNode } from "react";

// A box that follows the mouse, and flips to the other side near the screen edges
export default function FloatingTip({
  start,
  children,
}: {
  start: { x: number; y: number };
  children: ReactNode;
}) {
  const [pos, setPos] = useState(start);

  useEffect(() => {
    function onMove(e: globalThis.MouseEvent) {
      setPos({ x: e.clientX, y: e.clientY });
    }
    window.addEventListener("mousemove", onMove);
    return () => window.removeEventListener("mousemove", onMove);
  }, []);

  const style: CSSProperties = {};
  if (pos.x > window.innerWidth - 380) style.right = window.innerWidth - pos.x + 16;
  else style.left = pos.x + 16;
  if (pos.y > window.innerHeight - 340) style.bottom = window.innerHeight - pos.y + 16;
  else style.top = pos.y + 16;

  return (
    <div
      className="pointer-events-none fixed z-50 w-[340px] max-w-[90vw] rounded-md border border-neutral-400 bg-black/95 p-3 shadow-xl"
      style={style}
    >
      {children}
    </div>
  );
}
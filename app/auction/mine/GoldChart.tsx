"use client";

import { useState } from "react";

// Total gold across your characters over time. One series, so no legend -
// the heading names it. Steps rather than slopes: a balance only changes
// when you play.

const W = 720;
const H = 200;
const PAD_L = 60;
const PAD_R = 16;
const TOP = 12;
const BOT = H - 26;
const LINE = "#3987e5";
const GRID = "#2c261d";
const AXIS = "#a89a7c";
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

const dateLabel = (t: number) => {
  const d = new Date(t * 1000);
  return `${MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}`;
};
const gold = (c: number) => {
  const g = c / 10000;
  return g >= 100 ? `${Math.round(g).toLocaleString("en-US")}g` : g >= 1 ? `${Math.round(g * 10) / 10}g` : `${Math.round(c / 100)}s`;
};

function niceScale(v: number, count: number) {
  if (v <= 0) return { max: count, step: 1 };
  const raw = v / count;
  const p = Math.pow(10, Math.floor(Math.log10(raw)));
  const step = [1, 2, 5, 10].map((m) => m * p).find((s) => s >= raw) ?? 10 * p;
  return { max: Math.ceil(v / step) * step, step };
}

export default function GoldChart({ points }: { points: [number, number][] }) {
  const [hover, setHover] = useState<number | null>(null);
  if (points.length < 2) {
    return <p className="text-sm text-gray-400">Your gold chart starts once the tray app has sent your gold twice (each time you log out or /reload).</p>;
  }
  const t0 = points[0][0];
  const t1 = points[points.length - 1][0];
  const span = Math.max(1, t1 - t0);
  const x = (t: number) => PAD_L + ((t - t0) / span) * (W - PAD_L - PAD_R);
  const scale = niceScale(Math.max(...points.map((p) => p[1])), 4);
  const y = (v: number) => BOT - (v / scale.max) * (BOT - TOP);
  let d = `M${x(points[0][0]).toFixed(1)},${y(points[0][1]).toFixed(1)}`;
  for (let i = 1; i < points.length; i++) d += `H${x(points[i][0]).toFixed(1)}V${y(points[i][1]).toFixed(1)}`;
  const ticks: number[] = [];
  for (let v = 0; v <= scale.max + scale.step / 2; v += scale.step) ticks.push(v);
  const labels = [0, 0.25, 0.5, 0.75, 1].map((f) => t0 + f * span);

  const onMove = (e: React.MouseEvent<SVGRectElement>) => {
    const box = e.currentTarget.getBoundingClientRect();
    const px = ((e.clientX - box.left) / box.width) * W;
    let best = 0;
    for (let i = 1; i < points.length; i++) if (Math.abs(x(points[i][0]) - px) < Math.abs(x(points[best][0]) - px)) best = i;
    setHover(best);
  };
  const h = hover !== null ? points[hover] : null;

  return (
    <div className="relative">
      <svg viewBox={`0 0 ${W} ${H}`} className="h-auto w-full" role="img" aria-label="Total gold over time">
        {ticks.map((v) => (
          <g key={v}>
            <line x1={PAD_L} x2={W - PAD_R} y1={y(v)} y2={y(v)} stroke={GRID} strokeWidth={1} />
            <text x={PAD_L - 8} y={y(v) + 4} textAnchor="end" fontSize={11} fill={AXIS}>
              {gold(v)}
            </text>
          </g>
        ))}
        {labels.map((t, i) => (
          <text key={i} x={x(t)} y={H - 8} textAnchor={i === 0 ? "start" : i === 4 ? "end" : "middle"} fontSize={11} fill={AXIS}>
            {dateLabel(t)}
          </text>
        ))}
        <path d={d} fill="none" stroke={LINE} strokeWidth={2} strokeLinejoin="round" />
        {h && (
          <>
            <line x1={x(h[0])} x2={x(h[0])} y1={TOP} y2={BOT} stroke="#6b5229" strokeWidth={1} />
            <circle cx={x(h[0])} cy={y(h[1])} r={5} fill={LINE} stroke="#14110c" strokeWidth={2} />
          </>
        )}
        <rect x={PAD_L - 10} y={0} width={W - PAD_L - PAD_R + 20} height={H} fill="transparent" onMouseMove={onMove} onMouseLeave={() => setHover(null)} />
      </svg>
      {h && hover !== null && (
        <div
          className="pointer-events-none absolute top-1 rounded border border-neutral-600 bg-neutral-950/95 px-3 py-1.5 text-xs text-gray-200"
          style={{ left: `${(x(h[0]) / W) * 100}%`, transform: x(h[0]) > W * 0.6 ? "translateX(calc(-100% - 12px))" : "translateX(12px)" }}
        >
          {dateLabel(h[0])}: {gold(h[1])}
        </div>
      )}
    </div>
  );
}

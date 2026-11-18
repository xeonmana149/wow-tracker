"use client";

import { useState } from "react";
import { Money } from "../ui";

// Total gold across your characters over time. One series, so no legend -
// the heading names it. Steps rather than slopes: a balance only changes
// when you play, so the value at any moment is the last one recorded.
//
// The crosshair follows the mouse itself (not the nearest recorded point),
// and the readout shows the exact balance at that moment, the date and time
// in your own timezone, and the change since the start of the range.

const W = 720;
const H = 220;
const PAD_L = 62;
const PAD_R = 16;
const TOP = 12;
const BOT = H - 28;
const LINE = "#3987e5";
const GRID = "#2c261d";
const AXIS = "#a89a7c";
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

const RANGES = [
  { key: "day", label: "24 hours", secs: 86400 },
  { key: "week", label: "7 days", secs: 7 * 86400 },
  { key: "month", label: "30 days", secs: 30 * 86400 },
  { key: "all", label: "All", secs: 0 },
] as const;
type RangeKey = (typeof RANGES)[number]["key"];

const pad2 = (n: number) => String(n).padStart(2, "0");
const timeLabel = (t: number) => {
  const d = new Date(t * 1000);
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
};
const dateLabel = (t: number) => {
  const d = new Date(t * 1000);
  return `${MONTHS[d.getMonth()]} ${d.getDate()}`;
};
const fullLabel = (t: number) => {
  const d = new Date(t * 1000);
  return `${DAYS[d.getDay()]} ${MONTHS[d.getMonth()]} ${d.getDate()}, ${timeLabel(t)}`;
};
const gold = (c: number) => {
  if (c === 0) return "0g";
  const g = c / 10000;
  if (g >= 1000) return `${Math.round(g).toLocaleString("en-US")}g`;
  if (g >= 1) return `${Math.round(g * 10) / 10}g`;
  if (c >= 100) return `${Math.round(c / 10) / 10}s`;
  return `${Math.round(c)}c`;
};

// Round tick values covering lo..hi in about `count` steps.
function niceRange(lo: number, hi: number, count: number) {
  const span = Math.max(hi - lo, 1);
  const raw = span / count;
  const p = Math.pow(10, Math.floor(Math.log10(raw)));
  const step = [1, 2, 2.5, 5, 10].map((m) => m * p).find((s) => s >= raw) ?? 10 * p;
  const min = Math.floor(lo / step) * step;
  const max = Math.ceil(hi / step) * step;
  const ticks: number[] = [];
  for (let v = min; v <= max + step / 2; v += step) ticks.push(v);
  return { min, max: max === min ? min + step : max, ticks };
}

// Balance at time t: the last recorded value at or before it.
function valueAt(points: [number, number][], t: number) {
  let v = points[0][1];
  for (const p of points) {
    if (p[0] > t) break;
    v = p[1];
  }
  return v;
}

export default function GoldChart({ points }: { points: [number, number][] }) {
  const [range, setRange] = useState<RangeKey>("week");
  const [fromZero, setFromZero] = useState(false);
  const [hoverT, setHoverT] = useState<number | null>(null);

  if (points.length < 2) {
    return <p className="text-sm text-gray-400">Your gold chart starts once the tray app has sent your gold twice (each time you log out or /reload).</p>;
  }

  const sorted = [...points].sort((a, b) => a[0] - b[0]);
  const last = sorted[sorted.length - 1];
  const now = Math.max(last[0], Math.floor(Date.now() / 1000));
  const r = RANGES.find((x) => x.key === range) ?? RANGES[1];
  const t0 = r.secs ? Math.max(sorted[0][0], now - r.secs) : sorted[0][0];
  const t1 = now;
  // The window's points, starting with the balance carried in from before it.
  const pts: [number, number][] = [[t0, valueAt(sorted, t0)], ...sorted.filter((p) => p[0] > t0)];
  pts.push([t1, last[1]]);

  const values = pts.map((p) => p[1]);
  const lo = Math.min(...values);
  const hi = Math.max(...values);
  const scale = fromZero ? niceRange(0, hi, 4) : niceRange(lo - (hi - lo) * 0.1, hi + (hi - lo) * 0.1, 4);
  const span = Math.max(1, t1 - t0);
  const x = (t: number) => PAD_L + ((t - t0) / span) * (W - PAD_L - PAD_R);
  const y = (v: number) => BOT - ((v - scale.min) / (scale.max - scale.min)) * (BOT - TOP);

  let d = `M${x(pts[0][0]).toFixed(1)},${y(pts[0][1]).toFixed(1)}`;
  for (let i = 1; i < pts.length; i++) d += `H${x(pts[i][0]).toFixed(1)}V${y(pts[i][1]).toFixed(1)}`;

  // Five time labels; clock times for short ranges, dates for long ones.
  const short = span <= 2 * 86400;
  const xTicks = [0, 0.25, 0.5, 0.75, 1].map((f) => t0 + f * span);

  const change = last[1] - pts[0][1];
  const onMove = (e: React.MouseEvent<SVGRectElement>) => {
    const svg = e.currentTarget.ownerSVGElement;
    if (!svg) return;
    const box = svg.getBoundingClientRect();
    const px = ((e.clientX - box.left) / box.width) * W;
    const t = t0 + ((px - PAD_L) / (W - PAD_L - PAD_R)) * span;
    setHoverT(Math.min(t1, Math.max(t0, t)));
  };
  const hv = hoverT !== null ? valueAt(pts, hoverT) : null;

  return (
    <div>
      <div className="mb-2 flex flex-wrap items-center gap-2 text-xs">
        <div className="inline-flex overflow-hidden rounded border border-neutral-700">
          {RANGES.map((x) => (
            <button
              key={x.key}
              onClick={() => setRange(x.key)}
              className={`px-2.5 py-1 ${range === x.key ? "bg-amber-700/60 text-amber-100" : "text-gray-300 hover:bg-neutral-800"}`}
            >
              {x.label}
            </button>
          ))}
        </div>
        <label className="flex cursor-pointer items-center gap-1.5 text-gray-400">
          <input type="checkbox" checked={fromZero} onChange={(e) => setFromZero(e.target.checked)} />
          Start at zero
        </label>
        <span className="ml-auto flex flex-wrap items-center gap-x-4 gap-y-1 text-gray-400">
          <span>
            Change <Money c={change} sign />
          </span>
          <span>
            High <Money c={hi} />
          </span>
          <span>
            Low <Money c={lo} />
          </span>
        </span>
      </div>
      <div className="relative">
        <svg viewBox={`0 0 ${W} ${H}`} className="h-auto w-full" role="img" aria-label="Total gold over time">
          {scale.ticks.map((v) => (
            <g key={v}>
              <line x1={PAD_L} x2={W - PAD_R} y1={y(v)} y2={y(v)} stroke={GRID} strokeWidth={1} />
              <text x={PAD_L - 8} y={y(v) + 4} textAnchor="end" fontSize={11} fill={AXIS}>
                {gold(v)}
              </text>
            </g>
          ))}
          {xTicks.map((t, i) => (
            <text key={i} x={x(t)} y={H - 10} textAnchor={i === 0 ? "start" : i === 4 ? "end" : "middle"} fontSize={11} fill={AXIS}>
              {short ? timeLabel(t) : dateLabel(t)}
            </text>
          ))}
          <path d={d} fill="none" stroke={LINE} strokeWidth={2} strokeLinejoin="round" />
          {hoverT !== null && hv !== null && (
            <>
              <line x1={x(hoverT)} x2={x(hoverT)} y1={TOP} y2={BOT} stroke="#6b5229" strokeWidth={1} />
              <circle cx={x(hoverT)} cy={y(hv)} r={5} fill={LINE} stroke="#14110c" strokeWidth={2} />
            </>
          )}
          <rect
            x={PAD_L}
            y={TOP}
            width={W - PAD_L - PAD_R}
            height={BOT - TOP}
            fill="transparent"
            onMouseMove={onMove}
            onMouseLeave={() => setHoverT(null)}
          />
        </svg>
        {hoverT !== null && hv !== null && (
          <div
            className="pointer-events-none absolute top-1 z-10 rounded border border-neutral-600 bg-neutral-950/95 px-3 py-1.5 text-xs text-gray-200 shadow-lg"
            style={{ left: `${(x(hoverT) / W) * 100}%`, transform: x(hoverT) > W * 0.6 ? "translateX(calc(-100% - 12px))" : "translateX(12px)" }}
          >
            <div className="text-gray-400">{fullLabel(hoverT)}</div>
            <div className="text-sm">
              <Money c={hv} />
            </div>
            <div className="text-gray-400">
              <Money c={hv - pts[0][1]} sign /> since {short ? timeLabel(t0) : dateLabel(t0)}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

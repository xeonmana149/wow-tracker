"use client";

import { useState } from "react";

// Two charts that share the day axis: price (what it sold for vs. the
// market price listed) and how many sold each day. Kept separate rather
// than one chart with two y-scales.

type Point = { day: number; sold: number; mkt: number; qty: number; low: number };

const W = 720;
const PAD_L = 64;
const PAD_R = 92;
const SOLD = "#3987e5"; // categorical slot 1 (dark)
const MKT = "#d95926"; // categorical slot 2 (dark)
const GRID = "#2c261d";
const AXIS_TEXT = "#a89a7c";

function fmt(c: number): string {
  if (c >= 10000) {
    const g = c / 10000;
    return `${g >= 100 ? Math.round(g) : Math.round(g * 10) / 10}g`;
  }
  if (c >= 100) return `${Math.round(c / 100)}s`;
  return `${Math.round(c)}c`;
}
function fmtFull(c: number): string {
  if (!c) return "-";
  const g = Math.floor(c / 10000);
  const s = Math.floor((c % 10000) / 100);
  const cu = Math.round(c % 100);
  return [g ? `${g.toLocaleString("en-US")}g` : "", s ? `${s}s` : "", !g && (cu || !s) ? `${cu}c` : ""].filter(Boolean).join(" ");
}
// Same text on the server and in the browser (no locale formatting).
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const dayLabel = (d: number) => {
  const t = new Date(d * 86400000);
  return `${MONTHS[t.getUTCMonth()]} ${t.getUTCDate()}`;
};

// A round step (1, 2 or 5 x 10^n) giving about `count` intervals up to v.
function niceScale(v: number, count: number): { max: number; step: number } {
  if (v <= 0) return { max: count, step: 1 };
  const raw = v / count;
  const p = Math.pow(10, Math.floor(Math.log10(raw)));
  const step = [1, 2, 5, 10].map((m) => m * p).find((s) => s >= raw) ?? 10 * p;
  return { max: Math.ceil(v / step) * step, step };
}
const ticksOf = ({ max, step }: { max: number; step: number }) => {
  const out: number[] = [];
  for (let t = 0; t <= max + step / 2; t += step) out.push(t);
  return out;
};

export default function HistoryCharts({ points, today }: { points: Point[]; today: number }) {
  const [hover, setHover] = useState<number | null>(null);
  const n = points.length;
  const x = (i: number) => (n <= 1 ? PAD_L + (W - PAD_L - PAD_R) / 2 : PAD_L + (i * (W - PAD_L - PAD_R)) / (n - 1));

  // ---- price chart ----
  const PH = 220;
  const pTop = 14;
  const pBot = PH - 26;
  const pScale = niceScale(Math.max(1, ...points.map((p) => Math.max(p.sold, p.mkt))), 4);
  const pMax = pScale.max;
  const py = (v: number) => pBot - (v / pMax) * (pBot - pTop);
  const line = (key: "sold" | "mkt") => {
    let d = "";
    let pen = false;
    points.forEach((p, i) => {
      const v = p[key];
      if (!v) {
        pen = false;
        return;
      }
      d += `${pen ? "L" : "M"}${x(i).toFixed(1)},${py(v).toFixed(1)}`;
      pen = true;
    });
    return d;
  };
  const lastOf = (key: "sold" | "mkt") => {
    for (let i = n - 1; i >= 0; i--) if (points[i][key]) return i;
    return -1;
  };
  const ticks = ticksOf(pScale);

  // ---- volume chart ----
  const VH = 150;
  const vTop = 10;
  const vBot = VH - 26;
  const vScale = niceScale(Math.max(1, ...points.map((p) => p.qty)), 2);
  const vMax = vScale.max;
  const vy = (v: number) => vBot - (v / vMax) * (vBot - vTop);
  const slot = n <= 1 ? 60 : (W - PAD_L - PAD_R) / (n - 1);
  const barW = Math.max(4, Math.min(24, slot * 0.6));

  const onMove = (e: React.MouseEvent<SVGRectElement>) => {
    const box = e.currentTarget.getBoundingClientRect();
    const px = ((e.clientX - box.left) / box.width) * W;
    let best = 0;
    for (let i = 1; i < n; i++) if (Math.abs(x(i) - px) < Math.abs(x(best) - px)) best = i;
    setHover(best);
  };

  const h = hover !== null ? points[hover] : null;
  const labelEvery = Math.max(1, Math.ceil(n / 7));

  const tooltip = h && hover !== null && (
    <div
      className="pointer-events-none absolute top-2 z-10 rounded border border-neutral-600 bg-neutral-950/95 px-3 py-2 text-xs shadow-lg"
      style={{ left: `${(x(hover) / W) * 100}%`, transform: x(hover) > W * 0.6 ? "translateX(calc(-100% - 12px))" : "translateX(12px)" }}
    >
      <div className="mb-1 font-semibold text-gray-200">
        {dayLabel(h.day)}
        {h.day === today ? " (today so far)" : ""}
      </div>
      <div className="flex items-center gap-2 text-gray-300">
        <span className="inline-block h-0.5 w-3" style={{ background: SOLD }} /> Sold for {fmtFull(h.sold)}
      </div>
      <div className="flex items-center gap-2 text-gray-300">
        <span className="inline-block h-0.5 w-3" style={{ background: MKT }} /> Market price {fmtFull(h.mkt)}
      </div>
      <div className="text-gray-400">Cheapest seen {fmtFull(h.low)}</div>
      <div className="text-gray-400">{h.qty.toLocaleString("en-US")} sold</div>
    </div>
  );

  return (
    <div className="space-y-4">
      <div>
        <div className="mb-1 flex flex-wrap items-center gap-4 text-xs text-gray-400">
          <span className="font-semibold text-gray-300">Price per item, by day</span>
          <span className="flex items-center gap-1.5">
            <span className="inline-block h-0.5 w-4" style={{ background: SOLD }} /> What it sold for (average)
          </span>
          <span className="flex items-center gap-1.5">
            <span className="inline-block h-0.5 w-4" style={{ background: MKT }} /> Market price listed
          </span>
        </div>
        <div className="relative">
          <svg viewBox={`0 0 ${W} ${PH}`} className="h-auto w-full" role="img" aria-label="Price per item by day">
            {ticks.map((t) => (
              <g key={t}>
                <line x1={PAD_L} x2={W - PAD_R} y1={py(t)} y2={py(t)} stroke={GRID} strokeWidth={1} />
                <text x={PAD_L - 8} y={py(t) + 4} textAnchor="end" fontSize={11} fill={AXIS_TEXT}>
                  {fmt(t)}
                </text>
              </g>
            ))}
            {points.map((p, i) =>
              i % labelEvery === 0 || i === n - 1 ? (
                <text key={p.day} x={x(i)} y={PH - 8} textAnchor="middle" fontSize={11} fill={AXIS_TEXT}>
                  {dayLabel(p.day)}
                </text>
              ) : null
            )}
            {hover !== null && <line x1={x(hover)} x2={x(hover)} y1={pTop} y2={pBot} stroke="#6b5229" strokeWidth={1} />}
            <path d={line("mkt")} fill="none" stroke={MKT} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
            <path d={line("sold")} fill="none" stroke={SOLD} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
            {points.map((p, i) => (
              <g key={p.day}>
                {p.mkt > 0 && <circle cx={x(i)} cy={py(p.mkt)} r={hover === i ? 5 : n <= 3 ? 4 : 0} fill={MKT} stroke="#14110c" strokeWidth={2} />}
                {p.sold > 0 && <circle cx={x(i)} cy={py(p.sold)} r={hover === i ? 5 : n <= 3 ? 4 : 0} fill={SOLD} stroke="#14110c" strokeWidth={2} />}
              </g>
            ))}
            {(["sold", "mkt"] as const).map((k) => {
              const i = lastOf(k);
              if (i < 0) return null;
              const other = lastOf(k === "sold" ? "mkt" : "sold");
              let yy = py(points[i][k]) + 4;
              if (other === i) {
                const oy = py(points[i][k === "sold" ? "mkt" : "sold"]) + 4;
                if (Math.abs(oy - yy) < 13) yy += k === "sold" ? (yy <= oy ? -7 : 7) : yy < oy ? -7 : 7;
              }
              return (
                <text key={k} x={x(i) + 8} y={yy} fontSize={11} fill="#ece0c6">
                  {k === "sold" ? "sold" : "market"} {fmt(points[i][k])}
                </text>
              );
            })}
            <rect x={PAD_L - 20} y={0} width={W - PAD_L - PAD_R + 40} height={PH} fill="transparent" onMouseMove={onMove} onMouseLeave={() => setHover(null)} />
          </svg>
          {tooltip}
        </div>
      </div>

      <div>
        <div className="mb-1 text-xs text-gray-400">
          <span className="font-semibold text-gray-300">Sold per day</span>
          {points.some((p) => p.day === today) ? " - today's bar is faded: the day isn't over yet" : ""}
        </div>
        <svg viewBox={`0 0 ${W} ${VH}`} className="h-auto w-full" role="img" aria-label="Items sold per day">
          {ticksOf(vScale).map((t) => (
            <g key={t}>
              <line x1={PAD_L} x2={W - PAD_R} y1={vy(t)} y2={vy(t)} stroke={GRID} strokeWidth={1} />
              <text x={PAD_L - 8} y={vy(t) + 4} textAnchor="end" fontSize={11} fill={AXIS_TEXT}>
                {t >= 1000 ? `${Math.round(t / 100) / 10}k` : t}
              </text>
            </g>
          ))}
          {points.map((p, i) => {
            const top = vy(p.qty);
            const hgt = vBot - top;
            const r = Math.min(4, hgt / 2, barW / 2);
            const x0 = x(i) - barW / 2;
            return (
              <g key={p.day} onMouseEnter={() => setHover(i)} onMouseLeave={() => setHover(null)}>
                <rect x={x0 - 4} y={vTop} width={barW + 8} height={vBot - vTop} fill="transparent" />
                {hgt > 0 && (
                  <path
                    d={`M${x0},${vBot}V${top + r}Q${x0},${top} ${x0 + r},${top}H${x0 + barW - r}Q${x0 + barW},${top} ${x0 + barW},${top + r}V${vBot}Z`}
                    fill={SOLD}
                    opacity={(hover === null || hover === i ? 1 : 0.55) * (p.day === today ? 0.45 : 1)}
                  />
                )}
                {hover === i && (
                  <text x={x(i)} y={top - 4} textAnchor="middle" fontSize={11} fill="#ece0c6">
                    {p.qty.toLocaleString("en-US")}
                  </text>
                )}
              </g>
            );
          })}
          {points.map((p, i) =>
            i % labelEvery === 0 || i === n - 1 ? (
              <text key={p.day} x={x(i)} y={VH - 8} textAnchor="middle" fontSize={11} fill={AXIS_TEXT}>
                {dayLabel(p.day)}
              </text>
            ) : null
          )}
        </svg>
      </div>

      <details className="text-xs text-gray-400">
        <summary className="cursor-pointer select-none text-gray-400 hover:text-gray-200">Show as a table</summary>
        <table className="mt-2 w-full max-w-xl">
          <thead>
            <tr className="text-left text-gray-500">
              <th className="py-1">Day</th>
              <th className="py-1 text-right">Sold for</th>
              <th className="py-1 text-right">Market price</th>
              <th className="py-1 text-right">Cheapest seen</th>
              <th className="py-1 text-right">Sold</th>
            </tr>
          </thead>
          <tbody>
            {points.map((p) => (
              <tr key={p.day} className="border-t border-neutral-800">
                <td className="py-1">
                  {dayLabel(p.day)}
                  {p.day === today ? " (so far)" : ""}
                </td>
                <td className="py-1 text-right">{fmtFull(p.sold)}</td>
                <td className="py-1 text-right">{fmtFull(p.mkt)}</td>
                <td className="py-1 text-right">{fmtFull(p.low)}</td>
                <td className="py-1 text-right">{p.qty.toLocaleString("en-US")}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </details>
    </div>
  );
}

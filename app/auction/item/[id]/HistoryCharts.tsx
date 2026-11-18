"use client";

import { useMemo, useState } from "react";

// An item's history, a day at a time: a price chart and an activity chart
// that share the day axis and one crosshair. Kept as two charts rather than
// one with two y-scales.
//
// Options: the date range, which prices to draw (each one a fixed colour,
// so a series keeps its colour whatever else is switched on), a 7-day
// average to smooth out noisy days, whether the price axis starts at zero,
// and which activity to show as bars. A summary of the chosen range sits
// above, and the same numbers are in a table (and a CSV) below.

export type Point = {
  day: number; // unix day (UTC)
  sold: number; // items sold
  soldP: number; // average price they sold for
  min: number; // average cheapest buyout
  low: number; // lowest buyout seen
  mkt: number; // average market price
  listed: number; // average quantity listed
  posts: number; // new auctions
  exp: number; // quantity that expired
};

const W = 720;
const PAD_L = 64;
const PAD_R = 96;
const GRID = "#2c261d";
const AXIS_TEXT = "#a89a7c";
const INK = "#ece0c6";

// Fixed order and colours (the validated dark categorical slots 1-4).
const PRICES = [
  { key: "soldP", label: "Sold for", long: "What it actually sold for (average)", color: "#3987e5" },
  { key: "mkt", label: "Market", long: "Market price listed (cheapest 15%)", color: "#d95926" },
  { key: "min", label: "Cheapest", long: "Cheapest listing (daily average)", color: "#199e70" },
  { key: "low", label: "Lowest", long: "Lowest listing seen that day", color: "#c98500" },
] as const;
type PriceKey = (typeof PRICES)[number]["key"];

const ACTIVITY = [
  { key: "sold", label: "Sold", long: "Items sold" },
  { key: "listed", label: "Listed", long: "Quantity listed (daily average)" },
  { key: "posts", label: "New auctions", long: "New auctions posted" },
  { key: "exp", label: "Expired", long: "Quantity that expired unsold" },
] as const;
type ActivityKey = (typeof ACTIVITY)[number]["key"];

const RANGES = [
  { key: "7", label: "7 days", days: 7 },
  { key: "14", label: "14 days", days: 14 },
  { key: "30", label: "30 days", days: 30 },
  { key: "90", label: "90 days", days: 90 },
  { key: "all", label: "All", days: 0 },
] as const;
type RangeKey = (typeof RANGES)[number]["key"];

function fmt(c: number): string {
  if (c >= 10000) {
    const g = c / 10000;
    return `${g >= 100 ? Math.round(g).toLocaleString("en-US") : Math.round(g * 10) / 10}g`;
  }
  // One decimal, so 1.5s and 2s don't both read "2s" on an axis.
  if (c >= 100) return `${Math.round(c / 10) / 10}s`;
  return `${Math.round(c)}c`;
}
function fmtFull(c: number): string {
  if (!c) return "-";
  const g = Math.floor(c / 10000);
  const s = Math.floor((c % 10000) / 100);
  const cu = Math.round(c % 100);
  return [g ? `${g.toLocaleString("en-US")}g` : "", s ? `${s}s` : "", cu ? `${cu}c` : ""].filter(Boolean).join(" ") || "0c";
}
const qtyText = (v: number) => (v >= 1000 ? `${Math.round(v / 100) / 10}k` : String(Math.round(v * 10) / 10));

// Same text on the server and in the browser: UTC days, no locale formatting.
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const dayLabel = (d: number) => {
  const t = new Date(d * 86400000);
  return `${MONTHS[t.getUTCMonth()]} ${t.getUTCDate()}`;
};
const longDay = (d: number) => `${WEEKDAYS[new Date(d * 86400000).getUTCDay()]} ${dayLabel(d)}`;

// Round ticks covering lo..hi in about `count` steps.
function niceRange(lo: number, hi: number, count: number) {
  const span = Math.max(hi - lo, 1);
  const raw = span / count;
  const p = Math.pow(10, Math.floor(Math.log10(raw)));
  const step = [1, 2, 2.5, 5, 10].map((m) => m * p).find((s) => s >= raw) ?? 10 * p;
  const min = Math.max(0, Math.floor(lo / step) * step);
  let max = Math.ceil(hi / step) * step;
  if (max <= min) max = min + step;
  const ticks: number[] = [];
  for (let v = min; v <= max + step / 2; v += step) ticks.push(v);
  return { min, max, ticks };
}

// Trailing 7-day average of the days that have a value.
function smooth(points: Point[], key: PriceKey): number[] {
  return points.map((p) => {
    const vals = points.filter((q) => q.day <= p.day && q.day > p.day - 7 && q[key] > 0).map((q) => q[key]);
    return p[key] > 0 && vals.length ? vals.reduce((a, b) => a + b, 0) / vals.length : 0;
  });
}

function Toggle({ on, onClick, children, color }: { on: boolean; onClick: () => void; children: React.ReactNode; color?: string }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={on}
      className={`inline-flex items-center gap-1.5 rounded border px-2 py-1 text-xs ${
        on ? "border-neutral-500 bg-neutral-800 text-gray-100" : "border-neutral-800 text-gray-500 hover:text-gray-300"
      }`}
    >
      {color && <span className="inline-block h-0.5 w-3.5" style={{ background: on ? color : "#55504a" }} />}
      {children}
    </button>
  );
}

function Segmented<K extends string>({ value, options, onChange }: { value: K; options: readonly { key: K; label: string }[]; onChange: (k: K) => void }) {
  return (
    <div className="inline-flex overflow-hidden rounded border border-neutral-700 text-xs">
      {options.map((o) => (
        <button
          key={o.key}
          type="button"
          onClick={() => onChange(o.key)}
          className={`px-2.5 py-1 ${value === o.key ? "bg-amber-700/60 text-amber-100" : "text-gray-300 hover:bg-neutral-800"}`}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

function Summary({ label, value, note }: { label: string; value: React.ReactNode; note?: React.ReactNode }) {
  return (
    <div className="rounded border border-neutral-800 px-2.5 py-1.5">
      <div className="text-[11px] text-gray-500">{label}</div>
      <div className="text-sm font-semibold text-gray-100 tabular-nums">{value}</div>
      {note && <div className="text-[11px] text-gray-500">{note}</div>}
    </div>
  );
}

export default function HistoryCharts({ points: all, today, itemName }: { points: Point[]; today: number; itemName?: string }) {
  const sortedAll = useMemo(() => [...all].sort((a, b) => a.day - b.day), [all]);
  const span = sortedAll.length ? sortedAll[sortedAll.length - 1].day - sortedAll[0].day + 1 : 0;
  const [range, setRange] = useState<RangeKey>(span > 30 ? "30" : "all");
  const [shown, setShown] = useState<Record<PriceKey, boolean>>({ soldP: true, mkt: true, min: false, low: false });
  const [activity, setActivity] = useState<ActivityKey>("sold");
  const [avg, setAvg] = useState(false);
  const [fromZero, setFromZero] = useState(false);
  const [hover, setHover] = useState<number | null>(null);

  const r = RANGES.find((x) => x.key === range) ?? RANGES[RANGES.length - 1];
  const lastDay = sortedAll.length ? sortedAll[sortedAll.length - 1].day : today;
  const fromDay = r.days ? lastDay - r.days + 1 : sortedAll[0]?.day ?? lastDay;
  const points = sortedAll.filter((p) => p.day >= fromDay);
  const n = points.length;
  const d0 = points[0]?.day ?? fromDay;
  const d1 = Math.max(d0 + 1, lastDay);
  const plotW = W - PAD_L - PAD_R;
  const x = (day: number) => PAD_L + ((day - d0) / (d1 - d0)) * plotW;

  // Values per series: raw or 7-day average (worked out over all the data so
  // the first days of a short range still have a full week behind them).
  const series = PRICES.filter((s) => shown[s.key]).map((s) => {
    const vals = avg ? smooth(sortedAll, s.key).slice(sortedAll.length - n) : points.map((p) => p[s.key]);
    return { ...s, vals };
  });

  // ---- price chart ----
  const PH = 230;
  const pTop = 14;
  const pBot = PH - 26;
  const priceVals = series.flatMap((s) => s.vals.filter((v) => v > 0));
  const pLo = priceVals.length ? Math.min(...priceVals) : 0;
  const pHi = priceVals.length ? Math.max(...priceVals) : 1;
  const pScale = fromZero ? niceRange(0, pHi, 4) : niceRange(pLo - (pHi - pLo) * 0.08, pHi + (pHi - pLo) * 0.08, 4);
  const py = (v: number) => pBot - ((v - pScale.min) / (pScale.max - pScale.min)) * (pBot - pTop);
  const path = (vals: number[]) => {
    let d = "";
    let pen = false;
    points.forEach((p, i) => {
      const v = vals[i];
      // Lift the pen over missing values and over missing days.
      if (!v || (i > 0 && p.day - points[i - 1].day > 1)) pen = false;
      if (!v) return;
      d += `${pen ? "L" : "M"}${x(p.day).toFixed(1)},${py(v).toFixed(1)}`;
      pen = true;
    });
    return d;
  };
  // Labels at the end of each line, nudged apart so they never overlap.
  const endLabels = series
    .map((s) => {
      for (let i = n - 1; i >= 0; i--) if (s.vals[i] > 0) return { key: s.key, label: s.label, v: s.vals[i], i, y: py(s.vals[i]) + 4 };
      return null;
    })
    .filter((l): l is NonNullable<typeof l> => l !== null)
    .sort((a, b) => a.y - b.y);
  for (let i = 1; i < endLabels.length; i++) endLabels[i].y = Math.max(endLabels[i].y, endLabels[i - 1].y + 13);

  // ---- activity chart ----
  const VH = 150;
  const vTop = 12;
  const vBot = VH - 26;
  const act = ACTIVITY.find((a) => a.key === activity) ?? ACTIVITY[0];
  const vScale = niceRange(0, Math.max(1, ...points.map((p) => p[activity])), 2);
  const vy = (v: number) => vBot - (v / vScale.max) * (vBot - vTop);
  const barW = Math.max(3, Math.min(22, (plotW / Math.max(1, d1 - d0 + 1)) * 0.65));

  // ---- the chosen range in numbers ----
  const sum = (k: keyof Point) => points.reduce((a, p) => a + p[k], 0);
  const soldQty = sum("sold");
  const soldValue = points.reduce((a, p) => a + p.sold * p.soldP, 0);
  const expQty = sum("exp");
  const days = Math.max(1, points.filter((p) => p.day !== today).length || n);
  const firstMkt = points.find((p) => p.mkt > 0)?.mkt ?? 0;
  const lastMkt = [...points].reverse().find((p) => p.mkt > 0)?.mkt ?? 0;
  const mktChange = firstMkt && lastMkt ? Math.round(((lastMkt - firstMkt) / firstMkt) * 100) : null;
  const through = soldQty + expQty > 0 ? Math.round((soldQty / (soldQty + expQty)) * 100) : null;

  const onMove = (e: React.MouseEvent<SVGRectElement>) => {
    const svg = e.currentTarget.ownerSVGElement;
    if (!svg || !n) return;
    const box = svg.getBoundingClientRect();
    const px = ((e.clientX - box.left) / box.width) * W;
    let best = 0;
    for (let i = 1; i < n; i++) if (Math.abs(x(points[i].day) - px) < Math.abs(x(points[best].day) - px)) best = i;
    setHover(best);
  };
  const h = hover !== null ? points[hover] : null;
  const xTicks = (() => {
    const count = Math.min(7, Math.max(2, d1 - d0 + 1));
    const out: number[] = [];
    for (let i = 0; i < count; i++) out.push(Math.round(d0 + ((d1 - d0) * i) / (count - 1)));
    return [...new Set(out)];
  })();

  const csv = () => {
    const head = "day,sold,sold_for_copper,market_copper,cheapest_copper,lowest_copper,listed,new_auctions,expired";
    const body = points.map((p) => {
      const t = new Date(p.day * 86400000).toISOString().slice(0, 10);
      return [t, p.sold, p.soldP, p.mkt, p.min, p.low, p.listed, p.posts, p.exp].join(",");
    });
    const blob = new Blob([[head, ...body].join("\n")], { type: "text/csv" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `${(itemName || "item").replace(/[^a-z0-9]+/gi, "-").toLowerCase()}-price-history.csv`;
    a.click();
    URL.revokeObjectURL(a.href);
  };

  const crosshair = (top: number, bottom: number) =>
    h ? <line x1={x(h.day)} x2={x(h.day)} y1={top} y2={bottom} stroke="#6b5229" strokeWidth={1} /> : null;
  const hoverRect = (height: number) => (
    <rect x={PAD_L - 6} y={0} width={plotW + 12} height={height} fill="transparent" onMouseMove={onMove} onMouseLeave={() => setHover(null)} />
  );
  const dayAxis = (yPos: number) =>
    xTicks.map((d, i) => (
      <text key={d} x={x(d)} y={yPos} textAnchor={i === 0 ? "start" : i === xTicks.length - 1 ? "end" : "middle"} fontSize={11} fill={AXIS_TEXT}>
        {dayLabel(d)}
      </text>
    ));

  return (
    <div className="space-y-4">
      {/* Controls */}
      <div className="flex flex-wrap items-center gap-2">
        <Segmented value={range} options={RANGES} onChange={(k) => { setRange(k); setHover(null); }} />
        <span className="mx-1 h-5 w-px bg-neutral-800" />
        {PRICES.map((s) => (
          <Toggle key={s.key} on={shown[s.key]} color={s.color} onClick={() => setShown({ ...shown, [s.key]: !shown[s.key] })}>
            {s.label}
          </Toggle>
        ))}
        <span className="mx-1 h-5 w-px bg-neutral-800" />
        <Toggle on={avg} onClick={() => setAvg(!avg)}>7-day average</Toggle>
        <Toggle on={fromZero} onClick={() => setFromZero(!fromZero)}>Start at zero</Toggle>
      </div>

      {/* The range in numbers */}
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
        <Summary label="Average sold price" value={soldQty ? fmtFull(Math.round(soldValue / soldQty)) : "-"} />
        <Summary
          label="Market price change"
          value={mktChange === null ? "-" : `${mktChange > 0 ? "+" : ""}${mktChange}%`}
          note={firstMkt && lastMkt ? `${fmt(firstMkt)} to ${fmt(lastMkt)}` : undefined}
        />
        <Summary label="Sold in range" value={soldQty.toLocaleString("en-US")} />
        <Summary label="Sold per day" value={qtyText(soldQty / days)} note={today === lastDay ? "not counting today" : undefined} />
        <Summary label="Sell-through" value={through === null ? "-" : `${through}%`} note="sold vs. expired" />
        <Summary label="Days of data" value={`${n}`} note={`${dayLabel(d0)} to ${dayLabel(lastDay)}`} />
      </div>

      {/* Price chart */}
      <div>
        <div className="mb-1 text-xs text-gray-400">
          <span className="font-semibold text-gray-300">Price per item</span>
          {avg ? " (7-day average)" : ""} · hover for any day
        </div>
        <div className="relative">
          <svg viewBox={`0 0 ${W} ${PH}`} className="h-auto w-full" role="img" aria-label="Price per item by day">
            {pScale.ticks.map((t) => (
              <g key={t}>
                <line x1={PAD_L} x2={W - PAD_R} y1={py(t)} y2={py(t)} stroke={GRID} strokeWidth={1} />
                <text x={PAD_L - 8} y={py(t) + 4} textAnchor="end" fontSize={11} fill={AXIS_TEXT}>
                  {fmt(t)}
                </text>
              </g>
            ))}
            {dayAxis(PH - 8)}
            {crosshair(pTop, pBot)}
            {series.map((s) => (
              <path key={s.key} d={path(s.vals)} fill="none" stroke={s.color} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
            ))}
            {series.map((s) =>
              points.map((p, i) =>
                s.vals[i] > 0 && (hover === i || n <= 3) ? (
                  <circle key={`${s.key}${p.day}`} cx={x(p.day)} cy={py(s.vals[i])} r={hover === i ? 5 : 4} fill={s.color} stroke="#14110c" strokeWidth={2} />
                ) : null
              )
            )}
            {endLabels.map((l) => (
              <text key={l.key} x={x(points[l.i].day) + 8} y={l.y} fontSize={11} fill={INK}>
                {l.label.toLowerCase()} {fmt(l.v)}
              </text>
            ))}
            {!series.length && (
              <text x={PAD_L + plotW / 2} y={(pTop + pBot) / 2} textAnchor="middle" fontSize={12} fill={AXIS_TEXT}>
                Pick a price above to draw it
              </text>
            )}
            {hoverRect(PH)}
          </svg>
          {h && hover !== null && (
            <div
              className="pointer-events-none absolute top-2 z-10 min-w-[190px] rounded border border-neutral-600 bg-neutral-950/95 px-3 py-2 text-xs shadow-lg"
              style={{ left: `${(x(h.day) / W) * 100}%`, transform: x(h.day) > W * 0.55 ? "translateX(calc(-100% - 12px))" : "translateX(12px)" }}
            >
              <div className="mb-1 font-semibold text-gray-200">
                {longDay(h.day)}
                {h.day === today ? " (so far)" : ""}
              </div>
              {PRICES.map((s) => (
                <div key={s.key} className={`flex items-center gap-2 ${shown[s.key] ? "text-gray-200" : "text-gray-500"}`}>
                  <span className="inline-block h-0.5 w-3" style={{ background: s.color }} />
                  <span>{s.label}</span>
                  <span className="ml-auto tabular-nums">{fmtFull(h[s.key])}</span>
                </div>
              ))}
              <div className="mt-1 border-t border-neutral-800 pt-1 text-gray-400">
                {ACTIVITY.map((a) => (
                  <div key={a.key} className="flex gap-2">
                    <span>{a.label}</span>
                    <span className="ml-auto tabular-nums">{qtyText(h[a.key])}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Activity chart */}
      <div>
        <div className="mb-1 flex flex-wrap items-center gap-2 text-xs text-gray-400">
          <span className="font-semibold text-gray-300">{act.long}, per day</span>
          <span className="ml-auto">
            <Segmented value={activity} options={ACTIVITY} onChange={setActivity} />
          </span>
        </div>
        <svg viewBox={`0 0 ${W} ${VH}`} className="h-auto w-full" role="img" aria-label={`${act.long} per day`}>
          {vScale.ticks.map((t) => (
            <g key={t}>
              <line x1={PAD_L} x2={W - PAD_R} y1={vy(t)} y2={vy(t)} stroke={GRID} strokeWidth={1} />
              <text x={PAD_L - 8} y={vy(t) + 4} textAnchor="end" fontSize={11} fill={AXIS_TEXT}>
                {qtyText(t)}
              </text>
            </g>
          ))}
          {crosshair(vTop, vBot)}
          {points.map((p, i) => {
            const v = p[activity];
            const top = vy(v);
            const hgt = vBot - top;
            const rr = Math.min(4, hgt / 2, barW / 2);
            const x0 = x(p.day) - barW / 2;
            return (
              <g key={p.day}>
                {hgt > 0 && (
                  <path
                    d={`M${x0},${vBot}V${top + rr}Q${x0},${top} ${x0 + rr},${top}H${x0 + barW - rr}Q${x0 + barW},${top} ${x0 + barW},${top + rr}V${vBot}Z`}
                    fill="#3987e5"
                    opacity={(hover === null || hover === i ? 1 : 0.5) * (p.day === today ? 0.45 : 1)}
                  />
                )}
                {hover === i && (
                  <text x={x(p.day)} y={Math.max(vTop + 8, top - 4)} textAnchor="middle" fontSize={11} fill={INK}>
                    {qtyText(v)}
                  </text>
                )}
              </g>
            );
          })}
          {dayAxis(VH - 8)}
          {hoverRect(VH)}
        </svg>
        {points.some((p) => p.day === today) && <p className="text-[11px] text-gray-500">Today&apos;s bar is faded: the day isn&apos;t over yet.</p>}
      </div>

      <details className="text-xs text-gray-400">
        <summary className="cursor-pointer select-none text-gray-400 hover:text-gray-200">Show as a table</summary>
        <div className="mt-2 overflow-x-auto">
          <table className="w-full min-w-[640px]">
            <thead>
              <tr className="text-left text-gray-500">
                <th className="py-1">Day</th>
                <th className="py-1 text-right">Sold for</th>
                <th className="py-1 text-right">Market</th>
                <th className="py-1 text-right">Cheapest</th>
                <th className="py-1 text-right">Lowest</th>
                <th className="py-1 text-right">Sold</th>
                <th className="py-1 text-right">Listed</th>
                <th className="py-1 text-right">New auctions</th>
                <th className="py-1 text-right">Expired</th>
              </tr>
            </thead>
            <tbody>
              {[...points].reverse().map((p) => (
                <tr key={p.day} className="border-t border-neutral-800">
                  <td className="py-1">
                    {longDay(p.day)}
                    {p.day === today ? " (so far)" : ""}
                  </td>
                  <td className="py-1 text-right tabular-nums">{fmtFull(p.soldP)}</td>
                  <td className="py-1 text-right tabular-nums">{fmtFull(p.mkt)}</td>
                  <td className="py-1 text-right tabular-nums">{fmtFull(p.min)}</td>
                  <td className="py-1 text-right tabular-nums">{fmtFull(p.low)}</td>
                  <td className="py-1 text-right tabular-nums">{p.sold.toLocaleString("en-US")}</td>
                  <td className="py-1 text-right tabular-nums">{qtyText(p.listed)}</td>
                  <td className="py-1 text-right tabular-nums">{p.posts.toLocaleString("en-US")}</td>
                  <td className="py-1 text-right tabular-nums">{p.exp.toLocaleString("en-US")}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <button type="button" onClick={csv} className="mt-2 text-amber-300 hover:underline">
            Download this range as CSV
          </button>
        </div>
      </details>
    </div>
  );
}

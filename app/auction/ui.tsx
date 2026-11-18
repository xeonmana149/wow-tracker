import Link from "next/link";
import { CopperCoin, GoldCoin, SilverCoin } from "../MoneyIcons";
import type { Row, Speed } from "../../lib/marketView";

// Compact money: "12g 40s", "3s 5c", "80c". Copper is dropped once there's
// gold - nobody prices in copper at that point.
export function Money({ c, sign = false }: { c: number; sign?: boolean }) {
  const neg = c < 0;
  let v = Math.round(Math.abs(c));
  const g = Math.floor(v / 10000);
  v -= g * 10000;
  const s = Math.floor(v / 100);
  const cu = v - s * 100;
  return (
    // Signed amounts (profit, change) are green when up and red when down.
    <span className={`inline-flex items-center gap-1 whitespace-nowrap tabular-nums ${neg ? "text-red-300" : sign && c > 0 ? "text-emerald-300" : ""}`}>
      {neg ? "-" : sign && c > 0 ? "+" : ""}
      {g > 0 && (
        <span className="inline-flex items-center gap-0.5">
          {g.toLocaleString()}
          <GoldCoin size={12} />
        </span>
      )}
      {s > 0 && (
        <span className="inline-flex items-center gap-0.5">
          {s}
          <SilverCoin size={12} />
        </span>
      )}
      {g === 0 && (cu > 0 || s === 0) && (
        <span className="inline-flex items-center gap-0.5">
          {cu}
          <CopperCoin size={12} />
        </span>
      )}
    </span>
  );
}

export function ItemIcon({ src, size = 28 }: { src: string | null; size?: number }) {
  if (!src) return <span className="inline-block shrink-0 rounded border border-neutral-700 bg-neutral-800" style={{ width: size, height: size }} />;
  return (
    // Not loading="lazy": inside this layout the browser never starts lazy
    // images, and the icons are tiny (2-3 KB) anyway.
    // eslint-disable-next-line @next/next/no-img-element
    <img src={src} alt="" width={size} height={size} decoding="async" className="shrink-0 rounded border border-neutral-700" />
  );
}

export function ItemLink({ row, house, size = 28 }: { row: Pick<Row, "id" | "name" | "color" | "icon">; house?: string; size?: number }) {
  return (
    <Link href={itemHref(row.id, house)} className="inline-flex min-w-0 items-center gap-2 hover:underline">
      <ItemIcon src={row.icon} size={size} />
      <span className="truncate font-semibold" style={{ color: row.color }}>
        {row.name}
      </span>
    </Link>
  );
}

export const itemHref = (id: number, house?: string) => `/auction/item/${id}${house ? `?house=${house}` : ""}`;

const SPEED_STYLE: Record<Speed, string> = {
  fast: "border-emerald-500/50 text-emerald-300",
  steady: "border-neutral-500/60 text-neutral-200",
  slow: "border-amber-500/50 text-amber-300",
  rarely: "border-red-500/50 text-red-300",
};
const SPEED_LABEL: Record<Speed, string> = { fast: "Fast", steady: "Steady", slow: "Slow", rarely: "Rarely sells" };

export function SpeedBadge({ speed }: { speed: Speed | null }) {
  if (!speed) return <span className="text-xs text-gray-500">-</span>;
  return <span className={`rounded border px-1.5 py-0.5 text-xs ${SPEED_STYLE[speed]}`}>{SPEED_LABEL[speed]}</span>;
}

export function perDayText(d: number): string {
  if (d >= 100) return Math.round(d).toLocaleString();
  if (d >= 10) return String(Math.round(d));
  if (d >= 1) return String(Math.round(d * 10) / 10);
  if (d > 0) return "<1";
  return "0";
}

// Days since 1970 (UTC), the same day numbers the market history uses.
export function dayNumber(): number {
  return Math.floor(Date.now() / 86400000);
}

export function ago(t: number): string {
  const s = Math.max(0, Math.floor(Date.now() / 1000) - t);
  if (s < 90) return "just now";
  if (s < 3600) return `${Math.round(s / 60)} minutes ago`;
  if (s < 5400) return "1 hour ago";
  if (s < 86400 * 2) return `${Math.round(s / 3600)} hours ago`;
  return `${Math.round(s / 86400)} days ago`;
}

export function Panel({ children, className = "" }: { children: React.ReactNode; className?: string }) {
  return <section className={`rounded-lg border border-neutral-700 bg-neutral-900/40 p-3 md:p-4 ${className}`}>{children}</section>;
}

export function Empty({ children }: { children: React.ReactNode }) {
  return <p className="rounded-lg border border-dashed border-neutral-700 p-6 text-center text-sm text-gray-400">{children}</p>;
}

// Shared table look: header row muted, rows separated by hairlines.
export const TH = "px-2 py-1.5 text-left text-xs font-semibold uppercase tracking-wide text-gray-500";
export const TD = "px-2 py-1.5 align-middle";
export const TR = "border-t border-neutral-800 hover:bg-neutral-800/30";

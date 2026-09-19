import type { Bar } from "../lib/progress";

export default function ProgressBars({
  bars,
  compact = false,
}: {
  bars: Bar[];
  compact?: boolean;
}) {
  return (
    <div className={compact ? "grid grid-cols-2 gap-x-4 gap-y-2" : "flex flex-col gap-3"}>
      {bars.map((b) => {
        const pct = b.max > 0 ? Math.min(100, (b.value / b.max) * 100) : 0;
        const full = b.max > 0 && b.value >= b.max;

        return (
          <div key={b.key}>
            <div className="flex items-baseline justify-between gap-2 text-xs">
              <span className="text-gray-400">{b.label}</span>
              <span className={full ? "font-bold text-yellow-300" : "text-white"}>{b.text}</span>
            </div>
            <div className="mt-1 h-1.5 rounded bg-neutral-700">
              <div
                className={`h-1.5 rounded ${full ? "bg-yellow-500" : "bg-blue-500"}`}
                style={{ width: `${pct}%` }}
              />
            </div>
          </div>
        );
      })}
    </div>
  );
}
"use client";

import { useEffect, useRef, useState, type MouseEvent } from "react";
import {
  ItemTooltipBox,
  TwoColumnLine,
  buildFallbackTooltipLines,
  extractEffectLines,
  extractSlotAndSubclass,
  formatMoneyTokens,
  formatSlotLabel,
  genericizeTooltipLines,
  renderTooltipLine,
} from "../../lib/tooltip";
import { iconUrlForFileId } from "../../lib/icons";

type ItemResult = {
  id: number;
  name: string;
  quality: string | null;
  quality_color: string | null;
  item_class: string | null;
  item_subclass: string | null;
  inventory_type: string | null;
  required_level: number | null;
  armor: number | null;
  damage_min: number | null;
  damage_max: number | null;
  weapon_speed: number | null;
  stats: { type: string; value: number }[] | null;
  sell_price: number | null;
  icon: number | null;
  verified: boolean;
  tooltip: string[] | null;
};

const QUALITY_OPTIONS: { value: string; label: string; color: string }[] = [
  { value: "", label: "All", color: "#d4d4d4" },
  { value: "POOR", label: "Poor", color: "#9d9d9d" },
  { value: "COMMON", label: "Common", color: "#ffffff" },
  { value: "UNCOMMON", label: "Uncommon", color: "#1eff00" },
  { value: "RARE", label: "Rare", color: "#0070dd" },
  { value: "EPIC", label: "Epic", color: "#a335ee" },
  { value: "LEGENDARY", label: "Legendary", color: "#ff8000" },
];

// Follows the cursor rather than anchoring to the row, and is positioned
// `fixed` (viewport-relative) so it's never clipped by the scrollable
// results panel - a plain absolutely-positioned tooltip inside an
// overflow/scroll container gets cut off exactly like the last version did.
function FollowTooltip({
  x,
  y,
  children,
}: {
  x: number;
  y: number;
  children: React.ReactNode;
}) {
  return (
    <div
      className="pointer-events-none fixed z-50"
      style={{ left: x + 16, top: y + 16 }}
    >
      {children}
    </div>
  );
}

function ItemRow({ item }: { item: ItemResult }) {
  const [hoverPos, setHoverPos] = useState<{ x: number; y: number } | null>(null);
  const iconSrc = iconUrlForFileId(item.icon);
  const color = item.quality_color ? `#${item.quality_color}` : "#ffffff";
  const hasRealTooltip = !!item.tooltip && item.tooltip.length > 0;
  const tooltipLines = hasRealTooltip
    ? genericizeTooltipLines(item.tooltip as string[])
    : buildFallbackTooltipLines(item);
  const note = hasRealTooltip
    ? undefined
    : tooltipLines.length > 0
      ? "Unconfirmed - based on Blizzard's classic database, may differ in Forever"
      : "No data captured yet - needs manual entry";

  // A verified item's real slot/armor-or-weapon-type never got written to
  // the inventory_type/item_subclass columns (applyLiveObservation doesn't
  // set them - see lib/items.ts), but a live tooltip already says it in
  // plain text, so that's read directly instead for anything verified.
  // Unverified Blizzard-baseline rows DO have those columns, so they still
  // work as the fallback.
  const parsedSlot = hasRealTooltip ? extractSlotAndSubclass(item.tooltip as string[]) : null;
  const slotLine = parsedSlot?.slot
    ? [parsedSlot.slot, parsedSlot.subclass].filter(Boolean).join("  ")
    : [formatSlotLabel(item.inventory_type), item.item_subclass].filter(Boolean).join("  ");

  const armorOrDamage =
    item.armor != null
      ? `${item.armor} Armor`
      : item.damage_min != null && item.damage_max != null
        ? `${item.damage_min} - ${item.damage_max} Damage  Speed ${item.weapon_speed ?? "?"}`
        : null;

  const statsSummary =
    item.stats && item.stats.length > 0
      ? item.stats.map((s) => `+${s.value} ${s.type}`).join("  ·  ")
      : null;

  const effectLines = hasRealTooltip ? extractEffectLines(item.tooltip) : [];

  function handleMove(e: MouseEvent) {
    setHoverPos({ x: e.clientX, y: e.clientY });
  }

  return (
    <div
      className="group relative flex items-center gap-3 rounded border border-neutral-800 px-3 py-2 hover:bg-neutral-800/60"
      onMouseMove={handleMove}
      onMouseLeave={() => setHoverPos(null)}
    >
      <div className="h-9 w-9 flex-shrink-0 overflow-hidden rounded border border-neutral-600 bg-neutral-800">
        {iconSrc && (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={iconSrc} alt="" className="h-full w-full object-cover" />
        )}
      </div>

      <div className="min-w-0 flex-1">
        <div className="flex items-baseline gap-2">
          <span className="truncate text-sm font-semibold" style={{ color }}>
            {item.name}
          </span>
          {!item.verified && (
            <span className="whitespace-nowrap text-[10px] text-yellow-400">Unconfirmed</span>
          )}
        </div>
        {slotLine && (
          <TwoColumnLine text={slotLine} className="max-w-[220px] text-xs text-gray-400" />
        )}
        {armorOrDamage && (
          <TwoColumnLine text={armorOrDamage} className="max-w-[220px] text-xs text-gray-300" />
        )}
        {statsSummary && (
          <div className="truncate text-xs text-gray-300">{statsSummary}</div>
        )}
        {effectLines.map((line, i) => (
          <div key={i} className="truncate text-xs text-[#1eff00]">
            {line}
          </div>
        ))}
      </div>

      <div className="flex-shrink-0 text-right text-xs text-gray-400">
        {item.required_level != null && <div>Req. {item.required_level}</div>}
        {item.sell_price != null && (
          <div>{renderTooltipLine(formatMoneyTokens(item.sell_price))}</div>
        )}
      </div>

      {hoverPos && (
        <FollowTooltip x={hoverPos.x} y={hoverPos.y}>
          <ItemTooltipBox
            name={item.name}
            qualityColor={item.quality_color}
            lines={tooltipLines}
            note={note}
          />
        </FollowTooltip>
      )}
    </div>
  );
}

export default function ItemSearch() {
  const [query, setQuery] = useState("");
  const [quality, setQuality] = useState("");
  const [stat, setStat] = useState("");
  const [results, setResults] = useState<ItemResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const requestId = useRef(0);

  useEffect(() => {
    const trimmedQuery = query.trim();
    const trimmedStat = stat.trim();
    const active = trimmedQuery.length >= 2 || quality.length > 0 || trimmedStat.length >= 2;

    if (!active) {
      setResults([]);
      setError(null);
      setLoading(false);
      return;
    }

    setLoading(true);
    const thisRequest = ++requestId.current;
    const handle = setTimeout(async () => {
      try {
        const params = new URLSearchParams();
        if (trimmedQuery.length >= 2) params.set("q", trimmedQuery);
        if (quality) params.set("quality", quality);
        if (trimmedStat.length >= 2) params.set("stat", trimmedStat);

        const res = await fetch(`/api/items/search?${params.toString()}`);
        const data = await res.json();
        if (thisRequest !== requestId.current) return;
        if (!res.ok) {
          setError(data.error ?? "Search failed");
          setResults([]);
        } else {
          setError(null);
          setResults(data.items ?? []);
        }
      } catch {
        if (thisRequest === requestId.current) {
          setError("Search failed");
          setResults([]);
        }
      } finally {
        if (thisRequest === requestId.current) setLoading(false);
      }
    }, 250);

    return () => clearTimeout(handle);
  }, [query, quality, stat]);

  const active = query.trim().length >= 2 || quality.length > 0 || stat.trim().length >= 2;

  return (
    <div>
      <div className="flex flex-wrap items-center gap-2">
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search items..."
          className="w-full max-w-md rounded border border-neutral-700 bg-neutral-900 px-3 py-2 text-sm text-white placeholder:text-gray-500"
          autoFocus
        />
        <input
          type="text"
          value={stat}
          onChange={(e) => setStat(e.target.value)}
          placeholder="Filter by stat (e.g. Strength)"
          className="w-full max-w-[220px] rounded border border-neutral-700 bg-neutral-900 px-3 py-2 text-sm text-white placeholder:text-gray-500"
        />
      </div>

      <div className="mt-3 flex flex-wrap gap-2">
        {QUALITY_OPTIONS.map((opt) => (
          <button
            key={opt.value}
            type="button"
            onClick={() => setQuality(opt.value)}
            className="chip"
            style={{
              color: opt.color,
              borderColor: quality === opt.value ? opt.color : undefined,
              opacity: quality === opt.value || quality === "" ? 1 : 0.5,
            }}
          >
            {opt.label}
          </button>
        ))}
      </div>

      {query.trim().length > 0 && query.trim().length < 2 && (
        <p className="mt-3 text-sm text-gray-400">Keep typing - at least 2 characters.</p>
      )}
      {loading && <p className="mt-3 text-sm text-gray-500">Searching...</p>}
      {error && <p className="mt-3 text-sm text-red-400">{error}</p>}
      {!active && (
        <p className="mt-3 text-sm text-gray-400">
          Start typing a name, pick a quality, or filter by a stat to browse the item database.
        </p>
      )}

      {active && !loading && !error && (
        <p className="mt-4 text-xs text-gray-500">
          {results.length} result{results.length === 1 ? "" : "s"}
        </p>
      )}

      {active && !loading && !error && results.length > 0 && (
        <div
          className="mt-1 max-h-[70vh] overflow-y-auto rounded-md p-2"
          style={{ background: "#0c0c14", border: "1px solid #c8aa6e" }}
        >
          <div className="grid grid-cols-1 gap-2 lg:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4">
            {results.map((item) => (
              <ItemRow key={item.id} item={item} />
            ))}
          </div>
        </div>
      )}

      {active && !loading && !error && results.length === 0 && (
        <p className="mt-3 text-sm text-gray-400">No items found matching those filters.</p>
      )}
    </div>
  );
}
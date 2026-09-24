"use client";

import { useEffect, useRef, useState } from "react";
import { ItemTooltipBox, buildFallbackTooltipLines, genericizeTooltipLines } from "../../lib/tooltip";
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
        if (thisRequest !== requestId.current) return; // a newer keystroke already fired
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

  return (
    <div>
      <div className="flex flex-wrap items-center gap-2">
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Start typing an item name..."
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
      {!loading &&
        !error &&
        (query.trim().length >= 2 || quality || stat.trim().length >= 2) &&
        results.length === 0 && (
          <p className="mt-3 text-sm text-gray-400">No items found matching those filters.</p>
        )}
      {!loading && !query && !quality && !stat && (
        <p className="mt-3 text-sm text-gray-400">
          Start typing a name, pick a quality, or filter by a stat to browse the item database.
        </p>
      )}

      <div className="mt-4 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        {results.map((item) => {
          const iconSrc = iconUrlForFileId(item.icon);
          const hasRealTooltip = !!item.tooltip && item.tooltip.length > 0;
          const lines = hasRealTooltip
            ? genericizeTooltipLines(item.tooltip as string[])
            : buildFallbackTooltipLines(item);
          const note = hasRealTooltip
            ? undefined
            : lines.length > 0
              ? "Unconfirmed - based on Blizzard's classic database, may differ in Forever"
              : "No data captured yet - needs manual entry";

          return (
            <div key={item.id} className="flex items-start gap-3">
              <div className="h-12 w-12 flex-shrink-0 overflow-hidden rounded border border-neutral-600 bg-neutral-800">
                {iconSrc && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={iconSrc} alt="" className="h-full w-full object-cover" />
                )}
              </div>
              <ItemTooltipBox
                name={item.name}
                qualityColor={item.quality_color}
                lines={lines}
                note={note}
                className="flex-1"
              />
            </div>
          );
        })}
      </div>
    </div>
  );
}
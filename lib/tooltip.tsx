import type { ReactNode } from "react";

// Shared with GearCard.tsx's own ItemTooltip - same visual language (dark
// gradient panel, gold border, quality-colored title, coin dots for
// gold/silver/copper, green "<Made by X>" line) so an item looks the same
// whether you're looking at a character's equipped gear or browsing the
// Items page. GearCard keeps its own copy inline (it also handles hover
// positioning, which this shared version deliberately doesn't - callers
// decide whether to float it or lay it out inline).

const COIN_COLORS: Record<string, string> = {
  gold: "#ffd700",
  silver: "#c0c0c0",
  copper: "#b87333",
};

// The addon's stripMarkup swaps the Sell Price line's inline coin icons for
// {gold}/{silver}/{copper} tokens (curly braces) - handled defensively for
// [gold]/[silver]/[copper] too. Either way they become small colored coin
// dots instead of sitting on the page as literal text.
export function renderTooltipLine(line: string): ReactNode[] {
  const parts = line.split(/([{[](?:gold|silver|copper)[}\]])/g);
  return parts.map((part, i) => {
    const m = /^[{[](gold|silver|copper)[}\]]$/.exec(part);
    if (!m) return <span key={i}>{part}</span>;
    return (
      <span
        key={i}
        title={m[1]}
        className="mx-0.5 inline-block h-2.5 w-2.5 shrink-0 rounded-full align-middle"
        style={{ backgroundColor: COIN_COLORS[m[1]] }}
      />
    );
  });
}

export function isCraftedByLine(line: string) {
  return /^<.*made by.*>$/i.test(line.trim());
}

// "Equip: ..." proc/aura lines render green in the real game, same as a
// crafted-by line - both use isCraftedByLine's green in ItemTooltipBox.
export function isEquipLine(line: string) {
  return /^Equip:/i.test(line.trim());
}

const MADE_BY_RE = /^<.*made by.*>$/i;
const DURABILITY_RE = /^Durability \d+ \/ (\d+)$/;

// A scanned tooltip reflects ONE specific instance of an item (a particular
// character's crafter, that character's current wear-and-tear) - fine for
// GearCard showing a real equipped item, but misleading for the shared item
// database, which describes the item in general. This swaps those two
// instance-specific lines for generic ones: crafted-by loses the name, and
// durability resets to full (max/max) rather than whatever it happened to
// be worn down to when it was scanned.
export function genericizeTooltipLines(lines: string[]): string[] {
  return lines.map((line) => {
    if (MADE_BY_RE.test(line.trim())) return "<Made by a player>";
    const durabilityMatch = line.match(DURABILITY_RE);
    if (durabilityMatch) return `Durability ${durabilityMatch[1]} / ${durabilityMatch[1]}`;
    return line;
  });
}

// Blizzard's SCREAMING_CASE inventory type -> a normal-looking slot label,
// e.g. "MAINHAND" -> "Main Hand".
export function formatSlotLabel(inventoryType: string | null): string {
  if (!inventoryType) return "";
  const spaced = inventoryType.toLowerCase().replace(/hand/g, " hand").trim();
  return spaced
    .split(/\s+/)
    .filter(Boolean)
    .map((w) => w[0].toUpperCase() + w.slice(1))
    .join(" ");
}

// Formats copper into the same "{gold} {silver} {copper}" token line the
// addon's own scanned tooltips use, so it renders through renderTooltipLine
// identically to a real captured Sell Price line.
export function formatSellPriceLine(copper: number): string {
  const gold = Math.floor(copper / 10000);
  const silver = Math.floor((copper % 10000) / 100);
  const cop = copper % 100;
  const segments: string[] = [];
  if (gold > 0) segments.push(`${gold}{gold}`);
  if (gold > 0 || silver > 0) segments.push(`${silver}{silver}`);
  segments.push(`${cop}{copper}`);
  return `Sell Price: ${segments.join(" ")}`;
}

export type FallbackTooltipItem = {
  item_subclass: string | null;
  inventory_type: string | null;
  required_level: number | null;
  armor: number | null;
  damage_min: number | null;
  damage_max: number | null;
  weapon_speed: number | null;
  stats: { type: string; value: number }[] | null;
  sell_price: number | null;
};

// For an item with no real scanned tooltip yet (an unverified Blizzard-
// baseline row, or a bare auto_new placeholder) - builds tooltip-shaped
// lines out of whatever structured fields ARE known, so it still lays out
// like a real tooltip instead of a bare data table. Returns [] when there's
// nothing at all to show (a placeholder with only a name).
export function buildFallbackTooltipLines(item: FallbackTooltipItem): string[] {
  const lines: string[] = [];
  const slotLabel = formatSlotLabel(item.inventory_type);
  if (slotLabel || item.item_subclass) {
    lines.push([slotLabel, item.item_subclass].filter(Boolean).join("  "));
  }
  if (item.damage_min != null && item.damage_max != null) {
    lines.push(
      `${item.damage_min} - ${item.damage_max} Damage  Speed ${item.weapon_speed ?? "?"}`
    );
  }
  if (item.armor != null) {
    lines.push(`${item.armor} Armor`);
  }
  if (item.stats) {
    for (const s of item.stats) lines.push(`+${s.value} ${s.type}`);
  }
  if (item.required_level != null) {
    lines.push(`Requires Level ${item.required_level}`);
  }
  if (item.sell_price != null) {
    lines.push(formatSellPriceLine(item.sell_price));
  }
  return lines;
}

// The full WoW-style tooltip panel, unpositioned - GearCard floats its own
// copy as a hover popup; the Items page renders this inline in a list
// instead, which is why positioning isn't baked in here.
export function ItemTooltipBox({
  name,
  qualityColor,
  lines,
  note,
  className = "",
}: {
  name: string;
  qualityColor: string | null;
  lines: string[];
  note?: string;
  className?: string;
}) {
  const color = qualityColor ? `#${qualityColor}` : "#ffffff";
  return (
    <div
      className={`w-full max-w-xs rounded-md p-3 text-left text-sm shadow-lg ${className}`}
      style={{
        background: "linear-gradient(180deg, #0c0c14, #000005)",
        border: "1px solid #c8aa6e",
      }}
    >
      <div className="font-semibold" style={{ color }}>
        {name}
      </div>
      {lines
        .filter((line) => line !== name)
        .map((line, i) => (
          <div
            key={i}
            className={
              isCraftedByLine(line) || isEquipLine(line) ? "text-[#1eff00]" : "text-white"
            }
          >
            {renderTooltipLine(line)}
          </div>
        ))}
      {note && (
        <div className="mt-2 border-t border-neutral-700 pt-1.5 text-xs text-yellow-400">
          {note}
        </div>
      )}
    </div>
  );
}
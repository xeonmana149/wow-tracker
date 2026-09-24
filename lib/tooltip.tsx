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

// "Equip: ..." and "Use: ..." effect lines both render green in the real
// game, same as a crafted-by line - all three share the green in
// ItemTooltipBox.
export function isEquipLine(line: string) {
  return /^Equip:/i.test(line.trim());
}

export function isUseLine(line: string) {
  return /^Use:/i.test(line.trim());
}

// Tier-set "other piece" names render dim/indented in the real tooltip
// (e.g. under "Stormrage Raiment (0/8)"). Using non-breaking spaces (not
// plain spaces) as the indent so TwoColumnLine's "2+ plain spaces = two
// columns" split (see below) doesn't mistake the indent for a column gap.
const SET_PIECE_INDENT = "  ";

export function isSetPieceLine(line: string) {
  return line.startsWith(SET_PIECE_INDENT);
}

// "(3) Set: ..." / "(5) Set: ..." bonus tier lines - rendered green, same as
// an Equip:/Use: effect, since that's how the real tooltip colors them.
export function isSetBonusLine(line: string) {
  return /^\(\d+\)\s*Set:/i.test(line.trim());
}

// "Xeon Mana knows this recipe" / "Xeon Mana can craft this" - the
// friends-can-see-who-can-make-it lines added by lib/craftedBy.ts, not
// anything Blizzard's own tooltip ever shows. Colored the same sky blue as
// the existing "→ so-and-so can make this" character-comparison suggestion
// on the Items page, since it's the same kind of "someone you know can help
// with this" callout.
export function isKnownByLine(line: string) {
  return /(knows this recipe|can craft this)$/i.test(line.trim());
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

// Blizzard's inventory_type.type enum doesn't spell anything out in full
// (e.g. weapons are "WEAPONMAINHAND" / "TWOHWEAPON" / "WEAPONOFFHAND", not
// "MAINHAND"/"TWOHAND" - a generic "insert a space before 'hand'" rule
// mangles those), so this maps the specific codes actually seen from
// Blizzard's API to the label WoW itself shows, falling back to a generic
// title-case split only for anything unmapped.
const INVENTORY_TYPE_LABELS: Record<string, string> = {
  HEAD: "Head",
  NECK: "Neck",
  SHOULDER: "Shoulder",
  BODY: "Shirt",
  CHEST: "Chest",
  ROBE: "Chest",
  WAIST: "Waist",
  LEGS: "Legs",
  FEET: "Feet",
  WRIST: "Wrist",
  HAND: "Hands",
  HANDS: "Hands",
  FINGER: "Finger",
  TRINKET: "Trinket",
  CLOAK: "Back",
  BACK: "Back",
  TABARD: "Tabard",
  BAG: "Bag",
  QUIVER: "Quiver",
  AMMO: "Ammo",
  RELIC: "Relic",
  WEAPON: "One-Hand",
  WEAPONMAINHAND: "Main Hand",
  WEAPONOFFHAND: "Off Hand",
  TWOHWEAPON: "Two-Hand",
  SHIELD: "Off Hand",
  HOLDABLE: "Off Hand",
  RANGED: "Ranged",
  RANGEDRIGHT: "Ranged",
  THROWN: "Thrown",
  // Most bulk-seeded baseline items (consumables, quest items, trade goods,
  // reagents...) aren't equippable at all - Blizzard marks these
  // NON_EQUIP, and the real game shows no slot line whatsoever for them, so
  // this maps to an explicit "" rather than falling through to the generic
  // fallback below, which used to turn it into the literal "Non_equip".
  NON_EQUIP: "",
};

export function formatSlotLabel(inventoryType: string | null): string {
  if (!inventoryType) return "";
  const mapped = INVENTORY_TYPE_LABELS[inventoryType.toUpperCase()];
  // Checked with `!== undefined` rather than truthiness - NON_EQUIP maps to
  // "" on purpose, which a truthy check would skip straight past into the
  // generic fallback below.
  if (mapped !== undefined) return mapped;
  return inventoryType
    .toLowerCase()
    .split(/[\s_]+/)
    .filter(Boolean)
    .map((w) => w[0].toUpperCase() + w.slice(1))
    .join(" ");
}

// applyLiveObservation (lib/items.ts) never stores inventory_type/
// item_subclass on a verified row - a live tooltip already SAYS the slot
// and armor/weapon type in plain text ("Waist  Mail", "Two-Hand  Sword"),
// two columns separated by the addon's own "  " (two-space) join, so this
// reads it straight from there instead of relying on a column that's
// simply never populated for a verified item. Longest/most specific labels
// aren't needed here since none of these happen to prefix one another.
export const KNOWN_SLOT_LABELS = [
  "Main Hand",
  "Off Hand",
  "Two-Hand",
  "One-Hand",
  "Ranged",
  "Thrown",
  "Head",
  "Neck",
  "Shoulder",
  "Shirt",
  "Chest",
  "Waist",
  "Legs",
  "Feet",
  "Wrist",
  "Hands",
  "Finger",
  "Trinket",
  "Back",
  "Tabard",
  "Relic",
  "Ammo",
  "Bag",
];

export function extractSlotAndSubclass(tooltip: string[]): {
  slot: string | null;
  subclass: string | null;
} {
  for (const line of tooltip.slice(1)) {
    for (const label of KNOWN_SLOT_LABELS) {
      if (line === label) {
        return { slot: label, subclass: null };
      }
      if (line.startsWith(`${label}  `)) {
        return { slot: label, subclass: line.slice(label.length + 2).trim() };
      }
    }
  }
  return { slot: null, subclass: null };
}

// The bare "{gold} {silver} {copper}" tokens, no "Sell Price:" label - for
// compact contexts (the Items list row) that show a price without the full
// tooltip line around it.
export function formatMoneyTokens(copper: number): string {
  const gold = Math.floor(copper / 10000);
  const silver = Math.floor((copper % 10000) / 100);
  const cop = copper % 100;
  const segments: string[] = [];
  if (gold > 0) segments.push(`${gold}{gold}`);
  if (gold > 0 || silver > 0) segments.push(`${silver}{silver}`);
  segments.push(`${cop}{copper}`);
  return segments.join(" ");
}

// Formats copper into the same "{gold} {silver} {copper}" token line the
// addon's own scanned tooltips use, so it renders through renderTooltipLine
// identically to a real captured Sell Price line.
export function formatSellPriceLine(copper: number): string {
  return `Sell Price: ${formatMoneyTokens(copper)}`;
}

// Lines that render green in-game and matter for judging an item at a
// glance (a proc, a use-effect) - pulled out of a real scanned tooltip so
// the compact Items-list row can surface them without showing the whole
// tooltip. Only meaningful for a verified item; Blizzard's baseline data
// has no way to know about a Forever-specific proc on an unconfirmed item.
export function extractEffectLines(tooltip: string[] | null | undefined): string[] {
  if (!tooltip) return [];
  return tooltip.filter((line) => isEquipLine(line) || isUseLine(line));
}

// The addon deliberately joins a tooltip's left/right columns (e.g.
// "Two-Hand" + "Sword", "52 - 78 Damage" + "Speed 3.30") with exactly two
// spaces (see scanSlotTooltip in the addon: `leftText .. "  " .. rightText`)
// - but HTML collapses repeated whitespace, so rendered as plain text that
// structure just disappears and everything reads as one run-on line. This
// splits on the first 2+-space gap and lays the two halves out with real
// space between them, matching the real tooltip's look.
export function TwoColumnLine({
  text,
  className = "",
  leftClassName,
  rightClassName,
}: {
  text: string;
  className?: string;
  // Override just one side's color (e.g. turning only "Axe" red while
  // "Two-Hand" stays its normal color, matching how the real tooltip/
  // auction house only reddens the specific thing you fail, not the whole
  // line). Left unset, both sides inherit `className`'s color as normal.
  leftClassName?: string;
  rightClassName?: string;
}) {
  const match = text.match(/^(.*?) {2,}(.*)$/);
  if (!match) {
    return <div className={className}>{renderTooltipLine(text)}</div>;
  }
  return (
    <div className={`flex justify-between gap-4 ${className}`}>
      <span className={leftClassName}>{renderTooltipLine(match[1])}</span>
      <span className={rightClassName}>{renderTooltipLine(match[2])}</span>
    </div>
  );
}

export type FallbackTooltipItem = {
  level?: number | null;
  item_subclass: string | null;
  inventory_type: string | null;
  required_level: number | null;
  armor: number | null;
  damage_min: number | null;
  damage_max: number | null;
  weapon_speed: number | null;
  weapon_dps?: number | null;
  binding?: string | null;
  durability?: number | null;
  spell_lines?: string[] | null;
  profession_requirement?: string | null;
  reagents_text?: string | null;
  // "Classes: Druid" - only present on some class-restricted items (see
  // lib/items.ts's classes_text comment for the Atiesh caveat).
  classes_text?: string | null;
  // "Stormrage Raiment (0/8)" - set name + how many pieces are equipped
  // (always 0 for the shared item database, which isn't about any one
  // character's actual gear).
  item_set_line?: string | null;
  item_set_pieces?: string[] | null;
  item_set_bonuses?: string[] | null;
  stats: { type: string; value: number }[] | null;
  sell_price: number | null;
};

// For an item with no real scanned tooltip yet (an unverified Blizzard-
// baseline row, or a bare auto_new placeholder) - builds tooltip-shaped
// lines out of whatever structured fields ARE known, so it still lays out
// like a real tooltip instead of a bare data table. Returns [] when there's
// nothing at all to show (a placeholder with only a name).
//
// Line order follows the real in-game tooltip (checked 2026-09-24 against a
// live Stormrage Bracers tooltip, a Druid Tier 3 set piece): item level,
// binding, profession requirement (recipes), slot/type, damage+speed+dps,
// armor, stats, durability, class restriction, required level, Use:/Equip:
// text, then (if it's a set piece) a blank line, the set name/progress, the
// other pieces indented underneath, a blank line, and the set's bonus
// tiers - sell price and a recipe's reagent cost come last.
export function buildFallbackTooltipLines(item: FallbackTooltipItem): string[] {
  const lines: string[] = [];
  if (item.level != null) {
    lines.push(`Item Level ${item.level}`);
  }
  if (item.binding) {
    lines.push(item.binding);
  }
  if (item.profession_requirement) {
    lines.push(item.profession_requirement);
  }
  const slotLabel = formatSlotLabel(item.inventory_type);
  if (slotLabel || item.item_subclass) {
    lines.push([slotLabel, item.item_subclass].filter(Boolean).join("  "));
  }
  if (item.damage_min != null && item.damage_max != null) {
    lines.push(
      `${item.damage_min} - ${item.damage_max} Damage  Speed ${item.weapon_speed?.toFixed(2) ?? "?"}`
    );
    if (item.weapon_dps != null) {
      lines.push(`(${item.weapon_dps.toFixed(2)} damage per second)`);
    }
  }
  if (item.armor != null) {
    lines.push(`${item.armor} Armor`);
  }
  if (item.stats) {
    for (const s of item.stats) lines.push(`+${s.value} ${s.type}`);
  }
  if (item.durability != null) {
    lines.push(`Durability ${item.durability} / ${item.durability}`);
  }
  if (item.classes_text) {
    lines.push(item.classes_text);
  }
  if (item.required_level != null) {
    lines.push(`Requires Level ${item.required_level}`);
  }
  if (item.spell_lines) {
    for (const line of item.spell_lines) lines.push(line);
  }
  if (item.item_set_line) {
    lines.push("");
    lines.push(item.item_set_line);
    if (item.item_set_pieces) {
      for (const piece of item.item_set_pieces) lines.push(`${SET_PIECE_INDENT}${piece}`);
    }
    if (item.item_set_bonuses && item.item_set_bonuses.length > 0) {
      lines.push("");
      for (const bonus of item.item_set_bonuses) lines.push(bonus);
    }
  }
  if (item.sell_price != null) {
    lines.push(formatSellPriceLine(item.sell_price));
  }
  if (item.reagents_text) {
    lines.push(item.reagents_text);
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
  noteClassName = "text-yellow-400",
  characterNote,
  lineColor,
  className = "",
}: {
  name: string;
  qualityColor: string | null;
  lines: string[];
  note?: ReactNode;
  // Color for the note footer - defaults to the "Unconfirmed" yellow;
  // callers pass the green "confirmed" color when the note is instead
  // saying a real player's addon has actually scanned this item in Forever.
  noteClassName?: string;
  // An optional per-line color override - used by the Items page to turn a
  // "Requires Level N" / weapon-or-armor-type / "Requires <Profession> (N)"
  // line red when a selected character doesn't meet it, the same way the
  // real tooltip and the auction house do. Returning null/undefined falls
  // back to the default (green for crafted-by/Equip/Use, white otherwise).
  lineColor?: (
    line: string
  ) => { className?: string; leftClassName?: string; rightClassName?: string } | null | undefined;
  // A second footer, below the "Unconfirmed" note, for character-comparison
  // messaging (e.g. a red "you don't meet this" or a suggestion to use a
  // different character) - kept separate so it can have its own color.
  characterNote?: ReactNode;
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
        .map((line, i) => {
          const override = lineColor?.(line);
          const defaultClass =
            isCraftedByLine(line) || isEquipLine(line) || isUseLine(line) || isSetBonusLine(line)
              ? "text-[#1eff00]"
              : isSetPieceLine(line)
              ? "text-gray-400"
              : isKnownByLine(line)
              ? "text-sky-400"
              : "text-white";
          return (
            <TwoColumnLine
              key={i}
              text={line}
              className={override?.className ?? defaultClass}
              leftClassName={override?.leftClassName}
              rightClassName={override?.rightClassName}
            />
          );
        })}
      {note && (
        <div className={`mt-2 border-t border-neutral-700 pt-1.5 text-xs ${noteClassName}`}>
          {note}
        </div>
      )}
      {characterNote && (
        <div className="mt-1.5 text-xs">{characterNote}</div>
      )}
    </div>
  );
}
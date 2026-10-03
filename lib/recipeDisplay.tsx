"use client";

import { useState } from "react";
import { iconUrlForFileId } from "./icons";
import { renderTooltipLine } from "./tooltip";
import GameIcon from "../app/GameIcon";

// Shared recipe-chip rendering (2026-10-03, pulled out of
// app/crafting/CraftingDirectory.tsx so the character page's Professions
// card can show the exact same expandable recipe list/tooltip instead of
// just a bare "N recipes known" count - "maybe that list should be part of
// the character page somehow?"). Both places read from the same
// character_professions.recipes column, so this is one rendering
// implementation instead of two copies that could drift apart.

export type Reagent = {
  itemID: number;
  name: string;
  icon?: number | string | null;
  quantity: number;
  // Bare "rrggbb" hex (no '#'), read off the reagent's own rendered
  // tooltip color in-game - this server's items don't reliably carry
  // quality any other way.
  color?: string | null;
};

export type Recipe = {
  name: string;
  icon?: number | string | null;
  reagents?: Reagent[];
  // Raw tooltip text lines scraped from the crafted item, e.g. "Use:
  // Constructs a sharpening wheel..." / "Requires a Campfire nearby" -
  // line 1 is always just the item's own name, so it's skipped wherever
  // this is displayed. Coin values on a Sell Price line come through as
  // literal {gold}/{silver}/{copper} tokens (see lib/tooltip's
  // renderTooltipLine) rather than real numbers - everything else is plain
  // white/gray text, same as the rest of the site's item tooltips.
  tooltip?: string[];
  // The crafted item's own quality color, same "rrggbb" hex convention.
  color?: string | null;
};

// A recipe entry is a bare string on an addon build from before 1.3.0 (no
// icon capture yet), or a progressively richer object on newer ones
// (icon+id at 1.3.0, reagents+tooltip after that) - this makes every entry
// look the same regardless of which addon version actually produced it.
export function normalizeRecipe(r: string | Recipe): Recipe {
  return typeof r === "string" ? { name: r } : r;
}

// A game icon with a colored ring around it matching the item's quality
// (green/blue/purple/etc, same as the in-game border) - falls back to
// GameIcon's own default border when no color was captured.
export function QualityIcon({
  src,
  label,
  size,
  color,
}: {
  src?: string | null;
  label: string;
  size: number;
  color?: string | null;
}) {
  return (
    <span
      className="inline-block shrink-0 rounded"
      style={color ? { boxShadow: `0 0 0 2px #${color}` } : undefined}
    >
      <GameIcon src={src} label={label} size={size} />
    </span>
  );
}

// A recipe's "Use: ..." description and reagent list, shown when a
// RecipeChip is expanded - styled loosely like the real in-game tooltip
// (dark box, gold border) even though the colors on individual lines
// couldn't be preserved, only the text.
export function RecipeDetails({ r }: { r: Recipe }) {
  // Line 1 of a scraped tooltip is always just the item's own name, which
  // is already shown as the chip's label - skip it here to avoid repeating.
  const lines = (r.tooltip ?? []).slice(1);
  const reagents = r.reagents ?? [];

  if (lines.length === 0 && reagents.length === 0) {
    return (
      <div className="mt-2 rounded-lg border border-amber-700/60 bg-neutral-950 p-3">
        <p className="text-xs text-gray-500">
          No extra details captured for this recipe yet - run /wft recipescan again in-game to
          pick them up.
        </p>
      </div>
    );
  }

  return (
    <div className="w-72 max-w-full rounded-lg border border-amber-700/60 bg-neutral-950 p-3">
      {lines.map((line, i) => (
        <p key={i} className="text-xs leading-snug text-gray-300">
          {renderTooltipLine(line)}
        </p>
      ))}
      {reagents.length > 0 && (
        <div className={lines.length > 0 ? "mt-2 border-t border-neutral-800 pt-2" : ""}>
          <p className="text-xs font-bold text-amber-400">Reagents</p>
          <ul className="mt-1 flex flex-col gap-1">
            {reagents.map((rg) => (
              <li key={rg.itemID} className="flex items-center gap-1.5 text-xs">
                <QualityIcon src={iconUrlForFileId(rg.icon)} label={rg.name} size={20} color={rg.color} />
                <span style={rg.color ? { color: `#${rg.color}` } : undefined} className="text-gray-300">
                  {rg.quantity}x {rg.name}
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

// A single recipe pill - hovering shows its tooltip text and reagent list
// in a floating panel below it, just like hovering the recipe in-game.
// Also toggles on click/tap, since hover doesn't exist on touch devices.
export function RecipeChip({ r }: { r: Recipe }) {
  const [open, setOpen] = useState(false);

  return (
    <div
      className="relative"
      onMouseEnter={() => setOpen(true)}
      onMouseLeave={() => setOpen(false)}
    >
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="flex items-center gap-1 rounded border border-neutral-700 bg-neutral-900 py-0.5 pl-0.5 pr-1.5 text-xs hover:border-amber-500"
      >
        <QualityIcon src={iconUrlForFileId(r.icon)} label={r.name} size={18} color={r.color} />
        <span style={r.color ? { color: `#${r.color}` } : undefined} className="text-gray-300">
          {r.name}
        </span>
      </button>
      {open && (
        <div className="absolute left-0 top-full z-30 mt-1">
          <RecipeDetails r={r} />
        </div>
      )}
    </div>
  );
}

// A full wrap-list of recipe chips, sorted alphabetically - the exact
// layout CraftingDirectory's CrafterRow uses when expanded, now reusable
// anywhere a profession's known-recipe list needs to show up (e.g. the
// character page's Professions card).
export function RecipeChipList({ recipes }: { recipes: (string | Recipe)[] }) {
  const normalized = recipes.map(normalizeRecipe);
  if (normalized.length === 0) return null;
  return (
    <div className="flex flex-wrap gap-1.5">
      {[...normalized]
        .sort((a, b) => a.name.localeCompare(b.name))
        .map((r) => (
          <RecipeChip key={r.name} r={r} />
        ))}
    </div>
  );
}

"use client";

import { useEffect, useLayoutEffect, useMemo, useRef, useState, type MouseEvent, type ReactNode } from "react";
import {
  ItemTooltipBox,
  KNOWN_BY_COLOR_CLASS,
  KNOWN_SLOT_LABELS,
  buildFallbackTooltipLines,
  extractEffectLines,
  extractSlotAndSubclass,
  formatMoneyTokens,
  formatSlotLabel,
  genericizeTooltipLines,
  renderTooltipLine,
} from "../../lib/tooltip";
import { iconUrlForFileId, wowIconUrl } from "../../lib/icons";
import { supabase } from "../../lib/supabase";
import { addToPreBis, addToWishlist } from "../../lib/itemLists";
import { findCraftedBy, formatKnownByLines, type CraftedByInfo, type CraftReagent } from "../../lib/craftedBy";
import {
  characterMeetsProfession,
  classCanUseSubclass,
  extractProfessionRequirement,
  type CharacterSummary,
} from "../../lib/classRequirements";

type ItemResult = {
  id: number;
  name: string;
  quality: string | null;
  quality_color: string | null;
  item_class: string | null;
  item_subclass: string | null;
  inventory_type: string | null;
  level: number | null;
  required_level: number | null;
  armor: number | null;
  damage_min: number | null;
  damage_max: number | null;
  weapon_speed: number | null;
  weapon_dps: number | null;
  binding: string | null;
  durability: number | null;
  spell_lines: string[] | null;
  profession_requirement: string | null;
  reagents_text: string | null;
  classes_text: string | null;
  item_set_line: string | null;
  item_set_pieces: string[] | null;
  item_set_bonuses: string[] | null;
  stats: { type: string; value: number }[] | null;
  sell_price: number | null;
  icon: number | null;
  icon_name: string | null;
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

// Auction-House-style category tabs. Values match the keys
// /api/items/search maps to Blizzard's own item_class text server-side.
const CATEGORY_OPTIONS: { value: string; label: string }[] = [
  { value: "", label: "All" },
  { value: "weapon", label: "Weapons" },
  { value: "armor", label: "Armor" },
  { value: "container", label: "Containers" },
  { value: "consumable", label: "Consumables" },
  { value: "tradegoods", label: "Trade Goods" },
  { value: "ammo", label: "Ammo" },
  { value: "recipe", label: "Recipes" },
  { value: "quest", label: "Quest Items" },
  { value: "misc", label: "Misc" },
];

// Sorting (including quality's rank order) now happens server-side in
// /api/items/search, so it's correct across pages instead of only within
// whatever single batch used to get fetched.
type SortOption = "relevance" | "name" | "level" | "quality";
const SORT_OPTIONS: { value: SortOption; label: string }[] = [
  { value: "relevance", label: "Relevance" },
  { value: "name", label: "Name (A-Z)" },
  { value: "level", label: "Item Level" },
  { value: "quality", label: "Quality" },
];

// Clamps text to 2 visual lines instead of the old single-line `truncate` -
// long stat lists and Equip:/Use: text now wrap onto a second line instead
// of getting cut off after a handful of characters, while still keeping a
// card from growing unbounded for something with a huge tooltip.
const CLAMP_2: React.CSSProperties = {
  display: "-webkit-box",
  WebkitLineClamp: 2,
  WebkitBoxOrient: "vertical",
  overflow: "hidden",
};

// Keyed by item name (not id - a recipe and its crafted item are two
// different rows but share the same lookup) so a name only ever gets
// looked up once per page visit, no matter how many cards/inspector opens
// hover over it. Module-level (outside the component) so it survives
// re-renders and is shared across every ItemRow/ItemInspector on the page.
const craftedByCache = new Map<string, CraftedByInfo>();

// Only fetches once `active` (hovered, or the details panel is open for
// this item) - not on every card's initial mount, since that would fire a
// query per visible result just for browsing the list. findCraftedBy itself
// caches the underlying recipe data for 5 minutes, so even the first hover
// of a page visit is usually served from that, not a fresh query.
function useCraftedByOnDemand(item: ItemResult, active: boolean): CraftedByInfo | null {
  const [craftedBy, setCraftedBy] = useState<CraftedByInfo | null>(
    craftedByCache.get(item.name) ?? null
  );

  useEffect(() => {
    if (!active || craftedByCache.has(item.name)) return;
    let cancelled = false;
    findCraftedBy(supabase, item.name, item.item_class).then((result) => {
      craftedByCache.set(item.name, result);
      if (!cancelled) setCraftedBy(result);
    });
    return () => {
      cancelled = true;
    };
  }, [active, item.name, item.item_class]);

  return craftedBy;
}

// All the per-item derived display data (icon, tooltip lines, the character-
// comparison warnings, etc.) - pulled out into one place so both the compact
// card (ItemRow) and the bigger persistent details panel (ItemInspector) show
// exactly the same information instead of two hand-maintained copies.
function computeItemDisplay(
  item: ItemResult,
  character: CharacterSummary | null,
  allCharacters: CharacterSummary[]
) {
  const iconSrc = iconUrlForFileId(item.icon) ?? (item.icon_name ? wowIconUrl(item.icon_name) : null);
  const color = item.quality_color ? `#${item.quality_color}` : "#ffffff";
  const hasRealTooltip = !!item.tooltip && item.tooltip.length > 0;
  const tooltipLines = hasRealTooltip
    ? genericizeTooltipLines(item.tooltip as string[])
    : buildFallbackTooltipLines(item);
  // A verified row means a real player's addon actually scanned this item
  // in Forever (applyLiveObservation, lib/items.ts) - that always overwrites
  // and permanently outranks Blizzard's classic baseline, so this says so
  // plainly rather than just staying silent the way an unverified row's
  // badge does.
  const note = item.verified
    ? "Confirmed in Forever - seen on a real character"
    : tooltipLines.length > 0
      ? "Unconfirmed - based on Blizzard's classic database, may differ in Forever"
      : "No data captured yet - needs manual entry";

  const parsedSlot = hasRealTooltip ? extractSlotAndSubclass(item.tooltip as string[]) : null;
  const subclassForCheck = parsedSlot?.subclass ?? item.item_subclass;
  const slotPart = parsedSlot?.slot ?? formatSlotLabel(item.inventory_type);
  const subclassPart = parsedSlot?.subclass ?? item.item_subclass;

  const armorOrDamage =
    item.armor != null
      ? `${item.armor} Armor`
      : item.damage_min != null && item.damage_max != null
        ? `${item.damage_min} - ${item.damage_max} Damage  Speed ${item.weapon_speed?.toFixed(2) ?? "?"}`
        : null;
  const dpsLine = armorOrDamage && item.weapon_dps != null ? `(${item.weapon_dps.toFixed(2)} damage per second)` : null;

  const statsSummary =
    item.stats && item.stats.length > 0
      ? item.stats.map((s) => `+${s.value} ${s.type}`).join("  ·  ")
      : null;

  const effectLines = hasRealTooltip ? extractEffectLines(item.tooltip) : (item.spell_lines ?? []);

  const levelBad =
    !!character && item.required_level != null && item.required_level > character.level;
  const classBad = !!character && !classCanUseSubclass(character.class, subclassForCheck);
  const profReq = hasRealTooltip
    ? extractProfessionRequirement(item.tooltip)
    : item.profession_requirement
      ? extractProfessionRequirement([item.profession_requirement])
      : null;
  const profBad = !!character && !!profReq && !characterMeetsProfession(character, profReq);
  const suggestedCharacter =
    profBad && profReq
      ? allCharacters.find((c) => c.id !== character!.id && characterMeetsProfession(c, profReq))
      : undefined;
  const hasCharacterWarning = classBad || levelBad || profBad;

  function tooltipLineColor(
    line: string
  ): { className?: string; leftClassName?: string; rightClassName?: string } | null {
    if (!character) return null;
    const trimmed = line.trim();
    const levelMatch = /^Requires Level (\d+)$/i.exec(trimmed);
    if (levelMatch && Number(levelMatch[1]) > character.level) return { className: "text-red-500" };
    const lineProfReq = extractProfessionRequirement([trimmed]);
    if (lineProfReq && !characterMeetsProfession(character, lineProfReq)) {
      return { className: "text-red-500" };
    }
    for (const label of KNOWN_SLOT_LABELS) {
      if (trimmed.startsWith(`${label}  `)) {
        const subclass = trimmed.slice(label.length + 2).trim();
        if (!classCanUseSubclass(character.class, subclass)) return { rightClassName: "text-red-500" };
        break;
      }
    }
    return null;
  }

  const characterNote: ReactNode = hasCharacterWarning ? (
    <div className="flex flex-col gap-0.5">
      {classBad && (
        <div className="text-red-500">{character!.name} can&apos;t use this type of item.</div>
      )}
      {levelBad && (
        <div className="text-red-500">
          {character!.name} is too low level (needs {item.required_level}).
        </div>
      )}
      {profBad && profReq && (
        <div className="text-red-500">
          Requires {profReq.profession} ({profReq.skill}) - {character!.name} doesn&apos;t have it.
        </div>
      )}
      {suggestedCharacter && profReq && (
        <div className="text-teal-300">
          → {suggestedCharacter.name} can learn/craft this (
          {profReq.profession}{" "}
          {suggestedCharacter.professions.find(
            (p) => p.profession.toLowerCase() === profReq.profession.toLowerCase()
          )?.skill}
          )
        </div>
      )}
    </div>
  ) : undefined;

  return {
    iconSrc,
    color,
    tooltipLines,
    note,
    slotPart,
    subclassPart,
    armorOrDamage,
    dpsLine,
    statsSummary,
    effectLines,
    levelBad,
    classBad,
    profReq,
    profBad,
    suggestedCharacter,
    characterNote,
    tooltipLineColor,
  };
}

// Follows the cursor rather than anchoring to the row, and is positioned
// `fixed` (viewport-relative) so it's never clipped by the scrollable
// results panel. Hovering an item near the bottom of the page used to
// always place the tooltip below the cursor, which for a long tooltip can
// run off the bottom of the screen entirely (rendering underneath the
// Windows taskbar, unreadable) - this measures itself after it renders and
// flips above the cursor instead when there isn't enough room below, the
// same way the game's own tooltips behave. Also nudged back onto screen
// horizontally for an item hovered near the right edge.
function FollowTooltip({
  x,
  y,
  children,
}: {
  x: number;
  y: number;
  children: React.ReactNode;
}) {
  const ref = useRef<HTMLDivElement | null>(null);
  const [pos, setPos] = useState<{ left: number; top: number; ready: boolean }>({
    left: x + 16,
    top: y + 16,
    ready: false,
  });

  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const rect = el.getBoundingClientRect();
    const margin = 12;

    let top = y + 16;
    if (top + rect.height > window.innerHeight - margin) {
      // Not enough room below the cursor - flip to above it instead.
      top = y - rect.height - 16;
    }
    top = Math.max(margin, top);

    let left = x + 16;
    if (left + rect.width > window.innerWidth - margin) {
      left = window.innerWidth - rect.width - margin;
    }
    left = Math.max(margin, left);

    setPos({ left, top, ready: true });
    // rect.height/rect.width intentionally omitted - they're derived from
    // the same render this effect is measuring, not independent inputs.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [x, y]);

  return (
    <div
      ref={ref}
      className="pointer-events-none fixed z-50"
      style={{ left: pos.left, top: pos.top, visibility: pos.ready ? "visible" : "hidden" }}
    >
      {children}
    </div>
  );
}

// Numbered page controls under the results grid, now that it grows down
// the page instead of scrolling inside its own little box - up to 5 page
// numbers around the current one, plus Prev/Next and jumps to the very
// first/last page once there's enough pages that those aren't already
// among the 5 shown.
function Pagination({
  page,
  totalPages,
  onChange,
}: {
  page: number;
  totalPages: number;
  onChange: (page: number) => void;
}) {
  const windowSize = 5;
  let start = Math.max(1, page - Math.floor(windowSize / 2));
  const end = Math.min(totalPages, start + windowSize - 1);
  start = Math.max(1, end - windowSize + 1);
  const pages = Array.from({ length: end - start + 1 }, (_, i) => start + i);

  const btnClass = (active: boolean) =>
    `tab-btn min-w-[2.25rem] justify-center px-2 py-1 text-xs ${active ? "tab-btn-active" : ""}`;

  return (
    <div className="mt-3 flex flex-wrap items-center justify-center gap-1.5 border-t border-neutral-700/60 pt-3">
      <button type="button" disabled={page <= 1} onClick={() => onChange(page - 1)} className={btnClass(false)}>
        ‹ Prev
      </button>
      {start > 1 && (
        <>
          <button type="button" onClick={() => onChange(1)} className={btnClass(false)}>
            1
          </button>
          {start > 2 && <span className="px-1 text-gray-500">…</span>}
        </>
      )}
      {pages.map((p) => (
        <button key={p} type="button" onClick={() => onChange(p)} className={btnClass(p === page)}>
          {p}
        </button>
      ))}
      {end < totalPages && (
        <>
          {end < totalPages - 1 && <span className="px-1 text-gray-500">…</span>}
          <button type="button" onClick={() => onChange(totalPages)} className={btnClass(false)}>
            {totalPages}
          </button>
        </>
      )}
      <button
        type="button"
        disabled={page >= totalPages}
        onClick={() => onChange(page + 1)}
        className={btnClass(false)}
      >
        Next ›
      </button>
    </div>
  );
}

function Badge({ verified }: { verified: boolean }) {
  return verified ? (
    <span
      title="Confirmed in Forever - seen on a real character"
      className="shrink-0 rounded bg-[#1eff00]/10 px-1 py-[1px] text-[9px] font-semibold uppercase tracking-wide text-[#1eff00]"
    >
      Confirmed
    </span>
  ) : (
    <span
      title="Unconfirmed - based on Blizzard's classic database, which Forever may have changed"
      className="shrink-0 rounded bg-neutral-700/60 px-1 py-[1px] text-[9px] font-semibold uppercase tracking-wide text-gray-400"
    >
      Unconfirmed
    </span>
  );
}

// A reagent icon + colored name/quantity, matching the little icon chips
// the Crafting Directory already shows for a recipe's reagents (see
// CraftingDirectory.tsx's QualityIcon) - shown inside the item tooltip
// itself now, wherever lib/craftedBy.ts found a matching character's recipe
// scan with reagents on file.
function ReagentsRow({ reagents }: { reagents: CraftReagent[] }) {
  return (
    <div className="mt-2 border-t border-neutral-700 pt-1.5">
      <p className="text-xs text-gray-400">Requires:</p>
      <div className="mt-1 flex flex-wrap gap-x-3 gap-y-1">
        {reagents.map((r, i) => {
          const iconSrc =
            typeof r.icon === "number"
              ? iconUrlForFileId(r.icon)
              : typeof r.icon === "string"
                ? wowIconUrl(r.icon)
                : null;
          const color = r.color ? `#${r.color}` : "#ffffff";
          return (
            <span key={i} className="flex items-center gap-1 text-xs">
              <span className="h-4 w-4 shrink-0 overflow-hidden rounded border border-neutral-600 bg-neutral-800">
                {iconSrc && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={iconSrc} alt="" className="h-full w-full object-cover" />
                )}
              </span>
              <span style={{ color }}>
                {r.quantity}x {r.name}
              </span>
            </span>
          );
        })}
      </div>
    </div>
  );
}

function ItemRow({
  item,
  character,
  allCharacters,
  selected,
  onSelect,
}: {
  item: ItemResult;
  character: CharacterSummary | null;
  allCharacters: CharacterSummary[];
  selected: boolean;
  onSelect: (item: ItemResult) => void;
}) {
  const [hoverPos, setHoverPos] = useState<{ x: number; y: number } | null>(null);
  const d = computeItemDisplay(item, character, allCharacters);
  // Always active, not just on hover/select - the card body's own
  // "N characters can craft this" summary is always visible, so it needs
  // the data right away rather than waiting for a hover to kick off the
  // fetch (findCraftedBy's underlying query is a single cached table read
  // shared by every row on the page, not one query per item).
  const craftedBy = useCraftedByOnDemand(item, true);
  const knownByLines =
    craftedBy && craftedBy.crafters.length > 0 ? formatKnownByLines(craftedBy.crafters, item.item_class) : [];
  // The crafted item's OWN row never has reagent info from Blizzard (only
  // the separate recipe/plan item does) - this fills that gap from whoever
  // knows the recipe. Skipped when the item already has its own
  // reagents_text (i.e. this IS the recipe item), so it's never shown twice.
  const derivedReagents = !item.reagents_text ? craftedBy?.reagents ?? null : null;
  const tooltipLinesWithCrafters =
    knownByLines.length > 0 ? [...d.tooltipLines, "", ...knownByLines] : d.tooltipLines;

  const shownEffects = d.effectLines.slice(0, 2);
  const extraEffects = d.effectLines.length - shownEffects.length;

  function handleMove(e: MouseEvent) {
    setHoverPos({ x: e.clientX, y: e.clientY });
  }

  return (
    <div
      className={`group relative flex cursor-pointer gap-3 rounded-md border p-3 transition ${
        selected
          ? "border-amber-500/70 bg-amber-500/10"
          : "border-neutral-700 bg-black/30 hover:border-neutral-500 hover:bg-black/50"
      }`}
      onMouseMove={handleMove}
      onMouseLeave={() => setHoverPos(null)}
      onClick={() => onSelect(item)}
    >
      <div
        className="flex-shrink-0 overflow-hidden rounded border border-neutral-600 bg-neutral-800"
        style={{ width: 52, height: 52 }}
      >
        {d.iconSrc && (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={d.iconSrc} alt="" className="h-full w-full object-cover" />
        )}
      </div>

      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-x-1.5 gap-y-0.5">
          <span className="text-sm font-semibold leading-tight" style={{ color: d.color }}>
            {item.name}
          </span>
          <Badge verified={item.verified} />
        </div>

        <div className="mt-0.5 flex items-baseline justify-between gap-2 text-xs">
          <span className="min-w-0 truncate text-gray-400">
            {d.slotPart}
            {d.subclassPart && (
              <>
                <span className="text-gray-600"> • </span>
                <span className={d.classBad ? "text-red-500" : undefined}>{d.subclassPart}</span>
              </>
            )}
          </span>
          {item.required_level != null && (
            <span className={`shrink-0 ${d.levelBad ? "text-red-500" : "text-gray-400"}`}>
              Req. {item.required_level}
            </span>
          )}
        </div>

        {d.armorOrDamage && <div className="mt-0.5 text-xs text-gray-300">{d.armorOrDamage}</div>}
        {d.dpsLine && <div className="text-xs text-gray-500">{d.dpsLine}</div>}

        {d.statsSummary && (
          <div className="mt-1 text-xs text-gray-200" style={CLAMP_2}>
            {d.statsSummary}
          </div>
        )}
        {item.classes_text && (
          <div className="truncate text-xs text-gray-300">{item.classes_text}</div>
        )}
        {item.item_set_line && (
          <div className="truncate text-xs text-gray-400">{item.item_set_line}</div>
        )}
        {shownEffects.map((line, i) => (
          <div key={i} className="mt-0.5 text-xs text-[#1eff00]" style={CLAMP_2}>
            {line}
          </div>
        ))}
        {extraEffects > 0 && (
          <div className="text-[10px] text-gray-500">
            +{extraEffects} more effect{extraEffects === 1 ? "" : "s"} - hover for full tooltip
          </div>
        )}
        {d.profBad && d.profReq && (
          <div className="mt-0.5 text-xs text-red-500">
            Requires {d.profReq.profession} ({d.profReq.skill})
          </div>
        )}
        {d.suggestedCharacter && (
          <div className="text-xs text-teal-300">→ {d.suggestedCharacter.name} can make this</div>
        )}
        {knownByLines.length > 0 && (
          <div className={`text-xs ${KNOWN_BY_COLOR_CLASS}`}>
            {knownByLines.length === 1
              ? knownByLines[0]
              : `${knownByLines.length} characters ${
                  item.item_class === "Recipe" ? "know this recipe" : "can craft this"
                } - hover for names`}
          </div>
        )}

        {item.sell_price != null && (
          <div className="mt-1.5 flex justify-end text-xs text-gray-400">
            {renderTooltipLine(formatMoneyTokens(item.sell_price))}
          </div>
        )}
      </div>

      {hoverPos && (
        <FollowTooltip x={hoverPos.x} y={hoverPos.y}>
          <ItemTooltipBox
            name={item.name}
            qualityColor={item.quality_color}
            lines={tooltipLinesWithCrafters}
            note={d.note}
            noteClassName={item.verified ? "text-[#1eff00]" : "text-yellow-400"}
            lineColor={d.tooltipLineColor}
            characterNote={d.characterNote}
            beforeNote={derivedReagents ? <ReagentsRow reagents={derivedReagents} /> : undefined}
          />
        </FollowTooltip>
      )}
    </div>
  );
}

// A persistent details panel for whatever item was last clicked (rather than
// only ever showing details on hover) - gives the item browser somewhere to
// eventually grow tracker-specific actions (wishlist, pre-BiS lists, etc.)
// beyond just a Classic-style tooltip.
function ItemInspector({
  item,
  character,
  allCharacters,
  onClose,
}: {
  item: ItemResult;
  character: CharacterSummary | null;
  allCharacters: CharacterSummary[];
  onClose: () => void;
}) {
  const d = computeItemDisplay(item, character, allCharacters);
  const craftedBy = useCraftedByOnDemand(item, true);
  const knownByLines =
    craftedBy && craftedBy.crafters.length > 0 ? formatKnownByLines(craftedBy.crafters, item.item_class) : [];
  const derivedReagents = !item.reagents_text ? craftedBy?.reagents ?? null : null;
  const tooltipLinesWithCrafters =
    knownByLines.length > 0 ? [...d.tooltipLines, "", ...knownByLines] : d.tooltipLines;
  const [wishlistStatus, setWishlistStatus] = useState<string | null>(null);
  const [prebisStatus, setPrebisStatus] = useState<string | null>(null);

  // Reset the "Added!" feedback whenever a different item gets selected, so
  // it doesn't linger and look like it applies to the new item.
  useEffect(() => {
    setWishlistStatus(null);
    setPrebisStatus(null);
  }, [item.id]);

  const disabledReason = !character ? "Select a character above first" : undefined;

  async function handleWishlist() {
    if (!character) return;
    setWishlistStatus("Adding...");
    const result = await addToWishlist(supabase, {
      characterId: character.id,
      itemId: item.id,
      itemName: item.name,
    });
    setWishlistStatus(result.ok ? "Added!" : result.message);
  }

  async function handlePreBis() {
    if (!character) return;
    setPrebisStatus("Adding...");
    const result = await addToPreBis(supabase, {
      characterId: character.id,
      itemId: item.id,
      slot: d.slotPart || null,
    });
    setPrebisStatus(result.ok ? "Added!" : result.message);
  }

  return (
    <div className="relative w-full lg:w-auto">
      <button
        type="button"
        onClick={onClose}
        aria-label="Close item details"
        className="absolute -right-2 -top-2 z-10 flex h-6 w-6 items-center justify-center rounded-full border border-neutral-600 bg-neutral-900 text-xs text-gray-400 hover:text-white"
      >
        ✕
      </button>
      <div className="mb-2 flex justify-center">
        <div
          className="overflow-hidden rounded border border-neutral-600 bg-neutral-800"
          style={{ width: 64, height: 64 }}
        >
          {d.iconSrc && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={d.iconSrc} alt="" className="h-full w-full object-cover" />
          )}
        </div>
      </div>
      <ItemTooltipBox
        name={item.name}
        qualityColor={item.quality_color}
        lines={tooltipLinesWithCrafters}
        note={d.note}
        noteClassName={item.verified ? "text-[#1eff00]" : "text-yellow-400"}
        lineColor={d.tooltipLineColor}
        characterNote={d.characterNote}
        beforeNote={derivedReagents ? <ReagentsRow reagents={derivedReagents} /> : undefined}
        className="mx-auto"
      />
      <div className="mx-auto mt-3 flex max-w-xs flex-col gap-1.5">
        <button
          type="button"
          onClick={handleWishlist}
          disabled={!character}
          title={disabledReason}
          className="rounded bg-red-700 px-3 py-1.5 text-left text-sm disabled:cursor-not-allowed disabled:opacity-50"
        >
          + Add to Wishlist{character ? ` for ${character.name}` : ""}
        </button>
        {wishlistStatus && <p className="text-xs text-gray-400">{wishlistStatus}</p>}
        <button
          type="button"
          onClick={handlePreBis}
          disabled={!character}
          title={disabledReason}
          className="rounded bg-red-700 px-3 py-1.5 text-left text-sm disabled:cursor-not-allowed disabled:opacity-50"
        >
          + Add to Pre-BiS list{character ? ` for ${character.name}` : ""}
        </button>
        {prebisStatus && <p className="text-xs text-gray-400">{prebisStatus}</p>}
        {!character && (
          <p className="text-xs text-gray-500">
            Pick a character in the toolbar above to add items for them.
          </p>
        )}
      </div>
    </div>
  );
}

export default function ItemSearch() {
  const [query, setQuery] = useState("");
  const [quality, setQuality] = useState("");
  const [stat, setStat] = useState("");
  const [category, setCategory] = useState("");
  const [minLevel, setMinLevel] = useState("");
  const [maxLevel, setMaxLevel] = useState("");
  const [sort, setSort] = useState<SortOption>("relevance");
  const [results, setResults] = useState<ItemResult[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(30);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const requestId = useRef(0);
  const resultsTopRef = useRef<HTMLDivElement | null>(null);

  const [characters, setCharacters] = useState<CharacterSummary[]>([]);
  const [selectedCharacterId, setSelectedCharacterId] = useState("");

  // Lets you compare an item against one of your own characters, auction-
  // house style: red text for a level/weapon-skill/profession requirement
  // they don't meet, and a pointer to another of your characters if one of
  // them does. Only your own characters show up here (RLS scopes the
  // `characters` table to its owner, same as everywhere else this table is
  // queried from the browser).
  useEffect(() => {
    let cancelled = false;
    async function loadCharacters() {
      const { data: userData } = await supabase.auth.getUser();
      if (!userData.user) return;
      const { data, error } = await supabase
        .from("characters")
        .select("id, name, class, level, character_professions(profession, skill)")
        .eq("user_id", userData.user.id)
        .order("level", { ascending: false });
      if (cancelled || error || !data) return;
      setCharacters(
        data.map((c: any) => ({
          id: c.id,
          name: c.name,
          class: c.class,
          level: c.level,
          professions: (c.character_professions ?? []).map((p: any) => ({
            profession: p.profession,
            skill: p.skill,
          })),
        }))
      );
    }
    loadCharacters();
    return () => {
      cancelled = true;
    };
  }, []);

  const selectedCharacter = characters.find((c) => c.id === selectedCharacterId) ?? null;

  // Tracks the last filter/sort combination a fetch went out for, so a
  // change to any of them can jump back to page 1 (a new search shouldn't
  // land you on whatever deep page the previous one left off on) without
  // that reset fighting with `page` also being a dependency below.
  const lastFilterKey = useRef("");

  useEffect(() => {
    const trimmedQuery = query.trim();
    const trimmedStat = stat.trim();
    const trimmedMinLevel = minLevel.trim();
    const trimmedMaxLevel = maxLevel.trim();
    // No filters at all is a valid state now - it just means "browse
    // everything" (fetched with no params below). The only time there's
    // nothing worth fetching is a query that's been started but is too
    // short to filter on yet (a single character would match almost every
    // item and just be noise).
    const active = trimmedQuery.length !== 1;

    if (!active) {
      setResults([]);
      setTotal(0);
      setError(null);
      setLoading(false);
      return;
    }

    const filterKey = `${trimmedQuery}|${quality}|${trimmedStat}|${category}|${trimmedMinLevel}|${trimmedMaxLevel}|${sort}`;
    const filtersChanged = filterKey !== lastFilterKey.current;
    lastFilterKey.current = filterKey;
    const effectivePage = filtersChanged ? 1 : page;
    if (filtersChanged && page !== 1) setPage(1);

    setLoading(true);
    const thisRequest = ++requestId.current;
    const handle = setTimeout(async () => {
      try {
        const params = new URLSearchParams();
        if (trimmedQuery.length >= 2) params.set("q", trimmedQuery);
        if (quality) params.set("quality", quality);
        if (trimmedStat.length >= 2) params.set("stat", trimmedStat);
        if (category) params.set("category", category);
        if (trimmedMinLevel && Number.isFinite(Number(trimmedMinLevel))) {
          params.set("minLevel", trimmedMinLevel);
        }
        if (trimmedMaxLevel && Number.isFinite(Number(trimmedMaxLevel))) {
          params.set("maxLevel", trimmedMaxLevel);
        }
        if (sort !== "relevance") params.set("sort", sort);
        params.set("page", String(effectivePage));

        const res = await fetch(`/api/items/search?${params.toString()}`);
        const data = await res.json();
        if (thisRequest !== requestId.current) return;
        if (!res.ok) {
          setError(data.error ?? "Search failed");
          setResults([]);
          setTotal(0);
        } else {
          setError(null);
          setResults(data.items ?? []);
          setTotal(data.total ?? 0);
          setPageSize(data.pageSize ?? 30);
        }
      } catch {
        if (thisRequest === requestId.current) {
          setError("Search failed");
          setResults([]);
          setTotal(0);
        }
      } finally {
        if (thisRequest === requestId.current) setLoading(false);
      }
    }, 250);

    return () => clearTimeout(handle);
  }, [query, quality, stat, category, minLevel, maxLevel, sort, page]);

  // Clicking a card selects it for the details panel; if a new search makes
  // that item disappear from the results, the panel closes rather than
  // silently showing a now-irrelevant item.
  useEffect(() => {
    if (selectedId != null && !results.some((r) => r.id === selectedId)) {
      setSelectedId(null);
    }
  }, [results, selectedId]);

  const totalPages = Math.max(1, Math.ceil(total / pageSize));

  // Jumping to a page (or a new search resetting to page 1) scrolls back up
  // to the top of the results - now that the grid grows down the page
  // instead of scrolling in its own box, "Next" from the bottom of a long
  // page would otherwise leave you staring at wherever the new page's
  // scroll position happened to land. Skips the very first render so
  // landing on the Items page doesn't yank the scroll position around
  // before anyone has searched for anything.
  const didMountRef = useRef(false);
  useEffect(() => {
    if (!didMountRef.current) {
      didMountRef.current = true;
      return;
    }
    resultsTopRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [page]);

  const selectedItem = results.find((r) => r.id === selectedId) ?? null;

  // Mirrors the fetch-gating logic above: everything is "active" (worth
  // showing results for) except a query that's been started but is only
  // one character long.
  const active = query.trim().length !== 1;

  return (
    <div>
      <div
        className="space-y-3 rounded-md border p-3"
        style={{ background: "linear-gradient(180deg, rgba(20,17,12,0.85), rgba(10,9,6,0.85))", borderColor: "#4a4030" }}
      >
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
          <div className="flex items-center gap-1.5">
            <input
              type="number"
              min={0}
              value={minLevel}
              onChange={(e) => setMinLevel(e.target.value)}
              placeholder="Min lvl"
              className="w-[80px] rounded border border-neutral-700 bg-neutral-900 px-2 py-2 text-sm text-white placeholder:text-gray-500"
            />
            <span className="text-gray-500">-</span>
            <input
              type="number"
              min={0}
              value={maxLevel}
              onChange={(e) => setMaxLevel(e.target.value)}
              placeholder="Max lvl"
              className="w-[80px] rounded border border-neutral-700 bg-neutral-900 px-2 py-2 text-sm text-white placeholder:text-gray-500"
            />
          </div>
          {characters.length > 0 && (
            <select
              id="compare-character"
              value={selectedCharacterId}
              onChange={(e) => setSelectedCharacterId(e.target.value)}
              className="rounded border border-neutral-700 bg-neutral-900 px-2 py-2 text-sm text-white"
              title="Compare requirements against, and add items to their Wishlist/Pre-BiS"
            >
              <option value="">Character: None</option>
              {characters.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name} (Lv. {c.level} {c.class})
                </option>
              ))}
            </select>
          )}
        </div>

        <div className="flex flex-wrap gap-2">
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

        {/* Auction-House-style category tabs - "Quest Items" is the one
            exception to the usual Quest-item exclusion (see the API route),
            so picking it deliberately shows what's normally hidden. */}
        <div className="flex flex-wrap gap-1.5">
          {CATEGORY_OPTIONS.map((opt) => (
            <button
              key={opt.value}
              type="button"
              onClick={() => setCategory(opt.value)}
              aria-pressed={category === opt.value}
              className={`tab-btn px-2.5 py-1 text-xs ${category === opt.value ? "tab-btn-active" : ""}`}
            >
              {opt.label}
            </button>
          ))}
        </div>

        {active && !loading && !error && (
          <div className="flex flex-wrap items-center justify-between gap-2 border-t border-neutral-700/60 pt-2 text-xs text-gray-500">
            <span>
              {total} result{total === 1 ? "" : "s"}
              {totalPages > 1 && ` · page ${page} of ${totalPages}`}
            </span>
            <label className="flex items-center gap-1.5">
              Sort:
              <select
                value={sort}
                onChange={(e) => setSort(e.target.value as SortOption)}
                className="rounded border border-neutral-700 bg-neutral-900 px-1.5 py-1 text-xs text-white"
              >
                {SORT_OPTIONS.map((opt) => (
                  <option key={opt.value} value={opt.value}>
                    {opt.label}
                  </option>
                ))}
              </select>
            </label>
          </div>
        )}
      </div>

      {query.trim().length > 0 && query.trim().length < 2 && (
        <p className="mt-3 text-sm text-gray-400">Keep typing - at least 2 characters.</p>
      )}
      {loading && <p className="mt-3 text-sm text-gray-500">Searching...</p>}
      {error && <p className="mt-3 text-sm text-red-400">{error}</p>}

      {active && !loading && !error && results.length > 0 && (
        <>
          <p ref={resultsTopRef} className="mt-3 scroll-mt-4 text-[11px] text-gray-500">
            <span className="text-[#1eff00]">Confirmed</span> items have been seen live on a real
            Forever character. <span className="text-gray-400">Unconfirmed</span> ones are
            Blizzard&apos;s original classic data, which Forever may have changed - click any item
            for details, or hover for the full tooltip.
          </p>
          <div className="mt-1 flex flex-col gap-3 lg:flex-row lg:items-start">
            <div
              className="flex-1 rounded-md p-2"
              style={{
                background: "linear-gradient(180deg, #0c0c14, #000005)",
                border: "1px solid #c8aa6e",
              }}
            >
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 xl:grid-cols-3">
                {results.map((item) => (
                  <ItemRow
                    key={item.id}
                    item={item}
                    character={selectedCharacter}
                    allCharacters={characters}
                    selected={item.id === selectedId}
                    onSelect={(i) => setSelectedId(i.id === selectedId ? null : i.id)}
                  />
                ))}
              </div>

              {totalPages > 1 && (
                <Pagination page={page} totalPages={totalPages} onChange={setPage} />
              )}
            </div>

            {selectedItem && (
              <div className="lg:sticky lg:top-4 lg:w-[320px] lg:flex-shrink-0 lg:self-start">
                <ItemInspector
                  item={selectedItem}
                  character={selectedCharacter}
                  allCharacters={characters}
                  onClose={() => setSelectedId(null)}
                />
              </div>
            )}
          </div>
        </>
      )}

      {active && !loading && !error && results.length === 0 && (
        <p className="mt-3 text-sm text-gray-400">No items found matching those filters.</p>
      )}
    </div>
  );
}
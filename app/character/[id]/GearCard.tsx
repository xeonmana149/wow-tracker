"use client";

import { useEffect, useState, type CSSProperties, type ReactNode } from "react";
import {
  LEFT_SLOTS as LEFT,
  RIGHT_SLOTS as RIGHT,
  BOTTOM_SLOTS as BOTTOM,
  TOTAL_SLOTS,
} from "../../../lib/gear";
import { RACE_FACTION } from "../../../lib/options";
import { classIcon, iconUrl } from "../../../lib/icons";
import { supabase } from "../../../lib/supabase";
import { addToPreBis, addToWishlist } from "../../../lib/itemLists";
import { isCraftedByLine, isEquipLine, isUseLine, renderTooltipLine } from "../../../lib/tooltip";

type Item = {
  slot: string;
  item_name: string | null;
  item_link: string | null;
  // The shared item database's own id for this item, parsed by the addon
  // straight out of the item link (see importLogic.ts) - present on
  // anything synced since item_id was added, null on older rows that
  // haven't been re-synced yet. This is what lets "Add to Wishlist"/"Add to
  // Pre-BiS" work directly off an equipped item, and is the same id the
  // Items page (ItemSearch.tsx) uses, instead of equipped gear carrying its
  // own disconnected copy of an item's identity.
  item_id: number | null;
  item_quality: string | null;
  item_icon: string | null;
  tooltip: string[] | null;
};

// A plain stroke-only glyph per slot, standing in for the game's own
// paperdoll silhouette until something's equipped there - same visual
// language as the icon set already used elsewhere on the site (a bare svg
// wrapper, a handful of line paths), not a photo-real Blizzard texture,
// since we only have access to item icons (via the CDN below), not the
// client's own UI-PaperDoll-Slot-* art.
function SlotGlyph({ children }: { children: ReactNode }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width="60%"
      height="60%"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      className="text-neutral-600"
    >
      {children}
    </svg>
  );
}

const SLOT_ICONS: Record<string, ReactNode> = {
  Head: (
    <SlotGlyph>
      <path d="M5 13a7 7 0 0 1 14 0v3a2 2 0 0 1-2 2h-1v-3H8v3H7a2 2 0 0 1-2-2z" />
      <path d="M5 13h14" />
    </SlotGlyph>
  ),
  Neck: (
    <SlotGlyph>
      <path d="M6 4c0 4 2.5 7 6 7s6-3 6-7" />
      <circle cx="12" cy="15" r="3" />
    </SlotGlyph>
  ),
  Shoulders: (
    <SlotGlyph>
      <path d="M3 12a4 4 0 0 1 8 0v3H3z" />
      <path d="M13 12a4 4 0 0 1 8 0v3h-8z" />
    </SlotGlyph>
  ),
  Back: (
    <SlotGlyph>
      <path d="M12 3l7 3v5c0 5-3 8-7 10-4-2-7-5-7-10V6z" />
    </SlotGlyph>
  ),
  Chest: (
    <SlotGlyph>
      <path d="M8 4l4 2 4-2 3 4-2 2v9a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2v-9l-2-2z" />
    </SlotGlyph>
  ),
  Wrists: (
    <SlotGlyph>
      <rect x="5" y="9" width="14" height="6" rx="2" />
    </SlotGlyph>
  ),
  Hands: (
    <SlotGlyph>
      <path d="M8 12V6a1.5 1.5 0 0 1 3 0v5" />
      <path d="M11 11V5a1.5 1.5 0 0 1 3 0v6" />
      <path d="M14 11.5V6a1.5 1.5 0 0 1 3 0v7" />
      <path d="M8 12l-1.5 1a2 2 0 0 0-.9 2.4L7 19a3 3 0 0 0 3 2h4a3 3 0 0 0 3-2l1-4v-2" />
    </SlotGlyph>
  ),
  Waist: (
    <SlotGlyph>
      <rect x="3" y="10" width="18" height="4" rx="1" />
      <rect x="10" y="9" width="4" height="6" rx="1" />
    </SlotGlyph>
  ),
  Legs: (
    <SlotGlyph>
      <path d="M9 3h6l1 9-1 9h-3l-1-8-1 8H7l1-9z" />
    </SlotGlyph>
  ),
  Feet: (
    <SlotGlyph>
      <path d="M9 3v9l-4 3.5c-1 1-.5 2.5.8 2.5H19a1 1 0 0 0 1-1c0-2-1.5-3-3-3.5l-3-1V3z" />
    </SlotGlyph>
  ),
  "Ring 1": (
    <SlotGlyph>
      <circle cx="12" cy="15" r="5" />
      <path d="M9.5 10 11 5h2l1.5 5" />
    </SlotGlyph>
  ),
  "Ring 2": (
    <SlotGlyph>
      <circle cx="12" cy="15" r="5" />
      <path d="M9.5 10 11 5h2l1.5 5" />
    </SlotGlyph>
  ),
  "Trinket 1": (
    <SlotGlyph>
      <circle cx="12" cy="13" r="6" />
      <path d="M12 3v4" />
    </SlotGlyph>
  ),
  "Trinket 2": (
    <SlotGlyph>
      <circle cx="12" cy="13" r="6" />
      <path d="M12 3v4" />
    </SlotGlyph>
  ),
  "Main Hand": (
    <SlotGlyph>
      <path d="M6.5 17.5 17 7" />
      <path d="M14 4l6 6-3 3-6-6z" />
      <path d="M5 19l1.5-1.5" />
    </SlotGlyph>
  ),
  "Off Hand": (
    <SlotGlyph>
      <path d="M12 3l7 3v5c0 5-3 8-7 10-4-2-7-5-7-10V6z" />
      <path d="M12 3v18" />
    </SlotGlyph>
  ),
  "Ranged / Relic": (
    <SlotGlyph>
      <path d="M6 3c6 3 6 15 0 18" />
      <path d="M6 3v18" />
      <path d="M6 12h12" />
    </SlotGlyph>
  ),
};

// Small "+ Wishlist" / "+ Pre-BiS" action row shown at the bottom of an
// equipped item's tooltip - the exact same character_wishlist/
// character_prebis tables and lib/itemLists.ts helpers the Items page uses,
// so adding an item works identically whichever page you clicked it from.
// Only rendered for the character's own owner (same isOwner gate
// WishlistCard.tsx already uses) and only when this row has a real item_id
// to link (older un-resynced rows don't have one yet).
function GearItemActions({
  itemId,
  itemName,
  slot,
  characterId,
}: {
  itemId: number;
  itemName: string;
  slot: string;
  characterId: string;
}) {
  const [status, setStatus] = useState<{ wishlist?: string; prebis?: string }>({});

  async function handleWishlist() {
    setStatus((s) => ({ ...s, wishlist: "Adding..." }));
    const result = await addToWishlist(supabase, { characterId, itemId, itemName });
    setStatus((s) => ({ ...s, wishlist: result.ok ? "Added!" : result.message }));
  }

  async function handlePreBis() {
    setStatus((s) => ({ ...s, prebis: "Adding..." }));
    const result = await addToPreBis(supabase, { characterId, itemId, slot });
    setStatus((s) => ({ ...s, prebis: result.ok ? "Added!" : result.message }));
  }

  return (
    <div className="mt-2 flex flex-col gap-1 border-t border-neutral-700 pt-1.5 text-xs">
      <div className="flex gap-2">
        <button type="button" onClick={handleWishlist} className="rounded bg-red-700 px-1.5 py-0.5">
          + Wishlist
        </button>
        <button type="button" onClick={handlePreBis} className="rounded bg-red-700 px-1.5 py-0.5">
          + Pre-BiS
        </button>
      </div>
      {status.wishlist && <span className="text-gray-400">Wishlist: {status.wishlist}</span>}
      {status.prebis && <span className="text-gray-400">Pre-BiS: {status.prebis}</span>}
    </div>
  );
}

function ItemTooltip({
  entry,
  isOwner,
  characterId,
  weak,
}: {
  entry: Item;
  isOwner: boolean;
  characterId: string;
  weak?: { requiredLevel: number; characterLevel: number };
}) {
  const color = entry.item_quality ? `#${entry.item_quality}` : "#ffffff";
  const lines = entry.tooltip ?? [];

  return (
    <div
      className="absolute bottom-full left-1/2 z-50 mb-2 w-max max-w-xs -translate-x-1/2 rounded-md p-3 text-left text-sm shadow-lg"
      style={{
        background: "linear-gradient(180deg, #0c0c14, #000005)",
        border: "1px solid #c8aa6e",
      }}
    >
      <div className="font-semibold" style={{ color }}>
        {entry.item_name}
      </div>
      {lines
        .filter((line) => line !== entry.item_name)
        .map((line, i) => (
          <div
            key={i}
            className={
              isCraftedByLine(line) || isEquipLine(line) || isUseLine(line)
                ? "text-[#1eff00]"
                : "text-gray-300"
            }
          >
            {renderTooltipLine(line)}
          </div>
        ))}
      {weak && (
        <div className="mt-2 border-t border-neutral-700 pt-1.5 text-xs text-red-400">
          ⚠ Requires level {weak.requiredLevel} - well behind your character level (
          {weak.characterLevel}). Recommended to upgrade.
        </div>
      )}
      {isOwner && entry.item_id != null && entry.item_name && (
        <GearItemActions
          itemId={entry.item_id}
          itemName={entry.item_name}
          slot={entry.slot}
          characterId={characterId}
        />
      )}
    </div>
  );
}

function EmptySlotTooltip({ slot }: { slot: string }) {
  return (
    <div
      className="pointer-events-none absolute bottom-full left-1/2 z-50 mb-2 w-max -translate-x-1/2 rounded-md px-3 py-1.5 text-sm shadow-lg"
      style={{
        background: "linear-gradient(180deg, #0c0c14, #000005)",
        border: "1px solid #c8aa6e",
      }}
    >
      <span className="text-white">{slot}</span> <span className="text-gray-500">(empty)</span>
    </div>
  );
}

// A single equipment socket. Empty, it shows a dim glyph for that slot type
// (the closest we can get to the game's own paperdoll silhouettes, since we
// only have item icons to draw from, not the client's UI-PaperDoll-Slot-*
// art). Equipped, the item's own icon fills the entire socket edge-to-edge
// - same as the game, where the icon replaces the slot outline rather than
// sitting inside it - with the item-quality color taking over the frame.
function Tile({
  slot,
  entry,
  isOwner,
  characterId,
  weak,
}: {
  slot: string;
  entry: Item | undefined;
  isOwner: boolean;
  characterId: string;
  weak?: { requiredLevel: number; characterLevel: number };
}) {
  const hasItem = !!entry?.item_name;
  const color = entry?.item_quality ? `#${entry.item_quality}` : null;
  const flagged = hasItem && !!weak;

  return (
    <div className="group relative">
      <div
        className="gear-slot flex h-16 w-16 items-center justify-center overflow-hidden sm:h-20 sm:w-20"
        style={hasItem ? ({ "--slot-quality": color ?? "#9d9d9d" } as CSSProperties) : undefined}
        data-filled={hasItem || undefined}
      >
        {hasItem ? (
          entry?.item_icon ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={entry.item_icon}
              alt={entry.item_name ?? ""}
              draggable={false}
              className="h-full w-full object-cover"
              onError={(e) => {
                (e.currentTarget as HTMLImageElement).style.display = "none";
              }}
            />
          ) : (
            <span
              className="line-clamp-3 px-1 text-center text-[10px] font-semibold leading-tight"
              style={{ color: color ?? "white" }}
            >
              {entry.item_name}
            </span>
          )
        ) : (
          SLOT_ICONS[slot] ?? <span className="text-[10px] text-gray-500">{slot}</span>
        )}
      </div>

      {flagged && (
        // Replaces the old red ring + "!" badge (2026-10-02). Slot, icon
        // and its quality-colored border all stay completely normal - this
        // is purely a decorative overlay drawn on top, intentionally much
        // bigger than the slot, NOT sized to make its own transparent
        // window line up with the slot's edges. That pixel-matching
        // approach (several rounds of it) kept shrinking the apparent
        // artwork down to the slot's own tiny size and fighting the slot's
        // quality outline - wrong model entirely. This just centers the
        // whole asset over the slot at a fixed oversized scale: the gold
        // frame reads as surrounding the icon, the arrow badge pokes out
        // above/right, and the banner hangs below into the gap before the
        // next slot (gap-4 below gives it room - some overlap is fine).
        <img
          src="/gear-icons/recommended-upgrade.png"
          alt=""
          aria-label={`${slot} is well behind your level - recommended to upgrade`}
          title="Recommended to upgrade"
          draggable={false}
          className="upgrade-overlay pointer-events-none absolute z-10 max-w-none"
          style={{
            // max-w-none above (and maxWidth here, belt-and-suspenders)
            // override Tailwind Preflight's global `img { max-width: 100% }`
            // reset, which was silently capping this at the tile's own
            // width no matter what we set `width` to - that's what made
            // the banner look like it was pasted onto the icon instead of
            // hanging below it: the whole asset was being squashed back
            // down to tile size (2026-10-02, "the overlay is sitting in
            // the middle of the item icon").
            width: "165%",
            maxWidth: "165%",
            height: "auto",
            left: "50%",
            top: "50%",
            // The resting transform (translate + scale) lives in theme.css's
            // .upgrade-overlay rule, not here, specifically so the hover
            // state in theme.css CAN override it - an inline `transform`
            // here would always beat any stylesheet rule, hover included,
            // no matter how specific (2026-10-02, glow + lift on hover).
          }}
        />
      )}

      <div
        className={`invisible opacity-0 group-hover:visible group-hover:opacity-100 ${
          hasItem ? "" : "pointer-events-none"
        }`}
      >
        {hasItem ? (
          <ItemTooltip entry={entry as Item} isOwner={isOwner} characterId={characterId} weak={weak} />
        ) : (
          <EmptySlotTooltip slot={slot} />
        )}
      </div>
    </div>
  );
}

export default function GearCard({
  items,
  characterName,
  race,
  charClass,
  level,
  characterId,
  ownerId,
  weakSlots,
}: {
  items: Item[];
  characterName: string;
  race: string;
  charClass: string;
  level: number;
  characterId: string;
  ownerId: string;
  // Slots flagged by whatsNext()'s gear-upgrade check (lib/progress.ts) as
  // sitting well below the character's level, from a real scanned
  // requirement - not guessed. Optional so any other caller of this card
  // doesn't need to know about it.
  weakSlots?: Record<string, { requiredLevel: number; characterLevel: number }>;
}) {
  const [isOwner, setIsOwner] = useState(false);
  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setIsOwner(data.user?.id === ownerId));
  }, [ownerId]);
  const bySlot: Record<string, Item> = {};
  for (const i of items) bySlot[i.slot] = i;

  const filled = Object.values(bySlot).filter((i) => i.item_name).length;
  const faction = RACE_FACTION[race];
  const emblem = classIcon(charClass);

  function renderTile(slot: string) {
    return (
      <Tile
        key={slot}
        slot={slot}
        entry={bySlot[slot]}
        isOwner={isOwner}
        characterId={characterId}
        weak={weakSlots?.[slot]}
      />
    );
  }

  return (
    <section className="mt-8 max-w-2xl rounded bg-neutral-800 p-4">
      <h2 className="font-bold">Equipped Gear</h2>

      <div className="mt-4 flex items-stretch justify-center gap-2 sm:gap-3">
        {/* gap-6, up from gap-4 (2026-10-02, "slots are still very tightly
            packed vertically... makes the special frame feel cramped") -
            gives the Recommended Upgrade banner real breathing room below a
            flagged slot instead of almost touching the one beneath it. */}
        <div className="flex flex-col gap-6">{LEFT.map(renderTile)}</div>

        <div className="relative flex min-w-0 max-w-xs flex-1 flex-col items-center justify-center overflow-hidden rounded bg-neutral-900 p-3 text-center">
          {/* Large faded class emblem standing in for a character model -
              purely decorative, sits behind everything else in this panel. */}
          {emblem && (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={iconUrl(emblem)}
              alt=""
              draggable={false}
              className="pointer-events-none absolute left-1/2 top-1/2 h-40 w-40 -translate-x-1/2 -translate-y-1/2 rounded-full object-cover opacity-10 grayscale"
              onError={(e) => {
                (e.currentTarget as HTMLImageElement).style.display = "none";
              }}
            />
          )}

          <div className="relative text-lg font-bold">{characterName}</div>
          <div className="relative mt-1 text-xs text-gray-400">
            Level {level} {race} {charClass}
          </div>
          {faction && (
            <span
              className={`chip relative mt-2 ${
                faction === "Alliance" ? "chip-alliance" : "chip-horde"
              }`}
            >
              {faction}
            </span>
          )}
          <div className="relative mt-6 text-2xl font-bold">
            {filled} / {TOTAL_SLOTS}
          </div>
          <div className="relative text-xs text-gray-400">slots equipped</div>
        </div>

        <div className="flex flex-col gap-6">{RIGHT.map(renderTile)}</div>
      </div>

      {/* gap-6, matching the left/right columns above - a flagged slot in
          this row (rings/trinkets) needs the same breathing room for the
          Recommended Upgrade banner (2026-10-02). */}
      <div className="mt-3 flex justify-center gap-6">{BOTTOM.map(renderTile)}</div>

      <p className="mt-4 text-center text-xs text-gray-500">
        Filled in by importing your addon export. Hover a slot to see the item.
        {weakSlots && Object.keys(weakSlots).length > 0 && (
          <>
            {" "}
            <span className="text-red-400">⚠</span> marks a slot well behind your level.
          </>
        )}
      </p>
    </section>
  );
}
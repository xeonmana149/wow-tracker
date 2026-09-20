"use client";

import {
  LEFT_SLOTS as LEFT,
  RIGHT_SLOTS as RIGHT,
  BOTTOM_SLOTS as BOTTOM,
  TOTAL_SLOTS,
} from "../../../lib/gear";

type Item = {
  slot: string;
  item_name: string | null;
  item_link: string | null;
  item_quality: string | null;
  item_icon: string | null;
  tooltip: string[] | null;
};

function ItemTooltip({ entry }: { entry: Item }) {
  const color = entry.item_quality ? `#${entry.item_quality}` : "#ffffff";
  const lines = entry.tooltip ?? [];

  return (
    <div
      className="pointer-events-none absolute bottom-full left-1/2 z-50 mb-2 w-max max-w-xs -translate-x-1/2 rounded-md p-3 text-left text-sm shadow-lg"
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
          <div key={i} className="text-gray-300">
            {line}
          </div>
        ))}
    </div>
  );
}

function Tile({ slot, entry }: { slot: string; entry: Item | undefined }) {
  const hasItem = !!entry?.item_name;
  const color = entry?.item_quality ? `#${entry.item_quality}` : null;

  return (
    <div className="group relative">
      <div
        style={
          hasItem
            ? {
                borderColor: color ?? "#4ade80",
                backgroundColor: color ? `${color}26` : "#052e16",
              }
            : undefined
        }
        className={`flex h-20 w-16 flex-col items-center justify-center gap-0.5 rounded border-2 px-1 text-center leading-tight sm:w-24 ${
          hasItem ? "" : "border-neutral-700 bg-neutral-900"
        }`}
      >
        {hasItem ? (
          entry?.item_icon && (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={entry.item_icon}
              alt=""
              draggable={false}
              className="h-6 w-6 shrink-0 rounded border border-black/40 object-cover"
              onError={(e) => {
                (e.currentTarget as HTMLImageElement).style.display = "none";
              }}
            />
          )
        ) : (
          <span className="text-[10px] text-gray-400">{slot}</span>
        )}
        {entry?.item_name && (
          <span
            className="line-clamp-2 w-full break-words text-[11px] font-semibold"
            style={{ color: color ?? "white" }}
          >
            {entry.item_name}
          </span>
        )}
      </div>

      {hasItem && (
        <div className="pointer-events-none invisible opacity-0 group-hover:visible group-hover:opacity-100">
          <ItemTooltip entry={entry} />
        </div>
      )}
    </div>
  );
}

export default function GearCard({
  items,
  characterName,
  race,
  charClass,
  level,
}: {
  items: Item[];
  characterName: string;
  race: string;
  charClass: string;
  level: number;
}) {
  const bySlot: Record<string, Item> = {};
  for (const i of items) bySlot[i.slot] = i;

  const filled = Object.values(bySlot).filter((i) => i.item_name).length;

  function renderTile(slot: string) {
    return <Tile key={slot} slot={slot} entry={bySlot[slot]} />;
  }

  return (
    <section className="mt-8 max-w-2xl rounded bg-neutral-800 p-4">
      <h2 className="font-bold">Equipped Gear</h2>

      <div className="mt-4 flex items-stretch justify-center gap-2 sm:gap-3">
        <div className="flex flex-col gap-2">{LEFT.map(renderTile)}</div>

        <div className="flex min-w-0 max-w-xs flex-1 flex-col items-center justify-center rounded bg-neutral-900 p-3 text-center">
          <div className="text-lg font-bold">{characterName}</div>
          <div className="mt-1 text-xs text-gray-400">
            Level {level} {race} {charClass}
          </div>
          <div className="mt-6 text-2xl font-bold">
            {filled} / {TOTAL_SLOTS}
          </div>
          <div className="text-xs text-gray-400">slots equipped</div>
        </div>

        <div className="flex flex-col gap-2">{RIGHT.map(renderTile)}</div>
      </div>

      <div className="mt-3 flex justify-center gap-2 sm:gap-3">{BOTTOM.map(renderTile)}</div>

      <p className="mt-4 text-center text-xs text-gray-500">
        Filled in by importing your addon export. Hover a slot to see the item.
      </p>
    </section>
  );
}
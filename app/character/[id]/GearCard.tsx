"use client";

import { useEffect, useState } from "react";
import { supabase } from "../../../lib/supabase";

import {
  LEFT_SLOTS as LEFT,
  RIGHT_SLOTS as RIGHT,
  BOTTOM_SLOTS as BOTTOM,
  TOTAL_SLOTS,
} from "../../../lib/gear";

type Item = {
  slot: string;
  item_name: string | null;
  source: string | null;
  acquired: boolean;
  not_needed: boolean;
};

type Entry = {
  name: string;
  source: string;
  acquired: boolean;
  notNeeded: boolean;
};

const EMPTY: Entry = { name: "", source: "", acquired: false, notNeeded: false };

function Tile({
  slot,
  entry,
  selected,
  onClick,
}: {
  slot: string;
  entry: Entry | undefined;
  selected: boolean;
  onClick: () => void;
}) {
  const style = entry?.notNeeded
    ? "border-dashed border-neutral-700 bg-neutral-950 opacity-50"
    : entry?.acquired
    ? "border-green-500 bg-green-950"
    : entry
    ? "border-blue-500 bg-blue-950"
    : "border-neutral-700 bg-neutral-900";

  const title = entry?.notNeeded
    ? `${slot} (not needed)`
    : entry
    ? `${entry.name}${entry.source ? ` (${entry.source})` : ""}`
    : slot;

  return (
    <button
      type="button"
      onClick={onClick}
      title={title}
      className={`flex h-16 w-16 flex-col items-center justify-center gap-0.5 rounded border-2 px-1 text-center leading-tight sm:w-24 ${style} ${
        selected ? "ring-2 ring-yellow-400" : ""
      }`}
    >
      <span className="text-[10px] text-gray-400">{slot}</span>
      {entry?.notNeeded && (
        <span className="text-[10px] italic text-gray-500">Not needed</span>
      )}
      {entry && !entry.notNeeded && (
        <span className="line-clamp-2 w-full break-words text-[11px] font-semibold text-white">
          {entry.name}
        </span>
      )}
    </button>
  );
}

export default function GearCard({
  characterId,
  ownerId,
  items,
  characterName,
  race,
  charClass,
  level,
}: {
  characterId: string;
  ownerId: string | null;
  items: Item[];
  characterName: string;
  race: string;
  charClass: string;
  level: number;
}) {
  const [isOwner, setIsOwner] = useState(false);
  const [message, setMessage] = useState("");
  const [selected, setSelected] = useState<string | null>(null);
  const [draft, setDraft] = useState<Entry>(EMPTY);

  // Only slots that have an item (or are marked not needed) are in here
  const [entries, setEntries] = useState<Record<string, Entry>>(() => {
    const start: Record<string, Entry> = {};
    for (const i of items) {
      start[i.slot] = {
        name: i.item_name ?? "",
        source: i.source ?? "",
        acquired: i.acquired,
        notNeeded: i.not_needed,
      };
    }
    return start;
  });

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      setIsOwner(!!ownerId && data.user?.id === ownerId);
    });
  }, [ownerId]);

  function selectSlot(slot: string) {
    if (selected === slot) {
      setSelected(null);
      return;
    }
    setDraft(entries[slot] ?? EMPTY);
    setMessage("");
    setSelected(slot);
  }

  async function handleSave() {
    if (!selected) return;
    const name = draft.name.trim();

    if (!draft.notNeeded && !name) {
      setMessage("Enter an item name, tick Not needed, or use Clear to empty the slot.");
      return;
    }
    setMessage("Saving...");

    const saved: Entry = draft.notNeeded
      ? { name: "", source: "", acquired: false, notNeeded: true }
      : {
          name,
          source: draft.source.trim(),
          acquired: draft.acquired,
          notNeeded: false,
        };

    const { error } = await supabase.from("prebis_items").upsert(
      {
        character_id: characterId,
        slot: selected,
        item_name: saved.notNeeded ? null : saved.name,
        source: saved.source || null,
        acquired: saved.acquired,
        not_needed: saved.notNeeded,
      },
      { onConflict: "character_id,slot" }
    );

    if (error) {
      setMessage(error.message);
    } else {
      setEntries((prev) => ({ ...prev, [selected]: saved }));
      setMessage("");
      setSelected(null);
    }
  }

  async function handleClear() {
    if (!selected) return;

    if (entries[selected]) {
      const { error } = await supabase
        .from("prebis_items")
        .delete()
        .eq("character_id", characterId)
        .eq("slot", selected);

      if (error) {
        setMessage(error.message);
        return;
      }
    }

    setEntries((prev) => {
      const next = { ...prev };
      delete next[selected];
      return next;
    });
    setMessage("");
    setSelected(null);
  }

  const all = Object.values(entries);
  const notNeededCount = all.filter((e) => e.notNeeded).length;
  const planned = all.filter((e) => !e.notNeeded).length;
  const acquiredCount = all.filter((e) => e.acquired && !e.notNeeded).length;
  const needed = TOTAL_SLOTS - notNeededCount;
  const percent = needed > 0 ? Math.round((acquiredCount / needed) * 100) : 0;

  const selectedEntry = selected ? entries[selected] : undefined;

  function renderTile(slot: string) {
    return (
      <Tile
        key={slot}
        slot={slot}
        entry={entries[slot]}
        selected={selected === slot}
        onClick={() => selectSlot(slot)}
      />
    );
  }

  return (
    <section className="mt-8 max-w-2xl rounded bg-neutral-800 p-4">
      <h2 className="font-bold">Pre-BiS Gear</h2>

      <div className="mt-4 flex items-stretch justify-center gap-2 sm:gap-3">
        <div className="flex flex-col gap-2">{LEFT.map(renderTile)}</div>

        <div className="flex min-w-0 max-w-xs flex-1 flex-col items-center justify-center rounded bg-neutral-900 p-3 text-center">
          <div className="text-lg font-bold">{characterName}</div>
          <div className="mt-1 text-xs text-gray-400">
            Level {level} {race} {charClass}
          </div>
          <div className="mt-6 text-4xl font-bold">{percent}%</div>
          <div className="text-xs text-gray-400">
            {acquiredCount} / {needed} acquired
          </div>
          <div className="text-xs text-gray-500">{planned} planned</div>
          {notNeededCount > 0 && (
            <div className="text-xs text-gray-500">{notNeededCount} not needed</div>
          )}
          <div className="mt-3 h-2 w-full rounded bg-neutral-700">
            <div
              className={`h-2 rounded ${percent === 100 ? "bg-yellow-500" : "bg-blue-500"}`}
              style={{ width: `${percent}%` }}
            />
          </div>
        </div>

        <div className="flex flex-col gap-2">{RIGHT.map(renderTile)}</div>
      </div>

      <div className="mt-3 flex justify-center gap-2 sm:gap-3">{BOTTOM.map(renderTile)}</div>

      <div className="mt-4 flex flex-wrap justify-center gap-4 text-xs text-gray-400">
        <span className="flex items-center gap-1.5">
          <span className="h-3 w-3 rounded-sm border-2 border-neutral-700 bg-neutral-900" />
          Empty
        </span>
        <span className="flex items-center gap-1.5">
          <span className="h-3 w-3 rounded-sm border-2 border-blue-500 bg-blue-950" />
          Target
        </span>
        <span className="flex items-center gap-1.5">
          <span className="h-3 w-3 rounded-sm border-2 border-green-500 bg-green-950" />
          Acquired
        </span>
        <span className="flex items-center gap-1.5">
          <span className="h-3 w-3 rounded-sm border-2 border-dashed border-neutral-700 bg-neutral-950 opacity-50" />
          Not needed
        </span>
      </div>

      <div className="mt-4">
        {!selected && (
          <p className="text-center text-sm text-gray-500">
            {isOwner
              ? "Click a slot to set its Pre-BiS item."
              : "Click a slot to see its item."}
          </p>
        )}

        {selected && isOwner && (
          <div className="rounded bg-neutral-900 p-3">
            <h3 className="font-bold">{selected}</h3>
            <div className="mt-3 flex flex-col gap-3">
              <label className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={draft.notNeeded}
                  onChange={(e) => setDraft({ ...draft, notNeeded: e.target.checked })}
                  className="h-5 w-5"
                />
                Not needed (e.g. Off Hand with a two-hander)
              </label>

              <div
                className={`flex flex-col gap-3 ${
                  draft.notNeeded ? "pointer-events-none opacity-40" : ""
                }`}
              >
                <label className="flex flex-col gap-1 text-sm">
                  Item name
                  <input
                    value={draft.name}
                    disabled={draft.notNeeded}
                    onChange={(e) => setDraft({ ...draft, name: e.target.value })}
                    className="rounded bg-white p-2 text-black"
                  />
                </label>
                <label className="flex flex-col gap-1 text-sm">
                  Source (optional), e.g. Scholomance
                  <input
                    value={draft.source}
                    disabled={draft.notNeeded}
                    onChange={(e) => setDraft({ ...draft, source: e.target.value })}
                    className="rounded bg-white p-2 text-black"
                  />
                </label>
                <label className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={draft.acquired}
                    disabled={draft.notNeeded}
                    onChange={(e) => setDraft({ ...draft, acquired: e.target.checked })}
                    className="h-5 w-5"
                  />
                  Got it
                </label>
              </div>

              <div className="flex gap-2">
                <button
                  onClick={handleSave}
                  className="rounded bg-blue-600 px-4 py-2 text-white"
                >
                  Save
                </button>
                <button
                  onClick={handleClear}
                  className="rounded bg-red-700 px-4 py-2 text-white"
                >
                  Clear
                </button>
                <button
                  onClick={() => setSelected(null)}
                  className="rounded bg-neutral-700 px-4 py-2 text-white"
                >
                  Close
                </button>
              </div>
            </div>
          </div>
        )}

        {selected && !isOwner && (
          <div className="rounded bg-neutral-900 p-3">
            <h3 className="font-bold">{selected}</h3>
            {selectedEntry?.notNeeded ? (
              <p className="mt-2 text-sm text-gray-400">Not needed for this build.</p>
            ) : selectedEntry ? (
              <div className="mt-2 text-sm">
                <div>{selectedEntry.name}</div>
                {selectedEntry.source && (
                  <div className="text-gray-400">Source: {selectedEntry.source}</div>
                )}
                <div className={selectedEntry.acquired ? "text-green-400" : "text-gray-400"}>
                  {selectedEntry.acquired ? "✓ Acquired" : "Not acquired yet"}
                </div>
              </div>
            ) : (
              <p className="mt-2 text-sm text-gray-400">No item planned for this slot.</p>
            )}
          </div>
        )}

        {message && <p className="mt-3 text-sm text-red-400">{message}</p>}
      </div>
    </section>
  );
}
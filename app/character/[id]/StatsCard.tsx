"use client";

import { useEffect, useState } from "react";
import { supabase } from "../../../lib/supabase";
import {
  STAT_GROUPS,
  ALL_KEYS,
  START_VALUES,
  SIGNED_KEYS,
  type StatDef,
} from "../../../lib/stats";

type StatRow = { stat: string; value: number };
type Group = { title: string; stats: StatDef[] };

export default function StatsCard({
  characterId,
  ownerId,
  stats,
}: {
  characterId: string;
  ownerId: string | null;
  stats: StatRow[];
}) {
  const [isOwner, setIsOwner] = useState(false);
  const [hasData, setHasData] = useState(stats.length > 0);
  const [values, setValues] = useState<Record<string, number>>(() => {
    const start = { ...START_VALUES };
    for (const r of stats) start[r.stat] = Number(r.value);
    return start;
  });
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState<Record<string, string>>({});
  const [message, setMessage] = useState("");

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      setIsOwner(!!ownerId && data.user?.id === ownerId);
    });
  }, [ownerId]);

  function startEditing() {
    const d: Record<string, string> = {};
    for (const k of ALL_KEYS) d[k] = String(values[k]);
    setDraft(d);
    setMessage("");
    setEditing(true);
  }

  async function handleSave() {
    const next: Record<string, number> = {};
    for (const k of ALL_KEYS) {
      const n = Number(draft[k]);
      next[k] = Number.isFinite(n) && (SIGNED_KEYS.has(k) || n >= 0) ? n : 0;
    }

    if (next.main_hand_max < next.main_hand_min) {
      setMessage("Main Hand max damage can't be lower than the min.");
      return;
    }

    setMessage("Saving...");

    const rows = ALL_KEYS.map((k) => ({
      character_id: characterId,
      stat: k,
      value: next[k],
    }));

    const { error } = await supabase
      .from("character_stats")
      .upsert(rows, { onConflict: "character_id,stat" });

    if (error) {
      setMessage(error.message);
    } else {
      setValues(next);
      setHasData(true);
      setMessage("");
      setEditing(false);
    }
  }

  function show(def: StatDef) {
    if (def.keys.length === 2) {
      return `${values[def.keys[0]]} - ${values[def.keys[1]]}`;
    }
    return `${values[def.keys[0]]}${def.suffix ?? ""}`;
  }

  function renderRow(def: StatDef) {
    return (
      <div
        key={def.label}
        className="flex items-center justify-between gap-3 px-3 py-1.5 text-sm odd:bg-neutral-900/70"
      >
        <span className="text-amber-400">{def.label}:</span>

        {editing ? (
          <span className="flex items-center gap-1">
            {def.keys.map((k, i) => (
              <span key={k} className="flex items-center gap-1">
                {i > 0 && <span className="text-gray-400">-</span>}
                <input
                  type="number"
                  min={SIGNED_KEYS.has(k) ? undefined : 0}
                  step="any"
                  value={draft[k] ?? ""}
                  onChange={(e) => setDraft({ ...draft, [k]: e.target.value })}
                  aria-label={`${def.label}${
                    def.keys.length === 2 ? (i === 0 ? " min" : " max") : ""
                  }`}
                  className={`rounded bg-white p-1 text-right text-black ${
                    def.keys.length === 2 ? "w-16" : "w-24"
                  }`}
                />
              </span>
            ))}
            {def.suffix && <span className="text-gray-400">{def.suffix}</span>}
          </span>
        ) : (
          <span className="text-white">{show(def)}</span>
        )}
      </div>
    );
  }

  function renderGroup(group: Group) {
    return (
      <div key={group.title} className="flex flex-col gap-1">
        <h3
          className="rounded-lg border border-amber-900/70 py-1.5 text-center text-sm font-bold text-amber-50"
          style={{ background: "linear-gradient(180deg, #4a3b22, #241b0f)" }}
        >
          {group.title}
        </h3>
        {group.stats.map(renderRow)}
      </div>
    );
  }

  return (
    <section className="mt-4 max-w-2xl rounded bg-neutral-800 p-4">
      <div className="flex items-center justify-between">
        <h2 className="font-bold">Stats</h2>
        {isOwner && !editing && (
          <button
            onClick={startEditing}
            className="rounded bg-blue-600 px-3 py-1 text-sm text-white"
          >
            Edit stats
          </button>
        )}
      </div>

      {isOwner && !hasData && !editing && (
        <p className="mt-2 text-sm text-gray-400">
          No stats entered yet. Click Edit stats and copy the numbers from your
          in-game character panel.
        </p>
      )}

      <div className="mt-3 grid gap-4 sm:grid-cols-2">
        <div className="flex flex-col gap-4">
          {STAT_GROUPS.slice(0, 3).map(renderGroup)}
        </div>
        <div className="flex flex-col gap-4">
          {STAT_GROUPS.slice(3).map(renderGroup)}
        </div>
      </div>

      {editing && (
        <>
          <p className="mt-3 text-xs text-gray-500">
            For Hit, use the numbers from the tooltip of the weapon skill for the weapon
            you use. They can be negative.
          </p>
          <div className="mt-3 flex gap-2">
            <button
              onClick={handleSave}
              className="rounded bg-blue-600 px-4 py-2 text-white"
            >
              Save stats
            </button>
            <button
              onClick={() => setEditing(false)}
              className="rounded bg-neutral-700 px-4 py-2 text-white"
            >
              Cancel
            </button>
          </div>
        </>
      )}

      {message && <p className="mt-3 text-sm text-red-400">{message}</p>}
    </section>
  );
}
"use client";

import { useEffect, useState } from "react";
import { supabase } from "../lib/supabase";
import { classIcon } from "../lib/icons";
import GameIcon from "./GameIcon";

type ActivityKind =
  | "level_up"
  | "profession_maxed"
  | "character_created"
  | "epic_gear"
  | "gold_milestone"
  | "legacy_point"
  | "pvp_rank_up";

type Event = {
  id: string;
  kind: ActivityKind;
  message: string;
  created_at: string;
  characters: { class: string } | null;
};

const KIND_ICON: Record<ActivityKind, string> = {
  level_up: "⬆",
  profession_maxed: "⭐",
  character_created: "✨",
  epic_gear: "🟣",
  gold_milestone: "💰",
  legacy_point: "🏆",
  pvp_rank_up: "⚔",
};

function timeAgo(iso: string) {
  const diffMs = Date.now() - new Date(iso).getTime();
  const mins = Math.floor(diffMs / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

export default function ActivityFeed() {
  const [events, setEvents] = useState<Event[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    supabase
      .from("activity_events")
      .select("id, kind, message, created_at, characters(class)")
      .order("created_at", { ascending: false })
      .limit(20)
      .then(({ data }) => {
        setEvents((data ?? []) as unknown as Event[]);
        setLoading(false);
      });
  }, []);

  return (
    <section className="mt-6 rounded-lg border border-neutral-700 bg-neutral-900/40 p-4">
      <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
        Activity feed
      </h2>

      {loading && <p className="mt-3 text-sm text-gray-500">Loading...</p>}

      {!loading && events.length === 0 && (
        <p className="mt-3 text-sm text-gray-500">
          Nothing yet - level ups, maxed professions and new characters will show up here as
          everyone syncs.
        </p>
      )}

      {events.length > 0 && (
        <ul className="mt-3 flex flex-col gap-2">
          {events.map((e) => (
            <li
              key={e.id}
              className="flex items-center gap-3 rounded bg-neutral-800 px-3 py-2"
            >
              {e.characters?.class ? (
                <GameIcon
                  name={classIcon(e.characters.class)}
                  label={e.characters.class}
                  size={28}
                  round
                />
              ) : (
                <span className="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-neutral-700 text-sm">
                  {KIND_ICON[e.kind]}
                </span>
              )}
              <span className="min-w-0 flex-1 text-sm text-white">{e.message}</span>
              <span className="shrink-0 text-xs text-gray-500">{timeAgo(e.created_at)}</span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

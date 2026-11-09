"use client";

import { useEffect, useRef, useState } from "react";
import { supabase } from "../lib/supabase";
import { classIcon, iconUrlForFileId } from "../lib/icons";
import GameIcon from "./GameIcon";
import ActivityAchievementIcon from "./ActivityAchievementIcon";
import type { AchievementTier } from "../lib/achievements";

type ActivityKind =
  | "level_up"
  | "account_achievement_earned"
  | "boss_first_kill"
  | "pvp_kill"
  | "pvp_death"
  | "pve_death"
  | "duel"
  | "reputation_milestone"
  | "ah_sale"
  | "ah_purchase"
  | "item_won"
  | "item_looted"
  | "item_crafted"
  | "item_traded"
  | "profession_maxed"
  | "character_created"
  | "epic_gear"
  | "gold_milestone"
  | "legacy_point"
  | "pvp_rank_up"
  | "achievement_earned"
  | "legacy_completed";

type Event = {
  id: string;
  kind: ActivityKind;
  message: string;
  created_at: string;
  // Which specific achievement this row is about, and its tier if tiered -
  // only ever set when kind is "achievement_earned" (2026-09-25, so the
  // feed can show the actual badge art instead of a generic icon). Null on
  // every other kind, and on achievement rows logged before this existed.
  achievement_kind: string | null;
  achievement_tier: AchievementTier | null;
  user_id: string;
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
  achievement_earned: "🏅",
  legacy_completed: "🏆",
  account_achievement_earned: "🏅",
  boss_first_kill: "🐉",
  pvp_kill: "⚔",
  pvp_death: "💀",
  pve_death: "💀",
  duel: "🤺",
  reputation_milestone: "🤝",
  ah_sale: "💰",
  ah_purchase: "💰",
  item_won: "🟣",
  item_looted: "🟣",
  item_crafted: "🔨",
  item_traded: "🤝",
};

const LEGACY_PREFIX = "Completed Legacy Challenge: ";

// Challenge name -> icon file ID, loaded once for every feed on the page.
// Legacy rows only carry the challenge's name in their message, so the
// icon is looked up by that name.
let legacyIconsPromise: Promise<Map<string, number>> | null = null;
function loadLegacyIcons() {
  legacyIconsPromise ??= (async () => {
    const { data } = await supabase.from("legacy_achievement_definitions").select("name, icon");
    return new Map(
      (data ?? [])
        .filter((d): d is { name: string; icon: number } => d.icon != null)
        .map((d) => [d.name, d.icon])
    );
  })();
  return legacyIconsPromise;
}

// How many events the sidebar keeps in view at once. New ones push onto
// the top of the list; anything past this count falls off the bottom,
// so the feed never grows without bound while the page is open.
const FEED_LIMIT = 30;

// Reads activity_log (2026-11-09, "hook all that new activity stuff into
// ... the activities sidebar") - the same table as the Activity page, so
// PvP, duels, dungeon clears, AH and epic items show here too. `label` is
// renamed to `message` in the query so the rest of this file is unchanged.
const SELECT_COLUMNS =
  "id, kind, message:label, created_at, achievement_kind, achievement_tier, user_id, characters(class)";
const HIDDEN_KINDS = "(profile_updated)";

// Accounts that turned off "Show my activity in the global Activity feed"
async function hiddenAccounts(): Promise<Set<string>> {
  const { data } = await supabase.from("profiles").select("id").eq("show_activity", false);
  return new Set((data ?? []).map((p: { id: string }) => p.id));
}

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

// The icon shown per row - an earned achievement gets its actual badge art
// (with the same hover-to-enlarge preview used everywhere else the badge
// system renders), falling back to the class icon or generic kind emoji
// for everything else, same as before.
function EventIcon({ e, legacyIcons }: { e: Event; legacyIcons: Map<string, number> }) {
  if (e.kind === "legacy_completed") {
    const src = iconUrlForFileId(legacyIcons.get(e.message.replace(LEGACY_PREFIX, "")));
    if (src) return <GameIcon src={src} label={e.message} size={28} round />;
  }
  if ((e.kind === "achievement_earned" || e.kind === "account_achievement_earned") && e.achievement_kind) {
    return (
      <ActivityAchievementIcon
        kind={e.achievement_kind}
        tier={e.achievement_tier}
        label={e.message}
        size={28}
      />
    );
  }
  if (e.characters?.class) {
    return <GameIcon name={classIcon(e.characters.class)} label={e.characters.class} size={28} round />;
  }
  return (
    <span className="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-neutral-700 text-sm">
      {KIND_ICON[e.kind] ?? "•"}
    </span>
  );
}

export default function ActivityFeed({
  onNewEvent,
}: {
  // Called for every event that arrives live after the initial load (not
  // for the initial batch itself) - lets a wrapper like ActivitySidebar
  // show a "something happened" badge without duplicating the fetch/
  // subscription logic here.
  onNewEvent?: () => void;
} = {}) {
  const [events, setEvents] = useState<Event[]>([]);
  const [loading, setLoading] = useState(true);
  const [legacyIcons, setLegacyIcons] = useState<Map<string, number>>(new Map());

  useEffect(() => {
    let cancelled = false;
    loadLegacyIcons().then((icons) => {
      if (!cancelled) setLegacyIcons(icons);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  // Kept in a ref (rather than an effect dependency) so the subscription
  // below doesn't need to tear down and reconnect just because the parent
  // re-rendered with a new function identity for onNewEvent.
  const onNewEventRef = useRef(onNewEvent);
  useEffect(() => {
    onNewEventRef.current = onNewEvent;
  }, [onNewEvent]);

  useEffect(() => {
    let cancelled = false;

    let hidden = new Set<string>();
    async function loadInitial() {
      hidden = await hiddenAccounts();
      let query = supabase
        .from("activity_log")
        .select(SELECT_COLUMNS)
        .not("kind", "in", HIDDEN_KINDS)
        .order("created_at", { ascending: false })
        .limit(FEED_LIMIT);
      if (hidden.size > 0) query = query.not("user_id", "in", `(${[...hidden].join(",")})`);
      const { data } = await query;
      if (!cancelled) {
        setEvents((data ?? []) as unknown as Event[]);
        setLoading(false);
      }
    }

    loadInitial();

    // Live updates: whenever anyone's sync or edit inserts a new row,
    // pull that one row (with its joined character class) and slide it
    // onto the top of the list, trimming the oldest one off the end so
    // the feed stays capped at FEED_LIMIT without a page refresh.
    const channel = supabase
      .channel("activity_log_feed")
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "activity_log" },
        async (payload) => {
          const row = payload.new as { id: string; kind: string; user_id: string };
          if (row.kind === "profile_updated" || hidden.has(row.user_id)) return;
          const newId = row.id;
          const { data } = await supabase
            .from("activity_log")
            .select(SELECT_COLUMNS)
            .eq("id", newId)
            .single();
          if (data && !cancelled) {
            // Keep newest-first even when a row arrives with an earlier
            // real time (e.g. a kill from before the sync), and never twice
            setEvents((prev) =>
              [data as unknown as Event, ...prev.filter((p) => p.id !== newId)]
                .sort((a, b) => b.created_at.localeCompare(a.created_at))
                .slice(0, FEED_LIMIT)
            );
            onNewEventRef.current?.();
          }
        }
      )
      .subscribe();

    return () => {
      cancelled = true;
      supabase.removeChannel(channel);
    };
  }, []);

  return (
    <section className="flex h-full flex-col rounded-lg border border-neutral-700 bg-neutral-900/40 p-4">
      <h2 className="shrink-0 text-sm font-semibold uppercase tracking-wide text-gray-400">
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
        <ul className="mt-3 flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto pr-1">
          {events.map((e) => (
            <li
              key={e.id}
              className="flex items-center gap-3 rounded bg-neutral-800 px-3 py-2"
            >
              <EventIcon e={e} legacyIcons={legacyIcons} />
              <span className="min-w-0 flex-1 text-sm text-white">{e.message}</span>
              <span className="shrink-0 text-xs text-gray-500">{timeAgo(e.created_at)}</span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
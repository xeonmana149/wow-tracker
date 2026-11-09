"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { ACTIVITY_TYPES, loadActivityPage, type ActivityFilters, type ActivityRow } from "../../../../lib/activityLog";
import { supabase } from "../../../../lib/supabase";
import { formatDate, formatDateTime } from "../../../../lib/accountView";

// When WoW Forever went live (2026-11-09, "before the character made for
// launch add a WoW Forever Launches! section"). The feed draws a banner at
// this point in the timeline - everything below it is from before launch.
// Every launch character was created on 5 Nov, and the earliest dated
// Legacy Challenge completion is 4 Nov, so this sits at the start of 4 Nov.
const WOW_FOREVER_LAUNCH = "2026-11-04T00:00:00+10:30"; // midnight, Adelaide
const LAUNCH_MS = Date.parse(WOW_FOREVER_LAUNCH);
const beforeLaunch = (iso: string) => Date.parse(iso) < LAUNCH_MS;

function LaunchBanner() {
  return (
    <div className="my-2 rounded border border-amber-500/70 bg-gradient-to-r from-amber-950/60 via-amber-900/30 to-amber-950/60 px-4 py-3 text-center">
      <p className="text-lg font-bold tracking-wide text-amber-300">WoW Forever Launches!</p>
      <p className="text-xs text-amber-200/70">{formatDate(new Date(LAUNCH_MS).toISOString())}</p>
    </div>
  );
}

const EMPTY_FILTERS = { search: "", from: "", to: "", type: "", character: "" };

// Infinite-scroll activity list (2026-10-03, "Just an infinite long
// scrolldown maybe?"; then "I want it to be a global feed, just with the
// option to filter to only your accounts activity") - defaults to
// GLOBAL (every account, every character, site-wide), with a toggle to
// narrow down to just the one account whose Activity page this is
// (`accountUserId`/`accountName` - the page this is embedded in is still
// reached from one specific account's Activity tab, so "only this account"
// is the natural second option rather than a free-text account picker).
//
// Cursor-paginated by created_at (see loadActivityPage's own comment on why
// cursor rather than page number), one page fetched at a time as a sentinel
// div at the bottom of the list scrolls into view. Reads with the plain
// browser `supabase` client, not supabaseAdmin - the activity_log table's
// SELECT policy is "viewable by everyone" (sql/activity-log.sql), same
// visibility as the rest of this account page, so RLS doesn't need
// bypassing here.
export default function ActivityFeed({ accountUserId, accountName }: { accountUserId: string; accountName: string }) {
  const [scope, setScope] = useState<"global" | "account">("global");
  const [rows, setRows] = useState<ActivityRow[]>([]);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const sentinelRef = useRef<HTMLDivElement | null>(null);
  const loadingRef = useRef(false);
  const requestRef = useRef(0);
  const rowsRef = useRef<ActivityRow[]>([]);
  rowsRef.current = rows;

  // Search filters (2026-11-09). `filters` is what the inputs show; the
  // search box waits a moment after typing stops before it reloads, so
  // each keystroke doesn't fire its own query.
  const [filters, setFilters] = useState(EMPTY_FILTERS);
  const [search, setSearch] = useState("");
  const [characterNames, setCharacterNames] = useState<string[]>([]);
  useEffect(() => {
    const t = setTimeout(() => setFilters((f) => (f.search === search ? f : { ...f, search })), 300);
    return () => clearTimeout(t);
  }, [search]);
  useEffect(() => {
    supabase
      .from("characters")
      .select("name")
      .order("name")
      .then(({ data }) => setCharacterNames((data ?? []).map((c: { name: string }) => c.name)));
  }, []);
  const filtersActive = Object.values(filters).some(Boolean);
  // Date inputs give "YYYY-MM-DD" in the viewer's own time zone - "to"
  // covers that whole day
  const queryFilters: ActivityFilters = {
    search: filters.search,
    from: filters.from ? new Date(`${filters.from}T00:00:00`).toISOString() : null,
    to: filters.to ? new Date(`${filters.to}T23:59:59.999`).toISOString() : null,
    type: filters.type,
    character: filters.character,
  };
  const filtersKey = JSON.stringify(queryFilters);

  // Settings page's Notifications tab ("basic version... toggles that
  // control which events the Activity feed highlights", 2026-10-03) - a
  // `activity_log.kind` gets a highlighted style for whoever's CURRENTLY
  // SIGNED IN and has that kind's toggle on, regardless of whose row it is
  // or whose account page this is - it's the viewer's own preference, not
  // the page owner's. Defaults to both on (matching sql/account-settings.sql's
  // column defaults) for a logged-out visitor or anyone who hasn't touched
  // their Settings yet, so this starts as a bit of visual interest rather
  // than silently doing nothing until someone opts in.
  const [highlightKinds, setHighlightKinds] = useState<Set<string>>(
    new Set(["achievement_earned", "account_achievement_earned", "legacy_completed"])
  );

  useEffect(() => {
    async function loadPrefs() {
      const { data: userData } = await supabase.auth.getUser();
      if (!userData.user) return;
      const { data: profileRow } = await supabase
        .from("profiles")
        .select("notify_achievement_earned, notify_account_achievement_earned, notify_legacy_completed")
        .eq("id", userData.user.id)
        .maybeSingle();
      if (!profileRow) return;
      const next = new Set<string>();
      if (profileRow.notify_achievement_earned) next.add("achievement_earned");
      if (profileRow.notify_account_achievement_earned) next.add("account_achievement_earned");
      if (profileRow.notify_legacy_completed) next.add("legacy_completed");
      setHighlightKinds(next);
    }
    loadPrefs();
  }, []);

  const loadPage = useCallback(
    async (before: string | null, replace: boolean) => {
      if (loadingRef.current) return;
      loadingRef.current = true;
      // Bumped whenever the filters reset the list - a reply to an older
      // request is dropped instead of mixing old results into the new list
      const requestId = requestRef.current;
      setLoading(true);
      setError(null);
      try {
        const filterUserId = scope === "account" ? accountUserId : null;
        const { rows: next, hasMore: more } = await loadActivityPage(
          supabase,
          filterUserId,
          before,
          JSON.parse(filtersKey) as ActivityFilters
        );
        if (requestId !== requestRef.current) return;
        setRows((prev) => (replace ? next : [...prev, ...next]));
        setHasMore(more);
      } catch (err) {
        if (requestId !== requestRef.current) return;
        // Supabase errors are plain objects, not Error instances - read
        // their message too, so a failure says what actually went wrong
        const message =
          err instanceof Error
            ? err.message
            : typeof err === "object" && err && "message" in err
              ? String((err as { message: unknown }).message)
              : null;
        setError(message ? `Failed to load activity: ${message}` : "Failed to load activity");
      } finally {
        if (requestId === requestRef.current) {
          loadingRef.current = false;
          setLoading(false);
        }
      }
    },
    [scope, accountUserId, filtersKey]
  );

  // Fetch page 1 fresh whenever the scope toggle or a filter changes
  // (including the very first render) - that can't just keep paginating off
  // the old list, the "before" cursor and the set of rows it's cursoring
  // through are both different queries entirely. A load already in flight
  // is let go rather than waited on, so the newest filters always win.
  useEffect(() => {
    requestRef.current += 1;
    rowsRef.current = [];
    setRows([]);
    setHasMore(true);
    loadingRef.current = false;
    loadPage(null, true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [scope, filtersKey]);

  const loadMore = useCallback(() => {
    if (!hasMore) return;
    const current = rowsRef.current;
    const before = current.length > 0 ? current[current.length - 1].created_at : null;
    loadPage(before, false);
  }, [hasMore, loadPage]);

  useEffect(() => {
    const el = sentinelRef.current;
    if (!el) return;
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0]?.isIntersecting) loadMore();
      },
      { rootMargin: "400px" }
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, [loadMore]);

  return (
    <div className="mt-4 flex flex-col gap-2">
      <div className="flex flex-wrap gap-1.5">
        <button
          type="button"
          onClick={() => setScope("global")}
          className={`tab-btn px-3 py-1.5 text-sm ${scope === "global" ? "tab-btn-active" : ""}`}
        >
          All Activity
        </button>
        <button
          type="button"
          onClick={() => setScope("account")}
          className={`tab-btn px-3 py-1.5 text-sm ${scope === "account" ? "tab-btn-active" : ""}`}
        >
          {accountName} Only
        </button>
      </div>

      {/* Search filters (2026-11-09) */}
      <div className="flex flex-wrap items-end gap-2 rounded border border-neutral-700 bg-neutral-900/80 p-2 text-sm">
        <label className="flex min-w-[12rem] flex-1 flex-col gap-1">
          <span className="text-xs text-gray-400">Search</span>
          <input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="e.g. Gold tier, fish, level 20"
            className="rounded border border-neutral-600 bg-neutral-950 px-2 py-1.5 text-white placeholder:text-gray-600"
          />
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-xs text-gray-400">Type</span>
          <select
            value={filters.type}
            onChange={(e) => setFilters((f) => ({ ...f, type: e.target.value }))}
            className="rounded border border-neutral-600 bg-neutral-950 px-2 py-1.5 text-white"
          >
            <option value="">Everything</option>
            {Object.entries(ACTIVITY_TYPES).map(([key, t]) => (
              <option key={key} value={key}>
                {t.label}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-xs text-gray-400">Character</span>
          <select
            value={filters.character}
            onChange={(e) => setFilters((f) => ({ ...f, character: e.target.value }))}
            className="rounded border border-neutral-600 bg-neutral-950 px-2 py-1.5 text-white"
          >
            <option value="">Anyone</option>
            {characterNames.map((n) => (
              <option key={n} value={n}>
                {n}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-xs text-gray-400">From</span>
          <input
            type="date"
            value={filters.from}
            max={filters.to || undefined}
            onChange={(e) => setFilters((f) => ({ ...f, from: e.target.value }))}
            className="rounded border border-neutral-600 bg-neutral-950 px-2 py-1.5 text-white [color-scheme:dark]"
          />
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-xs text-gray-400">To</span>
          <input
            type="date"
            value={filters.to}
            min={filters.from || undefined}
            onChange={(e) => setFilters((f) => ({ ...f, to: e.target.value }))}
            className="rounded border border-neutral-600 bg-neutral-950 px-2 py-1.5 text-white [color-scheme:dark]"
          />
        </label>
        {(filtersActive || search) && (
          <button
            type="button"
            onClick={() => {
              setSearch("");
              setFilters(EMPTY_FILTERS);
            }}
            className="tab-btn px-3 py-1.5 text-sm"
          >
            Clear
          </button>
        )}
      </div>

      {rows.map((r, i) => (
        <div key={r.id} className="contents">
        {/* The launch banner sits where the timeline crosses launch: just
            before the first row older than it */}
        {beforeLaunch(r.created_at) &&
          i > 0 && !beforeLaunch(rows[i - 1].created_at) && <LaunchBanner />}
        <div
          className={`flex items-center justify-between gap-3 rounded border px-3 py-2 text-sm ${
            highlightKinds.has(r.kind)
              ? "border-amber-600/60 bg-amber-950/20"
              : "border-neutral-700 bg-neutral-900"
          }`}
        >
          <span className="min-w-0 truncate">
            {/* Account name only shown in the global feed - in the
                "this account only" scope every row belongs to the same
                account, so repeating it on every line would just be noise. */}
            {scope === "global" && (
              <Link href={`/account/${r.user_id}`} className="font-semibold text-white hover:underline">
                {r.accountName}
              </Link>
            )}
            {/* Always a separator after the name - account-wide rows (Legacy
                Challenges, account badges) have no character name to sit
                between them, which ran "Aaron" into "Completed..." */}
            {scope === "global" && <span className="text-gray-500"> · </span>}
            {r.character_name && <span className="font-semibold text-amber-200">{r.character_name} </span>}
            <span className="text-white">{r.label}</span>
          </span>
          <span className="shrink-0 text-xs text-gray-500">{formatDateTime(r.created_at)}</span>
        </div>
        </div>
      ))}

      {error && <p className="text-sm text-red-400">{error}</p>}
      {loading && <p className="text-sm text-gray-500">Loading...</p>}
      {/* Reached the oldest row and it's still after launch - the launch
          itself is the start of the timeline, so it goes at the very end
          (unless the date filter ends before launch or starts after it) */}
      {!loading &&
        !hasMore &&
        !error &&
        (rows.length === 0 || !beforeLaunch(rows[rows.length - 1].created_at)) &&
        (!queryFilters.from || Date.parse(queryFilters.from) <= LAUNCH_MS) &&
        (!queryFilters.to || Date.parse(queryFilters.to) >= LAUNCH_MS) &&
        (rows.length > 0 || !filtersActive) && <LaunchBanner />}
      {!loading && !hasMore && rows.length === 0 && !error && filtersActive && (
        <p className="text-sm text-gray-500">Nothing matches these filters.</p>
      )}
      {!loading && !hasMore && rows.length > 0 && <p className="text-center text-xs text-gray-600">That&apos;s everything.</p>}

      <div ref={sentinelRef} className="h-1" />
    </div>
  );
}
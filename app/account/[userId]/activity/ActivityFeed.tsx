"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { loadActivityPage, type ActivityRow } from "../../../../lib/activityLog";
import { supabase } from "../../../../lib/supabase";
import { formatDate } from "../../../../lib/accountView";

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
  const rowsRef = useRef<ActivityRow[]>([]);
  rowsRef.current = rows;

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
    new Set(["achievement_earned", "account_achievement_earned"])
  );

  useEffect(() => {
    async function loadPrefs() {
      const { data: userData } = await supabase.auth.getUser();
      if (!userData.user) return;
      const { data: profileRow } = await supabase
        .from("profiles")
        .select("notify_achievement_earned, notify_account_achievement_earned")
        .eq("id", userData.user.id)
        .maybeSingle();
      if (!profileRow) return;
      const next = new Set<string>();
      if (profileRow.notify_achievement_earned) next.add("achievement_earned");
      if (profileRow.notify_account_achievement_earned) next.add("account_achievement_earned");
      setHighlightKinds(next);
    }
    loadPrefs();
  }, []);

  const loadPage = useCallback(
    async (before: string | null, replace: boolean) => {
      if (loadingRef.current) return;
      loadingRef.current = true;
      setLoading(true);
      setError(null);
      try {
        const filterUserId = scope === "account" ? accountUserId : null;
        const { rows: next, hasMore: more } = await loadActivityPage(supabase, filterUserId, before);
        setRows((prev) => (replace ? next : [...prev, ...next]));
        setHasMore(more);
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to load activity");
      } finally {
        loadingRef.current = false;
        setLoading(false);
      }
    },
    [scope, accountUserId]
  );

  // Fetch page 1 fresh whenever the scope toggle changes (including the
  // very first render) - switching scope can't just keep paginating off the
  // old list, the "before" cursor and the set of rows it's cursoring through
  // are both different queries entirely.
  useEffect(() => {
    rowsRef.current = [];
    setRows([]);
    setHasMore(true);
    loadPage(null, true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [scope]);

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

      {rows.map((r) => (
        <div
          key={r.id}
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
            {scope === "global" && r.character_name && <span className="text-gray-500"> · </span>}
            {r.character_name && <span className="font-semibold text-amber-200">{r.character_name} </span>}
            <span className="text-white">{r.label}</span>
          </span>
          <span className="shrink-0 text-xs text-gray-500">{formatDate(r.created_at)}</span>
        </div>
      ))}

      {error && <p className="text-sm text-red-400">{error}</p>}
      {loading && <p className="text-sm text-gray-500">Loading...</p>}
      {!loading && !hasMore && rows.length === 0 && !error && (
        <p className="text-sm text-gray-500">
          Nothing logged yet - this started tracking today, so new activity will appear here going forward.
        </p>
      )}
      {!loading && !hasMore && rows.length > 0 && <p className="text-center text-xs text-gray-600">That&apos;s everything.</p>}

      <div ref={sentinelRef} className="h-1" />
    </div>
  );
}
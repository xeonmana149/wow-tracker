"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { loadActivityPage, type ActivityRow } from "../../../../lib/activityLog";
import { supabase } from "../../../../lib/supabase";
import { formatDate } from "../../../../lib/accountView";

// Infinite-scroll activity list (2026-10-03, "Just an infinite long
// scrolldown maybe?") - cursor-paginated by created_at (see
// loadActivityPage's own comment on why cursor rather than page number), one
// page fetched at a time as a sentinel div at the bottom of the list scrolls
// into view. Reads with the plain browser `supabase` client, not
// supabaseAdmin - the activity_log table's SELECT policy is "viewable by
// everyone" (sql/activity-log.sql), same visibility as the rest of this
// account page, so RLS doesn't need bypassing here.
export default function ActivityFeed({ userId }: { userId: string }) {
  const [rows, setRows] = useState<ActivityRow[]>([]);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const sentinelRef = useRef<HTMLDivElement | null>(null);
  const loadingRef = useRef(false);
  const rowsRef = useRef<ActivityRow[]>([]);
  rowsRef.current = rows;

  const loadMore = useCallback(async () => {
    if (loadingRef.current || !hasMore) return;
    loadingRef.current = true;
    setLoading(true);
    setError(null);
    try {
      const current = rowsRef.current;
      const before = current.length > 0 ? current[current.length - 1].created_at : null;
      const { rows: next, hasMore: more } = await loadActivityPage(supabase, userId, before);
      setRows((prev) => [...prev, ...next]);
      setHasMore(more);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load activity");
    } finally {
      loadingRef.current = false;
      setLoading(false);
    }
    // `hasMore`/`userId` only - rowsRef sidesteps needing `rows` itself as a
    // dependency, so this callback identity (and the IntersectionObserver
    // effect below that depends on it) doesn't churn on every page loaded.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hasMore, userId]);

  // Initial page, once.
  useEffect(() => {
    loadMore();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

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
      {rows.map((r) => (
        <div
          key={r.id}
          className="flex items-center justify-between gap-3 rounded border border-neutral-700 bg-neutral-900 px-3 py-2 text-sm"
        >
          <span className="min-w-0 truncate">
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

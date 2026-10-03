import type { SupabaseClient } from "@supabase/supabase-js";

// Site-wide Activity Log (2026-10-03, see sql/activity-log.sql) - a single
// shared `activity_log` table, one row per event, scoped by `user_id`. This
// file is the one place both "write an event" and "read a page of events"
// go through, so every call site logs in the same shape rather than each
// one inventing its own label format.

export type ActivityRow = {
  id: string;
  user_id: string;
  character_id: string | null;
  character_name: string | null;
  kind: string;
  label: string;
  created_at: string;
  // Account display name (2026-10-03, "I want it to be a global feed, just
  // with the option to filter to only your accounts activity") - needed so
  // a global, cross-account feed can say WHOSE activity each row is, not
  // just which of their characters did it. Embedded via `profiles(id)` (see
  // sql/activity-log.sql's comment on why `user_id` points there rather than
  // `auth.users(id)`), flattened here rather than left as a nested
  // `profiles: { display_name }` shape so every caller reads
  // `row.accountName` the same way regardless of how Postgrest returns it.
  accountName: string;
};

// Fire-and-forget by design - logging an event should never be able to fail
// the action that triggered it (earning an achievement, saving a profile
// edit). Callers intentionally don't `await` a rejection path back into
// their own error handling; this swallows its own failure and just warns to
// the console instead. `client` is whichever client the call site already
// has - the browser's RLS-scoped client for a user-initiated action (RLS
// only allows inserting your own user_id, see the SQL), or supabaseAdmin for
// something logged from server-side sync processing.
export async function logActivity(
  client: SupabaseClient,
  event: {
    userId: string;
    characterId?: string | null;
    characterName?: string | null;
    kind: string;
    label: string;
  }
): Promise<void> {
  try {
    const { error } = await client.from("activity_log").insert({
      user_id: event.userId,
      character_id: event.characterId ?? null,
      character_name: event.characterName ?? null,
      kind: event.kind,
      label: event.label,
    });
    if (error) console.warn("logActivity failed:", error.message);
  } catch (err) {
    console.warn("logActivity threw:", err);
  }
}

const PAGE_SIZE = 30;

type ActivityRowRaw = {
  id: string;
  user_id: string;
  character_id: string | null;
  character_name: string | null;
  kind: string;
  label: string;
  created_at: string;
  // Postgrest returns a related row as an object (or null if the profile
  // somehow doesn't exist) - never an array, since `user_id` is a plain
  // to-one foreign key here, not a to-many relationship.
  profiles: { display_name: string } | null;
};

// Cursor-paginated by created_at rather than offset/page-number - matches
// "infinite long scrolldown" (ActivityFeed.tsx just keeps asking for
// "everything older than the last row I already have"), and stays correct
// even as new rows keep landing at the top while someone's scrolled partway
// down (an offset-based page would skip/repeat rows as the total count
// shifts under it).
//
// `userId: null` (2026-10-03, "I want it to be a global feed, just with the
// option to filter to only your accounts activity") - the default scope is
// now everyone's activity, site-wide; passing a specific userId narrows it
// back down to one account, same query otherwise. The caller (ActivityFeed's
// scope toggle) decides which this is on any given page load.
export async function loadActivityPage(
  client: SupabaseClient,
  userId: string | null,
  before: string | null
): Promise<{ rows: ActivityRow[]; hasMore: boolean }> {
  let query = client
    .from("activity_log")
    .select("id, user_id, character_id, character_name, kind, label, created_at, profiles(display_name)")
    .order("created_at", { ascending: false })
    .limit(PAGE_SIZE + 1);
  if (userId) query = query.eq("user_id", userId);
  if (before) query = query.lt("created_at", before);

  const { data, error } = await query;
  if (error) throw error;
  const raw = (data ?? []) as unknown as ActivityRowRaw[];
  const rows: ActivityRow[] = raw.map((r) => ({
    id: r.id,
    user_id: r.user_id,
    character_id: r.character_id,
    character_name: r.character_name,
    kind: r.kind,
    label: r.label,
    created_at: r.created_at,
    accountName: r.profiles?.display_name ?? "Unknown",
  }));
  return { rows: rows.slice(0, PAGE_SIZE), hasMore: rows.length > PAGE_SIZE };
}
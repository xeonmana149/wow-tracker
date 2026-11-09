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
    // When it really happened, if not now (e.g. a Legacy Challenge done
    // before the addon was installed)
    createdAt?: string;
  }
): Promise<void> {
  try {
    const { error } = await client.from("activity_log").insert({
      user_id: event.userId,
      character_id: event.characterId ?? null,
      character_name: event.characterName ?? null,
      kind: event.kind,
      label: event.label,
      ...(event.createdAt ? { created_at: event.createdAt } : {}),
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
// Search filters on the Activity page (2026-11-09, "for the future when me
// and friends wanna look back"). Every field is optional; empty means "any".
export type ActivityFilters = {
  // Words anywhere in the event text, e.g. "Gold tier" or "fishing"
  search?: string;
  // Inclusive ISO timestamps - the page turns its date pickers into these
  from?: string | null;
  to?: string | null;
  // One of ACTIVITY_TYPES' keys
  type?: string;
  character?: string;
};

// The event types the filter offers, and which activity_log kinds each one
// covers
export const ACTIVITY_TYPES: Record<string, { label: string; kinds: string[] }> = {
  achievements: { label: "Achievements", kinds: ["achievement_earned", "account_achievement_earned"] },
  levels: { label: "Level ups", kinds: ["level_up"] },
  legacy: { label: "Legacy Challenges", kinds: ["legacy_completed"] },
  dungeons: { label: "First dungeon/raid clears", kinds: ["boss_first_kill"] },
  pvp: { label: "PvP kills & deaths", kinds: ["pvp_kill", "pvp_death"] },
  deaths: { label: "Deaths to monsters", kinds: ["pve_death"] },
  duels: { label: "Duels", kinds: ["duel"] },
  reputation: { label: "Reputation", kinds: ["reputation_milestone"] },
  auctions: { label: "Auction House (50g+ or epic)", kinds: ["ah_sale", "ah_purchase"] },
  items: { label: "Epic & legendary items", kinds: ["item_won", "item_looted", "item_crafted", "item_traded"] },
  characters: { label: "New characters", kinds: ["character_created"] },
};

// Kinds never shown in the feed - profile saves (removed 2026-11-09, "its
// not interesting"); any old rows left in the table stay hidden
const HIDDEN_KINDS = ["profile_updated"];

export async function loadActivityPage(
  client: SupabaseClient,
  userId: string | null,
  before: string | null,
  filters: ActivityFilters = {}
): Promise<{ rows: ActivityRow[]; hasMore: boolean }> {
  // Settings page's "Show my activity in the global Activity feed" toggle
  // (2026-10-03, sql/account-settings.sql's `show_activity`) - only applied
  // to the GLOBAL feed (`userId` null). Looking at one specific account's
  // own activity (the "X Only" scope) still shows everything for that
  // account, since you've explicitly asked for it rather than stumbling
  // onto it in the global stream.
  //
  // 2026-11-09: this used to be one query with a `profiles!inner(...)`
  // embed, but activity_log.user_id has no foreign key to profiles in the
  // live database, so PostgREST refused the join (PGRST200) and the whole
  // feed showed "Failed to load activity". Hidden accounts and display
  // names are now looked up in their own small queries instead, which
  // doesn't depend on that key existing.
  let query = client
    .from("activity_log")
    .select("id, user_id, character_id, character_name, kind, label, created_at")
    .order("created_at", { ascending: false })
    .limit(PAGE_SIZE + 1);
  if (userId) {
    query = query.eq("user_id", userId);
  } else {
    const { data: hidden, error: hiddenError } = await client
      .from("profiles")
      .select("id")
      .eq("show_activity", false);
    if (hiddenError) throw hiddenError;
    const hiddenIds = (hidden ?? []).map((p: { id: string }) => p.id);
    if (hiddenIds.length > 0) query = query.not("user_id", "in", `(${hiddenIds.join(",")})`);
  }
  if (before) query = query.lt("created_at", before);

  query = query.not("kind", "in", `(${HIDDEN_KINDS.join(",")})`);
  // `%` and `_` are wildcards in ilike - strip them so a search is literal
  const search = filters.search?.replace(/[%_]/g, "").trim();
  if (search) query = query.ilike("label", `%${search}%`);
  if (filters.from) query = query.gte("created_at", filters.from);
  if (filters.to) query = query.lte("created_at", filters.to);
  const type = filters.type ? ACTIVITY_TYPES[filters.type] : undefined;
  if (type) query = query.in("kind", type.kinds);
  if (filters.character) query = query.eq("character_name", filters.character);

  const { data, error } = await query;
  if (error) throw error;
  const raw = (data ?? []) as ActivityRowRaw[];

  const userIds = [...new Set(raw.map((r) => r.user_id).filter(Boolean))];
  const names = new Map<string, string>();
  if (userIds.length > 0) {
    const { data: profiles, error: profilesError } = await client
      .from("profiles")
      .select("id, display_name")
      .in("id", userIds);
    if (profilesError) throw profilesError;
    for (const p of (profiles ?? []) as { id: string; display_name: string | null }[]) {
      if (p.display_name) names.set(p.id, p.display_name);
    }
  }

  const rows: ActivityRow[] = raw.map((r) => ({
    id: r.id,
    user_id: r.user_id,
    character_id: r.character_id,
    character_name: r.character_name,
    kind: r.kind,
    label: r.label,
    created_at: r.created_at,
    accountName: names.get(r.user_id) ?? "Unknown",
  }));
  return { rows: rows.slice(0, PAGE_SIZE), hasMore: rows.length > PAGE_SIZE };
}
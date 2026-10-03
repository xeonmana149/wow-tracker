import type { SupabaseClient } from "@supabase/supabase-js";

// Account Management (2026-10-03, Settings tab: "Export tracker data /
// Import data / Reset profile customisation / Delete tracker account").
//
// EXPORT is a full, read-only snapshot of everything this account's RLS
// policies let the signed-in user see about themselves - safe to make as
// complete as possible since downloading your own data can't break anything.
//
// IMPORT is deliberately narrower than "put everything back exactly as it
// was". This repo's mirror doesn't have the full authoritative schema for
// the per-character sync tables (character_stats, character_statistics,
// character_professions, character_talents, equipped_gear, wishlist/Pre-BiS)
// - those are written by the addon/tray sync pipeline (see importLogic.ts),
// which knows the real NOT NULL columns, defaults and constraints for them.
// Blind-upserting a stale export snapshot into those tables risks either a
// failed insert (a required column I don't know about) or silently
// overwriting newer, real data with older numbers the moment someone
// restores a backup. The right way to restore that data is just re-running
// a sync from the addon/tray app.
//
// So Import only restores the things that are genuinely just account
// preferences/progress with no "live sync" source of truth to defer to
// instead:
//   - profile customization + Settings toggles (lib/profileCustomization.ts
//     / sql/account-settings.sql's columns)
//   - each character's hidden / include_in_statistics flags (Settings'
//     Characters section) - only for characters that still exist in the
//     current roster; a character deleted since the export isn't recreated
//   - account-wide and character achievement completion state, and Legacy
//     Challenge completion state - restoring "I'd already earned this"
//     doesn't fight with anything the addon would otherwise sync in
//
// If you want raw stats/gear/talents covered by Import too, I can add that
// once I have the real schema for those tables (exact columns, NOT NULL
// constraints, and any CHECK constraints) from Supabase's dashboard.

export const EXPORT_VERSION = 1;

const CHARACTER_CHILD_TABLES = [
  "character_professions",
  "character_statistics",
  "character_stats",
  "character_talents",
  "character_wishlist",
  "character_prebis",
  "equipped_gear",
  "achievements",
] as const;

export type AccountExport = {
  version: typeof EXPORT_VERSION;
  exportedAt: string;
  userId: string;
  profile: Record<string, unknown> | null;
  characters: Record<string, unknown>[];
  character_professions: Record<string, unknown>[];
  character_statistics: Record<string, unknown>[];
  character_stats: Record<string, unknown>[];
  character_talents: Record<string, unknown>[];
  character_wishlist: Record<string, unknown>[];
  character_prebis: Record<string, unknown>[];
  equipped_gear: Record<string, unknown>[];
  achievements: Record<string, unknown>[];
  account_achievements: Record<string, unknown>[];
  account_legacy_achievements: Record<string, unknown>[];
};

export async function exportAccountData(client: SupabaseClient, userId: string): Promise<AccountExport> {
  const [{ data: profile }, { data: characters }] = await Promise.all([
    client.from("profiles").select("*").eq("id", userId).maybeSingle(),
    client.from("characters").select("*").eq("user_id", userId),
  ]);

  const characterIds = (characters ?? []).map((c) => (c as { id: string }).id);

  const childResults =
    characterIds.length === 0
      ? CHARACTER_CHILD_TABLES.map(() => ({ data: [] as Record<string, unknown>[] }))
      : await Promise.all(
          CHARACTER_CHILD_TABLES.map((table) => client.from(table).select("*").in("character_id", characterIds))
        );

  const [{ data: accountAchievements }, { data: legacyAchievements }] = await Promise.all([
    client.from("account_achievements").select("*").eq("user_id", userId),
    client.from("account_legacy_achievements").select("*").eq("user_id", userId),
  ]);

  const byTable: Record<string, Record<string, unknown>[]> = {};
  CHARACTER_CHILD_TABLES.forEach((table, i) => {
    byTable[table] = (childResults[i].data ?? []) as Record<string, unknown>[];
  });

  return {
    version: EXPORT_VERSION,
    exportedAt: new Date().toISOString(),
    userId,
    profile: (profile ?? null) as Record<string, unknown> | null,
    characters: (characters ?? []) as Record<string, unknown>[],
    character_professions: byTable.character_professions,
    character_statistics: byTable.character_statistics,
    character_stats: byTable.character_stats,
    character_talents: byTable.character_talents,
    character_wishlist: byTable.character_wishlist,
    character_prebis: byTable.character_prebis,
    equipped_gear: byTable.equipped_gear,
    achievements: byTable.achievements,
    account_achievements: (accountAchievements ?? []) as Record<string, unknown>[],
    account_legacy_achievements: (legacyAchievements ?? []) as Record<string, unknown>[],
  };
}

export type RestoreResult = { ok: boolean; message: string };

const PROFILE_RESTORE_FIELDS = [
  "display_name",
  "avatar_icon",
  "banner_style",
  "motto",
  "favorite_character_id",
  "favorite_statistic_character_id",
  "favorite_statistic_category",
  "favorite_statistic_name",
  "favorite_achievement_type",
  "favorite_achievement_character_id",
  "favorite_achievement_kind",
  "favorite_item_character_id",
  "favorite_item_slot",
  "default_character_id",
  "profile_visibility",
  "show_playtime",
  "show_activity",
  "notify_achievement_earned",
  "notify_account_achievement_earned",
  "notify_legacy_completed",
] as const;

// Best-effort, field-by-field restore (2026-10-03) - only touches fields in
// PROFILE_RESTORE_FIELDS that actually exist in the uploaded file, so an
// older export (from before, say, notify_legacy_completed existed) doesn't
// wipe a setting it simply never knew about back to undefined/null.
export async function restoreFromExport(
  client: SupabaseClient,
  userId: string,
  data: unknown
): Promise<RestoreResult> {
  if (!data || typeof data !== "object") {
    return { ok: false, message: "That doesn't look like a WoW Forever Tracker export file." };
  }
  const parsed = data as Partial<AccountExport>;
  if (parsed.version !== EXPORT_VERSION) {
    return { ok: false, message: "This export file is from an incompatible version of the export format." };
  }
  if (!parsed.userId || parsed.userId !== userId) {
    return { ok: false, message: "This export file belongs to a different account, so it can't be restored here." };
  }

  try {
    // Profile customization + settings.
    if (parsed.profile && typeof parsed.profile === "object") {
      const patch: Record<string, unknown> = {};
      for (const field of PROFILE_RESTORE_FIELDS) {
        if (field in parsed.profile) patch[field] = (parsed.profile as Record<string, unknown>)[field];
      }
      if (Object.keys(patch).length > 0) {
        const { error } = await client.from("profiles").update(patch).eq("id", userId);
        if (error) throw new Error(`profile: ${error.message}`);
      }
    }

    // Per-character hidden/include_in_statistics flags - only for
    // characters still in the current roster.
    const { data: currentChars } = await client.from("characters").select("id").eq("user_id", userId);
    const currentIds = new Set(((currentChars ?? []) as { id: string }[]).map((c) => c.id));
    for (const c of parsed.characters ?? []) {
      const row = c as { id?: string; hidden?: boolean; include_in_statistics?: boolean };
      if (!row.id || !currentIds.has(row.id)) continue;
      const patch: Record<string, unknown> = {};
      if ("hidden" in row) patch.hidden = row.hidden;
      if ("include_in_statistics" in row) patch.include_in_statistics = row.include_in_statistics;
      if (Object.keys(patch).length === 0) continue;
      const { error } = await client.from("characters").update(patch).eq("id", row.id);
      if (error) throw new Error(`character ${row.id}: ${error.message}`);
    }

    // Character achievement completion state - same "only characters that
    // still exist" rule.
    const restorableAchievements = (parsed.achievements ?? []).filter((a) =>
      currentIds.has((a as { character_id?: string }).character_id ?? "")
    );
    if (restorableAchievements.length > 0) {
      const { error } = await client
        .from("achievements")
        .upsert(restorableAchievements, { onConflict: "character_id,kind" });
      if (error) throw new Error(`achievements: ${error.message}`);
    }

    // Account-wide achievements.
    if (parsed.account_achievements && parsed.account_achievements.length > 0) {
      const { error } = await client
        .from("account_achievements")
        .upsert(parsed.account_achievements, { onConflict: "user_id,kind" });
      if (error) throw new Error(`account achievements: ${error.message}`);
    }

    // Legacy Challenge completion state.
    if (parsed.account_legacy_achievements && parsed.account_legacy_achievements.length > 0) {
      const { error } = await client
        .from("account_legacy_achievements")
        .upsert(parsed.account_legacy_achievements, { onConflict: "user_id,achievement_id" });
      if (error) throw new Error(`legacy achievements: ${error.message}`);
    }

    return {
      ok: true,
      message:
        "Restored your profile, settings, hidden-character flags and achievement progress. " +
        "Gear, stats, professions, talents and wishlist weren't touched - re-sync the addon/tray app to refresh those.",
    };
  } catch (err) {
    return { ok: false, message: err instanceof Error ? err.message : "Restore failed." };
  }
}

// Matches the Edit Profile form's own defaults (app/account/page.tsx) -
// avatar_icon null falls back to the default icon, banner_style defaults to
// "parchment", same as a brand-new profile that's never been customized.
const DEFAULT_PROFILE_CUSTOMIZATION = {
  display_name: null,
  avatar_icon: null,
  banner_style: "parchment",
  motto: null,
  favorite_character_id: null,
  favorite_statistic_character_id: null,
  favorite_statistic_category: null,
  favorite_statistic_name: null,
  favorite_achievement_type: null,
  favorite_achievement_character_id: null,
  favorite_achievement_kind: null,
  favorite_item_character_id: null,
  favorite_item_slot: null,
};

export async function resetProfileCustomization(client: SupabaseClient, userId: string): Promise<RestoreResult> {
  const { error } = await client.from("profiles").update(DEFAULT_PROFILE_CUSTOMIZATION).eq("id", userId);
  if (error) return { ok: false, message: error.message };
  return { ok: true, message: "Profile customization reset." };
}

const DEFAULT_PROFILE_FULL_RESET = {
  ...DEFAULT_PROFILE_CUSTOMIZATION,
  default_character_id: null,
  profile_visibility: "public",
  show_playtime: true,
  show_activity: true,
  notify_achievement_earned: true,
  notify_account_achievement_earned: true,
  notify_legacy_completed: true,
};

// Delete tracker account (2026-10-03, "delete all tracker data, keep their
// login") - wipes every row this account owns and resets the profile back to
// a blank slate, but never touches the auth.users login itself, so they can
// sign back in and sync fresh at any time. Runs as the signed-in user's own
// RLS-scoped client, same trust model as the rest of this Settings page -
// relies on each table already having (or needing) a DELETE policy scoped to
// the owner, same as the UPDATE policies this page already depends on. If a
// table is missing that policy, its delete will fail and surface an error
// here rather than silently leaving orphaned data - worth checking Supabase's
// dashboard if that happens.
export async function deleteAccountData(client: SupabaseClient, userId: string): Promise<RestoreResult> {
  try {
    const { data: characters, error: charError } = await client
      .from("characters")
      .select("id")
      .eq("user_id", userId);
    if (charError) throw new Error(charError.message);
    const characterIds = ((characters ?? []) as { id: string }[]).map((c) => c.id);

    if (characterIds.length > 0) {
      for (const table of CHARACTER_CHILD_TABLES) {
        const { error } = await client.from(table).delete().in("character_id", characterIds);
        if (error) throw new Error(`${table}: ${error.message}`);
      }
      const { error: deleteCharsError } = await client.from("characters").delete().in("id", characterIds);
      if (deleteCharsError) throw new Error(`characters: ${deleteCharsError.message}`);
    }

    const { error: accountAchError } = await client.from("account_achievements").delete().eq("user_id", userId);
    if (accountAchError) throw new Error(`account_achievements: ${accountAchError.message}`);

    const { error: legacyError } = await client.from("account_legacy_achievements").delete().eq("user_id", userId);
    if (legacyError) throw new Error(`account_legacy_achievements: ${legacyError.message}`);

    // Best-effort - activity history isn't critical to the delete actually
    // succeeding, and some installs may not have both tables.
    await client.from("activity_log").delete().eq("user_id", userId);
    await client.from("activity_events").delete().eq("user_id", userId);

    const { error: profileError } = await client.from("profiles").update(DEFAULT_PROFILE_FULL_RESET).eq("id", userId);
    if (profileError) throw new Error(`profile: ${profileError.message}`);

    return {
      ok: true,
      message: "Your tracker data has been deleted. Your login still works - sync again anytime to start fresh.",
    };
  } catch (err) {
    return { ok: false, message: err instanceof Error ? err.message : "Delete failed." };
  }
}

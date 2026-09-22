import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "../../../lib/supabaseAdmin";
import { applyImport, type ParsedExport } from "../../../lib/importLogic";

// Plain "1.5.0" style dotted version strings, compared numerically part by
// part (not string comparison, so "1.10.0" correctly beats "1.9.0"). Missing
// parts count as 0. Anything unparseable, or no stored version yet, counts
// as "newer" so the very first sync always gets recorded.
function isVersionNewer(next: string, current: string | null): boolean {
  if (!current) return true;
  const a = next.split(".").map((n) => parseInt(n, 10) || 0);
  const b = current.split(".").map((n) => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const diff = (a[i] ?? 0) - (b[i] ?? 0);
    if (diff !== 0) return diff > 0;
  }
  return false;
}

export async function POST(req: NextRequest) {
  let body: { token?: string; data?: ParsedExport; trayVersion?: string };
  try {
    body = await req.json();
  } catch (e) {
    return NextResponse.json({ error: "Invalid JSON" }, { status: 400 });
  }

  const token = body.token;
  const parsed = body.data;
  if (!token || !parsed) {
    return NextResponse.json({ error: "Missing token or data" }, { status: 400 });
  }

  let characterId: string | null = null;

  // 1. Old-style per-character token - still honored for anyone set up
  //    before account-level tokens existed.
  const { data: charTokenRow } = await supabaseAdmin
    .from("character_sync_tokens")
    .select("character_id")
    .eq("token", token)
    .maybeSingle();

  if (charTokenRow) {
    characterId = charTokenRow.character_id;
  } else {
    // 2. Account-level token - find the owner, then find (or create) the
    //    character this export is for.
    const { data: userTokenRow } = await supabaseAdmin
      .from("user_sync_tokens")
      .select("user_id")
      .eq("token", token)
      .maybeSingle();

    if (!userTokenRow) {
      return NextResponse.json({ error: "Unknown sync token" }, { status: 401 });
    }
    const userId = userTokenRow.user_id;

    const name = parsed.basic?.name;
    if (!name) {
      return NextResponse.json(
        { error: "Export is missing a character name - update the addon and try again." },
        { status: 400 }
      );
    }
    const realm = parsed.basic?.realm ?? null;

    // Try an exact name+realm match first (the normal case once a
    // character has synced at least once before).
    const { data: exactMatch } = await supabaseAdmin
      .from("characters")
      .select("id, realm")
      .eq("user_id", userId)
      .ilike("name", name)
      .eq("realm", realm)
      .maybeSingle();

    if (exactMatch) {
      characterId = exactMatch.id;
    } else {
      // Fall back to a name-only match against a character that has no
      // realm saved yet - this is what an existing, manually-created
      // character looks like before its first auto-sync. Treat it as the
      // same character and fill in its realm, instead of creating a
      // duplicate.
      const { data: legacyMatch } = await supabaseAdmin
        .from("characters")
        .select("id, realm")
        .eq("user_id", userId)
        .ilike("name", name)
        .is("realm", null)
        .maybeSingle();

      if (legacyMatch) {
        characterId = legacyMatch.id;
        if (realm) {
          await supabaseAdmin.from("characters").update({ realm }).eq("id", legacyMatch.id);
        }
      } else {
        const { data: created, error: createError } = await supabaseAdmin
          .from("characters")
          .insert({
            user_id: userId,
            name,
            race: parsed.basic?.race || "Unknown",
            class: parsed.basic?.class || "Unknown",
            faction: parsed.basic?.faction ?? null,
            realm,
            // The database requires every character to have a non-empty
            // main_spec, and a ruleset from a fixed set of values
            // (PVP/PVE/RPPVE/HARDCORE) - the addon doesn't know either at
            // creation time (see earlier discussion on ruleset not being
            // addon-detectable yet), so these are placeholders. Edit them
            // on the site afterward if they're wrong for this character.
            main_spec: "Unspecified",
            ruleset: "PVE",
            // Explicitly "Unspecified" rather than leaving this out of the
            // insert - the column's own default is "Main", which would
            // silently mark every auto-created character as a main even
            // though the addon has no way to actually know that.
            character_type: "Unspecified",
            level: typeof parsed.basic?.level === "number" ? parsed.basic.level : 1,
            guild: parsed.basic?.guild ?? null,
            // Flags this character on the website so the owner gets a
            // "Needs attention" banner prompting them to fill in the real
            // main spec and ruleset (the addon can't know either yet).
            needs_setup: true,
          })
          .select("id")
          .single();

        if (createError || !created) {
          return NextResponse.json(
            { error: "Could not create character: " + (createError?.message ?? "unknown error") },
            { status: 500 }
          );
        }
        characterId = created.id;

        // Best-effort activity feed entry - never blocks the sync itself.
        try {
          await supabaseAdmin.from("activity_events").insert({
            character_id: characterId,
            user_id: userId,
            kind: "character_created",
            message: `${name} joined the roster`,
          });
        } catch {
          // ignored on purpose
        }
      }
    }
  }

  if (!characterId) {
    return NextResponse.json({ error: "Could not resolve a character for this token" }, { status: 500 });
  }

  const { data: character, error: charError } = await supabaseAdmin
    .from("characters")
    .select("id, active_spec, user_id")
    .eq("id", characterId)
    .single();

  if (charError || !character) {
    return NextResponse.json({ error: "Character not found" }, { status: 404 });
  }

  // Best-effort: record whatever addon/tray version this sync reports on
  // the account's profile, so the website itself can show an "update
  // available" banner instead of the desktop app nagging about it. Never
  // blocks the actual sync if this fails for any reason.
  //
  // Only ever moves the stored version FORWARD. Every character syncs
  // independently, each from its own SavedVariables file - if you've
  // logged into one character with the new addon but haven't touched an
  // alt since, that alt's export still carries the old version number.
  // The tray app re-syncs every enabled character on its own schedule
  // (e.g. after your PC wakes from sleep), so without this check that
  // alt's next sync would silently overwrite the account back to the old
  // version and the "update available" banner would reappear even though
  // you're actually up to date on the character you're playing.
  try {
    const addonVersion = (parsed as { meta?: { addonVersion?: string } }).meta?.addonVersion;
    const trayVersion = typeof body.trayVersion === "string" ? body.trayVersion : undefined;

    if (addonVersion || trayVersion) {
      const { data: currentProfile } = await supabaseAdmin
        .from("profiles")
        .select("addon_version, tray_version")
        .eq("id", character.user_id)
        .single();

      const versionUpdate: Record<string, string> = {};
      if (
        typeof addonVersion === "string" &&
        addonVersion &&
        isVersionNewer(addonVersion, currentProfile?.addon_version ?? null)
      ) {
        versionUpdate.addon_version = addonVersion;
      }
      if (trayVersion && isVersionNewer(trayVersion, currentProfile?.tray_version ?? null)) {
        versionUpdate.tray_version = trayVersion;
      }
      if (Object.keys(versionUpdate).length > 0) {
        await supabaseAdmin.from("profiles").update(versionUpdate).eq("id", character.user_id);
      }
    }
  } catch {
    // ignored on purpose
  }

  const { data: professions } = await supabaseAdmin
    .from("character_professions")
    .select("id, profession, skill")
    .eq("character_id", characterId);

  try {
    const result = await applyImport(
      supabaseAdmin,
      characterId,
      character.active_spec ?? 1,
      professions ?? [],
      parsed
    );
    return NextResponse.json({ ok: true, characterId, ...result });
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : "Import failed" },
      { status: 500 }
    );
  }
}
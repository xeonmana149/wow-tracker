import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "../../../lib/supabaseAdmin";
import { applyImport, type ParsedExport } from "../../../lib/importLogic";

export async function POST(req: NextRequest) {
  let body: { token?: string; data?: ParsedExport };
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
            level: typeof parsed.basic?.level === "number" ? parsed.basic.level : 1,
            guild: parsed.basic?.guild ?? null,
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
      }
    }
  }

  if (!characterId) {
    return NextResponse.json({ error: "Could not resolve a character for this token" }, { status: 500 });
  }

  const { data: character, error: charError } = await supabaseAdmin
    .from("characters")
    .select("id, active_spec")
    .eq("id", characterId)
    .single();

  if (charError || !character) {
    return NextResponse.json({ error: "Character not found" }, { status: 404 });
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
import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "../../lib/supabaseAdmin";

// Mirrors the character-lookup logic in /api/sync/route.ts, so a token that
// can create/update a character through that endpoint can also remove it
// through this one, using the same rules for which character it means.
export async function POST(req: NextRequest) {
  let body: { token?: string; name?: string; realm?: string | null };
  try {
    body = await req.json();
  } catch (e) {
    return NextResponse.json({ error: "Invalid JSON" }, { status: 400 });
  }

  const token = body.token;
  if (!token) {
    return NextResponse.json({ error: "Missing token" }, { status: 400 });
  }

  let characterId: string | null = null;

  // 1. Old-style per-character token - the token IS the character, so no
  //    name is needed to know which one this request means.
  const { data: charTokenRow } = await supabaseAdmin
    .from("character_sync_tokens")
    .select("character_id")
    .eq("token", token)
    .maybeSingle();

  if (charTokenRow) {
    characterId = charTokenRow.character_id;
  } else {
    // 2. Account-level token - the name (and realm, if known) says which of
    //    this account's characters to remove.
    const { data: userTokenRow } = await supabaseAdmin
      .from("user_sync_tokens")
      .select("user_id")
      .eq("token", token)
      .maybeSingle();

    if (!userTokenRow) {
      return NextResponse.json({ error: "Unknown sync token" }, { status: 401 });
    }
    const userId = userTokenRow.user_id;

    const name = body.name;
    if (!name) {
      return NextResponse.json({ error: "Missing character name" }, { status: 400 });
    }
    const realm = body.realm ?? null;

    // Same two-step match /api/sync uses: exact name+realm first, then a
    // name-only match against a realm-less row (a character created on the
    // site by hand, before it ever synced).
    const { data: exactMatch } = await supabaseAdmin
      .from("characters")
      .select("id")
      .eq("user_id", userId)
      .ilike("name", name)
      .eq("realm", realm)
      .maybeSingle();

    if (exactMatch) {
      characterId = exactMatch.id;
    } else {
      const { data: legacyMatch } = await supabaseAdmin
        .from("characters")
        .select("id")
        .eq("user_id", userId)
        .ilike("name", name)
        .is("realm", null)
        .maybeSingle();
      if (legacyMatch) characterId = legacyMatch.id;
    }
  }

  if (!characterId) {
    return NextResponse.json(
      { error: "Could not find that character on this account" },
      { status: 404 }
    );
  }

  // Clean up its own sync token first (if it has one), so nothing is left
  // pointing at a character that's about to stop existing.
  await supabaseAdmin.from("character_sync_tokens").delete().eq("character_id", characterId);

  // Deletes everything hanging off this character too (professions,
  // talents, legacy, gear, wishlist, per-character achievements) via the
  // same foreign-key CASCADE the earlier full reset relied on.
  const { error: deleteError } = await supabaseAdmin
    .from("characters")
    .delete()
    .eq("id", characterId);

  if (deleteError) {
    return NextResponse.json({ error: deleteError.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
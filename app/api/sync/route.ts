import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "../../../lib/supabaseAdmin";
import { applyImport, type ParsedExport } from "../../../lib/importLogic";

export async function POST(req: NextRequest) {
  let body: { token?: string; data?: ParsedExport };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  if (!body.token || typeof body.token !== "string" || !body.data) {
    return NextResponse.json({ error: "Missing token or data" }, { status: 400 });
  }

  const { data: tokenRow, error: tokenError } = await supabaseAdmin
    .from("character_sync_tokens")
    .select("character_id")
    .eq("token", body.token)
    .single();

  if (tokenError || !tokenRow) {
    return NextResponse.json({ error: "Invalid sync token" }, { status: 401 });
  }

  const { data: character, error: charError } = await supabaseAdmin
    .from("characters")
    .select("id, active_spec")
    .eq("id", tokenRow.character_id)
    .single();

  if (charError || !character) {
    return NextResponse.json({ error: "Character not found" }, { status: 404 });
  }

  const { data: professions } = await supabaseAdmin
    .from("character_professions")
    .select("id, profession, skill")
    .eq("character_id", character.id);

  try {
    const result = await applyImport(
      supabaseAdmin,
      character.id,
      character.active_spec ?? 1,
      professions ?? [],
      body.data
    );
    return NextResponse.json({ ok: true, ...result });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Import failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
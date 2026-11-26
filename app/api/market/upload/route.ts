import { NextRequest, NextResponse } from "next/server";
import { mergeUpload } from "../../../../lib/marketUser";
import { supabaseAdmin } from "../../../../lib/supabaseAdmin";
import { saveUserNodes } from "../../../../lib/sharedNodes";

// The tray app sends the Forever Gold addon's webExport table here (your
// auctions, each character's gold, saved farming trips), signed with the
// same sync token it uses for /api/sync. Stored privately per account; only
// that account's own "My auctions & gold" page reads it back.
//
// POST { token, data, trayVersion? }
export async function POST(req: NextRequest) {
  let body: { token?: string; data?: unknown };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON" }, { status: 400 });
  }
  const token = typeof body.token === "string" ? body.token : "";
  if (!token || !body.data || typeof body.data !== "object") {
    return NextResponse.json({ error: "Missing token or data" }, { status: 400 });
  }

  let userId: string | null = null;
  const { data: userRow } = await supabaseAdmin.from("user_sync_tokens").select("user_id").eq("token", token).maybeSingle();
  if (userRow?.user_id) {
    userId = userRow.user_id;
  } else {
    // Older per-character tokens: the character's owner.
    const { data: charRow } = await supabaseAdmin.from("character_sync_tokens").select("character_id").eq("token", token).maybeSingle();
    if (charRow?.character_id) {
      const { data: c } = await supabaseAdmin.from("characters").select("user_id").eq("id", charRow.character_id).maybeSingle();
      userId = c?.user_id ?? null;
    }
  }
  if (!userId) return NextResponse.json({ error: "Unknown sync token" }, { status: 401 });

  const f = await mergeUpload(userId, body.data);
  // Gathering spots, shared with friends (lib/sharedNodes.ts). Never fails the upload.
  try {
    await saveUserNodes(userId, (body.data as { nodes?: unknown }).nodes);
  } catch (e) {
    console.warn("shared nodes not saved:", e instanceof Error ? e.message : e);
  }
  return NextResponse.json({ ok: true, chars: Object.keys(f.chars).length, sessions: f.sessions.length });
}

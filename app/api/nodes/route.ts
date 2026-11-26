import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "../../../lib/supabaseAdmin";
import { loadSharedNodes } from "../../../lib/sharedNodes";

// Friends' gathering spots for Forever Gold's maps (lib/sharedNodes.ts).
// The tray app asks with the account's sync token about every 20 minutes
// and writes the answer into Forever Gold's SharedNodes.lua. Your own spots
// are left out - the addon already has them.
//
// POST { token } -> { made, maps: { [mapID]: [[x, y, kind, name, times, last, who], ...] } }
export const maxDuration = 30;

export async function POST(req: NextRequest) {
  let body: { token?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON" }, { status: 400 });
  }
  const token = typeof body.token === "string" ? body.token.trim() : "";
  if (!token) return NextResponse.json({ error: "Missing token" }, { status: 400 });
  const { data: row } = await supabaseAdmin.from("user_sync_tokens").select("user_id").eq("token", token).maybeSingle();
  if (!row) return NextResponse.json({ error: "Unknown sync token" }, { status: 401 });

  const maps = await loadSharedNodes(row.user_id);
  return NextResponse.json({ made: Math.floor(Date.now() / 1000), maps });
}

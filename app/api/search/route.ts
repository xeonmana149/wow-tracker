import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "../../../lib/supabaseAdmin";

// Combined top-bar search (2026-09-30: "the search function at the top
// should be items plus characters, plus accounts") - one endpoint, three
// small queries run in parallel, capped low since this feeds a quick
// dropdown under the search box, not a full results page (the Items page
// is still where you go for serious filtering - see ItemSearch.tsx).
//
// Uses supabaseAdmin rather than a per-request browser client because
// `characters` and `profiles` are otherwise RLS-scoped to their own owner
// (see the same note in lib/accountView.ts / ItemSearch.tsx) - a combined
// search across every player's characters and accounts is deliberately
// public here, the same way Leaderboards/Friends necessarily show other
// players' names already.

const RESULT_LIMIT = 6;

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const q = (searchParams.get("q") ?? "").trim();

  if (q.length < 2) {
    return NextResponse.json({ items: [], characters: [], accounts: [] });
  }

  const [itemsRes, charactersRes, profilesRes] = await Promise.all([
    supabaseAdmin
      .from("items")
      .select("id, name, quality_color, icon, icon_name")
      .ilike("name", `%${q}%`)
      .order("name", { ascending: true })
      .limit(RESULT_LIMIT),
    supabaseAdmin
      .from("characters")
      .select("id, name, level, class, race")
      .ilike("name", `%${q}%`)
      .order("level", { ascending: false })
      .limit(RESULT_LIMIT),
    supabaseAdmin
      .from("profiles")
      .select("id, display_name, avatar_icon")
      .ilike("display_name", `%${q}%`)
      .order("display_name", { ascending: true })
      .limit(RESULT_LIMIT),
  ]);

  return NextResponse.json({
    items: itemsRes.data ?? [],
    characters: charactersRes.data ?? [],
    accounts: profilesRes.data ?? [],
  });
}

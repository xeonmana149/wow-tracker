import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "../../../lib/supabaseAdmin";
import { normalizeLootStats } from "../../../lib/lootStats";

// What the tracker addon's in-game window shows that only the website knows
// (2026-11-26): the Crafting Directory, and this account's characters'
// loot and gathering totals. The tray app asks with the account's sync
// token about every 20 minutes and writes the answer into the addon's
// folder as SiteData.lua - addons can't go online themselves.
//
// The crafting part is the same public data as the /crafting page. The
// characters part is the token owner's own characters only.
//
// Shape (kept short - it becomes a Lua table the game loads):
//   { v, made, account,
//     characters: [{ name, class, level, loot }],
//     crafters:   [{ name, owner, class, mine, skills: { [profession]: skill } }],
//     recipes:    [{ n: name, p: profession, i: icon, c: [crafter index (1-based)],
//                    r: [[reagent, quantity]], t: [tooltip lines] }] }
export const maxDuration = 30;

type RawReagent = { name?: string; quantity?: number };
type RawRecipe = string | { name?: string; icon?: number | string | null; reagents?: RawReagent[]; tooltip?: string[] };
type CharRow = {
  id: string;
  name: string;
  class: string | null;
  user_id: string | null;
  profiles: { display_name?: string } | null;
  character_professions: { profession: string; skill: number | null; recipes: RawRecipe[] | null }[] | null;
};

export async function POST(req: NextRequest) {
  let body: { token?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON" }, { status: 400 });
  }
  const token = typeof body.token === "string" ? body.token.trim() : "";
  if (!token) return NextResponse.json({ error: "Missing token" }, { status: 400 });

  const { data: tokenRow } = await supabaseAdmin
    .from("user_sync_tokens")
    .select("user_id")
    .eq("token", token)
    .maybeSingle();
  if (!tokenRow) return NextResponse.json({ error: "Unknown sync token" }, { status: 401 });
  const userId: string = tokenRow.user_id;

  const [{ data: profile }, mine, crafting] = await Promise.all([
    supabaseAdmin.from("profiles").select("display_name").eq("id", userId).maybeSingle(),
    loadMyCharacters(userId),
    supabaseAdmin
      .from("characters")
      .select("id, name, class, user_id, profiles!user_id(display_name), character_professions(profession, skill, recipes)")
      .eq("hidden", false)
      .order("name", { ascending: true }),
  ]);
  if (crafting.error) return NextResponse.json({ error: crafting.error.message }, { status: 500 });

  const crafters: { name: string; owner: string; class: string; mine: boolean; skills: Record<string, number> }[] = [];
  const recipes = new Map<
    string,
    { n: string; p: string; i?: number | string; c: number[]; r?: [string, number][]; t?: string[] }
  >();

  for (const c of (crafting.data ?? []) as unknown as CharRow[]) {
    const profs = (c.character_professions ?? []).filter((p) => Array.isArray(p.recipes) && p.recipes.length > 0);
    if (profs.length === 0) continue;
    const skills: Record<string, number> = {};
    for (const p of c.character_professions ?? []) if (typeof p.skill === "number") skills[p.profession] = p.skill;
    crafters.push({
      name: c.name,
      owner: c.profiles?.display_name ?? "",
      class: c.class ?? "",
      mine: c.user_id === userId,
      skills,
    });
    const index = crafters.length; // Lua arrays start at 1
    for (const p of profs) {
      for (const raw of p.recipes ?? []) {
        const r = typeof raw === "string" ? { name: raw } : raw;
        const name = typeof r?.name === "string" ? r.name.trim() : "";
        if (!name) continue;
        const key = p.profession + "\u0000" + name.toLowerCase();
        let e = recipes.get(key);
        if (!e) {
          e = { n: name, p: p.profession, c: [] };
          recipes.set(key, e);
        }
        if (!e.c.includes(index)) e.c.push(index);
        if (e.i == null && (typeof r.icon === "number" || typeof r.icon === "string")) e.i = r.icon;
        if (!e.r && Array.isArray(r.reagents) && r.reagents.length > 0) {
          e.r = r.reagents
            .filter((g) => typeof g?.name === "string" && g.name)
            .map((g) => [g.name as string, Number(g.quantity) || 1] as [string, number]);
        }
        if (!e.t && Array.isArray(r.tooltip) && r.tooltip.length > 0) {
          // The first line repeats the item's name; ten more is plenty.
          e.t = r.tooltip
            .slice(1, 11)
            .filter((l) => typeof l === "string")
            .map((l) => l.slice(0, 160));
        }
      }
    }
  }

  return NextResponse.json({
    v: 1,
    made: Math.floor(Date.now() / 1000),
    account: profile?.display_name ?? "",
    characters: mine,
    crafters,
    recipes: [...recipes.values()].sort((a, b) => a.n.localeCompare(b.n) || a.p.localeCompare(b.p)),
  });
}

// The owner's characters with their loot totals. Works before
// sql/loot-stats.sql has been run too (the characters just come back without).
async function loadMyCharacters(userId: string) {
  const withLoot = await supabaseAdmin
    .from("characters")
    .select("name, class, level, loot_stats")
    .eq("user_id", userId)
    .order("name");
  if (!withLoot.error) {
    return (withLoot.data ?? []).map((c) => ({
      name: c.name,
      class: c.class ?? "",
      level: c.level ?? 0,
      loot: normalizeLootStats(c.loot_stats) ?? undefined,
    }));
  }
  const plain = await supabaseAdmin.from("characters").select("name, class, level").eq("user_id", userId).order("name");
  return (plain.data ?? []).map((c) => ({ name: c.name, class: c.class ?? "", level: c.level ?? 0 }));
}

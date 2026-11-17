// Pulls every crafting recipe in WoW Forever from Blizzard's Game Data API
// (the game's own "static-forever-us" namespace - Forever's real data, not
// the frozen classic one) and writes it in two shapes:
//
//   lib/data/forever-recipes.json        the website (crafting profits, item pages)
//   addon/ForeverGold/RecipeData.lua     the Forever Gold addon (tooltips)
//
// Run it again whenever Forever adds or changes recipes:
//
//   node --env-file=.env.local scripts/build-forever-recipes.mjs
//
// Needs BLIZZARD_CLIENT_ID / BLIZZARD_CLIENT_SECRET (already in .env.local).

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const NS = "static-forever-us";
const JSON_OUT = path.join(ROOT, "lib", "data", "forever-recipes.json");
const LUA_OUT = path.join(ROOT, "addon", "ForeverGold", "RecipeData.lua");

const id = process.env.BLIZZARD_CLIENT_ID;
const secret = process.env.BLIZZARD_CLIENT_SECRET;
if (!id || !secret) {
  console.error("BLIZZARD_CLIENT_ID / BLIZZARD_CLIENT_SECRET aren't set - run with --env-file=.env.local");
  process.exit(1);
}

const tokenRes = await fetch("https://oauth.battle.net/token", {
  method: "POST",
  body: new URLSearchParams({ grant_type: "client_credentials" }),
  headers: { Authorization: "Basic " + Buffer.from(`${id}:${secret}`).toString("base64") },
});
const { access_token: token } = await tokenRes.json();
if (!token) {
  console.error(`Couldn't get a Blizzard token (HTTP ${tokenRes.status}).`);
  process.exit(1);
}

async function get(p, tries = 4) {
  const url = `https://us.api.blizzard.com${p}?namespace=${NS}&locale=en_US`;
  for (let i = 0; i < tries; i++) {
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (res.ok) return res.json();
    if (res.status === 404) return null;
    // 429 / 5xx: back off and try again.
    await new Promise((r) => setTimeout(r, 500 * (i + 1)));
  }
  throw new Error(`${p} kept failing`);
}

// Runs fn over items, `limit` at a time (Blizzard allows 100 requests a second).
async function pool(items, limit, fn) {
  const out = new Array(items.length);
  let next = 0;
  async function worker() {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i], i);
    }
  }
  await Promise.all(Array.from({ length: limit }, worker));
  return out;
}

const index = await get("/data/wow/profession/index");
const professions = (index?.professions ?? []).filter((p) => !/\[DNT\]|test/i.test(p.name));

const refs = []; // { id, prof, category }
for (const p of professions) {
  const prof = await get(`/data/wow/profession/${p.id}`);
  for (const tier of prof?.skill_tiers ?? []) {
    const t = await get(`/data/wow/profession/${p.id}/skill-tier/${tier.id}`);
    for (const cat of t?.categories ?? []) {
      for (const r of cat.recipes ?? []) refs.push({ id: r.id, prof: p.name, category: cat.name });
    }
  }
  console.log(`${p.name}: ${refs.filter((r) => r.prof === p.name).length} recipes`);
}

let done = 0;
const details = await pool(refs, 12, async (ref) => {
  const r = await get(`/data/wow/recipe/${ref.id}`);
  if (++done % 250 === 0) console.log(`  ${done}/${refs.length}`);
  return r;
});

const recipes = [];
for (let i = 0; i < refs.length; i++) {
  const ref = refs[i];
  const r = details[i];
  if (!r) continue;
  const item = r.crafted_item?.id ?? r.alliance_crafted_item?.id ?? r.horde_crafted_item?.id ?? null;
  const q = r.crafted_quantity ?? {};
  const min = q.value ?? q.minimum ?? 1;
  const max = q.value ?? q.maximum ?? min;
  const reagents = (r.reagents ?? [])
    .filter((x) => x.reagent?.id && x.quantity > 0)
    .map((x) => [x.reagent.id, x.quantity]);
  recipes.push({
    id: ref.id,
    name: r.name ?? `Recipe ${ref.id}`,
    prof: ref.prof,
    category: ref.category,
    item, // null for enchants and other recipes that don't make an item
    qty: [min, max],
    reagents,
    rank: r.rank ?? null,
  });
}
recipes.sort((a, b) => a.prof.localeCompare(b.prof) || a.id - b.id);
// Blizzard lists some recipes twice under different ids (same name, same
// reagents) - keep the first so "used in N recipes" isn't double counted.
{
  const seen = new Set();
  for (let i = recipes.length - 1; i >= 0; i--) recipes[i]._k = `${recipes[i].prof}|${recipes[i].name}|${JSON.stringify(recipes[i].reagents)}`;
  const keep = recipes.filter((r) => (seen.has(r._k) ? false : (seen.add(r._k), true)));
  for (const r of keep) delete r._k;
  console.log(`dropped ${recipes.length - keep.length} duplicate recipes`);
  recipes.length = 0;
  recipes.push(...keep);
}

const profNames = [...new Set(recipes.map((r) => r.prof))].sort();
const made = Math.floor(Date.now() / 1000);

fs.mkdirSync(path.dirname(JSON_OUT), { recursive: true });
fs.writeFileSync(JSON_OUT, JSON.stringify({ made, namespace: NS, professions: profNames, recipes }));

// The addon gets one short string per recipe - thousands of little Lua
// tables would cost far more memory and load time:
//   [recipeID] = "profIndex|madeItemID|yield|reagentID:qty,reagentID:qty|name"
const luaStr = (s) => JSON.stringify(s).replace(/\\u([0-9a-f]{4})/gi, (_, h) => `\\${parseInt(h, 16)}`);
const lines = [
  "-- Written by scripts/build-forever-recipes.mjs from Blizzard's WoW Forever data.",
  "-- Every crafting recipe in the game, so tooltips can say what an item is used for.",
  "-- [recipeID] = \"profession|made item|yield|reagent:qty,...|name\"",
  "ForeverGoldRecipes = {",
  `  made = ${made},`,
  `  profs = { ${profNames.map(luaStr).join(", ")} },`,
  "  r = {",
];
for (const r of recipes) {
  const yieldAvg = Math.round(((r.qty[0] + r.qty[1]) / 2) * 10) / 10;
  const rs = r.reagents.map(([rid, q]) => `${rid}:${q}`).join(",");
  const name = r.name.replace(/\|/g, "/");
  lines.push(`    [${r.id}] = ${luaStr(`${profNames.indexOf(r.prof) + 1}|${r.item ?? 0}|${yieldAvg}|${rs}|${name}`)},`);
}
lines.push("  },", "}", "");
fs.writeFileSync(LUA_OUT, lines.join("\n"));

console.log(`\n${recipes.length} recipes across ${profNames.length} professions.`);
console.log(`wrote ${path.relative(ROOT, JSON_OUT)} (${(fs.statSync(JSON_OUT).size / 1024).toFixed(0)} KB)`);
console.log(`wrote ${path.relative(ROOT, LUA_OUT)} (${(fs.statSync(LUA_OUT).size / 1024).toFixed(0)} KB)`);

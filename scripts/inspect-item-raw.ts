// One-off diagnostic - NOT a fix, just evidence-gathering. Prints the full
// raw Blizzard response already stored for a couple of named items, so we
// can see exactly what fields are available (binding? durability? a
// recipe's "Use:" description? a profession skill requirement?) before
// writing code that extracts and displays them. Nothing here is a guess -
// it's the same JSON already sitting in your `items.raw` column.
//
// HOW TO RUN IT (same setup as the other scripts/*.ts files - same
// .env.local):
//   npx tsx scripts/inspect-item-raw.ts

import fs from "node:fs";
import path from "node:path";

function loadEnvLocal() {
  const envPath = path.resolve(process.cwd(), ".env.local");
  if (!fs.existsSync(envPath)) {
    console.warn(`No .env.local found at ${envPath} - continuing with whatever's already in your shell's environment.`);
    return;
  }
  const contents = fs.readFileSync(envPath, "utf8");
  for (const rawLine of contents.split("\n")) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const eq = line.indexOf("=");
    if (eq === -1) continue;
    const key = line.slice(0, eq).trim();
    let value = line.slice(eq + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    if (!(key in process.env)) process.env[key] = value;
  }
}
loadEnvLocal();

// Add/remove names here if you want to check other items too - it's a
// case-insensitive partial match against the item name. Checking Stormrage
// Bracers this time - a Druid tier-set piece whose real tooltip prints
// "Classes: Druid" plus the full set name, set piece list, and set bonus
// text. Atiesh (a weapon) had no class field at all in Blizzard's data, but
// a tier-set piece may expose class restriction and set membership
// differently - need to see the real shape before building anything.
const NAMES_TO_CHECK = ["Stormrage Bracers"];

// Writing to a file instead of console.log - the terminal itself was
// truncating the output on the last run, cutting off the top of the JSON
// before we could see it. A file has no such limit.
const OUTPUT_PATH = path.resolve(process.cwd(), "item-raw-dump.json");

async function main() {
  const { supabaseAdmin } = await import("../lib/supabaseAdmin");

  const output: unknown[] = [];

  for (const name of NAMES_TO_CHECK) {
    const { data: rows, error } = await supabaseAdmin
      .from("items")
      .select("id, name, source, verified, raw")
      .ilike("name", `%${name}%`);
    if (error) throw new Error(error.message);

    if (!rows || rows.length === 0) {
      console.log(`No rows found matching "${name}"`);
      continue;
    }

    for (const row of rows) {
      console.log(`Found: ${row.name} (id ${row.id}, source=${row.source}, verified=${row.verified})`);
      output.push({
        matchedName: name,
        id: row.id,
        name: row.name,
        source: row.source,
        verified: row.verified,
        raw: row.raw,
      });
    }
  }

  fs.writeFileSync(OUTPUT_PATH, JSON.stringify(output, null, 2), "utf8");
  console.log(`\nWrote full dump to ${OUTPUT_PATH} - attach that file back to me.`);
}

main().catch((err) => {
  console.error("\nInspect failed:", err);
  process.exit(1);
});
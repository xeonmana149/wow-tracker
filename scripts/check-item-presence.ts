// One-off diagnostic - NOT a fix. Checks a short list of item ids: are they
// in your `items` table at all, and separately, does Blizzard's API even
// know about them? Used to confirm whether a missing item (like Stormrage
// Bracers, id 16904) is a gap left by the bulk-seed job's cap-partitioning
// (Blizzard silently truncating a subclass search at ~1000 results, with no
// further splitting attempted once a subclass is still capped after the
// class->subclass split - see collectIdsForClass, scripts/bulk-seed-items.ts)
// or something else entirely.
//
// HOW TO RUN IT (same setup as the other scripts/*.ts files - same
// .env.local):
//   npx tsx scripts/check-item-presence.ts

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

// Add more ids here as you spot other missing items - Stormrage Bracers
// (Druid T3) is the one reported so far.
const IDS_TO_CHECK = [16904];

async function main() {
  const { supabaseAdmin } = await import("../lib/supabaseAdmin");
  const { blizzardGet } = await import("../lib/blizzard");
  const { ITEM_NAMESPACE, ITEM_REGION } = await import("../lib/items");

  for (const id of IDS_TO_CHECK) {
    console.log(`\n=== Item ${id} ===`);

    const { data: row, error } = await supabaseAdmin
      .from("items")
      .select("id, name, source, hidden, verified")
      .eq("id", id)
      .maybeSingle();
    if (error) throw new Error(error.message);

    if (row) {
      console.log(`In database: YES - "${row.name}" (source=${row.source}, hidden=${row.hidden}, verified=${row.verified})`);
    } else {
      console.log(`In database: NO - no row at all for this id.`);
    }

    try {
      const result = await blizzardGet(ITEM_REGION, `/data/wow/item/${id}`, { namespace: ITEM_NAMESPACE });
      if (result.ok) {
        const body = result.body as { name?: { en_US?: string }; item_subclass?: { name?: { en_US?: string } } };
        console.log(`Blizzard knows this id: YES - "${body.name?.en_US}" (${body.item_subclass?.name?.en_US})`);
      } else {
        console.log(`Blizzard knows this id: NO (status ${result.status}) - Blizzard's API doesn't recognize this id at all.`);
      }
    } catch (err) {
      console.log(`Blizzard lookup failed: ${err instanceof Error ? err.message : String(err)}`);
    }
  }
}

main().catch((err) => {
  console.error("\nCheck failed:", err);
  process.exit(1);
});
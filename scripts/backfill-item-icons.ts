// One-off (safely re-runnable) companion to bulk-seed-items.ts: fills in
// icon_name for every item already sitting in the `items` table with no
// icon at all - which is everything the bulk-seed job added, since
// ensureItemsExist() only fetches an icon for items it's creating fresh and
// never revisits a row that already exists. Run this once after a
// bulk-seed pass (or any time you notice icon-less items) to backfill them.
//
// HOW TO RUN IT (same setup as bulk-seed-items.ts - same .env.local):
//   npx tsx scripts/backfill-item-icons.ts
//
// Safe to stop and re-run - it only ever looks at rows still missing both
// `icon` and `icon_name`, so anything already filled in is left alone.

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

async function mapWithConcurrency<T, R>(items: T[], limit: number, fn: (item: T) => Promise<R>): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  async function worker() {
    while (true) {
      const i = next++;
      if (i >= items.length) return;
      results[i] = await fn(items[i]);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return results;
}

async function main() {
  const { fetchItemIconName } = await import("../lib/items");
  const { supabaseAdmin } = await import("../lib/supabaseAdmin");

  const startedAt = Date.now();
  const PAGE = 500;
  let totalFixed = 0;
  let totalMissed = 0;

  while (true) {
    const { data: rows, error } = await supabaseAdmin
      .from("items")
      .select("id")
      .is("icon", null)
      .is("icon_name", null)
      .limit(PAGE);
    if (error) throw new Error(error.message);
    if (!rows || rows.length === 0) break;

    const results = await mapWithConcurrency(rows, 8, async (row: { id: number }) => {
      const iconName = await fetchItemIconName(row.id);
      return { id: row.id, iconName };
    });

    // Every row in this batch gets written, even the misses - marked with
    // "" (not null) so a permanently icon-less placeholder item (Forever-
    // only, no Blizzard media at all) doesn't get re-selected by the
    // `.is("icon_name", null)` filter forever. "" still renders as "no
    // icon" everywhere else, same as null did.
    for (const r of results) {
      const { error: updateError } = await supabaseAdmin
        .from("items")
        .update({ icon_name: r.iconName ?? "" })
        .eq("id", r.id);
      if (updateError) console.warn(`  failed to save item ${r.id}: ${updateError.message}`);
    }

    const fixedThisBatch = results.filter((r) => r.iconName != null).length;
    totalFixed += fixedThisBatch;
    totalMissed += results.length - fixedThisBatch;
    console.log(`...${totalFixed} icons filled in so far (${totalMissed} items have no icon available from Blizzard)`);
  }

  const minutes = ((Date.now() - startedAt) / 60000).toFixed(1);
  console.log(`\nDone in ${minutes} minutes. Filled in ${totalFixed} icons; ${totalMissed} items had none available.`);
}

main().catch((err) => {
  console.error("\nIcon backfill failed:", err);
  process.exit(1);
});
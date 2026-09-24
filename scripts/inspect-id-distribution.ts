// One-off diagnostic - NOT a fix. We just found out the bulk-seed job
// pulled in Season of Discovery items alongside real vanilla Classic ones,
// because Blizzard serves both from the exact same API namespace
// (classic1x-us) with no separate flag to tell them apart. Confirmed
// example: item 217281 "Moonsteel Broadsword" is Wowhead-tagged "SoD Phase
// 2" - a brand-new SoD-only item, distinct from the real vanilla item of
// the same name (id 3853).
//
// Rather than guess an ID cutoff (that's exactly what caused the Armor
// regression earlier this session), this dumps the actual ID distribution
// of everything in your `items` table, bucketed, plus a sample of names
// from the highest bucket - so we can see where the real gap between
// "vanilla" and "SoD-only" IDs falls before writing any delete/hide
// migration.
//
// HOW TO RUN IT (same setup as the other scripts/*.ts files - same
// .env.local):
//   npx tsx scripts/inspect-id-distribution.ts

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

// Buckets chosen to straddle where we'd expect a gap: real vanilla content
// tops out somewhere in the low-to-mid 20,000s; anything else added to
// Classic Era over the years (small anniversary events, etc.) would likely
// sit just above that; SoD's brand-new items (confirmed example: 217281)
// look like they were handed out from Blizzard's *current* ID pool, which
// by now is well past 200,000 for any content, classic or retail.
const BUCKETS: [number, number | null][] = [
  [0, 20000],
  [20000, 25000],
  [25000, 30000],
  [30000, 50000],
  [50000, 100000],
  [100000, 200000],
  [200000, null],
];

async function main() {
  const { supabaseAdmin } = await import("../lib/supabaseAdmin");

  const { count: totalCount } = await supabaseAdmin
    .from("items")
    .select("id", { count: "exact", head: true })
    .eq("source", "classic_api");
  console.log(`Total baseline (classic_api) rows: ${totalCount}\n`);

  for (const [lo, hi] of BUCKETS) {
    let query = supabaseAdmin
      .from("items")
      .select("id", { count: "exact", head: true })
      .eq("source", "classic_api")
      .gte("id", lo);
    if (hi != null) query = query.lt("id", hi);
    const { count, error } = await query;
    if (error) throw new Error(error.message);
    console.log(`id in [${lo}, ${hi ?? "∞"}): ${count} items`);
  }

  // A sample from the highest bucket, so we can eyeball whether these
  // really do look like SoD/new content rather than something legitimate.
  const { data: sample, error: sampleError } = await supabaseAdmin
    .from("items")
    .select("id, name, verified")
    .eq("source", "classic_api")
    .gte("id", 100000)
    .order("id", { ascending: true })
    .limit(40);
  if (sampleError) throw new Error(sampleError.message);

  console.log(`\nSample of items with id >= 100000 (up to 40, lowest IDs first):`);
  for (const row of sample ?? []) {
    console.log(`  ${row.id}\t${row.name}${row.verified ? "  [VERIFIED - seen in Forever]" : ""}`);
  }

  // Also worth knowing: has anything in that high range actually been
  // CONFIRMED by a real player's addon? If so, it's genuinely in Forever
  // regardless of where Blizzard's data thinks it came from, and shouldn't
  // be deleted just because of its ID.
  const { count: verifiedHighCount } = await supabaseAdmin
    .from("items")
    .select("id", { count: "exact", head: true })
    .gte("id", 100000)
    .eq("verified", true);
  console.log(`\nOf items with id >= 100000, ${verifiedHighCount} are verified (actually seen in Forever).`);
}

main().catch((err) => {
  console.error("\nInspect failed:", err);
  process.exit(1);
});
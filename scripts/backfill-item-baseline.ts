// One-off (safely re-runnable) fix for items that were only ever created
// from a live tooltip observation (applyLiveObservation, source "auto_new")
// before it knew to also grab Blizzard's baseline for a brand-new item -
// see the 2026-09-24 fix in lib/items.ts. Those rows have real stats
// (quality/armor/stats/etc, from the tooltip - the trustworthy source) but
// are missing structural fields Blizzard's baseline is fine for: item
// level, item class/subclass, inventory type, required level. Without a
// known item level, a piece can never be flagged in "What's next" as
// worth upgrading, however far behind it actually is.
//
// Only ever fills in a field that's currently null - never touches
// anything a live tooltip already set (quality, armor, stats, price...),
// so this can't clobber real Forever data with Blizzard's un-rebalanced
// baseline. Skips ids that are clearly Forever-only (>= 100000, see
// isLikelyNonVanillaId) since Blizzard has no data for those anyway.
//
// HOW TO RUN IT (same setup as the other scripts/*.ts files - same
// .env.local, with BLIZZARD_CLIENT_ID/BLIZZARD_CLIENT_SECRET set):
//   npx tsx scripts/backfill-item-baseline.ts

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

type BaselineCandidateRow = {
  id: number;
  item_class: string | null;
  item_subclass: string | null;
  inventory_type: string | null;
  level: number | null;
  required_level: number | null;
};

async function main() {
  const { rowFromBlizzard, mapWithConcurrency, isLikelyNonVanillaId, ITEM_NAMESPACE, ITEM_REGION } =
    await import("../lib/items");
  const { blizzardGet } = await import("../lib/blizzard");
  const { supabaseAdmin } = await import("../lib/supabaseAdmin");

  const startedAt = Date.now();
  const PAGE = 500;
  let scanned = 0;
  let fixed = 0;
  let notFoundOnBlizzard = 0;
  let skippedNonVanilla = 0;
  let from = 0;

  while (true) {
    const { data, error } = await supabaseAdmin
      .from("items")
      .select("id, item_class, item_subclass, inventory_type, level, required_level")
      .is("level", null)
      .range(from, from + PAGE - 1);
    if (error) throw new Error(error.message);
    const rows = data as BaselineCandidateRow[] | null;
    if (!rows || rows.length === 0) break;

    const candidates: BaselineCandidateRow[] = rows.filter((r) => {
      if (isLikelyNonVanillaId(r.id)) {
        skippedNonVanilla++;
        return false;
      }
      return true;
    });

    await mapWithConcurrency(candidates, 8, async (row) => {
      scanned++;
      try {
        const result = await blizzardGet(ITEM_REGION, `/data/wow/item/${row.id}`, {
          namespace: ITEM_NAMESPACE,
        });
        if (!result.ok) {
          notFoundOnBlizzard++;
          return;
        }
        const baseline = rowFromBlizzard(row.id, result.body as Parameters<typeof rowFromBlizzard>[1]);

        const update: Record<string, unknown> = {};
        if (row.item_class == null && baseline.item_class != null) update.item_class = baseline.item_class;
        if (row.item_subclass == null && baseline.item_subclass != null) update.item_subclass = baseline.item_subclass;
        if (row.inventory_type == null && baseline.inventory_type != null) update.inventory_type = baseline.inventory_type;
        if (row.level == null && baseline.level != null) update.level = baseline.level;
        if (row.required_level == null && baseline.required_level != null) update.required_level = baseline.required_level;

        if (Object.keys(update).length === 0) return;

        const { error: updateError } = await supabaseAdmin.from("items").update(update).eq("id", row.id);
        if (updateError) {
          console.warn(`  failed to backfill baseline for item ${row.id}: ${updateError.message}`);
          return;
        }
        fixed++;
      } catch (err) {
        console.warn(`  error fetching item ${row.id} from Blizzard: ${(err as Error).message}`);
      }
    });

    console.log(`...scanned ${scanned}, fixed ${fixed} so far`);
    from += PAGE;
  }

  const minutes = ((Date.now() - startedAt) / 60000).toFixed(1);
  console.log(
    `\nDone in ${minutes} minutes. Scanned ${scanned} items missing a level, fixed ${fixed}, ${notFoundOnBlizzard} not known to Blizzard (genuine Forever-only items - nothing to backfill there), ${skippedNonVanilla} skipped as non-vanilla ids.`
  );
}

main().catch((err) => {
  console.error("\nBackfill failed:", err);
  process.exit(1);
});
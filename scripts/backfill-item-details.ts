// One-off (safely re-runnable) fix for every baseline item seeded before
// this project was reading item level, binding, durability, weapon DPS,
// "Use:"/"Equip:" text, profession requirements, and crafting reagents out
// of Blizzard's data. That data was already sitting in Blizzard's response
// this whole time - it just wasn't being read (and for weapon damage/speed
// specifically, the code was reading the WRONG field names entirely, so
// those were always null even though the real values were right there).
//
// Same pattern as fix-item-stats.ts: this doesn't call Blizzard again at
// all - every row's full response is already saved in its `raw` column, so
// this just re-derives the new fields from `raw` locally and writes them
// back.
//
// HOW TO RUN IT (same setup as the other scripts/*.ts files - same
// .env.local):
//   npx tsx scripts/backfill-item-details.ts

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

async function main() {
  const { extractPreviewItemDetails } = await import("../lib/items");
  const { supabaseAdmin } = await import("../lib/supabaseAdmin");

  const startedAt = Date.now();
  const PAGE = 500;
  let scanned = 0;
  let fixed = 0;
  let from = 0;
  // Blizzard's armor field path was never actually confirmed against a real
  // armor item (only weapons and a recipe were checked) - if it turns out
  // to be wrong the same way weapon damage was, this counts how often we
  // find an `armor` object in `raw` but extractPreviewItemDetails comes back
  // with a null armor value, so it's obvious from the summary at the end
  // rather than silently wrong again.
  let armorFieldMismatches = 0;

  while (true) {
    const { data: rows, error } = await supabaseAdmin
      .from("items")
      .select("id, raw, armor, damage_min, damage_max, weapon_speed, weapon_dps, binding, durability, spell_lines, profession_requirement, reagents_text, classes_text, item_set_line, item_set_pieces, item_set_bonuses, stats")
      .eq("source", "classic_api")
      .not("raw", "is", null)
      .range(from, from + PAGE - 1);
    if (error) throw new Error(error.message);
    if (!rows || rows.length === 0) break;

    for (const row of rows) {
      scanned++;
      const previewItem = (row.raw as { preview_item?: unknown } | null)?.preview_item as
        | Parameters<typeof extractPreviewItemDetails>[0]
        | undefined;
      const details = extractPreviewItemDetails(previewItem);

      const rawPreview = previewItem as { armor?: unknown } | undefined;
      if (rawPreview?.armor != null && details.armor == null) armorFieldMismatches++;

      const update = {
        armor: details.armor,
        damage_min: details.damage_min,
        damage_max: details.damage_max,
        weapon_speed: details.weapon_speed,
        weapon_dps: details.weapon_dps,
        binding: details.binding,
        durability: details.durability,
        spell_lines: details.spell_lines,
        profession_requirement: details.profession_requirement,
        reagents_text: details.reagents_text,
        classes_text: details.classes_text,
        item_set_line: details.item_set_line,
        item_set_pieces: details.item_set_pieces,
        item_set_bonuses: details.item_set_bonuses,
        stats: details.stats,
      };

      // Skip the write if nothing actually changed - no point re-writing
      // 13,000+ rows every time this is re-run for safety.
      const before = JSON.stringify({
        armor: row.armor,
        damage_min: row.damage_min,
        damage_max: row.damage_max,
        weapon_speed: row.weapon_speed,
        weapon_dps: row.weapon_dps,
        binding: row.binding,
        durability: row.durability,
        spell_lines: row.spell_lines,
        profession_requirement: row.profession_requirement,
        reagents_text: row.reagents_text,
        classes_text: row.classes_text,
        item_set_line: row.item_set_line,
        item_set_pieces: row.item_set_pieces,
        item_set_bonuses: row.item_set_bonuses,
        stats: row.stats,
      });
      if (before === JSON.stringify(update)) continue;

      const { error: updateError } = await supabaseAdmin.from("items").update(update).eq("id", row.id);
      if (updateError) {
        console.warn(`  failed to backfill details for item ${row.id}: ${updateError.message}`);
        continue;
      }
      fixed++;
    }

    console.log(`...scanned ${scanned}, fixed ${fixed} so far`);
    from += PAGE;
  }

  const minutes = ((Date.now() - startedAt) / 60000).toFixed(1);
  console.log(`\nDone in ${minutes} minutes. Scanned ${scanned} baseline items, fixed ${fixed}.`);
  if (armorFieldMismatches > 0) {
    console.log(
      `\nHeads up: ${armorFieldMismatches} rows had an "armor" object in their raw Blizzard data that didn't match the expected shape (preview_item.armor.value) - armor may not be populating correctly for those. Worth pasting one of their raw values back if you spot armor pieces still missing an Armor line.`
    );
  }
}

main().catch((err) => {
  console.error("\nBackfill failed:", err);
  process.exit(1);
});
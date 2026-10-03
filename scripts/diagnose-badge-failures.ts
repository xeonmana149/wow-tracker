// Diagnostic for the staging-sync-test.ts failures (2026-10-03).
//
// checkAccountAchievements/awardAchievement are deliberately written to
// swallow any DB error and just return false, so a sync never breaks just
// because one achievement failed to write - great for production safety,
// terrible for figuring out WHY something didn't award. This script does
// the exact same upserts those functions do, but prints the real error
// instead of swallowing it.
//
// Uses the same env vars as staging-sync-test.ts - run it right after that
// script, in the same terminal (the env vars are already set):
//   npx tsx scripts/diagnose-badge-failures.ts

import { createClient } from "@supabase/supabase-js";

const SYNC_TOKEN = process.env.SYNC_TOKEN;
const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SYNC_TOKEN || !SUPABASE_URL || !SERVICE_KEY) {
  console.error("Missing SYNC_TOKEN / NEXT_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY - set the same env vars as staging-sync-test.ts first.");
  process.exit(1);
}

const admin = createClient(SUPABASE_URL, SERVICE_KEY);

async function run() {
  const { data: tokenRow } = await admin.from("user_sync_tokens").select("user_id").eq("token", SYNC_TOKEN!).maybeSingle();
  if (!tokenRow) {
    console.error("Could not resolve the test account from SYNC_TOKEN.");
    process.exit(1);
  }
  const userId = tokenRow.user_id as string;

  const { data: anyCharacter } = await admin.from("characters").select("id").eq("user_id", userId).limit(1).maybeSingle();
  const characterId = anyCharacter?.id as string | undefined;

  console.log("=== account_achievements upserts (the ones staging-sync-test.ts said FAILED) ===");
  for (const kind of ["marathon", "battle_scarred", "apex_predator", "legacy_master", "completionist"]) {
    const { data, error } = await admin
      .from("account_achievements")
      .upsert({ user_id: userId, kind }, { onConflict: "user_id,kind", ignoreDuplicates: true })
      .select("kind");
    console.log(`\n${kind}:`);
    console.log(`  data: ${JSON.stringify(data)}`);
    console.log(`  error: ${error ? JSON.stringify(error) : "none"}`);
  }

  console.log("\n=== account_achievements upserts (ones that PASSED, for comparison) ===");
  for (const kind of ["tycoon", "class_collector"]) {
    const { data, error } = await admin
      .from("account_achievements")
      .upsert({ user_id: userId, kind }, { onConflict: "user_id,kind", ignoreDuplicates: true })
      .select("kind");
    console.log(`\n${kind}:`);
    console.log(`  data: ${JSON.stringify(data)}`);
    console.log(`  error: ${error ? JSON.stringify(error) : "none"}`);
  }

  if (characterId) {
    console.log("\n=== achievements upserts (the level milestones that FAILED) ===");
    for (const kind of ["level_10", "level_20", "level_30", "level_40", "level_50"]) {
      const { data, error } = await admin
        .from("achievements")
        .upsert({ character_id: characterId, kind }, { onConflict: "character_id,kind", ignoreDuplicates: true })
        .select("kind");
      console.log(`\n${kind}:`);
      console.log(`  data: ${JSON.stringify(data)}`);
      console.log(`  error: ${error ? JSON.stringify(error) : "none"}`);
    }

    console.log("\n=== achievements upsert (one that PASSED, for comparison) ===");
    const { data, error } = await admin
      .from("achievements")
      .upsert({ character_id: characterId, kind: "max_level" }, { onConflict: "character_id,kind", ignoreDuplicates: true })
      .select("kind");
    console.log(`\nmax_level:`);
    console.log(`  data: ${JSON.stringify(data)}`);
    console.log(`  error: ${error ? JSON.stringify(error) : "none"}`);
  } else {
    console.log("\n(No test character found to check the achievements table with - run staging-sync-test.ts first.)");
  }

  console.log(
    "\nWhat to look for: an `error` above with a message like \"violates check constraint\" or " +
      "\"invalid input value for enum\" confirms the database is rejecting these specific kind " +
      "strings - meaning a DB migration to allow them never ran, even though the website code " +
      "already expects them. `data: []` with `error: none` means the upsert succeeded as a no-op " +
      "(already existed) - that's fine. `data` with the row in it and `error: none` means it just " +
      "worked here, which would point back at the award CONDITION instead (the math/threshold), " +
      "not the database."
  );
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});

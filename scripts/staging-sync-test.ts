// Staging dry run (2026-10-03) - replays SYNTHETIC addon sync payloads
// straight at your real, deployed /api/sync route (the exact code path a
// real player's addon/tray app hits), then reads the database back to
// confirm every achievement/badge that SHOULD fire actually did.
//
// This is the complement to scripts/test-achievements.ts: that script
// proves the award FUNCTIONS are correct in isolation with fake data. This
// script proves the REAL route (token lookup, character creation, the
// applyImport() pipeline, checkAccountAchievements, the activity feed) all
// wire together correctly end to end - the category of bug a pure unit test
// can't see (wrong field name in the payload, a route that 500s, a DB
// constraint that rejects the insert, etc).
//
// IMPORTANT - USE A THROWAWAY TEST ACCOUNT, NOT YOUR MAIN ONE. This creates
// several "Synth <Class>" characters, each pushed to level 60 with every
// stat maxed out, to cover every threshold at once. Easiest cleanup when
// you're done: delete the whole test account, rather than hunting down
// individual characters.
//
// LEGACY CHALLENGES - REWORKED, NOT SKIPPED (2026-10-03) - this used to send
// 111 fabricated rows with fake IDs (900000+), which was fine when
// account_legacy_achievements was per-account, but legacy_achievement_definitions
// is now a single table SHARED by every account (see
// sql/legacy-achievement-shared-reference.sql), so those fake IDs would write
// "Synthetic Legacy Achievement N" into the real data every account's Legacy
// Challenges page reads from - which is exactly what happened the first time
// this ran after that migration shipped (see
// sql/cleanup-shared-definitions-test-pollution.sql), and why the sync route
// now hard-filters out any achievement_id >= 900000 before it ever reaches
// either legacy table (lib/importLogic.ts's LEGACY_ACHIEVEMENT_TEST_ID_FLOOR)
// - a fake-ID payload is accepted by /api/sync but silently dropped.
//
// So this now reads the REAL rows already sitting in legacy_achievement_definitions
// (via the admin client, before any character syncs) and replays THOSE exact
// achievement_id/category/name/icon/points/ui_points values back with
// completed: true - the upsert just rewrites the same real data over itself
// (a harmless no-op for the shared table) while still genuinely exercising
// the write path and letting Legacy Complete fire for real. Requires at
// least LEGACY_ACHIEVEMENT_TOTAL real rows to already exist (i.e. at least
// one real account has fully synced Legacy Challenges at least once) - if
// fewer exist, this part is skipped with a warning rather than inventing
// placeholder data, since there's no longer a safe way for this script to
// manufacture legacy achievement data from nothing.
//
// SETUP (one-time, a few minutes):
//   1. Sign up a new throwaway account on your site (a second email works
//      fine, or a test account if you have one).
//   2. On that account, generate an account-level sync token the same way
//      the real tray app setup does (Dashboard -> sync setup) and copy it.
//   3. Set the environment variables below and run:
//
//        $env:SYNC_URL="https://your-site.vercel.app/api/sync"
//        $env:SYNC_TOKEN="<the token from step 2>"
//        $env:NEXT_PUBLIC_SUPABASE_URL="<your project URL>"
//        $env:SUPABASE_SERVICE_ROLE_KEY="<your service role key>"
//        npx tsx scripts/staging-sync-test.ts
//
//      (bash/macOS/Linux: use `export VAR=value` instead of `$env:VAR=`.)
//      SYNC_URL defaults to http://localhost:3000/api/sync if you'd rather
//      run this against `npm run dev` first - cheaper to iterate on, same
//      code path, just not the real deployment.
//
// This talks to your REAL database (via the service role key, same as the
// sync route itself uses) - that's the whole point, but it's also why the
// throwaway-account warning above matters.

import { createClient } from "@supabase/supabase-js";
import { TIER_COUNTERS, tierThresholds, PERSONALITY_BADGES, TIERED_ACHIEVEMENT_KINDS, TOP_PVP_RANK_CAP, type TieredAchievementKind } from "../lib/achievements";
import { LEGACY_ACHIEVEMENT_TOTAL, PVP_DYNASTY_THRESHOLD, TIME_LOST_IN_AZEROTH_HOURS, ALL_PROFESSIONS } from "../lib/accountAchievements";
import { CLASSES, RACE_FACTION } from "../lib/options";

const SYNC_URL = process.env.SYNC_URL ?? "http://localhost:3000/api/sync";
const SYNC_TOKEN = process.env.SYNC_TOKEN;
const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SYNC_TOKEN || !SUPABASE_URL || !SERVICE_KEY) {
  console.error(
    "Missing required env vars. Need SYNC_TOKEN, NEXT_PUBLIC_SUPABASE_URL (or SUPABASE_URL), and SUPABASE_SERVICE_ROLE_KEY.\n" +
      "See the comment at the top of this file for how to set them up."
  );
  process.exit(1);
}

const admin = createClient(SUPABASE_URL, SERVICE_KEY);

// ---------------------------------------------------------------------------
// Payload building - every number here is DERIVED from the real thresholds
// (tierThresholds, LEGACY_ACHIEVEMENT_TOTAL, TIME_LOST_IN_AZEROTH_HOURS, etc.), never a
// second hardcoded copy, for the same reason scripts/test-achievements.ts
// does it that way: it can't drift out of sync with what it's testing.
// ---------------------------------------------------------------------------

let nextStatId = 1;
function buildStatistics(): { id: number; category: string; name: string; value: string }[] {
  const rows: { id: number; category: string; name: string; value: string }[] = [];
  const seen = new Set<string>();
  const push = (category: string, name: string, value: number) => {
    const key = `${category}::${name}`;
    if (seen.has(key)) return; // a stat can feed more than one badge (e.g. Social) - only send it once
    seen.add(key);
    rows.push({ id: nextStatId++, category, name, value: String(value) });
  };

  // Every TIERED_ACHIEVEMENT_KIND that's actually sourced from Statistics -
  // "recipes"/"master_chef" come from character_professions instead (handled
  // via the professions payload below), and "addicted" from timePlayedSeconds
  // (handled via basic.timePlayedSeconds below), so both are skipped here,
  // same as importLogic.ts itself skips "recipes" in this exact loop.
  for (const kind of TIERED_ACHIEVEMENT_KINDS) {
    if (kind === "recipes" || kind === "master_chef" || kind === "addicted") continue;
    const platinum = tierThresholds(kind as TieredAchievementKind).slice(-1)[0].value;
    // Comfortably over Platinum, not exactly on it - this script is proving
    // "the whole pipeline fires", not re-proving exact boundaries (that's
    // what test-achievements.ts's awardTier calls already covered).
    const value = Math.ceil(platinum * 1.2);
    for (const sel of TIER_COUNTERS[kind as TieredAchievementKind]) {
      if ("categoryOnly" in sel) {
        push(sel.categoryOnly, `Synthetic ${kind}`, value);
      } else {
        push(sel.category, sel.name, value);
      }
    }
  }

  // Personality badges - one stat each, same threshold+buffer approach.
  for (const badge of PERSONALITY_BADGES) {
    push(badge.category, badge.name, Math.ceil(badge.threshold * 1.5));
  }

  return rows;
}

type LegacyAchievementPayloadRow = {
  id: number;
  category: string;
  name: string;
  description?: string | null;
  completed: boolean;
  icon?: number | null;
  points?: number | null;
  uiPoints?: number;
};

// Reads the REAL rows already in the shared legacy_achievement_definitions
// table and replays them back with completed: true - see the file-header
// comment above for why this can no longer fabricate its own IDs. Returns
// an empty array (with a warning) if fewer than LEGACY_ACHIEVEMENT_TOTAL real
// rows exist yet, rather than padding with placeholder data.
async function buildLegacyAchievements(): Promise<LegacyAchievementPayloadRow[]> {
  const { data, error } = await admin
    .from("legacy_achievement_definitions")
    .select("achievement_id, category, name, description, icon, points, ui_points");

  if (error) {
    console.warn(`Could not read legacy_achievement_definitions (${error.message}) - skipping Legacy Challenges this run.`);
    return [];
  }
  if (!data || data.length < LEGACY_ACHIEVEMENT_TOTAL) {
    console.warn(
      `Only ${data?.length ?? 0}/${LEGACY_ACHIEVEMENT_TOTAL} real rows in legacy_achievement_definitions - ` +
        `need at least one real account to have fully synced Legacy Challenges before this script can exercise ` +
        `them. Skipping Legacy Challenges this run (legacy_complete and the Legacy Challenges page itself are ` +
        `unaffected either way).`
    );
    return [];
  }

  return data.map((row) => ({
    id: row.achievement_id as number,
    category: row.category as string,
    name: row.name as string,
    description: row.description as string | null,
    completed: true,
    icon: row.icon as number | null,
    points: row.points as number | null,
    uiPoints: typeof row.ui_points === "number" ? row.ui_points : undefined,
  }));
}

function buildProfessions(): { name: string; skill: number; recipes: string[] }[] {
  return ALL_PROFESSIONS.map((name) => ({
    name,
    skill: 300,
    // "recipes"/Artisan sums ACROSS every profession, "master_chef" counts
    // Cooking alone - 150 each clears Artisan's Platinum (750 total across
    // ~9 professions) and Master Chef's Platinum (100) comfortably.
    recipes: Array.from({ length: 150 }, (_, i) => `Synthetic ${name} Recipe ${i + 1}`),
  }));
}

type SyncPayload = Record<string, unknown>;

async function sendSync(payload: SyncPayload): Promise<any> {
  const res = await fetch(SYNC_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ token: SYNC_TOKEN, data: payload }),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(`Sync failed (${res.status}): ${JSON.stringify(json)}`);
  }
  return json;
}

async function syncOneCharacter(cls: string, race: string, index: number, legacyPayload: LegacyAchievementPayloadRow[]) {
  // Exactly two words - the DB enforces this (characters_name_two_words
  // check constraint, see the comment in api-sync-route.ts). Don't slice or
  // pad this further; any extra space creates a third word and the create
  // fails.
  const name = `Synth${index} ${cls.replace(/\s+/g, "")}`;
  // 1. Genesis sync - low level, establishes a real "before" row so the
  //    second sync's level jump actually registers as a level-up (a brand
  //    new character created AT level 60 would never trigger max_level/the
  //    milestones - see the comment in the chat about why this needs two
  //    syncs, not one).
  await sendSync({ basic: { name, race, class: cls, level: 1, money: 0 } });

  // 2. Everything-maxed sync.
  await sendSync({
    basic: {
      name,
      race,
      class: cls,
      level: 60,
      money: 999999 * 10000, // comfortably over every gold-based threshold
      honor: 999999,
      deaths: 0,
      pvpKills: 0,
      timePlayedSeconds: Math.ceil(TIME_LOST_IN_AZEROTH_HOURS * 1.2) * 3600,
    },
    gear: {
      mainHand: {
        link: "item:19019::::::::60:::::",
        name: "Thunderfury, Blessed Blade of the Windseeker",
        id: 19019,
        color: "ff8000", // Legendary - triggers the one-off legendary_item badge
        tooltip: ["Thunderfury, Blessed Blade of the Windseeker"],
      },
    },
    professions: buildProfessions(),
    statistics: buildStatistics(),
    legacyAchievements: legacyPayload,
    // Every synth character reports the top rank (2026-10-03) - nothing
    // about this field requires an actual in-game UI scan, that's only how
    // the REAL addon populates it (scanPvpRankFromUI); the sync route just
    // trusts whatever the payload says, so this script can set it directly
    // to exercise top_pvp_rank (one character is enough) and pvp_dynasty
    // (needs PVP_DYNASTY_THRESHOLD - every character here clears that).
    pvpRank: { rank: TOP_PVP_RANK_CAP, rankName: "Grand Marshal", points: 999999, pointsMax: 999999 },
  });

  return name;
}

async function run() {
  console.log(`Target: ${SYNC_URL}\n`);

  // One (class, race) pair per character, cycling the shorter list so every
  // class AND every race gets covered by the end, with as few throwaway
  // characters as possible.
  const allRaces = Object.keys(RACE_FACTION);
  const pairCount = Math.max(CLASSES.length, allRaces.length);
  if (pairCount < PVP_DYNASTY_THRESHOLD) {
    // Can't happen with the current class/race lists, but if either ever
    // shrinks below the threshold, fail loudly here rather than silently
    // under-covering pvp_dynasty below.
    console.warn(`Only ${pairCount} synth characters planned, but pvp_dynasty needs ${PVP_DYNASTY_THRESHOLD} - it won't be reliably exercised this run.`);
  }
  const legacyPayload = await buildLegacyAchievements();

  const createdNames: string[] = [];
  for (let i = 0; i < pairCount; i++) {
    const cls = CLASSES[i % CLASSES.length];
    const race = allRaces[i % allRaces.length];
    process.stdout.write(`Syncing ${cls}/${race} (${i + 1}/${pairCount})... `);
    try {
      const name = await syncOneCharacter(cls, race, i, legacyPayload);
      createdNames.push(name);
      console.log("done");
    } catch (e) {
      console.log("FAILED");
      console.error(e);
    }
  }

  // ---------------------------------------------------------------------
  // Resolve the test account's user_id from the token, then read back what
  // actually landed in the database.
  // ---------------------------------------------------------------------
  const { data: tokenRow } = await admin.from("user_sync_tokens").select("user_id").eq("token", SYNC_TOKEN!).maybeSingle();
  if (!tokenRow) {
    console.error("\nCould not resolve the test account from SYNC_TOKEN - is it an account-level token (not a per-character one)?");
    process.exit(1);
  }
  const userId = tokenRow.user_id as string;

  const { data: characters } = await admin.from("characters").select("id, name").eq("user_id", userId).in("name", createdNames);
  const characterIds = (characters ?? []).map((c) => c.id as string);

  const { data: achievementRows } = await admin.from("achievements").select("character_id, kind, tier").in("character_id", characterIds);
  const { data: accountRows } = await admin.from("account_achievements").select("kind").eq("user_id", userId);

  const earnedTieredAnywhere = new Set((achievementRows ?? []).filter((r) => r.tier === "Platinum").map((r) => r.kind));
  const earnedFlatAnywhere = new Set((achievementRows ?? []).filter((r) => r.tier === null).map((r) => r.kind));
  const earnedAccountKinds = new Set((accountRows ?? []).map((r) => r.kind));

  console.log("\n=== Character-level TIERED achievements (expect Platinum on at least one synth character) ===");
  for (const kind of TIERED_ACHIEVEMENT_KINDS) {
    const ok = earnedTieredAnywhere.has(kind);
    console.log(`${ok ? "PASS" : "FAIL"}  ${kind}`);
  }

  console.log("\n=== Character-level FLAT achievements fired this run ===");
  for (const kind of ["max_level", "maxed_profession", "renaissance", "legendary_item", "top_pvp_rank", ...PERSONALITY_BADGES.map((b) => b.kind), "level_10", "level_20", "level_30", "level_40", "level_50"]) {
    const ok = earnedFlatAnywhere.has(kind);
    console.log(`${ok ? "PASS" : "FAIL"}  ${kind}`);
  }

  console.log("\n=== Account badges ===");
  const expectedAccountKinds = [
    "full_roster",
    "alliance_completionist",
    "horde_completionist",
    "diplomat",
    "master_of_all_trades",
    "master_merchant",
    "blood_of_the_enemy",
    "apex_predator",
    "pvp_dynasty",
    "legacy_complete",
    "the_completionist",
    "time_lost_in_azeroth",
  ];
  for (const kind of expectedAccountKinds) {
    // legacy_complete can only fire if buildLegacyAchievements() found real
    // reference data to replay (see its own comment) - skip rather than FAIL
    // when there was nothing to test against, so a clean/empty database
    // doesn't look like a broken pipeline.
    if (kind === "legacy_complete" && legacyPayload.length === 0) {
      console.log("SKIP  legacy_complete (no real legacy_achievement_definitions rows to replay yet)");
      continue;
    }
    const ok = earnedAccountKinds.has(kind);
    console.log(`${ok ? "PASS" : "FAIL"}  ${kind}`);
  }

  console.log(
    [
      "",
      `Clean-up reminder: delete the throwaway account (or at least the`,
      `${createdNames.length} \"Synth ...\" characters) when you're done. Also run`,
      `DELETE FROM account_legacy_achievements WHERE user_id = '${userId}';`,
      `afterward if legacy_complete was tested above, so this throwaway`,
      `account doesn't keep sitting at "111/111 complete" forever.`,
    ].join("\n")
  );
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
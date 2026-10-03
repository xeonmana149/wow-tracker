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
import { TIER_COUNTERS, tierThresholds, PERSONALITY_BADGES, TIERED_ACHIEVEMENT_KINDS, type TieredAchievementKind } from "../lib/achievements";
import { LEGACY_ACHIEVEMENT_TOTAL, MARATHON_HOURS, ALL_PROFESSIONS } from "../lib/accountAchievements";
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
// (tierThresholds, LEGACY_ACHIEVEMENT_TOTAL, MARATHON_HOURS, etc.), never a
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

function buildLegacyAchievements(): {
  id: number;
  category: string;
  name: string;
  completed: boolean;
  uiPoints: number;
}[] {
  // Every row completed AND every row's ui_points revealed (>0) - the exact
  // "fully scanned, everything that gives points is done" state
  // checkAccountAchievements requires for Legacy Complete (see the
  // 2026-10-03 point-gating fix). Real Legacy Challenge IDs don't matter
  // here - checkAccountAchievements only cares about count/completed/
  // ui_points, not which specific achievement each row is.
  return Array.from({ length: LEGACY_ACHIEVEMENT_TOTAL }, (_, i) => ({
    id: 900000 + i,
    category: "Synthetic",
    name: `Synthetic Legacy Achievement ${i + 1}`,
    completed: true,
    uiPoints: 10,
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

async function syncOneCharacter(cls: string, race: string, index: number, legacyPayload: ReturnType<typeof buildLegacyAchievements>) {
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
      timePlayedSeconds: Math.ceil(MARATHON_HOURS * 1.2) * 3600,
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
  const legacyPayload = buildLegacyAchievements();

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
  for (const kind of ["max_level", "maxed_profession", "renaissance", "legendary_item", ...PERSONALITY_BADGES.map((b) => b.kind), "level_10", "level_20", "level_30", "level_40", "level_50"]) {
    const ok = earnedFlatAnywhere.has(kind);
    console.log(`${ok ? "PASS" : "FAIL"}  ${kind}`);
  }

  console.log("\n=== Account badges ===");
  const expectedAccountKinds = [
    "class_collector",
    "alliance_completionist",
    "horde_completionist",
    "diplomat",
    "master_of_all_trades",
    "tycoon",
    "battle_scarred",
    "apex_predator",
    "legacy_master",
    "completionist",
    "marathon",
  ];
  for (const kind of expectedAccountKinds) {
    const ok = earnedAccountKinds.has(kind);
    console.log(`${ok ? "PASS" : "FAIL"}  ${kind}`);
  }

  console.log(
    [
      "",
      "NOT exercised by this run, needs a different kind of check:",
      "  - top_pvp_rank / pvp_dynasty: now awarded for real (2026-10-03) via",
      "    the addon's scanPvpRankFromUI() + importLogic.ts's TOP_PVP_RANK_CAP",
      "    check, but that requires the addon to have actually scanned the",
      "    in-game PvP rank panel at least once - this synthetic run has no",
      "    way to fake that UI scan, so both stay untested here. Test for",
      "    real: open the Player vs. Player panel in-game on a Rank 14",
      "    character (or wait for one to reach it) and sync.",
      "",
      `Clean-up reminder: delete the throwaway account (or at least the`,
      `${createdNames.length} \"Synth ...\" characters) when you're done.`,
    ].join("\n")
  );
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
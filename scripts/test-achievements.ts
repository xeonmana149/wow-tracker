// Pre-launch achievement/account-badge test harness (2026-10-03).
//
// WHAT THIS IS: an automated test suite that exercises the REAL award
// functions (awardTier, checkAccountAchievements, computeAccountBadgeProgress)
// against a tiny in-memory fake Supabase client - no real database needed.
// It derives every expectation from the SAME exported constants the real
// code uses (TIERED_ACHIEVEMENT_KINDS, ACCOUNT_ACHIEVEMENT_BADGES,
// BLOOD_OF_THE_ENEMY_HONORABLE_KILLS, etc.) rather than hardcoding a second copy
// of the numbers - so if a threshold or a kind ever changes, this test file
// never needs editing to match, and it can never silently drift out of sync
// with the thing it's testing (the exact kind of drift that caused the
// Sell Price bug earlier - a fix shipped but nothing caught the mismatch).
//
// WHAT THIS CANNOT COVER: the handful of "flat" achievements that are
// awarded straight out of lib/importLogic.ts on a live sync (max_level,
// maxed_profession, renaissance, maxed_legacy, founding_member, the
// personality badges, level milestones) aren't unit-tested here, because
// triggering them for real means replaying a full addon sync payload
// through applyImport(), not just calling one small exported function.
// Section 4 below is a cheap "wiring" check instead (every kind that's
// DEFINED is fully wired up - has a message, a name, a family, an icon -
// which is exactly the category of bug this project has actually hit this
// session: a rename or a new kind that's missing from one of the lookup
// tables). For the sync-triggered achievements themselves, the real test is
// a staging dry run - see the bottom of this file's output for exactly
// what to do.
//
// HOW TO RUN (from your actual project root, not this delivery folder):
//   npx tsx scripts/test-achievements.ts
// (installs nothing permanent - tsx runs TypeScript directly. If you'd
// rather not use npx, `npm install -D tsx` once and reuse it.)
//
// Exits with code 1 if anything fails, so this can also run in CI /
// pre-deploy, not just by hand.

import {
  TIERED_ACHIEVEMENT_KINDS,
  tierThresholds,
  tierLabel,
  tierDescription,
  tierFamily,
  awardTier,
  awardAchievement,
  ACHIEVEMENT_MESSAGE,
  PERSONALITY_BADGES,
  LEVEL_MILESTONES,
  type TieredAchievementKind,
  type AchievementTier,
} from "../lib/achievements";
import { ACHIEVEMENT_BADGES } from "../lib/achievementBadges";
import { FLAT_ACHIEVEMENT_NAME, FLAT_ACHIEVEMENT_FAMILY } from "../lib/achievementCategories";
import {
  checkAccountAchievements,
  computeAccountBadgeProgress,
  ACCOUNT_ACHIEVEMENT_BADGES,
  ACCOUNT_ACHIEVEMENT_LOCAL_ICONS,
  MAX_CHARACTER_LEVEL,
  ALL_PROFESSIONS,
  BLOOD_OF_THE_ENEMY_HONORABLE_KILLS,
  MASTER_MERCHANT_GOLD,
  PVP_DYNASTY_THRESHOLD,
  APEX_PREDATOR_BOSS_KILLS,
  TIME_LOST_IN_AZEROTH_HOURS,
  LEGACY_ACHIEVEMENT_TOTAL,
  type AccountAchievementKind,
} from "../lib/accountAchievements";
import { CLASSES, RACE_FACTION } from "../lib/options";

// ---------------------------------------------------------------------------
// Tiny fake Supabase client - supports exactly the chain shapes this
// codebase actually uses (.from().select().eq()/.in()/.maybeSingle(),
// .from().upsert(opts).select()), backed by plain in-memory arrays. Good
// enough to drive the real award functions unmodified.
// ---------------------------------------------------------------------------
type Row = Record<string, any>;

class QueryBuilder implements PromiseLike<{ data: any; error: null }> {
  private filters: ((r: Row) => boolean)[] = [];
  private mode: "select" | "upsert" = "select";
  private upsertPayload?: Row[];
  private upsertOpts?: { onConflict?: string; ignoreDuplicates?: boolean };

  constructor(private rows: Row[]) {}

  select(_cols?: string) {
    return this;
  }
  eq(key: string, val: any) {
    this.filters.push((r) => r[key] === val);
    return this;
  }
  in(key: string, vals: any[]) {
    this.filters.push((r) => vals.includes(r[key]));
    return this;
  }
  upsert(payload: Row | Row[], opts?: { onConflict?: string; ignoreDuplicates?: boolean }) {
    this.mode = "upsert";
    this.upsertPayload = Array.isArray(payload) ? payload : [payload];
    this.upsertOpts = opts;
    return this;
  }
  maybeSingle() {
    const rows = this.resolve();
    return Promise.resolve({ data: rows[0] ?? null, error: null });
  }
  private resolve(): Row[] {
    if (this.mode === "upsert") {
      const keys = (this.upsertOpts?.onConflict ?? "").split(",").map((s) => s.trim()).filter(Boolean);
      const out: Row[] = [];
      for (const p of this.upsertPayload!) {
        const idx = keys.length ? this.rows.findIndex((r) => keys.every((k) => r[k] === p[k])) : -1;
        if (idx >= 0) {
          if (this.upsertOpts?.ignoreDuplicates) continue; // conflict + ignoreDuplicates -> no row back
          this.rows[idx] = { ...this.rows[idx], ...p };
          out.push(this.rows[idx]);
        } else {
          this.rows.push(p);
          out.push(p);
        }
      }
      return out;
    }
    return this.rows.filter((r) => this.filters.every((f) => f(r)));
  }
  then<T1 = any, T2 = never>(
    onfulfilled?: ((value: { data: any; error: null }) => T1 | PromiseLike<T1>) | null,
    onrejected?: any
  ): Promise<T1 | T2> {
    return Promise.resolve({ data: this.resolve(), error: null }).then(onfulfilled as any, onrejected);
  }
}

class FakeSupabase {
  private tables = new Map<string, Row[]>();
  from(name: string) {
    if (!this.tables.has(name)) this.tables.set(name, []);
    return new QueryBuilder(this.tables.get(name)!);
  }
  seed(name: string, rows: Row[]) {
    this.tables.set(name, [...rows]);
  }
  // cast to the real SupabaseClient type at call sites - the functions under
  // test only ever touch the handful of methods implemented above.
  asClient() {
    return this as unknown as import("@supabase/supabase-js").SupabaseClient;
  }
}

// ---------------------------------------------------------------------------
// Minimal test runner
// ---------------------------------------------------------------------------
let pass = 0;
let fail = 0;
const failures: string[] = [];

function check(name: string, cond: boolean, detail?: string) {
  if (cond) {
    pass++;
  } else {
    fail++;
    failures.push(detail ? `${name} - ${detail}` : name);
  }
}

async function run() {
  // =========================================================================
  // SECTION 1 - tiered character achievements: every threshold, every kind.
  // One value below each threshold must NOT reach that tier; the exact
  // threshold value MUST reach it; and a tier can never be lost once earned
  // (awardTier is a snapshot-each-sync check, so a later low value must not
  // downgrade someone who already hit a higher tier).
  // =========================================================================
  for (const kind of TIERED_ACHIEVEMENT_KINDS as TieredAchievementKind[]) {
    const thresholds = tierThresholds(kind); // Copper -> Platinum order
    check(`[wiring] ${kind} has 4 increasing thresholds`,
      thresholds.length === 4 && thresholds.every((t, i) => i === 0 || t.value > thresholds[i - 1].value),
      JSON.stringify(thresholds));

    for (const { tier, value } of thresholds) {
      const belowClient = new FakeSupabase();
      const below = await awardTier(belowClient.asClient(), "char-below", kind, value - 1);
      check(`${kind}/${tier}: value ${value - 1} (one under) does NOT award ${tier}`,
        below !== tier);

      const atClient = new FakeSupabase();
      const at = await awardTier(atClient.asClient(), "char-at", kind, value);
      check(`${kind}/${tier}: value ${value} (exact threshold) DOES award ${tier}`,
        at === tier);
    }

    // No-downgrade: reach Platinum, then re-check with 0 - must stay Platinum
    // (awardTier returns null when it doesn't IMPROVE the tier, which is the
    // correct "nothing new to report" signal - the row itself is untouched).
    const platinum = thresholds[thresholds.length - 1];
    const downgradeClient = new FakeSupabase();
    await awardTier(downgradeClient.asClient(), "char-down", kind, platinum.value);
    const second = await awardTier(downgradeClient.asClient(), "char-down", kind, 0);
    const stored = await downgradeClient
      .from("achievements")
      .select("tier")
      .eq("character_id", "char-down")
      .eq("kind", kind)
      .maybeSingle();
    check(`${kind}: dropping back to 0 after Platinum does not downgrade the stored tier`,
      second === null && stored.data?.tier === "Platinum");
  }

  // =========================================================================
  // SECTION 2 - account badges: every kind, via the REAL checkAccountAchievements
  // (so the fetch shape, the filters, and the gating logic are all exercised
  // exactly as they run in production, not re-implemented here).
  // =========================================================================
  const CHAR_FIELDS = (over: Partial<Row> = {}): Row => ({
    id: over.id ?? "c1",
    class: over.class ?? CLASSES[0],
    race: over.race ?? Object.keys(RACE_FACTION)[0],
    level: over.level ?? 1,
    money_copper: over.money_copper ?? 0,
    time_played_hours: over.time_played_hours ?? 0,
  });

  async function awardedKinds(seed: {
    characters: Row[];
    statRows?: Row[];
    professionRows?: Row[];
    pvpTopRankCharacterIds?: string[];
    legacyRows?: Row[];
  }): Promise<Set<AccountAchievementKind>> {
    const db = new FakeSupabase();
    db.seed("characters", seed.characters);
    db.seed("profiles", [{ id: "u1", display_name: "Tester" }]);
    db.seed(
      "achievements",
      (seed.pvpTopRankCharacterIds ?? []).map((cid) => ({ character_id: cid, kind: "top_pvp_rank" }))
    );
    db.seed("character_statistics", seed.statRows ?? []);
    db.seed("character_professions", seed.professionRows ?? []);
    db.seed("account_legacy_achievements", (seed.legacyRows ?? []).map((r) => ({ user_id: "u1", ...r })));
    // characters.user_id filter - checkAccountAchievements queries
    // .eq("user_id", userId), so every seeded character needs it set.
    for (const c of seed.characters) c.user_id = c.user_id ?? "u1";

    const messages = await checkAccountAchievements(db.asClient(), "u1");
    // Reverse-map messages back to kinds isn't reliable (free text), so
    // instead read back what actually got awarded.
    const awarded = await db.from("account_achievements").select("kind");
    void messages;
    return new Set((awarded.data as Row[]).map((r) => r.kind));
  }

  function maxedChar(id: string, cls: string, race: string): Row {
    return CHAR_FIELDS({ id, class: cls, race, level: MAX_CHARACTER_LEVEL });
  }

  // --- full_roster (Full Roster) --------------------------------------
  {
    const allButOne = CLASSES.slice(1).map((c, i) => maxedChar(`cc${i}`, c, Object.keys(RACE_FACTION)[0]));
    const short = await awardedKinds({ characters: allButOne });
    check("full_roster: one class short does NOT award", !short.has("full_roster"));

    const all = CLASSES.map((c, i) => maxedChar(`cc${i}`, c, Object.keys(RACE_FACTION)[0]));
    const full = await awardedKinds({ characters: all });
    check("full_roster: every class at level cap DOES award", full.has("full_roster"));

    // Regression guard for the exact "Big Family" loophole this replaced -
    // a pile of throwaway LOW-LEVEL alts covering every class must NOT
    // award, since none of them are actually maxed.
    const throwawayAlts = CLASSES.map((c, i) => CHAR_FIELDS({ id: `alt${i}`, class: c, level: 1 }));
    const gamed = await awardedKinds({ characters: throwawayAlts });
    check("full_roster: a roster of level-1 alts (no real play) does NOT award", !gamed.has("full_roster"));
  }

  // --- alliance_completionist / horde_completionist / diplomat -----------
  {
    const allRaces = Object.keys(RACE_FACTION);
    const allianceRaces = allRaces.filter((r) => RACE_FACTION[r] === "Alliance");
    const hordeRaces = allRaces.filter((r) => RACE_FACTION[r] === "Horde");

    const allianceOnly = allianceRaces.map((r, i) => maxedChar(`al${i}`, CLASSES[0], r));
    const resAlliance = await awardedKinds({ characters: allianceOnly });
    check("alliance_completionist: every Alliance race maxed DOES award", resAlliance.has("alliance_completionist"));
    check("horde_completionist: Alliance-only roster does NOT award Horde side", !resAlliance.has("horde_completionist"));
    check("diplomat: Alliance-only roster does NOT award (needs both factions)", !resAlliance.has("diplomat"));

    const both = [...allianceRaces, ...hordeRaces].map((r, i) => maxedChar(`bo${i}`, CLASSES[0], r));
    const resBoth = await awardedKinds({ characters: both });
    check("diplomat: every race on both factions maxed DOES award", resBoth.has("diplomat"));
  }

  // --- master_of_all_trades -----------------------------------------------
  {
    const char = [CHAR_FIELDS({ id: "p1", level: MAX_CHARACTER_LEVEL })];
    const allButOneProf = ALL_PROFESSIONS.slice(1).map((p) => ({ character_id: "p1", profession: p, skill: 300, recipes: [] }));
    const short = await awardedKinds({ characters: char, professionRows: allButOneProf });
    check("master_of_all_trades: one profession short of maxed does NOT award", !short.has("master_of_all_trades"));

    const allProf = ALL_PROFESSIONS.map((p) => ({ character_id: "p1", profession: p, skill: 300, recipes: [] }));
    const full = await awardedKinds({ characters: char, professionRows: allProf });
    check("master_of_all_trades: every profession maxed by someone DOES award", full.has("master_of_all_trades"));
  }

  // --- master_merchant (Master Merchant) --------------------------------------------
  {
    const below = await awardedKinds({ characters: [CHAR_FIELDS({ money_copper: (MASTER_MERCHANT_GOLD - 1) * 10000 })] });
    check(`master_merchant: ${MASTER_MERCHANT_GOLD - 1}g does NOT award`, !below.has("master_merchant"));
    const at = await awardedKinds({ characters: [CHAR_FIELDS({ money_copper: MASTER_MERCHANT_GOLD * 10000 })] });
    check(`master_merchant: exactly ${MASTER_MERCHANT_GOLD}g (combined) DOES award`, at.has("master_merchant"));
    // combined across characters, not any single one
    const combined = await awardedKinds({
      characters: [
        CHAR_FIELDS({ id: "g1", money_copper: (MASTER_MERCHANT_GOLD / 2) * 10000 }),
        CHAR_FIELDS({ id: "g2", money_copper: (MASTER_MERCHANT_GOLD / 2) * 10000 }),
      ],
    });
    check("master_merchant: combined gold across two characters DOES award", combined.has("master_merchant"));
  }

  // --- time_lost_in_azeroth (Time Lost in Azeroth) -------------------------------------
  {
    const below = await awardedKinds({ characters: [CHAR_FIELDS({ time_played_hours: TIME_LOST_IN_AZEROTH_HOURS - 1 })] });
    check(`time_lost_in_azeroth: ${TIME_LOST_IN_AZEROTH_HOURS - 1}h does NOT award`, !below.has("time_lost_in_azeroth"));
    const at = await awardedKinds({ characters: [CHAR_FIELDS({ time_played_hours: TIME_LOST_IN_AZEROTH_HOURS })] });
    check(`time_lost_in_azeroth: exactly ${TIME_LOST_IN_AZEROTH_HOURS}h DOES award`, at.has("time_lost_in_azeroth"));
  }

  // --- blood_of_the_enemy (Blood of the Enemy) ---------------------------------
  {
    const statsFor = (n: number) => [{ character_id: "c1", category: "Honorable Kills", name: "Total Honorable Kills", value: String(n) }];
    const below = await awardedKinds({ characters: [CHAR_FIELDS()], statRows: statsFor(BLOOD_OF_THE_ENEMY_HONORABLE_KILLS - 1) });
    check(`blood_of_the_enemy: ${BLOOD_OF_THE_ENEMY_HONORABLE_KILLS - 1} Honorable Kills does NOT award`, !below.has("blood_of_the_enemy"));
    const at = await awardedKinds({ characters: [CHAR_FIELDS()], statRows: statsFor(BLOOD_OF_THE_ENEMY_HONORABLE_KILLS) });
    check(`blood_of_the_enemy: exactly ${BLOOD_OF_THE_ENEMY_HONORABLE_KILLS} Honorable Kills DOES award`, at.has("blood_of_the_enemy"));
  }

  // --- apex_predator ---------------------------------------------------------
  {
    const statsFor = (n: number) => [{ character_id: "c1", category: "Boss Kills", name: "Some Boss", value: String(n) }];
    const below = await awardedKinds({ characters: [CHAR_FIELDS()], statRows: statsFor(APEX_PREDATOR_BOSS_KILLS - 1) });
    check(`apex_predator: ${APEX_PREDATOR_BOSS_KILLS - 1} boss kills does NOT award`, !below.has("apex_predator"));
    const at = await awardedKinds({ characters: [CHAR_FIELDS()], statRows: statsFor(APEX_PREDATOR_BOSS_KILLS) });
    check(`apex_predator: exactly ${APEX_PREDATOR_BOSS_KILLS} boss kills DOES award`, at.has("apex_predator"));
    // combined across multiple boss-kill rows, same as production
    const multi = await awardedKinds({
      characters: [CHAR_FIELDS()],
      statRows: [
        { character_id: "c1", category: "Boss Kills", name: "Boss A", value: String(Math.ceil(APEX_PREDATOR_BOSS_KILLS / 2)) },
        { character_id: "c1", category: "Boss Kills", name: "Boss B", value: String(Math.ceil(APEX_PREDATOR_BOSS_KILLS / 2)) },
      ],
    });
    check("apex_predator: boss kills summed across multiple boss rows DOES award", multi.has("apex_predator"));
  }

  // --- pvp_dynasty -----------------------------------------------------------
  {
    const ids = Array.from({ length: PVP_DYNASTY_THRESHOLD - 1 }, (_, i) => `pv${i}`);
    const below = await awardedKinds({
      characters: ids.map((id) => CHAR_FIELDS({ id })),
      pvpTopRankCharacterIds: ids,
    });
    check(`pvp_dynasty: ${PVP_DYNASTY_THRESHOLD - 1} top-rank characters does NOT award`, !below.has("pvp_dynasty"));

    const idsFull = Array.from({ length: PVP_DYNASTY_THRESHOLD }, (_, i) => `pv${i}`);
    const at = await awardedKinds({
      characters: idsFull.map((id) => CHAR_FIELDS({ id })),
      pvpTopRankCharacterIds: idsFull,
    });
    check(`pvp_dynasty: exactly ${PVP_DYNASTY_THRESHOLD} top-rank characters DOES award`, at.has("pvp_dynasty"));
  }

  // --- legacy_complete -----------------------------------------------------
  {
    const rowsOf = (n: number, completed: boolean) =>
      Array.from({ length: n }, (_, i) => ({ achievement_id: i, completed }));

    // A: not fully scanned yet (fewer rows than LEGACY_ACHIEVEMENT_TOTAL),
    // every seen row completed - shouldn't fire early just because
    // everything seen so far happens to be done.
    const notFullyScanned = await awardedKinds({
      characters: [CHAR_FIELDS()],
      legacyRows: rowsOf(LEGACY_ACHIEVEMENT_TOTAL - 1, true),
    });
    check("legacy_complete: fully synced but under LEGACY_ACHIEVEMENT_TOTAL rows does NOT award", !notFullyScanned.has("legacy_complete"));

    // B: fully scanned, but not every row completed.
    const scannedNotComplete = await awardedKinds({
      characters: [CHAR_FIELDS()],
      legacyRows: [
        ...rowsOf(LEGACY_ACHIEVEMENT_TOTAL - 1, true),
        { achievement_id: LEGACY_ACHIEVEMENT_TOTAL - 1, completed: false },
      ],
    });
    check("legacy_complete: fully scanned with one incomplete row does NOT award", !scannedNotComplete.has("legacy_complete"));

    // C: no legacy rows synced at all.
    const noneSynced = await awardedKinds({ characters: [CHAR_FIELDS()] });
    check("legacy_complete: no legacy rows synced does NOT award", !noneSynced.has("legacy_complete"));

    // D: fully scanned AND every row completed.
    const fullyComplete = await awardedKinds({
      characters: [CHAR_FIELDS()],
      legacyRows: rowsOf(LEGACY_ACHIEVEMENT_TOTAL, true),
    });
    check("legacy_complete: every row synced and completed DOES award", fullyComplete.has("legacy_complete"));
  }

  // =========================================================================
  // SECTION 3 - progress bars never show 100%+ for a badge that isn't
  // actually awardable yet.
  // =========================================================================
  {
    const chars = [CHAR_FIELDS({ level: 30 })]; // deliberately short of everything
    const progress = computeAccountBadgeProgress({
      chars: chars.map((c) => ({ level: c.level, class: c.class, race: c.race, money_copper: c.money_copper, time_played_hours: c.time_played_hours })),
      professionRows: [],
      statRows: [],
      pvpTopRankCharacterCount: 0,
      earnedAchievementCount: 0,
      totalAchievementCount: 10,
      legacyRows: [{ completed: true }, { completed: false }],
    });
    for (const [kind, p] of Object.entries(progress)) {
      check(`progress.${kind}: value (${p!.value}) never exceeds target (${p!.target})`, p!.value <= p!.target);
    }
  }

  // =========================================================================
  // SECTION 4 - wiring/consistency checks across every lookup table. This is
  // the cheap, high-value check: it catches a kind that's missing from one
  // table after a rename or an addition (exactly the bug class this project
  // has hit more than once this session - a badge renamed in one place but
  // not another).
  // =========================================================================
  // (ACCOUNT_ACHIEVEMENT_MESSAGE isn't exported from accountAchievements.ts,
  // so it can't be checked directly here - but every award path in Section 2
  // above already calls it for real via tryAward(), so a missing/broken
  // entry there would show up as a thrown error in those tests instead.)
  const accountKinds = Object.keys(ACCOUNT_ACHIEVEMENT_BADGES) as AccountAchievementKind[];
  for (const kind of accountKinds) {
    check(`[wiring] ${kind} has a badge label`, !!ACCOUNT_ACHIEVEMENT_BADGES[kind]?.label);
  }
  for (const kind of accountKinds) {
    const slug = ACCOUNT_ACHIEVEMENT_LOCAL_ICONS[kind];
    if (slug) {
      check(`[wiring] ${kind}'s local icon slug "${slug}" is lowercase-hyphen only (case-sensitive filesystems)`,
        /^[a-z0-9-]+$/.test(slug));
    }
  }

  const flatKinds = Object.keys(ACHIEVEMENT_BADGES) as (keyof typeof ACHIEVEMENT_BADGES)[];
  for (const kind of flatKinds) {
    check(`[wiring] flat achievement ${kind} has a name`, !!FLAT_ACHIEVEMENT_NAME[kind]);
    check(`[wiring] flat achievement ${kind} has a family`, !!FLAT_ACHIEVEMENT_FAMILY[kind]);
    check(`[wiring] flat achievement ${kind} has an activity message`, typeof ACHIEVEMENT_MESSAGE[kind] === "function");
  }
  for (const kind of TIERED_ACHIEVEMENT_KINDS) {
    check(`[wiring] tiered achievement ${kind} has a label`, typeof tierLabel(kind) === "string" && tierLabel(kind).length > 0);
    check(`[wiring] tiered achievement ${kind} has a description`, typeof tierDescription(kind) === "string" && tierDescription(kind).length > 0);
    check(`[wiring] tiered achievement ${kind} has a family`, !!tierFamily(kind));
  }
  for (const badge of PERSONALITY_BADGES) {
    check(`[wiring] personality badge ${badge.kind} has an activity message`, typeof ACHIEVEMENT_MESSAGE[badge.kind] === "function");
  }
  for (const m of LEVEL_MILESTONES) {
    check(`[wiring] level milestone ${m.kind} has an activity message`, typeof ACHIEVEMENT_MESSAGE[m.kind] === "function");
  }

  // =========================================================================
  // Report
  // =========================================================================
  console.log(`\n${pass} passed, ${fail} failed.\n`);
  if (failures.length) {
    console.log("FAILURES:");
    for (const f of failures) console.log(`  - ${f}`);
    console.log("");
  }

  console.log(
    [
      "NOT covered by this script (needs a live/staging dry run instead):",
      "  - The flat achievements awarded directly in importLogic.ts on sync",
      "    (max_level, maxed_profession, renaissance, maxed_legacy,",
      "    founding_member, the personality badges, level milestones) -",
      "    these need a real (or synthetic) addon sync payload replayed",
      "    through applyImport() to actually trigger, not just one exported",
      "    function. Section 4 above only checks that every one of them is",
      "    wired into every lookup table it needs to be in.",
      "  - Whether the addon's ACTUAL stat category/name strings in-game",
      "    still match TIER_COUNTERS' selectors (e.g. this session already",
      "    found 'Boss Kills' mixes dungeon+raid on this server) - that's",
      "    only verifiable against a real character_statistics dump from",
      "    the live server, not something a unit test can know in advance.",
      "  - Recommended pre-launch step: create one or two throwaway test",
      "    accounts, run the addon through a real play session (or hand-",
      "    edit a sync payload to simulate one), and watch every achievement",
      "    /badge you expect to fire actually fire on the live site once.",
    ].join("\n")
  );

  process.exit(fail > 0 ? 1 : 0);
}

run();
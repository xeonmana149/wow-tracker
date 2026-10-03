import type { SupabaseClient } from "@supabase/supabase-js";
import { CLASSES, RACE_FACTION } from "./options";
import { PRIMARY_PROFESSIONS, wowIconUrl } from "./icons";
import { buildAchievementItems } from "../app/achievementBoard";
import { MAX_CHARACTER_LEVEL, MAX_PROFESSION_SKILL, type AchievementTier } from "./achievements";

type AchievementRowDB = { character_id: string; kind: string; tier: AchievementTier | null; earned_at: string | null };

// Account-wide achievements - these look across ALL of a user's
// characters at once, unlike the per-character achievements in
// achievements.ts. Each is a one-off yes/no per account.
export type AccountAchievementKind =
  | "class_collector"
  | "alliance_completionist"
  | "horde_completionist"
  | "diplomat"
  | "master_of_all_trades"
  | "tycoon"
  // Replaced "big_family" (2026-10-03, "not hard to just make 10
  // characters" - that one only checked chars.length >= 10, so it was
  // free to cash in by rolling throwaway level-1 alts, no actual play
  // required). This instead sums the same "Total Honorable Kills" stat
  // the per-character honorable_kills achievement already tracks (see
  // TIER_COUNTERS in achievements.ts) across every character on the
  // account - real, hard-won PvP effort instead of a roster headcount.
  | "battle_scarred"
  | "pvp_dynasty"
  // Replaced "one_man_army" (2026-10-03) - that one was just 3+ characters
  // at the level cap, no boss-kill requirement despite the name's "army"
  // framing suggesting one. This instead sums the "Boss Kills" category
  // (every individual boss kill stat Blizzard tracks, same categoryOnly
  // selector the per-character boss_kills tiered achievement already uses -
  // see TIER_COUNTERS in achievements.ts) across every character on the
  // account. Originally scoped to raid bosses only, but the addon's actual
  // "Boss Kills" stat list (confirmed against a live scan) is an
  // unfiltered mix of dungeon and raid bosses from this server's own
  // (heavily customized, non-retail) instance roster, with no reliable way
  // to tell which is which from the name alone - Jordan opted to count
  // everything combined instead of guessing wrong on a per-boss list.
  | "apex_predator"
  // 2026-09-30 batch, from the "unlocking icons from achievements"/account-
  // progression brainstorm - Jordan picked these three out of a longer
  // list. A fourth idea ("every faction in the game exalted by someone on
  // the account") got proposed too but isn't buildable yet - the addon only
  // reports a COUNT of exalted factions per character (feeds the existing
  // per-character "Diplomat" achievement), not which specific factions, so
  // there's no way to know if two characters' exalted factions overlap or
  // cover the whole game. Would need new addon-side tracking (looping
  // GetFactionInfo, capturing names) before this can be built for real.
  //
  // "legacy_master" ("Legacy Complete") removed (2026-10-03, Jordan's call) -
  // existed from 2026-09-30 but never actually earned by anyone, so this is
  // a clean removal with no earned rows to worry about. The
  // account_achievements_kind_check constraint still allows the string (see
  // sql/items-migration-30.sql's own comment on why old kinds are left in
  // that list rather than torn out), so leaving it there is harmless.
  | "completionist"
  | "marathon";

// Icon names are real WoW icon names, resolved to actual game art through
// wowIconUrl() (see lib/icons.ts) by whatever renders these - AccountBadges
// for the site, or the badge tester page directly.
export const ACCOUNT_ACHIEVEMENT_BADGES: Record<
  AccountAchievementKind,
  { icon: string; label: string }
> = {
  // Display name "Full Roster" (2026-10-03, renamed from "Class Collector")
  // - the `kind` key stays class_collector since that's what's actually
  // stored in account_achievements rows; only the label shown on the site
  // changes.
  class_collector: {
    icon: "achievement_general",
    label: "Full Roster - A level-60 character of every class.",
  },
  alliance_completionist: {
    icon: "inv_bannerpvp_02",
    label: "Alliance Completionist - A level-60 character of every Alliance race.",
  },
  horde_completionist: {
    icon: "inv_bannerpvp_01",
    label: "Horde Completionist - A level-60 character of every Horde race.",
  },
  diplomat: {
    icon: "achievement_reputation_01",
    label: "Diplomat - A maxed character of every race, on both factions.",
  },
  master_of_all_trades: {
    icon: "trade_engineering",
    label: "Master of All Trades - Every profession maxed by someone on the account.",
  },
  // Display name "Master Merchant" (2026-10-03, renamed from "Tycoon").
  tycoon: {
    icon: "inv_misc_coin_06",
    label: "Master Merchant - 10,000 gold or more, combined across your characters.",
  },
  // Display name "Blood of the Enemy" (2026-10-03, renamed from
  // "Battle-Scarred").
  battle_scarred: {
    icon: "achievement_pvp_h_08",
    label: "Blood of the Enemy - 1,000 or more combined Honorable Kills across your characters.",
  },
  pvp_dynasty: {
    icon: "inv_jewelry_ring_03",
    label: "PvP Dynasty - Two or more characters at the top PvP rank.",
  },
  apex_predator: {
    icon: "inv_misc_head_dragon_01",
    label: "Apex Predator - 1,000 or more combined boss kills across your characters.",
  },
  completionist: {
    icon: "inv_misc_trophy_01",
    label: "The Completionist - Every character achievement earned by someone on the account.",
  },
  // Display name "Time Lost in Azeroth" (2026-10-03, renamed from
  // "The Marathon").
  marathon: {
    icon: "inv_misc_pocketwatch_01",
    label: "Time Lost in Azeroth - 1,000 or more hours played, combined across all characters.",
  },
};

// Local custom art for account badges (2026-09-30, filled out to cover
// every badge 2026-10-03) - same idea as FLAT_LOCAL_ICONS/TIERED_LOCAL_ICONS
// in lib/achievementBadges.ts: a badge with an entry here shows Jordan's own
// art from /public/account-badge-icons/<slug>.png instead of its
// ACCOUNT_ACHIEVEMENT_BADGES.icon CDN fallback. Every account badge now has
// its own art, matching the current display names (class_collector's file
// is "full-roster.png" for "Full Roster", tycoon's is "master-merchant.png"
// for "Master Merchant", etc.) - kept as a Partial type rather than a plain
// Record so a future new kind added without art yet doesn't need a
// placeholder entry here, it'll just fall back to its CDN icon until one
// exists.
export const ACCOUNT_ACHIEVEMENT_LOCAL_ICONS: Partial<Record<AccountAchievementKind, string>> = {
  // Display name "Full Roster" - filename matches the rename, not the kind.
  class_collector: "full-roster",
  alliance_completionist: "alliance-completionist",
  horde_completionist: "horde-completionist",
  diplomat: "diplomat",
  master_of_all_trades: "master-of-all-trades",
  // Display name "Master Merchant" - filename matches the rename.
  tycoon: "master-merchant",
  // Display name "Blood of the Enemy" - filename matches the rename.
  battle_scarred: "blood-of-the-enemy",
  pvp_dynasty: "pvp-dynasty",
  apex_predator: "apex-predator",
  // Display name "The Completionist".
  completionist: "the-completionist",
  // Display name "Time Lost in Azeroth" - filename matches the rename.
  marathon: "time-lost-in-azeroth",
};

export function localAccountBadgeIconSrc(slug: string) {
  return `/account-badge-icons/${slug}.png`;
}

// Resolves a badge's actual icon URL - local art if it has any, otherwise
// falls back to the CDN icon in ACCOUNT_ACHIEVEMENT_BADGES. Callers (e.g.
// AccountView.tsx) should use this instead of reaching into
// ACCOUNT_ACHIEVEMENT_BADGES[kind].icon + wowIconUrl() directly, so a badge
// getting local art later doesn't need a second place updated.
export function accountBadgeIconSrc(kind: AccountAchievementKind): string {
  const slug = ACCOUNT_ACHIEVEMENT_LOCAL_ICONS[kind];
  if (slug) return localAccountBadgeIconSrc(slug);
  return wowIconUrl(ACCOUNT_ACHIEVEMENT_BADGES[kind].icon);
}

const ACCOUNT_ACHIEVEMENT_MESSAGE: Record<AccountAchievementKind, (name: string) => string> = {
  class_collector: (name) => `${name} has a level-60 character of every class - Full Roster!`,
  alliance_completionist: (name) => `${name} has maxed a character of every Alliance race!`,
  horde_completionist: (name) => `${name} has maxed a character of every Horde race!`,
  diplomat: (name) => `${name} has maxed a character of every race, on both factions!`,
  master_of_all_trades: (name) => `${name}'s account has maxed every profession!`,
  tycoon: (name) => `${name} has amassed 10,000 gold across their characters - Master Merchant!`,
  battle_scarred: (name) => `${name} has racked up 1,000 or more combined Honorable Kills - Blood of the Enemy!`,
  pvp_dynasty: (name) => `${name} has two or more characters at the top PvP rank!`,
  apex_predator: (name) => `${name} has racked up 1,000 or more combined boss kills - Apex Predator!`,
  completionist: (name) => `${name}'s account has earned every character achievement - The Completionist!`,
  marathon: (name) => `${name} has played 1,000 or more hours, combined across their characters - Time Lost in Azeroth!`,
};

// Exported from here down (2026-10-03, "do that similar thing for all
// account badges that are trackable") - computeAccountBadgeProgress below
// needs the exact same numbers checkAccountAchievements awards against, so
// a progress bar can never show "100%" on a badge that isn't actually
// earned yet (or vice versa). Single source of truth, same reasoning as
// TIER_COUNTERS being shared between the sync route and the leaderboards
// page.
// MAX_CHARACTER_LEVEL/MAX_SKILL now come from ./achievements (2026-10-03,
// centralized so this stays in lockstep with achievementBoard.ts's display
// logic and importLogic.ts's award logic - see that file's comment). Kept
// re-exported under its original name below so scripts/test-achievements.ts
// and anything else importing MAX_CHARACTER_LEVEL from here specifically
// doesn't need updating.
export { MAX_CHARACTER_LEVEL };
const MAX_SKILL = MAX_PROFESSION_SKILL;
const SECONDARY_PROFESSIONS = ["First Aid", "Cooking", "Fishing"];
export const ALL_PROFESSIONS = [...PRIMARY_PROFESSIONS, ...SECONDARY_PROFESSIONS];
// 1,000 combined Honorable Kills across every character on the account -
// same "Honorable Kills"/"Total Honorable Kills" stat the per-character
// honorable_kills achievement already sums (see TIER_COUNTERS in
// achievements.ts), just totalled account-wide instead of per-character.
export const BATTLE_SCARRED_HONORABLE_KILLS = 1000;
export const TYCOON_GOLD = 10000;
export const PVP_DYNASTY_THRESHOLD = 2;
// 1,000 combined boss kills (dungeon + raid together - see the
// AccountAchievementKind comment on apex_predator for why this isn't
// split by instance type) across every character on the account.
export const APEX_PREDATOR_BOSS_KILLS = 1000;
// Legacy Challenges total (2026-09-27, confirmed in achievementBoard.ts's
// buildLegacyAchievementItems comments) - the addon reports every known
// Legacy Challenge achievement's state on each sync (not just completed
// ones), so a fully-synced account should have exactly this many rows in
// account_legacy_achievements. If Blizzard/the server ever adds more, bump
// this - a stale-low number would let Legacy Complete fire early.
export const LEGACY_ACHIEVEMENT_TOTAL = 111;
// Starting estimate, not tuned against real playtime data yet - easy to
// retune later, this is just one number.
export const MARATHON_HOURS = 1000;

async function award(
  supabase: SupabaseClient,
  userId: string,
  kind: AccountAchievementKind
): Promise<boolean> {
  const { data, error } = await supabase
    .from("account_achievements")
    .upsert({ user_id: userId, kind }, { onConflict: "user_id,kind", ignoreDuplicates: true })
    .select("kind");
  if (error) return false;
  return (data?.length ?? 0) > 0;
}

// Re-evaluates every account-wide achievement for this user from scratch
// and awards any that are newly met, returning one activity-feed-ready
// message per achievement earned by THIS call. Safe to call on every
// sync - each award is itself idempotent (a unique user+kind constraint
// plus ignoreDuplicates), and this only ever adds badges, never removes
// one even if the account later dips below the bar again (spending gold
// below 10,000 doesn't take Master Merchant away).
export async function checkAccountAchievements(
  supabase: SupabaseClient,
  userId: string
): Promise<string[]> {
  const { data: characters } = await supabase
    .from("characters")
    .select("id, class, race, level, money_copper, time_played_hours")
    .eq("user_id", userId);
  const chars = characters ?? [];
  if (chars.length === 0) return [];

  const { data: profile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", userId)
    .maybeSingle();
  const displayName = profile?.display_name ?? "Someone";

  const newMessages: string[] = [];
  async function tryAward(kind: AccountAchievementKind) {
    if (await award(supabase, userId, kind)) {
      newMessages.push(ACCOUNT_ACHIEVEMENT_MESSAGE[kind](displayName));
    }
  }

  const maxedChars = chars.filter((c) => c.level >= MAX_CHARACTER_LEVEL);
  const maxedClasses = new Set(maxedChars.map((c) => c.class));
  if (CLASSES.every((cls) => maxedClasses.has(cls))) {
    await tryAward("class_collector");
  }

  const maxedRaces = new Set(maxedChars.map((c) => c.race));
  const allRaces = Object.keys(RACE_FACTION);
  const allianceRaces = allRaces.filter((r) => RACE_FACTION[r] === "Alliance");
  const hordeRaces = allRaces.filter((r) => RACE_FACTION[r] === "Horde");
  const hasAlliance = allianceRaces.every((r) => maxedRaces.has(r));
  const hasHorde = hordeRaces.every((r) => maxedRaces.has(r));
  if (hasAlliance) await tryAward("alliance_completionist");
  if (hasHorde) await tryAward("horde_completionist");
  if (hasAlliance && hasHorde) await tryAward("diplomat");

  const totalCopper = chars.reduce((sum, c) => sum + (c.money_copper ?? 0), 0);
  if (totalCopper >= TYCOON_GOLD * 10000) {
    await tryAward("tycoon");
  }

  // Time Lost in Azeroth (2026-09-30) - combined played time across every
  // character on the account, no per-character minimum.
  const totalHoursPlayed = chars.reduce((sum, c) => sum + (c.time_played_hours ?? 0), 0);
  if (totalHoursPlayed >= MARATHON_HOURS) {
    await tryAward("marathon");
  }

  const characterIds = chars.map((c) => c.id);

  // Fetched early (not just where buildAchievementItems needs it further
  // down) so Blood of the Enemy's Honorable Kills sum can reuse the exact same
  // rows instead of a second character_statistics query.
  const [{ data: achievementRows }, { data: statRows }] = await Promise.all([
    supabase.from("achievements").select("character_id, kind, tier, earned_at").in("character_id", characterIds),
    supabase
      .from("character_statistics")
      .select("character_id, category, name, value")
      .in("character_id", characterIds),
  ]);

  // Blood of the Enemy (2026-10-03, replaced "Big Family" - see the
  // AccountAchievementKind comment for why) - sums "Total Honorable Kills"
  // straight off the raw stat rows rather than going through
  // computeCounter(), since that sums per-character while this needs one
  // account-wide total.
  const totalHonorableKills = (statRows ?? [])
    .filter((s) => s.category === "Honorable Kills" && s.name === "Total Honorable Kills")
    .reduce((sum, s) => {
      const n = Number(s.value.replace(/,/g, ""));
      return Number.isFinite(n) ? sum + n : sum;
    }, 0);
  if (totalHonorableKills >= BATTLE_SCARRED_HONORABLE_KILLS) {
    await tryAward("battle_scarred");
  }

  // Apex Predator (2026-10-03, replaced "One-Man Army" - see the
  // AccountAchievementKind comment for why) - sums every "Boss Kills"
  // category row (categoryOnly, same selector the per-character boss_kills
  // tiered achievement uses) across every character, dungeon and raid
  // bosses combined.
  const totalBossKills = (statRows ?? [])
    .filter((s) => s.category === "Boss Kills")
    .reduce((sum, s) => {
      const n = Number(s.value.replace(/,/g, ""));
      return Number.isFinite(n) ? sum + n : sum;
    }, 0);
  if (totalBossKills >= APEX_PREDATOR_BOSS_KILLS) {
    await tryAward("apex_predator");
  }

  // One shared fetch of character_professions - profession/skill feeds
  // Master of All Trades below, recipes feeds The Completionist's
  // buildAchievementItems() call further down, so there's no reason to
  // query this table twice.
  const { data: professionRows } = await supabase
    .from("character_professions")
    .select("character_id, profession, skill, recipes")
    .in("character_id", characterIds);
  const maxedProfessions = new Set(
    (professionRows ?? [])
      .filter((p) => p.skill >= MAX_SKILL)
      .map((p) => p.profession)
  );
  if (ALL_PROFESSIONS.every((p) => maxedProfessions.has(p))) {
    await tryAward("master_of_all_trades");
  }
  const recipesByChar = new Map<string, number>();
  for (const p of professionRows ?? []) {
    const count = Array.isArray(p.recipes) ? p.recipes.length : 0;
    recipesByChar.set(p.character_id, (recipesByChar.get(p.character_id) ?? 0) + count);
  }

  const { data: pvpTopRankRows } = await supabase
    .from("achievements")
    .select("character_id")
    .eq("kind", "top_pvp_rank")
    .in("character_id", characterIds);
  if ((pvpTopRankRows ?? []).length >= PVP_DYNASTY_THRESHOLD) {
    await tryAward("pvp_dynasty");
  }

  // "Legacy Complete" (legacy_master) removed 2026-10-03 - see the
  // AccountAchievementKind comment above.

  // The Completionist (2026-09-30) - every character achievement (the same
  // set the Account Progress bar on the overview page counts) earned by AT
  // LEAST ONE character, account-wide. Mirrors lib/accountView.ts's
  // mergeAccountItems in spirit, but only needs the union of "earned" -
  // no need to track which character/tier "wins" a key the way the actual
  // account overview does, so this stays a simpler pass over the same
  // buildAchievementItems() output every character page already uses.
  // (achievementRows/statRows themselves were already fetched above, for
  // Blood of the Enemy's Honorable Kills sum - reused here as-is.)

  const achByChar = new Map<string, AchievementRowDB[]>();
  for (const a of (achievementRows ?? []) as AchievementRowDB[]) {
    const list = achByChar.get(a.character_id) ?? [];
    list.push(a);
    achByChar.set(a.character_id, list);
  }
  const statsByChar = new Map<string, { category: string; name: string; value: string }[]>();
  for (const s of statRows ?? []) {
    const list = statsByChar.get(s.character_id) ?? [];
    list.push(s);
    statsByChar.set(s.character_id, list);
  }

  const earnedKeys = new Set<string>();
  let totalAchievementCount = 0;
  for (const c of chars) {
    const items = buildAchievementItems({
      achievementRows: achByChar.get(c.id) ?? [],
      statRows: statsByChar.get(c.id) ?? [],
      recipesCount: recipesByChar.get(c.id) ?? 0,
      hoursPlayed: c.time_played_hours ?? 0,
    });
    totalAchievementCount = items.length; // same list shape for every character
    for (const item of items) {
      if (item.earned) earnedKeys.add(item.key);
    }
  }
  if (totalAchievementCount > 0 && earnedKeys.size >= totalAchievementCount) {
    await tryAward("completionist");
  }

  return newMessages;
}

// Account badge progress (2026-10-03, "do that similar thing for all
// account badges that are trackable" - same "116 / 200" + bar treatment
// AchievementShowcase already gives an unearned tiered character
// achievement, just for the one-off account badges instead). Pure/no DB
// access on purpose - callers (loadAccountViewData, which already fetches
// everything below for other reasons) pass in plain data they already
// have, rather than this function re-querying Supabase itself. Every
// threshold here is the exact same exported constant checkAccountAchievements
// awards against, so a badge can never show "complete" progress without
// actually being earned (or the reverse).
//
// Not every badge gets an entry - completionist DOES get a plain
// completed/total too, but "legacy_master" is gone entirely (2026-10-03,
// see the AccountAchievementKind comment), so there's no longer a Legacy
// Challenges fraction computed here at all.
export function computeAccountBadgeProgress({
  chars,
  professionRows,
  statRows,
  pvpTopRankCharacterCount,
  earnedAchievementCount,
  totalAchievementCount,
}: {
  chars: { level: number; class: string; race: string; money_copper: number | null; time_played_hours: number | null }[];
  professionRows: { profession: string; skill: number }[];
  statRows: { category: string; name: string; value: string }[];
  pvpTopRankCharacterCount: number;
  earnedAchievementCount: number;
  totalAchievementCount: number;
}): Partial<Record<AccountAchievementKind, { value: number; target: number }>> {
  const progress: Partial<Record<AccountAchievementKind, { value: number; target: number }>> = {};

  const maxedChars = chars.filter((c) => c.level >= MAX_CHARACTER_LEVEL);
  const maxedClasses = new Set(maxedChars.map((c) => c.class));
  progress.class_collector = { value: maxedClasses.size, target: CLASSES.length };

  const maxedRaces = new Set(maxedChars.map((c) => c.race));
  const allRaces = Object.keys(RACE_FACTION);
  const allianceRaces = allRaces.filter((r) => RACE_FACTION[r] === "Alliance");
  const hordeRaces = allRaces.filter((r) => RACE_FACTION[r] === "Horde");
  progress.alliance_completionist = {
    value: allianceRaces.filter((r) => maxedRaces.has(r)).length,
    target: allianceRaces.length,
  };
  progress.horde_completionist = {
    value: hordeRaces.filter((r) => maxedRaces.has(r)).length,
    target: hordeRaces.length,
  };
  // Diplomat needs BOTH completionists done - every race on either faction
  // maxed, combined into one fraction out of every race in the game.
  progress.diplomat = { value: allRaces.filter((r) => maxedRaces.has(r)).length, target: allRaces.length };

  const maxedProfessions = new Set(professionRows.filter((p) => p.skill >= MAX_SKILL).map((p) => p.profession));
  progress.master_of_all_trades = { value: maxedProfessions.size, target: ALL_PROFESSIONS.length };

  const totalCopper = chars.reduce((sum, c) => sum + (c.money_copper ?? 0), 0);
  progress.tycoon = { value: Math.floor(totalCopper / 10000), target: TYCOON_GOLD };

  const totalHoursPlayed = chars.reduce((sum, c) => sum + (c.time_played_hours ?? 0), 0);
  progress.marathon = { value: Math.round(totalHoursPlayed), target: MARATHON_HOURS };

  progress.pvp_dynasty = { value: pvpTopRankCharacterCount, target: PVP_DYNASTY_THRESHOLD };

  const totalHonorableKills = statRows
    .filter((s) => s.category === "Honorable Kills" && s.name === "Total Honorable Kills")
    .reduce((sum, s) => {
      const n = Number(s.value.replace(/,/g, ""));
      return Number.isFinite(n) ? sum + n : sum;
    }, 0);
  progress.battle_scarred = { value: totalHonorableKills, target: BATTLE_SCARRED_HONORABLE_KILLS };

  const totalBossKills = statRows
    .filter((s) => s.category === "Boss Kills")
    .reduce((sum, s) => {
      const n = Number(s.value.replace(/,/g, ""));
      return Number.isFinite(n) ? sum + n : sum;
    }, 0);
  progress.apex_predator = { value: totalBossKills, target: APEX_PREDATOR_BOSS_KILLS };

  progress.completionist = { value: earnedAchievementCount, target: totalAchievementCount };

  return progress;
}

// Account badge breakdowns (2026-10-03, "if clicked on it shows the info of
// just where the stats are coming from ... Master Merchant could have a
// breakdown of where each amount of gold is coming from each character") -
// one line per character (or per class/race/profession, for the "which
// character covers this slot" badges) showing exactly what's feeding a
// badge's progress. Pure/no DB access, same reasoning as
// computeAccountBadgeProgress above - callers pass in data they already
// fetched. Not every badge gets one: "completionist" would mean listing
// 100+ achievement kinds, which is better served by the per-character
// achievements pages themselves than a cramped popup list, so it's left
// out on purpose.
export type AccountBadgeBreakdownLine = { label: string; value: string };

export function computeAccountBadgeBreakdown({
  chars,
  professionRows,
  statRows,
  achievementRows,
}: {
  chars: {
    id: string;
    name: string;
    level: number;
    class: string;
    race: string;
    money_copper: number | null;
    time_played_hours: number | null;
  }[];
  professionRows: { character_id: string; profession: string; skill: number }[];
  statRows: { character_id: string; category: string; name: string; value: string }[];
  achievementRows: { character_id: string; kind: string }[];
}): Partial<Record<AccountAchievementKind, AccountBadgeBreakdownLine[]>> {
  const breakdown: Partial<Record<AccountAchievementKind, AccountBadgeBreakdownLine[]>> = {};
  const charName = new Map(chars.map((c) => [c.id, c.name]));

  const statSum = (characterId: string, category: string, name: string) =>
    statRows
      .filter((s) => s.character_id === characterId && s.category === category && s.name === name)
      .reduce((sum, s) => {
        const n = Number(s.value.replace(/,/g, ""));
        return Number.isFinite(n) ? sum + n : sum;
      }, 0);

  // Master Merchant (tycoon) - gold per character, highest first. Characters
  // with no gold are left out rather than padding the list with "0g".
  breakdown.tycoon = chars
    .map((c) => ({ name: c.name, copper: c.money_copper ?? 0 }))
    .filter((c) => c.copper > 0)
    .sort((a, b) => b.copper - a.copper)
    .map((c) => ({ label: c.name, value: `${Math.floor(c.copper / 10000).toLocaleString()}g` }));

  // Blood of the Enemy (battle_scarred) - Honorable Kills per character.
  breakdown.battle_scarred = chars
    .map((c) => ({ name: c.name, kills: statSum(c.id, "Honorable Kills", "Total Honorable Kills") }))
    .filter((c) => c.kills > 0)
    .sort((a, b) => b.kills - a.kills)
    .map((c) => ({ label: c.name, value: `${c.kills.toLocaleString()} kills` }));

  // Apex Predator - combined "Boss Kills" category per character.
  breakdown.apex_predator = chars
    .map((c) => ({
      name: c.name,
      kills: statRows
        .filter((s) => s.character_id === c.id && s.category === "Boss Kills")
        .reduce((sum, s) => {
          const n = Number(s.value.replace(/,/g, ""));
          return Number.isFinite(n) ? sum + n : sum;
        }, 0),
    }))
    .filter((c) => c.kills > 0)
    .sort((a, b) => b.kills - a.kills)
    .map((c) => ({ label: c.name, value: `${c.kills.toLocaleString()} kills` }));

  // Time Lost in Azeroth (marathon) - hours played per character.
  breakdown.marathon = chars
    .map((c) => ({ name: c.name, hours: c.time_played_hours ?? 0 }))
    .filter((c) => c.hours > 0)
    .sort((a, b) => b.hours - a.hours)
    .map((c) => ({ label: c.name, value: `${Math.round(c.hours).toLocaleString()} hrs` }));

  // Master of All Trades - which character (if any) maxed each profession.
  const maxedByProfession = new Map<string, string>();
  for (const p of professionRows) {
    if (p.skill >= MAX_SKILL) {
      maxedByProfession.set(p.profession, charName.get(p.character_id) ?? "Unknown");
    }
  }
  breakdown.master_of_all_trades = ALL_PROFESSIONS.map((prof) => ({
    label: prof,
    value: maxedByProfession.get(prof) ?? "Not yet maxed",
  }));

  // Full Roster (class_collector) - which character (if any) is level 60
  // for each class.
  const maxedByClass = new Map<string, string>();
  for (const c of chars) {
    if (c.level >= MAX_CHARACTER_LEVEL) maxedByClass.set(c.class, c.name);
  }
  breakdown.class_collector = CLASSES.map((cls) => ({
    label: cls,
    value: maxedByClass.get(cls) ?? "Not yet at level 60",
  }));

  // Alliance/Horde Completionist + Diplomat - which character (if any) is
  // level 60 for each race. Diplomat needs both factions, so it just gets
  // every race in one combined list.
  const maxedByRace = new Map<string, string>();
  for (const c of chars) {
    if (c.level >= MAX_CHARACTER_LEVEL) maxedByRace.set(c.race, c.name);
  }
  const allRaces = Object.keys(RACE_FACTION);
  const raceLine = (race: string) => ({ label: race, value: maxedByRace.get(race) ?? "Not yet at level 60" });
  breakdown.alliance_completionist = allRaces.filter((r) => RACE_FACTION[r] === "Alliance").map(raceLine);
  breakdown.horde_completionist = allRaces.filter((r) => RACE_FACTION[r] === "Horde").map(raceLine);
  breakdown.diplomat = allRaces.map(raceLine);

  // PvP Dynasty - which characters currently hold the top PvP rank.
  const topRankChars = achievementRows
    .filter((a) => a.kind === "top_pvp_rank")
    .map((a) => charName.get(a.character_id) ?? "Unknown");
  breakdown.pvp_dynasty =
    topRankChars.length > 0
      ? topRankChars.map((name) => ({ label: name, value: "Top rank reached" }))
      : [{ label: "No characters yet", value: "—" }];

  return breakdown;
}
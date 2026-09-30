import type { SupabaseClient } from "@supabase/supabase-js";
import { CLASSES, RACE_FACTION } from "./options";
import { PRIMARY_PROFESSIONS } from "./icons";
import { buildAchievementItems } from "../app/achievementBoard";
import type { AchievementTier } from "./achievements";

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
  | "big_family"
  | "pvp_dynasty"
  // One-Man Army (2026-09-27) - 3+ characters at the level cap on one
  // account. Distinct from class_collector (every class, one each) and
  // pvp_dynasty (top rank, not level) - this is just "you've maxed out a
  // small army", no class/race/PvP requirement at all.
  | "one_man_army"
  // 2026-09-30 batch, from the "unlocking icons from achievements"/account-
  // progression brainstorm - Jordan picked these three out of a longer
  // list. A fourth idea ("every faction in the game exalted by someone on
  // the account") got proposed too but isn't buildable yet - the addon only
  // reports a COUNT of exalted factions per character (feeds the existing
  // per-character "Diplomat" achievement), not which specific factions, so
  // there's no way to know if two characters' exalted factions overlap or
  // cover the whole game. Would need new addon-side tracking (looping
  // GetFactionInfo, capturing names) before this can be built for real.
  | "legacy_master"
  | "completionist"
  | "marathon";

// Icon names are real WoW icon names, resolved to actual game art through
// wowIconUrl() (see lib/icons.ts) by whatever renders these - AccountBadges
// for the site, or the badge tester page directly.
export const ACCOUNT_ACHIEVEMENT_BADGES: Record<
  AccountAchievementKind,
  { icon: string; label: string }
> = {
  class_collector: {
    icon: "achievement_general",
    label: "Class Collector - a level-60 character of every class",
  },
  alliance_completionist: {
    icon: "inv_bannerpvp_02",
    label: "Alliance Completionist - a level-60 character of every Alliance race",
  },
  horde_completionist: {
    icon: "inv_bannerpvp_01",
    label: "Horde Completionist - a level-60 character of every Horde race",
  },
  diplomat: {
    icon: "achievement_reputation_01",
    label: "Diplomat - maxed a character of every race on both factions",
  },
  master_of_all_trades: {
    icon: "trade_engineering",
    label: "Master of All Trades - every profession maxed by someone on the account",
  },
  tycoon: {
    icon: "inv_misc_coin_06",
    label: "Tycoon - 10,000 combined gold across your characters",
  },
  big_family: { icon: "inv_misc_bag_10", label: "Big Family - 10 or more characters" },
  pvp_dynasty: {
    icon: "inv_jewelry_ring_03",
    label: "PvP Dynasty - 2 or more characters at the top PvP rank",
  },
  one_man_army: {
    icon: "achievement_bg_killxenemies_generalsroom",
    label: "One-Man Army - 3 or more characters at the level cap",
  },
  legacy_master: {
    icon: "inv_misc_rune_01",
    label: "Legacy Master - every Legacy Challenge achievement completed",
  },
  completionist: {
    icon: "inv_misc_trophy_01",
    label: "The Completionist - every character achievement earned by someone on the account",
  },
  marathon: {
    icon: "inv_misc_pocketwatch_01",
    label: "The Marathon - 1,000+ hours played, combined across all characters",
  },
};

const ACCOUNT_ACHIEVEMENT_MESSAGE: Record<AccountAchievementKind, (name: string) => string> = {
  class_collector: (name) => `${name} has a level-60 character of every class!`,
  alliance_completionist: (name) => `${name} has maxed a character of every Alliance race!`,
  horde_completionist: (name) => `${name} has maxed a character of every Horde race!`,
  diplomat: (name) => `${name} has maxed a character of every race on both factions!`,
  master_of_all_trades: (name) => `${name}'s account has maxed every profession!`,
  tycoon: (name) => `${name} has amassed 10,000 gold across their characters!`,
  big_family: (name) => `${name} is running a full roster - 10+ characters!`,
  pvp_dynasty: (name) => `${name} has 2+ characters at the top PvP rank!`,
  one_man_army: (name) => `${name} has 3+ characters at the level cap - One-Man Army!`,
  legacy_master: (name) => `${name} has completed every Legacy Challenge achievement - Legacy Master!`,
  completionist: (name) => `${name}'s account has earned every character achievement - The Completionist!`,
  marathon: (name) => `${name} has played 1,000+ hours combined across their characters - The Marathon!`,
};

const MAX_CHARACTER_LEVEL = 60;
const MAX_SKILL = 300;
const SECONDARY_PROFESSIONS = ["First Aid", "Cooking", "Fishing"];
const ALL_PROFESSIONS = [...PRIMARY_PROFESSIONS, ...SECONDARY_PROFESSIONS];
const BIG_FAMILY_THRESHOLD = 10;
const TYCOON_GOLD = 10000;
const PVP_DYNASTY_THRESHOLD = 2;
const ONE_MAN_ARMY_THRESHOLD = 3;
// Legacy Challenges total (2026-09-27, confirmed in achievementBoard.ts's
// buildLegacyAchievementItems comments) - the addon reports every known
// Legacy Challenge achievement's state on each sync (not just completed
// ones), so a fully-synced account should have exactly this many rows in
// account_legacy_achievements. If Blizzard/the server ever adds more, bump
// this - a stale-low number would let Legacy Master fire early.
const LEGACY_ACHIEVEMENT_TOTAL = 111;
// Starting estimate, not tuned against real playtime data yet - easy to
// retune later, this is just one number.
const MARATHON_HOURS = 1000;

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
// below 10,000 doesn't take Tycoon away).
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

  if (maxedChars.length >= ONE_MAN_ARMY_THRESHOLD) {
    await tryAward("one_man_army");
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

  if (chars.length >= BIG_FAMILY_THRESHOLD) {
    await tryAward("big_family");
  }

  // The Marathon (2026-09-30) - combined played time across every
  // character on the account, no per-character minimum.
  const totalHoursPlayed = chars.reduce((sum, c) => sum + (c.time_played_hours ?? 0), 0);
  if (totalHoursPlayed >= MARATHON_HOURS) {
    await tryAward("marathon");
  }

  const characterIds = chars.map((c) => c.id);
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

  // Legacy Master (2026-09-30) - every Legacy Challenge achievement
  // completed. account_legacy_achievements gets a row for every known
  // achievement on each sync (completed or not - see importLogic.ts), so a
  // fully-synced, fully-completed account has exactly LEGACY_ACHIEVEMENT_
  // TOTAL rows, all completed:true. Requiring the full row count (not just
  // "every row we happen to have is completed") guards against awarding
  // this to an account that's only synced a handful of categories so far.
  const { data: legacyRows } = await supabase
    .from("account_legacy_achievements")
    .select("completed")
    .eq("user_id", userId);
  const legacy = legacyRows ?? [];
  if (legacy.length >= LEGACY_ACHIEVEMENT_TOTAL && legacy.every((r) => r.completed)) {
    await tryAward("legacy_master");
  }

  // The Completionist (2026-09-30) - every character achievement (the same
  // set the Account Progress bar on the overview page counts) earned by AT
  // LEAST ONE character, account-wide. Mirrors lib/accountView.ts's
  // mergeAccountItems in spirit, but only needs the union of "earned" -
  // no need to track which character/tier "wins" a key the way the actual
  // account overview does, so this stays a simpler pass over the same
  // buildAchievementItems() output every character page already uses.
  const [{ data: achievementRows }, { data: statRows }] = await Promise.all([
    supabase.from("achievements").select("character_id, kind, tier, earned_at").in("character_id", characterIds),
    supabase
      .from("character_statistics")
      .select("character_id, category, name, value")
      .in("character_id", characterIds),
  ]);

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
import type { SupabaseClient } from "@supabase/supabase-js";
import { CLASSES, RACE_FACTION } from "./options";
import { PRIMARY_PROFESSIONS } from "./icons";

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
  | "pvp_dynasty";

export const ACCOUNT_ACHIEVEMENT_BADGES: Record<
  AccountAchievementKind,
  { icon: string; label: string }
> = {
  class_collector: { icon: "🧩", label: "Class Collector - a level-60 character of every class" },
  alliance_completionist: {
    icon: "🦁",
    label: "Alliance Completionist - a level-60 character of every Alliance race",
  },
  horde_completionist: {
    icon: "🐺",
    label: "Horde Completionist - a level-60 character of every Horde race",
  },
  diplomat: {
    icon: "🕊️",
    label: "Diplomat - maxed a character of every race on both factions",
  },
  master_of_all_trades: {
    icon: "🛠️",
    label: "Master of All Trades - every profession maxed by someone on the account",
  },
  tycoon: { icon: "💎", label: "Tycoon - 10,000 combined gold across your characters" },
  big_family: { icon: "👨‍👩‍👧‍👦", label: "Big Family - 5 or more characters" },
  pvp_dynasty: { icon: "🏰", label: "PvP Dynasty - 2 or more characters at the top PvP rank" },
};

const ACCOUNT_ACHIEVEMENT_MESSAGE: Record<AccountAchievementKind, (name: string) => string> = {
  class_collector: (name) => `${name} has a level-60 character of every class!`,
  alliance_completionist: (name) => `${name} has maxed a character of every Alliance race!`,
  horde_completionist: (name) => `${name} has maxed a character of every Horde race!`,
  diplomat: (name) => `${name} has maxed a character of every race on both factions!`,
  master_of_all_trades: (name) => `${name}'s account has maxed every profession!`,
  tycoon: (name) => `${name} has amassed 10,000 gold across their characters!`,
  big_family: (name) => `${name} is running a full roster - 5+ characters!`,
  pvp_dynasty: (name) => `${name} has 2+ characters at the top PvP rank!`,
};

const MAX_CHARACTER_LEVEL = 60;
const MAX_SKILL = 300;
const SECONDARY_PROFESSIONS = ["First Aid", "Cooking", "Fishing"];
const ALL_PROFESSIONS = [...PRIMARY_PROFESSIONS, ...SECONDARY_PROFESSIONS];
const BIG_FAMILY_THRESHOLD = 5;
const TYCOON_GOLD = 10000;
const PVP_DYNASTY_THRESHOLD = 2;

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
    .select("id, class, race, level, money_copper")
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

  if (chars.length >= BIG_FAMILY_THRESHOLD) {
    await tryAward("big_family");
  }

  const characterIds = chars.map((c) => c.id);
  const { data: professionRows } = await supabase
    .from("character_professions")
    .select("profession, skill")
    .in("character_id", characterIds);
  const maxedProfessions = new Set(
    (professionRows ?? [])
      .filter((p) => p.skill >= MAX_SKILL)
      .map((p) => p.profession)
  );
  if (ALL_PROFESSIONS.every((p) => maxedProfessions.has(p))) {
    await tryAward("master_of_all_trades");
  }

  const { data: pvpTopRankRows } = await supabase
    .from("achievements")
    .select("character_id")
    .eq("kind", "top_pvp_rank")
    .in("character_id", characterIds);
  if ((pvpTopRankRows ?? []).length >= PVP_DYNASTY_THRESHOLD) {
    await tryAward("pvp_dynasty");
  }

  return newMessages;
}

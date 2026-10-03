import type { SupabaseClient } from "@supabase/supabase-js";
import { CLASSES, RACE_FACTION } from "./options";
import { PRIMARY_PROFESSIONS, wowIconUrl } from "./icons";
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
  battle_scarred: {
    icon: "achievement_pvp_h_08",
    label: "Battle-Scarred - 1,000+ combined Honorable Kills across your characters",
  },
  pvp_dynasty: {
    icon: "inv_jewelry_ring_03",
    label: "PvP Dynasty - 2 or more characters at the top PvP rank",
  },
  apex_predator: {
    icon: "inv_misc_head_dragon_01",
    label: "Apex Predator - 1,000+ combined boss kills across your characters",
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

// Local custom art for account badges (2026-09-30) - same idea as
// FLAT_LOCAL_ICONS/TIERED_LOCAL_ICONS in lib/achievementBadges.ts: a badge
// with an entry here shows Jordan's own art from /public/account-badge-
// icons/<slug>.png instead of its ACCOUNT_ACHIEVEMENT_BADGES.icon CDN
// fallback. Only badges with actual art get listed here; everything else
// keeps using its CDN icon until art exists for it too - adding one is
// just: drop the file, add one line below.
export const ACCOUNT_ACHIEVEMENT_LOCAL_ICONS: Partial<Record<AccountAchievementKind, string>> = {
  class_collector: "class-collector",
  alliance_completionist: "alliance-completionist",
  horde_completionist: "horde-completionist",
  diplomat: "diplomat",
  master_of_all_trades: "master-of-all-trades",
  // File on disk is "Tycoon.png" (capitalized) - rename it to lowercase
  // "tycoon.png" in public/account-badge-icons/ to match this slug. Linux/
  // Vercel's filesystem is case-sensitive, so a mismatch here 404s instead
  // of silently falling back to the CDN icon.
  tycoon: "tycoon",
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
  class_collector: (name) => `${name} has a level-60 character of every class!`,
  alliance_completionist: (name) => `${name} has maxed a character of every Alliance race!`,
  horde_completionist: (name) => `${name} has maxed a character of every Horde race!`,
  diplomat: (name) => `${name} has maxed a character of every race on both factions!`,
  master_of_all_trades: (name) => `${name}'s account has maxed every profession!`,
  tycoon: (name) => `${name} has amassed 10,000 gold across their characters!`,
  battle_scarred: (name) => `${name} has racked up 1,000+ combined Honorable Kills - Battle-Scarred!`,
  pvp_dynasty: (name) => `${name} has 2+ characters at the top PvP rank!`,
  apex_predator: (name) => `${name} has racked up 1,000+ combined boss kills - Apex Predator!`,
  legacy_master: (name) => `${name} has completed every Legacy Challenge achievement - Legacy Master!`,
  completionist: (name) => `${name}'s account has earned every character achievement - The Completionist!`,
  marathon: (name) => `${name} has played 1,000+ hours combined across their characters - The Marathon!`,
};

const MAX_CHARACTER_LEVEL = 60;
const MAX_SKILL = 300;
const SECONDARY_PROFESSIONS = ["First Aid", "Cooking", "Fishing"];
const ALL_PROFESSIONS = [...PRIMARY_PROFESSIONS, ...SECONDARY_PROFESSIONS];
// 1,000 combined Honorable Kills across every character on the account -
// same "Honorable Kills"/"Total Honorable Kills" stat the per-character
// honorable_kills achievement already sums (see TIER_COUNTERS in
// achievements.ts), just totalled account-wide instead of per-character.
const BATTLE_SCARRED_HONORABLE_KILLS = 1000;
const TYCOON_GOLD = 10000;
const PVP_DYNASTY_THRESHOLD = 2;
// 1,000 combined boss kills (dungeon + raid together - see the
// AccountAchievementKind comment on apex_predator for why this isn't
// split by instance type) across every character on the account.
const APEX_PREDATOR_BOSS_KILLS = 1000;
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

  // The Marathon (2026-09-30) - combined played time across every
  // character on the account, no per-character minimum.
  const totalHoursPlayed = chars.reduce((sum, c) => sum + (c.time_played_hours ?? 0), 0);
  if (totalHoursPlayed >= MARATHON_HOURS) {
    await tryAward("marathon");
  }

  const characterIds = chars.map((c) => c.id);

  // Fetched early (not just where buildAchievementItems needs it further
  // down) so Battle-Scarred's Honorable Kills sum can reuse the exact same
  // rows instead of a second character_statistics query.
  const [{ data: achievementRows }, { data: statRows }] = await Promise.all([
    supabase.from("achievements").select("character_id, kind, tier, earned_at").in("character_id", characterIds),
    supabase
      .from("character_statistics")
      .select("character_id, category, name, value")
      .in("character_id", characterIds),
  ]);

  // Battle-Scarred (2026-10-03, replaced "Big Family" - see the
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
  // (achievementRows/statRows themselves were already fetched above, for
  // Battle-Scarred's Honorable Kills sum - reused here as-is.)

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
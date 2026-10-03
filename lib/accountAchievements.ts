import type { SupabaseClient } from "@supabase/supabase-js";
import { CLASSES, RACE_FACTION } from "./options";
import { PRIMARY_PROFESSIONS, wowIconUrl } from "./icons";
import { buildAchievementItems } from "../app/achievementBoard";
import { MAX_CHARACTER_LEVEL, MAX_PROFESSION_SKILL, type AchievementTier } from "./achievements";
import type { BadgeIconOverrides } from "./badgeIconOverrides";

type AchievementRowDB = { character_id: string; kind: string; tier: AchievementTier | null; earned_at: string | null };

// Account-wide achievements - these look across ALL of a user's
// characters at once, unlike the per-character achievements in
// achievements.ts. Each is a one-off yes/no per account.
export type AccountAchievementKind =
  // Renamed from "class_collector" (2026-10-03, "rename all account badges
  // achievement names in code to the pictures" - the internal kind
  // identifiers now match the display names/filenames instead of carrying
  // old pre-rename names). See the matching SQL migration for the
  // account_achievements.kind data rename this requires.
  | "full_roster"
  | "alliance_completionist"
  | "horde_completionist"
  | "diplomat"
  | "master_of_all_trades"
  // Renamed from "tycoon" (2026-10-03).
  | "master_merchant"
  // Replaced "big_family" (2026-10-03, "not hard to just make 10
  // characters" - that one only checked chars.length >= 10, so it was
  // free to cash in by rolling throwaway level-1 alts, no actual play
  // required). This instead sums the same "Total Honorable Kills" stat
  // the per-character honorable_kills achievement already tracks (see
  // TIER_COUNTERS in achievements.ts) across every character on the
  // account - real, hard-won PvP effort instead of a roster headcount.
  // Renamed from "battle_scarred" (2026-10-03).
  | "blood_of_the_enemy"
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
  // "legacy_master" ("Legacy Complete") - briefly removed on 2026-10-03
  // after a mixed-up request (Jordan actually meant the separate
  // per-character "maxed_legacy" achievement, which WAS a duplicate of
  // this and stays removed - see lib/achievements.ts). This account badge
  // itself is the real, intentional one: account_legacy_achievements is
  // already a single account-wide table (the Legacy Challenges panel is
  // the same 111-achievement list for every character), so this just
  // checks that every row is both synced and completed.
  // Renamed from "legacy_master" (2026-10-03).
  | "legacy_complete"
  // Renamed from "completionist" (2026-10-03).
  | "the_completionist"
  // Renamed from "marathon" (2026-10-03).
  | "time_lost_in_azeroth";

// Icon names are real WoW icon names, resolved to actual game art through
// wowIconUrl() (see lib/icons.ts) by whatever renders these - AccountBadges
// for the site, or the badge tester page directly.
export const ACCOUNT_ACHIEVEMENT_BADGES: Record<
  AccountAchievementKind,
  { icon: string; label: string }
> = {
  // Display name "Full Roster" (renamed from "Class Collector" 2026-10-03;
  // the `kind` key itself was renamed from class_collector to full_roster
  // the same day, see AccountAchievementKind's comment).
  full_roster: {
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
  // Display name "Master Merchant" (renamed from "Tycoon"; kind renamed
  // from tycoon to master_merchant 2026-10-03).
  master_merchant: {
    icon: "inv_misc_coin_06",
    label: "Master Merchant - 10,000 gold or more, combined across your characters.",
  },
  // Display name "Blood of the Enemy" (renamed from "Battle-Scarred"; kind
  // renamed from battle_scarred to blood_of_the_enemy 2026-10-03).
  blood_of_the_enemy: {
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
  // Icon changed 2026-10-03 ("why are these also showing wow icons and not
  // the correct square icon") - "achievement_dungeon_outland_dungeonmaster"
  // was a Mists of Pandaria-era addition, and this app's icon CDN
  // (wow.zamimg.com, see the ICON_URL_OVERRIDES comment at the top of
  // lib/icons.ts) only reliably mirrors classic/TBC-era art - that icon
  // name resolved to a broken/placeholder image instead of the real trophy
  // art. Swapped for a plain trophy icon that's been in the game (and on
  // that CDN) since vanilla. If this still doesn't look right, it can be
  // fine-tuned per-badge from the /dev/badges icon override tool without
  // another code change.
  // Kind renamed from legacy_master to legacy_complete 2026-10-03.
  legacy_complete: {
    icon: "inv_misc_trophy_02",
    label: "Legacy Complete - Every Legacy Challenge completed.",
  },
  // Kind renamed from completionist to the_completionist 2026-10-03.
  the_completionist: {
    icon: "inv_misc_trophy_01",
    label: "The Completionist - Every character achievement earned by someone on the account.",
  },
  // Display name "Time Lost in Azeroth" (renamed from "The Marathon"; kind
  // renamed from marathon to time_lost_in_azeroth 2026-10-03).
  time_lost_in_azeroth: {
    icon: "inv_misc_pocketwatch_01",
    label: "Time Lost in Azeroth - 1,000 or more hours played, combined across all characters.",
  },
};

// Local custom art for account badges (2026-09-30, filled out to cover
// every badge 2026-10-03) - same idea as FLAT_LOCAL_ICONS/TIERED_LOCAL_ICONS
// in lib/achievementBadges.ts: a badge with an entry here shows Jordan's own
// art from /public/account-badge-icons/<slug>.png instead of its
// ACCOUNT_ACHIEVEMENT_BADGES.icon CDN fallback. Every account badge now has
// its own art, and since 2026-10-03's kind rename the kind keys themselves
// match these filenames too (full_roster -> "full-roster.png", etc.) - kept
// as a Partial type rather than a plain Record so a future new kind added
// without art yet doesn't need a placeholder entry here, it'll just fall
// back to its CDN icon until one exists.
export const ACCOUNT_ACHIEVEMENT_LOCAL_ICONS: Partial<Record<AccountAchievementKind, string>> = {
  full_roster: "full-roster",
  alliance_completionist: "alliance-completionist",
  horde_completionist: "horde-completionist",
  diplomat: "diplomat",
  master_of_all_trades: "master-of-all-trades",
  // Back to plain "master-merchant" (2026-10-03) - Jordan confirmed the
  // actual master-merchant.png file already has the correct coin-bag art,
  // so the "-v2" cache-busting rename wasn't wanted. If the wrong picture
  // ever comes back after this, it's a browser/CDN cache serving stale bytes
  // under this exact URL - a hard refresh, or redeploying, should clear it.
  master_merchant: "master-merchant",
  blood_of_the_enemy: "blood-of-the-enemy",
  pvp_dynasty: "pvp-dynasty",
  apex_predator: "apex-predator",
  legacy_complete: "legacy-complete",
  the_completionist: "the-completionist",
  time_lost_in_azeroth: "time-lost-in-azeroth",
};

export function localAccountBadgeIconSrc(slug: string) {
  return `/account-badge-icons/${slug}.png`;
}

// Resolves a badge's actual icon URL. Priority: this badge's own local art
// if it has any; otherwise an admin-set override (the badge_icons table);
// otherwise its coded-in CDN icon from ACCOUNT_ACHIEVEMENT_BADGES.
//
// `overrides` defaults to {} so every existing call site (none of which used
// to pass overrides at all) keeps working unchanged.
//
// 2026-10-03 fix ("master merchant icon wrong in dashboard but right in
// account page") - AccountBadges.tsx (the Dashboard panel) had its own
// copy of this exact chain and WAS checking overrides; this function (used
// by AccountBadgesGrid.tsx on the Account Overview page) never took
// overrides at all, so a dev-set override only ever showed up on the
// Dashboard. Both now go through this one function so they can't drift
// apart again.
//
// 2026-10-03, same day - PRIORITY FLIPPED (was override-wins-over-everything)
// after that same fix surfaced a second bug: a stale "tycoon" override row
// set back before Master Merchant had local art was now winning on BOTH
// pages, showing the old plain CDN coin icon everywhere instead of the real
// master-merchant.png art. The /dev/badges page's own icon-override editor
// was removed back on 2026-09-25 (see its header comment - "the per-icon
// 'customize icons' editor...isn't used any more"), so there's no in-app way
// left to clear a stale row like that. Since every account badge now has its
// own confirmed local art (2026-10-03's "fill out every badge" pass), local
// art winning is the right default going forward - an override only still
// matters as a stopgap for a future badge added without art yet. Callers
// should use this instead of reaching into ACCOUNT_ACHIEVEMENT_BADGES[kind]
// .icon + wowIconUrl() directly, so a badge getting local art (or an
// override) later doesn't need a second place updated.
export function accountBadgeIconSrc(
  kind: AccountAchievementKind,
  overrides: BadgeIconOverrides = {}
): string {
  const slug = ACCOUNT_ACHIEVEMENT_LOCAL_ICONS[kind];
  if (slug) return localAccountBadgeIconSrc(slug);
  const overrideIcon = overrides[kind];
  if (overrideIcon) return wowIconUrl(overrideIcon);
  return wowIconUrl(ACCOUNT_ACHIEVEMENT_BADGES[kind].icon);
}

const ACCOUNT_ACHIEVEMENT_MESSAGE: Record<AccountAchievementKind, (name: string) => string> = {
  full_roster: (name) => `${name} has a level-60 character of every class - Full Roster!`,
  alliance_completionist: (name) => `${name} has maxed a character of every Alliance race!`,
  horde_completionist: (name) => `${name} has maxed a character of every Horde race!`,
  diplomat: (name) => `${name} has maxed a character of every race, on both factions!`,
  master_of_all_trades: (name) => `${name}'s account has maxed every profession!`,
  master_merchant: (name) => `${name} has amassed 10,000 gold across their characters - Master Merchant!`,
  blood_of_the_enemy: (name) => `${name} has racked up 1,000 or more combined Honorable Kills - Blood of the Enemy!`,
  pvp_dynasty: (name) => `${name} has two or more characters at the top PvP rank!`,
  apex_predator: (name) => `${name} has racked up 1,000 or more combined boss kills - Apex Predator!`,
  legacy_complete: (name) => `${name}'s account has completed every Legacy Challenge!`,
  the_completionist: (name) => `${name}'s account has earned every character achievement - The Completionist!`,
  time_lost_in_azeroth: (name) => `${name} has played 1,000 or more hours, combined across their characters - Time Lost in Azeroth!`,
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
// Renamed from BATTLE_SCARRED_HONORABLE_KILLS (2026-10-03).
export const BLOOD_OF_THE_ENEMY_HONORABLE_KILLS = 1000;
// Renamed from TYCOON_GOLD (2026-10-03).
export const MASTER_MERCHANT_GOLD = 10000;
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
// retune later, this is just one number. Renamed from MARATHON_HOURS
// (2026-10-03).
export const TIME_LOST_IN_AZEROTH_HOURS = 1000;

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
    await tryAward("full_roster");
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
  if (totalCopper >= MASTER_MERCHANT_GOLD * 10000) {
    await tryAward("master_merchant");
  }

  // Time Lost in Azeroth (2026-09-30) - combined played time across every
  // character on the account, no per-character minimum.
  const totalHoursPlayed = chars.reduce((sum, c) => sum + (c.time_played_hours ?? 0), 0);
  if (totalHoursPlayed >= TIME_LOST_IN_AZEROTH_HOURS) {
    await tryAward("time_lost_in_azeroth");
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
  if (totalHonorableKills >= BLOOD_OF_THE_ENEMY_HONORABLE_KILLS) {
    await tryAward("blood_of_the_enemy");
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

  // Legacy Complete (legacy_master) - account_legacy_achievements is a
  // single account-wide table (same 111-achievement list regardless of
  // which character the addon was scanning from), so this just checks
  // that it's been fully synced (at least LEGACY_ACHIEVEMENT_TOTAL rows -
  // a stale-low row count would let this fire early, before every category
  // tab had ever been browsed in-game) AND every one of those rows is
  // actually completed.
  const { data: legacyRows } = await supabase
    .from("account_legacy_achievements")
    .select("completed")
    .eq("user_id", userId);
  const legacyFullyScanned = (legacyRows?.length ?? 0) >= LEGACY_ACHIEVEMENT_TOTAL;
  const legacyPointRowsAllComplete = (legacyRows ?? []).every((r) => r.completed);
  if (legacyFullyScanned && legacyPointRowsAllComplete) {
    await tryAward("legacy_complete");
  }

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
    await tryAward("the_completionist");
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
// completed/total too, and so does legacy_master (completed Legacy
// Challenge rows out of LEGACY_ACHIEVEMENT_TOTAL).
export function computeAccountBadgeProgress({
  chars,
  professionRows,
  statRows,
  pvpTopRankCharacterCount,
  earnedAchievementCount,
  totalAchievementCount,
  legacyRows,
}: {
  chars: { level: number; class: string; race: string; money_copper: number | null; time_played_hours: number | null }[];
  professionRows: { profession: string; skill: number }[];
  statRows: { category: string; name: string; value: string }[];
  pvpTopRankCharacterCount: number;
  earnedAchievementCount: number;
  totalAchievementCount: number;
  legacyRows: { completed: boolean }[];
}): Partial<Record<AccountAchievementKind, { value: number; target: number }>> {
  const progress: Partial<Record<AccountAchievementKind, { value: number; target: number }>> = {};

  const maxedChars = chars.filter((c) => c.level >= MAX_CHARACTER_LEVEL);
  const maxedClasses = new Set(maxedChars.map((c) => c.class));
  progress.full_roster = { value: maxedClasses.size, target: CLASSES.length };

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
  progress.master_merchant = { value: Math.floor(totalCopper / 10000), target: MASTER_MERCHANT_GOLD };

  const totalHoursPlayed = chars.reduce((sum, c) => sum + (c.time_played_hours ?? 0), 0);
  progress.time_lost_in_azeroth = { value: Math.round(totalHoursPlayed), target: TIME_LOST_IN_AZEROTH_HOURS };

  progress.pvp_dynasty = { value: pvpTopRankCharacterCount, target: PVP_DYNASTY_THRESHOLD };

  const totalHonorableKills = statRows
    .filter((s) => s.category === "Honorable Kills" && s.name === "Total Honorable Kills")
    .reduce((sum, s) => {
      const n = Number(s.value.replace(/,/g, ""));
      return Number.isFinite(n) ? sum + n : sum;
    }, 0);
  progress.blood_of_the_enemy = { value: totalHonorableKills, target: BLOOD_OF_THE_ENEMY_HONORABLE_KILLS };

  const totalBossKills = statRows
    .filter((s) => s.category === "Boss Kills")
    .reduce((sum, s) => {
      const n = Number(s.value.replace(/,/g, ""));
      return Number.isFinite(n) ? sum + n : sum;
    }, 0);
  progress.apex_predator = { value: totalBossKills, target: APEX_PREDATOR_BOSS_KILLS };

  progress.legacy_complete = {
    value: legacyRows.filter((r) => r.completed).length,
    target: LEGACY_ACHIEVEMENT_TOTAL,
  };

  progress.the_completionist = { value: earnedAchievementCount, target: totalAchievementCount };

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

  // Master Merchant - gold per character, highest first. Characters with no
  // gold are left out rather than padding the list with "0g".
  breakdown.master_merchant = chars
    .map((c) => ({ name: c.name, copper: c.money_copper ?? 0 }))
    .filter((c) => c.copper > 0)
    .sort((a, b) => b.copper - a.copper)
    .map((c) => ({ label: c.name, value: `${Math.floor(c.copper / 10000).toLocaleString()}g` }));

  // Blood of the Enemy - Honorable Kills per character.
  breakdown.blood_of_the_enemy = chars
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

  // Time Lost in Azeroth - hours played per character.
  breakdown.time_lost_in_azeroth = chars
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

  // Full Roster - which character (if any) is level 60 for each class.
  const maxedByClass = new Map<string, string>();
  for (const c of chars) {
    if (c.level >= MAX_CHARACTER_LEVEL) maxedByClass.set(c.class, c.name);
  }
  breakdown.full_roster = CLASSES.map((cls) => ({
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
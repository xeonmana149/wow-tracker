import type { SupabaseClient } from "@supabase/supabase-js";
import { buildAchievementItems, type AchievementBoardItem } from "../app/achievementBoard";
import {
  TIERED_ACHIEVEMENT_KINDS,
  tierLabel,
  type AchievementTier,
  type TieredAchievementKind,
} from "./achievements";
import { FLAT_ACHIEVEMENT_NAME } from "./achievementCategories";
import {
  computeAccountBadgeProgress,
  computeAccountBadgeBreakdown,
  type AccountAchievementKind,
  type AccountBadgeBreakdownLine,
} from "./accountAchievements";
import { loadBadgeIconOverrides, type BadgeIconOverrides } from "./badgeIconOverrides";

// Shared account-overview data loading (2026-09-30, split out of
// app/account/page.tsx when "how do we see other players account pages?"
// turned into building a public account view). Both places that show an
// account overview need the EXACT same fetch + computation:
//  - app/account/page.tsx - your own account, fetched client-side with the
//    browser's RLS-scoped supabase client (`supabase` from lib/supabase).
//  - app/account/[userId]/page.tsx - someone else's account, fetched
//    SERVER-side with supabaseAdmin (lib/supabaseAdmin), because RLS on
//    `characters`/`achievements`/etc. otherwise only lets a user read their
//    own rows (see the "only your own characters show up here" comment in
//    items/ItemSearch.tsx - same restriction applies here for anyone else's
//    account, so a plain browser query for another user's data would just
//    come back empty rather than actually showing their overview).
// Passing in whichever client to use (rather than importing one fixed
// client here) is what lets one function serve both call sites without
// duplicating the merge/label logic a second time and risking it drifting.

export type CharacterRow = {
  id: string;
  name: string;
  level: number;
  class: string;
  race: string;
  character_type: string;
  time_played_hours: number | null;
  money_copper: number | null;
  // PvP rank (2026-10-03) - see lib/importLogic.ts's ParsedExport.pvpRank
  // comment. Null until the player's opened the in-game PvP panel at least
  // once.
  top_pvp_rank: number | null;
};

type AchievementRowDB = {
  character_id: string;
  kind: string;
  tier: AchievementTier | null;
  earned_at: string | null;
  tier_copper_at?: string | null;
  tier_silver_at?: string | null;
  tier_gold_at?: string | null;
  tier_platinum_at?: string | null;
};
type StatRow = { character_id: string; category: string; name: string; value: string };
// profession/skill added (2026-10-03) alongside the existing recipes field
// - both now needed here since computeAccountBadgeProgress's Master of All
// Trades fraction wants the same maxed-skill-count the award check uses,
// not just recipes (which only feeds Completionist/recipes achievements).
type ProfessionRow = { character_id: string; profession: string; skill: number; recipes: unknown[] | null };
// Feeds both the separate Legacy Challenges summary (legacyEarned/
// legacyPoints below) and computeAccountBadgeProgress's "Legacy Complete"
// account badge fraction (see lib/accountAchievements.ts) - same rows, two
// different uses, so only fetched once.
type LegacyRow = { completed: boolean; ui_points: number | null };

export type RecentAchievement = {
  characterId: string;
  characterName: string;
  kind: string;
  tier: AchievementTier | null;
  earnedAt: string;
  label: string;
};

const TIERED_SET = new Set<string>(TIERED_ACHIEVEMENT_KINDS);

export function labelFor(kind: string): string {
  if (TIERED_SET.has(kind)) return tierLabel(kind as TieredAchievementKind);
  return FLAT_ACHIEVEMENT_NAME[kind as keyof typeof FLAT_ACHIEVEMENT_NAME] ?? kind;
}

// Rolls per-character AchievementBoardItem[] arrays up into one account-wide
// view: earned if ANY character has earned it, keeping whichever character's
// copy has the highest points (i.e. the highest tier reached) rather than
// summing across characters. ownerByKey remembers which character each
// merged item actually came from, so Featured Achievements can link to a
// character page where that achievement/progress genuinely exists.
export function mergeAccountItems(
  perCharacter: { characterId: string; items: AchievementBoardItem[] }[]
): { items: AchievementBoardItem[]; ownerByKey: Map<string, string> } {
  const byKey = new Map<string, AchievementBoardItem>();
  const ownerByKey = new Map<string, string>();
  for (const { characterId, items } of perCharacter) {
    for (const item of items) {
      const existing = byKey.get(item.key);
      if (!existing) {
        byKey.set(item.key, item);
        ownerByKey.set(item.key, characterId);
        continue;
      }
      const existingRatio =
        !existing.earned && existing.tiered && existing.nextThreshold
          ? (existing.value ?? 0) / existing.nextThreshold
          : -1;
      const ratio =
        !item.earned && item.tiered && item.nextThreshold ? (item.value ?? 0) / item.nextThreshold : -1;
      const better =
        item.points > existing.points || (item.points === existing.points && !item.earned && ratio > existingRatio);
      if (better) {
        byKey.set(item.key, item);
        ownerByKey.set(item.key, characterId);
      }
    }
  }
  return { items: Array.from(byKey.values()), ownerByKey };
}

export function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}

export type AccountViewData = {
  found: boolean;
  userId: string;
  displayName: string;
  memberSince: string | null;
  avatarIcon: string | null;
  bannerStyle: string | null;
  motto: string | null;
  characters: CharacterRow[];
  mergedItems: AchievementBoardItem[];
  itemOwner: Map<string, string>;
  recent: RecentAchievement[];
  accountBadges: AccountAchievementKind[];
  // "X / Y" progress for whichever account badges reduce to one meaningful
  // fraction - see computeAccountBadgeProgress in accountAchievements.ts
  // for which ones and why. Absent entries (not every badge has one) mean
  // AccountBadgeTile falls back to its plain earned/not-earned display.
  accountBadgeProgress: Partial<Record<AccountAchievementKind, { value: number; target: number }>>;
  // Per-character/class/race/profession breakdown of what's feeding a
  // badge's progress (2026-10-03) - see computeAccountBadgeBreakdown in
  // accountAchievements.ts for which badges get one. Absent entries mean
  // AccountBadgeTile just shows the plain progress bar with no expandable
  // detail.
  accountBadgeBreakdown: Partial<Record<AccountAchievementKind, AccountBadgeBreakdownLine[]>>;
  legacyEarned: number;
  legacyPoints: number;
  // Admin-set per-badge icon overrides (the badge_icons table, edited from
  // /dev/badges) - 2026-10-03, so the Account Overview page's badges honor
  // the same overrides the Dashboard's AccountBadges panel already did (see
  // accountBadgeIconSrc in lib/accountAchievements.ts).
  iconOverrides: BadgeIconOverrides;
};

// `client` is either the browser's RLS-scoped supabase client (viewing your
// OWN account) or supabaseAdmin (viewing someone ELSE's - see the big
// comment above for why that's necessary). `authCreatedAt` is passed in
// separately rather than looked up in here, because getting it needs a
// different call depending on which client this is: the owner's own session
// reads it off `supabase.auth.getUser()`, while a public/server lookup needs
// `supabaseAdmin.auth.admin.getUserById(userId)` instead - both are the
// caller's job, this function just displays whatever came back (or null).
export async function loadAccountViewData(
  client: SupabaseClient,
  userId: string,
  authCreatedAt: string | null
): Promise<AccountViewData> {
  const [
    { data: profileRow },
    { data: characterRows },
    { data: accountAchievementRows },
    { data: legacyRows },
    iconOverrides,
  ] = await Promise.all([
    client
      .from("profiles")
      .select("display_name, avatar_icon, banner_style, motto")
      .eq("id", userId)
      .maybeSingle(),
    client
      .from("characters")
      .select("id, name, level, class, race, character_type, time_played_hours, money_copper, top_pvp_rank")
      .eq("user_id", userId),
    client.from("account_achievements").select("kind").eq("user_id", userId),
    client.from("account_legacy_achievements").select("completed, ui_points").eq("user_id", userId),
    // Not user-scoped - badge_icons is one global table of admin-set icon
    // swaps, the same overrides regardless of whose account page this is.
    loadBadgeIconOverrides(client),
  ]);

  const chars = (characterRows ?? []) as CharacterRow[];
  const characterIds = chars.map((c) => c.id);
  const legacy = (legacyRows ?? []) as LegacyRow[];

  let mergedItems: AchievementBoardItem[] = [];
  let itemOwner = new Map<string, string>();
  let recent: RecentAchievement[] = [];
  let accountBadgeProgress: ReturnType<typeof computeAccountBadgeProgress> = {};
  let accountBadgeBreakdown: ReturnType<typeof computeAccountBadgeBreakdown> = {};

  if (characterIds.length > 0) {
    const [{ data: achievementRows }, { data: statRows }, { data: professionRows }] = await Promise.all([
      client
        .from("achievements")
        .select("character_id, kind, tier, earned_at, tier_copper_at, tier_silver_at, tier_gold_at, tier_platinum_at")
        .in("character_id", characterIds),
      client
        .from("character_statistics")
        .select("character_id, category, name, value")
        .in("character_id", characterIds),
      client
        .from("character_professions")
        .select("character_id, profession, skill, recipes")
        .in("character_id", characterIds),
    ]);

    const achRows = (achievementRows ?? []) as AchievementRowDB[];
    const stRows = (statRows ?? []) as StatRow[];
    const profRows = (professionRows ?? []) as ProfessionRow[];

    const achByChar = new Map<string, AchievementRowDB[]>();
    for (const a of achRows) {
      const list = achByChar.get(a.character_id) ?? [];
      list.push(a);
      achByChar.set(a.character_id, list);
    }
    const statsByChar = new Map<string, StatRow[]>();
    for (const s of stRows) {
      const list = statsByChar.get(s.character_id) ?? [];
      list.push(s);
      statsByChar.set(s.character_id, list);
    }
    const recipesByChar = new Map<string, number>();
    const cookingRecipesByChar = new Map<string, number>();
    const highestProfessionSkillByChar = new Map<string, number>();
    for (const p of profRows) {
      const count = Array.isArray(p.recipes) ? p.recipes.length : 0;
      recipesByChar.set(p.character_id, (recipesByChar.get(p.character_id) ?? 0) + count);
      if (p.profession?.toLowerCase() === "cooking") {
        cookingRecipesByChar.set(p.character_id, (cookingRecipesByChar.get(p.character_id) ?? 0) + count);
      }
      highestProfessionSkillByChar.set(
        p.character_id,
        Math.max(highestProfessionSkillByChar.get(p.character_id) ?? 0, p.skill ?? 0)
      );
    }

    const perCharacterItems = chars.map((c) => ({
      characterId: c.id,
      items: buildAchievementItems({
        achievementRows: achByChar.get(c.id) ?? [],
        statRows: statsByChar.get(c.id) ?? [],
        recipesCount: recipesByChar.get(c.id) ?? 0,
        cookingRecipesCount: cookingRecipesByChar.get(c.id) ?? 0,
        hoursPlayed: c.time_played_hours ?? 0,
        level: c.level,
        highestProfessionSkill: highestProfessionSkillByChar.get(c.id) ?? 0,
        topPvpRank: c.top_pvp_rank,
      }),
    }));
    const merged = mergeAccountItems(perCharacterItems);
    mergedItems = merged.items;
    itemOwner = merged.ownerByKey;

    // Same totalAchievementCount quirk checkAccountAchievements has -
    // every character's buildAchievementItems() call returns the same-
    // length list shape (it's not actually per-character), so just the
    // first character's count stands in for "total possible".
    const earnedAchievementCount = mergedItems.filter((i) => i.earned).length;
    const totalAchievementCount = perCharacterItems[0]?.items.length ?? 0;
    const pvpTopRankCharacterCount = new Set(
      achRows.filter((a) => a.kind === "top_pvp_rank").map((a) => a.character_id)
    ).size;
    accountBadgeProgress = computeAccountBadgeProgress({
      chars,
      professionRows: profRows,
      statRows: stRows,
      pvpTopRankCharacterCount,
      earnedAchievementCount,
      totalAchievementCount,
      legacyRows: legacy,
    });
    accountBadgeBreakdown = computeAccountBadgeBreakdown({
      chars,
      professionRows: profRows,
      statRows: stRows,
      achievementRows: achRows,
    });

    const charName = new Map(chars.map((c) => [c.id, c.name]));
    recent = achRows
      .filter((a) => !!a.earned_at)
      .sort((a, b) => new Date(b.earned_at as string).getTime() - new Date(a.earned_at as string).getTime())
      .slice(0, 8)
      .map((a) => ({
        characterId: a.character_id,
        characterName: charName.get(a.character_id) ?? "Unknown",
        kind: a.kind,
        tier: a.tier,
        earnedAt: a.earned_at as string,
        label: labelFor(a.kind),
      }));
  }

  return {
    // A profile row missing AND zero characters means this userId doesn't
    // correspond to anyone real (or, for the public page, the page shouldn't
    // pretend it found someone) - the caller decides what to show for that.
    found: !!profileRow || chars.length > 0,
    userId,
    displayName: profileRow?.display_name ?? "Adventurer",
    memberSince: authCreatedAt,
    avatarIcon: profileRow?.avatar_icon ?? null,
    bannerStyle: profileRow?.banner_style ?? null,
    motto: profileRow?.motto ?? null,
    characters: chars,
    mergedItems,
    itemOwner,
    recent,
    accountBadges: ((accountAchievementRows ?? []) as { kind: AccountAchievementKind }[]).map((r) => r.kind),
    accountBadgeProgress,
    accountBadgeBreakdown,
    // Only count achievements that actually earn Legacy Points - matching
    // the same "don't include any that don't give legacy points" fix made
    // to AccountLegacyPage.tsx's own completed count (2026-09-30). Without
    // this, a completed class/profession achievement worth 0 points bumped
    // "completed" to 1 while points stayed at 0, which read as a bug.
    legacyEarned: legacy.filter((r) => r.completed && (r.ui_points ?? 0) > 0).length,
    legacyPoints: legacy.filter((r) => r.completed).reduce((sum, r) => sum + (r.ui_points ?? 0), 0),
    iconOverrides,
  };
}
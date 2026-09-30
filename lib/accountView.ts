import type { SupabaseClient } from "@supabase/supabase-js";
import { buildAchievementItems, type AchievementBoardItem } from "../app/achievementBoard";
import {
  TIERED_ACHIEVEMENT_KINDS,
  tierLabel,
  type AchievementTier,
  type TieredAchievementKind,
} from "./achievements";
import { FLAT_ACHIEVEMENT_NAME } from "./achievementCategories";
import type { AccountAchievementKind } from "./accountAchievements";

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
};

type AchievementRowDB = { character_id: string; kind: string; tier: AchievementTier | null; earned_at: string | null };
type StatRow = { character_id: string; category: string; name: string; value: string };
type ProfessionRow = { character_id: string; recipes: unknown[] | null };
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
  legacyEarned: number;
  legacyPoints: number;
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
  const [{ data: profileRow }, { data: characterRows }, { data: accountAchievementRows }, { data: legacyRows }] =
    await Promise.all([
      client
        .from("profiles")
        .select("display_name, avatar_icon, banner_style, motto")
        .eq("id", userId)
        .maybeSingle(),
      client
        .from("characters")
        .select("id, name, level, class, race, character_type, time_played_hours, money_copper")
        .eq("user_id", userId),
      client.from("account_achievements").select("kind").eq("user_id", userId),
      client.from("account_legacy_achievements").select("completed, ui_points").eq("user_id", userId),
    ]);

  const chars = (characterRows ?? []) as CharacterRow[];
  const characterIds = chars.map((c) => c.id);

  let mergedItems: AchievementBoardItem[] = [];
  let itemOwner = new Map<string, string>();
  let recent: RecentAchievement[] = [];

  if (characterIds.length > 0) {
    const [{ data: achievementRows }, { data: statRows }, { data: professionRows }] = await Promise.all([
      client.from("achievements").select("character_id, kind, tier, earned_at").in("character_id", characterIds),
      client
        .from("character_statistics")
        .select("character_id, category, name, value")
        .in("character_id", characterIds),
      client.from("character_professions").select("character_id, recipes").in("character_id", characterIds),
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
    for (const p of profRows) {
      const count = Array.isArray(p.recipes) ? p.recipes.length : 0;
      recipesByChar.set(p.character_id, (recipesByChar.get(p.character_id) ?? 0) + count);
    }

    const perCharacterItems = chars.map((c) => ({
      characterId: c.id,
      items: buildAchievementItems({
        achievementRows: achByChar.get(c.id) ?? [],
        statRows: statsByChar.get(c.id) ?? [],
        recipesCount: recipesByChar.get(c.id) ?? 0,
        hoursPlayed: c.time_played_hours ?? 0,
      }),
    }));
    const merged = mergeAccountItems(perCharacterItems);
    mergedItems = merged.items;
    itemOwner = merged.ownerByKey;

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

  const legacy = (legacyRows ?? []) as LegacyRow[];

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
    legacyEarned: legacy.filter((r) => r.completed).length,
    legacyPoints: legacy.filter((r) => r.completed).reduce((sum, r) => sum + (r.ui_points ?? 0), 0),
  };
}

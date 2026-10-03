import type { SupabaseClient } from "@supabase/supabase-js";
// Type-only import, erased at compile time - safe to pull from a "use
// client" component file without dragging it (or React) into this
// server-usable module. Reusing the exact shape StatisticsCard.tsx already
// expects means the per-character tab on the new Statistics page can just
// hand it this data directly, no reshaping needed.
import type { StatisticRow } from "../app/character/[id]/StatisticsCard";

// Account Statistics page (2026-10-03, "Statistics should go to a tab with
// account-wide statistics plus an area with all character statistics but
// they are like in their own tab to not overload info") - loads every
// synced character's raw character_statistics rows once, then hands back
// both shapes the page needs: grouped per character (for the per-character
// tabs, fed straight into the existing StatisticsCard) and summed into one
// account-wide total per stat name (for the top section).

export type AggregatedStat = { category: string; name: string; total: number };

// Only stats whose value parses as a plain number get aggregated - a
// "Battleground played the most" stat (its value is a zone NAME, not a
// number) or a money stat (Blizzard's raw texture-string format, see
// StatisticsCard.tsx's own parser) can't be meaningfully summed across
// characters without either throwing away information or re-implementing
// that texture-string math a second time here. Scope deliberately kept to
// "the numbers that are safe to add together" rather than attempting every
// stat type.
export function aggregateNumericStatistics(rows: { category: string; name: string; value: string }[]): AggregatedStat[] {
  const byKey = new Map<string, AggregatedStat>();
  for (const r of rows) {
    const n = Number(r.value.replace(/,/g, ""));
    if (!Number.isFinite(n)) continue;
    const key = `${r.category}|||${r.name}`;
    const existing = byKey.get(key);
    if (existing) existing.total += n;
    else byKey.set(key, { category: r.category, name: r.name, total: n });
  }
  return Array.from(byKey.values()).sort((a, b) => b.total - a.total);
}

export type AccountStatisticsData = {
  characters: { id: string; name: string }[];
  statsByCharacter: Record<string, StatisticRow[]>;
  aggregated: AggregatedStat[];
};

export async function loadAccountStatisticsData(client: SupabaseClient, userId: string): Promise<AccountStatisticsData> {
  const { data: characterRows } = await client
    .from("characters")
    .select("id, name, hidden, include_in_statistics")
    .eq("user_id", userId)
    .order("level", { ascending: false });
  const allCharacters = (characterRows ?? []) as { id: string; name: string; hidden: boolean; include_in_statistics: boolean }[];
  // Character Settings (2026-10-03, sql/account-settings.sql) - a hidden
  // character doesn't get a tab here at all (this page is reachable by
  // anyone, same as Account Achievements/Activity - see loadAccountViewData's
  // own comment on why there's no owner-vs-visitor branch at this layer).
  const characters = allCharacters.filter((c) => !c.hidden);
  const characterIds = characters.map((c) => c.id);
  // Separate from `hidden` - a character can keep its own stats tab while
  // being left out of the combined account-wide total (e.g. a twink/test
  // character whose numbers would just skew the aggregate).
  const statsCountTowardTotal = new Set(characters.filter((c) => c.include_in_statistics).map((c) => c.id));

  if (characterIds.length === 0) {
    return { characters: [], statsByCharacter: {}, aggregated: [] };
  }

  const { data: statRows } = await client
    .from("character_statistics")
    .select("character_id, category, name, value")
    .in("character_id", characterIds);
  const rows = (statRows ?? []) as { character_id: string; category: string; name: string; value: string }[];

  const statsByCharacter: Record<string, StatisticRow[]> = {};
  for (const c of characters) statsByCharacter[c.id] = [];
  for (const r of rows) {
    statsByCharacter[r.character_id]?.push({ category: r.category, name: r.name, value: r.value });
  }

  const aggregateRows = rows.filter((r) => statsCountTowardTotal.has(r.character_id));

  return {
    characters: characters.map((c) => ({ id: c.id, name: c.name })),
    statsByCharacter,
    aggregated: aggregateNumericStatistics(aggregateRows),
  };
}
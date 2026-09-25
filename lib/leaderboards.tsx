import type { SupabaseClient } from "@supabase/supabase-js";

export type LeaderboardEntry = {
  characterId: string;
  characterName: string;
  value: number;
};

export type Leaderboard = {
  key: string;
  label: string;
  entries: LeaderboardEntry[];
};

const TOP_N = 5;

// A curated set of Statistics-pane stats worth ranking the whole group on -
// deliberately not "all 159 stats", since most of them (weapon skills,
// individual battleground zone breakdowns, etc.) don't make for an
// interesting leaderboard. Matches the same real stat names the badge
// thresholds in lib/achievements.ts key off (see importLogic.ts's
// Statistics section), so "what earns a badge" and "what's ranked" stay
// consistent.
const LEADERBOARD_DEFS = [
  { key: "honorable_kills", label: "Honorable Kills", category: "Honorable Kills", name: "Total Honorable Kills" },
  { key: "gold_acquired", label: "Gold Acquired", category: "Wealth", name: "Total gold acquired" },
  { key: "quests_completed", label: "Quests Completed", category: "Quests", name: "Quests completed" },
  { key: "creatures_killed", label: "Creatures Killed", category: "Creatures", name: "Creatures killed" },
  { key: "killing_blows", label: "Killing Blows", category: "Killing Blows", name: "Total Killing Blows" },
] as const;

// Supabase returns the joined `characters` row as an object here (not an
// array) since character_id -> characters.id is many-to-one, but the
// generated types don't always reflect that - same defensive cast pattern
// already used for the prebis join in the character page.
function joinedCharacterName(row: { characters: unknown }): string | null {
  const c = row.characters;
  if (Array.isArray(c)) return (c[0] as { name?: string } | undefined)?.name ?? null;
  return (c as { name?: string } | null)?.name ?? null;
}

function parseValue(value: string): number | null {
  const n = Number(value.replace(/,/g, ""));
  return Number.isFinite(n) ? n : null;
}

// Builds the group's leaderboards straight from character_statistics -
// nothing precomputed or cached, so it's always as fresh as the last sync
// from anyone in the group. A leaderboard is left out entirely if nobody
// has a real (non "--") value for it yet, rather than showing an empty
// card.
export async function getLeaderboards(supabase: SupabaseClient): Promise<Leaderboard[]> {
  const results: Leaderboard[] = [];

  for (const def of LEADERBOARD_DEFS) {
    const { data } = await supabase
      .from("character_statistics")
      .select("character_id, value, characters(name)")
      .eq("category", def.category)
      .eq("name", def.name);

    const entries = (data ?? [])
      .map((row): LeaderboardEntry | null => {
        const value = parseValue(row.value as string);
        const characterName = joinedCharacterName(row as { characters: unknown });
        if (value == null || value <= 0 || !characterName) return null;
        return { characterId: row.character_id as string, characterName, value };
      })
      .filter((e): e is LeaderboardEntry => e !== null)
      .sort((a, b) => b.value - a.value)
      .slice(0, TOP_N);

    if (entries.length > 0) {
      results.push({ key: def.key, label: def.label, entries });
    }
  }

  // Boss Kills has no single aggregate stat - Blizzard tracks one counter
  // per boss - so this sums every entry under that category per character
  // instead of looking up one named stat, same approach the "boss_kills"
  // badge threshold uses in importLogic.ts.
  const { data: bossRows } = await supabase
    .from("character_statistics")
    .select("character_id, value, characters(name)")
    .eq("category", "Boss Kills");

  const bossTotals = new Map<string, { name: string; total: number }>();
  for (const row of bossRows ?? []) {
    const value = parseValue(row.value as string);
    const characterName = joinedCharacterName(row as { characters: unknown });
    if (value == null || !characterName) continue;
    const characterId = row.character_id as string;
    const existing = bossTotals.get(characterId) ?? { name: characterName, total: 0 };
    existing.total += value;
    bossTotals.set(characterId, existing);
  }
  const bossEntries = Array.from(bossTotals.entries())
    .map(([characterId, v]) => ({ characterId, characterName: v.name, value: v.total }))
    .filter((e) => e.value > 0)
    .sort((a, b) => b.value - a.value)
    .slice(0, TOP_N);
  if (bossEntries.length > 0) {
    results.push({ key: "boss_kills", label: "Boss Kills", entries: bossEntries });
  }

  return results;
}
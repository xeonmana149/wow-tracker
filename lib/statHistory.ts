import type { SupabaseClient } from "@supabase/supabase-js";

// Statistic history (2026-11-09, "can we attach times and dates to
// statistics?") - see sql/character-statistic-history.sql. Called from
// applyImport with the statistics as they were stored BEFORE this sync and
// the ones the addon just sent.
//
// Times come from the addon's statTimes (addon 1.9.5+): the moment it
// noticed each stat change in-game. Without one, the sync time is used.
//
// A character with no history yet first gets a baseline: one row per stat
// with is_baseline = true, holding the value already on file (dated when
// it was stored) or, for a stat never stored, the value just sent. Changes
// are recorded from then on. If the history table hasn't been created yet,
// this just warns and does nothing.

type Stat = { id: number; category: string; name: string; value: string };
export type StoredStat = { value: string; updated_at: string | null };

export function statTime(statTimes: Record<string, number> | undefined, statId: number): string | null {
  const t = statTimes?.[String(statId)];
  return typeof t === "number" && t > 0 ? new Date(t * 1000).toISOString() : null;
}

export async function recordStatHistory(
  supabase: SupabaseClient,
  character: { id: string; userId: string },
  previous: Map<number, StoredStat>,
  stats: Stat[],
  statTimes: Record<string, number> | undefined
): Promise<void> {
  const { count, error: countError } = await supabase
    .from("character_statistic_history")
    .select("id", { count: "exact", head: true })
    .eq("character_id", character.id);
  if (countError) {
    console.warn("recordStatHistory: history table unavailable:", countError.message);
    return;
  }

  const syncedAt = new Date().toISOString();
  const rows: Record<string, unknown>[] = [];
  const base = (s: Stat) => ({
    character_id: character.id,
    user_id: character.userId,
    stat_id: s.id,
    category: s.category,
    name: s.name,
  });
  const needsBaseline = (count ?? 0) === 0;

  for (const s of stats) {
    const before = previous.get(s.id);
    if (needsBaseline || !before) {
      // Starting point: what was already on file, else what just arrived
      rows.push({
        ...base(s),
        value: before ? before.value : s.value,
        previous_value: null,
        is_baseline: true,
        changed_at: before?.updated_at ?? syncedAt,
      });
      if (!before) continue;
    }
    if (before.value !== s.value) {
      rows.push({
        ...base(s),
        value: s.value,
        previous_value: before.value,
        is_baseline: false,
        changed_at: statTime(statTimes, s.id) ?? syncedAt,
      });
    }
  }

  for (let i = 0; i < rows.length; i += 500) {
    const { error } = await supabase.from("character_statistic_history").insert(rows.slice(i, i + 500));
    if (error) {
      console.warn("recordStatHistory: insert failed:", error.message);
      return;
    }
  }
}

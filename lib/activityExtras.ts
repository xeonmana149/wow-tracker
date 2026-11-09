import type { SupabaseClient } from "@supabase/supabase-js";
import { logActivity } from "./activityLog";

// Extra Activity feed events (2026-11-09, "I wish we had more stuff tracked
// like first completion of dungeons/raids and like pvp kills, the name of
// who killed you or who you killed with their level, class, name"):
//   - first dungeon/raid clears, from the game's Boss Kills statistics
//   - PvP kills and deaths, from the addon's PvP log (addon 1.9.5+)
//
// These go straight to activity_log via logActivity, NOT through
// importLogic's `events` array: that array is also bulk-inserted into the
// older activity_events table, whose `kind` CHECK constraint doesn't allow
// these kinds - one row it rejects would fail that whole batch.

type Character = { id: string; userId: string; name: string };

// ---------------------------------------------------------------------
// First dungeon / raid clears
// ---------------------------------------------------------------------
// The Statistics pane's "Boss Kills" category has one counter per dungeon
// or raid final boss, named like "Aku'mai kills (Blackfathom Deeps)", and
// "--" until the first kill. So a counter going from nothing to a number
// between two syncs is a first clear. A counter seen for the first time
// (a character's first sync, or a stat the addon only just started
// reporting) is treated as the starting point, not a clear - otherwise
// every boss already killed before this existed would flood the feed.

export const BOSS_KILLS_CATEGORY = "Boss Kills";

type Stat = { id: number; category: string; name: string; value: string };

function statNumber(value: string | null | undefined): number {
  const n = Number(String(value ?? "").replace(/,/g, ""));
  return Number.isFinite(n) ? n : 0;
}

// "Edwin VanCleef Kills (Deadmines)" -> { boss, place }
function parseBossStat(name: string): { boss: string; place: string | null } {
  const m = /^(.*?)\s+kills\s*(?:\((.*)\))?\s*$/i.exec(name);
  return m ? { boss: m[1], place: m[2] ?? null } : { boss: name, place: null };
}

export function firstBossKillLabel(characterName: string, statName: string): string {
  const { boss, place } = parseBossStat(statName);
  return place
    ? `${characterName} cleared ${place} for the first time - ${boss} defeated!`
    : `${characterName} defeated ${boss} for the first time!`;
}

// `previous` is what was stored for this character BEFORE this sync's
// statistics were saved (stat_id -> value)
export async function logFirstBossKills(
  supabase: SupabaseClient,
  character: Character,
  previous: Map<number, string>,
  stats: Stat[]
): Promise<void> {
  for (const s of stats) {
    if (s.category !== BOSS_KILLS_CATEGORY) continue;
    if (!previous.has(s.id)) continue;
    if (statNumber(previous.get(s.id)) > 0 || statNumber(s.value) <= 0) continue;
    await logActivity(supabase, {
      userId: character.userId,
      characterId: character.id,
      characterName: character.name,
      kind: "boss_first_kill",
      label: firstBossKillLabel(character.name, s.name),
    });
  }
}

// ---------------------------------------------------------------------
// PvP kills and deaths
// ---------------------------------------------------------------------

export type PvpLogEntry = {
  // Unix seconds, from the game client's clock
  t?: number;
  kind: "kill" | "death";
  name?: string;
  realm?: string;
  // -1 means "??" (10+ levels above you); missing means never seen
  level?: number;
  // The game's English tokens, e.g. "WARRIOR", "Scourge", "NightElf"
  class?: string;
  race?: string;
  zone?: string;
};

const RACE_NAMES: Record<string, string> = {
  Scourge: "Undead",
  NightElf: "Night Elf",
  BloodElf: "Blood Elf",
  VoidElf: "Void Elf",
  HighmountainTauren: "Highmountain Tauren",
  LightforgedDraenei: "Lightforged Draenei",
  DarkIronDwarf: "Dark Iron Dwarf",
  KulTiran: "Kul Tiran",
  ZandalariTroll: "Zandalari Troll",
  MagharOrc: "Mag'har Orc",
};

function raceName(token?: string): string | null {
  if (!token) return null;
  return RACE_NAMES[token] ?? token.replace(/([a-z])([A-Z])/g, "$1 $2");
}

function className(token?: string): string | null {
  if (!token) return null;
  if (token === "DEATHKNIGHT") return "Death Knight";
  if (token === "DEMONHUNTER") return "Demon Hunter";
  return token.charAt(0) + token.slice(1).toLowerCase();
}

// "(lvl 24 Orc Warrior)", "(lvl ?? Undead Rogue)", or "" if nothing known
function describe(e: PvpLogEntry): string {
  const parts: string[] = [];
  if (typeof e.level === "number") parts.push(`lvl ${e.level < 0 ? "??" : e.level}`);
  const race = raceName(e.race);
  const cls = className(e.class);
  if (race) parts.push(race);
  if (cls) parts.push(cls);
  return parts.length ? ` (${parts.join(" ")})` : "";
}

export function pvpLabel(characterName: string, e: PvpLogEntry): string {
  const who = e.name || "an unknown player";
  const where = e.zone ? ` in ${e.zone}` : "";
  return e.kind === "kill"
    ? `${characterName} killed ${who}${describe(e)}${where}`
    : `${characterName} was killed by ${who}${describe(e)}${where}`;
}

// The addon sends its whole recent log every sync, so each entry is matched
// against what's already posted (same character, kind and time) and only
// new ones are logged.
export async function logPvpEvents(
  supabase: SupabaseClient,
  character: Character,
  entries: PvpLogEntry[]
): Promise<void> {
  const valid = entries.filter(
    (e) => (e.kind === "kill" || e.kind === "death") && typeof e.t === "number" && e.t > 0
  );
  if (valid.length === 0) return;

  const times = valid.map((e) => new Date((e.t as number) * 1000).toISOString());
  const oldest = times.reduce((a, b) => (a < b ? a : b));
  const { data: existing, error } = await supabase
    .from("activity_log")
    .select("kind, created_at")
    .eq("character_id", character.id)
    .in("kind", ["pvp_kill", "pvp_death"])
    .gte("created_at", oldest);
  if (error) {
    console.warn("logPvpEvents: couldn't read existing entries:", error.message);
    return;
  }
  const posted = new Set(
    (existing ?? []).map((r: { kind: string; created_at: string }) => `${r.kind}|${Date.parse(r.created_at)}`)
  );

  for (let i = 0; i < valid.length; i++) {
    const e = valid[i];
    const kind = e.kind === "kill" ? "pvp_kill" : "pvp_death";
    const at = times[i];
    const key = `${kind}|${Date.parse(at)}`;
    if (posted.has(key)) continue;
    posted.add(key);
    await logActivity(supabase, {
      userId: character.userId,
      characterId: character.id,
      characterName: character.name,
      kind,
      label: pvpLabel(character.name, e),
      createdAt: at,
    });
  }
}

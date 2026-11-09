import type { SupabaseClient } from "@supabase/supabase-js";
import { logActivity } from "./activityLog";
import { statTime } from "./statHistory";

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
// statistics were saved (stat_id -> value). `statTimes` (addon 1.9.5+)
// dates the clear to the minute the addon saw the boss counter change;
// without it, the entry gets the sync time.
export async function logFirstBossKills(
  supabase: SupabaseClient,
  character: Character,
  previous: Map<number, string>,
  stats: Stat[],
  statTimes?: Record<string, number>
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
      createdAt: statTime(statTimes, s.id) ?? undefined,
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

// ---------------------------------------------------------------------
// Posting addon logs
// ---------------------------------------------------------------------
// The addon sends its whole recent log (PvP, Auction House, items) every
// sync, so each entry is matched against what's already posted for this
// character - same kind, time and text - and only new ones are logged.
// Matching on the text too means two different items from one trade (same
// second) are both kept.

type NewEntry = { kind: string; label: string; t: number };

async function postNewEntries(
  supabase: SupabaseClient,
  character: Character,
  kinds: string[],
  entries: NewEntry[]
): Promise<void> {
  if (entries.length === 0) return;
  const oldest = new Date(Math.min(...entries.map((e) => e.t)) * 1000).toISOString();
  const { data: existing, error } = await supabase
    .from("activity_log")
    .select("kind, label, created_at")
    .eq("character_id", character.id)
    .in("kind", kinds)
    .gte("created_at", oldest);
  if (error) {
    console.warn("postNewEntries: couldn't read existing entries:", error.message);
    return;
  }
  const keyOf = (kind: string, label: string, ms: number) => `${kind}|${Math.floor(ms / 1000)}|${label}`;
  const posted = new Set(
    (existing ?? []).map((r: { kind: string; label: string; created_at: string }) =>
      keyOf(r.kind, r.label, Date.parse(r.created_at))
    )
  );
  for (const e of entries) {
    const key = keyOf(e.kind, e.label, e.t * 1000);
    if (posted.has(key)) continue;
    posted.add(key);
    await logActivity(supabase, {
      userId: character.userId,
      characterId: character.id,
      characterName: character.name,
      kind: e.kind,
      label: e.label,
      createdAt: new Date(e.t * 1000).toISOString(),
    });
  }
}

const hasTime = (e: { t?: number }): e is { t: number } => typeof e.t === "number" && e.t > 0;

export async function logPvpEvents(
  supabase: SupabaseClient,
  character: Character,
  entries: PvpLogEntry[]
): Promise<void> {
  const rows = entries
    .filter((e) => (e.kind === "kill" || e.kind === "death") && hasTime(e))
    .map((e) => ({
      kind: e.kind === "kill" ? "pvp_kill" : "pvp_death",
      label: pvpLabel(character.name, e),
      t: e.t as number,
    }));
  await postNewEntries(supabase, character, ["pvp_kill", "pvp_death"], rows);
}

// ---------------------------------------------------------------------
// Auction House sales and purchases (2026-11-09, "how about auction house
// tracking like big sales or big buys maybe 50 gold+?" / "list the item
// too")
// ---------------------------------------------------------------------
// From the addon's auctionEvents log (addon 1.9.5+), read from Auction
// House mail invoices. The addon logs every sale and purchase; only ones
// at or above AUCTION_MIN_COPPER reach the feed.

export const AUCTION_MIN_COPPER = 50 * 10000; // 50 gold

export type AuctionLogEntry = {
  // Unix seconds - when the mail arrived (worked out from its expiry)
  t?: number;
  kind: "sale" | "purchase";
  item?: string;
  count?: number;
  // The buyer (for a sale) or seller (for a purchase)
  player?: string;
  // Copper - the final auction price
  price?: number;
  // Item quality (4 epic, 5 legendary) when the client knew it
  quality?: number;
};

// 725000 -> "72g 50s", 500000 -> "50g"
export function formatGold(copper: number): string {
  const g = Math.floor(copper / 10000);
  const s = Math.floor((copper % 10000) / 100);
  const c = copper % 100;
  const parts: string[] = [];
  if (g) parts.push(`${g.toLocaleString()}g`);
  if (s) parts.push(`${s}s`);
  if (c && !g) parts.push(`${c}c`);
  return parts.join(" ") || "0c";
}

const QUALITY_NAMES: Record<number, string> = { 4: "Epic", 5: "Legendary", 6: "Artifact" };

// "Thunderfury (Legendary)", "Runecloth x20" - quality only for epic+
function itemText(item: string | undefined, quality?: number, count?: number): string {
  const name = item || "an item";
  const qty = typeof count === "number" && count > 1 ? ` x${count}` : "";
  const q = typeof quality === "number" ? QUALITY_NAMES[quality] : undefined;
  return `${name}${qty}${q ? ` (${q})` : ""}`;
}

export function auctionLabel(characterName: string, e: AuctionLogEntry): string {
  const item = itemText(e.item, e.quality, e.count);
  const price = formatGold(e.price ?? 0);
  return e.kind === "sale"
    ? `${characterName} sold ${item} on the Auction House for ${price}${e.player ? ` to ${e.player}` : ""}`
    : `${characterName} bought ${item} from the Auction House for ${price}${e.player ? ` from ${e.player}` : ""}`;
}

// Posted when it's 50g+ or the item is epic or better
export async function logAuctionEvents(
  supabase: SupabaseClient,
  character: Character,
  entries: AuctionLogEntry[]
): Promise<void> {
  const rows = entries
    .filter(
      (e) =>
        (e.kind === "sale" || e.kind === "purchase") &&
        hasTime(e) &&
        typeof e.price === "number" &&
        (e.price >= AUCTION_MIN_COPPER || (typeof e.quality === "number" && e.quality >= 4))
    )
    .map((e) => ({
      kind: e.kind === "sale" ? "ah_sale" : "ah_purchase",
      label: auctionLabel(character.name, e),
      t: e.t as number,
    }));
  await postNewEntries(supabase, character, ["ah_sale", "ah_purchase"], rows);
}

// ---------------------------------------------------------------------
// Epic and legendary items (2026-11-09, "tracking when epics/legendaries
// are won in dungeon/raid/loot roll. or traded or crafted ... with the
// roll number too")
// ---------------------------------------------------------------------
// From the addon's itemEvents log (addon 1.9.5+), which only holds epic
// and better.

export type ItemLogEntry = {
  t?: number;
  kind: "won" | "looted" | "crafted" | "trade_gave" | "trade_got";
  item?: string;
  itemId?: number;
  quality?: number;
  count?: number;
  // Where it happened - the dungeon/raid name inside one, else the zone
  where?: string;
  // Loot rolls: your roll and its type (Need / Greed / Disenchant)
  roll?: number;
  rollType?: string;
  // Trades: who with
  player?: string;
};

const ITEM_KINDS: Record<ItemLogEntry["kind"], string> = {
  won: "item_won",
  looted: "item_looted",
  crafted: "item_crafted",
  trade_gave: "item_traded",
  trade_got: "item_traded",
};
export const ITEM_ACTIVITY_KINDS = ["item_won", "item_looted", "item_crafted", "item_traded"];

export function itemLabel(characterName: string, e: ItemLogEntry): string {
  const item = itemText(e.item, e.quality, e.count);
  const where = e.where ? ` in ${e.where}` : "";
  const who = e.player || "someone";
  switch (e.kind) {
    case "won": {
      const roll =
        typeof e.roll === "number" ? ` with a ${e.rollType ? `${e.rollType} ` : ""}roll of ${e.roll}` : "";
      return `${characterName} won ${item}${where}${roll}`;
    }
    case "looted":
      return `${characterName} looted ${item}${where}`;
    case "crafted":
      return `${characterName} crafted ${item}`;
    case "trade_got":
      return `${characterName} got ${item} from ${who} in a trade`;
    case "trade_gave":
      return `${characterName} traded ${item} to ${who}`;
  }
}

export async function logItemEvents(
  supabase: SupabaseClient,
  character: Character,
  entries: ItemLogEntry[]
): Promise<void> {
  const rows = entries
    .filter((e) => e.kind in ITEM_KINDS && hasTime(e) && (typeof e.quality !== "number" || e.quality >= 4))
    .map((e) => ({ kind: ITEM_KINDS[e.kind], label: itemLabel(character.name, e), t: e.t as number }));
  await postNewEntries(supabase, character, ITEM_ACTIVITY_KINDS, rows);
}

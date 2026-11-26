// Lifetime gathering and loot counters (addon 1.9.20+, 2026-11-26). The
// addon's Stats.lua keeps them per character; each sync stores the latest
// in characters.loot_stats (sql/loot-stats.sql). They only count up, so
// the newest report simply replaces the old one.

export const GATHER_KINDS = ["herb", "ore", "skin", "fish"] as const;
export const LOOT_WHERE = ["world", "dungeon", "raid"] as const;
export const LOOT_QUALITY = ["green", "blue", "epic", "legendary"] as const;

export type GatherKind = (typeof GATHER_KINDS)[number];
export type LootWhere = (typeof LOOT_WHERE)[number];
export type LootQuality = (typeof LOOT_QUALITY)[number];

export type LootFind = { link: string; name: string; q: LootQuality; where: LootWhere; at: number };

export type LootStats = {
  since: number | null;
  gather: Record<GatherKind, { n: number; items: number }>;
  chests: number;
  opened: number;
  drops: Record<LootWhere, Record<LootQuality, number>>;
  recent: LootFind[];
};

export const GATHER_LABEL: Record<GatherKind, string> = {
  herb: "Herbs gathered",
  ore: "Ore mined",
  skin: "Creatures skinned",
  fish: "Fish caught",
};

export const QUALITY_LABEL: Record<LootQuality, string> = {
  green: "Uncommon",
  blue: "Rare",
  epic: "Epic",
  legendary: "Legendary",
};

export const QUALITY_COLOR: Record<LootQuality, string> = {
  green: "#1eff00",
  blue: "#0070dd",
  epic: "#a335ee",
  legendary: "#ff8000",
};

export const WHERE_LABEL: Record<LootWhere, string> = { world: "World", dungeon: "Dungeons", raid: "Raids" };

function count(v: unknown): number {
  const n = typeof v === "number" ? v : typeof v === "string" ? Number(v) : NaN;
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
}

export function emptyLootStats(): LootStats {
  const drops = {} as LootStats["drops"];
  for (const w of LOOT_WHERE) drops[w] = { green: 0, blue: 0, epic: 0, legendary: 0 };
  const gather = {} as LootStats["gather"];
  for (const k of GATHER_KINDS) gather[k] = { n: 0, items: 0 };
  return { since: null, gather, chests: 0, opened: 0, drops, recent: [] };
}

// The addon's table (or what's stored) -> a clean LootStats. Anything
// missing or malformed counts as 0, so old or partial data never breaks a page.
export function normalizeLootStats(raw: unknown): LootStats | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  const out = emptyLootStats();
  out.since = count(r.since) || null;
  const gather = (r.gather ?? {}) as Record<string, Record<string, unknown> | undefined>;
  for (const k of GATHER_KINDS) {
    out.gather[k] = { n: count(gather[k]?.n), items: count(gather[k]?.items) };
  }
  out.chests = count(r.chests);
  out.opened = count(r.opened);
  const drops = (r.drops ?? {}) as Record<string, Record<string, unknown> | undefined>;
  for (const w of LOOT_WHERE) {
    for (const q of LOOT_QUALITY) out.drops[w][q] = count(drops[w]?.[q]);
  }
  const recent = Array.isArray(r.recent) ? r.recent : [];
  for (const e of recent.slice(-25)) {
    if (!e || typeof e !== "object") continue;
    const f = e as Record<string, unknown>;
    const link = typeof f.link === "string" ? f.link.slice(0, 400) : "";
    const name = link.match(/\|h\[(.+?)\]\|h/)?.[1] ?? "";
    const q = LOOT_QUALITY.includes(f.q as LootQuality) ? (f.q as LootQuality) : null;
    const where = LOOT_WHERE.includes(f.where as LootWhere) ? (f.where as LootWhere) : "world";
    if (!name || !q) continue;
    out.recent.push({ link, name, q, where, at: count(f.at) });
  }
  return out;
}

export function addLootStats(a: LootStats, b: LootStats): LootStats {
  const out = emptyLootStats();
  out.since = [a.since, b.since].filter((x): x is number => !!x).sort((x, y) => x - y)[0] ?? null;
  for (const k of GATHER_KINDS) {
    out.gather[k] = { n: a.gather[k].n + b.gather[k].n, items: a.gather[k].items + b.gather[k].items };
  }
  out.chests = a.chests + b.chests;
  out.opened = a.opened + b.opened;
  for (const w of LOOT_WHERE) for (const q of LOOT_QUALITY) out.drops[w][q] = a.drops[w][q] + b.drops[w][q];
  out.recent = [...a.recent, ...b.recent].sort((x, y) => y.at - x.at).slice(0, 25);
  return out;
}

export function totalDrops(s: LootStats, q: LootQuality): number {
  return LOOT_WHERE.reduce((n, w) => n + s.drops[w][q], 0);
}

export function hasAnyLoot(s: LootStats | null): boolean {
  if (!s) return false;
  return (
    GATHER_KINDS.some((k) => s.gather[k].n > 0) ||
    s.chests > 0 ||
    s.opened > 0 ||
    LOOT_QUALITY.some((q) => totalDrops(s, q) > 0)
  );
}

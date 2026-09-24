import type { SupabaseClient } from "@supabase/supabase-js";
import { blizzardGet } from "./blizzard";

// The confirmed base dataset for WoW Forever's item data - see the
// 2026-09-24 investigation: known classic items (small IDs) return real
// data here, and IDs Blizzard doesn't recognize (404) are genuine
// Forever-only items with no official data available yet.
//
// IMPORTANT caveat, also confirmed 2026-09-24: Blizzard's classic API is
// the frozen ORIGINAL vanilla dataset. WoW Forever reuses classic item IDs
// but can and does rebalance them (Runed Copper Belt, item 2857: Common
// with 86 Armor and no stats on Blizzard's API, but actually Uncommon with
// 91 Armor +3 Str +2 Sta in a real live Forever tooltip). So Blizzard's API
// is only trustworthy for rough structural info (name, slot, item class) -
// never for quality/armor/stats/price, which Forever can change freely. The
// only real ground truth for those is a live tooltip scanned off an actual
// player's client (see applyLiveObservation below), which always overwrites
// whatever baseline Blizzard gave us. An item nobody's ever equipped yet
// only has the unverified Blizzard baseline (or nothing at all, if it's
// Forever-only) - `verified` on the row says which case you're looking at.
// Exported so the bulk-seed script (scripts/bulk-seed-items.ts) uses the
// exact same namespace/region instead of a second hardcoded copy that could
// drift out of sync with this one.
export const ITEM_NAMESPACE = "static-classic1x-us";
export const ITEM_REGION = "us";

export type ItemSource = "classic_api" | "auto_new" | "manual";

export type ItemRow = {
  id: number;
  name: string;
  quality: string | null;
  quality_color: string | null;
  item_class: string | null;
  item_subclass: string | null;
  inventory_type: string | null;
  level: number | null;
  required_level: number | null;
  armor: number | null;
  damage_min: number | null;
  damage_max: number | null;
  weapon_speed: number | null;
  stats: unknown | null;
  sell_price: number | null;
  icon: number | null;
  source: ItemSource;
  raw: unknown | null;
  verified: boolean;
  tooltip: string[] | null;
};

// Blizzard's quality "type" enum -> the hex color the site already uses
// elsewhere for gear quality (matches WoW's own item-quality colors), and
// back the other way (a live tooltip gives us the color directly, from the
// game's own rendering, and we need the quality name from that).
const QUALITY_COLORS: Record<string, string> = {
  POOR: "9d9d9d",
  COMMON: "ffffff",
  UNCOMMON: "1eff00",
  RARE: "0070dd",
  EPIC: "a335ee",
  LEGENDARY: "ff8000",
};
const QUALITY_BY_COLOR: Record<string, string> = Object.fromEntries(
  Object.entries(QUALITY_COLORS).map(([quality, color]) => [color, quality])
);

type BlizzardItemBody = {
  id: number;
  name?: { en_US?: string };
  quality?: { type?: string };
  item_class?: { name?: { en_US?: string } };
  item_subclass?: { name?: { en_US?: string } };
  inventory_type?: { type?: string };
  level?: number;
  required_level?: number;
  sell_price?: number;
  preview_item?: {
    armor?: { value?: number };
    weapon_damage?: {
      min_damage?: { value?: number };
      max_damage?: { value?: number };
    };
    weapon_attack_speed?: { value?: number };
    stats?: { type?: { type?: string }; value?: number }[];
  };
};

function rowFromBlizzard(id: number, body: BlizzardItemBody): ItemRow {
  const qualityType = body.quality?.type ?? null;
  return {
    id,
    name: body.name?.en_US ?? `Item ${id}`,
    quality: qualityType,
    quality_color: qualityType ? QUALITY_COLORS[qualityType] ?? null : null,
    item_class: body.item_class?.name?.en_US ?? null,
    item_subclass: body.item_subclass?.name?.en_US ?? null,
    inventory_type: body.inventory_type?.type ?? null,
    level: body.level ?? null,
    required_level: body.required_level ?? null,
    armor: body.preview_item?.armor?.value ?? null,
    damage_min: body.preview_item?.weapon_damage?.min_damage?.value ?? null,
    damage_max: body.preview_item?.weapon_damage?.max_damage?.value ?? null,
    weapon_speed: body.preview_item?.weapon_attack_speed?.value ?? null,
    stats: body.preview_item?.stats ?? null,
    sell_price: body.sell_price ?? null,
    icon: null, // Blizzard doesn't give us the client-side fileID the rest
                // of the site uses for icons - filled in from the export's
                // own icon capture instead, when available (see below).
    source: "classic_api",
    raw: body,
    verified: false, // unconfirmed - Forever may have rebalanced this item;
                      // see the caveat above. Only a real scanned tooltip
                      // (applyLiveObservation) ever sets this true.
    tooltip: null,
  };
}

function placeholderRow(id: number, fallback: { name?: string; icon?: number | null }): ItemRow {
  return {
    id,
    name: fallback.name ?? `Unknown Item ${id}`,
    quality: null,
    quality_color: null,
    item_class: null,
    item_subclass: null,
    inventory_type: null,
    level: null,
    required_level: null,
    armor: null,
    damage_min: null,
    damage_max: null,
    weapon_speed: null,
    stats: null,
    sell_price: null,
    icon: fallback.icon ?? null,
    source: "auto_new",
    raw: null,
    verified: false,
    tooltip: null,
  };
}

// Runs `fn` over `items` with at most `limit` calls in flight at once,
// instead of either doing them all one-at-a-time (slow when there are
// thousands, like the classic-catalog bulk-seed job) or all at once (which
// would hammer Blizzard's API with hundreds of simultaneous requests and
// risk getting rate-limited). Order of `results` matches `items`.
async function mapWithConcurrency<T, R>(
  items: T[],
  limit: number,
  fn: (item: T) => Promise<R>
): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  async function worker() {
    while (true) {
      const i = next++;
      if (i >= items.length) return;
      results[i] = await fn(items[i]);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return results;
}

// Makes sure every item ID in `wanted` has a row in the `items` table,
// fetching an (unverified) baseline from Blizzard for anything missing, or
// creating a bare placeholder (source = "auto_new") when Blizzard doesn't
// know the item at all (a genuine WoW Forever-only item). Use this for
// items with no live tooltip to go on yet (e.g. seeding the browsable
// database ahead of anyone actually wearing something) - whenever a live
// tooltip IS available, call applyLiveObservation instead/as well, since
// that's the trustworthy source and always wins.
//
// Only ever touches items that don't already have a row - never re-fetches
// or overwrites an existing row (verified or not), so this can't clobber a
// real observation or a manual edit.
export async function ensureItemsExist(
  supabase: SupabaseClient,
  wanted: number[],
  fallbacks: Map<number, { name?: string; icon?: number | null }>
): Promise<void> {
  const uniqueIds = Array.from(new Set(wanted)).filter((id) => Number.isFinite(id) && id > 0);
  if (uniqueIds.length === 0) return;

  const { data: existing, error: selectError } = await supabase
    .from("items")
    .select("id")
    .in("id", uniqueIds);
  if (selectError) throw new Error(selectError.message);

  const existingIds = new Set((existing ?? []).map((r: { id: number }) => r.id));
  const missingIds = uniqueIds.filter((id) => !existingIds.has(id));
  if (missingIds.length === 0) return;

  const fetched = await mapWithConcurrency(missingIds, 8, async (id): Promise<ItemRow | null> => {
    const fallback = fallbacks.get(id) ?? {};
    try {
      const result = await blizzardGet(ITEM_REGION, `/data/wow/item/${id}`, {
        namespace: ITEM_NAMESPACE,
      });
      if (result.ok) {
        const row = rowFromBlizzard(id, result.body as BlizzardItemBody);
        row.icon = fallback.icon ?? row.icon;
        return row;
      }
      // 404 (or any other non-ok status) - Blizzard doesn't have this
      // item, so it's genuinely new. Placeholder now, fill in by hand later.
      return placeholderRow(id, fallback);
    } catch {
      // Network/token error - don't fail the whole sync over an item
      // lookup; just skip it for now and try again on a future sync.
      return null;
    }
  });
  const rows = fetched.filter((row): row is ItemRow => row !== null);

  if (rows.length === 0) return;
  const { error: insertError } = await supabase.from("items").upsert(rows, { onConflict: "id" });
  if (insertError) throw new Error(insertError.message);
}

export type ParsedTooltipStats = {
  armor?: number;
  damage_min?: number;
  damage_max?: number;
  weapon_speed?: number;
  required_level?: number;
  sell_price?: number;
  stats?: { type: string; value: number }[];
};

const ARMOR_RE = /^(\d+)\s+Armor$/;
const STAT_RE = /^\+(\d+)\s+([A-Za-z][A-Za-z ]*)$/;
const DAMAGE_RE = /^([\d.]+)\s*-\s*([\d.]+)\s+Damage\s+Speed\s+([\d.]+)$/;
const REQ_LEVEL_RE = /^Requires Level (\d+)$/;
const SELL_GOLD_RE = /(\d+)\{gold\}/;
const SELL_SILVER_RE = /(\d+)\{silver\}/;
const SELL_COPPER_RE = /(\d+)\{copper\}/;

// Turns the addon's scanned tooltip lines (already stripped of WoW's inline
// markup - see stripMarkup() in the addon) into structured fields. Only
// handles the lines that show up as flat "+N Stat" bonuses; "Equip:"-
// prefixed proc/aura effects are left as plain tooltip text for now rather
// than modeled as data, since fully representing procs is a much bigger job
// than basic stat totals need.
export function parseLiveTooltip(lines: string[]): ParsedTooltipStats {
  const out: ParsedTooltipStats = {};
  const stats: { type: string; value: number }[] = [];

  for (const line of lines) {
    let m: RegExpMatchArray | null;
    if ((m = line.match(ARMOR_RE))) {
      out.armor = Number(m[1]);
      continue;
    }
    if ((m = line.match(DAMAGE_RE))) {
      out.damage_min = Number(m[1]);
      out.damage_max = Number(m[2]);
      out.weapon_speed = Number(m[3]);
      continue;
    }
    if ((m = line.match(REQ_LEVEL_RE))) {
      out.required_level = Number(m[1]);
      continue;
    }
    if (line.startsWith("Sell Price:")) {
      const gold = Number(line.match(SELL_GOLD_RE)?.[1] ?? 0);
      const silver = Number(line.match(SELL_SILVER_RE)?.[1] ?? 0);
      const copper = Number(line.match(SELL_COPPER_RE)?.[1] ?? 0);
      out.sell_price = gold * 10000 + silver * 100 + copper;
      continue;
    }
    if (!line.startsWith("Equip:") && (m = line.match(STAT_RE))) {
      stats.push({ type: m[2].trim(), value: Number(m[1]) });
      continue;
    }
  }

  if (stats.length > 0) out.stats = stats;
  return out;
}

// The authoritative path: records what an item ACTUALLY looks like in
// Forever right now, straight from a real player's scanned tooltip. Always
// overwrites whatever was on file before (Blizzard's unverified baseline,
// or an older observation), since a fresh live tooltip is the closest thing
// to ground truth this project has. Called for every equipped item on every
// sync - cheap (one upsert, no external API call) and self-correcting if
// Forever ever rebalances something again later.
export async function applyLiveObservation(
  supabase: SupabaseClient,
  itemId: number,
  observation: { name: string; color?: string | null; icon?: number | null; tooltip?: string[] | null }
): Promise<void> {
  if (!observation.tooltip || observation.tooltip.length === 0) return;

  const parsed = parseLiveTooltip(observation.tooltip);
  const color = observation.color?.toLowerCase() ?? null;
  const quality = color ? QUALITY_BY_COLOR[color] ?? null : null;

  const update: Record<string, unknown> = {
    name: observation.name,
    verified: true,
    tooltip: observation.tooltip,
  };
  if (color) update.quality_color = color;
  if (quality) update.quality = quality;
  if (observation.icon != null) update.icon = observation.icon;
  if (parsed.armor != null) update.armor = parsed.armor;
  if (parsed.damage_min != null) update.damage_min = parsed.damage_min;
  if (parsed.damage_max != null) update.damage_max = parsed.damage_max;
  if (parsed.weapon_speed != null) update.weapon_speed = parsed.weapon_speed;
  if (parsed.required_level != null) update.required_level = parsed.required_level;
  if (parsed.sell_price != null) update.sell_price = parsed.sell_price;
  if (parsed.stats != null) update.stats = parsed.stats;

  const { data: existing, error: selectError } = await supabase
    .from("items")
    .select("id")
    .eq("id", itemId)
    .maybeSingle();
  if (selectError) throw new Error(selectError.message);

  if (existing) {
    const { error } = await supabase.from("items").update(update).eq("id", itemId);
    if (error) throw new Error(error.message);
  } else {
    const { error } = await supabase
      .from("items")
      .insert({ id: itemId, source: "auto_new" as ItemSource, ...update });
    if (error) throw new Error(error.message);
  }
}
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

// Blizzard's classic database is a straight pull of the real game's data,
// including a scattering of internal-only rows that were never meant to be
// player-facing: QA/test items, dev placeholders (named like "[PH] ..."),
// and one-off unobtainable items that shipped in the data but never in the
// game (spotted so far: "Fabled Steed", "Shard of the Defiler"). These get
// flagged `hidden` rather than skipped outright - the row still exists (in
// case it's ever needed for a manual fix), it just never shows up in the
// Items search. A real scanned tooltip is strong proof an item genuinely
// exists in Forever regardless of what its name looks like, so
// applyLiveObservation always clears this flag if it was set.
// "test" is intentionally a plain substring match (no word boundaries) -
// Blizzard's QA items are inconsistently named ("Test Legendary", "Rings of
// Critical Testing", "Fishing Pole JeffTest"), so a stricter whole-word
// match was missing the ones with "test" glued onto another word.
// [PH] was start-anchored before, but it shows up elsewhere in a name too
// (not just as a prefix) - matching it anywhere catches those too. zzOLD is
// Blizzard's own convention for sorting a retired/renamed row to the bottom
// of their internal tools; UNUSED covers both "[UNUSED] Old Thing" and a
// bare "Unused Whatever" with no brackets at all.
const JUNK_NAME_PATTERNS = [
  /test/i,
  /\[ph\]/i,
  /\bdebug\b/i,
  /\bqa\b/i,
  /^monster - /i,
  /zzold/i,
  /\bunused\b/i,
];
const JUNK_NAMES = new Set([
  "Fabled Steed",
  "Shard of the Defiler",
  // A bare "PH" (no brackets) doesn't match the \[ph\] pattern above, so
  // this one-off needs listing by its exact name instead.
  "Nax PH Crit Plate Shoulders",
]);

export function isLikelyJunkItemName(name: string): boolean {
  if (JUNK_NAMES.has(name)) return true;
  return JUNK_NAME_PATTERNS.some((re) => re.test(name));
}

// 2026-09-24: confirmed against the user's actual seeded data that
// Blizzard's classic1x-us namespace also serves Season of Discovery items
// (and other non-vanilla additions) with no separate flag to tell them
// apart from real vanilla Classic content - see sql/items-migration-9.sql
// for the full writeup. There's a clean gap with zero real vanilla items
// between id 25,000 and 100,000, and everything sampled at 100,000+ is
// unmistakably non-vanilla (SoD's rune system, SoD questline flavor items,
// internal dev/test names), so this keeps any future bulk-seed run from
// reintroducing the same problem for IDs migration 9 didn't already cover.
export function isLikelyNonVanillaId(id: number): boolean {
  return id >= 100000;
}

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
  // Blizzard's own precomputed value (already accounts for the exact
  // damage/speed combo), stored as-is rather than recomputed from
  // damage_min/damage_max/weapon_speed - display rounded to 2 decimals.
  weapon_dps: number | null;
  // e.g. "Binds when equipped" / "Binds when picked up" - null means
  // Blizzard's data doesn't mark this item as binding at all (most
  // consumables, trade goods, etc).
  binding: string | null;
  durability: number | null;
  // One tooltip line per entry - covers a recipe's "Use: Teaches you how to
  // make X." and an item's own "Equip: ..." proc text, which both come from
  // the same part of Blizzard's response (see BlizzardItemBody.spells).
  spell_lines: string[] | null;
  // e.g. "Requires Blacksmithing (180)" - only present on recipes. Stored
  // pre-formatted (not split into {profession, level}) so it reuses the
  // exact same "Requires <Profession> (<N>)" line shape that
  // extractProfessionRequirement (lib/classRequirements.ts) already parses
  // out of a real scanned tooltip - one parser now covers both sources.
  profession_requirement: string | null;
  // e.g. "Requires Steel Bar (8), Strong Flux (2), ..." - only present on
  // recipes. Pre-formatted the same way as profession_requirement.
  reagents_text: string | null;
  // e.g. "Classes: Druid" - only present on some class-restricted items
  // (mostly tier sets); Blizzard's data has no such field at all for other
  // class-restricted items like Atiesh's 4 versions (those need the
  // hand-curated table in classRequirements.ts instead).
  classes_text: string | null;
  // e.g. "Stormrage Raiment (0/8)" - only present on tier-set pieces.
  item_set_line: string | null;
  // The set's OTHER pieces (this item's own name isn't included) - just
  // names, e.g. ["Stormrage Belt", "Stormrage Boots", ...].
  item_set_pieces: string[] | null;
  // e.g. ["(3) Set: Allows 15% of your Mana regeneration...", "(5) Set: ...", "(8) Set: ..."]
  item_set_bonuses: string[] | null;
  stats: unknown | null;
  sell_price: number | null;
  icon: number | null;
  // A named icon (e.g. "inv_sword_04"), resolved from Blizzard's item-media
  // endpoint - this is how a baseline/placeholder item (nobody's ever
  // equipped or scanned it) still gets a real icon instead of a blank tile.
  // `icon` (the numeric client fileID) is still preferred when a live
  // export actually captured one, since that's a direct, guaranteed-correct
  // reference; this is the fallback for everything that only ever came from
  // Blizzard's API.
  icon_name: string | null;
  source: ItemSource;
  raw: unknown | null;
  verified: boolean;
  tooltip: string[] | null;
  hidden: boolean;
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

// 2026-09-24 correction: the weapon damage/speed fields below used to be
// named weapon_damage/weapon_attack_speed, which don't actually exist
// anywhere in Blizzard's real response - a guess that was never checked
// against real data, so every baseline weapon silently got damage_min/
// damage_max/weapon_speed = null from day one (that's why the Items page
// was showing weapon cards with no damage line at all). Confirmed against
// an actual stored `raw` response: it's `preview_item.weapon.damage.
// {min_value,max_value}` and `preview_item.weapon.attack_speed.value`
// (in milliseconds - 2800 means Speed 2.80, so divide by 1000 to display).
// Blizzard also hands back a precomputed, more-precise dps value at
// `preview_item.weapon.dps.value` - used as-is rather than recomputed here.
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
    weapon?: {
      damage?: { min_value?: number; max_value?: number };
      attack_speed?: { value?: number };
      dps?: { value?: number };
    };
    binding?: { name?: { en_US?: string } };
    durability?: { value?: number };
    // Covers both a recipe's "Use: Teaches you how to make X." and an
    // item's own "Equip: ..." proc text - both live in the same array,
    // just with different description wording. Rendered as one tooltip
    // line per entry.
    spells?: { description?: { en_US?: string } }[];
    requirements?: {
      // A plain "Requires Level N" is already covered by the top-level
      // required_level field above; this is specifically a profession
      // requirement (e.g. "Requires Blacksmithing (180)" on a recipe) -
      // Blizzard nests it as requirements.skill, not requirements.level.
      skill?: { display_string?: { en_US?: string } };
      // Class-restricted items (mostly tier sets) - confirmed present here
      // for Stormrage Bracers ("Classes: Druid"), ready-formatted, though
      // NOT present at all for every class-restricted item (Atiesh's 4
      // versions have nothing here - see classRequirements.ts for that
      // separate, hand-curated case).
      playable_classes?: { display_string?: { en_US?: string } };
    };
    // Only present on recipe items (item_class "Recipe") - what it costs to
    // craft. Blizzard hands back a ready-made, already-localized summary
    // string here rather than making us build one from the itemized
    // reagents[] list, which is plenty for a tooltip line.
    recipe?: { reagents_display_string?: { en_US?: string } };
    // Only present on tier-set pieces. Blizzard hands back ready-formatted
    // strings for everything here too: the set name + progress ("Stormrage
    // Raiment (0/8)"), each other piece's name, and each set-bonus tier's
    // full text ("(3) Set: Allows 15% of your Mana regeneration...").
    set?: {
      display_string?: { en_US?: string };
      items?: { item?: { name?: { en_US?: string } } }[];
      effects?: { display_string?: { en_US?: string }; required_count?: number }[];
    };
    // Blizzard nests the stat's actual identity two levels down (type.type
    // is a SCREAMING_CASE code like "STRENGTH"; type.name is its localized
    // display name) - stored as-is here, then flattened to the plain
    // {type: string, value} shape the rest of the site expects (same shape
    // a live tooltip parses into) by rowFromBlizzard below. Storing the raw
    // nested object directly used to be the bug behind stat lines rendering
    // as "+3 [object Object]".
    stats?: { type?: { type?: string; name?: { en_US?: string } }; value?: number }[];
  };
};

// Blizzard's stat type only sometimes includes a ready-made display name;
// when it doesn't, this turns "DODGE_RATING" into "Dodge Rating" rather than
// showing the raw enum code.
function titleCaseStatType(raw: string): string {
  return raw
    .toLowerCase()
    .split("_")
    .filter(Boolean)
    .map((w) => w[0].toUpperCase() + w.slice(1))
    .join(" ");
}

export function normalizeStats(
  stats: { type?: { type?: string; name?: { en_US?: string } }; value?: number }[] | undefined
): { type: string; value: number }[] | null {
  if (!stats || stats.length === 0) return null;
  return stats
    .filter((s) => s.value != null)
    .map((s) => ({
      type: s.type?.name?.en_US ?? (s.type?.type ? titleCaseStatType(s.type.type) : "Stat"),
      value: s.value as number,
    }));
}

// Fetches the icon Blizzard actually renders for an item (a named asset,
// e.g. "inv_sword_04") via the item-media endpoint - a separate call from
// the plain item lookup, since Blizzard doesn't include it there. Used for
// anything that only ever came from Blizzard's API (never equipped/scanned
// by an actual player, so there's no addon-captured fileID to use instead).
export async function fetchItemIconName(id: number): Promise<string | null> {
  try {
    const res = await blizzardGet(ITEM_REGION, `/data/wow/media/item/${id}`, {
      namespace: ITEM_NAMESPACE,
    });
    if (!res.ok) return null;
    const body = res.body as { assets?: { key?: string; value?: string }[] };
    const iconAsset = body.assets?.find((a) => a.key === "icon");
    const match = iconAsset?.value ? /\/([^/]+)\.\w+$/.exec(iconAsset.value) : null;
    return match ? match[1] : null;
  } catch {
    return null;
  }
}

// Pulls every field this project actually displays out of a Blizzard
// preview_item block. Exported (not just used inline by rowFromBlizzard) so
// scripts/backfill-item-details.ts can re-derive these same fields from the
// `raw` column already sitting in the database, for the ~13,687 rows seeded
// before these fields existed, without calling Blizzard a second time.
export function extractPreviewItemDetails(previewItem: BlizzardItemBody["preview_item"] | undefined) {
  const weapon = previewItem?.weapon;
  const speedMs = weapon?.attack_speed?.value ?? null;
  const spellLines =
    previewItem?.spells
      ?.map((s) => s.description?.en_US)
      .filter((line): line is string => !!line) ?? null;
  const itemSetPieces =
    previewItem?.set?.items
      ?.map((i) => i.item?.name?.en_US)
      .filter((name): name is string => !!name) ?? null;
  const itemSetBonuses =
    previewItem?.set?.effects
      ?.map((e) => e.display_string?.en_US)
      .filter((line): line is string => !!line) ?? null;
  return {
    armor: previewItem?.armor?.value ?? null,
    damage_min: weapon?.damage?.min_value ?? null,
    damage_max: weapon?.damage?.max_value ?? null,
    // Blizzard gives attack speed in milliseconds (2800 = Speed 2.80).
    weapon_speed: speedMs != null ? speedMs / 1000 : null,
    weapon_dps: weapon?.dps?.value ?? null,
    binding: previewItem?.binding?.name?.en_US ?? null,
    durability: previewItem?.durability?.value ?? null,
    spell_lines: spellLines && spellLines.length > 0 ? spellLines : null,
    profession_requirement: previewItem?.requirements?.skill?.display_string?.en_US ?? null,
    reagents_text: previewItem?.recipe?.reagents_display_string?.en_US
      ? `Requires ${previewItem.recipe.reagents_display_string.en_US}`
      : null,
    // "Classes: Druid" - present for tier-set pieces like Stormrage Bracers,
    // but NOT present at all for other class-restricted items (e.g. Atiesh's
    // 4 versions) - those need the hand-curated table instead.
    classes_text: previewItem?.requirements?.playable_classes?.display_string?.en_US ?? null,
    item_set_line: previewItem?.set?.display_string?.en_US ?? null,
    item_set_pieces: itemSetPieces && itemSetPieces.length > 0 ? itemSetPieces : null,
    item_set_bonuses: itemSetBonuses && itemSetBonuses.length > 0 ? itemSetBonuses : null,
    stats: normalizeStats(previewItem?.stats),
  };
}

function rowFromBlizzard(id: number, body: BlizzardItemBody): ItemRow {
  const qualityType = body.quality?.type ?? null;
  const details = extractPreviewItemDetails(body.preview_item);
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
    armor: details.armor,
    damage_min: details.damage_min,
    damage_max: details.damage_max,
    weapon_speed: details.weapon_speed,
    weapon_dps: details.weapon_dps,
    binding: details.binding,
    durability: details.durability,
    spell_lines: details.spell_lines,
    profession_requirement: details.profession_requirement,
    reagents_text: details.reagents_text,
    classes_text: details.classes_text,
    item_set_line: details.item_set_line,
    item_set_pieces: details.item_set_pieces,
    item_set_bonuses: details.item_set_bonuses,
    stats: details.stats,
    sell_price: body.sell_price ?? null,
    icon: null, // Blizzard doesn't give us the client-side fileID the rest
                // of the site uses for icons - filled in from the export's
                // own icon capture instead, when available (see below).
    icon_name: null, // filled in by the caller via fetchItemIconName - kept
                      // out of this function so a plain item-detail lookup
                      // never implies a second network call happened.
    source: "classic_api",
    raw: body,
    verified: false, // unconfirmed - Forever may have rebalanced this item;
                      // see the caveat above. Only a real scanned tooltip
                      // (applyLiveObservation) ever sets this true.
    tooltip: null,
    // Only applied here (not placeholderRow below) - a placeholder means
    // Blizzard returned 404 for this id, i.e. it's genuinely unknown to
    // Blizzard's classic data, which is exactly what a real Forever-only
    // custom item looks like. The non-vanilla-id check only makes sense for
    // ids Blizzard DID recognize, coming back tagged as Season of Discovery
    // (or similar) content instead of real vanilla Classic.
    hidden: isLikelyJunkItemName(body.name?.en_US ?? "") || isLikelyNonVanillaId(id),
  };
}

function placeholderRow(id: number, fallback: { name?: string; icon?: number | null }): ItemRow {
  const name = fallback.name ?? `Unknown Item ${id}`;
  return {
    id,
    name,
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
    weapon_dps: null,
    binding: null,
    durability: null,
    spell_lines: null,
    profession_requirement: null,
    reagents_text: null,
    classes_text: null,
    item_set_line: null,
    item_set_pieces: null,
    item_set_bonuses: null,
    stats: null,
    sell_price: null,
    icon: fallback.icon ?? null,
    icon_name: null,
    source: "auto_new",
    raw: null,
    verified: false,
    hidden: isLikelyJunkItemName(name),
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
      const row = result.ok
        ? rowFromBlizzard(id, result.body as BlizzardItemBody)
        : // 404 (or any other non-ok status) - Blizzard doesn't have this
          // item, so it's genuinely new. Placeholder now, fill in by hand later.
          placeholderRow(id, fallback);
      row.icon = fallback.icon ?? row.icon;
      // Only bother asking Blizzard for a named icon when there's no
      // addon-captured fileID already - that's a direct, guaranteed-correct
      // reference, so a second lookup here would be pure waste.
      if (row.icon == null) {
        row.icon_name = await fetchItemIconName(id);
      }
      return row;
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
    // A real player actually has this item equipped/in their bags - proof
    // it's genuinely obtainable, overriding any earlier guess (from a
    // name-pattern match against Blizzard's baseline data) that it might
    // have been a QA/test/unobtainable row.
    hidden: false,
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
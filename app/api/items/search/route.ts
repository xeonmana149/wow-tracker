import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "../../../../lib/supabaseAdmin";

const VALID_QUALITIES = new Set(["POOR", "COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY"]);
const SORT_OPTIONS = new Set(["relevance", "name", "level", "quality"]);
// Same rank order the client used to apply itself when quality-sorting the
// old single 60-row batch - kept here too since "quality" sort now needs a
// scan-and-sort-in-JS pass (see below), not a plain database column order.
const QUALITY_RANK: Record<string, number> = {
  POOR: 0,
  COMMON: 1,
  UNCOMMON: 2,
  RARE: 3,
  EPIC: 4,
  LEGENDARY: 5,
};

// The AH-style category tabs, mapped to Blizzard's own item_class name
// text (populated straight from the Game Data API - see rowFromBlizzard in
// lib/items.ts). A couple of these are best guesses at the exact classic
// spelling (Ammo in particular - Blizzard's own item class for
// arrows/bullets has historically been called "Projectile" rather than
// "Ammo"), so if a tab comes back oddly empty or misses obvious items,
// check what item_class actually says for one of them in the items table
// and this list is the only place that needs adjusting.
const CATEGORY_CLASSES: Record<string, string[]> = {
  weapon: ["Weapon"],
  armor: ["Armor"],
  container: ["Container"],
  consumable: ["Consumable"],
  tradegoods: ["Trade Goods"],
  ammo: ["Projectile", "Ammo", "Quiver"],
  recipe: ["Recipe"],
  quest: ["Quest"],
  misc: ["Miscellaneous", "Junk", "Reagent", "Key", "Item Enhancement", "Gem", "Glyph"],
};

// The results list now scrolls with the rest of the page instead of living
// in its own scrollbox, with numbered pages underneath rather than an
// ever-growing single batch - this is how many rows one page holds.
const PAGE_SIZE = 30;
// A stat filter (and, since it has the same problem, a "quality" sort) can't
// be expressed as a plain database column filter/order - `stats` is a
// free-form jsonb array (see the comment further down) and quality is
// plain text with no rank column of its own. Both fall back to pulling this
// many name/quality-matching rows, filtering/sorting them in JS, and paging
// out of that in-memory list instead of paging the query itself. Large
// enough to cover realistic searches without scanning the whole table.
const JS_SCAN_LIMIT = 300;

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const q = (searchParams.get("q") ?? "").trim();
  const quality = (searchParams.get("quality") ?? "").trim().toUpperCase();
  const stat = (searchParams.get("stat") ?? "").trim();
  const categoryParam = (searchParams.get("category") ?? "").trim().toLowerCase();
  const category = categoryParam in CATEGORY_CLASSES ? categoryParam : "";
  const minLevel = Number(searchParams.get("minLevel"));
  const maxLevel = Number(searchParams.get("maxLevel"));
  const sortParam = (searchParams.get("sort") ?? "relevance").trim();
  const sort = SORT_OPTIONS.has(sortParam) ? sortParam : "relevance";
  const page = Math.max(1, Math.trunc(Number(searchParams.get("page"))) || 1);

  const hasNameSearch = q.length >= 2;
  const hasQuality = VALID_QUALITIES.has(quality);
  const hasStat = stat.length >= 2;
  const hasCategory = category.length > 0;
  const hasMinLevel = Number.isFinite(minLevel) && minLevel > 0;
  const hasMaxLevel = Number.isFinite(maxLevel) && maxLevel > 0;

  // No filters at all used to short-circuit to an empty result here - that
  // was the actual reason the Items page showed nothing until you searched,
  // separate from (and in addition to) the frontend's own gating. Falls
  // through to the normal query below instead, which already defaults to
  // name order and excludes Quest items - i.e. a plain unfiltered browse.

  function baseQuery(withCount: boolean) {
    let query = supabaseAdmin
      .from("items")
      .select(
        "id, name, quality, quality_color, item_class, item_subclass, inventory_type, level, required_level, armor, damage_min, damage_max, weapon_speed, weapon_dps, binding, durability, spell_lines, profession_requirement, reagents_text, classes_text, item_set_line, item_set_pieces, item_set_bonuses, stats, sell_price, icon, icon_name, verified, tooltip",
        withCount ? { count: "exact" } : undefined
      )
      .eq("hidden", false);

    if (hasCategory) {
      // A specific category (including "Quest Items") says exactly which
      // item_class values to show, replacing the default Quest-exclusion
      // below entirely.
      query = query.in("item_class", CATEGORY_CLASSES[category]);
    } else {
      // Quest items aren't gear or anything you'd shop for in a plain
      // browse - they're just clutter here. Only an unverified/baseline row
      // ever has item_class set (a live tooltip observation never writes it
      // - see the gap noted in applyLiveObservation, lib/items.ts), so this
      // can only ever exclude Blizzard's own baseline quest items, not a
      // real scanned one; that's fine, `.or` lets a null item_class (any
      // verified item) through untouched either way.
      query = query.or("item_class.is.null,item_class.neq.Quest");
    }

    if (hasNameSearch) query = query.ilike("name", `%${q}%`);
    if (hasQuality) query = query.eq("quality", quality);
    if (hasMinLevel) query = query.gte("level", minLevel);
    if (hasMaxLevel) query = query.lte("level", maxLevel);
    return query;
  }

  const needsJsPass = hasStat || sort === "quality";

  if (needsJsPass) {
    // Deterministic scan order regardless of the requested sort - filtering
    // and (for a quality sort) the real ordering both happen below, in JS.
    const { data, error } = await baseQuery(false).order("name", { ascending: true }).limit(JS_SCAN_LIMIT);
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });

    let items = data ?? [];

    // Stat filtering happens here rather than as a jsonb query - `stats` is
    // a free-form array of {type, value} parsed straight out of tooltip
    // text (see parseLiveTooltip in lib/items.ts), and a simple case-
    // insensitive "does this item have a stat whose name contains X" check
    // is both easier to get right and plenty fast at this project's scale
    // than a jsonb containment query would be.
    if (hasStat) {
      const needle = stat.toLowerCase();
      items = items.filter(
        (item) =>
          Array.isArray(item.stats) &&
          (item.stats as { type?: string }[]).some((s) => s.type?.toLowerCase().includes(needle))
      );
    }

    if (sort === "quality") {
      items = [...items].sort(
        (a, b) => (QUALITY_RANK[b.quality ?? ""] ?? -1) - (QUALITY_RANK[a.quality ?? ""] ?? -1)
      );
    }

    const start = (page - 1) * PAGE_SIZE;
    return NextResponse.json({
      items: items.slice(start, start + PAGE_SIZE),
      total: items.length,
      page,
      pageSize: PAGE_SIZE,
    });
  }

  // "relevance" has never been a real ranking (there's no scoring here),
  // just the same natural alphabetical order "name" itself uses - kept as
  // the default so a plain browse isn't sorted by whichever order Postgres
  // felt like returning rows in. "level" wasn't a real column sort before
  // either (the old 60-row cap sorted in JS after the fact); doing it in
  // the query itself is what actually makes it correct across pages now
  // that there ARE multiple pages to page through.
  let query = baseQuery(true);
  query = sort === "level"
    ? query.order("level", { ascending: false, nullsFirst: false }).order("name", { ascending: true })
    : query.order("name", { ascending: true });

  const start = (page - 1) * PAGE_SIZE;
  const { data, error, count } = await query.range(start, start + PAGE_SIZE - 1);
  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ items: data ?? [], total: count ?? 0, page, pageSize: PAGE_SIZE });
}
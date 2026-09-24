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
  const sortParam = (searchParams.get("sort") ?? "relevance").trim();
  const sort = SORT_OPTIONS.has(sortParam) ? sortParam : "relevance";
  const page = Math.max(1, Math.trunc(Number(searchParams.get("page"))) || 1);

  const hasNameSearch = q.length >= 2;
  const hasQuality = VALID_QUALITIES.has(quality);
  const hasStat = stat.length >= 2;

  if (!hasNameSearch && !hasQuality && !hasStat) {
    return NextResponse.json({ items: [], total: 0, page: 1, pageSize: PAGE_SIZE });
  }

  function baseQuery(withCount: boolean) {
    let query = supabaseAdmin
      .from("items")
      .select(
        "id, name, quality, quality_color, item_class, item_subclass, inventory_type, level, required_level, armor, damage_min, damage_max, weapon_speed, weapon_dps, binding, durability, spell_lines, profession_requirement, reagents_text, classes_text, item_set_line, item_set_pieces, item_set_bonuses, stats, sell_price, icon, icon_name, verified, tooltip",
        withCount ? { count: "exact" } : undefined
      )
      // Quest items aren't gear or anything you'd shop for in this database -
      // they're just clutter here. Only an unverified/baseline row ever has
      // item_class set (a live tooltip observation never writes it - see the
      // gap noted in applyLiveObservation, lib/items.ts), so this can only
      // ever exclude Blizzard's own baseline quest items, not a real scanned
      // one; that's fine, `.or` lets a null item_class (any verified item)
      // through untouched either way.
      .or("item_class.is.null,item_class.neq.Quest")
      .eq("hidden", false);

    if (hasNameSearch) query = query.ilike("name", `%${q}%`);
    if (hasQuality) query = query.eq("quality", quality);
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
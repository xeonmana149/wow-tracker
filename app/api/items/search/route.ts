import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "../../../../lib/supabaseAdmin";

const VALID_QUALITIES = new Set(["POOR", "COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY"]);

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const q = (searchParams.get("q") ?? "").trim();
  const quality = (searchParams.get("quality") ?? "").trim().toUpperCase();
  const stat = (searchParams.get("stat") ?? "").trim();

  const hasNameSearch = q.length >= 2;
  const hasQuality = VALID_QUALITIES.has(quality);
  const hasStat = stat.length >= 2;

  if (!hasNameSearch && !hasQuality && !hasStat) {
    return NextResponse.json({ items: [] });
  }

  let query = supabaseAdmin
    .from("items")
    .select(
      "id, name, quality, quality_color, item_class, item_subclass, inventory_type, required_level, armor, damage_min, damage_max, weapon_speed, stats, sell_price, icon, icon_name, verified, tooltip"
    )
    // Quest items aren't gear or anything you'd shop for in this database -
    // they're just clutter here. Only an unverified/baseline row ever has
    // item_class set (a live tooltip observation never writes it - see the
    // gap noted in applyLiveObservation, lib/items.ts), so this can only
    // ever exclude Blizzard's own baseline quest items, not a real scanned
    // one; that's fine, `.or` lets a null item_class (any verified item)
    // through untouched either way.
    .or("item_class.is.null,item_class.neq.Quest")
    .order("verified", { ascending: false })
    .order("name", { ascending: true })
    .limit(60);

  if (hasNameSearch) query = query.ilike("name", `%${q}%`);
  if (hasQuality) query = query.eq("quality", quality);

  const { data, error } = await query;
  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  let items = data ?? [];

  // Stat filtering happens here rather than as a jsonb query - `stats` is a
  // free-form array of {type, value} parsed straight out of tooltip text
  // (see parseLiveTooltip in lib/items.ts), and a simple case-insensitive
  // "does this item have a stat whose name contains X" check is both easier
  // to get right and plenty fast at this project's scale than a jsonb
  // containment query would be.
  if (hasStat) {
    const needle = stat.toLowerCase();
    items = items.filter((item) =>
      Array.isArray(item.stats) &&
      (item.stats as { type?: string }[]).some((s) => s.type?.toLowerCase().includes(needle))
    );
  }

  return NextResponse.json({ items });
}
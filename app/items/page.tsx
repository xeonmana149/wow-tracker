import AuthStatus from "../AuthStatus";
import { supabaseAdmin } from "../../lib/supabaseAdmin";
import { iconUrlForFileId } from "../../lib/icons";

type ItemRow = {
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
  stats: { type: string; value: number }[] | null;
  sell_price: number | null;
  icon: number | null;
  verified: boolean;
};

// Blizzard's SCREAMING_CASE inventory type -> a normal-looking slot label,
// e.g. "MAINHAND" -> "Main Hand". Falls back to the item's subclass (e.g.
// "Sword") when there's no inventory type at all (a manually-added or
// still-blank auto_new row).
function formatSlot(inventoryType: string | null, itemSubclass: string | null) {
  if (!inventoryType) return itemSubclass ?? "";
  const spaced = inventoryType
    .toLowerCase()
    .replace(/hand/g, " hand")
    .replace(/finger/g, "finger")
    .trim();
  return spaced
    .split(/\s+/)
    .filter(Boolean)
    .map((w) => w[0].toUpperCase() + w.slice(1))
    .join(" ");
}

function formatMoney(copper: number | null) {
  if (copper == null) return null;
  const gold = Math.floor(copper / 10000);
  const silver = Math.floor((copper % 10000) / 100);
  const cop = copper % 100;
  const parts: string[] = [];
  if (gold > 0) parts.push(`${gold}g`);
  if (gold > 0 || silver > 0) parts.push(`${silver}s`);
  parts.push(`${cop}c`);
  return parts.join(" ");
}

export default async function Items({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const { q } = await searchParams;
  const query = (q ?? "").trim();

  let items: ItemRow[] = [];
  let loadError: string | null = null;

  if (query.length >= 2) {
    const { data, error } = await supabaseAdmin
      .from("items")
      .select(
        "id, name, quality, quality_color, item_class, item_subclass, inventory_type, level, required_level, armor, damage_min, damage_max, weapon_speed, stats, sell_price, icon, verified"
      )
      .ilike("name", `%${query}%`)
      .order("verified", { ascending: false })
      .order("name", { ascending: true })
      .limit(40);
    if (error) {
      loadError = error.message;
    } else {
      items = (data ?? []) as ItemRow[];
    }
  }

  return (
    <main className="mx-auto max-w-[1500px] p-4 md:p-6">
      <AuthStatus />

      <h1 className="text-3xl font-bold">Items</h1>
      <p className="mt-2 max-w-2xl text-sm text-gray-400">
        Search items that have actually been seen equipped by a real character, or looked up
        from Blizzard&apos;s classic database. Items marked{" "}
        <span className="font-semibold text-yellow-400">Unconfirmed</span> haven&apos;t been
        seen equipped in Forever yet - WoW Forever can rebalance classic items, so their real
        stats may differ from what&apos;s shown until someone&apos;s actually spotted wearing one.
      </p>

      <form className="mt-5 flex flex-wrap gap-2" action="/items">
        <input
          type="text"
          name="q"
          defaultValue={query}
          placeholder="Search for an item..."
          className="w-full max-w-md rounded border border-neutral-700 bg-neutral-900 px-3 py-2 text-sm text-white placeholder:text-gray-500"
        />
        <button type="submit" className="rounded bg-red-700 px-4 py-2 text-sm font-bold">
          Search
        </button>
      </form>

      {query.length > 0 && query.length < 2 && (
        <p className="mt-6 text-gray-400">Type at least 2 characters to search.</p>
      )}

      {loadError && <p className="mt-6 text-red-400">Couldn&apos;t search items: {loadError}</p>}

      {query.length >= 2 && !loadError && items.length === 0 && (
        <p className="mt-6 text-gray-400">
          No items found matching &quot;{query}&quot;. If it&apos;s a real item nobody&apos;s
          synced yet, it won&apos;t show up here until someone equips it and syncs.
        </p>
      )}

      {query.length === 0 && (
        <p className="mt-6 text-gray-400">
          Search above to browse the item database - it grows automatically every time anyone
          syncs their gear.
        </p>
      )}

      <div className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {items.map((item) => {
          const iconUrl = iconUrlForFileId(item.icon);
          const color = item.quality_color ? `#${item.quality_color}` : "#ffffff";
          return (
            <div
              key={item.id}
              className="flex gap-3 rounded border border-neutral-700 bg-neutral-900 p-3"
            >
              <div className="h-12 w-12 flex-shrink-0 overflow-hidden rounded border border-neutral-600 bg-neutral-800">
                {iconUrl && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={iconUrl} alt="" className="h-full w-full object-cover" />
                )}
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-x-2">
                  <span className="truncate font-semibold" style={{ color }}>
                    {item.name}
                  </span>
                  {!item.verified && (
                    <span className="chip whitespace-nowrap text-[10px] text-yellow-400">
                      Unconfirmed
                    </span>
                  )}
                </div>
                <div className="text-xs text-gray-400">
                  {[formatSlot(item.inventory_type, null), item.item_subclass]
                    .filter(Boolean)
                    .join(" · ")}
                </div>
                {item.armor != null && (
                  <div className="text-xs text-gray-300">{item.armor} Armor</div>
                )}
                {item.damage_min != null && item.damage_max != null && (
                  <div className="text-xs text-gray-300">
                    {item.damage_min} - {item.damage_max} Damage
                    {item.weapon_speed != null ? `  Speed ${item.weapon_speed}` : ""}
                  </div>
                )}
                {item.stats && item.stats.length > 0 && (
                  <div className="text-xs text-green-400">
                    {item.stats.map((s) => `+${s.value} ${s.type}`).join("  ")}
                  </div>
                )}
                <div className="mt-1 flex items-center justify-between text-xs text-gray-500">
                  {item.required_level != null && (
                    <span>Requires Level {item.required_level}</span>
                  )}
                  {formatMoney(item.sell_price) && <span>{formatMoney(item.sell_price)}</span>}
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </main>
  );
}
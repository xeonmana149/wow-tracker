// Server-only. Names, icons and vendor prices for everything on the
// auction house, so the Auction House pages can show more than item ids.
//
// Forever's own item data (Blizzard's static-forever-us namespace) comes
// first - it has Forever's real vendor prices and its new items. It's
// missing some items, so the site's items table (classic data) fills those
// in. Icons always come from Forever's item media, which covers everything.
//
// Kept as one file in the market bucket and topped up a little on every
// collection, so new items get a name within an hour or two.

import { blizzardGet } from "./blizzard";
import { getJson, putJson } from "./marketStore";
import { supabaseAdmin } from "./supabaseAdmin";

const FILE = "item-info.json";
const NAMESPACE = "static-forever-us";
const REGION = "us";
// Don't ask again about an id Blizzard didn't know for this long.
const RETRY_MISSING = 7 * 86400;

// [name, quality ("COMMON"...), item class, item subclass, vendor sell price,
//  icon file id, 1 = from Forever's own data (vendor price is Forever's real one)]
export type ItemInfo = [string, string, string, string, number, number, number?];

type InfoFile = { v: 1; items: Record<string, ItemInfo>; miss: Record<string, number> };

let mem: { file: InfoFile; at: number } | null = null;
const MEM_TTL = 10 * 60 * 1000;

export async function loadItemInfo(): Promise<InfoFile> {
  if (mem && Date.now() - mem.at < MEM_TTL) return mem.file;
  const file = (await getJson<InfoFile>(FILE)) ?? { v: 1, items: {}, miss: {} };
  file.items ??= {};
  file.miss ??= {};
  mem = { file, at: Date.now() };
  return file;
}

export function iconUrl(fileId: number | null | undefined): string | null {
  return fileId ? `https://render.worldofwarcraft.com/forever-us/icons/56/${fileId}.jpg` : null;
}

export const QUALITY_COLOR: Record<string, string> = {
  POOR: "#9d9d9d",
  COMMON: "#ffffff",
  UNCOMMON: "#1eff00",
  RARE: "#0070dd",
  EPIC: "#a335ee",
  LEGENDARY: "#ff8000",
};

type ItemBody = {
  name?: string;
  quality?: { type?: string };
  item_class?: { name?: string };
  item_subclass?: { name?: string };
  sell_price?: number;
};
type MediaBody = { assets?: { key?: string; value?: string; file_data_id?: number }[] };

async function fetchOne(id: number): Promise<{ info: ItemInfo | null; known: boolean }> {
  const params = { namespace: NAMESPACE, locale: "en_US" };
  const [item, media] = await Promise.all([
    blizzardGet(REGION, `/data/wow/item/${id}`, params),
    blizzardGet(REGION, `/data/wow/media/item/${id}`, params),
  ]);
  const asset = media.ok ? (media.body as MediaBody).assets?.find((a) => a.key === "icon") : undefined;
  const icon = asset?.file_data_id ?? Number(asset?.value?.match(/\/(\d+)\.jpg$/)?.[1] ?? 0);
  if (item.ok) {
    const b = item.body as ItemBody;
    return {
      info: [
        b.name ?? `Item ${id}`,
        b.quality?.type ?? "COMMON",
        b.item_class?.name ?? "",
        b.item_subclass?.name ?? "",
        b.sell_price ?? 0,
        icon,
        1,
      ],
      known: true,
    };
  }
  // Not in Forever's data: the caller fills in from the items table.
  return { info: icon ? ["", "", "", "", 0, icon] : null, known: false };
}

// Looks up to `limit` item ids we don't have yet. Returns how many were added.
export async function topUpItemInfo(ids: number[], limit = 150, concurrency = 8): Promise<number> {
  const file = await loadItemInfo();
  const now = Math.floor(Date.now() / 1000);
  const todo = ids
    .filter((id) => (file.miss[id] ? now - file.miss[id] >= RETRY_MISSING : !file.items[id]))
    .slice(0, limit);
  if (todo.length === 0) return 0;

  const results = new Map<number, { info: ItemInfo | null; known: boolean }>();
  let next = 0;
  async function worker() {
    while (next < todo.length) {
      const id = todo[next++];
      try {
        results.set(id, await fetchOne(id));
      } catch {
        // Network hiccup - try again next time.
      }
    }
  }
  await Promise.all(Array.from({ length: concurrency }, worker));

  // Fill the ones Forever didn't know from the site's items table.
  const unknown = [...results].filter(([, r]) => !r.known).map(([id]) => id);
  const fromTable = new Map<number, { name: string; quality: string | null; item_class: string | null; item_subclass: string | null; sell_price: number | null }>();
  for (let i = 0; i < unknown.length; i += 300) {
    const { data } = await supabaseAdmin
      .from("items")
      .select("id, name, quality, item_class, item_subclass, sell_price")
      .in("id", unknown.slice(i, i + 300));
    for (const row of data ?? []) fromTable.set(row.id, row);
  }

  let added = 0;
  for (const [id, r] of results) {
    if (r.known && r.info) {
      file.items[id] = r.info;
      added++;
      continue;
    }
    const row = fromTable.get(id);
    if (row) {
      file.items[id] = [row.name, row.quality ?? "COMMON", row.item_class ?? "", row.item_subclass ?? "", row.sell_price ?? 0, r.info?.[5] ?? 0, 0];
      added++;
    } else {
      file.miss[id] = now;
      if (r.info) file.items[id] = [`Item ${id}`, "COMMON", "", "", 0, r.info[5], 0];
    }
  }
  await putJson(FILE, file);
  mem = { file, at: Date.now() };
  return added;
}

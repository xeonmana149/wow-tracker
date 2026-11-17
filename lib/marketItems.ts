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
//  icon file id, source]
// source: 1 = Forever's own data; 2 = read from the WoW Forever game client
// itself (scripts imported once from the owner's Forever Gold saved data);
// 0/absent = the site's old classic items table (vendor price often wrong).
// 1 and 2 have trustworthy vendor prices.
export type ItemInfo = [string, string, string, string, number, number, number?];
export const vendorTrusted = (i: ItemInfo | undefined) => !!i && (i[6] === 1 || i[6] === 2);

// miss: ids Blizzard has no data for at all, and when we last asked.
// chk: ids we only have second-hand (classic table) or icon-less data for,
// and when we last asked Blizzard again.
type InfoFile = { v: 1; items: Record<string, ItemInfo>; miss: Record<string, number>; chk?: Record<string, number> };

// Entries worth asking Blizzard about again now and then.
const incomplete = (i: ItemInfo | undefined) => !!i && (!vendorTrusted(i) || !i[5]);

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

// One Blizzard request, retried once if Blizzard says "slow down" or has a
// hiccup. Only a 404 means the item really isn't there.
async function getWithRetry(path: string, params: Record<string, string>) {
  let res = await blizzardGet(REGION, path, params);
  if (!res.ok && res.status !== 404) {
    await new Promise((r) => setTimeout(r, 1200));
    res = await blizzardGet(REGION, path, params);
  }
  return res;
}

// null = Blizzard didn't answer properly; try this item again another time.
async function fetchOne(id: number): Promise<{ info: ItemInfo | null; known: boolean } | null> {
  const params = { namespace: NAMESPACE, locale: "en_US" };
  const [item, media] = await Promise.all([
    getWithRetry(`/data/wow/item/${id}`, params),
    getWithRetry(`/data/wow/media/item/${id}`, params),
  ]);
  if ((!item.ok && item.status !== 404) || (!media.ok && media.status !== 404)) return null;
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
  const chk = file.chk ?? {};
  // New items first, then ones we only have second-hand or icon-less data for.
  const fresh = ids.filter((id) => (file.miss[id] ? now - file.miss[id] >= RETRY_MISSING : !file.items[id]));
  const recheck = ids.filter((id) => !file.miss[id] && incomplete(file.items[id]) && now - (chk[id] ?? 0) >= RETRY_MISSING);
  const todo = [...new Set([...fresh, ...recheck])].slice(0, limit);
  if (todo.length === 0) return 0;

  const results = new Map<number, { info: ItemInfo | null; known: boolean }>();
  let next = 0;
  async function worker() {
    while (next < todo.length) {
      const id = todo[next++];
      try {
        const r = await fetchOne(id);
        if (r) results.set(id, r);
      } catch {
        // Network hiccup - try again next time.
      }
    }
  }
  await Promise.all(Array.from({ length: concurrency }, worker));

  // Fill the ones Forever didn't know from the site's items table.
  const unknown = [...results].filter(([, r]) => !r.known).map(([id]) => id);
  const fromTable = new Map<number, TableRow>();
  for (let i = 0; i < unknown.length; i += 300) {
    const { data } = await supabaseAdmin
      .from("items")
      .select("id, name, quality, item_class, item_subclass, sell_price")
      .in("id", unknown.slice(i, i + 300));
    for (const row of data ?? []) fromTable.set(row.id, row);
  }

  if (results.size === 0) return 0;
  // Apply our answers to the newest copy of the file, not the (possibly
  // minutes old) one this server instance had cached, so two servers topping
  // up at once don't undo each other's work.
  const latest = (await getJson<InfoFile>(FILE)) ?? file;
  latest.items ??= {};
  latest.miss ??= {};
  const latestChk = (latest.chk ??= {});
  const added = applyResults(latest, latestChk, results, fromTable, now);
  await putJson(FILE, latest);
  mem = { file: latest, at: Date.now() };
  return added;
}

type TableRow = { name: string; quality: string | null; item_class: string | null; item_subclass: string | null; sell_price: number | null };

function applyResults(
  file: InfoFile,
  chk: Record<string, number>,
  results: Map<number, { info: ItemInfo | null; known: boolean }>,
  fromTable: Map<number, TableRow>,
  now: number
): number {
  let added = 0;
  for (const [id, r] of results) {
    const had = file.items[id];
    if (had) chk[id] = now;
    if (r.known && r.info) {
      file.items[id] = r.info;
      delete chk[id];
      delete file.miss[id];
      added++;
      continue;
    }
    const row = fromTable.get(id);
    // The classic table sometimes holds the client's "still loading" text
    // instead of a name; never take that.
    const tableName = row?.name && !/^Retrieving item/i.test(row.name) ? row.name : null;
    const icon = r.info?.[5] || had?.[5] || 0;
    if (had?.[6] === 2) {
      // Straight from the game client: better than the classic table.
      if (icon && !had[5]) had[5] = icon;
    } else if (row && tableName) {
      file.items[id] = [tableName, row.quality ?? "COMMON", row.item_class ?? "", row.item_subclass ?? "", row.sell_price ?? 0, icon, 0];
      added++;
    } else if (had && !/^Retrieving item/i.test(had[0])) {
      if (icon && !had[5]) had[5] = icon;
    } else {
      file.miss[id] = now;
      file.items[id] = [`Item ${id}`, "COMMON", "", "", 0, icon, 0];
    }
  }
  return added;
}

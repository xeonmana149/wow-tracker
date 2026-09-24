// One-off (but safely re-runnable) maintenance script: pulls the ENTIRE
// classic1x item catalog from Blizzard's Game Data API and seeds every item
// into the `items` table as an unverified baseline row (source:
// "classic_api"), so the Items page shows the whole classic database
// immediately instead of only whatever's been synced from someone's
// inventory so far. A live scanned tooltip still always wins over this
// baseline (see applyLiveObservation in lib/items.ts) - this script never
// touches an item that already has a row, verified or not.
//
// WHY THIS IS A SCRIPT, NOT A WEBSITE FEATURE:
// Blizzard's search endpoint caps out at 1000 results per query
// (resultCountCapped: true past 50 pages), so the whole catalog has to be
// pulled in per-item-class chunks, and even some individual classes need to
// be split further by subclass to get under that cap. All told this is
// tens of thousands of Blizzard API calls, which comfortably blows past
// Vercel's serverless function time limit - so instead this runs locally,
// where there's no timeout, and you just watch it work.
//
// HOW TO RUN IT:
// 1. Create a ".env.local" file in the project root (same folder as
//    package.json) - if you don't already have one - with the SAME
//    Blizzard and Supabase values you set in Vercel's Environment
//    Variables (Project Settings > Environment Variables). Copy the exact
//    variable names from there. This file should already be covered by
//    Next.js's default .gitignore (".env*.local") - double check it never
//    gets committed, since it'll contain your Blizzard client secret and
//    Supabase service-role key.
// 2. From the project root, run:
//      npx tsx scripts/bulk-seed-items.ts
//    (npx will grab "tsx" - a TypeScript runner - automatically the first
//    time; no need to add it to package.json unless you want to run this
//    again later, in which case `npm i -D tsx` once makes future runs
//    faster to start.)
// 3. Let it run. It prints progress per item class and is safe to Ctrl-C
//    and re-run any time - already-seeded items are skipped, so a re-run
//    just picks up wherever it left off instead of starting over.
//
// This will take a while (likely 30-90+ minutes depending on how big the
// classic catalog turns out to be and how fast Blizzard's API responds) -
// that's expected, not a bug.

import fs from "node:fs";
import path from "node:path";

// Loaded manually (no extra dependency needed) and BEFORE any dynamic
// import below, because lib/supabaseAdmin.ts builds its Supabase client as
// soon as it's imported - if we imported it before this ran, it'd read
// empty env vars and fail.
function loadEnvLocal() {
  const envPath = path.resolve(process.cwd(), ".env.local");
  if (!fs.existsSync(envPath)) {
    console.warn(
      `No .env.local found at ${envPath} - continuing with whatever's already in your shell's environment.`
    );
    return;
  }
  const contents = fs.readFileSync(envPath, "utf8");
  for (const rawLine of contents.split("\n")) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const eq = line.indexOf("=");
    if (eq === -1) continue;
    const key = line.slice(0, eq).trim();
    let value = line.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (!(key in process.env)) process.env[key] = value;
  }
}
loadEnvLocal();

// A few item classes that don't exist (or are always empty) in the classic
// dataset - skipped even if Blizzard's index happens to list them, since
// searching them just wastes requests. This list is deliberately short;
// worst case an empty class just returns zero results quickly.
const SKIP_CLASS_IDS = new Set<number>([10, 16, 17, 18]);

// Fallback list, used only if Blizzard's own /data/wow/item-class/index
// call fails or comes back empty for some reason - these IDs are stable
// across every version of WoW's Game Data API.
const FALLBACK_ITEM_CLASSES: { id: number; name: string }[] = [
  { id: 0, name: "Consumable" },
  { id: 1, name: "Container" },
  { id: 2, name: "Weapon" },
  { id: 3, name: "Gem" },
  { id: 4, name: "Armor" },
  { id: 5, name: "Reagent" },
  { id: 6, name: "Projectile" },
  { id: 7, name: "Trade Goods" },
  { id: 9, name: "Recipe" },
  { id: 11, name: "Quiver" },
  { id: 12, name: "Quest" },
  { id: 13, name: "Key" },
  { id: 15, name: "Miscellaneous" },
];

// Blizzard's Game Data API returns most names as a localized object
// ({ en_US: "Weapon", ... }), not a plain string - both the item-class
// index and an item-class's embedded subclasses come back this way. Handles
// the (defensive) case where it's already a plain string too.
function localizedName(name: unknown, fallback: string): string {
  if (typeof name === "string") return name;
  if (name && typeof name === "object" && "en_US" in name) {
    const v = (name as { en_US?: unknown }).en_US;
    if (typeof v === "string") return v;
  }
  return fallback;
}

const PAGE_SIZE = 100;
const MAX_PAGES = 60; // safety valve well past Blizzard's ~50-page cap

type BlizzardGet = (
  region: string,
  path: string,
  params: Record<string, string>
) => Promise<{ ok: boolean; status: number; body: unknown }>;

async function pageSearch(
  blizzardGet: BlizzardGet,
  region: string,
  namespace: string,
  extraParams: Record<string, string>
): Promise<{ ids: number[]; capped: boolean }> {
  const ids: number[] = [];
  let capped = false;
  let page = 1;
  while (page <= MAX_PAGES) {
    const res = await blizzardGet(region, "/data/wow/search/item", {
      namespace,
      orderby: "id",
      _pageSize: String(PAGE_SIZE),
      _page: String(page),
      ...extraParams,
    });
    if (!res.ok) {
      // Transient failure mid-pagination - stop here rather than silently
      // pretending there's nothing more; whatever's missing gets picked up
      // on a re-run since already-seeded items are skipped next time.
      console.warn(`    search page ${page} failed (status ${res.status}) - stopping this query early`);
      break;
    }
    const body = res.body as {
      results?: { data?: { id?: number } }[];
      resultCountCapped?: boolean;
    };
    if (body.resultCountCapped) capped = true;
    const results = body.results ?? [];
    for (const r of results) {
      if (typeof r.data?.id === "number") ids.push(r.data.id);
    }
    if (results.length < PAGE_SIZE) break; // last page
    page++;
  }
  // resultCountCapped is Blizzard's own word that this query had more
  // matches than it would hand back through paging - trust it directly
  // rather than inferring it from how many pages we happened to walk
  // (a fixed ~1000-result ceiling can be hit well before any page-count
  // safety valve, and requiring both was masking real cap hits).
  return { ids, capped };
}

// A third partition level (splitting further by an "id.gte"/"id.lte" ID
// range) was tried here and REVERTED - turned out Blizzard's search
// endpoint doesn't actually honor those as range filters, so the recursive
// split wasn't narrowing anything, and worse, the code that called it threw
// away the perfectly good (if capped-at-1000) subclass results first,
// producing FEWER total items than just keeping the simple two-level
// (class -> subclass) split (confirmed on a live run: Armor dropped from
// 5491 items down to 1424 once this was added). Back to the simpler,
// verified-correct approach: a handful of large subclasses (Consumable,
// each Armor material, Quest, Junk) stay capped around 1000 each - anything
// beyond that still gets captured for real the moment someone actually
// scans one via a live tooltip (applyLiveObservation always wins anyway).

async function collectIdsForClass(
  blizzardGet: BlizzardGet,
  region: string,
  namespace: string,
  classId: number,
  className: string
): Promise<number[]> {
  const direct = await pageSearch(blizzardGet, region, namespace, {
    "item_class.id": String(classId),
  });
  if (!direct.capped) return direct.ids;

  console.log(`    ${className} hit the ~1000-result cap - splitting by subclass...`);
  const detailRes = await blizzardGet(region, `/data/wow/item-class/${classId}`, { namespace });
  const subclasses = ((detailRes.body as { item_subclasses?: { id: number; name?: unknown }[] })
    ?.item_subclasses ?? []) as { id: number; name?: unknown }[];

  const ids = new Set<number>(direct.ids);
  for (const sub of subclasses) {
    const subName = localizedName(sub.name, `subclass ${sub.id}`);
    const subParams = { "item_class.id": String(classId), "item_subclass.id": String(sub.id) };
    const subResult = await pageSearch(blizzardGet, region, namespace, subParams);
    for (const id of subResult.ids) ids.add(id);
    if (subResult.capped) {
      console.warn(
        `    ${className} / ${subName} STILL over the cap - some items in this subclass may be missed. They'll still get captured for real the moment someone actually has one (a live tooltip always wins anyway).`
      );
    }
  }
  return Array.from(ids);
}

async function main() {
  const { blizzardGet } = await import("../lib/blizzard");
  const { ensureItemsExist, ITEM_NAMESPACE, ITEM_REGION } = await import("../lib/items");
  const { supabaseAdmin } = await import("../lib/supabaseAdmin");

  const startedAt = Date.now();

  console.log(`Fetching item-class list from Blizzard (namespace: ${ITEM_NAMESPACE})...`);
  let itemClasses = FALLBACK_ITEM_CLASSES;
  try {
    const idxRes = await blizzardGet(ITEM_REGION, "/data/wow/item-class/index", {
      namespace: ITEM_NAMESPACE,
    });
    const fetched = (idxRes.body as { item_classes?: { id: number; name?: unknown }[] })
      ?.item_classes;
    if (idxRes.ok && fetched && fetched.length > 0) {
      itemClasses = fetched.map((c) => ({ id: c.id, name: localizedName(c.name, `Class ${c.id}`) }));
    } else {
      console.warn("  Couldn't read the item-class index - using the built-in fallback list.");
    }
  } catch {
    console.warn("  item-class index request failed - using the built-in fallback list.");
  }
  itemClasses = itemClasses.filter((c) => !SKIP_CLASS_IDS.has(c.id));

  console.log(`Found ${itemClasses.length} item classes to seed.\n`);

  let totalIds = 0;
  for (const cls of itemClasses) {
    console.log(`[${cls.name}] searching...`);
    const ids = await collectIdsForClass(blizzardGet, ITEM_REGION, ITEM_NAMESPACE, cls.id, cls.name);
    console.log(`[${cls.name}] found ${ids.length} items - seeding (skips anything already in the database)...`);
    totalIds += ids.length;

    const CHUNK = 200;
    for (let i = 0; i < ids.length; i += CHUNK) {
      const chunk = ids.slice(i, i + CHUNK);
      await ensureItemsExist(supabaseAdmin, chunk, new Map());
      console.log(
        `[${cls.name}]   ...${Math.min(i + CHUNK, ids.length)}/${ids.length} processed`
      );
    }
  }

  const { count } = await supabaseAdmin
    .from("items")
    .select("id", { count: "exact", head: true });

  const minutes = ((Date.now() - startedAt) / 60000).toFixed(1);
  console.log(`\nDone in ${minutes} minutes.`);
  console.log(`Looked at ${totalIds} item IDs across all classes (with overlap/dupes possible between classes).`);
  console.log(`The items table now has ${count ?? "?"} rows total.`);
}

main().catch((err) => {
  console.error("\nBulk seed failed:", err);
  process.exit(1);
});
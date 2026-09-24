import { NextRequest, NextResponse } from "next/server";
import { blizzardGet } from "../../../lib/blizzard";

// TEMPORARY diagnostic route - not linked from anywhere in the site's UI.
// Visit it directly with a query, e.g.:
//   /api/blizzard-diag?name=Linen+Cloth
//   /api/blizzard-diag?name=Linen+Cloth&namespace=static-classic1x-us&region=us
//   /api/blizzard-diag?id=2857
//   /api/blizzard-diag?id=279864&namespace=static-classic1x-us
//   /api/blizzard-diag?bulk=1&page=1&namespace=static-classic1x-us
// name-search mode tries Blizzard's item-search endpoint under a few likely
// namespaces (unless one is given explicitly); id mode looks an item up
// directly by its numeric ID via /data/wow/item/{id}; bulk mode tries the
// search endpoint with NO name filter, to see whether it'll hand back the
// entire catalog page by page (for seeding the items table with every
// classic item up front, instead of only what's been synced so far).
// Delete this route once the real search/lookup feature is built.
const CANDIDATE_NAMESPACES = [
  "static-us",
  "static-classic-us",
  "static-classic1x-us",
];

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const name = searchParams.get("name");
  const id = searchParams.get("id");
  const bulk = searchParams.get("bulk");
  const page = searchParams.get("page") ?? "1";
  const region = searchParams.get("region") ?? "us";
  const namespaceParam = searchParams.get("namespace");

  if (!name && !id && !bulk) {
    return NextResponse.json(
      {
        error:
          "Pass ?name=<item name to search for>, ?id=<numeric item id>, or ?bulk=1&page=<n>",
      },
      { status: 400 }
    );
  }

  const namespaces = namespaceParam ? [namespaceParam] : CANDIDATE_NAMESPACES;
  const results: Record<string, unknown> = {};

  for (const namespace of namespaces) {
    try {
      let result;
      if (id) {
        result = await blizzardGet(region, `/data/wow/item/${id}`, { namespace });
      } else if (bulk) {
        result = await blizzardGet(region, "/data/wow/search/item", {
          namespace,
          orderby: "id",
          _pageSize: "20",
          _page: page,
        });
      } else {
        result = await blizzardGet(region, "/data/wow/search/item", {
          namespace,
          "name.en_US": name as string,
          orderby: "id",
          _pageSize: "5",
        });
      }
      results[namespace] = result;
    } catch (e) {
      results[namespace] = { error: e instanceof Error ? e.message : String(e) };
    }
  }

  return NextResponse.json(results);
}
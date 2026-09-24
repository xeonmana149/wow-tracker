import { NextRequest, NextResponse } from "next/server";
import { blizzardGet } from "../../../lib/blizzard";

// TEMPORARY diagnostic route - not linked from anywhere in the site's UI.
// Visit it directly with a query, e.g.:
//   /api/blizzard-diag?name=Linen+Cloth
//   /api/blizzard-diag?name=Linen+Cloth&namespace=static-classic1x-us&region=us
// It tries Blizzard's item-search endpoint under a few likely namespaces
// (unless one is given explicitly) and returns whatever came back from
// each, so we can see from the real responses which namespace actually
// covers WoW Forever's items instead of guessing blind. Delete this route
// once that's figured out and the real search endpoint is built.
const CANDIDATE_NAMESPACES = [
  "static-us",
  "static-classic-us",
  "static-classic1x-us",
];

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const name = searchParams.get("name");
  const region = searchParams.get("region") ?? "us";
  const namespaceParam = searchParams.get("namespace");

  if (!name) {
    return NextResponse.json({ error: "Pass ?name=<item name to search for>" }, { status: 400 });
  }

  const namespaces = namespaceParam ? [namespaceParam] : CANDIDATE_NAMESPACES;
  const results: Record<string, unknown> = {};

  for (const namespace of namespaces) {
    try {
      const result = await blizzardGet(region, "/data/wow/search/item", {
        namespace,
        "name.en_US": name,
        orderby: "id",
        _pageSize: "5",
      });
      results[namespace] = result;
    } catch (e) {
      results[namespace] = { error: e instanceof Error ? e.message : String(e) };
    }
  }

  return NextResponse.json(results);
}
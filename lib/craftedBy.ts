import type { SupabaseClient } from "@supabase/supabase-js";

export type Crafter = {
  characterId: string;
  characterName: string;
  ownerName: string | null;
};

const RECIPE_PREFIX_RE = /^(Plans|Schematic|Formula|Pattern|Design|Recipe):\s*/i;

// "Plans: Moonsteel Broadsword" -> "Moonsteel Broadsword" - the recipe ITEM's
// own name always carries this prefix, but the trade skill window (what
// character_professions.recipes actually scrapes - see importLogic.ts and
// CraftingDirectory.tsx, which reads the exact same column) lists it under
// just the crafted item's plain name, with no prefix at all.
export function craftedItemName(recipeItemName: string): string {
  return recipeItemName.replace(RECIPE_PREFIX_RE, "").trim();
}

async function fetchForName(supabase: SupabaseClient, name: string): Promise<Crafter[]> {
  // `.contains` is a jsonb containment check - matches any row whose
  // `recipes` array has at least one element with this exact name, ignoring
  // whatever else (icon/reagents/tooltip/color) that element also carries.
  // `character_professions`/`characters`/`profiles` are all public-select
  // tables already (see crafting/page.tsx, which reads the same three with
  // the plain anon client) - the whole point of this feature is that
  // friends can see who knows what, same model as the Crafting Directory.
  const { data, error } = await supabase
    .from("character_professions")
    .select("characters!inner(id, name, profiles(display_name))")
    .contains("recipes", [{ name }]);
  if (error || !data) return [];

  const out: Crafter[] = [];
  for (const row of data as any[]) {
    const char = Array.isArray(row.characters) ? row.characters[0] : row.characters;
    if (!char) continue;
    out.push({
      characterId: char.id,
      characterName: char.name,
      ownerName: char.profiles?.display_name ?? null,
    });
  }
  return out;
}

// Finds every character in the group who knows the recipe for a given item -
// works whether `itemName` is the RECIPE item itself ("Plans: Moonsteel
// Broadsword", so also tries the crafted name with the prefix stripped) or
// the crafted item's own name (already an exact match, no stripping needed).
// Two small queries at most (only ever one for a non-recipe item), each
// scoped by a jsonb containment filter rather than pulling every
// character's whole recipe list down to filter client-side.
export async function findCraftersOf(
  supabase: SupabaseClient,
  itemName: string,
  itemClass: string | null
): Promise<Crafter[]> {
  const stripped = craftedItemName(itemName);
  const candidates =
    itemClass === "Recipe" && stripped.toLowerCase() !== itemName.toLowerCase()
      ? [itemName, stripped]
      : [itemName];

  const results = await Promise.all(candidates.map((n) => fetchForName(supabase, n)));
  const byId = new Map<string, Crafter>();
  for (const list of results) {
    for (const c of list) {
      if (!byId.has(c.characterId)) byId.set(c.characterId, c);
    }
  }
  return Array.from(byId.values()).sort((a, b) => a.characterName.localeCompare(b.characterName));
}

// "Xeon Mana knows this recipe" for a recipe/plan item, "Xeon Mana can craft
// this" for the resulting item itself - one line per character, with the
// owner's account name in parentheses when known, since a friend browsing
// this list cares who to actually message.
export function formatKnownByLines(crafters: Crafter[], itemClass: string | null): string[] {
  const verb = itemClass === "Recipe" ? "knows this recipe" : "can craft this";
  return crafters.map((c) => `${c.characterName} ${verb}${c.ownerName ? ` (${c.ownerName})` : ""}`);
}
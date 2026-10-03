import type { SupabaseClient } from "@supabase/supabase-js";

export type Crafter = {
  characterId: string;
  characterName: string;
  ownerName: string | null;
};

export type CraftReagent = {
  name: string;
  quantity: number;
  // Same shape the addon's recipe scan already captures for every reagent
  // (see CraftingDirectory.tsx's own Reagent type) - a numeric fileID from
  // a live scan, occasionally a named icon string, or nothing at all.
  icon?: number | string | null;
  // Bare "rrggbb" hex (no '#'), read off the reagent's own tooltip color.
  color?: string | null;
};

export type CraftedByInfo = {
  crafters: Crafter[];
  // Pulled from whichever matching character's recipe scan actually
  // captured reagents (an older addon build, or a recipe nobody's
  // re-scanned since, may have none - see CraftingDirectory.tsx's own "no
  // extra details captured yet" case). Null when nobody who knows this has
  // reagent data on file.
  reagents: CraftReagent[] | null;
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

type RawReagent = {
  itemID?: number;
  name: string;
  quantity: number;
  icon?: number | string | null;
  color?: string | null;
};
type RawRecipe = string | { name: string; reagents?: RawReagent[]; tooltip?: string[] };
type ProfessionRow = {
  recipes: RawRecipe[] | null;
  characters:
    | { id: string; name: string; profiles?: { display_name?: string } | null }
    | { id: string; name: string; profiles?: { display_name?: string } | null }[]
    | null;
};

function normalizeRecipe(r: RawRecipe): { name: string; reagents?: RawReagent[] } {
  return typeof r === "string" ? { name: r } : r;
}

// Everyone's recipe lists, fetched once and reused - same "read it all,
// filter in memory" approach the Crafting Directory page already uses at
// this project's scale (character_professions/characters/profiles are all
// public-select tables - see crafting/page.tsx, which queries the same
// three with the plain anon client). A single query instead of one per item
// hovered, AND it lets matching be done case/whitespace-insensitively in
// JS, which a database-side jsonb containment check can't do (that only
// matches an exact byte-for-byte string).
let cachedRows: ProfessionRow[] | null = null;
let cachedAt = 0;
const CACHE_TTL_MS = 5 * 60 * 1000;

async function loadAllRecipes(supabase: SupabaseClient): Promise<ProfessionRow[]> {
  const now = Date.now();
  if (cachedRows && now - cachedAt < CACHE_TTL_MS) return cachedRows;
  const { data, error } = await supabase
    .from("character_professions")
    .select("recipes, characters!inner(id, name, profiles!user_id(display_name))")
    .not("recipes", "is", null);
  if (error || !data) return cachedRows ?? [];
  cachedRows = data as unknown as ProfessionRow[];
  cachedAt = now;
  return cachedRows;
}

// Finds every character in the group who knows the recipe for a given item -
// works whether `itemName` is the RECIPE item itself ("Plans: Moonsteel
// Broadsword", so the prefix-stripped name is checked too) or the crafted
// item's own name (matches directly). Also returns a reagents line pulled
// from whichever matching character's scan actually captured them, since
// the crafted item's OWN row has no reagent info at all (Blizzard's data
// for the result item doesn't carry it - only the recipe/plan item does,
// and even then only when you can see that specific item's row).
export async function findCraftedBy(
  supabase: SupabaseClient,
  itemName: string,
  itemClass: string | null
): Promise<CraftedByInfo> {
  const stripped = craftedItemName(itemName);
  const candidates = new Set(
    [itemName, stripped].map((n) => n.trim().toLowerCase())
  );

  const rows = await loadAllRecipes(supabase);
  const crafters: Crafter[] = [];
  const seen = new Set<string>();
  let reagents: CraftReagent[] | null = null;

  for (const row of rows) {
    const char = Array.isArray(row.characters) ? row.characters[0] : row.characters;
    if (!char) continue;
    for (const raw of row.recipes ?? []) {
      const recipe = normalizeRecipe(raw);
      if (!candidates.has(recipe.name.trim().toLowerCase())) continue;

      if (!seen.has(char.id)) {
        seen.add(char.id);
        crafters.push({
          characterId: char.id,
          characterName: char.name,
          ownerName: char.profiles?.display_name ?? null,
        });
      }
      if (!reagents && recipe.reagents && recipe.reagents.length > 0) {
        reagents = recipe.reagents.map((r) => ({
          name: r.name,
          quantity: r.quantity,
          icon: r.icon ?? null,
          color: r.color ?? null,
        }));
      }
    }
  }

  crafters.sort((a, b) => a.characterName.localeCompare(b.characterName));
  // itemClass is accepted (not just itemName) so callers don't need to know
  // the prefix-stripping rule themselves - kept as a parameter rather than
  // inferred here in case a future caller wants to force the stripped-name
  // check even for an item whose class isn't loaded yet.
  void itemClass;
  return { crafters, reagents };
}

// "Xeon Mana knows this recipe" for a recipe/plan item, "Xeon Mana can craft
// this" for the resulting item itself - one line per character, with the
// owner's account name in parentheses when known, since a friend browsing
// this list cares who to actually message.
export function formatKnownByLines(crafters: Crafter[], itemClass: string | null): string[] {
  const verb = itemClass === "Recipe" ? "knows this recipe" : "can craft this";
  return crafters.map((c) => `${c.characterName} ${verb}${c.ownerName ? ` (${c.ownerName})` : ""}`);
}
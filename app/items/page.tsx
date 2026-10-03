import AuthStatus from "../AuthStatus";
import { supabase } from "../../lib/supabase";
import ItemsPageTabs from "./ItemsPageTabs";
import type { CraftingCharacter, CraftingPlayer } from "./craftingTypes";

// Only the Crafting Directory tab needs this (professions + recipes, same
// query the old standalone /crafting route used) - Item Search fetches its
// own results client-side via /api/items/search and doesn't touch this.
// Cached the same 30s the old route used: a newly scanned recipe can take
// up to that long to show up here, a fine trade for a directory people
// browse rather than something needing to be second-by-second live.
export const revalidate = 30;

export default async function ItemsPage({
  searchParams,
}: {
  // Next.js 15 passes searchParams as a Promise on async Server Component
  // pages, same as params elsewhere in this app (see character/[id]/page.tsx)
  // - it was typed and read here as a plain object, so `searchParams?.tab`
  // was reading a property off a Promise (always undefined). That's why the
  // dashboard's "Open Crafting Directory" button (?tab=crafting) silently
  // always landed on the Item Search tab instead.
  searchParams?: Promise<{ tab?: string }>;
}) {
  const resolvedSearchParams = await searchParams;

  const { data, error } = await supabase
    .from("characters")
    .select("id, name, class, user_id, profiles!user_id(display_name), character_professions(profession, skill, recipes)")
    .order("name", { ascending: true });

  const characters = (data ?? []) as unknown as (CraftingCharacter & {
    user_id: string | null;
    profiles: { display_name?: string } | null;
  })[];

  const byPlayer: Record<string, CraftingPlayer> = {};
  for (const c of characters) {
    const key = c.user_id ?? "none";
    if (!byPlayer[key]) {
      byPlayer[key] = { id: key, name: c.profiles?.display_name ?? "Unknown", characters: [] };
    }
    byPlayer[key].characters.push(c);
  }
  const players = Object.values(byPlayer).sort((a, b) => a.name.localeCompare(b.name));

  const initialTab = resolvedSearchParams?.tab === "crafting" ? "crafting" : "search";

  return (
    <main className="mx-auto max-w-[1500px] p-4 md:p-6">
      <AuthStatus />

      <h1 className="text-2xl font-bold">Items</h1>
      <p className="mt-1 max-w-2xl text-xs text-gray-500">
        Browse World of Warcraft: Forever&apos;s item database, or switch to the Crafting
        Directory to see who has each profession.
      </p>

      {error && (
        <p className="mt-4 text-red-400">Could not load characters: {error.message}</p>
      )}

      <div className="mt-2">
        <ItemsPageTabs players={players} initialTab={initialTab} />
      </div>
    </main>
  );
}
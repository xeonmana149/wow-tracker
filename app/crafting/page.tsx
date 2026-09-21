import { supabase } from "../../lib/supabase";
import type { CardCharacter } from "../CharacterCard";
import CraftingDirectory from "./Craftingdirectory";

export const dynamic = "force-dynamic";

// The crafting directory only ever needs each character's professions
// (with recipes) and who owns it - none of the talent/gear/achievement
// data the Dashboard and Friends pages pull in, so this fetches its own,
// smaller slice rather than reusing FriendPlayer/the Friends query.
export type CraftingCharacter = Pick<CardCharacter, "id" | "name" | "class" | "character_professions">;
export type CraftingPlayer = { id: string; name: string; characters: CraftingCharacter[] };

export default async function Crafting() {
  const { data, error } = await supabase
    .from("characters")
    .select("id, name, class, user_id, profiles(display_name), character_professions(profession, skill, recipes)")
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

  return (
    <main className="mx-auto max-w-[1500px] p-4 md:p-6">
      <h1 className="text-3xl font-bold">Crafting Directory</h1>
      <p className="mt-3 text-gray-400">
        Who can make what across the whole group - browse by profession or search by recipe.
      </p>

      {error && (
        <p className="mt-4 text-red-400">Could not load characters: {error.message}</p>
      )}

      {players.length === 0 && !error && (
        <p className="mt-6 text-gray-400">Nobody has created a character yet.</p>
      )}

      {players.length > 0 && (
        <div className="mt-6">
          <CraftingDirectory players={players} />
        </div>
      )}
    </main>
  );
}
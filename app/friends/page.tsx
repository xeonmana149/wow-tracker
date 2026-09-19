import { supabase } from "../../lib/supabase";
import { loadCardData } from "../../lib/server-data";
import type { CardCharacter } from "../CharacterCard";
import FriendsBrowser, { type FriendPlayer } from "./FriendsBrowser";

export const dynamic = "force-dynamic";

type FriendCharacter = CardCharacter & { user_id: string | null };

export default async function Friends() {
  const { data, error } = await supabase
    .from("characters")
    .select(
      "*, profiles(display_name, legacy_points), character_professions(profession, skill), character_talents(slot, tree, rank), character_legacy(rank), prebis_items(slot, item_name, source, acquired, not_needed)"
    )
    .order("level", { ascending: false });

  const characters = (data ?? []) as FriendCharacter[];
  const { specIcons, treeNames } = await loadCardData();

  const byPlayer: Record<string, FriendPlayer> = {};
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
      <h1 className="text-3xl font-bold">Friends</h1>
      <p className="mt-3 text-gray-400">
        Pick a friend to see their characters, or open the crafting directory to see who can make
        what. The numbers by each spec are talent points in each tree.
      </p>

      {error && (
        <p className="mt-4 text-red-400">Could not load characters: {error.message}</p>
      )}

      {players.length === 0 && !error && (
        <p className="mt-6 text-gray-400">Nobody has created a character yet.</p>
      )}

      {players.length > 0 && (
        <FriendsBrowser players={players} treeNames={treeNames} specIcons={specIcons} />
      )}
    </main>
  );
}
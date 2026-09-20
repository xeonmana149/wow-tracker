import { supabase } from "../../lib/supabase";
import { loadCardData } from "../../lib/server-data";
import type { CardCharacter } from "../CharacterCard";
import { loadBadgeIconOverrides } from "../../lib/badgeIconOverrides";
import FriendsBrowser, { type FriendPlayer } from "./FriendsBrowser";

export const dynamic = "force-dynamic";

type FriendCharacter = CardCharacter & { user_id: string | null };

export default async function Friends() {
  const { data, error } = await supabase
    .from("characters")
    .select(
      "*, profiles(display_name, legacy_points), character_professions(profession, skill), character_talents(slot, tree, rank), character_legacy(rank), character_wishlist(item_name, priority, obtained), achievements(kind, tier)"
    )
    .order("level", { ascending: false });

  const characters = (data ?? []) as unknown as FriendCharacter[];
  const { specIcons, treeNames } = await loadCardData();

  // Account-wide achievements live on the user, not any one character, so
  // they're fetched separately and matched up by user_id below.
  const { data: accountAchievementRows } = await supabase
    .from("account_achievements")
    .select("user_id, kind");
  const accountAchievementsByUser: Record<string, string[]> = {};
  for (const row of (accountAchievementRows ?? []) as { user_id: string; kind: string }[]) {
    const list = accountAchievementsByUser[row.user_id] ?? [];
    list.push(row.kind);
    accountAchievementsByUser[row.user_id] = list;
  }

  const byPlayer: Record<string, FriendPlayer> = {};
  for (const c of characters) {
    const key = c.user_id ?? "none";
    if (!byPlayer[key]) {
      byPlayer[key] = {
        id: key,
        name: c.profiles?.display_name ?? "Unknown",
        characters: [],
        accountAchievements: (accountAchievementsByUser[key] ?? []) as FriendPlayer["accountAchievements"],
      };
    }
    byPlayer[key].characters.push(c);
  }

  const players = Object.values(byPlayer).sort((a, b) => a.name.localeCompare(b.name));
  const iconOverrides = await loadBadgeIconOverrides(supabase);

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
        <FriendsBrowser
          players={players}
          treeNames={treeNames}
          specIcons={specIcons}
          iconOverrides={iconOverrides}
        />
      )}
    </main>
  );
}

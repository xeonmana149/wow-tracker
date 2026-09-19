import Link from "next/link";
import { supabase } from "../../lib/supabase";
import { loadCardData } from "../../lib/server-data";
import AuthStatus from "../AuthStatus";
import CharacterCard, { type CardCharacter } from "../CharacterCard";

export const dynamic = "force-dynamic";

type FriendCharacter = CardCharacter & {
  user_id: string | null;
  profiles: { display_name: string } | null;
};

type Player = { name: string; characters: FriendCharacter[] };

export default async function Friends() {
  const { data, error } = await supabase
    .from("characters")
    .select(
      "*, profiles(display_name), character_professions(profession, skill), character_talents(slot, tree, rank)"
    )
    .order("level", { ascending: false });

  const characters = (data ?? []) as FriendCharacter[];
  const { specIcons, treeNames } = await loadCardData();

  const players: Record<string, Player> = {};
  for (const c of characters) {
    const key = c.user_id ?? "none";
    if (!players[key]) {
      players[key] = { name: c.profiles?.display_name ?? "Unknown", characters: [] };
    }
    players[key].characters.push(c);
  }

  const sortedPlayers = Object.values(players).sort((a, b) => a.name.localeCompare(b.name));

  return (
    <main className="mx-auto max-w-[1500px] p-4 md:p-6">
      <AuthStatus />
      <h1 className="text-3xl font-bold">Friends</h1>
      <p className="mt-3 text-gray-400">
        Everyone&apos;s characters. The numbers by each spec are talent points in each tree.
      </p>

      {error && (
        <p className="mt-4 text-red-400">Could not load characters: {error.message}</p>
      )}

      {sortedPlayers.length === 0 && !error && (
        <p className="mt-6 text-gray-400">Nobody has created a character yet.</p>
      )}

      <div className="mt-6 flex flex-col gap-10">
        {sortedPlayers.map((player) => (
          <section key={player.name}>
            <h2 className="text-xl font-bold">
              {player.name}{" "}
              <span className="text-sm font-normal text-gray-400">
                · {player.characters.length}{" "}
                {player.characters.length === 1 ? "character" : "characters"}
              </span>
            </h2>
            <div className="mt-3 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
              {player.characters.map((c) => (
                <CharacterCard
                  key={c.id}
                  c={c}
                  treeNames={treeNames[c.class]}
                  specIcons={specIcons}
                />
              ))}
            </div>
          </section>
        ))}
      </div>
    </main>
  );
}
import Link from "next/link";
import { notFound } from "next/navigation";
import { supabase } from "../../../../lib/supabase";
import { cleanLegacy } from "../../../../lib/legacy";
import { loadLegacyData } from "../../../../lib/server-data";
import LegacyPlanner from "./LegacyPlanner";

export const dynamic = "force-dynamic";

// The character's Legacy perk planner - the "Open planner" button on the
// character page links here. Trees come from the current client data
// (loadLegacyData), so a Blizzard change to the trees shows up without a
// code change; saved ranks for perks that no longer exist are dropped.
export default async function LegacyPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;

  const { data: character } = await supabase
    .from("characters")
    .select("id, name, user_id, profiles!user_id(legacy_points)")
    .eq("id", id)
    .single();

  if (!character) notFound();

  const legacy = await loadLegacyData();
  const trees = legacy?.trees ?? [];

  const [{ data: appliedRows }, { data: planRows }] = await Promise.all([
    supabase.from("character_legacy").select("tree, perk, rank").eq("character_id", id),
    supabase.from("character_legacy_plans").select("tree, perk, rank").eq("character_id", id),
  ]);

  const profile = Array.isArray(character.profiles) ? character.profiles[0] : character.profiles;
  const earned = (profile as { legacy_points?: number } | null)?.legacy_points ?? 0;

  return (
    <main className="mx-auto max-w-[1500px] p-4 md:p-6">
      <Link href={`/character/${character.id}`} className="text-blue-400">
        ← Back to {character.name}
      </Link>
      <h1 className="mb-6 mt-4 text-3xl font-bold">{character.name}&apos;s Legacy</h1>

      {trees.length > 0 ? (
        <LegacyPlanner
          key={character.id}
          characterId={character.id}
          ownerId={character.user_id}
          earned={earned}
          trees={trees}
          initialApplied={cleanLegacy(trees, appliedRows ?? [])}
          initialPlan={cleanLegacy(trees, planRows ?? [])}
        />
      ) : (
        <p className="rounded bg-neutral-800 p-4 text-gray-300">
          The Legacy perk data hasn&apos;t been loaded yet.
        </p>
      )}

      <p className="mt-8 text-xs text-gray-500">
        Legacy perk data from{" "}
        <Link href="https://talentsforever.com" className="text-blue-400">
          Talents Forever
        </Link>{" "}
        (CC BY 4.0), read from the WoW Forever client. Icons and text belong to Blizzard
        Entertainment.
      </p>
    </main>
  );
}

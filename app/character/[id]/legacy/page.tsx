import Link from "next/link";
import { notFound } from "next/navigation";
import { supabase } from "../../../../lib/supabase";
import { cleanLegacy } from "../../../../lib/legacy";
import { loadLegacyText } from "../../../../lib/server-data";
import LegacyPlanner from "./LegacyPlanner";

export const dynamic = "force-dynamic";

export default async function LegacyPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;

  const { data: character } = await supabase
    .from("characters")
    .select("id, name, class, level, user_id")
    .eq("id", id)
    .single();

  if (!character) {
    notFound();
  }

  // Legacy points are earned across the whole account, so they live on the owner's profile
  let earned = 0;
  if (character.user_id) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("legacy_points")
      .eq("id", character.user_id)
      .single();
    earned = profile?.legacy_points ?? 0;
  }

  const { data: rows } = await supabase
    .from("character_legacy")
    .select("tree, perk, rank")
    .eq("character_id", id);

  const { data: planRows } = await supabase
    .from("character_legacy_plans")
    .select("tree, perk, rank")
    .eq("character_id", id);

  const { perks, trees } = await loadLegacyText();

  return (
    <main className="mx-auto max-w-[1500px] p-4 md:p-6">
      <Link href={`/character/${character.id}`} className="text-blue-400">
        ← Back to {character.name}
      </Link>
      <h1 className="mt-4 text-3xl font-bold">
        {character.name}&apos;s Legacy
      </h1>
      <p className="mb-6 mt-3 max-w-3xl text-gray-400">
        Legacy points are earned across your whole account, and each character spends them
        separately. They&apos;re separate from class talent points.
      </p>

      <LegacyPlanner
        key={character.id}
        characterId={character.id}
        ownerId={character.user_id}
        earned={earned}
        perkInfo={perks}
        treeIcons={trees}
        initialApplied={cleanLegacy(rows ?? [])}
        initialPlan={cleanLegacy(planRows ?? [])}
      />

      <p className="mt-8 text-xs text-gray-500">
        Perk text and pictures from{" "}
        <Link href="https://talentsforever.com" className="text-blue-400">
          Talents Forever
        </Link>
        , used under{" "}
        <Link href="https://creativecommons.org/licenses/by/4.0/" className="text-blue-400">
          CC BY 4.0
        </Link>
        . Requirements and per-rank values are from the{" "}
        <Link href="https://wowforevertalent.com/legacy/" className="text-blue-400">
          WoW Forever Talent legacy page
        </Link>
        . It was read from the WoW Forever beta, so it can change. Names, icons and tooltip text
        belong to Blizzard Entertainment. This is a fan project and isn&apos;t affiliated with
        Blizzard.
      </p>
    </main>
  );
}
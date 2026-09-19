import fs from "node:fs/promises";
import path from "node:path";
import Link from "next/link";
import { notFound } from "next/navigation";
import { supabase } from "../../../../lib/supabase";
import { START_VALUES } from "../../../../lib/stats";
import { cleanRanks, type ClassData } from "../../../../lib/talents";
import TalentWorkspace from "./TalentWorkspace";

export const dynamic = "force-dynamic";

type SlotRow = { slot: number; tree: string; talent: string; rank: number };

async function loadClassData(cls: string): Promise<ClassData | null> {
  try {
    const file = path.join(process.cwd(), "lib", "talent-data", `${cls.toLowerCase()}.json`);
    return JSON.parse(await fs.readFile(file, "utf8")) as ClassData;
  } catch {
    return null;
  }
}

// Split saved rows into the Primary (1) and Secondary (2) builds
function bySlot(data: ClassData, rows: SlotRow[] | null) {
  const list = rows ?? [];
  return {
    1: cleanRanks(data, list.filter((r) => r.slot === 1)),
    2: cleanRanks(data, list.filter((r) => r.slot === 2)),
  };
}

export default async function TalentsPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;

  const { data: character } = await supabase
    .from("characters")
    .select("id, name, class, level, user_id, main_spec, off_spec, active_spec")
    .eq("id", id)
    .single();

  if (!character) {
    notFound();
  }

  const data = await loadClassData(character.class);

  const { data: rows } = await supabase
    .from("character_talents")
    .select("slot, tree, talent, rank")
    .eq("character_id", id);

  const { data: planRows } = await supabase
    .from("character_talent_plans")
    .select("slot, tree, talent, rank")
    .eq("character_id", id);

  const { data: statRows } = await supabase
    .from("character_stats")
    .select("stat, value")
    .eq("character_id", id);

  const stats: Record<string, number> = { ...START_VALUES };
  for (const r of statRows ?? []) stats[r.stat] = Number(r.value);

  return (
    <main className="mx-auto max-w-[1500px] p-4 md:p-6">
      <Link href={`/character/${character.id}`} className="text-blue-400">
        ← Back to {character.name}
      </Link>
      <h1 className="mt-4 text-3xl font-bold">
        {character.name}&apos;s Talents
      </h1>
      <p className="mb-6 mt-1 text-gray-400">
        Level {character.level} {character.class}
      </p>

      {data ? (
        <TalentWorkspace
          key={character.id}
          characterId={character.id}
          ownerId={character.user_id}
          level={character.level}
          data={data}
          mainSpec={character.main_spec}
          offSpec={character.off_spec}
          initialActive={character.active_spec === 2 ? 2 : 1}
          initialApplied={bySlot(data, rows)}
          initialPlans={bySlot(data, planRows)}
          stats={stats}
          hasStats={(statRows ?? []).length > 0}
        />
      ) : (
        <div className="rounded bg-neutral-800 p-4">
          <p>The talent data for {character.class} hasn&apos;t been downloaded yet.</p>
          <p className="mt-2 text-sm text-gray-400">
            In the terminal, inside the wow-tracker folder, run:
          </p>
          <pre className="mt-2 rounded bg-neutral-900 p-2 text-sm">
            node scripts/get-talents.mjs
          </pre>
        </div>
      )}

      <p className="mt-8 text-xs text-gray-500">
        Talent data from{" "}
        <Link href="https://talentsforever.com" className="text-blue-400">
          Talents Forever
        </Link>
        , used under{" "}
        <Link href="https://creativecommons.org/licenses/by/4.0/" className="text-blue-400">
          CC BY 4.0
        </Link>
        . It was read from the WoW Forever beta, so it can change. Talent names, icons and tooltip text belong to Blizzard Entertainment. This is a fan project and isn&apos;t affiliated with Blizzard.
      </p>
    </main>
  );
}
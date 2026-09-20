import Link from "next/link";
import { notFound } from "next/navigation";
import { supabase } from "../../../lib/supabase";
import { RACE_FACTION } from "../../../lib/options";
import { pointsForLevel } from "../../../lib/talents";
import { LEGACY_CAP } from "../../../lib/legacy";
import { characterBars, whatsNext } from "../../../lib/progress";
import OwnerActions from "./OwnerActions";
import ProfessionsCard from "./ProfessionsCard";
import GearCard from "./GearCard";
import RacialsCard from "./RacialsCard";
import StatsCard from "./StatsCard";
import ProgressBars from "../../ProgressBars";
import NextList from "../../NextList";
import ImportPanel from "./ImportPanel";


export const dynamic = "force-dynamic";

function sum(o: Record<string, number>) {
  return Object.values(o).reduce((a, b) => a + b, 0);
}

function treeText(o: Record<string, number>) {
  const parts = Object.entries(o).map(([tree, points]) => `${tree} ${points}`);
  return parts.length > 0 ? ` · ${parts.join(" · ")}` : "";
}

export default async function CharacterPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;

  const { data: character } = await supabase
    .from("characters")
    .select("*, profiles(display_name, legacy_points)")
    .eq("id", id)
    .single();

  if (!character) {
    notFound();
  }

  const { data: professions } = await supabase
    .from("character_professions")
    .select("id, profession, skill")
    .eq("character_id", id);

  const { data: gear } = await supabase
    .from("equipped_gear")
    .select("slot, item_name, item_link, item_quality, item_icon, tooltip")
    .eq("character_id", id);

  const { data: stats } = await supabase
    .from("character_stats")
    .select("stat, value")
    .eq("character_id", id);

  const { data: talentRows } = await supabase
    .from("character_talents")
    .select("slot, tree, rank")
    .eq("character_id", id);

  const { data: legacyRows } = await supabase
    .from("character_legacy")
    .select("rank")
    .eq("character_id", id);
  const legacySpent = (legacyRows ?? []).reduce((n, r) => n + r.rank, 0);

  const faction = RACE_FACTION[character.race];

  // Points spent in each tree, for each spec
  const perSlot: Record<number, Record<string, number>> = { 1: {}, 2: {} };
  for (const r of talentRows ?? []) {
    const s = r.slot === 2 ? 2 : 1;
    perSlot[s][r.tree] = (perSlot[s][r.tree] ?? 0) + r.rank;
  }
  const talentBudget = pointsForLevel(character.level);
  const hasSecondary = !!character.off_spec;
  const activeIsSecondary = hasSecondary && character.active_spec === 2;

  // Progress bars and the to-do list, worked out from what's been entered
  const progressInput = {
    level: character.level,
    off_spec: character.off_spec,
    active_spec: character.active_spec,
    character_professions: professions ?? [],
    character_talents: talentRows ?? [],
    character_legacy: legacyRows ?? [],
  };
  const bars = characterBars(progressInput);
  const todos = whatsNext(progressInput, character.profiles?.legacy_points ?? 0);
  if ((stats ?? []).length === 0) {
    todos.push({ kind: "setup", text: "Enter the character's stats" });
  }

  return (
    <main className="mx-auto max-w-[1500px] p-4 md:p-6">
      <Link href="/" className="text-blue-400">← Back</Link>

      <header className="parchment mt-4 p-5 md:p-6">
        <div className="flex flex-wrap items-center gap-5">
          <div className="crest">
            <span className="crest-fallback">{character.class.charAt(0)}</span>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={`/talent-icons/class_${character.class.toLowerCase()}.jpg`} alt="" />
          </div>

          <div className="min-w-0 flex-1">
            <h1 className="text-3xl font-bold md:text-4xl">{character.name}</h1>
            <p className="mt-2 text-lg font-semibold">
              Level {character.level} {character.race} {character.class}
            </p>

            <div className="mt-3 flex flex-wrap gap-2">
              {faction && (
                <span className={`chip ${faction === "Alliance" ? "chip-alliance" : "chip-horde"}`}>
                  {faction}
                </span>
              )}
              {character.ruleset && <span className="chip">{character.ruleset}</span>}
              <span className="chip">{character.character_type}</span>
              {character.guild && <span className="chip">{`<${character.guild}>`}</span>}
              <span className="chip">
                Owned by {character.profiles?.display_name ?? "Unknown"}
              </span>
            </div>

            <div className="mt-2 flex flex-wrap gap-2">
              <span className="chip">
                Main · {character.main_spec || "No spec"} ({character.main_role})
              </span>
              {hasSecondary && !activeIsSecondary && (
                <span className="chip chip-active">Active</span>
              )}
              {hasSecondary && (
                <span className="chip">
                  Off · {character.off_spec}
                  {character.off_role ? ` (${character.off_role})` : ""}
                </span>
              )}
              {activeIsSecondary && <span className="chip chip-active">Active</span>}
            </div>
          </div>

          <div className="hero-actions flex flex-wrap items-center gap-3">
            <Link
              href={`/character/${character.id}/talents`}
              className="rounded bg-blue-600 px-4 py-2 text-white"
            >
              Talent planner
            </Link>
            <OwnerActions characterId={character.id} ownerId={character.user_id} />
          </div>
        </div>
      </header>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <section className="rounded bg-neutral-800 p-4">
          <h2 className="font-bold">Progress</h2>
          <div className="mt-3">
            <ProgressBars bars={bars} compact />
          </div>
        </section>

        <section className="rounded bg-neutral-800 p-4">
          <h2 className="font-bold">What&apos;s next</h2>
          <div className="mt-3">
            <NextList todos={todos} limit={7} empty="All caught up." />
          </div>
        </section>
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-2 xl:grid-cols-3">
        <div className="dash-col flex flex-col gap-4">
          <section className="rounded bg-neutral-800 p-4">
            <div className="flex items-center justify-between">
              <h2 className="font-bold">Talents</h2>
              <Link
                href={`/character/${character.id}/talents`}
                className="rounded bg-blue-600 px-3 py-1 text-sm text-white"
              >
                Open planner
              </Link>
            </div>
            <p className="mt-2 text-sm text-gray-400">
              {hasSecondary ? `Primary (${character.main_spec || "not set"}): ` : ""}
              {sum(perSlot[1])} of {talentBudget} points spent
              {treeText(perSlot[1])}
            </p>
            {hasSecondary && (
              <p className="mt-1 text-sm text-gray-400">
                Secondary ({character.off_spec}): {sum(perSlot[2])} of {talentBudget} points spent
                {treeText(perSlot[2])}
              </p>
            )}
            {hasSecondary && (
              <p className="mt-2 text-xs text-gray-500">
                The stats belong to the {activeIsSecondary ? "secondary" : "primary"} spec.
              </p>
            )}
          </section>

          <section className="rounded bg-neutral-800 p-4">
            <div className="flex items-center justify-between">
              <h2 className="font-bold">Legacy</h2>
              <Link
                href={`/character/${character.id}/legacy`}
                className="rounded bg-blue-600 px-3 py-1 text-sm text-white"
              >
                Open planner
              </Link>
            </div>
            <p className="mt-2 text-sm text-gray-400">
              {legacySpent} of {LEGACY_CAP} points spent
            </p>
          </section>

          <RacialsCard race={character.race} />

          <ProfessionsCard
            characterId={character.id}
            ownerId={character.user_id}
            professions={professions ?? []}
          />


          <ImportPanel
          characterId={character.id}
          ownerId={character.user_id}
          professions={professions ?? []}
          activeSpec={character.active_spec ?? 1}
          />


        </div>

        <div className="dash-col flex flex-col gap-4">
          <StatsCard
            key={`stats-${character.id}`}
            characterId={character.id}
            ownerId={character.user_id}
            stats={stats ?? []}
          />
        </div>

        <div className="dash-col flex flex-col gap-4 lg:col-span-2 xl:col-span-1">
          <GearCard
            key={character.id}
            items={gear ?? []}
            characterName={character.name}
            race={character.race}
            charClass={character.class}
            level={character.level}
          />
        </div>
      </div>
    </main>
  );
}
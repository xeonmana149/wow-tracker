"use client";

import { useEffect, useState, FormEvent } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "../../../lib/supabase";
import GameIcon from "../../GameIcon";
import { PROFESSION_ICONS } from "../../../lib/icons";
import { RecipeChipList, type Recipe } from "../../../lib/recipeDisplay";

const PRIMARY = [
  "Alchemy",
  "Blacksmithing",
  "Enchanting",
  "Engineering",
  "Herbalism",
  "Leatherworking",
  "Mining",
  "Skinning",
  "Tailoring",
];
const SECONDARY = ["Cooking", "First Aid", "Fishing"];
const MAX_SKILL = 300;
const MAX_PRIMARY = 2;

// A recipe entry is a bare string on an older addon build, or a richer
// object (icon/reagents/tooltip/etc.) on newer ones - same shape
// CraftingDirectory reads, now rendered the same expandable way here too
// (2026-10-03, "maybe that list should be part of the character page
// somehow?" - this used to just show a bare "N recipes known" count).
type Profession = {
  id: string;
  profession: string;
  skill: number;
  recipes?: (string | Recipe)[] | null;
};

export default function ProfessionsCard({
  characterId,
  ownerId,
  professions,
}: {
  characterId: string;
  ownerId: string | null;
  professions: Profession[];
}) {
  const router = useRouter();
  const [isOwner, setIsOwner] = useState(false);
  const [newProfession, setNewProfession] = useState("");
  const [newSkill, setNewSkill] = useState(1);
  const [message, setMessage] = useState("");
  // Which profession's recipe list is expanded - at most one at a time,
  // same "click to reveal" behavior as CraftingDirectory's CrafterRow.
  const [openRecipesId, setOpenRecipesId] = useState<string | null>(null);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      setIsOwner(!!ownerId && data.user?.id === ownerId);
    });
  }, [ownerId]);

  const known = professions.map((p) => p.profession);
  const primaryCount = professions.filter((p) => PRIMARY.includes(p.profession)).length;

  const available = [
    ...(primaryCount < MAX_PRIMARY ? PRIMARY : []),
    ...SECONDARY,
  ].filter((p) => !known.includes(p));

  const selected = available.includes(newProfession) ? newProfession : available[0];

  const sorted = [...professions].sort((a, b) => {
    const aPrimary = PRIMARY.includes(a.profession) ? 0 : 1;
    const bPrimary = PRIMARY.includes(b.profession) ? 0 : 1;
    return aPrimary - bPrimary || a.profession.localeCompare(b.profession);
  });

  async function handleAdd(e: FormEvent) {
    e.preventDefault();
    if (!selected) return;
    setMessage("");

    const { error } = await supabase.from("character_professions").insert({
      character_id: characterId,
      profession: selected,
      skill: Math.min(MAX_SKILL, Math.max(1, newSkill || 1)),
    });

    if (error) {
      setMessage(error.message);
    } else {
      setNewSkill(1);
      router.refresh();
    }
  }

  async function handleSkillChange(p: Profession, value: number) {
    const skill = Math.min(MAX_SKILL, Math.max(1, value || 1));
    if (skill === p.skill) return;

    const { error } = await supabase
      .from("character_professions")
      .update({ skill })
      .eq("id", p.id);

    if (error) setMessage(error.message);
    router.refresh();
  }

  async function handleRemove(id: string) {
    const { error } = await supabase
      .from("character_professions")
      .delete()
      .eq("id", id);

    if (error) setMessage(error.message);
    router.refresh();
  }

  return (
    <section className="mt-4 max-w-2xl rounded bg-neutral-800 p-4">
      <h2 className="font-bold">Professions</h2>

      {sorted.length === 0 && (
        <p className="mt-2 text-sm text-gray-400">No professions yet.</p>
      )}

      <ul className="mt-3 flex flex-col gap-3">
        {sorted.map((p) => {
          const recipeCount = Array.isArray(p.recipes) ? p.recipes.length : 0;
          const isOpen = openRecipesId === p.id;
          return (
            <li key={p.id}>
              <div className="flex items-center justify-between gap-3">
                <span className="flex items-center gap-2">
                  <GameIcon name={PROFESSION_ICONS[p.profession]} label={p.profession} size={28} />
                  <span>
                    {p.profession}
                    {PRIMARY.includes(p.profession) ? "" : " (secondary)"}
                  </span>
                  {recipeCount > 0 && (
                    <button
                      type="button"
                      onClick={() => setOpenRecipesId(isOpen ? null : p.id)}
                      className="rounded px-1.5 py-0.5 text-xs font-bold text-yellow-300 hover:bg-neutral-700"
                    >
                      {isOpen ? "Hide" : `${recipeCount} recipe${recipeCount === 1 ? "" : "s"} known`}
                    </button>
                  )}
                </span>

                {isOwner ? (
                  <span className="flex items-center gap-2">
                    <input
                      key={`${p.id}-${p.skill}`}
                      type="number"
                      min={1}
                      max={MAX_SKILL}
                      defaultValue={p.skill}
                      onBlur={(e) => handleSkillChange(p, Number(e.target.value))}
                      className="w-20 rounded bg-white p-1 text-black"
                    />
                    <span className="text-sm text-gray-400">/ {MAX_SKILL}</span>
                    <button
                      onClick={() => handleRemove(p.id)}
                      className="rounded bg-red-700 px-2 py-1 text-sm text-white"
                    >
                      Remove
                    </button>
                  </span>
                ) : (
                  <span className="text-sm text-gray-400">
                    {p.skill} / {MAX_SKILL}
                  </span>
                )}
              </div>

              <div className="mt-1 h-2 rounded bg-neutral-700">
                <div
                  className={`h-2 rounded ${
                    p.skill >= MAX_SKILL ? "bg-yellow-500" : "bg-blue-500"
                  }`}
                  style={{ width: `${(p.skill / MAX_SKILL) * 100}%` }}
                />
              </div>

              {isOpen && recipeCount > 0 && (
                <div className="mt-2 pl-9">
                  <RecipeChipList recipes={p.recipes ?? []} />
                </div>
              )}
            </li>
          );
        })}
      </ul>

      {isOwner && available.length > 0 && (
        <form onSubmit={handleAdd} className="mt-5 flex flex-wrap items-end gap-3">
          <label className="flex flex-col gap-1 text-sm">
            Add profession
            <select
              value={selected}
              onChange={(e) => setNewProfession(e.target.value)}
              className="rounded bg-white p-2 text-black"
            >
              {available.map((p) => (
                <option key={p}>{p}</option>
              ))}
            </select>
          </label>

          <label className="flex flex-col gap-1 text-sm">
            Skill
            <input
              type="number"
              min={1}
              max={MAX_SKILL}
              value={newSkill}
              onChange={(e) => setNewSkill(Number(e.target.value))}
              className="w-24 rounded bg-white p-2 text-black"
            />
          </label>

          <button type="submit" className="rounded bg-blue-600 px-4 py-2 text-white">
            Add
          </button>
        </form>
      )}

      {isOwner && primaryCount >= MAX_PRIMARY && (
        <p className="mt-3 text-xs text-gray-500">
          {MAX_PRIMARY} primary professions is the limit. Remove one to add another.
        </p>
      )}

      {message && <p className="mt-3 text-sm text-red-400">{message}</p>}
    </section>
  );
}
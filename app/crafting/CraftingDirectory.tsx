"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { PRIMARY_PROFESSIONS, PROFESSION_ICONS, classIcon, iconUrlForFileId } from "../../lib/icons";
import { MAX_SKILL, SECONDARY_PROFESSIONS, SUPPLIED_BY } from "../../lib/professions";
import GameIcon from "../GameIcon";
import {
  QualityIcon,
  RecipeChip,
  RecipeDetails,
  normalizeRecipe,
  type Recipe,
} from "../../lib/recipeDisplay";
import type { CraftingPlayer } from "./page";

type Entry = { id: string; name: string; cls: string; owner: string; skill: number; recipes: Recipe[] };

// Herbalism/Mining/Skinning are "primary" professions in the sense that they
// take up one of your two primary profession slots, but they don't actually
// craft anything - they gather materials for the other primary professions.
// Worth its own row so it doesn't get lost among Alchemy/Blacksmithing/etc.
const GATHERING_PROFESSIONS = new Set(["Herbalism", "Mining", "Skinning"]);
const CRAFTING_PROFESSIONS = PRIMARY_PROFESSIONS.filter((p) => !GATHERING_PROFESSIONS.has(p));
const GATHERING_LIST = PRIMARY_PROFESSIONS.filter((p) => GATHERING_PROFESSIONS.has(p));

const ALL_PROFESSIONS = [...PRIMARY_PROFESSIONS, ...SECONDARY_PROFESSIONS];

// Everyone in the group who has this profession, best first
function crafters(players: CraftingPlayer[], profession: string): Entry[] {
  const out: Entry[] = [];
  for (const p of players) {
    for (const c of p.characters) {
      for (const pr of c.character_professions ?? []) {
        if (pr.profession === profession) {
          out.push({
            id: c.id,
            name: c.name,
            cls: c.class,
            owner: p.name,
            skill: pr.skill,
            recipes: (pr.recipes ?? []).map(normalizeRecipe),
          });
        }
      }
    }
  }
  return out.sort((a, b) => b.skill - a.skill);
}

function SkillBar({ skill }: { skill: number }) {
  return (
    <div className="mt-0.5 h-1 rounded bg-neutral-700">
      <div
        className={`h-1 rounded ${skill >= MAX_SKILL ? "bg-yellow-500" : "bg-blue-500"}`}
        style={{ width: `${Math.min(100, (skill / MAX_SKILL) * 100)}%` }}
      />
    </div>
  );
}

// One crafter's row within a profession tab. Their known-recipe list is
// only ever fetched from data already on hand (character_professions.recipes,
// pulled in on the same query as everything else) - expanding just toggles
// whether it's shown, no extra request.
function CrafterRow({ e }: { e: Entry }) {
  const [open, setOpen] = useState(false);
  const hasRecipes = e.recipes.length > 0;

  return (
    <li>
      <div className="flex items-center gap-2 rounded px-1 py-0.5 hover:bg-neutral-900">
        <Link href={`/character/${e.id}`} className="flex min-w-0 flex-1 items-center gap-2">
          <GameIcon name={classIcon(e.cls)} label={e.cls} size={24} round />
          <span className="min-w-0 flex-1 truncate">
            <span className="font-bold text-white">{e.name}</span>{" "}
            <span className="text-xs text-gray-500">{e.owner}</span>
          </span>
          <span className={e.skill >= MAX_SKILL ? "font-bold text-yellow-300" : "text-gray-300"}>
            {e.skill}
          </span>
        </Link>
        {hasRecipes && (
          <button
            type="button"
            onClick={() => setOpen((v) => !v)}
            className="shrink-0 rounded px-2 py-0.5 text-xs text-gray-400 hover:bg-neutral-700 hover:text-white"
          >
            {open ? "Hide" : `${e.recipes.length} recipes`}
          </button>
        )}
      </div>
      <SkillBar skill={e.skill} />
      {open && hasRecipes && (
        <div className="mb-2 mt-1 flex flex-wrap gap-1.5 pl-8">
          {[...e.recipes]
            .sort((a, b) => a.name.localeCompare(b.name))
            .map((r) => (
              <RecipeChip key={r.name} r={r} />
            ))}
        </div>
      )}
    </li>
  );
}

function ProfessionPanel({ profession, list }: { profession: string; list: Entry[] }) {
  const supplier = SUPPLIED_BY[profession];
  const knownRecipes = list.reduce((n, e) => n + e.recipes.length, 0);

  return (
    <section className="rounded bg-neutral-800 p-4">
      <div className="flex items-center gap-3">
        <GameIcon name={PROFESSION_ICONS[profession]} label={profession} size={40} />
        <div className="min-w-0 flex-1">
          <h3 className="text-lg font-bold">{profession}</h3>
          <p className={`text-sm ${list.length === 0 ? "text-red-400" : "text-gray-400"}`}>
            {list.length === 0
              ? "Nobody has this yet"
              : `${list.length} ${list.length === 1 ? "character" : "characters"}${
                  knownRecipes > 0 ? ` · ${knownRecipes} recipes recorded` : ""
                }`}
          </p>
        </div>
      </div>

      {list.length > 0 && (
        <ul className="mt-3 flex flex-col gap-2">
          {list.map((e) => (
            <CrafterRow key={e.id} e={e} />
          ))}
        </ul>
      )}

      {supplier && (
        <p className="mt-3 border-t border-neutral-700 pt-2 text-xs text-gray-500">
          Materials come from {supplier}: {list.length > 0 ? "see above" : "nobody has this yet"}
        </p>
      )}
    </section>
  );
}

// One matched recipe within the search results - hovering its name/icon
// shows the same floating tooltip+reagents panel a RecipeChip does, above
// the list of everyone who knows it.
function SearchResultItem({
  profession,
  recipe,
  crafters: es,
}: {
  profession: string;
  recipe: Recipe;
  crafters: Entry[];
}) {
  const [open, setOpen] = useState(false);

  return (
    <li className="rounded bg-neutral-800 p-3">
      <div
        className="relative inline-block"
        onMouseEnter={() => setOpen(true)}
        onMouseLeave={() => setOpen(false)}
      >
        <button type="button" onClick={() => setOpen((v) => !v)} className="flex items-center gap-2 text-left">
          <QualityIcon src={iconUrlForFileId(recipe.icon)} label={recipe.name} size={28} color={recipe.color} />
          <span
            style={recipe.color ? { color: `#${recipe.color}` } : undefined}
            className="font-bold text-white"
          >
            {recipe.name}
          </span>
          <span className="text-xs text-gray-500">({profession})</span>
        </button>
        {open && (
          <div className="absolute left-0 top-full z-30 mt-1">
            <RecipeDetails r={recipe} />
          </div>
        )}
      </div>
      <ul className="mt-2 flex flex-col gap-1 pl-8">
        {es.map((e) => (
          <li key={e.id}>
            <Link
              href={`/character/${e.id}`}
              className="flex items-center gap-2 rounded px-1 py-0.5 hover:bg-neutral-900"
            >
              <GameIcon name={classIcon(e.cls)} label={e.cls} size={20} round />
              <span className="min-w-0 flex-1 truncate">
                <span className="font-bold text-white">{e.name}</span>{" "}
                <span className="text-xs text-gray-500">{e.owner}</span>
              </span>
              <span className={e.skill >= MAX_SKILL ? "font-bold text-yellow-300" : "text-gray-300"}>
                {e.skill}
              </span>
            </Link>
          </li>
        ))}
      </ul>
    </li>
  );
}

// Recipe search hits every profession's recipe lists at once, regardless of
// which tab is selected - the whole point is not having to know which
// profession makes something before you can look it up.
function SearchResults({
  results,
}: {
  results: { profession: string; recipe: Recipe; crafters: Entry[] }[];
}) {
  if (results.length === 0) {
    return <p className="mt-4 text-sm text-gray-400">No known recipe matches that.</p>;
  }

  return (
    <ul className="mt-4 flex flex-col gap-3">
      {results.map(({ profession, recipe, crafters: es }) => (
        <SearchResultItem key={`${profession}-${recipe.name}`} profession={profession} recipe={recipe} crafters={es} />
      ))}
    </ul>
  );
}

export default function CraftingDirectory({ players }: { players: CraftingPlayer[] }) {
  const [tab, setTab] = useState<string>(PRIMARY_PROFESSIONS[0]);
  const [query, setQuery] = useState("");

  const lists = useMemo(() => {
    const out: Record<string, Entry[]> = {};
    for (const p of ALL_PROFESSIONS) out[p] = crafters(players, p);
    return out;
  }, [players]);

  const missing = PRIMARY_PROFESSIONS.filter((p) => lists[p].length === 0);

  const searchResults = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return null;
    const byRecipe: Record<string, { profession: string; recipe: Recipe; crafters: Entry[] }> = {};
    for (const profession of ALL_PROFESSIONS) {
      for (const e of lists[profession]) {
        for (const r of e.recipes) {
          if (!r.name.toLowerCase().includes(q)) continue;
          const key = `${profession}::${r.name}`;
          if (!byRecipe[key]) byRecipe[key] = { profession, recipe: r, crafters: [] };
          // Prefer whichever copy of this recipe has the most captured
          // (icon/color/reagents/tooltip), in case one crafter's sync
          // recorded it before a given addon update and another's after.
          const cur = byRecipe[key].recipe;
          if ((!cur.icon && r.icon) || (!cur.color && r.color) || (!cur.reagents && r.reagents)) {
            byRecipe[key].recipe = { ...r, icon: r.icon ?? cur.icon, color: r.color ?? cur.color };
          }
          byRecipe[key].crafters.push(e);
        }
      }
    }
    return Object.values(byRecipe)
      .map((m) => ({ ...m, crafters: [...m.crafters].sort((a, b) => b.skill - a.skill) }))
      .sort((a, b) => a.recipe.name.localeCompare(b.recipe.name));
  }, [query, lists]);

  const TabButton = ({ p }: { p: string }) => (
    <button
      type="button"
      onClick={() => setTab(p)}
      aria-pressed={tab === p}
      className={`flex shrink-0 items-center gap-2 rounded-lg border px-3 py-2 text-sm transition-colors ${
        tab === p
          ? "border-amber-400 bg-amber-500/10 text-white"
          : "border-neutral-700 bg-neutral-800 text-gray-300 hover:bg-neutral-700"
      }`}
    >
      <GameIcon name={PROFESSION_ICONS[p]} label={p} size={20} />
      {p}
      {lists[p]?.length === 0 && <span className="text-red-400">·</span>}
    </button>
  );

  return (
    <div>
      <div className="mb-4">
        <p className="mt-1 text-sm text-gray-400">
          Who can make what across the whole group, best skill first. Search by recipe name to
          find it regardless of profession.
        </p>
        {missing.length > 0 ? (
          <p className="mt-2 text-sm text-red-400">
            Nobody in the group has: {missing.join(", ")}
          </p>
        ) : (
          <p className="mt-2 text-sm text-green-400">Every primary profession is covered.</p>
        )}
      </div>

      <input
        type="text"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder="Search recipes, e.g. &quot;Runed Copper Rod&quot;"
        className="w-full rounded border border-neutral-700 bg-neutral-900 px-3 py-2 text-sm text-white placeholder:text-gray-500 focus:border-amber-400 focus:outline-none"
      />

      {searchResults ? (
        <SearchResults results={searchResults} />
      ) : (
        <>
          <div className="mt-4 flex flex-col gap-3">
            <div>
              <h3 className="mb-1 text-xs uppercase tracking-wide text-gray-500">
                Crafting professions
              </h3>
              <div className="flex gap-2 overflow-x-auto pb-1">
                {CRAFTING_PROFESSIONS.map((p) => (
                  <TabButton key={p} p={p} />
                ))}
              </div>
            </div>
            <div>
              <h3 className="mb-1 text-xs uppercase tracking-wide text-gray-500">
                Gathering professions
              </h3>
              <div className="flex gap-2 overflow-x-auto pb-1">
                {GATHERING_LIST.map((p) => (
                  <TabButton key={p} p={p} />
                ))}
              </div>
            </div>
            <div>
              <h3 className="mb-1 text-xs uppercase tracking-wide text-gray-500">
                Secondary professions
              </h3>
              <div className="flex gap-2 overflow-x-auto pb-1">
                {SECONDARY_PROFESSIONS.map((p) => (
                  <TabButton key={p} p={p} />
                ))}
              </div>
            </div>
          </div>
          <div className="mt-4">
            <ProfessionPanel profession={tab} list={lists[tab]} />
          </div>
        </>
      )}
    </div>
  );
}
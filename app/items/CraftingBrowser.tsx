"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { PRIMARY_PROFESSIONS, PROFESSION_ICONS, classIcon, iconUrlForFileId } from "../../lib/icons";
import { MAX_SKILL, SECONDARY_PROFESSIONS, SUPPLIED_BY } from "../../lib/professions";
import GameIcon from "../GameIcon";
import type { CraftingPlayer } from "./craftingTypes";

type Reagent = {
  itemID: number;
  name: string;
  icon?: number | string | null;
  quantity: number;
  // Bare "rrggbb" hex (no '#'), read off the reagent's own rendered
  // tooltip color in-game - this server's items don't reliably carry
  // quality any other way.
  color?: string | null;
};
type Recipe = {
  name: string;
  icon?: number | string | null;
  reagents?: Reagent[];
  // Raw tooltip text lines scraped from the crafted item, e.g. "Use:
  // Constructs a sharpening wheel..." / "Requires a Campfire nearby" -
  // line 1 is always just the item's own name, so it's skipped wherever
  // this is displayed. Coin values on a Sell Price line come through as
  // literal {gold}/{silver}/{copper} tokens (see renderTooltipLine below)
  // rather than real numbers - everything else is plain white/gray text,
  // same as the rest of the site's item tooltips.
  tooltip?: string[];
  // The crafted item's own quality color, same "rrggbb" hex convention.
  color?: string | null;
};

const COIN_COLORS: Record<string, string> = {
  gold: "#ffd700",
  silver: "#c0c0c0",
  copper: "#b87333",
};

// A tooltip line can contain {gold}/{silver}/{copper} tokens in place of
// WoW's inline coin icons (see the addon's stripMarkup) - swapped here for
// small colored dots since the real icon images aren't available client-side.
function renderTooltipLine(line: string) {
  const parts = line.split(/(\{gold\}|\{silver\}|\{copper\})/g);
  return parts.map((part, i) => {
    const m = /^\{(gold|silver|copper)\}$/.exec(part);
    if (!m) return <span key={i}>{part}</span>;
    return (
      <span
        key={i}
        title={m[1]}
        className="mx-0.5 inline-block h-2.5 w-2.5 shrink-0 rounded-full align-middle"
        style={{ backgroundColor: COIN_COLORS[m[1]] }}
      />
    );
  });
}

// A game icon with a colored ring around it matching the item's quality
// (green/blue/purple/etc, same as the in-game border) - falls back to
// GameIcon's own default border when no color was captured.
function QualityIcon({
  src,
  label,
  size,
  color,
}: {
  src?: string | null;
  label: string;
  size: number;
  color?: string | null;
}) {
  return (
    <span
      className="inline-block shrink-0 rounded"
      style={color ? { boxShadow: `0 0 0 2px #${color}` } : undefined}
    >
      <GameIcon src={src} label={label} size={size} />
    </span>
  );
}
type Entry = { id: string; name: string; cls: string; owner: string; skill: number; recipes: Recipe[] };

// A recipe entry is a bare string on an addon build from before 1.3.0 (no
// icon capture yet), or a progressively richer object on newer ones
// (icon+id at 1.3.0, reagents+tooltip after that) - this makes every entry
// look the same regardless of which addon version actually produced it.
function normalizeRecipe(r: string | Recipe): Recipe {
  return typeof r === "string" ? { name: r } : r;
}

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

// A recipe's "Use: ..." description and reagent list, shown when a
// RecipeChip is expanded - styled loosely like the real in-game tooltip
// (dark box, gold border) even though the colors on individual lines
// couldn't be preserved, only the text.
function RecipeDetails({ r }: { r: Recipe }) {
  // Line 1 of a scraped tooltip is always just the item's own name, which
  // is already shown as the chip's label - skip it here to avoid repeating.
  const lines = (r.tooltip ?? []).slice(1);
  const reagents = r.reagents ?? [];

  if (lines.length === 0 && reagents.length === 0) {
    return (
      <div className="mt-2 rounded-lg border border-amber-700/60 bg-neutral-950 p-3">
        <p className="text-xs text-gray-500">
          No extra details captured for this recipe yet - run /wft recipescan again in-game to
          pick them up.
        </p>
      </div>
    );
  }

  return (
    <div className="w-72 max-w-full rounded-lg border border-amber-700/60 bg-neutral-950 p-3">
      {lines.map((line, i) => (
        <p key={i} className="text-xs leading-snug text-gray-300">
          {renderTooltipLine(line)}
        </p>
      ))}
      {reagents.length > 0 && (
        <div className={lines.length > 0 ? "mt-2 border-t border-neutral-800 pt-2" : ""}>
          <p className="text-xs font-bold text-amber-400">Reagents</p>
          <ul className="mt-1 flex flex-col gap-1">
            {reagents.map((rg) => (
              <li key={rg.itemID} className="flex items-center gap-1.5 text-xs">
                <QualityIcon src={iconUrlForFileId(rg.icon)} label={rg.name} size={20} color={rg.color} />
                <span style={rg.color ? { color: `#${rg.color}` } : undefined} className="text-gray-300">
                  {rg.quantity}x {rg.name}
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

// A single recipe pill - hovering shows its tooltip text and reagent list
// in a floating panel below it, just like hovering the recipe in-game.
// Also toggles on click/tap, since hover doesn't exist on touch devices.
// Uses data already fetched with everything else - no extra request.
function RecipeChip({ r }: { r: Recipe }) {
  const [open, setOpen] = useState(false);

  return (
    <div
      className="relative"
      onMouseEnter={() => setOpen(true)}
      onMouseLeave={() => setOpen(false)}
    >
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="flex items-center gap-1 rounded border border-neutral-700 bg-neutral-900 py-0.5 pl-0.5 pr-1.5 text-xs hover:border-amber-500"
      >
        <QualityIcon src={iconUrlForFileId(r.icon)} label={r.name} size={18} color={r.color} />
        <span style={r.color ? { color: `#${r.color}` } : undefined} className="text-gray-300">
          {r.name}
        </span>
      </button>
      {open && (
        <div className="absolute left-0 top-full z-30 mt-1">
          <RecipeDetails r={r} />
        </div>
      )}
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

export default function CraftingBrowser({ players }: { players: CraftingPlayer[] }) {
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
      className={`tab-btn shrink-0 ${tab === p ? "tab-btn-active" : ""}`}
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
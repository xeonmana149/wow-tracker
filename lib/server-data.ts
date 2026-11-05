import fs from "node:fs/promises";
import path from "node:path";
import { cache } from "react";
import { SPECS } from "./options";
import { norm } from "./icons";
import type { ClassData } from "./talents";
import { fetchGameData, type LegacyData, type RacialsData } from "./gameData";

const DIR = path.join(process.cwd(), "lib", "talent-data");

// Game data (talent trees, racials, legacy perks) auto-updates: it's fetched
// from talentsforever.com (the current client's data) through Next's data
// cache, re-checked at most once a day, so a Blizzard change to the trees
// reaches the site within a day with no code change or redeploy. If that
// fetch fails, the bundled copy in lib/talent-data (refresh it with
// `npx tsx scripts/get-talents.mts`) is used instead. Once per request.
const GAME_DATA_REVALIDATE_SECONDS = 60 * 60 * 24;

const loadLive = cache(async () => {
  try {
    const live = await fetchGameData(async (url) => {
      const res = await fetch(url, { next: { revalidate: GAME_DATA_REVALIDATE_SECONDS } });
      if (!res.ok) throw new Error(`status ${res.status}`);
      return res.json();
    });
    return live;
  } catch {
    return null;
  }
});

async function loadBundled<T>(file: string): Promise<T | null> {
  try {
    return JSON.parse(await fs.readFile(path.join(DIR, file), "utf8")) as T;
  } catch {
    return null;
  }
}

export async function loadClassData(cls: string): Promise<ClassData | null> {
  const key = cls.toLowerCase();
  const live = (await loadLive())?.classes.find((c) => c.class.toLowerCase() === key);
  return live ?? loadBundled<ClassData>(`${key}.json`);
}

export async function loadRacials(): Promise<RacialsData> {
  const live = (await loadLive())?.racials;
  if (live && Object.keys(live.races).length > 0) return live;
  return (await loadBundled<RacialsData>("_racials.json")) ?? { races: {} };
}

export async function loadLegacyData(): Promise<LegacyData | null> {
  return (await loadLive())?.legacy ?? loadBundled<LegacyData>("_legacy.json");
}

// Race and racial-ability pictures. Ability names are stored in a matchable form.
export async function loadIcons(): Promise<{
  races: Record<string, string>;
  abilities: Record<string, string>;
}> {
  const races: Record<string, string> = {};
  const abilities: Record<string, string> = {};
  try {
    const raw = JSON.parse(await fs.readFile(path.join(DIR, "_icons.json"), "utf8")) as {
      races?: Record<string, string>;
      abilities?: Record<string, string>;
    };
    Object.assign(races, raw.races ?? {});
    for (const [name, icon] of Object.entries(raw.abilities ?? {})) abilities[norm(name)] = icon;
  } catch {
    // no bundled icon list - the racials data below still covers it
  }
  // The current racials data wins over the bundled list
  for (const [race, r] of Object.entries((await loadRacials()).races)) {
    if (r.icon) races[race] = r.icon;
    for (const a of r.abilities) if (a.icon) abilities[norm(a.name)] = a.icon;
  }
  return { races, abilities };
}

function matches(treeName: string, specName: string) {
  const a = treeName.toLowerCase();
  const b = specName.toLowerCase();
  return a === b || a.startsWith(b) || b.startsWith(a);
}

// The picture for each spec, keyed "Class|Spec". It's the icon of the matching talent tree.
export async function loadSpecIcons(): Promise<Record<string, string>> {
  const out: Record<string, string> = {};
  for (const cls of Object.keys(SPECS)) {
    const data = await loadClassData(cls);
    if (!data) continue;
    for (const spec of SPECS[cls]) {
      const tree = data.trees.find((t) => matches(t.name, spec.name));
      if (tree) out[`${cls}|${spec.name}`] = tree.icon;
    }
  }
  return out;
}

// Everything the character cards need: spec pictures and the order of each class's talent trees
export async function loadCardData(): Promise<{
  specIcons: Record<string, string>;
  treeNames: Record<string, string[]>;
}> {
  const specIcons: Record<string, string> = {};
  const treeNames: Record<string, string[]> = {};

  for (const cls of Object.keys(SPECS)) {
    const data = await loadClassData(cls);
    if (!data) continue;

    treeNames[cls] = data.trees.map((t) => t.name);
    for (const spec of SPECS[cls]) {
      const tree = data.trees.find((t) => matches(t.name, spec.name));
      if (tree) specIcons[`${cls}|${spec.name}`] = tree.icon;
    }
  }

  return { specIcons, treeNames };
}

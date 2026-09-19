import fs from "node:fs/promises";
import path from "node:path";
import { SPECS } from "./options";
import { norm } from "./icons";
import type { ClassData } from "./talents";

const DIR = path.join(process.cwd(), "lib", "talent-data");

export async function loadClassData(cls: string): Promise<ClassData | null> {
  try {
    const file = path.join(DIR, `${cls.toLowerCase()}.json`);
    return JSON.parse(await fs.readFile(file, "utf8")) as ClassData;
  } catch {
    return null;
  }
}

// Race and racial-ability pictures. Ability names are stored in a matchable form.
export async function loadIcons(): Promise<{
  races: Record<string, string>;
  abilities: Record<string, string>;
}> {
  try {
    const raw = JSON.parse(await fs.readFile(path.join(DIR, "_icons.json"), "utf8")) as {
      races?: Record<string, string>;
      abilities?: Record<string, string>;
    };
    const abilities: Record<string, string> = {};
    for (const [name, icon] of Object.entries(raw.abilities ?? {})) {
      abilities[norm(name)] = icon;
    }
    return { races: raw.races ?? {}, abilities };
  } catch {
    return { races: {}, abilities: {} };
  }
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

type LegacyFile = {
  trees?: { name: string; icon: string; perks?: [string, number, string, string][] }[];
};

// Legacy perk descriptions and pictures from the downloaded data, keyed by perk name
export async function loadLegacyText(): Promise<{
  perks: Record<string, { desc: string; icon: string }>;
  trees: Record<string, string>;
}> {
  const perks: Record<string, { desc: string; icon: string }> = {};
  const trees: Record<string, string> = {};

  try {
    const raw = JSON.parse(
      await fs.readFile(path.join(DIR, "_legacy.json"), "utf8")
    ) as LegacyFile;

    for (const tree of raw.trees ?? []) {
      trees[tree.name] = tree.icon;
      for (const [name, , desc, icon] of tree.perks ?? []) {
        perks[norm(name)] = { desc, icon };
      }
    }
  } catch {
    // not downloaded yet: the planner still works, without descriptions and pictures
  }

  return { perks, trees };
}
// Turns talentsforever.com's per-class data exports into the shapes the site
// uses. Shared by scripts/get-talents.mts (refreshes the bundled JSON in
// lib/talent-data) and lib/server-data.ts (fetches it live, re-checked daily
// through Next's data cache), so both always agree.
//
// Source: https://talentsforever.com/data/<class>.json - Talents Forever,
// CC BY 4.0, read from the WoW Forever client's own data files. Icons and
// tooltip text belong to Blizzard Entertainment.
//
// Pure functions only - no fs, no network - so this is safe anywhere.

import type { ClassData, Talent, Tree } from "./talents";

export const GAME_DATA_SOURCE = "https://talentsforever.com";
export const GAME_DATA_CLASSES = [
  "warrior",
  "paladin",
  "hunter",
  "rogue",
  "priest",
  "shaman",
  "mage",
  "warlock",
  "druid",
] as const;

export type Racial = {
  name: string;
  kind: "Active" | "Passive";
  description: string;
  icon: string | null;
};

export type RacialsData = {
  // Race name as the site stores it (lib/options.ts RACES), e.g. "High Order Skyborne"
  races: Record<string, { icon: string | null; classes: string[]; abilities: Racial[] }>;
};

export type LegacyPerkData = {
  name: string;
  max: number;
  row: number; // 1-based, the client's own layout
  col: number; // 1-based, 1 to 4
  icon: string;
  ranks: string[]; // full tooltip text of each rank
  gate: number; // points needed in this tree from OTHER perks
  req: string | null; // perk in this tree that must be at max rank first
  placeholder: boolean; // "To be added in a future update" slot
  passive: boolean;
  cost: string | null; // e.g. "25 sec cast | 23 hour cooldown"
};

export type LegacyTreeData = { id: number | null; name: string; icon: string; perks: LegacyPerkData[] };

export type LegacyData = {
  points: number;
  source: string | null;
  trees: LegacyTreeData[];
};

// ---------------------------------------------------------------------
// Raw (talentsforever.com) shapes - only the fields read here
// ---------------------------------------------------------------------
type RawTalent = {
  name: string;
  max: number;
  row: number;
  col: number;
  passive?: boolean;
  icon: string;
  desc?: string[] | Record<string, string>;
  complete?: boolean;
  req?: string | null;
  reqText?: string | null;
  cost?: string | null;
  scaleIdx?: number[];
  classic?: { status?: string };
};

type RawRacialGroup = {
  race: string;
  icon?: string;
  classes?: string[];
  abilities?: [string, string, string?][];
};

type RawLegacyPerk = {
  name: string;
  max: number;
  row: number;
  col: number;
  icon?: string;
  ranks?: string[];
  gate?: number;
  req?: string;
  placeholder?: boolean;
  passive?: boolean;
  cost?: string;
};

export type RawClassFile = {
  class: string;
  generated?: string;
  talents: { source?: string; trees: { name: string; icon: string; talents: RawTalent[] }[] };
  racials?: Record<string, RawRacialGroup[]>;
  legacy?: {
    points?: number;
    source?: string;
    trees?: { id?: number; name: string; icon: string; perks?: RawLegacyPerk[] }[];
  };
};

// ---------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------
function clean(text: unknown) {
  return String(text ?? "")
    .replace(/<!--.*?-->/g, "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .trim();
}

// Ranks come as a list for some talents and as { "1": text } for others. Make them all the second kind.
function normalizeDesc(desc: RawTalent["desc"]): Record<string, string> {
  const out: Record<string, string> = {};
  if (Array.isArray(desc)) {
    desc.forEach((text, i) => {
      if (text) out[String(i + 1)] = clean(text);
    });
  } else if (desc) {
    for (const [rank, text] of Object.entries(desc)) out[rank] = clean(text);
  }
  return out;
}

// talentsforever names the two Skyborne races "Skyborne (High Order)" and
// "Skyborne (Windshaper)"; the site stores them as "High Order Skyborne" and
// "Windshaper Skyborne" (lib/options.ts).
export function siteRaceName(raw: string) {
  const m = /^Skyborne \((.+)\)$/.exec(raw.trim());
  return m ? `${m[1]} Skyborne` : raw.trim();
}

// Actives open their tooltip with a cast time, range or channel ("Instant, 2 min
// cooldown. ..."). Only the start counts - passives like Touch of the Grave
// mention an internal cooldown later in the text.
function racialKind(desc: string): "Active" | "Passive" {
  return /^(instant|channeled|[\d.]+ sec cast|\d+ yd range)/i.test(desc) ? "Active" : "Passive";
}

// ---------------------------------------------------------------------
// Transforms
// ---------------------------------------------------------------------
export function transformClass(raw: RawClassFile): ClassData {
  const trees: Tree[] = raw.talents.trees.map((tree) => ({
    name: tree.name,
    icon: tree.icon,
    talents: tree.talents.map(
      (t): Talent => ({
        name: t.name,
        max: t.max,
        row: t.row,
        col: t.col,
        passive: t.passive !== false,
        icon: t.icon,
        desc: normalizeDesc(t.desc),
        complete: !!t.complete,
        req: t.req ?? null,
        reqText: t.reqText ? clean(t.reqText) : null,
        cost: t.cost ? clean(t.cost) : null,
        scaleIdx: t.scaleIdx ?? [],
        isNew: t.classic?.status === "new",
      })
    ),
  }));
  return { class: raw.class, generated: raw.generated ?? "", trees };
}

// Every class file lists the races that can play it, so merge across all of them
export function transformRacials(files: RawClassFile[]): RacialsData {
  const races: RacialsData["races"] = {};
  for (const file of files) {
    for (const groups of Object.values(file.racials ?? {})) {
      for (const g of groups) {
        const name = siteRaceName(g.race);
        const entry = (races[name] ??= { icon: g.icon ?? null, classes: [], abilities: [] });
        for (const cls of g.classes ?? []) if (!entry.classes.includes(cls)) entry.classes.push(cls);
        for (const [abilityName, desc, icon] of g.abilities ?? []) {
          if (entry.abilities.some((a) => a.name === abilityName)) continue;
          const description = clean(desc);
          entry.abilities.push({ name: abilityName, kind: racialKind(description), description, icon: icon ?? null });
        }
      }
    }
  }
  return { races };
}

export function transformLegacy(files: RawClassFile[]): LegacyData | null {
  const raw = files.find((f) => f.legacy?.trees?.length)?.legacy;
  if (!raw?.trees) return null;
  return {
    points: raw.points ?? 16,
    source: raw.source ?? null,
    trees: raw.trees.map((tree) => ({
      id: tree.id ?? null,
      name: tree.name,
      icon: tree.icon,
      perks: (tree.perks ?? []).map((p) => ({
        name: p.name,
        max: p.max,
        row: p.row,
        col: p.col,
        icon: p.icon ?? "inv_misc_questionmark",
        ranks: (p.ranks ?? []).map(clean),
        gate: p.gate ?? 0,
        req: p.req ?? null,
        placeholder: !!p.placeholder,
        passive: p.passive !== false,
        cost: p.cost ? clean(p.cost) : null,
      })),
    })),
  };
}

// Every icon name the transformed data refers to (for bundling locally)
export function iconsIn(classes: ClassData[], racials: RacialsData, legacy: LegacyData | null) {
  const icons = new Set<string>();
  for (const c of classes) for (const t of c.trees) {
    icons.add(t.icon);
    for (const talent of t.talents) icons.add(talent.icon);
  }
  for (const r of Object.values(racials.races)) {
    if (r.icon) icons.add(r.icon);
    for (const a of r.abilities) if (a.icon) icons.add(a.icon);
  }
  for (const t of legacy?.trees ?? []) {
    icons.add(t.icon);
    for (const p of t.perks) icons.add(p.icon);
  }
  icons.delete("");
  return icons;
}

// Downloads and transforms everything. `fetchJson` is passed in so the
// script and the site's loader can each use their own fetch options.
export async function fetchGameData(fetchJson: (url: string) => Promise<unknown>) {
  const files: RawClassFile[] = [];
  const failed: string[] = [];
  for (const cls of GAME_DATA_CLASSES) {
    try {
      const raw = (await fetchJson(`${GAME_DATA_SOURCE}/data/${cls}.json`)) as RawClassFile;
      if (!raw?.talents?.trees?.length) throw new Error("no talent trees");
      files.push(raw);
    } catch (e) {
      failed.push(`${cls}: ${e instanceof Error ? e.message : e}`);
    }
  }
  return {
    classes: files.map(transformClass),
    racials: transformRacials(files),
    legacy: transformLegacy(files),
    failed,
  };
}

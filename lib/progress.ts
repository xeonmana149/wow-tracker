import { LEGACY_CAP } from "./legacy";
import { PRIMARY_PROFESSIONS } from "./icons";
import { MAX_SKILL } from "./professions";

export const MAX_LEVEL = 60;

// A very rough rule of thumb (not an exact Forever formula) that "on-level"
// gear roughly tracks character level 1:1 - quest greens can lag behind by
// a little without it meaning anything, but a piece sitting this far below
// your current level is usually genuinely outdated rather than just a
// recent quest reward you haven't replaced yet. Tune this (and how many
// pieces get suggested) here if it's flagging too eagerly or not enough.
const GEAR_LEVEL_GAP_THRESHOLD = 15;
const MAX_GEAR_TODOS = 2;

// Everything the progress bars and to-do list need to know about a character
export type ProgressInput = {
  level: number;
  off_spec?: string | null;
  active_spec?: number | null;
  character_professions?: { profession: string; skill: number }[];
  character_talents?: { slot?: number; rank: number }[];
  character_legacy?: { rank: number }[];
  // Raw equipped_gear rows, exactly as a query that joins the shared items
  // table for its level (`items(level)`) returns them - equipped_gear
  // itself doesn't store item level. `items` comes back as an object or a
  // one-element array depending on how Supabase infers the to-one
  // relationship; gearItemLevel() below normalizes either shape rather than
  // pushing that onto every caller. A row with no item_id link yet, or
  // whose item has no known level, simply can't be compared either way and
  // is skipped further down.
  equipped_gear?: {
    slot: string;
    items?: { level: number | null } | { level: number | null }[] | null;
  }[];
};

function gearItemLevel(g: { items?: { level: number | null } | { level: number | null }[] | null }) {
  const item = Array.isArray(g.items) ? g.items[0] : g.items;
  return item?.level ?? null;
}

export type Bar = { key: string; label: string; value: number; max: number; text: string };

export type Todo = {
  kind: "talent" | "legacy" | "profession" | "level" | "setup" | "gear";
  text: string;
  // Current/target numbers for todos that represent progress toward
  // something (skill level, character level, points spent) - lets the UI
  // draw a bar next to items that have one, and skip it for plain ones
  // like "Learn a profession" that don't have a natural number. Optional
  // so nothing that reads a Todo without knowing about these breaks.
  value?: number;
  max?: number;
};

function plural(n: number, one: string, many: string) {
  return n === 1 ? one : many;
}

// Talent points available at a given level - one per level starting at
// level 10 (no points before that), so the level cap of 60 works out to
// 51. Computed directly here rather than through lib/talents.ts, since
// that file wasn't available to check in this session.
function talentBudgetForLevel(level: number) {
  return Math.max(0, level - 9);
}

// Talent points spent in the spec the character is playing
function talentsSpent(c: ProgressInput) {
  const slot = c.off_spec && c.active_spec === 2 ? 2 : 1;
  return (c.character_talents ?? [])
    .filter((r) => (r.slot ?? 1) === slot)
    .reduce((n, r) => n + r.rank, 0);
}

function legacySpent(c: ProgressInput) {
  return (c.character_legacy ?? []).reduce((n, r) => n + r.rank, 0);
}

// Skill in the two best primary professions, out of 600
function primarySkill(c: ProgressInput) {
  return (c.character_professions ?? [])
    .filter((p) => PRIMARY_PROFESSIONS.includes(p.profession))
    .map((p) => p.skill)
    .sort((a, b) => b - a)
    .slice(0, 2)
    .reduce((n, s) => n + s, 0);
}

// Talent points aren't shown as a progress bar anywhere - a bar maxing out
// at a different number for every level (51 at level 60, but much less
// earlier on) doesn't tell you or anyone else anything useful to look at.
// The only thing worth surfacing is when points are sitting unspent, which
// whatsNext() below already does as a to-do item.
export function characterBars(c: ProgressInput): Bar[] {
  const legacy = legacySpent(c);
  const skill = primarySkill(c);

  return [
    { key: "level", label: "Level", value: c.level, max: MAX_LEVEL, text: `${c.level} / ${MAX_LEVEL}` },
    { key: "legacy", label: "Legacy", value: legacy, max: LEGACY_CAP, text: `${legacy} / ${LEGACY_CAP}` },
    {
      key: "professions",
      label: "Professions",
      value: skill,
      max: 2 * MAX_SKILL,
      text: `${skill} / ${2 * MAX_SKILL}`,
    },
  ];
}

// A to-do list worked out from what's already been entered. `earned` is the
// account's Legacy points.
export function whatsNext(c: ProgressInput, earned: number): Todo[] {
  const todos: Todo[] = [];

  const talentBudget = talentBudgetForLevel(c.level);
  const spentTalents = talentsSpent(c);
  const talentsLeft = talentBudget - spentTalents;
  if (talentsLeft > 0) {
    todos.push({
      kind: "talent",
      text: `${talentsLeft} unspent talent ${plural(talentsLeft, "point", "points")}`,
      value: spentTalents,
      max: talentBudget,
    });
  }

  const legacyTarget = Math.min(LEGACY_CAP, earned);
  const spentLegacy = legacySpent(c);
  const legacyLeft = legacyTarget - spentLegacy;
  if (legacyLeft > 0) {
    todos.push({
      kind: "legacy",
      text: `${legacyLeft} unspent Legacy ${plural(legacyLeft, "point", "points")}`,
      value: spentLegacy,
      max: legacyTarget,
    });
  }

  const profs = c.character_professions ?? [];
  if (c.level >= 5 && !profs.some((p) => PRIMARY_PROFESSIONS.includes(p.profession))) {
    todos.push({ kind: "profession", text: "Learn a profession" });
  }
  const unfinished = profs
    .filter((p) => p.skill < MAX_SKILL)
    .sort(
      (a, b) =>
        Number(PRIMARY_PROFESSIONS.includes(b.profession)) -
          Number(PRIMARY_PROFESSIONS.includes(a.profession)) || b.skill - a.skill
    );
  for (const p of unfinished.slice(0, 3)) {
    todos.push({
      kind: "profession",
      text: `${p.profession} ${p.skill} → ${MAX_SKILL}`,
      value: p.skill,
      max: MAX_SKILL,
    });
  }

  // The weakest equipped piece(s), if any are sitting well below current
  // character level - see GEAR_LEVEL_GAP_THRESHOLD above. Items with no
  // known level (no item_id link yet, or the shared items table hasn't got
  // a level for that id) can't be judged either way, so they're skipped
  // rather than assumed fine or assumed weak.
  const gearGaps = (c.equipped_gear ?? [])
    .map((g) => ({ slot: g.slot, item_level: gearItemLevel(g) }))
    .filter((g): g is { slot: string; item_level: number } => typeof g.item_level === "number")
    .map((g) => ({ ...g, gap: c.level - g.item_level }))
    .filter((g) => g.gap >= GEAR_LEVEL_GAP_THRESHOLD)
    .sort((a, b) => b.gap - a.gap);

  for (const g of gearGaps.slice(0, MAX_GEAR_TODOS)) {
    todos.push({
      kind: "gear",
      text: `${g.slot} is item level ${g.item_level} - well behind your character level (${c.level}), recommended to upgrade`,
      value: g.item_level,
      max: c.level,
    });
  }

  if (c.level < MAX_LEVEL) {
    todos.push({
      kind: "level",
      text: `Reach level ${MAX_LEVEL} (${MAX_LEVEL - c.level} to go)`,
      value: c.level,
      max: MAX_LEVEL,
    });
  }

  return todos;
}

// Primary professions that none of these characters have
export function missingProfessions(characters: { character_professions?: { profession: string }[] }[]) {
  const have = new Set(
    characters.flatMap((c) => (c.character_professions ?? []).map((p) => p.profession))
  );
  return PRIMARY_PROFESSIONS.filter((p) => !have.has(p));
}
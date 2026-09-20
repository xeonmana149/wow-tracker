import { pointsForLevel } from "./talents";
import { LEGACY_CAP } from "./legacy";
import { PRIMARY_PROFESSIONS } from "./icons";
import { MAX_SKILL } from "./professions";

export const MAX_LEVEL = 60;

// Everything the progress bars and to-do list need to know about a character
export type ProgressInput = {
  level: number;
  off_spec?: string | null;
  active_spec?: number | null;
  character_professions?: { profession: string; skill: number }[];
  character_talents?: { slot?: number; rank: number }[];
  character_legacy?: { rank: number }[];
};

export type Bar = { key: string; label: string; value: number; max: number; text: string };

export type Todo = {
  kind: "talent" | "legacy" | "profession" | "level" | "setup";
  text: string;
};

function plural(n: number, one: string, many: string) {
  return n === 1 ? one : many;
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

export function characterBars(c: ProgressInput): Bar[] {
  const budget = pointsForLevel(c.level);
  const talents = talentsSpent(c);
  const legacy = legacySpent(c);
  const skill = primarySkill(c);

  return [
    { key: "level", label: "Level", value: c.level, max: MAX_LEVEL, text: `${c.level} / ${MAX_LEVEL}` },
    {
      key: "talents",
      label: "Talents",
      value: talents,
      max: budget > 0 ? budget : 1,
      text: budget > 0 ? `${talents} / ${budget}` : "from level 10",
    },
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

  const talentsLeft = pointsForLevel(c.level) - talentsSpent(c);
  if (talentsLeft > 0) {
    todos.push({
      kind: "talent",
      text: `${talentsLeft} unspent talent ${plural(talentsLeft, "point", "points")}`,
    });
  }

  const legacyLeft = Math.min(LEGACY_CAP, earned) - legacySpent(c);
  if (legacyLeft > 0) {
    todos.push({
      kind: "legacy",
      text: `${legacyLeft} unspent Legacy ${plural(legacyLeft, "point", "points")}`,
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
    todos.push({ kind: "profession", text: `${p.profession} ${p.skill} → ${MAX_SKILL}` });
  }

  if (c.level < MAX_LEVEL) {
    todos.push({ kind: "level", text: `Reach level ${MAX_LEVEL} (${MAX_LEVEL - c.level} to go)` });
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

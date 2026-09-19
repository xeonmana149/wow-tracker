export type Talent = {
  name: string;
  max: number;
  row: number;
  col: number;
  passive: boolean;
  icon: string;
  desc: Record<string, string>;
  complete: boolean;
  req: string | null;
  reqText: string | null;
  cost: string | null;
  scaleIdx: number[];
  isNew: boolean;
};

export type Tree = { name: string; icon: string; talents: Talent[] };
export type ClassData = { class: string; generated: string; trees: Tree[] };

// How many ranks are learned in each talent, keyed by "Tree|Talent"
export type Ranks = Record<string, number>;

export type Check = { ok: true } | { ok: false; reason: string };

export const MAX_POINTS = 51;
export const ROW_GATE = 5; // every row down needs 5 more points spent in the tree

// One point per level from level 10, so 51 at level 60
export function pointsForLevel(level: number) {
  return Math.max(0, Math.min(MAX_POINTS, level - 9));
}

export function keyOf(tree: Tree | string, talent: Talent | string) {
  const t = typeof tree === "string" ? tree : tree.name;
  const n = typeof talent === "string" ? talent : talent.name;
  return `${t}|${n}`;
}

export function rankOf(ranks: Ranks, tree: Tree, talent: Talent) {
  return ranks[keyOf(tree, talent)] ?? 0;
}

// Points spent in a tree. With beforeRow, only counts rows above that row.
export function treePoints(tree: Tree, ranks: Ranks, beforeRow = Infinity) {
  let sum = 0;
  for (const t of tree.talents) {
    if (t.row < beforeRow) sum += rankOf(ranks, tree, t);
  }
  return sum;
}

export function totalPoints(data: ClassData, ranks: Ranks) {
  return data.trees.reduce((sum, tree) => sum + treePoints(tree, ranks), 0);
}

// Are this talent's row and prerequisite unlocked? (Ignores max rank and spare points.)
export function availability(tree: Tree, talent: Talent, ranks: Ranks): Check {
  const need = (talent.row - 1) * ROW_GATE;
  const have = treePoints(tree, ranks, talent.row);
  if (have < need) {
    return {
      ok: false,
      reason: `Needs ${need} points in ${tree.name} talents above this row (you have ${have}).`,
    };
  }

  if (talent.req) {
    const reqTalent = tree.talents.find((t) => t.name === talent.req);
    if (reqTalent && rankOf(ranks, tree, reqTalent) < reqTalent.max) {
      return {
        ok: false,
        reason: `Needs ${reqTalent.name} at max rank (${reqTalent.max}).`,
      };
    }
  }

  return { ok: true };
}

export function canLearn(tree: Tree, talent: Talent, ranks: Ranks, pointsLeft: number): Check {
  if (rankOf(ranks, tree, talent) >= talent.max) {
    return { ok: false, reason: "Already at max rank." };
  }
  const open = availability(tree, talent, ranks);
  if (!open.ok) return open;
  if (pointsLeft <= 0) return { ok: false, reason: "No unspent talent points." };
  return { ok: true };
}

// Is every learned talent in this tree still allowed to be learned?
function isTreeValid(tree: Tree, ranks: Ranks) {
  for (const t of tree.talents) {
    if (rankOf(ranks, tree, t) > 0 && !availability(tree, t, ranks).ok) return false;
  }
  return true;
}

// `locked` holds points that can't be taken back (the applied build)
export function canUnlearn(tree: Tree, talent: Talent, ranks: Ranks, locked: Ranks): Check {
  const rank = rankOf(ranks, tree, talent);
  const floor = locked[keyOf(tree, talent)] ?? 0;

  if (rank <= 0) return { ok: false, reason: "No points to remove." };
  if (rank <= floor) {
    return { ok: false, reason: "Applied points can't be removed. Use Respec to start over." };
  }

  const test = { ...ranks, [keyOf(tree, talent)]: rank - 1 };
  if (!isTreeValid(tree, test)) {
    return { ok: false, reason: "Other talents depend on this point. Remove those first." };
  }
  return { ok: true };
}

// The text for a rank. If that rank isn't recorded, fall back to the nearest one that is.
export function descFor(talent: Talent, rank: number) {
  const exact = talent.desc[String(rank)];
  if (exact) return { text: exact, exact: true, shownRank: rank };

  const known = Object.keys(talent.desc)
    .map(Number)
    .sort((a, b) => a - b);
  if (known.length === 0) return null;

  const pick = [...known].reverse().find((k) => k <= rank) ?? known[0];
  return { text: talent.desc[String(pick)], exact: false, shownRank: pick };
}

// Turn saved rows into ranks, ignoring talents that no longer exist in the data
export function cleanRanks(
  data: ClassData,
  rows: { tree: string; talent: string; rank: number }[]
): Ranks {
  const out: Ranks = {};
  for (const r of rows) {
    const tree = data.trees.find((t) => t.name === r.tree);
    const talent = tree?.talents.find((t) => t.name === r.talent);
    if (tree && talent) {
      out[keyOf(tree, talent)] = Math.min(talent.max, Math.max(0, r.rank));
    }
  }
  return out;
}
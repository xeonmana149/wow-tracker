import type { Check } from "./talents";
import type { LegacyPerkData, LegacyTreeData } from "./gameData";

// Legacy points are account-wide. Each character can spend up to this many at launch.
export const LEGACY_CAP = 16;

// The trees, perks, layout (row/col), rank text and icons come from the WoW
// Forever client's own data (lib/gameData.ts, loaded with loadLegacyData()
// in lib/server-data.ts) - nothing here is hand-kept any more.
export type LegacyPerk = LegacyPerkData;
export type LegacyTree = LegacyTreeData;

export type LegacyRanks = Record<string, number>;

export function legacyKey(tree: LegacyTree | string, perk: LegacyPerk | string) {
  const t = typeof tree === "string" ? tree : tree.name;
  const p = typeof perk === "string" ? perk : perk.name;
  return `${t}|${p}`;
}

export function legacyRank(ranks: LegacyRanks, tree: LegacyTree, perk: LegacyPerk) {
  return ranks[legacyKey(tree, perk)] ?? 0;
}

export function legacyTreePoints(tree: LegacyTree, ranks: LegacyRanks) {
  return tree.perks.reduce((sum, p) => sum + (p.placeholder ? 0 : legacyRank(ranks, tree, p)), 0);
}

export function legacyTotal(trees: LegacyTree[], ranks: LegacyRanks) {
  return trees.reduce((sum, t) => sum + legacyTreePoints(t, ranks), 0);
}

// Are this perk's point requirement and named requirement met? (Ignores max rank and spare points.)
export function legacyAvailability(tree: LegacyTree, perk: LegacyPerk, ranks: LegacyRanks): Check {
  // The point requirement counts the other perks in the tree, not this one
  const others = legacyTreePoints(tree, ranks) - legacyRank(ranks, tree, perk);
  if (perk.gate > 0 && others < perk.gate) {
    return {
      ok: false,
      reason: `Needs ${perk.gate} points in ${tree.name} from other perks (you have ${others}).`,
    };
  }

  if (perk.req) {
    const reqPerk = tree.perks.find((p) => p.name === perk.req);
    if (reqPerk && legacyRank(ranks, tree, reqPerk) < reqPerk.max) {
      return { ok: false, reason: `Needs ${reqPerk.name} at max rank (${reqPerk.max}).` };
    }
  }

  return { ok: true };
}

export function canLearnPerk(
  tree: LegacyTree,
  perk: LegacyPerk,
  ranks: LegacyRanks,
  pointsLeft: number
): Check {
  if (perk.placeholder) return { ok: false, reason: "Not in the game yet." };
  if (legacyRank(ranks, tree, perk) >= perk.max) return { ok: false, reason: "Already at max rank." };
  const open = legacyAvailability(tree, perk, ranks);
  if (!open.ok) return open;
  if (pointsLeft <= 0) return { ok: false, reason: "No unspent legacy points." };
  return { ok: true };
}

function isTreeValid(tree: LegacyTree, ranks: LegacyRanks) {
  for (const p of tree.perks) {
    if (legacyRank(ranks, tree, p) > 0 && !legacyAvailability(tree, p, ranks).ok) return false;
  }
  return true;
}

// `locked` holds points that can't be taken back (the applied build)
export function canUnlearnPerk(
  tree: LegacyTree,
  perk: LegacyPerk,
  ranks: LegacyRanks,
  locked: LegacyRanks
): Check {
  const rank = legacyRank(ranks, tree, perk);
  const floor = locked[legacyKey(tree, perk)] ?? 0;

  if (rank <= 0) return { ok: false, reason: "No points to remove." };
  if (rank <= floor) {
    return { ok: false, reason: "Applied points can't be removed. Use Respec to start over." };
  }

  const test = { ...ranks, [legacyKey(tree, perk)]: rank - 1 };
  if (!isTreeValid(tree, test)) {
    return { ok: false, reason: "Other perks depend on this point. Remove those first." };
  }
  return { ok: true };
}

// Turn saved rows into ranks, ignoring perks that aren't on the board any more
// and clamping ranks above a perk's (possibly lowered) max
export function cleanLegacy(
  trees: LegacyTree[],
  rows: { tree: string; perk: string; rank: number }[]
): LegacyRanks {
  const out: LegacyRanks = {};
  for (const r of rows) {
    const tree = trees.find((t) => t.name === r.tree);
    const perk = tree?.perks.find((p) => p.name === r.perk && !p.placeholder);
    if (tree && perk) out[legacyKey(tree, perk)] = Math.min(perk.max, Math.max(0, r.rank));
  }
  return out;
}

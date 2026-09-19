import type { Check } from "./talents";

// Legacy points are account-wide. Each character can spend up to this many at launch.
export const LEGACY_CAP = 16;

export type LegacyPerk = {
  name: string;
  max: number;
  gate: number; // points needed in this tree from OTHER perks. The row is gate / 5.
  req?: string; // a perk in this tree that must be at max rank first
  col: number; // column on the board, 1 to 4
  byRank: string[]; // the effect at each rank
};

export type LegacyTree = { name: string; hidden: number; perks: LegacyPerk[] };

// Requirements and per-rank values from the WoW Forever beta (17 Sept snapshot),
// as listed on wowforevertalent.com/legacy. The columns are my own arrangement.
export const LEGACY_TREES: LegacyTree[] = [
  {
    name: "Adventure",
    hidden: 2,
    perks: [
      { name: "Well Rested", max: 5, gate: 0, col: 1, byRank: ["4%", "8%", "12%", "16%", "20%"] },
      { name: "Thrill of Adventure", max: 5, gate: 0, col: 3, byRank: ["1%", "2%", "3%", "4%", "5%"] },
      {
        name: "Talented",
        max: 5,
        gate: 5,
        req: "Well Rested",
        col: 1,
        byRank: ["Level 9", "Level 8", "Level 7", "Level 6", "Level 5"],
      },
      { name: "High Alert", max: 2, gate: 5, col: 2, byRank: ["+1 level", "+2 levels"] },
      { name: "Field Guide", max: 3, gate: 5, col: 3, byRank: ["8%", "17%", "25%"] },
      { name: "Field Medicine", max: 2, gate: 5, col: 4, byRank: ["5 sec", "10 sec"] },
      { name: "Frequent Flier", max: 1, gate: 10, req: "Field Guide", col: 3, byRank: [] },
    ],
  },
  {
    name: "Resourcefulness",
    hidden: 2,
    perks: [
      { name: "Gourmand", max: 3, gate: 0, col: 1, byRank: ["33%", "67%", "100%"] },
      { name: "Reinforce", max: 5, gate: 0, col: 2, byRank: ["8%", "16%", "24%", "32%", "40%"] },
      {
        name: "The Quick and the Dead",
        max: 2,
        gate: 0,
        col: 3,
        byRank: ["5% for 1 min", "10% for 2 min"],
      },
      { name: "Permanence", max: 2, gate: 5, req: "Gourmand", col: 1, byRank: ["50%", "100%"] },
      { name: "For Great Honor", max: 5, gate: 5, col: 2, byRank: ["2%", "4%", "6%", "8%", "10%"] },
      { name: "Diplomat", max: 5, gate: 5, col: 4, byRank: ["2%", "4%", "6%", "8%", "10%"] },
      { name: "Reagent Economy", max: 1, gate: 10, req: "The Quick and the Dead", col: 3, byRank: [] },
    ],
  },
  {
    name: "Professions",
    hidden: 2,
    perks: [
      { name: "Working Overtime", max: 5, gate: 0, col: 1, byRank: ["4%", "8%", "12%", "16%", "20%"] },
      { name: "Bountiful Harvest", max: 5, gate: 0, col: 3, byRank: ["20%", "40%", "60%", "80%", "100%"] },
      { name: "Master Chef", max: 5, gate: 5, col: 1, byRank: ["10%", "20%", "30%", "40%", "50%"] },
      { name: "Bartering", max: 2, gate: 5, col: 2, byRank: ["5%", "10%"] },
      {
        name: "Performance Bonus",
        max: 3,
        gate: 5,
        req: "Bountiful Harvest",
        col: 3,
        byRank: ["5% chance", "10% chance", "15% chance"],
      },
      { name: "Luremaster", max: 2, gate: 5, col: 4, byRank: ["25%", "50%"] },
      { name: "Dedicated Study", max: 1, gate: 10, req: "Bartering", col: 2, byRank: [] },
    ],
  },
];

// Ranks spent in each perk, keyed "Tree|Perk"
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
  return tree.perks.reduce((sum, p) => sum + legacyRank(ranks, tree, p), 0);
}

export function legacyTotal(ranks: LegacyRanks) {
  return LEGACY_TREES.reduce((sum, t) => sum + legacyTreePoints(t, ranks), 0);
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

// Turn saved rows into ranks, ignoring perks that aren't on the board
export function cleanLegacy(rows: { tree: string; perk: string; rank: number }[]): LegacyRanks {
  const out: LegacyRanks = {};
  for (const r of rows) {
    const tree = LEGACY_TREES.find((t) => t.name === r.tree);
    const perk = tree?.perks.find((p) => p.name === r.perk);
    if (tree && perk) out[legacyKey(tree, perk)] = Math.min(perk.max, Math.max(0, r.rank));
  }
  return out;
}

// Used when the downloaded data doesn't include a perk. Bartering was added after the
// snapshot the download comes from.
export const LEGACY_FALLBACK_DESC: Record<string, string> = {
  "Well Rested": "Rested experience builds up 4% faster and its cap is 4% higher, per rank.",
  "Thrill of Adventure":
    "Killing blows on non-trivial enemies restore 1% of your max health and mana over 10 sec, per rank. Doesn't work in dungeons, raids or battlegrounds.",
  Talented:
    "Your first class talent point arrives at level 9 instead of 10, and each further rank moves it one level earlier, down to level 5. The 51-point cap doesn't change.",
  "High Alert":
    "Detects stealthed enemies as if your level were 1 higher per rank. Doesn't work in battlegrounds.",
  "Field Guide": "Cuts the cooldown on adding camp features by about 8% per rank.",
  "Field Medicine":
    "Shortens the Recently Bandaged effect by 5 sec per rank. Doesn't work in dungeons, raids or battlegrounds.",
  "Frequent Flier": "Flight paths cost 50% less and your flight mount flies 20% faster.",
  Gourmand: "Food buffs last 33% longer per rank.",
  Reinforce: "You lose 8% less durability when you die, per rank.",
  "The Quick and the Dead":
    "You move faster while dead, and after being resurrected your helpful spells and abilities cost nothing until you enter combat, for up to 1 min at rank 1 and 2 min at rank 2.",
  Permanence:
    "Your long-lasting group buffs last 50% longer per rank, and so do the benefits of resting at a camp.",
  "For Great Honor": "Honor gains are 2% higher per rank.",
  Diplomat: "Reputation gains are 2% higher per rank.",
  "Reagent Economy":
    "Your class abilities no longer need vendor reagents, and tier 1 camp features cost no reagents to craft.",
  "Working Overtime": "You're 4% more likely per rank to gain a skill-up from any tradeskill.",
  "Bountiful Harvest": "You find 20% more scarce materials per rank from Mining, Herbalism and Skinning.",
  "Master Chef": "Cooking recipes have a 10% chance per rank to make an extra result.",
  Bartering: "Vendors charge 5% less gold for their items per rank.",
  "Performance Bonus":
    "A 5% chance per rank of doubled Merchant Favor when you hand in a crate at the Azeroth Commerce Authority or Durotar Supply and Logistics.",
  Luremaster: "While fishing with a lure, you have a 25% chance per rank to catch an extra fish.",
  "Dedicated Study":
    "25 sec cast, 23 hour cooldown. Raises your lowest primary or secondary tradeskill by 1. If they're all at 300, you get 2 to 4 of a random Elemental Essence instead.",
};

// Pictures for perks the downloaded data doesn't have
export const LEGACY_FALLBACK_ICON: Record<string, string> = {
  Bartering: "inv_misc_coin_06",
};

// Pictures for each perk and tree, as used on wowforevertalent.com/legacy
export const LEGACY_PERK_ICONS: Record<string, string> = {
  "High Alert": "spell_shadow_detectlesserinvisibility",
  "Well Rested": "spell_nature_sleep",
  Talented: "ability_marksmanship",
  "Thrill of Adventure": "ability_hunter_huntervswild",
  "Field Guide": "inv_fishingchair",
  "Frequent Flier": "achievement_guild_ridelikethewind",
  "Field Medicine": "inv_misc_bandage_05",
  "For Great Honor": "achievement_bg_winwsg",
  Gourmand: "inv_misc_food_64",
  Permanence: "spell_misc_emotionhappy",
  "The Quick and the Dead": "spell_shadow_deadofnight",
  "Reagent Economy": "inv_misc_candle_02",
  Reinforce: "inv_misc_armorkit_17",
  Diplomat: "inv_scroll_03",
  "Master Chef": "achievement_profession_chefhat",
  "Working Overtime": "inv_misc_pocketwatch_03",
  Bartering: "inv_misc_coin_06",
  "Dedicated Study": "inv_misc_book_08",
  "Bountiful Harvest": "inv_misc_bag_18",
  "Performance Bonus": "racial_dwarf_findtreasure",
  Luremaster: "inv_misc_basket_04",
};

export const LEGACY_TREE_ICONS: Record<string, string> = {
  Adventure: "inv_misc_map_01",
  Resourcefulness: "inv_misc_coin_01",
  Professions: "trade_engineering",
};
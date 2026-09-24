// Approximate vanilla-era (WoW Forever is built on the classic1x dataset)
// class weapon/armor proficiency rules, used to flag "your selected
// character can't use this" in the Items page - the same way the in-game
// tooltip and the auction house turn a requirement red when you don't meet
// it. This is deliberately a simplification: real vanilla has a handful of
// exceptions (e.g. Hunters/Shaman only gaining Mail proficiency at level 40,
// a couple of class/weapon quirks that changed across patches) that aren't
// worth modeling for a small friend-group tracker. Treat this as "close
// enough to catch the obvious mismatches", not a rules engine.

export const PROFESSION_NAMES = [
  "Alchemy",
  "Blacksmithing",
  "Enchanting",
  "Engineering",
  "Herbalism",
  "Leatherworking",
  "Mining",
  "Skinning",
  "Tailoring",
  "Cooking",
  "First Aid",
  "Fishing",
] as const;

// A tooltip line for a recipe/plan/pattern item that requires a profession
// looks like "Requires Alchemy (275)" - this is the only place that
// information shows up (there's no structured column for it), so it's
// parsed straight out of a real scanned tooltip, same pattern as
// extractSlotAndSubclass in lib/tooltip.tsx.
const PROFESSION_REQ_RE = new RegExp(
  `^Requires (${PROFESSION_NAMES.join("|")}) \\((\\d+)\\)$`,
  "i"
);

export function extractProfessionRequirement(
  tooltip: string[] | null | undefined
): { profession: string; skill: number } | null {
  if (!tooltip) return null;
  for (const line of tooltip) {
    const m = PROFESSION_REQ_RE.exec(line.trim());
    if (m) return { profession: m[1], skill: Number(m[2]) };
  }
  return null;
}

const WEAPON_TOKENS = [
  "sword",
  "axe",
  "mace",
  "dagger",
  "fist",
  "polearm",
  "staff",
  "bow",
  "gun",
  "crossbow",
  "wand",
  "thrown",
  "fishing",
] as const;

const ARMOR_ORDER = ["cloth", "leather", "mail", "plate"] as const;

// Turns whatever a tooltip's second column or Blizzard's item_subclass says
// ("Sword", "Two-Handed Swords", "Leather", "Fishing Pole", ...) into one of
// the fixed tokens above, by substring match - handles both the singular
// wording a real tooltip uses and the pluralized wording Blizzard's API
// uses, without needing an exhaustive lookup of every phrasing.
function normalizeToken(subclass: string): string | null {
  const s = subclass.toLowerCase();
  if (s.includes("shield")) return "shield";
  for (const t of [...WEAPON_TOKENS, ...ARMOR_ORDER]) {
    if (s.includes(t)) return t;
  }
  return null;
}

const CLASS_WEAPON_TOKENS: Record<string, string[]> = {
  warrior: ["sword", "axe", "mace", "dagger", "fist", "polearm", "staff", "bow", "gun", "crossbow", "thrown", "fishing"],
  paladin: ["sword", "axe", "mace", "polearm", "fishing"],
  hunter: ["sword", "axe", "dagger", "fist", "polearm", "staff", "bow", "gun", "crossbow", "thrown", "fishing"],
  rogue: ["sword", "axe", "mace", "dagger", "fist", "bow", "gun", "crossbow", "thrown", "fishing"],
  priest: ["mace", "dagger", "staff", "wand", "fishing"],
  shaman: ["mace", "dagger", "fist", "staff", "fishing"],
  mage: ["sword", "dagger", "staff", "wand", "fishing"],
  warlock: ["sword", "dagger", "staff", "wand", "fishing"],
  druid: ["mace", "dagger", "staff", "fist", "fishing"],
};

const CLASS_MAX_ARMOR: Record<string, (typeof ARMOR_ORDER)[number]> = {
  warrior: "plate",
  paladin: "plate",
  hunter: "mail",
  rogue: "leather",
  shaman: "mail",
  priest: "cloth",
  mage: "cloth",
  warlock: "cloth",
  druid: "leather",
};

const CLASS_CAN_SHIELD: Record<string, boolean> = {
  warrior: true,
  paladin: true,
  shaman: true,
  hunter: false,
  rogue: false,
  priest: false,
  mage: false,
  warlock: false,
  druid: false,
};

// True unless the class definitely can't use this weapon/armor/shield type.
// Anything not recognized (a subclass string that isn't a weapon/armor/
// shield token - jewelry, a cloak, a bag, a quiver) is treated as fine for
// every class, since there's no meaningful class restriction to check.
export function classCanUseSubclass(className: string | null | undefined, subclass: string | null | undefined): boolean {
  if (!className || !subclass) return true;
  const cls = className.toLowerCase();
  const token = normalizeToken(subclass);
  if (!token) return true;
  if (token === "shield") return CLASS_CAN_SHIELD[cls] ?? true;
  if ((ARMOR_ORDER as readonly string[]).includes(token)) {
    const max = CLASS_MAX_ARMOR[cls];
    if (!max) return true;
    return ARMOR_ORDER.indexOf(token as (typeof ARMOR_ORDER)[number]) <= ARMOR_ORDER.indexOf(max);
  }
  const allowed = CLASS_WEAPON_TOKENS[cls];
  if (!allowed) return true;
  return allowed.includes(token);
}

export type CharacterProfessionSummary = { profession: string; skill: number };

export type CharacterSummary = {
  id: string;
  name: string;
  class: string;
  level: number;
  professions: CharacterProfessionSummary[];
};

export function characterMeetsProfession(
  character: CharacterSummary,
  requirement: { profession: string; skill: number } | null
): boolean {
  if (!requirement) return true;
  const p = character.professions.find(
    (p) => p.profession.toLowerCase() === requirement.profession.toLowerCase()
  );
  return !!p && p.skill >= requirement.skill;
}
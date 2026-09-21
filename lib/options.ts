export type Spec = { name: string; role: "Tank" | "Healer" | "DPS" };

// Each class and its specs. The role is just the default when you pick the spec.
export const SPECS: Record<string, Spec[]> = {
  Druid: [
    { name: "Balance", role: "DPS" },
    { name: "Feral", role: "DPS" },
    { name: "Restoration", role: "Healer" },
  ],
  Hunter: [
    { name: "Beast Mastery", role: "DPS" },
    { name: "Marksmanship", role: "DPS" },
    { name: "Survival", role: "DPS" },
  ],
  Mage: [
    { name: "Arcane", role: "DPS" },
    { name: "Fire", role: "DPS" },
    { name: "Frost", role: "DPS" },
  ],
  Paladin: [
    { name: "Holy", role: "Healer" },
    { name: "Protection", role: "Tank" },
    { name: "Retribution", role: "DPS" },
  ],
  Priest: [
    { name: "Discipline", role: "Healer" },
    { name: "Holy", role: "Healer" },
    { name: "Shadow", role: "DPS" },
  ],
  Rogue: [
    { name: "Assassination", role: "DPS" },
    { name: "Combat", role: "DPS" },
    { name: "Subtlety", role: "DPS" },
  ],
  Shaman: [
    { name: "Elemental", role: "DPS" },
    { name: "Enhancement", role: "DPS" },
    { name: "Restoration", role: "Healer" },
  ],
  Warlock: [
    { name: "Affliction", role: "DPS" },
    { name: "Demonology", role: "DPS" },
    { name: "Destruction", role: "DPS" },
  ],
  Warrior: [
    { name: "Arms", role: "DPS" },
    { name: "Fury", role: "DPS" },
    { name: "Protection", role: "Tank" },
  ],
};

export const CLASSES = Object.keys(SPECS);

// Each race and its faction. Skyborne is a separate race for each faction -
// "High Order Skyborne" on the Alliance side, "Windshaper Skyborne" on the
// Horde side - these are the actual in-lore race names the server uses
// (matching what UnitRace() reports in-game), not generic faction labels.
export const RACE_FACTION: Record<string, "Alliance" | "Horde"> = {
  Human: "Alliance",
  Dwarf: "Alliance",
  "Night Elf": "Alliance",
  Gnome: "Alliance",
  "High Order Skyborne": "Alliance",
  Orc: "Horde",
  Undead: "Horde",
  Tauren: "Horde",
  Troll: "Horde",
  "Windshaper Skyborne": "Horde",
};

export const RACES = Object.keys(RACE_FACTION);
export const CHARACTER_TYPES = ["Main", "Alt", "Gatherer", "PvPer"];
export const ROLES = ["Tank", "Healer", "DPS"];
export const RULESETS = ["PVP", "PVE", "RPPVE", "HARDCORE"];

export const FACTIONS = ["Alliance", "Horde"];

// Which classes each race can be, from the WoW Forever race and class guide.
export const RACE_CLASSES: Record<string, string[]> = {
  Human: ["Hunter", "Mage", "Paladin", "Priest", "Rogue", "Warlock", "Warrior"],
  Dwarf: ["Hunter", "Paladin", "Priest", "Rogue", "Shaman", "Warrior"],
  "Night Elf": ["Druid", "Hunter", "Priest", "Rogue", "Warrior"],
  Gnome: ["Mage", "Priest", "Rogue", "Warlock", "Warrior"],
  "High Order Skyborne": ["Druid", "Hunter", "Mage", "Rogue", "Warrior"],
  Orc: ["Hunter", "Mage", "Rogue", "Shaman", "Warlock", "Warrior"],
  Undead: ["Mage", "Paladin", "Priest", "Rogue", "Warlock", "Warrior"],
  Tauren: ["Druid", "Hunter", "Shaman", "Warrior"],
  Troll: ["Hunter", "Mage", "Priest", "Rogue", "Shaman", "Warlock", "Warrior"],
  "Windshaper Skyborne": ["Druid", "Hunter", "Rogue", "Shaman", "Warrior"],
};
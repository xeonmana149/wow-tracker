import iconNames from "./data/icon-names.json";

// Turns a raw Blizzard icon file ID (from GetInventoryItemTexture in the
// addon) into a real image URL, using a bundled fileID -> icon name lookup
// (the same kind of data community WoW tools use). Returns null if the ID
// isn't in the table - the UI falls back to the text tile in that case,
// never breaks.
export function iconUrlForFileId(fileId: number | string | null | undefined): string | null {
  if (fileId === null || fileId === undefined) return null;
  const name = (iconNames as Record<string, string>)[String(fileId)];
  if (!name) return null;
  return `https://wow.zamimg.com/images/wow/icons/large/${name}.jpg`;
}


// Picture helpers. Safe to use in any component.

export function iconUrl(name: string) {
  return `/talent-icons/${name}.jpg`;
}

// Lowercase and strip punctuation, so "Eureka!" and "eureka" match
export function norm(s: string) {
  return s.toLowerCase().replace(/[^a-z0-9]/g, "");
}

export const RACE_ICONS: Record<string, string> = {
  Human: "race_human_male",
  Dwarf: "race_dwarf_male",
  "Night Elf": "race_nightelf_male",
  Gnome: "race_gnome_male",
  "Alliance Skyborne": "race_skyborne",
  Orc: "race_orc_male",
  Undead: "race_scourge_male",
  Tauren: "race_tauren_male",
  Troll: "race_troll_male",
  "Horde Skyborne": "race_skyborne",
};

export function classIcon(cls: string) {
  return "class_" + cls.toLowerCase();
}

export const PRIMARY_PROFESSIONS = [
  "Alchemy",
  "Blacksmithing",
  "Enchanting",
  "Engineering",
  "Herbalism",
  "Leatherworking",
  "Mining",
  "Skinning",
  "Tailoring",
];

export const PROFESSION_ICONS: Record<string, string> = {
  Alchemy: "trade_alchemy",
  Blacksmithing: "trade_blacksmithing",
  Enchanting: "trade_engraving",
  Engineering: "trade_engineering",
  Herbalism: "trade_herbalism",
  Leatherworking: "trade_leatherworking",
  Mining: "trade_mining",
  Skinning: "inv_misc_pelt_wolf_01",
  Tailoring: "trade_tailoring",
  Cooking: "inv_misc_food_15",
  "First Aid": "spell_holy_sealofsalvation",
  Fishing: "trade_fishing",
};
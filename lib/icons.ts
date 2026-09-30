import iconNames from "./data/icon-names.json";

// A handful of icon file IDs that are real Blizzard assets but aren't
// hosted on wow.zamimg.com's icon CDN at all (it appears to mirror an
// older/classic-era icon set, so some newer or WoW-Forever-specific file
// IDs are simply missing there no matter what name we look up). For these,
// we bypass icon-names.json + zamimg entirely and point straight at a CDN
// that does have the image.
//
// 409547 = "Explore Mount Hyjal" Legacy Challenge achievement icon
// (interface/icons/achievement_zone_mount hyjal.blp). Confirmed 2026-09-30
// that wow.zamimg.com/.../achievement_zone_mounthyjal.jpg,
// achievement_zone_hyjal.jpg, and achievement_zone_mount_hyjal.jpg all
// 404 - the icon just isn't there - but WoWDB's own CDN has it.
const ICON_URL_OVERRIDES: Record<string, string> = {
  "409547": "https://icons.wowdb.com/retail/large/achievement_zone_mount_hyjal.jpg",
};

// Turns a raw Blizzard icon file ID (from GetInventoryItemTexture in the
// addon) into a real image URL, using a bundled fileID -> icon name lookup
// (the same kind of data community WoW tools use). Returns null if the ID
// isn't in the table - the UI falls back to the text tile in that case,
// never breaks.
export function iconUrlForFileId(fileId: number | string | null | undefined): string | null {
  if (fileId === null || fileId === undefined) return null;
  const key = String(fileId);
  if (ICON_URL_OVERRIDES[key]) return ICON_URL_OVERRIDES[key];
  const name = (iconNames as Record<string, string>)[key];
  if (!name) return null;
  return `https://wow.zamimg.com/images/wow/icons/large/${name}.jpg`;
}

// Same live icon CDN as iconUrlForFileId, but for icons picked by name up
// front (achievement badges) rather than looked up from an addon-reported
// file ID. Used instead of the local /talent-icons/ folder because there
// are far more of these than are worth bundling - the CDN has essentially
// every icon in the game.
export function wowIconUrl(name: string) {
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
  "High Order Skyborne": "race_skyborne_alliance",
  Orc: "race_orc_male",
  Undead: "race_scourge_male",
  Tauren: "race_tauren_male",
  Troll: "race_troll_male",
  "Windshaper Skyborne": "race_skyborne_horde",
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
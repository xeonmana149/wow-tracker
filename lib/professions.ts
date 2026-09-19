export const MAX_SKILL = 300;
export const SECONDARY_PROFESSIONS = ["Cooking", "First Aid", "Fishing"];

// Which gathering profession supplies each crafting profession
export const SUPPLIED_BY: Record<string, string> = {
  Alchemy: "Herbalism",
  Blacksmithing: "Mining",
  Engineering: "Mining",
  Leatherworking: "Skinning",
};
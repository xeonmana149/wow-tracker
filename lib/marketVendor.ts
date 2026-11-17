// Crafting supplies vendors sell in unlimited supply, with roughly what
// they cost (copper). Same list the Forever Gold addon uses
// (addon/ForeverGold/Data.lua), so crafting costs on the site don't treat
// thread, flux or vials as "only on the auction house".
export const VENDOR_SUPPLIES: Record<number, number> = {
  2880: 100, // Weak Flux
  3466: 2000, // Strong Flux
  3857: 500, // Coal
  3371: 20, // Empty Vial
  3372: 40, // Leaded Vial
  8925: 500, // Crystal Vial
  2320: 10, // Coarse Thread
  2321: 100, // Fine Thread
  4291: 500, // Silken Thread
  8343: 2000, // Heavy Silken Thread
  14341: 5000, // Rune Thread
  2678: 10, // Mild Spices
  2692: 40, // Hot Spices
  3713: 160, // Soothing Spices
  4470: 38, // Simple Wood
  4471: 135, // Flint and Tinder
  159: 5, // Refreshing Spring Water
  1179: 25, // Ice Cold Milk
  4289: 50, // Salt
  2324: 25, // Bleach
  2604: 50, // Red Dye
  2605: 100, // Green Dye
  6260: 50, // Blue Dye
  4340: 350, // Gray Dye
  4341: 500, // Yellow Dye
  6261: 1000, // Orange Dye
  2325: 1000, // Black Dye
  4342: 2500, // Purple Dye
  4399: 200, // Wooden Stock
  4400: 2000, // Heavy Stock
  6530: 100, // Nightcrawlers
  6529: 50, // Shiny Bauble
};

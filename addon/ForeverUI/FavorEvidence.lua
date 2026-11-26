-- Player-reported sources: keep separate from published recipe data.
-- Costs and vendors are deliberately omitted until independently confirmed.
local _, ns = ...
ns.FavorRecipeReports = {
    [251354] = "Player-reported Merchant's Favor source; cost and vendor not yet verified.",
}

-- Cross-checked vendor inventories, with QuestieDB Forever spawn coordinates.
-- Vendor stock and price: https://www.wowhead.com/forever/npc=248199/beneris
-- https://www.wowhead.com/forever/item=249536/formula-enchant-gloves-holy-power
-- https://www.wowhead.com/forever/item=249529/formula-idol-of-the-dream
-- https://guildloot.de/en/forever/guide/azeroth-commerce-authority/
ns.FavorVendors = {
    [248196] = { 248196, "Apothecary Durelle", "The Barrens", 1413, 49.93, 29.56, fac = "H" },
    [256729] = { 256729, "Nina Surefire", "Redridge Mountains", 1433, 10.86, 72.42, fac = "A" },
    [248197] = { 248197, "Gor'mak", "The Barrens", 1413, 49.83, 29.70, fac = "H" },
    [256730] = { 256730, "Stondry Darkhammer", "Redridge Mountains", 1433, 10.36, 74.78, fac = "A" },
    [248198] = { 248198, "Aza'bek", "The Barrens", 1413, 49.74, 29.35, fac = "H" },
    [256731] = { 256731, "Kalsey Sanden", "Redridge Mountains", 1433, 10.80, 72.76, fac = "A" },
    [248200] = { 248200, "Fizzlefuse", "The Barrens", 1413, 49.81, 29.72, fac = "H" },
    [256733] = { 256733, "Fritz Fizzle", "Redridge Mountains", 1433, 10.42, 74.32, fac = "A" },
    [248201] = { 248201, "Pawani", "The Barrens", 1413, 49.59, 29.67, fac = "H" },
    [256734] = { 256734, "Daniel Stitchsong", "Redridge Mountains", 1433, 10.02, 72.65, fac = "A" },
    [248202] = { 248202, "Jim'bek", "The Barrens", 1413, 49.59, 29.46, fac = "H" },
    [256735] = { 256735, "Mivin Shadowweave", "Redridge Mountains", 1433, 10.03, 72.83, fac = "A" },
    [248199] = { 248199, "Beneris", "The Barrens", 1413, 49.68, 29.8, fac = "H" },
    [256732] = { 256732, "Alynsia", "Redridge Mountains", 1433, 11.21, 71.5, fac = "A" },
}
ns.FavorRecipeVendorEvidence = {
    [249534] = { 248199, 256732 }, -- Enchant Gloves - Arcane Power
    [249536] = { 248199, 256732 }, -- Enchant Gloves - Holy Power
    [249529] = { 248199, 256732 }, -- Idol of the Dream
    [249530] = { 248199, 256732 }, -- Libram of Holy Alacrity
    [249532] = { 248199, 256732 }, -- Totem of Thunder
}

-- Cross-checked against photographed live Alliance vendor inventories.
-- https://gitm.gg/guides/wow-forever-merchants-favor-recipes/
-- https://www.wow-professions.com/forever/npc/nina-surefire
-- https://warcraft.wiki.gg/wiki/Gor%27mak
ns.FavorRecipeAudited = {
    [250998] = { cost = 180 }, -- Potion of Elemental Purging
    [285289] = { cost = 30, vendors = { 248197, 256730 } }, -- Cracked Blacksmith Hammer
    [285290] = { cost = 60, vendors = { 248197, 256730 } }, -- Mithril Blacksmith Hammer
    [285291] = { cost = 90, vendors = { 248197, 256730 } }, -- Arcanite Blacksmith Hammer
    [251426] = { cost = 90, vendors = { 248197, 256730 } }, -- Prefect's Waistguard
    [289560] = { cost = 180, vendors = { 248199, 256732 } }, -- Enchant Boots - Speed
}
-- Recent player inventories do not list these at Favor vendors. Older beta
-- databases do; absence from one vendor does not rule out another source.
-- https://www.curseforge.com/wow/addons/waylaidmaster/files/9677380
-- https://guide.wow4ever.se/en/npc/248200 (inventory reported 11 Nov)
-- https://guide.wow4ever.se/en/npc/248196 (inventory confirmed 19 Nov)
-- https://www.wowhead.com/forever/item=264221/schematic-gnomish-army-knife (player comments)
ns.FavorRecipeCautions = {
    [264221] = "Live inventories: not seen at Favor vendors as of 13 Nov; no verified drops or quest rewards found. The 270 Favor price is an older reference.",
    [264222] = "Live inventories: not seen at Favor vendors as of 13 Nov; no verified drops or quest rewards found. The 270 Favor price is an older reference.",
    [250996] = "Vendor reports conflict: not seen at Durelle on 19 Nov, though other sources list both vendors. No verified drops or quest rewards found; 120 Favor is an older reference.",
}

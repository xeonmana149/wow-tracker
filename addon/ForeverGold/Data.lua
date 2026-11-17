-- Forever Gold - built-in guide data
--
-- Everything in here is general vanilla-world knowledge: which things come
-- from where. It contains NO prices - prices always come from your own
-- auction house scans, so the advice adapts to your realm.
--
-- Items are written as { "Name", idHint, perHour }. The name is the source of
-- truth; the ID is only a hint and is double-checked against the client (see
-- ns.Resolve in Core.lua), because WoW Forever may number things differently
-- from 2004. perHour is a deliberately rough guess at how many of that item
-- one hour of the activity gives, used only to rank farms against each other.
-- Your real numbers come from the Kills & Loot window.

local _, ns = ...

----------------------------------------------------------------------
-- Things vendors sell in unlimited supply (approximate price in copper).
-- Used so crafting costs don't treat cheap vendor supplies as "unknown".
-- The moment you open a vendor that sells one, the real price replaces it.
----------------------------------------------------------------------
ns.VENDOR_ITEMS = {
    { "Weak Flux", 2880, 100 },
    { "Strong Flux", 3466, 2000 },
    { "Coal", 3857, 500 },
    { "Empty Vial", 3371, 20 },
    { "Leaded Vial", 3372, 40 },
    { "Crystal Vial", 8925, 500 },
    { "Coarse Thread", 2320, 10 },
    { "Fine Thread", 2321, 100 },
    { "Silken Thread", 4291, 500 },
    { "Heavy Silken Thread", 8343, 2000 },
    { "Rune Thread", 14341, 5000 },
    { "Mild Spices", 2678, 10 },
    { "Hot Spices", 2692, 40 },
    { "Soothing Spices", 3713, 160 },
    { "Simple Wood", 4470, 38 },
    { "Flint and Tinder", 4471, 135 },
    { "Refreshing Spring Water", 159, 5 },
    { "Ice Cold Milk", 1179, 25 },
    { "Salt", 4289, 50 },
    { "Bleach", 2324, 25 },
    { "Red Dye", 2604, 50 },
    { "Green Dye", 2605, 100 },
    { "Blue Dye", 6260, 50 },
    { "Gray Dye", 4340, 350 },
    { "Yellow Dye", 4341, 500 },
    { "Orange Dye", 6261, 1000 },
    { "Black Dye", 2325, 1000 },
    { "Purple Dye", 4342, 2500 },
    { "Wooden Stock", 4399, 200 },
    { "Heavy Stock", 4400, 2000 },
    { "Nightcrawlers", 6530, 100 },
    { "Shiny Bauble", 6529, 50 },
}

----------------------------------------------------------------------
-- Farms.
--   kind   = profession needed ("Mining", "Herbalism", "Fishing", "Skinning")
--            or nil when anyone can do it (killing things for drops)
--   skill  = profession skill needed
--   level  = character level where this becomes comfortable
--   horde / alliance / both = where to go
--   how    = one plain sentence
----------------------------------------------------------------------
ns.FARMS = {
    -------------------------------------------------------------- Mining
    {
        key = "mine-copper", kind = "Mining", skill = 1, level = 5,
        title = "Mine Copper",
        horde = "Durotar, Mulgore, Tirisfal Glades, The Barrens, Silverpine Forest",
        alliance = "Elwynn Forest, Dun Morogh, Westfall, Loch Modan, Darkshore",
        how = "Run the hills and cave mouths; copper sits along cliffs and rock walls.",
        items = { { "Copper Ore", 2770, 70 }, { "Rough Stone", 2835, 35 }, { "Malachite", 774, 2 },
            { "Tigerseye", 818, 2 }, { "Shadowgem", 1210, 1 } },
    },
    {
        key = "mine-tin", kind = "Mining", skill = 65, level = 16,
        title = "Mine Tin (and Silver)",
        horde = "Southern Barrens, Stonetalon Mountains, Hillsbrad Foothills, Ashenvale, Thousand Needles",
        alliance = "Redridge Mountains, Wetlands, Duskwood, Hillsbrad Foothills, Ashenvale",
        how = "Tin zones also spawn Silver veins now and then - silver is the real prize, never vendor it.",
        items = { { "Tin Ore", 2771, 55 }, { "Coarse Stone", 2836, 30 }, { "Copper Ore", 2770, 15 },
            { "Silver Ore", 2775, 4 }, { "Moss Agate", 1206, 2 }, { "Shadowgem", 1210, 2 },
            { "Lesser Moonstone", 1705, 1 } },
    },
    {
        key = "mine-iron", kind = "Mining", skill = 125, level = 30,
        title = "Mine Iron (and Gold)",
        both = "Arathi Highlands, Thousand Needles, Desolace, Alterac Mountains, Stranglethorn Vale, Badlands",
        how = "Iron zones also spawn Gold veins. Heavy Stone sells to blacksmiths and engineers.",
        items = { { "Iron Ore", 2772, 50 }, { "Heavy Stone", 2838, 28 }, { "Tin Ore", 2771, 10 },
            { "Gold Ore", 2776, 4 }, { "Jade", 1529, 2 }, { "Lesser Moonstone", 1705, 2 }, { "Citrine", 3864, 1 } },
    },
    {
        key = "mine-mithril", kind = "Mining", skill = 175, level = 40,
        title = "Mine Mithril (and Truesilver)",
        both = "Badlands, Tanaris, The Hinterlands, Searing Gorge, Feralas, Felwood, Burning Steppes",
        how = "Loop the mountain edges. Truesilver veins share the same spawn points.",
        items = { { "Mithril Ore", 3858, 45 }, { "Solid Stone", 7912, 25 }, { "Iron Ore", 2772, 8 },
            { "Truesilver Ore", 7911, 3 }, { "Citrine", 3864, 2 }, { "Aquamarine", 7909, 1 },
            { "Star Ruby", 7910, 1 } },
    },
    {
        key = "mine-thorium", kind = "Mining", skill = 245, level = 50,
        title = "Mine Thorium",
        both = "Un'Goro Crater, Winterspring, Burning Steppes, Western and Eastern Plaguelands, Silithus",
        how = "Un'Goro's outer rim is the classic loop. Rich Thorium (skill 275) can drop Arcane Crystals.",
        items = { { "Thorium Ore", 10620, 40 }, { "Dense Stone", 12365, 22 }, { "Mithril Ore", 3858, 8 },
            { "Arcane Crystal", 12363, 1 }, { "Blue Sapphire", 12361, 1 }, { "Large Opal", 12799, 1 },
            { "Star Ruby", 7910, 1 } },
    },
    ---------------------------------------------------------- Herbalism
    {
        key = "herb-starter", kind = "Herbalism", skill = 1, level = 3,
        title = "Pick starter herbs",
        horde = "Durotar, Mulgore, Tirisfal Glades, The Barrens",
        alliance = "Elwynn Forest, Teldrassil, Dun Morogh, Westfall, Loch Modan",
        how = "Peacebloom and Silverleaf grow on open ground, Earthroot on hillsides.",
        items = { { "Peacebloom", 2447, 40 }, { "Silverleaf", 765, 40 }, { "Earthroot", 2449, 20 } },
    },
    {
        key = "herb-mageroyal", kind = "Herbalism", skill = 50, level = 12,
        title = "Pick Mageroyal and Briarthorn",
        horde = "The Barrens, Silverpine Forest, Stonetalon Mountains",
        alliance = "Westfall, Darkshore, Loch Modan, Redridge Mountains",
        how = "Both give Swiftthistle as a bonus - rogues buy it for Thistle Tea, so don't vendor it.",
        items = { { "Mageroyal", 785, 35 }, { "Briarthorn", 2450, 30 }, { "Swiftthistle", 2452, 8 },
            { "Earthroot", 2449, 10 } },
    },
    {
        key = "herb-kelp", kind = "Herbalism", skill = 85, level = 15,
        title = "Pick Stranglekelp along the coast",
        horde = "The Barrens coast (Ratchet), Hillsbrad coast, Zoram Strand in Ashenvale",
        alliance = "Westfall coast, Darkshore coast, Wetlands coast, Hillsbrad coast",
        how = "It only grows underwater near the shore. Few people bother, so it's often pricey.",
        items = { { "Stranglekelp", 3820, 45 } },
    },
    {
        key = "herb-bruise", kind = "Herbalism", skill = 100, level = 20,
        title = "Pick Bruiseweed, Steelbloom and Kingsblood",
        horde = "Hillsbrad Foothills, Stonetalon Mountains, Ashenvale, Thousand Needles",
        alliance = "Wetlands, Duskwood, Redridge Mountains, Ashenvale",
        how = "Bruiseweed hugs buildings and ruins, Steelbloom is on cliffs, Kingsblood on open grass.",
        items = { { "Bruiseweed", 2453, 30 }, { "Wild Steelbloom", 3355, 15 }, { "Kingsblood", 3356, 25 },
            { "Briarthorn", 2450, 10 } },
    },
    {
        key = "herb-liferoot", kind = "Herbalism", skill = 150, level = 28,
        title = "Pick Liferoot, Kingsblood and Grave Moss",
        both = "Hillsbrad Foothills, Wetlands, Arathi Highlands, Stranglethorn Vale, Desolace",
        how = "Liferoot grows on river banks. Grave Moss only grows in graveyards and sells well.",
        items = { { "Liferoot", 3357, 25 }, { "Kingsblood", 3356, 25 }, { "Grave Moss", 3369, 8 },
            { "Wild Steelbloom", 3355, 10 } },
    },
    {
        key = "herb-fadeleaf", kind = "Herbalism", skill = 160, level = 33,
        title = "Pick Fadeleaf, Goldthorn and Khadgar's Whisker",
        both = "Arathi Highlands, Stranglethorn Vale, Alterac Mountains, Swamp of Sorrows, Dustwallow Marsh",
        how = "Rogues need Fadeleaf for Blinding Powder, so it holds its price.",
        items = { { "Fadeleaf", 3818, 25 }, { "Goldthorn", 3821, 25 }, { "Khadgar's Whisker", 3358, 25 },
            { "Wintersbite", 3819, 4 } },
    },
    {
        key = "herb-firebloom", kind = "Herbalism", skill = 205, level = 42,
        title = "Pick Firebloom, Purple Lotus and Sungrass",
        both = "Tanaris, Searing Gorge, Badlands, The Hinterlands, Feralas",
        how = "Firebloom is in hot, dry zones. Purple Lotus grows around troll and elf ruins.",
        items = { { "Firebloom", 4625, 25 }, { "Purple Lotus", 8831, 20 }, { "Sungrass", 8838, 25 },
            { "Arthas' Tears", 8836, 8 }, { "Blindweed", 8839, 5 }, { "Wildvine", 8153, 3 } },
    },
    {
        key = "herb-high", kind = "Herbalism", skill = 260, level = 50,
        title = "Pick Dreamfoil, Golden Sansam and Mountain Silversage",
        both = "Un'Goro Crater, Felwood, Winterspring, Eastern Plaguelands, Burning Steppes, Silithus",
        how = "The raiding herbs. Plaguebloom is in the Plaguelands, Icecap in Winterspring.",
        items = { { "Dreamfoil", 13463, 30 }, { "Golden Sansam", 13464, 25 }, { "Mountain Silversage", 13465, 15 },
            { "Plaguebloom", 13466, 10 }, { "Icecap", 13467, 8 }, { "Gromsblood", 8846, 8 },
            { "Black Lotus", 13468, 0.2 } },
    },
    ------------------------------------------------------------ Fishing
    {
        key = "fish-deviate", kind = "Fishing", skill = 1, level = 14,
        title = "Fish Deviate Fish in the Barrens oases",
        both = "The Barrens: Lushwater, Stagnant and Forgotten Pools oases, and inside Wailing Caverns",
        how = "A famous niche: cooks turn these into Savory Deviate Delight, which turns you into a pirate or ninja.",
        items = { { "Deviate Fish", 6522, 30 }, { "Raw Longjaw Mud Snapper", 6289, 30 },
            { "Raw Brilliant Smallfish", 6291, 20 } },
    },
    {
        key = "fish-blackmouth", kind = "Fishing", skill = 55, level = 12,
        title = "Fish Oily Blackmouth schools",
        horde = "The Barrens coast (Ratchet), Hillsbrad coast, Silverpine coast",
        alliance = "Westfall coast, Darkshore coast, Wetlands coast, Hillsbrad coast",
        how = "Look for the swirling 'Oily Blackmouth School' patches near shore. Alchemists need the oil.",
        items = { { "Oily Blackmouth", 6358, 50 }, { "Raw Rainbow Fin Albacore", 6361, 20 },
            { "Raw Slitherskin Mackerel", 6303, 15 } },
    },
    {
        key = "fish-sagefish", kind = "Fishing", skill = 55, level = 14,
        title = "Fish Sagefish schools",
        horde = "Rivers and lakes in Hillsbrad Foothills, Stonetalon Mountains, Silverpine Forest, Ashenvale",
        alliance = "Rivers and lakes in Loch Modan, Darkshore, Redridge Mountains, Hillsbrad Foothills",
        how = "Smoked Sagefish restores mana over time, so every levelling caster wants a stack.",
        items = { { "Raw Sagefish", 21071, 45 }, { "Raw Bristle Whisker Catfish", 6308, 20 },
            { "Raw Longjaw Mud Snapper", 6289, 20 } },
    },
    {
        key = "fish-firefin", kind = "Fishing", skill = 130, level = 30,
        title = "Fish Firefin Snapper schools",
        both = "Stranglethorn Vale coast, Arathi coast, Dustwallow Marsh coast, Desolace coast, Tanaris (Steamwheedle Port)",
        how = "Alchemists turn Firefin into Fire Oil. Floating wreckage nearby gives cloth, potions and trunks.",
        items = { { "Firefin Snapper", 6359, 45 }, { "Raw Rockscale Cod", 6362, 25 },
            { "Raw Spotted Yellowtail", 4603, 15 }, { "Oily Blackmouth", 6358, 10 } },
    },
    {
        key = "fish-eel", kind = "Fishing", skill = 205, level = 45,
        title = "Fish Stonescale Eel",
        both = "Coasts of Tanaris, Feralas, Azshara, The Hinterlands and southern Stranglethorn (Booty Bay)",
        how = "Bites far more often at night. Needed for raid potions, so the price stays high.",
        items = { { "Stonescale Eel", 13422, 25 }, { "Raw Spotted Yellowtail", 4603, 30 },
            { "Big-mouth Clam", 7973, 5 }, { "Firefin Snapper", 6359, 10 } },
    },
    {
        key = "fish-high", kind = "Fishing", skill = 250, level = 50,
        title = "Fish Nightfin, Sunscale and Winter Squid",
        both = "Inland lakes of Feralas, Un'Goro, Felwood and the Plaguelands; coasts of Azshara and Tanaris",
        how = "Nightfin bites at night, Sunscale by day. Winter Squid (winter months) makes the best agility food.",
        items = { { "Raw Nightfin Snapper", 13759, 20 }, { "Raw Sunscale Salmon", 13760, 20 },
            { "Winter Squid", 13755, 15 }, { "Raw Redgill", 13758, 20 }, { "Raw Whitescale Salmon", 13889, 15 },
            { "Darkclaw Lobster", 13888, 5 } },
    },
    ----------------------------------------------------------- Skinning
    {
        key = "skin-light", kind = "Skinning", skill = 1, level = 6,
        title = "Skin beasts for Light Leather",
        horde = "The Barrens (plainstriders, raptors, lions), Durotar, Mulgore, Silverpine Forest",
        alliance = "Westfall, Elwynn Forest, Loch Modan, Darkshore",
        how = "Kill anything furry or scaly between level 5 and 18 and skin it.",
        items = { { "Light Leather", 2318, 60 }, { "Ruined Leather Scraps", 2934, 40 }, { "Light Hide", 783, 6 } },
    },
    {
        key = "skin-medium", kind = "Skinning", skill = 100, level = 20,
        title = "Skin beasts for Medium Leather",
        horde = "Hillsbrad Foothills (bears, mountain lions), Ashenvale, Stonetalon Mountains, Thousand Needles",
        alliance = "Wetlands (raptors, crocolisks), Duskwood (wolves), Redridge Mountains, Ashenvale",
        how = "Beasts level 18 to 30. Hides are rarer and worth more than the leather.",
        items = { { "Medium Leather", 2319, 60 }, { "Light Leather", 2318, 20 }, { "Medium Hide", 4232, 6 } },
    },
    {
        key = "skin-heavy", kind = "Skinning", skill = 150, level = 30,
        title = "Skin beasts for Heavy Leather",
        both = "Stranglethorn Vale (tigers, panthers, raptors), Arathi Highlands (raptors), Desolace, Badlands",
        how = "Northern Stranglethorn is packed with skinnable beasts level 30 to 40.",
        items = { { "Heavy Leather", 4234, 55 }, { "Medium Leather", 2319, 20 }, { "Heavy Hide", 4235, 5 },
            { "Raptor Hide", 4461, 5 } },
    },
    {
        key = "skin-thick", kind = "Skinning", skill = 200, level = 40,
        title = "Skin beasts for Thick Leather",
        both = "Feralas (yetis, hippogryphs), Tanaris (hyenas, scorpids), The Hinterlands (wolves, turtles)",
        how = "Tanaris turtles and scorpids also give scales that leatherworkers pay well for.",
        items = { { "Thick Leather", 4304, 55 }, { "Heavy Leather", 4234, 15 }, { "Thick Hide", 8169, 4 },
            { "Turtle Scale", 8167, 6 }, { "Scorpid Scale", 8154, 6 } },
    },
    {
        key = "skin-rugged", kind = "Skinning", skill = 250, level = 50,
        title = "Skin beasts for Rugged Leather",
        both = "Un'Goro Crater (devilsaurs, raptors), Winterspring (yetis, bears), Felwood, Western Plaguelands",
        how = "Beasts level 48 and up. Devilsaur Leather from Un'Goro devilsaurs is the jackpot.",
        items = { { "Rugged Leather", 8170, 55 }, { "Thick Leather", 4304, 15 }, { "Rugged Hide", 8171, 3 },
            { "Devilsaur Leather", 15417, 1 } },
    },
    -------------------------------------------------------------- Cloth
    {
        key = "cloth-linen", level = 8,
        title = "Farm Linen Cloth from humanoids",
        horde = "The Barrens (Razormane quilboar, Kolkar centaur), Silverpine (Dalaran mages), Ragefire Chasm",
        alliance = "Westfall (Defias), Elwynn Forest (Defias, murlocs), Loch Modan (troggs, kobolds)",
        how = "Any humanoid level 5 to 20. Tailors and first-aiders burn through stacks of it.",
        items = { { "Linen Cloth", 2589, 90 }, { "Wool Cloth", 2592, 8 } },
    },
    {
        key = "cloth-wool", level = 18,
        title = "Farm Wool Cloth from humanoids",
        horde = "Hillsbrad Foothills (Syndicate, farmers, miners), Stonetalon (Venture Co.), Shadowfang Keep",
        alliance = "Duskwood, Wetlands (Dragonmaw orcs), Redridge (Blackrock orcs), The Stockade",
        how = "Wool drops from a narrow band of enemies (about level 15 to 28), so it is often scarce and pricey.",
        items = { { "Wool Cloth", 2592, 70 }, { "Linen Cloth", 2589, 25 }, { "Silk Cloth", 4306, 5 } },
    },
    {
        key = "cloth-silk", level = 30,
        title = "Farm Silk Cloth from humanoids",
        both = "Scarlet Monastery, Arathi Highlands (Syndicate, ogres), Alterac Mountains (Syndicate, ogres), Stranglethorn Vale (Venture Co., trolls)",
        how = "Humanoids level 28 to 40. Scarlet Monastery runs are the fastest source.",
        items = { { "Silk Cloth", 4306, 80 }, { "Wool Cloth", 2592, 15 }, { "Mageweave Cloth", 4338, 5 } },
    },
    {
        key = "cloth-mageweave", level = 42,
        title = "Farm Mageweave Cloth from humanoids",
        both = "Tanaris (Wastewander bandits, pirates), Zul'Farrak, Feralas (Gordunni ogres), The Hinterlands (trolls)",
        how = "Humanoids level 40 to 50. The Tanaris bandit camps are close together and respawn quickly.",
        items = { { "Mageweave Cloth", 4338, 80 }, { "Silk Cloth", 4306, 15 }, { "Runecloth", 14047, 5 } },
    },
    {
        key = "cloth-runecloth", level = 52,
        title = "Farm Runecloth from humanoids and undead",
        both = "Felwood (furbolgs, satyrs), Western and Eastern Plaguelands (undead), Winterspring (furbolgs), Azshara",
        how = "Level 50+ humanoids and undead. Felwood satyrs also drop Felcloth.",
        items = { { "Runecloth", 14047, 90 }, { "Mageweave Cloth", 4338, 10 }, { "Felcloth", 14256, 2 } },
    },
    -------------------------------------------------------- Other drops
    {
        key = "drop-clams", level = 12,
        title = "Farm murlocs for clams and pearls",
        horde = "The Barrens coast, Hillsbrad coast, Silverpine coast",
        alliance = "Westfall coast, Darkshore coast, Redridge (Lake Everstill), Wetlands coast",
        how = "Open the clams: Small Lustrous Pearls go to tailors and blacksmiths, Clam Meat to cooks.",
        items = { { "Small Lustrous Pearl", 5498, 4 }, { "Clam Meat", 5503, 30 }, { "Murloc Fin", 1468, 15 },
            { "Linen Cloth", 2589, 30 }, { "Slimy Murloc Scale", 5784, 20 } },
    },
    {
        key = "drop-spidersilk", level = 22,
        title = "Farm spiders for Spider's Silk",
        horde = "Hillsbrad Foothills (Forest Moss Creepers near Tarren Mill), Ashenvale",
        alliance = "Duskwood (spiders around the cemetery roads), Wetlands (Mosshide area spiders)",
        how = "Spider's Silk is needed for popular tailoring recipes and drops from few enemies.",
        items = { { "Spider's Silk", 3182, 12 }, { "Gooey Spider Leg", 2251, 30 }, { "Crisp Spider Meat", 1081, 20 } },
    },
    {
        key = "drop-flamesac", level = 24,
        title = "Farm Wetlands whelps for Small Flame Sacs",
        both = "Wetlands - the Lost Whelps and Crimson Whelps in the hills north-east of Menethil",
        how = "Flame sacs go into fire-protection potions and Dragonbreath Chili. The whelp pet is a bonus.",
        items = { { "Small Flame Sac", 4402, 14 } },
    },
    {
        key = "drop-elemental-arathi", level = 38,
        title = "Farm the Arathi elementals",
        both = "Arathi Highlands - the four Circles of Binding (fire in the west, earth, air and water at the others)",
        how = "Elemental Fire, Earth, Air and Water are all needed for crafting and never stop selling.",
        items = { { "Elemental Fire", 7068, 8 }, { "Elemental Earth", 7067, 8 }, { "Elemental Air", 7069, 6 },
            { "Elemental Water", 7070, 6 } },
    },
    {
        key = "drop-earth-badlands", level = 38,
        title = "Farm Badlands rock elementals",
        both = "Badlands - the rock elementals around the southern and eastern edges",
        how = "Elemental Earth plus stone. Easy for a miner because the area is full of iron and mithril too.",
        items = { { "Elemental Earth", 7067, 12 }, { "Solid Stone", 7912, 6 }, { "Heavy Stone", 2838, 6 } },
    },
    {
        key = "drop-kodo", kind = "Skinning", skill = 60, level = 14,
        title = "Skin Barrens kodos for Thin Kodo Leather",
        both = "The Barrens - the kodo herds roaming the central plains",
        how = "Leatherworkers need Thin Kodo Leather for a popular bag recipe, and nothing else gives it.",
        items = { { "Thin Kodo Leather", 5082, 20 }, { "Light Leather", 2318, 30 } },
    },
    {
        key = "drop-deviate", kind = "Skinning", skill = 60, level = 16,
        title = "Skin deviate creatures for Deviate Scales",
        both = "Wailing Caverns in the Barrens (the caves before and inside the dungeon)",
        how = "Deviate Scales only come from here and leatherworkers use them for a levelling set.",
        items = { { "Deviate Scale", 6470, 20 }, { "Perfect Deviate Scale", 6471, 3 }, { "Light Leather", 2318, 30 } },
    },
    {
        key = "drop-meat-bear", level = 20,
        title = "Hunt bears and lions for cooking meat",
        horde = "Hillsbrad Foothills (bears and mountain lions), Ashenvale (bears)",
        alliance = "Ashenvale, Loch Modan and Darkshore (bears), Hillsbrad Foothills",
        how = "In WoW Forever, Well Fed food also gives bonus kill XP, so cooks buy raw meat to sell to levellers.",
        items = { { "Big Bear Meat", 3730, 25 }, { "Bear Meat", 3173, 15 }, { "Lion Meat", 3731, 20 } },
    },
    {
        key = "drop-meat-raptor", level = 32,
        title = "Hunt Stranglethorn beasts for cooking meat",
        both = "Northern Stranglethorn Vale - tigers, panthers and raptors",
        how = "Tiger Meat and Raptor Flesh feed mid-level cooking recipes; pairs perfectly with skinning.",
        items = { { "Tiger Meat", 12202, 25 }, { "Raptor Flesh", 12184, 20 }, { "Raptor Egg", 3685, 5 } },
    },
    {
        key = "drop-meat-high", level = 48,
        title = "Hunt for Tender Wolf Meat and Giant Eggs",
        both = "Felwood and Winterspring (wolves, owls), Tanaris (rocs), Western Plaguelands (diseased wolves)",
        how = "These feed the top cooking recipes that raiders eat before every pull.",
        items = { { "Tender Wolf Meat", 12208, 25 }, { "Giant Egg", 12207, 12 }, { "White Spider Meat", 12205, 10 } },
    },
    {
        key = "drop-essence", level = 52,
        title = "Farm high-level elementals for Essences",
        both = "Felwood (toxic horrors), Un'Goro (Fire Plume Ridge), Winterspring, Silithus, Eastern Plaguelands",
        how = "Essence of Water, Fire, Earth and Air are needed for the best crafted gear.",
        items = { { "Essence of Water", 7080, 2 }, { "Essence of Fire", 7078, 2 }, { "Essence of Earth", 7076, 2 },
            { "Essence of Air", 7082, 2 }, { "Living Essence", 12803, 3 }, { "Elemental Fire", 7068, 10 },
            { "Elemental Water", 7070, 8 } },
    },
}

----------------------------------------------------------------------
-- Niche ideas, shown under Settings with live prices next to each item.
-- prof = nil means the tip is for everyone.
----------------------------------------------------------------------
ns.TIPS = {
    {
        title = "How this addon thinks",
        text = "It reads the lowest price of everything on the auction house, then compares that with what things cost you to make, farm or buy. Green numbers are money you keep after the auction house takes its 5%.",
    },
    {
        title = "Rare ore is never vendor trash",
        prof = "Mining",
        text = "Silver, Gold and Truesilver veins are rare spawns. Every blacksmith, engineer and jeweller hits a wall where they need a handful of these bars, so they sell for many times what common bars do.",
        items = { { "Silver Ore", 2775 }, { "Silver Bar", 2842 }, { "Gold Ore", 2776 }, { "Gold Bar", 3577 },
            { "Truesilver Ore", 7911 }, { "Truesilver Bar", 6037 } },
    },
    {
        title = "Stone is worth picking up",
        prof = "Mining",
        text = "The stone you get while mining looks like junk but blacksmiths and engineers need hundreds for grinding stones and blasting powder. Check the price before you vendor it.",
        items = { { "Rough Stone", 2835 }, { "Coarse Stone", 2836 }, { "Heavy Stone", 2838 },
            { "Solid Stone", 7912 }, { "Dense Stone", 12365 } },
    },
    {
        title = "Ore or bars? Check both",
        prof = "Mining",
        text = "Smelting is free, but bars are not always worth more than the ore. Make > Craft compares them for you every scan. Bronze is the big one: one Copper Bar plus one Tin Bar makes two Bronze Bars.",
        items = { { "Copper Ore", 2770 }, { "Copper Bar", 2840 }, { "Tin Ore", 2771 }, { "Tin Bar", 3576 },
            { "Bronze Bar", 2841 }, { "Iron Ore", 2772 }, { "Iron Bar", 3575 } },
    },
    {
        title = "Rods for enchanters",
        prof = "Blacksmithing",
        text = "Every enchanter needs one of each rod, and only a blacksmith can make them. Few blacksmiths bother to keep them stocked, so one or two listed at a time can sell for far more than the bars cost.",
        items = { { "Copper Rod", 6217 }, { "Silver Rod", 6338 }, { "Golden Rod", 11128 },
            { "Truesilver Rod", 11144 }, { "Arcanite Rod", 16206 } },
    },
    {
        title = "Grinding stones for other crafters",
        prof = "Blacksmithing",
        text = "Engineers and other blacksmiths need stacks of grinding stones to level and most don't want to make them. You turn cheap stone into something people actually search for.",
        items = { { "Rough Grinding Stone", 3470 }, { "Coarse Grinding Stone", 3478 },
            { "Heavy Grinding Stone", 3486 }, { "Solid Grinding Stone", 7966 }, { "Dense Grinding Stone", 12644 } },
    },
    {
        title = "Parts other professions need",
        prof = "Blacksmithing",
        text = "Buckles, chains, spikes and skeleton keys are bought by leatherworkers, warriors and rogues. They sell slowly but with almost no competition.",
        items = { { "Iron Buckle", 7071 }, { "Steel Weapon Chain", 6041 }, { "Iron Shield Spike", 6042 },
            { "Silver Skeleton Key", 15869 }, { "Golden Skeleton Key", 15870 }, { "Mithril Spurs", 7969 },
            { "Mithril Shield Spike", 7967 } },
    },
    {
        title = "Sharpening stones and weightstones",
        prof = "Blacksmithing",
        text = "Melee players use these on every weapon. The low-level ones barely sell; the Dense ones at level 45+ are used by raiders by the stack.",
        items = { { "Coarse Sharpening Stone", 2863 }, { "Heavy Sharpening Stone", 2871 },
            { "Solid Sharpening Stone", 7964 }, { "Dense Sharpening Stone", 12404 }, { "Dense Weightstone", 12643 } },
    },
    {
        title = "Food sells in WoW Forever",
        prof = "Cooking",
        text = "Here every Well Fed food also gives +5% experience from kills, so levelling players buy it. Cook what you loot and fish instead of vendoring the raw meat, and check Make > Craft for which dish pays best.",
        items = { { "Smoked Sagefish", 21072 }, { "Savory Deviate Delight", 6657 }, { "Herb Baked Egg", 6888 },
            { "Crab Cake", 2683 }, { "Dry Pork Ribs", 2687 }, { "Coyote Steak", 2684 }, { "Big Bear Steak", 3726 } },
    },
    {
        title = "Deviate Fish",
        prof = "Fishing",
        text = "Fished only in the Barrens oases and Wailing Caverns. Cooks turn it into Savory Deviate Delight, a fun food that turns people into pirates and ninjas - it has sold steadily for twenty years.",
        items = { { "Deviate Fish", 6522 }, { "Savory Deviate Delight", 6657 },
            { "Recipe: Savory Deviate Delight", 6661 } },
    },
    {
        title = "Fish that alchemists need",
        prof = "Fishing",
        text = "Oily Blackmouth, Firefin Snapper and Stonescale Eel are potion ingredients. Most alchemists don't fish, so they buy every stack. Fish the swirling schools - they give only that fish.",
        items = { { "Oily Blackmouth", 6358 }, { "Firefin Snapper", 6359 }, { "Stonescale Eel", 13422 } },
    },
    {
        title = "Sagefish for casters",
        prof = "Fishing",
        text = "Raw Sagefish cooks into Smoked Sagefish, which restores mana for 15 minutes. Mages, priests and warlocks buy it while levelling.",
        items = { { "Raw Sagefish", 21071 }, { "Smoked Sagefish", 21072 }, { "Raw Greater Sagefish", 21153 },
            { "Sagefish Delight", 21217 } },
    },
    {
        title = "Sell the cloth, not the bandage",
        prof = "First Aid",
        text = "Bandages almost never sell for more than the cloth in them, because everyone makes their own. Level First Aid with cloth you don't plan to sell, and put the rest on the auction house.",
        items = { { "Linen Cloth", 2589 }, { "Wool Cloth", 2592 }, { "Silk Cloth", 4306 },
            { "Mageweave Cloth", 4338 }, { "Runecloth", 14047 } },
    },
    {
        title = "Herbs rogues and alchemists fight over",
        prof = "Herbalism",
        text = "Swiftthistle (a bonus from Mageroyal and Briarthorn), Fadeleaf, Stranglekelp and Grave Moss are needed in small amounts by lots of people and are annoying to gather, which keeps them expensive.",
        items = { { "Swiftthistle", 2452 }, { "Fadeleaf", 3818 }, { "Stranglekelp", 3820 }, { "Grave Moss", 3369 },
            { "Wintersbite", 3819 }, { "Wildvine", 8153 } },
    },
    {
        title = "Hides and scales",
        prof = "Skinning",
        text = "Hides drop rarely and leatherworkers need them cured for key recipes. Scales and special leathers come from only one or two kinds of creature, so they stay valuable.",
        items = { { "Light Hide", 783 }, { "Medium Hide", 4232 }, { "Heavy Hide", 4235 }, { "Thick Hide", 8169 },
            { "Thin Kodo Leather", 5082 }, { "Deviate Scale", 6470 }, { "Turtle Scale", 8167 } },
    },
    {
        title = "Bags always sell",
        prof = "Tailoring",
        text = "Every new character needs four bags. They are the most reliable seller in the game - check Make > Craft for which bag has the best margin today.",
        items = { { "Linen Bag", 4238 }, { "Woolen Bag", 4240 }, { "Small Silk Pack", 4245 },
            { "Mageweave Bag", 10050 }, { "Runecloth Bag", 14046 } },
    },
    {
        title = "Armor kits",
        prof = "Leatherworking",
        text = "Armor kits are cheap to make and used on every piece of levelling gear. Low profit each, but they sell in volume.",
        items = { { "Light Armor Kit", 2304 }, { "Medium Armor Kit", 2313 }, { "Heavy Armor Kit", 4265 },
            { "Thick Armor Kit", 8173 }, { "Rugged Armor Kit", 15564 } },
    },
    {
        title = "Potions people use up",
        prof = "Alchemy",
        text = "Healing, mana and speed potions are drunk and re-bought constantly. Swiftness Potions and Free Action Potions are favourites in PvP.",
        items = { { "Minor Healing Potion", 118 }, { "Lesser Healing Potion", 858 }, { "Healing Potion", 929 },
            { "Swiftness Potion", 2459 }, { "Lesser Mana Potion", 3385 }, { "Free Action Potion", 5634 },
            { "Elixir of Water Breathing", 5996 } },
    },
    {
        title = "Disenchanting cheap greens",
        prof = "Enchanting",
        text = "Green gear that nobody wants is often listed for less than the dust and essence inside it. Compare the cheapest greens with these material prices.",
        items = { { "Strange Dust", 10940 }, { "Lesser Magic Essence", 10938 }, { "Greater Magic Essence", 10939 },
            { "Small Glimmering Shard", 10978 }, { "Soul Dust", 11083 }, { "Lesser Astral Essence", 10998 } },
    },
    {
        title = "Parts and explosives",
        prof = "Engineering",
        text = "Other engineers buy the boring intermediate parts rather than make them, and everyone can use basic explosives.",
        items = { { "Rough Blasting Powder", 4357 }, { "Handful of Copper Bolts", 4359 }, { "Bronze Tube", 4371 },
            { "Target Dummy", 4366 }, { "Gyrochronatom", 4389 }, { "Iron Grenade", 4390 } },
    },
    {
        title = "Vendors are a hidden goldmine",
        text = "Some vendors sell recipes and supplies in limited numbers, far from the cities. Players pay extra on the auction house to avoid the trip. Whenever you open any vendor, this addon quietly compares everything they sell with auction prices and tells you if something is worth buying to resell (see the Buy tab).",
    },
    {
        title = "Free money: auction items cheaper than a vendor pays",
        text = "New players list things for less than a shopkeeper would pay for them. The Buy tab lists these after every scan: buy them and sell them straight to any vendor. There is zero risk.",
    },
    {
        title = "The Sell button",
        text = "On the Sell tab, the Sell button checks that one item's price right now and lists yours just under the cheapest sensible listing. It will not go below your floor (what the item costs to make or what a vendor pays), it ignores silly lowball listings, and it never undercuts your own auctions. You always see the price and press Post yourself.",
    },
    {
        title = "Three habits that make the difference",
        text = "1) Scan every time you pass an auctioneer - fresh prices make every tab smarter. 2) List in small amounts; ten stacks at once just invites undercutting. 3) Items that expire unsold are information, not failure: try a lower price once, then stop making that item.",
    },
}

-- Words the Settings page explains in plain English.
ns.GLOSSARY = {
    { "Auction house cut", "When your auction sells, the auction house keeps 5% of the price. Every profit number in this addon already has that taken off." },
    { "Deposit", "A small fee you pay when you list something. You get it back if the item sells and lose it if the auction expires. It is based on the item's vendor value, so it is tiny for most trade goods." },
    { "Undercut", "Listing your item slightly cheaper than the current lowest price so yours is bought first. One copper cheaper is enough." },
    { "Margin", "Profit as a percentage of what you spent. 50% margin means you spent 1 gold to make 1 gold 50 silver." },
    { "Mats", "Short for materials - the ingredients a recipe needs." },
    { "Flip", "Buying something cheap and re-listing it for more. The riskiest way to make gold; start with the no-risk vendor flips on the Buy tab." },
    { "Floor", "The lowest price the Sell button will ever post at: what the item costs to make (or what a vendor pays), plus 5%, plus the auction house's cut. Below that you'd be better off not selling." },
    { "Lowball", "One or two items listed far below everything else, usually by mistake. They get bought within minutes, so there's no reason to match them." },
    { "Usual price", "The middle of the daily lowest prices this addon has seen over the last few weeks. One strange listing doesn't move it." },
}

-- Names for item IDs the guide mentions, so they can be shown before the
-- client has loaded them.
ns.STATIC_NAMES = {}
do
    local function add(list)
        for _, e in ipairs(list or {}) do
            if type(e[2]) == "number" then
                ns.STATIC_NAMES[e[2]] = e[1]
            end
        end
    end
    add(ns.VENDOR_ITEMS)
    for _, farm in ipairs(ns.FARMS) do add(farm.items) end
    for _, tip in ipairs(ns.TIPS) do add(tip.items) end
end

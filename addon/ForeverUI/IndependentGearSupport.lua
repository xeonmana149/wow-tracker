-- Adapted class and slot rules from OneForAll 6.2.12 (GPL-3.0-or-later).
-- Original source and notices: Attribution/OneForAll-6.2.12-reference-source.zip.
local _, ns = ...
local FLT = ns.IndependentReference
local LOC_SLOTS = {
  INVTYPE_HEAD = {1}, INVTYPE_NECK = {2}, INVTYPE_SHOULDER = {3}, INVTYPE_CLOAK = {15}, INVTYPE_CHEST = {5}, INVTYPE_ROBE = {5},
  INVTYPE_WRIST = {9}, INVTYPE_HAND = {10}, INVTYPE_WAIST = {6}, INVTYPE_LEGS = {7}, INVTYPE_FEET = {8},
  INVTYPE_FINGER = {11, 12}, INVTYPE_TRINKET = {13, 14},
  INVTYPE_WEAPON = {16, 17}, INVTYPE_2HWEAPON = {16}, INVTYPE_WEAPONMAINHAND = {16},
  INVTYPE_WEAPONOFFHAND = {17}, INVTYPE_SHIELD = {17}, INVTYPE_HOLDABLE = {17},
  INVTYPE_RANGED = {18}, INVTYPE_RANGEDRIGHT = {18}, INVTYPE_THROWN = {18}, INVTYPE_RELIC = {18},
}

local ARMOR_MAX = { WARRIOR = 4, PALADIN = 4, HUNTER = 3, SHAMAN = 3, ROGUE = 2, DRUID = 2, PRIEST = 1, MAGE = 1, WARLOCK = 1 }
local SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local DUAL_WIELD = { WARRIOR = true, ROGUE = true, HUNTER = true }
local RELIC = { PALADIN = 7, DRUID = 8, SHAMAN = 9 }
local WEAPONS = { -- weapon subclass IDs
  WARRIOR = {0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18}, PALADIN = {0, 1, 4, 5, 6, 7, 8},
  HUNTER = {0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18}, ROGUE = {0, 2, 3, 4, 7, 13, 15, 16, 18}, -- rogue 0 = one-handed axes (Forever, all rogues; user 11.11.)
  PRIEST = {4, 10, 15, 19}, SHAMAN = {0, 1, 4, 5, 10, 13, 15}, MAGE = {7, 10, 15, 19}, WARLOCK = {7, 10, 15, 19},
  DRUID = {4, 5, 6, 10, 13, 15}, -- 6 polearms: Forever lets druids learn them from 20 (client SkillRaceClassInfo; Discord kiaseli 10.11.)
}
FLT.CLASS_WEAPONS = WEAPONS -- also for the weapon trainers in UI/TrainerSpells.lua
local canWield = {}
for cls, list in pairs(WEAPONS) do canWield[cls] = {}; for _, s in ipairs(list) do canWield[cls][s] = true end end

-- quests of the other faction / for other classes (quest rewards); set by refreshSlots
local mySide, myClassBit
local function hasBit(mask, b) return b and math.floor(mask / b) % 2 == 1 end
local function usable(e, cls, level)
  if e.side and e.side ~= "" and mySide and e.side ~= mySide then return false end
  if e.cls and e.cls > 0 and myClassBit and not hasBit(e.cls, myClassBit) then return false end
  if e.cid == 2 then return canWield[cls] and canWield[cls][e.sub] or false end
  if e.cid ~= 4 then return true end
  if e.loc == "INVTYPE_CLOAK" or e.sub == 0 then return true end -- cloaks, rings, necks, trinkets, holdables
  if e.sub == 6 then return SHIELD[cls] or false end
  if e.sub >= 7 and e.sub <= 9 then return RELIC[cls] == e.sub end
  local max = ARMOR_MAX[cls] or 1
  if max >= 3 and (level or 60) < 40 then max = max - 1 end -- mail / plate from level 40
  return e.sub <= max
end

-- for GearValue.lua: slots per equip location, and whether the player's class can use an item
FLT.GEAR_LOC_SLOTS = LOC_SLOTS
local probe = {}
function FLT.GearCanUse(loc, cid, sub)
  local _, cls = UnitClass("player")
  probe.loc, probe.cid, probe.sub = loc, cid, sub
  return usable(probe, cls, UnitLevel and UnitLevel("player"))
end
function FLT.CanDualWield() local _, cls = UnitClass("player"); return DUAL_WIELD[cls] or false end


-- Read classic talent tabs when this client exposes them; otherwise the scorer
-- deliberately uses its leveling profile instead of guessing the active spec.
function FLT.TalentPointsPerTree()
    if not GetTalentTabInfo then return nil end
    local points = {}
    for i = 1, 3 do
        local ok, first, _, third, _, fifth = pcall(GetTalentTabInfo, i)
        if not ok then return nil end
        points[i] = type(first) == "string" and tonumber(third) or tonumber(fifth) or 0
    end
    return points
end

-- Build the index once from the local reference snapshot; no web requests.
local index
function FLT.GearIndex()
    if index then return index end
    index = {}
    local sourceByItem, bosses, crafted, quests, npcZones = {}, {}, {}, {}, {}
    for _, quest in ipairs(ns.BulkReferenceData and ns.BulkReferenceData.quests or {}) do quests[quest.id] = quest end
    for _, npc in ipairs(ns.BulkReferenceData and ns.BulkReferenceData.npcs or {}) do npcZones[npc.id] = npc.zone end
    -- Availability follows the dated reference used by OneForAll 6.2.12;
    -- unknown later unlocks must be updated rather than assumed to be live.
    local closed = { ["Molten Core"] = true, ["Blackwing Lair"] = true, ["Zul'Gurub"] = true,
        ["Ruins of Ahn'Qiraj"] = true, ["Temple of Ahn'Qiraj"] = true, ["Ahn'Qiraj"] = true, ["Naxxramas"] = true }
    local future = { ["Onyxia's Lair"] = 1796774400, ["Hyjal Summit"] = 1796774400, ["Barrow Deeps"] = 1796774400 }
    local now = GetServerTime and GetServerTime()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local function available(zone)
        if closed[zone] then return false end
        return not future[zone] or type(now) == "number" and now >= future[zone]
    end
    for _, dungeon in ipairs(FLT.DUNGEONS or {}) do
        for _, boss in ipairs(dungeon.bosses or {}) do
            if boss.npcID then bosses[boss.npcID] = { dungeon = dungeon, boss = boss.name } end
        end
    end
    for profession, recipes in pairs(FLT.PROFESSION_RECIPES or {}) do
        for _, recipe in ipairs(recipes) do
            if recipe.i and not crafted[recipe.i] then crafted[recipe.i] = { profession = profession, spell = recipe.s } end
        end
    end
    for _, edge in ipairs(ns.BulkReferenceData and ns.BulkReferenceData.edges or {}) do
        local itemID, kind, sourceID = edge[1], edge[2], edge[3]
        local quest = kind == "q" and quests[sourceID]
        local zone = quest and quest.zone or kind == "n" and npcZones[sourceID]
        local questForFaction = not quest or not faction or not quest.side or quest.side == "" or quest.side == "Both" or quest.side == faction
        if available(zone) and questForFaction then
            local info = sourceByItem[itemID] or {}; sourceByItem[itemID] = info
            if kind == "q" and not info.qid then info.qid = sourceID end
            if kind == "n" then info.hasNpc = true end
            if kind == "n" and edge[4] == "drop" and bosses[sourceID] and not info.dungeon then
                info.dungeon, info.boss = bosses[sourceID].dungeon, bosses[sourceID].boss
            end
        end
    end
    for _, record in ipairs(ns.BulkReferenceData and ns.BulkReferenceData.items or {}) do
        local g, sources, craft = record.gear, sourceByItem[record.id], crafted[record.id]
        if g and (sources or craft) then
            local gear = { id = record.id, name = record.name, q = record.quality, loc = g.loc, cid = g.cid, sub = g.sub,
                cls = g.cls, req = record.requiredLevel, src = "Community reference (availability may vary)" }
            if sources then
                gear.qid, gear.d, gear.boss = sources.qid, sources.dungeon, sources.boss
                local quest = sources.qid and quests[sources.qid]
                if quest and not sources.hasNpc and not craft then
                    gear.qreq = quest.required; gear.side = quest.side == "Horde" and "H" or quest.side == "Alliance" and "A" or nil
                end
            end
            if craft then gear.prof, gear.ps = craft.profession, craft.spell end
            gear.sourceKinds = { quest = sources and sources.qid ~= nil, crafted = craft ~= nil,
                dungeon = sources and sources.dungeon and not sources.dungeon.raid or false,
                raid = sources and sources.dungeon and sources.dungeon.raid and true or false }
            index[#index + 1] = gear
        end
    end
    return index
end

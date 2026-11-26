"""Test encyclopedia services with OneForAll absent and old progress migrated."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
events = {}
ns = { db = {}, Secret = function() return false end,
    IndependentReference = { BOOKS = {{ itemId = 100, questId = 200 }, { itemId = 101, questId = 201 }},
        DUNGEONS = {{ bosses = {{npcID = 123}} }}, BOSS_LEVELS = {}, BOSS_TYPES = {}, BOSS_SUMMONED = {} } }
ns.On = function(name, fn) events[name] = fn end
UnitGUID = function(unit) if unit == "player" then return "Player-A" end return "Creature-0-1-2-3-123-001" end
UnitExists = function() return true end
UnitLevel = function() return 20 end
UnitCreatureType = function() return "Humanoid" end
GetItemCount = function() return 0 end
C_QuestLog = { IsQuestFlaggedCompleted = function(id) return id == 201 end }
C_Container = {
    GetContainerNumSlots = function(bag) if bag == -1 then return 1 end return 0 end,
    GetContainerItemID = function() return 101 end,
}
CreateFrame = function()
  return { SetSize = function() end, SetPoint = function() end, Show = function() end, Hide = function() end,
    SetUnit = function() end, GetDisplayInfo = function() return 456 end }
end
UIParent = {}
OneForAllCharDB = { confirmedDone = {[100] = true}, manualDone = {[101] = true}, bankItems = {[101] = true} }
OneForAllDB = { bossInfo = {[999] = {level=42, ctype="Beast", displayID=789}} }
''')
run = lua.eval('function(s,n) local f,e=loadstring(s); assert(f,e); return f("ForeverUI",n) end')
run((root / 'IndependentFeatures.lua').read_text(encoding='utf-8'), lua.globals().ns)
lua.execute('''
events.PLAYER_LOGIN("PLAYER_LOGIN")
OneForAllCharDB = nil
OneForAllDB = nil
local r, s = ns.IndependentReference, ns.db.encyclopediaBookTracking["Player-A"]
assert(r:GetBookState(r.BOOKS[1]) == "done", "confirmed book progress must migrate")
assert(ns.db.encyclopediaBooks["Player-A"]["101"], "manual marks must migrate into editable marks")
assert(r:GetBossLevel({npcID=999}) == "42" and r:GetLearnedBossDisplay({npcID=999}) == 789, "known boss data must migrate")
assert(r:GetBookState(r.BOOKS[2]) == "bank", "cached bank contents must migrate")
events.BANKFRAME_OPENED("BANKFRAME_OPENED")
assert(s.bank[101], "bank items must be recorded while visiting the bank")
C_Container.GetContainerItemID = function() error("temporarily unavailable") end
events.BAG_UPDATE_DELAYED("BAG_UPDATE_DELAYED")
assert(s.bank[101], "a failed bank scan must not erase saved contents")
s.bank[101] = nil
assert(r:GetBookState(r.BOOKS[2]) == "questflag", "server quest flags must not be treated as confirmed turn-ins")
events.QUEST_TURNED_IN("QUEST_TURNED_IN", 201)
assert(r:GetBookState(r.BOOKS[2]) == "done", "observed book turn-in must be recorded")
events.PLAYER_TARGET_CHANGED("PLAYER_TARGET_CHANGED")
assert(r:GetBossLevel({npcID=123}) == "20" and r:GetBossType({npcID=123}) == "Humanoid")
assert(r:GetLearnedBossDisplay({npcID=123}) == 456, "observed boss portraits must survive without OneForAll")
UnitGUID = function(unit) if unit == "player" then return "Player-A" end return "Creature-0-1-2-3-987-001" end
events.UPDATE_MOUSEOVER_UNIT("UPDATE_MOUSEOVER_UNIT")
assert(r:GetLearnedBossDisplay({npcID=987}) == 456, "ordinary observed NPCs must retain their portraits")
assert(r:GetBossRank({npcID=123}) == "Elite")
assert(r:ShowOnMap({mapID=1,x=20,y=30}) == false, "a missing map must not claim success")
local marker
local canvas = { GetWidth = function() return 1000 end, GetHeight = function() return 500 end }
WorldMapFrame = { ScrollContainer = { Child = canvas }, IsShown = function() return true end,
    SetMapID = function(self, id) self.id = id end, GetMapID = function(self) return self.id end }
CreateFrame = function()
    marker = { SetSize = function() end, SetFrameStrata = function() end,
        CreateTexture = function() return {SetAllPoints=function() end, SetTexture=function() end} end,
        SetScript = function() end, ClearAllPoints = function() end,
        SetPoint = function(self, _, _, _, x, y) self.x, self.y = x, y end,
        Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end }
    return marker
end
assert(r:ShowOnMap({mapID=1,x=20,y=30}) and marker.shown and marker.x==200 and marker.y==-150,
    "the standalone fallback must mark the requested world map coordinates")
''')
print('Standalone library migration, turn-ins, bank preservation and boss observations passed')

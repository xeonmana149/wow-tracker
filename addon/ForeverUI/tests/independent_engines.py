"""Exercise the standalone scoring and profession engines without OneForAll."""
from pathlib import Path
from lupa.lua51 import LuaRuntime
root=Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
_G = _G or _ENV
function wipe(t) for k in pairs(t) do t[k]=nil end end
function UnitClass() return "Warrior", "WARRIOR", 1 end
function UnitLevel() return 20 end
function UnitGUID() return "Player-test" end
function UnitName() return "Tester" end
function UnitFactionGroup() return "Horde" end
function GetInventoryItemLink() return nil end
function GetInventoryItemID() return nil end
function GetItemCount() return 0 end
function CreateFrame() return { RegisterEvent=function() end, SetScript=function() end } end
C_Item = {
 GetItemInfoInstant=function(id) return id,nil,nil,"INVTYPE_HEAD",nil,4,1 end,
 GetItemInfo=function(id) return "Test item" end,
 GetItemStats=function(link)
  local id=tonumber(tostring(link):match("item:(%d+)"))
  return { ITEM_MOD_STRENGTH_SHORT=id==900003 and 2 or id==900004 and 1 or 5, ITEM_MOD_STAMINA_SHORT=3 }
 end,
}
GetItemInfoInstant = C_Item.GetItemInfoInstant
GetItemInfo = C_Item.GetItemInfo
ns={db={},Secret=function() return false end}
ns.On=function(_,f) f() end
ns.SpellKnown=function(id) return IsPlayerSpell and IsPlayerSpell(id) or false end
''')
run=lua.eval('function(s,n) local f,e=loadstring(s); assert(f,e); return f("ForeverUI",n) end');ns=lua.globals().ns
for name in ('IndependentReferenceData.lua','IndependentSkillUp.lua','BulkReferenceData.lua','IndependentGearSupport.lua','IndependentGearValue.lua'):
 run((root/name).read_text(encoding='utf8'),ns)
lua.execute('''
local ref=ns.IndependentReference
assert(type(ref.GearValue.Change)=="function" and type(ref.GearIndex)=="function")
local entries=ref.GearIndex(); assert(#entries > 1000, "bulk gear index unexpectedly small")
assert(ref.GearCanUse("INVTYPE_HEAD",4,1)==true)
assert(ref.GearCanUse("INVTYPE_HEAD",4,4)==false) -- level-20 warrior cannot wear plate
assert(ref.GearCanUse("INVTYPE_RANGED",2,19)==false) -- warrior cannot use wands
local kind=ref.GearValue.Change(900002); assert(kind=="new", "a valid upgrade in an empty slot should be suggested")
GetInventoryItemLink=function(_,slot) if slot==1 then return "item:900003:0" end end
GetInventoryItemID=function(_,slot) if slot==1 then return 900003 end end
ref.GearValue._reset()
assert(ref.GearValue.Change(900002)=="up", "stronger gear should score above equipped gear")
assert(ref.GearValue.Change(900004)=="down", "weaker gear should score below equipped gear")
local saved = ref.PROFESSION_RECIPES.Testing
ref.PROFESSION_RECIPES.Testing={{s=900000,i=900002,n="Test craft",req=1,y=50,g=75,gr=100,start=true,r={{900001,2,"Test reagent"}}}}
local skill=ref.SkillUp
GetProfessions=function() return 1 end
GetProfessionInfo=function() return "Testing",nil,14,75 end
IsPlayerSpell=function(id) return id==900000 end
local state=ref.GetProfessionState("Testing")
assert(state.skill==14 and state.maxSkill==75 and state.known[900000], "current-character profession knowledge must be read from the client")
ref.PROFESSION_RECIPES.Testing[1].start=nil
assert(skill.Acquire("Testing",ref.PROFESSION_RECIPES.Testing[1],state,{},"H") == 0, "learned recipe is available to plan")
IsPlayerSpell=function() return false end
assert(not ref.GetProfessionState("Testing").known[900000], "unknown recipes cannot be marked learned")
ref.PROFESSION_RECIPES.Testing[1].start=true
local old=skill.AHPrice
skill.AHPrice=function(id) if id==900001 then return 10 elseif id==900002 then return 30 end end
local profits=skill.Profit("Testing",false)
assert(#profits==1 and math.abs(profits[1].profit-8.5)<0.01, "profit must subtract materials and auction cut")
ref.VENDOR_PRICES[900001]=3
profits=skill.Profit("Testing",false)
assert(#profits==1 and math.abs(profits[1].profit-22.5)<0.01, "recorded vendor price must be used for vendor materials")
ref.VENDOR_PRICES[900001]=nil
local plan=skill.Plan("Testing",{from=1,to=3,ah=true,vendor=false,fresh=true})
assert(plan and #plan.steps>0 and plan.cost>0, "known priced recipe should yield a skill-up plan")
skill.AHPrice=function() return nil end
assert(#skill.Profit("Testing",false)==0, "unknown prices must not be invented")
skill.AHPrice=old; ref.PROFESSION_RECIPES.Testing=saved
''')
print('Standalone gear scoring, usability, skill-up, profit, and missing-price cases passed')

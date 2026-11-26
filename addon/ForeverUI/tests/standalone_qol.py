"""Test trainer, reward and camera decisions without the OneForAll addon."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
events = {}; opts = {}
ns = { db = {}, IndependentReference = {TRAINER_SPELLS = {[1]={
    {1,11,"Strike",1,0,false,111}, {4,12,"Strike",2,0,false,112},
    {8,13,"Strike",3,0,false,113}, {2,14,"Racial",1,2,false,114},
    {4,15,"Quest spell",0,0,false,115,"class quest"}}, [8]={{2,21,"Fireball",1,1,false,121}}}} }
ns.Secret = function() return false end
ns.Opt = function(k) return opts[k] end
ns.On = function(name,fn) events[name]=fn end
ns.WhenSafe = function(fn) fn() end
UnitClass = function() return "Warrior", "WARRIOR", 1 end
UnitRace = function() return "Human", "Human", 1 end
UnitLevel = function() return 5 end
IsPlayerSpell = function(id) return id == 12 end
GetActionInfo = function(slot) if slot == 1 then return "spell",11 elseif slot == 2 then return "macro",11 end end
local cvars={cameraDistanceMaxZoomFactor="1.9", outlineModeShowLootEffectWhenDisabled="0"}
C_CVar={GetCVar=function(k) return cvars[k] end, SetCVar=function(k,v) cvars[k]=tostring(v); return true end}
getCamera = function() return cvars.cameraDistanceMaxZoomFactor end
setCamera = function(v) cvars.cameraDistanceMaxZoomFactor=v end
getSparkles = function() return cvars.outlineModeShowLootEffectWhenDisabled end
C_Item={GetItemInfo=function(id) if id==1 then return nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,8 elseif id==2 then return nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,20 end end}
GetQuestItemLink = function(_,id) return id end
GetQuestItemInfo = function(_,id) return "name",nil,id==1 and 3 or 1 end
local function button(id)
  return {type="choice", IsShown=function() return true end, GetID=function() return id end,
    CreateTexture=function() return { SetSize=function() end, SetTexture=function() end, SetPoint=function() end,
      Show=function(self) self.visible=true end, Hide=function(self) self.visible=false end } end}
end
QuestInfoRewardsFrame={RewardButtons={button(1),button(2)}}
''')
run = lua.eval('function(s,n) local f,e=loadstring(s); assert(f,e); return f("ForeverUI",n) end')
run((root / 'Trainer.lua').read_text(encoding='utf-8'), lua.globals().ns)
lua.execute('''
OneForAllDB={trainerCosts={WARRIOR={["#13"]={c=88}, ["Strike|3"]={c=999}}}}
events.PLAYER_LOGIN("PLAYER_LOGIN")
assert(ns.db.trainerCosts[1][13]==88, "import only spell-ID trainer prices")
OneForAllDB=nil
''')
run((root / 'QualityOfLife.lua').read_text(encoding='utf-8'), lua.globals().ns)
lua.execute('''
local guide=ns.TrainerGuide
guide.mode="available"
local rows=guide:BuildList()
assert(#rows==1 and rows[1].id==15 and rows[1].quest, "exclude learned ranks and other races; identify quest spells")
guide.mode="upcoming"; rows=guide:BuildList()
assert(#rows==1 and rows[1].id==13 and rows[1].level==8, "list future spell ranks")
guide.viewClass=8; guide.mode="all"; rows=guide:BuildList()
assert(#rows==1 and rows[1].id==21, "browse another class without applying the current character's known spells")
guide.viewClass=nil
rows=guide:BuildLowRanks()
assert(#rows==1 and rows[1].id==11 and rows[1].newID==12 and #rows[1].slots==1, "find lower spell ranks but skip macros")
GetNumTrainerServices=function() return 1 end
GetTrainerServiceCost=function() return 125 end
CreateFrame=function() return {SetOwner=function() end, SetTrainerService=function() end,
    GetSpell=function() return "Strike",13 end, Hide=function() end} end
events.TRAINER_SHOW("TRAINER_SHOW")
assert(ns.db.trainerCosts[1][13]==125, "record an observed trainer price by spell ID")
events.TRAINER_CLOSED("TRAINER_CLOSED")
guide.mode="upcoming"; rows=guide:BuildList()
assert(rows[1].cost==125, "show the recorded price on the matching spell")
opts.qolQuestVendor=true; ns.MarkQuestRewards()
assert(QuestInfoRewardsFrame.RewardButtons[1].fuiVendorCoin.visible, "include stack count in vendor value")
assert(not QuestInfoRewardsFrame.RewardButtons[2].fuiVendorCoin, "do not mark the lower-value choice")
C_Item.GetItemInfo=function(id) if id==1 then return nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,8 end end
ns.MarkQuestRewards()
assert(not QuestInfoRewardsFrame.RewardButtons[1].fuiVendorCoin.visible, "hide recommendations until every price is available")
opts.qolCameraZoom=true; ns.ApplyCameraZoom()
assert(getCamera()=="4", "extend the camera distance")
opts.qolCameraZoom=false; ns.ApplyCameraZoom()
assert(getCamera()=="1.9", "restore the previous camera value")
opts.qolCameraZoom=true; ns.ApplyCameraZoom(); setCamera("3")
opts.qolCameraZoom=false; ns.ApplyCameraZoom()
assert(getCamera()=="3", "do not overwrite a later user change")
opts.qolQuestSparkles=true; ns.ApplyQuestSparkles()
assert(getSparkles()=="1", "enable the native quest loot glow")
opts.qolQuestSparkles=false; ns.Print=function() end; ns.ApplyQuestSparkles()
assert(getSparkles()=="0", "restore the previous quest loot glow setting")
''')
print('Trainer availability, low ranks, reward values and reversible camera setting passed')

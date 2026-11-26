"""Pet-rank migration/scanning and safe low-rank reminders."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
opts={qolLowRankCheck=true}; events={}; messages={}; guid="Player-hunter"
ns={db={}, Secret=function() return false end, Opt=function(k) return opts[k] end,
    On=function(k,f) events[k]=events[k] or {}; table.insert(events[k],f) end,
    WhenSafe=function(f) f() end, Print=function(s) messages[#messages+1]=s end}
ns.IndependentReference={
 PET_ABILITIES={{name="Bite",source="trainer",icon="test",ranks={{rank=1,level=1},{rank=2,level=10},{rank=3,level=20}}},
   {name="Claw",source="trainer",icon="test",ranks={{rank=1,level=1}}}},
 PET_TEACH_SPELLS={[11]={"Bite",1},[12]={"Bite",2},[13]={"Bite",3},[14]={"Claw",1}},
 TRAINER_SPELLS={[3]={{1,101,"Shot",1,0,false,1},{2,102,"Shot",2,0,false,1}}}}
UnitClass=function() return "Hunter","HUNTER",3 end
UnitGUID=function() return guid end
IsPlayerSpell=function(id) return id==102 or id==14 end
GetActionInfo=function(i) if i==1 then return "spell",101 end end
OneForAllCharDB={petAbilities={Bite={[2]=true}}}
''')
run = lua.eval('function(s,n) local f,e=loadstring(s); assert(f,e); return f("ForeverUI",n) end')
run((Path(__file__).resolve().parents[1] / 'Trainer.lua').read_text(encoding='utf8'), lua.globals().ns)
lua.execute('''
local t=ns.TrainerGuide
t:ImportPetRanks(); OneForAllCharDB=nil
assert(ns.db.trainerPetRanks[guid].ranks.Bite[2], "migrate previously known ranks")
GetCraftDisplaySkillLine=function() return "Beast Training" end
GetNumCrafts=function() return 2 end
GetCraftInfo=function(i) if i==1 then return "Bite","Rank 3","optimal" else return "Claw","","optimal" end end
t:ScanBeastTraining()
local known=ns.db.trainerPetRanks[guid].ranks
assert(known.Bite[2] and known.Bite[3] and known.Claw[1], "merge Beast Training ranks rather than replace them")
GetCraftDisplaySkillLine=function() return "Alchemy" end
GetCraftInfo=function() return "Bite","Rank 1","optimal" end
t:ScanBeastTraining(); assert(not known.Bite[1], "never read another profession as Beast Training")
t:ScanKnownPetSpells(); assert(known.Claw[1] and not known.Bite[1], "record only confirmed spell IDs")
IsPlayerSpell=function() return true end
t:ScanKnownPetSpells(); assert(not known.Bite[1], "ignore a client that reports all IDs as known")
IsPlayerSpell=function(id) return id==102 or id==14 end
local list=t:BuildLowRanks(); assert(#list==1 and list[1].id==101)
OneForAllDB={qol={lowRankKeep={[101]=true}}}; t:ImportKeptRanks()
assert(#t:BuildLowRanks()==0, "imported intentional downranks are suppressed")
t:ClearKeptRanks(); t:ImportKeptRanks(); assert(#t:BuildLowRanks()==1, "reset kept ranks without reimporting them")
t.frame={IsShown=function() return true end}; t.page="weapons"; t.mode="all"
t:NotifyLowRanks(); t:NotifyLowRanks()
assert(#messages==2, "the same low rank is announced only once after resetting keeps")
t.notifiedRanks={}; messages={}; local timers={}
t.Render=function() end
C_Timer={After=function(_,f) timers[#timers+1]=f end}
local function fire(event) for _,f in ipairs(events[event] or {}) do f(event) end end
fire("TRAINER_SHOW"); fire("SPELLS_CHANGED"); assert(#messages==0, "do not interrupt the trainer")
fire("TRAINER_CLOSED")
while #timers>0 do local f=table.remove(timers,1); f() end
assert(#messages==1, "check for lower ranks after the trainer closes")
fire("SPELLS_CHANGED"); while #timers>0 do local f=table.remove(timers,1); f() end
assert(#messages==1, "do not repeat an unchanged reminder")
guid="Player-other"; assert(not t:KeptRanks()[101] and not ns.db.trainerPetRanks[guid], "knowledge is isolated by character")
''')
print('Pet rank migration and merging, per-character keeps, and deduplicated reminders passed')

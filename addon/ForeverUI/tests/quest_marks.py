"""Exercise tooltip and quest-drop nameplate markers with no external addon."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
events={}; opts={qolQuestMarks=true}
ns={Secret=function() return false end, Opt=function(k) return opts[k] end,
 On=function(k,f) events[k]=f end, IndependentReference={QUEST_DROPS={[123]="201:301"}},
 modules={nameplates={units={}}}}
Enum={TooltipDataLineType={QuestObjective=7}}
C_TooltipInfo={GetUnit=function() return {lines={{type=7,leftText="Boars slain: 2/8"}}} end}
C_QuestLog={GetNumQuestLogEntries=function() return 1 end,
 GetInfo=function() return {questID=200} end,
 GetQuestObjectives=function(q) if q==200 then return {{text="Boars slain: 2/8",type="monster"}} end
   return {{text="Claw: 1/5",type="item",finished=false,numFulfilled=1,numRequired=5}} end,
 GetLogIndexForQuestID=function() return 1 end}
C_Item={GetItemNameByID=function() return "Claw" end}
UnitGUID=function() return "Creature-0-1-2-3-123-001" end
''')
run = lua.eval('function(s,n) local f,e=loadstring(s); assert(f,e); return f("ForeverUI",n) end')
run((Path(__file__).resolve().parents[1] / 'QuestMarks.lua').read_text(encoding='utf-8'), lua.globals().ns)
lua.execute('''
ns.QuestMarks:ReadLog()
local kind, progress=ns.QuestMarks:Objective("nameplate1")
assert(kind=="monster" and progress=="2/8", "use the live kill objective")
C_TooltipInfo.GetUnit=function() return {lines={{type=7,leftText="Boars slain: 8/8"}}} end
kind,progress=ns.QuestMarks:Objective("nameplate1")
assert(kind=="item" and progress=="1/5", "find an active quest drop when the kill objective is finished")
C_Item.GetItemNameByID=function() return nil end
assert(ns.QuestMarks:Objective("nameplate1")==nil, "do not guess which item objective is involved")
C_TooltipInfo.GetUnit=function() error("restricted") end
assert(ns.QuestMarks:Objective("nameplate1")==nil, "restricted tooltip data must not crash or create a false mark")
''')
print('Quest marks use known live objectives and avoid unverified results')

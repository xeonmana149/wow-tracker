"""Quest automation takes an NPC's quests one after another, safely."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
events={}; opts={qolAutoQuestAccept=true,qolAutoQuestTurnIn=true}; selected={}; shift=false; clock=0
active={}; available={}; options={}
ns={db={},Secret=function() return false end, Opt=function(k) return opts[k] end,
    On=function(k,f) events[k]=f end,WhenSafe=function(f) f() end}
IsShiftKeyDown=function() return shift end
GetTime=function() return clock end
C_GossipInfo={GetOptions=function() return options end, GetActiveQuests=function() return active end,
    GetAvailableQuests=function() return available end,
    SelectAvailableQuest=function(id) selected[#selected+1]="a"..id end,
    SelectActiveQuest=function(id) selected[#selected+1]="t"..id end}
-- The classic greeting window
greetAvail={}; greetActive={}; complete={}
GetNumAvailableQuests=function() return #greetAvail end
GetAvailableQuestInfo=function(i) local q=greetAvail[i]; return q.trivial, q.freq or 0, q.rep, false, q.id end
GetAvailableTitle=function(i) return greetAvail[i].title end
SelectAvailableQuest=function(i) selected[#selected+1]="ga"..(greetAvail[i].id or greetAvail[i].title) end
GetNumActiveQuests=function() return #greetActive end
GetActiveQuestID=function(i) return greetActive[i] end
SelectActiveQuest=function(i) selected[#selected+1]="gt"..greetActive[i] end
C_QuestLog={IsComplete=function(id) return complete[id] or false end}
''')
run = lua.eval('function(s,n) local f,e=loadstring(s); assert(f,e); return f("ForeverUI",n) end')
run((Path(__file__).resolve().parents[1] / 'QualityOfLife.lua').read_text(encoding='utf8'), lua.globals().ns)
lua.execute('''
local function last() return selected[#selected] end
-- Several quests: the first, then (list reopens after accepting) the next.
available={{questID=11,frequency=0},{questID=12,frequency=0},{questID=13,frequency=0}}
events.GOSSIP_SHOW(); assert(last()=="a11" and #selected==1, "first quest picked")
table.remove(available,1); events.GOSSIP_SHOW(); assert(last()=="a12", "then the next one")
table.remove(available,1); events.GOSSIP_SHOW(); assert(last()=="a13" and #selected==3, "and the next, all in a row")
-- A quest the game didn't give (still listed) isn't picked again for 15 seconds.
events.GOSSIP_SHOW(); assert(#selected==3, "no loop on a quest that stays listed")
clock=20; events.GOSSIP_SHOW(); assert(#selected==4, "tried again later")
-- Beside other dialogue options (an innkeeper with quests), quests are still picked.
clock=100; available={{questID=14,frequency=0}}; options={{type="vendor"}}; events.GOSSIP_SHOW(); assert(last()=="a14", "quests picked beside other options")
options={}
-- Left alone: repeatable, daily, trivial.
available={{questID=21,frequency=1},{questID=22,repeatable=true},{questID=23,frequency=0,isTrivial=true}}
local n=#selected; events.GOSSIP_SHOW(); assert(#selected==n, "skip repeatable, daily and grey quests")
-- Turn-ins first, only finished ones.
available={{questID=31,frequency=0}}; active={{questID=32,isComplete=false},{questID=33,isComplete=true}}
events.GOSSIP_SHOW(); assert(last()=="t33", "a finished turn-in comes before new quests")
active={{questID=32,isComplete=false}}; events.GOSSIP_SHOW(); assert(last()=="a31", "an unfinished one is skipped")
-- Shift pauses.
active={}; available={{questID=41,frequency=0}}; shift=true; n=#selected; events.GOSSIP_SHOW(); assert(#selected==n, "Shift pauses")
shift=false
-- Accept only, no turn-in.
opts.qolAutoQuestTurnIn=false; available={}; active={{questID=51,isComplete=true}}; n=#selected; events.GOSSIP_SHOW(); assert(#selected==n, "turn-in off leaves turn-ins")
opts.qolAutoQuestTurnIn=true; active={}
-- Classic greeting window: in a row, turn-ins first, grey skipped, titles when no ID.
greetAvail={{id=61},{id=62,trivial=true},{id=63}}; greetActive={64}; complete[64]=true
events.QUEST_GREETING(); assert(last()=="gt64", "greeting: finished turn-in first")
greetActive={}; events.QUEST_GREETING(); assert(last()=="ga61", "greeting: first quest")
table.remove(greetAvail,1); events.QUEST_GREETING(); assert(last()=="ga63", "greeting: grey skipped, next quest")
greetAvail={{title="Wanted: Hogger"}}; events.QUEST_GREETING(); assert(last()=="gaWanted: Hogger", "greeting: works without quest IDs")
n=#selected; events.QUEST_GREETING(); assert(#selected==n, "greeting: no loop")
opts.qolAutoQuestAccept=false; opts.qolAutoQuestTurnIn=false; clock=1000; greetAvail={{id=71}}
n=#selected; events.QUEST_GREETING(); events.GOSSIP_SHOW(); assert(#selected==n, "off means off")
''')
print('Quest automation takes quests in a row, turn-ins first, skipping repeatable, grey and Shift')

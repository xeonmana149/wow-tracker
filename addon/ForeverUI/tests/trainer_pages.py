"""Exercise weapon, pet, and branching class-quest trainer pages offline."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
ns={db={},Secret=function() return false end,On=function() end,OnOptional=function() end}
UnitClass=function() return "Warrior","WARRIOR",1 end
UnitRace=function() return "Orc","Orc",2 end
UnitFactionGroup=function() return "Horde" end
IsPlayerSpell=function(id) return id==196 end
C_QuestLog={IsQuestFlaggedCompleted=function(id) return id==100 end,
    GetLogIndexForQuestID=function(id) return id==101 and 1 or nil end}
ns.IndependentReference={
 CLASS_WEAPONS={WARRIOR={0,19}}, WEAPON_SKILL_NAME={[0]="Axes",[19]="Wands"},
 WEAPON_SKILL_SPELL={[0]=196,[19]=5009}, WEAPON_SKILL_ICON={[0]="INV_Axe_01"},
 WEAPON_TRAINERS={{name="Horde smith",side="H",city="Orgrimmar",map=1454,x=80,y=20,skills={0}},
     {name="Alliance smith",side="A",city="Stormwind",map=1453,x=60,y=30,skills={0}}},
 PET_TRAINERS={{name="Hunter trainer",side="H",city="Mulgore",map=1412,x=48,y=64},
     {name="Other trainer",side="A",city="Teldrassil",map=1438,x=50,y=50},
     {name="Neutral trainer",side="AH",city="Zephras",map=2521,x=55,y=55}},
 PET_TEACH_SPELLS={[500]={"Armor",1}}, PET_ABILITIES={{name="Armor",icon="x",source="trainer",effect="Armor bonus",ranks={{rank=1,level=4,tp=2,desc="Bonus"}}}},
 CLASS_QUESTS={milestones={WARRIOR={{"Stance",10,"icon","101/100/102"}}},
  quests={[100]="First|10|2|||Giver A|1411|40|50",[101]="Second|10|2|100||Giver B|1411|41|51",
          [102]="Other race|10|1|||Other|1429|20|20"}}}
''')
run = lua.eval('function(s,n) local f,e=loadstring(s); assert(f,e); return f("ForeverUI",n) end')
run((Path(__file__).resolve().parents[1] / 'Trainer.lua').read_text(encoding='utf8'), lua.globals().ns)
lua.execute('''
local t=ns.TrainerGuide
local rows=t:BuildWeaponLines()
assert(#rows==2 and rows[1].text:find("Known"), "show class weapon skills and known status")
t.expanded["weapon:WARRIOR:0"]=true; rows=t:BuildWeaponLines()
assert(#rows==3 and rows[2].name=="Horde smith" and rows[2].mapID==1454, "only show your faction's weapon trainer and location")
t.petView="trainers"; rows=t:BuildPetLines()
assert(#rows==2 and rows[1].name~="Other trainer" and rows[2].name~="Other trainer", "show faction and neutral pet trainers")
t.petView="abilities"; rows=t:BuildPetLines()
assert(#rows==1 and rows[1].name=="Armor" and rows[1].description:find("Not recorded") and rows[1].encyclopediaKey=="ability:Armor", "do not invent pet ability knowledge")
rows=t:BuildQuestLines(); assert(#rows==1 and rows[1].toggle, "quest milestones start collapsed")
t.expanded[rows[1].toggle]=true; rows=t:BuildQuestLines()
assert(#rows==3 and rows[2].questID==100 and rows[3].questID==101, "race-filter and order prerequisites before dependent quests")
assert(rows[2].description:find("flagged complete") and rows[3].description:find("In quest log"), "show quest statuses without inventing completion")
assert(rows[3].preAny=="100" and rows[3].mapID==1411 and rows[3].giver=="Giver B", "retain branch prerequisites and map coordinates")
''')
print('Weapon trainers, pet training and branching class quest pages passed')

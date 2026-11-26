"""Preserve OneForAll wishes and gear weights without overwriting user choices."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
events={}; messages={}; guid="Player-A"
ns={db={encyclopediaWishlists={["Player-A"]={["101"]={name="Kept name"}}}},
 Secret=function() return false end, Print=function(x) messages[#messages+1]=x end,
 On=function(k,f) events[k]=events[k] or {}; table.insert(events[k],f) end,
 IndependentReference={ENCHANT_OPTIONS={{s=77,e=33,n="Test enchant"},{i=44,e=55,n="Test kit"}}}}
OneForAllCharDB={wishlist={[101]=true,[102]=true,["ench:s77"]=true,["ench:i44"]=true,["ench:s999"]=true},
    gearSpec="custom",gearCustom={str=1.5,stamina=2},gearCustomV=2}
UnitGUID=function() return guid end
C_Item={GetItemInfo=function(id) return "Item "..id end}
wipe=function(t) for k in pairs(t) do t[k]=nil end end
CreateFrame=function() return {RegisterEvent=function() end,SetScript=function() end} end
''')
run = lua.eval('function(s,n) local f,e=loadstring(s); assert(f,e); return f("ForeverUI",n) end')
for name in ('IndependentGearValue.lua', 'Encyclopedia.lua'):
    run((root / name).read_text(encoding='utf8'), lua.globals().ns)
lua.execute('''
local function login() for _,fn in ipairs(events.PLAYER_LOGIN or {}) do fn("PLAYER_LOGIN") end end
login()
local wishes=ns.db.encyclopediaWishlists[guid]
assert(wishes["101"].name=="Kept name" and wishes["102"], "merge items without overwriting existing wishes")
assert(wishes["enchant:spell:77"].option.e==33 and wishes["enchant:item:44"].option.e==55, "migrate matched enchant wishes")
assert(ns.db.encyclopediaLegacyWishUnresolved[guid]["ench:s999"] and #messages==1, "retain and report unresolved wishes")
local settings=ns.db.encyclopediaEngine.characters[guid]
assert(settings.gearSpec=="custom" and settings.gearCustom.str==1.5 and settings.gearCustomV==2, "migrate custom weights")
wishes["102"]=nil; settings.gearSpec=nil; login()
assert(not wishes["102"] and settings.gearSpec==nil, "do not resurrect changes after the initial import")
guid="Player-B"; login()
assert(ns.db.encyclopediaWishlists[guid]["102"] and ns.db.encyclopediaEngine.characters[guid].gearCustom.str==1.5, "migrate per character")
guid="Player-C"; ns.db.encyclopediaEngine.characters[guid]={gearCustom={str=9},gearSpecTouched=true}; login()
assert(ns.db.encyclopediaEngine.characters[guid].gearSpec==nil and ns.db.encyclopediaEngine.characters[guid].gearCustom.str==9,
    "preserve an existing custom profile and automatic spec selection")
''')
print('Wishlist, enchant and gear-weight migration preserves per-character choices')

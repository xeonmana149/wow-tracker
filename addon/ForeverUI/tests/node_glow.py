"""Verify the opt-in gather glow preserves the player's interaction settings."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
opts = {}; handlers = {}; cv = {
  SoftTargetInteract="0", SoftTargetNameplateInteract="0", SoftTargetInteractRange="8",
  SoftTargetInteractArc="1", SoftTargetInteractOnlyInRange="1", SoftTargetIconGameObject="0",
  GamePadEnable="0" }
ns = {db={}, Opt=function(k) return opts[k] end, On=function(k,f) handlers[k]=f end, Err=function(_,msg) error(msg) end}
C_CVar = { GetCVar=function(k) return cv[k] end, SetCVar=function(k,v) cv[k]=tostring(v) end }
CreateFrame = function() return {SetScript=function() end, RegisterEvent=function() end, UnregisterAllEvents=function() end} end
InCombatLockdown = function() return false end
''')
run = lua.eval('function(s,n) local f,e=loadstring(s); assert(f,e); return f("ForeverUI",n) end')
run((Path(__file__).resolve().parents[1] / 'NodeGlow.lua').read_text(encoding='utf-8'), lua.globals().ns)
lua.execute('''
opts.qolNodeGlow=true; ns.NodeGlow.Apply(true)
assert(cv.SoftTargetInteract=="3" and cv.SoftTargetIconGameObject=="1" and cv.SoftTargetInteractRange=="15")
opts.qolNodeGlow=false; ns.NodeGlow.Apply(false)
assert(cv.SoftTargetInteract=="0" and cv.SoftTargetIconGameObject=="0" and cv.SoftTargetInteractRange=="8")
assert(cv.SoftTargetInteractArc=="1" and cv.SoftTargetInteractOnlyInRange=="1")
''')
print('Gather sparkle interaction settings restore correctly')

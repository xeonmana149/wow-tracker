-- Adapted from OneForAll 6.2.12 and Lueur; see Attribution/OneForAll-THIRD-PARTY.txt.
local _, ns = ...

-- Quality of Life "nodeGlow" (5.7.3, user 25.10., off by default): herbs and ore veins sparkle as you come near.
-- Adapted from Lueur 1.4.0 by Armytille (MIT License, see THIRD_PARTY_LICENSES.txt): its idea and its "sparkle"
-- effect, cut down to herbs and ore and without its minimap part (user 25.10.).
-- How: Blizzard's soft targeting always picks ONE thing near you to interact with (the unit "softinteract").
-- With a few game settings it is on all the time and the game gives that object a nameplate; when it is a herb or
-- an ore vein (read from its cursor icon) the sparkle sits on that nameplate. NPCs get nothing: their soft-target
-- nameplate is only switched on for herbs and ore. The settings are saved first and given back when the switch
-- goes off. No key is bound; with an Interact key you can gather the sparkling one.
-- Lean: nothing is registered while the switch is off; the animation only runs while a glow is shown.

local NG = {}
ns.NodeGlow = NG
local ASSET = "Interface\\AddOns\\ForeverUI\\Art\\"
local SOFT = "softinteract"
local sin, cos, sqrt, random, min, max, pi = math.sin, math.cos, math.sqrt, math.random, math.min, math.max, math.pi
local GOLD = { 1.00, 0.76, 0.26 } -- like our quest loot sparkles (user 25.10.: the golden dots)
local SIZE, OFFSET_Y = 120, -45

local function Q() return ns.Opt("qolNodeGlow") end
local function call(fn, ...) if type(fn) ~= "function" then return nil end local ok, a = pcall(fn, ...); if ok then return a end end
local function inCombat() return InCombatLockdown and InCombatLockdown() end

-- Game settings -------------------------------------------------------------------------
-- 6.2.1 (user 08.11.: "nur das aktivieren/deaktivieren das wirklich benoetigt wird", tested in the game, compared with
-- Forever Loot Sparkles 1.3.1): only these. SoftTargetInteract ("Enable Interact Key") and SoftTargetIconGameObject (the
-- interact icons on objects; without them an object gets no nameplate) are the player's settings: switched on only when
-- the option is switched on, never forced again. Not touched any more: SoftTargetIconInteract (icons on NPCs and above
-- nodes = the player's choice, user 08.11. "B"), SoftTargetInteractRangeIsHard and nameplateGameObjectMaxDistance (the
-- game's defaults 0 / 30 work); up to 6.2.0 they were set and are given back once (OLD).
local MANAGED = { "SoftTargetInteract", "SoftTargetNameplateInteract", "SoftTargetInteractRange", "SoftTargetInteractArc",
  "SoftTargetInteractOnlyInRange", "SoftTargetIconGameObject" }
local OLD = { "SoftTargetInteractRangeIsHard", "SoftTargetIconInteract", "nameplateGameObjectMaxDistance" }
local function getCVar(n) return call(C_CVar and C_CVar.GetCVar or GetCVar, n) end
-- only when it differs: every change fires CVAR_UPDATE for Blizzard's frames too
local function setCVar(n, v) local c = getCVar(n); if c ~= nil and c ~= tostring(v) then pcall(C_CVar and C_CVar.SetCVar or SetCVar, n, tostring(v)) end end
local function saved()
  if type(ns.db) ~= "table" then return nil end
  ns.db.nodeGlowState = ns.db.nodeGlowState or {}
  return ns.db.nodeGlowState
end
local pending, gate -- "apply" / "restore" after combat; nameplate switch state (nil = set it again)

-- with a controller the game runs its own interact target (gamepad action bar); our settings changes made Blizzard's
-- bar run as addon code there (Discord 06.11.: "SetPreferredGamepadInteractTarget() blocked") - no sparkle then
-- (user 06.11.: GamePadEnable is 1 also without a controller - a controller has to be connected too)
local function pad()
  if getCVar("GamePadEnable") ~= "1" then return false end
  local ids = C_GamePad and call(C_GamePad.GetAllDeviceIDs)
  return type(ids) == "table" and #ids > 0
end
local restore
-- force: the player switched the option on (or nothing is saved yet) - only then the two player settings are switched on
local function apply(force)
  if inCombat() then pending = force and "force" or (pending or "apply"); return end
  if pad() then restore(); return end
  local d = saved(); if not d then return end
  if not d.nodeGlowCVars then
    force = true
    d.nodeGlowCVars = {}
    for _, n in ipairs(MANAGED) do d.nodeGlowCVars[n] = getCVar(n) or false end
  end
  local s = d.nodeGlowCVars
  -- saved by 6.1.6 / 6.1.7 without it (they left the player's value alone): the value now is still the player's
  if s.SoftTargetInteract == false then s.SoftTargetInteract = getCVar("SoftTargetInteract") or false end
  for _, n in ipairs(OLD) do if s[n] ~= nil then if s[n] ~= false then setCVar(n, s[n]) end; s[n] = nil end end
  if force then
    -- soft targeting for mouse & keyboard too: 0 off, 1 controller only, 2 mouse & keyboard, 3 both (= the game's
    -- "Enable Interact Key" box); with 1 the game finds no nodes without a controller (Discord 06.11.)
    setCVar("SoftTargetInteract", 3)
    setCVar("SoftTargetIconGameObject", 1)      -- without it the game makes no nameplate for objects
  end
  setCVar("SoftTargetInteractRange", 15)
  setCVar("SoftTargetInteractArc", 2)           -- all around you
  setCVar("SoftTargetInteractOnlyInRange", 0)   -- also before you are in reach
  gate = nil
end
restore = function()
  if inCombat() then pending = "restore"; return end
  local d = saved(); if not (d and d.nodeGlowCVars) then return end
  for n, v in pairs(d.nodeGlowCVars) do if v ~= false then setCVar(n, v) end end
  d.nodeGlowCVars = nil
  gate = nil
end
-- the object's nameplate only for herbs and ore
local function setGate(open)
  if open == gate or inCombat() then return end
  gate = open
  setCVar("SoftTargetNameplateInteract", open and 1 or 0)
end

-- What is it --------------------------------------------------------------------------
local probe, cursorIDs
local function kindOf(unit)
  if call(UnitIsGameObject, unit) ~= true then return nil end
  if not probe then
    probe = UIParent:CreateTexture(nil, "BACKGROUND"); probe:Hide()
    cursorIDs = {}
    for file, kind in pairs({ GatherHerbs = "herb", Mine = "ore" }) do
      for _, pre in ipairs({ "", "Unable" }) do
        local id = call(GetFileIDFromPath, "Interface\\Cursor\\" .. pre .. file)
        if id then cursorIDs[id] = kind end
      end
    end
  end
  if not SetUnitCursorTexture or not pcall(SetUnitCursorTexture, probe, unit, nil, true) then return nil end
  local tex = probe:GetTexture()
  if type(tex) == "number" and cursorIDs[tex] then return cursorIDs[tex] end
  local name = type(tex) == "string" and tex:lower() or ""
  if name:find("gather", 1, true) then return "herb" end
  if name:find("mine", 1, true) then return "ore" end
end
-- only for a profession you have (Find Herbs / Find Minerals known)
local FINDER = { herb = { 2383, 8387 }, ore = { 2580, 8388 } }
local function trained(kind)
  local known = (C_SpellBook and C_SpellBook.IsSpellKnown) or IsPlayerSpell or IsSpellKnown
  if not known then return true end
  for _, id in ipairs(FINDER[kind]) do if call(known, id) then return true end end
  return false
end

-- The sparkle (Lueur's "sparkle" effect, simplified) -------------------------------------
local glow = {}
local STARS, DUST = 6, 3
local function layer(file, drawLayer)
  local t = glow.frame:CreateTexture(nil, drawLayer)
  t:SetTexture(ASSET .. file); t:SetBlendMode("ADD"); t:SetPoint("CENTER"); t:SetVertexColor(1, 1, 1, 0)
  return t
end
local function sized(t, w) t:SetSize(max(w, 0.01), max(w, 0.01)) end
local function tint(t, r, g, b, a) t:SetVertexColor(r, g, b, a <= 0 and 0 or (a >= 1 and 1 or a)) end
local function animate(self, elapsed)
  if elapsed > 0.1 then elapsed = 0.1 end
  glow.appear = min(1, glow.appear + elapsed / 0.45)
  glow.phase = glow.phase + elapsed * 2 * pi / 2.5
  glow.spin = glow.spin - elapsed
  local a = 1 - (1 - glow.appear) ^ 3
  local breath = 0.5 + 0.5 * sin(glow.phase)
  local r, g, b = GOLD[1], GOLD[2], GOLD[3]
  sized(glow.shade, SIZE * 1.9); tint(glow.shade, 0, 0, 0, a * 0.28)
  sized(glow.haze, SIZE * (1.55 + 0.12 * breath)); tint(glow.haze, r, g, b, a * 0.5 * (0.85 + 0.15 * breath))
  for i, d in ipairs(glow.dust) do -- motes slowly rising through the light
    local climb = (-glow.spin * 0.14 + i / DUST) % 1
    d:SetPoint("CENTER", self, "CENTER", (i - 2) * SIZE * 0.24 + sin(-glow.spin * 0.9 + i * 2.3) * SIZE * 0.05, (climb - 0.45) * SIZE * 0.8)
    sized(d, SIZE * 0.11); tint(d, r + (1 - r) * 0.55, g + (1 - g) * 0.55, b + (1 - b) * 0.55, a * sin(pi * climb) * 0.75)
  end
  for _, s in ipairs(glow.stars) do -- stars light up somewhere in the disc, fade and come back elsewhere
    s.age = s.age + elapsed
    if s.age >= s.life then
      local angle, reach = random() * 2 * pi, sqrt(random())
      s.x, s.y = cos(angle) * reach, sin(angle) * reach
      s.life, s.scale, s.age = 0.7 + 0.9 * random(), 0.55 + 0.75 * random(), -0.5 * random()
    end
    local shine = s.age > 0 and sin(pi * s.age / s.life) or 0
    s.t:SetPoint("CENTER", self, "CENTER", s.x * SIZE * 0.40, s.y * SIZE * 0.40)
    sized(s.t, SIZE * 0.55 * s.scale * (0.4 + 0.6 * shine))
    tint(s.t, r + (1 - r) * 0.75, g + (1 - g) * 0.75, b + (1 - b) * 0.75, a * shine * 0.85)
  end
end
local function build()
  glow.frame = CreateFrame("Frame"); glow.frame:SetSize(1, 1); glow.frame:Hide()
  glow.shade = layer("nodeglow_glow", "BACKGROUND"); glow.shade:SetBlendMode("BLEND")
  glow.haze = layer("nodeglow_glow", "BACKGROUND")
  glow.dust, glow.stars = {}, {}
  for i = 1, DUST do glow.dust[i] = layer("nodeglow_glow", "ARTWORK") end
  for i = 1, STARS do glow.stars[i] = { t = layer("nodeglow_flare", "OVERLAY"), age = 0, life = 0 } end
end
local function release()
  if not glow.frame then return end
  glow.frame:SetScript("OnUpdate", nil); glow.frame:Hide(); glow.frame:ClearAllPoints(); glow.frame:SetParent(nil)
  glow.anchor = nil
end
local function attach(plate)
  if glow.anchor == plate then return end
  if not glow.frame then build() end
  release()
  local f = glow.frame
  f:SetParent(plate)
  local ok, lvl = pcall(plate.GetFrameLevel, plate)
  if ok and type(lvl) == "number" then f:SetFrameLevel(max(lvl - 1, 0)) end
  f:SetPoint("CENTER", plate, "CENTER", 0, OFFSET_Y)
  if f.SetIgnoreParentAlpha then f:SetIgnoreParentAlpha(true) end
  glow.anchor, glow.appear, glow.phase, glow.spin = plate, 0, 0, random() * 2 * pi
  for _, s in ipairs(glow.stars) do s.age, s.life = 0, 0 end
  f:SetScript("OnUpdate", animate); f:Show()
end

-- Decide ---------------------------------------------------------------------------------
local function evaluate()
  if not Q() then release(); return end
  local kind = kindOf(SOFT)
  if not (kind and trained(kind)) then setGate(false); release(); return end
  setGate(true)
  local plate = C_NamePlate and call(C_NamePlate.GetNamePlateForUnit, SOFT)
  if plate then attach(plate) else release() end -- the nameplate follows with NAME_PLATE_UNIT_ADDED
end

local ev = CreateFrame("Frame")
-- 6.2.1: no more CVAR_UPDATE watching, no forcing after loading screens and no restore at logout (the next login set
-- everything again: many writes, and every write runs Blizzard's handlers as addon code)
-- VARIABLES_LOADED: the account-synced settings from the server can arrive after the login and overwrite ours
local EVENTS = { "PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD",
  "VARIABLES_LOADED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }
-- first session after updating to 6.2.1 (user 08.11.: no ore sparkle until switched off and on): 6.2.0 gave the values back
-- at every logout, the server keeps those and sends them after the login - switch both on again then (once more after
-- 5 s); later sessions keep what is set
local fresh
ev:SetScript("OnEvent", function(_, event, unit)
  if event == "PLAYER_REGEN_DISABLED" then
    -- settings can't change in combat: close the nameplate just before, or killed mobs keep a 0 % nameplate
    setGate(false); release(); return
  end
  if event == "PLAYER_ENTERING_WORLD" or event == "VARIABLES_LOADED" then
    apply(fresh)
    if fresh == true and C_Timer and C_Timer.After then
      fresh = "timer"
      C_Timer.After(5, function() if Q() then apply(true); evaluate() end; fresh = nil end)
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if pending == "restore" then restore() elseif pending then apply(pending == "force") end
    pending = nil
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    local plate = C_NamePlate and call(C_NamePlate.GetNamePlateForUnit, unit)
    if plate and plate == glow.anchor then release() end
    return
  end
  evaluate()
end)
-- the switch: events only while it is on; settings back when it goes off. switched = true when the player flipped it
-- (QoL.On passes the new value), nil at login
function NG.Apply(switched)
  if Q() then
    for _, e in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, e) end
    local d = switched == nil and saved()
    if d and not d.nodeGlow621 then d.nodeGlow621 = true; fresh = true end
    apply(switched ~= nil or fresh ~= nil); evaluate()
  else
    ev:UnregisterAllEvents(); release(); restore()
  end
end
NG._kindOf, NG._glow = kindOf, glow -- tests

ns.On("PLAYER_LOGIN", function()
  if Q() then local ok, err = pcall(NG.Apply); if not ok then ns.Err("NodeGlow", err) end end
end)

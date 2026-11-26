-- Adapted from OneForAll 6.2.12 UI/GearValue.lua (GPL-3.0-or-later).
-- Original source and notices: Attribution/OneForAll-6.2.12-reference-source.zip.
local _, ns = ...
local FLT = ns.IndependentReference
local OneForAllCharDB = {}
ns.On("PLAYER_LOGIN", function()
    ns.db.encyclopediaEngine = ns.db.encyclopediaEngine or {}
    local db = ns.db.encyclopediaEngine
    db.characters = db.characters or {}
    local id
    if UnitGUID then local ok, value = pcall(UnitGUID, "player"); if ok and type(value) == "string" and not ns.Secret(value) then id = value end end
    if not id and UnitName then local ok, value = pcall(UnitName, "player"); if ok and type(value) == "string" and not ns.Secret(value) then id = value end end
    id = id or "player"
    db.characters[id] = db.characters[id] or {}
    OneForAllCharDB = db.characters[id]
    local previous = _G.OneForAllCharDB
    if type(previous) == "table" and not OneForAllCharDB.gearReferenceImported
        and (previous.gearSpec ~= nil or type(previous.gearCustom) == "table") then
        if OneForAllCharDB.gearSpec == nil and OneForAllCharDB.gearCustom == nil and not OneForAllCharDB.gearSpecTouched
            and not ns.Secret(previous.gearSpec) and (type(previous.gearSpec) == "number" or previous.gearSpec == "custom") then
            OneForAllCharDB.gearSpec = previous.gearSpec
        end
        if OneForAllCharDB.gearCustom == nil and type(previous.gearCustom) == "table" then
            local copied = {}
            for key, value in pairs(previous.gearCustom) do
                if type(key) == "string" and type(value) == "number" and not ns.Secret(value) then copied[key] = value end
            end
            OneForAllCharDB.gearCustom = copied
            if type(previous.gearCustomV) == "number" and not ns.Secret(previous.gearCustomV) then OneForAllCharDB.gearCustomV = previous.gearCustomV end
        end
        OneForAllCharDB.gearReferenceImported = true
    end
end)
local L = FLT.L or setmetatable({}, { __index = function(_, k) return k end }) -- (tests without Locales)

-- Gear Planner "Value" (5.6.3): sum of the item's stats x the stat weights of the active spec (the talent tree
-- with the most points; user 16.10.: standard specs only, no choice yet). Weights: Data/GearWeights.lua (SimGear
-- Forever + our overrides, 6.2.6): level 60 = the raid profile, below 60 = the spec's leveling curve at the player's level,
-- no talents = the class's general leveling curve. Ratings are turned into % first (GEAR_RATING).
-- Compared with what is worn: rings / trinkets with the weaker one, two-handers with main + off hand; the % is of
-- the whole gear's Value (6.2.5).
-- Lean: weights are built once per spec / level / talent change, item values are cached per item and slot,
-- worn values per slot until the gear changes. Nothing runs until a tooltip or the planner asks.

local GV = {}
FLT.GearValue = GV
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local KEYS, RATING = FLT.GEAR_STAT_KEYS or {}, FLT.GEAR_RATING or {}
local W, specName, autoTree -- current weights; the talent tree with the most points
local values = {}  -- [slot][itemID] = value
local worn = {}    -- [slot] = value of the worn item (false = empty)
local speeds = {}  -- [itemID] = weapon speed (tooltip data)
local classOK = {} -- [itemID] = false when the item has "Classes: ..." without the player's class
local gearSum      -- Value of everything worn (6.2.5: the % is against the whole gear); nil = count again
-- GV.gen goes up whenever a Value can change (gear, weights, spec, level); the Gear Planner keeps its results until then
-- (6.2.10-beta2: "All slots" judged thousands of items on every redraw)
local function resetWorn() wipe(worn); gearSum = nil; GV.gen = (GV.gen or 0) + 1 end

local function curveAt(curve, level)
  local n = #curve
  local a, b = curve[1], curve[n]
  if level <= a[1] then b = a
  elseif level >= b[1] then a = b
  else
    for i = 1, n - 1 do
      if level >= curve[i][1] and level <= curve[i + 1][1] then a, b = curve[i], curve[i + 1]; break end
    end
  end
  local t = (b[1] > a[1]) and ((level - a[1]) / (b[1] - a[1])) or 0
  local out = {}
  for k, v in pairs(a[2]) do out[k] = v end
  for k in pairs(b[2]) do out[k] = out[k] or 0 end
  for k, va in pairs(out) do
    local v = va + ((b[2][k] or 0) - va) * t
    out[k] = (v > 0 and v < 0.02) and 0 or v
  end
  return out
end

-- own weights from before 6.2.5 had no melee / off-hand DPS fields: they count as before (dps; off hand half of it)
local function migrateCustom(c)
  if OneForAllCharDB.gearCustomV then return end
  if c.dpsmelee == nil then c.dpsmelee = tonumber(c.dps) end
  if c.dpsoh == nil and c.dpsmelee then c.dpsoh = c.dpsmelee * 0.5 end
  OneForAllCharDB.gearCustomV = 2
end

local function buildWeights()
  local _, cls = UnitClass("player")
  local data = FLT.GEAR_WEIGHTS and FLT.GEAR_WEIGHTS[cls]
  if not data then return end
  local ok, pts = pcall(FLT.TalentPointsPerTree or function() end)
  if not ok then pts = nil end
  local tree, best = nil, 0
  for i = 1, 3 do if pts and (pts[i] or 0) > best then tree, best = i, pts[i] end end
  autoTree = tree
  -- chosen in the Gear Planner (per character, user 18.10.); nil = the active spec
  local pick = type(OneForAllCharDB) == "table" and OneForAllCharDB.gearSpec
  -- own weights (5.7.3, Discord sparkledooks, user 27.10.): OneForAllCharDB.gearCustom, edited in the planner
  local custom = pick == "custom" and type(OneForAllCharDB.gearCustom) == "table" and OneForAllCharDB.gearCustom
  if custom then
    migrateCustom(custom)
    -- only what the editor shows counts (6.2.5: hidden keys of the copied spec - melee / off-hand weapon DPS, speed,
    -- health - counted although the editor did not show them; its "Weapon DPS" did nothing on melee weapons)
    local w = {}
    for _, st in ipairs(FLT.GEAR_CUSTOM_STATS or {}) do local v = tonumber(custom[st[1]]); if v then w[st[1]] = v end end
    -- melee weapon DPS only from its own fields (no fallback to the ranged / wand "dps")
    w.dpsmelee, w.dpsoh = w.dpsmelee or 0, w.dpsoh or 0
    W, specName = w, "Custom"
    wipe(values); resetWorn()
    return
  end
  if pick and data.specs[pick] then tree = pick end
  local spec = tree and data.specs[tree]
  local level = UnitLevel("player") or 1
  local w
  if spec and level >= 60 then
    w = {}; for k, v in pairs(spec.raid) do w[k] = v end
  else
    w = curveAt(data.curves[spec and spec.curve or "Leveling"] or data.curves.Leveling, level)
  end
  -- Forever has one hit and one crit rating for melee and spells (as Gear Judge does)
  w.hit = math.max(w.hit or 0, w.shit or 0); w.crit = math.max(w.crit or 0, w.scrit or 0)
  W, specName = w, spec and spec.name or "Leveling"
  wipe(values); resetWorn()
end
function GV.SpecName() if not W then buildWeights() end return specName end
-- the weights of a spec (nil = the active one) at the player's level, as the Value would use them
local function specWeights(i)
  local db = type(OneForAllCharDB) == "table" and OneForAllCharDB
  if not db then return {} end
  local keep = db.gearSpec
  db.gearSpec = i; W = nil; buildWeights()
  local w = {}; for k, v in pairs(W or {}) do w[k] = v end
  -- the weapon DPS weights as they count (6.2.5): main hand = dpsmelee, else dps; off hand = dpsoh, else half of it
  local melee = w.dpsmelee or w.dps or 0
  w.dpsmelee = melee; w.dpsoh = w.dpsoh or melee * 0.5
  local out = {}; for k, v in pairs(w) do if v ~= 0 then out[k] = math.floor(v * 100 + 0.5) / 100 end end
  db.gearSpec = keep; W = nil
  return out
end
-- own weights: created from the active spec the first time
function GV.CustomWeights()
  if type(OneForAllCharDB) ~= "table" then return {} end
  if type(OneForAllCharDB.gearCustom) ~= "table" then OneForAllCharDB.gearCustom = specWeights(nil); OneForAllCharDB.gearCustomV = 2
  else migrateCustom(OneForAllCharDB.gearCustom) end
  return OneForAllCharDB.gearCustom
end
function GV.SetCustomWeight(k, v)
  local c = GV.CustomWeights()
  v = tonumber(v); c[k] = (v and v ~= 0) and v or nil
  if OneForAllCharDB.gearSpec == "custom" then GV.SetSpec("custom") end
end
-- start again from a spec's weights (nil = the active spec)
function GV.ResetCustom(i)
  if type(OneForAllCharDB) ~= "table" then return end
  OneForAllCharDB.gearCustom = specWeights(i); OneForAllCharDB.gearCustomV = 2
  if OneForAllCharDB.gearSpec == "custom" then GV.SetSpec("custom") end
end
-- the planner's spec drop-down: the class's three specs, the one in use (nil = active spec) and the active one
function GV.Specs()
  if not W then buildWeights() end
  local _, cls = UnitClass("player")
  local data = FLT.GEAR_WEIGHTS and FLT.GEAR_WEIGHTS[cls]
  local pick = type(OneForAllCharDB) == "table" and OneForAllCharDB.gearSpec or nil
  return data and data.specs or {}, pick, autoTree
end
function GV.SetSpec(i)
  if type(OneForAllCharDB) ~= "table" then return end
  OneForAllCharDB.gearSpec, OneForAllCharDB.gearSpecTouched = i, true
  W = nil; wipe(values); resetWorn()
  if FLT.GearMarks and FLT.GearMarks.Refresh then FLT.GearMarks.Refresh() end
end

-- weapon speed is not in GetItemStats: read it once from the item's tooltip data
local function weaponSpeed(id)
  local s = speeds[id]
  if s ~= nil then return s or nil end
  s = false
  local data = type(C_TooltipInfo) == "table" and C_TooltipInfo.GetItemByID and C_TooltipInfo.GetItemByID(id)
  for _, line in ipairs(data and data.lines or {}) do
    local v = (line.rightText or ""):match("(%d+[%.,]%d+)")
    if v and (line.rightText or ""):find(SPEED or "Speed", 1, true) then s = tonumber((v:gsub(",", "."))); break end
  end
  speeds[id] = s
  return s or nil
end

-- class-only items ("Classes: Warlock"): no Value for other classes (user 23.10.: arrow on a warlock item for a priest)
local classPat
local function forMyClass(id)
  local ok = classOK[id]
  if ok ~= nil then return ok end
  local data = type(C_TooltipInfo) == "table" and C_TooltipInfo.GetItemByID and C_TooltipInfo.GetItemByID(id)
  if not (data and data.lines and data.lines[1]) then return true end -- no data yet: ask again later
  classPat = classPat or ("^" .. (type(ITEM_CLASSES_ALLOWED) == "string" and ITEM_CLASSES_ALLOWED or "Classes: %s"):gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%s", "(.+)") .. "$")
  ok = true
  for _, line in ipairs(data.lines) do
    local list = (line.leftText or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match(classPat)
    if list then
      local _, cls = UnitClass("player")
      local m = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls] or UnitClass("player")
      local f = LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[cls]
      ok = false
      for name in list:gmatch("[^,]+") do
        name = name:match("^%s*(.-)%s*$")
        if name == m or name == f then ok = true; break end
      end
      break
    end
  end
  classOK[id] = ok
  return ok
end

-- SimGear's weapon speed (6.2.6, Score.speedFactor): its spdmh / spdoh / spdrg = % of the weapon DPS value per second
-- above the kind's normalized speed, the speed clamped to what SimGear simmed for that kind
local SPEED_KIND = { twoHand = { 3.3, 2.8, 3.9 }, oneHand = { 2.4, 1.5, 2.9 }, dagger = { 1.7, 1.3, 1.9 }, ranged = { 2.8, 2.0, 3.2 } }
local function speedBonus(dpsValue, slot, id)
  local pct = (slot == 16 and W.spdmh) or (slot == 17 and W.spdoh) or (slot == 18 and W.spdrg)
  if not pct or pct == 0 or dpsValue <= 0 then return 0 end
  local sp = weaponSpeed(id)
  if not sp then return 0 end
  local kind = "ranged"
  if slot ~= 18 then
    local info = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    local _, _, _, loc, _, classID, subID
    if info then _, _, _, loc, _, classID, subID = info(id) end
    kind = (loc == "INVTYPE_2HWEAPON" and "twoHand") or (classID == 2 and subID == 15 and "dagger") or "oneHand"
  end
  local k = SPEED_KIND[kind]
  return dpsValue * pct / 100 * (math.min(math.max(sp, k[2]), k[3]) - k[1])
end

local function score(stats, slot, id, isWand)
  local total, dpsValue = 0, 0
  for k, v in pairs(stats) do
    local s = KEYS[k]
    if s and type(v) == "number" then
      local wk = s
      if s == "dps" then
        if slot == 17 and W.dpsoh then wk = "dpsoh"
        elseif (slot == 16 or slot == 17) and W.dpsmelee then wk = "dpsmelee"
        elseif isWand and W.dpswand then wk = "dpswand" end
      end
      local w = W[wk] or 0
      -- Forever has one hit and one crit for melee and spells (as Gear Judge): "spell hit" / "spell crit" on an item
      -- count at the higher weight too (6.1.6, Discord 06.11.: an Enhancement Shaman's spell crit counted 5.3 instead
      -- of 40.5 per 1 %; also for own weights)
      if s == "hit" or s == "shit" then w = math.max(W.hit or 0, W.shit or 0)
      elseif s == "crit" or s == "scrit" then w = math.max(W.crit or 0, W.scrit or 0) end
      -- spell power also heals: it counts with the higher of the two weights, not with both (Discord Nimair 05.11.:
      -- the leveling healer weights have both, and spell power counted 43.6 + 20)
      if k == "ITEM_MOD_SPELL_POWER_SHORT" then w = math.max(w, W.heal or 0) end
      if w > 0 then
        local val = RATING[s] and v / RATING[s] or v
        if slot == 17 and s == "dps" and wk ~= "dpsoh" then val = val * 0.5 end
        total = total + val * w
        if s == "dps" then dpsValue = dpsValue + val * w end
      end
    end
  end
  -- weapon speed: the main hand's weight for the main hand, the off hand's own one (speedoh) for the off hand
  -- (6.2.3, Discord Jax 09.11.: the main-hand speed weight counted for the off hand too)
  -- a negative weight = fast weapons are better: |weight| x (4.0 - speed), as Gear Judge does (6.2.5, own weights)
  local wsp = (slot == 16 and W.speed) or (slot == 17 and W.speedoh) or 0
  if wsp ~= 0 and stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT then
    local sp = weaponSpeed(id)
    if sp then total = total + (wsp > 0 and sp * wsp or -wsp * math.max(0, 4 - sp)) end
  end
  return total + speedBonus(dpsValue, slot, id)
end

-- Value of an enchant / armor kit / ... (FLT.ENCHANTS stats) on the item in a slot; nil = no Value (procs and
-- other effects). Percent values become ratings, flat weapon damage becomes DPS with the weapon's speed.
local estats = {} -- reused
function GV.EnchantValue(eid, slot, itemID)
  local e = FLT.ENCHANTS and FLT.ENCHANTS[eid]
  if not e or e[3] then return nil end
  if not W then buildWeights() end
  if not W then return nil end
  wipe(estats)
  for k, v in pairs(e[2]) do
    local pk = k:match("^PCT_(.+)$")
    if pk then
      local s = KEYS[pk]; estats[pk] = (estats[pk] or 0) + v * (s and RATING[s] or 1)
    elseif k == "WEAPON_DAMAGE" then
      local sp = itemID and weaponSpeed(itemID)
      if sp and sp > 0 then estats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT = (estats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT or 0) + v / sp end
    elseif KEYS[k] then estats[k] = (estats[k] or 0) + v end
  end
  local cid, sub
  if itemID and GetItemInfoInstant then cid, sub = select(6, GetItemInfoInstant(itemID)) end
  return score(estats, slot, itemID, cid == 2 and sub == 19)
end

local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
-- value of an item in a slot; nil while the client has no data for it yet
local function itemValue(id, slot, link)
  if not W then buildWeights() end
  if not W or not getStats then return nil end
  local cache = values[slot]
  if not cache then cache = {}; values[slot] = cache end
  -- by link when there is one: a worn "of the Eagle" item has stats its bare item ID lacks
  local key = link or id
  local v = cache[key]
  if v then return v end
  if not (GetItemInfo and GetItemInfo(id)) then return nil end
  local stats = getStats(link or ("item:" .. id))
  if not stats then return nil end
  local _, _, _, _, _, cid, sub = GetItemInfoInstant(id)
  v = score(stats, slot, id, cid == 2 and sub == 19)
  cache[key] = v
  return v
end

-- the item's own stats only: the enchant is taken out of the link (user 23.10.), its random bonus stays
local function bare(link) return type(link) == "string" and (link:gsub("(item:%d+):%d*", "%1:0", 1)) or nil end
local function wornValue(slot)
  local v = worn[slot]
  if v ~= nil then return v end
  local link = GetInventoryItemLink("player", slot)
  if not link then worn[slot] = 0; return 0 end
  link = bare(link)
  local id = tonumber(link:match("item:(%d+)"))
  v = id and itemValue(id, slot, link)
  if v then worn[slot] = v end
  return v
end


local function slotFor(loc, slots)
  if loc == "INVTYPE_WEAPONOFFHAND" then return 17 end
  return slots[1]
end

-- Set bonuses (6.2.2, user 09.11.: "kann der gearplaner auch set-boni einberechnen?"): Data/ItemSets.lua lists the
-- sets with plain stat bonuses (from the client). Putting an item on can lose a bonus of the worn set (3/5 -> 2/5) or
-- complete one: the Value of the bonuses before and after counts into the change. Procs are not in the data.
local setWorn -- [setID] = pieces worn; nil = count again (gear changed)
local function wornSets()
  if setWorn then return setWorn end
  setWorn = {}
  local S = FLT.ITEM_SETS
  if not (S and GetInventoryItemID) then return setWorn end
  for slot = 1, 19 do
    local id = GetInventoryItemID("player", slot)
    local set = id and S.items[id]
    if set then setWorn[set] = (setWorn[set] or 0) + 1 end
  end
  return setWorn
end
local sstats = {} -- reused
local function bonusValue(set, pieces)
  local list = FLT.ITEM_SETS.bonus[set]
  if not list or pieces < 2 then return 0 end
  wipe(sstats)
  for _, b in ipairs(list) do
    if b[1] <= pieces then
      for k, v in pairs(b[2]) do
        local pk = k:match("^PCT_(.+)$")
        if pk then local st = KEYS[pk]; sstats[pk] = (sstats[pk] or 0) + v * (st and RATING[st] or 1)
        else sstats[k] = (sstats[k] or 0) + v end
      end
    end
  end
  return score(sstats, 0, nil, false)
end
-- change of the set bonuses when the item `id` replaces the worn items in `slots` (nil = nothing)
local function setDelta(id, slots)
  local S = FLT.ITEM_SETS
  if not S then return 0 end
  local newSet = S.items[id]
  local old = {}
  for _, sl in ipairs(slots) do
    local w = GetInventoryItemID and GetInventoryItemID("player", sl)
    local set = w and S.items[w]
    if set then old[set] = (old[set] or 0) + 1 end
  end
  if not newSet and not next(old) then return 0 end
  local counts, d = wornSets(), 0
  local touched = {}
  if newSet then touched[newSet] = true end
  for set in pairs(old) do touched[set] = true end
  for set in pairs(touched) do
    local before = counts[set] or 0
    local after = before - (old[set] or 0) + (set == newSet and 1 or 0)
    if after ~= before then d = d + bonusValue(set, after) - bonusValue(set, before) end
  end
  return d
end

-- Value of an item and the change against what is worn: value, delta (nil = no data yet / not gear). With the link the
-- random bonus counts (user 05.11.: "... of the Bear" in the bags was valued without its stats - always a downgrade)
function GV.Upgrade(id, link)
  local _, _, _, loc, _, cid, sub = GetItemInfoInstant(id)
  local slots = loc and FLT.GEAR_LOC_SLOTS and FLT.GEAR_LOC_SLOTS[loc]
  if not slots then return nil end
  local slot = slotFor(loc, slots)
  link = link and tonumber(link:match("item:(%d+)")) == id and bare(link) or nil
  local v = itemValue(id, slot, link)
  if not v or not forMyClass(id) then return nil end
  for _, s in ipairs(slots) do
    if GetInventoryItemID and GetInventoryItemID("player", s) == id then return v, 0, true end
  end
  -- with a two-hander worn an off-hand item (shield, held item, off-hand weapon) has nothing to compare with - it would
  -- always be "slot empty" (user 06.11.: every shield an upgrade): no Value
  if loc == "INVTYPE_SHIELD" or loc == "INVTYPE_HOLDABLE" or loc == "INVTYPE_WEAPONOFFHAND" then
    local mh = GetInventoryItemID and GetInventoryItemID("player", 16)
    if mh and select(4, GetItemInfoInstant(mh)) == "INVTYPE_2HWEAPON" then return v end
  end
  local base, replaced, cover
  if loc == "INVTYPE_2HWEAPON" then
    -- shield tanks (Protection warriors and paladins) need the shield: a two-hander is no upgrade for them (6.2.5,
    -- Discord 11.11., as Gear Judge does) - unless they wear one already
    local _, cls = UnitClass("player")
    if (cls == "WARRIOR" or cls == "PALADIN") and GV.SpecName() == "Protection" then
      local mh = GetInventoryItemID and GetInventoryItemID("player", 16)
      if not (mh and select(4, GetItemInfoInstant(mh)) == "INVTYPE_2HWEAPON") then return v end
    end
    local a, b = wornValue(16), wornValue(17)
    base = a and b and (a + b); cover = { 16, 17 }
  elseif #slots == 2 and (loc ~= "INVTYPE_WEAPON" or (FLT.CanDualWield() and select(6, GetItemInfoInstant(GetInventoryItemID("player", 17) or 0)) == 2)) then
    local a, b = wornValue(slots[1]), wornValue(slots[2])
    if a and b then
      -- the item is valued for each slot it can go to: main hand and off hand weigh weapon DPS very differently (6.2.3,
      -- Discord Jax 09.11.: a weaker dagger was valued as a main hand against the worn off-hand dagger -> "Upgrade 70%").
      -- It replaces where it gains most - in Value, not in % of the slot (6.2.5: a strong main hand was compared with a
      -- weak off hand, whose small Value made any gain a big %); rings / trinkets (same gain): the weaker worn one.
      local va, vb = itemValue(id, slots[1], link), itemValue(id, slots[2], link)
      if not (va and vb) then return v end
      local useA
      if a <= 0 or b <= 0 then useA = a <= 0
      else
        local ga, gb = va - a, vb - b
        useA = ga > gb or (ga == gb and a <= b)
      end
      if useA then v, base, replaced = va, a, slots[1] else v, base, replaced = vb, b, slots[2] end
      cover = { replaced } -- named in the tooltip
    end
  else
    base = wornValue(slot); cover = { slot }
  end
  if not base then return v end
  -- the delta is the item alone; 6th value: what set bonuses add / take on top (shown as an own tooltip line)
  return v, v - base, false, base, replaced, setDelta(id, cover)
end

-- the Value of everything worn, active set bonuses included; nil while an item has no data yet
local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 } -- no shirt, no tabard
local function gearTotal()
  if gearSum then return gearSum end
  local t = 0
  for _, s in ipairs(GEAR_SLOTS) do
    local v = wornValue(s)
    if not v then return nil end
    t = t + v
  end
  if FLT.ITEM_SETS then for set, n in pairs(wornSets()) do t = t + bonusValue(set, n) end end
  gearSum = t
  return t
end
GV.Total = gearTotal
-- "2.4" / "2,4" (the client's decimal separator), from 10 % on without decimals
function GV.Pct(p)
  local s = string.format(p >= 9.95 and "%.0f" or "%.1f", p)
  local sep = type(DECIMAL_SEPERATOR) == "string" and DECIMAL_SEPERATOR or "."
  return sep ~= "." and (s:gsub("%.", sep)) or s
end

-- What players see is the change in % of the whole gear's Value (6.2.5, user 11.11.: "vergleich zum gesamten gear";
-- before it was % of the replaced item, so a weak worn item made every small gain huge): kind, pct
-- kind: "up" / "down" / "same" / "new" (nothing worn there, or it has no value) / "worn"; nil = no data yet;
-- third value: the slot compared with when there are two (rings, trinkets, dual wield)
-- 4th / 5th value: kind and % with the set bonuses it loses or completes (user 09.11.: the arrows stay for the item
-- alone - "theoretically better", worth taking along - and the tooltip shows the set line too); nil = no set change
local function kindOf(d, tot)
  local pct = d / tot * 100
  if pct >= 0.1 then return "up", pct elseif pct <= -0.1 then return "down", -pct end
  return "same"
end
function GV.Change(id, link)
  local v, d, equipped, base, replaced, sd = GV.Upgrade(id, link)
  if not v then return nil end
  if equipped then return "worn" end
  if not d then return nil end
  local tot = gearTotal()
  if not base or base <= 0 then
    -- nothing (of Value) worn there: "new", with the % when there is other gear to compare with
    if v <= 0 then return "same" end
    return "new", tot and tot > 0 and v / tot * 100 or nil
  end
  if not tot or tot <= 0 then return nil end
  local kind, pct = kindOf(d, tot)
  local sKind, sPct
  if sd and sd ~= 0 then sKind, sPct = kindOf(d + sd, tot) end
  return kind, pct, kind == "up" and replaced or nil, sKind, sPct, sd
end

-- own arrows (tools/art/arrows.py); the client's Arrow-Up-Up was tiny and odd in the tooltip (beta10)
local OFA = "|cffc8961eForever UI|r "
local UP, DOWN = OFA, OFA
GV.UP, GV.DOWN = UP, DOWN
-- "OFA <gold star> Wishlist" in item tooltips (user 03.11.), the star tinted like the wishlist star
GV.WISH = OFA
-- tooltip: green "Upgrade: 30%" with an arrow up, red "Downgrade: 12%" with an arrow down (like the user's example);
-- Quality of Life switch "gearValue", on by default (user 16.10.)
function GV.TooltipLine(tt, id, itemLink)
  local _, _, _, loc, _, cid, sub = GetItemInfoInstant(id)
  if not (loc and FLT.GEAR_LOC_SLOTS and FLT.GEAR_LOC_SLOTS[loc]) or not FLT.GearCanUse(loc, cid, sub) then return end
  local kind, pct, slot, sKind, sPct, sd = GV.Change(id, itemLink)
  -- with two slots (rings, trinkets, dual wield): which worn item it is compared with (user 17.10.)
  -- only for upgrades: a downgrade replaces nothing (user 22.10.)
  local link = kind == "up" and slot and GetInventoryItemLink("player", slot)
  local which = link and link:match("%[(.-)%]")
  which = which and ("  |cffb0b0b0" .. string.format(L["(replaces %s)"], which) .. "|r") or ""
  local function line(k, p, extra)
    if k == "up" then tt:AddLine(UP .. string.format(L["Upgrade: %s%%"], GV.Pct(p)) .. extra, 0.25, 1, 0.25)
    elseif k == "down" then tt:AddLine(DOWN .. string.format(L["Downgrade: %s%%"], GV.Pct(p)) .. extra, 1, 0.3, 0.3) end
  end
  if kind == "new" then
    if pct then line("up", pct, "  |cffb0b0b0" .. L["(slot empty)"] .. "|r")
    else tt:AddLine(UP .. L["Upgrade (slot empty)"], 0.25, 1, 0.25) end
    return
  end
  line(kind, pct, which)
  -- set bonuses (6.2.2, user 09.11.): a second line with the bonus it loses / completes, e.g. green "Upgrade: 8%" and
  -- red "Downgrade: 5% (set bonus lost)" - the item itself is better, worn now it costs the bonus
  if sKind then
    line(sKind, sPct, "  |cffb0b0b0" .. (sd < 0 and L["(set bonus lost)"] or L["(with set bonus)"]) .. "|r")
  end
end

-- /ofa gv (6.2.5-beta2, user 11.11.: "kann ich das im spiel irgendwie testen?"): how the Value of the item under the mouse
-- (or a linked item: /ofa gv [link]) comes about - weights, item, worn item, change, whole gear
function GV.Debug(itemString)
  local say = FLT.Msg or print
  local link = itemString
  if not link and GameTooltip and GameTooltip:IsShown() and GameTooltip.GetItem then link = select(2, GameTooltip:GetItem()) end
  local id = link and tonumber(link:match("item:(%d+)"))
  if not id then say(L["Point at an item (or shift-click it into the line), then type /ofa gv."]) return end
  if not W then buildWeights() end
  local name = (GetItemInfo and GetItemInfo(id)) or ("item:" .. id)
  say(string.format(L["Gear Value of %s - weights: %s, level %d"], name, L[specName or "Leveling"], UnitLevel("player") or 0))
  local v, d, equipped, base, replaced, sd = GV.Upgrade(id, link)
  local tot = gearTotal()
  if not v then say(L["No Value (not gear for you, or no item data yet)."]) return end
  local slots = {}
  for _, s in ipairs(GEAR_SLOTS) do local wv = wornValue(s); if wv and wv ~= 0 then slots[#slots + 1] = s .. "=" .. string.format("%.1f", wv) end end
  say(string.format(L["Worn Value per slot: %s"], table.concat(slots, "  ")))
  say(string.format(L["Item: %.1f  |  replaces: %s (slot %s)  |  change: %s  |  whole gear: %s"], v,
    base and string.format("%.1f", base) or "-", tostring(replaced or (equipped and "worn") or "-"),
    d and string.format("%+.1f", d) or "-", tot and string.format("%.1f", tot) or "-"))
  local kind, pct = GV.Change(id, link)
  say(string.format(L["Result: %s %s%%"], tostring(kind), pct and GV.Pct(pct) or "-") ..
    ((sd and sd ~= 0) and ("  (" .. string.format(L["set bonus %+.1f"], sd) .. ")") or ""))
end

-- refresh: talents / level change the weights, gear changes the worn values
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED",
  "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_EQUIPMENT_CHANGED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event)
  -- how often each event resets the scores (kept in the saved settings, to
  -- see if one fires far more than it should)
  GV.eventCounts = GV.eventCounts or {}
  GV.eventCounts[event] = (GV.eventCounts[event] or 0) + 1
  if ns.db then ns.db.gearEventCounts = GV.eventCounts end
  if event == "PLAYER_EQUIPMENT_CHANGED" then resetWorn(); setWorn = nil else W = nil; GV.gen = (GV.gen or 0) + 1 end
end)
GV._reset = function() W = nil; setWorn = nil; wipe(values); resetWorn(); wipe(speeds); wipe(classOK) end -- tests

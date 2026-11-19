-- Forever Gold - your characters
--
-- Remembers, for every character you log in on: level, gold, professions,
-- the recipes they know (read from the profession window the first time you
-- open it) and what's in their bags. That is what makes the advice about
-- YOUR characters instead of a generic guide.
--
-- (The farming timer lives in Tracker.lua.)

local _, ns = ...
local floor, max = math.floor, math.max

function ns.Char()
    local chars = ns.db.chars
    local c = chars[ns.charKey]
    if not c then
        c = {}
        chars[ns.charKey] = c
    end
    c.profs = c.profs or {}
    c.recipes = c.recipes or {}
    c.bags = c.bags or {}
    c.bound = c.bound or {}
    return c
end

local function refreshBasics()
    ns.RefreshPlayer()
    local c = ns.Char()
    c.name = ns.PlayerFullName()
    c.faction = ns.player.faction
    c.level = ns.player.level
    c.class = ns.player.class
    c.realmKey = ns.realmKey
    c.money = ns.try(GetMoney) or c.money or 0
    c.seen = time()
    ns.LogGold()
end

----------------------------------------------------------------------
-- Gold over time (the Characters tab's graph)
--
-- One point per 15 minutes at most: a change inside the same quarter hour
-- replaces the last point. Past 30 days, points are thinned to one a day.
----------------------------------------------------------------------

local GOLD_STEP, DAY = 900, 86400

-- Adds `value` to a log of { time, copper } points; returns the log, which
-- is a new (thinned) table once it gets long.
local function pushGold(log, now, value)
    local last = log[#log]
    if last and last[2] == value then
        return log
    end
    if last and math.floor(last[1] / GOLD_STEP) == math.floor(now / GOLD_STEP) and #log > 1 then
        last[1], last[2] = now, value
    else
        log[#log + 1] = { now, value }
    end
    if #log <= 2500 then
        return log
    end
    local keep, lastDay = {}, nil
    for _, p in ipairs(log) do
        local day = math.floor(p[1] / DAY)
        if p[1] > now - 30 * DAY then
            keep[#keep + 1] = p
        elseif day ~= lastDay then
            keep[#keep + 1] = p
            lastDay = day
        else
            keep[#keep] = p -- the day's last value
        end
    end
    return keep
end

-- The account total in db.goldLog, and this character's own gold in its
-- c.goldLog (only the logged-in character's gold can change).
function ns.LogGold()
    if not (ns.db and ns.db.goldLog) then
        return
    end
    local now = time()
    ns.db.goldLog = pushGold(ns.db.goldLog, now, ns.TotalGold())
    local c = ns.Char()
    if c and c.money then
        c.goldLog = pushGold(c.goldLog or {}, now, c.money)
    end
end

-- Points within the last `secs` seconds (all of them if nil), with the
-- value just before the window so the line starts at the left edge.
-- Returns points, change over the window. With `ch` (a character's saved
-- table), that character's gold instead of the account total.
function ns.GoldHistory(secs, ch)
    local log
    if ch then
        log = ch.goldLog or {}
        -- Characters from before this was recorded: one point from when
        -- they were last seen.
        if #log == 0 and ch.seen and ch.money then
            log = { { ch.seen, ch.money } }
        end
    else
        log = ns.db.goldLog or {}
    end
    local now = time()
    local from = secs and (now - secs) or (log[1] and log[1][1] or now)
    local pts, before = {}, nil
    for _, p in ipairs(log) do
        if p[1] < from then
            before = p
        else
            pts[#pts + 1] = p
        end
    end
    if before then
        table.insert(pts, 1, { from, before[2] })
    end
    local current = ch and (ch.money or 0) or ns.TotalGold()
    if #pts > 0 and pts[#pts][1] < now then
        pts[#pts + 1] = { now, current }
    end
    local change = #pts > 0 and (current - pts[1][2]) or 0
    return pts, change, from
end

local function refreshProfessions()
    local c = ns.Char()
    local a, b, d, e, f, g = ns.try(GetProfessions)
    local found = {}
    local any = false
    for _, idx in ipairs({ a or false, b or false, d or false, e or false, f or false, g or false }) do
        if idx then
            local name, _, skill, maxSkill, _, _, line = ns.try(GetProfessionInfo, idx)
            if name then
                found[name] = { skill = skill or 0, max = maxSkill or 0, line = line }
                any = true
            end
        end
    end
    if any then
        c.profs = found
        ns.Fire("PLAYER_CHANGED")
        if ns.RedrawWorldMap then
            ns.RedrawWorldMap()
        end
    end
end

-- Which profession gathers each kind of spot (chests are anyone's), by
-- name and by skill line so it works in any language.
local GATHER_PROF = {
    herb = { "Herbalism", 182 },
    ore = { "Mining", 186 },
    fish = { "Fishing", 356 },
}

-- Can this character gather this kind of spot? True until the professions
-- have been read, and always when the option to hide the others is off.
function ns.CanGather(kind)
    local need = GATHER_PROF[kind]
    if not need or ns.db.opts.onlyMyProfs == false then
        return true
    end
    local profs = ns.Char().profs
    if not next(profs) then
        return true
    end
    for name, p in pairs(profs) do
        if name == need[1] or p.line == need[2] then
            return true
        end
    end
    return false
end

----------------------------------------------------------------------
-- Bags
----------------------------------------------------------------------

local function scanBags()
    if not C_Container or not C_Container.GetContainerNumSlots then
        return
    end
    local c = ns.Char()
    local all, bound = {}, {}
    local last = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0)
    for bag = 0, last do
        local slots = ns.try(C_Container.GetContainerNumSlots, bag) or 0
        for slot = 1, slots do
            local info = ns.try(C_Container.GetContainerItemInfo, bag, slot)
            if type(info) == "table" and info.itemID then
                all[info.itemID] = (all[info.itemID] or 0) + (info.stackCount or 1)
                if info.isBound then
                    bound[info.itemID] = true
                end
            end
        end
    end
    c.bags, c.bound = all, bound
    c.money = ns.try(GetMoney) or c.money
    ns.Fire("BAGS_UPDATED")
end

----------------------------------------------------------------------
-- Recipes
--
-- recipes[profession][recipeID] = {
--     n = name, o = item it makes, y = how many it makes,
--     r = { {itemID, quantity}, ... }, d = difficulty colour (0 orange .. 3 grey)
-- }
----------------------------------------------------------------------

local announced = {}

local function openProfessionName(T)
    local info = ns.try(T.GetBaseProfessionInfo)
    if type(info) == "table" and info.professionName and info.professionName ~= "" then
        return info.professionName
    end
    info = ns.try(T.GetChildProfessionInfo)
    if type(info) == "table" then
        local name = info.parentProfessionName or info.professionName
        if name and name ~= "" then
            return name
        end
    end
    return nil
end

local function captureRecipes()
    local T = C_TradeSkillUI
    if not T or not T.GetAllRecipeIDs or not T.GetRecipeInfo or not T.GetRecipeSchematic then
        return
    end
    -- Someone else's linked profession, a guild recipe list or an NPC crafter
    -- is not something this character can make.
    if ns.try(T.IsTradeSkillLinked) or ns.try(T.IsTradeSkillGuild) or ns.try(T.IsNPCCrafting) then
        return
    end
    local prof = openProfessionName(T)
    local ids = ns.try(T.GetAllRecipeIDs)
    if not prof or type(ids) ~= "table" then
        return
    end
    local c = ns.Char()
    c.seenProf = c.seenProf or {}
    c.seenProf[prof] = true
    if #ids == 0 then
        return
    end
    local BASIC = (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 1
    local list, count = {}, 0
    for _, rid in ipairs(ids) do
        local info = ns.try(T.GetRecipeInfo, rid)
        if type(info) == "table" and info.learned and info.name then
            local sch = ns.try(T.GetRecipeSchematic, rid, false)
            if type(sch) == "table" and sch.outputItemID then
                local reagents = {}
                for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
                    local first = type(slot.reagents) == "table" and slot.reagents[1]
                    local basic = (slot.reagentType == nil or slot.reagentType == BASIC) and slot.required ~= false
                    if first and first.itemID and basic and (slot.quantityRequired or 0) > 0 then
                        reagents[#reagents + 1] = { first.itemID, slot.quantityRequired }
                        ns.Item(first.itemID)
                    end
                end
                local lo = sch.quantityMin or 1
                local hi = sch.quantityMax or lo
                list[rid] = {
                    n = info.name,
                    o = sch.outputItemID,
                    y = max(1, (lo + hi) / 2),
                    r = reagents,
                    d = info.relativeDifficulty,
                }
                ns.Item(sch.outputItemID)
                count = count + 1
            end
        end
    end
    if count == 0 then
        return
    end
    local before = 0
    for _ in pairs(c.recipes[prof] or {}) do
        before = before + 1
    end
    c.recipes[prof] = list
    if not announced[prof] and count ~= before then
        announced[prof] = true
        ns.Print("learned your " .. count .. " " .. prof .. " recipes. Make > Craft now shows which ones make money.")
    end
    ns.Fire("RECIPES_UPDATED")
end

local function queueRecipes()
    ns.Later("recipes", 0.8, captureRecipes)
end

ns.On("TRADE_SKILL_SHOW", queueRecipes)
ns.On("TRADE_SKILL_LIST_UPDATE", queueRecipes)
ns.On("TRADE_SKILL_DATA_SOURCE_CHANGED", queueRecipes)
ns.On("NEW_RECIPE_LEARNED", queueRecipes)

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

ns.Listen("READY", function()
    refreshBasics()
    C_Timer.After(2, ns.Guard("login-scan", function()
        refreshBasics()
        refreshProfessions()
        scanBags()
    end))
end)

ns.On("BAG_UPDATE_DELAYED", function()
    if ns.ready then
        ns.Later("bags", 0.5, scanBags)
    end
end)

ns.On("PLAYER_MONEY", function()
    if ns.ready then
        ns.Char().money = ns.try(GetMoney) or ns.Char().money
        ns.LogGold()
        ns.Later("ui-money", 0.5, function() ns.Fire("BAGS_UPDATED") end)
    end
end)

ns.On("SKILL_LINES_CHANGED", function()
    if ns.ready then
        ns.Later("profs", 1.0, refreshProfessions)
    end
end)

----------------------------------------------------------------------
-- How long each level took
--
-- Time logged in at each level, counted by the addon: c.lvl = { level,
-- secs, partial } is the level you're on (partial when the addon arrived
-- part-way through it), and c.levels[level] = { s = seconds, at = when,
-- partial } once it's done.
----------------------------------------------------------------------

local lvlFrom -- time() this login's count started from

local function lvlBank(c)
    if lvlFrom and c.lvl then
        local now = time()
        c.lvl.secs = (c.lvl.secs or 0) + math.max(0, now - lvlFrom)
        lvlFrom = now
    end
end

local function lvlStart()
    local c = ns.Char()
    local level = ns.try(UnitLevel, "player")
    if not level then
        return
    end
    if not c.lvl or c.lvl.level ~= level then
        c.lvl = { level = level, secs = 0, partial = true }
    end
    lvlFrom = time()
end

local function lvlUp(newLevel)
    local c = ns.Char()
    lvlBank(c)
    local cur = c.lvl
    newLevel = tonumber(newLevel) or ((cur and cur.level or 0) + 1)
    if cur and cur.level and cur.level < newLevel then
        c.levels = c.levels or {}
        c.levels[cur.level] = { s = floor(cur.secs or 0), at = time(), partial = cur.partial or nil }
    end
    c.lvl = { level = newLevel, secs = 0 }
    lvlFrom = time()
end
ns.LevelUp = lvlUp

-- { {level, secs, at, partial}, ... } newest first.
function ns.LevelTimes(ch)
    ch = ch or ns.Char()
    local out = {}
    for level, e in pairs(ch.levels or {}) do
        out[#out + 1] = { level = level, secs = e.s or 0, at = e.at, partial = e.partial }
    end
    table.sort(out, function(a, b) return a.level > b.level end)
    return out, ch.lvl
end

-- The current level's time so far.
function ns.LevelSoFar()
    local c = ns.Char()
    lvlBank(c)
    return c.lvl and c.lvl.secs or 0, c.lvl
end

ns.Listen("READY", function()
    lvlStart()
end)

ns.On("PLAYER_LOGOUT", function()
    if ns.ready then
        lvlBank(ns.Char())
    end
end)

ns.On("PLAYER_LEVEL_UP", function(level)
    if ns.ready then
        lvlUp(level)
        ns.Later("basics", 1.0, refreshBasics)
    end
end)

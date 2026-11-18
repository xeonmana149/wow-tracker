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

function ns.LogGold()
    local log = ns.db and ns.db.goldLog
    if not log then
        return
    end
    local now, total = time(), ns.TotalGold()
    local last = log[#log]
    if last and last[2] == total then
        return
    end
    if last and math.floor(last[1] / GOLD_STEP) == math.floor(now / GOLD_STEP) and #log > 1 then
        last[1], last[2] = now, total
    else
        log[#log + 1] = { now, total }
    end
    if #log > 2500 then
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
        ns.db.goldLog = keep
    end
end

-- Points within the last `secs` seconds (all of them if nil), with the
-- value just before the window so the line starts at the left edge.
-- Returns points, change over the window.
function ns.GoldHistory(secs)
    local log = ns.db.goldLog or {}
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
    local current = ns.TotalGold()
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
            local name, _, skill, maxSkill = ns.try(GetProfessionInfo, idx)
            if name then
                found[name] = { skill = skill or 0, max = maxSkill or 0 }
                any = true
            end
        end
    end
    if any then
        c.profs = found
        ns.Fire("PLAYER_CHANGED")
    end
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

ns.On("PLAYER_LEVEL_UP", function()
    if ns.ready then
        ns.Later("basics", 1.0, refreshBasics)
    end
end)

-- Forever Gold - Core
--
-- Shared plumbing for every other file: the saved-data tables, a safe event
-- system, money/time formatting and item lookups.
--
-- Design rules (the same ones the WoW Forever Tracker addon learned the hard
-- way on this client):
--  * WoW Forever runs the modern (retail-style) API on a vanilla world. Old
--    globals like GetItemInfo are gone; C_Item / C_AuctionHouse /
--    C_TradeSkillUI are what exist.
--  * Registering an event name the client doesn't know throws, so every
--    RegisterEvent goes through pcall.
--  * Every handler runs inside pcall. One broken feature must never take the
--    rest of the addon (or the user's UI) down with it.
--  * This addon is standalone. It never reads another addon's data.

local ADDON, ns = ...
_G.ForeverGold = ns

ns.TITLE = "Forever Gold"
ns.VERSION = "1.5.0"
-- The auction house keeps 5% of every sale.
ns.AH_CUT = 0.05

local floor, abs = math.floor, math.abs

----------------------------------------------------------------------
-- Printing and error capture
----------------------------------------------------------------------

function ns.Print(msg)
    print("|cffffd100Forever Gold:|r " .. tostring(msg))
end

ns.errors = {}
local warned = {}

function ns.Err(where, err)
    table.insert(ns.errors, 1, tostring(where) .. ": " .. tostring(err))
    ns.errors[21] = nil
    if not warned[where] then
        warned[where] = true
        ns.Print("|cffff7070a part of the addon hit a problem (" .. tostring(where)
            .. ").|r Everything else keeps working. Type |cffffffff/gold debug|r to see the details.")
    end
end

-- Calls fn(...) and returns its results, or nothing if it is missing/errors.
function ns.try(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if ok then
        return a, b, c, d, e, f
    end
    return nil
end

-- Wraps fn so an error inside it is recorded instead of thrown.
function ns.Guard(where, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            ns.Err(where, err)
        end
    end
end

----------------------------------------------------------------------
-- Game events
----------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}
ns.missingEvents = {}

function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then
            ns.missingEvents[event] = true
        end
    end
    table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then
        return
    end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then
            ns.Err(event, err)
        end
    end
end)

----------------------------------------------------------------------
-- Internal messages (one part of the addon telling the others "prices
-- changed", "bags changed", and so on)
----------------------------------------------------------------------

local listeners = {}

function ns.Listen(msg, fn)
    listeners[msg] = listeners[msg] or {}
    table.insert(listeners[msg], fn)
end

function ns.Fire(msg, ...)
    local list = listeners[msg]
    if not list then
        return
    end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then
            ns.Err(msg, err)
        end
    end
end

-- Runs fn once after `delay` seconds, however many times it is asked for in
-- the meantime. Used to collapse bursts of events into one piece of work.
local pending = {}
function ns.Later(key, delay, fn)
    if pending[key] then
        return
    end
    pending[key] = true
    C_Timer.After(delay, function()
        pending[key] = nil
        local ok, err = pcall(fn)
        if not ok then
            ns.Err(key, err)
        end
    end)
end

----------------------------------------------------------------------
-- Formatting
----------------------------------------------------------------------

local GOLD, SILVER, COPPER = "|cffffd100", "|cffc7c7cf", "|cffeda55f"

local function commas(n)
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if out:sub(1, 1) == "," then
        out = out:sub(2)
    end
    return out
end
ns.Commas = commas

-- 123456 copper -> "12g 34s". Shows the two biggest units only, because
-- nobody needs the copper on a 12 gold item.
function ns.Money(c)
    if type(c) ~= "number" then
        return "|cff808080--|r"
    end
    local neg = c < 0
    c = floor(abs(c) + 0.5)
    local g, s, k = floor(c / 10000), floor((c % 10000) / 100), c % 100
    local out
    if g > 0 then
        out = GOLD .. commas(g) .. "g|r"
        if g < 100 and s > 0 then
            out = out .. " " .. SILVER .. s .. "s|r"
        end
    elseif s > 0 then
        out = SILVER .. s .. "s|r"
        if k > 0 then
            out = out .. " " .. COPPER .. k .. "c|r"
        end
    else
        out = COPPER .. k .. "c|r"
    end
    if neg then
        out = "|cffff6060-|r" .. out
    end
    return out
end

-- Same, but with a green + or red - in front, for profits.
function ns.Profit(c)
    if type(c) ~= "number" then
        return "|cff808080--|r"
    end
    if c >= 0 then
        return "|cff40e060+|r" .. ns.Money(c)
    end
    return ns.Money(c)
end

function ns.Ago(t)
    if not t or t <= 0 then
        return "never"
    end
    local d = time() - t
    if d < 90 then
        return "just now"
    elseif d < 3600 then
        return floor(d / 60) .. " min ago"
    elseif d < 7200 then
        return "1 hour ago"
    elseif d < 86400 then
        return floor(d / 3600) .. " hours ago"
    elseif d < 172800 then
        return "yesterday"
    end
    return floor(d / 86400) .. " days ago"
end

function ns.Duration(sec)
    sec = floor(sec or 0)
    local h, m, s = floor(sec / 3600), floor((sec % 3600) / 60), sec % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    end
    return string.format("%d:%02d", m, s)
end

local QUALITY_HEX = {
    [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd",
    [4] = "a335ee", [5] = "ff8000", [6] = "e6cc80", [7] = "00ccff",
}
function ns.QualityHex(q)
    return QUALITY_HEX[q or 1] or "ffffff"
end

----------------------------------------------------------------------
-- Saved data
----------------------------------------------------------------------

local function ensure(t, key)
    if type(t[key]) ~= "table" then
        t[key] = {}
    end
    return t[key]
end

function ns.InitDB()
    if type(ForeverGoldDB) ~= "table" then
        ForeverGoldDB = {}
    end
    local db = ForeverGoldDB
    db.v = db.v or 1
    ensure(db, "realms")   -- auction prices, per realm+faction
    ensure(db, "items")    -- facts about items we have seen (name, vendor value...)
    ensure(db, "vendor")   -- what vendors charge, learned by visiting them
    ensure(db, "chars")    -- your characters: professions, recipes, bags
    ensure(db, "nodes")    -- ore / herb / fishing spots you have gathered
    ensure(db, "sessions") -- finished farming sessions
    local opts = ensure(db, "opts")
    if opts.autoScan == nil then opts.autoScan = true end
    if opts.tooltip == nil then opts.tooltip = true end
    if opts.waypoint == nil then opts.waypoint = true end
    if opts.minimapAngle == nil then opts.minimapAngle = 215 end
    if opts.fastScan == nil then opts.fastScan = true end
    if opts.dealMin == nil then opts.dealMin = 500 end -- 5 silver
    if opts.autoAge == nil then opts.autoAge = 300 end -- rescan after 5 minutes
    ns.db = db
    return db
end

-- The auction house a character can see is decided by realm and faction, so
-- prices are filed under both. The realm ID inside the player's GUID is used
-- instead of the realm's display name because the display name on WoW
-- Forever's numbered megaserver realms is long and may not be stable.
function ns.RefreshPlayer()
    local guid = ns.try(UnitGUID, "player") or "unknown"
    local realmID = type(guid) == "string" and guid:match("^Player%-(%d+)%-") or nil
    local faction = ns.try(UnitFactionGroup, "player") or "Neutral"
    local _, classFile = ns.try(UnitClass, "player")
    ns.player = {
        guid = guid,
        faction = faction,
        level = ns.try(UnitLevel, "player") or 1,
        class = classFile,
    }
    local realm = realmID or ns.try(GetNormalizedRealmName) or ns.try(GetRealmName) or "realm"
    ns.realmKey = tostring(realm) .. "-" .. tostring(faction)
    ns.charKey = guid
end

-- This realm+faction's price book.
function ns.R()
    local realms = ns.db.realms
    local key = ns.realmKey or "unknown"
    local r = realms[key]
    if not r then
        r = { prices = {} }
        realms[key] = r
    end
    if type(r.prices) ~= "table" then
        r.prices = {}
    end
    return r
end

----------------------------------------------------------------------
-- Item facts
--
-- db.items[id] = { n = name, q = quality, v = vendor sell price,
--                  c = classID, s = subclassID, b = bindType, l = minLevel,
--                  st = stack size }
-- Filled in lazily from C_Item.GetItemInfo and kept forever, so names and
-- vendor values are available instantly next session.
----------------------------------------------------------------------

local requested = {}
local nameIndex
ns.nameIndexDirty = true

function ns.RequestItem(id)
    if requested[id] or not C_Item or not C_Item.RequestLoadItemDataByID then
        return
    end
    requested[id] = true
    pcall(C_Item.RequestLoadItemDataByID, id)
end

function ns.Item(id)
    if type(id) ~= "number" then
        return nil
    end
    local items = ns.db.items
    local it = items[id]
    if it and it.n and it.v and it.st then
        return it
    end
    if C_Item and C_Item.GetItemInfo then
        local ok, name, _, quality, _, minLevel, _, _, stack, _, _, sell, classID, subID, bind =
            pcall(C_Item.GetItemInfo, id)
        if ok and name then
            it = it or {}
            it.n, it.q, it.v, it.c, it.s, it.b, it.l = name, quality, sell or 0, classID, subID, bind, minLevel
            it.st = stack or 1
            items[id] = it
            if nameIndex then
                local key = name:lower()
                if not nameIndex[key] then
                    nameIndex[key] = id
                end
            end
            return it
        end
    end
    ns.RequestItem(id)
    return it
end

function ns.ItemName(id)
    local it = ns.Item(id)
    if it and it.n then
        return it.n
    end
    local name = C_Item and ns.try(C_Item.GetItemNameByID, id)
    if name and name ~= "" then
        return name
    end
    if ns.STATIC_NAMES and ns.STATIC_NAMES[id] then
        return ns.STATIC_NAMES[id]
    end
    return "Item #" .. tostring(id)
end

-- Item name wrapped in its quality colour.
function ns.ItemText(id)
    local it = ns.Item(id)
    return "|cff" .. ns.QualityHex(it and it.q) .. ns.ItemName(id) .. "|r"
end

local QUESTION_MARK = 134400
function ns.Icon(id)
    local icon = C_Item and ns.try(C_Item.GetItemIconByID, id)
    return icon or QUESTION_MARK
end

-- Looks an item up by its (English/client) name among everything we have
-- seen. Used to double-check the built-in guide data: the guide lists items
-- by name with an ID hint, and if this client uses a different ID for that
-- name, the name wins.
function ns.FindItemByName(name)
    if not name then
        return nil
    end
    if ns.nameIndexDirty or not nameIndex then
        nameIndex = {}
        local prices = ns.R().prices
        for id, it in pairs(ns.db.items) do
            if it.n then
                local key = it.n:lower()
                local have = nameIndex[key]
                -- Two items can share a name; prefer one that's actually on
                -- the auction house.
                if not have or (prices[id] and not prices[have]) then
                    nameIndex[key] = id
                end
            end
        end
        ns.nameIndexDirty = false
    end
    return nameIndex[name:lower()]
end

-- Resolves a guide entry { "Copper Ore", 2770 } to the item ID this client
-- really uses, or nil if it can't be confirmed yet.
function ns.Resolve(entry)
    local name, hint = entry[1], entry[2]
    if entry.resolved then
        return entry.resolved
    end
    -- The guide's names are English. On another language's client the names
    -- can't be compared, so the ID hint is all there is.
    if ns.nonEnglish == nil then
        local locale = ns.try(GetLocale) or "enUS"
        ns.nonEnglish = not (locale == "enUS" or locale == "enGB")
    end
    if ns.nonEnglish then
        return hint
    end
    if hint then
        local it = ns.Item(hint)
        if it and it.n then
            if it.n:lower() == name:lower() then
                entry.resolved = hint
                return hint
            end
        else
            -- Not loaded yet. Trust the hint for now, but don't lock it in.
            local byName = ns.FindItemByName(name)
            return byName or hint
        end
    end
    local byName = ns.FindItemByName(name)
    if byName then
        entry.resolved = byName
    end
    return byName
end

ns.On("GET_ITEM_INFO_RECEIVED", function(itemID, success)
    if success and type(itemID) == "number" then
        ns.Item(itemID)
        ns.Later("items-updated", 1.0, function()
            ns.Fire("ITEMS_UPDATED")
        end)
    end
end)

-- Loads item facts for a big list of IDs a few at a time, so a fresh scan of
-- thousands of items doesn't freeze the game.
local warmQueue, warmPos, warmRunning = {}, 1, false
local function warmStep()
    local done = 0
    while warmPos <= #warmQueue and done < 60 do
        local id = warmQueue[warmPos]
        warmPos = warmPos + 1
        local it = ns.db.items[id]
        if not (it and it.n and it.v and it.st) then
            ns.Item(id)
            done = done + 1
        end
    end
    if warmPos <= #warmQueue then
        C_Timer.After(0.05, warmStep)
    else
        warmRunning = false
        warmQueue, warmPos = {}, 1
        ns.Later("items-updated", 1.5, function()
            ns.Fire("ITEMS_UPDATED")
        end)
    end
end

function ns.WarmItems(ids)
    for i = 1, #ids do
        warmQueue[#warmQueue + 1] = ids[i]
    end
    if not warmRunning and #warmQueue > 0 then
        warmRunning = true
        C_Timer.After(0.1, warmStep)
    end
end

----------------------------------------------------------------------
-- A hidden tooltip, for the one thing only a tooltip can tell us: the
-- player's full two-word name (UnitName stops at the first space here).
----------------------------------------------------------------------

local scanTip
local function stripCodes(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end
ns.StripCodes = stripCodes

function ns.PlayerFullName()
    local short = ns.try(UnitName, "player") or "You"
    if not scanTip then
        local ok, tip = pcall(CreateFrame, "GameTooltip", "ForeverGoldScanTip", nil, "GameTooltipTemplate")
        scanTip = ok and tip or false
    end
    if scanTip then
        local ok, text = pcall(function()
            scanTip:SetOwner(UIParent, "ANCHOR_NONE")
            scanTip:SetUnit("player")
            local fs = _G["ForeverGoldScanTipTextLeft1"]
            local t = fs and fs:GetText()
            scanTip:Hide()
            return t
        end)
        if ok and type(text) == "string" then
            text = stripCodes(text)
            -- Only trust it if it starts with the name the API gave us.
            if text:sub(1, #short) == short and #text < 40 then
                return text
            end
        end
    end
    return short
end

----------------------------------------------------------------------
-- Startup
----------------------------------------------------------------------

ns.On("ADDON_LOADED", function(name)
    if name == ADDON then
        ns.InitDB()
    end
end)

ns.On("PLAYER_LOGIN", function()
    if not ns.db then
        ns.InitDB()
    end
    ns.RefreshPlayer()
    ns.ready = true
    ns.Fire("READY")
    C_Timer.After(6, function()
        if ns.db and not ns.db.welcomed then
            ns.db.welcomed = true
            ns.Print("ready. Type |cffffffff/gold|r to open. First step: visit an auctioneer so I can read the prices.")
        end
    end)
end)

ns.On("PLAYER_LEVEL_UP", function(level)
    if ns.player and type(level) == "number" then
        ns.player.level = level
    end
    ns.Fire("PLAYER_CHANGED")
end)

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------

SLASH_FOREVERGOLD1 = "/gold"
SLASH_FOREVERGOLD2 = "/fg"
SLASH_FOREVERGOLD3 = "/forevergold"

SlashCmdList["FOREVERGOLD"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if not ns.ready then
        ns.Print("still loading - try again in a moment.")
        return
    end
    if msg == "" then
        if ns.ToggleUI then ns.ToggleUI() end
    elseif msg == "scan" then
        if ns.StartScan then ns.StartScan() end
    elseif msg == "scan full" or msg == "scan fast" then
        if ns.StartScan then ns.StartScan("replicate") end
    elseif msg == "scan slow" then
        if ns.StartScan then ns.StartScan("browse") end
    elseif msg == "stop" then
        if ns.StopRoute then ns.StopRoute() end
    elseif msg == "session" or msg == "track" then
        if ns.TrackerToggle then ns.TrackerToggle() end
    elseif msg == "kills" or msg == "loot" or msg == "tracker" or msg == "window" then
        if ns.ToggleTrackerWindow then ns.ToggleTrackerWindow() end
    elseif msg == "track reset" then
        if ns.TrackerReset then ns.TrackerReset() end
    elseif msg == "track save" then
        if ns.StopSession then ns.StopSession() end
    elseif msg == "market" then
        if ns.MarketStatus then ns.Print(ns.MarketStatus()) end
    elseif msg == "debug" then
        ns.Print("version " .. ns.VERSION .. ", price book '" .. tostring(ns.realmKey) .. "'")
        local n = 0
        for _ in pairs(ns.R().prices) do n = n + 1 end
        ns.Print("items with a price: " .. n .. ", last scan: " .. ns.Ago(ns.R().lastScan))
        local last = (ns.scan and ns.scan.lastResult) or ns.R().lastScanInfo
        if last then
            ns.Print("last scan" .. (last.at and (" (" .. ns.Ago(last.at) .. ")") or "") .. ": "
                .. (last.mode == "replicate" and "fast" or "slow") .. ", "
                .. last.n .. " items in " .. string.format("%.1f", last.took or 0) .. "s"
                .. (last.arrived and (", download arrived after " .. string.format("%.1f", last.arrived) .. "s") or "")
                .. (last.passes and last.passes > 1 and (", read " .. last.passes .. " times") or "")
                .. (last.pages and (", " .. last.pages .. " pages") or "")
                .. (last.auctions and (", " .. last.auctions .. " auctions") or ""))
            if last.note then
                ns.Print("  " .. last.note)
            end
        end
        local R = ns.R()
        ns.Print("fast scan: " .. (ns.db.opts.fastScan and "on" or "off")
            .. (R.fastBad and ", switched off after a failed check" or (R.fastOK and ", checked and trusted" or ", not yet checked"))
            .. ", usable again in " .. math.ceil(ns.FastScanWait() / 60) .. " min")
        if ns.MarketStatus then
            ns.Print(ns.MarketStatus())
        end
        local miss = {}
        for ev in pairs(ns.missingEvents) do miss[#miss + 1] = ev end
        if #miss > 0 then
            ns.Print("events this client doesn't have: " .. table.concat(miss, ", "))
        end
        if #ns.errors == 0 then
            ns.Print("no errors recorded.")
        else
            ns.Print("most recent errors:")
            for i = 1, math.min(8, #ns.errors) do
                print("  " .. ns.errors[i])
            end
        end
    elseif msg == "reset prices" then
        ns.R().prices = {}
        ns.R().lastScan = nil
        ns.Fire("PRICES_UPDATED")
        ns.Print("price book cleared.")
    else
        ns.Print("commands:")
        print("  |cffffffff/gold|r - open or close the window")
        print("  |cffffffff/gold scan|r - read auction prices (at an auctioneer)")
        print("  |cffffffff/gold kills|r - show or hide the Kills & Loot window (or right-click the minimap button)")
        print("  |cffffffff/gold track|r - start or pause the kill and loot tracker")
        print("  |cffffffff/gold track reset|r - wipe the tracker's numbers")
        print("  |cffffffff/gold track save|r - save the trip to Make > Farm and clear the tracker")
        print("  |cffffffff/gold market|r - where the sale-rate data stands")
        print("  |cffffffff/gold stop|r - stop following a route")
        print("  |cffffffff/gold debug|r - show technical details if something looks wrong")
    end
end

function ForeverGold_OnAddonCompartmentClick()
    if ns.ready and ns.ToggleUI then
        ns.ToggleUI()
    end
end

function ForeverGold_OnAddonCompartmentEnter(_, button)
    if GameTooltip and button then
        pcall(function()
            GameTooltip:SetOwner(button, "ANCHOR_LEFT")
            GameTooltip:SetText("Forever Gold")
            GameTooltip:AddLine("Click to open your gold-making advice.", 1, 1, 1)
            GameTooltip:Show()
        end)
    end
end

function ForeverGold_OnAddonCompartmentLeave()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

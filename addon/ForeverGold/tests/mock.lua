-- A stand-in for the WoW Forever client, just enough to run Forever Gold
-- end to end outside the game.

local M = { now = 1794500000, clock = 1000, printed = {}, undefined = {}, timers = {}, tickers = {}, frames = {} }
_G.MOCK = M

local realPrint = print
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    M.printed[#M.printed + 1] = table.concat(parts, " ")
end
M.realPrint = realPrint

function time() return M.now end
function GetTime() return M.clock end
function GetServerTime() return M.now end
date = os.date
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert

----------------------------------------------------------------------
-- Widgets
----------------------------------------------------------------------
local KNOWN_EVENTS = {}
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "GET_ITEM_INFO_RECEIVED", "MERCHANT_SHOW",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
    "AUCTION_HOUSE_BROWSE_FAILURE", "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "OWNED_AUCTIONS_UPDATED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "SKILL_LINES_CHANGED", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED",
    "LOOT_READY", "LOOT_OPENED", "NEW_RECIPE_LEARNED", "UNIT_HEALTH", "LOOT_SLOT_CLEARED", "LOOT_CLOSED",
    "MAIL_SHOW", "MAIL_CLOSED", "MERCHANT_CLOSED", "PLAYER_LOGOUT", "AUCTION_HOUSE_AUCTION_CREATED", "PLAYER_DEAD",
    "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_TURNED_IN" }) do
    KNOWN_EVENTS[e] = true
end

local methods = {}
local widgetMT
local function newWidget(kind, name, parent)
    local w = setmetatable({ _kind = kind, _name = name, _parent = parent, _scripts = {}, _events = {}, _shown = true,
        _w = 0, _h = 0, _text = "" }, widgetMT)
    if name then _G[name] = w end
    M.frames[#M.frames + 1] = w
    return w
end
M.newWidget = newWidget

function methods:SetScript(k, fn) self._scripts[k] = fn end
function methods:GetScript(k) return self._scripts[k] end
function methods:HookScript(k, fn)
    local old = self._scripts[k]
    self._scripts[k] = function(...) if old then old(...) end fn(...) end
end
function methods:RegisterEvent(e)
    if not KNOWN_EVENTS[e] then error("unknown event " .. tostring(e)) end
    self._events[e] = true
end
function methods:Show() local was = self._shown; self._shown = true; if not was and self._scripts.OnShow then self._scripts.OnShow(self) end end
function methods:Hide() local was = self._shown; self._shown = false; if was and self._scripts.OnHide then self._scripts.OnHide(self) end end
function methods:SetShown(s) if s then self:Show() else self:Hide() end end
function methods:IsShown() return self._shown end
function methods:IsVisible() return self._shown end
function methods:CreateTexture() return newWidget("Texture", nil, self) end
function methods:CreateFontString() return newWidget("FontString", nil, self) end
function methods:CreateLine() return newWidget("Line", nil, self) end
function methods:SetText(t) if t == nil then error("SetText(nil)") end self._text = tostring(t) end
function methods:GetText() return self._text end
function methods:SetSize(w, h) assert(type(w) == "number" and type(h) == "number", "SetSize needs numbers"); self._w, self._h = w, h end
function methods:SetWidth(w) assert(type(w) == "number", "SetWidth needs a number"); self._w = w end
function methods:SetHeight(h) assert(type(h) == "number", "SetHeight needs a number"); self._h = h end
function methods:GetWidth() return self._w end
function methods:GetHeight() return self._h end
function methods:GetSize() return self._w, self._h end
function methods:GetStringHeight() return 12 * math.max(1, math.ceil(#self._text / 110)) end
function methods:GetCenter() return 100, 100 end
function methods:GetLeft() return 900 end
function methods:GetTop() return 700 end
function methods:GetEffectiveScale() return 1 end
function methods:GetFrameLevel() return 1 end
function methods:GetParent() return self._parent end
function methods:SetParent(p) self._parent = p end
function methods:SetPoint(point, ...)
    assert(type(point) == "string", "SetPoint needs a point name")
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        assert(v ~= nil, "SetPoint got a nil argument")
        if type(v) == "number" then assert(v == v, "SetPoint got NaN") end
    end
end
function methods:SetStartPoint(point, rel, x, y) assert(type(x) == "number" and type(y) == "number" and x == x and y == y, "bad line start") end
function methods:SetEndPoint(point, rel, x, y) assert(type(x) == "number" and type(y) == "number" and x == x and y == y, "bad line end") end
function methods:SetColorTexture(r, g, b, a) assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "SetColorTexture needs numbers") end
function methods:SetTexture(t) assert(t ~= nil, "SetTexture(nil)") end
function methods:SetOwner(owner, anchor) assert(owner ~= nil and type(anchor) == "string", "SetOwner") ; self._lines = {} end
function methods:AddLine(text) assert(type(text) == "string", "AddLine needs text, got " .. type(text)); self._lines = self._lines or {}; self._lines[#self._lines + 1] = text end
function methods:AddDoubleLine(l, r) assert(type(l) == "string" and type(r) == "string", "AddDoubleLine needs two strings"); self._lines = self._lines or {}; self._lines[#self._lines + 1] = l .. "  ||  " .. r end
function methods:SetItemByID(id) assert(type(id) == "number", "SetItemByID") end
function methods:SetUnit() end
function methods:GetCanvas() self._canvas = self._canvas or newWidget("Frame", nil, self); self._canvas._w, self._canvas._h = 1002, 668; return self._canvas end
function methods:GetMapID() return 1413 end

widgetMT = { __index = function(t, k)
    local m = methods[k]
    if m then return m end
    if type(k) == "string" and k:sub(1, 1) ~= "_" and k:match("^[A-Z]") then
        -- any other widget method: accept and ignore
        return function() end
    end
    return nil
end }

function CreateFrame(kind, name, parent, template)
    assert(type(kind) == "string")
    local w = newWidget(kind, name, parent)
    if kind == "GameTooltip" and name then
        local fs = newWidget("FontString", name .. "TextLeft1", w)
        fs._text = "|cffffffffXeon Mana|r"
    end
    return w
end

UIParent = newWidget("Frame", "UIParent")
Minimap = newWidget("Frame", "Minimap"); Minimap._w = 140
GameTooltip = newWidget("GameTooltip", "GameTooltip")
ItemRefTooltip = newWidget("GameTooltip", "ItemRefTooltip")
WorldMapFrame = newWidget("Frame", "WorldMapFrame")
WorldMapFrame.OnMapChanged = function() end
AuctionHouseFrame = newWidget("Frame", "AuctionHouseFrame")
AuctionHouseFrame.SearchBar = { SetSearchText = function(_, t) M.lastSearch = t end, StartSearch = function() end }
UISpecialFrames = {}
SlashCmdList = {}
NUM_BAG_SLOTS = 4

function hooksecurefunc(tbl, name, fn)
    if type(tbl) == "string" then
        tbl, name, fn = _G, tbl, name
    end
    local old = tbl[name]
    tbl[name] = function(...) local r = old and old(...); fn(...); return r end
end

function M.fire(event, ...)
    for _, f in ipairs(M.frames) do
        if f._events[event] and f._scripts.OnEvent then
            f._scripts.OnEvent(f, event, ...)
        end
    end
end

-- Runs every OnUpdate script of shown frames once.
function M.update(elapsed)
    for _, f in ipairs(M.frames) do
        if f._shown and f._scripts.OnUpdate then
            f._scripts.OnUpdate(f, elapsed or 1.1)
        end
    end
end

----------------------------------------------------------------------
-- Timers
----------------------------------------------------------------------
C_Timer = {}
function C_Timer.After(delay, fn)
    assert(type(delay) == "number" and type(fn) == "function")
    M.timers[#M.timers + 1] = { at = M.clock + delay, fn = fn }
end
function C_Timer.NewTicker(interval, fn)
    local t = { interval = interval, fn = fn, next = M.clock + interval }
    function t:Cancel() self.cancelled = true end
    M.tickers[#M.tickers + 1] = t
    return t
end
-- Advance the clock by `seconds`, running whatever comes due.
function M.advance(seconds)
    local target = M.clock + seconds
    while true do
        local bestI, bestAt
        for i, t in ipairs(M.timers) do
            if t.at <= target and (not bestAt or t.at < bestAt) then bestI, bestAt = i, t.at end
        end
        local tick
        for _, t in ipairs(M.tickers) do
            if not t.cancelled and t.next <= target and (not bestAt or t.next < bestAt) then tick, bestAt, bestI = t, t.next, nil end
        end
        if tick then
            M.clock = tick.next
            tick.next = tick.next + tick.interval
            tick.fn(tick)
        elseif bestI then
            local t = table.remove(M.timers, bestI)
            M.clock = t.at
            t.fn()
        else
            break
        end
    end
    M.now = M.now + seconds
    M.clock = target
end

----------------------------------------------------------------------
-- Player
----------------------------------------------------------------------
M.player = { money = 89131, level = 25, x = 0.50, y = 0.50, facing = 0, zone = "The Barrens", map = 1413 }
function UnitGUID() return "Player-6801-00470CD5" end
function UnitName(u) if u == "npc" then return "Wrahk" end return "Xeon" end
function UnitFactionGroup() return "Horde" end
function UnitLevel() return M.player.level end
function UnitClass() return "Paladin", "PALADIN" end
function GetMoney() return M.player.money end
function GetRealmName() return "CAMWOW AU1 Realm 2 PvP" end
function GetNormalizedRealmName() return "PvP" end
function GetRealZoneText() return M.player.zone end
function GetPlayerFacing() return M.player.facing end
function GetCursorPosition() return 300, 300 end
function GetLocale() return "enUS" end
function IsShiftKeyDown() return M.shift end
function IsFishingLoot() return M.fishing end
function GetProfessions() return 1, 2, nil, 3, 4, 5 end
local PROFS = { { "Blacksmithing", 120, 150 }, { "Mining", 98, 150 }, { "Fishing", 60, 150 }, { "Cooking", 80, 150 }, { "First Aid", 70, 150 } }
function GetProfessionInfo(i) local p = PROFS[i]; if p then return p[1], 1, p[2], p[3] end end

----------------------------------------------------------------------
-- Items
----------------------------------------------------------------------
-- id = { name, quality, vendorSell, classID, bindType }
M.items = {
    [2770] = { "Copper Ore", 1, 5, 7 }, [2840] = { "Copper Bar", 1, 10, 7 }, [2771] = { "Tin Ore", 1, 25, 7 },
    [3576] = { "Tin Bar", 1, 35, 7 }, [2841] = { "Bronze Bar", 1, 50, 7 }, [2835] = { "Rough Stone", 1, 2, 7 },
    [2836] = { "Coarse Stone", 1, 15, 7 }, [2862] = { "Rough Sharpening Stone", 1, 3, 0 },
    [2853] = { "Copper Bracers", 1, 17, 4 }, [2880] = { "Weak Flux", 1, 25, 7 }, [2775] = { "Silver Ore", 2, 75, 7 },
    [6217] = { "Copper Rod", 1, 24, 7 }, [900001] = { "Gemmed Copper Boots", 3, 401, 4, 1 },
    [818] = { "Tigerseye", 2, 100, 3 }, [774] = { "Malachite", 2, 25, 3 }, [1210] = { "Shadowgem", 2, 250, 3 },
    [6948] = { "Hearthstone", 1, 0, 15, 1 }, [4865] = { "Ruined Pelt", 0, 5, 15 }, [2589] = { "Linen Cloth", 1, 13, 7 },
    [6522] = { "Deviate Fish", 1, 1, 7 }, [6289] = { "Raw Longjaw Mud Snapper", 1, 1, 7 },
    [6291] = { "Raw Brilliant Smallfish", 1, 1, 7 }, [765] = { "Silverleaf", 1, 5, 7 },
    [5772] = { "Pattern: Red Woolen Bag", 2, 125, 9 }, [1206] = { "Moss Agate", 2, 100, 3 },
    [1705] = { "Lesser Moonstone", 2, 150, 3 }, [2842] = { "Silver Bar", 2, 100, 7 }, [3470] = { "Rough Grinding Stone", 1, 5, 7 },
    [12345] = { "Worn Junk Sword", 0, 900, 2 }, [6358] = { "Oily Blackmouth", 1, 4, 7 },
    [12346] = { "Cheap Mail Boots", 1, 900, 4 }, [12347] = { "Bid Only Cloak", 1, 2000, 4 },
}
M.loaded = {}
local function info(id)
    local it = M.items[id]
    if not it then return nil end
    if not M.loaded[id] then
        -- first request for an item misses, like the real client's item cache
        M.loaded[id] = true
        if id % 7 == 0 then return nil end
    end
    return it
end
C_Item = {}
function C_Item.GetItemInfo(id)
    assert(type(id) == "number", "GetItemInfo needs a number")
    local it = info(id)
    if not it then return nil end
    local stack = (it[4] == 2 or it[4] == 4 or it[4] == 9 or it[4] == 15) and 1 or 20
    return it[1], "|cffffffff|Hitem:" .. id .. "|h[" .. it[1] .. "]|h|r", it[2], 10, 5, "Trade Goods", "Metal", stack, "", 134400, it[3], it[4], 0, it[5] or 0
end
function C_Item.GetItemNameByID(id) local it = M.items[id]; return it and it[1] or nil end
function C_Item.GetItemIconByID(id) return M.items[id] and (130000 + id % 1000) or nil end
function C_Item.RequestLoadItemDataByID(id) M.requested = (M.requested or 0) + 1 end

----------------------------------------------------------------------
-- Bags
----------------------------------------------------------------------
M.bags = { { 6948, 1, true }, { 2770, 40 }, { 2835, 23 }, { 2771, 12 }, { 4865, 6 }, { 2840, 8 }, { 2589, 35 }, { 2775, 2 }, { 3576, 4 } }
C_Container = {}
function C_Container.GetContainerNumSlots(bag) if bag == 0 then return 16 end return 0 end
function C_Container.GetContainerItemInfo(bag, slot)
    local b = M.bags[slot]
    if bag ~= 0 or not b then return nil end
    return { itemID = b[1], stackCount = b[2], isBound = b[3] or false }
end

----------------------------------------------------------------------
-- Professions
----------------------------------------------------------------------
M.recipes = {
    [2657] = { name = "Smelt Copper", out = 2840, r = { { 2770, 1 } } },
    [2659] = { name = "Smelt Bronze", out = 2841, lo = 2, hi = 2, r = { { 2840, 1 }, { 3576, 1 } } },
    [3304] = { name = "Smelt Tin", out = 3576, r = { { 2771, 1 } } },
    [2660] = { name = "Rough Sharpening Stone", out = 2862, r = { { 2835, 1 } } },
    [2663] = { name = "Copper Bracers", out = 2853, r = { { 2840, 2 } } },
    [1245287] = { name = "Copper Rod", out = 6217, r = { { 2840, 1 }, { 2880, 1 } } },
    [1252229] = { name = "Gemmed Copper Boots", out = 900001, r = { { 2840, 2 }, { 818, 2 } } },
    [3320] = { name = "Rough Grinding Stone", out = 3470, r = { { 2835, 2 } } },
    [99999] = { name = "Unlearned Thing", out = 2853, r = {}, unlearned = true },
}
Enum = {
    AuctionHouseFilter = { PoorQuality = 6, CommonQuality = 7, UncommonQuality = 8, RareQuality = 9, EpicQuality = 10, LegendaryQuality = 11, ArtifactQuality = 12 },
    AuctionHouseSortOrder = { Price = 0, Name = 1 },
    CraftingReagentType = { Modifying = 0, Basic = 1, Finishing = 2 },
    TooltipDataType = { Item = 0 },
}
C_TradeSkillUI = {}
function C_TradeSkillUI.GetAllRecipeIDs() local t = {} for id in pairs(M.recipes) do t[#t + 1] = id end table.sort(t) return t end
function C_TradeSkillUI.GetRecipeInfo(id) local r = M.recipes[id]; return r and { name = r.name, learned = not r.unlearned, relativeDifficulty = 1, recipeID = id } end
function C_TradeSkillUI.GetRecipeSchematic(id, recraft)
    assert(recraft == false)
    local r = M.recipes[id]
    local slots = {}
    for _, x in ipairs(r.r) do slots[#slots + 1] = { reagents = { { itemID = x[1] } }, quantityRequired = x[2], reagentType = 1, required = true } end
    slots[#slots + 1] = { reagents = { { itemID = 555 } }, quantityRequired = 1, reagentType = 2, required = false }
    return { outputItemID = r.out, quantityMin = r.lo or 1, quantityMax = r.hi or 1, reagentSlotSchematics = slots }
end
function C_TradeSkillUI.GetBaseProfessionInfo() return { professionName = M.openProf or "Blacksmithing" } end
function C_TradeSkillUI.IsTradeSkillLinked() return false end
function C_TradeSkillUI.IsTradeSkillGuild() return false end
function C_TradeSkillUI.IsNPCCrafting() return false end

----------------------------------------------------------------------
-- Auction house: delivers M.auctions in pages of 3
----------------------------------------------------------------------
-- { itemID, minPrice, quantity, suffix }
M.auctions = {
    { 2770, 40, 320 }, { 2840, 90, 150 }, { 2771, 210, 60 }, { 3576, 260, 40 }, { 2841, 420, 25 }, { 2835, 12, 500 },
    { 2862, 8, 30 }, { 2853, 300, 2 }, { 2775, 2500, 3 }, { 818, 900, 6 }, { 4865, 3, 4 }, { 2589, 60, 800 },
    { 6522, 350, 14 }, { 12345, 400, 1 }, { 5772, 4000, 1 }, { 2853, 280, 1, 7 }, { 6289, 30, 40 }, { 6291, 20, 20 },
    { 1206, 800, 5 }, { 2880, 300, 4 },
    -- gear whose "lowest price" in a browse scan is not what it seems:
    { 12346, 300, 1 }, -- a real 3s buyout (vendors pay 9s: a true flip)
    { 12347, 100, 1 }, -- 1s is only a bid; there is no buyout at all
}
-- (12345, the junk sword above, shows 4s in a browse scan, but that is a bid;
-- its cheapest real buyout is 15s.)
local AHS = { pos = 0, results = {} }
local function page()
    local out = {}
    for i = 1, 3 do
        local a = M.auctions[AHS.pos + i]
        if a then
            out[#out + 1] = { itemKey = { itemID = a[1], itemLevel = 10, itemSuffix = a[4] or 0, battlePetSpeciesID = 0 }, minPrice = a[2], totalQuantity = a[3] }
        end
    end
    AHS.pos = AHS.pos + 3
    for _, r in ipairs(out) do AHS.results[#AHS.results + 1] = r end
    return out
end
C_AuctionHouse = {}
function C_AuctionHouse.IsThrottledMessageSystemReady() return true end
function C_AuctionHouse.SendBrowseQuery(q)
    assert(type(q) == "table" and q.searchString == "" and #q.filters == 7 and #q.sorts == 2, "bad browse query")
    M.queries = (M.queries or 0) + 1
    AHS.pos, AHS.results = 0, {}
    C_Timer.After(0.3, function() page(); M.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end)
end
function C_AuctionHouse.RequestMoreBrowseResults()
    M.more = (M.more or 0) + 1
    C_Timer.After(0.2, function() local p = page(); if #p > 0 then M.fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", p) end end)
end
function C_AuctionHouse.GetBrowseResults() return AHS.results end
function C_AuctionHouse.HasFullBrowseResults() return AHS.pos >= #M.auctions end
function C_AuctionHouse.QueryOwnedAuctions(sorts) assert(type(sorts) == "table"); C_Timer.After(0.1, function() M.fire("OWNED_AUCTIONS_UPDATED") end) end
function C_AuctionHouse.GetOwnedAuctions() return { { itemKey = { itemID = 2840 }, status = 0, quantity = 5, buyoutAmount = 600 } } end
-- "Send me every auction": allowed once per 15 minutes, silently ignored otherwise.
-- M.replicateOverride[itemID] = { { count, totalBuyout }, ... } for items whose
-- real auctions differ from what a browse scan shows.
M.replicateOverride = { [12345] = { { 1, 0 }, { 1, 1500 } }, [12347] = { { 1, 0 } } }
M.repList = {}
local function buildReplicate()
    local list = {}
    for _, a in ipairs(M.auctions) do
        local id, price, qty = a[1], a[2], a[3]
        local over = M.replicateOverride[id]
        if over then
            for _, o in ipairs(over) do list[#list + 1] = { id = id, count = o[1], buyout = o[2] } end
        else
            local left, first = qty, true
            while left > 0 do
                local c = math.min(20, left)
                local unit = first and price or math.ceil(price * 1.2)
                list[#list + 1] = { id = id, count = c, buyout = unit * c }
                left, first = left - c, false
            end
        end
    end
    return list
end
function C_AuctionHouse.ReplicateItems()
    M.replicateCalls = (M.replicateCalls or 0) + 1
    if M.repSilent or (M.repLast and M.clock - M.repLast < 900) then return end
    M.repLast = M.clock
    M.repList = {}
    C_Timer.After(M.repDelay or 1.0, function()
        M.repList = buildReplicate()
        M.repReads = 0
        M.fire("REPLICATE_ITEM_LIST_UPDATE")
        M.fire("REPLICATE_ITEM_LIST_UPDATE") -- it fires repeatedly as item data loads
    end)
end
function C_AuctionHouse.GetNumReplicateItems() return #M.repList end
function C_AuctionHouse.GetReplicateItemInfo(i)
    local a = M.repList[i + 1] -- the real function counts from 0
    assert(a, "replicate index out of range: " .. tostring(i))
    M.repReads = M.repReads + 1
    local id = a.id
    -- first pass: pretend a third of the rows haven't got their item yet
    if M.repLazy and M.repReads <= #M.repList and i % 3 == 0 then id = nil end
    local buyout = a.buyout
    if M.repPerUnit and a.count > 0 then buyout = a.buyout / a.count end -- a client with different rules
    return nil, 134400, a.count, 1, true, 10, "", 1, 1, buyout, 0, nil, nil, "Someone", nil, 0, id, false
end
function debugprofilestop() return os.clock() * 1000 end

----------------------------------------------------------------------
-- Vendors
----------------------------------------------------------------------
M.merchant = { { 2880, 100, 1, -1 }, { 5772, 500, 1, 1 }, { 2901, 81, 1, -1 } }
function GetMerchantNumItems() return #M.merchant end
function GetMerchantItemID(i) return M.merchant[i][1] end
C_MerchantFrame = {}
function C_MerchantFrame.GetItemInfo(i) local m = M.merchant[i]; return { price = m[2], stackCount = m[3], numAvailable = m[4], hasExtendedCost = false } end

----------------------------------------------------------------------
-- Map
----------------------------------------------------------------------
local function vec(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
CreateVector2D = vec
C_Map = {}
function C_Map.GetBestMapForUnit() return M.player.map end
function C_Map.GetPlayerMapPosition(map) if map ~= M.player.map then return nil end return vec(M.player.x, M.player.y) end
function C_Map.GetMapInfo(id) return { name = id == 1413 and "The Barrens" or ("Zone " .. id), mapID = id } end
-- 1413 is 10000 yards wide (west) and 6666 tall (south); north/west increase the other way
function C_Map.GetWorldPosFromMapPos(map, v) return 1, vec(-v.y * 6666, -v.x * 10000) end
function C_Map.CanSetUserWaypointOnMap() return true end
function C_Map.SetUserWaypoint(p) M.waypoint = p end
function C_Map.ClearUserWaypoint() M.waypoint = nil end
UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map = map, x = x, y = y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
C_Spell = { GetSpellName = function(id) return ({ [2575] = "Mining", [2366] = "Herb Gathering", [7620] = "Fishing", [2657] = "Smelt Copper" })[id] end }

TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn) M.tooltipHook = fn end,
    AddLinePreCall = function(lineType, fn) M.linePreCalls = M.linePreCalls or {}; M.linePreCalls[lineType] = fn end,
}
Enum.TooltipDataLineType = { SellPrice = 11 }

----------------------------------------------------------------------
-- Selling: per-item search results and posting
----------------------------------------------------------------------
for _, e in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_AUCTION_CREATED",
    "AUCTION_HOUSE_POST_WARNING", "AUCTION_HOUSE_POST_ERROR", "AUCTION_HOUSE_SHOW_ERROR", "AUCTION_MULTISELL_FAILURE" }) do
    KNOWN_EVENTS[e] = true
end
Enum.ItemCommodityStatus = { Unknown = 0, Item = 1, Commodity = 2 }
Enum.AuctionHouseSortOrder.Buyout = 4
ItemLocation = {}
function ItemLocation:CreateFromBagAndSlot(bag, slot) return { bag = bag, slot = slot } end
function C_Item.DoesItemExist(loc) return M.bags[loc.slot] ~= nil end
function C_Item.GetItemID(loc) return M.bags[loc.slot][1] end
function C_Item.GetItemMaxStackSizeByID() return 20 end

-- M.market[itemID] = { { price, quantity, mine }, ... }
M.market = {}
M.posted = {}
local function isCommodity(id) local c = M.items[id] and M.items[id][4]; return c == 7 or c == 0 end
function C_AuctionHouse.MakeItemKey(id) return { itemID = id, itemLevel = 0, itemSuffix = 0 } end
function C_AuctionHouse.GetItemKeyFromItem(loc) return { itemID = M.bags[loc.slot][1], itemLevel = 10, itemSuffix = 0 } end
function C_AuctionHouse.IsSellItemValid(loc, showError) assert(showError == false); return true end
function C_AuctionHouse.GetItemCommodityStatus(loc) return isCommodity(M.bags[loc.slot][1]) and 2 or 1 end
function C_AuctionHouse.GetAvailablePostCount() return 1 end
function C_AuctionHouse.SupportsCopperValues() return true end
function C_AuctionHouse.SendSearchQuery(key, sorts, separate)
    assert(type(key) == "table" and key.itemID and type(sorts) == "table" and type(separate) == "boolean", "bad search query")
    M.searches = (M.searches or 0) + 1
    if M.searchSilent then return end
    C_Timer.After(0.2, function()
        if isCommodity(key.itemID) then M.fire("COMMODITY_SEARCH_RESULTS_UPDATED", key.itemID)
        else M.fire("ITEM_SEARCH_RESULTS_UPDATED", key) end
    end)
end
function C_AuctionHouse.GetNumCommoditySearchResults(id) return #(M.market[id] or {}) end
function C_AuctionHouse.GetCommoditySearchResultInfo(id, i)
    local l = M.market[id][i]
    return { itemID = id, unitPrice = l[1], quantity = l[2], containsOwnerItem = l[3] or false, containsAccountItem = false }
end
function C_AuctionHouse.GetNumItemSearchResults(key) return #(M.market[key.itemID] or {}) end
function C_AuctionHouse.GetItemSearchResultInfo(key, i)
    local l = M.market[key.itemID][i]
    return { itemKey = key, buyoutAmount = l[1] * l[2], quantity = l[2], containsOwnerItem = l[3] or false, containsAccountItem = false }
end
function C_AuctionHouse.CalculateCommodityDeposit(id, duration, qty) assert(type(id) == "number" and duration >= 1 and duration <= 3); return qty * 2 end
function C_AuctionHouse.CalculateItemDeposit(loc, duration, qty) assert(type(loc) == "table"); return 5 * qty end
local function created() C_Timer.After(0.3, function() M.fire("AUCTION_HOUSE_AUCTION_CREATED", 4242) end) end
function C_AuctionHouse.PostCommodity(loc, duration, qty, price)
    assert(type(loc) == "table" and qty >= 1 and price >= 1 and price == math.floor(price), "bad PostCommodity")
    if M.needConfirm then M.posted[#M.posted + 1] = { kind = "warn", id = M.bags[loc.slot][1] }; return true end
    M.posted[#M.posted + 1] = { kind = "commodity", id = M.bags[loc.slot][1], qty = qty, price = price, duration = duration }
    created()
    return false
end
function C_AuctionHouse.ConfirmPostCommodity(loc, duration, qty, price)
    M.posted[#M.posted + 1] = { kind = "commodity-confirmed", id = M.bags[loc.slot][1], qty = qty, price = price, duration = duration }
    created()
end
function C_AuctionHouse.PostItem(loc, duration, qty, bid, buyout)
    assert(type(loc) == "table" and bid == nil and buyout >= 1 and buyout == math.floor(buyout), "bad PostItem")
    M.posted[#M.posted + 1] = { kind = "item", id = M.bags[loc.slot][1], qty = qty, price = buyout, duration = duration }
    created()
    return false
end
function C_AuctionHouse.ConfirmPostItem() end
function StaticPopup_Hide(which) M.popupHidden = which end

-- Report (once) any global the addon reads that this mock doesn't define.
setmetatable(_G, { __index = function(_, k) M.undefined[k] = true return nil end })


----------------------------------------------------------------------
-- Kill and loot tracker support
----------------------------------------------------------------------
-- M.loot = { { type = 1 (item) | 2 (money), id =, qty =, src = guid }, ... }
M.loot = {}
function GetNumLootItems() return #M.loot end
function GetLootSlotType(i) local l = M.loot[i]; return l and l.type or 0 end
function GetLootSlotLink(i) local l = M.loot[i]; return l and l.id and ("|cffffffff|Hitem:" .. l.id .. "::::|h[x]|h|r") or nil end
function GetLootSlotInfo(i) local l = M.loot[i]; return 134400, "x", l and l.qty or 0, nil, l and l.quality or 1, false, l and l.quest or false end
function GetLootSourceInfo(i) local l = M.loot[i]; return l and l.src, 1 end
-- M.units[unit] = { guid =, name =, dead =, tapDenied =, player = }
M.units = {}
function UnitIsDead(u) local x = M.units[u]; return x and x.dead or false end
function UnitIsPlayer(u) local x = M.units[u]; return x and x.player or false end
function UnitCanAttack(a, u) return M.units[u] ~= nil end
function UnitIsTapDenied(u) local x = M.units[u]; return x and x.tapDenied or false end
do
    local guid, name = UnitGUID, UnitName
    UnitGUID = function(u) local x = M.units[u]; if x then return x.guid end return guid(u) end
    UnitName = function(u) local x = M.units[u]; if x then return x.name end return name(u) end
end
-- M.inbox[i] = { invoice = "seller", item =, count =, money = }
M.inbox = {}
function GetInboxInvoiceInfo(i) local m = M.inbox[i]; if not m then return nil end
    return m.invoice, m.item, "Buyer", 0, 0, 0, 0, 0, 0, 0, m.count end
function GetInboxHeaderInfo(i) local m = M.inbox[i]; return nil, nil, "Auction House", "Sold", m and m.money or 0 end
-- like the real client: the money arrives a moment after you click
function TakeInboxMoney(i)
    local m = M.inbox[i]
    if m and m.money > 0 then
        local amount = m.money
        m.money = 0
        C_Timer.After(0.2, function() M.player.money = M.player.money + amount; M.fire("PLAYER_MONEY") end)
    end
end
function AutoLootMailItem(i) TakeInboxMoney(i) end

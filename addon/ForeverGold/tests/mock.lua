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
for _, e in ipairs({ "ADDON_LOADED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "GET_ITEM_INFO_RECEIVED", "MERCHANT_SHOW",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
    "AUCTION_HOUSE_BROWSE_FAILURE", "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "OWNED_AUCTIONS_UPDATED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "CURSOR_CHANGED", "TRADE_CLOSED", "PLAYER_MONEY", "SKILL_LINES_CHANGED", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED",
    "LOOT_READY", "LOOT_OPENED", "NEW_RECIPE_LEARNED", "UNIT_HEALTH", "LOOT_SLOT_CLEARED", "LOOT_CLOSED",
    "MAIL_SHOW", "MAIL_CLOSED", "MERCHANT_CLOSED", "PLAYER_LOGOUT", "AUCTION_HOUSE_AUCTION_CREATED", "PLAYER_DEAD",
    "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_TURNED_IN", "MAP_EXPLORATION_UPDATED" }) do
    KNOWN_EVENTS[e] = true
end

M.knownEvents = KNOWN_EVENTS -- other addons' tests (Forever UI) add their own

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
function methods:SetAttribute(k, v) self._attributes = self._attributes or {}; self._attributes[k] = v end
function methods:GetAttribute(k) return self._attributes and self._attributes[k] end
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
function methods:CreateMaskTexture() return newWidget("MaskTexture", nil, self) end
function methods:AddMaskTexture(mask) self._masks = self._masks or {}; self._masks[mask] = true end
function methods:RemoveMaskTexture(mask) if self._masks then self._masks[mask] = nil end end
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
function methods:SetScale(s) self._scale = s end
function methods:GetScale() return self._scale or 1 end
function methods:GetStringHeight() return 12 * math.max(1, math.ceil(#self._text / 110)) end
function methods:GetCenter() return 100, 100 end
function methods:GetLeft() return 900 end
function methods:GetTop() return 700 end
function methods:GetBottom() return 90 end
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
    self._points = self._points or {}
    self._points[#self._points + 1] = { point, ... }
end
function methods:ClearAllPoints() self._points = {} end
function methods:GetPoint(i)
    local p = self._points and self._points[i or 1]
    if p then return unpack(p) end
end
function methods:SetStartPoint(point, rel, x, y) assert(type(x) == "number" and type(y) == "number" and x == x and y == y, "bad line start") end
function methods:SetEndPoint(point, rel, x, y) assert(type(x) == "number" and type(y) == "number" and x == x and y == y, "bad line end") end
function methods:SetColorTexture(r, g, b, a) assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "SetColorTexture needs numbers"); self._color = { r, g, b, a } end
function methods:SetTexture(t) assert(t ~= nil, "SetTexture(nil)"); self._texture = t end
function methods:SetAtlas(a) assert(type(a) == "string", "SetAtlas needs a name"); self._atlas = a end
function methods:SetOwner(owner, anchor) assert(owner ~= nil and type(anchor) == "string", "SetOwner") ; self._lines = {} end
function methods:AddLine(text) assert(type(text) == "string", "AddLine needs text, got " .. type(text)); self._lines = self._lines or {}; self._lines[#self._lines + 1] = text end
function methods:AddDoubleLine(l, r) assert(type(l) == "string" and type(r) == "string", "AddDoubleLine needs two strings"); self._lines = self._lines or {}; self._lines[#self._lines + 1] = l .. "  ||  " .. r end
function methods:SetItemByID(id) assert(type(id) == "number", "SetItemByID") end
function methods:SetUnit() end
function methods:GetCanvas() self._canvas = self._canvas or newWidget("Frame", nil, self); self._canvas._w, self._canvas._h = 1002, 668; return self._canvas end
function methods:GetMapID() return 1413 end
function methods:SetScale(s) assert(type(s) == "number" and s > 0, "SetScale needs a positive number"); self._scale = s end
function methods:GetScale() return self._scale or 1 end
function methods:SetAlpha(a) assert(type(a) == "number", "SetAlpha needs a number"); self._alpha = a end
function methods:GetAlpha() return self._alpha or 1 end
function methods:EnableMouse(on) self._mouse = on and true or false end
function methods:SetGradient(orientation, lo, hi)
    assert((orientation == "VERTICAL" or orientation == "HORIZONTAL") and type(lo) == "table" and type(hi) == "table",
        "SetGradient needs an orientation and two colours")
    self._gradient = { lo = lo, hi = hi }
end
function methods:Click(which) if self._scripts.OnClick then self._scripts.OnClick(self, which or "LeftButton") end end

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
    if template == "ContainerFrameItemButtonTemplate" then
        -- the real template's blue store highlight starts out shown (no hidden="true")
        w.BattlepayItemTexture = w:CreateTexture(nil, "OVERLAY")
        w.BattlepayItemTexture:Show()
        w.BagIndicator = w:CreateTexture(nil, "OVERLAY")
        w.BagIndicator:Hide()
    end
    return w
end

UIParent = newWidget("Frame", "UIParent")
WorldFrame = newWidget("Frame", "WorldFrame"); WorldFrame._h = 900; WorldFrame._w = 1600
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
function GetCursorPosition() return M.cursorX or 300, M.cursorY or 300 end
function GetLocale() return "enUS" end
function IsShiftKeyDown() return M.shift end
function IsFishingLoot() return M.fishing end
-- Herbalism rides in the archaeology slot (6) so a test can take it away (M.herbalism = false).
function GetProfessions() return 1, 2, M.herbalism ~= false and 6 or nil, 3, 4, 5 end
local PROFS = { { "Blacksmithing", 120, 150, 164 }, { "Mining", 98, 150, 186 }, { "Fishing", 60, 150, 356 }, { "Cooking", 80, 150, 185 },
    { "First Aid", 70, 150, 129 }, { "Herbalism", 90, 150, 182 } }
-- M.lostProf = "Mining": this character doesn't have it.
function GetProfessionInfo(i) local p = PROFS[i]; if p and p[1] ~= M.lostProf then return p[1], 1, p[2], p[3], 0, 0, p[4] end end

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
    [12348] = { "Large Axe", 1, 121, 2 },
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
-- Recipe items' subclass is the profession they teach (2 = Tailoring).
M.itemSub = { [5772] = 2 }
function C_Item.GetItemInfoInstant(id)
    local it = M.items[id]
    if not it then return nil end
    return id, "", "", "", 134400, it[4], M.itemSub[id] or 0
end
-- Dressing room: weapons (2) and armour (4) can be tried on; Ctrl is the DRESSUP modifier.
function C_Item.IsDressableItemByID(link)
    local id = type(link) == "number" and link or tonumber(tostring(link):match("item:(%d+)"))
    local it = id and M.items[id]
    return it ~= nil and (it[4] == 2 or it[4] == 4)
end
function IsModifiedClick(what) return what == "DRESSUP" and M.ctrl or false end
M.dressed = {}
function DressUpItemLink(link) M.dressed[#M.dressed + 1] = link; return true end
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
    return { itemID = b[1], stackCount = b[2], isBound = b[3] or false, isLocked = b[4] or false }
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
    AuctionHouseFilter = { UncollectedOnly = 1, UsableOnly = 2, ExactMatch = 5, PoorQuality = 6, CommonQuality = 7, UncommonQuality = 8, RareQuality = 9, EpicQuality = 10, LegendaryQuality = 11, ArtifactQuality = 12 },
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
    local list = AHS.list or M.auctions
    for i = 1, 3 do
        local a = list[AHS.pos + i]
        if a then
            out[#out + 1] = { itemKey = { itemID = a[1], itemLevel = 10, itemSuffix = a[4] or 0, battlePetSpeciesID = 0 }, minPrice = a[2], totalQuantity = a[3] }
        end
    end
    AHS.pos = AHS.pos + 3
    for _, r in ipairs(out) do AHS.results[#AHS.results + 1] = r end
    return out
end
C_AuctionHouse = {}
-- M.throttle = false: the auction house is busy ("you are doing that too fast").
function C_AuctionHouse.IsThrottledMessageSystemReady() return M.throttle ~= false end
function C_AuctionHouse.SendBrowseQuery(q)
    assert(type(q) == "table" and type(q.searchString) == "string" and type(q.filters) == "table" and #q.sorts == 2, "bad browse query")
    M.queries = (M.queries or 0) + 1
    M.lastBrowse = q
    M.browseCount = (M.browseCount or 0) + 1
    AHS.pos, AHS.results = 0, {}
    AHS.list = nil
    if q.searchString ~= "" then
        -- a name search: only the matching items
        AHS.list = {}
        for _, a in ipairs(M.auctions) do
            local it = M.items[a[1]]
            if it and it[1]:lower():find(q.searchString:lower(), 1, true) then AHS.list[#AHS.list + 1] = a end
        end
    end
    C_Timer.After(0.3, function() page(); M.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end)
end
function C_AuctionHouse.RequestMoreBrowseResults()
    M.more = (M.more or 0) + 1
    C_Timer.After(0.2, function() local p = page(); if #p > 0 then M.fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", p) end end)
end
function C_AuctionHouse.GetBrowseResults() return AHS.results end
function C_AuctionHouse.HasFullBrowseResults() return AHS.pos >= #(AHS.list or M.auctions) end
function C_AuctionHouse.QueryOwnedAuctions(sorts)
    assert(type(sorts) == "table")
    M.ownedQueries = (M.ownedQueries or 0) + 1
    C_Timer.After(0.1, function() M.fire("OWNED_AUCTIONS_UPDATED") end)
end
function C_AuctionHouse.GetOwnedAuctions()
    return M.owned or { { auctionID = 501, itemKey = { itemID = 2840 }, status = 0, quantity = 5, buyoutAmount = 600, timeLeftSeconds = 40000 } }
end
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
function C_Map.GetMapInfo(id)
    if id == 1414 then return { name = "Kalimdor", mapID = id, mapType = 2, parentMapID = 947 } end
    return { name = id == 1413 and "The Barrens" or ("Zone " .. id), mapID = id, mapType = 3,
        parentMapID = id == 1413 and 1414 or nil }
end
-- 1413 is 10000 yards wide (west) and 6666 tall (south); north/west increase the other way
function C_Map.GetWorldPosFromMapPos(map, v) return 1, vec(-v.y * 6666, -v.x * 10000) end
function C_Map.CanSetUserWaypointOnMap() return true end
-- The Barrens (art 1194 here) has one explored area; the rest comes from the reveal data.
function C_Map.GetMapArtID(map) return map == 1413 and 1194 or nil end
C_MapExplorationInfo = {}
function C_MapExplorationInfo.GetExploredMapTextures(map)
    if map ~= 1413 then return nil end
    return { { textureWidth = 445, textureHeight = 160, offsetX = 244, offsetY = 0, fileDataIDs = { 271435, 271442 },
        isShownByMouseOver = false } }
end
-- The Barrens has a map picture (4 x 3 tiles of 256); other zones don't.
function C_Map.GetMapArtLayers(map)
    if map ~= 1413 then return nil end
    return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } }
end
function C_Map.GetMapArtLayerTextures(map, layer)
    assert(layer == 1, "layer index starts at 1")
    local t = {}
    for i = 1, 12 do t[i] = 100000 + i end
    return t
end
function C_Map.SetUserWaypoint(p) M.waypoint = p; M.waypointSets = (M.waypointSets or 0) + 1 end
function C_Map.ClearUserWaypoint() M.waypoint = nil; if M.tracking == "waypoint" then M.tracking = nil end end
function C_Map.HasUserWaypoint() return M.waypoint ~= nil end
function C_Map.GetUserWaypoint() return M.waypoint end
UiMapPoint = { CreateFromCoordinates = function(map, x, y)
    return { map = map, x = x, y = y, uiMapID = map, position = vec(x, y) }
end }
-- M.tracking: "waypoint" when the map pin is tracked, or "quest" etc. for something else.
C_SuperTrack = {
    SetSuperTrackedUserWaypoint = function(on) M.tracking = on and "waypoint" or nil end,
    IsSuperTrackingUserWaypoint = function() return M.tracking == "waypoint" end,
    IsSuperTrackingAnything = function() return M.tracking ~= nil end,
}
-- The game's on-screen waypoint marker (follows the tracked pin).
Enum.NavigationState = { Invalid = 0, Occluded = 1, InRange = 2, Disabled = 3 }
M.navFrame = newWidget("Frame", nil, nil)
-- Where the game's waypoint marker is on screen (WorldFrame is 1600 x 900).
M.navFrame.GetCenter = function() return M.navX or 800, M.navY or 300 end
M.navDistance = 60
C_Navigation = {
    GetFrame = function() return (M.tracking == "waypoint" and not M.navGone) and M.navFrame or nil end,
    GetDistance = function() return M.navDistance end,
    GetTargetState = function() return M.navState or 2 end,
    HasValidScreenPosition = function() return not M.navOffscreen end,
    WasClampedToScreen = function() return M.navOffscreen and true or false end,
}
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
-- Game settings (console variables): only the ones this client has.
M.cvars = { rotateMinimap = "0", softTargetInteract = "1", SoftTargetIconInteract = "1", SoftTargetIconGameObject = "0",
    SoftTargetNameplateInteract = "0" }
function GetCVar(name) return M.cvars[name] end
function SetCVar(name, value)
    assert(type(name) == "string" and value ~= nil, "SetCVar needs a name and a value")
    if M.cvars[name] == nil then return false end
    M.cvars[name] = tostring(value)
    return true
end
function InCombatLockdown() return M.combat or false end
-- The thing the Interact Key has picked out (M.units.softinteract) wears a nameplate.
M.softPlate = newWidget("Frame", nil, nil)
C_NamePlate = { GetNamePlateForUnit = function(unit)
    if unit == "softinteract" and M.units and M.units.softinteract then return M.softPlate end
    return nil
end }
C_Spell = { GetSpellName = function(id) return ({ [2575] = "Mining", [2366] = "Herb Gathering", [7620] = "Fishing", [2657] = "Smelt Copper", [3365] = "Opening", [2383] = "Find Herbs", [2580] = "Find Minerals" })[id] end }

TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn) M.tooltipHook = fn end,
    AddLinePreCall = function(lineType, fn) M.linePreCalls = M.linePreCalls or {}; M.linePreCalls[lineType] = fn end,
}
Enum.TooltipDataLineType = { SellPrice = 11 }

----------------------------------------------------------------------
-- Selling: per-item search results and posting
----------------------------------------------------------------------
for _, e in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_AUCTION_CREATED",
    "AUCTION_HOUSE_POST_WARNING", "AUCTION_HOUSE_POST_ERROR", "AUCTION_HOUSE_SHOW_ERROR", "AUCTION_MULTISELL_FAILURE",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" }) do
    KNOWN_EVENTS[e] = true
end
Enum.AuctionHouseError = { NotEnoughMoney = 0, HigherBid = 1, BidIncrement = 2, BidOwn = 3, ItemNotFound = 4,
    RestrictedAccountTrial = 5, HasRestriction = 6, IsBusy = 7, Unavailable = 8, ItemHasQuote = 9, DatabaseError = 10 }
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
    -- l[5]: the seller (or a list of sellers at that price)
    local owners = type(l[5]) == "table" and l[5] or { l[5] or (l[3] and "Me" or "Someone") }
    return { itemID = id, unitPrice = l[1], quantity = l[2], containsOwnerItem = l[3] or false, containsAccountItem = false,
        owners = owners, totalNumberOfOwners = #owners, numOwnerItems = l[3] and l[2] or 0 }
end
function C_AuctionHouse.GetNumItemSearchResults(key) return #(M.market[key.itemID] or {}) end
function C_AuctionHouse.GetItemSearchResultInfo(key, i)
    local l = M.market[key.itemID][i]
    -- l[4]: the next bid that would be accepted, for the whole auction
    return { itemKey = key, auctionID = key.itemID * 100 + i, buyoutAmount = l[1] * l[2], quantity = l[2],
        containsOwnerItem = l[3] or false, containsAccountItem = false, owners = { l[5] or (l[3] and "player" or "Someone") },
        totalNumberOfOwners = 1,
        timeLeftSeconds = 7200 * i, timeLeft = 2, minBid = l[4] }
end
function C_AuctionHouse.CalculateCommodityDeposit(id, duration, qty) assert(type(id) == "number" and duration >= 1 and duration <= 3); return qty * 2 end
function C_AuctionHouse.CalculateItemDeposit(loc, duration, qty) assert(type(loc) == "table"); return 5 * qty end
-- M.postSilent: the post is sent but the answer never comes.
local function created()
    if M.postSilent then return end
    C_Timer.After(0.3, function() M.fire("AUCTION_HOUSE_AUCTION_CREATED", 4242) end)
end
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

----------------------------------------------------------------------
-- Buying and cancelling
----------------------------------------------------------------------
for _, e in ipairs({ "AUCTION_CANCELED", "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
    "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_PURCHASE_COMPLETED" }) do
    KNOWN_EVENTS[e] = true
end
function C_AuctionHouse.GetItemKeyInfo(key)
    M.keyInfoCalls = (M.keyInfoCalls or 0) + 1
    local it = M.items[key.itemID]
    if not it then return nil end
    return { itemID = key.itemID, itemName = it[1], quality = it[2], iconFileID = 134400, isCommodity = isCommodity(key.itemID), isEquipment = it[4] == 4 }
end
M.cancelled, M.bought, M.bids = {}, {}, {}
function C_AuctionHouse.CanCancelAuction(id) assert(type(id) == "number"); return true end
function C_AuctionHouse.GetCancelCost(id) assert(type(id) == "number"); return 30 end
function C_AuctionHouse.CancelAuction(id)
    assert(type(id) == "number", "bad CancelAuction")
    M.cancelled[#M.cancelled + 1] = id
    C_Timer.After(0.2, function() M.fire("AUCTION_CANCELED", id) end)
end
-- Buying stackable goods: ask for a quote, then confirm it.
function C_AuctionHouse.StartCommoditiesPurchase(id, qty)
    assert(type(id) == "number" and type(qty) == "number" and qty >= 1, "bad StartCommoditiesPurchase")
    M.quoteFor = { id = id, qty = qty }
    C_Timer.After(0.2, function()
        local left, total = qty, 0
        for _, l in ipairs(M.market[id] or {}) do
            if not l[3] then
                local take = math.min(left, l[2])
                total, left = total + take * l[1], left - take
            end
            if left <= 0 then break end
        end
        if left > 0 then M.fire("COMMODITY_PRICE_UNAVAILABLE") return end
        M.fire("COMMODITY_PRICE_UPDATED", math.floor(total / qty), total)
    end)
end
-- M.buyError = code: the game refuses on the spot, firing the error before
-- the call returns. M.buySilent: no answer ever comes. M.buyLate: the answer
-- comes after 30 seconds.
local function buyAnswer(event, arg)
    if M.buySilent then return end
    C_Timer.After(M.buyLate and 30 or 0.2, function() M.fire(event, arg) end)
end
function C_AuctionHouse.ConfirmCommoditiesPurchase(id, qty)
    assert(M.quoteFor and M.quoteFor.id == id and M.quoteFor.qty == qty, "confirm without a matching quote")
    M.quoteFor = nil
    if M.buyError then M.fire("AUCTION_HOUSE_SHOW_ERROR", M.buyError) return end
    M.bought[#M.bought + 1] = { id = id, qty = qty }
    buyAnswer("COMMODITY_PURCHASE_SUCCEEDED")
end
function C_AuctionHouse.CancelCommoditiesPurchase() M.quoteFor = nil end
function C_AuctionHouse.PlaceBid(aid, amount)
    assert(type(aid) == "number" and type(amount) == "number" and amount >= 1, "bad PlaceBid")
    if M.buyError then M.fire("AUCTION_HOUSE_SHOW_ERROR", M.buyError) return end
    M.bids[#M.bids + 1] = { aid = aid, amount = amount }
    buyAnswer("AUCTION_HOUSE_PURCHASE_COMPLETED", aid)
end
AuctionHouseUtil = { GetErrorText = function(e)
    return ({ [10] = "Internal auction error", [7] = "The auction house is busy" })[e]
end }
-- The game's category list (Blizzard_AuctionHouseUI)
AuctionCategories = {
    { name = "Weapons", filters = { { classID = 2 } }, subCategories = { { name = "Swords", filters = { { classID = 2, subClassID = 7 } } } } },
    { name = "Trade Goods", filters = { { classID = 7 } }, subCategories = { { name = "Metal & Stone", filters = { { classID = 7, subClassID = 7 } } } } },
}

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
    local level = UnitLevel
    UnitLevel = function(u) local x = M.units[u]; if x then return x.level end return level(u) end
end
function IsInInstance() return M.inInstance or false end

----------------------------------------------------------------------
-- Mailbox: inbox, send mail, and a server that answers (or doesn't)
----------------------------------------------------------------------
for _, e in ipairs({ "MAIL_INBOX_UPDATE", "MAIL_SUCCESS", "MAIL_FAILED", "MAIL_SEND_SUCCESS", "MAIL_SEND_INFO_UPDATE",
    "MAIL_LOCK_SEND_ITEMS", "MAIL_UNLOCK_SEND_ITEMS", "SECURE_TRANSFER_CONFIRM_SEND_MAIL",
    "SECURE_TRANSFER_CONFIRM_TAKE_MAIL_MONEY", "SECURE_TRANSFER_CANCEL", "UI_ERROR_MESSAGE", "CLOSE_INBOX_ITEM" }) do
    KNOWN_EVENTS[e] = true
end
ATTACHMENTS_MAX_SEND, ATTACHMENTS_MAX_RECEIVE, ATTACHMENTS_MAX = 12, 16, 16
MailFrame = newWidget("Frame", "MailFrame"); MailFrame._shown = false
OpenMailFrame = newWidget("Frame", "OpenMailFrame"); OpenMailFrame._shown = false
CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.5, 0, 0.25 }, PALADIN = { 0, 0.25, 0.5, 0.75 } }
function HideUIPanel(f) f:Hide() end
function CloseMail() M.fire("MAIL_CLOSED") end

-- Item subclasses (trade goods: 5 cloth, 6 leather, 7 metal & stone, 9 herb)
for id, sub in pairs({ [2770] = 7, [2840] = 7, [2771] = 7, [3576] = 7, [2841] = 7, [2835] = 7, [2836] = 7, [2775] = 7,
    [2842] = 7, [2589] = 5, [765] = 9,
    [12346] = 3, [12347] = 1, [12348] = 1, [2853] = 3 }) do -- mail boots, cloth cloak, axe, mail bracers
    M.items[id][6] = sub
end
M.items[2996] = { "Bolt of Linen Cloth", 1, 40, 7, 0, 5 }
M.items[2318] = { "Light Leather", 1, 15, 7, 0, 6 }
M.items[2447] = { "Peacebloom", 1, 4, 7, 0, 9 }
M.items[5056] = { "Quest Letter", 1, 0, 12 }
do
    local get = C_Item.GetItemInfo
    function C_Item.GetItemInfo(id)
        local r = { get(id) }
        local it = M.items[id]
        if r[1] and it then r[13] = it[6] or 0 end
        return unpack(r, 1, 14)
    end
end

-- Bags: M.bags[slot] = { id, count, bound, locked, quest = true }
function C_Container.GetContainerNumSlots(bag) if bag == 0 then return M.bagSlots or 16 end return 0 end
function C_Container.GetContainerItemQuestInfo(bag, slot)
    local b = bag == 0 and M.bags[slot]
    return { isQuestItem = b and b.quest or false, isActive = false }
end
function C_Container.CalculateTotalNumberOfFreeBagSlots()
    local n = 0
    for s = 1, M.bagSlots or 16 do if not M.bags[s] then n = n + 1 end end
    return n
end
local function freeSlot()
    for s = 1, M.bagSlots or 16 do if not M.bags[s] then return s end end
end
M.cursor = nil
function C_Container.PickupContainerItem(bag, slot)
    local b = bag == 0 and M.bags[slot]
    if M.cursor then M.cursor = nil return end
    if b and not b[4] then M.cursor = { bag = bag, slot = slot } end
end
function ClearCursor() M.cursor = nil end
function CursorHasItem() return M.cursor ~= nil end

-- M.inbox[i] = { sender, subject, money, cod, days, items = { [a] = { id, count } }, gm, body, invoice,
--                item, count (the invoice's), read, keep (don't delete it when emptied) }
M.inbox = {}
M.mailLog = {}  -- every mail command anyone sent: { what = name, ... }
M.takeDelay, M.takeMode = 0.3, "ok"     -- takeMode: ok | silent | fail
M.sendDelay, M.sendMode = 0.5, "ok"     -- sendMode: ok | fail | silent | lost (it goes, but no answer)
M.attachDelay = 0                        -- attachments show up this long after the click
M.mailBusy = false                       -- the server is busy with something else
local pending = 0
local function log(what, ...) M.mailLog[#M.mailLog + 1] = { what = what, ... } end
function M.MailCount(what) local n = 0; for _, l in ipairs(M.mailLog) do if l.what == what then n = n + 1 end end; return n end

local function inboxItems(m)
    local n = 0
    for a = 1, 16 do if m.items and m.items[a] then n = n + 1 end end
    return n
end
function GetInboxNumItems() return #M.inbox, M.inboxTotal or #M.inbox end
function GetInboxInvoiceInfo(i) local m = M.inbox[i]; if not m or not m.invoice then return nil end
    return m.invoice, m.item, "Buyer", 0, 0, 0, 0, 0, 0, 0, m.count end
function GetInboxHeaderInfo(i)
    local m = M.inbox[i]
    if not m then return nil end
    local first
    for a = 1, 16 do if m.items and m.items[a] then first = m.items[a]; break end end
    return "Interface\\Icons\\INV_Letter_15", "Interface\\Icons\\INV_Letter_15", m.sender or "Auction House",
        m.subject or "Sold", m.money or 0, m.cod or 0, m.days or 29.5, inboxItems(m), m.read or false, m.returned or false,
        true, true, m.gm or false, first and first[2], nil
end
function HasInboxItem(i, a) local m = M.inbox[i]; return (m and m.items and m.items[a] ~= nil) or false end
function GetInboxItem(i, a)
    local m = M.inbox[i]
    local it = m and m.items and m.items[a]
    if not it then return nil end
    local d = M.items[it[1]]
    return d and d[1] or "Item", it[1], 130000 + it[1] % 1000, it[2], d and d[2] or 1, true, false
end
function GetInboxText(i) local m = M.inbox[i]; if m then m.read = true; return m.body or "" end end
local function maybeDelete(m)
    if not m.keep and (m.money or 0) == 0 and inboxItems(m) == 0 and (m.body or "") == "" then
        for j, x in ipairs(M.inbox) do if x == m then table.remove(M.inbox, j) break end end
    end
end
local function settle(fn, delay)
    pending = pending + 1
    C_Timer.After(delay, function() pending = pending - 1; fn() end)
end
-- like the real client: the money arrives a moment after you click
function TakeInboxMoney(i)
    local m = M.inbox[i]
    log("TakeInboxMoney", i, m and m.subject)
    if not m or (m.money or 0) <= 0 then return end
    if M.takeMode == "silent" then return end
    settle(function()
        if M.takeMode == "fail" then M.fire("MAIL_FAILED"); return end
        local amount = m.money
        m.money = 0
        M.player.money = M.player.money + amount
        M.fire("PLAYER_MONEY")
        maybeDelete(m)
        M.fire("MAIL_INBOX_UPDATE")
    end, M.takeDelay)
end
function TakeInboxItem(i, a)
    local m = M.inbox[i]
    log("TakeInboxItem", i, a, m and m.subject)
    local it = m and m.items and m.items[a]
    if not it then return end
    if (m.cod or 0) > 0 then M.codPaid = true end
    if M.takeMode == "silent" then return end
    settle(function()
        local slot = freeSlot()
        if M.takeMode == "fail" or not slot then
            M.fire("UI_ERROR_MESSAGE", 3, "Inventory is full.")
            M.fire("MAIL_FAILED", it[1])
            return
        end
        if (m.cod or 0) > 0 then M.player.money = M.player.money - m.cod; m.cod = 0 end
        m.items[a] = nil
        M.bags[slot] = { it[1], it[2] }
        M.fire("MAIL_SUCCESS", it[1])
        M.fire("BAG_UPDATE_DELAYED")
        maybeDelete(m)
        M.fire("MAIL_INBOX_UPDATE")
    end, M.takeDelay)
end
function AutoLootMailItem(i) log("AutoLootMailItem", i); TakeInboxMoney(i) end
function ReturnInboxItem(i) log("ReturnInboxItem", i) end
function DeleteInboxItem(i) log("DeleteInboxItem", i) end
function CheckInbox() log("CheckInbox"); C_Timer.After(0.5, function() M.fire("MAIL_INBOX_UPDATE") end) end

-- Sending: M.send.atts[j] = { slot, id, count, at }
M.send = { atts = {}, money = 0, cod = 0 }
M.sentMail = {}
function SetSendMailShowing(on) M.send.showing = on end
function ClickSendMailItemButton(j, clear)
    local cur = M.send.atts[j]
    if clear then
        if cur and M.bags[cur.slot] then M.bags[cur.slot][4] = nil end
        M.send.atts[j] = nil
        return
    end
    if M.cursor then
        if cur and M.bags[cur.slot] then M.bags[cur.slot][4] = nil end
        local b = M.bags[M.cursor.slot]
        M.send.atts[j] = { slot = M.cursor.slot, id = b[1], count = b[2], at = M.clock + M.attachDelay }
        b[4] = true
        M.cursor = nil
    end
end
function HasSendMailItem(j) local a = M.send.atts[j]; return a ~= nil and M.clock >= a.at end
function GetSendMailItem(j)
    local a = M.send.atts[j]
    if not a or M.clock < a.at then return nil end
    return M.items[a.id] and M.items[a.id][1], a.id, 130000, a.count, 1
end
local function attCount() local n = 0; for j = 1, 16 do if M.send.atts[j] then n = n + 1 end end; return n end
function GetSendMailPrice() return 30 * math.max(1, attCount()) end
function SetSendMailMoney(c) M.send.money = c; return true end
function SetSendMailCOD(c) M.send.cod = c end
local function resetSend() M.send.atts, M.send.money, M.send.cod = {}, 0, 0 end
function SendMail(name, subject, body)
    local atts = {}
    for j = 1, 16 do local a = M.send.atts[j]; if a then atts[#atts + 1] = { id = a.id, count = a.count, slot = a.slot } end end
    local mail = { name = name, subject = subject, body = body, atts = atts, money = M.send.money, cod = M.send.cod,
        postage = GetSendMailPrice() }
    log("SendMail", mail)
    local mode = M.sendMode
    local function deliver()
        for _, a in ipairs(atts) do M.bags[a.slot] = nil end
        M.player.money = M.player.money - mail.postage - (mail.money or 0)
        M.sentMail[#M.sentMail + 1] = mail
        resetSend()
    end
    if mode == "silent" then return end
    if mode == "lost" then deliver(); M.fire("PLAYER_MONEY"); return end
    settle(function()
        if mode == "fail" then
            M.fire("UI_ERROR_MESSAGE", 2, "Cannot find player")
            M.fire("MAIL_FAILED")
            return
        end
        deliver()
        M.fire("PLAYER_MONEY")
        M.fire("MAIL_SEND_SUCCESS")
        M.fire("BAG_UPDATE_DELAYED")
    end, M.sendDelay)
end

C_Mail = {}
function C_Mail.IsCommandPending() return M.mailBusy or pending > 0 end
function C_Mail.CanCheckInbox() return true, 0 end
function C_Mail.HasInboxMoney(i) local m = M.inbox[i]; return m ~= nil and (m.money or 0) > 0 end
function C_Mail.IsCODEnabled() return true end

----------------------------------------------------------------------
-- The bag window: WoW Forever's bank tabs, new items, item button
-- helpers and the game's own (hidden) bag frames
----------------------------------------------------------------------
for _, e in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "BAG_UPDATE", "ITEM_LOCK_CHANGED",
    "BAG_UPDATE_COOLDOWN", "QUEST_ACCEPTED", "BAG_NEW_ITEMS_UPDATED" }) do
    KNOWN_EVENTS[e] = true
end
-- M.bank[slot] = { id, count } in bank tab 6, readable while M.bankOpen
M.bank = { { 2589, 20 }, nil, { 818, 2 } }
M.bankSlots = 8
Enum.BankType = { Character = 0, Guild = 1, Account = 2 }
C_Bank = {}
function C_Bank.FetchPurchasedBankTabData(t) assert(t == Enum.BankType.Character, "bank type"); return { { ID = 6, name = "Tab 1" } } end
function C_Bank.CanViewBank() return true end
local bagSlots = C_Container.GetContainerNumSlots
function C_Container.GetContainerNumSlots(bag)
    if bag == 6 then return M.bankOpen and M.bankSlots or 0 end
    return bagSlots(bag)
end
function C_Container.GetContainerItemInfo(bag, slot)
    local b = (bag == 0 and M.bags[slot]) or (bag == 6 and M.bankOpen and M.bank[slot]) or nil
    if not b then return nil end
    local it = M.items[b[1]]
    return { itemID = b[1], stackCount = b[2], isBound = b[3] or false, isLocked = b[4] or false,
        quality = it and it[2] or 1, iconFileID = 130000 + b[1] % 1000, hasNoValue = it ~= nil and it[3] == 0,
        hyperlink = "|cffffffff|Hitem:" .. b[1] .. "::::::::|h[" .. (it and it[1] or "?") .. "]|h|r" }
end
function C_Container.SortBags() M.sorted = (M.sorted or 0) + 1 end
function C_Container.SortBank(t) M.bankSorted = t end
M.used = {}
function C_Container.UseContainerItem(bag, slot) M.used[#M.used + 1] = { bag, slot } end
function C_Container.GetBagName(bag) return bag == 0 and "Backpack" or nil end
M.newItems = {}
C_NewItems = {}
function C_NewItems.IsNewItem(bag, slot) return M.newItems[bag .. ":" .. slot] or false end
function C_NewItems.ClearAll() M.newItems = {} end
function SetItemButtonTexture(b, t) b._icon = t end
function SetItemButtonCount(b, n) b._count = n end
function SetItemButtonQuality(b, q) b._quality = q end
function SetItemButtonDesaturated(b, d) b._desat = d end
function IsAltKeyDown() return M.alt or false end
ContainerFrameCombinedBags = CreateFrame("Frame", "ContainerFrameCombinedBags", UIParent)
ContainerFrameCombinedBags:Hide()
function OpenAllBags() ContainerFrameCombinedBags:Show() end
function CloseAllBags() ContainerFrameCombinedBags:Hide() end
function ToggleAllBags() if ContainerFrameCombinedBags:IsShown() then CloseAllBags() else OpenAllBags() end end
function methods:SetID(i) self._id = i end
function methods:GetID() return self._id or 0 end
-- the bag bar: more bags, bag families, the game's bag settings
for _, e in ipairs({ "BAG_SLOT_FLAGS_UPDATED", "PLAYER_EQUIPMENT_CHANGED" }) do
    KNOWN_EVENTS[e] = true
end
-- M.extraBags[bag] = { size =, fam =, id =, icon =, items = { [slot] = { id, count } } }
M.extraBags = {}
local numSlots2 = C_Container.GetContainerNumSlots
function C_Container.GetContainerNumSlots(bag)
    local x = M.extraBags[bag]
    if x then return x.size end
    return numSlots2(bag)
end
local itemInfo2 = C_Container.GetContainerItemInfo
function C_Container.GetContainerItemInfo(bag, slot)
    local x = M.extraBags[bag]
    if x then
        local b = x.items and x.items[slot]
        if not b then return nil end
        return { itemID = b[1], stackCount = b[2], quality = 1, iconFileID = 130001,
            hyperlink = "|cffffffff|Hitem:" .. b[1] .. "::::::::|h[?]|h|r" }
    end
    return itemInfo2(bag, slot)
end
function C_Container.GetContainerNumFreeSlots(bag)
    local x = M.extraBags[bag]
    if not x then return 0, 0 end
    local used = 0
    for _ in pairs(x.items or {}) do used = used + 1 end
    return x.size - used, x.fam or 0
end
function C_Container.ContainerIDToInventoryID(bag) return 30 + bag end
function GetInventoryItemID(unit, slot) local x = M.extraBags[slot - 30]; return x and x.id or nil end
function GetInventoryItemTexture(unit, slot) local x = M.extraBags[slot - 30]; return x and x.icon or nil end
Enum.BagSlotFlags = { DisableAutoSort = 1, ClassEquipment = 2, ClassConsumables = 4, ClassProfessionGoods = 8,
    ClassJunk = 16, ClassQuestItems = 32, ExcludeJunkSell = 64, ClassReagents = 128 }
M.bagFlags = {}
function C_Container.GetBagSlotFlag(bag, f) return M.bagFlags[bag .. ":" .. f] or false end
function C_Container.SetBagSlotFlag(bag, f, v) M.bagFlags[bag .. ":" .. f] = v or nil end
function C_Container.GetBackpackSellJunkDisabled() return M.backpackNoJunk or false end
function C_Container.SetBackpackSellJunkDisabled(v) M.backpackNoJunk = v end
function C_Container.GetBackpackAutosortDisabled() return M.backpackNoSort or false end
function C_Container.SetBackpackAutosortDisabled(v) M.backpackNoSort = v end
M.putInBag = {}
function PutItemInBag(slot) M.putInBag[#M.putInBag + 1] = slot end
function PutItemInBackpack() M.putInBag[#M.putInBag + 1] = "backpack" end
function PickupBagFromSlot(slot) M.pickedBag = slot end
StackSplitFrame = CreateFrame("Frame", "StackSplitFrame", UIParent)
StackSplitFrame:Hide()
-- scrolls are consumables, subclass 4 (the mage's Comprehension scrolls too)
M.items[211780] = { "Scroll: KWYJIBO", 1, 0, 0, 0, 4 }
M.items[954] = { "Scroll of Strength", 1, 25, 0, 0, 4 }
M.items[858] = { "Lesser Healing Potion", 1, 5, 0, 0, 1 }
-- the game's Options window (Settings): records categories, settings and controls
M.settings = { cats = {}, settings = {} }
local function newCat(name, parent)
    local c = { name = name, parent = parent, ID = 100 + #M.settings.cats, controls = {} }
    function c:GetID() return self.ID end
    M.settings.cats[#M.settings.cats + 1] = c
    local layout = {}
    function layout:AddInitializer(i) c.controls[#c.controls + 1] = i end
    return c, layout
end
Settings = { VarType = { Boolean = "boolean", Number = "number", String = "string" } }
function Settings.RegisterVerticalLayoutCategory(name) return newCat(name) end
function Settings.RegisterVerticalLayoutSubcategory(parent, name) return newCat(name, parent) end
function Settings.RegisterAddOnCategory(c) M.settings.addon = c end
function Settings.RegisterProxySetting(cat, variable, varType, name, default, get, set)
    assert(type(variable) == "string" and not M.settings.settings[variable], "duplicate setting " .. tostring(variable))
    assert(type(name) == "string" and type(get) == "function" and type(set) == "function", "proxy setting " .. variable)
    local s = { variable = variable, name = name, default = default, cat = cat, varType = varType }
    function s:GetValue() return get() end
    function s:SetValue(v) set(v) end
    M.settings.settings[variable] = s
    return s
end
function Settings.CreateCheckbox(cat, s) cat.controls[#cat.controls + 1] = { kind = "check", setting = s } end
function Settings.CreateDropdown(cat, s, opts) cat.controls[#cat.controls + 1] = { kind = "dropdown", setting = s, options = opts() } end
function Settings.CreateSlider(cat, s) cat.controls[#cat.controls + 1] = { kind = "slider", setting = s } end
function Settings.CreateSliderOptions() return { SetLabelFormatter = function() end } end
function Settings.CreateControlTextContainer()
    local d = {}
    return { Add = function(_, v, l) d[#d + 1] = { value = v, label = l } end, GetData = function() return d end }
end
function Settings.OpenToCategory(id) M.settings.opened = id end
function CreateSettingsListSectionHeaderInitializer(name) return { kind = "header", name = name } end
function CreateSettingsButtonInitializer(name, text, click) return { kind = "button", name = name, text = text, click = click } end
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
-- atlases the client ships (the bag frame's Cleanup button)
C_Texture = C_Texture or {}
function C_Texture.GetAtlasInfo(name) if name:match("^bags%-") or name:match("^raceicon%-") then return { width = 28, height = 26 } end end

----------------------------------------------------------------------
-- WoW Forever's bank bag slots: tab 1 is the bank, tabs 2+ hold a bag each
-- (the bag sits at Characterbanktab, i). M.bankTabs lists the bought tabs.
----------------------------------------------------------------------
for _, e in ipairs({ "BANK_TABS_CHANGED", "BAG_CONTAINER_UPDATE" }) do KNOWN_EVENTS[e] = true end
Enum.BagIndex = Enum.BagIndex or {}
Enum.BagIndex.Characterbanktab = -2
M.bankTabs = { { ID = 6, name = "Tab 1" } }
M.bankMax = 8
M.bankBag = nil -- { id, size }: the bag in bank bag slot 2 (tab ID 7)
M.money = M.money
function C_Bank.FetchPurchasedBankTabData(t) assert(t == Enum.BankType.Character, "bank type"); return M.bankTabs end
function C_Bank.FetchMaxNumBankTabs(t) assert(t == Enum.BankType.Character, "bank type"); return M.bankMax end
function C_Bank.FetchNumPurchasedBankTabs() return #M.bankTabs end
function C_Bank.FetchNextPurchasableBankTabData()
    if #M.bankTabs >= M.bankMax then return nil end
    return { tabCost = #M.bankTabs == 0 and 0 or 10000 * #M.bankTabs, canAfford = M.bankBroke ~= true }
end
function C_Bank.CanPurchaseBankTab() return #M.bankTabs < M.bankMax end
function C_Bank.PurchaseBankTab(t)
    assert(t == Enum.BankType.Character, "bank type")
    local n = #M.bankTabs + 1
    M.bankTabs[n] = { ID = 5 + n, name = "Tab " .. n }
    M.bankBought = (M.bankBought or 0) + 1
end
function C_Bank.CloseBankFrame()
    M.bankClosedByUs = (M.bankClosedByUs or 0) + 1
    M.bankOpen = false
    M.fire("BANKFRAME_CLOSED")
end
local tabSlots, tabItem = C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo
function C_Container.GetContainerNumSlots(bag)
    if bag == 7 then return M.bankOpen and M.bankTabs[2] and M.bankBag and M.bankBag[2] or 0 end
    return tabSlots(bag)
end
function C_Container.GetContainerItemInfo(bag, slot)
    if bag == Enum.BagIndex.Characterbanktab then
        if slot == 2 and M.bankOpen and M.bankTabs[2] and M.bankBag then
            return { itemID = M.bankBag[1], stackCount = 1, iconFileID = 133600 + M.bankBag[1] % 100, quality = 1,
                hyperlink = "|cffffffff|Hitem:" .. M.bankBag[1] .. "::::::::|h[Red Linen Bag]|h|r" }
        end
        return nil
    end
    return tabItem(bag, slot)
end
M.picked = {}
local pickup = C_Container.PickupContainerItem
function C_Container.PickupContainerItem(bag, slot)
    M.picked[#M.picked + 1] = { bag, slot }
    return pickup(bag, slot)
end
StaticPopupDialogs = StaticPopupDialogs or {}
function StaticPopup_Show(which, a, b, data) M.popup = { which = which, data = data } end
-- the game's bank frame (Camelot/BankFrame.xml): hiding it would end the visit
BankFrame = CreateFrame("Frame", "BankFrame", UIParent)
BankFrame:Hide()
BankFrame:SetScript("OnHide", function() M.gameBankHidOnUs = true end)

----------------------------------------------------------------------
-- Bag slots: item colours, the keyring, Pawn, faces and the guild bank
----------------------------------------------------------------------
ITEM_QUALITY_COLORS = { [0] = { r = 0.62, g = 0.62, b = 0.62 }, [1] = { r = 1, g = 1, b = 1 },
    [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 }, [4] = { r = 0.64, g = 0.21, b = 0.93 } }
M.items[5000] = { "Rot Hide Ichor", 1, 0, 12, 4 }
M.items[5001] = { "Skeleton Key", 1, 0, 13 }
-- the keyring: off until M.keyring = { size, items = { [slot] = { id, count } } }
Enum.BagIndex.Keyring = -20
M.keyring = nil
C_ActionBar = C_ActionBar or {}
function C_ActionBar.ShouldShowKeyring() return M.keyring ~= nil end
function GetKeyRingSize() return M.keyring and M.keyring.size or 0 end
local keyItem = C_Container.GetContainerItemInfo
function C_Container.GetContainerItemInfo(bag, slot)
    if bag == Enum.BagIndex.Keyring then
        local k = M.keyring and M.keyring.items[slot]
        if not k then return nil end
        return { itemID = k[1], stackCount = k[2], quality = 1, iconFileID = 134237,
            hyperlink = "|cffffffff|Hitem:" .. k[1] .. "::::::::|h[Skeleton Key]|h|r" }
    end
    return keyItem(bag, slot)
end
function C_NewItems.RemoveNewItem(bag, slot) M.newItems[bag .. ":" .. slot] = nil end
-- item tooltips as data: what stops you using an item is written in red
M.cantUse = {}
C_TooltipInfo = {}
function C_TooltipInfo.GetBagItem(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then return nil end
    local lines = { { leftText = "item", leftColor = { r = 1, g = 1, b = 1 } } }
    if M.cantUse[info.itemID] then
        lines[2] = { leftText = "Requires Level 40", leftColor = { r = 1, g = 0.125, b = 0.125 } }
    end
    return { lines = lines }
end
-- Pawn 2.14's public bag API: a link, level check, and a tri-state answer.
-- Deliberately do not invent PawnIsContainerItemAnUpgrade: it is not in
-- the installed addon, which let the old test pass while real arrows failed.
PawnIsInitialized = true
PawnCommon = { ShowBagUpgradeAdvisor = true }
function PawnShouldItemLinkHaveUpgradeArrow(link, checkLevel)
    M.pawnCalls = M.pawnCalls or {}
    table.insert(M.pawnCalls, { link, checkLevel })
    if M.pawnError then error("Pawn unavailable") end
    if M.pawnPending and M.pawnPending[link] then return nil end
    return M.pawnUp and M.pawnUp[link] == true or false
end
function PawnResetBags() end
-- faces
function UnitRace() return "Orc", "Orc" end
function UnitSex() return 2 end
-- the guild bank: M.guild = { name, tabs = { { name, icon, items = { [slot] = { id, count } } } } }
for _, e in ipairs({ "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GUILDBANKBAGSLOTS_CHANGED" }) do KNOWN_EVENTS[e] = true end
M.guild = nil
function IsInGuild() return M.guild ~= nil end
function GetGuildInfo() return M.guild and M.guild.name or nil end
function GetNumGuildBankTabs() return M.guild and #M.guild.tabs or 0 end
function GetGuildBankTabInfo(t) local tab = M.guild.tabs[t]; return tab.name, tab.icon, true end
function GetGuildBankItemInfo(t, s)
    local e = M.guild.tabs[t].items[s]
    if e then return 134400, e[2], false, false, 1 end
end
function GetGuildBankItemLink(t, s)
    local e = M.guild.tabs[t].items[s]
    if e then return "|cffffffff|Hitem:" .. e[1] .. "::::::::|h[x]|h|r" end
end
function GetCurrentGuildBankTab() return 1 end
function QueryGuildBankTab() M.guildQueried = (M.guildQueried or 0) + 1 end

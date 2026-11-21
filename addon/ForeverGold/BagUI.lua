-- Forever Gold - the bag windows
--
-- Replaces the game's bags with one window, and adds a bank window:
--   * all your bags in one grid (or split by bag), with search and the
--     game's own Sort;
--   * a bag bar: click a bag to hide or show its slots, hover it to light
--     them up, right-click it for its options (the game's own "assign to"
--     and "ignore" settings, hide, show only this one);
--   * slots of special bags (quivers, herb, mining, soul bags...) tinted to match;
--   * any of your characters' bags and banks, from the last time each was
--     saved (Inventory.lua) - pick them from the portrait at the top;
--     right-click the portrait to open that character's bank beside it;
--   * new loot gathered at the bottom until you close your bags;
--   * Forever Gold's own bits: banker marks (mail rules; Shift+right-click a
--     stack), "never mail", a Sell junk button at vendors, what your bags
--     are worth, and quick links to the auction house.
--
-- Your own bags use the game's own item buttons (ContainerFrameItemButtonTemplate),
-- one holder frame per bag whose ID is the bag, so clicking, right-click to
-- use and dragging are exactly the game's. The game's bag frames still open
-- and close as usual, just out of sight, and the bag window follows them.

local _, ns = ...
local floor, max, min = math.floor, math.max, math.min

local INV = ns.Inv

-- A view is one window and what it shows. BU (the bag window) is a view
-- itself; BU.bank is the bank window.
local function newView(where)
    return { where = where, search = "", _saved = {}, _usedSaved = 0, _bgs = {}, _usedBg = 0,
        _heads = {}, _usedHead = 0, _bagBtns = {}, _live = {}, _placed = {}, _info = {} }
end
local BU = newView("bags")
BU.char = nil
ns.BagUI = BU
local BV = newView("bank")
BU.bank = BV
local VIEWS = { BU, BV }

local SLOT, GAP, PAD = 37, 4, 12
local HEAD = 46       -- the title row
local BAR = 32        -- the bag bar under it
local BAGBTN = 28
local FOOT = 34
local SECTION = 20    -- a section's heading
local GREY = "|cff9a9a9a"
local CLASS_ICONS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local MAIL_ICON = "Interface\\Icons\\INV_Letter_15"
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local BANK_ICON = "Interface\\Icons\\INV_Misc_Bag_10_Blue"
local EMPTY_BAG_ICON = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
local BASE_FILL = { 0.105, 0.10, 0.09 }
local BASE_EDGE = { 0.20, 0.19, 0.16 }

local K, C

local function O()
    return ns.db.opts
end

function BU.Enabled()
    return O().bagUI ~= false
end

local function cols()
    return min(16, max(6, tonumber(O().bagCols) or 10))
end
local function showEmpty()
    return O().bagEmpty ~= false
end
local function split()
    return O().bagSplit == true
end
local function newSection()
    return O().bagNew ~= false
end
local function barShown()
    return O().bagBar ~= false
end
local function specialRows()
    return O().bagSpecialRows ~= false
end
local function junkDim()
    return O().bagJunkDim ~= false
end
local function bgAlpha()
    return min(1, max(0.2, tonumber(O().bagAlpha) or 1))
end
BU.BgAlpha = bgAlpha

local function shortName(name)
    return (tostring(name or "?"):gsub("%-.*$", ""))
end

local function viewingSelf(V)
    return V.char == nil or V.char == ns.charKey
end

-- Live means real, usable item buttons: your own bags, or your own bank
-- while you're standing at it.
local function isLive(V)
    V = V or BU
    if not viewingSelf(V) then
        return false
    end
    return V.where == "bags" or (V.where == "bank" and INV.bankOpen)
end
BU.IsLive = isLive

local function tip(owner, lines)
    if not GameTooltip then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    for i, l in ipairs(lines) do
        if i == 1 then
            GameTooltip:SetText(l, 1, 0.82, 0, 1, true)
        else
            GameTooltip:AddLine(l, 0.9, 0.9, 0.9, true)
        end
    end
    GameTooltip:Show()
end
local function untip()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

----------------------------------------------------------------------
-- Special bags: quivers, herb bags... get their own subtle slot colour
----------------------------------------------------------------------

local FAMILIES = {
    { bit = 1, name = "Quiver", c = { 0.16, 0.12, 0.07 } },              -- worn leather
    { bit = 2, name = "Ammo pouch", c = { 0.10, 0.11, 0.13 } },          -- gunmetal
    { bit = 4, name = "Soul bag", c = { 0.13, 0.07, 0.15 } },            -- fel purple
    { bit = 8, name = "Leatherworking bag", c = { 0.14, 0.10, 0.07 } },  -- tanned hide
    { bit = 16, name = "Inscription bag", c = { 0.07, 0.10, 0.16 } },    -- ink blue
    { bit = 32, name = "Herb bag", c = { 0.07, 0.14, 0.07 } },           -- leaf green
    { bit = 64, name = "Enchanting bag", c = { 0.11, 0.08, 0.17 } },     -- arcane violet
    { bit = 128, name = "Engineering bag", c = { 0.06, 0.12, 0.13 } },   -- oiled steel
    { bit = 256, name = "Keyring", c = { 0.15, 0.13, 0.05 } },           -- brass
    { bit = 512, name = "Gem bag", c = { 0.05, 0.12, 0.15 } },           -- sapphire
    { bit = 1024, name = "Mining bag", c = { 0.16, 0.09, 0.05 } },       -- copper ore
}
local REAGENT = { name = "Reagent bag", c = { 0.08, 0.13, 0.11 } }

local function hasBit(n, b)
    return n % (b * 2) >= b
end

-- A bag's kind, from its saved/live info: { name, c = {r,g,b} } or nil.
function BU.Family(info)
    if type(info) ~= "table" then
        return nil
    end
    if info.reagent then
        return REAGENT
    end
    local f = tonumber(info.fam) or 0
    if f > 0 then
        for _, F in ipairs(FAMILIES) do
            if hasBit(f, F.bit) then
                return F
            end
        end
    end
    return nil
end

local function edgeOf(c)
    return min(1, c[1] * 2.2), min(1, c[2] * 2.2), min(1, c[3] * 2.2)
end

----------------------------------------------------------------------
-- Banker marks: an item rule "send all of this to your banker"
----------------------------------------------------------------------

local MB = function() return ns.Mail end

function BU.BankerRule(id)
    local mb = MB()
    if not (mb and id) then
        return nil
    end
    for _, r in ipairs(mb.Rules()) do
        if r.item == id and r.to == "banker" then
            return r
        end
    end
end

function BU.IsMarked(id)
    local r = BU.BankerRule(id)
    return r and r.on and true or false
end

function BU.ToggleMark(id)
    local mb = MB()
    if not (mb and id) then
        return
    end
    local r = BU.BankerRule(id)
    if r and r.on then
        -- Unmarked: every banker rule of its own goes, and no group rule or
        -- quick-send pick sends it to the banker either.
        while r do
            mb.DeleteRule(r.id)
            r = BU.BankerRule(id)
        end
        if mb.SetBankerBlocked then
            mb.SetBankerBlocked(id, true)
        end
    else
        if mb.SetBankerBlocked then
            mb.SetBankerBlocked(id, false)
        end
        if r then
            mb.SetRuleOn(r.id, true)
        else
            mb.AddRule({ item = id, to = "banker", on = true, keep = 0, scope = "account" }, true)
        end
    end
    BU.Refresh()
end

local function bankerName()
    local mb = MB()
    local key = mb and mb.BankerKey and mb.BankerKey()
    return key and shortName(mb.NameOf(key)) or nil, key
end

----------------------------------------------------------------------
-- The game's own bag settings (right-click a bag)
----------------------------------------------------------------------

local FILTERS = {
    { "ClassEquipment", "Equipment" },
    { "ClassConsumables", "Consumables" },
    { "ClassProfessionGoods", "Profession Goods" },
    { "ClassJunk", "Junk" },
    { "ClassQuestItems", "Quest Items" },
    { "ClassReagents", "Reagents" },
}

local function flagValue(name)
    return Enum and Enum.BagSlotFlags and Enum.BagSlotFlags[name]
end

local function flagGet(bag, name)
    local f = flagValue(name)
    return f ~= nil and ns.try(C_Container.GetBagSlotFlag, bag, f) and true or false
end

local function flagSet(bag, name, value)
    local f = flagValue(name)
    if f then
        ns.try(C_Container.SetBagSlotFlag, bag, f, value)
    end
end

-- "Ignore this bag" for Cleanup (sort) or Sell junk; the backpack keeps its own.
function BU.Ignored(bag, which)
    if bag == 0 then
        local get = which == "sort" and C_Container.GetBackpackAutosortDisabled or C_Container.GetBackpackSellJunkDisabled
        return ns.try(get) and true or false
    end
    return flagGet(bag, which == "sort" and "DisableAutoSort" or "ExcludeJunkSell")
end

function BU.SetIgnored(bag, which, value)
    if bag == 0 then
        local set = which == "sort" and C_Container.SetBackpackAutosortDisabled or C_Container.SetBackpackSellJunkDisabled
        ns.try(set, value)
    else
        flagSet(bag, which == "sort" and "DisableAutoSort" or "ExcludeJunkSell", value)
    end
end

-- Like the game: only ordinary bags (not the backpack, profession or reagent bags).
local function canFilter(V, bag, info)
    if V.where ~= "bags" or not isLive(V) or type(bag) ~= "number" then
        return false
    end
    if bag < 1 or bag > (NUM_BAG_SLOTS or 4) or not flagValue("ClassEquipment") then
        return false
    end
    return BU.Family(info) == nil
end

local function invSlot(bag)
    return bag and bag > 0 and C_Container.ContainerIDToInventoryID
        and ns.try(C_Container.ContainerIDToInventoryID, bag) or nil
end

----------------------------------------------------------------------
-- Hidden bags (click a bag in the bar)
----------------------------------------------------------------------

local function hiddenKey(V, bag)
    return V.where .. ":" .. tostring(bag)
end

function BU.IsHidden(bag, V)
    local h = O().bagHidden
    return type(h) == "table" and h[hiddenKey(V or BU, bag)] == true
end

function BU.ToggleHidden(bag, V)
    V = V or BU
    O().bagHidden = type(O().bagHidden) == "table" and O().bagHidden or {}
    local k = hiddenKey(V, bag)
    O().bagHidden[k] = (not O().bagHidden[k]) or nil
    BU.Refresh(V)
end

-- Shows just this bag; again shows them all.
function BU.ShowOnly(bag, V)
    V = V or BU
    O().bagHidden = type(O().bagHidden) == "table" and O().bagHidden or {}
    local only = true
    for _, b in ipairs(V._order or {}) do
        if (b == bag) == BU.IsHidden(b, V) then
            only = false
        end
    end
    for _, b in ipairs(V._order or {}) do
        O().bagHidden[hiddenKey(V, b)] = (not only and b ~= bag) or nil
    end
    BU.Refresh(V)
end

local function onlyThis(V, bag)
    for _, b in ipairs(V._order or {}) do
        if (b == bag) == BU.IsHidden(b, V) then
            return false
        end
    end
    return true
end

----------------------------------------------------------------------
-- What's shown: a list of cells
--   { live = true, bag, slot, id, count, q, link, bound, new, where }
--   { id, count, q, link, bound, bag, slot } (saved)   { empty = true, bag, slot, live }
----------------------------------------------------------------------

local function liveCells(ids, where)
    local cells, size = {}, 0
    for _, bag in ipairs(ids) do
        local n = ns.try(C_Container.GetContainerNumSlots, bag) or 0
        size = size + n
        for slot = 1, n do
            local info = ns.try(C_Container.GetContainerItemInfo, bag, slot)
            local cell = { live = true, bag = bag, slot = slot, where = where }
            if type(info) == "table" and info.itemID then
                cell.id, cell.count, cell.q, cell.link = info.itemID, info.stackCount or 1, info.quality, info.hyperlink
                cell.bound, cell.locked, cell.noValue = info.isBound, info.isLocked, info.hasNoValue
                cell.new = C_NewItems and ns.try(C_NewItems.IsNewItem, bag, slot) and true or false
            else
                cell.empty = true
            end
            cells[#cells + 1] = cell
        end
    end
    return cells, size
end

local function savedCells(snap)
    local cells = {}
    if not snap then
        return cells, 0
    end
    local at = {}
    for _, e in ipairs(snap.slots or {}) do
        at[e[1]] = at[e[1]] or {}
        at[e[1]][e[2]] = e
    end
    local order = snap.order
    if not order or #order == 0 then
        -- an older save without sizes: just the items, then the free slots
        for _, e in ipairs(snap.slots or {}) do
            cells[#cells + 1] = { bag = e[1], slot = e[2], id = e[3], count = e[4], q = e[5], link = e[6] or nil, bound = e[7] }
        end
        for _ = #cells + 1, snap.size or 0 do
            cells[#cells + 1] = { empty = true }
        end
        return cells, snap.size or #cells
    end
    for _, bag in ipairs(order) do
        for slot = 1, snap.sizes[bag] or 0 do
            local e = at[bag] and at[bag][slot]
            if e then
                cells[#cells + 1] = { bag = bag, slot = slot, id = e[3], count = e[4], q = e[5], link = e[6] or nil, bound = e[7] }
            else
                cells[#cells + 1] = { empty = true, bag = bag, slot = slot }
            end
        end
    end
    return cells, snap.size or #cells
end

-- Everything a view shows: cells, slot count, when saved (nil for live),
-- whether nothing is saved, the bags in order, and each bag's info.
local function collect(V)
    if isLive(V) then
        local ids = V.where == "bank" and INV.BankIDs() or INV.BagIDs()
        local cells, size = liveCells(ids, V.where)
        local order, info = {}, {}
        for _, bag in ipairs(ids) do
            local n = ns.try(C_Container.GetContainerNumSlots, bag) or 0
            -- the bag bar shows your empty bag slots too, to drop a bag into
            if n > 0 or (V.where == "bags" and bag > 0) then
                order[#order + 1] = bag
                info[bag] = (INV.BagInfo(bag, V.where == "bank"))
                info[bag].size = n
            end
        end
        return { cells = cells, size = size, order = order, info = info }
    end
    local snap = INV.Snapshot(V.char or ns.charKey, V.where)
    local cells, size = savedCells(snap)
    local info = {}
    for _, bag in ipairs(snap and snap.order or {}) do
        local saved = type(snap.info) == "table" and type(snap.info[bag]) == "table" and snap.info[bag] or {}
        local copy = { size = snap.sizes and snap.sizes[bag] or 0 }
        for k, v in pairs(saved) do
            copy[k] = v
        end
        copy.size = snap.sizes and snap.sizes[bag] or 0
        info[bag] = copy
    end
    return { cells = cells, size = size, at = snap and snap.at or nil, missing = snap == nil,
        order = snap and snap.order or {}, info = info }
end

-- The cells for what a view shows now, the slot count, when it was saved
-- (nil for live) and whether nothing is saved.
function BU.Cells(V)
    local d = collect(V or BU)
    return d.cells, d.size, d.at, d.missing
end

local function matches(cell, q)
    if q == "" then
        return true
    end
    if not cell.id then
        return false
    end
    local name = ns.ItemName(cell.id)
    return name and name:lower():find(q, 1, true) ~= nil or false
end

----------------------------------------------------------------------
-- Value and junk
----------------------------------------------------------------------

-- Junk: gray items, plus anything you mark as junk, minus what you mark
-- "not junk". Junk is toned down in the bags and sold by Sell junk.
function BU.JunkMark(id)
    local j = O().bagJunk
    if type(j) == "table" then
        return j[id]
    end
    return nil
end

function BU.IsJunk(id, q)
    if not id then
        return false
    end
    local mark = BU.JunkMark(id)
    if mark ~= nil then
        return mark
    end
    return q == 0
end

-- Marks it junk (true), not junk (false), or back to the usual (nil).
function BU.SetJunk(id, value)
    if type(O().bagJunk) ~= "table" then
        O().bagJunk = {}
    end
    O().bagJunk[id] = value
    BU.Refresh()
end

-- What the shown items are worth: at auction (unbound, after the cut, never
-- below what a vendor pays) and at a vendor.
function BU.Worth(cells)
    local ah, vendor = 0, 0
    for _, c in ipairs(cells) do
        if c.id then
            local n = c.count or 1
            local v = ns.VendorSell(c.id) or 0
            vendor = vendor + v * n
            local p = not c.bound and ns.AHNet and ns.AHNet(c.id)
            if p and ns.Suspicious and ns.Suspicious(c.id, ns.AHPrice(c.id)) then
                p = nil
            end
            ah = ah + max(p or 0, v) * n
        end
    end
    return floor(ah), floor(vendor)
end

-- Gray items a vendor will buy, in your bags right now: { cell, ... }, total.
-- Bags set to "Ignore: Sell junk" are left alone, like the game does.
function BU.Junk()
    local out, total = {}, 0
    if not viewingSelf(BU) then
        return out, 0
    end
    for _, c in ipairs((liveCells(INV.BagIDs(), "bags"))) do
        if c.id and BU.IsJunk(c.id, c.q) and not c.noValue and not (MB() and MB().IsKept(c.id)) and not BU.Ignored(c.bag, "junk") then
            local v = ns.VendorSell(c.id) or 0
            if v > 0 then
                out[#out + 1] = c
                total = total + v * (c.count or 1)
            end
        end
    end
    return out, total
end

local merchantOpen = false
ns.On("MERCHANT_SHOW", function()
    merchantOpen = true
    BU.Refresh()
end)
ns.On("MERCHANT_CLOSED", function()
    merchantOpen = false
    BU.Refresh()
end)

-- Sells the junk, a few items a moment so the vendor keeps up.
function BU.SellJunk()
    if not merchantOpen then
        return
    end
    local list, total = BU.Junk()
    if #list == 0 then
        return
    end
    local i = 0
    local function step()
        if not merchantOpen then
            return
        end
        for _ = 1, 6 do
            i = i + 1
            local c = list[i]
            if not c then
                ns.Print("sold " .. #list .. " junk item" .. (#list == 1 and "" or "s") .. " for " .. ns.Money(total) .. ".")
                return
            end
            ns.try(C_Container.UseContainerItem, c.bag, c.slot)
        end
        C_Timer.After(0.2, step)
    end
    step()
end

----------------------------------------------------------------------
-- Buttons
----------------------------------------------------------------------

local holders, liveButtons, nameN = {}, {}, 0

local function overlays(b)
    b.fgTint = b:CreateTexture(nil, "ARTWORK", nil, 7)
    b.fgTint:SetPoint("TOPLEFT", 1, -1)
    b.fgTint:SetPoint("BOTTOMRIGHT", -1, 1)
    b.fgTint:Hide()
    b.fgMark = b:CreateTexture(nil, "OVERLAY", nil, 6)
    b.fgMark:SetSize(14, 14)
    b.fgMark:SetPoint("TOPLEFT", 1, -1)
    b.fgMark:SetTexture(MAIL_ICON)
    b.fgMark:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.fgMark:Hide()
    b.fgJunk = b:CreateTexture(nil, "OVERLAY", nil, 4)
    b.fgJunk:SetAllPoints()
    b.fgJunk:SetColorTexture(0.05, 0.04, 0.03, 0.5)
    b.fgJunk:Hide()
    b.fgDim = b:CreateTexture(nil, "OVERLAY", nil, 7)
    b.fgDim:SetAllPoints()
    b.fgDim:SetColorTexture(0, 0, 0, 0.72)
    b.fgDim:Hide()
    b.fgGlow = b:CreateTexture(nil, "OVERLAY", nil, 5)
    b.fgGlow:SetAllPoints()
    b.fgGlow:SetColorTexture(1, 0.8, 0.35, 0.28)
    if b.fgGlow.SetBlendMode then
        b.fgGlow:SetBlendMode("ADD")
    end
    b.fgGlow:Hide()
end

-- The stack-split box opens on Shift+click; Shift+right-click marks instead.
local function closeSplit(owner)
    local f = StackSplitFrame
    if f and f.IsShown and f:IsShown() and (f.owner == nil or f.owner == owner) then
        pcall(f.Hide, f)
    end
end

local function holder(V, bag)
    local h = holders[bag]
    if not h then
        h = CreateFrame("Frame", nil, V.win.body)
        h:SetID(bag)
        h:SetAllPoints(V.win.body)
        holders[bag] = h
    elseif h:GetParent() ~= V.win.body then
        h:SetParent(V.win.body)
        h:ClearAllPoints()
        h:SetAllPoints(V.win.body)
    end
    return h
end

local function liveButton(V, bag, slot)
    liveButtons[bag] = liveButtons[bag] or {}
    local b = liveButtons[bag][slot]
    if b then
        holder(V, bag)
        return b
    end
    nameN = nameN + 1
    local ok, made = pcall(CreateFrame, "ItemButton", "ForeverGoldBagItem" .. nameN, holder(V, bag),
        "ContainerFrameItemButtonTemplate")
    if not ok or not made then
        return nil
    end
    b = made
    b:SetID(slot)
    b:SetSize(SLOT, SLOT)
    overlays(b)
    -- Shift+right-click: send to banker. Alt+right-click: Forever Gold's actions.
    -- (A plain right-click still uses it - that's the game's own click.)
    b:HookScript("OnClick", function(self, which)
        local c = self.fgCell
        if which ~= "RightButton" or not (c and c.id) then
            return
        end
        if IsShiftKeyDown and IsShiftKeyDown() then
            closeSplit(self)
            BU.ToggleMark(c.id)
        elseif IsAltKeyDown and IsAltKeyDown() then
            BU.ItemMenu(self, c)
        end
    end)
    b:HookScript("OnEnter", function(self)
        if GameTooltip and GameTooltip:IsOwned(self) and self.fgCell and self.fgCell.id then
            GameTooltip:AddLine(GREY .. "Shift+right-click: send to banker  -  Alt+right-click: more|r")
            GameTooltip:Show()
        end
    end)
    liveButtons[bag][slot] = b
    return b
end

local function paintLive(b, cell)
    b.fgCell = cell
    local icon = cell.id and ns.try(C_Container.GetContainerItemInfo, cell.bag, cell.slot)
    icon = type(icon) == "table" and icon.iconFileID or nil
    pcall(SetItemButtonTexture, b, icon)
    pcall(SetItemButtonCount, b, cell.count or 0)
    pcall(SetItemButtonQuality, b, cell.q, cell.link, false, cell.bound)
    pcall(SetItemButtonDesaturated, b, (cell.locked or cell.junk) and true or false)
    if b.UpdateCooldown then
        pcall(b.UpdateCooldown, b, icon)
    end
    if b.UpdateNewItem then
        pcall(b.UpdateNewItem, b, cell.q)
    end
    if b.UpdateJunkItem then
        pcall(b.UpdateJunkItem, b, cell.q, cell.noValue)
    end
    if b.UpdateQuestItem and C_Container.GetContainerItemQuestInfo then
        local q = ns.try(C_Container.GetContainerItemQuestInfo, cell.bag, cell.slot)
        if type(q) == "table" then
            pcall(b.UpdateQuestItem, b, q.isQuestItem, q.questID, q.isActive)
        end
    end
end

local function savedButton(V)
    V._usedSaved = V._usedSaved + 1
    local b = V._saved[V._usedSaved]
    if b then
        return b
    end
    b = CreateFrame("Button", nil, V.win.body)
    b:SetSize(SLOT, SLOT)
    b.edge = b:CreateTexture(nil, "BACKGROUND")
    b.edge:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.92, 0.7, 0.15)
    overlays(b)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", function(self)
        local c = self.fgCell
        if not (c and c.id and GameTooltip) then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if c.link then
            GameTooltip:SetHyperlink(c.link)
        else
            GameTooltip:SetItemByID(c.id)
        end
        GameTooltip:AddLine(GREY .. "Click: Forever Gold actions  -  Shift+right-click: send to banker|r")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", untip)
    b:SetScript("OnClick", function(self, which)
        local c = self.fgCell
        if not (c and c.id) then
            return
        end
        if which == "RightButton" and IsShiftKeyDown and IsShiftKeyDown() then
            BU.ToggleMark(c.id)
            return
        end
        if IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
            local link = c.link or select(2, ns.try(C_Item.GetItemInfo, c.id))
            if link then
                ChatEdit_InsertLink(link)
                return
            end
        end
        BU.ItemMenu(self, c)
    end)
    V._saved[V._usedSaved] = b
    return b
end

local function paintSaved(b, cell)
    b.fgCell = cell
    local icon = ns.Icon(cell.id)
    K.setIcon(b.icon, icon)
    b.count:SetText((cell.count or 1) > 1 and tostring(cell.count) or "")
    K.edgeFor(b.edge, cell.id)
    if b.icon.SetDesaturated then
        b.icon:SetDesaturated(cell.junk and true or false)
    end
end

local function slotBg(V)
    V._usedBg = V._usedBg + 1
    local t = V._bgs[V._usedBg]
    if not t then
        local body = V.win.body
        t = { edge = body:CreateTexture(nil, "BACKGROUND", nil, 1), fill = body:CreateTexture(nil, "BACKGROUND", nil, 2),
            glow = body:CreateTexture(nil, "ARTWORK", nil, 1) }
        t.glow:SetColorTexture(1, 0.8, 0.35, 0.22)
        V._bgs[V._usedBg] = t
    end
    return t
end

local function paintBg(t, fam)
    local fill = fam and fam.c or BASE_FILL
    local er, eg, eb = BASE_EDGE[1], BASE_EDGE[2], BASE_EDGE[3]
    if fam then
        er, eg, eb = edgeOf(fam.c)
    end
    local a = 0.4 + 0.6 * bgAlpha()
    t.edge:SetColorTexture(er, eg, eb, a)
    t.fill:SetColorTexture(fill[1], fill[2], fill[3], a)
end

local function heading(V)
    V._usedHead = V._usedHead + 1
    local h = V._heads[V._usedHead]
    if not h then
        h = { left = K.label(V.win.body, "GameFontNormalSmall"), right = K.label(V.win.body, "GameFontDisableSmall") }
        h.left:SetTextColor(0.55, 0.75, 0.95)
        V._heads[V._usedHead] = h
    end
    h.left:Show()
    h.right:Show()
    return h
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------

local function bagName(V, bag)
    local info = V._info[bag]
    if info and info.name then
        return info.name
    end
    if V.where == "bank" then
        return "Bank tab " .. tostring(bag)
    end
    if bag == 0 then
        return "Backpack"
    end
    if info and (info.size or 0) == 0 then
        return "Empty bag slot"
    end
    return "Bag " .. bag
end
BU.BagName = function(bag, V) return bagName(V or BU, bag) end

-- Lays cells out in rows from y; returns the new y.
local function placeRow(V, list, y, q)
    local n = cols()
    local body = V.win.body
    for i, cell in ipairs(list) do
        local col, row = (i - 1) % n, floor((i - 1) / n)
        local x, cy = col * (SLOT + GAP), y - row * (SLOT + GAP)
        local fam = cell.bag ~= nil and BU.Family(V._info[cell.bag]) or nil
        cell.junk = junkDim() and BU.IsJunk(cell.id, cell.q) or nil
        local bg = slotBg(V)
        paintBg(bg, fam)
        bg.edge:ClearAllPoints()
        bg.edge:SetPoint("TOPLEFT", body, "TOPLEFT", x, cy)
        bg.edge:SetSize(SLOT, SLOT)
        bg.fill:ClearAllPoints()
        bg.fill:SetPoint("TOPLEFT", body, "TOPLEFT", x + 1, cy - 1)
        bg.fill:SetSize(SLOT - 2, SLOT - 2)
        bg.glow:ClearAllPoints()
        bg.glow:SetAllPoints(bg.edge)
        bg.glow:Hide()
        bg.edge:Show()
        bg.fill:Show()
        local b
        if cell.live then
            b = liveButton(V, cell.bag, cell.slot)
            if b then
                paintLive(b, cell)
                V._live[#V._live + 1] = b
            end
        elseif cell.id then
            b = savedButton(V)
            paintSaved(b, cell)
        end
        if b then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", body, "TOPLEFT", x, cy)
            b:Show()
            b.fgMark:SetShown(cell.id ~= nil and BU.IsMarked(cell.id))
            b.fgDim:SetShown(not matches(cell, q))
            -- junk: grayed out and toned down
            b.fgJunk:SetShown(cell.junk == true and not b.fgDim:IsShown())
            b.fgGlow:Hide()
            -- an empty slot of a special bag shows its colour through the game's slot art
            if fam and cell.empty then
                local r, g, bl = edgeOf(fam.c)
                b.fgTint:SetColorTexture(r, g, bl, 0.30)
                b.fgTint:Show()
            else
                b.fgTint:Hide()
            end
        end
        V._placed[#V._placed + 1] = { bag = cell.bag, b = b, bg = bg }
    end
    if #list == 0 then
        return y
    end
    return y - (floor((#list - 1) / n) + 1) * (SLOT + GAP)
end

-- Hovering a bag lights up its slots (nil: none).
function BU.HighlightBag(V, bag)
    V = V or BU
    V.hot = bag
    for _, p in ipairs(V._placed) do
        local on = bag ~= nil and p.bag == bag
        if p.b then
            p.b.fgGlow:SetShown(on)
        else
            p.bg.glow:SetShown(on)
        end
    end
end

local function sectionHead(V, y, left, right)
    local h = heading(V)
    local body = V.win.body
    h.left:ClearAllPoints()
    h.left:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y - 3)
    h.left:SetText(left)
    h.right:ClearAllPoints()
    h.right:SetPoint("TOPRIGHT", body, "TOPLEFT", cols() * (SLOT + GAP) - GAP, y - 3)
    h.right:SetText(right or "")
    return y - SECTION
end

local function hideAll(V)
    for _, b in ipairs(V._live) do
        -- only if no other view has taken it since
        if b.fgCell and b:GetParent() and b:GetParent():GetParent() == V.win.body then
            b:Hide()
            b.fgCell = nil
        end
    end
    for _, b in ipairs(V._saved) do
        b:Hide()
        b.fgCell = nil
    end
    for _, t in ipairs(V._bgs) do
        t.edge:Hide()
        t.fill:Hide()
        t.glow:Hide()
    end
    for _, h in ipairs(V._heads) do
        h.left:Hide()
        h.right:Hide()
    end
    V._live, V._placed = {}, {}
    V._usedSaved, V._usedBg, V._usedHead = 0, 0, 0
end

local function plural(n, word)
    return n .. " " .. word .. (n == 1 and "" or "s")
end

----------------------------------------------------------------------
-- The bag bar
----------------------------------------------------------------------

local function putIntoBag(V, bag)
    if not (CursorHasItem and CursorHasItem() and V.where == "bags" and isLive(V)) then
        return false
    end
    if bag == 0 then
        ns.try(PutItemInBackpack)
    else
        local slot = invSlot(bag)
        if slot then
            ns.try(PutItemInBag, slot)
        end
    end
    return true
end

function BU.BagClick(V, bag, which, anchor)
    V = V or BU
    if which == "RightButton" then
        return BU.BagMenu(V, bag, anchor)
    end
    if putIntoBag(V, bag) then
        return
    end
    local info = V._info[bag]
    if info and (info.size or 0) == 0 then
        return -- an empty bag slot: nothing to hide
    end
    BU.ToggleHidden(bag, V)
end

local function bagTip(V, b)
    local bag = b.bag
    local info = V._info[bag] or {}
    local lines = { bagName(V, bag) }
    if (info.size or 0) == 0 and V.where == "bags" and bag > 0 then
        lines[#lines + 1] = "No bag here. Drop a bag on it to put one in."
        return tip(b, lines)
    end
    lines[#lines + 1] = (b.free or 0) .. " of " .. (info.size or 0) .. " slots free"
    local fam = BU.Family(info)
    if fam then
        lines[#lines + 1] = "|cffd8c8a0" .. fam.name .. "|r"
    end
    if canFilter(V, bag, info) then
        local set = {}
        for _, f in ipairs(FILTERS) do
            if flagGet(bag, f[1]) then
                set[#set + 1] = f[2]
            end
        end
        if #set > 0 then
            lines[#lines + 1] = "Assigned to: " .. table.concat(set, ", ")
        end
    end
    if BU.IsHidden(bag, V) then
        lines[#lines + 1] = "|cffff9060Its slots are hidden.|r"
    end
    lines[#lines + 1] = GREY .. "Click: hide or show its slots  -  Right-click: options|r"
    tip(b, lines)
end

local function bagButton(V, i)
    local b = V._bagBtns[i]
    if b then
        return b
    end
    b = CreateFrame("Button", nil, V.win)
    b:SetSize(BAGBTN, BAGBTN)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b.edge = b:CreateTexture(nil, "BACKGROUND")
    b.edge:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.off = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.off:SetPoint("TOPLEFT", 2, -2)
    b.off:SetPoint("BOTTOMRIGHT", -2, 2)
    b.off:SetColorTexture(0, 0, 0, 0.62)
    b.off:Hide()
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.9, 0.6, 0.18)
    b:SetScript("OnClick", function(self, which)
        BU.BagClick(V, self.bag, which, self)
    end)
    b:SetScript("OnEnter", function(self)
        BU.HighlightBag(V, self.bag)
        bagTip(V, self)
    end)
    b:SetScript("OnLeave", function()
        BU.HighlightBag(V, nil)
        untip()
    end)
    -- drag a bag out of its slot, or drop one in
    b:SetScript("OnDragStart", function(self)
        local slot = V.where == "bags" and isLive(V) and invSlot(self.bag)
        if slot then
            ns.try(PickupBagFromSlot, slot)
        end
    end)
    b:SetScript("OnReceiveDrag", function(self)
        putIntoBag(V, self.bag)
    end)
    V._bagBtns[i] = b
    return b
end

local function layoutBar(V, d, freeBy)
    local win = V.win
    local n = 0
    if barShown() then
        for i, bag in ipairs(d.order) do
            n = i
            local b = bagButton(V, i)
            local info = d.info[bag] or {}
            b.bag, b.free = bag, freeBy[bag] or 0
            local empty = (info.size or 0) == 0
            local icon = info.icon
            if not icon then
                icon = empty and EMPTY_BAG_ICON or (bag == 0 and INV.BACKPACK_ICON) or (V.where == "bank" and BANK_ICON) or BAG_ICON
            end
            if empty then
                b.icon:SetTexture(icon)
                b.icon:SetTexCoord(0, 1, 0, 1)
            else
                K.setIcon(b.icon, icon)
            end
            local hidden = not empty and BU.IsHidden(bag, V)
            b.off:SetShown(hidden or empty)
            if b.icon.SetDesaturated then
                b.icon:SetDesaturated(hidden or empty)
            end
            b.count:SetText(empty and "" or tostring(b.free))
            local fam = BU.Family(info)
            if fam then
                local r, g, bl = edgeOf(fam.c)
                b.edge:SetColorTexture(r, g, bl, 1)
            else
                b.edge:SetColorTexture(C.goldEdge[1], C.goldEdge[2], C.goldEdge[3], hidden and 0.35 or 0.8)
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + (i - 1) * (BAGBTN + 4), -HEAD)
            b:Show()
        end
    end
    for i = n + 1, #V._bagBtns do
        V._bagBtns[i]:Hide()
    end
end

----------------------------------------------------------------------
-- Refreshing a window
----------------------------------------------------------------------

local function refreshView(V)
    local win = V.win
    if not (win and win:IsShown()) then
        return
    end
    local who = ns.db.chars[V.char or ns.charKey] or {}
    local live = isLive(V)
    local d = collect(V)
    local cells, size = d.cells, d.size
    V._order, V._info = d.order, d.info
    local q = (V.search or ""):lower()
    hideAll(V)

    -- title
    win.title:SetText(shortName(who.name or "?") .. "'s " .. (V.where == "bank" and "Bank" or "Inventory"))
    win.title:SetShown(not win.searchBox:IsShown())
    local coords = who.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[who.class]
    if coords then
        win.who.icon:SetTexture(CLASS_ICONS)
        win.who.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        K.setIcon(win.who.icon, V.where == "bank" and BANK_ICON or BAG_ICON)
    end
    if live then
        win.sub:SetText(V.where == "bank" and "AT THE BANK" or "FOREVER BAGS")
    elseif d.at then
        win.sub:SetText("SAVED " .. (ns.Ago and ns.Ago(d.at) or ""))
    else
        win.sub:SetText("")
    end
    if win.tabBags then
        win.tabBags:SetOn(true)
        win.tabBank:SetOn(BV.win ~= nil and BV.win:IsShown())
    end
    win.sort:SetShown(live)
    win.bg:SetAlpha(bgAlpha())

    -- the grid
    local used, empty, marked = 0, 0, 0
    local main, fresh = {}, {}
    local special, specialOrder = {}, {} -- quivers, reagent and profession bags: rows of their own
    local freeBy = {}
    for _, c in ipairs(cells) do
        if c.id then
            used = used + 1
            if BU.IsMarked(c.id) then
                marked = marked + 1
            end
        else
            empty = empty + 1
            if c.bag then
                freeBy[c.bag] = (freeBy[c.bag] or 0) + 1
            end
        end
        if c.bag ~= nil and BU.IsHidden(c.bag, V) then
            -- its bag is switched off in the bag bar
        elseif specialRows() and not split() and c.bag ~= nil and BU.Family(d.info[c.bag]) then
            if not special[c.bag] then
                special[c.bag] = {}
                specialOrder[#specialOrder + 1] = c.bag
            end
            if c.id or showEmpty() then
                table.insert(special[c.bag], c)
            end
        elseif c.new and newSection() and not split() then
            fresh[#fresh + 1] = c
        elseif c.id or showEmpty() then
            main[#main + 1] = c
        end
    end
    layoutBar(V, d, freeBy)
    local top = HEAD + (barShown() and BAR or 0)
    win.body:ClearAllPoints()
    win.body:SetPoint("TOPLEFT", PAD, -top)
    win.body:SetPoint("BOTTOMRIGHT", -PAD, FOOT + 4)
    win.sub:ClearAllPoints()
    win.sub:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, barShown() and -(HEAD + 9) or -36)

    local y = 0
    if d.missing then
        win.note:SetText(V.where == "bank"
            and "No bank saved for " .. shortName(who.name) .. " yet. It's saved each time they visit a banker."
            or "No bags saved for " .. shortName(who.name) .. " yet. Log in on them once.")
        win.note:Show()
        y = -40
    elseif #main == 0 and #fresh == 0 and #specialOrder == 0 and #cells > 0 then
        win.note:SetText("Every bag is hidden. Click one in the bar above to show it again.")
        win.note:Show()
        y = -40
    else
        win.note:Hide()
    end
    if split() then
        local byBag, order = {}, {}
        for _, c in ipairs(main) do
            local bag = c.bag or -999
            if not byBag[bag] then
                byBag[bag] = {}
                order[#order + 1] = bag
            end
            table.insert(byBag[bag], c)
        end
        for i, bag in ipairs(order) do
            local list = byBag[bag]
            local items = 0
            for _, c in ipairs(list) do
                if c.id then
                    items = items + 1
                end
            end
            local fam = BU.Family(V._info[bag])
            y = sectionHead(V, y, bagName(V, bag) .. (fam and (GREY .. "  " .. fam.name .. "|r") or ""), items .. " / " .. #list)
            y = placeRow(V, list, y, q)
            if i < #order then
                y = y - 6
            end
        end
    else
        y = placeRow(V, main, y, q)
    end
    -- each special bag on its own row(s), under the rest, named in its colour
    for _, bag in ipairs(specialOrder) do
        local list = special[bag]
        if #list > 0 then
            local items = 0
            for _, c in ipairs(list) do
                if c.id then
                    items = items + 1
                end
            end
            local fam = BU.Family(V._info[bag])
            local r, g, b = edgeOf(fam.c)
            local hex = string.format("|cff%02x%02x%02x", floor(min(1, r * 1.6) * 255), floor(min(1, g * 1.6) * 255), floor(min(1, b * 1.6) * 255))
            y = y - (#main > 0 and 8 or 0)
            y = sectionHead(V, y, hex .. bagName(V, bag) .. "|r", items .. " / " .. ((V._info[bag] or {}).size or #list))
            y = placeRow(V, list, y, q)
        end
    end
    if #fresh > 0 then
        y = y - 8
        y = sectionHead(V, y, "New loot", plural(#fresh, "item"))
        y = placeRow(V, fresh, y, q)
    end
    if V.hot then
        BU.HighlightBag(V, V.hot)
    end

    -- footer
    win.slots:SetText(used .. " / " .. size .. "  " .. GREY .. empty .. " free|r")
    win.markCount:SetText(tostring(marked))
    win.money:SetText(ns.Money(who.money or 0))
    if win.junk then
        local junk, junkTotal = {}, 0
        if live and V.where == "bags" and merchantOpen then
            junk, junkTotal = BU.Junk()
        end
        win.junk:SetShown(#junk > 0)
        if #junk > 0 then
            win.junk:SetLabel("Sell junk  " .. ns.Money(junkTotal))
        end
    end
    local ah, vendor = BU.Worth(cells)
    win.worth.ah, win.worth.vendor = ah, vendor
    win.worthText:SetText(GREY .. "worth|r " .. ns.Money(ah))

    -- size
    local n = cols()
    local w = PAD * 2 + n * (SLOT + GAP) - GAP
    local h = top - y + FOOT + PAD
    win:SetSize(max(w, 380), max(h, 160))
end

-- Everything the window(s) show, worked out again.
function BU.Refresh(V)
    if V then
        return refreshView(V)
    end
    for _, view in ipairs(VIEWS) do
        refreshView(view)
    end
end

function BU.Layout()
    ns.Later("bag-refresh", 0.05, BU.Refresh)
end

----------------------------------------------------------------------
-- Small popups: character picker, settings, item and bag actions
----------------------------------------------------------------------

local popup
local function closePopup()
    if popup then
        popup:Hide()
    end
end
BU.ClosePopup = closePopup

-- rows = { { text =, onClick =, on =, header = true, icon = }, ... }
local function openPopup(anchor, rows, width)
    if not popup then
        popup = CreateFrame("Frame", nil, UIParent)
        popup:SetFrameStrata("DIALOG")
        popup:EnableMouse(true)
        K.skin(popup)
        popup.rows = {}
    end
    for _, r in ipairs(popup.rows) do
        r:Hide()
    end
    width = width or 220
    local y = -8
    for i, row in ipairs(rows) do
        local r = popup.rows[i]
        if not r then
            r = K.button(popup, "", width - 16, 22)
            r.text:ClearAllPoints()
            r.text:SetPoint("LEFT", 26, 0)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(16, 16)
            r.icon:SetPoint("LEFT", 5, 0)
            popup.rows[i] = r
        end
        r:SetWidth(width - 16)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", popup, "TOPLEFT", 8, y)
        r:SetLabel(row.header and ("|cffffd100" .. row.text .. "|r") or row.text)
        r.onClick = row.onClick and function()
            closePopup()
            row.onClick()
        end or nil
        r:SetDisabled(row.header or row.disabled)
        r:SetOn(row.on)
        if row.icon then
            K.setIcon(r.icon, row.icon)
            r.icon:Show()
        elseif row.coords then
            r.icon:SetTexture(CLASS_ICONS)
            r.icon:SetTexCoord(row.coords[1], row.coords[2], row.coords[3], row.coords[4])
            r.icon:Show()
        else
            r.icon:Hide()
        end
        r:Show()
        y = y - (row.header and 20 or 24)
    end
    popup:SetSize(width, -y + 6)
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    popup:Show()
    popup.anchor = anchor
    return popup
end
BU.OpenPopup = openPopup

local function resetSearch(V)
    V.search = ""
    if V.win then
        V.win.searchBox:SetText("")
        V.win.searchBox:Hide()
    end
end

-- Shows a character's bags (or bank) in a window. The bag window shows bags;
-- asking it for a bank opens the bank window beside it.
function BU.Pick(key, where, V)
    V = V or BU
    if where == "bank" and V == BU then
        return BU.OpenBank(key)
    elseif where == "bags" and V == BV then
        return BU.OpenInventory(key)
    end
    V.char = key or ns.charKey
    V.hot = nil
    resetSearch(V)
    BU.Refresh(V)
end

function BU.PickerRows(V)
    V = V or BU
    local rows = { { text = "Locations", header = true } }
    rows[#rows + 1] = { text = "Inventory", icon = BAG_ICON, on = V.where == "bags",
        onClick = function() BU.Pick(V.char, "bags", V) end }
    rows[#rows + 1] = { text = V == BU and "Bank  " .. GREY .. "(opens beside)|r" or "Bank", icon = BANK_ICON,
        on = V.where == "bank" or (BV.win ~= nil and BV.win:IsShown()),
        onClick = function() BU.Pick(V.char, "bank", V) end }
    rows[#rows + 1] = { text = "Characters", header = true }
    for _, c in ipairs(INV.Characters()) do
        local coords = c.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.class]
        rows[#rows + 1] = { text = INV.ClassHex(c.class) .. shortName(c.name) .. "|r" .. (c.self and (GREY .. "  (you)|r") or ""),
            coords = coords, on = (V.char or ns.charKey) == c.key, key = c.key,
            onClick = function() BU.Pick(c.key, V.where, V) end }
    end
    return rows
end

local function settingRow(text, key, default)
    local on = O()[key]
    if on == nil then
        on = default
    end
    return { text = text, on = on, onClick = function()
        O()[key] = not on
        BU.Refresh()
    end }
end

local ALPHAS = { 1, 0.85, 0.7, 0.55, 0.4, 0.25 }

function BU.SettingsRows()
    return {
        { text = "Bag window", header = true },
        settingRow("Show empty slots", "bagEmpty", true),
        settingRow("Split by bag (off: one big inventory)", "bagSplit", false),
        settingRow("Quivers and special bags on their own rows", "bagSpecialRows", true),
        settingRow("New loot in its own row", "bagNew", true),
        settingRow("Show the bag bar", "bagBar", true),
        settingRow("Tone down junk (gray items and ones you mark)", "bagJunkDim", true),
        { text = "Columns: " .. cols() .. "  (click for more)", onClick = function()
            local n = cols() + 2
            O().bagCols = n > 16 and 6 or n
            BU.Refresh()
        end },
        { text = "Background: " .. floor(bgAlpha() * 100 + 0.5) .. "%  (click to change)", onClick = function()
            local now, nextA = bgAlpha(), ALPHAS[1]
            for i, a in ipairs(ALPHAS) do
                if math.abs(a - now) < 0.01 then
                    nextA = ALPHAS[i + 1] or ALPHAS[1]
                end
            end
            O().bagAlpha = nextA
            BU.Refresh()
        end },
        settingRow("Who-has lines in item tooltips", "bagTooltip", true),
        { text = "Use the game's bags instead", onClick = function()
            O().bagUI = false
            BU.Uninstall()
            ns.Print("the game's own bags are back. Turn Forever Gold's bags on again in /gold > Settings or with /gold bags.")
        end },
    }
end

function BU.ItemRows(cell)
    local id = cell.id
    local rows = { { text = ns.ItemName(id) or "Item", header = true } }
    local banker = bankerName()
    local mb = MB()
    if mb and banker then
        rows[#rows + 1] = { text = BU.IsMarked(id) and ("Stop sending to " .. banker) or ("To banker (" .. banker .. ")"),
            icon = MAIL_ICON, on = BU.IsMarked(id), onClick = function() BU.ToggleMark(id) end }
        if mb.IsBankerBlocked and mb.IsBankerBlocked(id) and not BU.IsMarked(id) then
            rows[#rows + 1] = { text = "Let group rules send it to " .. banker .. " again", onClick = function()
                mb.SetBankerBlocked(id, false)
                BU.Refresh()
            end }
        end
    end
    if mb then
        local kept = mb.IsKept(id)
        rows[#rows + 1] = { text = kept and "Allow mailing it again" or "Never mail this", on = kept,
            onClick = function()
                mb.SetKept(id, not kept)
                BU.Refresh()
            end }
    end
    if BU.IsJunk(id, cell.q) then
        rows[#rows + 1] = { text = "Not junk  " .. GREY .. "(keep it bright, never sell it)|r", onClick = function()
            if cell.q == 0 then
                BU.SetJunk(id, false) -- a gray you want to keep
            else
                BU.SetJunk(id, nil)
            end
        end }
    else
        rows[#rows + 1] = { text = "Mark as junk  " .. GREY .. "(toned down, sold by Sell junk)|r", onClick = function()
            if cell.q == 0 then
                BU.SetJunk(id, nil) -- a gray: junk again, as usual
            else
                BU.SetJunk(id, true)
            end
        end }
    end
    local ahOpen = AuctionHouseFrame and AuctionHouseFrame:IsShown()
    if ahOpen and cell.live and cell.where ~= "bank" and not cell.bound and ns.OpenSell then
        rows[#rows + 1] = { text = "Sell at auction", onClick = function() ns.OpenSell(id) end }
    end
    if ahOpen and ns.SearchAH then
        rows[#rows + 1] = { text = "Search the auction house", onClick = function() ns.SearchAH(ns.ItemName(id)) end }
    end
    local who, total = INV.WhoHas(id)
    if #who > 1 then
        rows[#rows + 1] = { text = GREY .. "Your characters have " .. total .. " (see tooltip)|r", disabled = true }
    end
    return rows
end

function BU.ItemMenu(anchor, cell)
    if not (cell and cell.id) then
        return
    end
    openPopup(anchor, BU.ItemRows(cell), 240)
end

-- Right-click a bag in the bar.
function BU.BagRows(V, bag)
    V = V or BU
    local info = V._info[bag] or {}
    local rows = { { text = bagName(V, bag), header = true } }
    if (info.size or 0) == 0 then
        rows[#rows + 1] = { text = GREY .. "No bag here. Drop a bag on it.|r", disabled = true }
        return rows
    end
    local hidden = BU.IsHidden(bag, V)
    rows[#rows + 1] = { text = hidden and "Show its slots" or "Hide its slots", on = hidden,
        onClick = function() BU.ToggleHidden(bag, V) end }
    local only = onlyThis(V, bag)
    rows[#rows + 1] = { text = only and "Show all bags" or "Show only this bag", on = only,
        onClick = function() BU.ShowOnly(bag, V) end }
    if canFilter(V, bag, info) then
        rows[#rows + 1] = { text = "Assign to bag:", header = true }
        for _, f in ipairs(FILTERS) do
            local on = flagGet(bag, f[1])
            rows[#rows + 1] = { text = f[2], on = on, onClick = function()
                flagSet(bag, f[1], not on)
                BU.Refresh(V)
            end }
        end
    end
    if V.where == "bags" and isLive(V) then
        rows[#rows + 1] = { text = "Ignore this bag", header = true }
        local noSort, noJunk = BU.Ignored(bag, "sort"), BU.Ignored(bag, "junk")
        rows[#rows + 1] = { text = "Cleanup", on = noSort, onClick = function() BU.SetIgnored(bag, "sort", not noSort) end }
        rows[#rows + 1] = { text = "Sell junk", on = noJunk, onClick = function()
            BU.SetIgnored(bag, "junk", not noJunk)
            BU.Refresh(V)
        end }
    end
    if BU.Family(info) and not split() then
        rows[#rows + 1] = { text = specialRows() and "Mix into the main grid" or "Put special bags on their own rows",
            onClick = function()
                O().bagSpecialRows = not specialRows()
                BU.Refresh()
            end }
    end
    rows[#rows + 1] = { text = split() and "Convert to one big inventory" or "Split into separate bags",
        onClick = function()
            O().bagSplit = not split() or nil
            BU.Refresh()
        end }
    return rows
end

function BU.BagMenu(V, bag, anchor)
    openPopup(anchor, BU.BagRows(V, bag), 230)
end

----------------------------------------------------------------------
-- The windows
----------------------------------------------------------------------

local function posKey(V)
    return V == BU and "bagPos" or "bankPos"
end

local function savePos(V)
    local point, _, rel, x, y = V.win:GetPoint(1)
    O()[posKey(V)] = { point or "BOTTOMRIGHT", rel or "BOTTOMRIGHT", x or -80, y or 120 }
end

local function iconButton(parent, icon, tipText, onClick)
    local b = K.button(parent, "", 26, 26, onClick)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 4, -4)
    b.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    K.setIcon(b.icon, icon)
    b:SetScript("OnEnter", function(self) tip(self, { tipText }) end)
    b:SetScript("OnLeave", untip)
    return b
end

local function toggleSearch(V)
    local box = V.win.searchBox
    if box:IsShown() then
        resetSearch(V)
    else
        box:Show()
        box:SetFocus()
    end
    BU.Refresh(V)
end
BU.ToggleSearch = function(V) toggleSearch(V or BU) end

local function build(V, name)
    K = ns.UIKit
    C = K.C
    local win = CreateFrame("Frame", name, UIParent)
    V.win = win
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePos(V)
    end)
    K.skin(win)
    win:SetSize(440, 300)
    win:Hide()

    -- Title: the character. Click to pick another; right-click opens the
    -- other window (bank beside the bags, or the bags beside the bank).
    win.who = CreateFrame("Button", nil, win)
    win.who:SetSize(28, 28)
    win.who:SetPoint("TOPLEFT", PAD, -10)
    win.who:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    K.skin(win.who, C.btn[1], C.btn[2], C.btn[3], 1, C.goldEdge[1], C.goldEdge[2], C.goldEdge[3], 1)
    win.who.icon = win.who:CreateTexture(nil, "ARTWORK")
    win.who.icon:SetPoint("TOPLEFT", 2, -2)
    win.who.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    win.who:SetScript("OnClick", function(self, which)
        if which == "RightButton" then
            closePopup()
            if V == BU then
                return BU.ToggleBank(V.char)
            end
            return BU.OpenInventory(V.char)
        end
        if popup and popup:IsShown() and popup.anchor == self then
            return closePopup()
        end
        openPopup(self, BU.PickerRows(V), 230)
    end)
    win.who:SetScript("OnEnter", function(self)
        tip(self, { "Your characters", "Click: look at any of your characters' bags or banks.",
            V == BU and "Right-click: their bank, in its own window." or "Right-click: their bags." })
    end)
    win.who:SetScript("OnLeave", untip)
    win.title = K.label(win, K.SERIF_L)
    win.title:SetPoint("LEFT", win.who, "RIGHT", 8, 0)
    win.title:SetTextColor(C.goldText[1], C.goldText[2], C.goldText[3])

    win.close = K.button(win, "X", 24, 24, function() win:Hide() end)
    win.close:SetPoint("TOPRIGHT", -PAD, -12)
    win.settings = iconButton(win, "Interface\\Icons\\Trade_Engineering", "Settings (Options > AddOns > Bags Forever)", function(self)
        closePopup()
        if ns.OpenOptions and ns.OpenOptions("bags") then
            return
        end
        openPopup(self, BU.SettingsRows(), 290)
    end)
    win.settings:SetPoint("RIGHT", win.close, "LEFT", -4, 0)
    win.sort = iconButton(win, "Interface\\Icons\\INV_Misc_Broom_01", "Sort items", function() BU.Sort(V) end)
    win.sort:SetPoint("RIGHT", win.settings, "LEFT", -4, 0)
    win.searchBtn = iconButton(win, "Interface\\Icons\\INV_Misc_Spyglass_03", "Search", function() toggleSearch(V) end)
    win.searchBtn:SetPoint("RIGHT", win.sort, "LEFT", -4, 0)
    win.sub = K.label(win, "GameFontDisableSmall")
    win.sub:SetPoint("TOPRIGHT", -PAD, -36)

    -- Search: takes the title's place
    win.searchBox = CreateFrame("EditBox", nil, win)
    win.searchBox:SetHeight(24)
    win.searchBox:SetPoint("LEFT", win.who, "RIGHT", 8, 0)
    win.searchBox:SetPoint("RIGHT", win.searchBtn, "LEFT", -6, 0)
    win.searchBox:SetAutoFocus(false)
    win.searchBox:SetFontObject("GameFontHighlight")
    win.searchBox:SetTextInsets(8, 8, 0, 0)
    K.skin(win.searchBox, C.panel[1], C.panel[2], C.panel[3], 1, C.goldEdge[1], C.goldEdge[2], C.goldEdge[3], 0.7)
    win.searchBox:SetScript("OnTextChanged", function(self)
        V.search = self:GetText() or ""
        BU.Refresh(V)
    end)
    win.searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        resetSearch(V)
        BU.Refresh(V)
    end)
    win.searchBox:SetScript("OnShow", function() win.title:Hide() end)
    win.searchBox:SetScript("OnHide", function() win.title:Show() end)
    win.searchBox:Hide()

    -- Bags / Bank, down the left side of the bag window
    if V == BU then
        win.tabBags = iconButton(win, BAG_ICON, "Inventory", function() BU.Pick(V.char, "bags", V) end)
        win.tabBags:SetSize(32, 32)
        win.tabBags:SetPoint("TOPRIGHT", win, "TOPLEFT", -4, -44)
        win.tabBank = iconButton(win, BANK_ICON, "Bank, in its own window (saved each visit)", function() BU.ToggleBank(V.char) end)
        win.tabBank:SetSize(32, 32)
        win.tabBank:SetPoint("TOP", win.tabBags, "BOTTOM", 0, -4)
    end

    -- The grid
    win.body = CreateFrame("Frame", nil, win)
    win.body:SetPoint("TOPLEFT", PAD, -HEAD)
    win.body:SetPoint("BOTTOMRIGHT", -PAD, FOOT + 4)
    win.note = K.label(win.body, "GameFontDisable")
    win.note:SetPoint("TOPLEFT", 0, -6)
    win.note:SetWidth(360)

    -- Footer
    local line = K.tex(win, "ARTWORK", C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 1)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", PAD, FOOT)
    line:SetPoint("BOTTOMRIGHT", -PAD, FOOT)
    local bagIcon = win:CreateTexture(nil, "ARTWORK")
    bagIcon:SetSize(16, 16)
    bagIcon:SetPoint("BOTTOMLEFT", PAD, 9)
    K.setIcon(bagIcon, V == BU and BAG_ICON or BANK_ICON)
    win.slots = K.label(win, "GameFontHighlightSmall")
    win.slots:SetPoint("LEFT", bagIcon, "RIGHT", 6, 0)
    win.money = K.label(win, "GameFontHighlightSmall")
    win.money:SetPoint("BOTTOMRIGHT", -PAD, 11)
    win.mark = CreateFrame("Button", nil, win)
    win.mark:SetSize(44, 20)
    win.mark:SetPoint("RIGHT", win.money, "LEFT", -12, 0)
    K.skin(win.mark, C.btn[1], C.btn[2], C.btn[3], 1, C.btnEdge[1], C.btnEdge[2], C.btnEdge[3], 1)
    local mi = win.mark:CreateTexture(nil, "ARTWORK")
    mi:SetSize(14, 14)
    mi:SetPoint("LEFT", 5, 0)
    K.setIcon(mi, MAIL_ICON)
    win.markCount = K.label(win.mark, "GameFontHighlightSmall")
    win.markCount:SetPoint("LEFT", mi, "RIGHT", 5, 0)
    win.mark:SetScript("OnEnter", function(self)
        local banker = bankerName()
        tip(self, { banker and ("To " .. banker) or "Banker marks",
            "Marked stacks are mailed to your banker at a mailbox (Send mail > To banker).",
            "Shift+right-click a stack to mark it (or unmark it)." })
    end)
    win.mark:SetScript("OnLeave", untip)
    win.worth = CreateFrame("Frame", nil, win)
    win.worth:SetSize(120, 20)
    win.worth:SetPoint("BOTTOM", 0, 7)
    win.worth:EnableMouse(true)
    win.worthText = K.label(win.worth, "GameFontHighlightSmall")
    win.worthText:SetPoint("CENTER")
    win.worth:SetScript("OnEnter", function(self)
        tip(self, { "What this is worth",
            "At auction: " .. ns.Money(self.ah or 0) .. "  (after the 5% cut, never less than a vendor pays; bound items at vendor price)",
            "At a vendor: " .. ns.Money(self.vendor or 0) })
    end)
    win.worth:SetScript("OnLeave", untip)
    if V == BU then
        win.junk = K.button(win, "Sell junk", 150, 22, function() BU.SellJunk() end)
        win.junk:SetPrimary(true)
        win.junk:SetPoint("BOTTOMLEFT", win, "TOPLEFT", 0, 4)
        win.junk:Hide()
    end

    win:SetScript("OnHide", function()
        closePopup()
        V.hot = nil
        if V == BU then
            if C_NewItems and C_NewItems.ClearAll then
                ns.try(C_NewItems.ClearAll)
            end
            if not BU.syncing and CloseAllBags then
                -- Escape or the X: shut the game's (hidden) bags too, so B opens them next time.
                BU.syncing = true
                pcall(CloseAllBags)
                BU.syncing = false
            end
        end
        if BU.win and BU.win:IsShown() then
            BU.Refresh(BU) -- the Bank tab's lit state
        end
    end)
    if UISpecialFrames then
        table.insert(UISpecialFrames, name)
    end
end

local function placeWindow(V)
    local win = V.win
    local p = O()[posKey(V)]
    win:ClearAllPoints()
    if p then
        win:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    elseif V == BV and BU.win and BU.win:IsShown() then
        win:SetPoint("TOPRIGHT", BU.win, "TOPLEFT", -44, 0)
    elseif V == BV then
        win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 60, -120)
    else
        win:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -80, 120)
    end
end

function BU.Sort(V)
    V = V or BU
    if not isLive(V) then
        return
    end
    if V.where == "bank" then
        if C_Container.SortBank and Enum and Enum.BankType then
            ns.try(C_Container.SortBank, Enum.BankType.Character)
        else
            ns.try(C_Container.SortBankBags)
        end
    else
        ns.try(C_Container.SortBags)
    end
end

-- The bag window: your own bags.
function BU.Open()
    if not BU.win then
        build(BU, "ForeverGoldBags")
        placeWindow(BU)
    end
    BU.char = ns.charKey
    BU.where = "bags"
    BU.win:Show()
    BU.Refresh()
end

-- The bag window, showing one of your characters' bags.
function BU.OpenInventory(key)
    if not (BU.win and BU.win:IsShown()) then
        BU.Open()
    end
    BU.Pick(key or ns.charKey, "bags", BU)
end

-- The bank window: a character's bank (live at the banker, else the last save).
function BU.OpenBank(key)
    if not BV.win then
        build(BV, "ForeverGoldBank")
    end
    BV.char = key or ns.charKey
    BV.hot = nil
    resetSearch(BV)
    if not BV.win:IsShown() then
        placeWindow(BV)
    end
    BV.win:Show()
    BU.Refresh()
end

function BU.ToggleBank(key)
    key = key or ns.charKey
    if BV.win and BV.win:IsShown() and (BV.char or ns.charKey) == key then
        BV.win:Hide()
    else
        BU.OpenBank(key)
    end
end

function BU.Close()
    if BU.win then
        BU.win:Hide()
    end
end

function BU.Toggle()
    if BU.win and BU.win:IsShown() then
        BU.Close()
    else
        BU.Open()
    end
end

----------------------------------------------------------------------
-- Following the game's bags
----------------------------------------------------------------------

local hiddenParent
local blizzFrames, savedParents = {}, {}

local function gameBagFrames()
    local list = {}
    if ContainerFrameCombinedBags then
        list[#list + 1] = ContainerFrameCombinedBags
    end
    for i = 1, NUM_CONTAINER_FRAMES or 13 do
        local f = _G["ContainerFrame" .. i]
        if f then
            list[#list + 1] = f
        end
    end
    return list
end

local function hideGameBags()
    if not BU.Enabled() then
        return
    end
    hiddenParent = hiddenParent or CreateFrame("Frame")
    hiddenParent:Hide()
    for _, f in ipairs(gameBagFrames()) do
        if f:GetParent() ~= hiddenParent then
            if not savedParents[f] then
                savedParents[f] = f:GetParent() or UIParent
                blizzFrames[#blizzFrames + 1] = f
            end
            pcall(f.SetParent, f, hiddenParent)
        end
    end
end

local function gameBagsOpen()
    for _, f in ipairs(gameBagFrames()) do
        if f:IsShown() then
            return true
        end
    end
    return false
end

function BU.Sync()
    if not BU.Enabled() or BU.syncing then
        return
    end
    hideGameBags()
    local open = gameBagsOpen()
    BU.syncing = true
    if open and not (BU.win and BU.win:IsShown()) then
        BU.Open()
    elseif not open and BU.win and BU.win:IsShown() then
        BU.win:Hide()
    end
    BU.syncing = false
end

function BU.Uninstall()
    BU.syncing = true
    for _, V in ipairs(VIEWS) do
        if V.win then
            V.win:Hide()
        end
    end
    BU.syncing = false
    for _, f in ipairs(blizzFrames) do
        pcall(f.SetParent, f, savedParents[f] or UIParent)
    end
    blizzFrames, savedParents = {}, {}
end

local hooked = false
function BU.Install()
    if not BU.Enabled() then
        return
    end
    hideGameBags()
    if hooked then
        return
    end
    hooked = true
    local function later()
        if BU.Enabled() then
            ns.Later("bag-sync", 0, BU.Sync)
        end
    end
    for _, name in ipairs({ "OpenAllBags", "CloseAllBags", "ToggleAllBags", "OpenBackpack", "CloseBackpack",
        "ToggleBackpack", "OpenBag", "CloseBag", "ToggleBag", "ContainerFrame_SetFullScreenFrame",
        "ContainerFrame_ClearFullScreenFrame" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, later)
        end
    end
end

ns.Listen("READY", function()
    ns.Guard("bags", BU.Install)()
end)

-- Turning it back on (Settings, or /gold bags).
function BU.Enable()
    O().bagUI = true
    BU.Install()
    BU.Open()
end

for _, msg in ipairs({ "INVENTORY", "BAGS_UPDATED", "MAIL", "PRICES_UPDATED", "BANK" }) do
    ns.Listen(msg, BU.Layout)
end
for _, ev in ipairs({ "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "QUEST_ACCEPTED", "PLAYER_MONEY", "BAG_NEW_ITEMS_UPDATED",
    "BAG_SLOT_FLAGS_UPDATED", "PLAYER_EQUIPMENT_CHANGED" }) do
    ns.On(ev, function()
        BU.Layout()
    end)
end

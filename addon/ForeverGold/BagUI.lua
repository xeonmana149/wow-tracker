-- Forever Gold - the bag window
--
-- Replaces the game's bags with one window:
--   * all your bags in one grid (or split by bag), with a search box and
--     the game's own Sort;
--   * any of your characters' bags and banks, from the last time each was
--     saved (Inventory.lua) - pick them from the name at the top;
--   * new loot gathered at the bottom until you close your bags;
--   * Forever Gold's own bits: banker marks (mail rules), "never mail",
--     a Sell junk button at vendors, what your bags are worth, and quick
--     links to the auction house.
--
-- Your own bags use the game's own item buttons (ContainerFrameItemButtonTemplate),
-- one holder frame per bag whose ID is the bag, so clicking, right-click to
-- use and dragging are exactly the game's. The game's bag frames still open
-- and close as usual, just out of sight, and this window follows them.

local _, ns = ...
local floor, max, min = math.floor, math.max, math.min

local INV = ns.Inv
local BU = { char = nil, where = "bags", search = "" }
ns.BagUI = BU

local SLOT, GAP, PAD = 37, 4, 12
local TOP = 46        -- below the title row
local FOOT = 34
local SECTION = 20    -- a section's heading
local GREY = "|cff9a9a9a"
local CLASS_ICONS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local MAIL_ICON = "Interface\\Icons\\INV_Letter_15"
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local BANK_ICON = "Interface\\Icons\\INV_Misc_Bag_10_Blue"

local K, C, win

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

local function shortName(name)
    return (tostring(name or "?"):gsub("%-.*$", ""))
end

local function viewingSelf()
    return BU.char == nil or BU.char == ns.charKey
end

-- Live means real, usable item buttons: your own bags, or your own bank
-- while you're standing at it.
local function isLive()
    if not viewingSelf() then
        return false
    end
    return BU.where == "bags" or (BU.where == "bank" and INV.bankOpen)
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
        mb.DeleteRule(r.id)
    elseif r then
        mb.SetRuleOn(r.id, true)
    else
        mb.AddRule({ item = id, to = "banker", on = true, keep = 0, scope = "account" }, true)
    end
    BU.Refresh()
end

local function bankerName()
    local mb = MB()
    local key = mb and mb.BankerKey and mb.BankerKey()
    return key and shortName(mb.NameOf(key)) or nil, key
end

----------------------------------------------------------------------
-- What's shown: a list of cells
--   { live = true, bag, slot, id, count, q, link, bound, new }
--   { id, count, q, link, bound } (saved)        { empty = true, bag, slot, live }
----------------------------------------------------------------------

local function liveCells(ids)
    local cells, size = {}, 0
    for _, bag in ipairs(ids) do
        local n = ns.try(C_Container.GetContainerNumSlots, bag) or 0
        size = size + n
        for slot = 1, n do
            local info = ns.try(C_Container.GetContainerItemInfo, bag, slot)
            local cell = { live = true, bag = bag, slot = slot }
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

-- The cells for what's picked now, the slot count, and when it was saved
-- (nil for live).
function BU.Cells()
    if isLive() then
        local cells, size = liveCells(BU.where == "bank" and INV.BankIDs() or INV.BagIDs())
        return cells, size, nil
    end
    local snap = INV.Snapshot(BU.char or ns.charKey, BU.where)
    local cells, size = savedCells(snap)
    return cells, size, snap and snap.at or nil, snap == nil
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
function BU.Junk()
    local out, total = {}, 0
    if not viewingSelf() then
        return out, 0
    end
    for _, c in ipairs((liveCells(INV.BagIDs()))) do
        if c.id and c.q == 0 and not c.noValue and not (MB() and MB().IsKept(c.id)) then
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
local savedButtons, usedSaved = {}, 0
local slotBgs, usedBg = {}, 0
local headings, usedHead = {}, 0

local function overlays(b)
    b.fgMark = b:CreateTexture(nil, "OVERLAY", nil, 6)
    b.fgMark:SetSize(14, 14)
    b.fgMark:SetPoint("TOPLEFT", 1, -1)
    b.fgMark:SetTexture(MAIL_ICON)
    b.fgMark:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.fgMark:Hide()
    b.fgDim = b:CreateTexture(nil, "OVERLAY", nil, 7)
    b.fgDim:SetAllPoints()
    b.fgDim:SetColorTexture(0, 0, 0, 0.72)
    b.fgDim:Hide()
end

local function holder(bag)
    local h = holders[bag]
    if not h then
        h = CreateFrame("Frame", nil, win.body)
        h:SetID(bag)
        h:SetAllPoints(win.body)
        holders[bag] = h
    end
    return h
end

local function liveButton(bag, slot)
    liveButtons[bag] = liveButtons[bag] or {}
    local b = liveButtons[bag][slot]
    if b then
        return b
    end
    nameN = nameN + 1
    local ok, made = pcall(CreateFrame, "ItemButton", "ForeverGoldBagItem" .. nameN, holder(bag),
        "ContainerFrameItemButtonTemplate")
    if not ok or not made then
        return nil
    end
    b = made
    b:SetID(slot)
    b:SetSize(SLOT, SLOT)
    overlays(b)
    -- Alt+right-click: Forever Gold's actions (a plain right-click still uses it).
    b:HookScript("OnClick", function(self, which)
        if which == "RightButton" and IsAltKeyDown and IsAltKeyDown() and self.fgCell then
            BU.ItemMenu(self, self.fgCell)
        end
    end)
    b:HookScript("OnEnter", function(self)
        if GameTooltip and GameTooltip:IsOwned(self) and self.fgCell and self.fgCell.id then
            GameTooltip:AddLine(GREY .. "Alt+right-click: Forever Gold actions|r")
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
    pcall(SetItemButtonDesaturated, b, cell.locked and true or false)
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

local function savedButton()
    usedSaved = usedSaved + 1
    local b = savedButtons[usedSaved]
    if b then
        return b
    end
    b = CreateFrame("Button", nil, win.body)
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
        GameTooltip:AddLine(GREY .. "Click: Forever Gold actions|r")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", untip)
    b:SetScript("OnClick", function(self)
        local c = self.fgCell
        if not (c and c.id) then
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
    savedButtons[usedSaved] = b
    return b
end

local function paintSaved(b, cell)
    b.fgCell = cell
    local icon = ns.Icon(cell.id)
    K.setIcon(b.icon, icon)
    b.count:SetText((cell.count or 1) > 1 and tostring(cell.count) or "")
    K.edgeFor(b.edge, cell.id)
end

local function slotBg()
    usedBg = usedBg + 1
    local t = slotBgs[usedBg]
    if not t then
        t = { edge = win.body:CreateTexture(nil, "BACKGROUND", nil, 1), fill = win.body:CreateTexture(nil, "BACKGROUND", nil, 2) }
        t.edge:SetColorTexture(0.20, 0.19, 0.16, 1)
        t.fill:SetColorTexture(0.105, 0.10, 0.09, 1)
        slotBgs[usedBg] = t
    end
    return t
end

local function heading()
    usedHead = usedHead + 1
    local h = headings[usedHead]
    if not h then
        h = { left = K.label(win.body, "GameFontNormalSmall"), right = K.label(win.body, "GameFontDisableSmall") }
        h.left:SetTextColor(0.55, 0.75, 0.95)
        headings[usedHead] = h
    end
    h.left:Show()
    h.right:Show()
    return h
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------

local function bagName(bag)
    if BU.where == "bank" then
        return "Bank tab " .. tostring(bag)
    end
    if bag == 0 then
        return "Backpack"
    end
    local n = viewingSelf() and C_Container.GetBagName and ns.try(C_Container.GetBagName, bag)
    return n or ("Bag " .. bag)
end

-- Lays cells out in rows from y; returns the new y.
local function placeRow(list, y, q, shown)
    local n = cols()
    for i, cell in ipairs(list) do
        local col, row = (i - 1) % n, floor((i - 1) / n)
        local x, cy = col * (SLOT + GAP), y - row * (SLOT + GAP)
        local bg = slotBg()
        bg.edge:ClearAllPoints()
        bg.edge:SetPoint("TOPLEFT", win.body, "TOPLEFT", x, cy)
        bg.edge:SetSize(SLOT, SLOT)
        bg.fill:ClearAllPoints()
        bg.fill:SetPoint("TOPLEFT", win.body, "TOPLEFT", x + 1, cy - 1)
        bg.fill:SetSize(SLOT - 2, SLOT - 2)
        bg.edge:Show()
        bg.fill:Show()
        local b
        if cell.live then
            b = liveButton(cell.bag, cell.slot)
            if b then
                paintLive(b, cell)
                shown[b] = true
            end
        elseif cell.id then
            b = savedButton()
            paintSaved(b, cell)
        end
        if b then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", win.body, "TOPLEFT", x, cy)
            b:Show()
            b.fgMark:SetShown(cell.id ~= nil and BU.IsMarked(cell.id))
            b.fgDim:SetShown(not matches(cell, q))
        end
    end
    if #list == 0 then
        return y
    end
    return y - (floor((#list - 1) / n) + 1) * (SLOT + GAP)
end

local function sectionHead(y, left, right)
    local h = heading()
    h.left:ClearAllPoints()
    h.left:SetPoint("TOPLEFT", win.body, "TOPLEFT", 0, y - 3)
    h.left:SetText(left)
    h.right:ClearAllPoints()
    h.right:SetPoint("TOPRIGHT", win.body, "TOPLEFT", cols() * (SLOT + GAP) - GAP, y - 3)
    h.right:SetText(right or "")
    return y - SECTION
end

local function hideAll()
    for _, bag in pairs(liveButtons) do
        for _, b in pairs(bag) do
            b:Hide()
            b.fgCell = nil
        end
    end
    for _, b in ipairs(savedButtons) do
        b:Hide()
        b.fgCell = nil
    end
    for _, t in ipairs(slotBgs) do
        t.edge:Hide()
        t.fill:Hide()
    end
    for _, h in ipairs(headings) do
        h.left:Hide()
        h.right:Hide()
    end
    usedSaved, usedBg, usedHead = 0, 0, 0
end

local function plural(n, word)
    return n .. " " .. word .. (n == 1 and "" or "s")
end

-- Everything the window shows, worked out again.
function BU.Refresh()
    if not (win and win:IsShown()) then
        return
    end
    local who = ns.db.chars[BU.char or ns.charKey] or {}
    local live = isLive()
    local cells, size, at, missing = BU.Cells()
    local q = (BU.search or ""):lower()
    hideAll()

    -- title
    win.title:SetText(shortName(who.name or "?") .. "'s " .. (BU.where == "bank" and "Bank" or "Inventory"))
    local coords = who.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[who.class]
    if coords then
        win.who.icon:SetTexture(CLASS_ICONS)
        win.who.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        K.setIcon(win.who.icon, BU.where == "bank" and BANK_ICON or BAG_ICON)
    end
    if live then
        win.sub:SetText(BU.where == "bank" and "AT THE BANK" or "FOREVER BAGS")
    elseif at then
        win.sub:SetText("SAVED " .. (ns.Ago and ns.Ago(at) or "") )
    else
        win.sub:SetText("")
    end
    win.tabBags:SetOn(BU.where == "bags")
    win.tabBank:SetOn(BU.where == "bank")
    win.sort:SetShown(live)

    -- the grid
    local used, empty, marked = 0, 0, 0
    local main, fresh = {}, {}
    for _, c in ipairs(cells) do
        if c.id then
            used = used + 1
            if BU.IsMarked(c.id) then
                marked = marked + 1
            end
        else
            empty = empty + 1
        end
        if c.new and newSection() and not split() then
            fresh[#fresh + 1] = c
        elseif c.id or showEmpty() then
            main[#main + 1] = c
        end
    end
    local shown = {}
    local y = 0
    if missing then
        win.note:SetText(BU.where == "bank"
            and "No bank saved for " .. shortName(who.name) .. " yet. It's saved each time they visit a banker."
            or "No bags saved for " .. shortName(who.name) .. " yet. Log in on them once.")
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
            y = sectionHead(y, bagName(bag), items .. " / " .. #list)
            y = placeRow(list, y, q, shown)
            if i < #order then
                y = y - 6
            end
        end
    else
        y = placeRow(main, y, q, shown)
    end
    if #fresh > 0 then
        y = y - 8
        y = sectionHead(y, "New loot", plural(#fresh, "item"))
        y = placeRow(fresh, y, q, shown)
    end

    -- footer
    win.slots:SetText(used .. " / " .. size .. "  " .. GREY .. empty .. " free|r")
    win.markCount:SetText(tostring(marked))
    win.money:SetText(ns.Money(who.money or 0))
    local junk, junkTotal = {}, 0
    if live and BU.where == "bags" and merchantOpen then
        junk, junkTotal = BU.Junk()
    end
    win.junk:SetShown(#junk > 0)
    if #junk > 0 then
        win.junk:SetLabel("Sell junk  " .. ns.Money(junkTotal))
    end
    local ah, vendor = BU.Worth(cells)
    win.worth.ah, win.worth.vendor = ah, vendor
    win.worthText:SetText(GREY .. "worth|r " .. ns.Money(ah))

    -- size
    local n = cols()
    local w = PAD * 2 + n * (SLOT + GAP) - GAP
    local h = TOP + (win.searchBox:IsShown() and 30 or 0) - y + FOOT + PAD
    win:SetSize(max(w, 380), max(h, 160))
end

function BU.Layout()
    ns.Later("bag-refresh", 0.05, BU.Refresh)
end

----------------------------------------------------------------------
-- Small popups: character picker, settings, item actions
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
        r:SetLabel(row.text)
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

function BU.Pick(key, where)
    BU.char = key or ns.charKey
    BU.where = where or BU.where
    BU.search = ""
    if win then
        win.searchBox:SetText("")
    end
    BU.Refresh()
end

function BU.PickerRows()
    local rows = { { text = "Locations", header = true } }
    rows[#rows + 1] = { text = "Inventory", icon = BAG_ICON, on = BU.where == "bags", onClick = function() BU.Pick(BU.char, "bags") end }
    rows[#rows + 1] = { text = "Bank", icon = BANK_ICON, on = BU.where == "bank", onClick = function() BU.Pick(BU.char, "bank") end }
    rows[#rows + 1] = { text = "Characters", header = true }
    for _, c in ipairs(INV.Characters()) do
        local coords = c.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.class]
        rows[#rows + 1] = { text = INV.ClassHex(c.class) .. shortName(c.name) .. "|r" .. (c.self and (GREY .. "  (you)|r") or ""),
            coords = coords, on = (BU.char or ns.charKey) == c.key, key = c.key,
            onClick = function() BU.Pick(c.key, BU.where) end }
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

function BU.SettingsRows()
    return {
        { text = "Bag window", header = true },
        settingRow("Show empty slots", "bagEmpty", true),
        settingRow("Split by bag (off: one big inventory)", "bagSplit", false),
        settingRow("New loot in its own row", "bagNew", true),
        { text = "Columns: " .. cols() .. "  (click for more)", onClick = function()
            local n = cols() + 2
            O().bagCols = n > 16 and 6 or n
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
    end
    if mb then
        local kept = mb.IsKept(id)
        rows[#rows + 1] = { text = kept and "Allow mailing it again" or "Never mail this", on = kept,
            onClick = function()
                mb.SetKept(id, not kept)
                BU.Refresh()
            end }
    end
    local ahOpen = AuctionHouseFrame and AuctionHouseFrame:IsShown()
    if ahOpen and cell.live and BU.where == "bags" and not cell.bound and ns.OpenSell then
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

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------

local function savePos()
    local point, _, rel, x, y = win:GetPoint(1)
    O().bagPos = { point or "BOTTOMRIGHT", rel or "BOTTOMRIGHT", x or -80, y or 120 }
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

local function build()
    K = ns.UIKit
    C = K.C
    win = CreateFrame("Frame", "ForeverGoldBags", UIParent)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePos()
    end)
    K.skin(win)
    local p = O().bagPos
    win:SetPoint(p and p[1] or "BOTTOMRIGHT", UIParent, p and p[2] or "BOTTOMRIGHT", p and p[3] or -80, p and p[4] or 120)
    win:SetSize(440, 300)
    win:Hide()

    -- Title: the character (click to pick another, or the bank)
    win.who = CreateFrame("Button", nil, win)
    win.who:SetSize(28, 28)
    win.who:SetPoint("TOPLEFT", PAD, -10)
    K.skin(win.who, C.btn[1], C.btn[2], C.btn[3], 1, C.goldEdge[1], C.goldEdge[2], C.goldEdge[3], 1)
    win.who.icon = win.who:CreateTexture(nil, "ARTWORK")
    win.who.icon:SetPoint("TOPLEFT", 2, -2)
    win.who.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    win.who:SetScript("OnClick", function(self)
        if popup and popup:IsShown() and popup.anchor == self then
            return closePopup()
        end
        openPopup(self, BU.PickerRows(), 230)
    end)
    win.who:SetScript("OnEnter", function(self) tip(self, { "Your characters", "Look at any of your characters' bags or banks." }) end)
    win.who:SetScript("OnLeave", untip)
    win.title = K.label(win, K.SERIF_L)
    win.title:SetPoint("LEFT", win.who, "RIGHT", 8, 0)
    win.title:SetTextColor(C.goldText[1], C.goldText[2], C.goldText[3])

    win.close = K.button(win, "X", 24, 24, function() BU.Close() end)
    win.close:SetPoint("TOPRIGHT", -PAD, -12)
    win.settings = iconButton(win, "Interface\\Icons\\Trade_Engineering", "Settings", function(self)
        if popup and popup:IsShown() and popup.anchor == self then
            return closePopup()
        end
        openPopup(self, BU.SettingsRows(), 290)
    end)
    win.settings:SetPoint("RIGHT", win.close, "LEFT", -4, 0)
    win.sort = iconButton(win, "Interface\\Icons\\INV_Misc_Broom_01", "Sort items", function() BU.Sort() end)
    win.sort:SetPoint("RIGHT", win.settings, "LEFT", -4, 0)
    win.searchBtn = iconButton(win, "Interface\\Icons\\INV_Misc_Spyglass_03", "Search", function()
        win.searchBox:SetShown(not win.searchBox:IsShown())
        if win.searchBox:IsShown() then
            win.searchBox:SetFocus()
        else
            win.searchBox:SetText("")
            BU.search = ""
        end
        BU.Refresh()
    end)
    win.searchBtn:SetPoint("RIGHT", win.sort, "LEFT", -4, 0)
    win.sub = K.label(win, "GameFontDisableSmall")
    win.sub:SetPoint("TOPRIGHT", -PAD, -40)

    -- Bags / Bank, down the left side
    win.tabBags = iconButton(win, BAG_ICON, "Inventory", function() BU.Pick(BU.char, "bags") end)
    win.tabBags:SetSize(32, 32)
    win.tabBags:SetPoint("TOPRIGHT", win, "TOPLEFT", -4, -44)
    win.tabBank = iconButton(win, BANK_ICON, "Bank (saved each visit)", function() BU.Pick(BU.char, "bank") end)
    win.tabBank:SetSize(32, 32)
    win.tabBank:SetPoint("TOP", win.tabBags, "BOTTOM", 0, -4)

    -- Search
    win.searchBox = CreateFrame("EditBox", nil, win)
    win.searchBox:SetSize(200, 22)
    win.searchBox:SetPoint("TOPLEFT", PAD, -TOP)
    win.searchBox:SetAutoFocus(false)
    win.searchBox:SetFontObject("GameFontHighlight")
    win.searchBox:SetTextInsets(6, 6, 0, 0)
    K.skin(win.searchBox, C.panel[1], C.panel[2], C.panel[3], 1, C.btnEdge[1], C.btnEdge[2], C.btnEdge[3], 1)
    win.searchBox:SetScript("OnTextChanged", function(self)
        BU.search = self:GetText() or ""
        BU.Refresh()
    end)
    win.searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        self:Hide()
        BU.Refresh()
    end)
    win.searchBox:Hide()

    -- The grid
    win.body = CreateFrame("Frame", nil, win)
    win.body:SetPoint("TOPLEFT", PAD, -TOP)
    win.body:SetPoint("BOTTOMRIGHT", -PAD, FOOT + 4)
    win.searchBox:SetScript("OnShow", function()
        win.body:SetPoint("TOPLEFT", PAD, -(TOP + 30))
    end)
    win.searchBox:SetScript("OnHide", function()
        win.body:SetPoint("TOPLEFT", PAD, -TOP)
    end)
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
    K.setIcon(bagIcon, BAG_ICON)
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
            "Click an item (Alt+right-click your own), then choose To banker." })
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
    win.junk = K.button(win, "Sell junk", 150, 22, function() BU.SellJunk() end)
    win.junk:SetPrimary(true)
    win.junk:SetPoint("BOTTOMLEFT", win, "TOPLEFT", 0, 4)
    win.junk:Hide()

    win:SetScript("OnHide", function()
        closePopup()
        if C_NewItems and C_NewItems.ClearAll then
            ns.try(C_NewItems.ClearAll)
        end
        if not BU.syncing and CloseAllBags then
            -- Escape or the X: shut the game's (hidden) bags too, so B opens them next time.
            BU.syncing = true
            pcall(CloseAllBags)
            BU.syncing = false
        end
    end)
    if UISpecialFrames then
        table.insert(UISpecialFrames, "ForeverGoldBags")
    end
    BU.win = win
end

function BU.Sort()
    if not isLive() then
        return
    end
    if BU.where == "bank" then
        if C_Container.SortBank and Enum and Enum.BankType then
            ns.try(C_Container.SortBank, Enum.BankType.Character)
        else
            ns.try(C_Container.SortBankBags)
        end
    else
        ns.try(C_Container.SortBags)
    end
end

function BU.Open(where)
    if not win then
        build()
    end
    BU.char = ns.charKey
    BU.where = where or "bags"
    win:Show()
    BU.Refresh()
end

function BU.Close()
    if win then
        win:Hide()
    end
end

function BU.Toggle()
    if win and win:IsShown() then
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
    if open and not (win and win:IsShown()) then
        BU.Open()
    elseif not open and win and win:IsShown() then
        win:Hide()
    end
    BU.syncing = false
end

function BU.Uninstall()
    BU.syncing = true
    if win then
        win:Hide()
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
for _, ev in ipairs({ "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "QUEST_ACCEPTED", "PLAYER_MONEY", "BAG_NEW_ITEMS_UPDATED" }) do
    ns.On(ev, function()
        BU.Layout()
    end)
end

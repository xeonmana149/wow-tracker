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

local SLOT, GAP, PAD = 37, 2, 8
local HEAD = 34       -- the title row
local BAR = 26        -- the bag bar under it
local BAGBTN = 22
local FOOT = 24
local SECTION = 15    -- a section's heading
local SECTION_GAP = 4 -- between the main grid and a special bag's rows
local GREY = "|cff9a9a9a"
local CLASS_ICONS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local ART = "Interface\\AddOns\\ForeverGold\\Art\\"
local MAIL_ICON = ART .. "bag-mail.tga"
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local BANK_ICON = "Interface\\Icons\\INV_Misc_Bag_10_Blue"
local BAG_UI_ICON = ART .. "bag-inventory.tga"
local BANK_UI_ICON = ART .. "bag-bank.tga"
local GUILD_ICON = ART .. "bag-guild.tga"
local KEY_UI_ICON = ART .. "bag-key.tga"
local EMPTY_BAG_ICON = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
-- What an empty item slot shows (the game's own buttons show it too)
local EMPTY_SLOT_ART = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"

-- whether the client ships one of its UI atlases
local function hasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local BASE_FILL = { 0.075, 0.067, 0.055 }

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

-- The columns a window lays out: the Columns setting, or more when its
-- title or bag bar need a wider window, so the slots fill it to the right
-- edge instead of leaving a gap (2026-11-21, the bank's locked slots).
local function viewCols(V)
    return (V and V._cols) or cols()
end
local function showEmpty()
    return O().bagEmpty ~= false
end
local function split()
    return O().bagSplit == true
end
local function newSection()
    return O().bagNew == true
end
local function barShown()
    return O().bagBar ~= false
end
-- the keyring's slots, shown from its button in the bag bar
local function keysShown()
    return O().bagKeys == true
end
-- the guild bank (saved each visit) in the bank window
local function guildShown()
    return O().bagGuild ~= false
end
local function specialRows()
    return O().bagSpecialRows ~= false
end
local function junkDim()
    return O().bagJunkDim ~= false
end
-- The window's size, from Options (50% to 150%).
local function bagScale()
    return min(1.5, max(0.5, tonumber(O().bagScale) or 1))
end

local function bgAlpha()
    return min(1, max(0.2, tonumber(O().bagAlpha) or 0.5))
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

-- These are custom rules: native bag flags only support broad categories.
local MATERIALS = {
    { key = "cloth", label = "cloth", sub = 5 },
    { key = "herbs", label = "herbs", sub = 9, family = 32 },
    { key = "ore", label = "ore & bars", sub = 7, family = 1024 },
    { key = "leather", label = "leather", sub = 6, family = 8 },
}
local MATERIAL_BY_KEY = {}
for _, material in ipairs(MATERIALS) do MATERIAL_BY_KEY[material.key] = material end

local function clothRule(key)
    local c = ns.Char()
    if (key or "cloth") == "cloth" then return type(c.clothBag) == "table" and c.clothBag or nil end
    local rules = c.materialBags
    return type(rules) == "table" and type(rules[key]) == "table" and rules[key] or nil
end

local function materialForBag(bag)
    for _, material in ipairs(MATERIALS) do
        local rule = clothRule(material.key)
        if rule and rule.bag == bag then return material end
    end
end

local function clothKind(id, key)
    if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local _, _, _, _, _, class, subclass = ns.try(C_Item.GetItemInfoInstant, id)
    if class == nil or subclass == nil then return nil end
    local material = MATERIAL_BY_KEY[key or "cloth"]
    return material and class == 7 and subclass == material.sub or false
end

local function clothEligible(V, bag, info, material)
    local family = tonumber(info.fam) or 0
    return V.where == "bags" and isLive(V) and type(bag) == "number" and bag > 0
        and (info.size or 0) > 0 and (info.reagent or family == 0
            or (material and material.family and hasBit(family, material.family)))
end

local function clothInfo(bag, slot)
    return ns.try(C_Container.GetContainerItemInfo, bag, slot)
end

local clothAutoTry
local function clothFinish(message, retry)
    local run = BU.clothSort
    BU.clothSort = nil
    if run and run.auto and retry then
        BU.clothAutoPending = true
        BU.materialAutoIndex = max(1, (BU.materialAutoIndex or 2) - 1)
    end
    if not (run and run.auto and (retry or (run.moved == 0 and message:find("^finished")))) then
        local label = run and MATERIAL_BY_KEY[run.kind or "cloth"]
        ns.Print((label and label.label or "Material") .. " sorting: " .. message)
    end
    BU.Refresh()
    if BU.clothAutoPending and not retry then ns.Later("cloth-auto", 0.5, clothAutoTry) end
end

local function clothBusy()
    if InCombatLockdown and InCombatLockdown() then return true end
    if CursorHasItem and CursorHasItem() then return true end
    if (ns.Mail and ns.Mail.open) or INV.bankOpen or ns.ahOpen then return true end
    for _, name in ipairs({ "TradeFrame", "MerchantFrame", "AuctionHouseFrame" }) do
        local frame = _G[name]
        if type(frame) == "table" and frame.IsShown and frame:IsShown() then return true end
    end
    return false
end

local function clothStep()
    local run = BU.clothSort
    if not run then return end
    local rule, material = clothRule(run.kind), MATERIAL_BY_KEY[run.kind or "cloth"]
    if not rule or rule.bag ~= run.bag or (not run.auto and (not isLive(BU) or not BU.win or not BU.win:IsShown())) then
        return clothFinish("stopped because the bag or rule changed.")
    end
    if clothBusy() then return clothFinish("paused while another action is in progress.", run.auto) end
    local currentBag = INV.BagInfo(run.bag, false)
    if run.bagID and currentBag.id ~= run.bagID then return clothFinish("stopped because the selected bag changed.") end
    if INV.NumSlots(run.bag) == 0 then return clothFinish("the selected bag is no longer equipped.") end

    if run.pending then
        local dest = clothInfo(run.pending.toBag, run.pending.toSlot)
        local source = clothInfo(run.pending.fromBag, run.pending.fromSlot)
        if type(dest) == "table" and dest.itemID == run.pending.id and not dest.isLocked
            and (not source or source.itemID ~= run.pending.id) then
            run.pending, run.waits, run.moved = nil, 0, run.moved + 1
        else
            run.waits = run.waits + 1
            if run.waits >= 20 then return clothFinish("stopped waiting for the last move; check your bags before retrying.") end
            ns.Later("cloth-sort", 0.25, clothStep)
            return
        end
    end

    local targetSlots = INV.NumSlots(run.bag)
    local freeTarget, unwanted
    for slot = 1, targetSlots do
        local item = clothInfo(run.bag, slot)
        if type(item) ~= "table" or not item.itemID then
            freeTarget = freeTarget or slot
        else
            local kind = clothKind(item.itemID, run.kind)
            if kind == nil then return clothFinish("waiting for item information; try again in a moment.", run.auto) end
            if not kind then
                if item.isLocked then return clothFinish("an item is locked; try again in a moment.", run.auto) end
                unwanted = { bag = run.bag, slot = slot, id = item.itemID }
                break
            end
        end
    end
    local from, toBag, toSlot, skippedCloth, waitingInfo
    if unwanted then
        -- Only use ordinary bags for displaced items: no guessing which
        -- profession-specific bags can accept them.
        for _, bag in ipairs(INV.BagIDs()) do
            local info = INV.BagInfo(bag, false)
            if bag ~= run.bag and not materialForBag(bag) and not info.keyring and not info.reagent and BU.Family(info) == nil then
                for slot = 1, INV.NumSlots(bag) do
                    if not clothInfo(bag, slot) then toBag, toSlot = bag, slot; break end
                end
            end
            if toBag then break end
        end
        if not toBag then return clothFinish("no free ordinary bag slot for the other items.") end
        from = unwanted
    elseif freeTarget then
        for _, bag in ipairs(INV.BagIDs()) do
            if bag ~= run.bag and bag ~= INV.KeyringID() and not materialForBag(bag) then
                for slot = 1, INV.NumSlots(bag) do
                    local item = clothInfo(bag, slot)
                    if type(item) == "table" and item.itemID and clothKind(item.itemID, run.kind) then
                        local reagentOK = true
                        if currentBag.reagent then
                            local itemInfo = C_Item and C_Item.GetItemInfo
                            local values = itemInfo and { ns.try(itemInfo, item.itemID) } or {}
                            local reagent = values[17]
                            if reagent == nil then waitingInfo = true end
                            reagentOK = reagent == true
                        elseif (tonumber(currentBag.fam) or 0) > 0 then
                            local getter = C_Item and C_Item.GetItemFamily
                            local itemFamily = getter and ns.try(getter, item.itemID)
                            if type(itemFamily) ~= "number" then
                                waitingInfo = true
                                reagentOK = false
                            else
                                reagentOK = material and material.family and hasBit(itemFamily, material.family) or false
                            end
                        end
                        if reagentOK and not item.isLocked then from = { bag = bag, slot = slot, id = item.itemID }; break end
                        skippedCloth = true
                    end
                end
            end
            if from then break end
        end
        if from then toBag, toSlot = run.bag, freeTarget end
    end
    if not from then
        if waitingInfo then return clothFinish("waiting for item information; try again in a moment.", run.auto) end
        return clothFinish("finished; moved " .. run.moved .. " stack" .. (run.moved == 1 and "" or "s")
            .. (not freeTarget and ". The selected bag is full."
                or skippedCloth and ". Some items were locked or not confirmed compatible with this bag." or "."))
    end
    local ok = pcall(C_Container.PickupContainerItem, from.bag, from.slot)
    if not ok or not (CursorHasItem and CursorHasItem()) then return clothFinish("could not pick up an item.") end
    local placed = pcall(C_Container.PickupContainerItem, toBag, toSlot)
    if not placed or (CursorHasItem and CursorHasItem()) then
        -- Return the item to its original slot; never clear or discard it.
        if CursorHasItem and CursorHasItem() and not clothInfo(from.bag, from.slot) then
            pcall(C_Container.PickupContainerItem, from.bag, from.slot)
        end
        return clothFinish("the item could not be placed; check your cursor and bags.")
    end
    run.pending = { fromBag = from.bag, fromSlot = from.slot, toBag = toBag, toSlot = toSlot, id = from.id }
    ns.Later("cloth-sort", 0.25, clothStep)
end

function BU.StartClothSort(automatic, key)
    key = key or "cloth"
    local rule = clothRule(key)
    if BU.clothSort then return ns.Print("Material sorting is already running.") end
    if not rule then return ns.Print("Choose a bag for this material first.") end
    if type(CursorHasItem) ~= "function" or not C_Container or type(C_Container.PickupContainerItem) ~= "function" then
        return ns.Print("Material sorting is unavailable on this client.")
    end
    BU.clothSort = { bag = rule.bag, bagID = rule.id, kind = key, moved = 0, waits = 0, auto = automatic == true }
    clothStep()
end

-- Compare stack totals rather than slot positions: our own moves and ordinary
-- rearrangement must not look like newly received items.
function BU.CheckClothLoot()
    local totals = {}
    for _, bag in ipairs(INV.BagIDs()) do
        if bag ~= INV.KeyringID() then
            for slot = 1, INV.NumSlots(bag) do
                local item = clothInfo(bag, slot)
                if type(item) == "table" and item.itemID then
                    totals[item.itemID] = (totals[item.itemID] or 0) + (tonumber(item.stackCount) or 1)
                end
            end
        end
    end
    local previous = BU.clothAutoSnapshot
    BU.clothAutoSnapshot = totals
    local hasRule = false
    for _, material in ipairs(MATERIALS) do if clothRule(material.key) then hasRule = true; break end end
    if previous and hasRule then
        for id, count in pairs(totals) do
            if count > (previous[id] or 0) then
                BU.clothAutoPending = true
                BU.materialAutoIndex = 1
                ns.Later("cloth-auto", 0.5, clothAutoTry)
                break
            end
        end
    end
end

clothAutoTry = function()
    if not BU.clothAutoPending then return end
    if BU.clothSort or clothBusy() then return end
    local index = BU.materialAutoIndex or 1
    while MATERIALS[index] do
        local material = MATERIALS[index]
        index = index + 1
        BU.materialAutoIndex = index
        if clothRule(material.key) then
            BU.StartClothSort(true, material.key)
            return
        end
    end
    BU.clothAutoPending, BU.materialAutoIndex = nil, nil
end

ns.Listen("READY", function() BU.CheckClothLoot() end)
ns.On("BAG_UPDATE_DELAYED", function() BU.CheckClothLoot() end)
for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "CURSOR_CHANGED", "ITEM_LOCK_CHANGED",
    "MAIL_CLOSED", "BANKFRAME_CLOSED", "TRADE_CLOSED", "MERCHANT_CLOSED", "AUCTION_HOUSE_CLOSED",
    "GET_ITEM_INFO_RECEIVED" }) do
    ns.On(event, function() if BU.clothAutoPending then ns.Later("cloth-auto", 0.5, clothAutoTry) end end)
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
        local n = INV.NumSlots(bag)
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
            local n = INV.NumSlots(bag)
            -- the bag bar shows your empty bag slots too, to drop a bag into
            local tab = V.where == "bank" and INV.tabs[bag]
            if n > 0 or (V.where == "bags" and bag > 0) or (tab and (tab.slot or 0) > 1) then
                order[#order + 1] = bag
                info[bag] = (INV.BagInfo(bag, V.where == "bank"))
                info[bag].size = n
            end
        end
        return { cells = cells, size = size, order = order, info = info,
            bank = V.where == "bank" and INV.BankSlots() or nil }
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
        order = snap and snap.order or {}, info = info, guild = snap and snap.guild or nil,
        bank = V.where == "bank" and snap and type(snap.bankSlots) == "table" and snap.bankSlots or nil }
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

-- What the shown items are worth: at auction (only what can be traded -
-- nothing soulbound, bind-on-pickup or quest - after the cut, never below
-- what a vendor pays) and at a vendor (everything).
function BU.Worth(cells)
    local ah, vendor = 0, 0
    for _, c in ipairs(cells) do
        if c.id then
            local n = c.count or 1
            local v = ns.VendorSell(c.id) or 0
            vendor = vendor + v * n
            if not ns.Untradeable(c.id, c.bound) then
                local p = ns.AHNet and ns.AHNet(c.id)
                if p and ns.Suspicious and ns.Suspicious(c.id, ns.AHPrice(c.id)) then
                    p = nil
                end
                ah = ah + max(p or 0, v) * n
            end
        end
    end
    return floor(ah), floor(vendor)
end

-- Gray items a vendor will buy, in your bags right now: { cell, ... }, total.
-- Bags set to "Ignore: Sell junk" are left alone, like the game does.
function BU.Junk(ownInventory)
    local out, total = {}, 0
    if not ownInventory and not viewingSelf(BU) then
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

local merchantOpen, saleGeneration, selling = false, 0, false
ns.On("MERCHANT_SHOW", function()
    merchantOpen = true
    BU.Refresh()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
            if merchantOpen and ForeverUI and ForeverUI.Opt and ForeverUI.Opt("qolAutoJunk") then
                BU.SellJunk(true)
            end
        end)
    end
end)
ns.On("MERCHANT_CLOSED", function()
    merchantOpen = false
    saleGeneration, selling = saleGeneration + 1, false
    BU.Refresh()
end)

-- Sells the junk, a few items a moment so the vendor keeps up.
function BU.SellJunk(ownInventory)
    if not merchantOpen or selling then
        return
    end
    local list = BU.Junk(ownInventory)
    if #list == 0 then
        return
    end
    local i, sold, total = 0, 0, 0
    selling = true
    saleGeneration = saleGeneration + 1
    local generation = saleGeneration
    local function step()
        if not merchantOpen or generation ~= saleGeneration then
            return
        end
        for _ = 1, 6 do
            i = i + 1
            local c = list[i]
            if not c then
                selling = false
                if sold > 0 then ns.Print("sold " .. sold .. " junk item" .. (sold == 1 and "" or "s") .. " for " .. ns.Money(total) .. ".") end
                return
            end
            local info = ns.try(C_Container.GetContainerItemInfo, c.bag, c.slot)
            if type(info) == "table" and info.itemID == c.id and info.stackCount == c.count
                and (not c.link or info.hyperlink == c.link) and not info.isLocked and not info.hasNoValue
                and BU.IsJunk(info.itemID, info.quality) and not (MB() and MB().IsKept(info.itemID))
                and not BU.Ignored(c.bag, "junk") then
                local value = ns.VendorSell(c.id) or 0
                if value > 0 then
                    local ok = pcall(C_Container.UseContainerItem, c.bag, c.slot)
                    if ok then sold, total = sold + 1, total + value * c.count end
                end
            end
        end
        C_Timer.After(0.2, step)
    end
    step()
end

----------------------------------------------------------------------
-- Buttons
----------------------------------------------------------------------

local holders, liveButtons, nameN = {}, {}, 0
local seen -- hovering new loot (below)
local HINT = GREY .. "Shift+right-click: send to banker  -  Alt+right-click: more|r"

-- Adds the hint to an item tooltip that belongs to one of our live slots.
function BU.TooltipHint(tooltip)
    local owner = tooltip and tooltip.GetOwner and tooltip:GetOwner()
    local c = type(owner) == "table" and rawget(owner, "fgCell")
    if c and c.live and c.id and rawget(owner, "fgUp") then
        tooltip:AddLine(HINT)
    end
end

-- A glow along a slot's edges that fades out toward the middle (four
-- gradient strips), instead of tinting the whole slot.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local function edgeGlow(owner, region, layer, sub, width)
    local g, t = {}, {}
    width = width or 9
    for i = 1, 4 do
        t[i] = owner:CreateTexture(nil, layer, nil, sub)
        t[i]:SetTexture(WHITE)
        if t[i].SetBlendMode then
            t[i]:SetBlendMode("ADD")
        end
        t[i]:Hide()
    end
    t[1]:SetPoint("TOPLEFT", region, "TOPLEFT")
    t[1]:SetPoint("TOPRIGHT", region, "TOPRIGHT")
    t[1]:SetHeight(width)
    t[2]:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT")
    t[2]:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT")
    t[2]:SetHeight(width)
    t[3]:SetPoint("TOPLEFT", region, "TOPLEFT")
    t[3]:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT")
    t[3]:SetWidth(width)
    t[4]:SetPoint("TOPRIGHT", region, "TOPRIGHT")
    t[4]:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT")
    t[4]:SetWidth(width)
    g.t = t
    function g:SetColor(r, gr, b, a)
        if self.r == r and self.g == gr and self.b == b and self.a == a then
            return
        end
        self.r, self.g, self.b, self.a = r, gr, b, a
        local on, off = CreateColor(r, gr, b, a), CreateColor(r, gr, b, 0)
        t[1]:SetGradient("VERTICAL", off, on)   -- top: bright at the edge
        t[2]:SetGradient("VERTICAL", on, off)   -- bottom
        t[3]:SetGradient("HORIZONTAL", on, off) -- left
        t[4]:SetGradient("HORIZONTAL", off, on) -- right
    end
    function g:SetShown(on)
        for i = 1, 4 do
            t[i]:SetShown(on and true or false)
        end
    end
    function g:Show() self:SetShown(true) end
    function g:Hide() self:SetShown(false) end
    function g:IsShown() return t[1]:IsShown() end
    return g
end

-- Blue means new loot and nothing else; a hovered bag's slots light up warm white.
local NEW_GLOW = { 0.35, 0.62, 1, 0.95 } -- new loot, until you hover it
local HOVER = { 1, 0.95, 0.7, 0.8 } -- a bag's slots, while you hover it in the bar

local function overlays(b)
    b.fgTint = b:CreateTexture(nil, "ARTWORK", nil, 7)
    b.fgTint:SetPoint("TOPLEFT", 1, -1)
    b.fgTint:SetPoint("BOTTOMRIGHT", -1, 1)
    b.fgTint:Hide()
    b.fgMark = b:CreateTexture(nil, "OVERLAY", nil, 6)
    b.fgMark:SetSize(13, 13)
    b.fgMark:SetPoint("TOPRIGHT", -1, -1)
    b.fgMark:SetTexture(MAIL_ICON)
    b.fgMark:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.fgMark:Hide()
    -- what the item is: quality, quest, equipment set or can't-use colour
    b.fgColor = edgeGlow(b, b, "OVERLAY", 2, 8)
    -- junk: a little gold coin in the corner
    b.fgCoin = b:CreateTexture(nil, "OVERLAY", nil, 6)
    b.fgCoin:SetSize(12, 12)
    b.fgCoin:SetPoint("TOPLEFT", 2, -2)
    b.fgCoin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    b.fgCoin:Hide()
    -- an upgrade for you (Pawn says so)
    b.fgUp = b:CreateTexture(nil, "OVERLAY", nil, 6)
    b.fgUp:SetSize(14, 14)
    b.fgUp:SetPoint("TOPLEFT", 1, -1)
    if hasAtlas("bags-greenarrow") then
        b.fgUp:SetAtlas("bags-greenarrow")
    else
        b.fgUp:SetTexture("Interface\\Buttons\\UI-MicroStream-Green")
        b.fgUp:SetTexCoord(0, 1, 1, 0)
    end
    b.fgUp:Hide()
    -- new loot: a pulsing glow until you hover it
    b.fgNewF = CreateFrame("Frame", nil, b)
    b.fgNewF:SetAllPoints()
    b.fgNewF:SetFrameLevel((b:GetFrameLevel() or 1) + 3)
    b.fgNew = edgeGlow(b.fgNewF, b.fgNewF, "OVERLAY", 3, 11)
    b.fgNew:SetColor(NEW_GLOW[1], NEW_GLOW[2], NEW_GLOW[3], NEW_GLOW[4])
    b.fgNew:Show()
    if b.fgNewF.CreateAnimationGroup then
        local ag = b.fgNewF:CreateAnimationGroup()
        if ag then
            local a = ag:CreateAnimation("Alpha")
            a:SetFromAlpha(1)
            a:SetToAlpha(0.15)
            a:SetDuration(0.7)
            ag:SetLooping("BOUNCE")
            b.fgNewAnim = ag
        end
    end
    b.fgNewF:Hide()
    b.fgJunk = b:CreateTexture(nil, "OVERLAY", nil, 4)
    b.fgJunk:SetAllPoints()
    b.fgJunk:SetColorTexture(0.05, 0.04, 0.03, 0.5)
    b.fgJunk:Hide()
    b.fgDim = b:CreateTexture(nil, "OVERLAY", nil, 7)
    b.fgDim:SetAllPoints()
    b.fgDim:SetColorTexture(0, 0, 0, 0.72)
    b.fgDim:Hide()
    b.fgGlow = edgeGlow(b, b, "OVERLAY", 5, 10)
    b.fgGlow:SetColor(HOVER[1], HOVER[2], HOVER[3], HOVER[4])
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

local BLIZZ_GLOWS = { "BattlepayItemTexture", "BagIndicator", "NewItemTexture" }

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
    -- The template's blue store highlight (BattlepayItemTexture) starts out
    -- shown, and only the game's own bag frame hides it, so on our buttons
    -- every slot glowed blue. It and the bag indicator never show here: our
    -- own new-loot glow does that job.
    for _, k in ipairs(BLIZZ_GLOWS) do
        local t = rawget(b, k)
        if type(t) == "table" then
            if t.SetAlpha then t:SetAlpha(0) end
            if t.Hide then t:Hide() end
        end
    end
    overlays(b)
    -- Shift+right-click: send to banker. Alt+right-click: Forever Gold's actions.
    -- (A plain right-click still uses it - that's the game's own click.)
    b:HookScript("OnClick", function(self, which)
        local c = self.fgCell
        if which == "LeftButton" and c and c.id and IsShiftKeyDown and IsShiftKeyDown()
            and ns.AuctionUI and ns.AuctionUI.SearchFromBag and ns.AuctionUI.SearchFromBag(c.id, c.link) then
            closeSplit(self)
            return
        end
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
        seen(self)
        -- the hint comes from the game's own item tooltip hook (BU.TooltipHint), which
        -- runs each time the button refreshes its tooltip; this is for a client without it
        if not BU.hintHooked and GameTooltip and GameTooltip:IsOwned(self) and self.fgCell and self.fgCell.id then
            GameTooltip:AddLine(HINT)
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
    -- Our own quality glow is the single border; the native quality frame
    -- otherwise stacks a second colour over the unusable-item indication.
    local nativeBorder = rawget(b, "IconBorder")
    if type(nativeBorder) == "table" and nativeBorder.SetAlpha then nativeBorder:SetAlpha(0) end
    pcall(SetItemButtonDesaturated, b, (cell.locked or cell.junk) and true or false)
    if b.UpdateCooldown then
        pcall(b.UpdateCooldown, b, icon)
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
        seen(self)
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
        if which == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() and ns.AuctionUI
            and ns.AuctionUI.SearchFromBag and ns.AuctionUI.SearchFromBag(c.id, c.link) then return end
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
            art = body:CreateTexture(nil, "BACKGROUND", nil, 3) }
        t.art:SetTexture(EMPTY_SLOT_ART)
        t.art:SetAllPoints(t.fill)
        t.art:Hide()
        t.glow = edgeGlow(body, t.fill, "ARTWORK", 1, 10)
        t.glow:SetColor(HOVER[1], HOVER[2], HOVER[3], HOVER[4])
        V._bgs[V._usedBg] = t
    end
    return t
end

local function paintBg(t, fam)
    local fill = fam and fam.c or BASE_FILL
    -- The ring outside every slot stays dark, special bags too: a coloured
    -- one spilled the bag's colour past the slot's edge (2026-11-21).
    local a = 0.4 + 0.6 * bgAlpha()
    t.edge:SetColorTexture(0.01, 0.01, 0.01, 0.95)
    t.fill:SetColorTexture(fill[1], fill[2], fill[3], a)
end

----------------------------------------------------------------------
-- What a slot shows about its item: quality, quest, equipment set,
-- can't use, junk coin, upgrade arrow, new-loot flash (Options > Bags Forever)
----------------------------------------------------------------------

local function slotOpt(key)
    return O()[key] ~= false
end

-- How bright the glows are: Options' 1-100%, 50% to start.
local function glowAlpha()
    local pct = min(100, max(1, tonumber(O().bagGlow) or 50))
    return 0.2 + 0.8 * pct / 100
end

local CLASS_QUEST = 12
-- Only gear and recipes (2026-11-21: lockboxes, meat and other trade goods
-- were turning red from other red tooltip text, such as "Locked").
local CAN_BE_UNUSABLE = { [2] = true, [4] = true, [9] = true } -- weapons, armour, recipes
local unusable = {}
BU.ResetUnusable = function() unusable = {} end

local function isRed(c)
    return type(c) == "table" and (c.r or 0) > 0.99 and (c.g or 1) < 0.2 and (c.b or 1) < 0.2
end

local function startsWithLocalized(text, template)
    if type(text) ~= "string" or type(template) ~= "string" then return false end
    local prefix = template:match("^(.-)%%[%d%$%.%-]*[sdif]") or template
    prefix = prefix:gsub("%s+$", "")
    return prefix ~= "" and text:sub(1, #prefix):lower() == prefix:lower()
end

local function requirementText(text)
    if type(text) ~= "string" then return false end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    for _,key in ipairs({"ITEM_MIN_LEVEL", "ITEM_REQ_SKILL", "ITEM_REQ_REPUTATION", "ITEM_CLASSES_ALLOWED", "ITEM_RACES_ALLOWED", "ITEM_SPELL_KNOWN"}) do
        if startsWithLocalized(text, _G[key]) then return true end
    end
    local lower=text:lower()
    return lower:match("^requires%s") ~= nil or lower:match("^classes:") ~= nil
        or lower:match("^races:") ~= nil or lower:match("^already known") ~= nil
end

local function recipeUseText(text)
    if type(text) ~= "string" then return false end
    return startsWithLocalized(text, _G.ITEM_SPELL_TRIGGER_ONUSE) or text:lower():match("^use:") ~= nil
end

-- Read actual red requirements, not arbitrary red tooltip lines. Recipes can
-- show a preview of their finished item before the recipe's own Use line.
function BU.Unusable(cell)
    if not (cell and cell.id and C_TooltipInfo) then
        return false
    end
    local it = ns.Item(cell.id)
    local class = it and it.c
    if class == nil and C_Item and C_Item.GetItemInfoInstant then
        class = select(6, ns.try(C_Item.GetItemInfoInstant, cell.id))
    end
    if not CAN_BE_UNUSABLE[class] then
        return false
    end
    local key = tostring(cell.link or cell.id)
    if unusable[key] ~= nil then
        return unusable[key]
    end
    local data
    if cell.live and C_TooltipInfo.GetBagItem then
        data = ns.try(C_TooltipInfo.GetBagItem, cell.bag, cell.slot)
    elseif cell.link and C_TooltipInfo.GetHyperlink then
        data = ns.try(C_TooltipInfo.GetHyperlink, cell.link)
    elseif C_TooltipInfo.GetItemByID then
        data = ns.try(C_TooltipInfo.GetItemByID, cell.id)
    end
    -- Tooltip data can briefly be unavailable while an item is moving or
    -- loading. Do not cache that as a usable item for the rest of the session.
    if type(data) ~= "table" or type(data.lines) ~= "table" or #data.lines < 2 then
        return false
    end
    local v = false
    if type(data) == "table" and type(data.lines) == "table" then
        local useLine
        if class == 9 then
            for i=2,#data.lines do
                local line=data.lines[i]
                if type(line)=="table" and recipeUseText(line.leftText) then useLine=i;break end
            end
        end
        for i = 2, #data.lines do
            local l = data.lines[i]
            local afterRecipePreview=class~=9 or not useLine or i>useLine
            local known=type(l)=="table" and type(l.leftText)=="string"
                and (startsWithLocalized(l.leftText,_G.ITEM_SPELL_KNOWN) or l.leftText:lower():match("^already known")~=nil)
            if type(l) == "table" and ((afterRecipePreview or known) and isRed(l.leftColor) and requirementText(l.leftText)
                or afterRecipePreview and isRed(l.rightColor) and requirementText(l.rightText)) then
                v = true
                break
            end
        end
    end
    unusable[key] = v
    return v
end

ns.Listen("RECIPES_UPDATED", function() BU.ResetUnusable(); if ns.ready then BU.Refresh() end end)
for _,ev in ipairs({"SKILL_LINES_CHANGED", "PLAYER_LEVEL_UP", "NEW_RECIPE_LEARNED"}) do
    ns.On(ev, function() BU.ResetUnusable(); if ns.ready then ns.Later("bag-unusable", 0.5, BU.Refresh) end end)
end

local function questItem(cell)
    if cell.live and C_Container.GetContainerItemQuestInfo then
        local q = ns.try(C_Container.GetContainerItemQuestInfo, cell.bag, cell.slot)
        if type(q) == "table" and (q.isQuestItem or q.questID ~= nil) then
            return true
        end
    end
    local it = ns.Item(cell.id)
    return it ~= nil and it.c == CLASS_QUEST
end

local function inGearSet(cell)
    if cell.live and C_Container.GetContainerItemEquipmentSetInfo then
        return ns.try(C_Container.GetContainerItemEquipmentSetInfo, cell.bag, cell.slot) and true or false
    end
    return false
end

local function upgrade(cell)
    if not cell.live or (PawnCommon and PawnCommon.ShowBagUpgradeAdvisor == false) then
        return false
    end
    -- Pawn 2.14 exposes a link-based, budgeted bag API. nil means "try
    -- later", not "not an upgrade" (uncached item or this frame's budget).
    if type(PawnShouldItemLinkHaveUpgradeArrow) == "function" then
        if PawnIsInitialized == false then
            return nil
        end
        local info = ns.try(C_Container.GetContainerItemInfo, cell.bag, cell.slot)
        if type(info) ~= "table" or info.itemID ~= cell.id then
            return false
        end
        local link = info.hyperlink
        if not link then
            return nil
        end
        local ok, up = pcall(PawnShouldItemLinkHaveUpgradeArrow, link, true)
        if not ok then
            return false
        end
        return up
    elseif type(PawnIsContainerItemAnUpgrade) == "function" then
        -- Older Pawn integrations may still expose the container helper.
        local ok, up = pcall(PawnIsContainerItemAnUpgrade, cell.bag, cell.slot)
        return ok and up and true or false
    end
    return false
end

local pendingUpgrades = {}
local paintUpgrade
local function retryUpgrades()
    local pending = pendingUpgrades
    pendingUpgrades = {}
    for b, entry in pairs(pending) do
        local V, cell = entry.view, entry.cell
        -- A button can have been reused for another item or an offline alt.
        if V.win and V.win:IsShown() and b:IsShown() and b.fgCell == cell then
            paintUpgrade(V, b, cell)
        end
    end
end

paintUpgrade = function(V, b, cell)
    pendingUpgrades[b] = nil
    local up = false
    if cell.id and slotOpt("bagUpgrade") then
        up = upgrade(cell)
    end
    b.fgUp:SetShown(up == true and not b.fgCoin:IsShown())
    if up == nil then
        pendingUpgrades[b] = { view = V, cell = cell }
        -- Pawn replenishes its budget every quarter-second. Retry only the
        -- undecided arrows, without relayout (which would disrupt dragging).
        ns.Later("bag-upgrade-retry", 0.3, retryUpgrades)
    end
end

function BU.RefreshUpgrades()
    for _, V in ipairs(VIEWS) do
        if V.win and V.win:IsShown() then
            for _, b in ipairs(V._live) do
                if b:IsShown() and b.fgCell then
                    paintUpgrade(V, b, b.fgCell)
                end
            end
        end
    end
end

local pawnHooked = false
local function hookPawn()
    if not pawnHooked and type(PawnResetBags) == "function" then
        pawnHooked = true
        -- Observe invalidation without taking over Pawn's default bags:
        -- users can switch our bag replacement off during the session.
        hooksecurefunc("PawnResetBags", function()
            ns.Later("bag-upgrades", 0, BU.RefreshUpgrades)
        end)
    end
end
ns.Listen("READY", hookPawn)
ns.On("ADDON_LOADED", function(_, name)
    if name == "Pawn" then
        hookPawn()
        ns.Later("bag-upgrades", 0, BU.RefreshUpgrades)
    end
end)

-- The glow colour for a cell, or nil: can't use, then quest, then set, then quality.
function BU.SlotColor(cell, V)
    if not (cell and cell.id) then
        return nil
    end
    local mine = V == nil or V.char == nil or V.char == ns.charKey
    if mine and slotOpt("bagUnusable") and BU.Unusable(cell) then
        return 1, 0.12, 0.1, "unusable"
    end
    if slotOpt("bagQuest") and questItem(cell) then
        return 1, 0.82, 0.1, "quest"
    end
    if slotOpt("bagSets") and inGearSet(cell) then
        return 0.25, 0.75, 1, "set"
    end
    if slotOpt("bagQuality") and (cell.q or 0) >= 2 then
        local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[cell.q]
        if c then
            return c.r, c.g, c.b, "quality"
        end
    end
    return nil
end

local function paintUnusableTint(b, why)
    local r, g, bl = 1, 1, 1
    if why == "unusable" then r, g, bl = 0.75, 0.3, 0.3 end
    local icon = rawget(b, "icon")
    if type(icon) == "table" and icon.SetVertexColor then
        icon:SetVertexColor(r, g, bl)
    elseif SetItemButtonTextureVertexColor then
        pcall(SetItemButtonTextureVertexColor, b, r, g, bl)
    end
end

local function paintMarks(V, b, cell)
    local r, g, bl, why = BU.SlotColor(cell, V)
    -- Show rarity at the edge and unusable status on the icon itself.
    -- For common items the red edge remains the only colour cue.
    if why == "unusable" and slotOpt("bagQuality") and (cell.q or 0) >= 2 then
        local quality = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[cell.q]
        if quality then r, g, bl = quality.r, quality.g, quality.b end
    end
    if r then
        -- toned down: 20% under the brightness setting, quest yellow 30%
        b.fgColor:SetColor(r, g, bl, glowAlpha() * (why == "quest" and 0.7 or 0.8))
        b.fgColor:Show()
    else
        b.fgColor:Hide()
    end
    b.fgWhy = why
    -- can't use it: darkened red, as the game shows it
    paintUnusableTint(b, why)
    b.fgCoin:SetShown(cell.id ~= nil and slotOpt("bagPoorCoin") and BU.IsJunk(cell.id, cell.q) and true or false)
    paintUpgrade(V, b, cell)
    -- new loot flashes until you hover it
    local new = cell.new and slotOpt("bagFlash") and true or false
    b.fgNewF:SetShown(new)
    if b.fgNewAnim then
        if new and not b.fgNewAnim:IsPlaying() then
            b.fgNewAnim:Play()
        elseif not new and b.fgNewAnim:IsPlaying() then
            b.fgNewAnim:Stop()
        end
    end
    -- the game's own new-item glow stays until the bags close: ours does the job
    for _, k in ipairs({ "NewItemTexture", "BattlepayItemTexture", "BagIndicator", "flashAnim", "newitemglowAnim" }) do
        local part = b[k]
        if type(part) == "table" then
            if part.Stop then
                part:Stop()
            elseif part.Hide then
                part:Hide()
            end
        end
    end
end

-- Use the same item indicators in the mail picker as in bags and bank.
function BU.PaintMailSlot(button, stack, view)
    if not button.fgColor then overlays(button) end
    local cell = { live = true, where = "bags" }
    if stack then
        cell.id, cell.bag, cell.slot = stack.id, stack.bag, stack.slot
        local info = ns.try(C_Container.GetContainerItemInfo, stack.bag, stack.slot)
        if type(info) == "table" and info.itemID == stack.id then
            cell.q, cell.link = info.quality, info.hyperlink
            cell.new = C_NewItems and ns.try(C_NewItems.IsNewItem, stack.bag, stack.slot) and true or false
        end
        if cell.q == nil then
            local item = ns.Item(stack.id)
            cell.q = item and item.q
        end
    end
    button.fgCell = cell
    paintMarks(view, button, cell)
end

-- Hovering new loot: it's seen, the flash stops.
function seen(b)
    local c = b.fgCell
    if c and c.new then
        c.new = false
        if c.live and C_NewItems and C_NewItems.RemoveNewItem then
            ns.try(C_NewItems.RemoveNewItem, c.bag, c.slot)
        end
        b.fgNewF:Hide()
        if b.fgNewAnim and b.fgNewAnim:IsPlaying() then
            b.fgNewAnim:Stop()
        end
    end
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
        if info and info.main then
            return "Bank"
        end
        if info and info.slot then
            return (info.size or 0) == 0 and "Empty bank bag slot" or "Bank bag " .. (info.slot - 1)
        end
        return "Bank tab " .. tostring(bag)
    end
    if bag == 0 then
        return "Backpack"
    end
    if info and (info.size or 0) == 0 then
        return info.reagent and "Empty reagent bag slot" or "Empty bag slot"
    end
    return "Bag " .. bag
end
BU.BagName = function(bag, V) return bagName(V or BU, bag) end

-- Lays cells out in rows from y; returns the new y.
local function placeRow(V, list, y, q)
    local n = viewCols(V)
    local body = V.win.body
    for i, cell in ipairs(list) do
        local col, row = (i - 1) % n, floor((i - 1) / n)
        local x, cy = col * (SLOT + GAP), y - row * (SLOT + GAP)
        local fam = cell.bag ~= nil and slotOpt("bagTypeColor") and BU.Family(V._info[cell.bag]) or nil
        cell.junk = junkDim() and BU.IsJunk(cell.id, cell.q) or nil
        local bg = slotBg(V)
        paintBg(bg, fam)
        -- a 1px dark ring just outside every slot, so each one has the same defined edge
        bg.edge:ClearAllPoints()
        bg.edge:SetPoint("TOPLEFT", body, "TOPLEFT", x - 1, cy + 1)
        bg.edge:SetSize(SLOT + 2, SLOT + 2)
        bg.fill:ClearAllPoints()
        bg.fill:SetPoint("TOPLEFT", body, "TOPLEFT", x, cy)
        bg.fill:SetSize(SLOT, SLOT)
        bg.glow:Hide() -- it follows the slot's fill
        bg.edge:Show()
        bg.fill:Show()
        -- a saved empty slot has no button: the same slot picture a live one shows
        bg.art:SetShown(not cell.live and not cell.id)
        local b
        if cell.live then
            b = liveButton(V, cell.bag, cell.slot)
            if b then
                paintLive(b, cell)
                V._live[#V._live + 1] = b
                b.fgGen = V._gen
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
            paintMarks(V, b, cell)
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

-- Hovering a bag lights up its slots (nil: none). btn: the bar button the
-- mouse is on, so a refresh only lights them again while it still is.
function BU.HighlightBag(V, bag, btn)
    V = V or BU
    V.hot = bag
    V.hotBtn = bag ~= nil and btn or nil
    for _, p in ipairs(V._placed) do
        local on = bag ~= nil and p.bag == bag
        if p.b then
            p.b.fgGlow:SetShown(on)
        else
            p.bg.glow:SetShown(on)
        end
    end
end

-- Is the mouse still on the bar button that lit a bag, and is it still
-- that bag's button?
function BU.StillHovered(V)
    local btn = V.hotBtn
    if type(btn) ~= "table" or btn.bag ~= V.hot or not btn:IsShown() then
        return false
    end
    if type(btn.IsMouseOver) ~= "function" then
        return false
    end
    local ok, over = pcall(btn.IsMouseOver, btn)
    return ok and over == true
end

local function sectionHead(V, y, left, right)
    local h = heading(V)
    local body = V.win.body
    h.left:ClearAllPoints()
    h.left:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y - 1)
    h.left:SetText(left)
    h.right:ClearAllPoints()
    h.right:SetPoint("TOPRIGHT", body, "TOPLEFT", viewCols(V) * (SLOT + GAP) - GAP, y - 1)
    h.right:SetText(right or "")
    return y - SECTION
end

local function hideAll(V)
    -- live buttons aren't hidden here: one under the mouse while you drag
    -- an item would lose the drop. Those not placed again are put away after.
    V._prevLive = V._live
    V._gen = (V._gen or 0) + 1
    for _, b in ipairs(V._saved) do
        b:Hide()
        b.fgCell = nil
    end
    for _, t in ipairs(V._bgs) do
        t.edge:Hide()
        t.fill:Hide()
        -- The empty-slot picture is a separate region on the body, not a
        -- child of the fill. Unused saved slots must be hidden explicitly.
        t.art:Hide()
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

-- Bank bag slot i's place in the game: the bag sits at (Characterbanktab, i).
local function bankBagSpot(V, bag)
    local info = V.where == "bank" and bag ~= nil and V._info[bag]
    local where = Enum and Enum.BagIndex and Enum.BagIndex.Characterbanktab
    if info and info.slot and where then
        return where, info.slot
    end
    return nil
end

local function putIntoBag(V, bag)
    if not (CursorHasItem and CursorHasItem() and isLive(V)) then
        return false
    end
    if V.where == "bank" then
        -- a bag on the cursor goes into (or swaps with) that bank bag slot
        local where, slot = bankBagSpot(V, bag)
        if not where then
            return false
        end
        ns.try(C_Container.PickupContainerItem, where, slot)
        return true
    end
    if V.where ~= "bags" then
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
    if bag == nil then
        return -- a locked bank bag slot: its own button handles buying
    end
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
    if b.locked then
        local lines = { "Bank bag slot (locked)" }
        if b.cost then
            lines[#lines + 1] = "Costs " .. ns.Money(b.cost) .. " to unlock"
        end
        lines[#lines + 1] = GREY .. (not b.nextUp and "Unlock the ones before it first."
            or isLive(V) and "Click to buy it." or "Buy it at a banker.") .. "|r"
        return tip(b, lines)
    end
    local bag = b.bag
    local info = V._info[bag] or {}
    local lines = { bagName(V, bag) }
    if (info.size or 0) == 0 and ((V.where == "bags" and bag > 0) or info.slot) then
        lines[#lines + 1] = info.reagent and "No reagent bag here. Drop a reagent bag on it to put one in."
            or "No bag here. Drop a bag on it to put one in."
        return tip(b, lines)
    end
    if info.main then
        lines[#lines + 1] = (b.free or 0) .. " of " .. (info.size or 0) .. " slots free"
        lines[#lines + 1] = GREY .. "Click: hide or show its slots|r"
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
    local material = materialForBag(bag)
    if V.where == "bags" and isLive(V) and material then
        lines[#lines + 1] = material.label .. " bag - sorts when you get items"
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
    -- a bank bag slot not bought yet
    b.lock = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.lock:SetPoint("TOPLEFT", 2, -2)
    b.lock:SetPoint("BOTTOMRIGHT", -2, 2)
    if hasAtlas("bankslot-icon-lock") then
        b.lock:SetAtlas("bankslot-icon-lock")
    else
        b.lock:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
    end
    b.lock:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.9, 0.6, 0.18)
    b:SetScript("OnClick", function(self, which)
        if self.locked then
            if self.nextUp then
                BU.BuyBankSlot()
            end
            return
        end
        BU.BagClick(V, self.bag, which, self)
    end)
    b:SetScript("OnEnter", function(self)
        BU.HighlightBag(V, self.bag, self)
        bagTip(V, self)
    end)
    b:SetScript("OnLeave", function()
        BU.HighlightBag(V, nil)
        untip()
    end)
    b:SetScript("OnHide", function(self)
        if V.hotBtn == self then
            BU.HighlightBag(V, nil)
        end
    end)
    -- drag a bag out of its slot, or drop one in
    b:SetScript("OnDragStart", function(self)
        if self.locked or not isLive(V) then
            return
        end
        if V.where == "bank" then
            local where, slot = bankBagSpot(V, self.bag)
            if where then
                ns.try(C_Container.PickupContainerItem, where, slot)
            end
            return
        end
        local slot = invSlot(self.bag)
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
    local bars, keyring = {}, nil
    for _, bag in ipairs(d.order) do
        if d.info[bag] and d.info[bag].keyring then
            keyring = bag -- it has its own button, at the right
        else
            bars[#bars + 1] = bag
        end
    end
    if barShown() then
        for i, bag in ipairs(bars) do
            n = i
            local b = bagButton(V, i)
            local info = d.info[bag] or {}
            b.bag, b.free = bag, freeBy[bag] or 0
            b.locked, b.nextUp, b.cost = nil, nil, nil
            b.lock:Hide()
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
        -- the bank's bag slots you haven't bought yet, locked; the next one is for sale
        local slots = d.bank
        if slots and (slots.max or 0) > 1 then
            local shown = n
            for s = (slots.bought or 0) + 1, slots.max do
                if shown >= slots.max then
                    break
                end
                n = n + 1
                shown = shown + 1
                local b = bagButton(V, n)
                b.bag, b.free = nil, 0
                b.locked = true
                b.nextUp = s == (slots.bought or 0) + 1
                b.cost = b.nextUp and slots.cost or nil
                b.icon:SetTexture(EMPTY_BAG_ICON)
                b.icon:SetTexCoord(0, 1, 0, 1)
                if b.icon.SetDesaturated then
                    b.icon:SetDesaturated(true)
                end
                b.off:Show()
                b.lock:Show()
                b.count:SetText("")
                b.edge:SetColorTexture(C.goldEdge[1], C.goldEdge[2], C.goldEdge[3], 0.35)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + (n - 1) * (BAGBTN + 4), -HEAD)
                b:Show()
            end
        end
    end
    for i = n + 1, #V._bagBtns do
        V._bagBtns[i]:Hide()
    end
    -- wide enough for the whole bar
    V._barW = n > 0 and PAD * 2 + n * (BAGBTN + 4) or 0
    -- at the banker: what the next bag slot costs, and a button to buy it
    if win.buy then
        local slots = d.bank
        local selling = barShown() and isLive(V) and slots and slots.canBuy and slots.cost
        win.buy:SetShown(selling and true or false)
        win.buyCost:SetShown(selling and true or false)
        -- the bar runs the width of the window here: the price stands in for "AT THE BANK"
        win.sub:SetShown(not selling)
        if selling then
            win.buyCost:SetText((slots.afford == false and "|cffff5050Cost:|r " or "Cost: ") .. ns.Money(slots.cost))
            win.buyCost:ClearAllPoints()
            win.buyCost:SetPoint("LEFT", win, "TOPLEFT", PAD + n * (BAGBTN + 4) + 6, -HEAD - BAGBTN / 2)
            win.buy:ClearAllPoints()
            win.buy:SetPoint("LEFT", win.buyCost, "RIGHT", 8, 0)
            local costW = tonumber(win.buyCost:GetStringWidth() or 0) or 0
            V._barW = V._barW + 6 + max(costW, 70) + 8 + 84
        end
    end
    -- the keyring, at the right of the bar: click to show or hide its row
    if win.keys then
        local info = keyring and d.info[keyring]
        local shownKeys = barShown() and info ~= nil
        win.keys:SetShown(shownKeys)
        if shownKeys then
            win.keys.bag = keyring
            local size = info.size or 0
            win.keys.used, win.keys.size = size - (freeBy[keyring] or 0), size
            K.setIcon(win.keys.icon, KEY_UI_ICON)
            local on = keysShown()
            win.keys.off:SetShown(not on)
            if win.keys.icon.SetDesaturated then
                win.keys.icon:SetDesaturated(not on)
            end
            win.keys.count:SetText(tostring(win.keys.used))
            win.keys:ClearAllPoints()
            win.keys:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, -HEAD)
            V._barW = V._barW + BAGBTN + 12
        end
        win.sub:ClearAllPoints()
        if shownKeys then
            win.sub:SetPoint("RIGHT", win.keys, "LEFT", -6, 0)
        else
            if barShown() then
                win.sub:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, -(HEAD + 6))
            else
                win.sub:SetPoint("RIGHT", win.searchBtn, "LEFT", -8, 0)
            end
        end
    end
end

-- Bank-tab purchases are restricted to the game's secure bank UI. Bring the
-- already-open game window back for this visit instead of calling that API.
function BU.BuyBankSlot()
    if not isLive(BV) then return false end
    if InCombatLockdown and InCombatLockdown() then
        ns.Print("Leave combat before switching to the game's bank.")
        return false
    end
    if BankFrame and BankFrame.IsShown and BankFrame:IsShown() and BU.RestoreGameBank and BU.RestoreGameBank() then
        -- Hiding our bank normally closes the interaction. Temporarily clear
        -- the flag, then keep it so bankClosed still cleans up our bags.
        local atBanker = BV.atBanker
        BV.atBanker = nil
        if BV.win then BV.win:Hide() end
        BV.atBanker = atBanker
        ns.Print("Use the game's bank window to buy a bank slot.")
        return true
    end
    ns.Print("To buy a bank slot, turn off 'Use it at the banker' in Bags Forever options, then reopen the bank.")
    if ns.OpenOptions then ns.OpenOptions("bags") end
    return false
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
    if V.where == "guild" then
        win.title:SetText((d.guild or (who.guild and who.guild:match("^(.-)%-")) or "Guild") .. " Bank")
    else
        win.title:SetText(shortName(who.name or "?") .. "'s " .. (V.where == "bank" and "Bank" or "Inventory"))
    end
    win.title:SetShown(not win.searchBox:IsShown())
    if not INV.SetFace(win.who.icon, who) then
        K.setIcon(win.who.icon, V.where == "bank" and BANK_ICON or BAG_ICON)
    end
    win.sub:SetText("")
    if win.tabBags then
        win.tabBags:SetOn(true)
        win.tabBank:SetOn(BV.win ~= nil and BV.win:IsShown() and BV.where == "bank")
        win.tabGuild:SetShown(guildShown() and (who.guild ~= nil))
        win.tabGuild:SetOn(BV.win ~= nil and BV.win:IsShown() and BV.where == "guild")
    end
    win.sort:SetShown(live)
    win.bg:SetAlpha(bgAlpha())

    -- the grid
    local used, empty, marked = 0, 0, 0
    local main, fresh = {}, {}
    local special, specialOrder = {}, {} -- quivers, reagent and profession bags: rows of their own
    local freeBy = {}
    local keyCells, keySize = {}, 0 -- the keyring: its own row, from its button; not in the slot count
    for _, c in ipairs(cells) do
        local key = c.bag ~= nil and d.info[c.bag] and d.info[c.bag].keyring
        if key then
            keySize = keySize + 1
            if not c.id then
                freeBy[c.bag] = (freeBy[c.bag] or 0) + 1
            end
            if keysShown() and (c.id or showEmpty()) then
                keyCells[#keyCells + 1] = c
            end
        elseif c.id then
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
        if key then
            -- placed in its own row below
        elseif c.bag ~= nil and BU.IsHidden(c.bag, V) then
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
    -- as many columns as fill the width the title and the bag bar need
    do
        local titleW = win.title:IsShown() and (tonumber(win.title:GetStringWidth() or 0) or 0) or 140
        V._headW = PAD + 24 + 6 + titleW + 12 + (16 + 5 + 20 + 5 + 16 + 5 + 22 + 5)
        local need = max(V._headW, V._barW or 0, 290)
        local n = cols()
        while n < 24 and PAD * 2 + n * (SLOT + GAP) - GAP < need do
            n = n + 1
        end
        V._cols = n
    end
    local top = HEAD + (barShown() and BAR or 0)
    win.body:ClearAllPoints()
    win.body:SetPoint("TOPLEFT", PAD, -top)
    win.body:SetPoint("BOTTOMRIGHT", -PAD, FOOT + 4)

    local y = 0
    -- Match the text width to the final grid/window width, even when the
    -- current frame is still showing its previous size during refresh.
    local noteCols = viewCols(V)
    local noteGridWidth = PAD * 2 + noteCols * (SLOT + GAP) - GAP
    local noteWindowWidth = max(noteGridWidth, V._headW or 0, V._barW or 0, 290)
    win.note:SetWidth(max(1, floor(noteWindowWidth + 0.5) - PAD * 2))
    if d.missing then
        win.note:SetText(V.where == "guild"
            and (who.guild and "No guild bank saved yet. It's saved each time you open the guild vault."
                or shortName(who.name) .. " isn't in a guild (or hasn't logged in since this was added).")
            or V.where == "bank"
            and "No bank saved for " .. shortName(who.name) .. " yet. It's saved each time they visit a banker."
            or "No bags saved for " .. shortName(who.name) .. " yet. Log in on them once.")
        win.note:Show()
        y = -max(40, (win.note:GetStringHeight() or 0) + 12)
    elseif #main == 0 and #fresh == 0 and #specialOrder == 0 and #cells > 0 then
        win.note:SetText("Every bag is hidden. Click one in the bar above to show it again.")
        win.note:Show()
        y = -max(40, (win.note:GetStringHeight() or 0) + 12)
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
                y = y - SECTION_GAP
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
            y = y - (#main > 0 and SECTION_GAP or 0)
            y = sectionHead(V, y, hex .. bagName(V, bag) .. "|r", items .. " / " .. ((V._info[bag] or {}).size or #list))
            y = placeRow(V, list, y, q)
        end
    end
    if #keyCells > 0 then
        local items = 0
        for _, c in ipairs(keyCells) do
            if c.id then
                items = items + 1
            end
        end
        y = y - SECTION_GAP
        y = sectionHead(V, y, "|cffd8c070Keyring|r", items .. " / " .. keySize)
        y = placeRow(V, keyCells, y, q)
    end
    if #fresh > 0 then
        y = y - SECTION_GAP
        y = sectionHead(V, y, "New loot", plural(#fresh, "item"))
        y = placeRow(V, fresh, y, q)
    end
    if V.hot ~= nil then
        if BU.StillHovered(V) then
            BU.HighlightBag(V, V.hot, V.hotBtn)
        else
            BU.HighlightBag(V, nil)
        end
    end
    for _, b in ipairs(V._prevLive or {}) do
        -- only if no other view has taken it since
        if b.fgGen ~= V._gen and b.fgCell and b:GetParent() and b:GetParent():GetParent() == V.win.body then
            b:Hide()
            b.fgCell = nil
        end
    end
    V._prevLive = nil

    -- footer
    size = size - keySize
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
    -- fitted to the grid, but never cutting off the title or the bag bar
    local n = viewCols(V)
    local w = PAD * 2 + n * (SLOT + GAP) - GAP
    local headW = V._headW or 0
    local h = top - y + FOOT + PAD
    win:SetScale(bagScale())
    win:SetSize(floor(max(w, headW, V._barW or 0, 290) + 0.5), floor(max(h, 120) + 0.5))
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
        if r.icon.SetDesaturated then
            r.icon:SetDesaturated(false)
        end
        r.onClick = row.onClick and function()
            closePopup()
            row.onClick()
        end or nil
        r:SetDisabled(row.header or row.disabled)
        r:SetOn(row.on)
        if row.face and INV.SetFace(r.icon, row.face) then
            r.icon:Show()
        elseif row.icon then
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
    if where == "guild" then
        return BU.OpenGuild(key)
    elseif where == "bank" and (V == BU or BV.where == "guild") then
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
    rows[#rows + 1] = { text = "Inventory", icon = BAG_UI_ICON, on = V.where == "bags",
        onClick = function() BU.Pick(V.char, "bags", V) end }
    rows[#rows + 1] = { text = V == BU and "Bank  " .. GREY .. "(opens beside)|r" or "Bank", icon = BANK_UI_ICON,
        on = V.where == "bank" or (BV.win ~= nil and BV.win:IsShown()),
        onClick = function() BU.Pick(V.char, "bank", V) end }
    local me = ns.db.chars[V.char or ns.charKey]
    if guildShown() and me and me.guild then
        rows[#rows + 1] = { text = "Guild bank", icon = GUILD_ICON,
            on = BV.win ~= nil and BV.win:IsShown() and BV.where == "guild",
            onClick = function() BU.Pick(V.char, "guild", V) end }
    end
    rows[#rows + 1] = { text = "Characters", header = true }
    for _, c in ipairs(INV.Characters()) do
        local coords = c.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.class]
        rows[#rows + 1] = { text = INV.ClassHex(c.class) .. shortName(c.name) .. "|r" .. (c.self and (GREY .. "  (you)|r") or ""),
            coords = coords, face = c, on = (V.char or ns.charKey) == c.key, key = c.key,
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

local ALPHAS = { 1, 0.85, 0.7, 0.5, 0.4, 0.25 }

function BU.SettingsRows()
    return {
        { text = "Bag window", header = true },
        settingRow("Show empty slots", "bagEmpty", true),
        settingRow("Split by bag (off: one big inventory)", "bagSplit", false),
        settingRow("Quivers and special bags on their own rows", "bagSpecialRows", true),
        settingRow("New loot in its own row", "bagNew", false),
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
        rows[#rows + 1] = { text = GREY .. (info.reagent and "No reagent bag here. Drop one on it.|r"
            or "No bag here. Drop a bag on it.|r"), disabled = true }
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
    if V.where == "bags" and isLive(V) and bag > 0 then
        local any = false
        for _, material in ipairs(MATERIALS) do if clothEligible(V, bag, info, material) then any = true; break end end
        if any then
        rows[#rows + 1] = { text = "Custom sorting", header = true }
        for _, m in ipairs(MATERIALS) do
            local material = m
            if clothEligible(V, bag, info, material) then
                local rule = clothRule(material.key)
                local selected = rule and rule.bag == bag
                rows[#rows + 1] = { text = "Use this bag for " .. material.label, on = selected, onClick = function()
                    local c = ns.Char()
                    c.materialBags = type(c.materialBags) == "table" and c.materialBags or {}
                    if not selected then
                        if c.clothBag and c.clothBag.bag == bag then c.clothBag = nil end
                        for key, existing in pairs(c.materialBags) do
                            if type(existing) == "table" and existing.bag == bag then c.materialBags[key] = nil end
                        end
                    end
                    if material.key == "cloth" then
                        if selected then c.clothBag = nil else c.clothBag = { bag = bag, id = info.id } end
                    else
                        if selected then c.materialBags[material.key] = nil
                        else c.materialBags[material.key] = { bag = bag, id = info.id } end
                    end
                    if BU.clothSort then BU.clothSort = nil end
                    BU.Refresh(V)
                end }
                if selected then
                    rows[#rows + 1] = { text = "Sort " .. material.label .. " now", onClick = function() BU.StartClothSort(false, material.key) end }
                end
            end
        end
        if materialForBag(bag) then
            rows[#rows + 1] = { text = GREY .. "Auto-sorts after new items.|r", disabled = true }
        end
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

-- Compact icon buttons, with the same hairline and hover as the other windows.
local function bareButton(parent, w, h, tipText, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    K.skin(b, C.btn[1], C.btn[2], C.btn[3], 1, C.btnEdge[1], C.btnEdge[2], C.btnEdge[3], 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.9, 0.6, 0.18)
    if hl.SetBlendMode then
        hl:SetBlendMode("ADD")
    end
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) tip(self, { tipText }) end)
    b:SetScript("OnLeave", untip)
    return b
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
    -- Bag transparency is controlled separately by the existing Background
    -- setting; leave its texture at full alpha so that setting stays exact.
    K.skin(win, C.bg[1], C.bg[2], C.bg[3], 1)
    win:SetSize(340, 300)
    win:SetScale(bagScale())
    win:Hide()

    -- Title: the character. Click to pick another; right-click opens the
    -- other window (bank beside the bags, or the bags beside the bank).
    win.who = CreateFrame("Button", nil, win)
    win.who:SetSize(24, 24)
    win.who:SetPoint("TOPLEFT", PAD, -6)
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
    win.title = K.label(win, K.SERIF_M or K.SERIF_L)
    win.title:SetPoint("LEFT", win.who, "RIGHT", 6, 0)
    win.title:SetTextColor(C.goldText[1], C.goldText[2], C.goldText[3])
    if win.title.SetWordWrap then
        win.title:SetWordWrap(false)
    end

    -- The same red-and-gold close button used by the other themed windows.
    win.close = K.closeButton(win, 22, 22, function() win:Hide() end)
    win.close:SetPoint("TOPRIGHT", -5, -5)
    win.settings = bareButton(win, 20, 20, "Settings (Options > AddOns > Bags Forever)", function(self)
        closePopup()
        if ns.OpenOptions and ns.OpenOptions("bags") then
            return
        end
        openPopup(self, BU.SettingsRows(), 290)
    end)
    win.settings.icon:SetTexture("Interface\\AddOns\\ForeverGold\\Art\\settings.tga")
    win.settings:SetPoint("RIGHT", win.close, "LEFT", -5, 0)
    win.sort = bareButton(win, 20, 20, "Sort items", function() BU.Sort(V) end)
    win.sort.icon:SetTexture(ART .. "bag-sort.tga")
    win.sort:SetPoint("RIGHT", win.settings, "LEFT", -5, 0)
    win.searchBtn = bareButton(win, 20, 20, "Search", function() toggleSearch(V) end)
    win.searchBtn.icon:SetTexture(ART .. "bag-search.tga")
    win.searchBtn:SetPoint("RIGHT", win.sort, "LEFT", -5, 0)
    win.title:SetPoint("RIGHT", win.searchBtn, "LEFT", -6, 0)
    win.sub = K.label(win, "GameFontDisableSmall")
    win.sub:SetPoint("TOPRIGHT", -PAD, -(HEAD + 6))

    -- the keyring, at the right end of the bag bar
    local keys = CreateFrame("Button", nil, win)
    win.keys = keys
    keys:SetSize(BAGBTN, BAGBTN)
    keys.edge = keys:CreateTexture(nil, "BACKGROUND")
    keys.edge:SetAllPoints()
    keys.edge:SetColorTexture(0.55, 0.45, 0.15, 0.9)
    keys.icon = keys:CreateTexture(nil, "ARTWORK")
    keys.icon:SetPoint("TOPLEFT", 2, -2)
    keys.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    keys.off = keys:CreateTexture(nil, "OVERLAY", nil, 1)
    keys.off:SetPoint("TOPLEFT", 2, -2)
    keys.off:SetPoint("BOTTOMRIGHT", -2, 2)
    keys.off:SetColorTexture(0, 0, 0, 0.5)
    keys.count = keys:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    keys.count:SetPoint("BOTTOMRIGHT", -1, 1)
    local khl = keys:CreateTexture(nil, "HIGHLIGHT")
    khl:SetAllPoints()
    khl:SetColorTexture(1, 0.9, 0.6, 0.18)
    keys:SetScript("OnClick", function()
        O().bagKeys = not keysShown()
        BU.Refresh()
    end)
    keys:SetScript("OnEnter", function(self)
        BU.HighlightBag(V, self.bag, self)
        tip(self, { "Keyring", (self.used or 0) .. " of " .. (self.size or 0) .. " slots used",
            GREY .. "Click: " .. (keysShown() and "hide" or "show") .. " your keys|r" })
    end)
    keys:SetScript("OnLeave", function()
        BU.HighlightBag(V, nil)
        untip()
    end)
    keys:Hide()

    -- Search: takes the title's place
    win.searchBox = CreateFrame("EditBox", nil, win)
    win.searchBox:SetHeight(20)
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
        win.tabBags = iconButton(win, BAG_UI_ICON, "Inventory", function() BU.Pick(V.char, "bags", V) end)
        win.tabBags:SetSize(28, 28)
        win.tabBags:SetPoint("TOPRIGHT", win, "TOPLEFT", -3, -HEAD)
        win.tabBank = iconButton(win, BANK_UI_ICON, "Bank, in its own window (saved each visit)", function() BU.ToggleBank(V.char) end)
        win.tabBank:SetSize(28, 28)
        win.tabBank:SetPoint("TOP", win.tabBags, "BOTTOM", 0, -4)
        win.tabGuild = iconButton(win, GUILD_ICON, "Guild bank, in the bank window (saved each visit)", function() BU.ToggleGuild(V.char) end)
        win.tabGuild:SetSize(28, 28)
        win.tabGuild:SetPoint("TOP", win.tabBank, "BOTTOM", 0, -4)
    end

    -- The grid
    win.body = CreateFrame("Frame", nil, win)
    win.body:SetPoint("TOPLEFT", PAD, -HEAD)
    win.body:SetPoint("BOTTOMRIGHT", -PAD, FOOT + 4)
    win.note = K.label(win.body, "GameFontDisable")
    win.note:SetPoint("TOPLEFT", 0, -6)
    win.note:SetWidth(1) -- set to the available body width on each refresh
    if win.note.SetWordWrap then win.note:SetWordWrap(true) end

    -- Footer
    local line = K.tex(win, "ARTWORK", C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 1)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", PAD, FOOT)
    line:SetPoint("BOTTOMRIGHT", -PAD, FOOT)
    local bagIcon = win:CreateTexture(nil, "ARTWORK")
    bagIcon:SetSize(14, 14)
    bagIcon:SetPoint("BOTTOMLEFT", PAD, 5)
    K.setIcon(bagIcon, V == BU and BAG_UI_ICON or BANK_UI_ICON)
    win.slots = K.label(win, "GameFontHighlightSmall")
    win.slots:SetPoint("LEFT", bagIcon, "RIGHT", 6, 0)
    win.money = K.label(win, "GameFontHighlightSmall")
    win.money:SetPoint("BOTTOMRIGHT", -PAD, 7)
    win.mark = CreateFrame("Button", nil, win)
    win.mark:SetSize(40, 17)
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
    win.worth:SetSize(110, 17)
    win.worth:SetPoint("BOTTOM", 0, 4)
    win.worth:EnableMouse(true)
    win.worthText = K.label(win.worth, "GameFontHighlightSmall")
    win.worthText:SetPoint("CENTER")
    win.worth:SetScript("OnEnter", function(self)
        tip(self, { "What this is worth",
            "At auction: " .. ns.Money(self.ah or 0) .. "  (after the 5% cut, never less than a vendor pays; soulbound and bind-on-pickup items left out)",
            "At a vendor: " .. ns.Money(self.vendor or 0) })
    end)
    win.worth:SetScript("OnLeave", untip)
    if V == BV then
        win.buyCost = K.label(win, "GameFontNormalSmall")
        win.buyCost:Hide()
        win.buy = K.button(win, "Game's bank", 84, 22, function() BU.BuyBankSlot() end)
        win.buy:Hide()
    end
    if V == BU then
        win.junk = K.button(win, "Sell junk", 150, 22, function() BU.SellJunk() end)
        win.junk:SetPrimary(true)
        win.junk:SetPoint("BOTTOMLEFT", win, "TOPLEFT", 0, 4)
        win.junk:Hide()
    end

    win:SetScript("OnHide", function()
        closePopup()
        V.hot = nil
        if V == BV and BV.atBanker then
            -- closing it at the banker ends the visit, as the game's bank frame does
            BV.atBanker = nil
            if INV.bankOpen and C_Bank and C_Bank.CloseBankFrame then
                ns.try(C_Bank.CloseBankFrame)
            end
        end
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
    BV.where = "bank"
    BV.char = key or ns.charKey
    BV.hot = nil
    resetSearch(BV)
    if not BV.win:IsShown() then
        placeWindow(BV)
    end
    BV.win:Show()
    BU.Refresh()
end

-- The bank window, showing a character's guild bank (saved each visit).
function BU.OpenGuild(key)
    BU.OpenBank(key)
    BV.where = "guild"
    BU.Refresh()
end

function BU.ToggleGuild(key)
    key = key or ns.charKey
    if BV.win and BV.win:IsShown() and BV.where == "guild" and (BV.char or ns.charKey) == key then
        BV.win:Hide()
    else
        BU.OpenGuild(key)
    end
end

function BU.ToggleBank(key)
    key = key or ns.charKey
    if BV.win and BV.win:IsShown() and BV.where == "bank" and (BV.char or ns.charKey) == key then
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

-- The game's bank frame, kept out of sight while ours does the job. It's moved
-- under a hidden frame while it's closed: hiding it at the banker would end
-- the visit (its OnHide closes the bank).
local function bankOn()
    return BU.Enabled() and O().bagBank ~= false
end
BU.BankEnabled = bankOn

local function hideGameBank()
    local f = BankFrame
    if not (f and bankOn()) or f:IsShown() then
        return
    end
    -- A character with no bank tabs needs the secure game bank to provide
    -- its first one. Addons cannot purchase it through C_Bank themselves.
    local kind = Enum and Enum.BankType and Enum.BankType.Character
    local count = kind and C_Bank and C_Bank.FetchNumPurchasedBankTabs
        and ns.try(C_Bank.FetchNumPurchasedBankTabs, kind)
    if count == 0 then
        if savedParents[f] and BU.RestoreGameBank then BU.RestoreGameBank() end
        return
    end
    hiddenParent = hiddenParent or CreateFrame("Frame")
    hiddenParent:Hide()
    if f:GetParent() ~= hiddenParent then
        if not savedParents[f] then
            savedParents[f] = f:GetParent() or UIParent
            blizzFrames[#blizzFrames + 1] = f
        end
        pcall(f.SetParent, f, hiddenParent)
    end
end

-- Gives the game its bank frame back (Bags Forever at the banker switched off).
function BU.RestoreGameBank()
    local f = BankFrame
    if f and savedParents[f] then
        local parent = savedParents[f]
        local ok = pcall(f.SetParent, f, parent)
        if not ok or f:GetParent() ~= parent then return false end
        savedParents[f] = nil
        for i, g in ipairs(blizzFrames) do
            if g == f then
                table.remove(blizzFrames, i)
                break
            end
        end
        return true
    end
    return false
end

local function ourBank()
    return BankFrame == nil or BankFrame:GetParent() == hiddenParent
end

-- At the banker: our bank window and your bags, like the game's.
local function bankOpened()
    if not bankOn() then
        return
    end
    hideGameBank()
    if not ourBank() then
        return -- the game's frame was up when we started: it does this visit
    end
    BV.openedBags = not (BU.win and BU.win:IsShown())
    BU.OpenBank(ns.charKey)
    BV.atBanker = true
    if BV.openedBags then
        if OpenAllBags then
            pcall(OpenAllBags)
        end
        if not (BU.win and BU.win:IsShown()) then
            BU.Open()
        end
    end
end

local function bankClosed()
    if BV.atBanker then
        BV.atBanker = nil
        if BV.win then
            BV.win:Hide()
        end
        if BV.openedBags then
            BV.openedBags = nil
            if CloseAllBags then
                pcall(CloseAllBags)
            end
            BU.Close()
        end
    end
    hideGameBank()
end

ns.Listen("BANK", function(open)
    if open then
        bankOpened()
    else
        bankClosed()
    end
end)

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
    hideGameBank()
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
-- Picking an item up or putting it down: repaint the buttons where they
-- are (a full relayout mid-drag would lose the drop).
function BU.Repaint()
    for _, V in ipairs(VIEWS) do
        if V.win and V.win:IsShown() then
            for _, b in ipairs(V._live) do
                local c = b.fgCell
                if c and c.live and b:IsShown() then
                    local info = ns.try(C_Container.GetContainerItemInfo, c.bag, c.slot)
                    c.locked = type(info) == "table" and info.isLocked or false
                    pcall(SetItemButtonDesaturated, b, (c.locked or c.junk) and true or false)
                    if b.UpdateCooldown then
                        pcall(b.UpdateCooldown, b, type(info) == "table" and info.iconFileID or nil)
                    end
                    -- The game can reset the icon colour when lock state is
                    -- updated. Keep the current item's red usability tint.
                    paintUnusableTint(b, b.fgWhy)
                end
            end
        end
    end
end
for _, ev in ipairs({ "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN" }) do
    ns.On(ev, function()
        BU.Repaint()
    end)
end
-- An item moved, split or arrived: redraw on the next frame. (The saved
-- copy of your bags follows half a second later; waiting for it made every
-- move lag, 2026-11-21.)
for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED" }) do
    ns.On(ev, function()
        for _, V in ipairs(VIEWS) do
            if V.win and V.win:IsShown() and isLive(V) then
                ns.Later("bag-refresh", 0, BU.Refresh)
                return
            end
        end
    end)
end
for _, ev in ipairs({ "QUEST_ACCEPTED", "PLAYER_MONEY", "BAG_NEW_ITEMS_UPDATED",
    "BAG_SLOT_FLAGS_UPDATED", "PLAYER_EQUIPMENT_CHANGED" }) do
    ns.On(ev, function()
        BU.Layout()
    end)
end

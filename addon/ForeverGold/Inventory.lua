-- Forever Gold - every character's bags and bank, saved
--
-- What's in each slot of your bags (and your bank, from the last time you
-- had it open) is kept in the saved file, so the bag window can show any of
-- your characters' bags and banks while you're logged in on another, and
-- item tooltips can say who has how many.
--
-- c.inv = {
--     bags = { size = total slots, at = when saved,
--              slots = { { bag, slot, itemID, count, quality, link or false, bound }, ... },
--              sizes = { [bag] = slots }, order = { bag, bag, ... } },
--     bank = { ...the same, from the last visit to a banker },
-- }
-- c.bags / c.bank = { [itemID] = count } (c.bags is filled in Chars.lua).
-- A link is only kept for weapons and armour, whose links carry the random
-- "of the Bear" part and enchants; everything else is rebuilt from its ID.

local _, ns = ...

local INV = {}
ns.Inv = INV

local CLASS_WEAPON, CLASS_ARMOR = 2, 4

-- Your bags: the backpack and the bags in your bag slots.
function INV.BagIDs()
    local ids = {}
    local last = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0)
    for bag = 0, last do
        ids[#ids + 1] = bag
    end
    return ids
end

-- The bank's containers, while it's open: its tabs (WoW Forever's bank),
-- or the old main bank and bank bags.
function INV.BankIDs()
    local ids = {}
    if C_Bank and C_Bank.FetchPurchasedBankTabData and Enum and Enum.BankType then
        local tabs = ns.try(C_Bank.FetchPurchasedBankTabData, Enum.BankType.Character)
        if type(tabs) == "table" then
            for _, t in ipairs(tabs) do
                if type(t) == "table" and t.ID then
                    ids[#ids + 1] = t.ID
                end
            end
        end
    end
    if #ids == 0 then
        local main = (Enum and Enum.BagIndex and Enum.BagIndex.Bank) or BANK_CONTAINER or -1
        ids[1] = main
        local first = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0) + 1
        for bag = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do
            ids[#ids + 1] = bag
        end
    end
    return ids
end

INV.bankOpen = false

local function keepLink(id, link)
    if type(link) ~= "string" then
        return nil
    end
    local it = ns.Item(id)
    if it and (it.c == CLASS_WEAPON or it.c == CLASS_ARMOR) then
        return link
    end
    return nil
end

-- Reads containers into { size, slots, at } and a count per item.
local function read(ids)
    local out, counts = { size = 0, slots = {}, sizes = {}, order = {}, at = time() }, {}
    if not C_Container or not C_Container.GetContainerNumSlots then
        return out, counts
    end
    for _, bag in ipairs(ids) do
        local n = ns.try(C_Container.GetContainerNumSlots, bag) or 0
        out.size = out.size + n
        if n > 0 then
            out.sizes[bag] = n
            out.order[#out.order + 1] = bag
        end
        for slot = 1, n do
            local info = ns.try(C_Container.GetContainerItemInfo, bag, slot)
            if type(info) == "table" and info.itemID then
                local count = info.stackCount or 1
                out.slots[#out.slots + 1] = { bag, slot, info.itemID, count, info.quality,
                    keepLink(info.itemID, info.hyperlink) or false, info.isBound and true or false }
                counts[info.itemID] = (counts[info.itemID] or 0) + count
            end
        end
    end
    return out, counts
end

function INV.SaveBags()
    local c = ns.Char()
    c.inv = type(c.inv) == "table" and c.inv or {}
    c.inv.bags = read(INV.BagIDs())
end

function INV.SaveBank()
    if not INV.bankOpen then
        return
    end
    local c = ns.Char()
    c.inv = type(c.inv) == "table" and c.inv or {}
    local snap, counts = read(INV.BankIDs())
    if snap.size == 0 then
        return -- the bank isn't really readable (yet): keep the last copy
    end
    c.inv.bank, c.bank = snap, counts
    ns.Fire("INVENTORY")
end

ns.Listen("BAGS_UPDATED", function()
    INV.SaveBags()
    if INV.bankOpen then
        INV.SaveBank()
    end
    ns.Fire("INVENTORY")
end)

ns.On("BANKFRAME_OPENED", function()
    INV.bankOpen = true
    ns.Later("inv-bank", 0.3, INV.SaveBank)
    ns.Fire("BANK", true)
end)
ns.On("BANKFRAME_CLOSED", function()
    if INV.bankOpen then
        INV.SaveBank()
    end
    INV.bankOpen = false
    ns.Fire("BANK", false)
end)
ns.On("PLAYERBANKSLOTS_CHANGED", function()
    ns.Later("inv-bank", 0.3, INV.SaveBank)
end)
ns.On("BAG_UPDATE", function()
    if INV.bankOpen then
        ns.Later("inv-bank", 0.3, INV.SaveBank)
    end
end)

----------------------------------------------------------------------
-- Reading it back
----------------------------------------------------------------------

-- Characters you've saved bags for, this one first, then by name:
-- { { key, name, class, money, realmKey, self }, ... }
function INV.Characters()
    local out = {}
    for key, c in pairs(ns.db.chars) do
        if type(c) == "table" and c.name then
            out[#out + 1] = { key = key, name = c.name, class = c.class, money = c.money, realmKey = c.realmKey,
                self = key == ns.charKey, hasBank = type(c.inv) == "table" and c.inv.bank ~= nil }
        end
    end
    table.sort(out, function(a, b)
        if a.self ~= b.self then
            return a.self
        end
        return a.name < b.name
    end)
    return out
end

-- The saved snapshot of a character's bags or bank, or nil.
function INV.Snapshot(key, where)
    local c = ns.db.chars[key]
    local inv = c and type(c.inv) == "table" and c.inv
    return inv and inv[where] or nil
end

-- How many of an item each character has: { { name, bags, bank, key }, ... },
-- the most first, and the total.
function INV.WhoHas(id)
    local out, total = {}, 0
    for key, c in pairs(ns.db.chars) do
        if type(c) == "table" and c.name then
            local bags = type(c.bags) == "table" and c.bags[id] or 0
            local bank = type(c.bank) == "table" and c.bank[id] or 0
            if bags + bank > 0 then
                out[#out + 1] = { name = c.name, bags = bags, bank = bank, key = key, class = c.class }
                total = total + bags + bank
            end
        end
    end
    table.sort(out, function(a, b) return a.bags + a.bank > b.bags + b.bank end)
    return out, total
end

local function shortName(name)
    return (tostring(name or "?"):gsub("%-.*$", ""))
end

local function classHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c and c.colorStr then
        return "|c" .. c.colorStr
    end
    return "|cffffffff"
end
INV.ClassHex = classHex

-- Item tooltips: "Your characters have 31: Xeon Banker 20 (bank 15), ..."
function ns.InventoryTooltip(tooltip, id)
    if ns.db.opts.bagTooltip == false then
        return
    end
    local who, total = INV.WhoHas(id)
    if #who == 0 then
        return
    end
    tooltip:AddLine("|cffffd100Your characters have " .. total .. "|r")
    for i = 1, math.min(6, #who) do
        local w = who[i]
        local where
        if w.bags > 0 and w.bank > 0 then
            where = w.bags .. " bags, " .. w.bank .. " bank"
        elseif w.bank > 0 then
            where = "bank"
        else
            where = "bags"
        end
        tooltip:AddDoubleLine("  " .. classHex(w.class) .. shortName(w.name) .. "|r",
            "|cffffffff" .. (w.bags + w.bank) .. "|r |cff9a9a9a(" .. where .. ")|r")
    end
    if #who > 6 then
        tooltip:AddLine("|cff9a9a9a  and " .. (#who - 6) .. " more|r")
    end
end

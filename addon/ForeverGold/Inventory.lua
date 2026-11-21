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
--              sizes = { [bag] = slots }, order = { bag, bag, ... },
--              info = { [bag] = { icon, fam, id, name, reagent } } },
--     bank = { ...the same, from the last visit to a banker },
-- }
-- c.bags / c.bank = { [itemID] = count } (c.bags is filled in Chars.lua).
-- A link is only kept for weapons and armour, whose links carry the random
-- "of the Bear" part and enchants; everything else is rebuilt from its ID.

local _, ns = ...

local INV = {}
ns.Inv = INV

local CLASS_WEAPON, CLASS_ARMOR = 2, 4
INV.KEYRING_ICON = "Interface\\Icons\\INV_Misc_Key_03"
INV.BACKPACK_ICON = "Interface\\Buttons\\Button-Backpack-Up"
INV.BANK_ICON = "Interface\\Icons\\INV_SideTab_Bank_c60" -- the game's own bank page icon
-- bank tab ID -> { name, icon, slot }, from the last time the bank was open.
-- On WoW Forever tab 1 is the bank itself and tabs 2+ are bank bag slots,
-- each holding the bag you put in it.
INV.tabs = {}

-- The keyring's container ID, on a client that shows one (WoW Forever does), or nil.
function INV.KeyringID()
    local id = (Enum and Enum.BagIndex and Enum.BagIndex.Keyring) or KEYRING_CONTAINER
    if not id or not GetKeyRingSize then
        return nil
    end
    if C_ActionBar and C_ActionBar.ShouldShowKeyring and not ns.try(C_ActionBar.ShouldShowKeyring) then
        return nil
    end
    return id
end

-- How many slots a container has (the keyring has its own size call).
function INV.NumSlots(bag)
    if bag ~= nil and bag == INV.KeyringID() then
        return tonumber(ns.try(GetKeyRingSize)) or 0
    end
    return tonumber(ns.try(C_Container.GetContainerNumSlots, bag)) or 0
end

-- Your bags: the backpack, the bags in your bag slots, and the keyring.
function INV.BagIDs()
    local ids = {}
    local last = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0)
    for bag = 0, last do
        ids[#ids + 1] = bag
    end
    local keys = INV.KeyringID()
    if keys then
        ids[#ids + 1] = keys
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
            for i, t in ipairs(tabs) do
                if type(t) == "table" and t.ID then
                    ids[#ids + 1] = t.ID
                    INV.tabs[t.ID] = { name = t.name, icon = t.icon, slot = i }
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

-- The bag in bank bag slot i (2 and up), as the game's item info, or nil.
function INV.BankBagItem(i)
    local where = Enum and Enum.BagIndex and Enum.BagIndex.Characterbanktab
    if not where or not i or i < 2 then
        return nil
    end
    local info = ns.try(C_Container.GetContainerItemInfo, where, i)
    if type(info) == "table" and info.itemID then
        return info
    end
    return nil
end

-- Your bank's bag slots while it's open: { max, bought, cost, afford, canBuy },
-- or nil on a bank without them.
function INV.BankSlots()
    if not (C_Bank and C_Bank.FetchMaxNumBankTabs and Enum and Enum.BankType) then
        return nil
    end
    local kind = Enum.BankType.Character
    local max = tonumber(ns.try(C_Bank.FetchMaxNumBankTabs, kind)) or 0
    if max < 2 then
        return nil
    end
    local bought = tonumber(C_Bank.FetchNumPurchasedBankTabs and ns.try(C_Bank.FetchNumPurchasedBankTabs, kind)) or 0
    local out = { max = max, bought = math.min(bought, max) }
    local nextTab = C_Bank.FetchNextPurchasableBankTabData and ns.try(C_Bank.FetchNextPurchasableBankTabData, kind)
    if type(nextTab) == "table" then
        out.cost, out.afford = tonumber(nextTab.tabCost), nextTab.canAfford ~= false
    end
    local can = bought < max
    if can and C_Bank.CanPurchaseBankTab then
        can = ns.try(C_Bank.CanPurchaseBankTab, kind) and true or false
    end
    out.canBuy = can and out.cost ~= nil
    return out
end

-- One of your bags right now: { icon, fam (the game's bag family bits:
-- quiver, herb bag, ...), id (the bag item), name, reagent } and its free slots.
function INV.BagInfo(bag, bank)
    local info = {}
    local free, fam = ns.try(C_Container.GetContainerNumFreeSlots, bag)
    info.fam = tonumber(fam) or 0
    if bank then
        local t = INV.tabs[bag]
        local slot = t and t.slot
        if slot == 1 and INV.BankSlots() then
            info.icon, info.name, info.main = INV.BANK_ICON, "Bank", true
        elseif slot and slot > 1 and INV.BankSlots() then
            -- a bank bag slot: what's in it is the bag you put there
            info.slot = slot
            local it = INV.BankBagItem(slot)
            if it then
                info.id, info.icon = it.itemID, it.iconFileID
                info.name = type(it.hyperlink) == "string" and it.hyperlink:match("%[(.-)%]") or nil
            end
        else
            info.icon, info.name = t and t.icon or nil, t and t.name or nil
        end
    elseif bag == 0 then
        info.icon, info.name = INV.BACKPACK_ICON, "Backpack"
    elseif bag == INV.KeyringID() then
        info.icon, info.name, info.fam, info.keyring = INV.KEYRING_ICON, "Keyring", 256, true
    else
        local slot = C_Container.ContainerIDToInventoryID and ns.try(C_Container.ContainerIDToInventoryID, bag)
        if slot then
            info.id = ns.try(GetInventoryItemID, "player", slot)
            info.icon = ns.try(GetInventoryItemTexture, "player", slot)
        end
        info.name = C_Container.GetBagName and ns.try(C_Container.GetBagName, bag) or nil
        info.reagent = (NUM_REAGENTBAG_SLOTS or 0) > 0 and bag > (NUM_BAG_SLOTS or 4) or nil
    end
    return info, tonumber(free) or 0
end

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
local function read(ids, bank)
    local out, counts = { size = 0, slots = {}, sizes = {}, order = {}, info = {}, at = time() }, {}
    if not C_Container or not C_Container.GetContainerNumSlots then
        return out, counts
    end
    for _, bag in ipairs(ids) do
        local n = INV.NumSlots(bag)
        out.size = out.size + n
        -- a bank bag slot you've bought but left empty is kept too, for the bag bar
        if n > 0 or (bank and INV.tabs[bag] and (INV.tabs[bag].slot or 0) > 1) then
            out.sizes[bag] = n
            out.order[#out.order + 1] = bag
            out.info[bag] = (INV.BagInfo(bag, bank))
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
    local snap, counts = read(INV.BankIDs(), true)
    if snap.size == 0 then
        return -- the bank isn't really readable (yet): keep the last copy
    end
    local slots = INV.BankSlots()
    if slots then
        snap.bankSlots = { max = slots.max, bought = slots.bought, cost = slots.cost }
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
-- a bank bag slot bought, or a bag put in or taken out
for _, ev in ipairs({ "BANK_TABS_CHANGED", "BAG_CONTAINER_UPDATE" }) do
    ns.On(ev, function()
        if INV.bankOpen then
            INV.BankIDs()
            ns.Later("inv-bank", 0.3, INV.SaveBank)
            ns.Fire("INVENTORY")
        end
    end)
end
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
            out[#out + 1] = { key = key, name = c.name, class = c.class, race = c.race, sex = c.sex, money = c.money, realmKey = c.realmKey,
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
    if where == "guild" then
        return INV.GuildSnapshot(c and c.guild)
    end
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
                out[#out + 1] = { name = c.name, bags = bags, bank = bank, key = key, class = c.class, race = c.race, sex = c.sex }
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

-- A character's face: the game's race icon ("raceicon-orc-male"), or nil
-- for a character saved before race was kept (or a client without them).
local RACE_ATLAS = { Scourge = "undead", HighmountainTauren = "highmountain", LightforgedDraenei = "lightforged",
    VoidElf = "voidelf", ZandalariTroll = "zandalari", KulTiran = "kultiran", DarkIronDwarf = "darkirondwarf",
    MagharOrc = "magharorc", Nightborne = "nightborne", Mechagnome = "mechagnome", Vulpera = "vulpera" }
function INV.FaceAtlas(c)
    if type(c) ~= "table" or type(c.race) ~= "string" then
        return nil
    end
    local name = "raceicon-" .. (RACE_ATLAS[c.race] or c.race:lower()) .. "-" .. (c.sex == 3 and "female" or "male")
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) then
        return name
    end
    return nil
end

-- The face as text for a tooltip line ("" when there isn't one).
function INV.FaceText(c, size)
    local atlas = INV.FaceAtlas(c)
    size = size or 14
    if atlas then
        return "|A:" .. atlas .. ":" .. size .. ":" .. size .. "|a "
    end
    return ""
end

-- Puts a character's face on a texture: race icon, else class icon. Returns true if it set one.
function INV.SetFace(tex, c)
    local atlas = INV.FaceAtlas(c)
    if atlas then
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetAtlas(atlas)
        return true
    end
    local coords = type(c) == "table" and c.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.class]
    if coords then
        tex:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        return true
    end
    return false
end

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
        tooltip:AddDoubleLine("  " .. INV.FaceText(w) .. classHex(w.class) .. shortName(w.name) .. "|r",
            "|cffffffff" .. (w.bags + w.bank) .. "|r |cff9a9a9a(" .. where .. ")|r")
    end
    if #who > 6 then
        tooltip:AddLine("|cff9a9a9a  and " .. (#who - 6) .. " more|r")
    end
end

----------------------------------------------------------------------
-- Guild bank: saved each visit, shown in the bank window
--
-- ns.db.guilds[guildKey] = { name, at, tabs = { [tab] = { name, icon,
--     slots = { { slot, itemID, count, quality, link or false }, ... } } } }
-- Only the tabs you can view are read. The game sends a tab's items when
-- asked (QueryGuildBankTab), so each tab is kept from the last time it
-- arrived with anything in it, or was the tab you had open.
----------------------------------------------------------------------

local GUILD_SLOTS = 98
local GUILD_TAB_BAG = 100 -- tab t shows as "bag" 100 + t

-- Your guild's key ("Guild Name-realm-faction"), or nil.
function INV.GuildKey()
    local name = IsInGuild and ns.try(IsInGuild) and ns.try(GetGuildInfo, "player")
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return name .. "-" .. tostring(ns.realmKey)
end

INV.guildOpen = false

function INV.SaveGuild()
    local key = INV.GuildKey()
    if not (key and INV.guildOpen and GetNumGuildBankTabs and GetGuildBankItemInfo) then
        return
    end
    ns.db.guilds = type(ns.db.guilds) == "table" and ns.db.guilds or {}
    local g = ns.db.guilds[key] or { tabs = {} }
    g.name = ns.try(GetGuildInfo, "player") or g.name
    local current = GetCurrentGuildBankTab and ns.try(GetCurrentGuildBankTab)
    local n = tonumber(ns.try(GetNumGuildBankTabs)) or 0
    for tab = 1, n do
        local name, icon, viewable = ns.try(GetGuildBankTabInfo, tab)
        if viewable then
            local slots = {}
            for slot = 1, GUILD_SLOTS do
                local _, count, _, _, quality = ns.try(GetGuildBankItemInfo, tab, slot)
                local link = GetGuildBankItemLink and ns.try(GetGuildBankItemLink, tab, slot)
                local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
                if id then
                    slots[#slots + 1] = { slot, id, count or 1, quality, keepLink(id, link) or false }
                end
            end
            local old = g.tabs[tab]
            if #slots > 0 or tab == current or not old then
                g.tabs[tab] = { name = name, icon = icon, slots = slots }
            else
                old.name, old.icon = name, icon
            end
        end
    end
    for tab = n + 1, #g.tabs do
        g.tabs[tab] = nil
    end
    g.at = time()
    ns.db.guilds[key] = g
    ns.Char().guild = key
    ns.Fire("INVENTORY")
end

-- A guild's bank in the same shape as a saved bank (tabs as bags), or nil.
function INV.GuildSnapshot(key)
    local g = key and type(ns.db.guilds) == "table" and ns.db.guilds[key]
    if type(g) ~= "table" or type(g.tabs) ~= "table" then
        return nil
    end
    local snap = { size = 0, slots = {}, sizes = {}, order = {}, info = {}, at = g.at, guild = g.name }
    for tab = 1, #g.tabs do
        local t = g.tabs[tab]
        if type(t) == "table" then
            local bag = GUILD_TAB_BAG + tab
            snap.order[#snap.order + 1] = bag
            snap.sizes[bag] = GUILD_SLOTS
            snap.size = snap.size + GUILD_SLOTS
            snap.info[bag] = { icon = t.icon, name = t.name or ("Tab " .. tab), tab = tab }
            for _, e in ipairs(t.slots or {}) do
                snap.slots[#snap.slots + 1] = { bag, e[1], e[2], e[3], e[4], e[5] or false, false }
            end
        end
    end
    return snap
end

ns.On("GUILDBANKFRAME_OPENED", function()
    INV.guildOpen = true
    -- ask for every tab you can see, so they're all saved
    if QueryGuildBankTab and GetNumGuildBankTabs then
        for tab = 1, tonumber(ns.try(GetNumGuildBankTabs)) or 0 do
            local _, _, viewable = ns.try(GetGuildBankTabInfo, tab)
            if viewable then
                ns.try(QueryGuildBankTab, tab)
            end
        end
    end
    ns.Later("inv-guild", 0.5, INV.SaveGuild)
end)
ns.On("GUILDBANKBAGSLOTS_CHANGED", function()
    if INV.guildOpen then
        ns.Later("inv-guild", 0.5, INV.SaveGuild)
    end
end)
ns.On("GUILDBANKFRAME_CLOSED", function()
    if INV.guildOpen then
        INV.SaveGuild()
    end
    INV.guildOpen = false
end)
ns.Listen("READY", function()
    local key = INV.GuildKey()
    if key or (IsInGuild and not ns.try(IsInGuild)) then
        ns.Char().guild = key
    end
end)

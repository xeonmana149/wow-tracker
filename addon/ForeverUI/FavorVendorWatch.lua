-- Passive, local-only checks of the three disputed Favor recipes.
-- This reads the merchant window; it never buys or modifies anything.
local _, ns = ...
local watched = {
    [248200] = { name = "Fizzlefuse", items = { [264221] = "Gnomish Army Knife", [264222] = "Loot-A-Rang" } },
    [256733] = { name = "Fritz Fizzle", items = { [264221] = "Gnomish Army Knife", [264222] = "Loot-A-Rang" } },
    [248196] = { name = "Apothecary Durelle", items = { [250996] = "Disorienting Smog Potion" } },
    [256729] = { name = "Nina Surefire", items = { [250996] = "Disorienting Smog Potion" } },
}
local current, serial = nil, 0

local function realm()
    local ok, name = pcall(function() return GetRealmName and GetRealmName() end)
    return ok and type(name) == "string" and name ~= "" and name or "Unknown realm"
end

local function vendorID()
    if type(UnitGUID) ~= "function" then return nil end
    for _, unit in ipairs({ "npc", "target" }) do
        local ok, guid = pcall(UnitGUID, unit)
        if ok and type(guid) == "string" and not ns.Secret(guid) then
            local kind, id = guid:match("^([^-]+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-")
            if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
        end
    end
end

local function stamp()
    local now = type(time) == "function" and time() or nil
    return type(now) == "number" and now or nil
end

local function itemID(index)
    if type(GetMerchantItemID) == "function" then
        local ok, id = pcall(GetMerchantItemID, index)
        if ok and type(id) == "number" and not ns.Secret(id) and id > 0 then return id end
    end
    if type(GetMerchantItemLink) == "function" then
        local ok, link = pcall(GetMerchantItemLink, index)
        if ok and type(link) == "string" and not ns.Secret(link) then return tonumber(link:match("item:(%d+)")) end
    end
end

-- Extended costs can contain several currencies or items. Only record the
-- amount when the component is explicitly identified as Merchant's Favor.
local function favorCost(index)
    if type(GetMerchantItemCostInfo) ~= "function" or type(GetMerchantItemCostItem) ~= "function" then return end
    local ok, count = pcall(GetMerchantItemCostInfo, index)
    if not ok or type(count) ~= "number" or ns.Secret(count) or count < 1 then return end
    local localized
    if C_CurrencyInfo and type(C_CurrencyInfo.GetCurrencyInfo) == "function" then
        local success, info = pcall(C_CurrencyInfo.GetCurrencyInfo, 3402)
        if success and type(info) == "table" and type(info.name) == "string" and not ns.Secret(info.name) then localized = info.name end
    end
    for i = 1, count do
        local success, _, amount, link, name = pcall(GetMerchantItemCostItem, index, i)
        if success and type(amount) == "number" and not ns.Secret(amount) and amount > 0 then
            local matched = false
            if type(link) == "string" and not ns.Secret(link) then matched = tonumber(link:match("currency:(%d+)")) == 3402 end
            if type(name) == "string" and not ns.Secret(name) then
                local plain = name:lower():gsub("’", "'"):gsub("‘", "'")
                matched = matched or plain == "merchant's favor" or plain == "merchant's favour" or (localized and name == localized)
            end
            if not matched and C_TooltipInfo and type(C_TooltipInfo.GetMerchantCostItem) == "function" then
                local tooltipOK, data = pcall(C_TooltipInfo.GetMerchantCostItem, index, i)
                if tooltipOK and type(data) == "table" and not ns.Secret(data.id) and not ns.Secret(data.type) then
                    local currencyType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Currency or 5
                    matched = data.type == currencyType and data.id == 3402
                end
            end
            if matched then
                local extra = count > 1
                if C_MerchantFrame and type(C_MerchantFrame.GetItemInfo) == "function" then
                    local infoOK, info = pcall(C_MerchantFrame.GetItemInfo, index)
                    if infoOK and type(info) == "table" and type(info.price) == "number" and not ns.Secret(info.price) and info.price > 0 then extra = true end
                end
                return amount, extra
            end
        end
    end
end

local function scan(session)
    if current ~= session or not ns.db or type(GetMerchantNumItems) ~= "function" then return end
    local ok, count = pcall(GetMerchantNumItems)
    if not ok or type(count) ~= "number" or ns.Secret(count) or count <= 0 then return end
    local found, complete = {}, true
    for i = 1, count do
        local id = itemID(i)
        if not id then complete = false else found[id] = i end
    end
    local vendor = watched[session.id]
    local changes, messages = false, {}
    ns.db.favorVendorChecks = ns.db.favorVendorChecks or {}
    local all = ns.db.favorVendorChecks
    all[session.realm] = all[session.realm] or {}
    local record = all[session.realm][session.id] or { items = {} }
    record.items = record.items or {}
    record.costs = record.costs or {}
    for id, name in pairs(vendor.items) do
        -- A partially loaded list may prove an item is present, but it cannot
        -- support an absent observation.
        if found[id] or complete then
            local status = found[id] and "shown" or "not_shown"
            if record.items[id] ~= status then changes = true end
            record.items[id] = status
            local amount, extra
            if found[id] then amount, extra = favorCost(found[id]) end
            if amount then
                local previous = record.costs[id]
                if not previous or previous.amount ~= amount or previous.extra ~= extra then changes = true end
                record.costs[id] = { amount = amount, extra = extra, checkedAt = stamp() }
            end
            local price = amount and (" (" .. amount .. " Favor" .. (extra and ", plus other costs" or "") .. ")") or (found[id] and " (Favor cost unavailable)" or "")
            messages[#messages + 1] = name .. (found[id] and ": shown" or ": not shown") .. price
        end
    end
    if #messages == 0 then return end
    record.checkedAt, record.complete = stamp(), complete
    all[session.realm][session.id] = record
    table.sort(messages)
    if changes and ns.Encyclopedia then ns.Encyclopedia.dataSignature = nil end
    local summary = table.concat(messages, "; ")
    if session.lastMessage ~= summary then
        session.lastMessage = summary
        ns.Print(vendor.name .. " check: " .. summary .. ". Not shown can depend on filters or reputation.")
    end
end

function ns.FavorVendorObservation(item, onlyVendor)
    local checks = ns.db and ns.db.favorVendorChecks and ns.db.favorVendorChecks[realm()]
    if type(checks) ~= "table" then return nil, false end
    local lines, found = {}, false
    for id, vendor in pairs(watched) do
        local record = checks[id]
        local status = type(record) == "table" and type(record.items) == "table" and record.items[item]
        if status and (not onlyVendor or onlyVendor == id) then
            local dateText = record.checkedAt and type(date) == "function" and date("%Y-%m-%d", record.checkedAt) or "date unknown"
            local price = type(record.costs) == "table" and record.costs[item]
            local costText = ""
            if status == "shown" and type(price) == "table" and type(price.amount) == "number" then
                local costDate = price.checkedAt and type(date) == "function" and date("%Y-%m-%d", price.checkedAt) or "date unknown"
                costText = "; " .. price.amount .. " Favor" .. (price.extra and " plus other costs" or "") .. " observed " .. costDate
            end
            lines[#lines + 1] = vendor.name .. ": " .. (status == "shown" and "shown" or "not shown") .. " (" .. dateText .. costText .. ")"
            if status == "shown" then found = true end
        end
    end
    if #lines == 0 then return nil, false end
    table.sort(lines)
    return "Your vendor checks: " .. table.concat(lines, "; ") .. ". Not shown may reflect filters or reputation.", found
end

ns.On("MERCHANT_SHOW", function()
    serial = serial + 1
    local id = vendorID()
    current = watched[id] and { id = id, realm = realm(), serial = serial } or nil
    if not current then return end
    local session = current
    -- Allow merchant entries to load; update events provide further retries.
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function() scan(session) end)
        C_Timer.After(3, function() scan(session) end)
    else scan(session) end
end)
ns.On("MERCHANT_UPDATE", function() if current then scan(current) end end)
ns.On("MERCHANT_CLOSED", function() current = nil end)

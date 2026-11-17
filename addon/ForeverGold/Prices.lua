-- Forever Gold - the price book
--
-- prices[itemID] = {
--     p = lowest price seen in the last scan (copper, for ONE item),
--     q = how many were listed in that scan (0 = none for sale right now),
--     t = when that was,
--     b = true  -> that price is a real buyout,
--         false -> checked, and it is bid-only (nobody can simply buy it),
--         nil   -> not known yet (a slow scan can't tell for gear),
--     h = { [dayNumber] = lowest price that day },   -- about 3 weeks of history
-- }
-- Plus what vendors charge, learned whenever you open a vendor window.

local _, ns = ...
local floor, max = math.floor, math.max

local HISTORY_DAYS = 21

local function today()
    return floor(time() / 86400)
end
ns.Today = today

----------------------------------------------------------------------
-- Reading prices
----------------------------------------------------------------------

-- Lowest price currently on the auction house, or nil if none are listed.
function ns.AHPrice(id)
    local r = ns.R().prices[id]
    if r and r.p and (r.q or 0) > 0 then
        return r.p, r.q, r.t
    end
    return nil
end

-- Can the current lowest price actually be bought outright? Stackable goods
-- can never be bid on, so for those the answer is always yes.
function ns.IsBuyout(id)
    local r = ns.R().prices[id]
    if not r then
        return false
    end
    if r.b ~= nil then
        return r.b
    end
    local it = ns.db.items[id]
    return (it and (it.st or 1) > 1) or false
end

-- Last price we ever saw, even if nobody is selling it right now.
function ns.LastPrice(id)
    local r = ns.R().prices[id]
    if r and r.p then
        return r.p, r.t
    end
    return nil
end

-- The freshest price any of your OTHER characters saw (another realm or
-- the other faction), for tooltips. Returns price, listed, when, who.
function ns.SharedPrice(id)
    local best, bestT, bestQ, bestWho
    for key, R in pairs(ns.db.realms) do
        if key ~= ns.realmKey and type(R) == "table" and type(R.prices) == "table" then
            local r = R.prices[id]
            if r and r.p and r.t and (not bestT or r.t > bestT) then
                local faction = tostring(key):match("%-(%a+)$")
                best, bestT, bestQ = r.p, r.t, r.q or 0
                bestWho = (R.lastScanBy or "another character") .. (faction and (" (" .. faction .. ")") or "")
            end
        end
    end
    return best, bestQ, bestT, bestWho
end

-- The middle of the daily lows we have on record. Returns price, daysOfData.
function ns.UsualPrice(id)
    local r = ns.R().prices[id]
    if not r or not r.h then
        return nil, 0
    end
    local vals = {}
    for _, p in pairs(r.h) do
        vals[#vals + 1] = p
    end
    if #vals == 0 then
        return nil, 0
    end
    table.sort(vals)
    local mid = floor((#vals + 1) / 2)
    local median = vals[mid]
    if #vals % 2 == 0 then
        median = (vals[mid] + vals[mid + 1]) / 2
    end
    return median, #vals
end

-- What you actually receive for one item sold at the current lowest price.
function ns.AHNet(id)
    local p = ns.AHPrice(id)
    if p then
        return p * (1 - ns.AH_CUT)
    end
    return nil
end

-- What a vendor pays you for one.
function ns.VendorSell(id)
    local it = ns.Item(id)
    if it and it.v and it.v > 0 then
        return it.v
    end
    return nil
end

-- The better of "auction it" and "vendor it". Returns value, "ah"|"vendor".
function ns.SellValue(id)
    local net = ns.AHNet(id)
    local v = ns.VendorSell(id)
    if net and (not v or net > v) then
        return net, "ah"
    end
    if v then
        return v, "vendor"
    end
    return nil
end

----------------------------------------------------------------------
-- What vendors charge
----------------------------------------------------------------------

local staticVendor
local function buildStaticVendor()
    staticVendor = {}
    for _, e in ipairs(ns.VENDOR_ITEMS or {}) do
        staticVendor[e[2]] = e
    end
end

-- Price to buy one from a vendor that never runs out. Returns price, isApprox.
function ns.VendorBuy(id)
    local v = ns.db.vendor[id]
    if v and v.p and not v.lim then
        return v.p, false
    end
    if not staticVendor then
        buildStaticVendor()
    end
    local e = staticVendor[id]
    if e then
        -- Only trust the built-in guess if this client agrees on the name.
        local it = ns.db.items[id]
        if it and it.n and it.n:lower() ~= e[1]:lower() then
            return nil
        end
        return e[3], true
    end
    return nil
end

local function merchantItem(i)
    local id = ns.try(GetMerchantItemID, i)
    if not id then
        local link = ns.try(GetMerchantItemLink, i)
        id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    end
    local price, stack, avail, extended
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = ns.try(C_MerchantFrame.GetItemInfo, i)
        if type(info) == "table" then
            price, stack, avail, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
        end
    elseif GetMerchantItemInfo then
        local ok, _, _, p, q, a, _, _, ext = pcall(GetMerchantItemInfo, i)
        if ok then
            price, stack, avail, extended = p, q, a, ext
        end
    end
    return id, price, stack, avail, extended
end

local function scanMerchant()
    local n = ns.try(GetMerchantNumItems) or 0
    if n == 0 then
        return
    end
    local npc = ns.try(UnitName, "npc")
    local zone = ns.try(GetRealZoneText)
    local finds = {}
    for i = 1, n do
        local id, price, stack, avail, extended = merchantItem(i)
        if id and price and price > 0 and not extended then
            local unit = price / max(1, stack or 1)
            local limited = (avail and avail >= 0) and true or nil
            ns.db.vendor[id] = { p = unit, lim = limited, t = time(), npc = npc, zone = zone }
            ns.Item(id)
            -- Only shout about it when it's real: it has actually been
            -- selling for that much, or this vendor's stock is limited. A
            -- high asking price on something any vendor sells proves nothing.
            local net, how = ns.ResaleValue(id)
            if net and (how == "sold" or limited) and net > unit * 1.25
                and net - unit >= (ns.db.opts.dealMin or 500) then
                finds[#finds + 1] = { id = id, buy = unit, net = net, how = how }
            end
        end
    end
    ns.Fire("VENDOR_UPDATED")
    if #finds > 0 then
        table.sort(finds, function(a, b) return (a.net - a.buy) > (b.net - b.buy) end)
        ns.Print("this vendor sells " .. #finds .. " thing" .. (#finds > 1 and "s" or "")
            .. " that go for more on the auction house:")
        for i = 1, math.min(3, #finds) do
            local f = finds[i]
            print("   " .. ns.ItemText(f.id) .. " - costs " .. ns.Money(f.buy) .. " here, "
                .. (f.how == "sold" and "has been selling for about " or "limited stock, listed for about ")
                .. ns.Money(f.net) .. " after the auction cut.")
        end
        if #finds > 3 then
            print("   ...and more. See the Buy tab in /gold.")
        end
    end
end

ns.On("MERCHANT_SHOW", function()
    C_Timer.After(0.5, ns.Guard("vendor", scanMerchant))
end)

----------------------------------------------------------------------
-- Writing prices (called by the scanner)
--
-- found[itemID] = { p = lowest price, q = quantity listed }
-- complete = true when the scan covered the whole auction house, which is
-- the only time it is safe to conclude "everything else is sold out".
----------------------------------------------------------------------

function ns.RecordPrices(found, complete)
    local prices = ns.R().prices
    local now, day = time(), today()
    for id, s in pairs(found) do
        local r = prices[id]
        if not r then
            r = {}
            prices[id] = r
        end
        r.p, r.q, r.t = s.p, s.q, now
        r.b = s.b
        local h = r.h
        if not h then
            h = {}
            r.h = h
        end
        if not h[day] or s.p < h[day] then
            h[day] = s.p
        end
        for d in pairs(h) do
            if d < day - HISTORY_DAYS then
                h[d] = nil
            end
        end
    end
    if complete then
        for id, r in pairs(prices) do
            if not found[id] then
                r.q = 0
            end
        end
    end
    ns.nameIndexDirty = true
end

-- How many different items have a live price, for the status line.
function ns.PriceCount()
    local n = 0
    for _, r in pairs(ns.R().prices) do
        if (r.q or 0) > 0 then
            n = n + 1
        end
    end
    return n
end

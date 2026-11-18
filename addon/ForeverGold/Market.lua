-- Forever Gold - how fast things really sell
--
-- An addon can only see what is listed right now, never what sold. Your
-- tracker website watches Blizzard's hourly auction snapshots and works out,
-- item by item, how many sell each day and what share of listings sell
-- before they run out. The WoW Forever Tracker app writes that into
-- MarketData.lua next to this file (the game reads it at login or /reload).
--
-- Without the app, or before it has run, everything here quietly returns
-- nil and the rest of the addon works exactly as before.
--
-- Blizzard's data covers every auction house, so the right one is picked by
-- comparing it with your own scan: the house whose prices match yours.

local _, ns = ...
local floor, max, min = math.floor, math.max, math.min

local parsed = {} -- [house] = { [itemID] = rate table or false }
local chosen -- house table in use, or false = checked and none matches
local chosenFor -- realmKey the choice was made for

local function market()
    local m = ForeverGoldMarket
    if type(m) == "table" and type(m.houses) == "table" then
        return m
    end
    return nil
end

local function decode(s)
    if type(s) ~= "string" then
        return nil
    end
    local a, b, c, d, e, f = s:match("^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)")
    if not a then
        return nil
    end
    return {
        perDay = tonumber(a) or 0, -- how many sold per day
        through = tonumber(b) or -1, -- % of listings that sold (-1 = not enough data)
        avg = tonumber(c) or 0, -- average price it actually sold for, each
        min = tonumber(d) or 0, -- cheapest buyout in Blizzard's latest snapshot
        listed = tonumber(e) or 0, -- how many listed in that snapshot
        posts = tonumber(f) or 0, -- new listings per day
    }
end

-- Which house's prices look like the ones you scanned yourself?
local function pickHouse()
    local m = market()
    if not m then
        return false
    end
    local prices = ns.R().prices
    local best, bestScore = false, 0
    for houseID, h in pairs(m.houses) do
        local overlap, exact = 0, 0
        if type(h.items) == "table" then
            for id, r in pairs(prices) do
                if r.p and (r.q or 0) > 0 then
                    local raw = h.items[id]
                    if raw then
                        local mn = tonumber(raw:match("^[^,]*,[^,]*,[^,]*,([^,]*)")) or 0
                        if mn > 0 then
                            overlap = overlap + 1
                            if math.abs(mn - r.p) <= max(1, r.p * 0.02) then
                                exact = exact + 1
                            end
                        end
                    end
                end
            end
        end
        local score = overlap >= 10 and exact / overlap or 0
        if score > bestScore then
            best, bestScore = houseID, score
        end
    end
    if best and bestScore >= 0.35 then
        local R = ns.R()
        R.marketHouse = best
        return best
    end
    return false
end

local function current()
    if chosen == nil or chosenFor ~= ns.realmKey then
        chosenFor = ns.realmKey
        local id = pickHouse()
        if not id then
            -- No scan to compare with yet: fall back on the last house this
            -- realm matched, if the data still has it.
            local m, remembered = market(), ns.R().marketHouse
            if m and remembered and m.houses[remembered] then
                id = remembered
            end
        end
        chosen = id and market().houses[id] and { id = id, data = market().houses[id] } or false
    end
    return chosen or nil
end

ns.Listen("PRICES_UPDATED", function()
    chosen = nil
end)
ns.Listen("READY", function()
    chosen = nil
end)

-- Sale numbers for one item, or nil when there's no data for it.
function ns.SaleRate(id)
    local h = current()
    if not h or not id then
        return nil
    end
    local cache = parsed[h.id]
    if not cache then
        cache = {}
        parsed[h.id] = cache
    end
    local r = cache[id]
    if r == nil then
        r = decode(h.data.items and h.data.items[id]) or false
        cache[id] = r
    end
    return r or nil
end

-- { house =, hours = how much data, t = snapshot time, made = when the app wrote it }
-- or nil plus a reason: "none" (no data file), "nomatch" (data doesn't match your scan)
function ns.MarketInfo()
    local m = market()
    if not m then
        return nil, "none"
    end
    local h = current()
    if not h then
        return nil, "nomatch"
    end
    return { house = h.id, hours = tonumber(h.data.hours) or 0, t = tonumber(h.data.t) or 0, made = tonumber(m.made) or 0 }
end

-- Enough hours of data to say anything at all?
local MIN_HOURS = 6

local SPEEDS = {
    fast = { text = "sells fast", color = "|cff40e060", weight = 1.0 },
    steady = { text = "sells steadily", color = "|cffffffff", weight = 0.75 },
    slow = { text = "sells slowly", color = "|cffffa040", weight = 0.35 },
    rarely = { text = "rarely sells", color = "|cffff7070", weight = 0.1 },
}
ns.SPEEDS = SPEEDS

-- "fast" | "steady" | "slow" | "rarely" | nil (not enough data)
function ns.SaleSpeed(id)
    local r = ns.SaleRate(id)
    local info = ns.MarketInfo()
    if not r or not info or info.hours < MIN_HOURS then
        return nil, r
    end
    -- Fast sellers show up within hours. Calling something slow, or saying
    -- it hardly ever sells, needs days of watching first - plenty of good
    -- items simply don't sell in any given afternoon.
    local t, d, hours = r.through, r.perDay, info.hours
    if t >= 60 or d >= 25 then
        return "fast", r
    end
    if hours < 24 then
        return nil, r
    end
    if t >= 35 or d >= 5 then
        return "steady", r
    elseif t >= 15 or d >= 0.5 then
        return "slow", r
    end
    if hours >= 48 and (t >= 0 or (d == 0 and r.listed > 0 and hours >= 72)) then
        return "rarely", r
    end
    return nil, r
end

-- How much to trust a profit when ranking: something that never sells is
-- worth less than its price tag. Unknown speed counts as middling.
-- When there's enough data this is the real share of listings that sell
-- (a big seller counts as at least 0.9), so a 40% margin that sells 1 in 10
-- listings ranks below a 15% margin that sells 8 in 10.
function ns.SpeedWeight(id)
    local s, r = ns.SaleSpeed(id)
    local info = ns.MarketInfo()
    if r and info and info.hours >= MIN_HOURS and (r.through or -1) >= 0 then
        local w = r.through / 100
        if (r.perDay or 0) >= 25 then
            w = max(w, 0.9)
        end
        return max(0.05, min(1, w))
    end
    return s and SPEEDS[s].weight or 0.6
end

local function perDayText(d)
    if d >= 10 then
        return tostring(floor(d + 0.5))
    elseif d >= 1 then
        return tostring(floor(d * 10 + 0.5) / 10)
    elseif d > 0 then
        return "under 1"
    end
    return "none"
end

-- One plain-English line, e.g. "sells fast - about 40 a day, 70% of listings sell".
-- short = true: just "sells fast". short = "mid": "sells fast (~40/day, 70% sell)".
function ns.SaleText(id, short)
    local s, r = ns.SaleSpeed(id)
    if not s then
        return nil
    end
    local sp = SPEEDS[s]
    local text = sp.color .. sp.text .. "|r"
    if short == "mid" then
        local bits = {}
        if r.perDay > 0 then
            bits[#bits + 1] = "~" .. perDayText(r.perDay) .. "/day"
        end
        if r.through >= 0 then
            bits[#bits + 1] = r.through .. "% sell"
        end
        return text .. (#bits > 0 and (" |cff9a9a9a(" .. table.concat(bits, ", ") .. ")|r") or "")
    elseif short then
        return text
    end
    local bits = {}
    if r.perDay > 0 then
        bits[#bits + 1] = "about " .. perDayText(r.perDay) .. " a day"
    end
    if r.through >= 0 then
        bits[#bits + 1] = r.through .. "% of listings sell"
    end
    if #bits > 0 then
        text = text .. " - " .. table.concat(bits, ", ")
    end
    return text
end

-- Is it worth putting up for sale at all? A short coloured verdict from the
-- sale data, or nil while there isn't enough of it.
local VERDICT = {
    fast = "|cff40e060worth listing|r",
    steady = "|cff40e060worth listing|r",
    slow = "|cffffa040list one or two|r",
    rarely = "|cffff7070hardly sells|r",
}
function ns.SaleVerdict(id)
    local s = ns.SaleSpeed(id)
    return s and VERDICT[s] or nil, s
end

-- What one realistically brings in at auction, after the 5% cut.
-- Returns net, how:
--   "sold"   - from what it has actually been selling for (sale-rate data)
--   "listed" - only the current asking price is known (no sale data yet)
--   nil, "nosale" - it's on the auction house but practically never sells
function ns.ResaleValue(id)
    local s, r = ns.SaleSpeed(id)
    local p = ns.AHPrice(id)
    if s and r then
        if r.avg > 0 and s ~= "rarely" then
            -- If someone is already listing it cheaper than it has been
            -- selling for, that's the price you'd have to match.
            local each = (p and p < r.avg) and p or r.avg
            return each * (1 - ns.AH_CUT), "sold"
        end
        return nil, "nosale"
    end
    if p then
        return p * (1 - ns.AH_CUT), "listed"
    end
    return nil
end

-- For the status line on the Tips tab and /gold debug.
function ns.MarketStatus()
    local info, why = ns.MarketInfo()
    if not info then
        if why == "none" then
            return "No sale-rate data yet. It comes from the WoW Forever Tracker app (needs it running, then /reload)."
        end
        if not ns.R().lastScan then
            return "Sale-rate data is here, but I need one auction house scan to know which auction house is yours."
        end
        return "Sale-rate data is here, but none of it matches your auction house's prices."
    end
    local days = info.hours / 24
    local span = days >= 2 and (floor(days + 0.5) .. " days") or (floor(info.hours + 0.5) .. " hours")
    local text = "Sale rates from " .. span .. " of Blizzard's auction data (auction house " .. info.house
        .. "), updated " .. ns.Ago(info.made) .. "."
    if info.hours < MIN_HOURS then
        text = text .. " Still collecting - speeds show after " .. MIN_HOURS .. " hours."
    end
    return text
end

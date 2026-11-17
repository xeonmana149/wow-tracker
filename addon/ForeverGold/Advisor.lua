-- Forever Gold - the advice engine
--
-- Turns the price book + your characters into answers:
--   CraftList()    what each recipe you know costs to make and earns
--   BagAdvice()    what in your bags should go to the auction house / a vendor
--   VendorFlips()  auction items cheaper than a vendor pays (risk-free)
--   VendorDeals()  vendor items that sell for more on the auction house
--   Bargains()     items far below their usual price
--   FarmList()     gathering and grinding spots, ranked by today's prices
--
-- Every list is cached until something it depends on changes.

local _, ns = ...
local floor, max, min = math.floor, math.max, math.min

local CUT = ns.AH_CUT

----------------------------------------------------------------------
-- Cache: one generation counter, bumped whenever inputs change
----------------------------------------------------------------------

local gen = 0
local cache = {}

local function bump()
    gen = gen + 1
end
for _, msg in ipairs({ "PRICES_UPDATED", "BAGS_UPDATED", "RECIPES_UPDATED", "ITEMS_UPDATED", "VENDOR_UPDATED",
    "PLAYER_CHANGED", "READY" }) do
    ns.Listen(msg, bump)
end

local function cached(key, build)
    local c = cache[key]
    if c and c.gen == gen then
        return c.value
    end
    local value = build()
    cache[key] = { gen = gen, value = value }
    return value
end

----------------------------------------------------------------------
-- Recipes across all your characters
----------------------------------------------------------------------

local function recipeBook()
    return cached("recipes", function()
        local list, byOut, seen = {}, {}, {}
        for key, c in pairs(ns.db.chars) do
            if not c.realmKey or c.realmKey == ns.realmKey then
                for prof, recs in pairs(c.recipes or {}) do
                    for rid, r in pairs(recs) do
                        local e = seen[rid]
                        if not e then
                            e = { id = rid, prof = prof, name = r.n, out = r.o, yield = r.y or 1,
                                reagents = r.r or {}, diff = r.d, chars = {} }
                            seen[rid] = e
                            list[#list + 1] = e
                            if r.o and not byOut[r.o] then
                                byOut[r.o] = e
                            end
                        end
                        e.chars[#e.chars + 1] = c.name or "another character"
                        if key == ns.charKey then
                            e.mine = true
                        end
                    end
                end
            end
        end
        return { list = list, byOut = byOut }
    end)
end

function ns.RecipeFor(itemID)
    return recipeBook().byOut[itemID]
end

-- Cheapest way to get one of an item right now.
-- Returns cost, source ("vendor" | "ah" | "craft" | "old"), isApproximate.
local craftCost

local function unitCost(id, depth, visiting)
    local best, src, approx
    local v, vApprox = ns.VendorBuy(id)
    if v then
        best, src, approx = v, "vendor", vApprox
    end
    local a = ns.AHPrice(id)
    if a and (not best or a < best) then
        best, src, approx = a, "ah", false
    end
    if depth < 2 and not visiting[id] then
        local rec = recipeBook().byOut[id]
        if rec then
            visiting[id] = true
            local c, _, cApprox = craftCost(rec, depth + 1, visiting)
            visiting[id] = nil
            if c and (not best or c < best) then
                best, src, approx = c, "craft", cApprox
            end
        end
    end
    if not best then
        local last = ns.LastPrice(id)
        if last then
            best, src, approx = last, "old", true
        end
    end
    return best, src, approx
end

-- Cost of the materials for ONE of what the recipe makes.
-- Returns cost, missingItemID, isApproximate, parts.
craftCost = function(rec, depth, visiting)
    local total, approxAny, parts = 0, false, {}
    for _, r in ipairs(rec.reagents) do
        local id, qty = r[1], r[2]
        local c, src, approx = unitCost(id, depth, visiting)
        if not c then
            return nil, id
        end
        total = total + c * qty
        approxAny = approxAny or approx
        parts[#parts + 1] = { id = id, qty = qty, each = c, src = src }
    end
    return total / max(1, rec.yield), nil, approxAny, parts
end

-- How many of this recipe the current character can make from their bags.
-- Vendor-bought supplies don't count as a limit. nil = no limit known.
local function canMake(rec)
    local bags = ns.Char().bags
    local limit
    for _, r in ipairs(rec.reagents) do
        local id, qty = r[1], r[2]
        if not ns.VendorBuy(id) then
            local n = floor((bags[id] or 0) / qty)
            if not limit or n < limit then
                limit = n
            end
        end
    end
    return limit and floor(limit * rec.yield) or nil
end

-- Is this the kind of thing people buy all the time, or once in a while?
-- Real sale rates (Market.lua) when there are any: "fast" | "steady" |
-- "slow" | "rarely". Otherwise a guess from what kind of item it is.
function ns.DemandNote(id)
    local speed = ns.SaleSpeed and ns.SaleSpeed(id)
    if speed then
        return speed, true
    end
    local it = ns.Item(id)
    local c = it and it.c
    if c == 0 or c == 7 or c == 5 or c == 1 or c == 6 then
        return "steady"
    elseif c == 2 or c == 4 then
        return "slow"
    end
    return nil
end

function ns.EvalRecipe(rec)
    local e = { rec = rec }
    local it = ns.Item(rec.out)
    e.bop = it and it.b == 1 or false
    e.cost, e.missing, e.approx, e.parts = craftCost(rec, 0, { [rec.out] = true })
    e.price, e.listed = ns.AHPrice(rec.out)
    e.last = ns.LastPrice(rec.out)
    e.vendor = it and it.v or 0
    if e.price and e.cost then
        e.net = e.price * (1 - CUT)
        e.profit = e.net - e.cost
        e.margin = e.cost > 0 and (e.profit / e.cost) or nil
    end
    if e.cost and e.vendor > 0 then
        e.vendorProfit = e.vendor - e.cost
    end
    if rec.mine then
        e.canMake = canMake(rec)
    end
    e.demand, e.measured = ns.DemandNote(rec.out)
    -- Profit you can actually expect to see: a big margin on something that
    -- never sells is worth less than a small one on something that flies.
    e.rank = e.profit and e.profit * (ns.SpeedWeight and ns.SpeedWeight(rec.out) or 1) or nil
    return e
end

-- Groups: good (profit > 0), untapped (nobody selling), bad (loses money),
-- unknown (a price is missing), bound (can't be sold at all).
function ns.CraftList()
    return cached("craft", function()
        local out = { good = {}, untapped = {}, bad = {}, unknown = {}, bound = {}, total = 0 }
        for _, rec in ipairs(recipeBook().list) do
            out.total = out.total + 1
            local e = ns.EvalRecipe(rec)
            if e.bop then
                out.bound[#out.bound + 1] = e
            elseif not e.cost then
                out.unknown[#out.unknown + 1] = e
            elseif not e.price then
                out.untapped[#out.untapped + 1] = e
            elseif e.profit > 0 then
                out.good[#out.good + 1] = e
            else
                out.bad[#out.bad + 1] = e
            end
        end
        table.sort(out.good, function(a, b)
            if a.rank ~= b.rank then
                return a.rank > b.rank
            end
            return a.profit > b.profit
        end)
        table.sort(out.bad, function(a, b) return a.profit > b.profit end)
        table.sort(out.untapped, function(a, b) return a.cost < b.cost end)
        table.sort(out.unknown, function(a, b) return (a.rec.name or "") < (b.rec.name or "") end)
        return out
    end)
end

-- Professions this character has but whose recipes haven't been read yet.
function ns.MissingRecipeProfessions()
    local c = ns.Char()
    local missing = {}
    local gathering = { Herbalism = true, Skinning = true }
    for name in pairs(c.profs) do
        local seen = c.seenProf and c.seenProf[name]
        if not gathering[name] and not seen and not (c.recipes[name] and next(c.recipes[name])) then
            missing[#missing + 1] = name
        end
    end
    table.sort(missing)
    return missing
end

----------------------------------------------------------------------
-- Bags
----------------------------------------------------------------------

-- Things you carry to use, not to sell.
local KEEP = {
    [6948] = true, -- Hearthstone
    [2901] = true, -- Mining Pick
    [5956] = true, -- Blacksmith Hammer
    [6256] = true, -- Fishing Pole
    [7005] = true, -- Skinning Knife
    [6219] = true, -- Arclight Spanner
    [4471] = true, -- Flint and Tinder
}

function ns.BagAdvice()
    return cached("bags", function()
        local c = ns.Char()
        local out = { ah = {}, vendor = {}, unlisted = {}, undercut = {}, ahTotal = 0, vendorTotal = 0 }

        -- Which of your materials feed a recipe that's currently profitable?
        local usedBy = {}
        for _, e in ipairs(ns.CraftList().good) do
            if e.rec.mine then
                for _, r in ipairs(e.rec.reagents) do
                    if not usedBy[r[1]] then
                        usedBy[r[1]] = e
                    end
                end
            end
        end

        for id, count in pairs(c.bags) do
            if not KEEP[id] then
                local it = ns.Item(id)
                local vendor = it and it.v or 0
                local row = { id = id, count = count, vendor = vendor, craft = usedBy[id] }
                if c.bound[id] then
                    -- Soulbound things can't be auctioned. Only call out the
                    -- grey junk; never suggest vendoring bound gear.
                    if it and it.q == 0 and vendor > 0 then
                        row.total = vendor * count
                        out.vendor[#out.vendor + 1] = row
                        out.vendorTotal = out.vendorTotal + row.total
                    end
                else
                    local price, listed = ns.AHPrice(id)
                    local net = price and price * (1 - CUT)
                    local speed = ns.SaleSpeed and ns.SaleSpeed(id)
                    row.speed = speed
                    if net and net > vendor * 1.15 and (net - vendor) * count >= 20 and speed ~= "rarely" then
                        row.price, row.listed, row.total = price, listed, net * count
                        out.ah[#out.ah + 1] = row
                        out.ahTotal = out.ahTotal + row.total
                    elseif vendor > 0 and it and (it.q == 0 or price) then
                        row.price = price
                        row.total = vendor * count
                        out.vendor[#out.vendor + 1] = row
                        out.vendorTotal = out.vendorTotal + row.total
                    elseif not price and it and (it.q or 0) >= 1 and (it.c == 7 or it.c == 0 or it.c == 5) then
                        row.last = ns.LastPrice(id)
                        out.unlisted[#out.unlisted + 1] = row
                    end
                end
            end
        end
        table.sort(out.ah, function(a, b) return a.total > b.total end)
        table.sort(out.vendor, function(a, b) return a.total > b.total end)
        table.sort(out.unlisted, function(a, b) return (a.last or 0) > (b.last or 0) end)

        -- Your auctions that someone has listed below.
        for _, a in ipairs(c.auctions or {}) do
            local price = ns.AHPrice(a.id)
            if price and price < a.p * 0.999 then
                out.undercut[#out.undercut + 1] = { id = a.id, count = a.q, mine = a.p, price = price }
            end
        end
        return out
    end)
end

----------------------------------------------------------------------
-- Deals
----------------------------------------------------------------------

local function dealMin()
    return ns.db.opts.dealMin or 500
end

-- Listed on the auction house for less than any vendor will pay you.
-- Only real buyouts: a low BID is not something you can just buy.
function ns.VendorFlips()
    return cached("vendorflips", function()
        local out, total = {}, 0
        local items = ns.db.items
        local least = dealMin()
        for id, r in pairs(ns.R().prices) do
            if (r.q or 0) > 0 and ns.IsBuyout(id) then
                local it = items[id]
                if it and it.v and it.v > r.p and it.v - r.p >= least then
                    out[#out + 1] = { id = id, price = r.p, vendor = it.v, profit = it.v - r.p, listed = r.q }
                    total = total + (it.v - r.p)
                end
            end
        end
        table.sort(out, function(a, b) return a.profit > b.profit end)
        out.total = total
        return out
    end)
end

-- Things you've seen at a vendor that sell for clearly more at auction.
--
-- Careful: a high LISTED price proves nothing. Someone listing a 42c vendor
-- throwing axe at 18s doesn't mean anyone buys it - anybody can walk to the
-- vendor. So a deal is only "sure" when the sale-rate data shows it really
-- sells for that much, or the vendor has limited stock (the real niche).
-- The rest are kept, marked unproven, and never advertised.
function ns.VendorDeals()
    return cached("vendordeals", function()
        local out = { sure = 0 }
        for id, v in pairs(ns.db.vendor) do
            local net, how = ns.ResaleValue(id)
            if net and v.p and net > v.p * 1.25 and net - v.p >= dealMin() then
                local price, listed = ns.AHPrice(id)
                local sure = how == "sold" or (v.lim and true or false)
                out[#out + 1] = { id = id, buy = v.p, price = net / (1 - CUT), net = net, profit = net - v.p,
                    listed = listed or 0, limited = v.lim, npc = v.npc, zone = v.zone, sure = sure, how = how }
                if sure then
                    out.sure = out.sure + 1
                end
            end
        end
        table.sort(out, function(a, b)
            if a.sure ~= b.sure then
                return a.sure
            end
            return a.profit > b.profit
        end)
        return out
    end)
end

-- Listed well below what it usually goes for. Needs a few days of scans.
function ns.Bargains()
    return cached("bargains", function()
        local out = {}
        local least = dealMin()
        for id, r in pairs(ns.R().prices) do
            if (r.q or 0) > 0 and r.h and ns.IsBuyout(id) then
                local usual, days = ns.UsualPrice(id)
                if usual and days >= 3 and r.p <= usual * 0.6 then
                    local profit = usual * (1 - CUT) - r.p
                    if profit >= least then
                        out[#out + 1] = { id = id, price = r.p, usual = usual, profit = profit, listed = r.q,
                            days = days }
                    end
                end
            end
        end
        table.sort(out, function(a, b) return a.profit > b.profit end)
        return out
    end)
end

-- Gear that LOOKS like a deal but whose price hasn't been confirmed as a
-- buyout yet. The scanner checks these one by one; until then they stay off
-- the Deals tab. Returns item IDs, most promising first.
function ns.PendingDeals()
    return cached("pendingdeals", function()
        local found = {}
        local items = ns.db.items
        local least = dealMin()
        for id, r in pairs(ns.R().prices) do
            if (r.q or 0) > 0 and r.b == nil then
                local it = items[id]
                if it and it.v and (it.st or 1) <= 1 then
                    local profit = it.v - r.p
                    local usual, days = ns.UsualPrice(id)
                    if usual and days >= 3 and r.p <= usual * 0.6 then
                        profit = max(profit, usual * (1 - CUT) - r.p)
                    end
                    if profit >= least then
                        found[#found + 1] = { id = id, profit = profit }
                    end
                end
            end
        end
        table.sort(found, function(a, b) return a.profit > b.profit end)
        local ids = {}
        for i, f in ipairs(found) do
            ids[i] = f.id
        end
        return ids
    end)
end

----------------------------------------------------------------------
-- Farms
----------------------------------------------------------------------

local function altWith(kind, skill, level)
    for key, c in pairs(ns.db.chars) do
        if key ~= ns.charKey and (c.level or 0) >= level - 2 then
            local p = c.profs and c.profs[kind]
            if not kind or (p and (p.skill or 0) >= skill) then
                return c.name
            end
        end
    end
    return nil
end

function ns.FarmList()
    return cached("farms", function()
        local me = ns.Char()
        local level = ns.player.level or 1
        local faction = ns.player.faction
        local out = {}
        for _, f in ipairs(ns.FARMS) do
            local e = { farm = f, items = {}, ok = true }
            local total, priced = 0, 0
            for _, entry in ipairs(f.items) do
                local id = ns.Resolve(entry)
                local value, how
                if id then
                    value, how = ns.SellValue(id)
                end
                local rate = entry[3] or 0
                e.items[#e.items + 1] = { id = id, name = entry[1], rate = rate, value = value, how = how }
                if value then
                    total = total + value * rate
                    priced = priced + 1
                end
            end
            e.perHour = priced > 0 and total or nil
            e.where = f.both or (faction == "Alliance" and f.alliance) or f.horde or f.alliance or ""
            if f.kind then
                local p = me.profs[f.kind]
                if not p then
                    e.ok = false
                    e.need = "Needs " .. f.kind
                elseif (p.skill or 0) < (f.skill or 1) then
                    e.ok = false
                    e.need = "Needs " .. f.kind .. " " .. f.skill .. " (you have " .. (p.skill or 0) .. ")"
                end
            end
            if e.ok and level < (f.level or 1) - 2 then
                e.ok = false
                e.need = "Best from level " .. f.level
            end
            if not e.ok then
                e.alt = altWith(f.kind, f.skill or 1, f.level or 1)
            end
            out[#out + 1] = e
        end
        table.sort(out, function(a, b)
            if a.ok ~= b.ok then
                return a.ok
            end
            return (a.perHour or 0) > (b.perHour or 0)
        end)
        return out
    end)
end

----------------------------------------------------------------------
-- Helpers for the window
----------------------------------------------------------------------

-- Which professions does anyone on your account have? (To pick relevant tips.)
function ns.AccountProfessions()
    local have = {}
    for _, c in pairs(ns.db.chars) do
        for name in pairs(c.profs or {}) do
            have[name] = true
        end
    end
    return have
end

function ns.TotalGold()
    local total = 0
    for _, c in pairs(ns.db.chars) do
        total = total + (c.money or 0)
    end
    return total
end

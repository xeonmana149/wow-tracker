-- Forever Gold - what your farming adds up to
--
-- Everything here is worked out from what the tracker (Tracker.lua) has
-- measured on your own characters - nothing is guessed from a drop table:
--
--   * Mob rankings: every mob you've killed enough of, by what a kill is
--     worth at today's prices, with how fast you kill them, where, and at
--     what level.
--   * Suggested farms: the ones worth an hour for the character you're on.
--   * Mob routes: a loop through the places you killed a mob.
--   * The dashboard's numbers: your usual gold an hour, luck against your
--     own drop rates, the days you farmed.

local _, ns = ...
local floor, max, min = math.floor, math.max, math.min

local RANK_MIN_KILLS = 10    -- a mob is ranked once you've killed this many
local SPEED_MIN = 5          -- kills in a row needed before "kills an hour" is trusted
local DEFAULT_KILLS_HR = 100 -- until then, a typical pace
local LUCK_MIN_KILLS = 20    -- earlier kills needed before a drop rate counts as "usual"

local function itemValue(id)
    local c = ns.Char()
    if (c.bound and c.bound[id]) or ns.Untradeable(id) then
        return ns.VendorSell(id) or 0
    end
    return ns.SellValue(id) or 0
end

local function isGood(id)
    local it = ns.Item(id)
    return it and it.q and it.q >= 2
end

----------------------------------------------------------------------
-- Your usual pace
----------------------------------------------------------------------

-- Gold an hour over your saved sessions (at least five minutes long), or nil.
function ns.FarmUsualPerHour(exceptStarted)
    local v, s = 0, 0
    for _, e in ipairs(ns.db.sessions or {}) do
        if (e.secs or 0) >= 300 and e.t ~= exceptStarted then
            v, s = v + (e.v or 0), s + e.secs
        end
    end
    if s < 300 then
        return nil
    end
    return v / s * 3600
end

----------------------------------------------------------------------
-- Mob rankings
----------------------------------------------------------------------

-- One mob from the all-time numbers, at today's prices.
-- o.skipGood leaves out green-or-better drops (they're luck, not income).
local function mobEntry(name, m, o)
    local k = m.k or 0
    if k <= 0 then
        return nil
    end
    local value, drops = 0, {}
    if m.items and next(m.items) then
        value = m.coin or 0
        for id, n in pairs(m.items) do
            if not (o.skipGood and isGood(id)) then
                value = value + itemValue(id) * n
            end
        end
    else
        value = m.v or 0 -- from before items were counted
    end
    for id, d in pairs(m.drops or {}) do
        local each = itemValue(id)
        local n = m.items and m.items[id]
        drops[#drops + 1] = { id = id, rate = min(1, d / k), d = d, each = each,
            per = (n and n / k or min(1, d / k)) * each, good = isGood(id) }
    end
    table.sort(drops, function(a, b)
        if a.per ~= b.per then
            return a.per > b.per
        end
        return a.rate > b.rate
    end)
    local best
    for _, d in ipairs(drops) do
        if not (o.skipGood and d.good) then
            best = d
            break
        end
    end
    local zones = {}
    for z, n in pairs(m.z or {}) do
        zones[#zones + 1] = { name = z, n = n }
    end
    table.sort(zones, function(a, b) return a.n > b.n end)
    local killsHr, measured = DEFAULT_KILLS_HR, false
    if (m.gapN or 0) >= SPEED_MIN and (m.gapS or 0) > 0 then
        killsHr = min(400, 3600 / (m.gapS / m.gapN))
        measured = true
    end
    local spots = 0
    for _, list in pairs(m.spots or {}) do
        spots = max(spots, #list)
    end
    local perKill = value / k
    return { name = name, k = k, perKill = perKill, value = value, best = best, drops = drops, zones = zones,
        where = zones[1] and zones[1].name or nil, lo = m.lo, hi = m.hi, inst = m.inst and not m.out,
        killsHr = killsHr, speedMeasured = measured, perHour = perKill * killsHr, spots = spots,
        coin = m.coin or 0 }
end

-- Every mob you've killed at least `minKills` times (RANK_MIN_KILLS by
-- default), best per kill first. o = { skipGood, outside, minKills }.
function ns.MobRanking(o)
    o = o or {}
    local out = {}
    local need = o.minKills or RANK_MIN_KILLS
    for name, m in pairs(ns.TrackerLife().mobs) do
        if (m.k or 0) >= need then
            local e = mobEntry(name, m, o)
            if e and not (o.outside and e.inst) then
                out[#out + 1] = e
            end
        end
    end
    table.sort(out, function(a, b)
        if a.perKill ~= b.perKill then
            return a.perKill > b.perKill
        end
        return a.name < b.name
    end)
    return out
end
ns.FARM_RANK_MIN = RANK_MIN_KILLS

----------------------------------------------------------------------
-- Suggested farms
--
-- Mobs you've measured that pay well for this character: level-appropriate
-- (you can kill them, and they're not far below you), outside dungeons,
-- and worth at least your usual gold an hour (or 20 silver an hour before
-- you have a usual).
----------------------------------------------------------------------

local MIN_PER_HOUR = 2000

function ns.FarmSuggestions(limit)
    local level = ns.try(UnitLevel, "player") or (ns.player and ns.player.level) or 1
    local usual = ns.FarmUsualPerHour()
    local floorHr = max(MIN_PER_HOUR, usual and usual * 0.9 or 0)
    local out = {}
    for _, e in ipairs(ns.MobRanking({ outside = true })) do
        local hi = e.hi or e.lo
        local fits = not hi or (level >= hi - 2 and level <= hi + 15)
        if fits and e.perHour >= floorHr then
            e.vsUsual = usual and usual > 0 and (e.perHour / usual - 1) or nil
            out[#out + 1] = e
        end
    end
    table.sort(out, function(a, b) return a.perHour > b.perHour end)
    for i = #out, (limit or 5) + 1, -1 do
        out[i] = nil
    end
    return out
end

----------------------------------------------------------------------
-- A route through where you killed a mob
----------------------------------------------------------------------

-- The map with the most kill spots for this mob (the one you're on wins a tie).
function ns.MobRouteMap(name)
    local m = ns.TrackerLife().mobs[name]
    if not (m and m.spots) then
        return nil
    end
    local here = ns.PlayerMapPos and ns.PlayerMapPos()
    local best, bestN
    for mapID, list in pairs(m.spots) do
        local n = #list + ((mapID == here) and 0.5 or 0)
        if #list >= 2 and (not bestN or n > bestN) then
            best, bestN = mapID, n
        end
    end
    return best, best and #m.spots[best] or 0
end

function ns.PlanMobRoute(name)
    local mapID = ns.MobRouteMap(name)
    if not mapID then
        return nil, "I need at least two places you've killed " .. name .. " in one zone. Kill a few more with the tracker on."
    end
    local pts = {}
    for _, p in ipairs(ns.TrackerLife().mobs[name].spots[mapID]) do
        pts[#pts + 1] = { x = p[1], y = p[2], k = "mob", n = name, c = p[3] }
    end
    return ns.PlanRouteThrough(mapID, pts, { mob = true })
end

function ns.StartMobRoute(name)
    local plan, why = ns.PlanMobRoute(name)
    if not plan then
        ns.Print(why)
        return nil
    end
    plan.mob = name
    ns.StartRoute(plan)
    ns.Print("route started: " .. plan.n .. " places you've killed " .. name .. " in " .. ns.MapName(plan.map)
        .. ". Follow the arrow and the gold beam; it moves on as you reach each one.")
    return plan
end

----------------------------------------------------------------------
-- Luck: this session's drops against your own usual rates
----------------------------------------------------------------------

-- Returns { pct (-1..+), kills, items = { {id, got, expected}, ... } } or nil
-- when there isn't enough history to compare with.
function ns.FarmLuck()
    local t = ns.Tracker()
    if not t then
        return nil
    end
    local life = ns.TrackerLife().mobs
    local got, want, kills = 0, 0, 0
    local byItem = {}
    for name, m in pairs(t.mob or {}) do
        local lm = life[name]
        local prior = lm and (lm.k or 0) - (m.k or 0) or 0
        if m.k and m.k > 0 and prior >= LUCK_MIN_KILLS then
            kills = kills + m.k
            local seen = {}
            for id, d in pairs(lm.drops or {}) do
                local before = d - ((m.drops or {})[id] or 0)
                local rate = max(0, before) / prior
                local now = (m.drops or {})[id] or 0
                local each = itemValue(id)
                local e = byItem[id] or { id = id, got = 0, expected = 0 }
                e.got = e.got + now
                e.expected = e.expected + rate * m.k
                byItem[id] = e
                got = got + now * each
                want = want + rate * m.k * each
                seen[id] = true
            end
            -- Something new this time that never dropped before.
            for id, now in pairs(m.drops or {}) do
                if not seen[id] then
                    local e = byItem[id] or { id = id, got = 0, expected = 0 }
                    e.got = e.got + now
                    byItem[id] = e
                    got = got + now * itemValue(id)
                end
            end
        end
    end
    if kills == 0 or want <= 0 then
        return nil
    end
    local items = {}
    for _, e in pairs(byItem) do
        if e.expected >= 0.5 or e.got > 0 then
            items[#items + 1] = e
        end
    end
    table.sort(items, function(a, b) return a.expected > b.expected end)
    return { pct = got / want - 1, kills = kills, items = items }
end

----------------------------------------------------------------------
-- Days you farmed
----------------------------------------------------------------------

-- { days = { [key] = {s, v, k} }, streak, longest, best = {key, v} }
function ns.FarmDays()
    local days = ns.db.farmDays or {}
    local best
    for key, d in pairs(days) do
        if (d.v or 0) > 0 and (not best or d.v > best.v) then
            best = { key = key, v = d.v }
        end
    end
    local function farmed(t)
        local d = days[ns.FarmDayKey(t)]
        return d and ((d.s or 0) >= 60 or (d.v or 0) > 0)
    end
    -- The run of days up to today (or yesterday, if today hasn't started).
    local now = time()
    local streak, t = 0, now
    if not farmed(t) then
        t = t - 86400
    end
    while farmed(t) do
        streak = streak + 1
        t = t - 86400
    end
    -- Longest run in what's kept.
    local keys = {}
    for key in pairs(days) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    local longest, run, prevT = 0, 0, nil
    for _, key in ipairs(keys) do
        local y, m, d = key:match("^(%d+)-(%d+)-(%d+)$")
        local kt = y and time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
        local e = days[key]
        if kt and ((e.s or 0) >= 60 or (e.v or 0) > 0) then
            if prevT and math.abs(kt - prevT - 86400) < 7200 then
                run = run + 1
            else
                run = 1
            end
            prevT = kt
            longest = max(longest, run)
        end
    end
    return { days = days, streak = streak, longest = max(longest, streak), best = best }
end

----------------------------------------------------------------------
-- Overall: everything measured so far
----------------------------------------------------------------------

function ns.FarmOverall()
    local days = ns.db.farmDays or {}
    local secs, value, kills = 0, 0, 0
    for _, d in pairs(days) do
        secs, value, kills = secs + (d.s or 0), value + (d.v or 0), kills + (d.k or 0)
    end
    local most
    for name, m in pairs(ns.TrackerLife().mobs) do
        if not most or (m.k or 0) > most.k then
            most = { name = name, k = m.k or 0 }
        end
    end
    return { secs = secs, value = value, kills = kills, perHour = secs >= 300 and value / secs * 3600 or nil,
        most = most, from = ns.db.farmFrom or {} }
end

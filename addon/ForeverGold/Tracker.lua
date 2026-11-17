-- Forever Gold - kill and loot tracker
--
-- Start the timer, play, and see exactly where your gold came from:
--   * kills (and which mobs)
--   * coin looted, and items looted - split into mobs, Mining, Herbalism,
--     Skinning, Fishing and other (chests, clams...)
--   * money that actually came in: auction sales (from the mailbox),
--     vendor sales, other (quests, trades) - and what you spent
--
-- Pause, resume and reset whenever you like. Time only counts while it's
-- running, and logging out pauses it until you log back in.
--
-- Kills are counted without the combat log (a combat-log handler is what
-- got the tracker addon's "blocked action" popup): an enemy you or your
-- group tagged dying in front of you, or a corpse you loot, is a kill.

local _, ns = ...
local floor, max, min = math.floor, math.max, math.min

local LOOT_ITEM, LOOT_MONEY = 1, 2
local CATS = { "mob", "Mining", "Herbalism", "Skinning", "Fishing", "other" }
ns.TRACK_CATS = CATS
local CAT_LABEL = { mob = "Mob drops", Mining = "Mining", Herbalism = "Herbalism", Skinning = "Skinning",
    Fishing = "Fishing", other = "Chests, clams and other" }
ns.TRACK_CAT_LABEL = CAT_LABEL

local function blank()
    local loot = {}
    for _, c in ipairs(CATS) do
        loot[c] = {}
    end
    return {
        guid = ns.charKey,
        started = time(),
        secs = 0,
        kills = 0,
        mobs = {},
        loot = loot,
        coin = 0,
        inc = { ah = 0, vendor = 0, mail = 0, other = 0 },
        out = { ah = 0, vendor = 0, other = 0 },
        sold = {},
        zone = ns.try(GetRealZoneText) or "",
        -- Per mob: mob[name] = { k = kills, at = last kill, z = { [zone] = kills },
        --   items = { [id] = n }, coin = copper, good = green-or-better drops,
        --   since = kills since the last green-or-better drop }
        mob = {},
        -- Per gathering node: nodes[name] = { n = times, cat = "Mining"..., items = { [id] = n }, at = last }
        nodes = {},
        gathers = 0,
        streak = 0, -- kills since you last died
        best = 0,
    }
end

-- The tracker for this character, or nil if none has been started.
local function T()
    local t = ns.db.track and ns.db.track[ns.charKey]
    if t and not t.mob then
        -- Started by an older version: add the newer tables.
        t.mob, t.nodes, t.gathers, t.streak, t.best = {}, {}, 0, 0, 0
    end
    return t
end

-- All-time numbers across every trip (account-wide, by name):
-- life.mobs[name] = { k = kills, v = value looted, good = green-or-better drops }
-- life.nodes[name] = { n = times gathered, v = value }
local function Life()
    local l = ns.db.life
    if type(l) ~= "table" then
        l = { mobs = {}, nodes = {} }
        ns.db.life = l
    end
    l.mobs = l.mobs or {}
    l.nodes = l.nodes or {}
    return l
end
ns.TrackerLife = Life

function ns.Tracker()
    return T()
end

function ns.TrackerRunning()
    local t = T()
    return t and t.runAt and true or false
end

function ns.TrackerSeconds()
    local t = T()
    if not t then
        return 0
    end
    return (t.secs or 0) + (t.runAt and max(0, time() - t.runAt) or 0)
end

----------------------------------------------------------------------
-- Controls
----------------------------------------------------------------------

local lastMoney

function ns.TrackerStart()
    ns.db.track = ns.db.track or {}
    local t = T()
    if not t then
        t = blank()
        ns.db.track[ns.charKey] = t
        ns.Print("tracker started. Kills, loot and every copper in or out are counted from now. Pause it any time.")
    elseif not t.runAt then
        ns.Print("tracker running again.")
    end
    t.runAt = t.runAt or time()
    t.autoPaused = nil
    lastMoney = ns.try(GetMoney) or lastMoney
    ns.Fire("SESSION")
end

function ns.TrackerPause(quiet)
    local t = T()
    if not t or not t.runAt then
        return
    end
    t.secs = (t.secs or 0) + max(0, time() - t.runAt)
    t.runAt = nil
    if not quiet then
        ns.Print("tracker paused at " .. ns.Duration(t.secs) .. ".")
    end
    ns.Fire("SESSION")
end

function ns.TrackerToggle()
    if ns.TrackerRunning() then
        ns.TrackerPause()
    else
        ns.TrackerStart()
    end
end

-- Wipes the numbers. Keeps running if it was running.
function ns.TrackerReset()
    local t = T()
    local wasRunning = t and t.runAt
    ns.db.track = ns.db.track or {}
    local fresh = blank()
    if wasRunning then
        fresh.runAt = time()
    end
    ns.db.track[ns.charKey] = wasRunning and fresh or nil
    lastMoney = ns.try(GetMoney) or lastMoney
    ns.Print("tracker reset" .. (wasRunning and " - counting from zero again." or "."))
    ns.Fire("SESSION")
end

----------------------------------------------------------------------
-- Adding it all up
----------------------------------------------------------------------

local function itemValue(id)
    local c = ns.Char()
    if c.bound and c.bound[id] then
        return ns.VendorSell(id) or 0, "vendor"
    end
    local v, how = ns.SellValue(id)
    return v or 0, how
end

-- Everything worked out at today's prices:
-- { secs, kills, coin, lootValue, made, perHour,
--   cats = { [cat] = { value, items = { {id, n, v}, ... } } },
--   cashIn, cashOut, net, inc, out, mobs = sorted { {name, n} }, sold = sorted { {name, q, v} },
--   items = all looted items sorted by value }
function ns.TrackerSummary()
    local t = T()
    if not t then
        return nil
    end
    local s = { secs = ns.TrackerSeconds(), kills = t.kills or 0, coin = t.coin or 0, cats = {}, items = {} }
    local lootValue = 0
    for _, cat in ipairs(CATS) do
        local entry = { value = 0, items = {} }
        for id, n in pairs(t.loot[cat] or {}) do
            local each = itemValue(id)
            local v = each * n
            entry.items[#entry.items + 1] = { id = id, n = n, v = v }
            s.items[#s.items + 1] = { id = id, n = n, v = v, cat = cat }
            entry.value = entry.value + v
        end
        table.sort(entry.items, function(a, b) return a.v > b.v end)
        s.cats[cat] = entry
        lootValue = lootValue + entry.value
    end
    table.sort(s.items, function(a, b) return a.v > b.v end)
    s.lootValue = lootValue
    s.made = lootValue + s.coin
    s.perHour = s.secs > 60 and s.made / s.secs * 3600 or nil
    s.inc, s.out = t.inc, t.out
    s.cashIn = (t.inc.ah or 0) + (t.inc.vendor or 0) + (t.inc.mail or 0) + (t.inc.other or 0) + s.coin
    s.cashOut = (t.out.ah or 0) + (t.out.vendor or 0) + (t.out.other or 0)
    s.net = s.cashIn - s.cashOut
    s.mobs = {}
    for name, n in pairs(t.mobs or {}) do
        s.mobs[#s.mobs + 1] = { name = name, n = n }
    end
    table.sort(s.mobs, function(a, b) return a.n > b.n end)
    s.sold = {}
    for name, e in pairs(t.sold or {}) do
        s.sold[#s.sold + 1] = { name = name, q = e.q or 0, v = e.v or 0 }
    end
    table.sort(s.sold, function(a, b) return a.v > b.v end)
    s.zone = t.zone
    s.running = t.runAt and true or false
    s.streak, s.best, s.gathers = t.streak or 0, t.best or 0, t.gathers or 0
    return s
end

-- Each mob killed this trip, at today's prices:
-- { name, k, at, value, perKill, coin, good, since, zones = { names by kills },
--   items = { {id, n, v} by value }, life = { k, v, good } }
-- sort: "recent" (default), "kills" or "value"
function ns.TrackerMobs(sort)
    local t = T()
    local out = {}
    if not t then
        return out
    end
    local life = Life().mobs
    for name, m in pairs(t.mob) do
        local e = { name = name, k = m.k, at = m.at or 0, coin = m.coin or 0, good = m.good or 0, since = m.since or 0,
            items = {}, zones = {}, life = life[name] or { k = 0, v = 0, good = 0 } }
        local v = e.coin
        for id, n in pairs(m.items) do
            local each = itemValue(id)
            e.items[#e.items + 1] = { id = id, n = n, v = each * n }
            v = v + each * n
        end
        table.sort(e.items, function(a, b) return a.v > b.v end)
        for z, n in pairs(m.z or {}) do
            e.zones[#e.zones + 1] = { name = z, n = n }
        end
        table.sort(e.zones, function(a, b) return a.n > b.n end)
        e.value = v
        e.perKill = m.k > 0 and v / m.k or 0
        out[#out + 1] = e
    end
    local by = {
        kills = function(a, b) return a.k > b.k or (a.k == b.k and a.name < b.name) end,
        value = function(a, b) return a.value > b.value or (a.value == b.value and a.name < b.name) end,
        recent = function(a, b) return a.at > b.at or (a.at == b.at and a.name < b.name) end,
    }
    table.sort(out, by[sort] or by.recent)
    return out
end

-- Each gathering node this trip: { name, n, cat, value, items, life = { n, v } }, most gathered first.
function ns.TrackerNodes()
    local t = T()
    local out = {}
    if not t then
        return out
    end
    local life = Life().nodes
    for name, e in pairs(t.nodes) do
        local v, items = 0, {}
        for id, n in pairs(e.items) do
            local each = itemValue(id)
            items[#items + 1] = { id = id, n = n, v = each * n }
            v = v + each * n
        end
        table.sort(items, function(a, b) return a.v > b.v end)
        out[#out + 1] = { name = name, n = e.n, cat = e.cat, value = v, items = items, life = life[name] or { n = 0, v = 0 } }
    end
    table.sort(out, function(a, b) return a.n > b.n or (a.n == b.n and a.name < b.name) end)
    return out
end

----------------------------------------------------------------------
-- The old "farming session" names, used by the HUD and buttons
----------------------------------------------------------------------

function ns.SessionActive()
    return T()
end

-- total value made, seconds, looted items sorted by value, coin
function ns.SessionValue()
    local s = ns.TrackerSummary()
    if not s then
        return 0, 0, {}, 0
    end
    return s.made, max(1, s.secs), s.items, s.coin
end

function ns.StartSession()
    ns.TrackerStart()
end

-- Saves the trip to "Your measured farming sessions" and clears the tracker.
function ns.StopSession()
    local s = ns.TrackerSummary()
    if not s then
        return
    end
    local top = {}
    for i = 1, min(4, #s.items) do
        top[i] = { s.items[i].id, s.items[i].n }
    end
    if s.secs >= 60 or s.made > 0 then
        table.insert(ns.db.sessions, 1, { t = T().started, secs = max(1, s.secs), v = floor(s.made),
            zone = ns.try(GetRealZoneText) or s.zone, top = top, who = ns.Char().name, kills = s.kills,
            cash = floor(s.net) })
        ns.db.sessions[31] = nil
    end
    ns.db.track[ns.charKey] = nil
    ns.Print("trip saved: " .. ns.Money(s.made) .. " in " .. ns.Duration(max(1, s.secs))
        .. (s.perHour and (" - that's " .. ns.Money(s.perHour) .. " per hour") or "") .. ", " .. s.kills .. " kills.")
    ns.Fire("SESSION")
end

function ns.ToggleSession()
    ns.TrackerToggle()
end

----------------------------------------------------------------------
-- Kills
----------------------------------------------------------------------

local counted, countedList = {}, {}
local guidName = {} -- names of recently seen mobs, so loot can be put against the right one
local function markCounted(guid)
    counted[guid] = true
    countedList[#countedList + 1] = guid
    if #countedList > 600 then
        local old = table.remove(countedList, 1)
        counted[old] = nil
        guidName[old] = nil
    end
end

local function nameOf(guid)
    if not guid then
        return nil
    end
    if guidName[guid] then
        return guidName[guid]
    end
    for _, unit in ipairs({ "target", "mouseover", "focus" }) do
        if ns.try(UnitGUID, unit) == guid then
            local n = ns.try(UnitName, unit)
            if n and n ~= "" then
                guidName[guid] = n
                return n
            end
        end
    end
    return nil
end

local function mobEntry(t, name)
    local m = t.mob[name]
    if not m then
        m = { k = 0, at = 0, z = {}, items = {}, coin = 0, good = 0, since = 0 }
        t.mob[name] = m
    end
    return m
end

local function lifeMob(name)
    local l = Life().mobs
    local e = l[name]
    if not e then
        e = { k = 0, v = 0, good = 0 }
        l[name] = e
    end
    return e
end

local function addKill(guid, name)
    local t = T()
    if not t or not t.runAt or not guid or counted[guid] then
        return
    end
    markCounted(guid)
    if name and name ~= "" then
        guidName[guid] = name
    else
        name = nameOf(guid)
    end
    t.kills = (t.kills or 0) + 1
    t.streak = (t.streak or 0) + 1
    if t.streak > (t.best or 0) then
        t.best = t.streak
    end
    if name and name ~= "" then
        t.mobs[name] = (t.mobs[name] or 0) + 1
        local m = mobEntry(t, name)
        m.k = m.k + 1
        m.at = time()
        m.since = m.since + 1
        local zone = ns.try(GetRealZoneText) or ""
        if zone ~= "" then
            m.z[zone] = (m.z[zone] or 0) + 1
        end
        local lm = lifeMob(name)
        lm.k = lm.k + 1
    end
    ns.Later("track-ui", 0.5, function() ns.Fire("SESSION") end)
end

-- Dying ends the kill streak.
ns.On("PLAYER_DEAD", function()
    local t = T()
    if t and t.runAt then
        t.streak = 0
        ns.Fire("SESSION")
    end
end)

local function watchedUnit(unit)
    return unit == "target" or unit == "focus" or unit == "mouseover" or unit == "softenemy"
        or (type(unit) == "string" and unit:sub(1, 9) == "nameplate")
end

ns.On("UNIT_HEALTH", function(unit)
    if not ns.ready or not ns.TrackerRunning() or not watchedUnit(unit) then
        return
    end
    if not ns.try(UnitIsDead, unit) or ns.try(UnitIsPlayer, unit) then
        return
    end
    if not ns.try(UnitCanAttack, "player", unit) or ns.try(UnitIsTapDenied, unit) then
        return
    end
    local guid = ns.try(UnitGUID, unit)
    if type(guid) == "string" and (guid:find("^Creature") or guid:find("^Vehicle")) then
        addKill(guid, ns.try(UnitName, unit))
    end
end)

----------------------------------------------------------------------
-- Loot
----------------------------------------------------------------------

local lastGather -- { cat =, at =, node = }
local gatherCat = { ore = "Mining", herb = "Herbalism", skin = "Skinning" }
local sent -- { target =, at = }: what the last spell was cast on ("Copper Vein")

ns.On("UNIT_SPELLCAST_SENT", function(unit, target)
    if unit == "player" and type(target) == "string" and target ~= "" then
        sent = { target = target, at = GetTime() }
    end
end)

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" or not ns.GatherKind then
        return
    end
    local kind = ns.GatherKind(spellID)
    if gatherCat[kind] then
        local node = sent and GetTime() - sent.at < 10 and sent.target or nil
        lastGather = { cat = gatherCat[kind], at = GetTime(), node = node }
    end
end)

local looting = false
local pending = {} -- [slot] = { id, n, cat, mob, node, q }
local coinMob -- the mob the coin in this loot window came from

local function slotSource(slot)
    if type(GetLootSourceInfo) ~= "function" then
        return nil
    end
    local ok, guid = pcall(GetLootSourceInfo, slot)
    if ok and type(guid) == "string" then
        return guid
    end
    return nil
end

local function onLootReady()
    looting = true
    if not ns.TrackerRunning() then
        return
    end
    local fishing = type(IsFishingLoot) == "function" and ns.try(IsFishingLoot)
    local gather = lastGather and GetTime() - lastGather.at < 3 and lastGather.cat or nil
    wipe(pending)
    coinMob = nil
    local n = ns.try(GetNumLootItems) or 0
    local usedGather = false
    local t = T()
    for slot = 1, n do
        local guid = slotSource(slot)
        local fromNode = guid and guid:find("^GameObject")
        local fromCorpse = guid and (guid:find("^Creature") or guid:find("^Vehicle"))
        -- A gathering cast only claims loot from the right kind of thing:
        -- ore and herbs come from nodes, skins from corpses.
        local gatherFits = gather and (not guid or (gather == "Skinning" and fromCorpse)
            or (gather ~= "Skinning" and fromNode))
        local cat
        if fishing then
            cat = "Fishing"
        elseif gatherFits then
            cat = gather
            usedGather = true
        elseif fromCorpse then
            cat = "mob"
            -- Looting a corpse also counts it as a kill, in case its death
            -- happened somewhere the health check couldn't see.
            addKill(guid)
        else
            cat = "other"
        end
        local mob = cat == "mob" and nameOf(guid) or nil
        local slotType = ns.try(GetLootSlotType, slot)
        if slotType == LOOT_ITEM then
            local link = ns.try(GetLootSlotLink, slot)
            local id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
            local _, _, qty, _, quality = ns.try(GetLootSlotInfo, slot)
            if id then
                pending[slot] = { id = id, n = max(1, tonumber(qty) or 1), cat = cat, mob = mob,
                    node = gatherFits and gather and lastGather and lastGather.node or nil, q = tonumber(quality) }
            end
        elseif slotType == LOOT_MONEY and mob then
            coinMob = mob
        end
    end
    if usedGather then
        -- One cast, one loot window: count the node once.
        local node = lastGather.node or gather
        if t then
            local e = t.nodes[node]
            if not e then
                e = { n = 0, cat = gather, items = {}, at = 0 }
                t.nodes[node] = e
            end
            e.n = e.n + 1
            e.at = time()
            t.gathers = (t.gathers or 0) + 1
            local ln = Life().nodes
            ln[node] = ln[node] or { n = 0, v = 0 }
            ln[node].n = ln[node].n + 1
        end
        lastGather = nil
    end
end

ns.On("LOOT_READY", onLootReady)
ns.On("LOOT_OPENED", function()
    if not looting then
        onLootReady()
    end
    looting = true
end)

ns.On("LOOT_SLOT_CLEARED", function(slot)
    local p = pending[slot]
    pending[slot] = nil
    local t = T()
    if not p or not t or not t.runAt then
        return
    end
    local bucket = t.loot[p.cat] or t.loot.other
    bucket[p.id] = (bucket[p.id] or 0) + p.n
    local it = ns.Item(p.id)
    local q = p.q or (it and it.q)
    local worth = (itemValue(p.id) or 0) * p.n
    if p.mob then
        local m = mobEntry(t, p.mob)
        m.items[p.id] = (m.items[p.id] or 0) + p.n
        local lm = lifeMob(p.mob)
        lm.v = lm.v + worth
        if q and q >= 2 then
            m.good = m.good + 1
            m.since = 0
            lm.good = lm.good + 1
        end
    end
    if p.node and t.nodes[p.node] then
        local e = t.nodes[p.node]
        e.items[p.id] = (e.items[p.id] or 0) + p.n
        local ln = Life().nodes[p.node]
        if ln then
            ln.v = ln.v + worth
        end
    end
    ns.Later("track-ui", 0.5, function() ns.Fire("SESSION") end)
end)

ns.On("LOOT_CLOSED", function()
    -- Money from the loot window lands a moment after it closes.
    C_Timer.After(0.5, function()
        looting = false
    end)
    wipe(pending)
end)

----------------------------------------------------------------------
-- Money in and out
----------------------------------------------------------------------

local mailOpen, merchantOpen = false, false
local invoice -- the auction-sale mail you just took money from

ns.On("MAIL_SHOW", function() mailOpen = true end)
ns.On("MAIL_CLOSED", function() mailOpen = false end)
ns.On("MERCHANT_SHOW", function() merchantOpen = true end)
ns.On("MERCHANT_CLOSED", function() merchantOpen = false end)

local function noteMail(index)
    if type(index) ~= "number" or type(GetInboxInvoiceInfo) ~= "function" then
        return
    end
    local ok, kind, itemName, _, _, _, _, _, _, _, _, count = pcall(GetInboxInvoiceInfo, index)
    if ok and kind == "seller" then
        invoice = { item = itemName, count = tonumber(count) or 1, at = GetTime() }
    else
        invoice = nil
    end
end

local function hookMail()
    if type(hooksecurefunc) ~= "function" then
        return
    end
    if type(TakeInboxMoney) == "function" then
        hooksecurefunc("TakeInboxMoney", noteMail)
    end
    if type(AutoLootMailItem) == "function" then
        hooksecurefunc("AutoLootMailItem", noteMail)
    end
end

ns.On("PLAYER_MONEY", function()
    local now = ns.try(GetMoney)
    if not now then
        return
    end
    local delta = lastMoney and (now - lastMoney) or 0
    lastMoney = now
    local t = T()
    if not ns.ready or not t or not t.runAt or delta == 0 then
        return
    end
    if delta > 0 then
        if looting then
            t.coin = (t.coin or 0) + delta
            if coinMob then
                local m = mobEntry(t, coinMob)
                m.coin = m.coin + delta
                local lm = lifeMob(coinMob)
                lm.v = lm.v + delta
            end
        elseif mailOpen then
            if invoice and GetTime() - invoice.at < 10 then
                t.inc.ah = (t.inc.ah or 0) + delta
                local name = invoice.item or "?"
                local e = t.sold[name] or { q = 0, v = 0 }
                e.q, e.v = e.q + invoice.count, e.v + delta
                t.sold[name] = e
                invoice = nil
            else
                t.inc.mail = (t.inc.mail or 0) + delta
            end
        elseif merchantOpen then
            t.inc.vendor = (t.inc.vendor or 0) + delta
        else
            t.inc.other = (t.inc.other or 0) + delta
        end
    else
        local spent = -delta
        if merchantOpen then
            t.out.vendor = (t.out.vendor or 0) + spent
        elseif ns.ahOpen then
            t.out.ah = (t.out.ah or 0) + spent
        else
            t.out.other = (t.out.other or 0) + spent
        end
    end
    ns.Later("track-ui", 0.5, function() ns.Fire("SESSION") end)
end)

----------------------------------------------------------------------
-- Logging out pauses; logging back in carries on
----------------------------------------------------------------------

ns.On("PLAYER_LOGOUT", function()
    local t = T()
    if t and t.runAt then
        t.secs = (t.secs or 0) + max(0, time() - t.runAt)
        t.runAt = nil
        t.autoPaused = true
    end
end)

ns.Listen("READY", function()
    lastMoney = ns.try(GetMoney)
    hookMail()
    ns.db.track = ns.db.track or {}
    -- Old-style session from before the tracker existed: drop it.
    if ns.db.session then
        ns.db.session = nil
    end
    local t = T()
    if t and t.autoPaused then
        t.autoPaused = nil
        t.runAt = time()
    end
end)

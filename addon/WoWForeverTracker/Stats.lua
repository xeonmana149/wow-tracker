-- Lifetime gathering and loot counters (1.9.20, 2026-11-26: "track total
-- herbs/ore/skins gathered, chests opened, world blues/epics, world greens,
-- per character and account total").
--
-- Always on, nothing to start. Kept per character in WFTSyncDB.lootStats,
-- sent with every sync (the website adds up the account) and shown in game
-- by Hub.lua:
--
--   lootStats = {
--     v = 1, since = time counting started,
--     gather = { herb = { n = nodes, items = items }, ore = ..., skin = ..., fish = ... },
--     chests = chests opened in the world,
--     opened = containers opened from your bags (clams, lockboxes, bags of loot),
--     drops = { world = { green =, blue =, epic =, legendary = }, dungeon = {...}, raid = {...} },
--     recent = { { link =, q = "blue", where = "world", at = }, ... } -- the latest blue or better
--   }
--
-- How each is told apart:
--   * gathering: a Mining / Herb Gathering / Skinning cast that succeeded,
--     followed within 3 seconds by a loot window from the right kind of
--     thing (a node for ore and herbs, a corpse for skins); fishing is the
--     game's own IsFishingLoot. One loot window counts one node.
--   * chests: an "Opening" cast that succeeded on something named like a
--     chest (chest, strongbox, coffer, footlocker, trunk, cache).
--   * containers: a loot window whose source is an item in your bags.
--   * drops: "You receive loot: [item]" (which includes rolls you won),
--     green or better, by where you were. Items out of a gathering loot
--     window (a green gem from a mining node) don't count as drops.
-- Every value the game hands over is checked for being a secret value
-- first; a secret one is skipped, never compared.

local _, ns = ...
ns = ns or {}

local GATHER_KINDS = { "herb", "ore", "skin", "fish" }
local WHERE = { "world", "dungeon", "raid" }
local QUALITY = { "green", "blue", "epic", "legendary" }
local RECENT_MAX = 25
local CHEST_WORDS = { "chest", "strongbox", "coffer", "footlocker", "trunk", "cache" }
-- The colour in an item link says its quality.
local LINK_QUALITY = {
    ["1eff00"] = "green", ["0070dd"] = "blue", ["0070ff"] = "blue", ["a335ee"] = "epic",
    ["ff8000"] = "legendary",
}
local QUALITY_BY_NUMBER = { [2] = "green", [3] = "blue", [4] = "epic", [5] = "legendary" }

local function secret(v)
    return type(issecretvalue) == "function" and issecretvalue(v) and true or false
end

-- pcall that gives up (nil) when the call fails or hands back a secret.
local function try(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local r = { pcall(fn, ...) }
    if not r[1] then
        return nil
    end
    for i = 2, table.maxn(r) do
        if secret(r[i]) then
            return nil
        end
    end
    return unpack(r, 2, table.maxn(r))
end
ns.try = ns.try or try

local function now()
    return (type(GetTime) == "function" and GetTime()) or 0
end

local function stats()
    WFTSyncDB = WFTSyncDB or {}
    local s = WFTSyncDB.lootStats
    if type(s) ~= "table" then
        s = { v = 1, since = time() }
        WFTSyncDB.lootStats = s
    end
    s.gather = type(s.gather) == "table" and s.gather or {}
    for _, k in ipairs(GATHER_KINDS) do
        local g = s.gather[k]
        if type(g) ~= "table" then
            g = {}
            s.gather[k] = g
        end
        g.n = tonumber(g.n) or 0
        g.items = tonumber(g.items) or 0
    end
    s.chests = tonumber(s.chests) or 0
    s.opened = tonumber(s.opened) or 0
    s.drops = type(s.drops) == "table" and s.drops or {}
    for _, w in ipairs(WHERE) do
        local d = s.drops[w]
        if type(d) ~= "table" then
            d = {}
            s.drops[w] = d
        end
        for _, q in ipairs(QUALITY) do
            d[q] = tonumber(d[q]) or 0
        end
    end
    s.recent = type(s.recent) == "table" and s.recent or {}
    return s
end
ns.LootStats = stats

local function where()
    local inside, kind = try(IsInInstance)
    if inside and kind == "raid" then
        return "raid"
    elseif inside and kind == "party" then
        return "dungeon"
    end
    return "world"
end

local function isChestName(name)
    if type(name) ~= "string" or secret(name) then
        return false
    end
    local l = name:lower()
    for _, w in ipairs(CHEST_WORDS) do
        if l:find(w, 1, true) then
            return true
        end
    end
    return false
end
ns.IsChestName = ns.IsChestName or isChestName

local spellKind = {}
local function gatherKind(spellID)
    if not spellID or secret(spellID) then
        return nil
    end
    local known = spellKind[spellID]
    if known ~= nil then
        return known or nil
    end
    local name = (C_Spell and try(C_Spell.GetSpellName, spellID)) or try(GetSpellInfo, spellID)
    local kind = false
    if type(name) == "string" then
        local l = name:lower()
        -- Find Herbs / Find Minerals only switch on minimap tracking.
        if l:find("^find ") or l:find("^track ") then
            kind = false
        elseif l:find("^mining") then
            kind = "ore"
        elseif l:find("herb") then
            kind = "herb"
        elseif l == "skinning" then
            kind = "skin"
        elseif l == "fishing" then
            kind = "fish"
        elseif l:find("^opening") then
            kind = "open"
        end
    end
    spellKind[spellID] = kind
    return kind or nil
end
ns.StatsGatherKind = gatherKind

local function slotSource(slot)
    local guid = try(GetLootSourceInfo, slot)
    return type(guid) == "string" and guid or nil
end

local function itemID(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

local function qualityOf(link)
    if type(link) ~= "string" then
        return nil
    end
    local color = link:match("|c%x%x(%x%x%x%x%x%x)")
    local q = color and LINK_QUALITY[color:lower()]
    if q then
        return q
    end
    local _, _, number = try(GetItemInfo, link)
    return QUALITY_BY_NUMBER[tonumber(number) or 0]
end

----------------------------------------------------------------------
-- Watching
----------------------------------------------------------------------

local state = {
    sent = nil,        -- { target =, at = }: what the last cast was aimed at
    gather = nil,      -- { kind =, at = }: a gathering cast that just finished
    counted = false,   -- this loot window has been counted
    gathered = {},     -- [itemID] = time: items that just came out of a gathering window
    containers = {},   -- [item guid] = true: bag containers already counted
}
ns.StatsState = state

local function onSent(unit, target)
    if secret(unit) or unit ~= "player" then
        return
    end
    if secret(target) or type(target) ~= "string" or target == "" then
        state.sent = nil
    else
        state.sent = { target = target, at = now() }
    end
end

local function onSucceeded(unit, _, spellID)
    if secret(unit) or unit ~= "player" then
        return
    end
    local kind = gatherKind(spellID)
    if kind == "open" then
        local target = state.sent and now() - state.sent.at < 20 and state.sent.target or nil
        if isChestName(target) then
            local s = stats()
            s.chests = s.chests + 1
        end
        state.sent = nil
    elseif kind == "fish" then
        state.fishAt = now()
    elseif kind then
        state.gather = { kind = kind, at = now() }
    end
end

local function onLoot()
    if state.counted then
        return
    end
    state.counted = true
    local s = stats()
    local n = try(GetNumLootItems) or 0
    local fishing
    if type(IsFishingLoot) == "function" then
        fishing = try(IsFishingLoot) and true or false
    else
        -- No direct answer: loot within a cast's length of starting to fish.
        fishing = state.fishAt and now() - state.fishAt < 32 or false
    end
    local g = state.gather and now() - state.gather.at < 3 and state.gather.kind or nil
    local first = slotSource(1)
    local fromNode = first and first:find("^GameObject") and true or false
    local fromCorpse = first and (first:find("^Creature") or first:find("^Vehicle")) and true or false
    local kind
    if fishing then
        kind = "fish"
    elseif g and (not first or (g == "skin" and fromCorpse) or (g ~= "skin" and fromNode)) then
        kind = g
    end
    if kind then
        local entry = s.gather[kind]
        entry.n = entry.n + 1
        for slot = 1, n do
            local link = try(GetLootSlotLink, slot)
            local id = itemID(link)
            if id then
                local _, _, qty = try(GetLootSlotInfo, slot)
                entry.items = entry.items + math.max(1, tonumber(qty) or 1)
                state.gathered[id] = now()
            end
        end
        if kind == "fish" then
            state.fishAt = nil
        else
            state.gather = nil
        end
    elseif first and first:find("^Item") and not state.containers[first] then
        state.containers[first] = true
        s.opened = s.opened + 1
    end
end

-- "You receive loot: %s" and "You receive loot: %sx%d" as Lua patterns.
local lootPatterns
local function toPattern(fmt)
    if type(fmt) ~= "string" then
        return nil
    end
    local p = fmt:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
    p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    p = p:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
    return "^" .. p .. "$"
end
local function patterns()
    if not lootPatterns then
        lootPatterns = {}
        -- The longer "...x%d" form first, so its count isn't read as part of the link.
        for _, key in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF" }) do
            local p = toPattern(_G[key])
            if p then
                lootPatterns[#lootPatterns + 1] = p
            end
        end
        if #lootPatterns == 0 then
            lootPatterns[1] = "^You receive loot: (.+)$"
        end
    end
    return lootPatterns
end

local function onLootMessage(msg)
    if type(msg) ~= "string" or secret(msg) then
        return
    end
    local link
    for _, p in ipairs(patterns()) do
        link = msg:match(p)
        if link then
            break
        end
    end
    if not link then
        return
    end
    link = link:match("(|c%x+|Hitem:.-|h.-|h|r)") or link
    local q = qualityOf(link)
    if not q then
        return
    end
    local id = itemID(link)
    if id and state.gathered[id] and now() - state.gathered[id] < 10 then
        return -- out of a gathering node, not a drop
    end
    local s = stats()
    local w = where()
    s.drops[w][q] = s.drops[w][q] + 1
    if q ~= "green" then
        table.insert(s.recent, { link = link, q = q, where = w, at = time() })
        while #s.recent > RECENT_MAX do
            table.remove(s.recent, 1)
        end
    end
end

local frame = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "LOOT_READY",
    "LOOT_OPENED", "LOOT_CLOSED", "CHAT_MSG_LOOT" }) do
    pcall(frame.RegisterEvent, frame, e)
end
frame:SetScript("OnEvent", function(_, event, ...)
    local ok, err = pcall(function(...)
        if event == "UNIT_SPELLCAST_SENT" then
            onSent(...)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            onSucceeded(...)
        elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
            onLoot()
        elseif event == "LOOT_CLOSED" then
            state.counted = false
        elseif event == "CHAT_MSG_LOOT" then
            onLootMessage(...)
        elseif event == "PLAYER_LOGIN" then
            stats()
        end
    end, ...)
    if not ok and type(WFTSyncDB) == "table" then
        WFTSyncDB.statsErr = tostring(err)
    end
end)
ns.StatsOnEvent = frame:GetScript("OnEvent")

-- Sums of a lootStats table, for the window and its account column.
function ns.LootTotals(s)
    local t = { herb = 0, ore = 0, skin = 0, fish = 0, herbItems = 0, oreItems = 0, skinItems = 0, fishItems = 0,
        chests = 0, opened = 0, drops = {} }
    for _, w in ipairs(WHERE) do
        t.drops[w] = { green = 0, blue = 0, epic = 0, legendary = 0 }
    end
    if type(s) ~= "table" then
        return t
    end
    for _, k in ipairs(GATHER_KINDS) do
        local g = type(s.gather) == "table" and s.gather[k]
        if type(g) == "table" then
            t[k] = tonumber(g.n) or 0
            t[k .. "Items"] = tonumber(g.items) or 0
        end
    end
    t.chests = tonumber(s.chests) or 0
    t.opened = tonumber(s.opened) or 0
    for _, w in ipairs(WHERE) do
        local d = type(s.drops) == "table" and s.drops[w]
        if type(d) == "table" then
            for _, q in ipairs(QUALITY) do
                t.drops[w][q] = tonumber(d[q]) or 0
            end
        end
    end
    return t
end

function ns.AddTotals(a, b)
    for k, v in pairs(b) do
        if type(v) == "number" then
            a[k] = (a[k] or 0) + v
        end
    end
    for _, w in ipairs(WHERE) do
        for _, q in ipairs(QUALITY) do
            a.drops[w][q] = a.drops[w][q] + b.drops[w][q]
        end
    end
    return a
end

ns.LOOT_WHERE, ns.LOOT_QUALITY, ns.GATHER_KINDS = WHERE, QUALITY, GATHER_KINDS

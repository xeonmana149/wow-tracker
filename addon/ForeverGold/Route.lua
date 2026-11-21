-- Forever Gold - gathering spots and routes
--
-- 1. Remembers every ore vein, herb and fishing spot you gather, with its
--    exact map position. (Nothing is copied from other addons or websites -
--    the map of nodes is your own, and it covers WoW Forever's new zones.)
-- 2. Builds a short loop through the spots in a zone.
-- 3. Guides you round the loop with an arrow and, if the game supports it
--    here, the built-in map waypoint.
--
-- nodes[uiMapID] = { { x=, y=, k="ore"|"herb"|"fish", n="Copper Vein", c=timesGathered, t=lastTime }, ... }

local _, ns = ...
local sqrt, abs, floor = math.sqrt, math.abs, math.floor

-- Each kind has its own picture (pickaxe, leaf, hook) so the map reads
-- without relying on colour.
ns.KINDS = {
    ore = { label = "Ore", one = "ore vein", many = "ore veins", none = "No ore recorded",
        icon = "Interface\\Icons\\Trade_Mining", color = { 0.98, 0.62, 0.20 } },
    herb = { label = "Herbs", one = "herb spot", many = "herb spots", none = "No herbs recorded",
        icon = "Interface\\Icons\\Trade_Herbalism", color = { 0.35, 0.90, 0.35 } },
    fish = { label = "Fishing", one = "fishing spot", many = "fishing spots", none = "No fishing recorded",
        icon = "Interface\\Icons\\Trade_Fishing", color = { 0.35, 0.65, 1.00 } },
    -- Where a chest has stood. Chests move between a handful of places, so
    -- a recorded spot is somewhere one turns up, not a promise.
    chest = { label = "Chests", one = "chest spot", many = "chest spots", none = "No chests recorded",
        icon = "Interface\\Icons\\INV_Box_02", color = { 0.95, 0.80, 0.45 } },
    -- Where you've killed a mob: only used by a route through those places
    -- (Farming > Mobs), never drawn as recorded spots.
    mob = { label = "Mobs", one = "kill spot", many = "kill spots", none = "No kills recorded",
        icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", color = { 0.90, 0.35, 0.30 } },
}
ns.KIND_ORDER = { "herb", "ore", "fish", "chest" }

-- A spot's own picture: the item it gives (Copper Ore for a Copper Vein,
-- Silverleaf for Silverleaf), so the map shows what's there, not just "a
-- herb". Anything not known here falls back to the kind's picture.
local NODE_ITEM = {
    ["copper vein"] = 2770, ["tin vein"] = 2771, ["iron deposit"] = 2772, ["silver vein"] = 2775,
    ["gold vein"] = 2776, ["mithril deposit"] = 3858, ["truesilver deposit"] = 7911,
    ["small thorium vein"] = 10620, ["rich thorium vein"] = 10620, ["dark iron deposit"] = 11370,
    ["incendicite mineral vein"] = 3340, ["lesser bloodstone deposit"] = 4278, ["indurium mineral vein"] = 5833,
    ["peacebloom"] = 2447, ["silverleaf"] = 765, ["earthroot"] = 2449, ["mageroyal"] = 785, ["briarthorn"] = 2450,
    ["stranglekelp"] = 3820, ["bruiseweed"] = 2453, ["wild steelbloom"] = 3355, ["grave moss"] = 3369,
    ["kingsblood"] = 3356, ["liferoot"] = 3357, ["fadeleaf"] = 3818, ["goldthorn"] = 3821,
    ["khadgar's whisker"] = 3358, ["wintersbite"] = 3819, ["firebloom"] = 4625, ["purple lotus"] = 8831,
    ["arthas' tears"] = 8836, ["sungrass"] = 8838, ["blindweed"] = 8839, ["ghost mushroom"] = 8845,
    ["gromsblood"] = 8846, ["golden sansam"] = 13464, ["dreamfoil"] = 13463, ["mountain silversage"] = 13465,
    ["plaguebloom"] = 13466, ["icecap"] = 13467, ["black lotus"] = 13468,
}
local nodeIcons = {}
function ns.NodeIcon(n)
    local kind = n and ns.KINDS[n.k]
    local fallback = kind and kind.icon or 134400
    local name = n and n.n
    if (n and n.k ~= "ore" and n.k ~= "herb") or type(name) ~= "string" or name == "" then
        return fallback
    end
    local key = name:lower():gsub("^ooze covered ", "")
    local icon = nodeIcons[key]
    if icon == nil then
        local id = NODE_ITEM[key]
        -- WoW Forever's starter herbs have a word in front ("Stunted
        -- Silverleaf", "Wilted Peacebloom"): drop words until one is known.
        local rest = key
        while not id and rest:find(" ") do
            rest = rest:gsub("^%S+%s+", "")
            id = NODE_ITEM[rest]
        end
        if not id and ns.FindItemByName then
            -- WoW Forever's own herbs are named like the herb itself; a new
            -- "X Vein" / "X Deposit" gives "X Ore".
            id = ns.FindItemByName(n.k == "herb" and key
                or (key:gsub("^small ", ""):gsub("^rich ", ""):gsub(" vein$", ""):gsub(" deposit$", "") .. " ore"))
        end
        icon = id and C_Item and ns.try(C_Item.GetItemIconByID, id) or false
        -- An unknown name is looked up again later (the item may be seen by then).
        if icon or id then
            nodeIcons[key] = icon
        end
    end
    return icon or fallback
end

-- What an opened thing has to be called to count as a chest (not a quest
-- crate, a door or a sack of grain).
local CHEST_WORDS = { "chest", "strongbox", "coffer", "footlocker", "trunk" }
local function isChest(name)
    if type(name) ~= "string" then
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
ns.IsChestName = isChest

----------------------------------------------------------------------
-- Where am I?
----------------------------------------------------------------------

function ns.PlayerMapPos(mapID)
    if not C_Map or not C_Map.GetBestMapForUnit then
        return nil
    end
    mapID = mapID or ns.try(C_Map.GetBestMapForUnit, "player")
    if not mapID then
        return nil
    end
    local pos = ns.try(C_Map.GetPlayerMapPosition, mapID, "player")
    if not pos or not pos.GetXY then
        return nil
    end
    local x, y = pos:GetXY()
    if not x or not y or (x == 0 and y == 0) then
        return nil
    end
    return mapID, x, y
end

function ns.MapName(mapID)
    local info = C_Map and ns.try(C_Map.GetMapInfo, mapID)
    return (type(info) == "table" and info.name) or ("Map " .. tostring(mapID))
end

-- Map position -> world position in yards (north, west), when the client
-- can tell us.
local function worldPos(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then
        return nil
    end
    local ok, _, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if ok and pos and pos.GetXY then
        return pos:GetXY()
    end
    return nil
end

----------------------------------------------------------------------
-- Recording nodes
----------------------------------------------------------------------

local spellKind = {}
local function gatherKind(spellID)
    if not spellID then
        return nil
    end
    local known = spellKind[spellID]
    if known ~= nil then
        return known or nil
    end
    local name = C_Spell and ns.try(C_Spell.GetSpellName, spellID)
    local kind = false
    if type(name) == "string" then
        local l = name:lower()
        -- Find Herbs / Find Minerals only switch on minimap tracking: no node.
        if l:find("^find ") or l:find("^track ") then
            kind = false
        elseif l == "mining" or l:find("^mining") then
            kind = "ore"
        elseif l:find("herb") then
            kind = "herb"
        elseif l == "fishing" then
            kind = "fish"
        elseif l == "skinning" then
            kind = "skin"
        elseif l:find("^opening") then
            kind = "open" -- chests, but also doors and quest objects: the target's name decides
        end
    end
    spellKind[spellID] = kind
    return kind or nil
end

-- "ore" | "herb" | "fish" | "skin" | "open" | nil - the loot tracker uses this too.
ns.GatherKind = gatherKind

function ns.RecordNode(kind, name)
    local mapID, x, y = ns.PlayerMapPos()
    if not mapID then
        return
    end
    local nodes = ns.db.nodes
    local list = nodes[mapID]
    if not list then
        list = {}
        nodes[mapID] = list
    end
    -- Fishing "spots" are stretches of water, so they merge over a wider area.
    local radius = (kind == "fish") and 0.02 or 0.008
    for _, n in ipairs(list) do
        if n.k == kind and abs(n.x - x) < radius and abs(n.y - y) < radius then
            n.c = (n.c or 1) + 1
            n.t = time()
            if name and name ~= "" then
                n.n = name
            end
            return
        end
    end
    list[#list + 1] = { x = floor(x * 10000 + 0.5) / 10000, y = floor(y * 10000 + 0.5) / 10000,
        k = kind, n = name, c = 1, t = time() }
    ns.Fire("NODES_UPDATED")
end

local pendingCast
local lastFishCast

ns.On("UNIT_SPELLCAST_SENT", function(unit, target, _, spellID)
    if unit ~= "player" then
        return
    end
    local kind = gatherKind(spellID)
    if kind == "ore" or kind == "herb" then
        pendingCast = { kind = kind, name = target, at = GetTime() }
    elseif kind == "open" and isChest(target) then
        pendingCast = { kind = "chest", name = target, at = GetTime() }
    end
end)

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" or not ns.ready then
        return
    end
    local kind = gatherKind(spellID)
    if kind == "fish" then
        lastFishCast = GetTime()
    end
    if kind == "ore" or kind == "herb" then
        local name
        if pendingCast and pendingCast.kind == kind and GetTime() - pendingCast.at < 20 then
            name = pendingCast.name
        end
        pendingCast = nil
        ns.RecordNode(kind, name)
    elseif kind == "open" then
        -- Only a chest picked out when the cast started counts.
        if pendingCast and pendingCast.kind == "chest" and GetTime() - pendingCast.at < 20 then
            ns.RecordNode("chest", pendingCast.name)
        end
        pendingCast = nil
    end
end)

-- Fishing only counts once something is actually on the hook.
local function onLoot()
    local fishing
    if type(IsFishingLoot) == "function" then
        fishing = ns.try(IsFishingLoot)
    else
        -- No direct answer available: loot that opens within a cast's length
        -- of starting to fish is a catch.
        fishing = lastFishCast and GetTime() - lastFishCast < 32
    end
    if ns.ready and fishing then
        ns.Later("fish-node", 0.2, function()
            ns.RecordNode("fish", "Fishing spot")
        end)
    end
end
ns.On("LOOT_READY", onLoot)
ns.On("LOOT_OPENED", onLoot)

-- Zones with recorded nodes:
-- { {map=, name=, ore=, herb=, fish=, total=, skipped=, last=}, ... }
function ns.NodeZones()
    local out = {}
    for mapID, list in pairs(ns.db.nodes) do
        if #list > 0 then
            local z = { map = mapID, name = ns.MapName(mapID), ore = 0, herb = 0, fish = 0, chest = 0, total = #list,
                skipped = 0, last = 0 }
            for _, n in ipairs(list) do
                z[n.k] = (z[n.k] or 0) + 1
                if n.skip then
                    z.skipped = z.skipped + 1
                end
                if (n.t or 0) > z.last then
                    z.last = n.t
                end
            end
            out[#out + 1] = z
        end
    end
    table.sort(out, function(a, b)
        if a.total ~= b.total then
            return a.total > b.total
        end
        return a.name < b.name
    end)
    return out
end

-- The continent a zone is on ({ id =, name = }), or nil.
local continents = {}
function ns.ContinentOf(mapID)
    local c = continents[mapID]
    if c ~= nil then
        return c or nil
    end
    c = false
    local continentType = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
    local id = mapID
    for _ = 1, 8 do
        local info = id and C_Map and ns.try(C_Map.GetMapInfo, id)
        if type(info) ~= "table" then
            break
        end
        if info.mapType == continentType then
            c = { id = id, name = info.name or ("Map " .. id) }
            break
        end
        id = info.parentMapID
        if not id or id == 0 then
            break
        end
    end
    continents[mapID] = c
    return c or nil
end

-- "19 herb spots · No ore recorded"
function ns.ZoneSummary(z)
    local parts = {}
    for _, k in ipairs(ns.KIND_ORDER) do
        local n = z[k] or 0
        if n > 0 then
            parts[#parts + 1] = n .. " " .. (n == 1 and ns.KINDS[k].one or ns.KINDS[k].many)
        end
    end
    -- Mention a missing herb/ore kind, since those are the two people pair up.
    if (z.herb or 0) == 0 and (z.ore or 0) > 0 then
        parts[#parts + 1] = ns.KINDS.herb.none
    elseif (z.ore or 0) == 0 and (z.herb or 0) > 0 then
        parts[#parts + 1] = ns.KINDS.ore.none
    end
    return table.concat(parts, " · ")
end

function ns.ForgetZone(mapID)
    ns.db.nodes[mapID] = nil
    ns.db.routes[mapID] = nil
    if ns.route and ns.route.map == mapID then
        ns.StopRoute()
    end
    ns.Fire("NODES_UPDATED")
end

-- Leave an awkward spot out of routes (or put it back). Kept between sessions.
function ns.SetNodeSkipped(node, skip)
    node.skip = skip and true or nil
    ns.Fire("NODES_UPDATED")
end

function ns.IncludeAllNodes(mapID)
    for _, n in ipairs(ns.db.nodes[mapID] or {}) do
        n.skip = nil
    end
    ns.Fire("NODES_UPDATED")
end

-- Spots in a zone that a route with these kinds would use.
function ns.MatchingNodes(mapID, kinds)
    local out, skipped = {}, 0
    for _, n in ipairs(ns.db.nodes[mapID] or {}) do
        if kinds[n.k] then
            if n.skip then
                skipped = skipped + 1
            else
                out[#out + 1] = n
            end
        end
    end
    return out, skipped
end

----------------------------------------------------------------------
-- Building a route
--
-- "Visit every spot once and come back to the start, walking as little as
-- possible." Start by always walking to the nearest unvisited spot, then
-- repeatedly untangle any two legs that cross (the classic 2-opt trick).
-- Map coordinates are squashed (maps are 1.5 times wider than tall), so x
-- distances are stretched to match.
----------------------------------------------------------------------

local ASPECT = 1.5
local MAX_STOPS = 300

local function dist(a, b)
    local dx, dy = (a.x - b.x) * ASPECT, a.y - b.y
    return sqrt(dx * dx + dy * dy)
end

-- Works out a loop without starting it (the Routes page previews this).
-- start: a node to begin at; otherwise the stop nearest you.
function ns.PlanRoute(mapID, kinds, start)
    local pts = ns.MatchingNodes(mapID, kinds)
    if #pts < 2 then
        return nil, "I need at least two recorded spots of that kind in this zone."
    end
    return ns.PlanRouteThrough(mapID, pts, kinds, start)
end

-- The same loop through any list of points ({ x =, y =, k =, n = }).
function ns.PlanRouteThrough(mapID, pts, kinds, start)
    if #pts < 2 then
        return nil, "I need at least two spots for a loop."
    end
    if #pts > MAX_STOPS then
        table.sort(pts, function(a, b) return (a.c or 1) > (b.c or 1) end)
        for i = #pts, MAX_STOPS + 1, -1 do
            pts[i] = nil
        end
    end

    -- Nearest-neighbour tour, starting from the spot closest to the player.
    local n = #pts
    local _, px, py = ns.PlayerMapPos(mapID)
    local here = { x = px or pts[1].x, y = py or pts[1].y }
    local used, tour = {}, {}
    local cur = here
    for step = 1, n do
        local best, bestD
        for i = 1, n do
            if not used[i] then
                local d = dist(cur, pts[i])
                if not bestD or d < bestD then
                    best, bestD = i, d
                end
            end
        end
        used[best] = true
        tour[step] = pts[best]
        cur = pts[best]
    end

    -- 2-opt: reverse a stretch whenever that makes the loop shorter.
    local improved, passes = true, 0
    while improved and passes < 8 do
        improved = false
        passes = passes + 1
        for i = 1, n - 1 do
            for j = i + 1, n do
                local a, b = tour[i], tour[i + 1]
                local c, d = tour[j], tour[(j % n) + 1]
                if a ~= d and b ~= c then
                    local delta = dist(a, c) + dist(b, d) - dist(a, b) - dist(c, d)
                    if delta < -1e-7 then
                        local lo, hi = i + 1, j
                        while lo < hi do
                            tour[lo], tour[hi] = tour[hi], tour[lo]
                            lo, hi = lo + 1, hi - 1
                        end
                        improved = true
                    end
                end
            end
        end
    end

    -- Begin at the stop you picked, or else the one nearest you.
    local first, firstD = 1, nil
    for i = 1, n do
        if start and tour[i] == start then
            first, firstD = i, -1
            break
        end
        local d = dist(here, tour[i])
        if not firstD or d < firstD then
            first, firstD = i, d
        end
    end

    -- Straight-line length, in map units and (when the game can convert)
    -- in yards.
    local length, yards = 0, 0
    for i = 1, n do
        local a, b = tour[i], tour[(i % n) + 1]
        length = length + dist(a, b)
        if yards then
            local an, aw = worldPos(mapID, a.x, a.y)
            local bn, bw = worldPos(mapID, b.x, b.y)
            if an and bn then
                yards = yards + sqrt((an - bn) ^ 2 + (aw - bw) ^ 2)
            else
                yards = nil
            end
        end
    end
    if yards and yards <= 0 then
        yards = nil
    end

    local copy = {}
    for k, v in pairs(kinds) do
        copy[k] = v
    end
    return { map = mapID, pts = tour, i = first, first = first, n = n, kinds = copy, length = length,
        yards = yards, visited = 0 }
end

-- Follow a planned loop: the arrow, the map pin and the progress count.
function ns.StartRoute(plan)
    if not plan then
        return nil
    end
    if ns.route then
        ns.StopRoute()
    end
    plan.i, plan.visited, plan.paused = plan.first or plan.i or 1, 0, nil
    if ns.Beam then
        ns.Beam.own = nil -- the route's pin replaces the nearest-spot one
    end
    ns.route = plan
    ns.SetRouteWaypoint()
    ns.Fire("ROUTE")
    return ns.route
end

function ns.BuildRoute(mapID, kinds, start)
    local plan, why = ns.PlanRoute(mapID, kinds, start)
    if not plan then
        return nil, why
    end
    return ns.StartRoute(plan)
end

-- Pausing keeps your place but stops the arrow and the auto-advance.
function ns.PauseRoute(paused)
    local r = ns.route
    if not r then
        return
    end
    r.paused = paused and true or nil
    if paused then
        if r.usedWaypoint and C_Map and C_Map.ClearUserWaypoint then
            pcall(C_Map.ClearUserWaypoint)
        end
    else
        ns.SetRouteWaypoint()
    end
    ns.Fire("ROUTE")
end

-- Which stop you're on, counting from where you started: 1..n, plus laps.
function ns.RouteProgress(r)
    r = r or ns.route
    if not r then
        return nil
    end
    local v = r.visited or 0
    return (v % r.n) + 1, r.n, floor(v / r.n) + 1
end

-- Remember what to include and where to start for this zone.
function ns.SaveRoute(mapID, kinds, start)
    local copy = {}
    for k, v in pairs(kinds) do
        copy[k] = v and true or nil
    end
    ns.db.routes[mapID] = { kinds = copy, start = start and { x = start.x, y = start.y } or nil, at = time() }
    ns.Fire("NODES_UPDATED")
end

-- The node a saved start position points at, if it's still recorded.
function ns.SavedStart(mapID)
    local saved = ns.db.routes[mapID]
    if not (saved and saved.start) then
        return nil
    end
    for _, n in ipairs(ns.db.nodes[mapID] or {}) do
        if abs(n.x - saved.start.x) < 1e-4 and abs(n.y - saved.start.y) < 1e-4 then
            return n
        end
    end
    return nil
end

----------------------------------------------------------------------
-- Following a route
----------------------------------------------------------------------

-- Puts the game's map pin on a spot and tracks it. Returns true if it worked.
function ns.SetWaypoint(map, x, y)
    if not (map and x and y and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
        return false
    end
    if C_Map.CanSetUserWaypointOnMap and not ns.try(C_Map.CanSetUserWaypointOnMap, map) then
        return false
    end
    return pcall(function()
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x, y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    end) and true or false
end

function ns.SetRouteWaypoint()
    local r = ns.route
    if not r or r.paused or not ns.db.opts.waypoint then
        return
    end
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
        return
    end
    if C_Map.CanSetUserWaypointOnMap and not ns.try(C_Map.CanSetUserWaypointOnMap, r.map) then
        return
    end
    local pt = r.pts[r.i]
    local ok = pcall(function()
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(r.map, pt.x, pt.y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    end)
    r.usedWaypoint = r.usedWaypoint or ok
end

function ns.NextStop()
    local r = ns.route
    if not r then
        return
    end
    r.i = (r.i % r.n) + 1
    r.visited = (r.visited or 0) + 1
    ns.SetRouteWaypoint()
    ns.Fire("ROUTE")
end

function ns.StopRoute()
    local r = ns.route
    if not r then
        return
    end
    if r.usedWaypoint and C_Map and C_Map.ClearUserWaypoint then
        pcall(C_Map.ClearUserWaypoint)
    end
    ns.route = nil
    ns.Fire("ROUTE")
end

-- Everything the on-screen guide needs, worked out fresh each time.
-- Returns nil when there's no route; otherwise a table:
--   name, index, count, onMap, yards (may be nil), angle (radians to turn
--   left from straight ahead; may be nil)
local ARRIVE_YARDS = 28
local ARRIVE_MAP = 0.006

function ns.RouteStatus(hops)
    hops = hops or 0
    local r = ns.route
    if not r then
        return nil
    end
    local pt = r.pts[r.i]
    local kindInfo = ns.KINDS[pt.k]
    local step, _, lap = ns.RouteProgress(r)
    local st = { name = pt.n or (kindInfo and kindInfo.label) or "Next spot", index = r.i, count = r.n,
        step = step, lap = lap, paused = r.paused, zone = ns.MapName(r.map) }
    if r.paused then
        return st
    end
    local _, px, py = ns.PlayerMapPos(r.map)
    if not px then
        st.onMap = false
        return st
    end
    st.onMap = true
    local facing = ns.try(GetPlayerFacing)
    local pn, pw = worldPos(r.map, px, py)
    local tn, tw = worldPos(r.map, pt.x, pt.y)
    local arrived
    if pn and tn then
        local dn, dw = tn - pn, tw - pw
        st.yards = sqrt(dn * dn + dw * dw)
        if facing then
            st.angle = math.atan2(dw, dn) - facing
        end
        arrived = st.yards < ARRIVE_YARDS
    else
        -- No yard conversion available: work in map units instead.
        local dx, dy = (pt.x - px) * ASPECT, pt.y - py
        if facing then
            st.angle = math.atan2(-dx, -dy) - facing
        end
        arrived = sqrt(dx * dx + dy * dy) < ARRIVE_MAP
    end
    -- (hops stops this going round forever when every stop is within reach.)
    if arrived and hops < r.n then
        ns.NextStop()
        return ns.RouteStatus(hops + 1)
    end
    return st
end

----------------------------------------------------------------------
-- Drawing nodes and the route on any frame (the world map, and the little
-- map inside the Forever Gold window)
----------------------------------------------------------------------

local PLAYER_ARROW = "Interface\\Minimap\\MinimapArrow"
local CROSS = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7"

-- parent: the frame to draw on. Layers, bottom to top: the zone's own map
-- picture (optional), the route, the spots, then you.
-- Spot icons are item pictures, square with their own dark background:
-- cut them round so only the ore or herb itself shows, with a thin dark
-- rim to keep them readable on the map. Clients without masks get the
-- picture as it is, with nothing behind it.
local ROUND_MASK = "Interface/CharacterFrame/TempPortraitAlphaMask"

local function roundOff(owner, tex)
    if type(owner.CreateMaskTexture) ~= "function" or type(tex.AddMaskTexture) ~= "function" then
        return false
    end
    local ok, mask = pcall(owner.CreateMaskTexture, owner)
    if not ok or type(mask) ~= "table" then
        return false
    end
    mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    return pcall(tex.AddMaskTexture, tex, mask) and true or false
end

-- A spot icon: the picture, cut round, on a thin dark rim (or bare).
local function spotIcon(owner, icon, rim)
    local round = roundOff(owner, icon)
    if rim then
        if round and roundOff(owner, rim) then
            rim:SetColorTexture(0, 0, 0, 0.8)
        else
            rim:Hide()
            rim.off = true
        end
    end
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    return round
end
ns.SpotIcon = spotIcon

-- What a spot is, for a tooltip: its name, then what it is and how often
-- you've gathered there.
function ns.SpotTooltip(owner, n, extra)
    if not GameTooltip or not n then
        return
    end
    local kind = ns.KINDS[n.k]
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(n.n or (kind and kind.label) or "Spot", 1, 0.82, 0)
    local times = n.c or 1
    GameTooltip:AddLine((kind and kind.one or "spot") .. " - gathered " .. times .. (times == 1 and " time" or " times")
        .. (n.t and ns.Ago and (", last " .. ns.Ago(n.t)) or ""), 0.8, 0.8, 0.8)
    if n.skip then
        GameTooltip:AddLine("Left out of routes.", 1, 0.45, 0.45)
    end
    if extra then
        GameTooltip:AddLine(extra, 1, 0.85, 0.2)
    end
    GameTooltip:Show()
end

-- Hovering shows a tooltip, but clicks go through to the map underneath.
local function hoverOnly(f)
    if type(f.SetMouseClickEnabled) == "function" and type(f.SetMouseMotionEnabled) == "function" then
        f:EnableMouse(true)
        f:SetMouseClickEnabled(false)
        f:SetMouseMotionEnabled(true)
        return true
    end
    return false
end

function ns.NewPlotter(parent)
    local plot = { parent = parent, tiles = {}, lines = {}, marks = {}, usedLines = 0, usedMarks = 0 }

    local art = CreateFrame("Frame", nil, parent)
    art:SetAllPoints(parent)
    art:SetClipsChildren(true)
    local shade = art:CreateTexture(nil, "OVERLAY")
    shade:SetAllPoints(art)
    shade:SetColorTexture(0, 0, 0, 0.38)
    shade:Hide()
    plot.art, plot.shade = art, shade

    local lineFrame = CreateFrame("Frame", nil, parent)
    lineFrame:SetAllPoints(parent)
    plot.lineFrame = lineFrame

    local markFrame = CreateFrame("Frame", nil, parent)
    markFrame:SetAllPoints(parent)
    plot.markFrame = markFrame

    local you = CreateFrame("Frame", nil, parent)
    you:SetSize(22, 22)
    you.tex = you:CreateTexture(nil, "OVERLAY")
    you.tex:SetAllPoints(you)
    you.tex:SetTexture(PLAYER_ARROW)
    you:Hide()
    plot.you = you

    local function tileTex(self, i, sub)
        local t = self.tiles[i]
        if not t then
            t = art:CreateTexture(nil, "BACKGROUND")
            self.tiles[i] = t
        end
        t:SetDrawLayer("BACKGROUND", sub)
        return t
    end

    -- One explored-area picture: w x h pixels at x, y on the zone art, cut
    -- into tiles of up to tw x th (the last row and column are partial and
    -- sit at the top left of a power-of-two file). Returns tiles used.
    local function drawPiece(self, used, piece, tw, th, sx, sy, sub)
        local across, down = math.ceil(piece.w / tw), math.ceil(piece.h / th)
        for j = 1, down do
            local ph, fh = th, th
            if j == down then
                ph = piece.h % th
                if ph == 0 then ph = th end
                fh = 16
                while fh < ph do fh = fh * 2 end
            end
            for k = 1, across do
                local file = piece.files[(j - 1) * across + k]
                if file then
                    local pw, fw = tw, tw
                    if k == across then
                        pw = piece.w % tw
                        if pw == 0 then pw = tw end
                        fw = 16
                        while fw < pw do fw = fw * 2 end
                    end
                    used = used + 1
                    local t = tileTex(self, used, sub)
                    t:SetTexture(file)
                    t:SetTexCoord(0, pw / fw, 0, ph / fh)
                    t:SetSize(pw * sx, ph * sy)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", art, "TOPLEFT", (piece.x + tw * (k - 1)) * sx, -(piece.y + th * (j - 1)) * sy)
                    t:Show()
                end
            end
        end
        return used
    end

    -- The areas drawn over the bare parchment: the ones you've explored (the
    -- game tells us), plus, unless switched off, the rest of the zone.
    local function pieces(mapID)
        local out, seen = {}, {}
        local explored = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures
            and ns.try(C_MapExplorationInfo.GetExploredMapTextures, mapID)
        for _, e in ipairs(type(explored) == "table" and explored or {}) do
            if not e.isShownByMouseOver and type(e.fileDataIDs) == "table" then
                local key = (e.textureWidth or 0) .. ":" .. (e.textureHeight or 0) .. ":" .. (e.offsetX or 0) .. ":" .. (e.offsetY or 0)
                seen[key] = true
                out[#out + 1] = { w = e.textureWidth or 0, h = e.textureHeight or 0, x = e.offsetX or 0, y = e.offsetY or 0,
                    files = e.fileDataIDs, top = e.isDrawOnTopLayer }
            end
        end
        if ns.db.opts.revealMap ~= false and ns.MAP_REVEAL and C_Map.GetMapArtID then
            local artID = ns.try(C_Map.GetMapArtID, mapID)
            for key, list in pairs(artID and ns.MAP_REVEAL[artID] or {}) do
                if not seen[key] then
                    local w, h, x, y = key:match("^(%d+):(%d+):(%d+):(%d+)$")
                    if w then
                        local files = {}
                        for id in list:gmatch("%d+") do
                            files[#files + 1] = tonumber(id)
                        end
                        out[#out + 1] = { w = tonumber(w), h = tonumber(h), x = tonumber(x), y = tonumber(y), files = files }
                    end
                end
            end
        end
        return out
    end

    -- The zone's map picture, made of the same tiles the world map uses.
    -- Returns "ok", "loading" or "none".
    function plot:Art(mapID, w, h)
        local version = (ns.mapArtVersion or 0) .. tostring(ns.db.opts.revealMap ~= false)
        if self.artMap == mapID and self.artW == w and self.artH == h and self.artVersion == version then
            return self:ArtState()
        end
        self.artMap, self.artW, self.artH, self.artOK, self.artVersion = mapID, w, h, false, version
        for _, t in ipairs(self.tiles) do
            t:Hide()
        end
        shade:Hide()
        local layers = mapID and C_Map and C_Map.GetMapArtLayers and ns.try(C_Map.GetMapArtLayers, mapID)
        local L = type(layers) == "table" and layers[1]
        local textures = L and C_Map.GetMapArtLayerTextures and ns.try(C_Map.GetMapArtLayerTextures, mapID, 1)
        if not (L and type(textures) == "table" and #textures > 0 and (L.layerWidth or 0) > 0 and (L.layerHeight or 0) > 0
            and (L.tileWidth or 0) > 0 and (L.tileHeight or 0) > 0) then
            return "none"
        end
        local sx, sy = w / L.layerWidth, h / L.layerHeight
        local cols = math.ceil(L.layerWidth / L.tileWidth)
        local rows = math.ceil(L.layerHeight / L.tileHeight)
        local used = 0
        for row = 1, rows do
            for col = 1, cols do
                local file = textures[(row - 1) * cols + col]
                if file then
                    used = used + 1
                    local t = tileTex(self, used, 0)
                    local x0, y0 = (col - 1) * L.tileWidth, (row - 1) * L.tileHeight
                    -- The last tiles hang past the map's edge: show only the part on it.
                    local fw = math.min(1, (L.layerWidth - x0) / L.tileWidth)
                    local fh = math.min(1, (L.layerHeight - y0) / L.tileHeight)
                    t:SetTexture(file)
                    t:SetTexCoord(0, fw, 0, fh)
                    t:SetSize(L.tileWidth * fw * sx, L.tileHeight * fh * sy)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", art, "TOPLEFT", x0 * sx, -y0 * sy)
                    t:Show()
                end
            end
        end
        local base = used
        for _, piece in ipairs(pieces(mapID)) do
            used = drawPiece(self, used, piece, L.tileWidth, L.tileHeight, sx, sy, piece.top and 2 or 1)
        end
        self.pieceTiles = used - base
        self.usedTiles = used
        self.artOK = used > 0
        shade:SetShown(self.artOK)
        return self:ArtState()
    end

    function plot:ArtState()
        if not self.artOK then
            return "none"
        end
        for i = 1, self.usedTiles or 0 do
            local t = self.tiles[i]
            if t.IsObjectLoaded and t:IsObjectLoaded() == false then
                return "loading"
            end
        end
        return "ok"
    end

    function plot:Line(sub)
        self.usedLines = self.usedLines + 1
        local l = self.lines[self.usedLines]
        if not l then
            l = lineFrame:CreateLine(nil, "ARTWORK")
            self.lines[self.usedLines] = l
        end
        l:SetDrawLayer("ARTWORK", sub or 0)
        l:Show()
        return l
    end

    function plot:Mark()
        self.usedMarks = self.usedMarks + 1
        local m = self.marks[self.usedMarks]
        if not m then
            m = CreateFrame("Button", nil, markFrame)
            m.ring = m:CreateTexture(nil, "BACKGROUND")
            m.ring:SetPoint("CENTER")
            m.back = m:CreateTexture(nil, "BORDER")
            m.back:SetPoint("CENTER")
            m.icon = m:CreateTexture(nil, "ARTWORK")
            m.icon:SetPoint("CENTER")
            m.round = spotIcon(m, m.icon, m.back)
            if m.round then
                roundOff(m, m.ring)
            end
            m.cross = m:CreateTexture(nil, "OVERLAY")
            m.cross:SetPoint("CENTER")
            m.cross:SetTexture(CROSS)
            m.tag = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            m.tag:SetPoint("BOTTOM", m, "TOP", 0, 1)
            if m.RegisterForClicks then
                m:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            end
            m:SetScript("OnClick", function(self, button)
                if plot.onClick and self.node then
                    plot.onClick(self.node, button)
                end
            end)
            m:SetScript("OnEnter", function(self)
                if plot.onEnter and self.node then
                    plot.onEnter(self, self.node)
                elseif self.node then
                    ns.SpotTooltip(self, self.node, self.tagText)
                end
            end)
            m:SetScript("OnLeave", function()
                if GameTooltip then
                    GameTooltip:Hide()
                end
            end)
            self.marks[self.usedMarks] = m
        end
        m:Show()
        return m
    end

    function plot:Clear()
        for i = 1, #self.lines do self.lines[i]:Hide() end
        for i = 1, #self.marks do self.marks[i]:Hide() end
        self.usedLines, self.usedMarks = 0, 0
        you:Hide()
    end

    -- A leg of the route: a dark outline under a gold line, with a small
    -- chevron halfway along showing which way to walk.
    -- (ax, ay) to (bx, by) in pixels from the top left. unit: how big one
    -- screen pixel is here (the world map's canvas is zoomed).
    function plot:Leg(ax, ay, bx, by, thick, unit)
        unit = unit or 1
        local under = self:Line(0)
        under:SetColorTexture(0, 0, 0, 0.85)
        under:SetThickness(thick + 2.5 * unit)
        under:SetStartPoint("TOPLEFT", lineFrame, ax, -ay)
        under:SetEndPoint("TOPLEFT", lineFrame, bx, -by)
        local over = self:Line(2)
        over:SetColorTexture(1, 0.82, 0.1, 0.95)
        over:SetThickness(thick)
        over:SetStartPoint("TOPLEFT", lineFrame, ax, -ay)
        over:SetEndPoint("TOPLEFT", lineFrame, bx, -by)
        local dx, dy = bx - ax, by - ay
        local len = sqrt(dx * dx + dy * dy)
        if len < 34 * unit then
            return
        end
        local ux, uy = dx / len, dy / len
        local mx, my = ax + dx * 0.5 + ux * 3 * unit, ay + dy * 0.5 + uy * 3 * unit
        for _, side in ipairs({ 1, -1 }) do
            local wx = mx - ux * 6 * unit + (-uy) * 4 * unit * side
            local wy = my - uy * 6 * unit + ux * 4 * unit * side
            local c = self:Line(3)
            c:SetColorTexture(0.1, 0.07, 0, 1)
            c:SetThickness(2 * unit)
            c:SetStartPoint("TOPLEFT", lineFrame, mx, -my)
            c:SetEndPoint("TOPLEFT", lineFrame, wx, -wy)
        end
    end

    -- o: { kinds = {ore=true,...} or nil for all, route = a plan or the
    -- running route, player = true to draw you, size = marker size,
    -- art = true to draw the zone map underneath, interactive = true,
    -- onClick = function(node, button), onEnter = function(marker, node),
    -- maps = { other zones whose spots to draw too }, project =
    -- function(zoneMapID, x, y) -> x, y on this map (nil: not on it),
    -- unit = how big a screen pixel is here }
    -- Returns { art = "ok"|"loading"|"none"|"off", shown = spots drawn }
    function plot:Draw(mapID, w, h, o)
        o = o or {}
        self:Clear()
        self.onClick, self.onEnter = o.onClick, o.onEnter
        -- Siblings on the same level draw in any order: stack them.
        local base = parent:GetFrameLevel() or 1
        art:SetFrameLevel(base + 1)
        lineFrame:SetFrameLevel(base + 2)
        markFrame:SetFrameLevel(base + 3)
        local info = { art = "off", shown = 0 }
        if not mapID or not w or w <= 0 or not h or h <= 0 then
            return info
        end
        if o.art then
            info.art = self:Art(mapID, w, h)
        end
        local size = o.size or 12
        local unit = o.unit or 1
        local project = o.project or function(m, x, y)
            if m == mapID then
                return x, y
            end
        end
        local maps = o.maps or { mapID }
        local r = o.route
        local special = {}
        if r then
            local ps = {}
            for i = 1, r.n do
                local x, y = project(r.map, r.pts[i].x, r.pts[i].y)
                if not x then
                    ps = nil
                    break
                end
                ps[i] = { x * w, y * h }
            end
            if ps then
                for i = 1, r.n do
                    local a, b = ps[i], ps[(i % r.n) + 1]
                    self:Leg(a[1], a[2], b[1], b[2], math.max(1.5 * unit, size * 0.18), unit)
                end
                local pt = r.pts[r.i]
                if pt then
                    special[pt] = ns.route == r and (r.paused and "Paused" or "Next") or "Start"
                end
            end
        end
        for _, zone in ipairs(maps) do
          for _, n in ipairs(ns.db.nodes[zone] or {}) do
            local cx, cy
            if not o.kinds or o.kinds[n.k] then
                cx, cy = project(zone, n.x, n.y)
            end
            if cx then
                local m = self:Mark()
                m.node = n
                local tag = special[n]
                local s = tag and math.floor(size * 1.35) or size
                m:SetSize(s + 4 * unit, s + 4 * unit)
                m.back:SetSize(s + 2 * unit, s + 2 * unit)
                m.icon:SetSize(s, s)
                m.icon:SetTexture(ns.NodeIcon(n))
                m.tagText = tag == "Next" and "Next stop on your route" or tag == "Paused" and "Next stop (route paused)"
                    or tag == "Start" and "Where the route starts" or nil
                if tag then
                    m.ring:SetSize(s + 8 * unit, s + 8 * unit)
                    m.ring:SetColorTexture(1, 0.85, 0.2, 1)
                    m.ring:Show()
                    m.tag:SetText(tag)
                    m.tag:Show()
                else
                    m.ring:Hide()
                    m.tag:Hide()
                end
                local skipped = n.skip and true or false
                if m.icon.SetDesaturated then
                    m.icon:SetDesaturated(skipped)
                end
                m.icon:SetAlpha(skipped and 0.45 or 1)
                m.cross:SetSize(s * 0.8, s * 0.8)
                m.cross:SetShown(skipped)
                if o.interactive then
                    m:EnableMouse(true)
                    if m.SetMouseClickEnabled then
                        m:SetMouseClickEnabled(true)
                    end
                elseif not (o.hover and hoverOnly(m)) then
                    m:EnableMouse(false)
                end
                m:SetFrameLevel(markFrame:GetFrameLevel() + (tag and 3 or 1))
                m:ClearAllPoints()
                m:SetPoint("CENTER", markFrame, "TOPLEFT", cx * w, -cy * h)
                if m.tag.SetScale then
                    m.tag:SetScale(unit)
                end
                info.shown = info.shown + 1
            end
          end
        end
        self.player = o.player and { mapID = mapID, w = w, h = h } or nil
        self:UpdatePlayer()
        return info
    end

    -- Just you: cheap enough to run several times a second.
    function plot:UpdatePlayer()
        local p = self.player
        if not p then
            you:Hide()
            return false
        end
        local _, x, y = ns.PlayerMapPos(p.mapID)
        if not x or x < 0 or x > 1 or y < 0 or y > 1 then
            you:Hide()
            return false
        end
        you:ClearAllPoints()
        you:SetPoint("CENTER", parent, "TOPLEFT", x * p.w, -y * p.h)
        local facing = ns.try(GetPlayerFacing)
        if facing and you.tex.SetRotation then
            you.tex:SetRotation(facing)
        end
        you:SetFrameLevel(markFrame:GetFrameLevel() + 6)
        you:Show()
        return true
    end

    return plot
end

----------------------------------------------------------------------
-- World map overlay
----------------------------------------------------------------------

-- Your spots and the route on the game's world map: on a zone, on its
-- continent, and on OpenMap's stitched map of the whole world when that's up.
-- Pins keep the same size on screen however far you zoom.

local mapOverlay, mapPlot
local drawnScale

local function openMap()
    local api = rawget(_G, "OpenMapAPI")
    return type(api) == "table" and api or nil
end

-- A function placing a zone's 0..1 position on the map being shown, or nil
-- for zones that aren't on it.
local function projection(shown)
    local api = openMap()
    if api and api.IsStitched and api.IsStitched() then
        return function(m, x, y)
            local u, v = api.WorldFromMap(m, x, y)
            if not u then
                return nil
            end
            return api.MapFromWorld(shown, u, v)
        end
    end
    local rects = {}
    return function(m, x, y)
        if m == shown then
            return x, y
        end
        local r = rects[m]
        if r == nil then
            r = false
            if C_Map and C_Map.GetMapRectOnMap then
                local ok, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, m, shown)
                if ok and left and right and top and bottom and right > left and bottom > top then
                    r = { left, right, top, bottom }
                end
            end
            rects[m] = r
        end
        if not r then
            return nil
        end
        return r[1] + x * (r[2] - r[1]), r[3] + y * (r[4] - r[3])
    end
end

local function canvasScale()
    local s = WorldMapFrame.GetCanvasScale and ns.try(WorldMapFrame.GetCanvasScale, WorldMapFrame)
    return (type(s) == "number" and s > 0) and s or 1
end

local function redrawWorldMap()
    if not mapOverlay or not WorldMapFrame or not WorldMapFrame:IsShown() then
        return
    end
    if ns.UpdateMapButton then
        ns.Guard("map-button", ns.UpdateMapButton)()
    end
    if ns.db.opts.worldMapSpots == false then
        mapPlot:Clear()
        return
    end
    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local canvas = WorldMapFrame:GetCanvas()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local api = openMap()
    local level = canvas:GetFrameLevel() + 400
    if api and api.ArtTopLevel then
        level = math.max(level, (ns.try(api.ArtTopLevel) or 0) + 5)
    end
    mapOverlay:SetFrameLevel(level)
    local maps = {}
    for zone, list in pairs(ns.db.nodes) do
        if #list > 0 then
            maps[#maps + 1] = zone
        end
    end
    local scale = canvasScale()
    drawnScale = scale
    local unit = 1 / scale
    local opts = ns.db.opts
    mapPlot:Draw(mapID, w, h, { size = 15 * unit, unit = unit, maps = maps, project = projection(mapID), hover = true,
        kinds = ns.MapKinds(), route = opts.mapRoute ~= false and ns.route or nil })
end

-- Which kinds of spot the world map shows (nil: all of them): the ones
-- ticked, and only those this character has the profession for.
function ns.MapKinds()
    local off = ns.db.opts.mapKinds
    off = type(off) == "table" and off or {}
    local on, all = {}, true
    for _, k in ipairs(ns.KIND_ORDER) do
        if off[k] ~= false and ns.CanGather(k) then
            on[k] = true
        else
            all = false
        end
    end
    return (not all) and on or nil
end

-- Whether a spot of this kind is shown to you at all (map, minimap, beams).
local function shownKind(kind)
    return ns.CanGather(kind)
end

function ns.MapKindOn(kind)
    local off = ns.db.opts.mapKinds
    return not (type(off) == "table" and off[kind] == false)
end

function ns.SetMapKind(kind, on)
    local opts = ns.db.opts
    if type(opts.mapKinds) ~= "table" then
        opts.mapKinds = {}
    end
    if on then
        opts.mapKinds[kind] = nil
    else
        opts.mapKinds[kind] = false
    end
    ns.RedrawWorldMap()
    if ns.RefreshMapButton then
        ns.RefreshMapButton()
    end
end

function ns.SetMapSpots(on)
    ns.db.opts.worldMapSpots = on and true or false
    ns.RedrawWorldMap()
    if ns.RefreshMapButton then
        ns.RefreshMapButton()
    end
end
ns.RedrawWorldMap = function() ns.Guard("worldmap", redrawWorldMap)() end
ns.WorldMapPlot = function() return mapPlot end

local function setupWorldMap()
    if mapOverlay or not WorldMapFrame or not WorldMapFrame.GetCanvas then
        return
    end
    local ok = pcall(function()
        local canvas = WorldMapFrame:GetCanvas()
        mapOverlay = CreateFrame("Frame", nil, canvas)
        mapOverlay:SetAllPoints(canvas)
        mapOverlay:SetFrameLevel(canvas:GetFrameLevel() + 400)
        mapPlot = ns.NewPlotter(mapOverlay)
        if WorldMapFrame.OnMapChanged then
            hooksecurefunc(WorldMapFrame, "OnMapChanged", ns.RedrawWorldMap)
        end
        WorldMapFrame:HookScript("OnShow", ns.RedrawWorldMap)
        -- Zooming changes the canvas scale: redraw so pins stay one size.
        local since = 0
        mapOverlay:SetScript("OnUpdate", function(_, elapsed)
            since = since + elapsed
            if since < 0.2 then
                return
            end
            since = 0
            if drawnScale and math.abs(canvasScale() - drawnScale) > drawnScale * 0.02 then
                ns.RedrawWorldMap()
            end
        end)
    end)
    if not ok then
        mapOverlay = nil
    end
end

----------------------------------------------------------------------
-- The map's gathering button
--
-- A small button on the world map (OpenMap's or the game's), top right,
-- left of whatever buttons the game keeps in that corner. Click: a little
-- menu to show or hide the spots, each kind, the route line and the
-- minimap's spots. Right-click: everything on or off at once.
----------------------------------------------------------------------

local MAP_KIND_LABELS_T = { herb = "Herbs", ore = "Ore", fish = "Fishing pools", chest = "Chests" }

local mapButton, mapMenu

local function mapContainer()
    if not WorldMapFrame then
        return nil
    end
    local sc = rawget(WorldMapFrame, "ScrollContainer")
    if type(sc) ~= "table" and WorldMapFrame.GetCanvasContainer then
        sc = ns.try(WorldMapFrame.GetCanvasContainer, WorldMapFrame)
    end
    return type(sc) == "table" and sc or WorldMapFrame
end

-- The column of round map buttons other addons (Questie, RareScanner...) add
-- through Krowi_WorldMapButtons: in Forever it runs down the map's top left,
-- one button every 32 pixels from the canvas container's corner.
local KROWI_STEP = 32
local function krowiColumn()
    local lib = LibStub and LibStub.GetLibrary and LibStub:GetLibrary("Krowi_WorldMapButtons-1.4", true)
    if type(lib) ~= "table" or type(lib.Buttons) ~= "table" or lib.AnchorPoint ~= "TOPLEFT" then
        return nil
    end
    local shown = 0
    for _, b in ipairs(lib.Buttons) do
        if b ~= mapButton and b.IsShown and b:IsShown() then
            shown = shown + 1
        end
    end
    if shown == 0 then
        return nil
    end
    return lib, shown
end

local krowiHooked
local function hookKrowi(lib)
    if krowiHooked or not hooksecurefunc or type(lib.SetPoints) ~= "function" then
        return
    end
    krowiHooked = true
    hooksecurefunc(lib, "SetPoints", function()
        if ns.PlaceMapButton then
            ns.Guard("map-button", ns.PlaceMapButton)()
        end
    end)
end

-- Under the other addons' round buttons on the left when they are there,
-- otherwise top right, left of the game's own buttons in that corner.
local function placeMapButton()
    local sc = mapContainer()
    if not mapButton or not sc then
        return
    end
    local lib, shown = krowiColumn()
    if lib then
        hookKrowi(lib)
        local rel = WorldMapFrame.GetCanvasContainer and ns.try(WorldMapFrame.GetCanvasContainer, WorldMapFrame)
        rel = type(rel) == "table" and rel or sc
        -- Our button is 30 wide in a 32 slot: one pixel in keeps it centred.
        local x = (tonumber(lib.XOffset) or 3) + (KROWI_STEP - 30) / 2
        local y = (tonumber(lib.YOffset) or 0) - shown * KROWI_STEP - (KROWI_STEP - 30) / 2
        mapButton.side = "left"
        mapButton:ClearAllPoints()
        mapButton:SetPoint("TOPLEFT", rel, "TOPLEFT", x, y)
        return
    end
    mapButton.side = "right"
    local x = 8
    local right, top = sc.GetRight and sc:GetRight(), sc.GetTop and sc:GetTop()
    for _, f in ipairs(WorldMapFrame.overlayFrames or {}) do
        local shown = f.IsShown and f:IsShown()
        local fl, ft, fr = shown and f:GetLeft(), f.GetTop and f:GetTop(), f.GetRight and f:GetRight()
        if fl and fr and ft and right and top and right - fr < 40 and top - ft < 40 and fr - fl < 220 then
            x = math.max(x, right - fl + 4)
        end
    end
    mapButton:ClearAllPoints()
    mapButton:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -x, -8)
end
ns.PlaceMapButton = placeMapButton

local function anySpotsShown()
    return ns.db.opts.worldMapSpots ~= false
end

local function refreshMapButton()
    if not mapButton then
        return
    end
    local on = anySpotsShown()
    if mapButton.icon.SetDesaturated then
        mapButton.icon:SetDesaturated(not on)
    end
    mapButton.icon:SetAlpha(on and 1 or 0.5)
    mapButton.off:SetShown(not on)
    if mapMenu and mapMenu:IsShown() then
        for _, row in ipairs(mapMenu.rows) do
            local checked = row.get()
            row.mark:SetShown(checked)
            local dim = row.needsSpots and not on
            row.text:SetAlpha(dim and 0.45 or 1)
            if row.icon then
                row.icon:SetAlpha(dim and 0.45 or 1)
                if row.icon.SetDesaturated then
                    row.icon:SetDesaturated(not checked or dim)
                end
            end
        end
    end
end
ns.RefreshMapButton = refreshMapButton

local function buildMapMenu()
    local K = ns.UIKit
    local m = CreateFrame("Frame", "ForeverGoldMapFilter", mapButton)
    m:SetFrameStrata("DIALOG")
    m:EnableMouse(true)
    m:SetPoint("TOPRIGHT", mapButton, "BOTTOMRIGHT", 0, -4)
    if K and K.skin then
        K.skin(m)
    end
    local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -9)
    title:SetText("Gathering spots")
    m.rows = {}
    local y = -30
    local function row(text, icon, get, set, needsSpots)
        local r = CreateFrame("Button", nil, m)
        r:SetSize(196, 20)
        r:SetPoint("TOPLEFT", 6, y)
        y = y - 21
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.92, 0.7, 0.07)
        local box = r:CreateTexture(nil, "ARTWORK")
        box:SetSize(14, 14)
        box:SetPoint("LEFT", 4, 0)
        box:SetColorTexture(0.04, 0.04, 0.04, 1)
        local edge = r:CreateTexture(nil, "BORDER")
        edge:SetPoint("TOPLEFT", box, "TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 1, -1)
        edge:SetColorTexture(0.55, 0.47, 0.3, 1)
        r.mark = r:CreateTexture(nil, "OVERLAY")
        r.mark:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
        r.mark:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
        r.mark:SetColorTexture(1, 0.82, 0.2, 1)
        local x = 24
        if icon then
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(16, 16)
            r.icon:SetPoint("LEFT", x, 0)
            r.icon:SetTexture(icon)
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            x = x + 20
        end
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", x, 0)
        r.text:SetText(text)
        r.get, r.set, r.needsSpots = get, set, needsSpots
        r:SetScript("OnClick", function()
            local ok, err = pcall(set, not get())
            if not ok then
                ns.Err("map-filter", err)
            end
            refreshMapButton()
        end)
        m.rows[#m.rows + 1] = r
        return r
    end
    row("Show on the map", nil, anySpotsShown, function(v) ns.SetMapSpots(v) end)
    for _, k in ipairs(ns.KIND_ORDER) do
        local kind = ns.KINDS[k]
        row(MAP_KIND_LABELS_T[k] or k, kind and kind.icon, function() return ns.MapKindOn(k) end,
            function(v) ns.SetMapKind(k, v) end, true)
    end
    row("Route line", "Interface\\Icons\\INV_Misc_Map_01", function() return ns.db.opts.mapRoute ~= false end,
        function(v)
            ns.db.opts.mapRoute = v and true or false
            ns.RedrawWorldMap()
        end, true)
    row("On the minimap too", nil, function() return ns.db.opts.minimapSpots ~= false end,
        function(v) ns.db.opts.minimapSpots = v and true or false end)
    m:SetSize(208, -y + 8)
    m:Hide()
    return m
end

function ns.ToggleMapMenu(show)
    if not mapButton then
        return
    end
    if not mapMenu then
        mapMenu = buildMapMenu()
        ns.MapFilterMenu = mapMenu
    end
    if show == nil then
        show = not mapMenu:IsShown()
    end
    -- Open beside the button, towards the middle of the map.
    mapMenu:ClearAllPoints()
    if mapButton.side == "left" then
        mapMenu:SetPoint("TOPLEFT", mapButton, "TOPRIGHT", 6, 0)
    else
        mapMenu:SetPoint("TOPRIGHT", mapButton, "BOTTOMRIGHT", 0, -4)
    end
    mapMenu:SetShown(show)
    refreshMapButton()
end

local function setupMapButton()
    if mapButton or not WorldMapFrame then
        return
    end
    local sc = mapContainer()
    local b = CreateFrame("Button", "ForeverGoldMapButton", sc)
    b:SetSize(30, 30)
    b:SetFrameStrata(WorldMapFrame.GetFrameStrata and WorldMapFrame:GetFrameStrata() or "HIGH")
    b.back = b:CreateTexture(nil, "BACKGROUND")
    b.back:SetAllPoints()
    b.back:SetColorTexture(0.05, 0.045, 0.035, 0.9)
    b.edge = b:CreateTexture(nil, "BORDER")
    b.edge:SetPoint("TOPLEFT", -1, 1)
    b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    b.edge:SetColorTexture(0.62, 0.5, 0.25, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 3, -3)
    b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    b.icon:SetTexture(ns.KINDS.herb.icon)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- A red slash across it while everything is hidden.
    b.off = b:CreateTexture(nil, "OVERLAY")
    b.off:SetPoint("CENTER")
    b.off:SetSize(34, 3)
    b.off:SetColorTexture(0.9, 0.2, 0.15, 0.95)
    if b.off.SetRotation then
        b.off:SetRotation(-0.785)
    end
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.9, 0.6, 0.15)
    if b.RegisterForClicks then
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    b:SetScript("OnClick", function(_, which)
        if which == "RightButton" then
            ns.SetMapSpots(not anySpotsShown())
        else
            ns.ToggleMapMenu()
        end
    end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, self.side == "left" and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
        GameTooltip:SetText("Forever Gold: gathering spots", 1, 0.82, 0)
        GameTooltip:AddLine(anySpotsShown() and "Showing on the map." or "Hidden.", 1, 1, 1)
        GameTooltip:AddLine("Click: choose herbs, ore, fishing, chests, route.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: show or hide them all.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    mapButton = b
    ns.MapButton = b
    WorldMapFrame:HookScript("OnHide", function()
        if mapMenu then mapMenu:Hide() end
    end)
end

-- Every redraw: the button exists, sits above the map's art, and is in its corner.
function ns.UpdateMapButton()
    if not WorldMapFrame then
        return
    end
    if not mapButton then
        setupMapButton()
    end
    if not mapButton then
        return
    end
    local sc = mapContainer()
    local level = (sc.GetFrameLevel and sc:GetFrameLevel() or 1) + 50
    local api = openMap()
    if api and api.ArtTopLevel then
        level = math.max(level, (ns.try(api.ArtTopLevel) or 0) + 20)
    end
    if mapOverlay then
        level = math.max(level, mapOverlay:GetFrameLevel() + 20)
    end
    mapButton:SetFrameLevel(level)
    mapButton:SetShown(ns.db.opts.mapButton ~= false)
    placeMapButton()
    refreshMapButton()
end

-- OpenMap: redraw when it switches between its map and Blizzard's, and put
-- our switch in its menu.
local openMapHooked
local function hookOpenMap()
    local api = openMap()
    if openMapHooked or not api then
        return
    end
    openMapHooked = true
    if api.RegisterCallback then
        pcall(api.RegisterCallback, "ForeverGold", "OpenMap_StitchedChanged", function() ns.RedrawWorldMap() end)
    end
    if api.RegisterMenuToggle then
        pcall(api.RegisterMenuToggle, "ForeverGold", { id = "spots", label = "Gathering spots and route",
            icon = ns.KINDS.herb.icon, section = "Forever Gold",
            get = function() return ns.db.opts.worldMapSpots ~= false end,
            set = function(v) ns.SetMapSpots(v) end })
        -- One switch per kind, so each can be starred onto OpenMap's bar too.
        for _, k in ipairs(ns.KIND_ORDER) do
            local kind = ns.KINDS[k]
            pcall(api.RegisterMenuToggle, "ForeverGold", { id = "kind-" .. k, label = "  " .. (MAP_KIND_LABELS_T[k] or k),
                icon = kind and kind.icon, section = "Forever Gold",
                get = function() return ns.MapKindOn(k) end,
                set = function(v) ns.SetMapKind(k, v) end })
        end
        pcall(api.RegisterMenuToggle, "ForeverGold", { id = "route", label = "  Route line",
            icon = "Interface\\Icons\\INV_Misc_Map_01", section = "Forever Gold",
            get = function() return ns.db.opts.mapRoute ~= false end,
            set = function(v)
                ns.db.opts.mapRoute = v and true or false
                ns.RedrawWorldMap()
                if ns.RefreshMapButton then ns.RefreshMapButton() end
            end })
        pcall(api.RegisterMenuToggle, "ForeverGold", { id = "minimap", label = "Gathering spots on the minimap",
            icon = ns.KINDS.ore.icon, section = "Forever Gold",
            get = function() return ns.db.opts.minimapSpots ~= false end,
            set = function(v) ns.db.opts.minimapSpots = v and true or false end })
    end
end

ns.Listen("READY", function()
    C_Timer.After(3, ns.Guard("worldmap-setup", setupWorldMap))
    ns.Guard("openmap", hookOpenMap)()
end)
ns.On("ADDON_LOADED", function(name)
    if name == "Blizzard_WorldMap" and ns.ready then
        setupWorldMap()
    elseif name == "OpenMap" and ns.ready then
        ns.Guard("openmap", hookOpenMap)()
    end
end)
ns.Listen("ROUTE", ns.RedrawWorldMap)
ns.Listen("NODES_UPDATED", ns.RedrawWorldMap)

-- Explored areas change as you travel: the Routes map redraws its picture.
ns.On("MAP_EXPLORATION_UPDATED", function()
    ns.mapArtVersion = (ns.mapArtVersion or 0) + 1
end)

----------------------------------------------------------------------
-- Minimap pins: your spots around you, and the route's next stop (kept on
-- the minimap's edge when it's further away).
----------------------------------------------------------------------

-- How many yards from the centre to the edge of the minimap, by zoom level.
local MINI_OUTDOOR = { 233 + 1 / 3, 200, 166 + 2 / 3, 133 + 1 / 3, 100, 66 + 2 / 3 }
local MINI_INDOOR = { 150, 120, 90, 60, 40, 25 }

local mini = { pins = {}, used = 0 }
local worldCache = setmetatable({}, { __mode = "k" })

local function nodeWorld(mapID, n)
    local c = worldCache[n]
    if c == nil then
        local north, west = worldPos(mapID, n.x, n.y)
        c = north and { north, west } or false
        worldCache[n] = c
    end
    return c
end

local function miniPin()
    mini.used = mini.used + 1
    local p = mini.pins[mini.used]
    if not p then
        p = CreateFrame("Frame", nil, Minimap)
        p:SetSize(14, 14)
        p.ring = p:CreateTexture(nil, "BACKGROUND")
        p.ring:SetPoint("CENTER")
        p.ring:SetSize(18, 18)
        p.ring:SetColorTexture(1, 0.85, 0.2, 1)
        p.back = p:CreateTexture(nil, "BORDER")
        p.back:SetPoint("CENTER")
        p.back:SetSize(14, 14)
        p.icon = p:CreateTexture(nil, "ARTWORK")
        p.icon:SetPoint("CENTER")
        p.icon:SetSize(12, 12)
        if spotIcon(p, p.icon, p.back) then
            roundOff(p, p.ring)
        end
        hoverOnly(p)
        p:SetScript("OnEnter", function(self)
            ns.SpotTooltip(self, self.node, self.isNext and "Next stop on your route" or nil)
        end)
        p:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
        mini.pins[mini.used] = p
    end
    p:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 5)
    p:Show()
    return p
end

local function hideMini(from)
    for i = from, #mini.pins do
        mini.pins[i]:Hide()
    end
end

local function updateMinimap()
    mini.used = 0
    if ns.db.opts.minimapSpots == false or not Minimap:IsVisible() then
        hideMini(1)
        return
    end
    local mapID, px, py = ns.PlayerMapPos()
    local pn, pw
    if mapID then
        pn, pw = worldPos(mapID, px, py)
    end
    if not pn then
        hideMini(1)
        return
    end
    local zoom = (Minimap.GetZoom and ns.try(Minimap.GetZoom, Minimap)) or 0
    local indoor = type(IsIndoors) == "function" and ns.try(IsIndoors)
    local radius = (indoor and MINI_INDOOR or MINI_OUTDOOR)[zoom + 1] or MINI_OUTDOOR[1]
    local half = (Minimap:GetWidth() or 140) / 2
    local rotate = type(GetCVar) == "function" and ns.try(GetCVar, "rotateMinimap") == "1"
    local facing = rotate and ns.try(GetPlayerFacing) or nil
    local cosf, sinf = facing and math.cos(facing) or 1, facing and math.sin(facing) or 0
    local square = type(GetMinimapShape) == "function" and ns.try(GetMinimapShape) == "SQUARE"
    local r = ns.route
    local next = r and not r.paused and r.map == mapID and r.pts[r.i] or nil
    local function place(n, isNext)
        local c = nodeWorld(mapID, n)
        if not c then
            return
        end
        -- Screen right is east (minus west), up is north.
        local x, y = -(c[2] - pw), c[1] - pn
        if facing then
            x, y = x * cosf + y * sinf, -x * sinf + y * cosf
        end
        local far = square and math.max(abs(x), abs(y)) or sqrt(x * x + y * y)
        if far > radius * 0.96 then
            if not isNext then
                return
            end
            -- The next stop sits on the edge, pointing the way.
            local k = radius * 0.92 / far
            x, y = x * k, y * k
        end
        local p = miniPin()
        p.icon:SetTexture(ns.NodeIcon(n))
        p.icon:SetAlpha(1)
        p.node, p.isNext = n, isNext
        p.ring:SetShown(isNext)
        p:ClearAllPoints()
        p:SetPoint("CENTER", Minimap, "CENTER", x / radius * half, y / radius * half)
    end
    for _, n in ipairs(ns.db.nodes[mapID] or {}) do
        if not n.skip and n ~= next and shownKind(n.k) then
            place(n, false)
        end
    end
    if next then
        place(next, true)
    end
    hideMini(mini.used + 1)
end

ns.Listen("READY", function()
    if not Minimap then
        return
    end
    local f = CreateFrame("Frame", nil, Minimap)
    local since = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < 0.1 then
            return
        end
        since = 0
        local ok, err = pcall(updateMinimap)
        if not ok then
            ns.Err("minimap", err)
            hideMini(1)
            f:SetScript("OnUpdate", nil)
        end
    end)
    mini.frame = f
end)
ns.UpdateMinimapPins = updateMinimap
ns.MinimapPins = mini

----------------------------------------------------------------------
-- Loot beams
--
-- A column of light standing on the spot you're heading for. An addon
-- can't draw in the 3D world itself; what it can do is follow the game's
-- own waypoint marker, which C_Navigation keeps at the tracked map pin's
-- place on screen. So there's one beam at a time:
--   * on a route: the next stop, in bright gold;
--   * otherwise: the nearest spot you've recorded, in white. That one puts
--     the map pin down itself, but only while you aren't tracking anything
--     else (a quest, your own pin), and it moves on from spots you've just
--     been to.
-- The beam is drawn in screen space and sized by distance, so it shrinks
-- as the spot gets further away (down to a minimum, so it never vanishes).
----------------------------------------------------------------------

local BEAM_ROUTE = { 1, 0.80, 0.16 }  -- gold: the next stop on your route
local BEAM_SPOT = { 0.92, 0.94, 1 }   -- white: the nearest spot, no route running
local NEAREST_RANGE = 400             -- further away than this isn't "nearby"
local VISITED_FOR = 300               -- seconds a spot you've just been to is passed over
local WHITE = "Interface\\Buttons\\WHITE8X8"
local DISC = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local beam = { visited = setmetatable({}, { __mode = "k" }) }
ns.Beam = beam

-- Is the game's tracked pin the one at this place? (With anyTracking, just
-- whether the pin is there, tracked or not.)
local function trackingPin(map, x, y, anyTracking)
    if not (map and C_Map and C_Map.GetUserWaypoint) then
        return false
    end
    if not anyTracking and C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint
        and not ns.try(C_SuperTrack.IsSuperTrackingUserWaypoint) then
        return false
    end
    local p = ns.try(C_Map.GetUserWaypoint)
    if type(p) ~= "table" or p.uiMapID ~= map then
        return false
    end
    local px, py
    if p.position and p.position.GetXY then
        px, py = p.position:GetXY()
    end
    return (px and py and abs(px - x) < 0.001 and abs(py - y) < 0.001) and true or false
end
beam.TrackingPin = trackingPin

-- The nearest recorded spot in this zone you haven't just been to.
local function nearestSpot()
    local mapID, px, py = ns.PlayerMapPos()
    if not mapID then
        return nil
    end
    local pn, pw = worldPos(mapID, px, py)
    if not pn then
        return nil
    end
    local now = GetTime()
    local best, bestD
    for _, n in ipairs(ns.db.nodes[mapID] or {}) do
        if not n.skip and shownKind(n.k) then
            local c = nodeWorld(mapID, n)
            if c then
                local dn, dw = c[1] - pn, c[2] - pw
                local d = sqrt(dn * dn + dw * dw)
                if d < ARRIVE_YARDS then
                    beam.visited[n] = now
                end
                local seen = beam.visited[n]
                if not (seen and now - seen < VISITED_FOR) and d < NEAREST_RANGE and (not bestD or d < bestD) then
                    best, bestD = n, d
                end
            end
        end
    end
    return best, mapID
end

-- Lets go of the pin the nearest-spot beam put down (never a route's or yours).
local function releaseSpot()
    local own = beam.own
    beam.own = nil
    local r = ns.route
    if own and not (r and not r.paused) and trackingPin(own.map, own.x, own.y) and C_Map.ClearUserWaypoint then
        pcall(C_Map.ClearUserWaypoint)
    end
end
beam.Release = releaseSpot

-- Once a second: which spot the white beam belongs on, if any.
local function updateSpot()
    local opts = ns.db.opts
    local r = ns.route
    if opts.lootBeam == false or opts.nearestBeam == false or (r and not r.paused) then
        releaseSpot()
        return
    end
    -- The player tracked something else, placed their own pin, or the game
    -- cleared ours on arrival: it's not ours any more. A pin of ours left
    -- behind under a tracked quest is tidied away.
    local own = beam.own
    if own and not trackingPin(own.map, own.x, own.y) then
        beam.own = nil
        if trackingPin(own.map, own.x, own.y, true) then
            if C_Map.ClearUserWaypoint then
                pcall(C_Map.ClearUserWaypoint)
            end
        elseif not (C_Map.HasUserWaypoint and ns.try(C_Map.HasUserWaypoint)) then
            -- The pin's simply gone: the game clears it when you get there.
            beam.visited[own.node] = GetTime()
        end
    end
    local n, mapID = nearestSpot()
    if not n then
        releaseSpot()
        return
    end
    if beam.own and beam.own.node == n then
        return
    end
    if not beam.own then
        -- Only an empty slot: never replace a quest, a corpse or a pin you placed.
        if C_Map.HasUserWaypoint and ns.try(C_Map.HasUserWaypoint) then
            return
        end
        if C_SuperTrack and C_SuperTrack.IsSuperTrackingAnything and ns.try(C_SuperTrack.IsSuperTrackingAnything) then
            return
        end
    end
    if ns.SetWaypoint(mapID, n.x, n.y) then
        beam.own = { node = n, map = mapID, x = n.x, y = n.y }
    end
end
beam.UpdateSpot = updateSpot

-- What the beam should be right now: colour, or nil for none.
local function beamColor()
    if ns.db.opts.lootBeam == false then
        return nil
    end
    local r = ns.route
    if r and not r.paused then
        local pt = r.pts[r.i]
        return pt and trackingPin(r.map, pt.x, pt.y) and BEAM_ROUTE or nil
    end
    local own = beam.own
    return own and trackingPin(own.map, own.x, own.y) and BEAM_SPOT or nil
end

----------------------------------------------------------------------
-- How a beam looks: a slim shaft of light, like a loot drop's, standing
-- in the world like a real column.
--
-- An addon can't draw in the 3D world, and the game never says which way
-- the camera points. It does say where on screen the spot is and how far
-- away it is, plus the camera's zoom and field of view. From those the
-- camera's tilt is worked out, and the beam is drawn as a column of light
-- standing up from the spot, seen through that camera. So it leans the
-- way upright things lean towards the sides of the screen, tapers with
-- distance, stands tall seen from the side, and, looking straight down on
-- it, shrinks to a short glow over a round pool of light.
--
--   * a thin, near-white hot core (normal blending, so it still reads on
--     snow, sand and daylight - additive light alone washes out there);
--   * three soft halos around it in the beam's colour, each wider and
--     fainter, so the edges melt into the scene instead of stopping;
--   * everything fades out going up, so the top dissolves into the air;
--   * a short flare, and a soft pool lying flat on the ground, at the foot;
--   * a few motes of light drifting up the shaft.
-- Each layer is a run of short line segments, so it can lean and taper.
-- It's drawn on the 3D world's layer (behind nameplates and the whole UI)
-- and keeps a minimum size on screen, so a far one is still a clear line.
----------------------------------------------------------------------

local HALOS = { -- width (x the core), brightness at the foot
    { 2.6, 0.50 },
    { 5.0, 0.20 },
    { 9.0, 0.08 },
}
local POOLS = { -- width (x the core), brightness
    { 13, 0.10 },
    { 7, 0.22 },
    { 3, 0.55 },
}
local MOTES = 4
local SEGS = 8             -- line segments in each layer, foot to top
local BEAM_YARDS = 9       -- how tall the column stands
local CORE_YARDS = 0.14    -- how wide its hot core is
local EYE, EYE_MOUNTED = 1.9, 3.2 -- the camera turns about a point this high above your feet

local sin, cos, tan, rad = math.sin, math.cos, math.tan, math.rad

-- The beam's colour, lifted towards white for the hot centre.
local function lighten(c, k)
    return c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k
end

local function segment(f, drawLayer, additive)
    local l = f:CreateLine(nil, drawLayer)
    l:SetColorTexture(1, 1, 1, 1)
    if l.SetBlendMode then
        l:SetBlendMode(additive and "ADD" or "BLEND")
    end
    return l
end

local function disc(f, drawLayer, sub)
    local t = f:CreateTexture(nil, drawLayer, nil, sub)
    t:SetTexture(DISC)
    if t.SetBlendMode then
        t:SetBlendMode("ADD")
    end
    return t
end

local function buildBeam()
    -- On the world's layer when there is one: under nameplates and the UI.
    local parent = WorldFrame or UIParent
    local f = CreateFrame("Frame", nil, parent)
    f:SetFrameStrata("BACKGROUND")
    f:SetFrameLevel(1)
    f:EnableMouse(false)
    f:SetSize(1, 1) -- just a point: the foot. Everything is drawn from it.
    f.pools = {}
    for i, _ in ipairs(POOLS) do
        local t = disc(f, "BACKGROUND", i)
        t:SetPoint("CENTER", f, "BOTTOM", 0, 0)
        f.pools[i] = t
    end
    f.pool = f.pools[#POOLS]
    -- layers[1] is the core; the rest are the halos, widest last.
    f.layers = {}
    for i = #HALOS, 1, -1 do
        local segs = {}
        for k = 1, SEGS do
            segs[k] = segment(f, "BORDER", true)
        end
        f.layers[i + 1] = segs
    end
    f.flare = segment(f, "BORDER", true)
    local core = {}
    for k = 1, SEGS do
        core[k] = segment(f, "ARTWORK", false)
    end
    f.layers[1] = core
    f.core, f.halos = core, {}
    for i = 1, #HALOS do
        f.halos[i] = f.layers[i + 1]
    end
    f.motes = {}
    for i = 1, MOTES do
        local t = disc(f, "OVERLAY", 1)
        t.phase = (i - 1) / MOTES
        t.speed = 0.42 + 0.09 * i
        t.sway = (i % 2 == 0) and 1 or -1
        f.motes[i] = t
    end
    f:Hide()
    return f
end

-- How bright segment k (of SEGS) of a layer is: bright at the foot, gone at the top.
local function fade(k, foot)
    local mid = (k - 0.5) / SEGS
    return foot * (1 - mid) ^ 1.3
end

local function paint(f, c)
    if f.color == c then
        return
    end
    f.color = c
    local cr, cg, cb = lighten(c, 0.65)
    f.coreRGB = { cr, cg, cb }
    for k, l in ipairs(f.core) do
        l:SetColorTexture(cr, cg, cb, fade(k, 0.95))
    end
    for i, spec in ipairs(HALOS) do
        for k, l in ipairs(f.halos[i]) do
            l:SetColorTexture(c[1], c[2], c[3], fade(k, spec[2]))
        end
    end
    f.flare:SetColorTexture(c[1], c[2], c[3], 0.30)
    for i, spec in ipairs(POOLS) do
        f.pools[i]:SetVertexColor(c[1], c[2], c[3], spec[2])
    end
    local mr, mg, mb = lighten(c, 0.5)
    for _, m in ipairs(f.motes) do
        m:SetVertexColor(mr, mg, mb, 1)
    end
end

----------------------------------------------------------------------
-- The camera, worked out from where the spot is on screen
----------------------------------------------------------------------

-- A point seen through a camera tilted down by `tilt` (radians), orbiting
-- `zoom` yards back from its pivot. The point is `u` yards ahead of the
-- pivot along the camera's facing, `r` to the right and `z` up from it.
-- Returns its screen offset from the centre (x right, y up) and its depth.
local function project(tilt, u, r, z, zoom, focal)
    local s, c = sin(tilt), cos(tilt)
    local depth = u * c - z * s + zoom
    if depth < 0.05 then
        depth = 0.05
    end
    return focal * r / depth, focal * (u * s + z * c) / depth, depth
end
beam.Project = project

-- The tilt and the spot's bearing (off the camera's facing) that put a spot
-- `dist` yards away, `z` yards above the pivot, at screen offset (sx, sy).
local function solveCamera(sx, sy, dist, z, zoom, focal, tilt)
    tilt = tilt or 0.35
    local bearing = 0
    for _ = 1, 4 do
        local lo, hi = -1.5, 1.5
        for _ = 1, 18 do
            local mid = (lo + hi) / 2
            if project(tilt, dist * cos(mid), dist * sin(mid), z, zoom, focal) < sx then
                lo = mid
            else
                hi = mid
            end
        end
        bearing = (lo + hi) / 2
        local u, r = dist * cos(bearing), dist * sin(bearing)
        lo, hi = -1.2, 1.55
        for _ = 1, 18 do
            local mid = (lo + hi) / 2
            local _, py = project(mid, u, r, z, zoom, focal)
            if py < sy then
                lo = mid
            else
                hi = mid
            end
        end
        tilt = (lo + hi) / 2
    end
    return tilt, bearing
end
beam.SolveCamera = solveCamera

-- The field of view's vertical half-angle. The game's setting is taken as
-- the width of a 4:3 view; wider screens see more at the sides.
local function focalLength(screenH)
    local deg = tonumber(GetCVar and ns.try(GetCVar, "cameraFov") or nil) or 90
    deg = math.max(30, math.min(150, deg))
    return (screenH / 2) / (tan(rad(deg) / 2) * 0.75)
end

-- Stands the beam on the spot. (x, y) is the spot on screen, in the
-- coordinates of `region`; `dist` is how far away it is; `up` is how far
-- above the ground the screen point sits (a nameplate floats a little).
-- `region` is what the game hangs on the thing (its marker or nameplate) and
-- (x, y) where that is on screen; `up` is how many yards above the ground
-- that point is. The beam stands on the ground under it: the frame is moved
-- down from the anchor by the ground point's offset on screen.
local function placeBeam(f, region, x, y, dist, alpha, up)
    local world = f:GetParent() or UIParent
    local sw, sh = world:GetWidth() or 0, world:GetHeight() or 0
    if sh <= 0 then
        sw, sh = 1024, 768
    end
    local sx, sy
    if x and y then
        local okS, rs = pcall(region.GetEffectiveScale, region)
        local scale = ((okS and rs) or 1) / (world:GetEffectiveScale() or 1)
        sx, sy = x * scale - sw / 2, y * scale - sh / 2
    else
        -- The game won't say where the anchor is on screen (a restricted
        -- region): the beam still hangs from it, and leans as if it were a
        -- little below the middle of the screen, where what you face usually is.
        sx, sy = 0, -sh * 0.12
    end
    local focal = focalLength(sh)
    local zoom = tonumber(GetCameraZoom and ns.try(GetCameraZoom) or nil) or 12
    zoom = math.max(0, math.min(50, zoom))
    local eye = (IsMounted and ns.try(IsMounted)) and EYE_MOUNTED or EYE
    local anchorZ = (up or 0) - eye
    local footZ = -eye
    dist = math.max(dist or 10, 1)

    -- The tilt moves smoothly, so a wobble in the reading doesn't shake the beam.
    local tilt, bearing = solveCamera(sx, sy, dist, anchorZ, zoom, focal, f.tilt)
    f.tilt = f.tilt and (f.tilt + (tilt - f.tilt) * 0.3) or tilt
    tilt = f.tilt
    local u, r = dist * cos(bearing), dist * sin(bearing)
    local x0, y0, d0 = project(tilt, u, r, footZ, zoom, focal)
    -- From the anchor down to the ground under it (never further than a
    -- little of the screen, in case the distance is a guess).
    local ox, oy = 0, 0
    if (up or 0) > 0 then
        local xa, ya = project(tilt, u, r, anchorZ, zoom, focal)
        ox, oy = x0 - xa, y0 - ya
        local reach = sqrt(ox * ox + oy * oy)
        local most = sh * 0.12
        if reach > most then
            ox, oy = ox * most / reach, oy * most / reach
        end
    end
    if f.rel and (not f.ox or math.abs(f.ox - ox) > 0.3 or math.abs(f.oy - oy) > 0.3) then
        f:ClearAllPoints()
        pcall(f.SetPoint, f, "BOTTOM", region, f.rel, ox, oy)
        f.ox, f.oy = ox, oy
    end

    -- The column, cut short if its top would come past the camera.
    local tall = BEAM_YARDS
    local s = sin(tilt)
    if s > 0.01 then
        tall = math.min(tall, (d0 - 1) / s)
    end
    tall = math.max(tall, 0.5)
    local x1, y1, d1 = project(tilt, u, r, footZ + tall, zoom, focal)
    local dx, dy = x1 - x0, y1 - y0
    local len = sqrt(dx * dx + dy * dy)
    if len < 0.001 then
        dx, dy, len = 0, 1, 1
    end
    -- Far away it would be a speck: keep it a clear line. Up close, never
    -- fill the screen.
    local least = math.min(40, 12 + dist * 0.4)
    local most = sh * 0.45
    local want = math.max(least, math.min(most, len))
    dx, dy, len = dx * want / len, dy * want / len, want

    -- Nearer parts look wider.
    local wFoot = math.max(1.6, math.min(4.5, focal * CORE_YARDS / d0))
    local wTop = wFoot * math.max(0.4, math.min(2.5, d0 / math.max(d1, 0.5)))

    for i, segs in ipairs(f.layers) do
        local wide = (i == 1) and 1 or HALOS[i - 1][1]
        local reach = (i == 1) and 1 or (1 - 0.06 * (i - 1))
        for k, l in ipairs(segs) do
            local t0, t1 = (k - 1) / SEGS * reach, k / SEGS * reach
            local tm = (t0 + t1) / 2
            l:SetStartPoint("BOTTOM", f, dx * t0, dy * t0)
            l:SetEndPoint("BOTTOM", f, dx * t1, dy * t1)
            l:SetThickness((wFoot + (wTop - wFoot) * tm) * wide)
        end
    end
    f.flare:SetStartPoint("BOTTOM", f, 0, 0)
    f.flare:SetEndPoint("BOTTOM", f, dx * 0.16, dy * 0.16)
    f.flare:SetThickness(wFoot * 6)

    -- The pool lies on the ground: round seen from above, a thin ellipse
    -- seen from the side.
    local _, ya = project(tilt, u + 1, r, footZ, zoom, focal)
    local _, yb = project(tilt, u - 1, r, footZ, zoom, focal)
    local flat = math.max(0.15, math.min(1, math.abs(ya - yb) / math.max(0.001, 2 * focal / d0)))
    for i, spec in ipairs(POOLS) do
        local w = wFoot * spec[1]
        f.pools[i]:SetSize(w, w * flat)
    end

    -- Motes rise from the foot along the shaft, sway a little, and fade.
    local now = GetTime()
    local px, py = -dy / len, dx / len
    for _, m in ipairs(f.motes) do
        local t = (now * m.speed + m.phase) % 1
        local size = math.max(1.5, wFoot * 0.9)
        local side = m.sway * wFoot * 1.6 * sin((t + m.phase) * 6.28)
        m:SetSize(size, size)
        m:ClearAllPoints()
        m:SetPoint("CENTER", f, "BOTTOM", dx * 0.72 * t + px * side, dy * 0.72 * t + py * side)
        m:SetAlpha(math.min(1, t * 6) * (1 - t) * 0.9)
    end
    -- A slow breath, and a faint shimmer in the core.
    local shimmer = 0.88 + 0.12 * sin(now * 7.3)
    for _, l in ipairs(f.core) do
        l:SetAlpha(shimmer)
    end
    f:SetAlpha(alpha * (0.9 + 0.1 * sin(now * 2.2)))
    f.len, f.dx, f.dy, f.coreW, f.topW, f.flat, f.tall = len, dx, dy, wFoot, wTop, flat, tall
    f:Show()
end

local NAV_ALPHA -- state -> how visible, like the game's own marker
local function navAlpha(state)
    if not NAV_ALPHA then
        local S = Enum and Enum.NavigationState or {}
        NAV_ALPHA = { [S.Invalid or 0] = 0, [S.Occluded or 1] = 0.55, [S.InRange or 2] = 1, [S.Disabled or 3] = 0 }
    end
    return NAV_ALPHA[state] or 0
end

local function hideBeam()
    if beam.frame then
        beam.frame:Hide()
    end
end

-- Every frame: put the beam on the marker, sized for how far away it is.
local function drawBeam()
    local c = beamColor()
    local N = C_Navigation
    if not c or not (N and N.GetFrame) then
        hideBeam()
        return
    end
    local nav = ns.try(N.GetFrame)
    if not nav or (N.HasValidScreenPosition and not ns.try(N.HasValidScreenPosition))
        or (N.WasClampedToScreen and ns.try(N.WasClampedToScreen)) then
        -- Off screen: the game's own marker points the way at the edge.
        hideBeam()
        return
    end
    local alpha = N.GetTargetState and navAlpha(ns.try(N.GetTargetState)) or 1
    local d = (N.GetDistance and ns.try(N.GetDistance)) or 100
    -- Standing on it: fade out over the last few yards.
    alpha = alpha * math.max(0, math.min(1, (d - 2) / 5))
    if alpha <= 0 then
        hideBeam()
        return
    end
    -- The same spot already has a beam on the object itself (below): that
    -- one sits exactly on it, so this one steps aside.
    local r = ns.route
    local target = (r and not r.paused) and r.pts[r.i] or (beam.own and beam.own.node)
    if beam.softNode and beam.softNode == target then
        hideBeam()
        return
    end
    local f = beam.frame
    if not f then
        f = buildBeam()
        beam.frame = f
    end
    if f.anchor ~= nav then
        f:ClearAllPoints()
        if not pcall(f.SetPoint, f, "BOTTOM", nav, "CENTER", 0, 0) then
            beam.broken = true
            hideBeam()
            return
        end
        f.anchor, f.rel, f.ox, f.oy = nav, "CENTER", 0, 0
    end
    paint(f, c)
    -- Where the marker is on screen; some clients won't say (restricted
    -- regions), and then the beam still stands on it, from an estimate.
    local okC, nx, ny = pcall(nav.GetCenter, nav)
    if not (okC and nx and ny) then
        nx, ny = nil, nil
    end
    placeBeam(f, nav, nx, ny, d, alpha, 0)
end
beam.Draw = drawBeam

----------------------------------------------------------------------
-- Beams on things you haven't recorded yet
--
-- With the game's Interact Key on, it picks out the herb, vein or chest in
-- front of you and hangs its interact icon on it - on a nameplate standing
-- on the object. A beam hangs from that too, so it works for spots that
-- were never recorded. It only reaches as far as the game's interact
-- targeting does (close by, roughly where you're facing), and it's one
-- object at a time.
--
-- The colour says what it is:
--   gold        a stop on the route you're running
--   white       a spot you've recorded
--   light blue  something new - gather it and it's recorded
----------------------------------------------------------------------

local BEAM_NEW = { 0.36, 0.60, 1 }  -- magic blue
-- About how tall each kind of thing stands, in yards: its nameplate sits on top.
local OBJECT_TOP = { herb = 1.0, ore = 1.7, chest = 1.1, fish = 0.2 }
beam.COLORS = { route = BEAM_ROUTE, recorded = BEAM_SPOT, new = BEAM_NEW }

-- The game settings this needs, and what they're set to. What they were
-- before is kept (ns.db.beamCVars) and put back when the option is off.
local BEAM_CVARS = {
    softTargetInteract = "3",          -- Interact Key: keyboard and mouse too, not just a gamepad
    SoftTargetIconInteract = "1",      -- the icon on what it picked
    SoftTargetIconGameObject = "1",    -- ...including objects (herbs, veins, chests)
    SoftTargetNameplateInteract = "1", -- and the nameplate that icon sits on
}

local function applyCVars(on)
    if not (GetCVar and SetCVar) then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return -- try again out of combat
    end
    if on then
        if ns.db.beamCVars then
            return
        end
        local saved = {}
        for name, value in pairs(BEAM_CVARS) do
            local old = ns.try(GetCVar, name)
            if old ~= nil then -- a setting this client doesn't have is left alone
                saved[name] = tostring(old)
                if tostring(old) ~= value then
                    pcall(SetCVar, name, value)
                end
            end
        end
        ns.db.beamCVars = saved
    elseif ns.db.beamCVars then
        for name, old in pairs(ns.db.beamCVars) do
            pcall(SetCVar, name, old)
        end
        ns.db.beamCVars = nil
    end
end
beam.ApplyCVars = applyCVars

local function wantSoft()
    local o = ns.db.opts
    return o.lootBeam ~= false and o.beamUnrecorded ~= false
end

-- What a gatherable thing is, from its name. Names you've gathered before
-- are learned (that covers WoW Forever's own herbs); otherwise the usual
-- wording: "... Vein", "... School", chests by name, and the classic herbs.
local HERBS = {}
for _, h in ipairs({ "peacebloom", "silverleaf", "earthroot", "mageroyal", "briarthorn", "stranglekelp", "bruiseweed",
    "wild steelbloom", "grave moss", "kingsblood", "liferoot", "fadeleaf", "goldthorn", "khadgar's whisker", "wintersbite",
    "firebloom", "purple lotus", "arthas' tears", "sungrass", "blindweed", "ghost mushroom", "gromsblood", "golden sansam",
    "dreamfoil", "mountain silversage", "plaguebloom", "icecap", "black lotus" }) do
    HERBS[h] = true
end

local learned
ns.Listen("NODES_UPDATED", function() learned = nil end)

local function objectKind(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    if not learned then
        learned = {}
        for _, list in pairs(ns.db.nodes) do
            for _, n in ipairs(list) do
                if n.n and n.k ~= "fish" then
                    learned[n.n] = n.k
                end
            end
        end
    end
    if learned[name] then
        return learned[name]
    end
    local l = name:lower()
    if isChest(name) then
        return "chest"
    elseif l:find("vein", 1, true) or l:find(" deposit$") then
        return "ore"
    elseif l:find("school", 1, true) or l:find("wreckage", 1, true) or l:find("floating debris", 1, true)
        or l:find("oil spill", 1, true) then
        return "fish"
    elseif HERBS[l] then
        return "herb"
    end
    return nil
end
beam.ObjectKind = objectKind

-- The recorded spot of this kind nearest to you, if one is close enough to
-- be the thing in front of you. Returns node, yards.
local MATCH_YARDS = 30
local function recordedHere(kind)
    local mapID, px, py = ns.PlayerMapPos()
    if not mapID then
        return nil
    end
    local pn, pw = worldPos(mapID, px, py)
    if not pn then
        return nil
    end
    local best, bestD
    for _, n in ipairs(ns.db.nodes[mapID] or {}) do
        if n.k == kind then
            local c = nodeWorld(mapID, n)
            if c then
                local dn, dw = c[1] - pn, c[2] - pw
                local d = sqrt(dn * dn + dw * dw)
                if d < MATCH_YARDS and (not bestD or d < bestD) then
                    best, bestD = n, d
                end
            end
        end
    end
    return best, bestD, mapID
end

-- Stops on the running route, for "is this one of yours?".
local routeSet, routeSetFor = {}, nil
local function onRoute(node)
    local r = ns.route
    if not (node and r and not r.paused) then
        return false
    end
    if routeSetFor ~= r then
        routeSet, routeSetFor = {}, r
        for _, p in ipairs(r.pts) do
            routeSet[p] = true
        end
    end
    return routeSet[node] or false
end

local seenObjects, seenCount = {}, 0

-- The thing the game has picked out in front of you, if it's gatherable:
-- { kind =, name = }.
local function softObject()
    local guid = UnitGUID and ns.try(UnitGUID, "softinteract")
    if type(guid) ~= "string" or not guid:find("^GameObject") then
        return nil
    end
    local o = seenObjects[guid]
    if o == nil then
        local name = UnitName and ns.try(UnitName, "softinteract")
        local kind = objectKind(name)
        o = kind and { kind = kind, name = name } or false
        if seenCount > 300 then
            seenObjects, seenCount = {}, 0
        end
        seenObjects[guid] = o
        seenCount = seenCount + 1
    end
    return o or nil
end

local function hideSoft()
    beam.softNode = nil
    beam.softKind = nil
    if beam.softFrame then
        beam.softFrame:Hide()
    end
end

local lastMatch = { at = -1 }
local function drawSoft()
    if not wantSoft() or not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
        hideSoft()
        return
    end
    local o = softObject()
    if o and not shownKind(o.kind) then
        o = nil -- a herb without Herbalism, a vein without Mining...
    end
    local plate = o and ns.try(C_NamePlate.GetNamePlateForUnit, "softinteract")
    if not plate then
        hideSoft()
        return
    end
    -- Which recorded spot (if any) it is: looked up a few times a second.
    local now = GetTime()
    if lastMatch.obj ~= o or now - lastMatch.at > 0.25 then
        lastMatch.obj, lastMatch.at = o, now
        lastMatch.node, lastMatch.d = recordedHere(o.kind)
    end
    local node, d = lastMatch.node, lastMatch.d
    local c = onRoute(node) and BEAM_ROUTE or (node and BEAM_SPOT) or BEAM_NEW
    local f = beam.softFrame
    if not f then
        f = buildBeam()
        beam.softFrame = f
    end
    if f.anchor ~= plate then
        f:ClearAllPoints()
        if not pcall(f.SetPoint, f, "BOTTOM", plate, "BOTTOM", 0, 0) then
            -- Nameplates are off-limits here (some places protect them).
            hideSoft()
            return
        end
        f.anchor, f.rel, f.ox, f.oy = plate, "BOTTOM", 0, 0
    end
    beam.softNode, beam.softKind = node, (c == BEAM_ROUTE and "route") or (node and "recorded") or "new"
    paint(f, c)
    -- The game only picks things out close by: a few yards when it's new.
    -- Some nameplates can't be measured at all ("Can't measure restricted
    -- regions", 2026-11-20): then there's simply no beam on the object.
    -- Nameplates usually can't be measured ("Can't measure restricted
    -- regions", 2026-11-20): the beam still hangs from the plate, placed
    -- from an estimate of where it is.
    local okC, px = pcall(plate.GetCenter, plate)
    local okB, py = pcall(plate.GetBottom, plate)
    if not (okC and okB and px and py) then
        px, py = nil, nil
    end
    -- The nameplate sits on top of the object: the beam stands on the
    -- ground under it.
    placeBeam(f, plate, px, py, d or 6, 1, OBJECT_TOP[o.kind] or 1)
end
beam.DrawSoft = drawSoft

-- Each part runs on its own (2026-11-19, a friend's beams all went off at
-- once and the error was gone by the time anyone could look). One that
-- fails is saved with the line it failed on (see ns.Err), hidden, and tried
-- again half a minute later; the others carry on. One that keeps failing
-- stays off until /reload.
local RETRY_AFTER, GIVE_UP_AFTER = 30, 5
local PARTS = {
    { name = "loot-beam (nearest spot)", run = updateSpot, hide = function() end, slow = true },
    { name = "loot-beam (on the object)", run = drawSoft, hide = hideSoft },
    { name = "loot-beam (on the marker)", run = drawBeam, hide = hideBeam },
}
beam.parts = PARTS

local function stackOf(err)
    local trace = (debugstack and debugstack(2, 12, 0)) or (debug and debug.traceback and debug.traceback("", 2)) or ""
    return tostring(err) .. "\n" .. trace
end

local function runPart(p, now)
    if p.off and now < p.off then
        return
    end
    local ok, err = xpcall(p.run, stackOf)
    if ok then
        return
    end
    local msg, stack = err:match("^(.-)\n(.*)$")
    p.fails = (p.fails or 0) + 1
    p.off = now + (p.fails >= GIVE_UP_AFTER and math.huge or RETRY_AFTER)
    ns.Err(p.name, msg or err, stack)
    pcall(p.hide)
end
beam.RunPart = runPart

ns.Listen("READY", function()
    applyCVars(wantSoft())
    local driver = CreateFrame("Frame", nil, UIParent)
    local since = 1
    driver:SetScript("OnUpdate", function(_, elapsed)
        if beam.broken then
            hideBeam()
            hideSoft()
            driver:SetScript("OnUpdate", nil)
            return
        end
        since = since + elapsed
        local now = GetTime()
        local second = since >= 1
        if second then
            since = 0
            -- The option was switched: set the game's settings, or put them back.
            if wantSoft() ~= (ns.db.beamCVars ~= nil) then
                applyCVars(wantSoft())
            end
        end
        for _, p in ipairs(PARTS) do
            if second or not p.slow then
                runPart(p, now)
            end
        end
    end)
    beam.driver = driver
end)

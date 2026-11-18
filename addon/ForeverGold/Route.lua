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

ns.KINDS = {
    ore = { label = "Ore", color = { 0.98, 0.62, 0.20 } },
    herb = { label = "Herbs", color = { 0.35, 0.90, 0.35 } },
    fish = { label = "Fishing", color = { 0.35, 0.65, 1.00 } },
}

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
        if l == "mining" or l:find("^mining") then
            kind = "ore"
        elseif l:find("herb") then
            kind = "herb"
        elseif l == "fishing" then
            kind = "fish"
        elseif l == "skinning" then
            kind = "skin"
        end
    end
    spellKind[spellID] = kind
    return kind or nil
end

-- "ore" | "herb" | "fish" | "skin" | nil - the loot tracker uses this too.
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

-- Zones with recorded nodes: { {map=, name=, ore=, herb=, fish=, total=}, ... }
function ns.NodeZones()
    local out = {}
    for mapID, list in pairs(ns.db.nodes) do
        if #list > 0 then
            local z = { map = mapID, name = ns.MapName(mapID), ore = 0, herb = 0, fish = 0, total = #list }
            for _, n in ipairs(list) do
                z[n.k] = (z[n.k] or 0) + 1
            end
            out[#out + 1] = z
        end
    end
    table.sort(out, function(a, b) return a.total > b.total end)
    return out
end

function ns.ForgetZone(mapID)
    ns.db.nodes[mapID] = nil
    if ns.route and ns.route.map == mapID then
        ns.StopRoute()
    end
    ns.Fire("NODES_UPDATED")
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

function ns.BuildRoute(mapID, kinds)
    local source = ns.db.nodes[mapID] or {}
    local pts = {}
    for _, n in ipairs(source) do
        if kinds[n.k] then
            pts[#pts + 1] = n
        end
    end
    if #pts < 2 then
        return nil, "I need at least two recorded spots of that kind in this zone."
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

    -- Begin at the stop nearest the player.
    local first, firstD = 1, nil
    for i = 1, n do
        local d = dist(here, tour[i])
        if not firstD or d < firstD then
            first, firstD = i, d
        end
    end

    local length = 0
    for i = 1, n do
        length = length + dist(tour[i], tour[(i % n) + 1])
    end

    ns.route = { map = mapID, pts = tour, i = first, n = n, kinds = kinds, length = length, visited = 0 }
    ns.SetRouteWaypoint()
    ns.Fire("ROUTE")
    return ns.route
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
    if not r or not ns.db.opts.waypoint then
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
    local st = { name = pt.n or (kindInfo and kindInfo.label) or "Next spot", index = r.i, count = r.n,
        zone = ns.MapName(r.map) }
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

function ns.NewPlotter(parent)
    local plot = { parent = parent, dots = {}, lines = {}, usedDots = 0, usedLines = 0 }

    function plot:Dot()
        self.usedDots = self.usedDots + 1
        local d = self.dots[self.usedDots]
        if not d then
            d = parent:CreateTexture(nil, "OVERLAY")
            self.dots[self.usedDots] = d
        end
        d:Show()
        return d
    end

    function plot:Line()
        self.usedLines = self.usedLines + 1
        local l = self.lines[self.usedLines]
        if not l then
            l = parent:CreateLine(nil, "ARTWORK")
            self.lines[self.usedLines] = l
        end
        l:Show()
        return l
    end

    function plot:Clear()
        for i = 1, #self.dots do self.dots[i]:Hide() end
        for i = 1, #self.lines do self.lines[i]:Hide() end
        self.usedDots, self.usedLines = 0, 0
    end

    -- kinds: which node kinds to show (nil = all). showPlayer: draw "you".
    function plot:Draw(mapID, w, h, dotSize, kinds, showPlayer)
        self:Clear()
        if not mapID or not w or w <= 0 or not h or h <= 0 then
            return
        end
        local r = ns.route
        if r and r.map == mapID then
            for i = 1, r.n do
                local a, b = r.pts[i], r.pts[(i % r.n) + 1]
                local line = self:Line()
                line:SetColorTexture(1, 0.82, 0, 0.75)
                line:SetThickness(math.max(1.5, dotSize * 0.3))
                line:SetStartPoint("TOPLEFT", parent, a.x * w, -a.y * h)
                line:SetEndPoint("TOPLEFT", parent, b.x * w, -b.y * h)
            end
        end
        for _, n in ipairs(ns.db.nodes[mapID] or {}) do
            if not kinds or kinds[n.k] then
                local info = ns.KINDS[n.k]
                local c = info and info.color or { 1, 1, 1 }
                local d = self:Dot()
                d:SetColorTexture(c[1], c[2], c[3], 1)
                d:SetSize(dotSize, dotSize)
                d:ClearAllPoints()
                d:SetPoint("CENTER", parent, "TOPLEFT", n.x * w, -n.y * h)
            end
        end
        if r and r.map == mapID then
            local pt = r.pts[r.i]
            local d = self:Dot()
            d:SetColorTexture(1, 1, 1, 1)
            d:SetSize(dotSize * 1.8, dotSize * 1.8)
            d:ClearAllPoints()
            d:SetPoint("CENTER", parent, "TOPLEFT", pt.x * w, -pt.y * h)
        end
        if showPlayer then
            local _, px, py = ns.PlayerMapPos(mapID)
            if px then
                local d = self:Dot()
                d:SetColorTexture(1, 0.2, 0.9, 1)
                d:SetSize(dotSize * 1.4, dotSize * 1.4)
                d:ClearAllPoints()
                d:SetPoint("CENTER", parent, "TOPLEFT", px * w, -py * h)
            end
        end
    end

    return plot
end

----------------------------------------------------------------------
-- World map overlay
----------------------------------------------------------------------

local mapOverlay, mapPlot

local function redrawWorldMap()
    if not mapOverlay or not WorldMapFrame or not WorldMapFrame:IsShown() then
        return
    end
    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local canvas = WorldMapFrame:GetCanvas()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    if not ns.db.opts.hideMapNodes then
        mapPlot:Draw(mapID, w, h, math.max(5, w / 150), nil, false)
    else
        mapPlot:Clear()
    end
end

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
            hooksecurefunc(WorldMapFrame, "OnMapChanged", ns.Guard("worldmap", redrawWorldMap))
        end
        WorldMapFrame:HookScript("OnShow", ns.Guard("worldmap", redrawWorldMap))
    end)
    if not ok then
        mapOverlay = nil
    end
end

ns.Listen("READY", function()
    C_Timer.After(3, ns.Guard("worldmap-setup", setupWorldMap))
end)
ns.On("ADDON_LOADED", function(name)
    if name == "Blizzard_WorldMap" and ns.ready then
        setupWorldMap()
    end
end)
ns.Listen("ROUTE", function() ns.Guard("worldmap", redrawWorldMap)() end)
ns.Listen("NODES_UPDATED", function() ns.Guard("worldmap", redrawWorldMap)() end)

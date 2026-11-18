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
}
ns.KIND_ORDER = { "herb", "ore", "fish" }

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

-- Zones with recorded nodes:
-- { {map=, name=, ore=, herb=, fish=, total=, skipped=, last=}, ... }
function ns.NodeZones()
    local out = {}
    for mapID, list in pairs(ns.db.nodes) do
        if #list > 0 then
            local z = { map = mapID, name = ns.MapName(mapID), ore = 0, herb = 0, fish = 0, total = #list,
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
            m.back:SetColorTexture(0, 0, 0, 0.9)
            m.icon = m:CreateTexture(nil, "ARTWORK")
            m.icon:SetPoint("CENTER")
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
                local kind = ns.KINDS[n.k]
                local m = self:Mark()
                m.node = n
                local tag = special[n]
                local s = tag and math.floor(size * 1.35) or size
                m:SetSize(s + 4 * unit, s + 4 * unit)
                m.back:SetSize(s + 2 * unit, s + 2 * unit)
                m.icon:SetSize(s, s)
                m.icon:SetTexture(kind and kind.icon or 134400)
                m.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
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
                m:EnableMouse(o.interactive and true or false)
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
    mapPlot:Draw(mapID, w, h, { size = 15 * unit, unit = unit, route = ns.route, maps = maps, project = projection(mapID) })
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
            set = function(v)
                ns.db.opts.worldMapSpots = v and true or false
                ns.RedrawWorldMap()
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
        p.back:SetColorTexture(0, 0, 0, 0.85)
        p.icon = p:CreateTexture(nil, "ARTWORK")
        p.icon:SetPoint("CENTER")
        p.icon:SetSize(12, 12)
        p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
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
        local kind = ns.KINDS[n.k]
        local p = miniPin()
        p.icon:SetTexture(kind and kind.icon or 134400)
        p.icon:SetAlpha(1)
        p.ring:SetShown(isNext)
        p:ClearAllPoints()
        p:SetPoint("CENTER", Minimap, "CENTER", x / radius * half, y / radius * half)
    end
    for _, n in ipairs(ns.db.nodes[mapID] or {}) do
        if not n.skip and n ~= next then
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

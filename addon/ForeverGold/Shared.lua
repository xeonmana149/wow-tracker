-- Forever Gold - friends' gathering spots (2026-11-26: "have it so gathered
-- nodes are shared between all my friends, like on the map")
--
-- Your own spots go to the website with the rest of webExport (Web.lua).
-- The site puts everyone's together and the WoW Forever Tracker app writes
-- them into SharedNodes.lua next to this file (ForeverGoldShared), which the
-- game reads at login or /reload.
--
-- Here they are added to ns.db.nodes beside your own, marked f = "who found
-- it", so the world map, minimap, beams and routes all use them with no
-- changes of their own. A spot near one of yours (same kind) is left out -
-- yours is already there. Every load clears the old friends' spots first,
-- so a friend's spot never piles up or gets sent back to the site as yours.
-- Gathering one makes it yours (ns.RecordNode clears the mark).
--
-- Settings > Gathering Forever > "Friends' spots" turns it off.

local _, ns = ...

local function near(list, kind, x, y)
    local radius = (kind == "fish") and 0.02 or 0.008
    for _, n in ipairs(list) do
        if n.k == kind and not n.f and math.abs(n.x - x) < radius and math.abs(n.y - y) < radius then
            return true
        end
    end
    return false
end

-- Takes every friends' spot out of the saved spots.
function ns.ClearSharedNodes()
    local removed = 0
    for mapID, list in pairs(ns.db and ns.db.nodes or {}) do
        if type(list) == "table" then
            for i = #list, 1, -1 do
                if type(list[i]) == "table" and list[i].f then
                    table.remove(list, i)
                    removed = removed + 1
                end
            end
            if #list == 0 then
                ns.db.nodes[mapID] = nil
            end
        end
    end
    return removed
end

local KINDS = { ore = true, herb = true, fish = true, chest = true }

-- Clears the old friends' spots and adds the current ones. Returns how many.
function ns.MergeSharedNodes()
    if not ns.db or type(ns.db.nodes) ~= "table" then
        return 0
    end
    ns.ClearSharedNodes()
    local added = 0
    local shared = type(ForeverGoldShared) == "table" and ForeverGoldShared or nil
    local on = not (ns.db.opts and ns.db.opts.friendSpots == false)
    if on and shared and type(shared.maps) == "table" then
        for key, spots in pairs(shared.maps) do
            local mapID = tonumber(key)
            if mapID and type(spots) == "table" then
                local list = ns.db.nodes[mapID]
                for _, s in ipairs(spots) do
                    -- { x, y, kind, name, times, last, who }
                    local x, y, k = tonumber(s[1]), tonumber(s[2]), s[3]
                    if x and y and KINDS[k] and not (list and near(list, k, x, y)) then
                        if not list then
                            list = {}
                            ns.db.nodes[mapID] = list
                        end
                        list[#list + 1] = {
                            x = x, y = y, k = k,
                            n = type(s[4]) == "string" and s[4] ~= "" and s[4] or nil,
                            c = tonumber(s[5]) or 1,
                            t = tonumber(s[6]) or nil,
                            f = type(s[7]) == "string" and s[7] ~= "" and s[7] or "a friend",
                        }
                        added = added + 1
                    end
                end
            end
        end
    end
    if ns.Fire then
        ns.Fire("NODES_UPDATED")
    end
    return added
end

ns.Listen("READY", function()
    local ok, err = pcall(ns.MergeSharedNodes)
    if not ok and ns.Err then
        ns.Err("shared spots", err)
    end
end)

-- Before the game saves: friends' spots aren't kept in your saved file
-- (the next login adds the current ones again).
ns.On("PLAYER_LOGOUT", function()
    pcall(ns.ClearSharedNodes)
end)

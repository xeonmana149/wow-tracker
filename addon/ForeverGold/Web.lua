-- Forever Gold - what the website gets
--
-- The WoW Forever Tracker app reads this addon's saved file and sends one
-- small part of it, ForeverGoldDB.webExport, to your account on the
-- website. That powers the Auction House "My auctions & gold" page:
--   * your auctions, so the site can tell you when you've been undercut
--   * each character's gold, so it can chart your gold over time
--   * your saved farming trips (the Track tab)
--   * your gathering spots, which the site shares with your friends (Shared.lua)
-- Nothing else in the saved file (prices, bags, recipes, notes) is sent.
-- The game only writes saved files at logout or /reload.

local _, ns = ...

function ns.BuildWebExport()
    local db = ns.db
    if not db then
        return
    end
    local chars = {}
    for _, c in pairs(db.chars or {}) do
        if type(c) == "table" and c.name then
            local R = c.realmKey and db.realms and db.realms[c.realmKey]
            chars[#chars + 1] = {
                name = c.name,
                faction = c.faction,
                level = c.level,
                class = c.class,
                money = c.money or 0,
                seen = c.seen or 0,
                house = R and R.marketHouse or nil,
                auctions = c.webAuctions,
            }
        end
    end
    local sessions = {}
    for i, s in ipairs(db.sessions or {}) do
        if i > 30 then
            break
        end
        sessions[i] = s
    end
    -- Your gathering spots, shared with your friends (Shared.lua). Never
    -- friends' spots (f), and nothing when "Friends' spots" is off.
    local nodes
    if not (db.opts and db.opts.friendSpots == false) then
        nodes = {}
        for mapID, list in pairs(db.nodes or {}) do
            local out = {}
            for _, n in ipairs(type(list) == "table" and list or {}) do
                if type(n) == "table" and not n.f and n.x and n.y and n.k then
                    out[#out + 1] = { n.x, n.y, n.k, n.n or "", n.c or 1, n.t or 0 }
                end
            end
            if #out > 0 then
                nodes[tostring(mapID)] = out
            end
        end
    end
    db.webExport = { v = 1, t = time(), addon = ns.VERSION, chars = chars, sessions = sessions, nodes = nodes }
end

ns.Listen("READY", function()
    ns.BuildWebExport()
end)

ns.On("PLAYER_LOGOUT", function()
    ns.BuildWebExport()
end)

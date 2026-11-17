-- Forever Gold - what an item is used for
--
-- RecipeData.lua holds every crafting recipe in WoW Forever (pulled from
-- Blizzard's own Forever data by scripts/build-forever-recipes.mjs), so a
-- tooltip can say how many recipes use an item and in which professions -
-- including professions none of your characters have.
--
-- Blizzard's web recipe ids aren't the ids the game uses, so "your
-- characters know it" is matched by profession and recipe name.

local _, ns = ...

local uses -- [itemID] = { { prof =, name = }, ... } sorted by profession, then name
local known -- ["Profession|recipe name"] = { "Char Name", ... }

local function build()
    uses = {}
    local data = ForeverGoldRecipes
    if type(data) ~= "table" or type(data.r) ~= "table" then
        return
    end
    local profs = type(data.profs) == "table" and data.profs or {}
    for _, s in pairs(data.r) do
        if type(s) == "string" then
            local p, rs, name = s:match("^(%d+)|%d+|[^|]*|([^|]*)|(.*)$")
            if p then
                local e = { prof = profs[tonumber(p)] or "?", name = name }
                local seen = {}
                for id in rs:gmatch("(%d+):%d+") do
                    id = tonumber(id)
                    if not seen[id] then
                        seen[id] = true
                        local list = uses[id]
                        if not list then
                            list = {}
                            uses[id] = list
                        end
                        list[#list + 1] = e
                    end
                end
            end
        end
    end
    for _, list in pairs(uses) do
        table.sort(list, function(a, b)
            if a.prof ~= b.prof then
                return a.prof < b.prof
            end
            return a.name < b.name
        end)
    end
end

local function buildKnown()
    known = {}
    for _, c in pairs(ns.db.chars or {}) do
        for prof, recs in pairs(c.recipes or {}) do
            for _, r in pairs(recs) do
                if r.n then
                    local key = prof .. "|" .. r.n
                    local list = known[key]
                    if not list then
                        list = {}
                        known[key] = list
                    end
                    list[#list + 1] = c.name or "another character"
                end
            end
        end
    end
end

ns.Listen("RECIPES_UPDATED", function()
    known = nil
end)

-- Every recipe that uses this item, or nil.
function ns.RecipeUses(id)
    if not uses then
        build()
    end
    return id and uses[id] or nil
end

-- Which of your characters know this recipe (a list of names), or nil.
function ns.RecipeKnownBy(prof, name)
    if not known then
        buildKnown()
    end
    return known[prof .. "|" .. name]
end

-- For the tooltip: "Tailoring 5, First Aid 2", total count, how many you know.
function ns.RecipeUseSummary(id)
    local list = ns.RecipeUses(id)
    if not list or #list == 0 then
        return nil
    end
    local order, counts, mine = {}, {}, 0
    for _, e in ipairs(list) do
        if not counts[e.prof] then
            counts[e.prof] = 0
            order[#order + 1] = e.prof
        end
        counts[e.prof] = counts[e.prof] + 1
        if ns.RecipeKnownBy(e.prof, e.name) then
            mine = mine + 1
        end
    end
    -- Most-used profession first.
    table.sort(order, function(a, b)
        if counts[a] ~= counts[b] then
            return counts[a] > counts[b]
        end
        return a < b
    end)
    local bits = {}
    for _, prof in ipairs(order) do
        bits[#bits + 1] = prof .. " " .. counts[prof]
    end
    return table.concat(bits, ", "), #list, mine, list
end

-- Standalone guide. Native map art works independently; when installed, the
-- separate Dungeon Journal can provide its custom maps and recorded pins.
local _, ns = ...
local G = { category = "dungeon", view = "Bosses", instanceOffset = 0, entryOffset = 0 }
ns.InstanceGuide = G

local function button(parent, caption, width, height)
    local b = CreateFrame("Button", nil, parent); b:SetSize(width, height); ns.Panel(b, { edge = 0.7 })
    b.text = ns.Text(b, 11, ns.C.text); b.text:SetPoint("CENTER"); b.text:SetText(caption)
    local h = b:CreateTexture(nil, "HIGHLIGHT"); h:SetAllPoints(); h:SetColorTexture(1, 0.85, 0.48, 0.12)
    return b
end
local function text(parent, size, color, point, x, y, width)
    local t = ns.Text(parent, size, color); t:SetPoint(point, x, y); t:SetWidth(width); t:SetJustifyH("LEFT"); t:SetJustifyV("TOP"); return t
end
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...); if ok and not ns.Secret(value) then return value end
end

-- Client map IDs and tile prefixes. These remain usable without the journal.
local nativeMaps = {
    ["Ragefire Chasm"] = {{213, "Ragefire", 1}},
    ["The Deadmines"] = {{291, "TheDeadmines", 1}, {292, "TheDeadmines", 2}},
    ["Wailing Caverns"] = {{279, "WailingCaverns", 1}},
    ["Shadowfang Keep"] = {{310, "ShadowfangKeep", 1}, {316, "ShadowfangKeep", 7}, {315, "ShadowfangKeep", 6}},
    ["Blackfathom Deeps"] = {{221, "BlackFathomDeeps", 1}, {222, "BlackFathomDeeps", 2}, {223, "BlackFathomDeeps", 3}},
    ["The Stockade"] = {{225, "TheStockade", 1}},
    ["Gnomeregan"] = {{226, "Gnomeregan", 1}, {227, "Gnomeregan", 2}, {228, "Gnomeregan", 3}, {229, "Gnomeregan", 4}},
    ["Razorfen Kraul"] = {{301, "RazorfenKraul", 1}},
    ["Razorfen Downs"] = {{300, "RazorfenDowns", 1}},
    ["Scarlet Monastery: Graveyard"] = {{302, "ScarletMonastery", 1}},
    ["Scarlet Monastery: Library"] = {{303, "ScarletMonastery", 2}},
    ["Scarlet Monastery: Armory"] = {{304, "ScarletMonastery", 3}},
    ["Scarlet Monastery: Cathedral"] = {{305, "ScarletMonastery", 4}},
    ["Uldaman"] = {{230, "Uldaman", 1}, {231, "Uldaman", 2}},
    ["Blackrock Depths"] = {{242, "BlackrockDepths", 1}, {243, "BlackrockDepths", 2}},
    ["Dire Maul: North"] = {{235, "DireMaul", 1}},
    ["Dire Maul: West"] = {{236, "DireMaul", 2}, {237, "DireMaul", 3}, {238, "DireMaul", 4}},
    ["Dire Maul: East"] = {{240, "DireMaul", 6}, {239, "DireMaul", 5}},
    ["Maraudon"] = {{280, "Maraudon", 1}, {281, "Maraudon", 2}},
    ["Stratholme"] = {{317, "Stratholme", 1}, {318, "Stratholme", 2}},
    ["Scholomance"] = {{306, "ScholomanceOLD", 1}, {307, "ScholomanceOLD", 2}, {308, "ScholomanceOLD", 3}, {309, "ScholomanceOLD", 4}},
}

function G:MapData(dungeon)
    if not dungeon or not dungeon.name then return end
    local journal = _G.ForeverDungeonJournal_NS
    local maps = type(journal) == "table" and journal.DUNGEON_MAPS
    local name = dungeon.name == "The Temple of Atal'Hakkar" and "Sunken Temple" or dungeon.name
    local data = type(maps) == "table" and maps[name]
    if type(data) == "table" and type(data.floors) == "table" and #data.floors > 0 then return data, "Dungeon Journal" end
    local entries = nativeMaps[dungeon.name]
    if not entries then return end
    local result = { floors = {} }
    for _, entry in ipairs(entries) do
        result.floors[#result.floors + 1] = { uiMapID = entry[1], tiles = "Interface\\WorldMap\\" .. entry[2] .. "\\" .. entry[2] .. entry[3] .. "_" }
    end
    return result, "Game map"
end

local function questStatusText(status)
    if status == "Completed" or status == "Ready to turn in" then return "|cff59d966" .. status .. "|r" end
    if status == "In progress" then return "|cffffd140" .. status .. "|r" end
    return status == "Not recorded" and "Not completed" or status or "Unknown"
end
local function questStatus(quest)
    local page = ns.Encyclopedia and ns.Encyclopedia.QuestPage
    if page then return page.Status({ data = quest }) end
    return "Unknown"
end
function G:Instances()
    local list = {}
    for _, d in ipairs(ns.IndependentReference and ns.IndependentReference.DUNGEONS or {}) do
        if (d.raid and true or false) == (self.category == "raid") then list[#list + 1] = d end
    end
    table.sort(list, function(a, b)
        local al = tonumber(tostring(a.level or ""):match("%d+")) or 999
        local bl = tonumber(tostring(b.level or ""):match("%d+")) or 999
        if al ~= bl then return al < bl end
        return (a.name or "") < (b.name or "")
    end)
    return list
end
function G:QuestProgress(dungeon)
    local tracker = ns.DungeonQuestTracker
    local quests = tracker and tracker:Quests(dungeon) or dungeon and dungeon.quests or {}
    local total, done, unknown, seen = 0, 0, false, {}
    for _, q in ipairs(quests) do
        local id = tonumber(q.id)
        local applicable = not tracker or tracker:QuestVisible(q)
        if id and id > 0 and applicable and not seen[id] then
            seen[id] = true; total = total + 1
            local status = questStatus(q)
            if status == "Completed" then done = done + 1 elseif status == "Unknown" then unknown = true end
        end
    end
    return done, total, unknown
end
function G:SelectDungeon(d)
    self.dungeon, self.entry, self.entryOffset, self.lootOffset = d, nil, 0, 0
    self.mapFloor, self.mapDungeon = 1, d
    self:Render()
end

-- Reuse the client map tiles; optional journal data supplies custom artwork,
-- floor patches and recorded markers without copying its files into our addon.
function G:RenderMap(d)
    local panel = self.frame.mapPanel
    local canvas = panel.canvas
    for _, texture in ipairs(canvas.tiles) do texture:Hide() end
    for _, texture in ipairs(canvas.patches) do texture:Hide() end
    for _, pin in ipairs(canvas.pins) do pin:Hide() end
    canvas.entrance:Hide(); canvas.art:Hide()
    local data, source = self:MapData(d)
    if self.mapDungeon ~= d then self.mapDungeon, self.mapFloor = d, 1 end
    local floors = data and data.floors
    local count = type(floors) == "table" and #floors or 0
    self.mapFloor = math.max(1, math.min(self.mapFloor or 1, math.max(1, count)))
    local floor = floors and floors[self.mapFloor]
    panel.previous:SetShown(count > 1); panel.next:SetShown(count > 1)
    panel.floor:SetShown(count > 0); canvas:SetShown(count > 0)
    if not floor then
        panel.message:Show()
        panel.message:SetText("Interior map not available for this instance.\n\nYou can still show its entrance on the world map.")
        panel.floor:SetText("")
        return
    end
    panel.message:Hide()
    panel.floor:SetText((floor.label or ("Floor " .. self.mapFloor)) .. "  •  " .. self.mapFloor .. " / " .. count .. "  •  " .. source)
    local width, height = 600, 400
    local displayed = false
    if type(floor.texture) == "string" then
        canvas.art:SetTexture(floor.texture)
        canvas.art:SetTexCoord(0, floor.texRight or 1, 0, floor.texBottom or 1)
        canvas.art:Show(); displayed = true
    else
        local layers = floor.uiMapID and C_Map and safe(C_Map.GetMapArtLayers, floor.uiMapID)
        local layer = type(layers) == "table" and layers[1]
        local files = layer and C_Map and safe(C_Map.GetMapArtLayerTextures, floor.uiMapID, 1)
        local lw, lh, tw, th
        if type(layer) == "table" and type(files) == "table" then
            lw, lh, tw, th = layer.layerWidth, layer.layerHeight, layer.tileWidth, layer.tileHeight
        end
        local valid = type(lw) == "number" and type(lh) == "number" and type(tw) == "number" and type(th) == "number"
            and lw > 0 and lh > 0 and tw > 0 and th > 0 and math.ceil(lw/tw) * math.ceil(lh/th) <= 64
        if not valid and type(floor.tiles) == "string" then lw, lh, tw, th, files = 1002, 668, 256, 256, nil; valid = true end
        if valid then
            local cols, rows, index = math.ceil(lw/tw), math.ceil(lh/th), 0
            for y = 0, rows - 1 do for x = 0, cols - 1 do
                index = index + 1
                local path = files and files[index] or (not files and floor.tiles .. index)
                if path then
                    local tile = canvas.tiles[index]
                    if not tile then tile = canvas:CreateTexture(nil, "ARTWORK"); canvas.tiles[index] = tile end
                    local px, py = x * tw, y * th
                    local partW, partH = math.min(tw, lw - px), math.min(th, lh - py)
                    local loaded = tile:SetTexture(path)
                    if loaded == false and files and type(floor.tiles) == "string" then loaded = tile:SetTexture(floor.tiles .. index) end
                    tile:SetTexCoord(0, partW/tw, 0, partH/th)
                    tile:SetSize(width * partW/lw, height * partH/lh)
                    tile:ClearAllPoints(); tile:SetPoint("TOPLEFT", canvas, "TOPLEFT", width * px/lw, -height * py/lh)
                    if loaded ~= false then tile:Show(); displayed = true end
                end
            end end
        end
    end
    if not displayed then
        canvas:Hide(); panel.message:Show(); panel.message:SetText("The map artwork is unavailable in this client.")
        return
    end
    for i, patch in ipairs(floor.patches or {}) do
        if type(patch.tex) == "string" and type(patch.x0) == "number" and type(patch.x1) == "number"
            and type(patch.y0) == "number" and type(patch.y1) == "number" and patch.x1 > patch.x0 and patch.y1 > patch.y0 then
            local texture = canvas.patches[i]
            if not texture then texture = canvas:CreateTexture(nil, "OVERLAY", nil, 1); canvas.patches[i] = texture end
            texture:SetTexture(patch.tex); texture:SetSize(width*(patch.x1-patch.x0), height*(patch.y1-patch.y0))
            texture:ClearAllPoints(); texture:SetPoint("TOPLEFT", canvas, "TOPLEFT", width*patch.x0, -height*patch.y0)
            texture:SetAlpha(patch.alpha or 1); texture:Show()
        end
    end
    local entrance = data.entrance
    if type(entrance) == "table" and (entrance.floor or 1) == self.mapFloor
        and type(entrance.x) == "number" and type(entrance.y) == "number"
        and entrance.x >= 0 and entrance.x <= 1 and entrance.y >= 0 and entrance.y <= 1 then
        canvas.entrance:ClearAllPoints(); canvas.entrance:SetPoint("CENTER", canvas, "TOPLEFT", width*entrance.x, -height*entrance.y)
        canvas.entrance:Show()
    end
    local used = 0
    for _, boss in ipairs(data.bosses or {}) do
        if type(boss.name) == "string" and type(boss.x) == "number" and type(boss.y) == "number"
            and boss.x >= 0 and boss.x <= 1 and boss.y >= 0 and boss.y <= 1 and (boss.floor or 1) == self.mapFloor then
            used = used + 1
            local pin = canvas.pins[used]
            if not pin then
                pin = CreateFrame("Button", nil, canvas); pin:SetSize(25, 25); ns.Panel(pin, {alpha=0.95, edge=0.9})
                pin.icon = pin:CreateTexture(nil, "ARTWORK"); pin.icon:SetPoint("TOPLEFT", 2, -2); pin.icon:SetPoint("BOTTOMRIGHT", -2, 2)
                pin:SetScript("OnEnter", function(self) if GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText(self.bossName, 1, 0.82, 0); if self.value then GameTooltip:AddLine("Click for boss details", 1, 1, 1) end; GameTooltip:Show() end end)
                pin:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                pin:SetScript("OnClick", function(self) if self.value then G.view, G.entry, G.entryOffset = "Bosses", self.value, 0; G.frame.detailPanel.offset = 0; G:Render() end end)
                canvas.pins[used] = pin
            end
            pin.bossName, pin.value = boss.name, nil
            for _, candidate in ipairs(d.bosses or {}) do if type(candidate.name) == "string" and candidate.name:lower() == boss.name:lower() then pin.value = candidate; break end end
            pin.icon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\instance-guide")
            if pin.value and ns.Encyclopedia and ns.Encyclopedia.EntryIcon then ns.Encyclopedia.EntryIcon(pin.icon, {kind="boss", data=pin.value, links={{kind="dungeon", data=d}}}) end
            pin:ClearAllPoints(); pin:SetPoint("CENTER", canvas, "TOPLEFT", width*boss.x, -height*boss.y); pin:Show()
        end
    end
end
function G:OpenMap()
    local d, ref, enc = self.dungeon, ns.IndependentReference, ns.Encyclopedia
    local id = d and ref and ref.MAP_IDS and ref.MAP_IDS[d.mapZone]
    if d and id and d.mapX and d.mapY and enc and enc.ShowLocation and enc.ShowLocation(id, d.mapX, d.mapY) then
        if self.frame then self.frame:Hide() end
    else
        ns.Print("No recorded entrance location for this instance.")
    end
end
function G:QuestLocation(q)
    local enc = ns.Encyclopedia
    local loc = q and enc and enc.QuestStartLocation and enc.QuestStartLocation({data=q})
    if loc then return loc end
    local starts = q and q.starts
    if type(starts) ~= "string" then return end
    local x, y = starts:match("%((%d+%.?%d*)%s*,%s*(%d+%.?%d*)%)")
    x, y = tonumber(x), tonumber(y)
    if not x or not y or x > 100 or y > 100 then return end
    local match, mapID
    for zone, id in pairs(ns.IndependentReference and ns.IndependentReference.MAP_IDS or {}) do
        if type(zone) == "string" and type(id) == "number" and starts:lower():find(zone:lower(), 1, true)
            and (not match or #zone > #match) then match, mapID = zone, id end
    end
    if mapID then return {mapID=mapID, x=x, y=y} end
end
-- Only explicit links are used to build a linear quest chain. Branching or
-- incomplete data remains separate instead of pretending alternatives are required.
function G:QuestRows(dungeon)
    local tracker = ns.DungeonQuestTracker
    local source = tracker and tracker:Quests(dungeon) or dungeon and dungeon.quests or {}
    local faction = safe(UnitFactionGroup, "player")
    faction = type(faction) == "string" and faction:lower() or nil
    local class
    if type(UnitClass) == "function" then
        local ok, _, token = pcall(UnitClass, "player")
        if ok and not ns.Secret(token) and type(token) == "string" then class = token:upper() end
    end
    self.chainOpen = self.chainOpen or {}
    self.chainCache = self.chainCache or {}
    local function flatten(groups)
        local rows = {}
        for _, chain in ipairs(groups) do
            local first = chain[1].id
            rows[#rows + 1] = { quest = chain[1], chain = #chain > 1 and chain or nil, root = first, depth = 0,
                chainIndex = #chain > 1 and 1 or nil, chainLength = #chain > 1 and #chain or nil,
                optionalLeadIn = tonumber(first) == 6562 }
            if #chain > 1 and self.chainOpen[first] then
                for i = 2, #chain do rows[#rows + 1] = { quest = chain[i], root = first, depth = 1, chainIndex = i, chainLength = #chain, optionalLeadIn = tonumber(first) == 6562 } end
            end
        end
        return rows
    end
    local cached = self.chainCache[dungeon]
    if cached and cached.faction == faction and cached.class == class then return flatten(cached.groups) end
    local function allowed(q)
        if tracker then return tracker:QuestVisible(q) end
        local side = tostring(q.side or ""):lower()
        return not faction or side == "" or side == "both" or side == faction
            or side == "h" and faction == "horde" or side == "a" and faction == "alliance"
    end
    local byID, referenceByID, dungeonIDs = {}, {}, {}
    for _, q in ipairs(ns.BulkReferenceData and ns.BulkReferenceData.quests or {}) do
        if type(q.id) == "number" and not byID[q.id] then byID[q.id] = q; referenceByID[q.id] = q end
    end
    for _, q in ipairs(source) do if type(q.id) == "number" then byID[q.id] = q; dungeonIDs[q.id] = true end end
    local discoveries = ns.QuestDiscoveryData and ns.QuestDiscoveryData.records or {}
    -- The quest pin reference records this missing link in the five-part
    -- Unending Torment chain. Its full quest details are not yet in our data.
    if dungeon.key == "lordaeron" and not byID[97290] and byID[97289] and byID[97291] then
        byID[97290] = {id=97290, name="Unending Torment", side="Horde", level=21,
            note="Quest details have not been recorded yet.", classic={previous=97289, next=97291}}
    end
    local function single(value)
        if type(value) == "table" and #value == 1 then return tonumber(value[1]) end
        if type(value) ~= "table" then return tonumber(value) end
    end
    local function links(q)
        local fallback = referenceByID[tonumber(q.id)]
        if fallback and (type(fallback.name) ~= "string" or fallback.name:lower() ~= tostring(q.name or ""):lower()) then fallback = nil end
        local classic = q.classic or (fallback and fallback.classic) or {}
        local nextID = dungeonIDs[q.id] and safe(QuestDB and QuestDB.nextQuestInChain, q.id) or nil
        local discovery = discoveries[tonumber(q.id)]
        if type(discovery) ~= "table" or type(discovery.name) ~= "string" or discovery.name:lower() ~= tostring(q.name or ""):lower() then discovery = nil end
        if type(nextID) ~= "number" or nextID <= 0 then nextID = single(classic.next) or (discovery and single(discovery.next)) end
        local prevID = single(classic.previous) or (discovery and single(discovery.previous))
        if not prevID and QuestDB and dungeonIDs[q.id] then
            local group = safe(QuestDB.preQuestGroup, q.id)
            local single = safe(QuestDB.preQuestSingle, q.id)
            if type(group) == "table" and #group == 1 then prevID = group[1]
            elseif type(single) == "table" and #single == 1 then prevID = single[1] end
        end
        return tonumber(prevID), tonumber(nextID)
    end
    local nextByID, prevByID, inbound = {}, {}, {}
    for id, q in pairs(byID) do
        local prev, nextID = links(q)
        if prev and prev > 0 and byID[prev] then prevByID[id] = prev end
        if nextID and nextID > 0 and byID[nextID] then
            nextByID[id] = nextID; inbound[nextID] = (inbound[nextID] or 0) + 1
        end
    end
    for id, previous in pairs(prevByID) do
        if not nextByID[previous] then nextByID[previous] = id; inbound[id] = (inbound[id] or 0) + 1
        elseif nextByID[previous] ~= id then nextByID[previous] = false end
    end
    local groups, included = {}, {}
    for _, q in ipairs(source) do
        local id = tonumber(q.id)
        if id and allowed(q) and not included[id] then
            local first, seen = id, {}
            while prevByID[first] and not seen[first] do
                seen[first] = true
                local previous = prevByID[first]
                if not byID[previous] or not allowed(byID[previous]) or nextByID[previous] ~= first or (inbound[first] or 0) > 1 then break end
                first = previous
            end
            local chain, current, visited = {}, first, {}
            while current and byID[current] and allowed(byID[current]) and not visited[current] and #chain < 30 do
                visited[current] = true; chain[#chain + 1] = byID[current]
                local nextID = nextByID[current]
                if type(nextID) ~= "number" or (inbound[nextID] or 0) > 1 then break end
                current = nextID
            end
            if not visited[id] then chain = {q}; first = id end
            for _, step in ipairs(chain) do included[step.id] = true end
            groups[#groups + 1] = chain
        end
    end
    self.chainCache[dungeon] = {faction=faction, class=class, groups=groups}
    return flatten(groups)
end

local function itemIcon(id)
    return id and (safe(C_Item and C_Item.GetItemIconByID, id) or safe(GetItemIcon, id)) or nil
end
local function showItem(row)
    if not (row.value and row.value.id and GameTooltip) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(row.value.id); GameTooltip:Show()
end
local function makeItemRow(parent, width)
    local row = button(parent, "", width, 38)
    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(30, 30); row.icon:SetPoint("LEFT", 4, 0)
    row.text:ClearAllPoints(); row.text:SetPoint("LEFT", 42, 0); row.text:SetWidth(width - 50); row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
    row:SetScript("OnEnter", showItem); row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row:SetScript("OnClick", function(self)
        local item = self.value
        if item and item.id and IsControlKeyDown and IsControlKeyDown() and DressUpItemLink then pcall(DressUpItemLink, "item:" .. item.id) end
    end)
    return row
end

function G:Render()
    local f = self.frame; if not f then return end
    local instances = self:Instances()
    local query = (self.search or ""):lower():match("^%s*(.-)%s*$")
    if query ~= "" then
        local filtered = {}
        for _, d in ipairs(instances) do
            local hit = tostring(d.name or ""):lower():find(query, 1, true) ~= nil
            for _, b in ipairs(d.bosses or {}) do
                if tostring(b.name or ""):lower():find(query, 1, true) then hit = true end
                for _, item in ipairs(b.loot or {}) do if tostring(item.name or ""):lower():find(query, 1, true) then hit = true end end
            end
            local tracker = ns.DungeonQuestTracker
            for _, q in ipairs(tracker and tracker:Quests(d) or d.quests or {}) do
                if (not tracker or tracker:QuestVisible(q)) and tostring(q.name or ""):lower():find(query, 1, true) then hit = true end
            end
            if hit then filtered[#filtered + 1] = d end
        end
        instances = filtered
    end
    local overview = self.dungeon == nil
    f.instances:SetShown(overview); f.browseHeading:SetShown(overview)
    f.back:SetShown(not overview); f.banner:SetShown(not overview); f.detailBody:SetShown(not overview)
    for name, b in pairs(f.categories) do b:SetShown(overview); b.fuiPanel.bright = name == self.category; ns.PaintPanel(b) end
    f.search:SetShown(overview)
    f.title:SetText("Instance Guide")
    local totalRows = math.ceil(#instances / 2)
    self.instanceOffset = math.max(0, math.min(self.instanceOffset or 0, math.max(0, totalRows - 3)))
    ns.UpdateListScrollbar(f.instances.scrollbar, self.instanceOffset, totalRows - 3)
    for i, card in ipairs(f.instances.rows) do
        local d = instances[self.instanceOffset * 2 + i]; card.value = d; card:SetShown(overview and d ~= nil)
        if d then
            local art, l, r, t, b = ns.Encyclopedia.DungeonArt(d, 464, 146)
            card.art:SetShown(art ~= nil); if art then card.art:SetTexture(art); card.art:SetTexCoord(l, r, t, b) end
            card.name:SetText(d.name or "Unknown")
            card.level:SetText("Level " .. tostring(d.level or "?"))
            local done, total, unknown = self:QuestProgress(d)
            card.count:SetText(total > 0 and ((unknown and "?" or done) .. "/" .. total .. " quests") or "")
        end
    end
    if overview then return end
    local d = self.dungeon
    f.banner.name:SetText(d.name or "Unknown")
    f.banner.meta:SetText("Level " .. tostring(d.level or "?") .. "  •  " .. tostring(d.mapZone or d.area or "Location unknown"))
    local art, l, r, t, b = ns.Encyclopedia.DungeonArt(d, 112, 56)
    f.banner.art:SetShown(art ~= nil); if art then f.banner.art:SetTexture(art); f.banner.art:SetTexCoord(l, r, t, b) end
    for name, tab in pairs(f.views) do tab.fuiPanel.bright = name == self.view; ns.PaintPanel(tab) end
    local mapMode, questMode = self.view == "Map", self.view == "Quests"
    f.mapPanel:SetShown(mapMode); f.entries:SetShown(not mapMode); f.detailPanel:SetShown(not mapMode)
    f.track:SetShown(questMode); f.map:SetShown(mapMode)
    local tracker = ns.DungeonQuestTracker
    f.track.text:SetText(tracker and tracker:GetTracked() == d.key and "Stop tracking" or "Track quests")
    if mapMode then
        self:RenderMap(d)
        return
    end
    local rows = {}
    if questMode then rows = self:QuestRows(d)
    else for _, boss in ipairs(d.bosses or {}) do rows[#rows + 1] = {boss=boss} end end
    if not self.entry then
        for _, row in ipairs(rows) do if row.quest or row.boss then self.entry = row.quest or row.boss; break end end
    end
    self.entryOffset = math.max(0, math.min(self.entryOffset or 0, math.max(0, #rows - #f.entries.rows)))
    ns.UpdateListScrollbar(f.entries.scrollbar, self.entryOffset, #rows - #f.entries.rows)
    local _, questCount = self:QuestProgress(d)
    f.entries.heading:SetText((questMode and "Quests" or "Bosses") .. "  |  " .. (questMode and questCount or #(d.bosses or {})))
    local rowTop = -44
    for i, row in ipairs(f.entries.rows) do
        local data = rows[self.entryOffset + i]; row.data = data; row.value = data and (data.quest or data.boss); row:SetShown(data ~= nil)
        if data then
            local obj = row.value; local status = questMode and questStatus(obj) or nil
            local step = questMode and data.depth == 1
            local height = step and 42 or 55
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", f.entries, "TOPLEFT", step and 25 or 8, rowTop)
            row:SetSize(step and 340 or 357, height)
            rowTop = rowTop - height - 4
            row.icon:SetSize(step and 27 or 38, step and 27 or 38)
            row.name:ClearAllPoints(); row.name:SetPoint("TOPLEFT", row, "TOPLEFT", step and 42 or 53, step and -5 or -9)
            row.sub:ClearAllPoints(); row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", step and 42 or 53, step and 5 or 8)
            row.name:SetWidth(step and 225 or 235); row.sub:SetWidth(step and 225 or 235)
            row.name:SetText(obj.name or "Unknown")
            local bossLevel = obj.level or (ns.IndependentReference and ns.IndependentReference.BOSS_LEVELS
                and (ns.IndependentReference.BOSS_LEVELS[obj.npcID] or ns.IndependentReference.BOSS_LEVELS[obj.name]))
            row.sub:SetText(questMode and ((data.optionalLeadIn and (data.depth == 0 and "Optional lead-in  •  " or "Has optional lead-in  •  ") or data.chainIndex and ("Chain " .. data.chainIndex .. "/" .. data.chainLength .. "  •  ") or "") .. (obj.required and ("Level " .. obj.required .. "+  •  ") or "") .. questStatusText(status))
                or ("Level " .. tostring(bossLevel or "?")))
            if questMode and status == "Completed" then row.name:SetTextColor(0.35, 0.85, 0.4)
            elseif questMode and (status == "In progress" or status == "Ready to turn in") then row.name:SetTextColor(1, 0.82, 0.25)
            else row.name:SetTextColor(ns.C.text[1], ns.C.text[2], ns.C.text[3]) end
            row.chain:SetShown(data.chain ~= nil)
            row.chainIcon:SetShown(questMode and data.chainIndex ~= nil)
            if data.chain then row.chain.text:SetText(self.chainOpen[data.root] and "−" or "+") end
            local entry = {kind = questMode and "quest" or "boss", data = obj, links = {{kind="dungeon", data=d}}}
            ns.Encyclopedia.EntryIcon(row.icon, entry)
            row.fuiPanel.bright = obj == self.entry; ns.PaintPanel(row)
        end
    end
    local selected = self.entry
    f.detailPanel.name:SetText(selected and selected.name or (questMode and "No quests recorded" or "No bosses recorded"))
    local selectedStatus = selected and questStatus(selected)
    local selectedLevel = selected and (selected.level or (ns.IndependentReference and ns.IndependentReference.BOSS_LEVELS
        and (ns.IndependentReference.BOSS_LEVELS[selected.npcID] or ns.IndependentReference.BOSS_LEVELS[selected.name])))
    f.detailPanel.meta:SetText(selected and (questMode and (questStatusText(selectedStatus) .. "  •  " .. tostring(selected.side or "Faction unknown") .. (selected.required and ("  •  Level " .. selected.required .. "+") or "")) or ("Level " .. tostring(selectedLevel or "?"))) or "")
    f.questMap:SetShown(questMode and selected ~= nil)
    local content, pos = f.detailPanel.content, -9
    local function addLine(label, value)
        local field = content.fields[label]; field.label:ClearAllPoints(); field.label:SetPoint("TOPLEFT", 8, pos)
        field.value:ClearAllPoints(); field.value:SetPoint("TOPLEFT", 8, pos - 19); field.value:SetText(value or "Not recorded")
        field.label:SetShown(true); field.value:SetShown(true)
        pos = pos - 23 - math.max(14, field.value:GetStringHeight() or 14) - 10
    end
    for _, field in pairs(content.fields) do field.label:Hide(); field.value:Hide() end
    local items = {}
    if selected and questMode then
        addLine("OBJECTIVE", selected.objective)
        addLine("STARTS", selected.starts)
        addLine("TURN IN", selected.turnin)
        addLine("REWARDS", selected.rewardSummary or "Items below, where recorded")
        local seen = {}
        for _, collection in ipairs({ selected.rewards or {}, selected.alsoRewards or {} }) do for _, item in ipairs(collection) do
            local key = item.id or item.name; if key and not seen[key] then seen[key] = true; items[#items + 1] = item end
        end end
    elseif selected then
        addLine("LOOT", #(selected.loot or {}) > 0 and "Hover over an item for its details." or "No loot recorded.")
        items = selected.loot or {}
    end
    for i, row in ipairs(content.items) do
        local item = items[i]; row.value = item; row:SetShown(item ~= nil)
        if item then
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 8, pos); pos = pos - 42
            row.text:SetText(item.name or ("Item " .. tostring(item.id or "?")))
            local quality = item.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality]
            if quality then row.text:SetTextColor(quality.r, quality.g, quality.b) else row.text:SetTextColor(ns.C.text[1], ns.C.text[2], ns.C.text[3]) end
            row.icon:SetTexture(itemIcon(item.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
        end
    end
    content.more:SetText(#items > #content.items and ("+" .. (#items - #content.items) .. " more items") or "")
    content.more:ClearAllPoints(); content.more:SetPoint("TOPLEFT", 8, pos)
    local height = math.max(366, -pos + 35); content:SetHeight(height)
    local maxOffset = math.max(0, height - 366)
    f.detailPanel.offset = math.min(f.detailPanel.offset or 0, maxOffset)
    f.detailPanel.scroll:SetVerticalScroll(f.detailPanel.offset)
    ns.UpdateListScrollbar(f.detailPanel.scrollbar, f.detailPanel.offset, maxOffset)
end

function G:Build()
    if self.frame then return end
    local f = CreateFrame("Frame", "ForeverUIInstanceGuide", UIParent); self.frame = f
    f:SetSize(1000, 660); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true); f:EnableMouse(true); ns.Panel(f)
    f:SetMovable(true); f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", function(self) if not InCombatLockdown or not InCombatLockdown() then self:StartMoving() end end); f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    ns.RememberWindow(f, "instanceGuide")
    f.title = ns.Text(f, 18, ns.C.bright); f.title:SetPoint("TOP", 0, -15); f.title:SetWidth(420); f.title:SetJustifyH("CENTER")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetSize(30, 30); close:SetPoint("TOPRIGHT", -6, -5); close:SetScript("OnClick", function() f:Hide() end)
    f.search = CreateFrame("EditBox", nil, f, "InputBoxTemplate"); f.search:SetSize(240, 25); f.search:SetPoint("TOPLEFT", 18, -12); f.search:SetAutoFocus(false)
    f.searchHint = text(f.search, 10, ns.C.muted, "LEFT", 8, 0, 220); f.searchHint:SetText("Search instances, bosses, loot...")
    f.search:SetScript("OnTextChanged", function(self) G.search = self:GetText() or ""; f.searchHint:SetShown(G.search == ""); G.instanceOffset = 0; G:Render() end)
    f.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.browseHeading = text(f, 11, ns.C.muted, "TOPRIGHT", -28, -62, 280); f.browseHeading:SetJustifyH("RIGHT"); f.browseHeading:SetText("Choose a dungeon or raid")
    f.categories = {}
    for i, spec in ipairs({{"dungeon", "Dungeons"}, {"raid", "Raids"}}) do
        local b = button(f, spec[2], 125, 28); b:SetPoint("TOPLEFT", 18 + (i - 1) * 131, -54)
        b:SetScript("OnClick", function() G.category, G.dungeon, G.entry, G.instanceOffset, G.entryOffset = spec[1], nil, nil, 0, 0; G:Render() end); f.categories[spec[1]] = b
    end
    f.back = button(f, "<  All instances", 126, 28); f.back:SetPoint("TOPLEFT", 18, -54)
    f.back:SetScript("OnClick", function() G.dungeon, G.entry = nil, nil; G:Render() end)
    local list = CreateFrame("Frame", nil, f); f.instances = list; list:SetPoint("TOPLEFT", 18, -96); list:SetSize(950, 548); list.rows = {}
    for i = 1, 6 do
        local card = button(list, "", 464, 166); card:SetPoint("TOPLEFT", ((i - 1) % 2) * 474, -math.floor((i - 1) / 2) * 178)
        card.text:Hide(); card.art = card:CreateTexture(nil, "ARTWORK"); card.art:SetPoint("TOPLEFT", 1, -1); card.art:SetPoint("BOTTOMRIGHT", -1, 1)
        local top = card:CreateTexture(nil, "OVERLAY"); top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1); top:SetHeight(34); top:SetColorTexture(0.04, 0.035, 0.03, 0.8)
        local bottom = card:CreateTexture(nil, "OVERLAY"); bottom:SetPoint("BOTTOMLEFT", 1, 1); bottom:SetPoint("BOTTOMRIGHT", -1, 1); bottom:SetHeight(24); bottom:SetColorTexture(0.04, 0.035, 0.03, 0.8)
        card.name = text(card, 14, ns.C.bright, "TOPLEFT", 10, -9, 300)
        card.count = text(card, 10, ns.C.text, "TOPRIGHT", -10, -10, 125); card.count:SetJustifyH("RIGHT")
        card.level = text(card, 10, ns.C.text, "BOTTOMLEFT", 10, 6, 200)
        card:SetScript("OnClick", function(self) if self.value then G:SelectDungeon(self.value) end end); list.rows[i] = card
    end
    list.scrollbar = ns.ListScrollbar(list, function(offset) G.instanceOffset = offset; G:Render() end)
    list:EnableMouseWheel(true); list:SetScript("OnMouseWheel", function(_, delta) G.instanceOffset = G.instanceOffset - delta; G:Render() end)
    f.banner = CreateFrame("Frame", nil, f); f.banner:SetPoint("TOPLEFT", 18, -92); f.banner:SetSize(950, 72); ns.Panel(f.banner, {edge=0.7})
    f.banner.art = f.banner:CreateTexture(nil, "ARTWORK"); f.banner.art:SetSize(112, 56); f.banner.art:SetPoint("LEFT", 7, 0)
    f.banner.name = text(f.banner, 17, ns.C.bright, "TOPLEFT", 130, -12, 360)
    f.banner.meta = text(f.banner, 10, ns.C.muted, "TOPLEFT", 130, -41, 360)
    f.views = {}
    for i, name in ipairs({"Map", "Bosses", "Quests"}) do
        local tab = button(f.banner, name, 112, 30); tab:SetPoint("RIGHT", f.banner, "RIGHT", -8 - (3 - i) * 118, 0)
        tab:SetScript("OnClick", function() G.view, G.entry, G.entryOffset, G.lootOffset = name, nil, 0, 0; f.detailPanel.offset = 0; G:Render() end); f.views[name] = tab
    end
    f.detailBody = CreateFrame("Frame", nil, f); f.detailBody:SetPoint("TOPLEFT", 18, -176); f.detailBody:SetSize(950, 468)
    local body = f.detailBody
    f.mapPanel = CreateFrame("Frame", nil, body); f.mapPanel:SetAllPoints(); ns.Panel(f.mapPanel, {edge=0.55})
    f.mapPanel.message = text(f.mapPanel, 13, ns.C.text, "TOPLEFT", 18, -18, 800); f.mapPanel.message:SetWordWrap(true)
    f.mapPanel.floor = text(f.mapPanel, 11, ns.C.bright, "TOPLEFT", 180, -12, 590)
    f.mapPanel.previous = button(f.mapPanel, "<", 28, 24); f.mapPanel.previous:SetPoint("TOPLEFT", 18, -12)
    f.mapPanel.next = button(f.mapPanel, ">", 28, 24); f.mapPanel.next:SetPoint("LEFT", f.mapPanel.previous, "RIGHT", 4, 0)
    f.mapPanel.previous:SetScript("OnClick", function() G.mapFloor = math.max(1, (G.mapFloor or 1) - 1); G:Render() end)
    f.mapPanel.next:SetScript("OnClick", function() G.mapFloor = (G.mapFloor or 1) + 1; G:Render() end)
    local canvas = CreateFrame("Frame", nil, f.mapPanel); f.mapPanel.canvas = canvas
    canvas:SetSize(600, 400); canvas:SetPoint("TOP", f.mapPanel, "TOP", 0, -40)
    canvas.tiles, canvas.patches, canvas.pins = {}, {}, {}
    canvas.art = canvas:CreateTexture(nil, "ARTWORK"); canvas.art:SetAllPoints(); canvas.art:Hide()
    canvas.entrance = button(canvas, "E", 20, 20)
    canvas.entrance:SetScript("OnEnter", function(self) if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Entrance", 1, 0.82, 0); GameTooltip:Show() end end)
    canvas.entrance:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    canvas.entrance:Hide()
    f.map = button(f.mapPanel, "Show entrance on map", 190, 28); f.map:SetPoint("BOTTOMLEFT", 18, 18); f.map:SetScript("OnClick", function() G:OpenMap() end)
    f.entries = CreateFrame("Frame", nil, body); f.entries:SetPoint("TOPLEFT"); f.entries:SetSize(380, 468); ns.Panel(f.entries, {edge=0.55}); f.entries.rows = {}
    f.entries.heading = text(f.entries, 14, ns.C.bright, "TOPLEFT", 12, -12, 215)
    f.track = button(f.entries, "Track quests", 112, 25); f.track:SetPoint("TOPRIGHT", -13, -8)
    f.track:SetScript("OnClick", function() local d,t=G.dungeon,ns.DungeonQuestTracker; if not (d and d.key and t) then return end; if not t.frame then ns.Print("Enable Dungeon quest tracker in Forever UI settings, then reload."); return end; if t:GetTracked()==d.key then t:SetTracked(nil) else t:SetTracked(d.key) end; G:Render() end)
    for i = 1, 7 do
        local row = button(f.entries, "", 357, 55); row:SetPoint("TOPLEFT", 8, -44 - (i - 1) * 59); row.text:Hide()
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(38, 38); row.icon:SetPoint("LEFT", 7, 0)
        row.name = text(row, 12, ns.C.text, "TOPLEFT", 53, -9, 235); row.name:SetWordWrap(false)
        row.sub = text(row, 10, ns.C.muted, "BOTTOMLEFT", 53, 8, 235); row.sub:SetWordWrap(false)
        row.chainIcon = row:CreateTexture(nil, "ARTWORK"); row.chainIcon:SetSize(19, 19); row.chainIcon:SetPoint("RIGHT", -32, 0)
        row.chainIcon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\tracker-chain"); row.chainIcon:SetVertexColor(0.9, 0.69, 0.3)
        row.chain = button(row, "+", 22, 22); row.chain:SetPoint("RIGHT", -5, 0)
        row.chain:SetScript("OnClick", function() local data=row.data; if data and data.chain then G.chainOpen[data.root] = not G.chainOpen[data.root]; G:Render() end end)
        row:SetScript("OnClick", function(self) if self.value then G.entry=self.value; f.detailPanel.offset=0; G:Render() end end); f.entries.rows[i] = row
    end
    f.entries.scrollbar = ns.ListScrollbar(f.entries, function(offset) G.entryOffset=offset; G:Render() end)
    f.entries:EnableMouseWheel(true); f.entries:SetScript("OnMouseWheel", function(_,delta) G.entryOffset=G.entryOffset-delta; G:Render() end)
    local dp = CreateFrame("Frame", nil, body); f.detailPanel = dp; dp:SetPoint("TOPLEFT", 394, 0); dp:SetSize(556, 468); ns.Panel(dp, {edge=0.55}); dp.offset=0
    dp.name = text(dp, 16, ns.C.bright, "TOPLEFT", 14, -13, 520); dp.meta = text(dp, 10, ns.C.muted, "TOPLEFT", 14, -38, 520)
    dp.scroll = CreateFrame("ScrollFrame", nil, dp); dp.scroll:SetPoint("TOPLEFT", 8, -62); dp.scroll:SetSize(528, 366)
    dp.content = CreateFrame("Frame", nil, dp.scroll); dp.content:SetSize(516, 366); dp.scroll:SetScrollChild(dp.content)
    dp.content.fields = {}
    for _, heading in ipairs({"OBJECTIVE", "STARTS", "TURN IN", "REWARDS", "LOOT"}) do
        local label = text(dp.content, 11, ns.C.bright, "TOPLEFT", 8, 0, 490); label:SetText(heading)
        local value = text(dp.content, 12, ns.C.text, "TOPLEFT", 8, 0, 490); value:SetWordWrap(true)
        dp.content.fields[heading] = {label=label,value=value}
    end
    dp.content.items = {}; for i=1,30 do dp.content.items[i] = makeItemRow(dp.content, 490) end
    dp.content.more = text(dp.content, 10, ns.C.muted, "TOPLEFT", 8, 0, 490)
    dp.scrollbar = ns.ListScrollbar(dp.scroll, function(offset) dp.offset=offset; G:Render() end)
    dp.scroll:EnableMouseWheel(true); dp.scroll:SetScript("OnMouseWheel", function(_,delta) dp.offset=math.max(0,(dp.offset or 0)-delta*45); G:Render() end)
    f.questMap = button(dp, "Show quest start", 150, 24); f.questMap:SetPoint("BOTTOMRIGHT", -12, 8)
    f.questMap:SetScript("OnClick", function()
        local enc=ns.Encyclopedia; local loc=G:QuestLocation(G.entry)
        if loc and enc.ShowLocation(loc.mapID, loc.x, loc.y) then f:Hide()
        else ns.Print("No recorded start location for this quest.") end
    end)
    if type(UISpecialFrames)=="table" then table.insert(UISpecialFrames, "ForeverUIInstanceGuide") end
    f:Hide()
end
-- Open the exact quest selected in the encyclopedia, using the same dungeon
-- object and quest records as the tracker and guide.
function G:OpenQuest(dungeon, quest)
    if not dungeon or not quest then return end
    self:Build()
    self.view = "Quests"
    self:SelectDungeon(dungeon)
    self.entry = quest
    for _, row in ipairs(self:QuestRows(dungeon)) do
        if row.chain then
            for _, step in ipairs(row.chain) do
                if tonumber(step.id) == tonumber(quest.id) then self.chainOpen[row.root] = true; break end
            end
        end
    end
    for index, row in ipairs(self:QuestRows(dungeon)) do
        if tonumber(row.quest.id) == tonumber(quest.id) then
            self.entryOffset = math.max(0, index - #self.frame.entries.rows)
            break
        end
    end
    if ns.Encyclopedia and ns.Encyclopedia.window then ns.Encyclopedia.window:Hide() end
    self.frame:Show(); self:Render()
end
function G:Toggle()
    self:Build()
    if self.frame:IsShown() then self.frame:Hide() else self.frame:Show(); self:Render() end
end
local function refresh()
    if ns.Encyclopedia and ns.Encyclopedia.QuestPage then ns.Encyclopedia.QuestPage.statusCache = {} end
    if G.frame and G.frame:IsShown() then G:Render() end
    local enc = ns.Encyclopedia
    if enc and enc.window and enc.window:IsShown() and enc.selected == "Dungeons" then enc:Render() end
end
ns.On("QUEST_LOG_UPDATE", refresh); ns.On("QUEST_TURNED_IN", refresh)

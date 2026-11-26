-- Standalone encyclopedia services. The reference tables are attributed in
-- IndependentReferenceData.lua; no separate addon is needed at runtime.
local _, ns = ...
local ref = ns.IndependentReference
if not ref then return end

local function characterStore()
    ns.db = ns.db or {}
    ns.db.encyclopediaBookTracking = ns.db.encyclopediaBookTracking or {}
    local key
    if UnitGUID then local ok, v = pcall(UnitGUID, "player"); if ok and type(v) == "string" and not ns.Secret(v) and v ~= "" then key = v end end
    if not key and UnitFullName then local ok, n, r = pcall(UnitFullName, "player"); if ok and type(n) == "string" and not ns.Secret(n) then key = tostring(r or "") .. ":" .. n end end
    key = key or "player"
    local all = ns.db.encyclopediaBookTracking
    all[key] = all[key] or { confirmed = {}, manual = {}, bank = {} }
    local saved = all[key]
    saved.confirmed, saved.manual, saved.bank = saved.confirmed or {}, saved.manual or {}, saved.bank or {}
    return saved, key
end

local function importBooks()
    local bosses = type(_G.OneForAllDB) == "table" and _G.OneForAllDB.bossInfo
    if type(bosses) == "table" then
        ns.db.encyclopediaBosses = ns.db.encyclopediaBosses or {}
        for id, observed in pairs(bosses) do
            if tonumber(id) and type(observed) == "table" then
                local saved = ns.db.encyclopediaBosses[tonumber(id)] or {}
                if not saved.displayID and type(observed.displayID) == "number" and not ns.Secret(observed.displayID) and observed.displayID > 0 then saved.displayID = observed.displayID end
                if not saved.level and type(observed.level) == "number" and not ns.Secret(observed.level) then saved.level = observed.level end
                if not saved.creatureType and type(observed.ctype) == "string" and not ns.Secret(observed.ctype) then saved.creatureType = observed.ctype end
                ns.db.encyclopediaBosses[tonumber(id)] = saved
            end
        end
    end
    local old = _G.OneForAllCharDB
    if type(old) ~= "table" then return end
    local saved, key = characterStore()
    if saved.importedOneForAll then return end
    ns.db.encyclopediaBooks = ns.db.encyclopediaBooks or {}
    ns.db.encyclopediaBooks[key] = ns.db.encyclopediaBooks[key] or {}
    if type(old.manualDone) == "table" then
        for id, value in pairs(old.manualDone) do if value and tonumber(id) then ns.db.encyclopediaBooks[key][tostring(id)] = true end end
    end
    for _, entry in ipairs({ {old.confirmedDone, saved.confirmed}, {old.bankItems, saved.bank} }) do
        if type(entry[1]) == "table" then
            for id, value in pairs(entry[1]) do if value and tonumber(id) then entry[2][tonumber(id)] = true end end
        end
    end
    saved.importedOneForAll = true
end

function ref:GetBookState(book)
    if not book or not book.itemId then return "missing" end
    local saved, id = characterStore(), book.itemId
    if saved.confirmed[id] then return "done" end
    if saved.manual[id] then return "manual" end
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    if count then
        local ok, value = pcall(count, id, false)
        if ok and type(value) == "number" and not ns.Secret(value) and value > 0 then return "bag" end
        ok, value = pcall(count, id, true)
        if ok and type(value) == "number" and not ns.Secret(value) and value > 0 then return "bank" end
    end
    if saved.bank[id] then return "bank" end
    local completed = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
    if completed and book.questId then
        local ok, value = pcall(completed, book.questId)
        if ok and not ns.Secret(value) and value then return "questflag" end
    end
    return "missing"
end

local bankOpen = false
local function scanBank()
    local slots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local item = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
    if not (slots and item) then return end
    local found, valid = {}, false
    for _, bag in ipairs({-1, 5, 6, 7, 8, 9, 10, 11}) do
        local ok, n = pcall(slots, bag)
        if not ok or type(n) ~= "number" or ns.Secret(n) then return end
        if bag == -1 and n > 0 then valid = true end
        if n > 0 then
            for slot = 1, n do
                local success, id = pcall(item, bag, slot)
                if not success or ns.Secret(id) then return end
                if success and type(id) == "number" and not ns.Secret(id) then found[id] = true end
            end
        end
    end
    if valid then characterStore().bank = found end
end

ns.On("PLAYER_LOGIN", importBooks)
ns.On("QUEST_TURNED_IN", function(_, questID)
    if type(questID) ~= "number" or ns.Secret(questID) then return end
    for _, book in ipairs(ref.BOOKS or {}) do
        if book.questId == questID and book.itemId then
            characterStore().confirmed[book.itemId] = true
            local encyclopedia = ns.Encyclopedia
            if encyclopedia and encyclopedia.window and encyclopedia.window:IsShown() then encyclopedia:Render() end
            break
        end
    end
end)
ns.On("BANKFRAME_OPENED", function() bankOpen = true; scanBank() end)
ns.On("BANKFRAME_CLOSED", function() bankOpen = false end)
ns.On("BAG_UPDATE_DELAYED", function() if bankOpen then scanBank() end end)

local function learned(boss)
    return ns.db and ns.db.encyclopediaBosses and boss and boss.npcID and ns.db.encyclopediaBosses[boss.npcID]
end
function ref:GetBossLevel(boss)
    local seen = learned(boss); local level = seen and seen.level
    if type(level) == "number" then return level < 0 and "??" or tostring(level) end
    return boss and ref.BOSS_LEVELS and (ref.BOSS_LEVELS[boss.npcID] or ref.BOSS_LEVELS[boss.name])
end
function ref:GetBossType(boss)
    return boss and ((ref.BOSS_TYPES and ref.BOSS_TYPES[boss.npcID]) or (learned(boss) and learned(boss).creatureType))
end
function ref:GetBossRank(boss)
    if not boss then return end
    if boss.rare then return "Rare" end
    if ref.BOSS_SUMMONED and ref.BOSS_SUMMONED[boss.npcID] then return "Summoned" end
    return "Elite"
end
function ref:GetLearnedBossDisplay(boss)
    local info = learned(boss); return info and info.displayID
end
local model, modelBusy
local function observe(unit)
    if not (UnitGUID and UnitExists and UnitExists(unit)) then return end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or type(guid) ~= "string" or ns.Secret(guid) then return end
    local id = tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if not id then return end
    -- Learn ordinary NPCs as well as bosses as they are encountered. An NPC
    -- ID alone is not a display ID, so never invent a portrait for one.
    ns.db.encyclopediaBosses = ns.db.encyclopediaBosses or {}
    local info = ns.db.encyclopediaBosses[id] or {}; ns.db.encyclopediaBosses[id] = info
    if UnitLevel then local good, level = pcall(UnitLevel, unit); if good and type(level) == "number" and not ns.Secret(level) then info.level = level end end
    if UnitCreatureType then local good, value = pcall(UnitCreatureType, unit); if good and type(value) == "string" and not ns.Secret(value) and value ~= "" then info.creatureType = value end end
    if info.displayID or modelBusy then return end
    model = model or CreateFrame("PlayerModel", nil, UIParent)
    if not (model.SetUnit and model.GetDisplayInfo) then return end
    modelBusy = true
    model:SetSize(1, 1); model:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10, -10); model:Show()
    if not pcall(model.SetUnit, model, unit) then model:Hide(); modelBusy = false; return end
    local attempts = 0
    local function poll()
        attempts = attempts + 1
        local same, current = pcall(UnitGUID, unit)
        if not same or ns.Secret(current) or current ~= guid then model:Hide(); modelBusy = false; return end
        local good, display = pcall(model.GetDisplayInfo, model)
        if good and type(display) == "number" and not ns.Secret(display) and display > 0 then
            info.displayID = display; model:Hide(); modelBusy = false
            local encyclopedia = ns.Encyclopedia
            if encyclopedia and encyclopedia.window and encyclopedia.window:IsShown() then encyclopedia:Render() end
        elseif attempts < 10 and C_Timer and C_Timer.After then C_Timer.After(0.2, poll) else model:Hide(); modelBusy = false end
    end
    poll()
end
ns.On("PLAYER_TARGET_CHANGED", function() observe("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() observe("mouseover") end)
ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit) observe(unit) end)

-- Older clients may not support user waypoints; place a marker on the map
-- canvas instead. It is scoped to the selected map and can be clicked away.
local mapMarker
function ref:ShowOnMap(place)
    local mapID, x, y = place and place.mapID, place and place.x, place and place.y
    if not (mapID and type(x) == "number" and type(y) == "number") then return false end
    if not WorldMapFrame then
        if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_WorldMap")
        elseif LoadAddOn then pcall(LoadAddOn, "Blizzard_WorldMap") end
    end
    local map = WorldMapFrame
    if not map then return false end
    if not map:IsShown() then
        if C_Map and C_Map.OpenWorldMap then pcall(C_Map.OpenWorldMap, mapID)
        elseif ShowUIPanel then pcall(ShowUIPanel, map)
        elseif ToggleWorldMap then pcall(ToggleWorldMap)
        else return false end
    end
    if map.SetMapID then pcall(map.SetMapID, map, mapID) end
    local canvas = map.ScrollContainer and map.ScrollContainer.Child
    if not canvas then return false end
    if not mapMarker then
        mapMarker = CreateFrame("Button", "ForeverUIEncyclopediaMapPin", canvas)
        mapMarker:SetSize(24, 24)
        mapMarker:SetFrameStrata("TOOLTIP")
        local icon = mapMarker:CreateTexture(nil, "OVERLAY")
        icon:SetAllPoints(); icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
        mapMarker:SetScript("OnClick", function(self) self:Hide() end)
        if hooksecurefunc and map.OnMapChanged then
            hooksecurefunc(map, "OnMapChanged", function()
                if mapMarker and mapMarker.mapID and map.GetMapID then mapMarker:SetShown(map:GetMapID() == mapMarker.mapID) end
            end)
        end
    end
    mapMarker.mapID = mapID
    local function position()
        if mapMarker.mapID ~= mapID then return end
        if map.GetMapID and map:GetMapID() ~= mapID then mapMarker:Hide(); return end
        local w, h = canvas:GetWidth(), canvas:GetHeight()
        if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return end
        mapMarker:ClearAllPoints()
        mapMarker:SetPoint("CENTER", canvas, "TOPLEFT", x * w / 100, -y * h / 100)
        mapMarker:Show()
    end
    position()
    if C_Timer and C_Timer.After then C_Timer.After(0.05, position); C_Timer.After(0.25, position) end
    return true
end

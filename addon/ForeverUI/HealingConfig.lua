-- Aura tracking and per-character snapshots for healing and nameplates.
local _, ns = ...
local m = ns.modules.healing
local MODES = { "mine", "all", "list", "off" }
local LABEL = { mine = "My helpful effects", all = "All helpful effects", list = "Listed spell IDs", off = "Off" }
local PROFILE_KEYS = { "plateThreat", "plateTank", "plateBorder", "plateAuras", "plateAuraSize", "plateAuraCount", "plateAuraTimers", "plateHealthText", "plateTarget", "plateFocus", "plateTargetOfTarget", "plateCast", "plateThreatText", "plateThreatPercent", "healSolo", "healDeficit", "healPets", "healScale", "healWidth", "healHeight", "healRaidRows", "healPower", "healClassColor", "healRoleColor", "healThreat", "healAuraTimers", "healAbsorbs", "healDispelButtons", "healReplaceParty", "healTargets" }
local PROFILE_CVARS = { "nameplateShowEnemies", "nameplateShowFriends", "nameplateMotion", "nameplateGlobalScale" }

local function key()
    return ns.HealingCharacterKey()
end

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = clone(v) end
    return result
end

function m:GetAuraConfig()
    local character = key()
    local value = character and ns.db.healAura and ns.db.healAura[character]
    if type(value) ~= "table" then return { mode = "mine", ids = {} } end
    return value
end

function m:SetAuraConfig(mode, idsText)
    if InCombatLockdown and InCombatLockdown() then ns.Print("change aura settings after combat."); return false end
    if not LABEL[mode] then ns.Print("unknown aura mode."); return false end
    local character = key()
    if not character then return false end
    local ids, count = {}, 0
    for token in tostring(idsText or ""):gmatch("[^,%s]+") do
        local id = tonumber(token)
        if not id or id < 1 or id ~= math.floor(id) or id > 2147483647 then
            ns.Print("aura list must contain numeric spell IDs separated by commas.")
            return false
        end
        if not ids[id] then ids[id], count = true, count + 1 end
        if count > 64 then ns.Print("use at most 64 aura spell IDs."); return false end
    end
    ns.db.healAura = ns.db.healAura or {}
    ns.db.healAura[character] = { mode = mode, ids = ids }
    self:UpdateUnits()
    return true
end

function m:TrackedAuras(unit)
    local result, kinds, config = {}, {}, self:GetAuraConfig()
    if config.mode == "off" or not (C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function") then return result, kinds end
    local filters = config.mode == "list" and { "HELPFUL", "HARMFUL" }
        or { config.mode == "all" and "HELPFUL" or "HELPFUL|PLAYER" }
    for _, filter in ipairs(filters) do
        for i = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if not ok or ns.Secret(aura) or type(aura) ~= "table" then break end
            local id = aura.spellId
            local match = config.mode ~= "list" or (not ns.Secret(id) and type(id) == "number" and type(config.ids) == "table" and config.ids[id])
            if match then
                result[#result + 1] = aura
                kinds[#result] = filter
                if #result >= 3 then return result, kinds end
            end
        end
    end
    return result, kinds
end

local function snapshot(character)
    local options = {}
    for _, k in ipairs(PROFILE_KEYS) do options[k] = ns.Opt(k) end
    local cvars = {}
    if C_CVar and type(C_CVar.GetCVar) == "function" then
        for _, name in ipairs(PROFILE_CVARS) do
            local ok, value = pcall(C_CVar.GetCVar, name)
            if ok and not ns.Secret(value) and (type(value) == "string" or type(value) == "number") then cvars[name] = tostring(value) end
        end
    end
    return { bindings = clone((ns.db.healBindings and ns.db.healBindings[character]) or {}),
        aura = clone((ns.db.healAura and ns.db.healAura[character]) or { mode = "mine", ids = {} }),
        plateAura = clone(ns.db.plateAuraFilter or { mode = "mine", ids = {} }),
        plates = options, plateCVars = cvars }
end

local function profiles(character)
    ns.db.healProfiles = ns.db.healProfiles or {}
    local p = ns.db.healProfiles[character]
    if type(p) ~= "table" then
        p = { active = "Default", items = { Default = snapshot(character) } }
        ns.db.healProfiles[character] = p
    end
    p.items = p.items or {}
    return p
end

local function validName(name)
    return type(name) == "string" and name ~= "" and #name <= 40 and not name:find("[%c]")
end

function m:SaveProfile(name)
    if InCombatLockdown and InCombatLockdown() then ns.Print("change profiles after combat."); return false end
    local character = key()
    if not character or not validName(name) then ns.Print("enter a profile name of up to 40 characters."); return false end
    local p = profiles(character)
    p.items[name], p.active = snapshot(character), name
    ns.Print("saved profile " .. name .. ".")
    return true
end

function m:LoadProfile(name)
    if InCombatLockdown and InCombatLockdown() then ns.Print("change profiles after combat."); return false end
    local character = key()
    if not character then return false end
    local p, profile = profiles(character)
    profile = p.items[name]
    if type(profile) ~= "table" then ns.Print("profile not found: " .. tostring(name)); return false end
    ns.db.healBindings, ns.db.healAura = ns.db.healBindings or {}, ns.db.healAura or {}
    ns.db.healBindings[character], ns.db.healAura[character] = clone(profile.bindings or {}), clone(profile.aura or { mode = "mine", ids = {} })
    if type(profile.plateAura) == "table" then ns.db.plateAuraFilter = clone(profile.plateAura) end
    local petsBefore = ns.Opt("healPets")
    for _, k in ipairs(PROFILE_KEYS) do if profile.plates and profile.plates[k] ~= nil then ns.O()[k] = profile.plates[k] end end
    if type(profile.plateCVars) == "table" and C_CVar and type(C_CVar.SetCVar) == "function" then
        for _, name in ipairs(PROFILE_CVARS) do
            local value = profile.plateCVars[name]
            if type(value) == "string" or type(value) == "number" then
                local ok, result = pcall(C_CVar.SetCVar, name, tostring(value))
                if not ok or result == false then ns.Print("the game did not allow the " .. name .. " setting to change.") end
            end
        end
    end
    p.active = name
    self:Refresh()
    local plates = ns.modules.nameplates
    if plates and plates.built and plates.ApplyOptions then plates:ApplyOptions() end
    ns.Print("loaded profile " .. name .. ".")
    if petsBefore ~= ns.Opt("healPets") then ns.Print("reload to apply the profile's pet frame setting.") end
    return true
end

function m:DeleteProfile(name)
    if InCombatLockdown and InCombatLockdown() then ns.Print("change profiles after combat."); return false end
    local character = key()
    if not character then return false end
    local p = profiles(character)
    if name == p.active then ns.Print("load a different profile before deleting this one."); return false end
    if not p.items[name] then ns.Print("profile not found: " .. tostring(name)); return false end
    p.items[name] = nil
    ns.Print("deleted profile " .. name .. ".")
    return true
end

local function button(parent, label, width, x, y, click)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 24); b:SetPoint("BOTTOMLEFT", x, y); ns.Panel(b)
    local t = ns.Text(b, 11, ns.C.bright); t:SetPoint("CENTER"); t:SetText(label)
    b:SetScript("OnClick", click)
    return b
end

local function window(name, title, height)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(390, height); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); ns.Panel(f, { alpha = 1.1 })
    f.TitleContainer = CreateFrame("Frame", nil, f)
    f.TitleContainer:SetPoint("TOPLEFT"); f.TitleContainer:SetPoint("TOPRIGHT"); f.TitleContainer:SetHeight(29)
    local heading = ns.Text(f, 14, ns.C.bright); heading:SetPoint("TOPLEFT", 14, -12); heading:SetText(title)
    f.CloseButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.CloseButton:SetSize(26, 24); f.CloseButton:SetPoint("TOPRIGHT", -5, -5)
    f.CloseButton:SetScript("OnClick", function() f:Hide() end)
    if ns.MakeWindowMovable then ns.MakeWindowMovable(f, name) end
    f:Hide()
    return f
end

local function input(parent, y)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(360, 23); e:SetPoint("TOPLEFT", 14, y); e:SetFontObject(ChatFontNormal)
    e:SetTextInsets(5, 5, 0, 0); e:SetAutoFocus(false); ns.Panel(e, { alpha = 0.8, edge = 0.6 })
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
end

function m:ShowAuraConfig()
    if not self.auraConfigWindow then
        local f = window("ForeverUIAuraConfig", "Healing aura tracking", 185)
        f.mode = "mine"
        local hint = ns.Text(f, 10, ns.C.muted); hint:SetPoint("TOPLEFT", 14, -40); hint:SetText("Click the mode to change it. List accepts spell IDs, separated by commas.")
        local modeButton = CreateFrame("Button", nil, f); modeButton:SetSize(230, 24); modeButton:SetPoint("TOPLEFT", 14, -59); ns.Panel(modeButton)
        f.modeText = ns.Text(modeButton, 11, ns.C.bright); f.modeText:SetPoint("CENTER")
        modeButton:SetScript("OnClick", function()
            local at = 1; for i, mode in ipairs(MODES) do if mode == f.mode then at = i end end
            f.mode = MODES[at % #MODES + 1]; f.modeText:SetText(LABEL[f.mode])
        end)
        f.input = input(f, -94)
        f.save = button(f, "Save", 80, 294, 12, function()
            if m:SetAuraConfig(f.mode, f.input:GetText()) then f:Hide(); ns.Print("healing aura settings saved.") end
        end)
        self.auraConfigWindow = f
    end
    local f, config = self.auraConfigWindow, self:GetAuraConfig()
    f.mode = LABEL[config.mode] and config.mode or "mine"; f.modeText:SetText(LABEL[f.mode])
    local ids = {}; for id in pairs(config.ids or {}) do ids[#ids + 1] = id end; table.sort(ids)
    local text = {}; for _, id in ipairs(ids) do text[#text + 1] = tostring(id) end
    f.input:SetText(table.concat(text, ", ")); f:Show()
end

function m:ShowPlateAuraConfig()
    local plates = ns.modules.nameplates
    if not plates or not plates.built then ns.Print("enable threat nameplates and reload first."); return end
    local modes = { "mine", "all", "minehelpful", "helpful", "list" }
    local labels = { mine = "My harmful effects", all = "All harmful effects", minehelpful = "My helpful effects", helpful = "All helpful effects", list = "Listed spell IDs" }
    if not self.plateAuraWindow then
        local f = window("ForeverUIPlateAuraConfig", "Nameplate aura tracking", 185)
        f.mode = "mine"
        local hint = ns.Text(f, 10, ns.C.muted); hint:SetPoint("TOPLEFT", 14, -40)
        hint:SetText("Click the mode to change it. List accepts spell IDs separated by commas.")
        local mode = CreateFrame("Button", nil, f); mode:SetSize(230, 24); mode:SetPoint("TOPLEFT", 14, -59); ns.Panel(mode)
        f.modeText = ns.Text(mode, 11, ns.C.bright); f.modeText:SetPoint("CENTER")
        mode:SetScript("OnClick", function()
            local at = 1; for i, value in ipairs(modes) do if value == f.mode then at = i end end
            f.mode = modes[at % #modes + 1]; f.modeText:SetText(labels[f.mode])
        end)
        f.input = input(f, -94)
        f.save = button(f, "Save", 80, 294, 12, function()
            if plates:SetAuraFilter(f.mode, f.input:GetText()) then f:Hide(); ns.Print("nameplate aura settings saved.") end
        end)
        self.plateAuraWindow = f
    end
    local f, config = self.plateAuraWindow, plates:GetAuraFilter()
    f.mode = labels[config.mode] and config.mode or "mine"; f.modeText:SetText(labels[f.mode])
    local ids = {}; for id in pairs(config.ids or {}) do ids[#ids + 1] = id end; table.sort(ids)
    local text = {}; for _, id in ipairs(ids) do text[#text + 1] = tostring(id) end
    f.input:SetText(table.concat(text, ", ")); f:Show()
end

function m:ShowProfiles()
    local character = key(); if not character then return end
    local p = profiles(character)
    if not self.profileWindow then
        local f = window("ForeverUIProfiles", "Healing and nameplate profiles", 190)
        f.details = ns.Text(f, 10, ns.C.muted); f.details:SetPoint("TOPLEFT", 14, -40); f.details:SetWidth(355); f.details:SetJustifyH("LEFT")
        f.input = input(f, -84)
        f.save = button(f, "Save as", 100, 14, 12, function() if m:SaveProfile(f.input:GetText()) then m:ShowProfiles() end end)
        f.load = button(f, "Load", 100, 124, 12, function() if m:LoadProfile(f.input:GetText()) then m:ShowProfiles() end end)
        f.delete = button(f, "Delete", 100, 234, 12, function() if m:DeleteProfile(f.input:GetText()) then m:ShowProfiles() end end)
        self.profileWindow = f
    end
    local names = {}; for name in pairs(p.items) do names[#names + 1] = name end; table.sort(names)
    self.profileWindow.details:SetText("Current: " .. tostring(p.active or "Default") .. "\nSaved: " .. table.concat(names, ", "))
    self.profileWindow.input:SetText(p.active or "Default"); self.profileWindow:Show()
end

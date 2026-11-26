-- Conservative styling for accessible native nameplates. Forbidden plates are
-- left to the game; threat is only coloured when the client exposes it.
local _, ns = ...
local UNIT_FILL = "Interface\\TargetingFrame\\UI-StatusBar"
local m = ns.Module("nameplates", "Threat nameplates", function(self)
    self.units = {}
    local timer = CreateFrame("Frame", nil, UIParent)
    local elapsed = 0
    timer:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.5 then elapsed = 0; self:UpdateAuraTimers() end
    end)
    self.auraTimer = timer
    ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit)
        if C_Timer and C_Timer.After then C_Timer.After(0, function() self:Add(unit) end) else self:Add(unit) end
    end)
    ns.On("NAME_PLATE_UNIT_REMOVED", function(_, unit) self:Remove(unit) end)
    ns.On("UNIT_AURA", function(_, unit) self:UpdateAuras(unit) end)
    ns.On("UNIT_HEALTH", function(_, unit) self:UpdateInfo(unit) end)
    ns.On("UNIT_MAXHEALTH", function(_, unit) self:UpdateInfo(unit) end)
    ns.On("PLAYER_TARGET_CHANGED", function() for unit in pairs(self.units) do self:UpdateInfo(unit) end end)
    ns.On("PLAYER_FOCUS_CHANGED", function() for unit in pairs(self.units) do self:UpdateInfo(unit) end end)
    ns.On("UNIT_TARGET", function(_, unit) self:UpdateInfo(unit) end)
    for _, event in ipairs({ "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED" }) do
        ns.On(event, function() self:UpdateThreat() end)
    end
    self:InstallHooks()
    ns.On("ADDON_LOADED", function() self:InstallHooks() end)
    ns.On("PLAYER_REGEN_ENABLED", function() self:Refresh() end)
    ns.On("PLAYER_ENTERING_WORLD", function() self:Refresh() end)
    self:Refresh()
end)

function m:InstallHooks()
    if self.colorHook or type(CompactUnitFrame_UpdateHealthColor) ~= "function" or not hooksecurefunc then return end
    hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame) self:NativeColorUpdated(frame) end)
    self.colorHook = true
end

local function accessible(object)
    if type(object) ~= "table" then return false end
    if type(object.IsForbidden) == "function" then
        local ok, forbidden = pcall(object.IsForbidden, object)
        if not ok or ns.Secret(forbidden) or forbidden then return false end
    end
    return true
end

local function canModify(bar)
    if not accessible(bar) then return false end
    if InCombatLockdown and InCombatLockdown() and type(bar.IsProtected) == "function" then
        local ok, protected = pcall(bar.IsProtected, bar)
        if not ok or ns.Secret(protected) or protected then return false end
    end
    return true
end

local function canCreateDecoration(bar)
    if not canModify(bar) then return false end
    if InCombatLockdown and InCombatLockdown() then
        -- Only create cosmetic regions in combat when the client explicitly
        -- reports the bar is not protected. Unknown states remain untouched.
        if type(bar.IsProtected) ~= "function" then return false end
        local ok, protected = pcall(bar.IsProtected, bar)
        return ok and not ns.Secret(protected) and protected == false
    end
    return true
end

local function stylePlateFill(bar)
    if not canModify(bar) then return end
    bar:SetStatusBarTexture(UNIT_FILL)
    for _, region in ipairs({ bar.selectedBorder or false, bar.bgTexture or false }) do
        if type(region) == "table" and type(region.SetAlpha) == "function" then region:SetAlpha(0) end
    end
    if not canCreateDecoration(bar) then return end
    if not bar.fuiPlateBackground then
        local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetAllPoints(bar)
        bg:SetColorTexture(ns.C.dark[1], ns.C.dark[2], ns.C.dark[3], 0.9)
        bar.fuiPlateBackground = bg
        local shade = bar:CreateTexture(nil, "OVERLAY", nil, 0)
        if type(CreateColor) == "function" and type(shade.SetGradient) == "function" then
            shade:SetColorTexture(1, 1, 1, 1)
            shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.30), CreateColor(0, 0, 0, 0))
        else
            shade:SetColorTexture(0, 0, 0, 0.12)
        end
        bar.fuiPlateShade = shade
    end
    local texture = type(bar.GetStatusBarTexture) == "function" and bar:GetStatusBarTexture()
    if type(texture) ~= "table" then texture = bar end
    bar.fuiPlateShade:ClearAllPoints()
    bar.fuiPlateShade:SetPoint("TOPLEFT", texture, "TOPLEFT", 0, 0)
    bar.fuiPlateShade:SetPoint("BOTTOMRIGHT", texture, "BOTTOMRIGHT", 0, 0)
end

local function styleCast(cast)
    if not canModify(cast) or type(cast.SetStatusBarTexture) ~= "function" then return end
    if ns.Opt("plateCast") then
        if not (InCombatLockdown and InCombatLockdown()) and not cast.fuiPlateCast then
            local edge = CreateFrame("Frame", nil, cast)
            edge:SetPoint("TOPLEFT", cast, "TOPLEFT", -1, 1)
            edge:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", 1, -1)
            ns.Panel(edge, { noBg = true, edge = 0.7 })
            cast.fuiPlateCast = edge
            if type(cast.UpdateBarFillTexture) == "function" and hooksecurefunc then
                hooksecurefunc(cast, "UpdateBarFillTexture", function(self)
                    if ns.Opt("plateCast") and canModify(self) then self:SetStatusBarTexture(ns.FLAT) end
                end)
            end
        end
        if cast.fuiPlateCast and cast.fuiPlateCast.SetAlpha then cast.fuiPlateCast:SetAlpha(1) end
        cast:SetStatusBarTexture(ns.FLAT)
    elseif cast.fuiPlateCast then
        cast.fuiPlateCast:SetAlpha(0)
        if type(cast.UpdateBarFillTexture) == "function" then cast:UpdateBarFillTexture() end
    end
end

local function prepareAuras(bar)
    if not ns.Opt("plateAuras") or not canCreateDecoration(bar) then return end
    local icons = bar.fuiPlateAuras
    if icons and InCombatLockdown and InCombatLockdown() then return end
    if not icons then
        icons = {}
        local stacks, timers = {}, {}
        for i = 1, 5 do
            local icon = bar:CreateTexture(nil, "OVERLAY", nil, 5)
            icon:Hide()
            icons[i] = icon
            local count = ns.Text(bar, 9)
            count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
            count:Hide()
            stacks[i] = count
            local time = ns.Text(bar, 9, ns.C.bright)
            time:SetPoint("CENTER", icon, "CENTER")
            time:Hide()
            timers[i] = time
        end
        bar.fuiPlateAuras = icons
        bar.fuiPlateAuraStacks = stacks
        bar.fuiPlateAuraTimes = timers
    end
    local size = math.max(12, math.min(24, tonumber(ns.Opt("plateAuraSize")) or 16))
    for i, icon in ipairs(icons) do
        icon:SetSize(size, size)
        icon:ClearAllPoints()
        icon:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", (i - 1) * (size + 2), 3)
    end
end

local function prepareInfo(bar)
    if not canCreateDecoration(bar) then return end
    if not bar.fuiPlateHealth then
        local label = ns.Text(bar, 10)
        label:SetPoint("CENTER")
        label:Hide()
        bar.fuiPlateHealth = label
    end
    if not bar.fuiPlateTarget then
        local line = bar:CreateTexture(nil, "OVERLAY", nil, 6)
        line:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 1)
        line:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 1)
        line:SetHeight(2)
        line:SetColorTexture(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3], 1)
        line:Hide()
        bar.fuiPlateTarget = line
    end
    if not bar.fuiPlateThreat then
        local label = ns.Text(bar, 9, ns.C.bright)
        label:SetPoint("RIGHT", bar, "LEFT", -4, 0)
        label:Hide()
        bar.fuiPlateThreat = label
    end
    if not bar.fuiPlateFocus then
        local focus = ns.Text(bar, 10, ns.C.bright)
        focus:SetPoint("LEFT", bar, "RIGHT", 4, 0)
        focus:SetText("F")
        focus:Hide()
        bar.fuiPlateFocus = focus
    end
    if not bar.fuiPlateTargetName then
        local name = ns.Text(bar, 9, ns.C.text)
        name:SetPoint("LEFT", bar, "RIGHT", 18, 0)
        name:SetWidth(90)
        name:SetJustifyH("LEFT")
        if name.SetWordWrap then name:SetWordWrap(false) end
        name:Hide()
        bar.fuiPlateTargetName = name
    end
end

function m:UpdateInfo(unit)
    local data = self.units[unit]
    local bar = data and data.bar
    if not bar or not canModify(bar) then return end
    if bar.fuiPlateHealth then
        local value, maximum
        if ns.Opt("plateHealthText") and type(UnitHealth) == "function" and type(UnitHealthMax) == "function" then
            local ok, v = pcall(UnitHealth, unit)
            local maxOK, m = pcall(UnitHealthMax, unit)
            if ok and maxOK and not ns.Secret(v) and not ns.Secret(m) and type(v) == "number" and type(m) == "number" and m > 0 then value, maximum = v, m end
        end
        if maximum then
            bar.fuiPlateHealth:SetText(math.floor(value * 100 / maximum + 0.5) .. "%")
            bar.fuiPlateHealth:Show()
        else bar.fuiPlateHealth:Hide() end
    end
    if bar.fuiPlateTarget then
        local isTarget = false
        if ns.Opt("plateTarget") and type(UnitIsUnit) == "function" then
            local ok, value = pcall(UnitIsUnit, unit, "target")
            isTarget = ok and not ns.Secret(value) and value == true
        end
        bar.fuiPlateTarget:SetShown(isTarget)
    end
    if bar.fuiPlateFocus then
        local isFocus = false
        if ns.Opt("plateFocus") and type(UnitIsUnit) == "function" then
            local ok, value = pcall(UnitIsUnit, unit, "focus")
            isFocus = ok and not ns.Secret(value) and value == true
        end
        bar.fuiPlateFocus:SetShown(isFocus)
    end
    if bar.fuiPlateTargetName then
        local name
        if ns.Opt("plateTargetOfTarget") and type(unit) == "string" and type(UnitName) == "function" then
            local ok, value = pcall(UnitName, unit .. "target")
            if ok and not ns.Secret(value) and type(value) == "string" and value ~= "" then name = value end
        end
        if name then bar.fuiPlateTargetName:SetText(name); bar.fuiPlateTargetName:Show()
        else bar.fuiPlateTargetName:Hide() end
    end
end

function m:GetAuraFilter()
    local filter = ns.db.plateAuraFilter
    if type(filter) ~= "table" then return { mode = "mine", ids = {} } end
    return filter
end

function m:SetAuraFilter(mode, text)
    if InCombatLockdown and InCombatLockdown() then ns.Print("change nameplate aura settings after combat."); return false end
    if mode ~= "mine" and mode ~= "all" and mode ~= "helpful" and mode ~= "minehelpful" and mode ~= "list" then return false end
    local ids, count = {}, 0
    for token in tostring(text or ""):gmatch("[^,%s]+") do
        local id = tonumber(token)
        if not id or id < 1 or id ~= math.floor(id) or id > 2147483647 then
            ns.Print("aura list must contain numeric spell IDs separated by commas."); return false
        end
        if not ids[id] then ids[id], count = true, count + 1 end
        if count > 64 then ns.Print("use at most 64 aura spell IDs."); return false end
    end
    ns.db.plateAuraFilter = { mode = mode, ids = ids }
    self:ApplyOptions()
    return true
end

function m:UpdateAuras(unit)
    local data = self.units[unit]
    local bar = data and data.bar
    if not bar or not canModify(bar) or not bar.fuiPlateAuras then return end
    local icons = bar.fuiPlateAuras
    for _, icon in ipairs(icons) do icon:Hide(); icon.fuiExpiration = nil end
    for _, count in ipairs(bar.fuiPlateAuraStacks or {}) do count:Hide() end
    for _, time in ipairs(bar.fuiPlateAuraTimes or {}) do time:Hide() end
    if not ns.Opt("plateAuras") or not (C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function") then return end
    local config = self:GetAuraFilter()
    local filters = config.mode == "list" and { "HARMFUL", "HELPFUL" }
        or { config.mode == "mine" and "HARMFUL|PLAYER" or config.mode == "minehelpful" and "HELPFUL|PLAYER"
            or config.mode == "helpful" and "HELPFUL" or "HARMFUL" }
    local maximum = math.floor(math.max(1, math.min(#icons, tonumber(ns.Opt("plateAuraCount")) or 3)))
    local displayed = 0
    for _, filter in ipairs(filters) do
        for index = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
            if not ok or ns.Secret(aura) or type(aura) ~= "table" then break end
            local texture = aura.icon
            local id = aura.spellId
            local matched = config.mode ~= "list" or (not ns.Secret(id) and type(id) == "number" and type(config.ids) == "table" and config.ids[id])
            if matched and not ns.Secret(texture) and (type(texture) == "number" or type(texture) == "string") then
                displayed = displayed + 1
                icons[displayed]:SetTexture(texture)
                icons[displayed]:Show()
                local expiration = aura.expirationTime
                if not ns.Secret(expiration) and type(expiration) == "number" and expiration > 0 then icons[displayed].fuiExpiration = expiration end
                local count = aura.applications
                local label = bar.fuiPlateAuraStacks and bar.fuiPlateAuraStacks[displayed]
                if label and not ns.Secret(count) and type(count) == "number" and count > 1 then
                    label:SetText(tostring(count)); label:Show()
                end
                if displayed == maximum then break end
            end
        end
        if displayed == maximum then break end
    end
    self:UpdateAuraTimers(unit)
end

function m:UpdateAuraTimers(only)
    local now = type(GetTime) == "function" and GetTime()
    if ns.Secret(now) or type(now) ~= "number" then return end
    for unit, data in pairs(self.units) do
        local bar = data.bar
        if (not only or only == unit) and canModify(bar) and bar.fuiPlateAuraTimes then
            for i, label in ipairs(bar.fuiPlateAuraTimes) do
                local expiration = bar.fuiPlateAuras[i].fuiExpiration
                if ns.Opt("plateAuras") and ns.Opt("plateAuraTimers") and type(expiration) == "number" and expiration > now then
                    local remaining = expiration - now
                    label:SetText(remaining >= 60 and (math.ceil(remaining / 60) .. "m") or tostring(math.ceil(remaining)))
                    label:Show()
                else label:Hide() end
            end
        end
    end
end

function m:Add(unit)
    if type(unit) ~= "string" then return end
    if not (C_NamePlate and type(C_NamePlate.GetNamePlateForUnit) == "function") then return end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not accessible(plate) then return end
    local worked, bar, cast = pcall(function()
        local frame = plate.UnitFrame
        local container = frame and frame.HealthBarsContainer
        local castContainer = frame and frame.CastBarsContainer
        return (container and (container.healthBar or container.HealthBar)) or (frame and (frame.healthBar or frame.HealthBar)),
            (castContainer and (castContainer.castBar or castContainer.CastBar)) or (frame and (frame.castBar or frame.CastBar))
    end)
    if not worked or not accessible(bar) or type(bar.SetStatusBarTexture) ~= "function" then return end
    local inCombat = InCombatLockdown and InCombatLockdown()
    if inCombat and type(bar.IsProtected) == "function" then
        local canRead, protected = pcall(bar.IsProtected, bar)
        if not canRead or ns.Secret(protected) or protected then return end
    end
    local existing = self.units[unit]
    if existing and existing.bar == bar then
        pcall(stylePlateFill, bar)
        if not inCombat and not bar.fuiPlateEdge then
            pcall(function()
                local edge = CreateFrame("Frame", nil, bar)
                edge:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 2)
                edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 2, -2)
                ns.Panel(edge, { noBg = true, edge = 0.7 })
                edge:SetAlpha(ns.Opt("plateBorder") and 1 or 0)
                bar.fuiPlateEdge = edge
            end)
        end
        pcall(prepareAuras, bar)
        pcall(prepareInfo, bar)
        existing.cast = cast
        styleCast(cast)
        self:UpdateAuras(unit)
        self:UpdateInfo(unit)
        self:UpdateThreat(unit)
        return
    end
    -- Nameplate frames are pooled. If the game reuses a bar before its old
    -- removal event arrives, restore its native color before sampling it for
    -- the new unit; otherwise an old threat color becomes the new baseline.
    for oldUnit, data in pairs(self.units) do
        if oldUnit ~= unit and data.bar == bar then self:Remove(oldUnit) end
    end
    local colored, r, g, b, a = pcall(bar.GetStatusBarColor, bar)
    local base
    if colored and not ns.Secret(r) and not ns.Secret(g) and not ns.Secret(b)
        and type(r) == "number" and type(g) == "number" and type(b) == "number" then
        base = { r, g, b, not ns.Secret(a) and type(a) == "number" and a or 1 }
    end
    local styled = pcall(function()
        stylePlateFill(bar)
        -- Existing accessible bars can be recoloured in combat, but do not
        -- create or reanchor frames until combat has ended.
        if not inCombat and not bar.fuiPlateEdge then
            local edge = CreateFrame("Frame", nil, bar)
            edge:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 2)
            edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 2, -2)
            ns.Panel(edge, { noBg = true, edge = 0.7 })
            edge:SetAlpha(ns.Opt("plateBorder") and 1 or 0)
            bar.fuiPlateEdge = edge
        end
    end)
    if not styled then return end
    self.units[unit] = { bar = bar, base = base, cast = cast }
    pcall(prepareAuras, bar)
    pcall(prepareInfo, bar)
    styleCast(cast)
    self:UpdateAuras(unit)
    self:UpdateInfo(unit)
    self:UpdateThreat(unit)
end

local THREAT = {
    [0] = { 0.37, 0.70, 0.36 }, [1] = { 0.95, 0.78, 0.25 },
    [2] = { 0.96, 0.48, 0.18 }, [3] = { 0.86, 0.22, 0.18 },
}
local TANK_THREAT = { [0] = THREAT[3], [1] = THREAT[2], [2] = THREAT[1], [3] = THREAT[0] }
local THREAT_TEXT = { [0] = "Low", [1] = "Rising", [2] = "High", [3] = "Aggro" }
function m:NativeColorUpdated(frame)
    if not accessible(frame) then return end
    local ok, unit, bar = pcall(function()
        local container = frame.HealthBarsContainer
        return frame.unit, (container and (container.healthBar or container.HealthBar)) or frame.healthBar or frame.HealthBar
    end)
    if not ok or ns.Secret(unit) or type(unit) ~= "string" then return end
    local data = self.units[unit]
    if not data or data.bar ~= bar or not accessible(bar) then return end
    local read, r, g, b, a = pcall(bar.GetStatusBarColor, bar)
    if read and not ns.Secret(r) and not ns.Secret(g) and not ns.Secret(b)
        and type(r) == "number" and type(g) == "number" and type(b) == "number" then
        data.base = { r, g, b, not ns.Secret(a) and type(a) == "number" and a or 1 }
    end
    self:UpdateThreat(unit)
end
function m:UpdateThreat(only)
    local tank = ns.Opt("plateTank") and true or false
    if type(UnitGroupRolesAssigned) == "function" then
        local ok, role = pcall(UnitGroupRolesAssigned, "player")
        tank = tank or (ok and not ns.Secret(role) and role == "TANK")
    end
    for unit, data in pairs(self.units) do
        if not only or unit == only then
            local protected = false
            if InCombatLockdown and InCombatLockdown() and type(data.bar.IsProtected) == "function" then
                local ok, value = pcall(data.bar.IsProtected, data.bar)
                protected = not ok or ns.Secret(value) or value
            end
            local ok, status = false, nil
            if (ns.Opt("plateThreat") or ns.Opt("plateThreatText")) and type(UnitThreatSituation) == "function" then
                ok, status = pcall(UnitThreatSituation, "player", unit)
            end
            local threatColor
            if ok and not ns.Secret(status) and type(status) == "number" then
                threatColor = tank and TANK_THREAT[status] or THREAT[status]
            end
            local color = (ns.Opt("plateThreat") and threatColor) or data.base
            if not protected and color and type(color[1]) == "number" and type(color[2]) == "number" and type(color[3]) == "number" then
                pcall(data.bar.SetStatusBarColor, data.bar, color[1], color[2], color[3], color[4] or 1)
            end
            if not protected and data.bar.fuiPlateThreat then
                local text = ok and not ns.Secret(status) and type(status) == "number" and THREAT_TEXT[status] or nil
                if ns.Opt("plateThreatText") and text then
                    if ns.Opt("plateThreatPercent") and type(UnitDetailedThreatSituation) == "function" then
                        local got, _, _, percent = pcall(UnitDetailedThreatSituation, "player", unit)
                        if got and not ns.Secret(percent) and type(percent) == "number" then
                            text = tostring(math.floor(percent + 0.5)) .. "%"
                        end
                    end
                    data.bar.fuiPlateThreat:SetText(text)
                    if threatColor then data.bar.fuiPlateThreat:SetTextColor(threatColor[1], threatColor[2], threatColor[3]) end
                    data.bar.fuiPlateThreat:Show()
                else data.bar.fuiPlateThreat:Hide() end
            end
        end
    end
end

function m:ApplyOptions()
    self:UpdateThreat()
    ns.WhenSafe(function()
        for unit, data in pairs(self.units) do
            local edge = data.bar and data.bar.fuiPlateEdge
            if edge and edge.SetAlpha then edge:SetAlpha(ns.Opt("plateBorder") and 1 or 0) end
            if canModify(data.bar) then
                prepareAuras(data.bar)
                prepareInfo(data.bar)
                self:UpdateAuras(unit)
                self:UpdateInfo(unit)
            end
            styleCast(data.cast)
        end
    end)
end

function m:Remove(unit)
    local data = self.units[unit]
    local canRestore = data and data.base
    if canRestore and InCombatLockdown and InCombatLockdown() and type(data.bar.IsProtected) == "function" then
        local ok, protected = pcall(data.bar.IsProtected, data.bar)
        canRestore = ok and not ns.Secret(protected) and not protected
    end
    if canRestore then pcall(data.bar.SetStatusBarColor, data.bar, unpack(data.base)) end
    if data and canModify(data.bar) and data.bar.fuiPlateAuras then
        for _, icon in ipairs(data.bar.fuiPlateAuras) do icon:Hide() end
        for _, label in ipairs(data.bar.fuiPlateAuraStacks or {}) do label:Hide() end
        for _, label in ipairs(data.bar.fuiPlateAuraTimes or {}) do label:Hide() end
    end
    if data and canModify(data.bar) then
        if data.bar.fuiPlateHealth then data.bar.fuiPlateHealth:Hide() end
        if data.bar.fuiPlateTarget then data.bar.fuiPlateTarget:Hide() end
        if data.bar.fuiPlateThreat then data.bar.fuiPlateThreat:Hide() end
        if data.bar.fuiPlateFocus then data.bar.fuiPlateFocus:Hide() end
        if data.bar.fuiPlateTargetName then data.bar.fuiPlateTargetName:Hide() end
    end
    self.units[unit] = nil
end

function m:Refresh()
    if InCombatLockdown and InCombatLockdown() then return end
    if not (C_NamePlate and type(C_NamePlate.GetNamePlates) == "function") then return end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return end
    for _, plate in ipairs(plates) do
        if accessible(plate) then
            local got, unit = pcall(function() return plate.UnitFrame and plate.UnitFrame.unit end)
            if got and not ns.Secret(unit) and type(unit) == "string" then
                self:Add(unit)
            end
        end
    end
end

-- Restyle the native target and focus frames without replacing their secure
-- unit buttons, indicators, bars, auras, or Edit Mode positioning.
local _, ns = ...

-- Use the client's own status text so protected or secret combat values stay
-- with the native unit frames. Apply once; subsequent game settings are yours.
function ns.EnableUnitStatusTextOnce()
    ns.WhenSafe(function()
        if not ns.db or ns.db.unitStatusTextEnabled then return end
        local get = (C_CVar and C_CVar.GetCVar) or GetCVar
        local set = (C_CVar and C_CVar.SetCVar) or SetCVar
        if type(get) ~= "function" or type(set) ~= "function" then return end
        local ok, mode = pcall(get, "statusTextDisplay")
        if not ok or ns.Secret(mode) or type(mode) ~= "string" then return end
        local displayOK = pcall(set, "statusTextDisplay", "NUMERIC")
        local statusOK = pcall(set, "statusText", "1")
        if displayOK and statusOK then ns.db.unitStatusTextEnabled = true end
    end)
end
ns.On("PLAYER_LOGIN", ns.EnableUnitStatusTextOnce)
local UNIT_FILL = "Interface\\TargetingFrame\\UI-StatusBar"

-- The native prediction segments use the same portrait-shaped masks as the
-- original fills. Our rectangular bars need those segments unmasked as well;
-- the client still controls each segment's position and predicted amount.
local function unmaskPredictions(bar)
    local mask = bar.fuiUnitMask
    if not mask then return end
    for _, name in ipairs({ "MyHealPredictionBar", "OtherHealPredictionBar", "TotalAbsorbBar", "HealAbsorbBar", "ManaCostPredictionBar" }) do
        local segment = bar[name]
        if type(segment) == "table" then
            for _, part in ipairs({ "Fill", "TiledFillOverlay" }) do
                local texture = segment[part]
                if type(texture) == "table" and type(texture.RemoveMaskTexture) == "function" then
                    pcall(texture.RemoveMaskTexture, texture, mask)
                end
                -- Native health atlases also have transparent padding even
                -- without the mask. Keep Blizzard's prediction tint while
                -- using the same full-height fill texture as the health bar.
                if part == "Fill" and name ~= "ManaCostPredictionBar" and type(texture) == "table"
                    and type(texture.SetTexture) == "function" then
                    local function applyFill(self)
                        self:SetTexture(UNIT_FILL)
                        if self.SetTexCoord then self:SetTexCoord(0, 1, 0, 1) end
                    end
                    if not texture.fuiPredictionAtlasHook and type(texture.SetAtlas) == "function" and hooksecurefunc then
                        texture.fuiPredictionAtlasHook = true
                        hooksecurefunc(texture, "SetAtlas", applyFill)
                    end
                    applyFill(texture)
                end
            end
        end
    end
end

local function bindShading(bar)
    local style = bar.fuiUnitBar
    if not style then return end
    local texture = type(bar.GetStatusBarTexture) == "function" and bar:GetStatusBarTexture()
    if type(texture) ~= "table" then texture = bar end
    -- Forever's portrait-shaped masks still clip the new rectangular fills.
    -- Detach only this bar's known mask from its fill and prediction segments.
    if bar.fuiUnitMask and type(texture.RemoveMaskTexture) == "function" then
        pcall(texture.RemoveMaskTexture, texture, bar.fuiUnitMask)
    end
    unmaskPredictions(bar)
    -- The client can update the fill atlas directly without calling the
    -- status bar's SetStatusBarTexture method.
    if texture ~= bar and not texture.fuiUnitAtlasHook and type(texture.SetAtlas) == "function" and hooksecurefunc then
        texture.fuiUnitAtlasHook = true
        hooksecurefunc(texture, "SetAtlas", function(self)
            if self.fuiSettingUnitAtlas then return end
            self.fuiSettingUnitAtlas = true
            self:SetTexture(UNIT_FILL)
            if self.SetTexCoord then self:SetTexCoord(0, 1, 0, 1) end
            if bar.fuiUnitMask and type(self.RemoveMaskTexture) == "function" then
                pcall(self.RemoveMaskTexture, self, bar.fuiUnitMask)
            end
            self.fuiSettingUnitAtlas = nil
        end)
    end
    style.shade:ClearAllPoints()
    style.shade:SetPoint("TOPLEFT", texture, "TOPLEFT", 0, 0)
    style.shade:SetPoint("BOTTOMRIGHT", texture, "BOTTOMRIGHT", 0, 0)
    style.sheen:ClearAllPoints()
    style.sheen:SetPoint("TOPLEFT", texture, "TOPLEFT", 0, 0)
    style.sheen:SetPoint("TOPRIGHT", texture, "TOPRIGHT", 0, 0)
end

local function flatFill(bar)
    if type(bar) == "table" and type(bar.SetStatusBarTexture) == "function" then
        bar:SetStatusBarTexture(UNIT_FILL)
        if bar.fuiHealth and type(bar.SetStatusBarColor) == "function" then
            bar:SetStatusBarColor(0.31, 0.68, 0.29, 1)
        end
        bindShading(bar)
    end
end

local function powerFill(bar)
    if type(bar) ~= "table" or not bar.fuiUnitBar then return end
    flatFill(bar)
    local unit = bar.unit or bar.fuiPowerUnit
    if type(UnitPowerType) ~= "function" or type(unit) ~= "string" then return end
    local ok, powerType, token = pcall(UnitPowerType, unit)
    if not ok or ns.Secret(token) or ns.Secret(powerType) then return end
    if token == "MANA" or powerType == 0 then
        bar:SetStatusBarColor(0.16, 0.36, 0.78, 1)
        return
    end
    local info = type(PowerBarColor) == "table" and (PowerBarColor[token] or PowerBarColor[powerType])
    if type(info) == "table" and type(info.r) == "number" and type(info.g) == "number" and type(info.b) == "number" then
        bar:SetStatusBarColor(info.r, info.g, info.b, 1)
    end
end

local function styleBar(bar, isHealth)
    if type(bar) ~= "table" or bar.fuiUnitBar or type(bar.SetStatusBarTexture) ~= "function" then return end
    bar.fuiHealth = isHealth or nil
    flatFill(bar)
    -- The client can recolor health bars for class or reaction after our
    -- initial styling. Keep the same green after those updates as well.
    if isHealth and hooksecurefunc and type(bar.SetStatusBarColor) == "function" then
        hooksecurefunc(bar, "SetStatusBarColor", function(self)
            if self.fuiSettingHealthColor then return end
            self.fuiSettingHealthColor = true
            self:SetStatusBarColor(0.31, 0.68, 0.29, 1)
            self.fuiSettingHealthColor = nil
        end)
    end
    local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints(bar)
    bg:SetColorTexture(ns.C.dark[1], ns.C.dark[2], ns.C.dark[3], ns.PanelAlpha())
    local sheen = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    sheen:SetColorTexture(1, 0.91, 0.72, 0.14)
    sheen:SetHeight(2)
    local shade = bar:CreateTexture(nil, "OVERLAY", nil, 0)
    if type(CreateColor) == "function" and type(shade.SetGradient) == "function" then
        shade:SetColorTexture(1, 1, 1, 1)
        shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.30), CreateColor(0, 0, 0, 0))
    else
        shade:SetColorTexture(0, 0, 0, 0.12)
    end
    bar.fuiUnitBar = { background = bg, sheen = sheen, shade = shade }
    bindShading(bar)
    -- Player and target frames can reapply different native atlases on later
    -- updates. Restore the shared fill and keep the shading on its new edge.
    if hooksecurefunc then
        hooksecurefunc(bar, "SetStatusBarTexture", function(self, texture)
            if self.fuiSettingUnitTexture then return end
            if ns.Secret(texture) then return end
            if texture ~= UNIT_FILL then
                self.fuiSettingUnitTexture = true
                self:SetStatusBarTexture(UNIT_FILL)
                self.fuiSettingUnitTexture = nil
            end
            bindShading(self)
        end)
    end
    if not isHealth then powerFill(bar) end
end

-- A restrained hairline around the full bar, rather than around the fill,
-- stays visible as health or resources change.
local function borderBar(bar)
    local style = type(bar) == "table" and bar.fuiUnitBar
    if not style or style.edge then return end
    local lines = {}
    for i = 1, 4 do
        local line = bar:CreateTexture(nil, "OVERLAY", nil, 6)
        line:SetColorTexture(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], 0.65)
        if line.SetSnapToPixelGrid then line:SetSnapToPixelGrid(false) end
        if line.SetTexelSnappingBias then line:SetTexelSnappingBias(0) end
        lines[i] = line
    end
    lines[1]:SetPoint("TOPLEFT"); lines[1]:SetPoint("TOPRIGHT"); lines[1]:SetHeight(1)
    lines[2]:SetPoint("BOTTOMLEFT"); lines[2]:SetPoint("BOTTOMRIGHT"); lines[2]:SetHeight(1)
    -- Vertical strokes stop between the horizontals so the corners are not
    -- double-painted and darker than the other edges.
    lines[3]:SetPoint("TOPLEFT", 0, -1); lines[3]:SetPoint("BOTTOMLEFT", 0, 1); lines[3]:SetWidth(1)
    lines[4]:SetPoint("TOPRIGHT", 0, -1); lines[4]:SetPoint("BOTTOMRIGHT", 0, 1); lines[4]:SetWidth(1)
    style.edge = lines
end

-- Keep each bar inside the panel, separated from its neighbours; do not
-- resize the health bar or change its unit/value/colour handling.
local function alignBars(name, health, power, largerPower)
    if type(name) ~= "table" or type(health) ~= "table" or type(power) ~= "table" then return end
    local width = health:GetWidth()
    -- Frame geometry can be secret even outside combat, including while the
    -- client is updating player art. Leave the last safe layout in place.
    if ns.Secret(width) or type(width) ~= "number" or width <= 0 then return end
    name:ClearAllPoints()
    name:SetPoint("BOTTOM", health, "TOP", 0, 3)
    name:SetWidth(math.max(1, width - 12))
    if name.SetWordWrap then name:SetWordWrap(false) end
    if name.SetNonSpaceWrap then name:SetNonSpaceWrap(false) end
    if name.SetMaxLines then name:SetMaxLines(1) end
    name:SetJustifyH("CENTER")
    power:ClearAllPoints()
    power:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -2)
    power:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -2)
    power:SetWidth(width)
    if largerPower and power.SetHeight then power:SetHeight(12) end
end

local function styleManaCost(power)
    local prediction = type(power) == "table" and power.ManaCostPredictionBar
    local fill = type(prediction) == "table" and prediction.Fill
    if type(fill) ~= "table" or type(fill.SetColorTexture) ~= "function" then return end
    local function apply(self)
        self:SetColorTexture(0.98, 0.72, 0.20, 0.95)
        if self.SetVertexColor then self:SetVertexColor(1, 1, 1, 1) end
    end
    if not fill.fuiManaCostHook and type(fill.SetAtlas) == "function" and hooksecurefunc then
        fill.fuiManaCostHook = true
        hooksecurefunc(fill, "SetAtlas", apply)
    end
    apply(fill)
end

local function portraitRim(frame, portrait)
    local rim = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    rim:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\unit-portrait-ring.tga")
    rim:SetPoint("TOPLEFT", portrait, "TOPLEFT", -2, 2)
    rim:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 2, -2)
    rim:SetVertexColor(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], 0.9)
    return rim
end

-- The native atlas includes a portrait and name streak sized for Blizzard's
-- original frame. Use a single portrait-sized glow for our custom geometry.
local function alignThreatFlash(flash, portrait)
    if type(flash) ~= "table" or type(flash.ClearAllPoints) ~= "function" then return end
    if flash.SetTexture then flash:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\unit-combat-glow.tga") end
    if flash.SetTexCoord then flash:SetTexCoord(0, 1, 0, 1) end
    if flash.SetVertexColor then flash:SetVertexColor(1, 0.1, 0.05, 1) end
    flash:ClearAllPoints()
    flash:SetPoint("TOPLEFT", portrait, "TOPLEFT", -4, 4)
    flash:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 4, -4)
    if not flash.fuiAtlasHook and type(flash.SetAtlas) == "function" and hooksecurefunc then
        flash.fuiAtlasHook = true
        hooksecurefunc(flash, "SetAtlas", function() pcall(alignThreatFlash, flash, portrait) end)
    end
end

local function updatePlayerStatusVisibility(status, replacement)
    if not status then return end
    -- Native rest/status animations can overwrite region alpha. A transparent
    -- texture cannot become a yellow rectangle when those animations play.
    if status.SetColorTexture then status:SetColorTexture(1, 1, 1, 0) end
    if status.SetAlpha then status:SetAlpha(0) end
    local combat = PlayerFrame and PlayerFrame.inCombat
    if replacement and replacement.SetShown then
        replacement:SetShown(not ns.Secret(combat) and combat == true)
    end
end

local function alignPlayerStatus(status, name)
    if type(status) ~= "table" or not status.SetTexture or not status.ClearAllPoints then return end
    if status.SetColorTexture then status:SetColorTexture(1, 1, 1, 0) end
    if status.SetTexCoord then status:SetTexCoord(0, 1, 0, 1) end
    status:ClearAllPoints()
    status:SetPoint("TOPLEFT", name, "TOPLEFT", -2, 1)
    status:SetPoint("BOTTOMRIGHT", name, "BOTTOMRIGHT", 2, -1)
    updatePlayerStatusVisibility(status, status.fuiCombatName)
    if not status.fuiAtlasHook and type(status.SetAtlas) == "function" and hooksecurefunc then
        status.fuiAtlasHook = true
        hooksecurefunc(status, "SetAtlas", function() pcall(alignPlayerStatus, status, name) end)
    end
end

-- Use the same on-screen gap on each side even when one frame is scaled.
local function placePortrait(frame, body, portrait, onLeft)
    local gap = 4
    if frame.GetEffectiveScale and UIParent.GetEffectiveScale then
        local ok, frameScale, uiScale = pcall(function() return frame:GetEffectiveScale(), UIParent:GetEffectiveScale() end)
        if ok and type(frameScale) == "number" and frameScale > 0 and type(uiScale) == "number" and uiScale > 0 then
            gap = gap * uiScale / frameScale
        end
    end
    portrait:ClearAllPoints()
    if onLeft then portrait:SetPoint("RIGHT", body, "LEFT", -gap, 0)
    else portrait:SetPoint("LEFT", body, "RIGHT", gap, 0) end
end

local function installAuraSpacing(frame, name)
    if type(frame.AnchorAuraContainer) ~= "function" or not hooksecurefunc then return end
    local function position()
        local aura
        if type(frame.GetAuraContainer) == "function" then
            local ok, value = pcall(frame.GetAuraContainer, frame)
            if ok then aura = value end
        end
        if type(aura) ~= "table" or type(aura.SetPoint) ~= "function" then return end
        if type(aura.IsForbidden) == "function" then
            local ok, forbidden = pcall(aura.IsForbidden, aura)
            if not ok or ns.Secret(forbidden) or forbidden then return end
        end
        -- Keep the game's own mirrored layout when it is already above.
        if type(aura.IsFlowLayoutMirroredVertically) == "function" then
            local ok, mirrored = pcall(aura.IsFlowLayoutMirroredVertically, aura)
            if not ok or ns.Secret(mirrored) or mirrored then return end
        end
        if InCombatLockdown and InCombatLockdown() then
            if type(aura.IsProtected) ~= "function" then ns.WhenSafe(position); return end
            local ok, protected = pcall(aura.IsProtected, aura)
            if not ok or ns.Secret(protected) or protected then ns.WhenSafe(position); return end
        end
        aura:ClearAllPoints()
        aura:SetPoint("BOTTOMLEFT", name, "TOPLEFT", 0, 8)
    end
    hooksecurefunc(frame, "AnchorAuraContainer", position)
    position()
end

local function updateClassName(frame, unit)
    local skin = type(frame) == "table" and frame.fuiTargetSkin
    if not skin or not skin.className then return end
    local isPlayer = false
    if type(UnitIsPlayer) == "function" then
        local ok, value = pcall(UnitIsPlayer, unit)
        isPlayer = ok and not ns.Secret(value) and value == true
    end
    local color
    if isPlayer and type(UnitClass) == "function" then
        local ok, _, class = pcall(UnitClass, unit)
        if ok and not ns.Secret(class) and type(class) == "string" then
            color = type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[class]
        end
    end
    if type(color) == "table" and type(color.r) == "number" and type(color.g) == "number" and type(color.b) == "number" then
        skin.className:SetColorTexture(color.r, color.g, color.b, 0.45)
        skin.className:Show()
    else
        skin.className:Hide()
    end
    if skin.reaction and skin.reaction.SetAlpha then skin.reaction:SetAlpha(isPlayer and 0 or 0.35) end
end

-- Questie creates an anonymous target-frame child when an objective is
-- present. Move only a child carrying a Questie icon, never unrelated icons.
local function positionQuestieMarker(frame, portrait)
    if not (type(frame) == "table" and type(portrait) == "table" and type(frame.GetChildren) == "function") then return end
    if InCombatLockdown and InCombatLockdown() then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        pcall(function()
            if type(child) ~= "table" or (child.IsForbidden and child:IsForbidden()) then return end
            local icon = child.Icon
            if type(icon) ~= "table" or type(icon.GetTexture) ~= "function" then return end
            local texture = icon:GetTexture()
            if type(texture) ~= "string" or not texture:lower():find("questie", 1, true) then return end
            child:ClearAllPoints()
            child:SetPoint("BOTTOM", portrait, "TOP", 0, 3)
        end)
    end
end

local questieHooks
local function installQuestieHooks()
    if questieHooks or type(QuestieLoader) ~= "table" or type(QuestieLoader.ImportModule) ~= "function" or not hooksecurefunc then return end
    local ok, module = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieNameplate")
    if not ok or type(module) ~= "table" or type(module.DrawTargetFrame) ~= "function" then return end
    local function place()
        local frame = _G.TargetFrame
        local container = type(frame) == "table" and frame.TargetFrameContainer
        positionQuestieMarker(frame, type(container) == "table" and container.Portrait)
    end
    local function position()
        ns.WhenSafe(place)
    end
    hooksecurefunc(module, "DrawTargetFrame", position)
    if type(module.RedrawFrameIcon) == "function" then hooksecurefunc(module, "RedrawFrameIcon", position) end
    questieHooks = true
    position()
end

local m = ns.Module("targetframe", "Target and focus frames", function(m)
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_REGEN_ENABLED" }) do
        ns.On(event, function() m:Refresh() end)
    end
    ns.On("ADDON_LOADED", function() installQuestieHooks() end)
    installQuestieHooks()
    if type(UnitFrameManaBar_UpdateType) == "function" and hooksecurefunc then
        hooksecurefunc("UnitFrameManaBar_UpdateType", powerFill)
    end
    if type(UnitFrameHealthBar_Update) == "function" and hooksecurefunc then
        hooksecurefunc("UnitFrameHealthBar_Update", function(bar)
            if type(bar) == "table" and bar.fuiTargetHealth then flatFill(bar) end
        end)
    end
    m:Refresh()
end)

local function apply(frame)
    if type(frame) ~= "table" then return end
    if frame.fuiTargetSkin then
        local content = frame.TargetFrameContent
        local main = type(content) == "table" and content.TargetFrameContentMain
        local health = type(main) == "table" and main.HealthBarsContainer
        if type(main) == "table" and type(health) == "table" then alignBars(main.Name, health.HealthBar, main.ManaBar, true) end
        local container = frame.TargetFrameContainer
        if type(container) == "table" and type(container.Portrait) == "table" then
            placePortrait(frame, frame.fuiTargetSkin.body, container.Portrait, false)
        end
        return
    end
    local container, content = frame.TargetFrameContainer, frame.TargetFrameContent
    local main = type(content) == "table" and content.TargetFrameContentMain
    if type(container) ~= "table" or type(main) ~= "table" then return end
    local health, power, name, portrait = main.HealthBarsContainer, main.ManaBar, main.Name, container.Portrait
    if type(health) ~= "table" or type(power) ~= "table" or type(name) ~= "table" or type(portrait) ~= "table" then return end
    if type(health.HealthBar) == "table" then health.HealthBar.fuiUnitMask = health.HealthBarMask end
    power.fuiUnitMask = power.ManaBarMask
    power.fuiPowerUnit = frame == _G.FocusFrame and "focus" or "target"
    alignBars(name, health.HealthBar, power, true)
    if type(health.HealthBar) == "table" then health.HealthBar.fuiTargetHealth = true end
    styleBar(health.HealthBar, true)
    styleBar(power)
    borderBar(health.HealthBar)
    borderBar(power)
    -- The client reapplies its health atlas when a target's classification changes.
    if type(frame.UpdateHealthBarVisuals) == "function" and hooksecurefunc then
        local function align() alignBars(name, health.HealthBar, power, true) end
        hooksecurefunc(frame, "UpdateHealthBarVisuals", function()
            flatFill(health.HealthBar)
            ns.WhenSafe(align)
        end)
    end

    local body = CreateFrame("Frame", nil, frame)
    body:SetFrameLevel(frame:GetFrameLevel())
    body:SetPoint("TOPLEFT", name, "TOPLEFT", -11, 4)
    body:SetPoint("BOTTOMRIGHT", power, "BOTTOMRIGHT", 5, -6)
    ns.Panel(body)
    placePortrait(frame, body, portrait, false)
    local levelCircle = main.LevelBackgroundCircle
    if type(levelCircle) == "table" and type(levelCircle.ClearAllPoints) == "function" then
        levelCircle:ClearAllPoints()
        levelCircle:SetPoint("CENTER", portrait, "BOTTOMRIGHT", -4, 4)
    end
    local portraitPanel = portraitRim(frame, portrait)
    alignThreatFlash(container.Flash, portrait)
    if type(container.FrameTexture) == "table" and container.FrameTexture.SetAlpha then
        container.FrameTexture:SetAlpha(0)
    end
    if type(main.ReputationColor) == "table" and main.ReputationColor.SetAlpha then
        -- Keep the native reaction colour as a subtle friendly/hostile cue.
        main.ReputationColor:SetAlpha(0.35)
    end
    local className = main:CreateTexture(nil, "BACKGROUND", nil, 1)
    className:SetPoint("TOPLEFT", name, "TOPLEFT", -2, 1)
    className:SetPoint("BOTTOMRIGHT", name, "BOTTOMRIGHT", 2, -1)
    className:Hide()
    frame.fuiTargetSkin = { body = body, portrait = portraitPanel, className = className, reaction = main.ReputationColor }
    installAuraSpacing(frame, name)
end

local function placeTargetOfTarget(frame, owner)
    if not (type(frame) == "table" and type(owner) == "table" and type(owner.fuiTargetSkin) == "table") then return end
    -- Protected unit frames cannot anchor to our addon-created backdrop.
    -- Preserve the backdrop's position when geometry is available, but anchor
    -- to the native owner instead so the client accepts the relationship.
    local x, y = 0, -20
    local body = owner.fuiTargetSkin.body
    if type(body) == "table" and type(body.GetRight) == "function" and type(body.GetBottom) == "function"
        and type(owner.GetRight) == "function" and type(owner.GetBottom) == "function" then
        local ok, br, bb, bs, oright, obottom, oscale = pcall(function()
            return body:GetRight(), body:GetBottom(), body:GetEffectiveScale(), owner:GetRight(), owner:GetBottom(), owner:GetEffectiveScale()
        end)
        if ok and not ns.Secret(br) and not ns.Secret(bb) and not ns.Secret(bs) and not ns.Secret(oright)
            and not ns.Secret(obottom) and not ns.Secret(oscale) and type(br) == "number" and type(bb) == "number"
            and type(bs) == "number" and type(oright) == "number" and type(obottom) == "number"
            and type(oscale) == "number" and oscale > 0 and bs > 0 then
            x, y = br * bs / oscale - oright, bb * bs / oscale - obottom - 20
        end
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", x, y)
end

local function applyTargetOfTarget(frame, owner)
    if type(frame) ~= "table" or frame.fuiTargetOfTargetSkin then return end
    local name, portrait, health, power = frame.Name, frame.Portrait, frame.HealthBar, frame.ManaBar
    if type(name) ~= "table" or type(portrait) ~= "table" or type(health) ~= "table"
        or type(power) ~= "table" then return end
    health.fuiUnitMask = health.HealthBarMask
    power.fuiUnitMask = power.ManaBarMask
    power.fuiPowerUnit = owner == _G.FocusFrame and "focustarget" or "targettarget"
    alignBars(name, health, power)
    styleBar(health, true)
    styleBar(power)
    local body = CreateFrame("Frame", nil, frame)
    body:SetFrameLevel(frame:GetFrameLevel())
    body:SetPoint("TOPLEFT", name, "TOPLEFT", -11, 3)
    body:SetPoint("BOTTOMRIGHT", power, "BOTTOMRIGHT", 5, -6)
    ns.Panel(body)
    local rim = portraitRim(frame, portrait)
    if type(frame.FrameTexture) == "table" and type(frame.FrameTexture.SetAlpha) == "function" then
        frame.FrameTexture:SetAlpha(0)
    end
    frame.fuiTargetOfTargetSkin = { body = body, portrait = rim }
    placeTargetOfTarget(frame, owner)
    if type(owner) == "table" and type(owner.SetSmallSize) == "function" and hooksecurefunc and not owner.fuiTotPositionHook then
        owner.fuiTotPositionHook = true
        hooksecurefunc(owner, "SetSmallSize", function()
            ns.WhenSafe(function() placeTargetOfTarget(frame, owner) end)
        end)
    end
end

function m:Refresh()
    if InCombatLockdown and InCombatLockdown() then
        updateClassName(_G.TargetFrame, "target")
        updateClassName(_G.FocusFrame, "focus")
        return
    end
    apply(_G.TargetFrame)
    apply(_G.FocusFrame)
    installQuestieHooks()
    updateClassName(_G.TargetFrame, "target")
    updateClassName(_G.FocusFrame, "focus")
    local target, focus = _G.TargetFrame, _G.FocusFrame
    applyTargetOfTarget(type(target) == "table" and target.totFrame or _G.TargetFrameToT, target)
    applyTargetOfTarget(type(focus) == "table" and focus.totFrame or _G.FocusFrameToT, focus)
end

local player = ns.Module("playerframe", "Player frame", function(self)
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
        ns.On(event, function() self:Refresh() end)
    end
    self:Refresh()
end)

function player:Refresh()
    if InCombatLockdown and InCombatLockdown() then return end
    local frame = _G.PlayerFrame
    if type(frame) ~= "table" then return end
    if frame.fuiPlayerSkin then
        local existing = frame.PlayerFrameContainer
        if type(existing) == "table" and type(existing.PlayerPortrait) == "table" then
            placePortrait(frame, frame.fuiPlayerSkin.body, existing.PlayerPortrait, true)
        end
        return
    end
    local container, content = frame.PlayerFrameContainer, frame.PlayerFrameContent
    local main = type(content) == "table" and content.PlayerFrameContentMain
    local area = type(main) == "table" and main.ManaBarArea
    local power = type(area) == "table" and area.ManaBar
    local name = _G.PlayerName
    local portrait = type(container) == "table" and container.PlayerPortrait
    if type(main) ~= "table" or type(main.HealthBarsContainer) ~= "table"
        or type(power) ~= "table" or type(name) ~= "table" or type(portrait) ~= "table" then return end
    power.fuiPowerUnit = "player"
    if type(main.HealthBarsContainer.HealthBar) == "table" then
        main.HealthBarsContainer.HealthBar.fuiUnitMask = main.HealthBarsContainer.HealthBarMask
    end
    power.fuiUnitMask = power.ManaBarMask
    alignBars(name, main.HealthBarsContainer.HealthBar, power, true)
    if type(PlayerFrame_UpdatePlayerNameTextAnchor) == "function" and hooksecurefunc then
        local function align() alignBars(name, main.HealthBarsContainer.HealthBar, power, true) end
        hooksecurefunc("PlayerFrame_UpdatePlayerNameTextAnchor", function() ns.WhenSafe(align) end)
    end
    styleBar(main.HealthBarsContainer.HealthBar, true)
    styleBar(power)
    borderBar(main.HealthBarsContainer.HealthBar)
    borderBar(power)
    styleManaCost(power)

    local body = CreateFrame("Frame", nil, frame)
    body:SetFrameLevel(frame:GetFrameLevel())
    body:SetPoint("TOPLEFT", name, "TOPLEFT", -11, 4)
    body:SetPoint("BOTTOMRIGHT", power, "BOTTOMRIGHT", 5, -6)
    ns.Panel(body)
    placePortrait(frame, body, portrait, true)
    local portraitMask = container.PlayerPortraitMask
    if type(portraitMask) == "table" and type(portraitMask.ClearAllPoints) == "function" then
        portraitMask:ClearAllPoints()
        portraitMask:SetPoint("TOPLEFT", portrait, "TOPLEFT", 0, 0)
        portraitMask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 0, 0)
    end
    local levelCircle = main.LevelBackgroundCircle
    if type(levelCircle) == "table" and type(levelCircle.ClearAllPoints) == "function" then
        levelCircle:ClearAllPoints()
        levelCircle:SetPoint("CENTER", portrait, "BOTTOMLEFT", 4, 4)
    end
    local portraitPanel = portraitRim(frame, portrait)
    alignThreatFlash(container.FrameFlash, portrait)
    if type(main.StatusTexture) == "table" and main.CreateTexture then
        local combatName = main:CreateTexture(nil, "ARTWORK")
        combatName:SetPoint("TOPLEFT", name, "TOPLEFT", -2, 1)
        combatName:SetPoint("BOTTOMRIGHT", name, "BOTTOMRIGHT", 2, -1)
        combatName:SetColorTexture(0.8, 0.12, 0.08, 0.25)
        main.StatusTexture.fuiCombatName = combatName
    end
    alignPlayerStatus(main.StatusTexture, name)
    if type(PlayerFrame_UpdateStatus) == "function" and hooksecurefunc and type(main.StatusTexture) == "table" then
        hooksecurefunc("PlayerFrame_UpdateStatus", function()
            updatePlayerStatusVisibility(main.StatusTexture, main.StatusTexture.fuiCombatName)
        end)
    end
    if type(PlayerFrame_UpdateFlashTextureVisuals) == "function" and hooksecurefunc then
        local function alignFlash() alignThreatFlash(container.FrameFlash, portrait) end
        hooksecurefunc("PlayerFrame_UpdateFlashTextureVisuals", function() ns.WhenSafe(alignFlash) end)
    end
    if type(container.FrameTexture) == "table" and container.FrameTexture.SetAlpha then
        container.FrameTexture:SetAlpha(0)
    end
    frame.fuiPlayerSkin = { body = body, portrait = portraitPanel }
end

local pet = ns.Module("petframe", "Pet frame", function(self)
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UNIT_PET", "PLAYER_REGEN_ENABLED" }) do
        ns.On(event, function() self:Refresh() end)
    end
    self:Refresh()
end)

function pet:Refresh()
    if InCombatLockdown and InCombatLockdown() then return end
    local frame, name, health, power = _G.PetFrame, _G.PetName, _G.PetFrameHealthBar, _G.PetFrameManaBar
    local portrait = type(frame) == "table" and (frame.Portrait or _G.PetPortrait)
    if type(frame) ~= "table" or frame.fuiPetSkin or type(name) ~= "table"
        or type(health) ~= "table" or type(power) ~= "table" or type(portrait) ~= "table" then return end
    alignBars(name, health, power)
    styleBar(health, true)
    styleBar(power)
    local body = CreateFrame("Frame", nil, frame)
    body:SetFrameLevel(frame:GetFrameLevel())
    body:SetPoint("TOPLEFT", name, "TOPLEFT", -11, 3)
    body:SetPoint("BOTTOMRIGHT", power, "BOTTOMRIGHT", 5, -6)
    ns.Panel(body)
    local rim = portraitRim(frame, portrait)
    if type(_G.PetFrameTexture) == "table" and PetFrameTexture.SetAlpha then PetFrameTexture:SetAlpha(0) end
    frame.fuiPetSkin = { body = body, portrait = rim }
end

local party = ns.Module("partyframe", "Party frames", function(self)
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED" }) do
        ns.On(event, function() self:Refresh() end)
    end
    local group = _G.PartyFrame
    if type(group) == "table" and type(group.InitializePartyMemberFrames) == "function" and hooksecurefunc then
        hooksecurefunc(group, "InitializePartyMemberFrames", function() self:Refresh() end)
    end
    self:Refresh()
end)

local function applyPartyMember(frame)
    if type(frame) ~= "table" then return end
    if frame.fuiPartySkin then
        local container = frame.HealthBarContainer
        alignBars(frame.Name, type(container) == "table" and container.HealthBar, frame.ManaBar)
        return
    end
    local healthContainer = frame.HealthBarContainer
    local health = type(healthContainer) == "table" and healthContainer.HealthBar
    local power, name, portrait = frame.ManaBar, frame.Name, frame.Portrait
    if type(health) ~= "table" or type(power) ~= "table" or type(name) ~= "table"
        or type(portrait) ~= "table" then return end
    alignBars(name, health, power)
    styleBar(health, true)
    styleBar(power)
    local body = CreateFrame("Frame", nil, frame)
    body:SetFrameLevel(frame:GetFrameLevel())
    body:SetPoint("TOPLEFT", name, "TOPLEFT", -11, 3)
    body:SetPoint("BOTTOMRIGHT", power, "BOTTOMRIGHT", 5, -6)
    ns.Panel(body)
    local rim = portraitRim(frame, portrait)
    if type(frame.Texture) == "table" and type(frame.Texture.SetAlpha) == "function" then frame.Texture:SetAlpha(0) end
    -- The game reassigns these fills on group and vehicle art updates.
    if type(frame.UpdateArt) == "function" and hooksecurefunc then
        hooksecurefunc(frame, "UpdateArt", function()
            flatFill(health)
            powerFill(power)
            if not (InCombatLockdown and InCombatLockdown()) then alignBars(name, health, power) end
        end)
    end
    frame.fuiPartySkin = { body = body, portrait = rim }
end

function party:Refresh()
    if InCombatLockdown and InCombatLockdown() then return end
    local group = _G.PartyFrame
    if type(group) ~= "table" then return end
    for i = 1, 4 do
        local member
        if type(group.GetPartyMemberFrame) == "function" then member = group:GetPartyMemberFrame(i) end
        member = member or group["MemberFrame" .. i] or _G["PartyMemberFrame" .. i]
        applyPartyMember(member)
    end
end

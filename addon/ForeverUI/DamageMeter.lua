-- Forever UI - the game's damage meter.
--
-- The client's own meter (it counts what the combat log would, without an
-- addon reading the combat log). Each window gets the dark panel and the
-- gold hairline, its header bar goes, and the bars go flat, keeping the
-- class colours. Its settings (what it counts, bar height, icons) are the
-- game's, from the cog on the window.

local _, ns = ...

local styled = setmetatable({}, { __mode = "k" })
local styleEntry

local function fade(texture)
    if type(texture) == "table" and texture.SetAlpha then texture:SetAlpha(0) end
end

local function skinControl(button)
    if type(button) ~= "table" or button.fuiMeterControl then return end
    button.fuiMeterControl = true
    for _, key in ipairs({ "Background", "Left", "Middle", "Right" }) do fade(button[key]) end
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        if button[getter] then fade(button[getter](button)) end
    end
    ns.Panel(button, { alpha = 0.9 })
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", 1, -1)
    highlight:SetPoint("BOTTOMRIGHT", -1, 1)
    highlight:SetColorTexture(1, 0.85, 0.48, 0.12)
end

local function lineIcon(button, width, height, x, y)
    local line = button:CreateTexture(nil, "OVERLAY", nil, 7)
    line:SetPoint("CENTER", x or 0, y or 0)
    line:SetSize(width, height)
    line:SetColorTexture(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3], 1)
    return line
end

local function meterIcon(button, name, size)
    local icon = button:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetPoint("CENTER")
    icon:SetSize(size, size)
    icon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\meter-" .. name .. ".tga")
    return icon
end

local function foldAppearance(w)
    local minimized = w.IsMinimized and w:IsMinimized() or false
    local panel = w.fuiPanel
    if panel then
        panel.bg:ClearAllPoints()
        panel.bg:SetPoint("TOPLEFT")
        if minimized then panel.bg:SetPoint("BOTTOMRIGHT", w, "TOPRIGHT", 0, -28)
        else panel.bg:SetPoint("BOTTOMRIGHT") end
        local bottom, left, right = panel.lines[2], panel.lines[3], panel.lines[4]
        bottom:ClearAllPoints()
        left:ClearAllPoints()
        right:ClearAllPoints()
        if minimized then
            bottom:SetPoint("TOPLEFT", w, "TOPLEFT", 0, -27)
            bottom:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, -27)
            left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT", w, "TOPLEFT", 0, -28)
            right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT", w, "TOPRIGHT", 0, -28)
        else
            bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT")
            left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT")
            right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT")
        end
    end
    if w.fuiPlus then w.fuiPlus:SetShown(minimized) end
    if w.fuiRule then w.fuiRule:SetShown(not minimized) end
    if w.fuiDragHandle and w.EnableMouse then w:EnableMouse(not minimized) end
end

local function addDragHandle(w, meter)
    if not (type(meter) == "table" and meter.SetMovable and w.CreateTexture and w.GetFrameLevel) then return end
    if w.GetSessionWindowIndex and w:GetSessionWindowIndex() ~= 1 then return end
    local handle = CreateFrame("Frame", nil, w)
    handle:SetPoint("TOPLEFT", 1, -1)
    handle:SetPoint("TOPRIGHT", -1, -1)
    handle:SetHeight(27)
    handle:SetFrameLevel(w:GetFrameLevel() + 1)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    for _, button in ipairs({ w.DamageMeterTypeDropdown, w.SessionDropdown, w.SettingsDropdown, w.MinimizeButton, w.fuiReset }) do
        if button and button.SetFrameLevel then button:SetFrameLevel(handle:GetFrameLevel() + 1) end
    end
    ns.WhenSafe(function() meter:SetMovable(true) end)
    handle:SetScript("OnDragStart", function()
        if (InCombatLockdown and InCombatLockdown()) or (w.IsLocked and w:IsLocked()) then return end
        -- Edit Mode can change this flag again after the meter is built.
        local ok = pcall(function()
            meter:SetMovable(true)
            meter:StartMoving()
        end)
        if ok then
            handle.fuiMoving = true
        else
            ns.Print("can't move the damage meter right now; try again outside combat.")
        end
    end)
    handle:SetScript("OnDragStop", function()
        if not handle.fuiMoving then return end
        handle.fuiMoving = nil
        meter:StopMovingOrSizing()
        if meter.SetUserPlaced then meter:SetUserPlaced(false) end
        local x, y = meter:GetLeft(), meter:GetTop()
        if type(x) == "number" and type(y) == "number" and ns.db then
            ns.db.windowPos = ns.db.windowPos or {}
            ns.db.windowPos.damageMeter = { x = x, y = y }
        end
    end)
    w.fuiDragHandle = handle
    local function restore()
        ns.WhenSafe(function()
            local pos = ns.db and ns.db.windowPos and ns.db.windowPos.damageMeter
            local edit = EditModeManagerFrame
            if handle.fuiMoving or (edit and edit.IsEditModeActive and edit:IsEditModeActive()) then return end
            if pos and type(pos.x) == "number" and type(pos.y) == "number" then
                meter:ClearAllPoints()
                meter:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
            end
        end)
    end
    restore()
    if C_Timer and C_Timer.After then C_Timer.After(1, restore) end
    ns.On("PLAYER_ENTERING_WORLD", restore)
    -- Moved (or resized) in the game's Edit Mode: keep where it was left
    -- there, rather than putting it back where it was before (2026-11-26).
    local function remember()
        local x, y = meter:GetLeft(), meter:GetTop()
        if type(x) == "number" and type(y) == "number" and not ns.Secret(x) and not ns.Secret(y) and ns.db then
            ns.db.windowPos = ns.db.windowPos or {}
            ns.db.windowPos.damageMeter = { x = x, y = y }
        end
    end
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("EditMode.Exit", function()
            if C_Timer and C_Timer.After then C_Timer.After(0, remember) else remember() end
        end, handle)
    end
end

local function skinHeader(w, meter)
    local session, settings, minimize = w.SessionDropdown, w.SettingsDropdown, w.MinimizeButton
    local typeDropdown = w.DamageMeterTypeDropdown
    if type(session) ~= "table" then session = nil end
    if type(settings) ~= "table" then settings = nil end
    if type(minimize) ~= "table" then minimize = nil end
    if type(typeDropdown) == "table" then
        typeDropdown:SetSize(20, 20)
        if w.SessionTimer then
            typeDropdown:ClearAllPoints()
            typeDropdown:SetPoint("TOPLEFT", w.SessionTimer, "TOPRIGHT", 0, 5)
        end
        skinControl(typeDropdown)
        fade(typeDropdown.Arrow)
        local arrow = typeDropdown:CreateTexture(nil, "OVERLAY", nil, 7)
        arrow:SetPoint("CENTER")
        arrow:SetSize(12, 12)
        arrow:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\scroll-arrow-down.tga")
    end
    if minimize then
        minimize:SetSize(20, 20)
        minimize:ClearAllPoints()
        minimize:SetPoint("TOPRIGHT", w, "TOPRIGHT", -4, -4)
    end
    if settings and minimize then
        settings:SetSize(20, 20)
        settings:ClearAllPoints()
        settings:SetPoint("RIGHT", minimize, "LEFT", -3, 0)
    end
    if session then
        session:SetHeight(20)
        local width = session.GetWidth and session:GetWidth() or 18
        session:SetWidth(math.max(38, width + 20))
    end
    skinControl(session)
    if session then
        fade(session.Arrow)
        -- WowStyle2 also owns a generic Text field. Its narrow default
        -- anchors produce an ellipsis over the meter's own SessionName.
        fade(session.Text)
        local icon = meterIcon(session, "segment", 19)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", 1, 0)
        if type(session.SessionName) == "table" then
            session.SessionName:ClearAllPoints()
            session.SessionName:SetPoint("LEFT", icon, "RIGHT", 1, 0)
            session.SessionName:SetPoint("RIGHT", -2, 0)
        end
    end
    skinControl(settings)
    if settings then
        fade(settings.Icon)
        meterIcon(settings, "settings", 20)
    end
    skinControl(minimize)
    if minimize then
        lineIcon(minimize, 9, 2)
        w.fuiPlus = lineIcon(minimize, 2, 9)
    end
    if settings and session and C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
        local reset = CreateFrame("Button", nil, w)
        reset:SetSize(20, 20)
        reset:SetPoint("RIGHT", settings, "LEFT", -3, 0)
        skinControl(reset)
        meterIcon(reset, "reset", 20)
        reset:SetScript("OnClick", function() C_DamageMeter.ResetAllCombatSessions() end)
        reset:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Reset damage meter data")
            GameTooltip:Show()
        end)
        reset:SetScript("OnLeave", function() GameTooltip:Hide() end)
        session:ClearAllPoints()
        session:SetPoint("RIGHT", reset, "LEFT", -3, 0)
        w.fuiReset = reset
    elseif session and settings then
        session:ClearAllPoints()
        session:SetPoint("RIGHT", settings, "LEFT", -3, 0)
    end
    if typeDropdown and type(typeDropdown.TypeName) == "table" and session then
        local title = typeDropdown.TypeName
        title:ClearAllPoints()
        title:SetPoint("LEFT", typeDropdown, "RIGHT", 4, 0)
        title:SetPoint("RIGHT", session, "LEFT", -5, 0)
    end
    addDragHandle(w, meter)
    if w.SetMinimized then hooksecurefunc(w, "SetMinimized", foldAppearance) end
    foldAppearance(w)
end

-- ScrollBox acquires and reinitializes entries during Blizzard's combat data
-- refresh. Do not mutate those rows from inside that refresh's call stack.
local pendingStyle = setmetatable({}, { __mode = "k" })
local pendingBackground = setmetatable({}, { __mode = "k" })
local function deferEntry(entry, pending, fn)
    if pending[entry] then return end
    pending[entry] = true
    local function apply()
        if InCombatLockdown and InCombatLockdown() then ns.WhenSafe(apply); return end
        pending[entry] = nil
        fn(entry)
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, apply) else ns.WhenSafe(apply) end
end

local function styleEntries(box, owner)
    if box and ScrollUtil and ScrollUtil.AddAcquiredFrameCallback then
        ScrollUtil.AddAcquiredFrameCallback(box, function(_, frame)
            if type(frame) == "table" then deferEntry(frame, pendingStyle, styleEntry) end
        end, owner, true)
    end
end

styleEntry = function(entry)
    if type(entry) ~= "table" or styled[entry] then
        return
    end
    styled[entry] = true
    local sb = entry.StatusBar
    if sb and sb.SetStatusBarTexture then
        sb:SetStatusBarTexture(ns.FLAT)
    end
    -- The native NumberFont is very condensed at the meter's smaller scale.
    -- Use the game's regular UI face with a soft shadow for contrast, while
    -- leaving the player's text-scale setting and the row layout intact.
    local uiFont = GameFontHighlight and GameFontHighlight.GetFont and GameFontHighlight:GetFont()
    for _, key in ipairs({ "Name", "Value" }) do
        local text = sb and sb[key]
        if type(text) == "table" and text.SetFont and text.GetFont then
            local oldFont = text:GetFont()
            local font = uiFont or oldFont
            if font then text:SetFont(font, 12, "") end
            if text.SetShadowOffset then text:SetShadowOffset(1, -1) end
            if text.SetShadowColor then text:SetShadowColor(0, 0, 0, 0.95) end
        end
    end
    local function flatBack(self)
        local bg = self.StatusBar and self.StatusBar.Background
        if bg and bg.SetColorTexture then
            bg:SetColorTexture(0, 0, 0, 0.35)
        end
        local edge = self.StatusBar and self.StatusBar.BackgroundEdge
        if edge and edge.SetAlpha then
            edge:SetAlpha(0)
        end
    end
    if entry.SetupSharedStyleBackground then
        hooksecurefunc(entry, "SetupSharedStyleBackground", function(self)
            deferEntry(self, pendingBackground, flatBack)
        end)
    end
    flatBack(entry)
    local icon = entry.Icon and entry.Icon.Icon
    if icon and icon.SetTexCoord then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

local function styleSourceWindow(source)
    if type(source) ~= "table" or styled[source] then return end
    styled[source] = true
    -- The native background is an anchor for the scroll box; keep it in
    -- place and hide only its artwork.
    if source.Background then source.Background:SetAlpha(0) end
    ns.Panel(source)
    local close = source.CloseButton
    if type(close) == "table" then
        for _, state in ipairs({ { "SetNormalAtlas", "RedButton-Exit" },
            { "SetPushedAtlas", "RedButton-exit-pressed" },
            { "SetDisabledAtlas", "RedButton-Exit-Disabled" },
            { "SetHighlightAtlas", "RedButton-Highlight" } }) do
            if type(close[state[1]]) == "function" then pcall(close[state[1]], close, state[2]) end
        end
    end
    -- Leave the native scrolling rows alone. Registering addon callbacks on
    -- their recycled ScrollBox frames can taint Blizzard's secret combat data.
end

local function styleWindow(w, meter)
    if type(w) ~= "table" or styled[w] then
        return false
    end
    styled[w] = true
    if w.Header then
        w.Header:SetAlpha(0)
    end
    local inner = w.MinimizeContainer
    if type(inner) == "table" then
        ns.Bin(inner.Background)
    end
    ns.Panel(w)
    -- a hairline under the title row
    local rule = w:CreateTexture(nil, "BORDER", nil, 7)
    rule:SetPoint("TOPLEFT", 1, -28)
    rule:SetPoint("TOPRIGHT", -1, -28)
    rule:SetHeight(1)
    rule:SetColorTexture(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], ns.EdgeAlpha() * 0.6)
    w.fuiRule = rule
    skinHeader(w, meter)

    -- The combat rows are owned and refreshed by the client. Styling their
    -- pooled frames taints the refresh on restricted clients, so retain the
    -- native rows while theming the surrounding window and controls.
    if inner then styleSourceWindow(inner.SourceWindow) end
    return true
end

local function instanceLocation()
    if type(IsInInstance) ~= "function" then return nil end
    local inside, kind = IsInInstance()
    if not inside or (kind ~= "party" and kind ~= "raid") then return nil end
    local id
    if type(GetInstanceInfo) == "function" then
        local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
        if type(instanceID) == "number" and instanceID > 0 then id = instanceID end
    end
    return { kind = kind, id = id }
end

local function enteredInstance(previous, current)
    if not current then return false end
    if not previous or previous.kind ~= current.kind then return true end
    return previous.id and current.id and previous.id ~= current.id or false
end

local function instanceEntry(meter)
    if ns.Opt("meterInstanceReset") and C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
        C_DamageMeter.ResetAllCombatSessions()
    end
    if not ns.Opt("meterInstanceOpen") then return end
    local window = meter.GetPrimarySessionWindow and meter:GetPrimarySessionWindow()
    local damageDone = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone
    if not window then return end
    if damageDone and meter.SetSessionWindowDamageMeterType then
        meter:SetSessionWindowDamageMeterType(window, damageDone)
    end
    if meter.SetSessionWindowMinimized then meter:SetSessionWindowMinimized(window, false) end
    if window.Show then window:Show() end
    if meter.Show then meter:Show() end
end

local m = ns.Module("meter", "Damage meter", function(m)
    m.windows = {}
    ns.AfterBlizzard("Blizzard_DamageMeter", function()
        local meter = DamageMeter
        if type(meter) ~= "table" then
            return
        end
        local lastLocation = instanceLocation()
        local function zoneChanged(event, initialLogin, reloading)
            local current = instanceLocation()
            if not (event == "PLAYER_ENTERING_WORLD" and (initialLogin or reloading))
                and enteredInstance(lastLocation, current) then
                instanceEntry(meter)
            end
            lastLocation = current
        end
        ns.On("PLAYER_ENTERING_WORLD", zoneChanged)
        ns.On("ZONE_CHANGED_NEW_AREA", zoneChanged)
        -- Scale the edit-mode parent rather than its edge-anchored primary
        -- window, so the selection outline and the visible meter agree.
        ns.WhenSafe(function()
            if not meter.fuiScaleApplied and meter.GetScale and meter.SetScale then
                -- 22/28 (about 0.79): the 28-high title row then draws 22
                -- high, the same as the dungeon and farming trackers' headers
                meter:SetScale(meter:GetScale() * 22 / 28)
                meter.fuiScaleApplied = true
            end
        end)
        local function styleAll()
            if meter.ForEachSessionWindow and type(meter.windowDataList) == "table" then
                meter:ForEachSessionWindow(function(w)
                    if styleWindow(w, meter) then
                        table.insert(m.windows, w)
                    end
                end)
            end
        end
        if meter.SetupSessionWindow then
            hooksecurefunc(meter, "SetupSessionWindow", function(_, _, windowData)
                local w = windowData and windowData.sessionWindow
                if styleWindow(w, meter) then
                    table.insert(m.windows, w)
                end
            end)
        end
        styleAll()
    end)
end)

function m:Restyle()
    for _, w in ipairs(self.windows or {}) do
        if w.fuiRule then
            w.fuiRule:SetColorTexture(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], ns.EdgeAlpha() * 0.6)
        end
    end
end

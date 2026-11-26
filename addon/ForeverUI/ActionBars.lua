-- Forever UI - the action bars, restyled.
--
-- The game's own bars and buttons (so keybinds, paging, stances, vehicles
-- and Edit Mode all keep working, and nothing here can cause a "blocked
-- action" in combat). Each button loses its chunky frame: square icon, a
-- dark backing with the gold hairline, keybind small in the corner, a red
-- tint when out of range. The gryphons and the bar's frame go. Where each
-- bar sits, how many rows and how big: Edit Mode, as before.

local _, ns = ...

local BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local SMALL = { "PetActionButton", "StanceButton", "PossessButton" }
local BAR_FRAMES = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
    "MultiBar5", "MultiBar6", "MultiBar7", "PetActionBar", "StanceBar", "PossessActionBar" }

local function shrinkBars()
    for _, name in ipairs(BAR_FRAMES) do
        local f = _G[name]
        if type(f) == "table" and f.SetScale and not f.fuiSizeApplied then
            local ok, err = pcall(function()
                local current = f.GetScale and f:GetScale() or 1
                if type(current) ~= "number" or current <= 0 then current = 1 end
                f:SetScale(current * 0.8)
                f.fuiSizeApplied = true
            end)
            if not ok then ns.Err("action bar size " .. name, err) end
        end
    end
end

-- The main bar can have a different base icon size from the multibars even
-- after both frame scales are reduced. Compare on-screen icon widths after
-- the client has finished its initial layout, and only reduce the main bar
-- if it is still larger. Do this once per UI load, never once per zone.
local calibrated = false
local function matchMainBar()
    if calibrated then return end
    local main = MainActionBar or MainMenuBar
    local first = ActionButton1
    local other = MultiBarBottomLeftButton1 or MultiBarBottomRightButton1 or MultiBarRightButton1 or MultiBarLeftButton1
    if not (main and first and other and main.SetScale and first.GetWidth and other.GetWidth
        and first.GetEffectiveScale and other.GetEffectiveScale) then return end
    local ok, err = pcall(function()
        local a, b = first:GetWidth(), other:GetWidth()
        local as, bs = first:GetEffectiveScale(), other:GetEffectiveScale()
        if type(a) ~= "number" or type(b) ~= "number" or type(as) ~= "number" or type(bs) ~= "number"
            or a <= 0 or b <= 0 or as <= 0 or bs <= 0 then return end
        local ratio = (b * bs) / (a * as)
        if ratio < 0.97 then
            local current = main:GetScale()
            if type(current) ~= "number" or current <= 0 then return end
            main:SetScale(current * ratio)
            calibrated = true
        end
    end)
    if not ok then ns.Err("main bar calibration", err) end
end

local function hide(region)
    if type(region) == "table" and region.SetAlpha then
        region:SetAlpha(0)
    end
end

-- Puts back what the game's art refresh (UpdateButtonArt) changes.
local function reart(b)
    hide(b.NormalTexture)
    hide(b.GetNormalTexture and b:GetNormalTexture())
    hide(b.SlotArt)
    hide(b.SlotBackground)
    local pushed = b.GetPushedTexture and b:GetPushedTexture()
    if pushed and pushed.SetColorTexture then
        pushed:SetColorTexture(0, 0, 0, 0.35)
        pushed:ClearAllPoints()
        pushed:SetAllPoints(b)
    end
end

local function styleButton(b)
    if type(b) ~= "table" or b.fuiStyled then
        return false
    end
    b.fuiStyled = true
    local C = ns.C

    -- square icon, 1px in from the edge
    local icon = b.icon or b.Icon
    if icon then
        if b.IconMask and icon.RemoveMaskTexture then
            pcall(icon.RemoveMaskTexture, icon, b.IconMask)
        end
        if icon.SetTexCoord then
            icon:SetTexCoord(0, 1, 0, 1)
        end
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    end

    -- the dark backing (what an empty slot shows) and the hairline
    local panel = ns.Panel(b)
    -- A one-unit edge can round down to zero at the reduced action-bar scale.
    -- Keep it visible above the icon even on tightly packed vertical bars.
    for i, line in ipairs(panel.lines) do
        if line.SetDrawLayer then line:SetDrawLayer("OVERLAY", 6) end
        if i <= 2 then line:SetHeight(1.5) else line:SetWidth(1.5) end
    end

    -- hover, checked (active stance, auto attack)
    local hl = b.GetHighlightTexture and b:GetHighlightTexture()
    if hl and hl.SetColorTexture then
        hl:SetColorTexture(1, 0.94, 0.78, 0.14)
        hl:ClearAllPoints()
        hl:SetAllPoints(b)
    end
    local checked = b.GetCheckedTexture and b:GetCheckedTexture()
    if checked and checked.SetColorTexture then
        checked:SetColorTexture(C.bright[1], C.bright[2], C.bright[3], 0.28)
        checked:ClearAllPoints()
        checked:SetAllPoints(b)
    end

    -- out of range: a red tint over the icon
    b.fuiRange = b:CreateTexture(nil, "ARTWORK", nil, 7)
    b.fuiRange:SetPoint("TOPLEFT", 1, -1)
    b.fuiRange:SetPoint("BOTTOMRIGHT", -1, 1)
    b.fuiRange:SetColorTexture(0.75, 0.16, 0.12, 0.45)
    b.fuiRange:Hide()

    -- text: keybind top right, count bottom right, macro names small
    local hk = b.HotKey
    if hk and hk.SetPoint then
        hk:ClearAllPoints()
        hk:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -3)
        local font, size, flags = hk:GetFont()
        if font then hk:SetFont(font, math.max(9, (size or 12) - 2), flags or "OUTLINE") end
    end
    local count = b.Count
    if count and count.SetPoint then
        count:ClearAllPoints()
        count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    end
    local name = b.Name
    if name and name.GetFont then
        local font, _, flags = name:GetFont()
        if font then name:SetFont(font, 9, flags or "OUTLINE") end
    end

    -- the cooldown sweep a little darker, no bright edge
    local cd = b.cooldown
    if cd then
        if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.7) end
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        cd:ClearAllPoints()
        cd:SetPoint("TOPLEFT", 1, -1)
        cd:SetPoint("BOTTOMRIGHT", -1, 1)
    end

    reart(b)
    if b.UpdateButtonArt then
        hooksecurefunc(b, "UpdateButtonArt", reart)
    end
    return true
end

-- Skin the native shaman bar and its flyout without moving or replacing its
-- secure buttons. Some of the flyout buttons are created only when opened.
local function styleTotems()
    if InCombatLockdown and InCombatLockdown() then return end
    local flyout = _G.MultiCastFlyoutFrame
    if type(flyout) == "table" then
        for _, key in ipairs({ "top", "middle", "bottom", "Top", "Middle", "Bottom" }) do hide(flyout[key]) end
        if flyout.CreateTexture and not flyout.fuiPanel then ns.Panel(flyout, { alpha = 0.8, edge = 0.7 }) end
        for _, button in ipairs(type(flyout.buttons) == "table" and flyout.buttons or {}) do styleButton(button) end
        if flyout.HookScript and not flyout.fuiTotemHook then
            flyout.fuiTotemHook = true
            flyout:HookScript("OnShow", function() ns.WhenSafe(styleTotems) end)
        end
    end
    for _, prefix in ipairs({ "MultiCastActionButton", "MultiCastFlyoutButton" }) do
        for i = 1, 12 do
            local button = _G[prefix .. i]
            if type(button) == "table" then styleButton(button); hide(button.overlay) end
        end
    end
    for i = 1, 4 do
        local slot = _G["MultiCastSlotButton" .. i]
        if type(slot) == "table" then hide(slot.overlay) end
    end
    for _, name in ipairs({ "MultiCastSummonSpellButton", "MultiCastRecallSpellButton" }) do
        local button = _G[name]
        if type(button) == "table" then styleButton(button); hide(button.overlay) end
    end
    local arrow = _G.MultiCastFlyoutFrameOpenButton
    if type(arrow) == "table" and arrow.CreateTexture and not arrow.fuiTotemArrow then
        ns.Panel(arrow, { alpha = 0.8, edge = 0.7 })
        hide(arrow.GetNormalTexture and arrow:GetNormalTexture())
        local icon = arrow:CreateTexture(nil, "ARTWORK")
        icon:SetSize(12, 12)
        icon:SetPoint("CENTER", arrow, "CENTER", 0, 0)
        icon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\scroll-arrow-down.tga")
        arrow.fuiTotemArrow = icon
    end
end

local m = ns.Module("actionbars", "Action bars", function(m)
    m.buttons = {}
    ns.On("PLAYER_ENTERING_WORLD", function()
        ns.WhenSafe(shrinkBars)
        ns.WhenSafe(styleTotems)
        if not calibrated and C_Timer and C_Timer.After then
            -- The other bar's Edit Mode scale can be applied after our first
            -- comparison. Equal sizes aren't proof that layout is finished.
            for _, delay in ipairs({ 1, 3, 8 }) do
                C_Timer.After(delay, function() ns.WhenSafe(matchMainBar) end)
            end
        end
    end)
    ns.On("ADDON_LOADED", function() ns.WhenSafe(styleTotems) end)
    ns.On("SPELLS_CHANGED", function() ns.WhenSafe(styleTotems) end)
    styleTotems()
    for _, prefix in ipairs(BARS) do
        for i = 1, 12 do
            local b = _G[prefix .. i]
            if styleButton(b) then
                table.insert(m.buttons, b)
            end
        end
    end
    for _, prefix in ipairs(SMALL) do
        for i = 1, 10 do
            local b = _G[prefix .. i]
            if styleButton(b) then
                table.insert(m.buttons, b)
            end
        end
    end

    -- the main bar's frame, gryphons and the dividers between its buttons
    local main = MainActionBar or MainMenuBar
    if main then
        hide(main.BorderArt)
        hide(main.EndCaps)
        if main.UpdateDividers then
            local function noDividers(self)
                for _, key in ipairs({ "HorizontalDividersPool", "VerticalDividersPool" }) do
                    local pool = self[key]
                    if type(pool) == "table" and pool.EnumerateActive then
                        for d in pool:EnumerateActive() do
                            d:SetAlpha(0)
                        end
                    end
                end
            end
            hooksecurefunc(main, "UpdateDividers", noDividers)
            noDividers(main)
        end
    end

    -- out of range: red tint (the game only reddens the keybind)
    if ActionButton_UpdateRangeIndicator then
        hooksecurefunc("ActionButton_UpdateRangeIndicator", function(self, checksRange, inRange)
            local t = self and self.fuiRange
            if t then
                t:SetShown(checksRange and inRange == false and true or false)
            end
        end)
    end
end)

function m:Restyle()
    for _, b in ipairs(self.buttons or {}) do
        ns.PaintPanel(b)
    end
end

-- Forever UI character statistics: reuse Blizzard's class-aware stat data and
-- row templates, but lay the rows out in columns without a scroll bar.
local _, ns = ...
local COL_W, GAP, PAD = 187, 10, 8
local HEADER_H, ROW_H, ICON_H = 22, 19, 29

local function arrange(data, height)
    if type(data) ~= "table" or type(height) ~= "number" or height < 70 then return end
    local groups, group, total = {}, nil, 0
    for _, entry in ipairs(data) do
        if type(entry) == "table" and not entry.shouldRemove then
            local h = entry.isHeader and HEADER_H or (entry.texture and ICON_H or ROW_H)
            -- Break exceptionally long categories into chunks, while keeping
            -- the heading attached to at least its first row.
            if not group or entry.isHeader or group.height + h > height then
                group = { entries = {}, height = 0 }
                groups[#groups + 1] = group
            end
            group.entries[#group.entries + 1] = { data = entry, height = h }
            group.height, total = group.height + h, total + h
        end
    end
    if #groups == 0 then return end
    local columns = math.max(math.ceil(total / height), #groups > 1 and 2 or 1)
    -- Place whole categories into the least-filled column. If a category
    -- won't fit, retry with another column rather than clipping rows.
    while columns <= #groups do
        local used, result, fits = {}, {}, true
        for c = 1, columns do used[c] = 0 end
        for _, block in ipairs(groups) do
            local best
            for c = 1, columns do
                if used[c] + block.height <= height and (not best or used[c] < used[best]) then best = c end
            end
            if not best then fits = false; break end
            for _, item in ipairs(block.entries) do
                result[#result + 1] = { data = item.data, column = best, y = used[best], height = item.height }
                used[best] = used[best] + item.height
            end
        end
        if fits then return result, columns end
        columns = columns + 1
    end
end
ns.ArrangeCharacterStats = arrange

local function safeShown(frame)
    if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
end

-- A frame can be implicitly protected by an anchored or child frame. Only
-- modify it during lockdown when the client explicitly reports it safe.
local function combatSafe(frame)
    if type(frame) ~= "table" or type(frame.IsProtected) ~= "function" then return false end
    if type(frame.IsForbidden) == "function" then
        local ok, forbidden = pcall(frame.IsForbidden, frame)
        if not ok or forbidden then return false end
    end
    local ok, protected = pcall(frame.IsProtected, frame)
    return ok and protected == false
end

local m = ns.Module("characterpage", "Character page", function(m)
    m.rows = {}
    m.wideWidth = tonumber(ns.db.characterWideWidth)
    function m:RefreshSafely()
        if self.refreshing then return end
        self.refreshing = true
        local ok, err = pcall(function() self:Refresh() end)
        self.refreshing = false
        if not ok then
            self:Restore()
            if not self.reportedError then ns.Err("character page", err); self.reportedError = true end
        end
    end
    function m:HookNativeStats()
        local stats = CharacterStatsPaneScrollBox
        if type(stats) ~= "table" or self.hookedStats == stats then return end
        self.hookedStats = stats
        if type(stats.UpdateStats) == "function" then
            hooksecurefunc(stats, "UpdateStats", function() m:RefreshSafely() end)
        end
        if type(stats.HookScript) == "function" then
            stats:HookScript("OnShow", function()
                m:RefreshSafely()
                if C_Timer and C_Timer.After then C_Timer.After(0, function() m:RefreshSafely() end) end
            end)
        end
    end
    function m:HookWindow()
        local frame = CharacterFrame
        if type(frame) ~= "table" or self.hookedWindow == frame then return end
        self.hookedWindow = frame
        if type(frame.UpdateSize) == "function" then
            hooksecurefunc(frame, "UpdateSize", function(selfFrame)
                if selfFrame.activeSubframe == "PaperDollFrame" and type(selfFrame.GetWidth) == "function" then
                    local width = selfFrame:GetWidth()
                    if type(width) == "number" and width > 0 then m.statsBase = width end
                end
                m:ApplyWideWindow()
            end)
        end
        if type(frame.UpdateTitle) == "function" then
            hooksecurefunc(frame, "UpdateTitle", function() m:UpdateHeading() end)
        end
        if type(frame.HookScript) == "function" then
            frame:HookScript("OnShow", function() m:ApplyWideWindow(); m:UpdateHeading() end)
        end
    end
    m:HookNativeStats()
    m:HookWindow()
    -- PLAYER_REGEN_DISABLED can fire just before lockdown takes effect; check
    -- again on the next frame, once the client's protection state is final.
    ns.On("PLAYER_REGEN_DISABLED", function()
        if C_Timer and C_Timer.After then C_Timer.After(0, function() m:RefreshSafely() end) end
    end)
    ns.On("PLAYER_REGEN_ENABLED", function()
        m:RefreshSafely()
        m:UpdateHeading()
    end)
    local timer = CreateFrame("Frame")
    local elapsed = 0
    timer:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed < 0.4 then return end
        elapsed = 0
        m:HookNativeStats()
        m:HookWindow()
        m:RefreshSafely()
    end)
    m.timer = timer
end)

function m:UpdateHeading()
    if InCombatLockdown and InCombatLockdown() then return end
    local frame, paper, level = CharacterFrame, PaperDollFrame, PaperDollLevelInfo
    if type(frame) ~= "table" or frame.activeSubframe ~= "PaperDollFrame" then return end
    if type(frame.SetTitle) == "function" then frame:SetTitle(CHARACTER or "Character") end
    local host = frame.LeftPaneHost
    if type(host) ~= "table" or type(paper) ~= "table" then return end
    if not self.nameLabel then
        local label = ns.Text(paper, 13, ns.C.text)
        label:SetPoint("TOP", host, "TOP", 0, -5)
        self.nameLabel = label
    end
    local name = UnitName and UnitName("player")
    if type(name) == "string" and name ~= "" and not ns.Secret(name) then self.nameLabel:SetText(name) end
    if type(level) == "table" and not self.headingPlaced then
        level:ClearAllPoints()
        level:SetPoint("TOP", host, "TOP", 0, -25)
        self.headingPlaced = true
    end
end

local function placePaneToggle(frame)
    local button, left = frame.RightPaneToggleButton, frame.LeftPaneHost
    if type(button) ~= "table" or type(left) ~= "table" or type(button.GetPoint) ~= "function"
        or type(button.ClearAllPoints) ~= "function" or type(button.SetPoint) ~= "function" then return end
    local target = frame.activeSubframe == "StatisticsFrame" and frame or left
    local point, relative, relativePoint, x, y = button:GetPoint(1)
    local offsetY = target == frame and -26 or -6
    if point == "TOPRIGHT" and relative == target and relativePoint == "TOPRIGHT"
        and x == -6 and y == offsetY then return end
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", target, "TOPRIGHT", -6, offsetY)
end

local function stretchStatistics(frame)
    if frame.activeSubframe ~= "StatisticsFrame" then return end
    local stats, left = _G.StatisticsFrame, frame.LeftPaneHost
    local box = type(stats) == "table" and stats.ScrollBox
    if type(left) ~= "table" or type(box) ~= "table" or type(box.GetPoint) ~= "function"
        or type(box.ClearAllPoints) ~= "function" or type(box.SetPoint) ~= "function" then return end
    local point, relative, relativePoint, x, y = box:GetPoint(2)
    if point == "BOTTOMRIGHT" and relative == frame and relativePoint == "BOTTOMRIGHT"
        and x == -25 and y == 15 then return end
    -- The native scrollbar follows this list; keep the list's original top
    -- inset while letting its right edge use the whole character window.
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", left, "TOPLEFT", 10, -40)
    box:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -25, 15)
end

function m:ApplyWideWindow()
    local combat = InCombatLockdown and InCombatLockdown()
    if combat and not self:CanLayoutInCombat() then self:CombatFallback(); return end
    local frame = CharacterFrame
    if type(frame) ~= "table" or not safeShown(frame) then return end
    -- These tab-specific anchor changes can wait; the ordinary paper-doll
    -- stats only need the existing anchors and the wider window.
    if not combat then placePaneToggle(frame); stretchStatistics(frame) end
    local wide, screen = self.wideWidth, UIParent:GetWidth()
    if type(wide) ~= "number" or type(screen) ~= "number" or wide > screen - 40 then return end
    local current = frame:GetWidth()
    if type(current) == "number" and math.abs(current - wide) > 0.1 then frame:SetWidth(wide) end
    local left = frame.LeftPaneHost
    if type(left) ~= "table" or type(left.GetWidth) ~= "function" or type(left.SetWidth) ~= "function" then return end
    local leftWidth = left:GetWidth()
    if not self.leftBase and type(leftWidth) == "number" and leftWidth > 0 then self.leftBase = leftWidth end
    local paperDoll = frame.activeSubframe == "PaperDollFrame"
    if paperDoll and self.leftBase then
        if math.abs(leftWidth - self.leftBase) > 0.1 then left:SetWidth(self.leftBase) end
    elseif type(frame.activeSubframe) == "string" and not paperDoll then
        -- Camelot anchors the detail panel immediately after LeftPaneHost.
        -- Give the list the extra width while keeping that panel inside the
        -- window, rather than pushing it past the right-hand tabs.
        local right = frame.RightPaneHost
        local rightWidth = type(right) == "table" and type(right.GetWidth) == "function" and right:GetWidth() or nil
        if type(rightWidth) ~= "number" or rightWidth <= 0 then rightWidth = 233 end
        local target = math.max(1, wide - rightWidth)
        if type(leftWidth) == "number" and math.abs(leftWidth - target) > 0.1 then left:SetWidth(target) end
    end
end

function m:CanLayoutInCombat()
    local frame, stats = CharacterFrame, CharacterStatsPaneScrollBox
    if not (combatSafe(frame) and combatSafe(frame.LeftPaneHost)) then return false end
    if type(stats) == "table" then
        if not combatSafe(stats) or (stats.ScrollBox and not combatSafe(stats.ScrollBox))
            or (stats.ScrollBar and not combatSafe(stats.ScrollBar)) then return false end
    end
    if self.panel and not combatSafe(self.panel) then return false end
    return true
end

function m:CombatFallback()
    if self.hiddenScroll or (self.panel and safeShown(self.panel)) then self:Restore() end
end

function m:Restore()
    if self.panel then self.panel:Hide() end
    if self.hiddenScroll then
        local s = self.hiddenScroll
        if s.box then s.box:SetAlpha(s.boxAlpha); if s.box.EnableMouse then s.box:EnableMouse(s.boxMouse) end end
        if s.bar then s.bar:SetAlpha(s.barAlpha); if s.bar.EnableMouse then s.bar:EnableMouse(s.barMouse) end end
        self.hiddenScroll = nil
    end
    local frame = self.frame
    if frame and self.baseWidth and self.appliedWidth and not safeShown(frame) and not (InCombatLockdown and InCombatLockdown()) then
        local width = frame:GetWidth()
        if type(width) == "number" and math.abs(width - self.appliedWidth) < 1 then frame:SetWidth(self.baseWidth) end
    end
    self.baseWidth, self.appliedWidth, self.frame = nil, nil, nil
    self.data, self.signature = nil, nil
end

local function regionAlpha(f)
    local ok, value = pcall(function() return f:GetAlpha() end)
    return ok and type(value) == "number" and value or 1
end
local function mouseEnabled(f)
    if type(f.IsMouseEnabled) ~= "function" then return true end
    local ok, value = pcall(f.IsMouseEnabled, f)
    return not ok or value ~= false
end

function m:Refresh()
    if InCombatLockdown and InCombatLockdown() and not self:CanLayoutInCombat() then self:CombatFallback(); return end
    local frame, stats = CharacterFrame, CharacterStatsPaneScrollBox
    if not (type(frame) == "table" and safeShown(frame) and type(stats) == "table" and safeShown(stats)
        and type(stats.ScrollBox) == "table" and type(stats.elementData) == "table") then
        if self.frame then self:Restore() end
        self:ApplyWideWindow()
        return
    end
    local height = stats:GetHeight()
    local screenWidth = UIParent:GetWidth()
    if type(height) ~= "number" or type(screenWidth) ~= "number" then return end
    local availableHeight = height - 2 * PAD
    local items, columns = arrange(stats.elementData, availableHeight)
    if not items then if self.frame then self:Restore() end; return end
    local currentWidth = frame:GetWidth()
    if type(currentWidth) ~= "number" or currentWidth <= 0 then return end
    local base = self.baseWidth or self.statsBase or currentWidth
    -- If Blizzard changed the width (e.g. a character tab switch), respect it.
    if self.appliedWidth and math.abs(currentWidth - self.appliedWidth) > 1 then base = currentWidth end
    local desired = math.max(base + math.max(0, columns - 1) * (COL_W + GAP), self.wideWidth or 0)
    if desired > screenWidth - 40 then
        if self.frame then self:Restore() end
        if currentWidth > screenWidth - 40 and base <= screenWidth - 40 then frame:SetWidth(base) end
        return -- leave the original scrollable stats usable on small screens
    end
    if not self.panel then
        local panel = CreateFrame("Frame", "ForeverUICharacterStats", stats)
        panel:SetAllPoints(stats)
        self.panel = panel
    end
    local signature = tostring(#items) .. ":" .. tostring(columns)
    -- Blizzard rebuilds elementData when stats change; do not cache its values.
    if self.data ~= stats.elementData or self.signature ~= signature then
        for _, row in ipairs(self.rows) do row:Hide() end
        local created = {}
        for i, item in ipairs(items) do
            local entry = item.data
            local kind = entry.isHeader and "header" or (entry.texture and "icon" or "stat")
            local row = self.rows[i]
            if not row or row.fuiKind ~= kind then
                if row then row:Hide() end
                if kind == "header" then
                    row = CreateFrame("Frame", nil, self.panel)
                    row.title = ns.Text(row, 11, ns.C.bright)
                    row.title:SetPoint("LEFT", 2, 0)
                    local line = row:CreateTexture(nil, "BORDER")
                    line:SetPoint("BOTTOMLEFT", 0, 0); line:SetPoint("BOTTOMRIGHT", 0, 0); line:SetHeight(1)
                    line:SetColorTexture(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], 0.45)
                else
                    local template = kind == "icon" and "CharacterStatFrameScrollBoxIconElementTemplate"
                        or "CharacterStatFrameScrollBoxLabelElementTemplate"
                    row = CreateFrame("Frame", nil, self.panel, template)
                    if type(row.Init) ~= "function" then error("native character stat template unavailable") end
                end
                row.fuiKind = kind
                self.rows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.panel, "TOPLEFT", PAD + (item.column - 1) * (COL_W + GAP), -PAD - item.y)
            row:SetSize(COL_W, item.height)
            if kind == "header" then row.title:SetText(entry.name or "")
            else
                row:Init(entry)
                if row.Background and row.Background.SetAlpha then row.Background:SetAlpha(0) end
            end
            created[#created + 1] = row
        end
        self.data, self.signature = stats.elementData, signature
        for _, row in ipairs(created) do row:Show() end
    end
    -- Only hide the native scroll controls after every replacement row worked.
    if not self.hiddenScroll then
        local box, bar = stats.ScrollBox, stats.ScrollBar
        self.hiddenScroll = { box = box, boxAlpha = regionAlpha(box), boxMouse = mouseEnabled(box) }
        if type(bar) == "table" then
            self.hiddenScroll.bar, self.hiddenScroll.barAlpha, self.hiddenScroll.barMouse = bar, regionAlpha(bar), mouseEnabled(bar)
        end
        box:SetAlpha(0); if box.EnableMouse then box:EnableMouse(false) end
        if self.hiddenScroll.bar then bar:SetAlpha(0); if bar.EnableMouse then bar:EnableMouse(false) end end
    end
    self.frame, self.baseWidth, self.appliedWidth = frame, base, desired
    self.statsBase, self.wideWidth = base, desired
    ns.db.characterWideWidth = desired
    if math.abs(currentWidth - desired) > 0.1 then frame:SetWidth(desired) end
    self:ApplyWideWindow()
    self.panel:Show()
end

-- Forever UI - the cast bar and the swing timers.
--
-- Both are the game's own (the client has its own swing timer, which knows
-- about every swing without reading the combat log). They lose their
-- frame art: a flat fill on a dark bar with the gold hairline. Where they
-- sit and how big: Edit Mode, as before.

local _, ns = ...

-- what a fill colour means
local function castColor(barType)
    local C = ns.C
    if barType == "interrupted" then
        return 0.75, 0.2, 0.16
    elseif barType == "uninterruptable" then
        return 0.55, 0.55, 0.58
    elseif barType == "channel" then
        return 0.55, 0.72, 0.45
    elseif barType == "applyingcrafting" or barType == "applyingtalents" then
        return 0.5, 0.62, 0.8
    end
    return C.gold[1], C.gold[2], C.gold[3]
end

-- A hairline 1px outside a bar (above it, so the fill never covers it) and
-- a dark backing under it.
local function frameBar(bar)
    local edge = CreateFrame("Frame", nil, bar)
    edge:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
    ns.Panel(edge, { noBg = true })
    local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints(bar)
    bg:SetColorTexture(ns.C.dark[1], ns.C.dark[2], ns.C.dark[3], ns.PanelAlpha())
    bar.fuiBg = bg
    bar.fuiEdge = edge
    return edge
end

----------------------------------------------------------------------
-- Cast bar
----------------------------------------------------------------------

-- The game's glows, frame and flashes. Taken away rather than hidden, so
-- its animations can play on them without anything drawing.
local CAST_ART = { "Border", "TextBorder", "Background", "DropShadow", "BorderShield", "Flash", "StandardGlow",
    "CraftGlow", "ChannelShadow", "EnergyGlow", "InterruptGlow", "ChargeGlow", "BaseGlow", "WispGlow", "Shine" }

local function anchorProgress(bar)
    local line = bar.fuiProgressLine
    local texture = type(bar.GetStatusBarTexture) == "function" and bar:GetStatusBarTexture()
    if not line or type(texture) ~= "table" then return end
    local reverse = false
    if type(bar.GetReverseFill) == "function" then
        local ok, value = pcall(bar.GetReverseFill, bar)
        reverse = ok and not ns.Secret(value) and value == true
    end
    line:ClearAllPoints()
    if reverse then
        line:SetPoint("TOPLEFT", texture, "TOPLEFT", 0, 0)
        line:SetPoint("BOTTOMLEFT", texture, "BOTTOMLEFT", 0, 0)
    else
        line:SetPoint("TOPRIGHT", texture, "TOPRIGHT", 0, 0)
        line:SetPoint("BOTTOMRIGHT", texture, "BOTTOMRIGHT", 0, 0)
    end
    line:SetWidth(2)
    if bar.Spark and bar.Spark.SetAlpha then bar.Spark:SetAlpha(0) end
end

local function fill(bar)
    local t = bar.barType
    if ns.Secret(t) then
        anchorProgress(bar)
        return -- the game's own colours, then
    end
    bar:SetStatusBarTexture(ns.FLAT)
    bar:SetStatusBarColor(castColor(t))
    anchorProgress(bar)
end

local function updateCastTimer(bar)
    local timer = bar.fuiTimer
    if not timer then return end
    local casting, channeling, reverse = bar.casting, bar.channeling, bar.reverseChanneling
    if ns.Secret(casting) or ns.Secret(channeling) or ns.Secret(reverse)
        or not (casting or channeling or reverse)
        or type(bar.GetMinMaxValues) ~= "function" or type(bar.GetValue) ~= "function" then
        timer:Hide()
        return
    end
    local ok, low, high = pcall(bar.GetMinMaxValues, bar)
    local okValue, value = pcall(bar.GetValue, bar)
    if not ok or not okValue or ns.Secret(low) or ns.Secret(high) or ns.Secret(value)
        or type(low) ~= "number" or type(high) ~= "number" or type(value) ~= "number" then
        timer:Hide()
        return
    end
    local remaining = (channeling and not casting and not reverse) and (value - low) or (high - value)
    timer:SetText(string.format("%.1fs", math.max(0, remaining)))
    timer:Show()
end

local function styleCastBar(bar)
    if type(bar) ~= "table" or bar.fuiStyled then
        return false
    end
    bar.fuiStyled = true
    for _, key in ipairs(CAST_ART) do
        ns.Bin(bar[key])
    end
    frameBar(bar)
    if bar == _G.PlayerCastingBarFrame or bar == _G.OverlayPlayerCastingBarFrame then
        local line = bar:CreateTexture(nil, "OVERLAY", nil, 5)
        line:SetColorTexture(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3], 1)
        bar.fuiProgressLine = line
    end
    local icon = bar.Icon
    if icon and icon.SetTexCoord then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    local text = bar.Text
    local isPlayer = bar == _G.PlayerCastingBarFrame or bar == _G.OverlayPlayerCastingBarFrame
    if text and text.GetFont then
        -- Keep the label outside the status bar's fill clipping. A separate
        -- sibling follows the whole bar, not its changing filled width.
        -- An independent UIParent child avoids inheriting clipping and frame
        -- layers from the client's casting bar containers.
        local textHost = CreateFrame("Frame", nil, UIParent)
        textHost:SetAllPoints(bar)
        if textHost.EnableMouse then textHost:EnableMouse(false) end
        -- Cast and interaction fills may use a different client container.
        -- Keep this label above either container but below game tooltips.
        local function raiseText()
            if textHost.SetFrameStrata and bar.GetFrameStrata then
                local strata = bar:GetFrameStrata()
                if ns.Secret(strata) or type(strata) ~= "string" then strata = "MEDIUM" end
                textHost:SetFrameStrata(strata == "TOOLTIP" and "TOOLTIP" or "FULLSCREEN_DIALOG")
            end
            if textHost.SetFrameLevel and bar.GetFrameLevel then
                local level = bar:GetFrameLevel()
                if not ns.Secret(level) and type(level) == "number" then textHost:SetFrameLevel(math.max(100, level + 10)) end
            end
        end
        raiseText()
        bar.fuiTextHost = textHost
        local label = ns.Text(textHost, 10, ns.C.text, "OVERLAY")
        if label.SetDrawLayer then label:SetDrawLayer("OVERLAY", 7) end
        bar.fuiCastLabel = label
        local function syncText()
            if text.SetAlpha then pcall(text.SetAlpha, text, 0) end
            if text.GetText then
                local ok, value = pcall(text.GetText, text)
                if ok then pcall(label.SetText, label, value) end
            end
        end
        local function centerText()
            label:ClearAllPoints()
            local inset = isPlayer and 42 or 4
            label:SetPoint("LEFT", textHost, "LEFT", inset, 0)
            label:SetPoint("RIGHT", textHost, "RIGHT", -inset, 0)
            label:SetJustifyH("CENTER")
        end
        if bar.HookScript then
            bar:HookScript("OnShow", function() raiseText(); centerText(); syncText(); textHost:Show() end)
            bar:HookScript("OnHide", function() textHost:Hide() end)
        end
        if bar.IsShown and not bar:IsShown() then textHost:Hide() end
        local font = text:GetFont()
        if font then label:SetFont(font, 10, "OUTLINE") end
        centerText(); syncText()
        if type(hooksecurefunc) == "function" and type(text.SetText) == "function" then
            pcall(hooksecurefunc, text, "SetText", syncText)
        end
        if bar.HookScript then
            local elapsed = 0
            bar:HookScript("OnUpdate", function(_, dt)
                elapsed = elapsed + (dt or 0)
                if elapsed >= 0.1 then elapsed = 0; syncText() end
            end)
        end
        if isPlayer then
            local timer = ns.Text(textHost, 10, ns.C.text)
            timer:SetPoint("RIGHT", textHost, "RIGHT", -5, 0)
            timer:SetWidth(36)
            timer:SetJustifyH("RIGHT")
            timer:Hide()
            bar.fuiTimer = timer
            -- The client may already provide a cast-time label; ours uses the
            -- unclipped overlay and replaces that label only for this bar.
            if type(bar.CastTimeText) == "table" and bar.CastTimeText.SetAlpha then bar.CastTimeText:SetAlpha(0) end
            if bar.HookScript then
                local elapsed = 0
                bar:HookScript("OnUpdate", function(self, dt)
                    elapsed = elapsed + (dt or 0)
                    if elapsed >= 0.1 then elapsed = 0; updateCastTimer(self) end
                end)
                bar:HookScript("OnHide", function(self) self.fuiTimer:Hide() end)
            end
        end
    end
    if bar.UpdateBarFillTexture then
        hooksecurefunc(bar, "UpdateBarFillTexture", fill)
    end
    fill(bar)
    return true
end

-- The client uses the same pool for breath, fatigue and feign-death timers.
-- Style the game's bars in place so timer behaviour and native Edit Mode stay.
local function mirrorFill(timer)
    local bar = type(timer) == "table" and timer.StatusBar
    if type(bar) ~= "table" then return end
    bar:SetStatusBarTexture(ns.FLAT)
    local kind = timer.timer
    if ns.Secret(kind) then kind = nil end
    local c = kind == "BREATH" and { 0.35, 0.62, 0.78 }
        or kind == "DEATH" and { 0.72, 0.3, 0.25 }
        or kind == "FEIGNDEATH" and { 0.55, 0.72, 0.45 } or ns.C.gold
    bar:SetStatusBarColor(c[1], c[2], c[3])
end

local function styleMirrorTimer(timer)
    if type(timer) ~= "table" or timer.fuiMirrorStyled or type(timer.StatusBar) ~= "table" then return end
    local bar = timer.StatusBar
    timer.fuiMirrorStyled = true
    if timer.Border and timer.Border.SetAlpha then timer.Border:SetAlpha(0) end
    if timer.TextBorder and timer.TextBorder.SetAlpha then timer.TextBorder:SetAlpha(0) end
    if type(timer.GetRegions) == "function" then
        for _, region in ipairs({ timer:GetRegions() }) do
            if type(region) == "table" and type(region.GetAtlas) == "function" then
                local ok, atlas = pcall(region.GetAtlas, region)
                if ok and atlas == "ui-castingbar-background" and region.SetAlpha then region:SetAlpha(0) end
            end
        end
    end
    frameBar(bar)
    if type(timer.Text) == "table" and timer.Text.ClearAllPoints and timer.Text.SetPoint then
        timer.Text:ClearAllPoints()
        timer.Text:SetPoint("CENTER", bar, "CENTER", 0, 0)
        if timer.Text.SetJustifyH then timer.Text:SetJustifyH("CENTER") end
        if timer.Text.SetTextColor then timer.Text:SetTextColor(ns.C.text[1], ns.C.text[2], ns.C.text[3]) end
    end
    if type(timer.Setup) == "function" then hooksecurefunc(timer, "Setup", mirrorFill) end
    mirrorFill(timer)
end

local cast = ns.Module("castbar", "Cast bar", function(m)
    m.bars = {}
    m.mirrors = {}
    -- Some client layouts omit the overlay bar. A nil in a literal frame
    -- list would stop ipairs before reaching the pet's cast bar.
    for _, name in ipairs({ "PlayerCastingBarFrame", "OverlayPlayerCastingBarFrame", "PetCastingBarFrame" }) do
        local bar = _G[name]
        if styleCastBar(bar) then
            table.insert(m.bars, bar)
        end
    end
    local watcher = CreateFrame("Frame", nil, UIParent)
    local elapsed = 0
    watcher:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.5 then elapsed = 0; m:MatchSwingSize() end
    end)
    m.sizeWatcher = watcher
    ns.On("PLAYER_REGEN_ENABLED", function() m:MatchSwingSize() end)
    m:MatchSwingSize()
    ns.AfterBlizzard("Blizzard_MirrorTimer", function()
        local container = _G.MirrorTimerContainer
        for _, timer in ipairs(type(container) == "table" and type(container.mirrorTimers) == "table" and container.mirrorTimers or {}) do
            styleMirrorTimer(timer)
            if timer.fuiMirrorStyled then table.insert(m.mirrors, timer) end
        end
    end)
end)

function cast:MatchSwingSize()
    if InCombatLockdown and InCombatLockdown() then return end
    local swing = _G.SwingTimerMainHandFrame
    if type(swing) ~= "table" or not swing.GetWidth or not swing.GetHeight or not swing.GetEffectiveScale then return end
    local width, height, scale = swing:GetWidth(), swing:GetHeight(), swing:GetEffectiveScale()
    if type(width) ~= "number" or type(height) ~= "number" or type(scale) ~= "number"
        or width <= 0 or height <= 0 or scale <= 0 then return end
    -- The visible swing fill can be shorter than its enclosing frame. Match
    -- that actual on-screen thickness instead of the surrounding container.
    local fill = swing.StatusBar
    local fillHeight, fillScale
    if type(fill) == "table" and fill.GetHeight and fill.GetEffectiveScale then
        fillHeight, fillScale = fill:GetHeight(), fill:GetEffectiveScale()
    end
    local screenHeight = height * scale
    if type(fillHeight) == "number" and type(fillScale) == "number" and fillHeight > 0 and fillScale > 0 then
        screenHeight = fillHeight * fillScale
    end
    for _, name in ipairs({ "PlayerCastingBarFrame", "OverlayPlayerCastingBarFrame" }) do
        local bar = _G[name]
        if type(bar) == "table" and bar.fuiStyled and bar.GetEffectiveScale and bar.SetSize then
            local barScale = bar:GetEffectiveScale()
            if type(barScale) == "number" and barScale > 0 then
                local w, h = width * scale / barScale, screenHeight / barScale
                if math.abs((bar:GetWidth() or 0) - w) > 0.1 or math.abs((bar:GetHeight() or 0) - h) > 0.1 then
                    bar:SetSize(w, h)
                end
            end
        end
    end
end

function cast:Restyle()
    for _, bar in ipairs(self.bars or {}) do
        bar.fuiBg:SetColorTexture(ns.C.dark[1], ns.C.dark[2], ns.C.dark[3], ns.PanelAlpha())
        fill(bar)
    end
    for _, timer in ipairs(self.mirrors or {}) do
        local bg = timer.StatusBar and timer.StatusBar.fuiBg
        if bg then bg:SetColorTexture(ns.C.dark[1], ns.C.dark[2], ns.C.dark[3], ns.PanelAlpha()) end
        mirrorFill(timer)
    end
end

----------------------------------------------------------------------
-- Swing timers
----------------------------------------------------------------------

local SWING = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }

local function swingColor(f)
    local C = ns.C
    local kind = f.swingType
    if kind == 1 then
        return C.muted -- off hand
    elseif kind == 2 then
        return { 0.6, 0.72, 0.5 } -- ranged
    end
    return C.gold
end

local function swingFill(f)
    local sb = f.StatusBar
    if not sb then
        return
    end
    sb:SetStatusBarTexture(ns.FLAT)
    local c = swingColor(f)
    sb:SetStatusBarColor(c[1], c[2], c[3])
    local pip, tex = sb.Pip, sb:GetStatusBarTexture()
    if pip and tex then
        pip:SetColorTexture(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3], 1)
        pip:ClearAllPoints()
        pip:SetPoint("TOPRIGHT", tex, "TOPRIGHT", 0, 0)
        pip:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 0, 0)
        pip:SetWidth(2)
    end
end

-- Out of range the game dims the bar; ours dims with it.
local function swingRange(f)
    local a = (f.IsOutOfRange and f:IsOutOfRange()) and 0.4 or 1
    local p = f.fuiPanel
    if p then
        p.bg:SetAlpha(a)
        for _, l in ipairs(p.lines) do
            l:SetAlpha(a)
        end
    end
end

local function styleSwing(f)
    if type(f) ~= "table" or f.fuiStyled then
        return false
    end
    f.fuiStyled = true
    ns.WhenSafe(function()
        if not f.fuiSizeApplied and f.SetScale then
            local ok, err = pcall(function()
                local current = f.GetScale and f:GetScale() or 1
                if type(current) ~= "number" or current <= 0 then current = 1 end
                f:SetScale(current * 0.9)
                f.fuiSizeApplied = true
            end)
            if not ok then ns.Err("swing size", err) end
        end
    end)
    ns.Bin(f.Background)
    ns.Bin(f.Border)
    ns.Panel(f)
    local sb = f.StatusBar
    if sb then
        sb:ClearAllPoints()
        sb:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        sb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        ns.Bin(sb.TypeLabelShadow)
        for _, fs in ipairs({ sb.TypeLabel, sb.TimeLabel }) do
            if fs and fs.GetFont then
                local font, _, flags = fs:GetFont()
                if font then fs:SetFont(font, 10, flags or "") end
            end
        end
    end
    if f.InitializeBarPresentation then
        hooksecurefunc(f, "InitializeBarPresentation", swingFill)
    end
    if f.ApplyRangePresentation then
        hooksecurefunc(f, "ApplyRangePresentation", swingRange)
    end
    swingFill(f)
    return true
end

local swing = ns.Module("swing", "Swing timers", function(m)
    m.bars = {}
    ns.AfterBlizzard("Blizzard_SwingTimer", function()
        for _, name in ipairs(SWING) do
            local f = _G[name]
            if styleSwing(f) then
                table.insert(m.bars, f)
            end
        end
    end)
end)

function swing:Restyle()
    for _, f in ipairs(self.bars or {}) do
        swingFill(f)
    end
end

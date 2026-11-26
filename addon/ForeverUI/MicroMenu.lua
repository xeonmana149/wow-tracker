-- Forever UI - the micro menu and the bag bar.
--
-- These stay the game's own buttons (replacing them breaks the shop and
-- help buttons, and some panels won't open from an addon's click). We take
-- away their chunky frame art, put them on one dark strip with the gold
-- hairline, and keep them where you put them (/fui move), even after Edit
-- Mode or a vehicle moves them.

local _, ns = ...

local function hideArt(tex)
    if type(tex) == "table" and tex.SetAlpha then
        tex:SetAlpha(0)
    end
end

-- Fades a strip until the mouse is on it (Options: "Fade the micro menu").
local function fader(strip, frames, key, update)
    local function over()
        for _, f in ipairs(frames) do
            if f and f.IsMouseOver and f:IsShown() and f:IsMouseOver() then
                return true
            end
        end
        return false
    end
    local t = 0
    strip:SetScript("OnUpdate", function(self, elapsed)
        t = t + (elapsed or 0)
        if t < 0.15 then
            return
        end
        t = 0
        if update then update() end
        local a = 1
        if ns.Opt(key) and not over() then
            a = 0.3
        end
        for _, f in ipairs(frames) do
            if f and f.SetAlpha then
                f:SetAlpha(a)
            end
        end
    end)
end

----------------------------------------------------------------------
-- Micro menu
----------------------------------------------------------------------

local MENU = {
    { "Character", "character", { "CharacterMicroButton" } },
    { "Professions", "professions", { "ProfessionMicroButton" } },
    { "Spellbook", "spellbook", { "SpellbookMicroButton" } },
    { "Talents", "talents", { "TalentMicroButton" } },
    { "Legacy", "legacy", { "LegacyMicroButton" } },
    { "Quests", "quests", { "QuestLogMicroButton" } },
    { "Guild", "guild", { "GuildMicroButton" } },
    { "Dungeons", "dungeons", { "LFDMicroButton", "LFGMicroButton" } },
    { "Account collections", "collections", { "CollectionsMicroButton", "CollectionMicroButton", "AccountCollectionsMicroButton", "AccountMicroButton" } },
    { "Shop", "shop", { "StoreMicroButton", "ShopMicroButton" } },
    { "Friends", "friends", { "SocialsMicroButton", "QuickJoinToastButton" } },
    { "Bags", "bags-gold", { "MainMenuBarBackpackButton" } },
}

local LEGACY_TREES = { [1187] = true, [1188] = true, [1189] = true }
local function positive(value)
    return not ns.Secret(value) and type(value) == "number" and value > 0
end

-- Trait currencies are the points left to spend. Legacy uses separate trees;
-- never infer that a missing or restricted result means points are available.
local function unspentPoints()
    local talent, legacy = false, false
    if type(GetNumUnspentTalents) == "function" then
        local ok, n = pcall(GetNumUnspentTalents)
        if ok and positive(n) then talent = true end
    end
    local traits, class = C_Traits, C_ClassTalents
    if not (traits and type(traits.GetTreeCurrencyInfo) == "function") then return talent, legacy end
    local active
    if class and type(class.GetActiveConfigID) == "function" then
        local ok, id = pcall(class.GetActiveConfigID)
        if ok and not ns.Secret(id) and type(id) == "number" then active = id end
    end
    local function scan(config, tree, isLegacy)
        if not config then return end
        local ok, list = pcall(traits.GetTreeCurrencyInfo, config, tree, true)
        if not ok or ns.Secret(list) or type(list) ~= "table" then return end
        for _, currency in ipairs(list) do
            if not ns.Secret(currency) and type(currency) == "table" and positive(currency.quantity) then
                if isLegacy then legacy = true else talent = true end
            end
        end
    end
    if active and type(traits.GetConfigInfo) == "function" then
        local ok, info = pcall(traits.GetConfigInfo, active)
        local trees = ok and not ns.Secret(info) and type(info) == "table" and info.treeIDs
        if not ns.Secret(trees) and type(trees) == "table" then
            for _, tree in ipairs(trees) do
                if not ns.Secret(tree) and type(tree) == "number" and not LEGACY_TREES[tree] then scan(active, tree, false) end
            end
        end
    end
    for tree in pairs(LEGACY_TREES) do
        local config
        if type(traits.GetConfigIDByTreeID) == "function" then
            local ok, id = pcall(traits.GetConfigIDByTreeID, tree)
            if ok and not ns.Secret(id) and type(id) == "number" then config = id end
        end
        scan(config or active, tree, true)
    end
    return talent, legacy
end

-- Use the native button's enabled state rather than guessing level gates:
-- Forever can change these independently of the standard WoW client.
local function locked(target)
    if not target then return true end
    if type(target.IsEnabled) ~= "function" then return false end
    local ok, enabled = pcall(target.IsEnabled, target)
    if not ok or (ns.Secret and ns.Secret(enabled)) then return false end
    return enabled == false or enabled == 0
end

local function updateLock(button)
    -- The client disables many micro buttons temporarily while the game menu
    -- is open. That is not the same thing as a level or feature lock.
    if GameMenuFrame and GameMenuFrame.IsShown and GameMenuFrame:IsShown() then return end
    local isLocked = not (button.fuiGuildAction and type(ToggleGuildFrame) == "function") and locked(button.fuiTarget)
    if button.fuiLocked == isLocked then return end
    button.fuiLocked = isLocked
    button.fuiIcon:SetAlpha(isLocked and 0.35 or 1)
    local color = isLocked and ns.C.muted or ns.C.text
    button.fuiLabel:SetTextColor(color[1], color[2], color[3])
    if button.fuiLockText then
        local requirement = button.fuiTarget and button.fuiTarget.disabledTooltip
        if ns.Secret(requirement) or type(requirement) ~= "string" or requirement == "" then requirement = "Locked" end
        button.fuiLockText:SetText(requirement)
        button.fuiLockText:SetShown(isLocked)
    end
end

ns.Module("micro", "Micro menu", function(m)
    local container, menu = MicroMenuContainer, MicroMenu
    if not (container and menu) then
        error("no micro menu on this client")
    end
    -- the frame art around the row
    hideArt(menu.BorderArt)
    hideArt(menu.BackgroundArt)

    -- Keep the game's buttons alive as secure-click targets. The original
    -- row is visually hidden but not reparented or destroyed.
    container:SetAlpha(0)
    if container.EnableMouse then container:EnableMouse(false) end
    -- Mouse input is per frame: making the parent transparent or disabling
    -- its mouse does not stop its visible children from catching clicks.
    -- Keep the buttons shown for the secure click proxies below, but make
    -- the original hit targets click-through.
    ns.WhenSafe(function()
        if menu.EnableMouse then menu:EnableMouse(false) end
        for _, spec in ipairs(MENU) do
            if spec[2] ~= "bags-gold" then
                for _, name in ipairs(spec[3]) do
                    local native = _G[name]
                    if native and native.EnableMouse then native:EnableMouse(false) end
                end
            end
        end
        for _, name in ipairs({ "MainMenuMicroButton", "HelpMicroButton" }) do
            local native = _G[name]
            if native and native.EnableMouse then native:EnableMouse(false) end
        end
    end)

    local strip = CreateFrame("Frame", "ForeverUIMicroStrip", UIParent)
    -- Adopt the two-row arrangement once; subsequent layout edits are kept.
    if ns.Opt("microFit") and not ns.db.microFitPlacementV2 then
        ns.db.opts.microColumns = 5
        ns.db.pos.micro = nil
        ns.db.microFitPlacementV2 = true
    end
    -- Apply the requested one-row layout once, retaining any saved position.
    if not ns.db.microSingleRowV1 then
        local size = 36
        local action = _G.MultiBarBottomLeftButton1 or _G.ActionButton1
        if action and action.GetHeight and action.GetEffectiveScale and UIParent.GetEffectiveScale then
            local ok, h, scale, uiScale = pcall(function()
                return action:GetHeight(), action:GetEffectiveScale(), UIParent:GetEffectiveScale()
            end)
            if ok and type(h) == "number" and type(scale) == "number" and type(uiScale) == "number" and uiScale > 0 then
                size = math.max(30, math.min(70, h * scale / uiScale - 4))
            end
        end
        ns.db.opts.microColumns = #MENU
        ns.db.opts.microWidth = math.max(45, size)
        ns.db.opts.microHeight = size
        ns.db.opts.microScale = 1
        ns.db.opts.microFit = false
        ns.db.microSingleRowAutoFit = true
        ns.db.microSingleRowV1 = true
    end
    if not ns.db.microSingleRowV2 then
        ns.db.opts.microColumns = #MENU
        ns.db.microSingleRowV2 = true
    end
    if not ns.db.microTwoRowsV1 then
        ns.db.opts.microColumns = 6
        ns.db.opts.microFit = false
        ns.db.microTwoRowsV1 = true
    end
    if ns.db.microSingleRowAutoFit == nil then ns.db.microSingleRowAutoFit = true end
    local columns = math.max(1, math.min(#MENU, math.floor(tonumber(ns.Opt("microColumns")) or 2)))
    local width = math.max(45, math.min(150, tonumber(ns.Opt("microWidth")) or 97))
    local height = math.max(30, math.min(70, tonumber(ns.Opt("microHeight")) or 35))
    local gap = math.max(0, math.min(12, tonumber(ns.Opt("microGap")) or 2))
    local iconSize = math.max(18, math.min(48, tonumber(ns.Opt("microIcon")) or 31, height - 4, width - 4))
    strip:SetSize(4 + columns * width + (columns - 1) * gap, 4 + math.ceil(#MENU / columns) * height + (math.ceil(#MENU / columns) - 1) * gap)
    strip:SetScale(math.max(0.5, math.min(1.5, tonumber(ns.Opt("microScale")) or 1)))
    ns.Panel(strip, { noBg = true, edge = 0 })
    m.strip, m.buttons = strip, {}
    local labels = ns.Opt("microLabels")
    -- Apply the requested new placement once; later Edit Mode moves remain yours.
    if ns.Opt("microFit") and not ns.db.microFitPlacementV1 then
        ns.db.pos.micro = nil
        ns.db.microFitPlacementV1 = true
    end
    ns.Place(strip, "micro", "Micro menu", { "BOTTOMLEFT", "BOTTOMLEFT", 12, 16 }, nil,
        { scaleOption = "microScale", scaleMax = 1.5, onScale = function(scale) strip:SetScale(scale) end })
    for i, spec in ipairs(MENU) do
        -- The guild micro button uses an ordinary OnClick that calls
        -- ToggleGuildFrame. Invoke that same game action directly instead of
        -- relying on a forwarded synthetic click to a hidden button.
        local isGuild = spec[2] == "guild"
        local template = not isGuild and "SecureActionButtonTemplate" or nil
        local button = CreateFrame("Button", "ForeverUIMenu" .. i, strip, template)
        button:SetSize(width, height)
        button:SetPoint("TOPLEFT", strip, "TOPLEFT", 2 + ((i - 1) % columns) * (width + gap), -2 - math.floor((i - 1) / columns) * (height + gap))
        if isGuild then
            button:RegisterForClicks("LeftButtonUp")
        else
            button:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
            button:SetAttribute("useOnKeyDown", false)
        end
        local target
        for _, name in ipairs(spec[3]) do if _G[name] then target = _G[name]; break end end
        if isGuild then
            button.fuiGuildAction = true
            button:SetScript("OnClick", function()
                if type(ToggleGuildFrame) == "function" then ToggleGuildFrame() end
            end)
        elseif target then
            button:SetAttribute("type1", "click")
            button:SetAttribute("clickbutton", target)
        end
        ns.Panel(button, { alpha = 0.8, edge = 0.7 })
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(button)
        highlight:SetColorTexture(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3], 0.18)
        button.fuiHighlight = highlight
        local art = button:CreateTexture(nil, "ARTWORK")
        art:SetSize(iconSize, iconSize)
        if labels then art:SetPoint("LEFT", 4, 0)
        else art:SetPoint("CENTER", 0, 0) end
        local iconName = spec[2] == "bags-gold" and "bags" or spec[2]
        local iconFile = iconName == "spellbook" and "spellbook-neutral"
            or iconName == "friends" and "friends-horde" or iconName .. "-minimal"
        art:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\" .. iconFile)
        local text = ns.Text(button, 10, (target or (isGuild and type(ToggleGuildFrame) == "function")) and ns.C.text or ns.C.muted)
        text:SetPoint("LEFT", art, "RIGHT", 3, 0)
        text:SetText(spec[1])
        text:SetShown(labels)
        button.fuiIcon, button.fuiLabel, button.fuiTarget = art, text, target
        if spec[2] == "talents" or spec[2] == "legacy" then
            local pulse = CreateFrame("Frame", nil, button)
            pulse:SetAllPoints(button)
            if pulse.EnableMouse then pulse:EnableMouse(false) end
            if pulse.SetFrameLevel and button.GetFrameLevel then pulse:SetFrameLevel(button:GetFrameLevel() + 4) end
            local fill = pulse:CreateTexture(nil, "BACKGROUND")
            fill:SetPoint("TOPLEFT", 2, -2); fill:SetPoint("BOTTOMRIGHT", -2, 2)
            fill:SetColorTexture(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3], 0.12)
            pulse.fuiEdges = {}
            for i = 1, 4 do
                local edge = pulse:CreateTexture(nil, "OVERLAY")
                edge:SetColorTexture(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3], 1)
                if i == 1 then edge:SetPoint("TOPLEFT"); edge:SetPoint("TOPRIGHT"); edge:SetHeight(2)
                elseif i == 2 then edge:SetPoint("BOTTOMLEFT"); edge:SetPoint("BOTTOMRIGHT"); edge:SetHeight(2)
                elseif i == 3 then edge:SetPoint("TOPLEFT"); edge:SetPoint("BOTTOMLEFT"); edge:SetWidth(2)
                else edge:SetPoint("TOPRIGHT"); edge:SetPoint("BOTTOMRIGHT"); edge:SetWidth(2) end
                pulse.fuiEdges[i] = edge
            end
            pulse:Hide()
            button.fuiPointPulse = pulse
        end
        if spec[2] == "friends" then
            m.friends = button
        end
        local lockText = ns.Text(button, 8, { 0.9, 0.3, 0.25 })
        lockText:SetPoint("BOTTOM", button, "BOTTOM", 0, 4)
        if lockText.SetWidth then lockText:SetWidth(width - 6) end
        if lockText.SetWordWrap then lockText:SetWordWrap(false) end
        button.fuiLockText = lockText
        updateLock(button)
        button:SetScript("OnEnter", function(self)
            if GameTooltip then
                updateLock(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(spec[1], 1, 0.82, 0)
                if not target and not (isGuild and type(ToggleGuildFrame) == "function") then
                    GameTooltip:AddLine("Unavailable on this client", 0.7, 0.7, 0.7)
                elseif self.fuiLocked then
                    GameTooltip:AddLine("Locked or unavailable right now.", 0.7, 0.7, 0.7)
                    GameTooltip:AddLine("Unlock requirements are set by the game.", 0.7, 0.7, 0.7)
                end
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        table.insert(m.buttons, button)
    end
    function m:FitSingleRow()
        if not ns.db.microSingleRowAutoFit or ns.Opt("microFit")
            or ns.moving or (InCombatLockdown and InCombatLockdown()) or not ns.ActionBarBounds then return end
        local actionLeft, _, actionTop, actionBottom = ns.ActionBarBounds()
        local left, bottom = strip:GetLeft(), strip:GetBottom()
        local uiScale = UIParent:GetEffectiveScale()
        local scale = strip:GetEffectiveScale()
        if type(actionLeft) ~= "number" or type(left) ~= "number" or type(uiScale) ~= "number"
            or uiScale <= 0 or type(scale) ~= "number" or scale <= 0 then return end
        scale = scale / uiScale
        local action = _G.MultiBarBottomLeftButton1 or _G.ActionButton1
        if not (action and action.GetWidth and action.GetHeight and action.GetEffectiveScale) then return end
        local ok, actionW, actionH, actionScale = pcall(function()
            return action:GetWidth(), action:GetHeight(), action:GetEffectiveScale()
        end)
        if not ok or type(actionW) ~= "number" or type(actionH) ~= "number"
            or type(actionScale) ~= "number" or actionW <= 0 or actionH <= 0 or actionScale <= 0 then return end
        local cellW, cellH = actionW * actionScale / uiScale / scale, actionH * actionScale / uiScale / scale
        local rows = math.ceil(#MENU / columns)
        local menuW, menuH = 4 + columns * cellW + (columns - 1) * gap, 4 + rows * cellH + (rows - 1) * gap
        if not self.rowWidth or math.abs(self.rowWidth - cellW) >= 0.1
            or not self.rowHeight or math.abs(self.rowHeight - cellH) >= 0.1 then
        strip:SetSize(menuW, menuH)
        for i, button in ipairs(self.buttons) do
            button:SetSize(cellW, cellH)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", strip, "TOPLEFT", 2 + ((i - 1) % columns) * (cellW + gap),
                -2 - math.floor((i - 1) / columns) * (cellH + gap))
            if button.fuiLockText then button.fuiLockText:SetWidth(math.max(1, cellW - 6)) end
            local artSize = math.max(8, math.min(iconSize, cellW - 6, cellH - 4))
            button.fuiIcon:SetSize(artSize, artSize)
        end
        self.rowWidth, self.rowHeight = cellW, cellH
        end
        -- Only adjust the default placement. A position saved in Edit Mode
        -- is intentional and must not be overridden by collision avoidance.
        if not ns.db.pos.micro and type(bottom) == "number" and type(actionTop) == "number" and type(actionBottom) == "number"
            and left * scale + menuW * scale + 6 > actionLeft
            and bottom * scale < actionTop and (bottom + menuH) * scale > actionBottom then
            local top = actionTop
            local xp = ns.modules.xpbar and ns.modules.xpbar.holder
            if xp and xp.IsShown and xp:IsShown() then
                local xpTop, xpScale = xp:GetTop(), xp:GetEffectiveScale()
                if type(xpTop) == "number" and type(xpScale) == "number" then top = math.max(top, xpTop * xpScale / uiScale) end
            end
            strip:ClearAllPoints()
            strip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", math.max(0, left), (top + 6) / scale)
        end
    end
    function m:FitBesideXP()
        if not ns.Opt("microFit") or ns.moving or (InCombatLockdown and InCombatLockdown()) then return end
        local xp = ns.modules.xpbar and ns.modules.xpbar.holder
        if not (xp and xp.IsShown and xp:IsShown()) then return end
        local ok, left, top, scale = pcall(function()
            return xp:GetLeft(), xp:GetTop(), xp:GetEffectiveScale() / UIParent:GetEffectiveScale()
        end)
        if not ok or type(left) ~= "number" or type(top) ~= "number" or type(scale) ~= "number" or scale <= 0 then return end
        local stripScale = strip:GetEffectiveScale() / UIParent:GetEffectiveScale()
        if type(stripScale) ~= "number" or stripScale <= 0 then return end
        local _, _, _, actionBottom
        if ns.ActionBarBounds then _, _, _, actionBottom = ns.ActionBarBounds() end
        if type(actionBottom) ~= "number" then return end
        local bottom = math.max(0, actionBottom)
        local availableW, availableH = left * scale - 22, top * scale - bottom
        local rows = math.ceil(#MENU / columns)
        local side = math.min((availableW / stripScale - 4 - (columns - 1) * gap) / columns,
            (availableH / stripScale - 4 - (rows - 1) * gap) / rows)
        if side < 20 then return end
        local cellW, cellH = side, side
        local menuW = 4 + columns * side + (columns - 1) * gap
        local menuH = 4 + rows * side + (rows - 1) * gap
        if not self.fitW or math.abs(self.fitW - cellW) > 0.5 or math.abs(self.fitH - cellH) > 0.5 then
            strip:SetSize(menuW, menuH)
            for i, button in ipairs(self.buttons) do
                button:SetSize(cellW, cellH)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", strip, "TOPLEFT", 2 + ((i - 1) % columns) * (cellW + gap),
                    -2 - math.floor((i - 1) / columns) * (cellH + gap))
                if button.fuiLockText then button.fuiLockText:SetWidth(cellW - 6) end
                local artSize = math.max(12, math.min(cellH * 0.7, cellW - 10,
                    labels and cellW * 0.4 or cellW))
                button.fuiIcon:SetSize(artSize, artSize)
            end
            self.fitW, self.fitH = cellW, cellH
        end
        if not ns.db.pos.micro then
            local x = 12 + (availableW - menuW * stripScale) / 2
            if not self.fitX or math.abs(self.fitX - x) > 0.5 or math.abs(self.fitY - bottom) > 0.5 then
                strip:ClearAllPoints()
                strip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / stripScale, bottom / stripScale)
                self.fitX, self.fitY = x, bottom
            end
        elseif ns.db.pos.micro then
            self.fitX, self.fitY = nil, nil
        end
    end
    -- The game anchors this reminder to its hidden native micro button.
    -- Anchor it to our visible Talents button instead, without changing the
    -- game-owned alert while protected layout changes are blocked in combat.
    function m:AlignTalentAlert()
        if InCombatLockdown and InCombatLockdown() then return end
        local button = self.buttons and self.buttons[4]
        if not button then return end
        -- Newer clients use pooled HelpTips instead of TalentMicroButtonAlert.
        -- Only re-anchor the tip frame. Writing its fields (relativeRegion,
        -- info...) or calling its layout methods from here would taint the
        -- shared HelpTip pool. The game menu reads that pool when it opens, so
        -- its buttons, then Edit Mode and the party frames, would run tainted
        -- and break on secret values.
        if HelpTip and HelpTip.framePool and HelpTip.framePool.EnumerateActive then
            for tip in HelpTip.framePool:EnumerateActive() do
                local info = tip.info
                if info and info.system == "MicroButtons" and tip.relativeRegion == TalentMicroButton
                    and tip.ClearAllPoints and tip.SetPoint and not (tip.IsForbidden and tip:IsForbidden()) then
                    local point, relative = tip:GetPoint()
                    if not (point == "BOTTOM" and relative == button) then
                        tip:ClearAllPoints()
                        tip:SetPoint("BOTTOM", button, "TOP", 0, 10)
                    end
                end
            end
        end
        local alert = _G.TalentMicroButtonAlert or (TalentMicroButton and TalentMicroButton.Alert)
        if not ((type(alert) == "table" or type(alert) == "userdata") and button
            and alert.GetPoint and alert.ClearAllPoints and alert.SetPoint) then return end
        if alert.IsForbidden and alert:IsForbidden() then return end
        local point, relative, relativePoint = alert:GetPoint()
        if point == "BOTTOM" and relative == button and relativePoint == "TOP" then return end
        alert:ClearAllPoints()
        alert:SetPoint("BOTTOM", button, "TOP", 0, 10)
    end
    function m:UpdatePointAlerts()
        local talent, legacy = unspentPoints()
        self.talentPointsAvailable, self.legacyPointsAvailable = talent, legacy
    end
    m:UpdatePointAlerts()
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_TALENT_UPDATE",
        "CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED" }) do
        ns.OnOptional(event, function() m:UpdatePointAlerts() end)
    end
    fader(strip, { strip }, "microFade", function()
        for _, button in ipairs(m.buttons) do updateLock(button) end
        m.pointPoll = (m.pointPoll or 0) + 0.15
        if m.pointPoll >= 2 then m.pointPoll = 0; m:UpdatePointAlerts() end
        local now = type(GetTime) == "function" and GetTime() or 0
        if ns.Secret(now) or type(now) ~= "number" then now = 0 end
        for _, item in ipairs({ { m.buttons[4], m.talentPointsAvailable }, { m.buttons[5], m.legacyPointsAvailable } }) do
            local button, active = item[1], item[2]
            if button and button.fuiPointPulse then
                button.fuiPointPulse:SetShown(active and not button.fuiLocked)
                button.fuiPointPulse:SetAlpha(0.45 + 0.45 * (0.5 + 0.5 * math.sin(now * 4)))
            end
        end
        m:FitSingleRow()
        m:FitBesideXP()
        m:AlignTalentAlert()
    end)
    m:AlignTalentAlert()
end)

----------------------------------------------------------------------
-- Bag bar
----------------------------------------------------------------------

local BAG_BUTTONS = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
    "CharacterBag3Slot", "CharacterReagentBag0Slot" }

local function styleBag(b, backpack)
    if not b or b.fuiStyled then
        return
    end
    b.fuiStyled = true
    hideArt(b.GetNormalTexture and b:GetNormalTexture())
    hideArt(b.NormalTexture)
    hideArt(b.SlotHighlightTexture)
    hideArt(b.CircleMask)
    local icon = b.icon or b.Icon or (b:GetName() and _G[b:GetName() .. "IconTexture"])
    if icon then
        if icon.SetTexCoord then
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        -- round masks from the game's bag art: off, so the icon is square like the strip
        if icon.GetNumMaskTextures and icon.RemoveMaskTexture and icon.GetMaskTexture then
            local n = icon:GetNumMaskTextures()
            for i = type(n) == "number" and n or 0, 1, -1 do
                local mask = icon:GetMaskTexture(i)
                if mask then
                    icon:RemoveMaskTexture(mask)
                end
            end
        end
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    end
    -- the hairline in front of the icon; the backpack in bright gold
    local edge = CreateFrame("Frame", nil, b)
    edge:SetAllPoints()
    edge:SetFrameLevel((b:GetFrameLevel() or 1) + 2)
    ns.Panel(edge, { noBg = true, bright = backpack })
    b.fuiEdge = edge
end

ns.Module("bags", "Bag bar", function(m)
    local bar = BagsBar
    if not bar then
        error("no bag bar on this client")
    end
    if ns.Opt("hideBagBar") then
        ns.Stash(bar)
        ns.WhenSafe(function()
            for _, name in ipairs(BAG_BUTTONS) do
                local button = _G[name]
                if button and button.EnableMouse then button:EnableMouse(false) end
            end
        end)
        return
    end
    for i, name in ipairs(BAG_BUTTONS) do
        styleBag(_G[name], i == 1)
    end
    ns.Place(bar, "bags", "Bag bar", { "BOTTOMRIGHT", "BOTTOMRIGHT", -24, 64 }, true)
    fader(CreateFrame("Frame", nil, bar), { bar }, "microFade")
end)

-- Forever UI - the minimap.
--
-- Square, with the gold hairline, the zone above it, coordinates and the
-- clock along the bottom, a mail icon when you have some, and every addon's
-- minimap button gathered into one drawer (the "+N" corner button) instead
-- of ringing the map. The game's own minimap frame and its art go.

local _, ns = ...
local floor = math.floor

-- Children of the minimap that are the game's, never gathered into the drawer.
local GAME_PARTS = { "Minimap", "MiniMap", "GameTime", "ExpansionLanding", "QueueStatus", "ForeverUI", "TimeManager" }

local function isGamePart(name)
    for _, p in ipairs(GAME_PARTS) do
        if name:sub(1, #p) == p then
            return true
        end
    end
    return false
end

local function cornerButton(parent, w)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 22, 22)
    b:SetFrameLevel((parent:GetFrameLevel() or 1) + 6)
    ns.Panel(b)
    return b
end

local m = ns.Module("minimap", "Minimap", function(m)
    local map = Minimap
    if not map then
        error("no minimap")
    end
    local size = tonumber(ns.Opt("mapSize")) or 200

    local holder = CreateFrame("Frame", "ForeverUIMinimap", UIParent)
    holder:SetSize(size, size)
    holder:SetFrameStrata("LOW")
    ns.Panel(holder)
    m.holder = holder

    -- the minimap itself moves into our frame, square
    map:SetParent(holder)
    map:SetScale(1)
    map:SetFrameLevel((holder:GetFrameLevel() or 1) + 1)
    ns.Keep(map, function(f)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", holder, "TOPLEFT", 1, -1)
        f:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -1, 1)
    end)
    map:SetSize(size - 2, size - 2)
    local function square()
        map:SetMaskTexture("Interface\\Buttons\\WHITE8X8")
        -- The game's round quest/archaeology ring can show as a white
        -- checkerboard over a square minimap. Hide only the ring, leaving the
        -- actual quest-area fill and markers controlled by the game.
        for _, method in ipairs({ "SetQuestBlobRingAlpha", "SetQuestBlobRingScalar", "SetArchBlobRingAlpha", "SetArchBlobRingScalar" }) do
            if type(map[method]) == "function" then pcall(map[method], map, 0) end
        end
    end
    square()
    -- the game puts its round mask back when the rotate setting changes
    if MinimapCluster and MinimapCluster.UpdateMinimapConfig then
        hooksecurefunc(MinimapCluster, "UpdateMinimapConfig", square)
    end
    -- other addons ask this to place their buttons
    function GetMinimapShape()
        return "SQUARE"
    end

    -- the game's frame, ring art, zone bar, clock and buttons go
    ns.Stash(MinimapCluster)
    ns.Stash(MinimapBackdrop)
    for _, tex in ipairs({ MinimapCompassTexture, MinimapCompassTextureUnderlay }) do
        if tex and tex.SetAlpha then
            tex:SetAlpha(0)
        end
    end

    -- scroll to zoom
    map:EnableMouseWheel(true)
    map:SetScript("OnMouseWheel", function(self, delta)
        local z, top = self:GetZoom() or 0, (self:GetZoomLevels() or 5) - 1
        if delta > 0 then
            self:SetZoom(math.min(top, z + 1))
        else
            self:SetZoom(math.max(0, z - 1))
        end
    end)

    -- zone name, above
    local zone = ns.Text(holder, 13, ns.C.bright)
    zone:SetPoint("BOTTOM", holder, "TOP", 0, 5)
    m.zone = zone

    -- Coordinates and clock sit below the map instead of covering it.
    local strip = CreateFrame("Button", nil, holder)
    strip:SetFrameLevel((map:GetFrameLevel() or 1) + 5)
    strip:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -2)
    strip:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, -2)
    strip:SetHeight(20)
    ns.Panel(strip, { alpha = 0.9, edge = 0.7 })
    m.coords = ns.Text(strip, 10)
    m.coords:SetPoint("LEFT", 8, 0)
    m.clock = ns.Text(strip, 10)
    m.clock:SetPoint("RIGHT", -8, 0)
    -- Reserve independent space between the coordinates and the clock so
    -- longer coordinates cannot overlap frame rate or latency.
    m.stats = ns.Text(strip, 9, ns.C.muted)
    m.stats:SetPoint("LEFT", m.coords, "RIGHT", 5, 0)
    m.stats:SetPoint("RIGHT", m.clock, "LEFT", -5, 0)
    if m.stats.SetJustifyH then m.stats:SetJustifyH("RIGHT") end
    if m.stats.SetWordWrap then m.stats:SetWordWrap(false) end
    strip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Forever UI")
        local fps = GetFramerate and GetFramerate() or 0
        local _, _, home, world = 0, 0, 0, 0
        if GetNetStats then
            _, _, home, world = GetNetStats()
        end
        GameTooltip:AddDoubleLine("Frame rate", string.format("%d fps", fps), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Latency (home)", string.format("%d ms", home or 0), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Latency (world)", string.format("%d ms", world or 0), 1, 1, 1, 1, 1, 1)
        GameTooltip:Show()
    end)
    strip:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    m.strip = strip

    -- Four equal cells span the information strip, including the tracker
    -- button, which can be created after this module starts.
    local gap = 4
    local cellWidth = math.max(1, (size - gap * 3) / 4)
    local row = CreateFrame("Frame", nil, holder)
    row:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -4)
    row:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 0, -4)
    row:SetHeight(22)
    m.buttonRow = row

    -- mail
    local mail = cornerButton(holder)
    mail:SetPoint("TOPRIGHT", holder, "TOPLEFT", -4, -28)
    mail.glow = mail:CreateTexture(nil, "ARTWORK")
    mail.glow:SetPoint("TOPLEFT", 2, -2); mail.glow:SetPoint("BOTTOMRIGHT", -2, 2)
    mail.glow:SetColorTexture(1, 0.68, 0.2, 1); mail.glow:SetAlpha(0.12)
    mail.icon = mail:CreateTexture(nil, "OVERLAY")
    mail.icon:SetPoint("TOPLEFT", 3, -3)
    mail.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    mail.icon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\mail-inbox.tga")
    mail:SetScript("OnUpdate", function(self, elapsed)
        self.pulse = ((self.pulse or 0) + (elapsed or 0)) % 3
        self.glow:SetAlpha(0.12 + 0.10 * (0.5 - 0.5 * math.cos(self.pulse * 2 * math.pi / 3)))
    end)
    mail:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("You have mail", 1, 0.82, 0)
        local senders = { GetLatestThreeSenders and GetLatestThreeSenders() }
        for _, s in ipairs(senders) do
            GameTooltip:AddLine(s, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    mail:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    m.mail = mail

    -- A separate calendar shortcut, aligned with the right edge below the map.
    local calendar = cornerButton(holder, cellWidth)
    calendar:SetPoint("TOPLEFT", row, "TOPLEFT", 3 * (cellWidth + gap), 0)
    calendar.icon = calendar:CreateTexture(nil, "ARTWORK")
    calendar.icon:SetSize(18, 18)
    calendar.icon:SetPoint("CENTER")
    calendar.icon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\calendar.tga")
    calendar:SetScript("OnClick", function()
        if ToggleCalendar then pcall(ToggleCalendar) end
    end)
    calendar:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Calendar", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    calendar:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    m.calendar = calendar

    -- The addon drawer starts the row, followed by the encyclopedia.
    local settings = cornerButton(holder, cellWidth)
    settings:SetPoint("TOPLEFT", row, "TOPLEFT", cellWidth + gap, 0)
    settings.icon = settings:CreateTexture(nil, "ARTWORK")
    settings.icon:SetSize(18, 18)
    settings.icon:SetPoint("CENTER")
    settings.icon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\encyclopedia.tga")
    settings:SetScript("OnClick", function() if ns.OpenEncyclopedia then ns.OpenEncyclopedia() end end)
    settings:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Forever Encyclopedia", 1, 0.82, 0)
        GameTooltip:AddLine("Browse the encyclopedia and open Forever UI settings.", 1, 1, 1)
        GameTooltip:Show()
    end)
    settings:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    m.settings = settings

    -- the drawer of addon buttons
    local open = cornerButton(holder, cellWidth)
    open:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    -- Leave room for the addon count beside the themed icon.
    open.icon = open:CreateTexture(nil, "ARTWORK")
    open.icon:SetSize(14, 14)
    open.icon:SetPoint("LEFT", open, "LEFT", 3, 0)
    open.icon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\addons.tga")
    open.text = ns.Text(open, 9, ns.C.bright)
    open.text:SetPoint("RIGHT", -3, 0)
    local openHover = open:CreateTexture(nil, "HIGHLIGHT")
    openHover:SetPoint("TOPLEFT", 1, -1)
    openHover:SetPoint("BOTTOMRIGHT", -1, 1)
    openHover:SetColorTexture(1, 0.85, 0.48, 0.12)
    local drawer = CreateFrame("Frame", "ForeverUIMinimapDrawer", holder)
    drawer:SetFrameStrata("MEDIUM")
    drawer:SetPoint("TOPRIGHT", open, "TOPLEFT", -4, 0)
    ns.Panel(drawer, { alpha = 1.1, edge = 0.8 })
    drawer:Hide()
    open:SetScript("OnClick", function()
        m:Gather()
        drawer:SetShown(not drawer:IsShown())
        ns.PaintPanel(open)
    end)
    open:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Addon buttons", 1, 0.82, 0)
        GameTooltip:AddLine("Every addon's minimap button, kept in here.", 1, 1, 1)
        GameTooltip:Show()
    end)
    open:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    m.open, m.drawer, m.gathered = open, drawer, {}

    -- A second aligned row can hold more shortcuts as they are added.
    local extraRow = CreateFrame("Frame", nil, holder)
    extraRow:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -4)
    extraRow:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", 0, -4)
    extraRow:SetHeight(22)
    m.extraButtonRow = extraRow
    local gold = cornerButton(holder, cellWidth)
    gold:SetPoint("TOPLEFT", extraRow, "TOPLEFT", 0, 0)
    gold.icon = gold:CreateTexture(nil, "ARTWORK")
    gold.icon:SetSize(18, 18)
    gold.icon:SetPoint("CENTER")
    gold.icon:SetTexture("Interface\\AddOns\\ForeverGold\\Art\\gold-logo.tga")
    gold:SetScript("OnClick", function()
        if _G.ForeverGold and _G.ForeverGold.ToggleUI then _G.ForeverGold.ToggleUI() end
    end)
    gold:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Forever Gold", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    gold:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    m.gold = gold

    -- The instance guide sits alongside Forever Gold on the second row.
    local guide = cornerButton(holder, cellWidth)
    guide:SetPoint("TOPLEFT", extraRow, "TOPLEFT", cellWidth + gap, 0)
    guide.icon = guide:CreateTexture(nil, "ARTWORK")
    guide.icon:SetSize(18, 18)
    guide.icon:SetPoint("CENTER")
    guide.icon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\instance-guide.tga")
    local guideHover = guide:CreateTexture(nil, "HIGHLIGHT")
    guideHover:SetPoint("TOPLEFT", 1, -1); guideHover:SetPoint("BOTTOMRIGHT", -1, 1)
    guideHover:SetColorTexture(1, 0.85, 0.48, 0.12)
    guide:SetScript("OnClick", function() if ns.InstanceGuide then ns.InstanceGuide:Toggle() end end)
    guide:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Instance Guide", 1, 0.82, 0)
        GameTooltip:AddLine("Browse dungeon and raid bosses, loot and quests.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    guide:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    m.instanceGuide = guide

    local function alignSync()
        local sync = _G.WFTSyncButton
        if type(sync) ~= "table" or not sync.SetPoint then return end
        ns.WhenSafe(function()
            sync:ClearAllPoints()
            sync:SetSize(cellWidth, 22)
            sync:SetPoint("TOPLEFT", row, "TOPLEFT", 2 * (cellWidth + gap), 0)
            sync.fuiCompact = true
            if sync.icon and sync.label then
                sync.icon:ClearAllPoints()
                sync.icon:SetSize(12, 12)
                sync.icon:SetPoint("LEFT", 4, 0)
                sync.label:ClearAllPoints()
                sync.label:SetPoint("LEFT", sync.icon, "RIGHT", 1, 0)
                sync.label:SetPoint("RIGHT", sync, "RIGHT", -2, 0)
                sync.label:SetShown(cellWidth >= 35)
            end
            if sync.fuiRefresh then sync.fuiRefresh() end
        end)
    end
    m.AlignSync = alignSync
    ns.On("ADDON_LOADED", function(_, name)
        if name == "WoWForeverTracker" and C_Timer then C_Timer.After(0, alignSync) end
    end)

    ns.Place(holder, "minimap", "Minimap", { "TOPRIGHT", "TOPRIGHT", -24, -36 })

    for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
        ns.On(e, function() m:Zone() end)
    end
    ns.On("UPDATE_PENDING_MAIL", function() m:Mail() end)
    ns.On("PLAYER_ENTERING_WORLD", function()
        m:Mail()
        m:Gather()
        alignSync()
        -- addons that make their buttons late
        if C_Timer then
            C_Timer.After(3, function() m:Gather() end)
        end
    end)
    local t = 0
    holder:SetScript("OnUpdate", function(_, elapsed)
        t = t + (elapsed or 0)
        if t >= 0.2 then
            t = 0
            m:Tick()
        end
    end)
    m:Zone()
    m:Mail()
    m:Tick()
    m:Gather()
end)

function m:Zone()
    local text = GetMinimapZoneText and GetMinimapZoneText() or ""
    self.zone:SetText(text)
end

function m:Mail()
    local hasMail = HasNewMail and HasNewMail() and true or false
    self.mail:SetShown(hasMail)
    if not hasMail then self.mail.pulse = 0; self.mail.glow:SetAlpha(0.12) end
end

function m:Tick()
    local x, y
    if C_Map and C_Map.GetBestMapForUnit then
        local id = C_Map.GetBestMapForUnit("player")
        local pos = id and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(id, "player")
        if pos then
            x, y = pos.x, pos.y
            if type(x) ~= "number" and pos.GetXY then
                x, y = pos:GetXY()
            end
        end
    end
    if x and y and (x > 0 or y > 0) then
        self.coords:SetText(string.format("%.1f, %.1f", x * 100, y * 100))
    else
        self.coords:SetText("")
    end
    self.clock:SetText(date("%H:%M"))
    self.statsWait = (self.statsWait or 0) - 1
    if self.statsWait <= 0 then
        self.statsWait = 5 -- once a second
        self:Stats()
    end
end

-- "60 fps  42 ms": the latency green, yellow past 150 ms, red past 300.
local function msColor(ms)
    if ms >= 300 then
        return "ffd8503c"
    elseif ms >= 150 then
        return "ffe3c06a"
    end
    return "ff8fc070"
end

function m:Stats()
    if not self.stats then
        return
    end
    local fps = GetFramerate and GetFramerate() or 0
    local ms = 0
    if GetNetStats then
        local _, _, home, world = GetNetStats()
        ms = math.max(home or 0, world or 0)
    end
    self.stats:SetText(string.format("%d fps  |c%s%d ms|r", fps, msColor(ms), ms))
end

-- Collect the addon's buttons in rows of ten, starting next to the opener
-- and growing left. Each additional row grows downward.
function m:Gather()
    local found = self.gathered
    local seen = {}
    for _, b in ipairs(found) do
        seen[b] = true
    end
    -- Buttons elsewhere that hang off the minimap (OneForAll's badge sits on
    -- the screen, anchored under the map) count too.
    local function onMap(c)
        if not c.GetPoint then
            return false
        end
        local name = c.GetName and c:GetName()
        if type(name) == "string" and name:find("^OneForAll") then
            return true
        end
        local _, rel = c:GetPoint(1)
        return rel ~= nil and (rel == Minimap or rel == MinimapCluster or rel == self.holder)
    end
    -- Minimap containers sometimes include invisible placeholder Buttons.
    -- Only discard a button when all its click scripts and secure actions can
    -- be inspected and are absent; retain unknown or restricted buttons.
    local function inert(c)
        if type(c.GetScript) ~= "function" or type(c.GetAttribute) ~= "function" then return false end
        for _, event in ipairs({ "OnClick", "OnMouseDown", "OnMouseUp", "OnReceiveDrag" }) do
            local ok, fn = pcall(c.GetScript, c, event)
            if not ok or ns.Secret(fn) then return false end
            if fn ~= nil then return false end
        end
        for _, key in ipairs({ "type", "type1", "type2", "*type1", "*type2" }) do
            local ok, value = pcall(c.GetAttribute, c, key)
            if not ok or ns.Secret(value) then return false end
            if value ~= nil then return false end
        end
        return true
    end
    for _, parent in ipairs({ Minimap, MinimapBackdrop, UIParent }) do
        if parent and parent.GetChildren then
            for _, c in ipairs({ parent:GetChildren() }) do
                -- Some children are forbidden secure frames; even querying a
                -- method can fail. One inaccessible button must not abort setup.
                pcall(function()
                    if seen[c] or (c.IsForbidden and c:IsForbidden()) or inert(c) then return end
                    if type(c.IsShown) == "function" then
                        local visible = c:IsShown()
                        if not ns.Secret(visible) and visible == false then return end
                    end
                    if type(c.GetAlpha) == "function" then
                        local alpha = c:GetAlpha()
                        if not ns.Secret(alpha) and type(alpha) == "number" and alpha <= 0 then return end
                    end
                    local name = c.GetName and c:GetName()
                    local w = c.GetWidth and c:GetWidth() or 0
                    if not (type(name) == "string" and not isGamePart(name)
                        and c.IsObjectType and c:IsObjectType("Button") and w >= 16 and w <= 48
                        and (parent ~= UIParent or onMap(c))) then return end
                    c:SetParent(self.drawer)
                    -- no dragging around a map edge that isn't there
                    if c.RegisterForDrag then
                        c:RegisterForDrag()
                    end
                    local i = #found + 1
                    local cell = CreateFrame("Frame", nil, self.drawer)
                    cell:SetSize(34, 34)
                    cell:SetPoint("TOPRIGHT", self.drawer, "TOPRIGHT", -6 - ((i - 1) % 10) * 36,
                        -6 - floor((i - 1) / 10) * 36)
                    ns.Panel(cell, { alpha = 0.8, edge = 0.55 })
                    if cell.EnableMouse then cell:EnableMouse(false) end
                    if c.SetFrameLevel and cell.GetFrameLevel then c:SetFrameLevel(cell:GetFrameLevel() + 1) end
                    c.fuiDrawerCell = cell
                    -- LibDBIcon supplies a decorative round tracking border;
                    -- keep the addon's own icon and click behavior intact.
                    if c.icon and c.border and c.border.SetAlpha then c.border:SetAlpha(0) end
                    if c.CreateTexture then
                        local highlight = c:CreateTexture(nil, "HIGHLIGHT")
                        highlight:SetAllPoints(c)
                        highlight:SetColorTexture(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3], 0.14)
                        c.fuiDrawerHighlight = highlight
                    end
                    ns.Keep(c, function(f)
                        f:ClearAllPoints()
                        f:SetPoint("CENTER", cell, "CENTER", 0, 0)
                    end)
                    seen[c] = true
                    table.insert(found, c)
                end)
            end
        end
    end
    -- Other addons can hide or take back a button after we collect it. Do not
    -- leave its empty cell behind, and compact the remaining buttons in place.
    local n = 0
    for _, button in ipairs(found) do
        local cell = button.fuiDrawerCell
        local ok, available = pcall(function()
            if button.IsForbidden and button:IsForbidden() then return false end
            if button.GetParent and button:GetParent() ~= self.drawer then return false end
            if button.IsShown and not button:IsShown() then return false end
            local alpha = button.GetAlpha and button:GetAlpha()
            if alpha ~= nil and not ns.Secret(alpha) and type(alpha) == "number" and alpha <= 0 then return false end
            return true
        end)
        if cell then
            if ok and available then
                n = n + 1
                cell:ClearAllPoints()
                cell:SetPoint("TOPRIGHT", self.drawer, "TOPRIGHT", -6 - ((n - 1) % 10) * 36,
                    -6 - floor((n - 1) / 10) * 36)
                cell:Show()
            else
                cell:Hide()
            end
        end
    end
    local columns = math.max(1, math.min(10, n))
    local rows = math.max(1, math.ceil(n / 10))
    self.drawer:SetSize(10 + columns * 36, 10 + rows * 36)
    self.open.text:SetText("+" .. n)
    self.open:SetShown(n > 0)
    if self.open.fuiPanel then
        self.open.fuiPanel.bright = self.drawer:IsShown()
    end
end

function m:Restyle()
    if self.strip then
        ns.PaintPanel(self.strip)
    end
end

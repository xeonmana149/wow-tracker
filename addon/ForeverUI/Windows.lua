-- Forever UI - the game's windows.
--
-- Character, professions, spellbook and talents, legacy, quest log, guild,
-- group finder, collections, the shop and the rest are mostly built from
-- the same few parts: a frame border (NineSlice), a portrait, a rock or
-- marble backdrop, insets, tabs, a red close button, panel buttons,
-- dropdowns and scroll bars. This skins those parts: the dark panel with
-- the gold hairline, flat tabs, a plain close cross. Each window's own art
-- (the character model's backdrop, the talent tree) comes later, window by
-- window.
--
-- Only how things look changes: nothing is moved, resized or shown, so a
-- window the game protects in combat still opens as it always did.

local _, ns = ...

local done = setmetatable({}, { __mode = "k" })

-- a part, if it is one (a frame's key could be anything)
local function T(x)
    return type(x) == "table" and x or nil
end

local function fade(region)
    if type(region) == "table" and region.SetAlpha then
        region:SetAlpha(0)
    end
end

local function fadeAll(list)
    for _, r in ipairs(type(list) == "table" and list or {}) do
        fade(r)
    end
end

-- Only remove textures belonging directly to known character-page frames;
-- equipment buttons, character model and addon-drawn panels stay intact.
local function fadeNativeTextures(frame)
    if type(frame) ~= "table" or type(frame.GetRegions) ~= "function" then return end
    local p = frame.fuiPanel
    for _, region in ipairs({ frame:GetRegions() }) do
        local own = region == frame.fuiCharacterIcon or region == frame.fuiTop or region == frame.fuiRule or region == frame.fuiPvpDivider
            or region == frame.fuiFlatBackground
        if p then
            own = own or region == p.bg
            for _, line in ipairs(p.lines or {}) do if region == line then own = true end end
        end
        if not own and region.IsObjectType then
            local ok, isTexture = pcall(region.IsObjectType, region, "Texture")
            if ok and isTexture then fade(region) end
        end
    end
end

-- texture or frame: a texture is taken away, a frame faded
local function clear(x)
    if type(x) ~= "table" then
        return
    end
    if x.SetTexture then
        ns.Bin(x)
    else
        fade(x)
    end
end

----------------------------------------------------------------------
-- Parts
----------------------------------------------------------------------

local function hover(b, inset)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", inset or 1, -(inset or 1))
    hl:SetPoint("BOTTOMRIGHT", -(inset or 1), inset or 1)
    hl:SetColorTexture(1, 0.94, 0.78, 0.08)
    return hl
end

-- Keep the game's red-and-gold close art and the existing click handler.
local function skinClose(b)
    if type(b) ~= "table" or done[b] then
        return
    end
    done[b] = true
    for _, state in ipairs({ { "SetNormalAtlas", "RedButton-Exit" }, { "SetPushedAtlas", "RedButton-exit-pressed" },
        { "SetDisabledAtlas", "RedButton-Exit-Disabled" }, { "SetHighlightAtlas", "RedButton-Highlight" } }) do
        if type(b[state[1]]) == "function" then pcall(b[state[1]], b, state[2]) end
    end
end

-- A tab: flat, dark, the hairline; the open one gets the bright edge and
-- a gold line along its top.
local TAB_ART = { "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive", "LeftHighlight",
    "MiddleHighlight", "RightHighlight", "LeftDisabled", "MiddleDisabled", "RightDisabled" }

local function tabState(tab)
    local p = tab.fuiPanel
    if not p then
        return
    end
    local active = T(tab.LeftActive)
    local open = active and active.IsShown and active:IsShown() or tab.isSelected
    p.bright = open and true or false
    ns.PaintPanel(tab)
    if tab.fuiTop then
        tab.fuiTop:SetShown(p.bright)
    end
end

local function skinTab(tab)
    if type(tab) ~= "table" or done[tab] or not tab.CreateTexture then
        return
    end
    done[tab] = true
    for _, k in ipairs(TAB_ART) do
        fade(tab[k])
    end
    fadeAll(tab.TabTextures)
    fadeAll(tab.RotatedTextures)
    fade(tab.SquareBackground)
    fade(tab.SquareBackgroundActive)
    fade(tab.SquareBackgroundActiveGlow)
    fade(tab.GetHighlightTexture and tab:GetHighlightTexture())
    ns.Panel(tab, { alpha = 0.9 })
    local top = tab:CreateTexture(nil, "ARTWORK", nil, 7)
    top:SetPoint("TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", -1, -1)
    top:SetHeight(2)
    top:SetColorTexture(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3], 0.9)
    tab.fuiTop = top
    hover(tab)
    if tab.SetTabSelected then
        hooksecurefunc(tab, "SetTabSelected", tabState)
    end
    tabState(tab)
end

-- Panel buttons ("Accept", "Train") and text boxes: three-piece art.
local function skinButton(b)
    if type(b) ~= "table" or done[b] then
        return
    end
    done[b] = true
    fade(b.Left)
    fade(b.Middle)
    fade(b.Right)
    if b.GetNormalTexture then
        fade(b:GetNormalTexture())
        fade(b:GetPushedTexture())
        fade(b:GetDisabledTexture())
        fade(b:GetHighlightTexture())
    end
    ns.Panel(b, { alpha = 0.9 })
    if b.IsObjectType and b:IsObjectType("Button") then
        hover(b)
    end
end

-- The game's dropdowns: a backdrop and an arrow.
local function skinDropdown(d)
    if type(d) ~= "table" or done[d] then
        return
    end
    done[d] = true
    fade(d.Background)
    ns.Panel(d, { alpha = 0.9 })
    hover(d)
end

-- Thin scroll bars: a dark track, a gold thumb.
local function skinScrollBar(s)
    if type(s) ~= "table" or done[s] then
        return
    end
    local track = s.Track
    local thumb = type(track) == "table" and track.Thumb
    if type(thumb) ~= "table" or not thumb.CreateTexture then
        return
    end
    done[s] = true
    ns.Panel(track, { noBg = true, edge = 0.65 })
    for _, part in ipairs({ track, thumb }) do
        fade(part.Begin)
        fade(part.Middle)
        fade(part.End)
    end
    local line = track:CreateTexture(nil, "BACKGROUND")
    line:SetPoint("TOP", 0, 0)
    line:SetPoint("BOTTOM", 0, 0)
    line:SetWidth(2)
    line:SetColorTexture(0, 0, 0, 0.5)
    local bar = thumb:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOP", 0, -1)
    bar:SetPoint("BOTTOM", 0, 1)
    bar:SetWidth(4)
    bar:SetColorTexture(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], 0.7)
    for _, arrow in ipairs({ s.Back, s.Forward }) do
        if type(arrow) == "table" and arrow.SetAlpha then
            arrow:SetAlpha(0.6)
        end
    end
end

-- An inset (the darker box most windows put their list in).
local function skinInset(inset)
    if type(inset) ~= "table" or done[inset] or not inset.CreateTexture then
        return
    end
    done[inset] = true
    clear(inset.Bg)
    fade(inset.NineSlice)
    ns.Panel(inset, { alpha = 0.45, edge = 0.5 })
end

----------------------------------------------------------------------
-- Looking through a window for those parts
----------------------------------------------------------------------

local function kind(f)
    if type(f) ~= "table" or done[f] then
        return nil
    end
    if f.IsForbidden and f:IsForbidden() then
        return nil
    end
    -- The game's one-pixel Apply Changes glow has Left/Middle/Right fields,
    -- but it is not a button. Skinning it adds our own line through the text.
    local parent = f.GetParent and f:GetParent()
    if type(parent) == "table" and parent.YellowGlow == f then return nil end
    local track = T(f.Track)
    if track and T(track.Thumb) then
        return "scroll"
    end
    if T(f.LeftActive) and T(f.MiddleActive) then
        return "tab"
    end
    if T(f.Arrow) and T(f.Background) and T(f.Text) then
        return "dropdown"
    end
    if T(f.Left) and T(f.Middle) and T(f.Right) then
        return "button"
    end
    if T(f.NineSlice) and T(f.Bg) and not T(f.PortraitContainer) then
        return "inset"
    end
    return nil
end

local SKIN = { scroll = skinScrollBar, tab = skinTab, dropdown = skinDropdown, button = skinButton, inset = skinInset }

local function walk(f, depth)
    if depth > 6 or type(f) ~= "table" or not f.GetChildren then
        return
    end
    for _, c in ipairs({ f:GetChildren() }) do
        local k = kind(c)
        if k then
            pcall(SKIN[k], c)
        end
        -- not into lists (their rows come and go) or scroll bars
        if k ~= "scroll" and not T(c.ScrollTarget) and not (c.IsForbidden and c:IsForbidden()) then
            walk(c, depth + 1)
        end
    end
end

local function skinWindow(f, opts)
    opts = opts or {}
    if type(f) ~= "table" or done[f] or not f.CreateTexture then
        return false
    end
    if f.IsForbidden and f:IsForbidden() then
        return false
    end
    done[f] = true
    fade(f.NineSlice)
    clear(f.Bg)
    clear(f.TopTileStreaks)
    fade(f.PortraitContainer)
    fade(f.portrait)
    local name = f.GetName and f:GetName()
    if name then
        fade(_G[name .. "Portrait"])
        clear(_G[name .. "Bg"])
    end
    ns.Panel(f, { noBg = opts.noBg })
    -- a hairline under the title row
    local rule = f:CreateTexture(nil, "BORDER", nil, 7)
    rule:SetPoint("TOPLEFT", 1, -22)
    rule:SetPoint("TOPRIGHT", -1, -22)
    rule:SetHeight(1)
    rule:SetColorTexture(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], ns.EdgeAlpha() * 0.6)
    f.fuiRule = rule

    local title = T(f.TitleContainer) and T(f.TitleContainer.TitleText) or (name and T(_G[name .. "TitleText"]))
    if title and title.SetTextColor then
        title:SetTextColor(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3])
    end
    skinClose(T(f.CloseButton) or (name and T(_G[name .. "CloseButton"])))

    for _, inset in pairs({ T(f.Inset), T(f.LeftInset), T(f.RightInset), name and T(_G[name .. "Inset"]),
        name and T(_G[name .. "InsetRight"]) }) do
        skinInset(inset)
    end
    -- tabs: the old kind (Tabs, or NameTab1..), and the tab system's
    for _, tab in ipairs(type(f.Tabs) == "table" and f.Tabs or {}) do
        skinTab(tab)
    end
    for i = 1, 10 do
        local tab = name and T(_G[name .. "Tab" .. i])
        if not tab then
            break
        end
        skinTab(tab)
    end
    local system = f.TabSystem
    if type(system) == "table" then
        for _, tab in ipairs(type(system.tabs) == "table" and system.tabs or {}) do
            skinTab(tab)
        end
        if system.AddTab then
            hooksecurefunc(system, "AddTab", function(self)
                for _, tab in ipairs(self.tabs or {}) do
                    skinTab(tab)
                end
            end)
        end
    end
    walk(f, 1)
    -- parts some windows only make when a tab first opens
    f:HookScript("OnShow", function(self)
        walk(self, 1)
    end)
    if not opts.noBg and name and ns.MakeWindowMovable then ns.MakeWindowMovable(f, name) end
    return true
end
ns.SkinWindow = skinWindow

----------------------------------------------------------------------
-- Which windows, and when
----------------------------------------------------------------------

-- name = the game's addon it lives in (nil: always loaded)
local WINDOWS = {
    CharacterFrame = false,
    FriendsFrame = false,
    MerchantFrame = false,
    MailFrame = false,
    GossipFrame = false,
    QuestFrame = false,
    DressUpFrame = false,
    TradeFrame = false,
    LFGParentFrame = "Blizzard_GroupFinder_VanillaStyle",
    PVEFrame = "Blizzard_GroupFinder",
    ProfessionsBookFrame = "Blizzard_ProfessionsBook",
    ProfessionsFrame = "Blizzard_Professions",
    PlayerSpellsFrame = "Blizzard_PlayerSpells",
    LegacySystemFrame = "Blizzard_LegacySystem",
    CommunitiesFrame = "Blizzard_Communities",
    CollectionsJournal = "Blizzard_Collections",
    AccountStoreFrame = "Blizzard_AccountStore",
    AchievementFrame = "Blizzard_AchievementUI",
    EncounterJournal = "Blizzard_EncounterJournal",
    HousingDashboardFrame = "Blizzard_HousingDashboard",
    TokenFrame = "Blizzard_TokenUI",
    -- the quest log is the world map's side panel; the map's border frame
    -- sits over the map, so no backing on that one
    WorldMapFrame = { addon = "Blizzard_WorldMap", part = "BorderFrame", noBg = true, also = "QuestMapFrame" },
}

-- Keep equipment icons, tooltips, quality indicators and click behaviour;
-- replace the game's decorative slot frame with a simple gold edge.
local EQUIPMENT = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist",
    "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1",
    "MainHand", "SecondaryHand", "Ranged" }
local EQUIPMENT_IDS = { Head=1, Neck=2, Shoulder=3, Shirt=4, Chest=5, Waist=6, Legs=7,
    Feet=8, Wrist=9, Hands=10, Finger0=11, Finger1=12, Trinket0=13, Trinket1=14,
    Back=15, MainHand=16, SecondaryHand=17, Ranged=18, Tabard=19 }

-- Match Forever Gold's four additive, inward-fading rarity strips.
local function equipmentGlow(edge)
    local parts = {}
    for i = 1, 4 do
        local t = edge:CreateTexture(nil, "OVERLAY", nil, 2)
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        if t.SetBlendMode then t:SetBlendMode("ADD") end
        t:Hide(); parts[i] = t
    end
    parts[1]:SetPoint("TOPLEFT"); parts[1]:SetPoint("TOPRIGHT"); parts[1]:SetHeight(8)
    parts[2]:SetPoint("BOTTOMLEFT"); parts[2]:SetPoint("BOTTOMRIGHT"); parts[2]:SetHeight(8)
    parts[3]:SetPoint("TOPLEFT"); parts[3]:SetPoint("BOTTOMLEFT"); parts[3]:SetWidth(8)
    parts[4]:SetPoint("TOPRIGHT"); parts[4]:SetPoint("BOTTOMRIGHT"); parts[4]:SetWidth(8)
    return parts
end

local function updateEquipmentQuality(button)
    local edge = button and button.fuiEquipmentEdge
    if not edge or not edge.fuiQualityGlow then return end
    local slot = button.fuiEquipmentSlot
    local quality
    if type(GetInventoryItemQuality) == "function" and slot then
        local ok, value = pcall(GetInventoryItemQuality, "player", slot)
        if ok and not ns.Secret(value) and type(value) == "number" then quality = value end
    end
    if quality == nil and type(GetInventoryItemID) == "function" and type(GetItemInfo) == "function" and slot then
        local ok, id = pcall(GetInventoryItemID, "player", slot)
        if ok and not ns.Secret(id) and id then
            local got, _, _, value = pcall(GetItemInfo, id)
            if got and not ns.Secret(value) and type(value) == "number" then quality = value end
        end
    end
    local color = quality and quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    local opts = ForeverGold and ForeverGold.db and ForeverGold.db.opts
    local enabled = type(opts) ~= "table" or opts.bagQuality ~= false
    if color and enabled and type(CreateColor) == "function" then
        local pct = math.min(100, math.max(1, tonumber(opts and opts.bagGlow) or 50))
        local alpha = (0.2 + 0.8 * pct / 100) * 0.8
        local on, off = CreateColor(color.r, color.g, color.b, alpha), CreateColor(color.r, color.g, color.b, 0)
        local t = edge.fuiQualityGlow
        t[1]:SetGradient("VERTICAL", off, on); t[2]:SetGradient("VERTICAL", on, off)
        t[3]:SetGradient("HORIZONTAL", on, off); t[4]:SetGradient("HORIZONTAL", off, on)
        for _, texture in ipairs(t) do texture:Show() end
    else
        for _, texture in ipairs(edge.fuiQualityGlow) do texture:Hide() end
    end
end

local function skinEquipment()
    for _, name in ipairs(EQUIPMENT) do
        local button = _G["Character" .. name .. "Slot"]
        if type(button) == "table" and button.CreateTexture
            and not (button.IsForbidden and button:IsForbidden()) then
            local ok, err = pcall(function()
                local slotFrame = _G["Character" .. name .. "SlotFrame"]
                local tex
                if type(button.GetNormalTexture) == "function" then
                    tex = button:GetNormalTexture()
                end
                -- Blizzard calls GetNormalTexture():SetVertexColor while
                -- updating equipment. Reparenting that texture makes the
                -- accessor return nil, so keep it owned by its button.
                fade(tex)
                fade(slotFrame)
                fade(button.Frame)
                -- WoW Forever's Camelot template draws the copper equipment
                -- bezel in a separate decorative child, not the normal texture.
                fade(button.BorderFrame)
                fade(button.IconBorder)
                button.fuiEquipmentSlot = EQUIPMENT_IDS[name]
                if not button.fuiEquipmentEdge then
                    local edge = CreateFrame("Frame", nil, button)
                    edge:SetAllPoints(button)
                    edge:SetFrameLevel((button:GetFrameLevel() or 1) + 2)
                    if edge.EnableMouse then edge:EnableMouse(false) end
                    ns.Panel(edge, { noBg = true, edge = 1.15 })
                    edge.fuiQualityGlow = equipmentGlow(edge)
                    button.fuiEquipmentEdge = edge
                end
                updateEquipmentQuality(button)
            end)
            if not ok then ns.Err("equipment " .. name, err) end
        end
    end
end

-- Keep Blizzard's buttons, selected states and click handlers; replace only
-- the visual labels/artwork on the character window's own tabs.
local CHARACTER_TABS = {
    { 1, "character-minimal", "Character" }, { 2, "reputation-tab", "Reputation" },
    { 3, "skills-tab", "Skills" }, { 4, "pvp-tab", "Player vs Player" },
    { 5, "currency-tab", "Currency" }, { 6, "statistics-tab", "Statistics" },
}
local SIDEBAR_TABS = {
    { 1, "statistics-tab", "Statistics" }, { 2, "equipment-tab", "Equipment Manager" },
    { 3, "titles-tab", "Titles" },
}
local function characterIcon(tab, icon, label, sidebar)
    if type(tab) ~= "table" or not tab.CreateTexture then return end
    if tab.IsForbidden and tab:IsForbidden() then return end
    if sidebar then
        fade(tab.Icon); fade(tab.TabBg); fade(tab.Hider); fade(tab.Highlight)
        if not tab.fuiPanel then ns.Panel(tab, { alpha = 0.8, edge = 0.65 }) end
    else
        local text = type(tab.GetFontString) == "function" and tab:GetFontString() or nil
        fade(type(text) == "table" and text or tab.Text)
        for _, key in ipairs({ "Icon", "icon", "NormalTexture", "Portrait", "Background", "TabBg" }) do fade(tab[key]) end
        if type(tab.GetNormalTexture) == "function" then
            local ok, tex = pcall(tab.GetNormalTexture, tab)
            if ok then fade(tex) end
        end
        if not tab.fuiPanel then ns.Panel(tab, { alpha = 1, edge = 0.8 }) end
    end
    fadeNativeTextures(tab)
    if tab.fuiCharacterIcon then return end
    local art = tab:CreateTexture(nil, "OVERLAY", nil, 7)
    art:SetSize(sidebar and 30 or 38, sidebar and 30 or 38)
    art:SetPoint("CENTER", tab, "CENTER", 0, 0)
    art:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\" .. icon)
    -- The new tab art is slightly paler than the original minibar assets.
    -- Match the existing ochre palette without altering the shared orc icon.
    if icon ~= "character-minimal" and art.SetVertexColor then art:SetVertexColor(1, 0.95, 0.77, 1) end
    tab.fuiCharacterIcon = art
    if tab.HookScript then
        tab:HookScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(label, 1, 0.82, 0)
            GameTooltip:Show()
        end)
        tab:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
end

local function skinCharacterTabs()
    local frame = CharacterFrame
    if type(frame) ~= "table" then return end
    for _, spec in ipairs(CHARACTER_TABS) do
        local tab = _G["CharacterFrameTab" .. spec[1]]
        if type(CharacterFrame_GetTab) == "function" then
            local ok, result = pcall(CharacterFrame_GetTab, spec[1])
            if ok and type(result) == "table" then tab = result end
        end
        local ok, err = pcall(characterIcon, tab, spec[2], spec[3], false)
        if not ok then ns.Err("character tab " .. spec[1], err) end
    end
    for _, spec in ipairs(SIDEBAR_TABS) do
        local ok, err = pcall(characterIcon, _G["PaperDollSidebarTab" .. spec[1]], spec[2], spec[3], true)
        if not ok then ns.Err("character sidebar " .. spec[1], err) end
    end
end

local function hideCharacterModelBackground(model)
    local scene = CharacterModelScene
    if type(scene) ~= "table" and type(PaperDollFrame) == "table" then scene = PaperDollFrame.CharacterModelScene end
    if type(scene) ~= "table" or (model and model ~= scene) then return end
    for _, key in ipairs({ "BackgroundTopLeft", "BackgroundTopRight", "BackgroundBotLeft", "BackgroundBotRight", "BackgroundOverlay" }) do
        fade(scene[key])
    end
    fadeNativeTextures(scene)
end

local function skinCharacterSurface()
    if type(CharacterFrame) ~= "table" then return end
    fade(CharacterFrame.Background)
    fade(CharacterFrame.TitleBg)
    fadeNativeTextures(CharacterFrame)
    if type(CharacterFrame.TitleContainer) == "table" then fadeNativeTextures(CharacterFrame.TitleContainer) end
    -- Camelot uses distinct left/right hosts and an unnamed divider child.
    -- Leave the hosts themselves alive: the paper doll and tabs anchor to them.
    if type(CharacterFrame.LeftPaneHost) == "table" then fadeNativeTextures(CharacterFrame.LeftPaneHost) end
    local right = CharacterFrame.RightPaneHost
    if type(right) == "table" then
        fadeNativeTextures(right)
        fade(right.StoneBg)
        if type(right.GetChildren) == "function" then
            for _, child in ipairs({ right:GetChildren() }) do
                if type(child) == "table" and type(child.GetRegions) == "function" then
                    for _, region in ipairs({ child:GetRegions() }) do
                        if type(region) == "table" and type(region.GetAtlas) == "function" then
                            local ok, atlas = pcall(region.GetAtlas, region)
                            if ok and atlas == "common-framedivider" then fade(region) end
                        end
                    end
                end
            end
        end
    end
    if CharacterFrame.fuiPanel then
        CharacterFrame.fuiPanel.alpha = 1
        CharacterFrame.fuiPanel.edge = 1.35
        ns.PaintPanel(CharacterFrame)
    end
    if type(CharacterFrame.InsetRight) == "table" then
        skinInset(CharacterFrame.InsetRight)
        fade(CharacterFrame.InsetRight.NineSlice)
        fade(CharacterFrame.InsetRight.Bg)
        fadeNativeTextures(CharacterFrame.InsetRight)
        if CharacterFrame.InsetRight.fuiPanel then
            CharacterFrame.InsetRight.fuiPanel.noBg = true
            CharacterFrame.InsetRight.fuiPanel.edge = 0
            ns.PaintPanel(CharacterFrame.InsetRight)
        end
    end
    if type(CharacterFrame.Inset) == "table" then
        fade(CharacterFrame.Inset.NineSlice)
        fade(CharacterFrame.Inset.Bg)
        fadeNativeTextures(CharacterFrame.Inset)
        if CharacterFrame.Inset.fuiPanel then
            CharacterFrame.Inset.fuiPanel.noBg = true
            CharacterFrame.Inset.fuiPanel.edge = 0
            ns.PaintPanel(CharacterFrame.Inset)
        end
    end
    if type(CharacterStatsPane) == "table" then
        fade(CharacterStatsPane.ClassBackground)
        fadeNativeTextures(CharacterStatsPane)
    end
    if type(CharacterStatsPaneScrollBox) == "table" then fadeNativeTextures(CharacterStatsPaneScrollBox) end
    if type(PaperDollFrame) == "table" then
        fadeNativeTextures(PaperDollFrame)
        local strip = PaperDollFrame.TopBackgroundStripHost
        if type(strip) == "table" then
            fade(strip.TopBackgroundStrip); fade(strip.TopBackgroundStripBottomEdge)
            fadeNativeTextures(strip)
        end
    end
    if type(CharacterModelFrame) == "table" then fadeNativeTextures(CharacterModelFrame) end
    hideCharacterModelBackground()
    for _, name in ipairs({ "CharacterModelFrameBackgroundTopLeft", "CharacterModelFrameBackgroundTopRight",
        "CharacterModelFrameBackgroundBotLeft", "CharacterModelFrameBackgroundBotRight", "CharacterModelFrameBackgroundOverlay" }) do
        fade(_G[name])
    end
    if type(PaperDollSidebarTabs) == "table" then
        fade(PaperDollSidebarTabs.DecorLeft); fade(PaperDollSidebarTabs.DecorRight)
        fadeNativeTextures(PaperDollSidebarTabs)
        if PaperDollSidebarTabs.fuiFlatBackground then PaperDollSidebarTabs.fuiFlatBackground:Hide() end
    end
end

-- Camelot uses ColoredProgressBarTemplate for these, including a Frame (not a
-- StatusBar) for reputation. Keep Blizzard's values and reaction colours.
local pageFillColors = {
    ["common-stat-bar-blue"] = { 0.16, 0.42, 0.76 },
    ["common-stat-bar-green"] = { 0.25, 0.66, 0.27 },
    ["common-stat-bar-red"] = { 0.72, 0.21, 0.18 },
}
local function paintPageFill(bar)
    if InCombatLockdown and InCombatLockdown() then return end
    local fill = bar and bar.Fill
    if type(fill) ~= "table" or not fill.GetAtlas then return end
    local atlas = fill:GetAtlas()
    if type(atlas) ~= "string" then return end
    local color = pageFillColors[atlas:lower()]
    if color and fill.SetVertexColor then fill:SetVertexColor(unpack(color)) end
    if fill.SetTexture then fill:SetTexture(ns.FLAT) end
    if fill.SetTexCoord then fill:SetTexCoord(0, 1, 0, 1) end
end

local function skinPageProgress(bar)
    if type(bar) ~= "table" or not bar.CreateTexture
        or (bar.IsForbidden and bar:IsForbidden()) then return end
    if type(bar.Fill) ~= "table" or type(bar.FillArea) ~= "table" then return end
    if not bar.fuiPageBar then
        -- Only suppress the template's background, not the fill or text.
        if bar.GetRegions then
            for _, region in ipairs({ bar:GetRegions() }) do
                local atlas = region.GetAtlas and region:GetAtlas()
                if type(atlas) == "string" and atlas:lower() == "common-stat-bar-bg" then fade(region) end
            end
        end
        local edge = CreateFrame("Frame", nil, bar)
        edge:SetPoint("TOPLEFT", bar, "LEFT", 0, 8)
        edge:SetPoint("BOTTOMRIGHT", bar, "RIGHT", 0, -8)
        if edge.EnableMouse then edge:EnableMouse(false) end
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(edge)
        bg:SetColorTexture(0.07, 0.06, 0.05, 0.9)
        ns.Panel(edge, { noBg = true, edge = 0.8 })
        bar.fuiPageBar = edge
        local area, fill = bar.FillArea, bar.Fill
        if area.ClearAllPoints and area.SetPoint then
            area:ClearAllPoints()
            area:SetPoint("TOPLEFT", edge, "TOPLEFT", 1, -1)
            area:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -1, 1)
        end
        if fill.ClearAllPoints and fill.SetPoint then
            fill:ClearAllPoints()
            fill:SetPoint("TOPLEFT", area, "TOPLEFT")
            fill:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT")
        end
        if fill.RemoveMaskTexture and bar.Mask then fill:RemoveMaskTexture(bar.Mask) end
        if type(bar.SetFillPercent) == "function" then
            hooksecurefunc(bar, "SetFillPercent", paintPageFill)
        end
    end
    paintPageFill(bar)
end

local function skinCharacterEntry(row)
    if InCombatLockdown and InCombatLockdown() then return end
    local content = type(row) == "table" and row.Content
    if type(content) == "table" then
        skinPageProgress(content.ReputationBar)
        skinPageProgress(content.SkillsBar)
    end
end

local function skinCharacterList(box)
    if type(box) ~= "table" then return end
    -- ScrollBox recycles rows; style each one after Blizzard initializes it.
    if not box.fuiCharacterRows and ScrollBoxListMixin and ScrollBoxListMixin.Event
        and ScrollBoxListMixin.Event.OnInitializedFrame and box.RegisterCallback then
        box.fuiCharacterRows = true
        box:RegisterCallback(ScrollBoxListMixin.Event.OnInitializedFrame,
            function(_, row) skinCharacterEntry(row) end, box)
    end
    if box.ForEachFrame and (not box.GetView or box:GetView()) then box:ForEachFrame(skinCharacterEntry) end
end

local function skinCharacterBars()
    if InCombatLockdown and InCombatLockdown() then return end
    local seen = {}
    local function visit(frame, depth)
        if depth > 7 or type(frame) ~= "table" or seen[frame]
            or (frame.IsForbidden and frame:IsForbidden()) then return end
        seen[frame] = true
        if type(frame.IsObjectType) == "function" and frame:IsObjectType("StatusBar")
            and type(frame.SetStatusBarTexture) == "function" then
            frame:SetStatusBarTexture(ns.FLAT)
            if not frame.fuiPageBar and frame.CreateTexture then
                local edge = CreateFrame("Frame", nil, frame)
                edge:SetAllPoints(frame)
                if edge.EnableMouse then edge:EnableMouse(false) end
                ns.Panel(edge, { noBg = true, edge = 0.8 })
                frame.fuiPageBar = edge
                fade(frame.Border); fade(frame.border); fade(frame.NineSlice)
            end
        end
        if type(frame.GetChildren) == "function" then
            for _, child in ipairs({ frame:GetChildren() }) do visit(child, depth + 1) end
        end
    end
    local reputation, skills = _G.ReputationFrame, _G.SkillsFrame
    for _, root in ipairs({ reputation or false, skills or false }) do
        if type(root) == "table" then
            skinCharacterList(root.ScrollBox)
            if root.ScrollBar then skinScrollBar(root.ScrollBar) end
        end
    end
    skinPageProgress(reputation and reputation.ReputationDetailFrame and reputation.ReputationDetailFrame.StandingBar)
    skinPageProgress(skills and skills.SkillDetailFrame and skills.SkillDetailFrame.RankBar)
    -- The pet pane is a paper-doll sidebar in Forever, not PetPaperDollFrame.
    local pet = _G.CharacterStatsPanePetScrollBox
    visit(pet, 1)
    skinPageProgress(_G.PetPaperDollFrameExpBar)
end

local skinMerchantHooks = {}
local function saveMerchantPosition(region)
    if type(region) ~= "table" or not region.GetPoint then return nil end
    local point, relative, anchor, x, y = region:GetPoint(1)
    if not point then return nil end
    local saved = { point = point, relative = relative or (region.GetParent and region:GetParent()),
        anchor = anchor or point, x = x or 0, y = y or 0 }
    if region.GetSize then saved.width, saved.height = region:GetSize() end
    if region.GetWordWrap then saved.wrap = region:GetWordWrap() end
    return saved
end

local function restoreMerchantPosition(region, saved, size)
    if type(region) ~= "table" or not saved or not saved.relative or not region.ClearAllPoints or not region.SetPoint then return end
    region:ClearAllPoints()
    region:SetPoint(saved.point, saved.relative, saved.anchor, saved.x, saved.y)
    if size and region.SetSize and type(saved.width) == "number" and type(saved.height) == "number"
        and saved.width > 0 and saved.height > 0 then region:SetSize(saved.width, saved.height) end
    if type(saved.wrap) == "boolean" and region.SetWordWrap then region:SetWordWrap(saved.wrap) end
end

local function skinMerchantItems()
    if InCombatLockdown and InCombatLockdown() then return end
    local buybackPage = type(_G.MerchantFrame) == "table" and _G.MerchantFrame.selectedTab == 2
    local count
    if buybackPage and type(GetNumBuybackItems) == "function" then
        local ok, value = pcall(GetNumBuybackItems)
        if ok and not ns.Secret(value) and type(value) == "number" then count = value end
    end
    fade(_G.BuybackBG)
    for i = 1, 12 do
        local name = "MerchantItem" .. i
        local row = _G[name]
        local button = _G[name .. "ItemButton"] or (row and row.ItemButton)
        if type(row) == "table" and row.CreateTexture and not (row.IsForbidden and row:IsForbidden()) then
            fade(row.SlotTexture); fade(_G[name .. "NameFrame"])
            if not row.fuiPanel then ns.Panel(row, { alpha = 0.48, edge = 0.55 }) end
            local visible = not buybackPage or not count or i <= count
            if row.fuiPanel.bg then row.fuiPanel.bg:SetShown(visible) end
            for _, line in ipairs(row.fuiPanel.lines or {}) do line:SetShown(visible) end
            local label, money = row.Name or _G[name .. "Name"], _G[name .. "MoneyFrame"]
            if buybackPage then
                if not row.fuiBuybackLayout then
                    row.fuiBuybackLayout = { label = saveMerchantPosition(label), money = saveMerchantPosition(money),
                        button = saveMerchantPosition(button) }
                end
                if type(button) == "table" and button.ClearAllPoints and button.SetPoint then
                    button:ClearAllPoints(); button:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
                end
                if type(label) == "table" and label.ClearAllPoints and label.SetPoint then
                    label:ClearAllPoints(); label:SetPoint("TOPLEFT", row, "TOPLEFT", 46, -5)
                    label:SetPoint("TOPRIGHT", row, "TOPRIGHT", -5, -5)
                    if label.SetHeight then label:SetHeight(14) end
                    if type(row.fuiBuybackLayout.label) == "table" and type(row.fuiBuybackLayout.label.wrap) == "boolean"
                        and label.SetWordWrap then label:SetWordWrap(false) end
                end
                if type(money) == "table" and money.ClearAllPoints and money.SetPoint then
                    money:ClearAllPoints(); money:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 46, 5)
                end
            elseif row.fuiBuybackLayout then
                restoreMerchantPosition(button, row.fuiBuybackLayout.button)
                restoreMerchantPosition(label, row.fuiBuybackLayout.label, true)
                restoreMerchantPosition(money, row.fuiBuybackLayout.money)
                row.fuiBuybackLayout = nil
            end
        end
        if type(button) == "table" and button.CreateTexture and not button.fuiMerchantEdge
            and not (button.IsForbidden and button:IsForbidden()) then
            local edge = CreateFrame("Frame", nil, button)
            edge:SetAllPoints(button)
            if edge.EnableMouse then edge:EnableMouse(false) end
            ns.Panel(edge, { noBg = true, edge = 0.8 })
            button.fuiMerchantEdge = edge
            fade(button.BorderFrame); fade(button.Border)
        end
    end
    local buyback = _G.MerchantBuyBackItem
    if type(buyback) == "table" and buyback.CreateTexture and not buyback.fuiPanel then
        fade(buyback.SlotTexture); fade(_G.MerchantBuyBackItemNameFrame)
        ns.Panel(buyback, { alpha = 0.48, edge = 0.55 })
    end
    for _, name in ipairs({ "MerchantFrame_UpdateBuybackInfo", "MerchantFrame_UpdateMerchantInfo" }) do
        if type(_G[name]) == "function" and not skinMerchantHooks[name] then
            skinMerchantHooks[name] = true
            hooksecurefunc(name, function() ns.WhenSafe(skinMerchantItems) end)
        end
    end
end

-- Collection subpages are created lazily. Remove only their named frame
-- artwork; leave collection icons, previews and their click handlers alone.
local function skinCollections()
    if InCombatLockdown and InCombatLockdown() then return end
    local journal = _G.CollectionsJournal
    for _, name in ipairs({ "CollectionsJournal", "MountJournal", "PetJournal", "ToyBox", "HeirloomsJournal", "WardrobeCollectionFrame" }) do
        local frame = _G[name]
        if type(frame) == "table" and not (frame.IsForbidden and frame:IsForbidden()) then
            fade(frame.Background); fade(frame.Bg); fade(frame.NineSlice)
            for _, inset in ipairs({ frame.Inset or false, frame.LeftInset or false, frame.RightInset or false }) do
                if type(inset) == "table" then skinInset(inset) end
            end
            walk(frame, 1)
        end
    end
    if type(journal) == "table" and journal.HookScript and not journal.fuiCollectionRefresh then
        journal.fuiCollectionRefresh = true
        journal:HookScript("OnShow", skinCollections)
        if type(journal.SetTab) == "function" then hooksecurefunc(journal, "SetTab", skinCollections) end
    end
end

local function updatePvpDivider()
    local frame = CharacterFrame
    local pane = type(frame) == "table" and frame.RightPaneHost
    if type(pane) ~= "table" or not pane.CreateTexture then return end
    if not pane.fuiPvpDivider then
        local line = pane:CreateTexture(nil, "OVERLAY", nil, 7)
        line:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -4)
        line:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 4)
        line:SetWidth(1)
        line:SetColorTexture(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], ns.EdgeAlpha() * 0.8)
        pane.fuiPvpDivider = line
    end
    pane.fuiPvpDivider:SetShown(frame.activeSubframe == "PVPRankFrame")
end

-- Flat bars retain Blizzard's rank text and skill updates. Colours use stable
-- skill-line IDs first so they do not depend on the client's language.
local PROFESSION_COLORS = {
    [171] = { 0.43, 0.70, 0.42 }, [164] = { 0.68, 0.43, 0.27 },
    [333] = { 0.61, 0.46, 0.72 }, [202] = { 0.76, 0.58, 0.29 },
    [182] = { 0.38, 0.66, 0.37 }, [165] = { 0.63, 0.43, 0.29 },
    [186] = { 0.52, 0.62, 0.68 }, [393] = { 0.65, 0.45, 0.29 },
    [197] = { 0.48, 0.55, 0.72 }, [185] = { 0.75, 0.50, 0.30 },
    [129] = { 0.70, 0.32, 0.32 }, [356] = { 0.31, 0.57, 0.69 },
}
local function paintProfessionRank(bar, info)
    if type(bar) ~= "table" or not bar.fuiRankFill then return end
    local id = type(info) == "table" and (info.parentProfessionID or info.professionID or info.skillLineID) or bar.fuiSkillLine
    local color = PROFESSION_COLORS[id] or ns.C.gold
    local ratio = type(info) == "table" and type(info.skillLevel) == "number" and type(info.maxSkillLevel) == "number"
        and info.maxSkillLevel > 0 and math.min(1, math.max(0, info.skillLevel / info.maxSkillLevel)) or bar.ratio
    local width = type(bar.GetWidth) == "function" and bar:GetWidth() or nil
    if type(ratio) == "number" and type(width) == "number" and width > 2 then
        bar.fuiRankFill:SetColorTexture(color[1], color[2], color[3], 0.85)
        bar.fuiRankFill:SetWidth(math.max(0.1, (width - 2) * ratio))
        bar.fuiRankFill:SetShown(ratio > 0)
    else
        bar.fuiRankFill:Hide()
    end
    fade(bar.Background); fade(bar.Border); fade(bar.Fill); fade(bar.Flare)
end

local function skinProfessionRank(bar, skillLine)
    if type(bar) ~= "table" or not bar.CreateTexture then return end
    if skillLine then bar.fuiSkillLine = skillLine end
    if not bar.fuiRankFill then
        ns.Panel(bar, { alpha = 0.7, edge = 0.65 })
        local fill = bar:CreateTexture(nil, "ARTWORK", nil, 4)
        fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMLEFT", 1, 1)
        bar.fuiRankFill = fill
        -- Camelot offsets the original text container down to fit its old
        -- artwork. Center the existing text on our flat bar instead.
        local text = type(bar.Rank) == "table" and bar.Rank.Text
        if type(text) == "table" and text.ClearAllPoints and text.SetPoint then
            text:ClearAllPoints()
            text:SetPoint("CENTER", bar, "CENTER", 0, 0)
            if text.SetJustifyH then text:SetJustifyH("CENTER") end
        end
        if type(bar.Update) == "function" then
            hooksecurefunc(bar, "Update", function(self, info) paintProfessionRank(self, info) end)
        end
    end
    paintProfessionRank(bar)
end

-- The Camelot profession overview gives each primary and secondary skill its
-- own Background texture. FormatProfession replaces its atlas on updates.
local function skinProfessionBook(book)
    if type(book) ~= "table" then return end
    local content = book.ProfessionsContentFrame
    if type(content) == "table" then
        for _, name in ipairs({ "PrimaryProfession1", "PrimaryProfession2", "SecondaryProfession1",
            "SecondaryProfession2", "SecondaryProfession3", "SecondaryProfession4", "SecondaryProfession5" }) do
            local card = content[name]
            if type(card) == "table" then
                fade(card.Background)
                if card.CreateTexture and not card.fuiPanel then ns.Panel(card, { alpha = 0.45, edge = 0 }) end
                skinProfessionRank(card.StatusBar, card.skillLine)
            end
        end
        -- Adjacent Camelot cards overlap slightly. Drawing four borders on
        -- each card produces doubled, misaligned seams, so draw one shared
        -- divider at each row/column boundary instead.
        local boundaries = {
            { "primary", content.PrimaryProfession2, "horizontal" },
            { "secondary", content.SecondaryProfession1, "horizontal" },
            { "secondary2", content.SecondaryProfession2, "vertical" },
            { "secondary3", content.SecondaryProfession3, "vertical" },
        }
        if content.CreateTexture then
            content.fuiProfessionDividers = content.fuiProfessionDividers or {}
            for _, spec in ipairs(boundaries) do
                local anchor = spec[2]
                if type(anchor) == "table" and not content.fuiProfessionDividers[spec[1]] then
                    local line = content:CreateTexture(nil, "OVERLAY")
                    if spec[3] == "horizontal" then
                        local last = spec[1] == "secondary" and content.SecondaryProfession3 or anchor
                        if type(last) ~= "table" then last = anchor end
                        line:SetPoint("LEFT", anchor, "TOPLEFT")
                        line:SetPoint("RIGHT", last, "TOPRIGHT")
                        line:SetHeight(1)
                    else
                        line:SetPoint("TOP", anchor, "TOPLEFT")
                        line:SetPoint("BOTTOM", anchor, "BOTTOMLEFT")
                        line:SetWidth(1)
                    end
                    line:SetColorTexture(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], ns.EdgeAlpha() * 0.65)
                    content.fuiProfessionDividers[spec[1]] = line
                end
            end
        end
    end
    if type(book.FormatProfession) == "function" and not book.fuiFormatProfessionHook then
        book.fuiFormatProfessionHook = true
        hooksecurefunc(book, "FormatProfession", function(_, card)
            if type(card) == "table" then fade(card.Background); skinProfessionRank(card.StatusBar, card.skillLine) end
        end)
    end
    if book.HookScript and not book.fuiProfessionBookHook then
        book.fuiProfessionBookHook = true
        book:HookScript("OnShow", skinProfessionBook)
    end
end

-- Forever Gold records recipes by recipe ID. Never guess from item names or
-- treat a missing listing as a zero price; this is a per-output estimate.
local function professionEstimate(page)
    local gold, form = _G.ForeverGold, page.SchematicForm
    if type(gold) ~= "table" or type(gold.Char) ~= "function" or type(gold.EvalRecipe) ~= "function"
        or type(gold.Money) ~= "function" or type(form) ~= "table" or type(form.GetRecipeInfo) ~= "function" then
        return { status = "Forever Gold prices unavailable", age = "Select a recipe to see an estimate" }
    end
    local info = form:GetRecipeInfo()
    local id = type(info) == "table" and info.recipeID
    if not id then return { status = "Select a recipe", age = "Estimates use your last auction scan" } end
    local char = gold.Char()
    for _, recipes in pairs(type(char) == "table" and char.recipes or {}) do
        local r = recipes[id]
        if type(r) == "table" and r.o and type(r.r) == "table" and #r.r > 0 then
            local e = gold.EvalRecipe({ id = id, out = r.o, yield = r.y or 1, reagents = r.r })
            local cost = e.cost and ((e.approx and "~" or "") .. gold.Money(e.cost)) or "unknown"
            local price = e.price and gold.Money(e.price) or "unknown"
            local profit = e.profit and (gold.Profit and gold.Profit(e.profit) or gold.Money(e.profit)) or "unknown"
            local realm = type(gold.R) == "function" and gold.R() or nil
            local age = type(realm) == "table" and realm.lastScan and type(gold.Ago) == "function" and gold.Ago(realm.lastScan) or "no scan"
            return { cost = cost, sale = e.bop and "Bound" or price,
                profit = e.bop and "Not sellable" or profit, age = "Scanned: " .. age }
        end
    end
    return { status = "Recipe prices unavailable", age = "Waiting for Forever Gold recipe data" }
end

-- What one craft costs in reagents (2026-11-26: "say the cost of crafting
-- something, like auction cost, above estimated value"). Each reagent at
-- Forever Gold's cheapest source (auction, vendor, crafting it yourself, or
-- an older price), split into what's already in your bags and what you'd
-- still have to buy. Unlike Estimated value's Cost (per item made), this is
-- per press of Create.
local SOURCE_LABEL = { ah = "auction", vendor = "vendor", craft = "crafted", old = "older price" }
local function craftingCost(page)
    local gold, form = _G.ForeverGold, page.SchematicForm
    if type(gold) ~= "table" or type(gold.Char) ~= "function" or type(gold.Money) ~= "function"
        or type(form) ~= "table" or type(form.GetRecipeInfo) ~= "function" then
        return { status = "Forever Gold prices unavailable" }
    end
    local info = form:GetRecipeInfo()
    local id = type(info) == "table" and info.recipeID
    if not id then return { status = "Select a recipe" } end
    local char = gold.Char()
    local bags = type(char) == "table" and type(char.bags) == "table" and char.bags or {}
    for _, recipes in pairs(type(char) == "table" and char.recipes or {}) do
        local r = recipes[id]
        if type(r) == "table" and type(r.r) == "table" and #r.r > 0 then
            -- Forever Gold's own pick of the cheapest source for each reagent.
            local each = {}
            if type(gold.EvalRecipe) == "function" and r.o then
                local ok, e = pcall(gold.EvalRecipe, { id = id, out = r.o, yield = r.y or 1, reagents = r.r })
                for _, part in ipairs(ok and type(e) == "table" and e.parts or {}) do
                    each[part.id] = { price = part.each, src = part.src }
                end
            end
            local total, have, buy, unknown, lines = 0, 0, 0, false, {}
            for _, reagent in ipairs(r.r) do
                local itemID, qty = reagent[1], tonumber(reagent[2]) or 1
                local known = each[itemID]
                if not known and type(gold.AHPrice) == "function" then
                    local price = gold.AHPrice(itemID)
                    if price then known = { price = price, src = "ah" } end
                end
                if not known and type(gold.VendorBuy) == "function" then
                    local price = gold.VendorBuy(itemID)
                    if price then known = { price = price, src = "vendor" } end
                end
                local owned = math.min(qty, tonumber(bags[itemID]) or 0)
                local name = type(gold.ItemName) == "function" and gold.ItemName(itemID) or ("item " .. tostring(itemID))
                if known and type(known.price) == "number" then
                    total = total + known.price * qty
                    have = have + known.price * owned
                    buy = buy + known.price * (qty - owned)
                    lines[#lines + 1] = { qty .. " x " .. tostring(name), gold.Money(known.price * qty) .. "  |cff999999("
                        .. gold.Money(known.price) .. " each, " .. (SOURCE_LABEL[known.src] or "price") .. ")|r" }
                else
                    unknown = true
                    lines[#lines + 1] = { qty .. " x " .. tostring(name), "|cff999999no price yet|r" }
                end
            end
            local function money(v)
                if unknown then return v > 0 and (gold.Money(v) .. " +?") or "unknown" end
                return gold.Money(v)
            end
            return { total = money(total), have = money(have), buy = money(buy), lines = lines,
                note = unknown and "Some reagents have no price yet - scan the auction house." or nil }
        end
    end
    return { status = "Recipe prices unavailable" }
end

local function refreshCraftingCost(page)
    local box = page and page.fuiCraftCost
    if not box then return end
    local ok, data = pcall(craftingCost, page)
    if not ok or type(data) ~= "table" then data = { status = "Recipe prices unavailable" } end
    box.data = data
    box.status:SetText(data.status or "")
    for _, key in ipairs({ "total", "have", "buy" }) do
        box[key].label:SetShown(not data.status)
        box[key].value:SetShown(not data.status)
        box[key].value:SetText(data[key] or "")
    end
end

local function refreshProfessionEstimate(page)
    refreshCraftingCost(page)
    local box = page and page.fuiEstimate
    if not box then return end
    local ok, data = pcall(professionEstimate, page)
    if not ok or type(data) ~= "table" then data = { status = "Recipe prices unavailable", age = "Open Forever Gold to check prices" } end
    box.status:SetText(data.status or "")
    box.age:SetText(data.age or "")
    for _, key in ipairs({ "cost", "sale", "profit" }) do
        box[key].label:SetShown(not data.status)
        box[key].value:SetShown(not data.status)
        box[key].value:SetText(data[key] or "")
    end
end

local function positionProfessionEstimate(page)
    local box, form, cost = page.fuiEstimate, page.SchematicForm, page.fuiCraftCost
    if not box or type(form) ~= "table" then return end
    local anchor
    for _, name in ipairs({ "FinishingReagents", "OptionalReagents", "Reagents" }) do
        local part = form[name]
        if type(part) == "table" and (not part.IsShown or part:IsShown()) then anchor = part; break end
    end
    if not anchor then box:Hide(); if cost then cost:Hide() end; return end
    -- Do not cover the controls if an unusually long reagent list fills the
    -- form: the crafting cost goes first, the estimate only if both fit.
    local room = math.huge
    if anchor.GetBottom and form.GetBottom then
        local bottom, floor = anchor:GetBottom(), form:GetBottom()
        if type(bottom) == "number" and type(floor) == "number" then room = bottom - floor end
    end
    local below = anchor
    if cost then
        if room < 90 then cost:Hide(); box:Hide(); return end
        cost:ClearAllPoints()
        cost:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
        cost:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -10)
        cost:Show()
        below = cost
        room = room - 72
    end
    if room < 90 then box:Hide(); return end
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -10)
    box:SetPoint("TOPRIGHT", below, "BOTTOMRIGHT", 0, -10)
    box:Show()
end

local function skinProfessionWorkspace(page)
    if type(page) ~= "table" then return end
    local list, form = page.RecipeList, page.SchematicForm
    if type(list) == "table" and list.CreateTexture and not list.fuiPanel then
        ns.Panel(list, { noBg = true, edge = 0.65 })
    end
    if type(form) == "table" and form.CreateTexture and not form.fuiPanel then
        ns.Panel(form, { noBg = true, edge = 0.65 })
    end
    skinProfessionRank(page.RankBar, type(page.professionInfo) == "table" and page.professionInfo.professionID)
    paintProfessionRank(page.RankBar, page.professionInfo)
    -- Keep the recipe list full-height and place the estimate after the last
    -- visible reagent group on the recipe details side.
    if not page.fuiEstimate and type(form) == "table" and form.CreateTexture then
      -- Two boxes of three columns: Crafting cost above Estimated value.
      local function valueBox(title, specs, height)
        local box = CreateFrame("Frame", nil, form)
        box:SetHeight(height)
        ns.Panel(box, { alpha = 0.65, edge = 0.7 })
        local heading = ns.Text(box, 11, ns.C.bright)
        heading:SetPoint("TOPLEFT", 8, -6); heading:SetText(title)
        box.status = ns.Text(box, 11, ns.C.text)
        box.status:SetPoint("TOPLEFT", 8, -25)
        box.status:SetPoint("TOPRIGHT", box, "TOPRIGHT", -8, -25)
        box.status:SetJustifyH("LEFT")
        if box.status.SetWordWrap then box.status:SetWordWrap(false) end
        box.age = ns.Text(box, 10, ns.C.muted)
        box.age:SetPoint("BOTTOMLEFT", 8, 6)
        box.age:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 6)
        box.age:SetJustifyH("LEFT")
        if box.age.SetWordWrap then box.age:SetWordWrap(false) end
        local columns = {}
        for i, spec in ipairs(specs) do
            local column = CreateFrame("Frame", nil, box)
            column:SetPoint("TOPLEFT", box, "TOPLEFT", 8 + (i - 1) * 100, -25)
            column:SetSize(96, 30)
            column.label = ns.Text(column, 10, ns.C.muted)
            column.label:SetPoint("TOPLEFT"); column.label:SetText(spec[2])
            column.label:SetPoint("TOPRIGHT")
            column.label:SetJustifyH("LEFT")
            if column.label.SetWordWrap then column.label:SetWordWrap(false) end
            column.value = ns.Text(column, 11, ns.C.text)
            column.value:SetPoint("BOTTOMLEFT")
            column.value:SetPoint("BOTTOMRIGHT")
            column.value:SetJustifyH("LEFT")
            if column.value.SetWordWrap then column.value:SetWordWrap(false) end
            box[spec[1]] = column
            columns[i] = column
        end
        box:SetScript("OnSizeChanged", function(_, width)
            if type(width) ~= "number" or width <= 16 then return end
            local columnWidth = (width - 16) / 3
            for i, column in ipairs(columns) do
                column:ClearAllPoints()
                column:SetPoint("TOPLEFT", box, "TOPLEFT", 8 + (i - 1) * columnWidth, -25)
                column:SetWidth(math.max(1, columnWidth - 4))
            end
        end)
        return box
      end
        local cost = valueBox("Crafting cost", { { "total", "Per craft" }, { "have", "In your bags" }, { "buy", "Still to buy" } }, 62)
        cost.age:Hide()
        -- Hovering lists each reagent's price and where it comes from.
        cost:EnableMouse(true)
        cost:SetScript("OnEnter", function(self)
            local data = self.data
            if type(data) ~= "table" or type(data.lines) ~= "table" or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Reagents for one craft")
            for _, line in ipairs(data.lines) do
                GameTooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 1, 1, 1)
            end
            if data.note then GameTooltip:AddLine(data.note, 1, 0.6, 0.2, true) end
            GameTooltip:Show()
        end)
        cost:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        page.fuiCraftCost = cost
        local box = valueBox("Estimated value", { { "cost", "Cost" }, { "sale", "Sale" }, { "profit", "Profit (net)" } }, 72)
        page.fuiEstimate = box
        for _, fn in ipairs({ "SelectRecipe", "Refresh" }) do
            if type(page[fn]) == "function" then hooksecurefunc(page, fn, function() refreshProfessionEstimate(page); positionProfessionEstimate(page) end) end
        end
        if type(form.Refresh) == "function" then hooksecurefunc(form, "Refresh", function() positionProfessionEstimate(page) end) end
    end
    local gold = _G.ForeverGold
    if page.fuiEstimate and type(gold) == "table" and type(gold.Listen) == "function" and not page.fuiGoldListeners then
        page.fuiGoldListeners = true
        for _, event in ipairs({ "RECIPES_UPDATED", "PRICES_UPDATED", "ITEMS_UPDATED" }) do
            gold.Listen(event, function() refreshProfessionEstimate(page) end)
        end
    end
    refreshProfessionEstimate(page)
    positionProfessionEstimate(page)
end

-- Remove the actual Camelot background layers without touching skill icons,
-- selection markers, text or the game's crafting controls.
local function skinProfessions(frame)
    if type(frame) ~= "table" then return end
    -- These are reassigned or shown by Blizzard when switching professions
    -- and when changing between the full and minimized crafting views.
    fade(frame.Bg)
    fade(frame.TopTileStreaks)
    local page = frame.CraftingPage
    if type(page) == "table" and type(page.GetRegions) == "function" then
        for _, region in ipairs({ page:GetRegions() }) do
            if type(region) == "table" and type(region.GetAtlas) == "function" then
                local ok, atlas = pcall(region.GetAtlas, region)
                if ok and atlas == "Profession-Background-Template2" then fade(region) end
            end
        end
    end
    if type(page) == "table" then
        skinProfessionWorkspace(page)
        local form, list = page.SchematicForm, page.RecipeList
        if type(form) == "table" then
            fade(form.Background)
            fade(form.MinimalBackground)
            fade(form.NineSlice)
            -- Camelot's schematic template adds this unnamed copper frame.
            if type(form.GetRegions) == "function" then
                for _, region in ipairs({ form:GetRegions() }) do
                    if type(region) == "table" and type(region.GetAtlas) == "function" then
                        local ok, atlas = pcall(region.GetAtlas, region)
                        if ok and atlas == "common-insideframe" then fade(region) end
                    end
                end
            end
        end
        if type(list) == "table" then fade(list.Background); fade(list.BackgroundNineSlice) end
        if page.HookScript and not page.fuiProfessionShowHook then
            page.fuiProfessionShowHook = true
            page:HookScript("OnShow", function() skinProfessions(frame) end)
        end
        if type(page.Refresh) == "function" and not page.fuiProfessionRefreshHook then
            page.fuiProfessionRefreshHook = true
            hooksecurefunc(page, "Refresh", function() skinProfessions(frame) end)
        end
    end
    skinProfessionBook(frame.BookPage)
    if type(frame.OverrideArt) == "function" and not frame.fuiProfessionArtHook then
        frame.fuiProfessionArtHook = true
        hooksecurefunc(frame, "OverrideArt", function() skinProfessions(frame) end)
    end
    -- Leave the profession side tabs to Camelot: its selected highlight follows
    -- the icon's clipped corners, unlike the addon's rectangular panel.
end

local function spellBookText(font, color)
    if type(font) == "table" and type(font.SetTextColor) == "function" then
        font:SetTextColor(color[1], color[2], color[3])
    end
end

local function skinSpellIcon(row)
    local button = type(row) == "table" and row.Button
    local icon = type(button) == "table" and button.Icon
    if type(button) ~= "table" or type(icon) ~= "table" or not button.CreateTexture then return end
    fade(button.Border); fade(button.BorderShadow); fade(button.BorderSheen)
    if not button.fuiSpellIconEdge then
        local edge = CreateFrame("Frame", nil, button)
        edge:SetAllPoints(icon)
        if edge.SetFrameLevel and button.GetFrameLevel then edge:SetFrameLevel((button:GetFrameLevel() or 1) + 2) end
        if edge.EnableMouse then edge:EnableMouse(false) end
        ns.Panel(edge, { noBg = true, edge = 0.9 })
        button.fuiSpellIconEdge = edge
    end
    if type(row.ApplyBorderArt) == "function" and not row.fuiSpellBorderHook then
        row.fuiSpellBorderHook = true
        hooksecurefunc(row, "ApplyBorderArt", function() skinSpellIcon(row) end)
    end
end

local function skinSpellCategory(tab)
    if type(tab) ~= "table" or not tab.CreateTexture then return end
    skinTab(tab)
    for _, key in ipairs({ "SquareBackground", "SquareBackgroundActive", "SquareBackgroundActiveGlow" }) do fade(tab[key]) end
    if tab.fuiPanel then tab.fuiPanel.noBg = true; tab.fuiPanel.edge = 0; tab.fuiPanel.bright = false; ns.PaintPanel(tab) end
    if tab.fuiTop then tab.fuiTop:Hide() end
    if type(tab.Icon) == "table" and not tab.fuiSpellTabEdge then
        local edge = CreateFrame("Frame", nil, tab)
        edge:SetAllPoints(tab.Icon)
        if edge.SetFrameLevel and tab.GetFrameLevel then edge:SetFrameLevel((tab:GetFrameLevel() or 1) + 2) end
        if edge.EnableMouse then edge:EnableMouse(false) end
        ns.Panel(edge, { noBg = true, edge = 0.9 })
        tab.fuiSpellTabEdge = edge
        if type(tab.SetTabSelected) == "function" then
            hooksecurefunc(tab, "SetTabSelected", function(self, selected)
                for _, key in ipairs({ "SquareBackground", "SquareBackgroundActive", "SquareBackgroundActiveGlow" }) do fade(self[key]) end
                if self.fuiTop then self.fuiTop:Hide() end
                if self.fuiPanel then self.fuiPanel.bright = false; ns.PaintPanel(self) end
                if self.fuiSpellTabEdge and self.fuiSpellTabEdge.fuiPanel then
                    self.fuiSpellTabEdge.fuiPanel.bright = selected and true or false
                    ns.PaintPanel(self.fuiSpellTabEdge)
                end
            end)
        end
    end
    if tab.fuiSpellTabEdge and tab.fuiSpellTabEdge.fuiPanel then
        tab.fuiSpellTabEdge.fuiPanel.bright = tab.isSelected and true or false
        ns.PaintPanel(tab.fuiSpellTabEdge)
    end
end

-- Spell rows are recycled when changing pages; theme only their decorative
-- backplates and labels, never their button, icon, cooldown or drag scripts.
local function skinSpellBookRow(row)
    if type(row) ~= "table" then return end
    local text = row.TextContainer
    if type(text) == "table" then
        fade(row.Backplate)
        skinSpellIcon(row)
        spellBookText(text.Name or row.Name, ns.C.text)
        spellBookText(text.SubName or row.SubName, ns.C.muted)
        spellBookText(text.RequiredLevel or row.RequiredLevel, ns.C.muted)
    elseif type(row.Text) == "table" and row.Border and row.Backplate then
        -- SpellBookHeaderTemplate, not a spell or an interactive control.
        fade(row.Backplate); fade(row.Border)
        spellBookText(row.Text, ns.C.bright)
        if row.CreateTexture and not row.fuiSpellRule then
            local rule = row:CreateTexture(nil, "ARTWORK")
            rule:SetPoint("BOTTOMLEFT", 0, 0); rule:SetPoint("BOTTOMRIGHT", 0, 0)
            rule:SetHeight(1); rule:SetColorTexture(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], 0.5)
            row.fuiSpellRule = rule
        end
    end
end

local function walkSpellBookRows(frame, depth)
    if depth > 5 or type(frame) ~= "table" then return end
    skinSpellBookRow(frame)
    if type(frame.GetChildren) ~= "function" then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        if type(child) == "table" and not (child.IsForbidden and child:IsForbidden()) then
            walkSpellBookRows(child, depth + 1)
        end
    end
end

local function alignSpellBookSearch(book)
    if InCombatLockdown and InCombatLockdown() then return end
    local search, dropdown, trainer = book.SearchBox, book.SettingsDropdown, book.fuiTrainerButton
    if type(search) ~= "table" or type(dropdown) ~= "table" or type(trainer) ~= "table" then return end

    -- Keep the settings arrow's existing horizontal anchors (including the
    -- assisted-combat layout), but align its vertical centre with the tabs.
    local targetTop
    if trainer.GetCenter and trainer.GetEffectiveScale and book.GetTop and book.GetEffectiveScale
        and dropdown.GetHeight and dropdown.GetEffectiveScale then
        local ok, top, bookScale, center, trainerScale, height, dropdownScale = pcall(function()
            local _, y = trainer:GetCenter()
            return book:GetTop(), book:GetEffectiveScale(), y, trainer:GetEffectiveScale(), dropdown:GetHeight(), dropdown:GetEffectiveScale()
        end)
        if ok and not ns.Secret(top) and not ns.Secret(bookScale) and not ns.Secret(center)
            and not ns.Secret(trainerScale) and not ns.Secret(height) and not ns.Secret(dropdownScale)
            and type(top) == "number" and type(bookScale) == "number" and bookScale > 0
            and type(center) == "number" and type(trainerScale) == "number"
            and type(height) == "number" and height > 0 and type(dropdownScale) == "number" then
            targetTop = (center * trainerScale + height * dropdownScale / 2 - top * bookScale) / bookScale
        end
    end
    if targetTop and dropdown.GetNumPoints and dropdown.GetPoint and dropdown.ClearAllPoints and dropdown.SetPoint then
        local points, hasTop = {}, false
        for i = 1, dropdown:GetNumPoints() do
            local p, rel, rp, x, y = dropdown:GetPoint(i)
            if p == "TOP" or p == "TOPRIGHT" or p == "TOPLEFT" then
                if rel == book or rel == nil then y, hasTop = targetTop, true end
            end
            points[#points + 1] = { p, rel or book, rp or p, x or 0, y or 0 }
        end
        if hasTop then
            dropdown:ClearAllPoints()
            for _, point in ipairs(points) do dropdown:SetPoint(unpack(point)) end
        end
    end

    if search.ClearAllPoints and search.SetPoint then
        search:ClearAllPoints()
        search:SetPoint("RIGHT", dropdown, "LEFT", -5, 0)
    end
    local icon = search.searchIcon or search.SearchIcon
    if type(icon) == "table" and icon.ClearAllPoints and icon.SetPoint then
        icon:ClearAllPoints(); icon:SetPoint("LEFT", search, "LEFT", 6, 0)
    end
    if search.GetTextInsets and search.SetTextInsets then
        local l, r, t, b = search:GetTextInsets()
        if not ns.Secret(l) and not ns.Secret(r) and not ns.Secret(t) and not ns.Secret(b)
            and type(l) == "number" and type(r) == "number" and type(t) == "number" and type(b) == "number" then
            search:SetTextInsets(math.max(l, 24), r, t, b)
        end
    end
    local instructions = search.Instructions
    if type(instructions) == "table" and instructions.ClearAllPoints and instructions.SetPoint then
        instructions:ClearAllPoints()
        instructions:SetPoint("LEFT", search, "LEFT", 24, 0)
        instructions:SetPoint("RIGHT", search, "RIGHT", -20, 0)
    end

    -- Blizzard's width calculation does not include our added trainer tab.
    if search.GetRight and search.GetWidth and search.SetWidth and trainer.GetRight then
        local right, tabRight, width = search:GetRight(), trainer:GetRight(), search:GetWidth()
        if not ns.Secret(right) and not ns.Secret(tabRight) and not ns.Secret(width)
            and type(right) == "number" and type(tabRight) == "number" and type(width) == "number" then
            local available = right - tabRight - 8
            if available > 0 and width > available then search:SetWidth(available) end
        end
    end
end

local function skinSpellBook(frame)
    local book = type(frame) == "table" and frame.SpellBookFrame
    if type(book) ~= "table" then return end
    if ns.AddTrainerButton then ns.AddTrainerButton(frame) end
    alignSpellBookSearch(book)
    for _, key in ipairs({ "TopBar", "BookBGHalved", "BookBGLeft", "BookBGRight", "BookCornerFlipbook", "Bookmark" }) do
        fade(book[key])
    end
    -- The parent window already supplies the border and title divider; an
    -- additional border on the inset book creates a stray line under it.
    local system = book.CategoryTabSystem
    if type(system) == "table" then
        for _, tab in ipairs(type(system.tabs) == "table" and system.tabs or {}) do skinSpellCategory(tab) end
    end
    local paged = book.PagedSpellsFrame
    if type(paged) == "table" then
        for _, view in ipairs(type(paged.ViewFrames) == "table" and paged.ViewFrames or {}) do walkSpellBookRows(view, 1) end
        local controls = paged.PagingControls
        if type(controls) == "table" then
            spellBookText(controls.PageText, ns.C.text)
            for _, button in pairs({ controls.PrevPageButton, controls.NextPageButton }) do
                if type(button) == "table" then
                    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
                        if type(button[getter]) == "function" then
                            local ok, tex = pcall(button[getter], button)
                            if ok and type(tex) == "table" and type(tex.SetVertexColor) == "function" then
                                tex:SetVertexColor(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3])
                            end
                        end
                    end
                end
            end
        end
    end
    if type(book.ForEachDisplayedSpell) == "function" then pcall(book.ForEachDisplayedSpell, book, skinSpellBookRow) end
    if book.HookScript and not book.fuiSpellBookHook then
        book.fuiSpellBookHook = true
        book:HookScript("OnShow", function()
            skinSpellBook(frame)
            -- The tab geometry may not be resolved until the next frame.
            if C_Timer and C_Timer.After then C_Timer.After(0, function()
                if not book.IsShown or book:IsShown() then alignSpellBookSearch(book) end
            end) end
        end)
        if type(book.SetMinimized) == "function" then hooksecurefunc(book, "SetMinimized", function() skinSpellBook(frame) end) end
        if type(book.AddIconTab) == "function" then hooksecurefunc(book, "AddIconTab", function() skinSpellBook(frame) end) end
        for _, method in ipairs({ "UpdateAttic", "ResizeSearchBox" }) do
            if type(book[method]) == "function" then hooksecurefunc(book, method, function() alignSpellBookSearch(book) end) end
        end
        if EventRegistry and type(EventRegistry.RegisterCallback) == "function" then
            EventRegistry:RegisterCallback("PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged", function() skinSpellBook(frame) end, book)
        end
    end
end

-- Camelot's talent tree has its own class artwork and a copper inner frame.
-- Its textures are also used as anchors, so fade them without removing or
-- reparenting them. Talent nodes and their state indicators are left alone.
local function centerTalentTab(tab)
    if type(tab) ~= "table" then return end
    local text = tab.Text
    if type(text) == "table" and text.ClearAllPoints and text.SetPoint then
        text:ClearAllPoints()
        text:SetPoint("CENTER", tab, "CENTER", 0, 0)
        if text.SetJustifyH then text:SetJustifyH("CENTER") end
    end
    if type(tab.SetTabSelected) == "function" and not tab.fuiTalentCenterHook then
        tab.fuiTalentCenterHook = true
        hooksecurefunc(tab, "SetTabSelected", centerTalentTab)
    end
end

local function stopTalentBackgroundAnimations(talents)
    for _, animation in ipairs(type(talents.backgroundAnims) == "table" and talents.backgroundAnims or {}) do
        if type(animation) == "table" and type(animation.SetPlaying) == "function" then animation:SetPlaying(false) end
    end
    for _, key in ipairs({ "Clouds1", "Clouds2", "AirParticlesClose", "AirParticlesFar",
        "OverlayBackgroundRight", "OverlayBackgroundMid" }) do
        fade(talents[key])
    end
end

local function centerTalentHeaderNumber(header)
    if type(header) ~= "table" or type(header.Icon) ~= "table"
        or (InCombatLockdown and InCombatLockdown()) then return end
    for _, key in ipairs({ "Text", "Points", "PointsText", "PointsSpent", "Count" }) do
        local text = header[key]
        if type(text) == "table" and text.GetText and text.ClearAllPoints and text.SetPoint then
            local value = text:GetText()
            if not ns.Secret(value) and type(value) == "string" and value:match("^%s*%d+%s*$") then
                text:ClearAllPoints()
                text:SetPoint("TOP", header.Icon, "BOTTOM", 0, -2)
                if text.SetJustifyH then text:SetJustifyH("CENTER") end
            end
            if text.SetText and not text.fuiTalentHeaderHook then
                text.fuiTalentHeaderHook = true
                hooksecurefunc(text, "SetText", function() centerTalentHeaderNumber(header) end)
            end
        end
    end
end

-- Centre the unspent talent points number in its box by eye, not by its text
-- box: a line of text reserves room below the digits, so they sit high, and
-- the font's "1" stands right of its slot. Nudge by a share of the font size.
local function centerTalentAmount(text, box)
    local size = 12
    if text.GetFont then
        local _, fontSize = text:GetFont()
        if type(fontSize) == "number" and fontSize > 0 then size = fontSize end
    end
    local value = text.GetText and text:GetText()
    local x = 0
    if type(value) == "string" then
        if value:sub(1, 1) == "1" then x = x - size * 0.03 end
        if value:sub(-1) == "1" then x = x - size * 0.03 end
    end
    text:ClearAllPoints()
    text:SetPoint("CENTER", box, "CENTER", x, -size * 0.04)
end

local function skinTalentPage(frame)
    local talents = type(frame) == "table" and frame.TalentsFrame
    if type(talents) ~= "table" then return end
    local applyGlow = type(talents.ApplyButton) == "table" and talents.ApplyButton.YellowGlow
    if type(applyGlow) == "table" then
        fade(applyGlow)
        fade(applyGlow.Left); fade(applyGlow.Middle); fade(applyGlow.Right)
    end
    stopTalentBackgroundAnimations(talents)
    for _, key in ipairs({ "Background", "ClassBackground", "OverlayBackgroundRight", "OverlayBackgroundMid",
        "Clouds1", "Clouds2", "AirParticlesClose", "AirParticlesFar", "BackgroundBorder",
        "DividerHorizontalLeft", "DividerHorizontalRight", "DividerVerticalLeft", "DividerVerticalRight" }) do
        fade(talents[key])
    end
    local treeBg = talents.ClassBackground
    if type(treeBg) == "table" and talents.CreateTexture and not talents.fuiTreeEdge then
        local edge = CreateFrame("Frame", nil, talents)
        edge:SetAllPoints(treeBg)
        if edge.EnableMouse then edge:EnableMouse(false) end
        ns.Panel(edge, { noBg = true, edge = 0.75 })
        -- The tree background extends behind the Apply Changes controls;
        -- its bottom hairline otherwise cuts straight through the button.
        edge.fuiPanel.lines[2]:Hide()
        talents.fuiTreeEdge = edge
    end
    -- Anchor to Camelot's existing divider positions so the lines stay aligned
    -- with the three trees without changing their layout or node links.
    for _, key in ipairs({ "DividerVerticalLeft", "DividerVerticalRight" }) do
        local original = talents[key]
        local slot = "fui" .. key
        if type(original) == "table" and talents.CreateTexture and not talents[slot] then
            local line = talents:CreateTexture(nil, "OVERLAY", nil, 1)
            line:SetPoint("TOP", original, "TOP")
            line:SetPoint("BOTTOM", original, "BOTTOM")
            line:SetWidth(1)
            line:SetColorTexture(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], 0.55)
            talents[slot] = line
        end
    end
    local tabs = talents.TabSystem
    if type(tabs) == "table" then
        for _, tab in ipairs(type(tabs.tabs) == "table" and tabs.tabs or {}) do
            skinTab(tab)
            centerTalentTab(tab)
        end
    end
    for _, header in ipairs(type(talents.treeHeaders) == "table" and talents.treeHeaders or {}) do
        if type(header) == "table" then
            fade(header.MainRing); fade(header.TextBackground); fade(header.Divider)
            spellBookText(header.Name, ns.C.bright)
            spellBookText(header.Text, ns.C.text)
            centerTalentHeaderNumber(header)
            if type(header.Icon) == "table" and header.CreateTexture and not header.fuiTalentIconEdge then
                local edge = CreateFrame("Frame", nil, header)
                edge:SetAllPoints(header.Icon)
                if edge.EnableMouse then edge:EnableMouse(false) end
                ns.Panel(edge, { noBg = true, edge = 0.8 })
                header.fuiTalentIconEdge = edge
            end
        end
    end
    local currency = talents.ClassCurrencyDisplay
    if type(currency) == "table" then
        fade(currency.Border)
        local amount = currency.CurrentAmountContainer
        if type(amount) == "table" and amount.CreateTexture and not amount.fuiPanel then
            ns.Panel(amount, { noBg = true, edge = 0.75 })
        end
        local text = type(amount) == "table" and amount.CurrencyAmount
        if type(text) == "table" and text.ClearAllPoints and text.SetPoint and not amount.fuiCenteredAmount then
            if text.SetJustifyH then text:SetJustifyH("CENTER") end
            if text.SetJustifyV then text:SetJustifyV("MIDDLE") end
            centerTalentAmount(text, amount)
            if type(text.SetText) == "function" then
                hooksecurefunc(text, "SetText", function(self) centerTalentAmount(self, amount) end)
            end
            amount.fuiCenteredAmount = true
        end
    end
    if talents.HookScript and not talents.fuiTalentHook then
        talents.fuiTalentHook = true
        talents:HookScript("OnShow", function() skinTalentPage(frame) end)
        for _, method in ipairs({ "UpdateSpecBackground", "UpdateClassVisuals", "RefreshTreeHeaders", "UpdateTabs" }) do
            if type(talents[method]) == "function" then
                hooksecurefunc(talents, method, function() skinTalentPage(frame) end)
            end
        end
        if type(talents.SetBackgroundAnimationsPlaying) == "function" then
            hooksecurefunc(talents, "SetBackgroundAnimationsPlaying", function(self, playing)
                if playing then stopTalentBackgroundAnimations(self) end
            end)
        end
    end
end

-- Legacy uses a trait tree with interactive nodes and connecting lines.  Only
-- touch named background artwork on its containers; the tree itself remains
-- entirely owned by the game.
local LEGACY_POINT_ART = "Interface\\AddOns\\ForeverUI\\Art\\legacy-points-emblem"

local function skinLegacyShield(shield, offsetX)
    if type(shield) ~= "table" then return end
    local icon, points = shield.Icon, shield.Points
    if type(icon) == "table" and icon.SetTexture then
        icon:SetTexture(LEGACY_POINT_ART)
        if icon.SetTexCoord then icon:SetTexCoord(0, 1, 0, 1) end
    end
    if type(icon) == "table" and type(points) == "table" and points.ClearAllPoints and points.SetPoint then
        -- The crown sits above the shield's body. Offset relative to the
        -- actual icon height so the small reward shields and the larger
        -- summary shield both center the glyph within the dark area.
        local height = icon.GetHeight and icon:GetHeight() or nil
        if ns.Secret(height) or type(height) ~= "number" or height <= 0 then height = 51 end
        points:ClearAllPoints()
        points:SetPoint("CENTER", icon, "CENTER", offsetX or -1.5, -height * 0.04)
        if points.SetJustifyH then points:SetJustifyH("CENTER") end
        if points.SetJustifyV then points:SetJustifyV("MIDDLE") end
    end
end

local function legacyCard(card)
    if type(card) ~= "table" or not card.CreateTexture then return end
    for _, key in ipairs({ "Background", "BackgroundTop", "BackgroundMiddle", "BackgroundBottom",
        "TitleBar", "SelectedOverlay" }) do fade(card[key]) end
    if type(card.Icon) == "table" then fade(card.Icon.frame) end
    skinLegacyShield(card.Shield, -0.5)
    if not card.fuiPanel then ns.Panel(card, { alpha = 0.65, edge = 0.65 }) end
    if card.fuiPanel and type(card.IsSelected) == "function" then
        local ok, selected = pcall(card.IsSelected, card)
        if ok then card.fuiPanel.bright = selected and true or false; ns.PaintPanel(card) end
    end
end

local function suppressLegacyRewardArt(texture)
    if type(texture) ~= "table" or type(texture.SetAlpha) ~= "function" then return end
    fade(texture)
    if texture.Hide then texture:Hide() end
    -- Renown redraws pooled card art, including when hovered. Keep only this
    -- decorative texture transparent without changing the card's own alpha.
    if not texture.fuiLegacyHidden and type(hooksecurefunc) == "function" then
        texture.fuiLegacyHidden = true
        local resetting = false
        hooksecurefunc(texture, "SetAlpha", function(self, alpha)
            if not resetting and not ns.Secret(alpha) and type(alpha) == "number" and alpha ~= 0 then
                resetting = true
                self:SetAlpha(0)
                resetting = false
            end
        end)
        if type(texture.Show) == "function" then
            hooksecurefunc(texture, "Show", function(self)
                if not resetting then
                    resetting = true
                    self:SetAlpha(0)
                    if self.Hide then self:Hide() end
                    resetting = false
                end
            end)
        end
        if type(texture.SetShown) == "function" then
            hooksecurefunc(texture, "SetShown", function(self, shown)
                if not ns.Secret(shown) and shown and not resetting then
                    resetting = true
                    self:SetAlpha(0)
                    if self.Hide then self:Hide() end
                    resetting = false
                end
            end)
        end
        if type(texture.SetAtlas) == "function" then
            hooksecurefunc(texture, "SetAtlas", function(self)
                if not resetting then
                    resetting = true
                    self:SetAlpha(0)
                    if self.Hide then self:Hide() end
                    resetting = false
                end
            end)
        end
    end
end

-- Camelot can supply the reward-card texture through the track's pooled
-- descendants rather than the card's named field. Only suppress that exact
-- atlas family; item icons, reward state and checkmarks stay untouched.
local function scanLegacyRewardArt(frame, depth)
    if type(frame) ~= "table" or depth > 8 then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    if type(frame.GetRegions) == "function" then
        for _, region in ipairs({ frame:GetRegions() }) do
            if type(region) == "table" and type(region.GetAtlas) == "function" then
                local ok, atlas = pcall(region.GetAtlas, region)
                if ok and not ns.Secret(atlas) and type(atlas) == "string"
                    and atlas:lower():find("legacy%-rewards%-tracker%-cards") then
                    suppressLegacyRewardArt(region)
                end
            end
        end
    end
    if type(frame.GetChildren) == "function" then
        for _, child in ipairs({ frame:GetChildren() }) do scanLegacyRewardArt(child, depth + 1) end
    end
end

local function skinLegacyRewardCard(card)
    if type(card) ~= "table" or not card.CreateTexture then return end
    suppressLegacyRewardArt(card.RewardCardBG)
    suppressLegacyRewardArt(card.IconBorder)
    suppressLegacyRewardArt(card.LevelSquare)
    if not card.fuiPanel then ns.Panel(card, { alpha = 0.65, edge = 0.65 }) end
    if card.fuiPanel and not card.fuiLegacyPanelInset then
        -- Adjacent reward cards overlap by five pixels in Blizzard's track.
        -- Inset the same lines used for both idle and hover to avoid doubled,
        -- offset borders where neighbouring cards meet.
        local p = card.fuiPanel
        local edges = {
            { "TOPLEFT", "TOPRIGHT", 2, -2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 2, -2 },
            { "TOPLEFT", "BOTTOMLEFT", 2, 2 }, { "TOPRIGHT", "BOTTOMRIGHT", -2, -2 },
        }
        for i, e in ipairs(edges) do
            local line = p.lines[i]
            line:ClearAllPoints()
            line:SetPoint(e[1], card, e[1], e[3], 0)
            line:SetPoint(e[2], card, e[2], e[4], 0)
        end
        p.bg:ClearAllPoints()
        p.bg:SetPoint("TOPLEFT", card, "TOPLEFT", 2, 0)
        p.bg:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 0)
        card.fuiLegacyPanelInset = true
    end
    if type(card.Level) == "table" and card.Level.ClearAllPoints and card.Level.SetPoint then
        card.Level:ClearAllPoints()
        card.Level:SetPoint("TOP", card, "TOP", 0, -8)
        if card.Level.SetJustifyH then card.Level:SetJustifyH("CENTER") end
    end
    if type(card.Icon) == "table" and not card.fuiLegacyIconEdge then
        local edge = CreateFrame("Frame", nil, card)
        edge:SetAllPoints(card.Icon)
        if edge.EnableMouse then edge:EnableMouse(false) end
        ns.Panel(edge, { noBg = true, edge = 0.8 })
        card.fuiLegacyIconEdge = edge
    end
    if not card.fuiLegacyRewardHook then
        card.fuiLegacyRewardHook = true
        if card.HookScript then
            card:HookScript("OnEnter", function(self)
                skinLegacyRewardCard(self)
                local legacy = _G.LegacySystemFrame
                local page = type(legacy) == "table" and legacy.RewardTrackPage
                local track = type(page) == "table" and page.LegacyRewardProgressFrame
                if type(track) == "table" then scanLegacyRewardArt(track, 1) end
                if self.fuiPanel then self.fuiPanel.bright = true; ns.PaintPanel(self) end
            end)
            card:HookScript("OnLeave", function(self)
                skinLegacyRewardCard(self)
                if self.fuiPanel then self.fuiPanel.bright = false; ns.PaintPanel(self) end
            end)
        end
        -- The reward track reapplies native art and alpha while scrolling and
        -- hovering, so strip its card art again after those updates.
        for _, method in ipairs({ "ApplyAlpha", "Refresh" }) do
            if type(card[method]) == "function" then hooksecurefunc(card, method, skinLegacyRewardCard) end
        end
    end
end

local function legacyRewardCards(page)
    local progress = type(page) == "table" and page.LegacyRewardProgressFrame
    if type(progress) ~= "table" or type(progress.GetElements) ~= "function" then return end
    scanLegacyRewardArt(progress, 1)
    local ok, elements = pcall(progress.GetElements, progress)
    if not ok or type(elements) ~= "table" then return end
    for _, card in ipairs(elements) do
        skinLegacyRewardCard(card)
    end
end

-- Camelot adds a wide amber backing to each square Legacy rank label.  It is
-- an unnamed region on the node, so remove that atlas only, not the node's
-- state borders, icon, rank text, or the connecting arrows.
local function skinLegacyNode(button)
    if type(button) ~= "table" or type(button.GetRegions) ~= "function" then return end
    for _, region in ipairs({ button:GetRegions() }) do
        if region.IsObjectType and region:IsObjectType("Texture") and region.GetAtlas then
            local ok, atlas = pcall(region.GetAtlas, region)
            if ok and type(atlas) == "string" and atlas:lower() == "talents-square-box-c60" then
                fade(region)
            end
        end
    end
end

local function skinLegacyTreeNodes(panel)
    if type(panel) ~= "table" then return end
    if type(panel.EnumerateAllTalentButtons) == "function" then
        for button in panel:EnumerateAllTalentButtons() do skinLegacyNode(button) end
    end
    if not panel.fuiLegacyNodeHook and type(panel.RegisterCallback) == "function" then
        panel.fuiLegacyNodeHook = true
        panel:RegisterCallback("TalentButtonAcquired", function(_, button) skinLegacyNode(button) end, panel)
    end
end

local function skinLegacy(frame)
    if type(frame) ~= "table" then return end
    local function surface(part)
        if type(part) ~= "table" then return end
        for _, key in ipairs({ "Background", "BackgroundArt", "BackgroundTexture", "ClassBackground",
            "TreeBackground", "BackgroundBorder", "OverlayBackgroundLeft", "OverlayBackgroundMid",
            "OverlayBackgroundRight", "Clouds1", "Clouds2", "AirParticlesClose", "AirParticlesFar" }) do
            fade(part[key])
        end
        -- Some clients expose backdrop textures only as regions rather than
        -- named fields. Restrict this to explicitly named background art.
        if part.GetRegions then
            for _, region in ipairs({ part:GetRegions() }) do
                if region.IsObjectType and region:IsObjectType("Texture") and region.GetAtlas then
                    local ok, atlas = pcall(region.GetAtlas, region)
                    if ok and type(atlas) == "string" and atlas:lower():find("background", 1, true) then
                        fade(region)
                    end
                end
            end
        end
        local tabs = part.TabSystem
        if type(tabs) == "table" then
            for _, tab in ipairs(type(tabs.tabs) == "table" and tabs.tabs or {}) do skinTab(tab) end
        end
        for _, tab in ipairs(type(part.Tabs) == "table" and part.Tabs or {}) do skinTab(tab) end
        for _, key in ipairs({ "ApplyButton", "ApplyChangesButton", "CommitButton" }) do
            local button = part[key]
            if type(button) == "table" then
                skinButton(button)
                local glow = button.YellowGlow
                if type(glow) == "table" then fade(glow); fade(glow.Left); fade(glow.Middle); fade(glow.Right) end
            end
        end
        if type(part.ScrollBar) == "table" then skinScrollBar(part.ScrollBar) end
    end
    surface(frame)
    local title = type(frame.TitleContainer) == "table" and frame.TitleContainer.TitleText
        or _G.LegacySystemFrameTitleText
    if type(title) == "table" and title.ClearAllPoints and title.SetPoint then
        title:ClearAllPoints()
        title:SetPoint("CENTER", frame, "TOP", 0, -11)
        if title.SetJustifyH then title:SetJustifyH("CENTER") end
    end
    for i, icon in ipairs({ "legacy-minimal", "quests-minimal", "talents-minimal" }) do
        local tab = type(frame.Tabs) == "table" and frame.Tabs[i]
        if type(tab) == "table" and tab.CreateTexture then
            fade(tab.Background); fade(tab.SelectedTexture); fade(tab.HighlightTexture); fade(tab.Icon)
            if not tab.fuiPanel then ns.Panel(tab, { alpha = 0.9 }) end
            if not tab.fuiLegacyIcon then
                local art = tab:CreateTexture(nil, "OVERLAY", nil, 7)
                art:SetSize(30, 30); art:SetPoint("CENTER", tab, "CENTER", 0, 0)
                art:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\" .. icon)
                tab.fuiLegacyIcon = art
            end
            if tab.fuiPanel then
                tab.fuiPanel.bright = frame.currentPage == i
                ns.PaintPanel(tab)
            end
        end
    end
    for _, key in ipairs({ "RewardTrackPage", "TreePage", "ChallengesPage" }) do
        local page = frame[key]
        if type(page) == "table" then
            surface(page)
            surface(page.LegacyTreeTraitPanel)
            skinLegacyTreeNodes(page.LegacyTreeTraitPanel)
            local divider = page.VerticalDivider
            if type(divider) == "table" and divider.CreateTexture then
                if not divider.fuiLegacyDivider then
                    fadeNativeTextures(divider)
                    local line = divider:CreateTexture(nil, "OVERLAY")
                    line:SetPoint("TOP", divider, "TOP", 0, 0)
                    line:SetPoint("BOTTOM", divider, "BOTTOM", 0, 0)
                    line:SetWidth(1)
                    line:SetColorTexture(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], 0.55)
                    divider.fuiLegacyDivider = line
                end
            end
            local summary = page.LegacyTreePointSummary
            if type(summary) == "table" then fade(summary.Border); skinLegacyShield(summary.Shield) end
            local challengeSummary = page.LegacyChallengePointSummary
            if type(challengeSummary) == "table" then skinLegacyShield(challengeSummary.Shield) end
            local selection = page.LegacyTreeSelectionPanel
            if type(selection) == "table" then
                for _, button in ipairs(type(selection.treeButtons) == "table" and selection.treeButtons or {}) do
                    if type(button) == "table" and button.CreateTexture then
                        fade(button.Background); fade(button.SelectedGlow); fade(button.Ring); fade(button.RingTexture)
                        if not button.fuiPanel then ns.Panel(button, { alpha = 0.8, edge = 0.65 }) end
                        if button.fuiPanel and type(button.GetChecked) == "function" then
                            button.fuiPanel.bright = button:GetChecked() and true or false
                            ns.PaintPanel(button)
                        end
                    end
                end
                if not selection.fuiLegacyHook then
                    selection.fuiLegacyHook = true
                    for _, method in ipairs({ "RefreshTreeButtons", "UpdateSelection" }) do
                        if type(selection[method]) == "function" then
                            hooksecurefunc(selection, method, function() skinLegacy(frame) end)
                        end
                    end
                end
            end
            for _, part in ipairs({ page.CategoryList, page.DetailPane, page.LegacyChallengePointSummary }) do
                if type(part) == "table" then surface(part) end
            end
            local detail = page.DetailPane
            local scroll = type(detail) == "table" and detail.ScrollBox
            if type(scroll) == "table" then
                local function prepareCard(card)
                    if type(card) ~= "table" then return end
                    legacyCard(card)
                    if not card.fuiLegacyRefreshHook then
                        card.fuiLegacyRefreshHook = true
                        for _, method in ipairs({ "RefreshStateArt", "Saturate", "Desaturate" }) do
                            if type(card[method]) == "function" then hooksecurefunc(card, method, legacyCard) end
                        end
                    end
                end
                if type(scroll.ForEachFrame) == "function" then scroll:ForEachFrame(prepareCard) end
                if not scroll.fuiLegacyHook and type(scroll.RegisterCallback) == "function"
                    and type(ScrollBoxListMixin) == "table" and type(ScrollBoxListMixin.Event) == "table"
                    and ScrollBoxListMixin.Event.OnInitializedFrame then
                    scroll.fuiLegacyHook = true
                    scroll:RegisterCallback(ScrollBoxListMixin.Event.OnInitializedFrame,
                        function(_, card) prepareCard(card) end, frame)
                end
            end
            local bar = page.LegacyRewardProgressBar
            if type(bar) == "table" then
                fade(page.ProgressBarBackground); fade(bar.ProgressBarFrame)
                if bar.SetStatusBarTexture then bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8") end
                if bar.SetStatusBarColor then bar:SetStatusBarColor(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], 0.85) end
                if bar.CreateTexture and not bar.fuiPanel then ns.Panel(bar, { noBg = true, edge = 0.65 }) end
            end
            if key == "RewardTrackPage" then
                local emblem, points = page.Icon, page.Points
                if type(emblem) == "table" and emblem.SetTexture then
                    emblem:SetTexture(LEGACY_POINT_ART)
                    if emblem.SetTexCoord then emblem:SetTexCoord(0, 1, 0, 1) end
                end
                if type(points) == "table" and type(emblem) == "table" and points.ClearAllPoints and points.SetPoint then
                    points:ClearAllPoints()
                    -- The crown occupies the top of the image; the middle
                    -- of the shield itself sits a little lower.
                    points:SetPoint("CENTER", emblem, "CENTER", -2, -13)
                    if points.SetJustifyH then points:SetJustifyH("CENTER") end
                end
            end
            legacyRewardCards(page)
            if key == "RewardTrackPage" and not page.fuiLegacyTrackHook then
                page.fuiLegacyTrackHook = true
                for _, method in ipairs({ "Refresh", "OnTrackUpdate" }) do
                    if type(page[method]) == "function" then
                        hooksecurefunc(page, method, function(self) legacyRewardCards(self) end)
                    end
                end
            end
            if page.HookScript and not page.fuiLegacyHook then
                page.fuiLegacyHook = true
                page:HookScript("OnShow", function() skinLegacy(frame) end)
            end
        end
    end
    if frame.HookScript and not frame.fuiLegacyHook then
        frame.fuiLegacyHook = true
        frame:HookScript("OnShow", function() skinLegacy(frame) end)
        if type(frame.SelectPage) == "function" then hooksecurefunc(frame, "SelectPage", function() skinLegacy(frame) end) end
    end
end

local function skinLootRow(row)
    if type(row) ~= "table" or not row.CreateTexture then return end
    fade(row.NameFrame)
    fade(row.BorderFrame)
    fade(row.QualityStripe)
    if not row.fuiPanel then ns.Panel(row, { alpha = 0.8, edge = 0.7 }) end
    if type(row.Item) == "table" and row.Item.CreateTexture and not row.Item.fuiLootEdge then
        -- Keep the native ItemButton normal texture: Blizzard uses it when
        -- updating loot quality and locked states.
        local edge = CreateFrame("Frame", nil, row.Item)
        edge:SetAllPoints(row.Item)
        edge:SetFrameLevel(row.Item:GetFrameLevel() + 2)
        ns.Panel(edge, { noBg = true, edge = 0.8 })
        row.Item.fuiLootEdge = edge
    end
end

local lootHooked = {}
local function skinLoot()
    local frame = _G.LootFrame
    if type(frame) ~= "table" then return end
    if frame.CreateTexture and not frame.fuiPanel then
        fade(frame.NineSlice)
        fade(frame.Background)
        fade(frame.Bg)
        ns.Panel(frame)
        skinClose(T(frame.CloseButton))
    end
    for _, mixin in ipairs({ _G.LootFrameElementMixin or false, _G.LootFrameItemElementMixin or false }) do
        if type(mixin) == "table" and type(mixin.Init) == "function" and not lootHooked[mixin] then
            lootHooked[mixin] = true
            hooksecurefunc(mixin, "Init", skinLootRow)
        end
    end
    local box = frame.ScrollBox
    if type(box) == "table" and type(box.ForEachFrame) == "function" then
        box:ForEachFrame(skinLootRow)
    end
end

local m = ns.Module("windows", "Windows", function(m)
    m.skinned = {}
    ns.On("LOOT_OPENED", function()
        skinLoot()
        if C_Timer and C_Timer.After then C_Timer.After(0, skinLoot) end
    end)
    ns.On("ADDON_LOADED", skinLoot)
    ns.On("MERCHANT_SHOW", function()
        skinMerchantItems()
        if C_Timer and C_Timer.After then C_Timer.After(0, skinMerchantItems) end
    end)
    ns.OnOptional("MERCHANT_UPDATE", function() ns.WhenSafe(skinMerchantItems) end)
    for _, event in ipairs({ "UPDATE_FACTION", "SKILL_LINES_CHANGED", "UNIT_PET" }) do
        ns.OnOptional(event, function() ns.WhenSafe(skinCharacterBars) end)
    end
    skinLoot()
    skinEquipment()
    for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }) do
        ns.OnOptional(event, function() if CharacterFrame and CharacterFrame:IsShown() then skinEquipment() end end)
    end
    if type(CharacterFrame) == "table" and CharacterFrame.HookScript then
        CharacterFrame:HookScript("OnShow", skinEquipment)
        CharacterFrame:HookScript("OnShow", skinCharacterTabs)
        CharacterFrame:HookScript("OnShow", skinCharacterSurface)
        CharacterFrame:HookScript("OnShow", updatePvpDivider)
        CharacterFrame:HookScript("OnShow", skinCharacterBars)
        if type(CharacterFrame.ShowSubFrame) == "function" then
            hooksecurefunc(CharacterFrame, "ShowSubFrame", updatePvpDivider)
            hooksecurefunc(CharacterFrame, "ShowSubFrame", skinCharacterBars)
        end
    end
    if type(PaperDollFrame_ShowSidebar) == "function" then
        hooksecurefunc("PaperDollFrame_ShowSidebar", function() ns.WhenSafe(skinCharacterBars) end)
    end
    local function try(name)
        local f = _G[name]
        local opts = type(WINDOWS[name]) == "table" and WINDOWS[name] or nil
        if opts and opts.part then
            f = type(f) == "table" and f[opts.part] or nil
        end
        if skinWindow(f, opts) then
            table.insert(m.skinned, f)
        end
        if name == "ProfessionsBookFrame" and type(f) == "table" then
            fade(_G.ProfessionsBookPage1); fade(_G.ProfessionsBookPage2)
            skinProfessionBook(f)
        elseif name == "ProfessionsFrame" and type(f) == "table" then
            skinProfessions(f)
            if f.HookScript and not f.fuiProfessionsHook then
                f.fuiProfessionsHook = true
                f:HookScript("OnShow", skinProfessions)
            end
        elseif name == "PlayerSpellsFrame" and type(f) == "table" then
            skinSpellBook(f)
            skinTalentPage(f)
        elseif name == "LegacySystemFrame" and type(f) == "table" then
            skinLegacy(f)
        elseif name == "CollectionsJournal" and type(f) == "table" then
            skinCollections()
        end
        -- the quest log's buttons and scroll bars, beside the map
        local also = opts and opts.also and _G[opts.also]
        if type(also) == "table" and also.HookScript then
            walk(also, 1)
            also:HookScript("OnShow", function(self) walk(self, 1) end)
        end
    end
    local byAddon = {}
    for name, spec in pairs(WINDOWS) do
        local addon = type(spec) == "table" and spec.addon or spec
        if addon then
            byAddon[addon] = byAddon[addon] or {}
            table.insert(byAddon[addon], name)
        else
            try(name)
        end
    end
    for addon, names in pairs(byAddon) do
        ns.AfterBlizzard(addon, function()
            for _, name in ipairs(names) do
                try(name)
            end
        end)
    end
    skinCharacterTabs()
    skinCharacterSurface()
    updatePvpDivider()
    if type(PaperDollFrame_UpdateSidebarTabs) == "function" then
        hooksecurefunc("PaperDollFrame_UpdateSidebarTabs", skinCharacterTabs)
    end
    if type(SetPaperDollBackground) == "function" then
        hooksecurefunc("SetPaperDollBackground", hideCharacterModelBackground)
    end
    if type(PaperDollItemSlotButton_OnShow) == "function" then
        hooksecurefunc("PaperDollItemSlotButton_OnShow", skinEquipment)
    end
    if type(PaperDollItemSlotButton_Update) == "function" then
        hooksecurefunc("PaperDollItemSlotButton_Update", function(button)
            if type(button) ~= "table" or not button.fuiEquipmentEdge then return end
            if type(button.GetNormalTexture) == "function" then fade(button:GetNormalTexture()) end
            if type(button.GetName) == "function" then
                local name = button:GetName()
                if type(name) == "string" then fade(_G[name .. "Frame"]) end
            end
            fade(button.Frame)
            fade(button.BorderFrame)
            fade(button.IconBorder)
            updateEquipmentQuality(button)
        end)
    end
    -- and any other standard window the game opens (trainers, the bank,
    -- the auction house...): if it has the usual frame, it gets the look
    if ShowUIPanel then
        hooksecurefunc("ShowUIPanel", function(f)
            if type(f) == "table" and not done[f] and T(f.NineSlice) and (T(f.PortraitContainer) or T(f.TitleContainer)) then
                local function skin()
                    if done[f] then return end
                    local ok, err = pcall(function()
                        if skinWindow(f) then
                            table.insert(m.skinned, f)
                        end
                    end)
                    if not ok then
                        ns.Err("window", err)
                    end
                end
                -- a protected window opened mid-fight: re-anchoring its parts
                -- would be blocked, so it gets the look once combat ends
                local protected = f.IsProtected and f:IsProtected()
                if protected and InCombatLockdown and InCombatLockdown() then ns.WhenSafe(skin) else skin() end
            end
        end)
    end
    -- the old tab kind keeps its look in step with which tab is open
    for _, fn in ipairs({ "PanelTemplates_SelectTab", "PanelTemplates_DeselectTab" }) do
        if _G[fn] then
            hooksecurefunc(fn, function(tab)
                if type(tab) == "table" and done[tab] then
                    tabState(tab)
                end
            end)
        end
    end
end)

function m:Restyle()
    for _, f in ipairs(self.skinned or {}) do
        if f.fuiRule then
            f.fuiRule:SetColorTexture(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], ns.EdgeAlpha() * 0.6)
        end
    end
end

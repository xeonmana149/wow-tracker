-- The bits of the game's HUD Forever UI touches, on top of Forever Gold's mock.
local M = MOCK
M.knownEvents.BANKFRAME_OPENED = true
M.knownEvents.BANKFRAME_CLOSED = true
M.knownEvents.UPDATE_MOUSEOVER_UNIT = true
M.knownEvents.QUEST_DETAIL = true
M.knownEvents.QUEST_PROGRESS = true
M.knownEvents.TRAINER_SHOW = true
M.knownEvents.TRAINER_UPDATE = true
M.knownEvents.TRAINER_CLOSED = true
M.knownEvents.MERCHANT_UPDATE = true
M.knownEvents.CRAFT_SHOW = true
M.knownEvents.CRAFT_UPDATE = true
M.knownEvents.GOSSIP_SHOW = true
M.knownEvents.QUEST_GREETING = true
M.cvars = { nameplateShowEnemies = "1", nameplateShowFriends = "0", nameplateMotion = "1", nameplateGlobalScale = "1" }
C_CVar = {
    GetCVar = function(name) return M.cvars[name] end,
    GetCVarBool = function(name) local value = M.cvars[name]; if value ~= nil then return value ~= "0" end end,
    SetCVar = function(name, value) M.cvars[name] = tostring(value) end,
}
EventRegistry = { callbacks = {} }
function EventRegistry:RegisterCallback(name, fn, owner)
    local previous = self.callbacks[name]
    self.callbacks[name] = function(...)
        if previous then previous(...) end
        fn(owner, ...)
    end
end
for _, e in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION",
    "PLAYER_UPDATE_RESTING", "UPDATE_FACTION", "PLAYER_ENTERING_WORLD", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED", "QUEST_LOG_UPDATE", "QUEST_DATA_LOAD_RESULT",
    "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "UPDATE_PENDING_MAIL",
    "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_PET", "GROUP_ROSTER_UPDATE", "SPELLS_CHANGED", "UNIT_AURA",
    "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION", "UNIT_NAME_UPDATE", "UNIT_CONNECTION", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE", "UNIT_FLAGS", "PLAYER_ROLES_ASSIGNED",
    "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "INCOMING_RESURRECT_CHANGED", "UNIT_TARGET",
    "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED" }) do
    M.knownEvents[e] = true
end
for _, e in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_FRIEND_INFO_CHANGED", "BN_CONNECTED" }) do M.knownEvents[e] = true end
C_FriendList = { GetNumOnlineFriends = function() return M.onlineFriends or 0 end }
function BNGetNumFriends() return 10, M.onlineBnet or 0 end
function ToggleGuildFrame() M.guildToggleCount = (M.guildToggleCount or 0) + 1 end
function UnitPowerType() return 3, "ENERGY" end
PowerBarColor = { ENERGY = { r = 1, g = 0.85, b = 0.1 } }
function UnitFrameManaBar_UpdateType(bar)
    bar:SetStatusBarTexture("native-power")
    bar:SetStatusBarColor(1, 1, 1)
end
function UnitFrameHealthBar_Update(bar)
    bar:SetStatusBarColor(1, 1, 1)
end

UIParent._w, UIParent._h = 1920, 1080

M.xp = { cur = 12450, max = 31200, rested = 8200 }
function UnitXP() return M.xp.cur end
function UnitXPMax() return M.xp.max end
function GetXPExhaustion() return M.xp.rested end
function IsXPUserDisabled() return false end
GameRulesUtil = { IsPlayerAtEffectiveMaxLevel = function() return M.player.level >= 60 end }
M.watched = nil
C_Reputation = { GetWatchedFactionData = function() return M.watched end }
FACTION_BAR_COLORS = { [5] = { r = 0, g = 0.6, b = 0.1 } }
FACTION_STANDING_LABEL5 = "Friendly"

StatusTrackingBarManager = CreateFrame("Frame", "StatusTrackingBarManager", UIParent)
MicroMenuContainer = CreateFrame("Frame", "MicroMenuContainer", UIParent)
MicroMenu = CreateFrame("Frame", "MicroMenu", MicroMenuContainer)
MicroMenu.BorderArt = MicroMenu:CreateTexture()
MicroMenu.BackgroundArt = MicroMenu:CreateTexture()
GameMenuFrame = CreateFrame("Frame", "GameMenuFrame", UIParent)
GameMenuFrame:Hide()
for _, name in ipairs({ "CharacterMicroButton", "SpellbookMicroButton", "ProfessionMicroButton", "TalentMicroButton",
    "QuestLogMicroButton", "QuickJoinToastButton", "GuildMicroButton", "LFDMicroButton", "LegacyMicroButton",
    "CollectionsMicroButton", "StoreMicroButton" }) do
    local button = CreateFrame("Button", name, MicroMenu)
    button.IsEnabled = function(self) return self._enabled ~= false end
end
BagsBar = CreateFrame("Frame", "BagsBar", UIParent)
for _, n in ipairs({ "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
    "CharacterBag3Slot", "CharacterReagentBag0Slot" }) do
    local b = CreateFrame("ItemButton", n, BagsBar)
    b.IsEnabled = function(self) return self._enabled ~= false end
    b.icon = b:CreateTexture()
    b._normal = b:CreateTexture()
    b.GetNormalTexture = function(self) return self._normal end
end

MinimapCluster = CreateFrame("Frame", "MinimapCluster", UIParent)
MinimapCluster.UpdateMinimapConfig = function() Minimap:SetMaskTexture("ui-hud-minimap-frame-generic-mask") end
Minimap = CreateFrame("Frame", "Minimap", MinimapCluster)
MinimapBackdrop = CreateFrame("Frame", "MinimapBackdrop", Minimap)
MinimapCompassTexture = MinimapBackdrop:CreateTexture()
MinimapCompassTextureUnderlay = MinimapBackdrop:CreateTexture()
Minimap._zoom = 0
function Minimap:SetMaskTexture(t) self._mask = t end
function Minimap:GetZoom() return self._zoom end
function Minimap:SetZoom(z) self._zoom = z end
function Minimap:GetZoomLevels() return 6 end
-- two addons' minimap buttons, and one of the game's own
local function addonButton(name)
    local b = CreateFrame("Button", name, Minimap)
    b._w, b._h = 31, 31
    b.IsObjectType = function(_, t) return t == "Button" end
    b.GetName = function() return name end
    b:SetScript("OnClick", function() end)
    return b
end
M.lib1 = addonButton("LibDBIcon10_Questie")
M.lib2 = addonButton("ForeverGoldMinimapButton")
M.gameBtn = addonButton("MinimapZoomIn")
M.forbidden = addonButton("ForbiddenMinimapButton")
M.forbidden.IsForbidden = function() return true end
M.forbidden.GetName = function() error("attempt to access forbidden object") end
function Minimap:GetChildren() return MinimapBackdrop, M.lib1, M.lib2, M.gameBtn, M.forbidden end
function GetMinimapZoneText() return "Westfall" end
M.mail = false
function HasNewMail() return M.mail end
C_Map = C_Map or {}
C_Map.GetBestMapForUnit = function() return 1436 end
C_Map.GetPlayerMapPosition = function() return { x = 0.524, y = 0.471 } end

-- action bars: two buttons on the main bar, one pet button
MainActionBar = CreateFrame("Frame", "MainActionBar", UIParent)
MainActionBar.BorderArt = MainActionBar:CreateTexture()
MainActionBar.EndCaps = CreateFrame("Frame", nil, MainActionBar)
MainActionBar.UpdateDividers = function() end
local function actionButton(name)
    local b = CreateFrame("CheckButton", name, MainActionBar)
    b.icon = b:CreateTexture()
    b.IconMask = b:CreateTexture()
    b.SlotArt = b:CreateTexture()
    b.SlotBackground = b:CreateTexture()
    b.NormalTexture = b:CreateTexture()
    b.HotKey = b:CreateFontString()
    b.Count = b:CreateFontString()
    b.Name = b:CreateFontString()
    b.cooldown = CreateFrame("Cooldown", nil, b)
    b.UpdateButtonArt = function(self) self.SlotArt:SetAlpha(1) end
    b.SetTooltip = function(self) GameTooltip_SetDefaultAnchor(GameTooltip, self) end
    return b
end
actionButton("ActionButton1")
actionButton("ActionButton2")
actionButton("PetActionButton1")
MultiBarBottomLeft = CreateFrame("Frame", "MultiBarBottomLeft", UIParent)
actionButton("MultiBarBottomLeftButton1")
MultiBarBottomLeftButton1:SetSize(32, 32)
ActionButton1:SetSize(40, 40)
function ActionButton_UpdateRangeIndicator(self, checksRange, inRange) end

-- tooltips
function GameTooltip_SetDefaultAnchor(tt, parent) tt:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -13, 64) end
GameTooltip.NineSlice = { SetCenterColor = function(self, r, g, b, a) self.center = { r, g, b, a } end,
    SetBorderColor = function(self, r, g, b, a) self.border = { r, g, b, a } end }

-- OneForAll's badge: on the screen, anchored under the minimap
M.ofa = CreateFrame("Button", "OneForAllMinimapButton", UIParent)
M.ofa._w = 32
M.ofa.IsObjectType = function(_, t) return t == "Button" end
M.ofa.GetName = function() return "OneForAllMinimapButton" end
M.ofa:SetScript("OnClick", function() end)
M.ofa:SetPoint("TOP", Minimap, "BOTTOM", 0, -8)
function UIParent:GetChildren() return M.ofa end

-- the game's menu button, last on the micro menu
MainMenuMicroButton = CreateFrame("Button", "MainMenuMicroButton", MicroMenu)
MicroMenu.Layout = function(self) self._laidOut = (self._laidOut or 0) + 1 end
M.fps, M.ms = 60, 42
function GetFramerate() return M.fps + 0.4 end
function GetNetStats() return 0, 0, M.ms, M.ms - 4 end

-- the cast bar, as the game makes it
local function texWithBar(bar)
    bar.SetStatusBarTexture = function(self, t) self._fill = t end
    bar.SetStatusBarColor = function(self, r, g, b) self._fillColor = { r, g, b } end
    bar._tex = bar:CreateTexture()
    bar.GetStatusBarTexture = function(self) return self._tex end
end
PlayerCastingBarFrame = CreateFrame("StatusBar", "PlayerCastingBarFrame", UIParent)
texWithBar(PlayerCastingBarFrame)
for _, k in ipairs({ "Border", "TextBorder", "Background", "Flash", "Icon", "Spark" }) do
    PlayerCastingBarFrame[k] = PlayerCastingBarFrame:CreateTexture()
end
PlayerCastingBarFrame.Text = PlayerCastingBarFrame:CreateFontString()
PlayerCastingBarFrame.UpdateBarFillTexture = function(self)
    self:SetStatusBarTexture("ui-castingbar-filling-" .. (self.barType or "standard"))
end
-- A pet bar exists even when the optional overlay cast bar does not.
PetCastingBarFrame = CreateFrame("StatusBar", "PetCastingBarFrame", UIParent)
texWithBar(PetCastingBarFrame)
PetCastingBarFrame.Border = PetCastingBarFrame:CreateTexture()
PetCastingBarFrame.Icon = PetCastingBarFrame:CreateTexture()
PetCastingBarFrame.Text = PetCastingBarFrame:CreateFontString()

-- swing timers (their own addon)
M.loadedAddons = { Blizzard_SwingTimer = true }
C_AddOns = C_AddOns or {}
C_AddOns.IsAddOnLoaded = function(name) return M.loadedAddons[name] or false end
local function swingFrame(name, kind)
    local f = CreateFrame("Frame", name, UIParent)
    f.swingType = kind
    f.Background = f:CreateTexture()
    f.Border = f:CreateTexture()
    f.StatusBar = CreateFrame("StatusBar", nil, f)
    texWithBar(f.StatusBar)
    f.StatusBar.Pip = f.StatusBar:CreateTexture()
    f.StatusBar.TypeLabelShadow = f.StatusBar:CreateTexture()
    f.StatusBar.TypeLabel = f.StatusBar:CreateFontString()
    f.StatusBar.TimeLabel = f.StatusBar:CreateFontString()
    f.InitializeBarPresentation = function(self) self.StatusBar:SetStatusBarTexture("ui-swingtimerbar-filling") end
    f.out = false
    f.IsOutOfRange = function(self) return self.out end
    f.ApplyRangePresentation = function(self) self.Border:SetAlpha(self.out and 0.5 or 1) end
    return f
end
swingFrame("SwingTimerMainHandFrame", 0)
swingFrame("SwingTimerOffHandFrame", 1)
swingFrame("SwingTimerRangedFrame", 2)

-- buffs and debuffs: two icons each, plus a private aura anchor
local function auraButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b.Icon = b:CreateTexture()
    b.DebuffBorder = b:CreateTexture()
    b.TempEnchantBorder = b:CreateTexture()
    b.Duration = b:CreateFontString()
    b.Count = b:CreateFontString()
    b.UpdateAuraType = function(self, t) self.auraType = t end
    return b
end
BuffFrame = CreateFrame("Frame", "BuffFrame", UIParent)
BuffFrame.auraFrames = { auraButton(BuffFrame), auraButton(BuffFrame), CreateFrame("Frame", nil, BuffFrame) }
BuffFrame.auraFrames[2].auraType = "TempEnchant"
BuffFrame.UpdateAuraButtons = function() end
DebuffFrame = CreateFrame("Frame", "DebuffFrame", UIParent)
DebuffFrame.auraFrames = { auraButton(DebuffFrame) }
DebuffFrame.UpdateAuraButtons = function() end

-- the damage meter (its own addon, loaded after us)
ScrollUtil = { AddAcquiredFrameCallback = function(box, cb, owner, existing)
    box._acquired = box._acquired or {}
    table.insert(box._acquired, cb)
end }
local function meterEntry(parent)
    local e = CreateFrame("Button", nil, parent)
    e.StatusBar = CreateFrame("StatusBar", nil, e)
    texWithBar(e.StatusBar)
    e.StatusBar.Background = e.StatusBar:CreateTexture()
    e.StatusBar.BackgroundEdge = e.StatusBar:CreateTexture()
    e.StatusBar.Name = e.StatusBar:CreateFontString()
    e.StatusBar.Value = e.StatusBar:CreateFontString()
    for _, text in ipairs({ e.StatusBar.Name, e.StatusBar.Value }) do
        text.GetFont = function(self) return self._font or "Fonts/Number.ttf", self._fontSize or 10, self._fontFlags or "OUTLINE" end
        text.SetFont = function(self, face, size, flags) self._font, self._fontSize, self._fontFlags = face, size, flags end
    end
    e.Icon = CreateFrame("Frame", nil, e)
    e.Icon.Icon = e.Icon:CreateTexture()
    e.SetupSharedStyleBackground = function(self) self.StatusBar.Background:SetAtlas("ui-damagemeters-bar-shadowbg") end
    return e
end
M.meterEntry = meterEntry
function M.loadMeter()
    M.instanceKind, M.instanceID = nil, nil
    function IsInInstance() return M.instanceKind ~= nil, M.instanceKind or "none" end
    function GetInstanceInfo() return "Test", M.instanceKind, 1, "Normal", 5, 0, false, M.instanceID end
    Enum.DamageMeterType = { DamageDone = 1 }
    DamageMeter = CreateFrame("Frame", "DamageMeter", UIParent)
    C_DamageMeter = { ResetAllCombatSessions = function() M.meterResetCount = (M.meterResetCount or 0) + 1 end }
    DamageMeter.windowDataList = {}
    DamageMeter.GetPrimarySessionWindow = function(self)
        return self.windowDataList[1] and self.windowDataList[1].sessionWindow
    end
    DamageMeter.SetSessionWindowDamageMeterType = function(self, window, kind) window.testMeterType = kind end
    DamageMeter.SetSessionWindowMinimized = function(self, window, minimized) window:SetMinimized(minimized) end
    DamageMeter.ForEachSessionWindow = function(self, fn)
        for _, d in pairs(self.windowDataList) do if d.sessionWindow then fn(d.sessionWindow) end end
    end
    DamageMeter.SetupSessionWindow = function(self, index, data)
        local w = data.sessionWindow or CreateFrame("Frame", "DamageMeterSessionWindow" .. index, self)
        data.sessionWindow = w
        w.Header = w:CreateTexture()
        w.GetSessionWindowIndex = function() return index end
        w.SetMinimized = function(self, minimized) self.minimized = minimized end
        w.IsMinimized = function(self) return self.minimized end
        w.DamageMeterTypeDropdown = CreateFrame("Button", nil, w)
        w.SessionDropdown = CreateFrame("Button", nil, w)
        w.SessionDropdown.Background = w.SessionDropdown:CreateTexture()
        w.SessionDropdown.Text = w.SessionDropdown:CreateFontString()
        w.SessionDropdown.SessionName = w.SessionDropdown:CreateFontString()
        w.SettingsDropdown = CreateFrame("Button", nil, w)
        w.SettingsDropdown.Icon = w.SettingsDropdown:CreateTexture()
        w.MinimizeButton = CreateFrame("Button", nil, w)
        w.MinimizeContainer = CreateFrame("Frame", nil, w)
        w.MinimizeContainer.Background = w.MinimizeContainer:CreateTexture()
        w.MinimizeContainer.SourceWindow = CreateFrame("Frame", nil, w.MinimizeContainer)
        local source = w.MinimizeContainer.SourceWindow
        source.Background = source:CreateTexture()
        source.ScrollBox = CreateFrame("Frame", nil, source)
        w.box = CreateFrame("Frame", nil, w.MinimizeContainer)
        w.GetScrollBox = function(s) return s.box end
        self.windowDataList[index] = data
    end
    M.loadedAddons.Blizzard_DamageMeter = true
    M.fire("ADDON_LOADED", "Blizzard_DamageMeter")
end

-- a window as the game builds one: border, portrait, backdrop, inset,
-- tabs, close button, a panel button, a dropdown, a scroll bar
local function closeButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b.SetNormalAtlas = function(self, atlas) self._normalAtlas = atlas end
    b.SetPushedAtlas = function(self, atlas) self._pushedAtlas = atlas end
    b.SetDisabledAtlas = function(self, atlas) self._disabledAtlas = atlas end
    b.SetHighlightAtlas = function(self, atlas) self._highlightAtlas = atlas end
    for _, k in ipairs({ "_n", "_p", "_d", "_h" }) do b[k] = b:CreateTexture() end
    b.GetNormalTexture = function(s) return s._n end
    b.GetPushedTexture = function(s) return s._p end
    b.GetDisabledTexture = function(s) return s._d end
    b.GetHighlightTexture = function(s) return s._h end
    return b
end
local function tabButton(name, parent)
    local t = CreateFrame("Button", name, parent)
    for _, k in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive" }) do
        t[k] = t:CreateTexture()
    end
    t.Text = t:CreateFontString()
    return t
end
function M.window(name)
    local f = CreateFrame("Frame", name, UIParent)
    f.NineSlice = CreateFrame("Frame", nil, f)
    f.PortraitContainer = CreateFrame("Frame", nil, f)
    f.Bg = f:CreateTexture()
    f.TopTileStreaks = f:CreateTexture()
    f.TitleContainer = CreateFrame("Frame", nil, f)
    f.TitleContainer.TitleText = f.TitleContainer:CreateFontString()
    f.CloseButton = closeButton(f)
    f.Inset = CreateFrame("Frame", nil, f)
    f.Inset.Bg = f.Inset:CreateTexture()
    f.Inset.NineSlice = CreateFrame("Frame", nil, f.Inset)
    local t1, t2 = tabButton(name .. "Tab1", f), tabButton(name .. "Tab2", f)
    t1.LeftActive:Show(); t2.LeftActive:Hide()
    local btn = CreateFrame("Button", nil, f.Inset)
    btn.Left, btn.Middle, btn.Right = btn:CreateTexture(), btn:CreateTexture(), btn:CreateTexture()
    local dd = CreateFrame("Frame", nil, f)
    dd.Arrow, dd.Background, dd.Text = dd:CreateTexture(), dd:CreateTexture(), dd:CreateFontString()
    local sb = CreateFrame("Frame", nil, f.Inset)
    sb.Track = CreateFrame("Frame", nil, sb)
    sb.Track.Thumb = CreateFrame("Button", nil, sb.Track)
    sb.Track.Begin = sb.Track:CreateTexture()
    sb.Track.Thumb.Middle = sb.Track.Thumb:CreateTexture()
    f._kids = { f.NineSlice, f.PortraitContainer, f.TitleContainer, f.CloseButton, f.Inset, t1, t2, dd }
    f.GetChildren = function(s) return unpack(s._kids) end
    f.Inset.GetChildren = function() return f.Inset.NineSlice, btn, sb end
    f.parts = { tab1 = t1, tab2 = t2, button = btn, dropdown = dd, scroll = sb }
    return f
end
M.window("CharacterFrame")
CharacterFrame.UpdateSize = function(self) self:SetWidth(500) end
CharacterFrame.ShowSubFrame = function(self, name) self.activeSubframe = name end
CharacterFrame.SetTitle = function(self, title) self._title = title end
CharacterFrame.UpdateTitle = function(self) self:SetTitle(self.activeSubframe == "PaperDollFrame" and "Xeon" or "Reputation") end
CharacterFrame.Background = CharacterFrame:CreateTexture()
CharacterFrame.LeftPaneHost = CreateFrame("Frame", nil, CharacterFrame)
CharacterFrame.LeftPaneHost.art = CharacterFrame.LeftPaneHost:CreateTexture()
CharacterFrame.LeftPaneHost.art.IsObjectType = function(_, kind) return kind == "Texture" end
CharacterFrame.LeftPaneHost.GetRegions = function(self) return self.art end
CharacterFrame.RightPaneHost = CreateFrame("Frame", nil, CharacterFrame)
CharacterFrame.RightPaneHost.StoneBg = CharacterFrame.RightPaneHost:CreateTexture()
CharacterFrame.RightPaneHost.StoneBg.IsObjectType = function(_, kind) return kind == "Texture" end
CharacterFrame.RightPaneHost.GetRegions = function(self) return self.StoneBg end
M.characterDivider = CreateFrame("Frame", nil, CharacterFrame.RightPaneHost)
M.characterDivider.art = M.characterDivider:CreateTexture()
M.characterDivider.art.GetAtlas = function() return "common-framedivider" end
M.characterDivider.GetRegions = function(self) return self.art end
CharacterFrame.RightPaneHost.GetChildren = function() return M.characterDivider end
PaperDollFrame = CreateFrame("Frame", "PaperDollFrame", CharacterFrame)
PaperDollLevelInfo = CreateFrame("Frame", "PaperDollLevelInfo", PaperDollFrame)
CharacterModelScene = CreateFrame("Frame", "CharacterModelScene", PaperDollFrame)
CharacterModelScene.BackgroundOverlay = CharacterModelScene:CreateTexture()
function SetPaperDollBackground(model) model.BackgroundOverlay:SetAlpha(0.8) end
PaperDollFrame.TopBackgroundStripHost = CreateFrame("Frame", nil, PaperDollFrame)
PaperDollFrame.TopBackgroundStripHost.TopBackgroundStrip = PaperDollFrame.TopBackgroundStripHost:CreateTexture()
PaperDollFrame.TopBackgroundStripHost.TopBackgroundStripBottomEdge = PaperDollFrame.TopBackgroundStripHost:CreateTexture()
CharacterFrameTab1.Icon = CharacterFrameTab1:CreateTexture()
CharacterFrameTab1.Icon.IsObjectType = function(_, kind) return kind == "Texture" end
CharacterFrameTab1.GetRegions = function(self) return self.Icon, self.fuiCharacterIcon end
CharacterModelFrameBackgroundTopLeft = CharacterFrame:CreateTexture()
for i = 3, 6 do tabButton("CharacterFrameTab" .. i, CharacterFrame) end
for i = 1, 3 do
    local tab = CreateFrame("Button", "PaperDollSidebarTab" .. i, CharacterFrame)
    tab.Icon, tab.TabBg, tab.Hider, tab.Highlight = tab:CreateTexture(), tab:CreateTexture(), tab:CreateTexture(), tab:CreateTexture()
end
CharacterHeadSlot = CreateFrame("Button", "CharacterHeadSlot", CharacterFrame)
CharacterHeadSlot.BorderFrame = CreateFrame("Frame", nil, CharacterHeadSlot)
CharacterHeadSlotFrame = CharacterHeadSlot:CreateTexture()
CharacterHeadSlot.icon = CharacterHeadSlot:CreateTexture()
CharacterHeadSlot._normal = CharacterHeadSlot:CreateTexture()
CharacterHeadSlot.GetNormalTexture = function(self)
    if self._normal:GetParent() == self then return self._normal end
end
CharacterFinger0Slot = CreateFrame("Button", "CharacterFinger0Slot", CharacterFrame)
CharacterFinger0SlotFrame = CharacterFinger0Slot:CreateTexture()
CharacterFinger0Slot.GetNormalTexture = function(self)
    if CharacterFinger0SlotFrame:GetParent() == self then return CharacterFinger0SlotFrame end
end
function PaperDollItemSlotButton_Update(button)
    local normal = button:GetNormalTexture()
    assert(normal, "game requires the button's normal texture")
    normal:SetAlpha(1)
end
NUM_CHAT_WINDOWS = 2
GameFontHighlightSmall = { GetFont = function() return "Fonts/ForeverUITest.ttf", 10, "" end }
ChatFontNormal = { GetFont = function() return "Fonts/ChatNormal.ttf", 12, "" end }
ChatFrame1 = CreateFrame("Frame", "ChatFrame1", UIParent)
ChatFrame1.GetFont = function(self) return self._font or "Fonts/Chat.ttf", self._fontSize or 16, "OUTLINE" end
ChatFrame1.SetFont = function(self, face, size, flags) self._font, self._fontSize, self._fontFlags = face, size, flags end
ChatFrame1.Background = ChatFrame1:CreateTexture()
ChatFrame1.ScrollBar = CreateFrame("Frame", nil, ChatFrame1)
ChatFrame1.ScrollBar.Track = CreateFrame("Frame", nil, ChatFrame1.ScrollBar)
ChatFrame1.ScrollBar.Track.Thumb = CreateFrame("Frame", nil, ChatFrame1.ScrollBar.Track)
ChatFrame1.ScrollBar.Track.Thumb.Middle = ChatFrame1.ScrollBar.Track.Thumb:CreateTexture()
ChatFrame1.ScrollBar.Back = CreateFrame("Button", nil, ChatFrame1.ScrollBar)
ChatFrame1.ScrollBar.Back.Texture = ChatFrame1.ScrollBar.Back:CreateTexture()
ChatFrame1.ScrollBar.Back.Texture.SetVertexColor = function(self, r, g, b, a) self._tint = { r, g, b, a } end
ChatFrame1.ScrollBar.Forward = CreateFrame("Button", nil, ChatFrame1.ScrollBar)
ChatFrame1.ScrollBar.Forward.Texture = ChatFrame1.ScrollBar.Forward:CreateTexture()
ChatFrame1.ScrollBar.Forward.Texture.SetVertexColor = function(self, r, g, b, a) self._tint = { r, g, b, a } end
ChatFrame1.ScrollToBottomButton = CreateFrame("Button", nil, ChatFrame1)
ChatFrame1.ScrollToBottomButton._normal = ChatFrame1.ScrollToBottomButton:CreateTexture()
ChatFrame1.ScrollToBottomButton.GetNormalTexture = function(self) return self._normal end
ChatFrame1.buttonFrame = CreateFrame("Frame", nil, ChatFrame1)
ChatFrame1.buttonFrame.Background = ChatFrame1.buttonFrame:CreateTexture()
M.copyChatButton = CreateFrame("Button", nil, ChatFrame1)
M.copyChatButton.IsObjectType = function(_, kind) return kind == "Button" end
M.copyChatButton.GetName = function() return nil end
M.copyChatButton:SetSize(18, 18)
M.copyChatButton:SetPoint("TOPRIGHT", ChatFrame1, "TOPRIGHT", 2, 2)
ChatFrame1.GetChildren = function() return M.copyChatButton end
ChatFrame1Tab = CreateFrame("Button", "ChatFrame1Tab", UIParent)
ChatFrame1EditBox = CreateFrame("EditBox", "ChatFrame1EditBox", UIParent)
ChatFrame1EditBox.GetFont = function(self) return self._font or "Fonts/Chat.ttf", self._fontSize or 14, "" end
ChatFrame1EditBox.SetFont = function(self, face, size, flags) self._font, self._fontSize, self._fontFlags = face, size, flags end
ChatFrame1Tab.Left = ChatFrame1Tab:CreateTexture()
ChatFrame1Tab.Left:SetTexture("old-tab-art")
ChatFrame1EditBox.Left = ChatFrame1EditBox:CreateTexture()
ChatFrame1EditBox.Left:SetTexture("old-input-art")
ChatFrameMenuButton = CreateFrame("Button", "ChatFrameMenuButton", UIParent)
ChatFrameChannelButton = CreateFrame("Button", "ChatFrameChannelButton", UIParent)
TextToSpeechButton = CreateFrame("Button", "TextToSpeechButton", UIParent)
function PanelTemplates_SelectTab(tab) tab.LeftActive:Show() end
function PanelTemplates_DeselectTab(tab) tab.LeftActive:Hide() end
function ShowUIPanel(f) if f then f:Show() end end

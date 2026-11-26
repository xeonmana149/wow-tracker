-- Forever UI, start to finish in the mock client.
local M = MOCK
local ns = NS
local failed = 0
local function check(ok, what)
    M.realPrint((ok and "  ok   " or "  FAIL ") .. what)
    if not ok then failed = failed + 1 end
end
OneForAllDB = { qol = { copyChat = true, chatHide = true } }
do
local minimapRings = {}
for _, method in ipairs({ "SetQuestBlobRingAlpha", "SetQuestBlobRingScalar", "SetArchBlobRingAlpha", "SetArchBlobRingScalar" }) do
    Minimap[method] = function(_, value) minimapRings[method] = value end
end
M.fire("ADDON_LOADED", "ForeverUI")
M.fire("PLAYER_LOGIN")
M.fire("PLAYER_ENTERING_WORLD")
check(minimapRings.SetQuestBlobRingAlpha == 0 and minimapRings.SetQuestBlobRingScalar == 0
    and minimapRings.SetArchBlobRingAlpha == 0 and minimapRings.SetArchBlobRingScalar == 0,
    "the square minimap removes the round quest and archaeology ring artifacts")
MinimapCluster:UpdateMinimapConfig()
check(Minimap._mask == "Interface\\Buttons\\WHITE8X8" and minimapRings.SetQuestBlobRingAlpha == 0,
    "the square mask and ring fix survive a native minimap configuration update")
end
check(OneForAllDB.qol.chatHide == false, "OneForAll's chat hide button is disabled before its login setup")
do
    local previous, initialized = C_CVar, ns.db.unitStatusTextEnabled
    local values = {statusTextDisplay = "NONE", statusText = "0"}
    C_CVar = {GetCVar = function(key) return values[key] end, SetCVar = function(key, value) values[key] = value end}
    ns.db.unitStatusTextEnabled = nil
    ns.EnableUnitStatusTextOnce()
    check(values.statusTextDisplay == "NUMERIC" and values.statusText == "1",
        "player and target status text is enabled with native numeric values")
    values.statusTextDisplay = "PERCENT"
    ns.EnableUnitStatusTextOnce()
    check(values.statusTextDisplay == "PERCENT", "later changes to the game's status text setting are respected")
    C_CVar, ns.db.unitStatusTextEnabled = previous, initialized
end

for _, m in ipairs(ns.modules) do
    check(m.built, m.name .. " is built")
end
check(#ns.errors == 0, "no errors: " .. tostring(ns.errors[1]))
local nameplateSizeSetting = M.settings.settings.FOREVERUI_CVAR_NAMEPLATEGLOBALSCALE
local stackingSetting = M.settings.settings.FOREVERUI_CVAR_NAMEPLATEMOTION
check(nameplateSizeSetting and stackingSetting, "available native nameplate scale and stacking controls are registered")
M.combat = true
nameplateSizeSetting:SetValue(1.2)
nameplateSizeSetting:SetValue(1.3)
check(M.cvars.nameplateGlobalScale == "1", "native nameplate setting changes wait during combat")
M.combat = false
M.fire("PLAYER_REGEN_ENABLED")
check(M.cvars.nameplateGlobalScale == "1.3", "the latest queued nameplate size applies after combat")
nameplateSizeSetting:SetValue(1)
CharacterFrame:ShowSubFrame("PVPRankFrame")
check(CharacterFrame.RightPaneHost.fuiPvpDivider:IsShown(), "PvP details have a gold divider")
CharacterFrame:ShowSubFrame("ReputationFrame")
check(not CharacterFrame.RightPaneHost.fuiPvpDivider:IsShown(), "the PvP divider is hidden on other character tabs")
local guildButton = ns.modules.micro.buttons[7]
guildButton._scripts.OnClick(guildButton, "LeftButton")
check(M.guildToggleCount == 1 and not guildButton.fuiLocked,
    "guild button calls the game's guild toggle once")
-- Exercise lock-state updates with the manually sized layout below; the
-- automatic layout is tested separately with explicit screen coordinates.
ns.db.opts.microFit = false
local dungeon = ns.modules.micro.buttons[8]
LFDMicroButton._enabled = false
LFDMicroButton.disabledTooltip = "Available at level 15"
ns.modules.micro.strip._scripts.OnUpdate(ns.modules.micro.strip, 0.2)
check(dungeon.fuiLocked and dungeon.fuiLockText:IsShown() and dungeon.fuiIcon:GetAlpha() == 0.35,
    "a locked native menu button is dimmed and marked with a lock")
check(dungeon.fuiLockText:IsShown() and dungeon.fuiLockText:GetText() == "Available at level 15",
    "the locked cell shows the native requirement in red text")
dungeon._scripts.OnEnter(dungeon)
check(table.concat(GameTooltip._lines or {}, " "):find("Locked or unavailable", 1, true), "hover explains the locked state")
LFDMicroButton._enabled = true
ns.modules.micro.strip._scripts.OnUpdate(ns.modules.micro.strip, 0.2)
check(not dungeon.fuiLocked and not dungeon.fuiLockText:IsShown() and dungeon.fuiIcon:GetAlpha() == 1,
    "the menu updates when the native button unlocks")
check(not dungeon.fuiLockText:IsShown(), "unlocking removes the lock text")
GameMenuFrame:Show()
CharacterMicroButton._enabled = false
ns.modules.micro.strip._scripts.OnUpdate(ns.modules.micro.strip, 0.2)
check(not ns.modules.micro.buttons[1].fuiLocked, "opening the game menu doesn't falsely lock character")
GameMenuFrame:Hide()
ns.modules.micro.strip._scripts.OnUpdate(ns.modules.micro.strip, 0.2)
check(ns.modules.micro.buttons[1].fuiLocked, "the native state refreshes after the game menu closes")
CharacterMicroButton._enabled = true
ns.modules.micro.strip._scripts.OnUpdate(ns.modules.micro.strip, 0.2)

-- XP bar
do
    local unitFill = "Interface\\TargetingFrame\\UI-StatusBar"
    local function unitBar(parent)
        local bar = CreateFrame("StatusBar", nil, parent)
        bar:SetWidth(120)
        bar._fillTexture = bar:CreateTexture()
        bar._fillTexture.SetAtlas = function(self, atlas) self._atlas = atlas end
        bar.GetStatusBarTexture = function(self) return self._fillTexture end
        bar.SetStatusBarTexture = function(self, texture) self._fill = texture end
        bar.SetStatusBarColor = function(self, r, g, b) self._fillColor = { r, g, b } end
        return bar
    end
    local function nativeUnit(name)
        local frame = CreateFrame("Button", name, UIParent)
        frame.TargetFrameContainer = CreateFrame("Frame", nil, frame)
        frame.TargetFrameContainer.Portrait = frame:CreateTexture()
        frame.TargetFrameContainer.FrameTexture = frame:CreateTexture()
        frame.TargetFrameContainer.Flash = frame:CreateTexture()
        frame.TargetFrameContainer.Flash.SetAtlas = function(self, atlas) self._atlas = atlas end
        frame.TargetFrameContent = CreateFrame("Frame", nil, frame)
        local main = CreateFrame("Frame", nil, frame.TargetFrameContent)
        frame.TargetFrameContent.TargetFrameContentMain = main
        main.Name = frame:CreateFontString()
        main.ReputationColor = frame:CreateTexture()
        main.LevelBackgroundCircle = frame:CreateTexture()
        main.HealthBarsContainer = CreateFrame("Frame", nil, main)
        main.HealthBarsContainer.HealthBar = unitBar(main.HealthBarsContainer)
        main.ManaBar = unitBar(main)
        main.HealthBarsContainer.HealthBarMask = {}
        main.ManaBar.ManaBarMask = {}
        main.HealthBarsContainer.HealthBar._fillTexture.RemoveMaskTexture = function(self, mask) self.removedMask = mask end
        main.ManaBar._fillTexture.RemoveMaskTexture = function(self, mask) self.removedMask = mask end
        frame.auraContainer = CreateFrame("Frame", nil, frame)
        frame.GetAuraContainer = function(self) return self.auraContainer end
        frame.AnchorAuraContainer = function(self)
            self.auraContainer:ClearAllPoints()
            self.auraContainer:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, 0)
        end
        frame.UpdateHealthBarVisuals = function(self) self.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar._fill = "native" end
        return frame
    end
    TargetFrame, FocusFrame = nativeUnit("TargetFrame"), nativeUnit("FocusFrame")
    local previousQuestieLoader = QuestieLoader
    local questModule = { DrawTargetFrame = function() end, RedrawFrameIcon = function() end }
    QuestieLoader = { ImportModule = function(_, name) if name == "QuestieNameplate" then return questModule end end }
    local questMarker = CreateFrame("Frame", nil, TargetFrame)
    questMarker.Icon = questMarker:CreateTexture()
    questMarker.Icon.GetTexture = function() return "Interface\\AddOns\\Questie\\Icons\\loot.blp" end
    TargetFrame.GetChildren = function() return questMarker end
    ns.modules.targetframe:Refresh()
    check(TargetFrame.fuiTargetSkin and FocusFrame.fuiTargetSkin
        and TargetFrame.TargetFrameContainer.FrameTexture:GetAlpha() == 0
        and TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor:GetAlpha() == 0.35,
        "target and focus use gold panels while retaining native unit frames")
    local flashPoint, flashRelative, flashAnchor, flashX, flashY = FocusFrame.TargetFrameContainer.Flash:GetPoint()
    check(flashPoint == "TOPLEFT" and flashRelative == FocusFrame.TargetFrameContainer.Portrait
        and flashAnchor == "TOPLEFT" and flashX == -4 and flashY == 4,
        "focus threat glow follows its own portrait rather than the target")
    FocusFrame.TargetFrameContainer.Flash:SetAtlas("native-threat-art")
    check(FocusFrame.TargetFrameContainer.Flash._texture:find("unit%-combat%-glow"),
        "native threat updates retain the portrait-sized glow")
    local portraitPoint, portraitRelative, portraitAnchor, portraitX = TargetFrame.TargetFrameContainer.Portrait:GetPoint()
    local levelPoint, levelRelative = TargetFrame.TargetFrameContent.TargetFrameContentMain.LevelBackgroundCircle:GetPoint()
    check(portraitPoint == "LEFT" and portraitRelative == TargetFrame.fuiTargetSkin.body and portraitAnchor == "RIGHT"
        and portraitX == 4 and levelPoint == "CENTER" and levelRelative == TargetFrame.TargetFrameContainer.Portrait,
        "target portrait clears the panel and the level badge follows it")
    questModule:DrawTargetFrame()
    local markerPoint, markerRelative, markerAnchor, _, markerY = questMarker:GetPoint()
    check(markerPoint == "BOTTOM" and markerRelative == TargetFrame.TargetFrameContainer.Portrait
        and markerAnchor == "TOP" and markerY == 3, "Questie's target icon is centered above the portrait")
    QuestieLoader = previousQuestieLoader
    local oldIsPlayer, oldClass, oldColors = UnitIsPlayer, UnitClass, RAID_CLASS_COLORS
    UnitIsPlayer = function(unit) return unit == "target" end
    UnitClass = function() return "Shaman", "SHAMAN" end
    RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 } }
    ns.modules.targetframe:Refresh()
    check(TargetFrame.fuiTargetSkin.className:IsShown()
        and TargetFrame.fuiTargetSkin.className._color[3] == 0.87
        and TargetFrame.fuiTargetSkin.reaction:GetAlpha() == 0
        and not FocusFrame.fuiTargetSkin.className:IsShown(),
        "player target names show their class color without replacing NPC reaction colors")
    UnitIsPlayer, UnitClass, RAID_CLASS_COLORS = oldIsPlayer, oldClass, oldColors
    ns.modules.targetframe:Refresh()
    local skin = TargetFrame.fuiTargetSkin
    ns.modules.targetframe:Refresh()
    check(TargetFrame.fuiTargetSkin == skin, "unit frame refresh does not duplicate the panels")
    local targetHealth = TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
    local targetMain = TargetFrame.TargetFrameContent.TargetFrameContentMain
    check(targetHealth._fillTexture.removedMask == targetMain.HealthBarsContainer.HealthBarMask
        and targetMain.ManaBar._fillTexture.removedMask == targetMain.ManaBar.ManaBarMask,
        "the game's shaped health and mana masks no longer clip the rectangular fills")
    TargetFrame:AnchorAuraContainer()
    local auraPoint, auraRelative, auraAnchor, _, auraY = TargetFrame.auraContainer:GetPoint(1)
    check(auraPoint == "BOTTOMLEFT" and auraRelative == targetMain.Name and auraAnchor == "TOPLEFT" and auraY == 8,
        "target buffs and debuffs stay above the panel when the game reanchors them")
    TargetFrame.auraContainer.IsFlowLayoutMirroredVertically = function() return true end
    TargetFrame:AnchorAuraContainer()
    local _, mirroredRelative = TargetFrame.auraContainer:GetPoint(1)
    check(mirroredRelative == TargetFrame, "the native mirrored aura layout is preserved")
    TargetFrame.auraContainer.IsFlowLayoutMirroredVertically = function() return false end
    TargetFrame.auraContainer.IsProtected = function() return true end
    M.combat = true
    TargetFrame:AnchorAuraContainer()
    local _, combatRelative = TargetFrame.auraContainer:GetPoint(1)
    check(combatRelative == TargetFrame, "protected target auras are not repositioned during combat")
    M.combat = false
    M.fire("PLAYER_REGEN_ENABLED")
    local _, afterCombatRelative = TargetFrame.auraContainer:GetPoint(1)
    check(afterCombatRelative == targetMain.Name, "protected target auras are repositioned after combat")
    targetMain.ManaBar.unit = "target"
    UnitFrameManaBar_UpdateType(targetMain.ManaBar)
    check(targetMain.ManaBar._fill == unitFill and targetMain.ManaBar._fillColor[1] == 1
        and targetMain.ManaBar._fillColor[2] == 0.85 and targetMain.ManaBar._fillColor[3] == 0.1,
        "power type updates retain the shaded texture and the energy color")
    local oldPowerType = UnitPowerType
    UnitPowerType = function() return 0, "MANA" end
    UnitFrameManaBar_UpdateType(targetMain.ManaBar)
    check(targetMain.ManaBar._fillColor[1] == 0.16 and targetMain.ManaBar._fillColor[2] == 0.36
        and targetMain.ManaBar._fillColor[3] == 0.78, "mana uses a readable blue without changing other resource colors")
    UnitPowerType = oldPowerType
    local namePoint, nameRel = targetMain.Name:GetPoint(1)
    local powerPoint, powerRel, _, _, powerY = targetMain.ManaBar:GetPoint(1)
    check(namePoint == "BOTTOM" and nameRel == targetHealth and powerPoint == "TOPLEFT" and powerRel == targetHealth
        and powerY == -2 and targetMain.Name:GetWidth() == targetHealth:GetWidth() - 12
        and targetMain.ManaBar:GetWidth() == targetHealth:GetWidth(), "unit names and bars are centered with room between borders")
    check(targetHealth._fill == unitFill and targetHealth.fuiUnitBar
        and FocusFrame.TargetFrameContent.TargetFrameContentMain.ManaBar._fill == unitFill,
        "target and focus health and power bars use the shared shaded fill")
    local targetShade = targetHealth.fuiUnitBar.shade
    check(targetShade:GetPoint(1) ~= nil, "target health shading is anchored to the fill")
    targetHealth:SetStatusBarTexture("native-atlas")
    targetMain.ManaBar:SetStatusBarTexture("native-atlas")
    check(targetHealth._fill == unitFill and targetMain.ManaBar._fill == unitFill
        and targetMain.ManaBar.fuiUnitBar.shade ~= nil,
        "native texture refreshes keep the matching health and power shading")
    check(targetHealth._fillColor[2] > targetHealth._fillColor[1] and #targetHealth.fuiUnitBar.edge == 4
        and #targetMain.ManaBar.fuiUnitBar.edge == 4,
        "target health and power have subtle full-bar borders and health stays green")
    TargetFrame:UpdateHealthBarVisuals()
    check(targetHealth._fill == unitFill, "target health stays shaded after native classification updates")
    targetHealth:GetStatusBarTexture():SetAtlas("native-target-health")
    check(targetHealth:GetStatusBarTexture()._texture == unitFill, "direct native atlas changes restore the shared fill")
    UnitFrameHealthBar_Update(targetHealth)
    check(targetHealth._fillColor[2] > targetHealth._fillColor[1], "native health updates do not make target health white")
    targetHealth:SetStatusBarColor(0.1, 0.2, 1)
    check(targetHealth._fillColor[2] > targetHealth._fillColor[3], "native class coloring cannot turn target health blue")
    local function secondaryTarget(parent)
        local f = CreateFrame("Button", nil, parent)
        f.Name, f.Portrait, f.FrameTexture = f:CreateFontString(), f:CreateTexture(), f:CreateTexture()
        f.HealthBar, f.ManaBar = unitBar(f), unitBar(f)
        return f
    end
    TargetFrame.totFrame, FocusFrame.totFrame = secondaryTarget(TargetFrame), secondaryTarget(FocusFrame)
    M.combat = true
    ns.modules.targetframe:Refresh()
    check(not TargetFrame.totFrame.fuiTargetOfTargetSkin, "target-of-target styling waits for combat to end")
    M.combat = false
    M.fire("PLAYER_REGEN_ENABLED")
    check(TargetFrame.totFrame.fuiTargetOfTargetSkin and FocusFrame.totFrame.fuiTargetOfTargetSkin
        and TargetFrame.totFrame.FrameTexture:GetAlpha() == 0
        and TargetFrame.totFrame.HealthBar._fill == unitFill and FocusFrame.totFrame.ManaBar._fill == unitFill,
        "target-of-target and focus target use matching portrait, panels and bars")
    local totPoint, totRelative, totAnchor, _, totY = FocusFrame.totFrame:GetPoint()
    check(totPoint == "TOPRIGHT" and totRelative == FocusFrame and totAnchor == "BOTTOMRIGHT" and totY == -20,
        "focus target anchors to the native focus frame with clearance")
    local totSkin = TargetFrame.totFrame.fuiTargetOfTargetSkin
    ns.modules.targetframe:Refresh()
    check(TargetFrame.totFrame.fuiTargetOfTargetSkin == totSkin, "target-of-target styling is not duplicated")
    PlayerFrame = CreateFrame("Button", "PlayerFrame", UIParent)
    PlayerFrame.PlayerFrameContainer = CreateFrame("Frame", nil, PlayerFrame)
    PlayerFrame.PlayerFrameContainer.PlayerPortrait = PlayerFrame:CreateTexture()
    PlayerFrame.PlayerFrameContainer.PlayerPortraitMask = PlayerFrame:CreateTexture()
    PlayerFrame.PlayerFrameContainer.FrameTexture = PlayerFrame:CreateTexture()
    PlayerFrame.PlayerFrameContainer.FrameFlash = PlayerFrame:CreateTexture()
    PlayerFrame.PlayerFrameContent = CreateFrame("Frame", nil, PlayerFrame)
    local main = CreateFrame("Frame", nil, PlayerFrame.PlayerFrameContent)
    main.StatusTexture = PlayerFrame:CreateTexture()
    local oldResting, oldUpdateStatus = IsResting, PlayerFrame_UpdateStatus
    local oldNameAnchor = PlayerFrame_UpdatePlayerNameTextAnchor
    PlayerFrame_UpdatePlayerNameTextAnchor = function() end
    local resting = false
    IsResting = function() return resting end
    PlayerFrame_UpdateStatus = function() end
    PlayerFrame.PlayerFrameContent.PlayerFrameContentMain = main
    PlayerName = PlayerFrame:CreateFontString()
    main.HealthBarsContainer = CreateFrame("Frame", nil, main)
    main.HealthBarsContainer.HealthBar = unitBar(main.HealthBarsContainer)
    main.HealthBarsContainer.HealthBarMask = {}
    main.HealthBarsContainer.HealthBar._fillTexture.RemoveMaskTexture = function(self, mask) self.removedMask = mask end
    for _, name in ipairs({"MyHealPredictionBar", "OtherHealPredictionBar", "TotalAbsorbBar", "HealAbsorbBar"}) do
        local segment = CreateFrame("Frame", nil, main.HealthBarsContainer.HealthBar)
        segment.Fill = segment:CreateTexture()
        segment.Fill.RemoveMaskTexture = function(self, mask) self.removedMask = mask end
        main.HealthBarsContainer.HealthBar[name] = segment
    end
    main.HealthBarsContainer.HealthBar.TotalAbsorbBar.TiledFillOverlay = main.HealthBarsContainer.HealthBar.TotalAbsorbBar:CreateTexture()
    main.HealthBarsContainer.HealthBar.TotalAbsorbBar.TiledFillOverlay.RemoveMaskTexture = function(self, mask) self.removedMask = mask end
    main.ManaBarArea = CreateFrame("Frame", nil, main)
    main.ManaBarArea.ManaBar = unitBar(main.ManaBarArea)
    main.ManaBarArea.ManaBar.ManaBarMask = {}
    main.ManaBarArea.ManaBar._fillTexture.RemoveMaskTexture = function(self, mask) self.removedMask = mask end
    main.LevelBackgroundCircle = PlayerFrame:CreateTexture()
    main.ManaBarArea.ManaBar.ManaCostPredictionBar = CreateFrame("Frame", nil, main.ManaBarArea.ManaBar)
    local manaCost = main.ManaBarArea.ManaBar.ManaCostPredictionBar:CreateTexture()
    manaCost.RemoveMaskTexture = function(self, mask) self.removedMask = mask end
    manaCost.SetAtlas = function(self, atlas) self._atlas = atlas end
    main.ManaBarArea.ManaBar.ManaCostPredictionBar.Fill = manaCost
    M.combat = true
    ns.modules.playerframe:Refresh()
    check(not PlayerFrame.fuiPlayerSkin, "player frame styling waits until combat ends")
    M.combat = false
    M.fire("PLAYER_REGEN_ENABLED")
    check(PlayerFrame.fuiPlayerSkin and PlayerFrame.PlayerFrameContainer.FrameTexture:GetAlpha() == 0,
        "player frame receives the same gold panels while retaining native elements")
    do
        local health = main.HealthBarsContainer.HealthBar
        local oldWidth, oldSecret = health.GetWidth, ns.Secret
        local nameWidth, powerWidth = PlayerName:GetWidth(), main.ManaBarArea.ManaBar:GetWidth()
        health.GetWidth = function() return 99123 end
        ns.Secret = function(value) return value == 99123 or oldSecret(value) end
        local ok = pcall(PlayerFrame_UpdatePlayerNameTextAnchor)
        check(ok and PlayerName:GetWidth() == nameWidth and main.ManaBarArea.ManaBar:GetWidth() == powerWidth,
            "secret player-bar width is not compared or applied during name-anchor updates")
        health.GetWidth, ns.Secret = oldWidth, oldSecret
        PlayerName:SetWidth(1)
        PlayerFrame_UpdatePlayerNameTextAnchor()
        check(PlayerName:GetWidth() == health:GetWidth() - 12,
            "the player-bar layout realigns on the next non-secret update")
    end
    local pp, pr, pa, px, py = PlayerFrame.PlayerFrameContainer.PlayerPortrait:GetPoint()
    local mp, mr = PlayerFrame.PlayerFrameContainer.PlayerPortraitMask:GetPoint()
    local lp, lr = main.LevelBackgroundCircle:GetPoint()
    check(pp == "RIGHT" and pr == PlayerFrame.fuiPlayerSkin.body and pa == "LEFT" and px == -4 and py == 0
        and mp == "TOPLEFT" and mr == PlayerFrame.PlayerFrameContainer.PlayerPortrait
        and lp == "CENTER" and lr == PlayerFrame.PlayerFrameContainer.PlayerPortrait,
        "the player portrait, mask and level badge align with the panel")
    local pfp, pfr, pfa, pfx, pfy = PlayerFrame.PlayerFrameContainer.FrameFlash:GetPoint()
    check(pfp == "TOPLEFT" and pfr == PlayerFrame.PlayerFrameContainer.PlayerPortrait and pfa == "TOPLEFT"
        and pfx == -4 and pfy == 4, "player combat glow surrounds the moved portrait")
    local sp, sr, sa = main.StatusTexture:GetPoint()
    check(sp == "TOPLEFT" and sr == PlayerName and sa == "TOPLEFT" and main.StatusTexture:GetAlpha() == 0,
        "native status artwork is transparent and stays inside the name area")
    resting = true
    PlayerFrame_UpdateStatus()
    check(main.StatusTexture:GetAlpha() == 0 and main.StatusTexture._color[4] == 0
        and not main.StatusTexture.fuiCombatName:IsShown(), "resting cannot show the native yellow bar")
    resting = false
    PlayerFrame.inCombat = true
    PlayerFrame_UpdateStatus()
    check(main.StatusTexture:GetAlpha() == 0 and main.StatusTexture.fuiCombatName:IsShown(),
        "combat uses a separate red status tint")
    PlayerFrame.inCombat = false
    IsResting, PlayerFrame_UpdateStatus = oldResting, oldUpdateStatus
    PlayerFrame_UpdatePlayerNameTextAnchor = oldNameAnchor
    local originalScale = TargetFrame.GetEffectiveScale
    TargetFrame.GetEffectiveScale = function() return 0.8 end
    ns.modules.targetframe:Refresh()
    local _, _, _, targetGap = TargetFrame.TargetFrameContainer.Portrait:GetPoint()
    check(math.abs(targetGap * 0.8 + px) < 0.001,
        "player and target portraits have mirrored on-screen spacing at different scales")
    TargetFrame.GetEffectiveScale = originalScale
    ns.modules.targetframe:Refresh()
    check(main.HealthBarsContainer.HealthBar._fillTexture.removedMask == main.HealthBarsContainer.HealthBarMask
        and main.ManaBarArea.ManaBar._fillTexture.removedMask == main.ManaBarArea.ManaBar.ManaBarMask,
        "player health and resource fills are not clipped by native portrait-shaped masks")
    for _, name in ipairs({"MyHealPredictionBar", "OtherHealPredictionBar", "TotalAbsorbBar", "HealAbsorbBar"}) do
        check(main.HealthBarsContainer.HealthBar[name].Fill.removedMask == main.HealthBarsContainer.HealthBarMask,
            name .. " fills the rectangular health bar without its old mask")
        check(main.HealthBarsContainer.HealthBar[name].Fill._texture == unitFill,
            name .. " uses the same full-height texture as health")
    end
    check(main.HealthBarsContainer.HealthBar.TotalAbsorbBar.TiledFillOverlay.removedMask == main.HealthBarsContainer.HealthBarMask
        and manaCost.removedMask == main.ManaBarArea.ManaBar.ManaBarMask,
        "absorb and mana cost predictions use the full bar height")
    check(main.HealthBarsContainer.HealthBar._fill == unitFill and main.ManaBarArea.ManaBar._fill == unitFill,
        "player health and power bars use the shared shaded fill")
    check(#main.HealthBarsContainer.HealthBar.fuiUnitBar.edge == 4 and #main.ManaBarArea.ManaBar.fuiUnitBar.edge == 4,
        "player health and power have subtle full-bar borders")
    local _, _, insetY = main.ManaBarArea.ManaBar.fuiUnitBar.edge[3]:GetPoint(1)
    check(insetY == -1, "bar border corners do not paint over themselves")
    check(main.ManaBarArea.ManaBar:GetHeight() == 12 and targetMain.ManaBar:GetHeight() == 12
        and manaCost._color[1] == 0.98 and manaCost._color[2] == 0.72,
        "player and target power bars are taller and player spell cost is high contrast")
    manaCost:SetAtlas("native-mana-cost")
    check(manaCost._color[1] == 0.98 and manaCost._color[3] == 0.20,
        "spell cost remains high contrast when the native atlas is refreshed")
    main.HealthBarsContainer.HealthBar:SetStatusBarTexture("native-atlas")
    main.ManaBarArea.ManaBar:SetStatusBarTexture("native-atlas")
    check(main.HealthBarsContainer.HealthBar._fill == unitFill and main.ManaBarArea.ManaBar._fill == unitFill
        and main.ManaBarArea.ManaBar.fuiUnitBar.shade ~= nil,
        "player health and power keep the same shading after native updates")
    main.HealthBarsContainer.HealthBar:SetStatusBarColor(0, 0, 1)
    check(main.HealthBarsContainer.HealthBar._fillColor[2] > main.HealthBarsContainer.HealthBar._fillColor[3],
        "player health remains green after a native color update")
    local playerSkin = PlayerFrame.fuiPlayerSkin
    ns.modules.playerframe:Refresh()
    check(PlayerFrame.fuiPlayerSkin == playerSkin, "player frame styling is not duplicated")
    check(playerSkin.portrait._texture:find("unit%-portrait%-ring%.tga"),
        "player portrait has a round gold rim instead of a square outline")
    PetFrame = CreateFrame("Button", "PetFrame", PlayerFrame)
    PetFrame.Portrait = PetFrame:CreateTexture()
    PetFrameTexture = PetFrame:CreateTexture()
    PetName = PetFrame:CreateFontString()
    PetFrameHealthBar = unitBar(PetFrame)
    PetFrameManaBar = unitBar(PetFrame)
    M.fire("UNIT_PET", "player")
    check(PetFrame.fuiPetSkin and PetFrameTexture:GetAlpha() == 0
        and PetFrame.fuiPetSkin.portrait._texture:find("unit%-portrait%-ring%.tga"),
        "pet uses a matching panel and round portrait rim")
    check(PetFrameHealthBar._fill == unitFill and PetFrameManaBar._fill == unitFill,
        "pet health and power bars use the shared shaded fill")
    PartyFrame = CreateFrame("Frame", "PartyFrame", UIParent)
    local member = CreateFrame("Button", nil, PartyFrame)
    member.Name, member.Portrait, member.Texture = member:CreateFontString(), member:CreateTexture(), member:CreateTexture()
    member.HealthBarContainer = CreateFrame("Frame", nil, member)
    member.HealthBarContainer.HealthBar = unitBar(member.HealthBarContainer)
    member.ManaBar = unitBar(member)
    member.UpdateArt = function(self)
        self.HealthBarContainer.HealthBar._fill = "native"
        self.ManaBar._fill = "native"
    end
    PartyFrame.GetPartyMemberFrame = function(_, i) if i == 1 then return member end end
    M.fire("GROUP_ROSTER_UPDATE")
    check(member.fuiPartySkin and member.Texture:GetAlpha() == 0
        and member.HealthBarContainer.HealthBar._fill == unitFill and member.ManaBar._fill == unitFill,
        "party members use the matching panels and bars")
    member:UpdateArt()
    check(member.HealthBarContainer.HealthBar._fill == unitFill and member.ManaBar._fill == unitFill,
        "party bars remain shaded after the native art updates")
    local partySkin = member.fuiPartySkin
    ns.modules.partyframe:Refresh()
    check(member.fuiPartySkin == partySkin, "reused party frames are not styled twice")
end
do
    local dispel = ns.modules.dispel
    local oldSpell, oldName = IsPlayerSpell, C_Spell.GetSpellName
    local oldSound, sounds = PlaySoundFile, {}
    PlaySoundFile = function(path, channel) sounds[#sounds + 1] = { path, channel }; return true end
    RegisterUnitWatch = function(frame) frame._unitWatch = true end
    RegisterStateDriver = function(frame, state, condition) frame._driver = condition end
    IsPlayerSpell = function(id) return id == 1152 end
    C_Spell.GetSpellName = function(id) if id == 1152 then return "Purify" end return oldName(id) end
    C_UnitAuras = { GetAuraDataByIndex = function(unit, index)
        if unit == "player" and index == 1 then return { dispelName = "Poison" } end
    end }
    ns.db.opts.healPets = true
    M.fire("SPELLS_CHANGED")
    check(dispel.holder and dispel.holder:IsShown() and #dispel.rows == 45,
        "known dispel creates secure party and raid unit controls")
    local r = dispel.rows[1]
    check(#sounds == 1 and sounds[1][1]:find("dispel%-alert%.ogg") and sounds[1][2] == "SFX",
        "a newly curable effect plays the dispel alert on the effects channel")
    dispel:UpdateAuras("player")
    check(#sounds == 1, "unchanged curable effects do not repeat the alert")
    check(dispel.holder.fuiPanel.noBg and r.fuiPanel and r.fuiPanel.alpha == 0.8 and r.hover,
        "compact dispel squares use themed gold panels and hover highlights")
    check(r._unitWatch and r:GetWidth() == 18 and r:GetHeight() == 18 and r:GetAttribute("unit") == "player"
        and r:GetAttribute("useOnKeyDown") == false
        and r:GetAttribute("type1") == "spell" and r:GetAttribute("spell1") == "Purify"
        and r:GetAttribute("type2") == nil,
        "compact cure squares use learned spells and fixed secure targets")
    local _, _, _, firstX, firstY = dispel.rows[1]:GetPoint()
    local _, _, _, secondX, secondY = dispel.rows[2]:GetPoint()
    local _, _, _, lastX, lastY = dispel.rows[5]:GetPoint()
    local _, _, _, raidX, raidY = dispel.rows[11]:GetPoint()
    check(firstY == secondY and firstY == lastY and secondX > firstX
        and secondX - firstX == r:GetWidth() + 4
        and math.abs((lastX - firstX) - 4 * (secondX - firstX)) < 0.01
        and raidX == firstX and raidY < firstY,
        "dispel squares are evenly spaced in one party row and wrap raid rows")
    local _, partyAnchor, _, partyX, partyY = r:GetParent():GetPoint()
    check(partyAnchor == dispel.holder and partyX == 0 and partyY == 0 and firstX == 0
        and dispel.holder:GetWidth() == 5 * r:GetWidth() + 16,
        "dispel row has no extra inset and aligns with its healing portrait anchor")
    local savedDispelPos = ns.db.pos.dispel
    ns.db.pos.dispel = { x = 250, y = 300 }
    dispel.holder:ClearAllPoints()
    dispel.holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 250, 300)
    dispel:AttachHealing()
    local savedPoint, savedRelative = dispel.holder:GetPoint()
    check(savedPoint == "CENTER" and savedRelative == UIParent, "moving the dispel squares survives healing refresh")
    ns.db.pos.dispel = savedDispelPos
    dispel:AttachHealing()
    check(r.icon._color[4] == 0.85 and r.activeKind == "Poison",
        "the affected member's square highlights curable poison")
    check(r.icon._color[1] > r.icon._color[2] and r.icon._color[3] > r.icon._color[1],
        "curable effects use the purple dispel indicator")
    check(r.flash:IsShown() and not dispel.rows[2].flash:IsShown(),
        "only the affected character's dispel square starts flashing")
    dispel:UpdateFlash(0)
    local firstFlash = r.flash:GetAlpha()
    dispel:UpdateFlash(0.3)
    check(r.flash:GetAlpha() > firstFlash, "the affected square pulses visibly")
    C_UnitAuras.GetAuraDataByIndex = function(unit, index)
        if unit == "party1" and index == 1 then return { dispelName = "Disease" } end
    end
    M.combat = true
    dispel:UpdateAuras("player"); dispel:UpdateAuras("party1")
    check(not r.flash:IsShown() and dispel.rows[2].flash:IsShown()
        and dispel.rows[2]:GetAttribute("spell1") == "Purify",
        "flash follows a group member's curable effect during combat without changing secure casting")
    C_UnitAuras.GetAuraDataByIndex = function(unit, index)
        if unit == "party1" and index == 1 then return { dispelName = "Curse" } end
    end
    dispel:UpdateAuras("party1")
    check(not dispel.rows[2].flash:IsShown() and not dispel.hasCurable,
        "uncurable effects do not flash and the pulse stops after the effect clears")
    check(#sounds == 1, "uncurable effects do not play the dispel alert")
    ns.db.opts.dispelSound = false
    C_UnitAuras.GetAuraDataByIndex = function(unit, index)
        if unit == "party1" and index == 1 then return { dispelName = "Disease" } end
    end
    dispel.lastAlert = GetTime() - 2; dispel:UpdateAuras("party1")
    check(#sounds == 1, "dispel sounds can be disabled")
    ns.db.opts.dispelSound = nil
    dispel:UpdateAuras("party1")
    C_UnitAuras.GetAuraDataByIndex = function() return nil end
    dispel:UpdateAuras("party1")
    C_UnitAuras.GetAuraDataByIndex = function(unit, index)
        if unit == "party1" and index == 1 then return { dispelName = "Disease" } end
    end
    dispel:UpdateAuras("party1")
    check(#sounds == 2, "a newly applied curable effect alerts again after the previous effect clears")
    M.combat = false
    C_UnitAuras.GetAuraDataByIndex = function(unit, index)
        if unit == "player" and index == 1 then return { dispelName = "Poison" } end
    end
    dispel:UpdateAuras()
    IsPlayerSpell = function(id) return id == 1152 or id == 4987 end
    C_Spell.GetSpellName = function(id) if id == 1152 then return "Purify" elseif id == 4987 then return "Cleanse" end return oldName(id) end
    dispel:Refresh()
    check(r:GetAttribute("spell1") == "Cleanse" and r:GetAttribute("spell2") == nil,
        "one learned broad dispel handles all its supported types with one click")
    local oldClass = UnitClass
    UnitClass = function() return "Shaman", "SHAMAN" end
    IsPlayerSpell = function(id) return id == 526 or id == 2870 end
    C_Spell.GetSpellName = function(id)
        if id == 526 then return "Cure Poison" elseif id == 2870 then return "Cure Disease" end
        return oldName(id)
    end
    dispel:Refresh()
    check(r:GetAttribute("spell1") == "Cure Poison" and r:GetAttribute("spell2") == "Cure Disease",
        "different learned dispels remain separately available on the compact square")
    UnitClass = oldClass
    IsPlayerSpell = function(id) return id == 1152 end
    C_Spell.GetSpellName = function(id) if id == 1152 then return "Purify" end return oldName(id) end
    dispel:Refresh()
    check(dispel:Toggle() and not dispel.holder:IsShown(), "dispel panel can be hidden per character")
    dispel:Refresh()
    check(not dispel.holder:IsShown(), "dispel panel stays hidden after a refresh")
    check(dispel:Toggle() and dispel.holder:IsShown(), "dispel panel can be shown again")
    M.combat = true
    check(not dispel:Toggle() and dispel.holder:IsShown(), "combat cannot change dispel panel visibility")
    IsPlayerSpell = function() return false end
    dispel:Refresh()
    check(r:GetAttribute("spell1") == "Purify", "combat never changes secure spell attributes")
    M.combat = false
    dispel:Refresh()
    check(dispel.holder:IsShown() and r:GetAttribute("spell1") == nil and #r.actions == 0,
        "the dispel panel stays visible without a learned cure and does not cast a spell")
    r._scripts.OnEnter(r)
    check(table.concat(GameTooltip._lines or {}, " "):find("No supported dispel", 1, true),
        "the tooltip explains when no dispel is available")
    check(dispel:Toggle() and not dispel.holder:IsShown() and dispel:Toggle() and dispel.holder:IsShown(),
        "the panel can still be hidden and shown without a learned dispel")
    IsPlayerSpell, C_Spell.GetSpellName = oldSpell, oldName
    local heal = ns.modules.healing
    UnitHealth = function() return 75 end
    UnitHealthMax = function() return 100 end
    heal:Refresh()
    PlaySoundFile = oldSound
    local point, relative, relativePoint = dispel.holder:GetPoint()
    check(point == "BOTTOMLEFT" and relative == heal.rows[1].portraitButton and relativePoint == "TOPLEFT",
        "the compact dispel panel sits above the first healing portrait")
    check(heal.holder and #heal.rows == 92 and heal.rows[1]:GetAttribute("unit") == "player"
        and heal.rows[46]:GetAttribute("unit") == "pet" and heal.rows[51]:GetAttribute("unit") == "raidpet1"
        and heal.rows[1]:GetAttribute("type1") == "target" and heal.rows[1]:GetAttribute("useOnKeyDown") == false,
        "healing frames provide secure group and optional pet targets with reliable mouse-up casting")
    local previousAuraGetter = C_UnitAuras.GetAuraDataByIndex
    local previousAuraTooltip, previousSpellDescription = C_TooltipInfo.GetUnitAura, C_Spell.GetSpellDescription
    C_TooltipInfo.GetUnitAura = function(_, _, filter)
        if filter == "HELPFUL" then return { lines = { { leftText = "Fortitude" }, { leftText = "Increases stamina." } } } end
    end
    C_Spell.GetSpellDescription = function(id) if id == 12 then return "Deals damage over time." end end
    C_UnitAuras.GetAuraDataByIndex = function(unit, index, filter)
        if unit == "player" and index == 1 and filter == "HELPFUL" then
            return { name = "Fortitude", icon = 1234, applications = 2, expirationTime = GetTime() + 30 }
        end
        if unit == "player" and index == 1 and filter == "HARMFUL" then return { name = "Poison", icon = 5678, spellId = 12 } end
    end
    heal.rows[1]._scripts.OnEnter(heal.rows[1])
    local tooltipText = table.concat(GameTooltip._lines or {}, " | ")
    check(tooltipText:find("Fortitude", 1, true) and tooltipText:find("2 stacks", 1, true)
        and tooltipText:find("30s", 1, true) and tooltipText:find("Poison", 1, true)
        and tooltipText:find("|T1234:16:16|t", 1, true) and tooltipText:find("Increases stamina.", 1, true)
        and tooltipText:find("Deals damage over time.", 1, true),
        "healing-frame tooltip shows aura icons, descriptions, stacks and duration")
    C_UnitAuras.GetAuraDataByIndex = function() error("aura lookup denied") end
    C_TooltipInfo.GetUnitAura = function(_, index, filter)
        if index == 1 and filter == "HELPFUL" then
            return { lines = { { leftText = "Fallback buff" }, { leftText = "A readable effect." } } }
        end
    end
    heal:ShowAuraTooltip(heal.rows[1])
    tooltipText = table.concat(GameTooltip._lines or {}, " | ")
    check(tooltipText:find("Fallback buff", 1, true) and tooltipText:find("A readable effect.", 1, true)
        and tooltipText:find("Can't read effects right now", 1, true),
        "tooltip falls back to readable aura tooltip data and reports denied sections")
    local oldOwned = GameTooltip.IsOwned
    GameTooltip.IsOwned = function(_, owner) return owner == heal.rows[1] end
    C_UnitAuras.GetAuraDataByIndex = function(unit, index, filter)
        if unit == "player" and index == 1 and filter == "HARMFUL" then return { name = "New debuff" } end
    end
    M.fire("UNIT_AURA", "player")
    check(table.concat(GameTooltip._lines or {}, " | "):find("New debuff", 1, true),
        "the open healing-frame tooltip updates when auras change")
    GameTooltip.IsOwned = oldOwned
    C_UnitAuras.GetAuraDataByIndex = previousAuraGetter
    C_TooltipInfo.GetUnitAura, C_Spell.GetSpellDescription = previousAuraTooltip, previousSpellDescription
    heal.rows[1]._scripts.OnLeave(heal.rows[1])
    check(heal.rows[1].portraitButton:GetAttribute("unit") == "player"
        and heal.rows[1].portraitButton:GetAttribute("type1") == "target"
        and heal.rows[1].portraitButton:GetAttribute("useOnKeyDown") == false,
        "the portrait uses a separate secure left-click target action")
    local partyBefore, positionBefore, flagBefore = PartyFrame, ns.db.pos.healing, ns.db.healPartyPositionV1
    local partyForPosition = CreateFrame("Frame", nil, UIParent)
    partyForPosition:SetSize(180, 180)
    partyForPosition.GetLeft = function() return 320 end
    partyForPosition.GetTop = function() return 700 end
    PartyFrame = partyForPosition
    ns.db.healPartyPositionV1 = nil
    heal:InitialPartyPosition(heal.holder)
    check(ns.db.pos.healing and ns.db.pos.healing.x == 408 and ns.db.pos.healing.y == 696,
        "healing frames move beside the original party frame on first load")
    ns.db.pos.healing.x = 450
    heal:InitialPartyPosition(heal.holder)
    check(ns.db.pos.healing.x == 450, "later healing-frame moves are preserved")
    PartyFrame, ns.db.pos.healing, ns.db.healPartyPositionV1 = partyBefore, positionBefore, flagBefore
    check(heal.rows[91]:GetAttribute("unit") == "target" and heal.rows[91]._driver == "[@target,exists,help] show; hide"
        and heal.rows[92]._driver == "[@focus,exists,help] show; hide" and heal.targetHolder._driver == "hide",
        "optional target and focus frames use friendly-only secure visibility")
    ns.db.opts.healTargets = true
    heal:Refresh()
    check(heal.targetHolder._driver == "show", "friendly target and focus frames can be enabled")
    ns.db.opts.healTargets = false
    heal:Refresh()
    ns.db.opts.healReplaceParty = false
    heal:Refresh()
    local nativeMember = PartyFrame:GetPartyMemberFrame(1)
    PartyFrame:SetAlpha(0.8)
    nativeMember._mouseEnabled = true
    nativeMember.IsMouseEnabled = function(self) return self._mouseEnabled end
    nativeMember.EnableMouse = function(self, value) self._mouseEnabled = value end
    CompactPartyFrame = CreateFrame("Frame", "CompactPartyFrame", UIParent)
    CompactPartyFrame:SetAlpha(0.7)
    local compactMember = CreateFrame("Button", "CompactPartyFrameMember1", CompactPartyFrame)
    CompactPartyFrame.MemberFrame1 = compactMember
    compactMember._mouseEnabled = true
    compactMember.IsMouseEnabled = function(self) return self._mouseEnabled end
    compactMember.EnableMouse = function(self, value) self._mouseEnabled = value end
    ns.db.opts.healReplaceParty = true
    heal:Refresh()
    check(PartyFrame:GetAlpha() == 0 and not nativeMember._mouseEnabled
        and CompactPartyFrame:GetAlpha() == 0 and not compactMember._mouseEnabled,
        "healing frames replace native and compact party frames")
    M.combat = true
    ns.db.opts.healReplaceParty = false
    heal:Refresh()
    check(PartyFrame:GetAlpha() == 0 and not nativeMember._mouseEnabled,
        "native party frames are not changed during combat")
    M.combat = false
    heal:Refresh()
    check(PartyFrame:GetAlpha() == 0.8 and nativeMember._mouseEnabled
        and CompactPartyFrame:GetAlpha() == 0.7 and compactMember._mouseEnabled,
        "disabling replacement restores native party frame visibility and mouse input")
    ns.db.opts.healReplaceParty = true
    heal:Refresh()
    local handle = heal.moveHandle
    check(handle.fuiPanel and handle.fuiGrip and #handle.fuiGrip == 6,
        "healing move handle has a themed panel and four-way gold grip")
    local originalAfter, pending = C_Timer.After, nil
    C_Timer.After = function(delay, fn) check(delay == 0.45, "the move handle has a short hold delay"); pending = fn end
    handle._scripts.OnMouseDown(handle, "LeftButton")
    handle._scripts.OnMouseUp(handle, "LeftButton")
    pending()
    check(not heal.holder.fuiDragging, "a short click does not move healing frames")
    handle._scripts.OnMouseDown(handle, "LeftButton")
    pending()
    check(heal.holder.fuiDragging, "holding the corner handle starts a drag outside combat")
    handle._scripts.OnMouseUp(handle, "LeftButton")
    check(not heal.holder.fuiDragging and ns.db.pos.healing and ns.db.pos.healing.x,
        "dragging the healing frame saves its position")
    handle._scripts.OnMouseUp(handle, "RightButton")
    check(ns.db.healMoveLocked and handle.fuiLockMark:IsShown() and not handle.fuiGrip[1]:IsShown()
        and #handle.fuiLock == 4, "right-click locks the healing frame and shows a gold lock icon")
    pending = nil
    handle._scripts.OnMouseDown(handle, "LeftButton")
    check(not pending and not heal.holder.fuiDragging, "the locked handle cannot start a drag")
    handle._scripts.OnMouseUp(handle, "RightButton")
    check(not ns.db.healMoveLocked and not handle.fuiLockMark:IsShown() and handle.fuiGrip[1]:IsShown(),
        "right-click unlocks the healing frame and restores the move icon")
    M.combat = true
    handle._scripts.OnMouseDown(handle, "LeftButton")
    check(not heal.holder.fuiDragging, "healing frame cannot start moving in combat")
    M.combat = false
    C_Timer.After = originalAfter
    ns.db.opts.healSolo = true
    heal:Refresh()
    check(heal.holder._driver == "show", "solo mode shows the healing frames without a group")
    M.combat = true
    ns.db.opts.healSolo = false
    heal:Refresh()
    check(heal.holder._driver == "show", "combat does not change the secure visibility driver")
    M.combat = false
    heal:Refresh()
    check(heal.holder._driver == "[group] show; hide", "group visibility is restored outside combat")
    ns.db.opts.healDeficit = true
    heal:UpdateUnits("player")
    check(heal.rows[1].status:GetText() == "-25", "healing frames can display missing health")
    ns.db.opts.healDeficit = false
    ns.db.opts.healScale = 1.25
    heal:Refresh()
    check(heal.holder:GetScale() == 1.25, "healing frame size follows the configured scale")
    ns.db.opts.healScale = 1
    heal:Refresh()
    ns.db.opts.healWidth, ns.db.opts.healHeight, ns.db.opts.healRaidRows = 150, 30, 5
    heal:Refresh()
    local raidSix = heal.rows[11]
    local _, _, _, raidX, raidY = raidSix:GetPoint(1)
    check(heal.rows[1]:GetWidth() == 150 and heal.rows[1]:GetHeight() == 30
        and raidX == 216 and raidY == 0,
        "raid layout uses configured frame dimensions and members per column")
    M.combat = true
    ns.db.opts.healWidth = 170
    heal:Refresh()
    check(heal.rows[1]:GetWidth() == 150, "healing frame layout does not change during combat")
    M.combat = false
    heal:Refresh()
    check(heal.rows[1]:GetWidth() == 170, "pending healing frame layout applies after combat")
    ns.db.opts.healWidth, ns.db.opts.healHeight, ns.db.opts.healRaidRows = 120, 25, 8
    heal:Refresh()
    local healthBar, powerBar = heal.rows[1].bar, heal.rows[1].power
    check(powerBar:GetHeight() == 8, "healing frames use a more visible resource bar")
    healthBar.SetStatusBarColor = function(self, r, g, b) self._healingColor = { r, g, b } end
    powerBar.SetStatusBarColor = function(self, r, g, b) self._healingColor = { r, g, b } end
    local oldClass, oldClassColors, oldPower, oldPowerMax, oldThreat = UnitClass, RAID_CLASS_COLORS, UnitPower, UnitPowerMax, UnitThreatSituation
    UnitClass = function() return "Shaman", "SHAMAN" end
    RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 } }
    UnitPower, UnitPowerMax = function() return 30 end, function() return 100 end
    UnitThreatSituation = function() return 3 end
    ns.db.opts.healClassColor = true
    heal:UpdateUnits("player")
    check(healthBar._healingColor[3] == 0.87 and powerBar:GetAlpha() == 1
        and powerBar._healingColor[1] == 1 and heal.rows[1].threat._color[4] == 1,
        "group frames show class color, power type, and high threat")
    local oldRole = UnitGroupRolesAssigned
    UnitGroupRolesAssigned = function() return "HEALER" end
    M.fire("PLAYER_ROLES_ASSIGNED")
    check(healthBar._healingColor[1] == 0.95 and healthBar._healingColor[2] == 0.78,
        "healer role overrides the class color with yellow")
    check(heal.rows[1].roleBadge:IsShown() and heal.rows[1].roleIcon._texture:find("heal%-role%-healer"),
        "assigned healer gets the green healing icon")
    UnitGroupRolesAssigned = function() return "TANK" end
    M.fire("PLAYER_ROLES_ASSIGNED")
    check(healthBar._healingColor[1] == 0.86 and healthBar._healingColor[2] == 0.22,
        "tank role overrides the class color with red")
    check(heal.rows[1].roleBadge:IsShown() and heal.rows[1].roleIcon._texture:find("heal%-role%-tank"),
        "assigned tank gets the blue shield icon")
    ns.db.opts.healRoleColor = false
    UnitGroupRolesAssigned = function() return "DAMAGER" end
    heal:UpdateUnits("player")
    check(heal.rows[1].roleBadge:IsShown() and heal.rows[1].roleIcon._texture:find("heal%-role%-damage"),
        "assigned damage role gets the red icon even with role colors off")
    M.combat = true
    UnitGroupRolesAssigned = function() return "HEALER" end
    heal:UpdateUnits("player")
    check(heal.rows[1].roleIcon._texture:find("heal%-role%-healer")
        and heal.rows[1].portraitButton:GetAttribute("type1") == "target",
        "role indicators update during combat without changing the portrait's target action")
    M.combat = false
    UnitGroupRolesAssigned = function() return "NONE" end
    heal:UpdateUnits("player")
    check(not heal.rows[1].roleBadge:IsShown(), "unassigned roles do not show a misleading icon")
    UnitGroupRolesAssigned = function() return "TANK" end
    heal:UpdateUnits("pet")
    check(not heal.rows[46].roleBadge:IsShown(), "pets do not show player role icons")
    ns.db.opts.healRoleColor = true
    UnitGroupRolesAssigned = oldRole
    ns.db.opts.healPower, ns.db.opts.healThreat, ns.db.opts.healClassColor = false, false, false
    heal:UpdateUnits("player")
    check(powerBar:GetAlpha() == 0 and heal.rows[1].threat._color[4] == 0
        and healthBar._healingColor[2] > healthBar._healingColor[1],
        "group power, threat and class colors can be disabled")
    ns.db.opts.healPower, ns.db.opts.healThreat = true, true
    UnitPower, UnitPowerMax = function() return 30 end, function() return 60 end
    heal:UpdateUnits("player")
    check(heal.rows[1].powerText:GetText() == "50%", "healing frames show the resource percentage")
    UnitClass, RAID_CLASS_COLORS, UnitPower, UnitPowerMax, UnitThreatSituation = oldClass, oldClassColors, oldPower, oldPowerMax, oldThreat
    local savedKey, savedGuid = ns.healingCharacterKey, UnitGUID
    ns.healingCharacterKey = nil
    UnitGUID = function() return "Player-test-one" end
    heal:SetBinding("button4", "Healing Wave")
    ns.healingCharacterKey = nil
    UnitGUID = function() return "Player-test-two" end
    heal:SetBinding("button4", "Holy Light")
    check(ns.db.healBindings["guid:Player-test-one"].button4 == "Healing Wave"
        and ns.db.healBindings["guid:Player-test-two"].button4 == "Holy Light",
        "healing bindings stay separate for characters sharing a name")
    ns.db.healBindings["guid:Player-test-one"], ns.db.healBindings["guid:Player-test-two"] = nil, nil
    ns.healingCharacterKey, UnitGUID = savedKey, savedGuid
    heal:SetBinding("shift-left", "Healing Touch")
    check(heal.rows[1]:GetAttribute("shift-type1") == "spell"
        and heal.rows[1]:GetAttribute("shift-spell1") == "Healing Touch", "healing clicks bind a spell for this character")
    M.combat = true
    heal:SetBinding("shift-left", "Other Spell")
    check(heal.rows[1]:GetAttribute("shift-spell1") == "Healing Touch", "healing bindings stay unchanged during combat")
    M.combat = false
    heal:SetBinding("shift-left", "clear")
    check(heal.rows[1]:GetAttribute("shift-spell1") == nil, "healing bindings can be cleared")
    heal:SetBinding("button4", "item:Heavy Linen Bandage")
    check(heal.rows[1]:GetAttribute("type4") == "item" and heal.rows[1]:GetAttribute("item4") == "Heavy Linen Bandage",
        "healing frames support mouse button four using an item")
    heal:SetBinding("button4", "macro:Quick Heal")
    check(heal.rows[1]:GetAttribute("type4") == "macro" and heal.rows[1]:GetAttribute("macro4") == "Quick Heal"
        and heal.rows[1]:GetAttribute("item4") == nil, "switching actions clears the previous secure item")
    heal:SetBinding("alt-ctrl-shift-button5", "focus")
    check(heal.rows[1]:GetAttribute("alt-ctrl-shift-type5") == "focus",
        "healing frames support combined modifiers and focus")
    ns.db.opts.healPets = false
    check(heal:SetAuraConfig("list", "444, 555"), "aura spell ID list saves")
    local originalAuras = C_UnitAuras.GetAuraDataByIndex
    C_UnitAuras.GetAuraDataByIndex = function(unit, index, filter)
        if unit == "player" and index == 1 and filter == "HELPFUL" then return { spellId = 444, icon = 44 } end
        if unit == "player" and index == 1 and filter == "HARMFUL" then return { spellId = 555, icon = 55 } end
    end
    local tracked = heal:TrackedAuras("player")
    check(#tracked == 2 and tracked[1].icon == 44 and tracked[2].icon == 55,
        "configured IDs find both helpful and harmful effects")
    heal:UpdateUnits("player")
    check(heal.rows[1].buffs[1]._texture == 44 and heal.rows[1].harmfulIcon._texture == 55,
        "helpful and harmful tracked effects appear in separate areas")
    check(not heal:SetAuraConfig("list", "444, invalid") and heal:GetAuraConfig().ids[444],
        "invalid aura input does not overwrite the saved list")
    C_UnitAuras.GetAuraDataByIndex = originalAuras
    ns.db.opts.plateThreat = false
    M.cvars.nameplateGlobalScale = "1.25"
    check(heal:SaveProfile("Raid"), "healing and nameplate settings can be saved as a profile")
    heal:SetBinding("left", "Other Spell")
    heal:SetAuraConfig("off", "")
    ns.db.opts.plateThreat = true
    M.cvars.nameplateGlobalScale = "1.5"
    check(heal:LoadProfile("Raid") and heal.rows[1]:GetAttribute("macro4") == "Quick Heal"
        and heal:GetAuraConfig().ids[444] and ns.db.opts.plateThreat == false and M.cvars.nameplateGlobalScale == "1.25",
        "loading a profile restores bindings, aura IDs and nameplate options and size")
    M.cvars.nameplateGlobalScale = "1"
    M.combat = true
    check(not heal:LoadProfile("Default"), "profiles cannot change secure bindings during combat")
    M.combat = false
    check(not heal:DeleteProfile("Raid") and heal:LoadProfile("Default") and heal:DeleteProfile("Raid"),
        "an active profile is protected from deletion until another is loaded")
    heal:SetAuraConfig("mine", "")
    ns.db.opts.plateThreat = true
    heal:ShowConfig()
    local oldCursor, oldClear, oldSpellName = GetCursorInfo, ClearCursor, C_Spell.GetSpellName
    local cleared = false
    GetCursorInfo = function() return "spell", 5, "spell", 331 end
    ClearCursor = function() cleared = true end
    C_Spell.GetSpellName = function(id) if id == 331 then return "Healing Wave" end return oldSpellName(id) end
    heal.config.inputs["shift-left"]._scripts.OnReceiveDrag(heal.config.inputs["shift-left"])
    check(heal.config.inputs["shift-left"]:GetText() == "Healing Wave" and cleared,
        "dragging a spell into a healing binding fills the field")
    C_Spell.GetSpellSubtext = function() return "Rank 2" end
    check(heal:DropBindingSpell(heal.config.inputs["shift-left"])
        and heal.config.inputs["shift-left"]:GetText() == "Healing Wave(Rank 2)",
        "dragging a ranked spell retains the selected rank")
    C_Spell.GetSpellSubtext = nil
    heal.config.inputs["shift-left"]:SetText("Healing Wave")
    cleared = false
    GetCursorInfo = function() return "item", 123 end
    check(not heal:DropBindingSpell(heal.config.inputs["shift-left"]) and not cleared
        and heal.config.inputs["shift-left"]:GetText() == "Healing Wave", "other dragged objects do not overwrite bindings")
    GetCursorInfo = function() return "spell", 5, "spell", 331 end
    M.combat = true
    check(not heal:DropBindingSpell(heal.config.inputs["shift-left"]) and not cleared,
        "dragging a spell does not alter bindings in combat")
    M.combat = false
    GetCursorInfo, ClearCursor, C_Spell.GetSpellName = oldCursor, oldClear, oldSpellName
    local oldKnown = IsPlayerSpell
    IsPlayerSpell = function(id) return id == 635 end
    C_Spell.GetSpellName = function(id) if id == 635 then return "Holy Light" end return oldSpellName(id) end
    heal.config.inputs["shift-left"]:SetText("")
    check(heal:SuggestBindings() == 1 and heal.config.inputs["shift-left"]:GetText() == "Holy Light",
        "suggestions fill an empty field with a learned class spell")
    heal.config.inputs["shift-left"]:SetText("My Custom Spell")
    check(heal:SuggestBindings() == 0 and heal.config.inputs["shift-left"]:GetText() == "My Custom Spell",
        "suggestions preserve existing binding text")
    IsPlayerSpell, C_Spell.GetSpellName = oldKnown, oldSpellName
    heal.config.inputs["left"]:SetText("Healing Touch")
    heal.config.save._scripts.OnClick(heal.config.save)
    check(heal.rows[1]:GetAttribute("spell1") == "Healing Touch" and not heal.config:IsShown(),
        "the healing binding editor saves secure click spells")
    dispel.spells = { Poison = "Purify" }
    ns.db.opts.healDispelButtons = true -- the optional portrait controls can still be enabled separately
    UnitInRange = function(unit) if unit == "player" then return false, true end return true, true end
    UnitGetIncomingHeals = function() return 10 end
    UnitGetTotalAbsorbs = function() return 20 end
    UnitGetTotalHealAbsorbs = function() return 5 end
    heal.rows[1].predict.SetValue = function(self, value) self._observedValue = value end
    heal.rows[1].absorb.SetValue = function(self, value) self._observedValue = value end
    C_UnitAuras.GetAuraDataByIndex = function(unit, index, filter)
        if unit == "player" and index == 1 then
            if filter == "HARMFUL" then return { dispelName = "Poison" } end
            if filter == "HELPFUL|PLAYER" then return { icon = 1234, applications = 3, expirationTime = GetTime() + 20 } end
        end
    end
    heal:Refresh()
    local inlineDispel = heal.rows[1].dispelButton
    check(inlineDispel and inlineDispel:GetAttribute("unit") == "player"
        and inlineDispel:GetAttribute("type1") == "spell" and inlineDispel:GetAttribute("spell1") == "Purify"
        and inlineDispel.fill._color[4] == 0.85,
        "learned dispel buttons above portraits target and highlight the affected unit")
    M.combat = true
    heal:Refresh()
    check(inlineDispel:GetAttribute("spell1") == "Purify", "inline dispel spell attributes remain fixed during combat")
    M.combat = false
    dispel.spells = { Poison = "Purify", Disease = "Purify", Magic = "Cleanse" }
    heal:Refresh()
    check(#heal.dispelGroups == 2 and inlineDispel:GetAttribute("spell1") == "Cleanse"
        and inlineDispel:GetAttribute("spell2") == "Purify" and inlineDispel.label:GetText() == "R",
        "one dispel square uses right-click for the second learned spell")
    dispel.spells = { Poison = "Purify" }
    heal:Refresh()
    heal:UpdateUnits("player")
    check(heal.rows[1].status:GetText() == "75%  +5" and heal.rows[1].bar:GetAlpha() == 0.45
        and heal.rows[1].debuff._color[4] == 1, "healing frames show health, range and curable debuffs")
    check(heal.rows[1].hasPrediction and heal.rows[1].predict:GetAlpha() == 0.45
        and heal.rows[1].buffs[1]._texture == 1234 and heal.rows[1].buffs[1]:IsShown()
        and heal.rows[1].buffStacks[1]:GetText() == "3" and heal.rows[1].buffStacks[1]:IsShown(),
        "healing frames show incoming heals and aura stacks")
    check(heal.rows[1].predict._observedValue == 80 and heal.rows[1].absorb._observedValue == 100
        and heal.rows[1].hasAbsorb and heal.rows[1].absorb:GetAlpha() == 0.45,
        "healing predictions account for heal absorbs and show damage shields")
    check(heal.rows[2]:GetAttribute("unit") == "party1" and heal.rows[2]:GetAttribute("*unit1") == "party1"
        and heal.rows[2]:GetAttribute("checkselfcast") == false,
        "party healing clicks explicitly use the clicked party member")
    do
        local oldHealth, oldSecret = UnitHealth, ns.Secret
        local secretValue, incomingValue = {}, {}
        ns.Secret = function(value) return value == secretValue or value == incomingValue or oldSecret(value) end
        UnitHealth = function() return secretValue end
        local row = heal.rows[1]
        row.predictFill = row.bar:CreateTexture()
        row.secretPredict.SetValue = function(self, value) self.observed = value end
        CreateUnitHealPredictionCalculator = function() return { GetIncomingHeals = function() return incomingValue end } end
        UnitGetDetailedHealPrediction = function(unit, healer) check(unit == "player" and healer == "player", "calculator uses the displayed unit") end
        heal:UpdateUnits("player")
        check(row.secretPredict:IsShown() and row.secretPredict.observed == incomingValue,
            "restricted incoming heals are passed directly to the prediction bar")
        UnitHealth, ns.Secret, CreateUnitHealPredictionCalculator, UnitGetDetailedHealPrediction = oldHealth, oldSecret, nil, nil
        heal:UpdateUnits("player")
    end
    ns.db.opts.healAbsorbs = false
    M.fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    check(not heal.rows[1].hasAbsorb and heal.rows[1].predict._observedValue == 85,
        "the absorb display can be disabled")
    ns.db.opts.healAbsorbs = true
    ns.db.opts.healAuraTimers = true
    heal:UpdateRanges()
    check(heal.rows[1].buffTimes[1]:IsShown() and heal.rows[1].buffTimes[1]:GetText() == "20",
        "healing frames show the remaining time of tracked auras")
    ns.db.opts.healAuraTimers = false
    heal:UpdateRanges()
    check(not heal.rows[1].buffTimes[1]:IsShown(), "healing aura timers can be disabled")
    local oldDead, oldIncoming = UnitIsDeadOrGhost, UnitHasIncomingResurrection
    UnitIsDeadOrGhost, UnitHasIncomingResurrection = function() return true end, function() return true end
    M.fire("INCOMING_RESURRECT_CHANGED", "player")
    check(heal.rows[1].status:GetText() == "Resurrect", "healing frames show incoming resurrection")
    UnitIsDeadOrGhost, UnitHasIncomingResurrection = oldDead, oldIncoming
    UnitInRange = nil
    UnitGetIncomingHeals = nil
    UnitGetTotalAbsorbs, UnitGetTotalHealAbsorbs = nil, nil
    dispel.spells = {}
    heal:Refresh()
    check(not inlineDispel:IsShown(), "inline dispel buttons hide when no supported cure is learned")
    local plateBar = CreateFrame("StatusBar", nil, UIParent)
    plateBar.SetStatusBarTexture = function(self, tex) self._fill = tex end
    plateBar.SetStatusBarColor = function(self, r, g, b) self._fillColor = { r, g, b } end
    plateBar.GetStatusBarColor = function() return 0.4, 0.6, 0.2, 1 end
    plateBar.selectedBorder, plateBar.bgTexture = plateBar:CreateTexture(), plateBar:CreateTexture()
    local castBar = CreateFrame("StatusBar", nil, UIParent)
    castBar.SetStatusBarTexture = function(self, tex) self._fill = tex end
    castBar.UpdateBarFillTexture = function(self) self:SetStatusBarTexture("native-cast") end
    local plate = { UnitFrame = { unit = "nameplate1", HealthBarsContainer = { healthBar = plateBar }, CastBarsContainer = { castBar = castBar } } }
    C_NamePlate.GetNamePlateForUnit = function() return plate end
    UnitThreatSituation = function() return 3 end
    ns.modules.nameplates:Add("nameplate1")
    check(plateBar._fill == "Interface\\TargetingFrame\\UI-StatusBar" and plateBar.fuiPlateEdge and plateBar.fuiPlateShade
        and plateBar.selectedBorder:GetAlpha() == 0 and plateBar._fillColor[1] > plateBar._fillColor[2],
        "accessible nameplates get a shaded fill, themed border and red high-threat color")
    ns.db.opts.plateThreatText = true
    ns.modules.nameplates:UpdateThreat("nameplate1")
    check(plateBar.fuiPlateThreat:IsShown() and plateBar.fuiPlateThreat:GetText() == "Aggro",
        "nameplate threat label identifies who has aggro")
    UnitDetailedThreatSituation = function() return false, 3, 87.3, 87.3, 100 end
    ns.db.opts.plateThreatPercent = true
    ns.modules.nameplates:UpdateThreat("nameplate1")
    check(plateBar.fuiPlateThreat:GetText() == "87%", "nameplate threat label can show a percentage")
    UnitDetailedThreatSituation, ns.db.opts.plateThreatPercent = nil, false
    ns.db.opts.plateThreatText = false
    ns.modules.nameplates:UpdateThreat("nameplate1")
    check(not plateBar.fuiPlateThreat:IsShown(), "nameplate threat labels can be disabled")
    check(castBar._fill == ns.FLAT and castBar.fuiPlateCast, "nameplate cast bars use the flat themed fill")
    castBar:UpdateBarFillTexture()
    check(castBar._fill == ns.FLAT, "nameplate cast styling survives the native cast refresh")
    ns.db.opts.plateCast = false
    ns.modules.nameplates:ApplyOptions()
    check(castBar._fill == "native-cast" and castBar.fuiPlateCast:GetAlpha() == 0,
        "disabling nameplate cast styling restores the native fill")
    ns.db.opts.plateCast = true
    ns.modules.nameplates:ApplyOptions()
    local oldUnitIsUnit = UnitIsUnit
    UnitIsUnit = function(unit, target) return unit == "nameplate1" and target == "target" end
    ns.db.opts.plateHealthText = true
    ns.modules.nameplates:UpdateInfo("nameplate1")
    check(plateBar.fuiPlateHealth:IsShown() and plateBar.fuiPlateHealth:GetText() == "75%"
        and plateBar.fuiPlateTarget:IsShown(), "nameplates show health percentage and the current target indicator")
    UnitIsUnit = function() return false end
    M.fire("PLAYER_TARGET_CHANGED")
    check(not plateBar.fuiPlateTarget:IsShown(), "nameplate target highlight follows the current target")
    local oldUnitName = UnitName
    UnitIsUnit = function(unit, token) return unit == "nameplate1" and token == "focus" end
    UnitName = function(unit) if unit == "nameplate1target" then return "Xeon Mana" end return oldUnitName(unit) end
    ns.db.opts.plateFocus, ns.db.opts.plateTargetOfTarget = true, true
    M.fire("UNIT_TARGET", "nameplate1")
    check(plateBar.fuiPlateFocus:IsShown() and plateBar.fuiPlateTargetName:IsShown()
        and plateBar.fuiPlateTargetName:GetText() == "Xeon Mana", "nameplates can show focus and the unit's target")
    UnitName = function(unit) if unit == "nameplate1target" then return nil end return oldUnitName(unit) end
    M.fire("UNIT_TARGET", "nameplate1")
    check(not plateBar.fuiPlateTargetName:IsShown(), "nameplate target text clears when the unit loses its target")
    UnitName = oldUnitName
    ns.db.opts.plateFocus, ns.db.opts.plateTargetOfTarget = false, false
    UnitIsUnit, ns.db.opts.plateHealthText = oldUnitIsUnit, false
    ns.db.opts.plateAuras = true
    C_UnitAuras.GetAuraDataByIndex = function(unit, index, filter)
        if unit == "nameplate1" and index == 1 and filter == "HARMFUL|PLAYER" then return { icon = 987, applications = 2, expirationTime = GetTime() + 24 } end
    end
    ns.modules.nameplates:ApplyOptions()
    check(plateBar.fuiPlateAuras and plateBar.fuiPlateAuras[1]:IsShown() and plateBar.fuiPlateAuras[1]._texture == 987
        and plateBar.fuiPlateAuraStacks[1]:GetText() == "2" and plateBar.fuiPlateAuraStacks[1]:IsShown()
        and plateBar.fuiPlateAuraTimes[1]:IsShown() and plateBar.fuiPlateAuraTimes[1]:GetText() == "24",
        "nameplates can display the player's debuffs, stacks and time remaining")
    ns.db.opts.plateAuraSize, ns.db.opts.plateAuraCount = 20, 1
    ns.modules.nameplates:ApplyOptions()
    check(#plateBar.fuiPlateAuras == 5 and plateBar.fuiPlateAuras[1]:GetWidth() == 20,
        "nameplate aura icon size is configurable")
    C_UnitAuras.GetAuraDataByIndex = function(unit, index, filter)
        if unit == "nameplate1" and filter == "HARMFUL" then
            if index == 1 then return { icon = 111, spellId = 111 } end
            if index == 2 then return { icon = 222, spellId = 222 } end
        end
    end
    check(ns.modules.nameplates:SetAuraFilter("list", "222"), "nameplate spell ID filter saves")
    check(plateBar.fuiPlateAuras[1]._texture == 222 and plateBar.fuiPlateAuras[1]:IsShown(),
        "nameplate filters display only listed spell IDs")
    C_UnitAuras.GetAuraDataByIndex = function(unit, index, filter)
        if unit == "nameplate1" and index == 1 and filter == "HELPFUL" then return { icon = 222, spellId = 222 } end
    end
    ns.modules.nameplates:UpdateAuras("nameplate1")
    check(plateBar.fuiPlateAuras[1]:IsShown() and plateBar.fuiPlateAuras[1]._texture == 222,
        "a listed spell is found among helpful nameplate effects")
    check(not ns.modules.nameplates:SetAuraFilter("list", "bad") and ns.modules.nameplates:GetAuraFilter().ids[222],
        "invalid nameplate IDs do not replace the saved filter")
    check(heal:SaveProfile("Plate Test"), "profile saves the nameplate aura filter")
    ns.modules.nameplates:SetAuraFilter("all", "")
    check(heal:LoadProfile("Plate Test") and ns.modules.nameplates:GetAuraFilter().ids[222],
        "profile restores the nameplate aura filter")
    ns.modules.nameplates:SetAuraFilter("mine", "")
    ns.db.opts.plateAuraSize, ns.db.opts.plateAuraCount = 16, 3
    C_UnitAuras.GetAuraDataByIndex = function() return nil end
    M.fire("UNIT_AURA", "nameplate1")
    check(not plateBar.fuiPlateAuras[1]:IsShown() and not plateBar.fuiPlateAuraStacks[1]:IsShown(),
        "nameplate debuffs and stacks clear when their auras expire")
    ns.db.opts.plateAuras = false
    ns.db.opts.plateThreat = false
    ns.modules.nameplates:UpdateThreat("nameplate1")
    check(plateBar._fillColor[1] == 0.4 and plateBar._fillColor[2] == 0.6,
        "disabling threat coloring restores the native color")
    ns.db.opts.plateThreat = true
    UnitThreatSituation = function() return nil end
    ns.modules.nameplates:UpdateThreat("nameplate1")
    check(plateBar._fillColor[1] == 0.4 and plateBar._fillColor[2] == 0.6,
        "unavailable threat information restores the native color")
    UnitThreatSituation = function() return 3 end
    ns.db.opts.plateBorder = false
    ns.modules.nameplates:ApplyOptions()
    check(plateBar.fuiPlateEdge:GetAlpha() == 0, "nameplate borders can be hidden")
    ns.db.opts.plateBorder = true
    ns.modules.nameplates:ApplyOptions()
    plateBar.GetStatusBarColor = function() return 0.2, 0.5, 0.7, 1 end
    CompactUnitFrame_UpdateHealthColor = function(frame) frame.HealthBarsContainer.healthBar:SetStatusBarColor(0.2, 0.5, 0.7) end
    ns.modules.nameplates:InstallHooks()
    CompactUnitFrame_UpdateHealthColor(plate.UnitFrame)
    check(plateBar._fillColor[1] > plateBar._fillColor[2], "threat color survives native color updates")
    ns.modules.nameplates:Remove("nameplate1")
    check(plateBar._fillColor[1] == 0.2 and plateBar._fillColor[3] == 0.7 and not ns.modules.nameplates.units.nameplate1,
        "recycled nameplates restore their latest native color")
    local combatBar = CreateFrame("StatusBar", nil, UIParent)
    combatBar.SetStatusBarTexture = plateBar.SetStatusBarTexture
    combatBar.SetStatusBarColor = plateBar.SetStatusBarColor
    combatBar.GetStatusBarColor = plateBar.GetStatusBarColor
    combatBar.IsProtected = function() return false end
    plate.UnitFrame.HealthBarsContainer.healthBar = combatBar
    M.combat = true
    ns.db.opts.plateAuras = true
    C_UnitAuras.GetAuraDataByIndex = function(unit, index, filter)
        if unit == "nameplate3" and index == 1 and filter == "HARMFUL|PLAYER" then return { icon = 4321 } end
    end
    ns.modules.nameplates:Add("nameplate3")
    check(ns.modules.nameplates.units.nameplate3 and combatBar._fill == "Interface\\TargetingFrame\\UI-StatusBar" and not combatBar.fuiPlateEdge,
        "accessible nameplates appearing in combat get threat styling without creating frames")
    check(combatBar.fuiPlateAuras and combatBar.fuiPlateAuras[1]:IsShown() and combatBar.fuiPlateAuras[1]._texture == 4321
        and combatBar.fuiPlateHealth and combatBar.fuiPlateTarget,
        "unprotected nameplates appearing in combat receive aura and info regions")
    ns.db.opts.plateAuras = false
    combatBar.IsProtected = function() return true end
    combatBar._fillColor = { 0.11, 0.22, 0.33 }
    ns.modules.nameplates:UpdateThreat("nameplate3")
    check(combatBar._fillColor[1] == 0.11, "a nameplate becoming protected is not recolored in combat")
    ns.modules.nameplates:Add("nameplate4")
    check(not ns.modules.nameplates.units.nameplate4, "protected nameplates are not modified in combat")
    M.combat = false
    combatBar.IsProtected = function() return false end
    ns.modules.nameplates:Add("nameplate3")
    check(combatBar.fuiPlateEdge ~= nil, "nameplate borders are added after combat")
    UnitGroupRolesAssigned = function() return "TANK" end
    ns.modules.nameplates:UpdateThreat("nameplate3")
    check(combatBar._fillColor[2] > combatBar._fillColor[1], "a tank holding threat sees green")
    UnitGroupRolesAssigned = nil
    plate.IsForbidden = function() return true end
    ns.modules.nameplates:Add("nameplate2")
    check(not ns.modules.nameplates.units.nameplate2, "forbidden nameplates are left alone")
end
local xp = ns.modules.xpbar
do
    local savedLog, savedReward = C_QuestLog, GetQuestLogRewardXP
    C_QuestLog = {
        GetNumQuestLogEntries = function() return 3 end,
        GetInfo = function(i) return ({ { questID = 1 }, { questID = 2 }, { questID = 3 } })[i] end,
        IsComplete = function(id) return id ~= 2 end,
    }
    GetQuestLogRewardXP = function(id) return id == 1 and 5000 or nil end
    xp.xp:SetWidth(312)
    M.fire("QUEST_LOG_UPDATE")
    check(xp.questXP == 5000 and xp.questCount == 1 and xp.xp.quest:IsShown()
        and math.abs(xp.xp.quest:GetWidth() - 310 * 5000 / 31200) < 0.01,
        "completed known quest XP appears after the earned XP")
    local topPoint, topOwner, topAnchor, _, topY = xp.xp.quest:GetPoint(1)
    local bottomPoint, bottomOwner, bottomAnchor, _, bottomY = xp.xp.quest:GetPoint(2)
    check(topPoint == "TOPLEFT" and topOwner == xp.xp and topAnchor == "TOPLEFT" and topY == -1
        and bottomPoint == "BOTTOMLEFT" and bottomOwner == xp.xp and bottomAnchor == "BOTTOMLEFT" and bottomY == 1
        and xp.xp.questSheen:IsShown() and xp.xp.questShade:IsShown(),
        "quest XP uses the full inner bar height with matching shading")
    ns.O().qolQuestXP = false; xp:Update()
    check(not xp.xp.quest:IsShown() and not xp.xp.questSheen:IsShown() and not xp.xp.questShade:IsShown(),
        "quest XP indicator and shading can be turned off")
    ns.O().qolQuestXP = nil
    C_QuestLog, GetQuestLogRewardXP = savedLog, savedReward
    xp:Update()
end
check(StatusTrackingBarManager:GetParent() == UIParent and StatusTrackingBarManager:GetAlpha() == 0,
    "the native status bars are invisible without reparenting the layout-managed frame")
check(xp.holder:IsShown() and xp.xp:IsShown() and not xp.rep:IsShown(), "levelling, no faction watched: just the XP bar")
check(xp.xp.edge and #xp.xp.edge == 4 and not xp.xp.fuiPanel.lines[1]:IsShown(),
    "the XP bar has one visible gold outline above its fill")
check(xp.xp.text:GetText():find("12,450 / 31,200", 1, true) and xp.xp.text:GetText():find("8,200 rested", 1, true),
    "it says the XP and rested: " .. xp.xp.text:GetText())
do
    xp.xp:SetWidth(312)
    xp:Update()
    local restPoint, restRelative, restAnchor = xp.xp.rest:GetPoint(1)
    local endPoint, endRelative, endAnchor = xp.xp.rest:GetPoint(2)
    check(restPoint == "TOPLEFT" and restRelative == xp.xp.fill and restAnchor == "TOPLEFT"
        and endPoint == "BOTTOMRIGHT" and endRelative == xp.xp.fill and endAnchor == "BOTTOMRIGHT"
        and xp.xp.rest:IsShown() and math.abs(xp.xp.fill:GetWidth() - 310 * 12450 / 31200) < 0.01,
        "rested blue overlays exactly the earned XP fill")
    local saved = M.xp.rested
    M.xp.rested = 999999
    xp:Update()
    check(xp.xp.rest:IsShown() and math.abs(xp.xp.fill:GetWidth() - 310 * 12450 / 31200) < 0.01,
        "additional rested XP does not change the earned XP width")
    M.xp.rested = 0
    xp:Update()
    check(not xp.xp.rest:IsShown(), "the rested segment hides when no rested XP remains")
    M.xp.rested = saved
    xp:Update()
end
check(xp.holder:GetWidth() == 1920 * 0.7, "uses a compact fallback width before action bar geometry is available")
do
    local old1, old12 = ActionButton1, ActionButton12
    local function measured(x)
        return { IsVisible = function() return true end, GetCenter = function() return x, 100 end,
            GetLeft = function() return x - 20 end, GetRight = function() return x + 20 end,
            GetTop = function() return 120 end, GetEffectiveScale = function() return UIParent:GetEffectiveScale() end }
    end
    ActionButton1, ActionButton12 = measured(300), measured(740)
    xp:UpdateLayout()
    local point, relative, relativePoint, x, y = xp.holder:GetPoint()
    check(xp.holder:GetWidth() == 480 and point == "BOTTOM" and relative == UIParent
        and relativePoint == "BOTTOMLEFT" and x == 520 and y == 122,
        "XP bar matches horizontal action bar bounds and sits above it")
    ns.db.pos.xpbar = { x = 10, y = 20 }
    xp.holder:ClearAllPoints(); xp.holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 10, 20)
    ActionButton12 = measured(840)
    xp:UpdateLayout()
    local savedPoint, _, _, savedX, savedY = xp.holder:GetPoint()
    check(xp.holder:GetWidth() == 580 and savedPoint == "CENTER" and savedX == 570 and savedY == 20,
        "a manually moved XP bar keeps its height and aligns horizontally")
    ns.db.pos.xpbar = nil
    ActionButton1, ActionButton12 = old1, old12
end
M.watched = { factionID = 72, name = "Stormwind", reaction = 5, currentReactionThreshold = 3000, nextReactionThreshold = 9000, currentStanding = 5400 }
M.fire("UPDATE_FACTION")
check(xp.rep:IsShown() and xp.rep.text:GetText():find("Stormwind    Friendly    2,400 / 6,000", 1, true),
    "watching Stormwind: a reputation bar too: " .. xp.rep.text:GetText())
M.player.level = 60
M.fire("PLAYER_LEVEL_UP")
check(not xp.xp:IsShown() and xp.rep:IsShown() and xp.rep:GetHeight() == 14, "at max level the reputation bar takes its place")
M.watched = nil
M.fire("UPDATE_FACTION")
check(not xp.holder:IsShown(), "max level, nothing watched: no bar at all")
M.player.level = 34
M.fire("PLAYER_LEVEL_UP")

-- micro menu and bags
check(MicroMenu.BorderArt:GetAlpha() == 0 and MicroMenu.BackgroundArt:GetAlpha() == 0, "the micro menu's frame art is gone")
check(ns.modules.micro.strip.fuiPanel ~= nil, "the micro buttons sit on a dark strip with the gold edge")
local p = { ns.modules.micro.strip:GetPoint() }
check(p[1] == "BOTTOMLEFT" and p[2] == UIParent, "the micro menu goes bottom left")
check(MicroMenuContainer:GetAlpha() == 0 and #ns.modules.micro.buttons == 12
    and ns.db.opts.microColumns == 6 and ns.modules.micro.strip:GetHeight() == 2 * ns.modules.micro.buttons[1]:GetHeight() + 6,
    "the original row is hidden and twelve buttons fit in two rows")
check(GuildMicroButton._mouse == false and CharacterMicroButton._mouse == false
    and SpellbookMicroButton._mouse == false and MainMenuBarBackpackButton._mouse == false,
    "hidden native menu and bag buttons do not intercept mouse clicks")
for i, button in ipairs(ns.modules.micro.buttons) do
    local point, _, _, x, y = button:GetPoint()
    check(point == "TOPLEFT" and x == 2 + ((i - 1) % 6) * (button:GetWidth() + 2)
        and y == -2 - math.floor((i - 1) / 6) * (button:GetHeight() + 2)
        and button.fuiTarget and ((i == 7 and button.fuiGuildAction) or (button:GetAttribute("type1") == "click"
        and button:GetAttribute("clickbutton") == button.fuiTarget)) and button.fuiIcon._texture and not button.fuiLabel:IsShown(),
        "menu cell " .. i .. " has a custom icon and game action")
end
local legacy, bags = ns.modules.micro.buttons[5], ns.modules.micro.buttons[12]
do
    TalentMicroButtonAlert = CreateFrame("Frame", nil, UIParent)
    ns.modules.micro:AlignTalentAlert()
    local point, anchor, relativePoint = TalentMicroButtonAlert:GetPoint()
    check(point == "BOTTOM" and anchor == ns.modules.micro.buttons[4] and relativePoint == "TOP",
        "talent reminder is anchored above the visible Talents button")
    TalentMicroButtonAlert = nil
    local oldHelpTip = HelpTip
    local tip = CreateFrame("Frame", nil, UIParent)
    tip.info = { system = "MicroButtons" }
    tip.relativeRegion = TalentMicroButton
    tip.AnchorAndRotate = function(self) self.anchored = true end
    HelpTip = { Point = { TopEdgeCenter = 2 }, Alignment = { Center = 2 }, framePool = {
        EnumerateActive = function() local done; return function() if not done then done = true; return tip end end end,
    } }
    ns.modules.micro:AlignTalentAlert()
    local tipPoint, tipAnchor, tipRelative = tip:GetPoint()
    check(tipPoint == "BOTTOM" and tipAnchor == ns.modules.micro.buttons[4] and tipRelative == "TOP",
        "pooled talent reminder follows the visible Talents button")
    check(tip.relativeRegion == TalentMicroButton and tip.info.targetPoint == nil and not tip.anchored,
        "the shared HelpTip pool is only re-anchored, never written to, so it stays untainted")
    HelpTip = oldHelpTip
end
local expected = { CharacterMicroButton, ProfessionMicroButton, SpellbookMicroButton, TalentMicroButton,
    LegacyMicroButton, QuestLogMicroButton, GuildMicroButton, LFDMicroButton,
    CollectionsMicroButton, StoreMicroButton, QuickJoinToastButton, MainMenuBarBackpackButton }
for i, target in ipairs(expected) do
    check(ns.modules.micro.buttons[i].fuiTarget == target, "micro menu button " .. i .. " follows the requested order")
end
check(ns.modules.micro.buttons[9].fuiIcon._texture:find("collections%-minimal")
    and ns.modules.micro.buttons[10].fuiIcon._texture:find("shop%-minimal"),
    "collections and shop use their own minibar icons")
do
    local strip = ns.modules.micro.strip
    local bounds, getLeft, getBottom = ns.ActionBarBounds, strip.GetLeft, strip.GetBottom
    ns.ActionBarBounds = function() return 100, 1400, 200, 40 end
    strip.GetLeft = function() return 10 end
    strip.GetBottom = function() return 40 end
    ns.modules.micro:FitSingleRow()
    local _, _, _, _, y = strip:GetPoint()
    local action = MultiBarBottomLeftButton1 or ActionButton1
    local button = ns.modules.micro.buttons[1]
    check(math.abs(button:GetWidth() * strip:GetEffectiveScale() - action:GetWidth() * action:GetEffectiveScale()) < 0.01
        and math.abs(button:GetHeight() * strip:GetEffectiveScale() - action:GetHeight() * action:GetEffectiveScale()) < 0.01
        and y > 200, "full-size two-row micro menu moves above the action bars when it cannot fit beside them")
    ns.db.pos.micro = { x = 100, y = 40 }
    strip:ClearAllPoints()
    strip:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 100, 40)
    ns.modules.micro:FitSingleRow()
    local point, _, _, savedX, savedY = strip:GetPoint()
    check(point == "CENTER" and savedX == 100 and savedY == 40,
        "automatic fitting preserves a saved Edit Mode position even when it overlaps the action bars")
    ns.db.pos.micro = nil
    ns.ActionBarBounds, strip.GetLeft, strip.GetBottom = bounds, getLeft, getBottom
end
do
    local strip = ns.modules.micro.strip
    local savedBounds = ns.ActionBarBounds
    ns.ActionBarBounds = function() return 500, 1400, 200, 40 end
    local savedLeft, savedTop, savedScale = xp.holder.GetLeft, xp.holder.GetTop, xp.holder.GetEffectiveScale
    xp.holder.GetLeft = function() return 500 end
    xp.holder.GetTop = function() return 216 end
    xp.holder.GetEffectiveScale = function() return UIParent:GetEffectiveScale() end
    ns.db.opts.microFit = true
    ns.modules.micro:FitBesideXP()
    local point, _, _, x, y = strip:GetPoint()
    check(math.abs(strip:GetWidth() - 478) < 0.01 and point == "BOTTOMLEFT" and math.abs(x - 12) < 0.01 and y == 40,
        "micro menu fits left of XP and aligns its bottom to the action bars")
    check(math.abs(ns.modules.micro.buttons[1]:GetWidth() - ns.modules.micro.buttons[1]:GetHeight()) < 0.01,
        "micro menu cells are square")
    ns.ActionBarBounds = savedBounds
    xp.holder.GetLeft, xp.holder.GetTop, xp.holder.GetEffectiveScale = savedLeft, savedTop, savedScale
    ns.db.opts.microFit = false
end
check(legacy.fuiTarget == LegacyMicroButton and bags.fuiTarget == MainMenuBarBackpackButton,
    "Legacy and Bags use their own native buttons")
LegacyMicroButton._enabled = false
ns.modules.micro.strip._scripts.OnUpdate(ns.modules.micro.strip, 0.2)
check(legacy.fuiLocked and legacy.fuiLockText:IsShown(), "Legacy shows lock text while its native button is disabled")
LegacyMicroButton._enabled = true
ns.modules.micro.strip._scripts.OnUpdate(ns.modules.micro.strip, 0.2)
check(not legacy.fuiLocked and not legacy.fuiLockText:IsShown(), "Legacy becomes available when its native button unlocks")
do
    local oldTraits, oldClass, oldUnspent = C_Traits, C_ClassTalents, GetNumUnspentTalents
    local talentPoints, legacyPoints = 2, 1
    C_ClassTalents = { GetActiveConfigID = function() return 77 end }
    C_Traits = { GetConfigInfo = function() return { treeIDs = { 12 } } end,
        GetConfigIDByTreeID = function(tree) if tree == 1187 then return 88 end end,
        GetTreeCurrencyInfo = function(config, tree)
            if config == 77 and tree == 12 then return { { quantity = talentPoints } } end
            if config == 88 and tree == 1187 then return { { quantity = legacyPoints } } end
            return {}
        end }
    GetNumUnspentTalents = function() return 0 end
    ns.modules.micro:UpdatePointAlerts()
    ns.modules.micro.strip._scripts.OnUpdate(ns.modules.micro.strip, 0.2)
    check(ns.modules.micro.buttons[4].fuiPointPulse:IsShown() and legacy.fuiPointPulse:IsShown(),
        "talent and legacy icons pulse when their separate trees have unspent points")
    talentPoints, legacyPoints = 0, 0
    ns.modules.micro:UpdatePointAlerts()
    ns.modules.micro.strip._scripts.OnUpdate(ns.modules.micro.strip, 0.2)
    check(not ns.modules.micro.buttons[4].fuiPointPulse:IsShown() and not legacy.fuiPointPulse:IsShown(),
        "point flashes stop after points are spent")
    C_Traits, C_ClassTalents, GetNumUnspentTalents = oldTraits, oldClass, oldUnspent
    ns.modules.micro:UpdatePointAlerts()
end
check(BagsBar:GetParent() == ns.hider, "the bag bar is hidden without changing key bindings")
local friends = ns.modules.micro.friends
check(not friends.fuiCount and friends.fuiIcon:GetWidth() > 0,
    "the Friends icon has no count and uses the standard icon layout")
check(QuickJoinToastButton:GetAlpha() == 0 and QuickJoinToastButton:GetParent() == MicroMenu
    and friends:GetAttribute("clickbutton") == QuickJoinToastButton, "the hidden social icon remains the native Friends click target")
check(ChatFrameMenuButton:GetAlpha() == 0 and ChatFrameChannelButton:GetAlpha() == 0 and TextToSpeechButton:GetAlpha() == 0,
    "the chat-side menu, channel and voice icons are visually hidden")
check(not ChatFrame1.fuiPanel and not ChatFrame1.fuiChatOutline and not ChatFrame1Tab.fuiPanel and ChatFrame1EditBox.fuiPanel,
    "chat and tabs have no outline and the input has a gold panel")
check(ChatFrame1.Background:GetAlpha() == 0, "the oversized native chat background is hidden")
check(ChatFrame1.fuiChatShade and ChatFrame1.fuiChatShade._color[4] == 0.10,
    "chat gets a faint dark background confined to the message area")
check(OneForAllDB.qol.copyChat == false, "OneForAll copy buttons are disabled before login")
check(not M.copyChatButton:IsShown(), "the existing anonymous copy button is hidden")
check(ChatFrame1.buttonFrame.Background:GetAlpha() == 0, "the separate chat side panel background is hidden")
check(ChatFrame1.ScrollBar.fuiGoldScroll, "the native scrollbar receives a gold track and thumb")
check(ChatFrame1.ScrollBar.Back.Texture:GetAlpha() == 0 and ChatFrame1.ScrollBar.Forward.Texture:GetAlpha() == 0
    and ChatFrame1.ScrollBar.Back.fuiGoldArrow._texture:find("scroll%-arrow%-up")
    and ChatFrame1.ScrollBar.Forward.fuiGoldArrow._texture:find("scroll%-arrow%-down"),
    "native scrollbar arrows are replaced by custom gold arrows")
check(ChatFrame1.ScrollToBottomButton.fuiGoldArrow and ChatFrame1.ScrollToBottomButton._normal:GetAlpha() == 0,
    "the native scroll arrow is replaced by a gold chevron")
check(ChatFrame1EditBox:GetHeight() == 24 and ChatFrame1EditBox.fuiPanel.edge == 1.4,
    "the input has a compact height and a stronger gold edge")
check(ChatFrame1._font == "Fonts/ChatNormal.ttf" and ChatFrame1._fontSize == 16 and ChatFrame1._fontFlags == "OUTLINE"
    and ChatFrame1EditBox._font == "Fonts/ForeverUITest.ttf" and ChatFrame1EditBox._fontSize == 14,
    "chat messages use the chat font, input uses the UI font, and sizes and flags are preserved")
local editPoint, editAnchor, editRelative, _, editY = ChatFrame1EditBox:GetPoint()
check(editPoint == "TOPLEFT" and editAnchor == ChatFrame1 and editRelative == "BOTTOMLEFT" and editY == -4,
    "chat input sits below the newest message with a gap")
check(ChatFrame1Tab.Left:GetAlpha() == 0 and ChatFrame1EditBox.Left:GetAlpha() == 0,
    "old tab and input artwork is removed")
check(ChatFrame1Tab.fuiUnderline:IsShown(), "the selected chat tab has an underline")
check(ChatFrame1EditBox.fuiPanel.bg:IsShown(), "the input styling remains visible when not typing")
local chatPanel = ChatFrame1Tab.fuiUnderline
M.fire("PLAYER_ENTERING_WORLD")
check(ChatFrame1Tab.fuiUnderline == chatPanel, "chat styling is not duplicated on refresh")

-- minimap
local mm = ns.modules.minimap
check(Minimap:GetParent() == mm.holder and Minimap._mask == "Interface\\Buttons\\WHITE8X8" and GetMinimapShape() == "SQUARE",
    "the minimap is square, in our frame")
MinimapCluster.UpdateMinimapConfig(MinimapCluster)
check(Minimap._mask == "Interface\\Buttons\\WHITE8X8", "and stays square when the game resets its mask")
check(MinimapCluster:GetParent() == ns.hider, "the game's minimap frame is put away")
check(mm.zone:GetText() == "Westfall" and mm.coords:GetText() == "52.4, 47.1", "zone above, coordinates below")
local stripPoint, stripRelative, stripAnchor, stripX, stripY = mm.strip:GetPoint(1)
check(stripPoint == "TOPLEFT" and stripRelative == mm.holder and stripAnchor == "BOTTOMLEFT"
    and stripX == 0 and stripY == -2, "minimap information strip sits below the map")
check(mm.strip.fuiPanel and mm.strip.fuiPanel.edge == 0.7 and mm.strip.fuiPanel.bg:IsShown(),
    "minimap information strip uses the shared dark and gold theme")
local statsPoint, statsRelative, statsRelativePoint = mm.stats:GetPoint(1)
check(statsPoint == "LEFT" and statsRelative == mm.coords and statsRelativePoint == "RIGHT",
    "minimap stats start after the coordinates")
do
    local oldDB, oldCommand, oldAdjusted = OpenMapTweaksDB, SlashCmdList.OPENMAPTWEAKS, ns.db.openMapQuestPinsAdjusted
    ns.db.openMapQuestPinsAdjusted = nil
    OpenMapTweaksDB = { pinZoom = 8, performance = true }
    SlashCmdList.OPENMAPTWEAKS = function(value) if value == "pins 1" then OpenMapTweaksDB.pinZoom = 1 end end
    ns.ConfigureOpenMapQuestPins()
    check(OpenMapTweaksDB.pinZoom == 1 and OpenMapTweaksDB.performance and ns.db.openMapQuestPinsAdjusted,
        "OpenMap quest pins stay visible at zone zoom while performance mode stays enabled")
    OpenMapTweaksDB.pinZoom = 4; ns.ConfigureOpenMapQuestPins()
    check(OpenMapTweaksDB.pinZoom == 4, "later OpenMap zoom preferences are respected")
    OpenMapTweaksDB, SlashCmdList.OPENMAPTWEAKS, ns.db.openMapQuestPinsAdjusted = oldDB, oldCommand, oldAdjusted
end
check(not mm.mail:IsShown(), "no mail, no mail icon")
M.mail = true
M.fire("UPDATE_PENDING_MAIL")
check(mm.mail:IsShown(), "mail: the icon shows")
do
    local pulse = mm.mail:GetScript("OnUpdate")
    local before = mm.mail.glow:GetAlpha()
    pulse(mm.mail, 1.5)
    check(mm.mail.glow:GetAlpha() > before, "mail icon gently pulses while mail is waiting")
    M.mail = false; mm:Mail()
    check(not mm.mail:IsShown() and mm.mail.glow:GetAlpha() == 0.12, "mail pulse resets when there is no new mail")
    M.mail = true; mm:Mail()
end
local mailPoint, mailOwner, mailRelative, mailX, mailY = mm.mail:GetPoint()
check(mailPoint == "TOPRIGHT" and mailOwner == mm.holder and mailRelative == "TOPLEFT" and mailX == -4 and mailY == -28,
    "mail indicator sits below the gathering filter to the left of the map")
local calPoint, calOwner, calRelative, calX, calY = mm.calendar:GetPoint()
check(calPoint == "TOPLEFT" and calOwner == mm.buttonRow and calRelative == "TOPLEFT"
    and calX == 3 * (mm.calendar:GetWidth() + 4) and calY == 0,
    "calendar is the fourth evenly spaced button")
local calendarOpened = false
ToggleCalendar = function() calendarOpened = true end
mm.calendar:Click()
check(calendarOpened, "calendar button opens the calendar")
check(#mm.gathered == 3 and M.lib1:GetParent() == mm.drawer and M.lib2:GetParent() == mm.drawer
    and M.ofa:GetParent() == mm.drawer and M.gameBtn:GetParent() == Minimap and mm.open.text:GetText() == "+3",
    "addon buttons go in the drawer, OneForAll's badge too (the game's stay): " .. #mm.gathered)
check(mm.open.icon and mm.open.icon._texture == "Interface\\AddOns\\ForeverUI\\Art\\addons.tga",
    "the addon drawer button has its own themed icon")
check(not mm.drawer.title and not mm.drawer.rule and M.lib1.fuiDrawerCell.fuiPanel
    and M.lib1.fuiDrawerHighlight, "addon drawer has gold cells and hover highlights without a heading or divider")
local openPoint, openRelative, openRelativePoint, openX, openY = mm.open:GetPoint()
check(openPoint == "TOPLEFT" and openRelative == mm.buttonRow and openRelativePoint == "TOPLEFT"
    and openX == 0 and openY == 0, "addon drawer button starts the row")
local settingsPoint, settingsOwner, settingsAnchor = mm.settings:GetPoint()
check(settingsPoint == "TOPLEFT" and settingsOwner == mm.buttonRow and settingsAnchor == "TOPLEFT"
    and select(4, mm.settings:GetPoint()) == mm.settings:GetWidth() + 4, "encyclopedia occupies the second cell")
check(mm.gold and mm.gold:GetWidth() == mm.settings:GetWidth() and mm.gold:GetParent() == mm.holder,
    "Forever Gold has an equal-sized shortcut on the second row")
do
    local point, owner, anchor, x, y = mm.instanceGuide:GetPoint()
    check(point == "TOPLEFT" and owner == mm.extraButtonRow and anchor == "TOPLEFT"
        and x == mm.gold:GetWidth() + 4 and y == 0 and mm.instanceGuide:GetWidth() == mm.gold:GetWidth(),
        "Instance Guide is the equal-sized cell immediately right of Forever Gold")
    check(mm.instanceGuide.icon._texture == "Interface\\AddOns\\ForeverUI\\Art\\instance-guide.tga",
        "Instance Guide has its own themed icon")
    mm.instanceGuide:Click()
    check(ns.InstanceGuide.frame and ns.InstanceGuide.frame:IsShown(), "Instance Guide button opens its own window")
    mm.instanceGuide:Click()
    check(not ns.InstanceGuide.frame:IsShown(), "Instance Guide button closes its own window")
end
do
    local oldGold, opened = ForeverGold, false
    ForeverGold = { ToggleUI = function() opened = true end }
    mm.gold:Click()
    check(opened, "Forever Gold shortcut opens the addon")
    ForeverGold = oldGold
end
check(mm.settings.icon._texture == "Interface\\AddOns\\ForeverUI\\Art\\encyclopedia.tga",
    "encyclopedia button uses its own icon")
WFTSyncButton = CreateFrame("Button", "WFTSyncButton", UIParent)
mm.AlignSync()
local syncPoint, syncOwner, syncAnchor, syncX, syncY = WFTSyncButton:GetPoint()
check(syncPoint == "TOPLEFT" and syncOwner == mm.buttonRow and syncAnchor == "TOPLEFT"
    and syncX == 2 * (mm.settings:GetWidth() + 4) and syncY == 0
    and WFTSyncButton:GetWidth() == mm.settings:GetWidth() and WFTSyncButton.fuiCompact,
    "sync button occupies the third equal cell")
WFTSyncButton = nil
mm.settings:Click()
check(ns.Encyclopedia.window and ns.Encyclopedia.window:IsShown(), "encyclopedia minimap button opens the encyclopedia")
ns.Encyclopedia.window.settings:Click()
check(ns.optionsWindow and ns.optionsWindow:IsShown(), "encyclopedia offers access to Forever UI settings")
ns.optionsWindow:Hide()
mm.open:Click()
check(mm.drawer:IsShown(), "+3 opens the drawer")
local drawerPoint, drawerRelative, drawerRelativePoint, drawerX, drawerY = mm.drawer:GetPoint()
check(drawerPoint == "TOPRIGHT" and drawerRelative == mm.open and drawerRelativePoint == "TOPLEFT"
    and drawerX == -4 and drawerY == 0, "the addon drawer opens to the left of its button")
local oldChildren = Minimap.GetChildren
local extraButtons = {}
for i = 1, 8 do
    local name = "DrawerTest" .. i
    local b = CreateFrame("Button", name, Minimap)
    b:SetSize(31, 31)
    b.IsObjectType = function(_, kind) return kind == "Button" end
    b.GetName = function() return name end
    b:SetScript("OnClick", function() end)
    extraButtons[i] = b
end
Minimap.GetChildren = function() return unpack(extraButtons) end
mm:Gather()
local cellPoint, _, cellRelative, cellX, cellY = extraButtons[8].fuiDrawerCell:GetPoint()
check(#mm.gathered == 11 and mm.drawer:GetWidth() == 370 and mm.drawer:GetHeight() == 82
    and cellPoint == "TOPRIGHT" and cellRelative == "TOPRIGHT" and cellX == -6 and cellY == -42,
    "drawer wraps its eleventh button onto a new row after ten, growing left")
Minimap.GetChildren = oldChildren
do
    local blank = CreateFrame("Button", "EmptyMinimapPlaceholder", Minimap)
    blank:SetSize(31, 31); blank.IsObjectType = function(_, kind) return kind == "Button" end
    local invisible = CreateFrame("Button", "HiddenMinimapPlaceholder", Minimap)
    invisible:SetSize(31, 31); invisible.IsObjectType = function(_, kind) return kind == "Button" end
    invisible:SetScript("OnClick", function() end); invisible:SetAlpha(0)
    Minimap.GetChildren = function() return blank, invisible end
    local before = #mm.gathered
    mm:Gather()
    check(#mm.gathered == before and blank:GetParent() == Minimap and invisible:GetParent() == Minimap,
        "inert and invisible minimap buttons stay out of the addon drawer")
    Minimap.GetChildren = oldChildren
end
do
    local moved, following = extraButtons[1], extraButtons[2]
    moved:SetParent(UIParent)
    mm:Gather()
    local _, _, _, x, y = following.fuiDrawerCell:GetPoint()
    check(not moved.fuiDrawerCell:IsShown() and following.fuiDrawerCell:IsShown()
        and x == -114 and y == -6 and mm.open.text:GetText() == "+10",
        "the drawer removes an abandoned cell and closes the gap")
    moved:SetParent(mm.drawer)
    moved:Hide()
    mm:Gather()
    check(not moved.fuiDrawerCell:IsShown(), "the drawer hides cells for buttons that become hidden")
    moved:Show()
    mm:Gather()
    check(moved.fuiDrawerCell:IsShown() and mm.open.text:GetText() == "+11",
        "the drawer restores a button when it becomes visible again")
end
local z = Minimap._zoom
Minimap._scripts.OnMouseWheel(Minimap, 1)
check(Minimap._zoom == z + 1, "scroll zooms")

-- action bars
check(math.abs(MainActionBar:GetScale() - 0.8) < 0.001, "the main action bar is 20 percent smaller")
M.fire("PLAYER_ENTERING_WORLD")
check(math.abs(MainActionBar:GetScale() - 0.8) < 0.001, "zone changes do not repeatedly shrink action bars")
ActionButton1:SetSize(45, 45)
MultiBarBottomLeftButton1:SetSize(45, 45)
ActionButton1.GetEffectiveScale = function() return 0.8 end
MultiBarBottomLeftButton1.GetEffectiveScale = function() return M.testReferenceScale or 0.8 end
M.advance(1.1)
check(math.abs(MainActionBar:GetScale() - 0.8) < 0.001, "equal initial sizes do not prematurely finish calibration")
M.testReferenceScale = 0.64
M.advance(2)
check(math.abs(MainActionBar:GetScale() - 0.64) < 0.001, "a larger main bar is matched to the smaller multibar after layout")
M.fire("PLAYER_ENTERING_WORLD"); M.advance(1.1)
check(math.abs(MainActionBar:GetScale() - 0.64) < 0.001, "matching does not shrink the main bar repeatedly")
check(ActionButton1.NormalTexture:GetAlpha() == 0 and ActionButton1.SlotArt:GetAlpha() == 0 and ActionButton1.fuiPanel ~= nil
    and PetActionButton1.fuiPanel ~= nil, "action buttons lose the game's frame and get the dark backing and gold edge")
check(MultiBarBottomLeftButton1.fuiPanel.lines[1]:GetHeight() == 1.5 and MultiBarBottomLeftButton1.fuiPanel.lines[3]:GetWidth() == 1.5,
    "action bar outlines remain visible at the reduced scale")
ActionButton1:UpdateButtonArt()
check(ActionButton1.SlotArt:GetAlpha() == 0, "and stay that way when the game refreshes their art")
check(MainActionBar.BorderArt:GetAlpha() == 0 and MainActionBar.EndCaps:GetAlpha() == 0, "no bar frame, no gryphons")
ActionButton_UpdateRangeIndicator(ActionButton1, true, false)
check(ActionButton1.fuiRange:IsShown(), "out of range: red tint")
ActionButton_UpdateRangeIndicator(ActionButton1, true, true)
check(not ActionButton1.fuiRange:IsShown(), "back in range: gone")

-- tooltips
GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
local tp = { GameTooltip:GetPoint() }
check(tp[2] == ns.modules.tooltip.anchor, "the default tooltip starts from Forever UI's movable spot")
GameTooltip.GetOwner = function() return ActionButton1 end
ActionButton1._scripts.OnEnter(ActionButton1)
local actionPoint, actionOwner, actionRelative = GameTooltip:GetPoint()
check(actionPoint == "BOTTOMLEFT" and actionOwner == ActionButton1 and actionRelative == "TOPRIGHT",
    "an action button's tooltip appears at its upper-right corner")
ActionButton1:SetTooltip()
local refreshedPoint, refreshedOwner, refreshedRelative = GameTooltip:GetPoint()
check(refreshedPoint == "BOTTOMLEFT" and refreshedOwner == ActionButton1 and refreshedRelative == "TOPRIGHT",
    "tooltip refresh keeps the action button anchor instead of the default position")
GameTooltip.GetOwner = function() return UIParent end
GameTooltip_SetDefaultAnchor(GameTooltip, ActionButton2)
local defaultPoint, defaultOwner, defaultRelative = GameTooltip:GetPoint()
check(defaultPoint == "BOTTOMLEFT" and defaultOwner == ActionButton2 and defaultRelative == "TOPRIGHT",
    "the default anchor uses the hovered action button even before tooltip ownership updates")
GameTooltip.GetOwner = function() return UIParent end

-- game menu button off, frame rate and latency on the minimap
check(MicroMenuContainer:GetAlpha() == 0, "the original game menu button is visually hidden with the old row")
mm:Stats()
check(mm.stats:GetText():find("60 fps", 1, true) and mm.stats:GetText():find("42 ms", 1, true),
    "frame rate and latency on the minimap: " .. tostring(mm.stats:GetText()))
M.ms = 420
mm:Stats()
check(mm.stats:GetText():find("ffd8503c", 1, true), "bad latency goes red")
M.ms = 42
mm.strip._scripts.OnEnter(mm.strip)
check(#(GameTooltip._lines or {}) >= 4, "hovering it shows home and world latency")

-- cast bar
do
    local custom = ns.CustomAuras
    local oldGet = C_UnitAuras.GetAuraDataByIndex
    C_UnitAuras.GetAuraDataByIndex = function(unit, index, filter)
        if unit == "player" and index == 1 and filter == "HELPFUL" then return { spellId = 444, icon = 44 } end
    end
    check(custom:Save("buff 444 player\ndebuff 555 target"), "custom indicators accept valid spell IDs")
    check(custom.cells[1]:IsShown() and not custom.cells[2]:IsShown(), "custom indicators show only matching effects")
    check(not custom:Save("buff invalid") and #custom:Rules() == 2, "invalid custom indicator input preserves saved rules")
    local oldCooldown = C_Spell.GetSpellCooldown
    C_Spell.GetSpellCooldown = function() return { startTime = GetTime(), duration = 8 } end
    check(custom:Save("cooldown 123") and custom.cells[1]:IsShown()
        and custom.cells[1].timer:GetText() == "8", "custom cooldown indicator shows remaining seconds")
    C_Spell.GetSpellCooldown = oldCooldown
    check(custom:Save(""), "custom indicators can be cleared")
    C_UnitAuras.GetAuraDataByIndex = oldGet
end
do
    local tracker, oldLog = ns.DungeonQuestTracker, C_QuestLog
    C_QuestLog = C_QuestLog or {}
    local log = C_QuestLog
    local oldInstance, oldInfo = IsInInstance, GetInstanceInfo
    local oldCount, oldLogInfo, oldObjectives = log.GetNumQuestLogEntries, log.GetInfo, log.GetQuestObjectives
    IsInInstance = function() return true, "party" end
    GetInstanceInfo = function() return "Ragefire Chasm" end
    log.GetNumQuestLogEntries = function() return 1 end
    log.GetInfo = function() return { questID = 5723, title = "Testing an Enemy's Strength" } end
    log.GetQuestObjectives = function() return { { text = "Troggs slain: 2/8", finished = false } } end
    tracker:Refresh()
    check(tracker.frame:IsShown() and tracker.title:GetText():find("Ragefire Chasm", 1, true)
        and tracker.lines[2]:GetText():find("Troggs slain", 1, true), "dungeon tracker shows active dungeon quest objectives")
    do
        local oldComplete = log.IsComplete
        tracker.lines[1].SetTextColor = function(self, r, g, b) self.testColor = { r, g, b } end
        tracker.lines[2].SetTextColor = function(self, r, g, b) self.testColor = { r, g, b } end
        log.IsComplete = function(id) return id == 5723 end
        tracker:Refresh()
        check(tracker.rowButtons[1].row.status == "Ready to turn in"
            and tracker.lines[2]:GetText() == "Ready to turn in"
            and tracker.rowButtons[1].statusIcon._texture:find("tracker%-quest"),
            "active finished quest displays ready to turn in without a completion checkmark")
        local _, _, _, titleX = tracker.lines[1]:GetPoint()
        local _, _, _, detailX = tracker.lines[2]:GetPoint()
        check(tracker.lines[1].testColor[1] == 1 and tracker.lines[2].testColor[2] == 0.85
            and tracker.lines[2].testColor[1] == 0.35 and detailX > titleX
            and tracker.rowButtons[1].questBackground:IsShown() and not tracker.rowButtons[2].questBackground:IsShown(),
            "ready status is green, its quest stays yellow, and details are indented under the header")
        log.IsComplete = function() return false end
        log.GetQuestObjectives = function() return { { text = "Troggs slain: 8/8", finished = true } } end
        tracker:Refresh()
        check(tracker.rowButtons[1].row.status == "In progress" and tracker.lines[2]:GetText() == "Troggs slain: 8/8",
            "a finished objective alone does not claim a quest is ready")
        log.IsComplete = nil
        log.GetInfo = function() return { questID = 5723, isComplete = true } end
        tracker:Refresh()
        check(tracker.lines[2]:GetText() == "Ready to turn in", "quest-log completion is used if the completion API is unavailable")
        log.IsComplete = oldComplete
        log.GetInfo = function() return { questID = 5723, title = "Testing an Enemy's Strength" } end
        log.GetQuestObjectives = function() return { { text = "Troggs slain: 2/8", finished = false } } end
    end
    IsInInstance = function() return false, "none" end
    tracker:SetTracked("rfc")
    check(tracker.frame:IsShown() and tracker:GetTracked() == "rfc" and tracker.title:GetText():find("Ragefire Chasm", 1, true),
        "a selected dungeon can be tracked outside the instance")
    tracker.collapse:Click()
    check(tracker.collapsed and ns.db.dungeonTrackerCollapsed and tracker.frame:GetHeight() == 22,
        "instance tracker can be minimized and remembers that preference")
    tracker.collapse:Click()
    check(not tracker.collapsed and tracker.lines[1]:IsShown(), "instance tracker restores its quest list")
    tracker.rowButtons[1]:Click()
    check(ns.InstanceGuide.frame:IsShown() and ns.InstanceGuide.view == "Quests"
        and ns.InstanceGuide.entry == tracker.rowButtons[1].row.quest,
        "clicking a tracked quest opens its guide details")
    ns.InstanceGuide.frame:Hide()
    ns.InstanceGuide.dungeon, ns.InstanceGuide.entry = nil, nil
    check(tracker.header:GetScript("OnDragStart") ~= nil and tracker.header:GetScript("OnDragStop") ~= nil,
        "instance tracker header can be dragged")
    do
        local read = tracker.Read
        tracker.Read = function()
            local rows = {}; for i = 1, 15 do rows[i] = {title = "Quest " .. i, status = "Not recorded"} end
            return "Test dungeon", rows, 0, 15, false
        end
        tracker:Refresh()
        tracker.frame:GetScript("OnMouseWheel")(tracker.frame, -1)
        check(tracker.offset == 3 and tracker.lines[1]:GetText():find("Quest 4", 1, true),
            "instance tracker scrolls through longer quest lists")
        tracker.Read, tracker.offset = read, 0
        tracker:Refresh()
    end
    check(#select(2, tracker:Read()) > 1, "tracking includes recorded quests beyond the active quest log")
    do
        local page, old = ns.Encyclopedia.QuestPage, ns.Encyclopedia.QuestPage.Status
        page.Status = function(entry) return entry.data.id == 5724 and "Completed" or "Not recorded" end
        local _, rows = tracker:Read(); local inside
        for _, row in ipairs(rows) do if row.title == "Returning the Lost Satchel" then inside = row end end
        check(inside and inside.status == "Completed" and inside.chain and inside.inside,
            "tracker distinguishes completed quests and recorded chain and inside starts")
        tracker:Refresh()
        local matching
        for _, row in ipairs(tracker.rowButtons) do if row.row and row.row.title == "Returning the Lost Satchel" then matching = row end end
        check(matching and matching.statusIcon._texture:find("tracker%-complete") and matching.chainIcon:IsShown()
            and matching.insideIcon:IsShown(), "tracker uses status, chain and inside icons")
        page.Status = old
    end
    tracker:SetTracked(nil)
    tracker:Refresh(); check(not tracker.frame:IsShown(), "dungeon tracker hides outside instances")
    IsInInstance, GetInstanceInfo = oldInstance, oldInfo
    log.GetNumQuestLogEntries, log.GetInfo, log.GetQuestObjectives = oldCount, oldLogInfo, oldObjectives
    C_QuestLog = oldLog
end
do
    local guide, page = ns.InstanceGuide, ns.Encyclopedia.QuestPage
    local oldStatus, oldFaction = page.Status, UnitFactionGroup
    UnitFactionGroup = function() return "Horde" end
    page.Status = function(entry) return entry.data.id == 1 and "Completed" or "Not recorded" end
    local done, total, unknown = guide:QuestProgress({quests = {{id=1,side="Horde"},{id=2,side="Alliance"},{id=3,side="Both"},{id=1,side="Horde"}}})
    check(done == 1 and total == 2 and not unknown, "instance progress counts each applicable quest once")
    page.Status = function() return "Unknown" end
    done, total, unknown = guide:QuestProgress({quests={{id=4,side="Horde"}}})
    check(done == 0 and total == 1 and unknown, "instance progress preserves unknown completion state")
    page.Status, UnitFactionGroup = oldStatus, oldFaction
    do
        local oldClass, oldFaction = UnitClass, UnitFactionGroup
        UnitFactionGroup = function() return "Horde" end
        UnitClass = function() return "Paladin", "PALADIN" end
        local sfk
        for _, dungeon in ipairs(guide:Instances()) do if dungeon.key == "sfk" then sfk = dungeon; break end end
        local _, count = guide:QuestProgress(sfk)
        check(count == 4, "Shadowfang Keep counts only Horde paladin quests, including Old Fire-Eye")
        local present = {}
        for _, row in ipairs(guide:QuestRows(sfk)) do
            for _, quest in ipairs(row.chain or {row.quest}) do present[quest.id] = true end
        end
        check(present[1098] and present[1013] and present[1014] and present[95140]
            and not present[1740] and not present[78261] and not present[1654],
            "Shadowfang quest rows hide other classes and the opposite faction")
        local tracker = ns.DungeonQuestTracker
        tracker:SetTracked("sfk")
        local _, trackedRows, _, trackedTotal = tracker:Read()
        local tracked = {}; for _, row in ipairs(trackedRows or {}) do tracked[row.title] = true end
        check(trackedTotal == 4 and tracked["Old Fire-Eye"] and not tracked["The Orb of Soran'ruk"] and not tracked["The Horn of Xelthos"],
            "the instance tracker uses the same class and faction filters")
        tracker:SetTracked(nil)
        UnitClass = function() return "Warlock", "WARLOCK" end
        local warlock = {}
        for _, row in ipairs(guide:QuestRows(sfk)) do
            for _, quest in ipairs(row.chain or {row.quest}) do warlock[quest.id] = true end
        end
        check(warlock[1740] and not warlock[95140] and not warlock[78261],
            "changing class rebuilds the quest list")
        local bits = { WARRIOR=1, PALADIN=2, HUNTER=4, ROGUE=8, PRIEST=16, SHAMAN=64, MAGE=128, WARLOCK=256, DRUID=1024 }
        local classChecks = true
        for class in pairs(bits) do
            UnitClass = function() return class, class end
            for _, dungeon in ipairs(ns.IndependentReference.DUNGEONS) do
                for _, quest in ipairs(tracker:Quests(dungeon)) do
                    if quest.class and (quest.side == "Both" or quest.side == "Horde") then
                        if tracker:QuestVisible(quest) ~= (quest.class:upper() == class) then classChecks = false end
                    end
                end
            end
        end
        check(classChecks, "every dungeon and raid applies its recorded class restrictions")
        local oldQuestDB = QuestDB
        UnitClass = function() return "Paladin", "PALADIN" end
        QuestDB = { requiredClasses = function(id) if id == 998100 then return bits.WARLOCK end end }
        check(not tracker:QuestVisible({id=998100, name="Questie-only restriction", side="Both"})
            and tracker:QuestVisible({id=998100, name="Forever override", side="Both", class="PALADIN"})
            and tracker:QuestVisible({id=998101, name="Normal quest", side="Both"})
            and tracker:QuestVisible({id=998102, name="Shared class quest", side="Both", classes="Paladin, Warrior"}),
            "Questie restrictions supplement missing class data without overriding explicit Forever data")
        QuestDB = oldQuestDB
        UnitClass, UnitFactionGroup = oldClass, oldFaction
        guide.chainCache = {}
    end
    guide:Toggle()
    check(guide.frame:IsShown() and guide.frame.title:GetText() == "Instance Guide" and guide.frame.instances:IsShown(),
        "instance guide opens on the full-width artwork grid")
    local rfc
    for _, d in ipairs(guide:Instances()) do if d.key == "rfc" then rfc = d; break end end
    guide:SelectDungeon(rfc)
    guide.frame.views.Quests:Click()
    check(not guide.frame.instances:IsShown() and guide.frame.banner:IsShown() and guide.frame.back:IsShown()
        and guide.frame.track:IsShown() and guide.frame.entries.rows[1].value ~= nil,
        "selecting a dungeon opens its own full-width page with quest list")
    do
        local chain
        for _, row in ipairs(guide:QuestRows(rfc)) do
            if row.quest.id == 5722 then chain = row.chain; break end
        end
        check(chain and #chain >= 2 and chain[2].id == 5724,
            "the Ragefire satchel quests use their recorded chain links")
        local marked
        for _, row in ipairs(guide.frame.entries.rows) do
            if row.data and row.data.quest and row.data.quest.id == 5722 then marked = row end
        end
        check(marked and marked.chainIcon:IsShown() and marked.chain:IsShown()
            and marked.sub:GetText():find("Chain 1/", 1, true),
            "quest chain is marked and identified in the instance guide")
        if marked then
            marked.chain:Click()
            local first, step
            for _, row in ipairs(guide.frame.entries.rows) do
                if row.data and row.data.quest and row.data.quest.id == 5722 then first = row end
                if row.data and row.data.quest and row.data.quest.id == 5724 then step = row end
            end
            local stepX
            if step then local _, _, _, x = step:GetPoint(); stepX = x end
            check(first and step and step:GetHeight() < first:GetHeight() and step:GetWidth() < first:GetWidth()
                and stepX == 25 and step.icon:GetWidth() < first.icon:GetWidth(),
                "expanded quest chain steps are smaller and indented under the starting quest")
            marked.chain:Click()
        end
    end
    do
        local oldJournal = _G.ForeverDungeonJournal_NS
        local oldLayers, oldTextures = C_Map.GetMapArtLayers, C_Map.GetMapArtLayerTextures
        local mapInstance = {name="Test Interior", bosses={{name="Test boss"}}, quests={}}
        _G.ForeverDungeonJournal_NS = {DUNGEON_MAPS={["Test Interior"]={
            floors={{texture="test-floor-one", label="Upper"}, {texture="test-floor-two", label="Lower"}},
            entrance={x=.2,y=.3}, bosses={{name="Test boss",x=.5,y=.6}, {name="Second boss",floor=2,x=.1,y=.2}},
        }}}
        guide:SelectDungeon(mapInstance)
        guide.frame.views.Map:Click()
        local canvas = guide.frame.mapPanel.canvas
        check(canvas:IsShown() and canvas.art:IsShown() and canvas.entrance:IsShown()
            and canvas.pins[1]:IsShown() and canvas.pins[1].value == mapInstance.bosses[1],
            "custom dungeon maps show their floor artwork, entrance and linked boss")
        local _, parent, anchor, x, y = canvas.pins[1]:GetPoint()
        check(parent == canvas and anchor == "TOPLEFT" and x == 300 and y == -240,
            "boss map markers use normalized map coordinates")
        canvas.pins[1]:Click()
        check(guide.view == "Bosses" and guide.entry == mapInstance.bosses[1], "map marker opens boss details")
        guide.frame.views.Map:Click()
        guide.frame.mapPanel.next:Click()
        check(guide.mapFloor == 2 and not canvas.entrance:IsShown() and canvas.pins[1].bossName == "Second boss"
            and guide.frame.mapPanel.floor:GetText():find("Lower", 1, true),
            "floor switching refreshes map markers and entrance")
        _G.ForeverDungeonJournal_NS = nil
        C_Map.GetMapArtLayers = function() return {{layerWidth=512,layerHeight=256,tileWidth=256,tileHeight=256}} end
        C_Map.GetMapArtLayerTextures = function() return {123, 456} end
        guide:SelectDungeon(rfc)
        check(guide.mapFloor == 1 and canvas.tiles[1]:IsShown() and canvas.tiles[2]:IsShown()
            and not canvas.art:IsShown() and not canvas.entrance:IsShown(),
            "client dungeon map tiles work without the journal and reset the selected floor")
        C_Map.GetMapArtLayers = nil
        C_Map.GetMapArtLayerTextures = nil
        guide:Render()
        check(canvas.tiles[1]:IsShown() and canvas.tiles[12]:IsShown(), "legacy dungeon map tiles provide an API fallback")
        guide:SelectDungeon({name="No interior", bosses={}, quests={}})
        check(guide.frame.mapPanel.message:IsShown() and not canvas:IsShown(), "missing interiors show a clear fallback")
        _G.ForeverDungeonJournal_NS = oldJournal
        C_Map.GetMapArtLayers, C_Map.GetMapArtLayerTextures = oldLayers, oldTextures
        guide:SelectDungeon(rfc)
        guide.frame.views.Quests:Click()
    end
    do
        local oldStatus = page.Status
        local status = "Ready to turn in"
        page.Status = function() return status end
        local row = guide.frame.entries.rows[1]
        local oldColor = row.name.SetTextColor
        row.name.SetTextColor = function(self, r, g, b) self.testColor = {r,g,b} end
        guide.entry = row.value
        guide:Render()
        check(row.name.testColor[1] == 1 and row.sub:GetText():find("|cff59d966Ready to turn in|r", 1, true)
            and guide.frame.detailPanel.meta:GetText():find("|cff59d966Ready to turn in|r", 1, true),
            "ready quests have yellow titles and green turn-in status in the list and details")
        status = "Completed"
        guide:Render()
        check(row.name.testColor[2] == .85 and row.sub:GetText():find("|cff59d966Completed|r", 1, true),
            "completed quests have green titles and status")
        status = "In progress"
        guide:Render()
        check(row.name.testColor[1] == 1 and row.sub:GetText():find("|cffffd140In progress|r", 1, true),
            "in-progress quests use yellow")
        row.name.SetTextColor, page.Status = oldColor, oldStatus
        guide:Render()
    end
    guide.frame.track:Click()
    check(ns.DungeonQuestTracker:GetTracked() == "rfc", "the guide starts the selected dungeon tracker")
    guide.frame.track:Click()
    check(ns.DungeonQuestTracker:GetTracked() == nil, "the guide stops the selected dungeon tracker")
    do
        local synthetic = { quests = {
            { id=998001, name="First step", side="Both", classic={next=998002} },
            { id=998002, name="Second step", side="Both", classic={previous=998001, next=998003} },
            { id=998003, name="Third step", side="Both", classic={previous=998002} },
        } }
        local rows = guide:QuestRows(synthetic)
        check(#rows == 1 and rows[1].quest.id == 998001 and #rows[1].chain == 3
            and rows[1].chainIndex == 1 and rows[1].chainLength == 3,
            "recorded sequential quests start as a collapsed chain")
        guide.chainOpen[998001] = true
        rows = guide:QuestRows(synthetic)
        check(#rows == 3 and rows[2].quest.id == 998002 and rows[2].depth == 1 and rows[3].quest.id == 998003
            and rows[2].chainIndex == 2 and rows[3].chainIndex == 3 and rows[3].chainLength == 3,
            "expanding a chain shows its later steps in order")
        guide.chainOpen[998001] = nil
    end
    guide.frame.back:Click()
    check(guide.frame.instances:IsShown() and not guide.frame.banner:IsShown(), "back returns to the instance artwork grid")
    guide:Toggle()
end
local cb = PlayerCastingBarFrame
local castPoint, castRel, castAnchor = cb.fuiCastLabel:GetPoint(1)
local castRight, castRightRel, castRightAnchor = cb.fuiCastLabel:GetPoint(2)
check(castPoint == "LEFT" and castRel == cb.fuiTextHost and castAnchor == "LEFT"
    and castRight == "RIGHT" and castRightRel == cb.fuiTextHost and castRightAnchor == "RIGHT"
    and cb.Text:GetParent() == cb and cb.fuiCastLabel:GetParent() == cb.fuiTextHost and cb.fuiTextHost:GetParent() == UIParent,
    "cast label is centered in an independent overlay while the native text remains in place")
cb.Text:SetText("Skinning")
check(cb.fuiCastLabel:GetText() == "Skinning" and cb.Text:GetAlpha() == 0,
    "native cast and interaction names are mirrored to the visible overlay")
cb:Hide()
check(not cb.fuiTextHost:IsShown(), "the cast text overlay hides with the cast bar")
local raisedLevel
cb.fuiTextHost.SetFrameLevel = function(_, level) raisedLevel = level end
cb.fuiTextHost.SetFrameStrata = function(self, strata) self.fuiTestStrata = strata end
cb:Show()
check(cb.fuiTextHost:IsShown(), "the cast text overlay returns with the cast bar")
check(raisedLevel >= cb:GetFrameLevel() + 10 and cb.fuiTextHost.fuiTestStrata == "FULLSCREEN_DIALOG",
    "interaction text draws above separate cast-bar containers")
cb.casting = true
cb.GetMinMaxValues = function() return 0, 3 end
cb.GetValue = function() return 1.25 end
cb._scripts.OnUpdate(cb, 0.11)
check(cb.fuiTimer:IsShown() and cb.fuiTimer:GetText() == "1.8s", "interaction bar shows time remaining")
cb.casting, cb.channeling = nil, true
cb.GetValue = function() return 0.6 end
cb._scripts.OnUpdate(cb, 0.11)
check(cb.fuiTimer:GetText() == "0.6s", "channeled casts count down from their current value")
cb.channeling = nil
cb._scripts.OnUpdate(cb, 0.11)
check(not cb.fuiTimer:IsShown(), "the timer disappears when no cast is active")
check(cb.Border:GetParent() == ns.hider and cb.Flash:GetParent() == ns.hider and cb.fuiEdge ~= nil,
    "the cast bar loses its frame and glows, gets the gold hairline")
cb.barType = "standard"
cb:UpdateBarFillTexture()
check(cb._fill == ns.FLAT and cb._fillColor[1] == ns.C.gold[1], "a cast fills flat gold")
local progressPoint, progressTexture, progressAnchor = cb.fuiProgressLine:GetPoint(1)
check(progressPoint == "TOPRIGHT" and progressTexture == cb:GetStatusBarTexture() and progressAnchor == "TOPRIGHT"
    and cb.Spark:GetAlpha() == 0, "interaction progress line follows the fill edge across the bar")
cb.GetReverseFill = function() return true end
cb:UpdateBarFillTexture()
progressPoint, progressTexture, progressAnchor = cb.fuiProgressLine:GetPoint(1)
check(progressPoint == "TOPLEFT" and progressTexture == cb:GetStatusBarTexture() and progressAnchor == "TOPLEFT",
    "reversed fills use the other progress edge")
cb.GetReverseFill = nil
cb.barType = "interrupted"
cb:UpdateBarFillTexture()
check(cb._fillColor[1] > 0.7 and cb._fillColor[2] < 0.3, "interrupted goes red")
check(OverlayPlayerCastingBarFrame == nil and PetCastingBarFrame.fuiEdge ~= nil,
    "the pet cast bar is styled even without an overlay cast bar")

-- swing timers
local sw = SwingTimerMainHandFrame
sw:SetSize(220, 16)
sw.GetEffectiveScale = function() return 0.9 end
cb.GetEffectiveScale = function() return 1 end
ns.modules.castbar:MatchSwingSize()
check(math.abs(cb:GetWidth() - 198) < 0.01 and math.abs(cb:GetHeight() - 14.4) < 0.01,
    "player cast and gathering bar matches the main-hand swing timer's on-screen size")
M.combat = true
sw:SetSize(240, 16)
ns.modules.castbar:MatchSwingSize()
check(math.abs(cb:GetWidth() - 198) < 0.01, "cast sizing waits until combat ends")
M.combat = false
M.fire("PLAYER_REGEN_ENABLED")
check(math.abs(cb:GetWidth() - 216) < 0.01, "cast size catches up after combat")
sw.StatusBar:SetSize(220, 10)
sw.StatusBar.GetEffectiveScale = function() return 0.9 end
ns.modules.castbar:MatchSwingSize()
check(math.abs(cb:GetHeight() - 9) < 0.01,
    "cast and gathering bars match the visible swing fill thickness")
check(math.abs(sw:GetScale() - 0.9) < 0.001, "swing timers are 10 percent smaller")
check(sw.Border:GetParent() == ns.hider and sw.fuiPanel ~= nil and sw.StatusBar._fill == ns.FLAT,
    "swing timers: flat bar on the dark panel")
sw:InitializeBarPresentation()
check(sw.StatusBar._fill == ns.FLAT, "and stay flat when the game sets them up again")
check(SwingTimerOffHandFrame.StatusBar._fillColor[1] == ns.C.muted[1], "off hand is the muted colour")
sw.out = true
sw:ApplyRangePresentation()
check(sw.fuiPanel.bg:GetAlpha() < 1, "out of range, the panel dims with the bar")
sw.out = false
sw:ApplyRangePresentation()

-- buffs and debuffs
local buff = BuffFrame.auraFrames[1]
check(buff.fuiEdge ~= nil and #ns.modules.auras.buttons == 3, "buff and debuff icons get the hairline (not the private aura spot)")
check(BuffFrame.auraFrames[2].fuiEdge.fuiPanel.bright,
    "a weapon enchant already active at login gets its bright edge immediately")
check(DebuffFrame.auraFrames[1].DebuffBorder:GetPoint() == "TOPLEFT", "the debuff colour hugs the icon")
buff:UpdateAuraType("TempEnchant")
check(buff.fuiEdge.fuiPanel.bright, "a weapon enchant gets the bright edge")

-- damage meter, which the game loads after us
M.loadMeter()
check(math.abs(DamageMeter:GetScale() - 22 / 28) < 0.001, "the damage meter and its edit-mode parent draw its title row 22 high")
DamageMeter:SetupSessionWindow(1, {})
local w = DamageMeterSessionWindow1
check(w.fuiPanel ~= nil and w.Header:GetAlpha() == 0, "the damage meter window gets the dark panel, no header bar")
check(w.SettingsDropdown.fuiPanel and w.SettingsDropdown.Icon:GetAlpha() == 0 and w.MinimizeButton.fuiPanel
    and w.SessionDropdown.Background:GetAlpha() == 0, "meter controls replace native artwork with themed buttons")
check(w.SessionDropdown.Text:GetAlpha() == 0 and w.SessionDropdown.SessionName:GetAlpha() ~= 0
    and w.SessionDropdown:GetWidth() >= 38, "the segment has room for its icon and session name without the generic ellipsis")
check(w.MinimizeButton:GetWidth() == 20 and w.MinimizeButton:GetHeight() == 20
    and w.SettingsDropdown:GetWidth() == 20 and w.SettingsDropdown:GetHeight() == 20
    and w.SessionDropdown:GetHeight() == 20 and w.DamageMeterTypeDropdown:GetHeight() == 20,
    "meter header controls have matching heights and compact icons")
local _, settingsAnchor, _, settingsGap, settingsY = w.SettingsDropdown:GetPoint()
local _, sessionAnchor, _, sessionGap, sessionY = w.SessionDropdown:GetPoint()
check(settingsAnchor == w.MinimizeButton and settingsGap == -3 and settingsY == 0
    and sessionAnchor == w.fuiReset and sessionGap == -3 and sessionY == 0,
    "meter buttons share a baseline and do not touch")
check(w.fuiReset ~= nil and w.fuiDragHandle ~= nil, "meter has a reset control and a draggable header")
DamageMeter.SetMovable = function(self, movable) self.testMovable = movable end
DamageMeter.StartMoving = function(self)
    assert(self.testMovable, "the game made the meter immovable")
    self.testMoving = true
end
DamageMeter.StopMovingOrSizing = function(self) self.testMoving = false end
DamageMeter.GetLeft = function() return 120 end
DamageMeter.GetTop = function() return 600 end
w.fuiDragHandle:GetScript("OnDragStart")(w.fuiDragHandle)
check(DamageMeter.testMoving, "dragging the meter header moves the edit-mode parent")
w.fuiDragHandle:GetScript("OnDragStop")(w.fuiDragHandle)
check(not DamageMeter.testMoving and ns.db.windowPos.damageMeter.x == 120, "meter drag saves its position")
w.fuiReset:GetScript("OnClick")(w.fuiReset)
check(M.meterResetCount == 1, "reset control resets combat sessions once")
M.instanceKind, M.instanceID = "party", 33
w:SetMinimized(true)
DamageMeter:Hide()
M.fire("PLAYER_ENTERING_WORLD", false, false)
check(M.meterResetCount == 2 and w.testMeterType == Enum.DamageMeterType.DamageDone
    and not w:IsMinimized() and DamageMeter:IsShown(), "entering a dungeon resets and opens Damage Done")
M.fire("ZONE_CHANGED_NEW_AREA")
M.fire("PLAYER_ENTERING_WORLD", false, true)
check(M.meterResetCount == 2, "duplicate zone events and reloads inside do not reset the meter")
M.instanceKind, M.instanceID = nil, nil
M.fire("ZONE_CHANGED_NEW_AREA")
ns.O().meterInstanceReset = false
M.instanceKind, M.instanceID = "raid", 409
w:SetMinimized(true)
M.fire("PLAYER_ENTERING_WORLD", false, false)
check(M.meterResetCount == 2 and not w:IsMinimized(), "automatic reset can be disabled separately from opening")
M.instanceKind, M.instanceID = nil, nil
M.fire("ZONE_CHANGED_NEW_AREA")
ns.O().meterInstanceReset = true
ns.O().meterInstanceOpen = false
w:SetMinimized(true)
M.instanceKind, M.instanceID = "party", 33
M.fire("PLAYER_ENTERING_WORLD", false, false)
check(M.meterResetCount == 3 and w:IsMinimized(), "automatic opening can be disabled separately from reset")
ns.O().meterInstanceOpen = true
M.instanceKind, M.instanceID = nil, nil
M.fire("ZONE_CHANGED_NEW_AREA")
w:SetMinimized(true)
check(w.fuiPlus:IsShown() and not w.fuiRule:IsShown(), "minimized meter shows its restore icon and compact header")
w:SetMinimized(false)
check(not w.fuiPlus:IsShown() and w.fuiRule:IsShown(), "restoring meter returns its normal header")
local source = w.MinimizeContainer.SourceWindow
check(source.fuiPanel ~= nil and source.Background:GetAlpha() == 0, "the meter's breakdown window gets the matching panel")
local entry = M.meterEntry(w.box)
check(not w.box._acquired or #w.box._acquired == 0, "meter rows are not hooked by the addon")
check(not source.ScrollBox._acquired or #source.ScrollBox._acquired == 0, "breakdown rows are not hooked by the addon")
check(entry.StatusBar._fill ~= ns.FLAT, "native combat rows remain untouched")
do
    ns.db.windowPos.damageMeter = { x = 321, y = 654 }
    M.fire("PLAYER_ENTERING_WORLD", false, true)
    local meterPoint, _, _, meterX, meterY = DamageMeter:GetPoint()
    check(meterPoint == "TOPLEFT" and meterX == 321 and meterY == 654,
        "meter position restores the latest drag rather than the initial position")
end
DamageMeter:SetupSessionWindow(1, DamageMeter.windowDataList[1])
check(math.abs(DamageMeter:GetScale() - 22 / 28) < 0.001, "reopening a meter does not repeatedly shrink it")

-- windows
local cf = CharacterFrame
check(cf.fuiPanel.edge == 1.35 and cf.fuiPanel.alpha == 1 and cf.Background:GetAlpha() == 0 and CharacterModelFrameBackgroundTopLeft:GetAlpha() == 0,
    "character window has a stronger gold edge and no native backdrop art")
check(cf.LeftPaneHost.art:GetAlpha() == 0 and cf.RightPaneHost.StoneBg:GetAlpha() == 0
    and M.characterDivider.art:GetAlpha() == 0 and PaperDollFrame.TopBackgroundStripHost.TopBackgroundStrip:GetAlpha() == 0,
    "Camelot's pane backgrounds, divider and gray header are hidden")
SetPaperDollBackground(CharacterModelScene)
check(CharacterModelScene.BackgroundOverlay:GetAlpha() == 0 and CharacterModelScene:IsShown(),
    "the model background stays hidden when the game refreshes the preview")
check(CharacterFrameTab1.Icon:GetAlpha() == 0 and CharacterFrameTab1.fuiCharacterIcon:GetWidth() == 38,
    "native character tab artwork is hidden and the custom icon is larger")
for i, icon in ipairs({ "character%-minimal", "reputation%-tab", "skills%-tab", "pvp%-tab", "currency%-tab", "statistics%-tab" }) do
    local tab = _G["CharacterFrameTab" .. i]
    check(tab.fuiCharacterIcon and tab.fuiCharacterIcon._texture:find(icon) and tab.Text:GetAlpha() == 0,
        "character tab " .. i .. " has its matching icon")
end
for i, icon in ipairs({ "statistics%-tab", "equipment%-tab", "titles%-tab" }) do
    local tab = _G["PaperDollSidebarTab" .. i]
    check(tab.fuiCharacterIcon and tab.fuiCharacterIcon._texture:find(icon) and tab.Icon:GetAlpha() == 0,
        "character sidebar tab " .. i .. " has its matching icon")
end
check(CharacterHeadSlot.fuiEquipmentEdge and CharacterFinger0Slot.fuiEquipmentEdge
    and CharacterHeadSlot.fuiEquipmentEdge.fuiPanel.noBg, "character gear slots keep their buttons and gain a subtle transparent edge")
check(CharacterHeadSlotFrame:GetParent() == CharacterHeadSlot and CharacterHeadSlot:GetNormalTexture() == CharacterHeadSlot._normal
    and CharacterHeadSlotFrame:GetAlpha() == 0 and CharacterHeadSlot._normal:GetAlpha() == 0
    and CharacterHeadSlot.BorderFrame:GetAlpha() == 0 and CharacterHeadSlot.icon:GetAlpha() == 1
    and CharacterHeadSlot.fuiEquipmentEdge.fuiPanel.edge == 1.15,
    "equipment's native frame is hidden, its item icon remains and its gold edge is visible")
check(CharacterFinger0Slot:GetNormalTexture() == CharacterFinger0SlotFrame and CharacterFinger0SlotFrame:GetAlpha() == 0,
    "a normal texture shared with the decorative slot frame remains owned by its button")
PaperDollItemSlotButton_Update(CharacterHeadSlot)
check(CharacterHeadSlot:GetNormalTexture() == CharacterHeadSlot._normal and CharacterHeadSlot._normal:GetAlpha() == 0,
    "native item updates retain the normal texture and the decorative border remains hidden")
do
    local previous = GetInventoryItemQuality
    local quality = 3
    GetInventoryItemQuality = function(_, slot) if slot == 1 then return quality end end
    PaperDollItemSlotButton_Update(CharacterHeadSlot)
    local glow = CharacterHeadSlot.fuiEquipmentEdge.fuiQualityGlow
    check(glow[1]:IsShown() and glow[1]._gradient.hi.b == ITEM_QUALITY_COLORS[3].b,
        "equipped rare items show the matching bag-style rarity glow")
    quality = 2; PaperDollItemSlotButton_Update(CharacterHeadSlot)
    check(glow[1]:IsShown() and glow[1]._gradient.hi.g == ITEM_QUALITY_COLORS[2].g,
        "equipped rarity glow updates when gear changes")
    quality = nil; PaperDollItemSlotButton_Update(CharacterHeadSlot)
    check(not glow[1]:IsShown() and CharacterHeadSlot.fuiEquipmentEdge.fuiPanel.noBg,
        "empty equipment slots retain their normal gold edge without a rarity glow")
    GetInventoryItemQuality = previous
end
local equipmentEdge = CharacterHeadSlot.fuiEquipmentEdge
cf:Hide(); cf:Show()
check(CharacterHeadSlot.fuiEquipmentEdge == equipmentEdge, "reopening character information does not duplicate equipment edges")
check(cf.fuiPanel ~= nil and cf.NineSlice:GetAlpha() == 0 and cf.PortraitContainer:GetAlpha() == 0
    and cf.Bg:GetParent() == ns.hider, "a window: the game's border, portrait and backdrop go, the dark panel comes")
check(cf.CloseButton._normalAtlas == "RedButton-Exit" and cf.CloseButton._pushedAtlas == "RedButton-exit-pressed",
    "windows use the native red-and-gold close button")
check(cf.Inset.fuiPanel ~= nil and cf.Inset.Bg:GetParent() == ns.hider, "its inset gets a lighter panel")
local t1, t2 = cf.parts.tab1, cf.parts.tab2
check(t1.Left:GetAlpha() == 0 and t1.fuiPanel.bright and not t2.fuiPanel.bright, "tabs go flat; the open one is bright")
PanelTemplates_DeselectTab(t1)
PanelTemplates_SelectTab(t2)
check(t2.fuiPanel.bright and not t1.fuiPanel.bright and t2.fuiTop:IsShown(), "switching tabs moves the bright one")
check(cf.parts.button.fuiPanel ~= nil and cf.parts.button.Left:GetAlpha() == 0, "panel buttons inside go flat")
check(cf.parts.dropdown.fuiPanel ~= nil and cf.parts.dropdown.Background:GetAlpha() == 0, "dropdowns too")
check(cf.parts.scroll.Track.Begin:GetAlpha() == 0, "and scroll bars")
local trainer = M.window("ClassTrainerFrame")
ShowUIPanel(trainer)
check(trainer.fuiPanel ~= nil, "any other standard window the game opens gets the look")
local store = M.window("AccountStoreFrame")
M.loadedAddons.Blizzard_AccountStore = true
M.fire("ADDON_LOADED", "Blizzard_AccountStore")
check(store.fuiPanel ~= nil, "a window in its own addon gets it once that loads (the shop)")
local forbidden = M.window("StoreFrame")
forbidden.IsForbidden = function() return true end
ShowUIPanel(forbidden)
check(forbidden.fuiPanel == nil, "a window the game keeps from addons is left alone")
local sparse = M.window("SparseCloseWindow")
sparse.CloseButton._n = nil
ShowUIPanel(sparse)
check(sparse.CloseButton._normalAtlas == "RedButton-Exit" and sparse.CloseButton._highlightAtlas == "RedButton-Highlight",
    "the red-and-gold close button is applied even when normal art was absent")

-- Layout hooks must be bounded during combat and replaceable afterward.
local protected = CreateFrame("Frame", nil, UIParent)
protected.IsProtected = function() return true end
local placements = 0
ns.Keep(protected, function(f)
    placements = placements + 1
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)
end)
M.combat = true
for i = 1, 30 do protected:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
check(placements == 1, "protected layout repairs wait until combat ends")
M.combat = false
M.fire("PLAYER_REGEN_ENABLED")
check(placements == 2, "a burst of combat layout updates repairs each frame once")
placements = 0
ns.Keep(protected, function(f)
    placements = placements + 1
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 20)
end)
check(placements == 1 and protected:GetPoint() == "BOTTOMLEFT",
    "replacing a placement reuses its hook without recursive re-entry")
protected:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
check(placements == 2 and protected:GetPoint() == "BOTTOMLEFT", "future repairs use the replacement placement once")
M.combat = true
ns.WhenSafe(function() error("test deferred failure") end)
M.combat = false
M.fire("PLAYER_REGEN_ENABLED")
check(#ns.errors == 1 and ns.errors[1]:find("after combat", 1, true), "deferred layout failures are visible in /fui errors")
wipe(ns.errors)

-- move mode
EventRegistry.callbacks["EditMode.Enter"]()
check(ns.moving, "opening Edit Mode shows the addon movement handles")
EventRegistry.callbacks["EditMode.Exit"]()
check(not ns.moving, "closing Edit Mode hides the addon movement handles")
EditModeManagerFrame = { IsEditModeActive = function() return true end, IsSnapEnabled = function() return true end,
    Grid = { gridSpacing = 20, IsShown = function() return true end, GetCenter = function() return 100, 100 end,
        GetEffectiveScale = function() return 1 end } }
local sx, sy = ns.SnapToGrid(112, 131, 20, 20)
check(sx == 110 and sy == 130, "Edit Mode snap aligns the nearest edge or center to the visible grid")
EditModeManagerFrame.IsSnapEnabled = function() return false end
sx, sy = ns.SnapToGrid(112, 131, 20, 20)
check(sx == 112 and sy == 131, "disabling Edit Mode snap preserves free positioning")
EditModeManagerFrame = nil
ns.ToggleMoveMode(true)
check(ns.moving, "move mode opens")
local healMover = ns.moveBoxes.healing
ns.db.healMoveLocked = true
local healingPos = ns.db.pos.healing
healMover._scripts.OnDragStart(healMover)
healMover._scripts.OnMouseUp(healMover, "RightButton")
check(not healMover.fuiDragging and ns.db.pos.healing == healingPos,
    "the healing lock prevents moving or resetting it in Edit Mode")
ns.db.healMoveLocked = false
local mover = ns.moveBoxes.minimap
mover:SetSize(200, 200) -- mock SetAllPoints does not derive dimensions
local priorPos = { x = 123, y = 456 }
ns.db.pos.minimap = priorPos
mover.GetCenter = function() return nil, nil end
mover._scripts.OnDragStart(mover)
mover._scripts.OnDragStop(mover)
check(ns.db.pos.minimap == priorPos, "an unmeasurable mover cannot start a drag or overwrite its position")
mover.GetCenter = function() return 100, 200 end
mover._scripts.OnDragStart(mover)
local _, follow = ns.modules.minimap.holder:GetPoint()
check(follow == mover and mover:GetWidth() == 200, "the element follows a sized drag handle")
mover.GetCenter = function() return nil, nil end
mover._scripts.OnDragStop(mover)
check(ns.db.pos.minimap == priorPos and not mover.fuiDragging, "missing coordinates after a drag preserve the previous position")
mover.GetCenter = function() return 100, 200 end
mover._scripts.OnDragStart(mover)
mover.GetCenter = function() return 300, 400 end
mover._scripts.OnDragStop(mover)
check(ns.db.pos.minimap.x == 300 and ns.db.pos.minimap.y == 400, "a measurable drag saves its position")
mover.GetCenter = function() return 300, 400 end
mover._scripts.OnDragStart(mover)
M.combat = true
mover:Hide()
check(not mover.fuiDragging, "entering combat cancels a drag safely")
M.combat = false
M.fire("PLAYER_REGEN_ENABLED")
local _, rel = ns.modules.minimap.holder:GetPoint()
check(rel == UIParent and ns.db.pos.minimap.x == 300, "after combat the element returns to its last saved position")
ns.ToggleMoveMode(false)
ns.db.pos.minimap = { x = 300, y = 500 }
ns.ResetPositions()
check(next(ns.db.pos) == nil, "reset clears saved spots")
M.combat = true
ns.ToggleMoveMode(true)
check(not ns.moving, "no move mode in combat")
M.combat = false

-- Edit Mode resizing and remembered windows (2026-11-26)
do
    ns.ToggleMoveMode(true)
    local xpBox, xpBar = ns.moveBoxes.xpbar, ns.modules.xpbar.holder
    local before = xpBar:GetScale()
    xpBox._scripts.OnMouseWheel(xpBox, 1)
    check(ns.db.scale.xpbar and math.abs(ns.db.scale.xpbar - 1.05) < 0.001
        and math.abs(xpBar:GetScale() - before * 1.05) < 0.001, "scrolling over a handle resizes its element and saves it")
    check(ns.db.pos.xpbar ~= nil, "resizing pins the element's center so it grows evenly")
    xpBox._scripts.OnMouseUp(xpBox, "RightButton")
    check(ns.db.scale.xpbar == nil and math.abs(xpBar:GetScale() - before) < 0.001 and ns.db.pos.xpbar == nil,
        "right-click puts both the position and the size back")
    for _ = 1, 40 do xpBox._scripts.OnMouseWheel(xpBox, 1) end
    check(math.abs(ns.db.scale.xpbar - 2) < 0.001, "sizes stop at twice the normal size")
    xpBox._scripts.OnMouseUp(xpBox, "RightButton")

    local microBox = ns.moveBoxes.micro
    local oldMicro = ns.db.opts.microScale
    microBox._scripts.OnMouseWheel(microBox, -1)
    check(math.abs(ns.db.opts.microScale - ((oldMicro or 1) - 0.05)) < 0.001
        and math.abs(ns.modules.micro.strip:GetScale() - ns.db.opts.microScale) < 0.001,
        "the micro menu's handle changes its own Menu scale setting")
    ns.db.opts.microScale = oldMicro
    check(ns.moveBoxes.tooltip.grip == nil, "the tooltip anchor has a position only")

    local tracker = ns.DungeonTracker or (ns.modules.dungeontracker and ns.modules.dungeontracker.T)
    local hiddenFrame = _G.ForeverUIDungeonQuestTracker
    if hiddenFrame then
        hiddenFrame:Hide()
        ns.ToggleMoveMode(false); ns.ToggleMoveMode(true)
        local hb = ns.moveBoxes.dungeonQuestTracker
        check(hb:IsShown() and hb.label:GetText():find("(hidden)", 1, true), "hidden elements still get a handle in Edit Mode")
    end

    -- another addon's frame with its own saving joins Edit Mode
    local ext = CreateFrame("Frame", "ForeverGoldTracker", UIParent)
    ext:SetSize(286, 22); ext:SetMovable(true)
    ext.StartMoving = ext.StartMoving or function() end
    ext.StopMovingOrSizing = ext.StopMovingOrSizing or function() end
    local calls = {}
    ext.fuiExternal = { save = function() calls.save = true end, getScale = function() return calls.scale or 1 end,
        setScale = function(s) calls.scale = s end, reset = function() calls.reset = true end }
    ns.ToggleMoveMode(false); ns.ToggleMoveMode(true)
    local eb = ns.moveBoxes.goldTracker
    check(eb and eb:IsShown(), "the farming tracker gets an Edit Mode handle")
    eb._scripts.OnMouseWheel(eb, 1)
    check(calls.scale and math.abs(calls.scale - 1.05) < 0.001, "its handle resizes it through its own setting")
    eb._scripts.OnDragStart(eb); eb._scripts.OnDragStop(eb)
    check(calls.save, "moving it lets it save its own position")
    eb._scripts.OnMouseUp(eb, "RightButton")
    check(calls.reset, "right-click resets it")
    ns.ToggleMoveMode(false)

    -- a window opens where it was left and at the size it was given
    local win = CreateFrame("Frame", "ForeverUITestWindow", UIParent)
    win:SetSize(300, 200); win:SetPoint("CENTER"); win:SetMovable(true)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    ns.RememberWindow(win, "testWindow")
    win.GetLeft = function() return 140 end
    win.GetTop = function() return 620 end
    win._scripts.OnDragStop(win)
    check(ns.db.windowPos.testWindow.x == 140 and ns.db.windowPos.testWindow.y == 620, "dragging a window saves where it was left")
    ns.db.windowScale.testWindow = 1.2
    win:Hide(); win:ClearAllPoints(); win:SetPoint("CENTER"); win:Show()
    local point, _, _, x, y = win:GetPoint()
    check(point == "TOPLEFT" and x == 140 and y == 620 and math.abs(win:GetScale() - 1.2) < 0.001,
        "opening the window again puts it back, at its saved size")
    check(win.fuiGrip ~= nil, "windows have a resize grip")
    ns.db.windowPos.testWindow, ns.db.windowScale.testWindow = nil, nil
    for _, name in ipairs({ "encyclopedia", "instanceGuide", "settings", "trainerGuide" }) do
        ns.db.windowPos[name] = nil
    end
end

-- The wider character page consumes the game's complete stat data, and
-- restores the native scroll view when it cannot fit or the sidebar changes.
do
    local categories = {}
    for i = 1, 4 do
        categories[#categories + 1] = { isHeader = true, name = "Group " .. i }
        categories[#categories + 1] = { name = "Stat A", statIndex = 1 }
        categories[#categories + 1] = { name = "Stat B", statIndex = 2 }
    end
    local layout, count = ns.ArrangeCharacterStats(categories, 140)
    check(count == 2 and layout[1].column == layout[2].column and layout[4].column ~= layout[1].column
        and layout[7].column == layout[1].column and layout[10].column == layout[4].column,
        "stat categories stay together and are balanced across columns")
    local create = CreateFrame
    CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        if template == "CharacterStatFrameScrollBoxLabelElementTemplate"
            or template == "CharacterStatFrameScrollBoxIconElementTemplate" then
            f.Background = f:CreateTexture()
            f.Init = function(self, data) self.statData = data end
        end
        return f
    end
    CharacterFrame:SetSize(500, 280); CharacterFrame:Show()
    CharacterFrame.activeSubframe = "PaperDollFrame"
    CharacterFrame.LeftPaneHost:SetWidth(398)
    CharacterFrame.RightPaneHost:SetWidth(233)
    CharacterFrame:UpdateTitle()
    local headingPoint, headingRelative, _, _, headingY = PaperDollLevelInfo:GetPoint()
    check(CharacterFrame._title == "Character" and ns.modules.characterpage.nameLabel:GetText() == "Xeon"
        and headingPoint == "TOP" and headingRelative == CharacterFrame.LeftPaneHost and headingY == -25,
        "character heading shows the page title, name, and lowered level")
    CharacterStatsPaneScrollBox = CreateFrame("Frame", "CharacterStatsPaneScrollBox", CharacterFrame)
    CharacterStatsPaneScrollBox:SetHeight(216)
    CharacterStatsPaneScrollBox.ScrollBox = CreateFrame("Frame", nil, CharacterStatsPaneScrollBox)
    CharacterStatsPaneScrollBox.ScrollBar = CreateFrame("Frame", nil, CharacterStatsPaneScrollBox)
    CharacterStatsPaneScrollBox.UpdateStats = function(self, data) self.elementData = data end
    local data = { { isHeader = true, name = "General" } }
    for i = 1, 18 do data[#data + 1] = { name = "STAT" .. i, statIndex = i, unit = "player" } end
    CharacterStatsPaneScrollBox.elementData = data
    local page = ns.modules.characterpage
    page:HookNativeStats()
    page:Refresh()
    check(page.panel and page.panel:IsShown() and #page.rows == #data and CharacterFrame:GetWidth() > 500,
        "the character page displays all native stats in multiple columns and widens the window")
    check(not page.panel.fuiBackground and page.rows[2].Background:GetAlpha() == 0,
        "stats share the window background without the native gray row artwork")
    check(CharacterStatsPaneScrollBox.ScrollBox:GetAlpha() == 0 and CharacterStatsPaneScrollBox.ScrollBar:GetAlpha() == 0,
        "the native scroll list is hidden after replacement rows are ready")
    local newData = { { isHeader = true, name = "General" }, { name = "UPDATED", statIndex = 1, unit = "player" } }
    CharacterStatsPaneScrollBox:UpdateStats(newData)
    check(page.rows[2].statData == newData[2], "changed character stats refresh immediately when the game updates them")
    CharacterStatsPaneScrollBox:Hide()
    CharacterFrame.activeSubframe = "ReputationFrame"
    CharacterFrame:UpdateTitle()
    check(CharacterFrame._title == "Reputation", "other tabs retain their own title")
    CharacterFrame:UpdateSize()
    page:Refresh()
    check(not page.panel:IsShown() and CharacterStatsPaneScrollBox.ScrollBox:GetAlpha() == 1
        and CharacterFrame:GetWidth() > 500
        and CharacterFrame.LeftPaneHost:GetWidth() + CharacterFrame.RightPaneHost:GetWidth() == CharacterFrame:GetWidth(),
        "other tabs keep the wide window and reserve space for their details")
    CharacterFrame.activeSubframe = "PVPRankFrame"
    CharacterFrame:UpdateSize()
    check(CharacterFrame.LeftPaneHost:GetWidth() + CharacterFrame.RightPaneHost:GetWidth() == CharacterFrame:GetWidth(),
        "PvP details also remain within the window")
    StatisticsFrame = CreateFrame("Frame", "StatisticsFrame", CharacterFrame)
    StatisticsFrame.ScrollBox = CreateFrame("Frame", nil, StatisticsFrame)
    StatisticsFrame.ScrollBox:SetPoint("TOPLEFT", CharacterFrame.LeftPaneHost, "TOPLEFT", 10, -40)
    StatisticsFrame.ScrollBox:SetPoint("BOTTOMRIGHT", CharacterFrame.LeftPaneHost, "BOTTOMRIGHT", -25, 15)
    StatisticsFrame.ScrollBar = CreateFrame("Frame", nil, StatisticsFrame)
    StatisticsFrame.ScrollBar:SetPoint("TOPLEFT", StatisticsFrame.ScrollBox, "TOPRIGHT", 5, -2)
    CharacterFrame.RightPaneToggleButton = CreateFrame("Button", nil, CharacterFrame)
    CharacterFrame.RightPaneToggleButton:SetPoint("TOPRIGHT", CharacterFrame.LeftPaneHost, "TOPRIGHT", -6, -6)
    CharacterFrame.activeSubframe = "StatisticsFrame"
    CharacterFrame:UpdateSize()
    page:Refresh()
    local point, relative, relativePoint, x, y = StatisticsFrame.ScrollBox:GetPoint(2)
    local _, scrollbarRelative = StatisticsFrame.ScrollBar:GetPoint(1)
    check(point == "BOTTOMRIGHT" and relative == CharacterFrame and relativePoint == "BOTTOMRIGHT"
        and x == -25 and y == 15 and scrollbarRelative == StatisticsFrame.ScrollBox,
        "statistics list and its scrollbar extend to the character window edge")
    local _, arrowRelative, _, _, arrowY = CharacterFrame.RightPaneToggleButton:GetPoint(1)
    check(arrowRelative == CharacterFrame and arrowY == -26, "statistics pane arrow aligns with the window edge")
    CharacterFrame.activeSubframe = "PaperDollFrame"
    CharacterFrame:UpdateSize()
    local _, restoredRelative = CharacterFrame.RightPaneToggleButton:GetPoint(1)
    check(restoredRelative == CharacterFrame.LeftPaneHost, "other tabs restore the pane arrow position")
    check(CharacterFrame.LeftPaneHost:GetWidth() == 398 and CharacterFrame:GetWidth() > 500,
        "returning to character restores the equipment pane while preserving the window width")
    CharacterStatsPaneScrollBox:Show(); CharacterStatsPaneScrollBox.elementData = data
    local screenWidth = UIParent:GetWidth(); UIParent:SetWidth(540)
    page:Refresh()
    check(not page.panel:IsShown() and CharacterStatsPaneScrollBox.ScrollBox:GetAlpha() == 1,
        "on a small screen the native scroll list remains usable")
    UIParent:SetWidth(screenWidth)
    page:Refresh()
    check(page.panel:IsShown(), "the wider layout returns when space is available")
    local combatFrames = { CharacterFrame, CharacterFrame.LeftPaneHost, CharacterStatsPaneScrollBox,
        CharacterStatsPaneScrollBox.ScrollBox, CharacterStatsPaneScrollBox.ScrollBar, page.panel }
    for _, frame in ipairs(combatFrames) do frame.IsProtected = function() return M.characterProtected or false end end
    M.combat = true
    M.fire("PLAYER_REGEN_DISABLED")
    M.advance(0.1)
    CharacterFrame:Hide(); CharacterFrame:UpdateSize(); CharacterFrame:Show()
    check(CharacterFrame:GetWidth() > 500 and page.panel:IsShown() and CharacterStatsPaneScrollBox.ScrollBox:GetAlpha() == 0,
        "an unprotected character window stays wide and keeps its stat columns when opened in combat")
    local combatData = { { isHeader = true, name = "General" }, { name = "COMBAT UPDATED", statIndex = 1, unit = "player" } }
    CharacterStatsPaneScrollBox:UpdateStats(combatData)
    check(page.rows[2].statData == combatData[2], "the wide stats update in combat when the frames are unprotected")
    M.characterProtected = true
    page:Refresh()
    check(not page.panel:IsShown() and CharacterStatsPaneScrollBox.ScrollBox:GetAlpha() == 1
        and CharacterStatsPaneScrollBox.ScrollBar:GetAlpha() == 1,
        "protected frames fall back to native stats without changing their layout")
    CharacterFrame:Hide(); CharacterFrame:SetWidth(500); CharacterFrame:Show()
    CharacterFrame:UpdateSize(); page:Refresh()
    check(CharacterFrame:GetWidth() == 500 and not page.panel:IsShown()
        and CharacterStatsPaneScrollBox.ScrollBox:GetAlpha() == 1,
        "opening a narrow character window in combat does not draw stats outside it")
    M.combat = false
    M.characterProtected = false
    CharacterStatsPaneScrollBox.elementData = data
    M.fire("PLAYER_REGEN_ENABLED")
    check(CharacterFrame:GetWidth() > 500 and page.panel:IsShown() and CharacterStatsPaneScrollBox.ScrollBox:GetAlpha() == 0,
        "leaving combat restores the full width and multi-column statistics")
    M.combat = true
    M.characterProtected = true
    CharacterStatsPaneScrollBox:Hide()
    page:Refresh()
    check(CharacterFrame:GetWidth() > 500, "the protected character layout is not resized during combat")
    M.combat = false
    M.characterProtected = false
    page:Refresh()
    check(CharacterFrame:GetWidth() > 500 and CharacterStatsPaneScrollBox.ScrollBox:GetAlpha() == 1,
        "the native layout is restored after combat")
    CreateFrame = create
end

-- A late-loaded Camelot profession window keeps functional art while replacing
-- its specific parchment background and side-tab backdrop.
do
    local f = M.window("ProfessionsFrame")
    f.GetName = function() return "ProfessionsFrame" end
    f.StartMoving = function(self) self._moving = true end
    f.StopMovingOrSizing = function(self) self._moving = false end
    f.CraftingPage = CreateFrame("Frame", nil, f)
    local parchment, icon = f.CraftingPage:CreateTexture(), f.CraftingPage:CreateTexture()
    parchment.GetAtlas = function() return "Profession-Background-Template2" end
    icon.GetAtlas = function() return "some-recipe-icon" end
    f.CraftingPage.GetRegions = function() return parchment, icon end
    f.CraftingPage.SchematicForm = CreateFrame("Frame", nil, f.CraftingPage)
    local form = f.CraftingPage.SchematicForm
    form.Reagents = CreateFrame("Frame", nil, form)
    form.GetBottom = function() return 0 end
    form.Reagents.GetBottom = function() return 180 end
    form.Background, form.MinimalBackground = form:CreateTexture(), form:CreateTexture()
    form.NineSlice = CreateFrame("Frame", nil, form)
    form.recipeIcon = form:CreateTexture()
    local copper = form:CreateTexture()
    copper.GetAtlas = function() return "common-insideframe" end
    form.GetRegions = function() return copper, form.recipeIcon end
    f.CraftingPage.RecipeList = CreateFrame("Frame", nil, f.CraftingPage)
    f.CraftingPage.RecipeList.ScrollBox = CreateFrame("Frame", nil, f.CraftingPage.RecipeList)
    f.CraftingPage.RecipeList.Background = f.CraftingPage.RecipeList:CreateTexture()
    f.CraftingPage.RecipeList.BackgroundNineSlice = CreateFrame("Frame", nil, f.CraftingPage.RecipeList)
    f.CraftingPage.Refresh = function() form.Background:SetAlpha(1); form.MinimalBackground:SetAlpha(1) end
    f.BookPage = CreateFrame("Frame", nil, f)
    f.BookPage.ProfessionsContentFrame = CreateFrame("Frame", nil, f.BookPage)
    local cards = f.BookPage.ProfessionsContentFrame
    cards.PrimaryProfession1 = CreateFrame("Frame", nil, cards)
    cards.PrimaryProfession1.Background = cards.PrimaryProfession1:CreateTexture()
    cards.PrimaryProfession1.skillIcon = cards.PrimaryProfession1:CreateTexture()
    cards.PrimaryProfession2 = CreateFrame("Frame", nil, cards)
    cards.PrimaryProfession2.Background = cards.PrimaryProfession2:CreateTexture()
    cards.SecondaryProfession1 = CreateFrame("Frame", nil, cards)
    cards.SecondaryProfession1.Background = cards.SecondaryProfession1:CreateTexture()
    cards.SecondaryProfession2 = CreateFrame("Frame", nil, cards)
    cards.SecondaryProfession3 = CreateFrame("Frame", nil, cards)
    local rank = CreateFrame("Frame", nil, cards.SecondaryProfession1)
    rank:SetWidth(100)
    rank.Rank = CreateFrame("Frame", nil, rank)
    rank.Rank.Text = rank.Rank:CreateFontString()
    rank.Background, rank.Border, rank.Fill, rank.Flare = rank:CreateTexture(), rank:CreateTexture(), rank:CreateTexture(), rank:CreateTexture()
    rank.ratio = 63 / 75
    rank.Update = function(self, info) self.ratio = info.skillLevel / info.maxSkillLevel end
    cards.SecondaryProfession1.StatusBar, cards.SecondaryProfession1.skillLine = rank, 393
    f.BookPage.FormatProfession = function(_, card) card.Background:SetAlpha(1) end
    form.GetRecipeInfo = function() return { recipeID = 42 } end
    local originalGold = ForeverGold
    ForeverGold = {
        Char = function() return { bags = { [200] = 1 }, recipes = { Smithing = { [42] = { o = 100, y = 1, r = { { 200, 2 } } } } } } end,
        EvalRecipe = function(rec) return { cost = 100, price = 200, profit = 90, parts = { { id = 200, qty = 2, each = 50, src = "ah" } } } end,
        ItemName = function(id) return "Bronze Bar" end,
        Money = function(v) return tostring(v) .. "c" end,
        Profit = function(v) return "+" .. tostring(v) .. "c" end,
        R = function() return { lastScan = 1 } end,
        Ago = function() return "5m ago" end,
    }
    local tab = CreateFrame("Frame", nil, f)
    tab.Background, tab.Icon, tab.SelectedTexture = tab:CreateTexture(), tab:CreateTexture(), tab:CreateTexture()
    f.Professions1Tab = tab
    M.fire("ADDON_LOADED", "Blizzard_Professions")
    f.TitleContainer._scripts.OnMouseDown(f.TitleContainer, "LeftButton")
    check(f._moving, "profession window begins moving from its title")
    f.TitleContainer._scripts.OnMouseUp(f.TitleContainer, "LeftButton")
    check(not f._moving and ns.db.windowPos.ProfessionsFrame.x == 900 and ns.db.windowPos.ProfessionsFrame.y == 700,
        "profession window saves the dragged position")
    f:Hide(); f:Show()
    local windowPoint, _, _, windowX, windowY = f:GetPoint()
    check(windowPoint == "TOPLEFT" and windowX == 900 and windowY == 700, "profession window restores its position on reopen")
    f.ofaMovable = true; OneForAllDB.qol.moveWindows = true
    f.TitleContainer._scripts.OnMouseDown(f.TitleContainer, "LeftButton")
    check(not f._moving, "OneForAll retains control when its window mover is enabled")
    f.ofaMovable = nil; OneForAllDB.qol.moveWindows = false
    M.combat = true
    f.TitleContainer._scripts.OnMouseDown(f.TitleContainer, "LeftButton")
    check(not f._moving, "window dragging does not start during combat")
    M.combat = false
    check(parchment:GetAlpha() == 0 and icon:GetAlpha() == 1,
        "profession parchment is removed without hiding recipe art")
    check(not tab.fuiPanel and tab.Background:GetAlpha() == 1 and tab.Icon:GetAlpha() == 1,
        "profession tabs retain their shaped native artwork without rectangular borders")
    tab:SetChecked(true)
    check(tab.SelectedTexture:GetAlpha() == 1,
        "the selected profession tab retains its native shaped highlight")
    check(f.CraftingPage.RecipeList.fuiPanel and form.fuiPanel and cards.PrimaryProfession1.fuiPanel,
        "crafting sections and overview cards get the gold panel theme")
    check(cards.PrimaryProfession1.fuiPanel.edge == 0 and cards.fuiProfessionDividers.primary
        and cards.fuiProfessionDividers.secondary and cards.fuiProfessionDividers.secondary2
        and cards.fuiProfessionDividers.secondary3, "profession cards share single aligned separators")
    check(f.CraftingPage.fuiEstimate and f.CraftingPage.fuiEstimate.cost.value:GetText():find("100c", 1, true)
        and f.CraftingPage.fuiEstimate.profit.value:GetText():find("+90c", 1, true)
        and f.CraftingPage.fuiEstimate.age:GetText():find("5m ago", 1, true),
        "profession estimate uses Forever Gold's cost, profit and scan age")
    local _, ageRight = f.CraftingPage.fuiEstimate.age:GetPoint(2)
    local valueRight = f.CraftingPage.fuiEstimate.profit.value:GetPoint(2)
    check(ageRight == f.CraftingPage.fuiEstimate and valueRight == "BOTTOMRIGHT",
        "estimate labels and values are constrained to their containers")
    check(rank.fuiRankFill and math.abs(rank.fuiRankFill:GetWidth() - 98 * 63 / 75) < 0.01
        and rank.Background:GetAlpha() == 0 and rank.Fill:GetAlpha() == 0,
        "skinning keeps its real progress in a flat themed skill bar")
    local labelPoint, labelAnchor, labelRelative, labelX, labelY = rank.Rank.Text:GetPoint()
    check(labelPoint == "CENTER" and labelAnchor == rank and labelRelative == "CENTER" and labelX == 0 and labelY == 0,
        "profession rank text is centered on the new bar")
    rank:Update({ professionID = 393, skillLevel = 75, maxSkillLevel = 75 })
    check(math.abs(rank.fuiRankFill:GetWidth() - 98) < 0.01, "profession progress refreshes when the rank changes")
    local craftCost = f.CraftingPage.fuiCraftCost
    local costPoint, costAnchor, costRelative = craftCost:GetPoint()
    local estimatePoint, estimateAnchor, estimateRelative = f.CraftingPage.fuiEstimate:GetPoint()
    check(craftCost:GetParent() == form and costPoint == "TOPLEFT" and costAnchor == form.Reagents
        and costRelative == "BOTTOMLEFT" and estimatePoint == "TOPLEFT" and estimateAnchor == craftCost
        and estimateRelative == "BOTTOMLEFT",
        "crafting cost sits below the reagents, the estimate below it, outside the recipe list")
    check(craftCost.total.value:GetText() == "100c" and craftCost.have.value:GetText() == "50c"
        and craftCost.buy.value:GetText() == "50c",
        "crafting cost: per craft, what's in your bags and what's left to buy")
    craftCost._scripts.OnEnter(craftCost)
    check(craftCost.data.lines[1][1] == "2 x Bronze Bar" and craftCost.data.lines[1][2]:find("auction", 1, true),
        "hovering the crafting cost lists each reagent's price and source")
    craftCost._scripts.OnLeave(craftCost)
    ForeverGold.EvalRecipe = function() return { cost = 100, bop = true } end
    f.CraftingPage:Refresh()
    check(f.CraftingPage.fuiEstimate.profit.value:GetText():find("Not sellable", 1, true),
        "bound items are not advertised as auction profit")
    ForeverGold.EvalRecipe = function() return { cost = nil, price = nil } end
    f.CraftingPage:Refresh()
    check(f.CraftingPage.fuiEstimate.cost.value:GetText():find("unknown", 1, true)
        and f.CraftingPage.fuiEstimate.profit.value:GetText():find("unknown", 1, true),
        "missing prices are not treated as zero")
    ForeverGold = nil
    f.CraftingPage:Refresh()
    check(f.CraftingPage.fuiEstimate.status:GetText() == "Forever Gold prices unavailable",
        "crafting stays usable without Forever Gold")
    ForeverGold = originalGold
    check(form.Background:GetAlpha() == 0 and form.MinimalBackground:GetAlpha() == 0
        and form.NineSlice:GetAlpha() == 0 and form.recipeIcon:GetAlpha() == 1
        and copper:GetAlpha() == 0 and f.CraftingPage.RecipeList.Background:GetAlpha() == 0
        and f.CraftingPage.RecipeList.BackgroundNineSlice:GetAlpha() == 0,
        "profession-specific schematic and list backgrounds are removed without hiding recipe icons")
    check(cards.PrimaryProfession1.Background:GetAlpha() == 0 and cards.SecondaryProfession1.Background:GetAlpha() == 0
        and cards.PrimaryProfession1.skillIcon:GetAlpha() == 1, "Camelot overview cards lose their backgrounds and keep their icons")
    f.BookPage:FormatProfession(cards.PrimaryProfession1)
    check(cards.PrimaryProfession1.Background:GetAlpha() == 0, "updating a profession does not restore its card background")
    f.CraftingPage:Refresh()
    check(form.Background:GetAlpha() == 0 and form.MinimalBackground:GetAlpha() == 0,
        "profession backgrounds remain hidden after switching or minimizing the view")
    f:Hide(); parchment:SetAlpha(1); f:Show()
    check(parchment:GetAlpha() == 0, "profession styling is reapplied when the window opens")
end

-- Legacy's artwork can be replaced without touching its interactive tree.
do
    local f = M.window("LegacySystemFrame")
    f.RewardTrackPage = CreateFrame("Frame", nil, f)
    f.RewardTrackPage.Background = f.RewardTrackPage:CreateTexture()
    f.RewardTrackPage.Icon = f.RewardTrackPage:CreateTexture()
    f.RewardTrackPage.Points = f.RewardTrackPage:CreateFontString()
    f.TitleContainer = CreateFrame("Frame", nil, f)
    f.TitleContainer.TitleText = f.TitleContainer:CreateFontString()
    local reward = CreateFrame("Frame", nil, f.RewardTrackPage)
    reward.RewardCardBG, reward.IconBorder, reward.LevelSquare = reward:CreateTexture(), reward:CreateTexture(), reward:CreateTexture()
    reward.Icon, reward.Level = reward:CreateTexture(), reward:CreateFontString()
    reward.ApplyAlpha = function(self) self.RewardCardBG:SetAlpha(1) end
    reward.Refresh = function() end
    local track = CreateFrame("Frame", nil, f.RewardTrackPage)
    track.GetElements = function() return { reward } end
    local nativeFrame = CreateFrame("Frame", nil, track)
    local nativeCardArt = nativeFrame:CreateTexture()
    nativeCardArt.GetAtlas = function() return "Legacy-Rewards-Tracker-Cards-Disable" end
    nativeFrame.GetRegions = function() return nativeCardArt end
    track.GetChildren = function() return nativeFrame end
    f.RewardTrackPage.LegacyRewardProgressFrame = track
    f.ChallengesPage = CreateFrame("Frame", nil, f)
    f.ChallengesPage.Background = f.ChallengesPage:CreateTexture()
    f.ChallengesPage.LegacyChallengePointSummary = CreateFrame("Frame", nil, f.ChallengesPage)
    local challengeShield = CreateFrame("Frame", nil, f.ChallengesPage.LegacyChallengePointSummary)
    challengeShield.Icon = challengeShield:CreateTexture(); challengeShield.Points = challengeShield:CreateFontString()
    challengeShield.Icon:SetSize(46, 66)
    f.ChallengesPage.LegacyChallengePointSummary.Shield = challengeShield
    local challengeCard = CreateFrame("Frame", nil, f.ChallengesPage)
    challengeCard.Shield = CreateFrame("Frame", nil, challengeCard)
    challengeCard.Shield.Icon = challengeCard.Shield:CreateTexture()
    challengeCard.Shield.Icon:SetSize(35, 51)
    challengeCard.Shield.Points = challengeCard.Shield:CreateFontString()
    f.ChallengesPage.DetailPane = CreateFrame("Frame", nil, f.ChallengesPage)
    f.ChallengesPage.DetailPane.ScrollBox = { ForEachFrame = function(_, fn) fn(challengeCard) end }
    f.Tabs = {}
    for i = 1, 3 do
        local tab = CreateFrame("Frame", nil, f)
        tab.Background, tab.Icon, tab.SelectedTexture = tab:CreateTexture(), tab:CreateTexture(), tab:CreateTexture()
        f.Tabs[i] = tab
    end
    f.currentPage = 1
    f.TreePage = CreateFrame("Frame", nil, f)
    f.TreePage.Background = f.TreePage:CreateTexture()
    f.TreePage.LegacyTreePointSummary = CreateFrame("Frame", nil, f.TreePage)
    local treeShield = CreateFrame("Frame", nil, f.TreePage.LegacyTreePointSummary)
    treeShield.Icon = treeShield:CreateTexture(); treeShield.Points = treeShield:CreateFontString()
    treeShield.Icon:SetSize(35, 51)
    f.TreePage.LegacyTreePointSummary.Shield = treeShield
    local tree = CreateFrame("Frame", nil, f.TreePage)
    f.TreePage.LegacyTreeTraitPanel = tree
    tree.ApplyButton = CreateFrame("Button", nil, tree)
    tree.ApplyButton.YellowGlow = CreateFrame("Frame", nil, tree.ApplyButton)
    for _, key in ipairs({ "Left", "Middle", "Right" }) do tree.ApplyButton.YellowGlow[key] = tree.ApplyButton.YellowGlow:CreateTexture() end
    tree.Background = tree:CreateTexture()
    tree.ButtonsParent = CreateFrame("Frame", nil, tree)
    local node = CreateFrame("Button", nil, tree.ButtonsParent)
    node.Icon = node:CreateTexture()
    local rankGlow = node:CreateTexture()
    rankGlow.GetAtlas = function() return "Talents-Square-Box-c60" end
    rankGlow.IsObjectType = function(_, kind) return kind == "Texture" end
    node.GetRegions = function() return node.Icon, rankGlow end
    local rankText = node:CreateFontString()
    tree.EnumerateAllTalentButtons = function() local nodes = { node }; return function() return table.remove(nodes) end end
    tree.RegisterCallback = function(self, event, fn, owner) self._legacyCallback = function(button) fn(owner, button) end end
    M.fire("ADDON_LOADED", "Blizzard_LegacySystem")
    check(f.TreePage.Background:GetAlpha() == 0 and tree.Background:GetAlpha() == 0,
        "legacy window hides its page and tree background art")
    check(tree.ApplyButton.YellowGlow.Middle:GetAlpha() == 0 and tree.ApplyButton.YellowGlow.Left:GetAlpha() == 0,
        "the legacy apply button has no native glow line")
    check(node:GetAlpha() == 1 and node.Icon:GetAlpha() == 1 and tree.ButtonsParent:GetAlpha() == 1,
        "legacy tree nodes remain visible and interactive")
    check(rankGlow:GetAlpha() == 0 and rankText:GetAlpha() == 1, "legacy rank backing is hidden without hiding its text")
    rankGlow:SetAlpha(1); tree._legacyCallback(node)
    check(rankGlow:GetAlpha() == 0, "recycled legacy nodes lose the rank backing")
    check(f.RewardTrackPage.Background:GetAlpha() == 0 and f.ChallengesPage.Background:GetAlpha() == 0
        and f.Tabs[1].Background:GetAlpha() == 0 and f.Tabs[1].Icon:GetAlpha() == 0
        and f.Tabs[1].fuiLegacyIcon ~= nil, "legacy reward and challenge pages and side tabs use the new theme")
    reward:ApplyAlpha()
    check(reward.RewardCardBG:GetAlpha() == 0 and reward.fuiLegacyIconEdge ~= nil,
        "reward card restores the themed icon border and hides the old hover art after alpha updates")
    reward.RewardCardBG:SetAlpha(1)
    check(reward.RewardCardBG:GetAlpha() == 0 and reward.fuiLegacyPanelInset,
        "native reward hover artwork stays hidden and adjacent panels have inset borders")
    reward.RewardCardBG:Show()
    check(not reward.RewardCardBG:IsShown(), "the old reward card artwork stays hidden if the game shows it again")
    check(not nativeCardArt:IsShown() and nativeCardArt:GetAlpha() == 0,
        "Camelot reward-card atlas is removed from pooled track descendants")
    local _, challengeAnchor = challengeShield.Points:GetPoint()
    local _, treeAnchor = treeShield.Points:GetPoint()
    check(challengeAnchor == challengeShield.Icon and treeAnchor == treeShield.Icon,
        "legacy challenge and tree point emblems have their number centered on the icon")
    local _, _, _, pointX, pointY = challengeShield.Points:GetPoint()
    check(pointX == -1.5 and math.abs(pointY + 66 * 0.04) < 0.01,
        "legacy shield number offsets scale with the emblem height")
    local _, _, _, _, smallY = treeShield.Points:GetPoint()
    check(math.abs(smallY + 51 * 0.04) < 0.01, "smaller legacy shields use a proportional number offset")
    local _, _, _, cardX = challengeCard.Shield.Points:GetPoint()
    check(cardX == -0.5, "yellow reward numbers have their own horizontal alignment")
    local _, pointsAnchor = f.RewardTrackPage.Points:GetPoint()
    local _, titleAnchor = f.TitleContainer.TitleText:GetPoint()
    local _, levelAnchor, _, _, levelY = reward.Level:GetPoint()
    check(pointsAnchor == f.RewardTrackPage.Icon and titleAnchor == f and levelAnchor == reward and levelY == -8,
        "legacy heading, point count and reward levels are aligned to their containers")
    tree.Background:SetAlpha(1)
    f.TreePage:Hide(); f.TreePage:Show()
    check(tree.Background:GetAlpha() == 0, "legacy background styling returns after page changes")
end

-- Camelot spellbook: pooled rows and page art are refreshed on page changes.
do
    local f = M.window("PlayerSpellsFrame")
    local book = CreateFrame("Frame", nil, f)
    f.SpellBookFrame = book
    for _, key in ipairs({ "TopBar", "BookBGHalved", "BookBGLeft", "BookBGRight", "BookCornerFlipbook", "Bookmark" }) do
        book[key] = book:CreateTexture()
    end
    local row = CreateFrame("Frame", nil, book)
    row.Backplate = row:CreateTexture()
    row.TextContainer = CreateFrame("Frame", nil, row)
    row.TextContainer.Name = row.TextContainer:CreateFontString()
    row.TextContainer.Name.SetTextColor = function(self, r, g, b) self._rgb = { r, g, b } end
    row.TextContainer.SubName = row.TextContainer:CreateFontString()
    row.TextContainer.RequiredLevel = row.TextContainer:CreateFontString()
    row.Button = CreateFrame("Button", nil, row)
    row.Button.Icon = row.Button:CreateTexture()
    row.Button.Border = row.Button:CreateTexture()
    row.Button.BorderShadow = row.Button:CreateTexture()
    row.Button.BorderSheen = row.Button:CreateTexture()
    row.ApplyBorderArt = function() row.Button.Border:SetAlpha(1) end
    row.Button:SetScript("OnClick", function() M.spellClicked = true end)
    local header = CreateFrame("Frame", nil, book)
    header.Text = header:CreateFontString()
    header.Border, header.Backplate = header:CreateTexture(), header:CreateTexture()
    local view = CreateFrame("Frame", nil, book)
    view.GetChildren = function() return row, header end
    book.PagedSpellsFrame = { ViewFrames = { view } }
    local category = CreateFrame("Button", nil, book)
    category.Icon = category:CreateTexture()
    category.Icon:SetSize(38, 38)
    for _, key in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive" }) do category[key] = category:CreateTexture() end
    category.SquareBackground = category:CreateTexture()
    category.SquareBackgroundActive = category:CreateTexture()
    category.SquareBackgroundActiveGlow = category:CreateTexture()
    category.SetTabSelected = function(self, selected) self.isSelected = selected end
    book.CategoryTabSystem = { tabs = { category } }
    book.GetTop = function() return 800 end
    book.SettingsDropdown = CreateFrame("Button", nil, book)
    book.SettingsDropdown:SetSize(20, 20)
    book.SettingsDropdown:SetPoint("TOPRIGHT", book, "TOPRIGHT", -30, -27)
    book.SettingsDropdown.GetNumPoints = function(self) return #(self._points or {}) end
    book.SearchBox = CreateFrame("EditBox", nil, book)
    book.SearchBox:SetSize(300, 30)
    book.SearchBox.GetRight = function() return 600 end
    book.SearchBox.GetTextInsets = function() return 14, 18, 0, 0 end
    book.SearchBox.SetTextInsets = function(self, ...) self._insets = { ... } end
    book.SearchBox.searchIcon = book.SearchBox:CreateTexture()
    book.SearchBox.Instructions = book.SearchBox:CreateFontString()
    book.UpdateAttic = function(self)
        self.SettingsDropdown:ClearAllPoints()
        self.SettingsDropdown:SetPoint("TOPRIGHT", self, "TOPRIGHT", -30, -27)
    end
    book.ResizeSearchBox = function(self) self.SearchBox:SetWidth(300) end
    book.ForEachDisplayedSpell = function(_, fn) fn(row) end
    local talents = CreateFrame("Frame", nil, f)
    f.TalentsFrame = talents
    talents.ApplyButton = CreateFrame("Button", nil, talents)
    talents.ApplyButton.YellowGlow = CreateFrame("Frame", nil, talents.ApplyButton)
    for _, key in ipairs({ "Left", "Middle", "Right" }) do talents.ApplyButton.YellowGlow[key] = talents.ApplyButton.YellowGlow:CreateTexture() end
    table.insert(f._kids, talents)
    talents.GetChildren = function() return talents.ApplyButton end
    talents.ApplyButton.GetChildren = function(self) return self.YellowGlow end
    for _, key in ipairs({ "Background", "ClassBackground", "OverlayBackgroundRight", "Clouds1", "BackgroundBorder", "DividerVerticalLeft", "DividerVerticalRight" }) do
        talents[key] = talents:CreateTexture()
    end
    local backgroundAnim = { SetPlaying = function(self, playing) self.playing = playing end }
    local commitAnim = { playing = true }
    talents.backgroundAnims, talents.commitFlashAnims = { backgroundAnim }, { commitAnim }
    talents.SetBackgroundAnimationsPlaying = function(self, playing)
        for _, animation in ipairs(self.backgroundAnims) do animation:SetPlaying(playing) end
        self.Clouds1:SetAlpha(1)
    end
    talents.ClassCurrencyDisplay = CreateFrame("Frame", nil, talents)
    talents.ClassCurrencyDisplay.Border = talents.ClassCurrencyDisplay:CreateTexture()
    talents.ClassCurrencyDisplay.CurrentAmountContainer = CreateFrame("Frame", nil, talents.ClassCurrencyDisplay)
    talents.ClassCurrencyDisplay.CurrentAmountContainer.CurrencyAmount = talents.ClassCurrencyDisplay.CurrentAmountContainer:CreateFontString()
    talents.ClassCurrencyDisplay:SetPoint("BOTTOMLEFT", talents, "BOTTOMLEFT", 20, 30)
    talents.ClassCurrencyDisplay.CurrentAmountContainer.CurrencyAmount.GetFont = function() return "font", 25 end
    local talentNode = CreateFrame("Button", nil, talents)
    talentNode.Icon = talentNode:CreateTexture()
    talentNode:SetScript("OnClick", function() M.talentClicked = true end)
    local treeHeader = CreateFrame("Frame", nil, talents)
    treeHeader.Icon = treeHeader:CreateTexture()
    treeHeader.MainRing, treeHeader.TextBackground, treeHeader.Divider = treeHeader:CreateTexture(), treeHeader:CreateTexture(), treeHeader:CreateTexture()
    treeHeader.Name, treeHeader.Text = treeHeader:CreateFontString(), treeHeader:CreateFontString()
    treeHeader.Text:SetText("19")
    talents.treeHeaders = { treeHeader }
    local talentTab = CreateFrame("Button", nil, talents)
    talentTab.Text = talentTab:CreateFontString()
    for _, key in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive" }) do talentTab[key] = talentTab:CreateTexture() end
    talentTab.SetTabSelected = function(self) self.Text:ClearAllPoints(); self.Text:SetPoint("CENTER", self, "CENTER", 0, -4) end
    talents.TabSystem = { tabs = { talentTab } }
    talents.RefreshTreeHeaders = function() treeHeader.MainRing:SetAlpha(1) end
    f.ofaTrainerButton = CreateFrame("Button", nil, book)
    M.fire("ADDON_LOADED", "Blizzard_PlayerSpells")
    do
        local button = book.fuiTrainerButton
        local point, relative, anchor, x = button:GetPoint()
        check(button and button:GetWidth() == 38 and button:GetHeight() == 38
            and point == "LEFT" and relative == category.Icon and anchor == "RIGHT" and x == 8
            and button.icon._texture:find("training%-minimal%.tga"),
            "training button matches the native spellbook icon and sits beside it")
        check(not f.ofaTrainerButton:IsShown() and not f.ofaTrainerButton._mouse,
            "the overlapping OneForAll training button is hidden")
        f.ofaTrainerButton:Show()
        check(not f.ofaTrainerButton:IsShown(), "the duplicate trainer button stays hidden if reshown")
        local oldOpen, clicked = ns.TrainerGuide.Open, false
        ns.TrainerGuide.Open = function() clicked = true end
        button:Click()
        ns.TrainerGuide.Open = oldOpen
        check(clicked, "the training icon opens Forever UI's guide")
        category.Icon:SetSize(44, 44)
        book:Hide(); book:Show()
        check(button:GetWidth() == 44 and button:GetHeight() == 44,
            "the training button follows spellbook icon size on show")
        button.GetCenter = function() return 450, 755 end
        button.GetRight = function() return 400 end
        book:UpdateAttic()
        book:ResizeSearchBox()
        local _, _, _, _, dropdownY = book.SettingsDropdown:GetPoint()
        local searchPoint, searchOwner, searchAnchor, searchX, searchY = book.SearchBox:GetPoint()
        local iconPoint, iconOwner, _, iconX = book.SearchBox.searchIcon:GetPoint()
        check(dropdownY == -35 and searchPoint == "RIGHT" and searchOwner == book.SettingsDropdown
            and searchAnchor == "LEFT" and searchX == -5 and searchY == 0,
            "the spellbook search and settings arrow line up with the training icon")
        check(iconPoint == "LEFT" and iconOwner == book.SearchBox and iconX == 6
            and book.SearchBox._insets[1] == 24 and book.SearchBox:GetWidth() == 192,
            "the search icon and input have padding and the field leaves room for training")
    end
    check(talents.ApplyButton.YellowGlow.Middle:GetAlpha() == 0, "the talent apply button has no native glow line")
    check(not talents.ApplyButton.YellowGlow.fuiPanel and talents.ApplyButton.YellowGlow:GetAlpha() == 0,
        "the one-pixel native glow is not mistaken for a themed button")
    check(book.BookBGLeft:GetAlpha() == 0 and book.BookBGRight:GetAlpha() == 0
        and book.BookBGHalved:GetAlpha() == 0 and f.fuiPanel and not book.fuiPanel,
        "spellbook page art is replaced by the shared theme")
    check(row.Backplate:GetAlpha() == 0 and row.TextContainer.Name._rgb[1] == ns.C.text[1]
        and header.fuiSpellRule and header.Backplate:GetAlpha() == 0,
        "spell rows and headings remain readable on the dark page")
    check(row.Button.Border:GetAlpha() == 0 and row.Button.BorderShadow:GetAlpha() == 0
        and row.Button.fuiSpellIconEdge and category.SquareBackground:GetAlpha() == 0
        and category.fuiSpellTabEdge, "spell and category icons use gold edges instead of copper artwork")
    category:SetTabSelected(true)
    check(category.fuiSpellTabEdge.fuiPanel.bright and not category.fuiPanel.bright,
        "the selected category highlights only its icon edge")
    row:ApplyBorderArt()
    check(row.Button.Border:GetAlpha() == 0, "spell borders stay themed after a visual update")
    row.Button:Click()
    check(M.spellClicked and row.Button.Icon:GetAlpha() == 1, "spell controls and icons remain intact")
    check(talents.Background:GetAlpha() == 0 and talents.ClassBackground:GetAlpha() == 0
        and talents.BackgroundBorder:GetAlpha() == 0 and talents.fuiTreeEdge
        and treeHeader.MainRing:GetAlpha() == 0 and treeHeader.fuiTalentIconEdge,
        "Camelot talent backgrounds and copper artwork are replaced with gold edges")
    do
        local point, relative, anchor = treeHeader.Text:GetPoint()
        check(point == "TOP" and relative == treeHeader.Icon and anchor == "BOTTOM",
            "the talent tree number is centered below its icon")
    end
    check(not talents.fuiTreeEdge.fuiPanel.lines[2]:IsShown(),
        "the bottom tree border does not cross the Apply Changes button")
    talents:SetBackgroundAnimationsPlaying(true)
    check(not backgroundAnim.playing and talents.Clouds1:GetAlpha() == 0 and commitAnim.playing,
        "background animations stay stopped without disabling talent interaction effects")
    local currency = talents.ClassCurrencyDisplay.CurrentAmountContainer
    local point, relative, relativePoint = currency.CurrencyAmount:GetPoint()
    check(talents.fuiDividerVerticalLeft and talents.fuiDividerVerticalRight
        and point == "CENTER" and relative == currency and relativePoint == "CENTER",
        "talent trees have separators and the unspent amount is centered")
    local cPoint, cRel, cRelPoint, cX, cY = talents.ClassCurrencyDisplay:GetPoint()
    check(cPoint == "BOTTOMLEFT" and cRel == talents and cRelPoint == "BOTTOMLEFT" and cX == 20 and cY == 30,
        "the unspent talent points box keeps its own place on the page")
    currency.CurrencyAmount:SetText("1")
    local _, _, _, oneX, oneY = currency.CurrencyAmount:GetPoint()
    currency.CurrencyAmount:SetText("5")
    local _, _, _, fiveX, fiveY = currency.CurrencyAmount:GetPoint()
    check(math.abs(oneX + 1.5) < 0.01 and math.abs(oneY + 1) < 0.01 and fiveX == 0 and math.abs(fiveY + 1) < 0.01
        and not currency.CurrencyAmount:GetPoint(2),
        "the unspent talent points number sits in the middle of its box")
    talentTab:SetTabSelected(true)
    local tabPoint, tabAnchor, tabRelative, tabX, tabY = talentTab.Text:GetPoint()
    check(tabPoint == "CENTER" and tabAnchor == talentTab and tabRelative == "CENTER" and tabX == 0 and tabY == 0,
        "talent tab labels stay centered after selection")
    talentNode:Click()
    check(M.talentClicked and talentNode.Icon:GetAlpha() == 1, "talent nodes remain interactive and visible")
    talents:RefreshTreeHeaders()
    check(treeHeader.MainRing:GetAlpha() == 0, "talent headers are restyled after they are rebuilt")
    row.Backplate:SetAlpha(1)
    EventRegistry.callbacks["PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged"]()
    check(row.Backplate:GetAlpha() == 0, "recycled spell rows are restyled after page changes")
end

do
    local container = CreateFrame("Frame", "MirrorTimerContainer", UIParent)
    local timer = CreateFrame("Frame", nil, container)
    timer.StatusBar = CreateFrame("StatusBar", nil, timer)
    timer.StatusBar.SetStatusBarTexture = function(self, tex) self._fill = tex end
    timer.StatusBar.SetStatusBarColor = function(self, r, g, b) self._fillColor = { r, g, b } end
    timer.Border, timer.TextBorder, timer.Text = timer:CreateTexture(), timer:CreateTexture(), timer:CreateFontString()
    local bg = timer:CreateTexture()
    bg.GetAtlas = function() return "ui-castingbar-background" end
    timer.GetRegions = function() return bg end
    timer.Setup = function(self, kind) self.timer = kind; self.StatusBar:SetStatusBarTexture("native") end
    container.mirrorTimers = { timer }
    M.fire("ADDON_LOADED", "Blizzard_MirrorTimer")
    timer:Setup("BREATH")
    local point, anchor, relative = timer.Text:GetPoint()
    check(timer.Border:GetAlpha() == 0 and timer.TextBorder:GetAlpha() == 0 and bg:GetAlpha() == 0
        and timer.StatusBar._fill == ns.FLAT and timer.StatusBar._fillColor[3] > timer.StatusBar._fillColor[1]
        and point == "CENTER" and anchor == timer.StatusBar and relative == "CENTER",
        "breath timer uses a flat blue bar and centered native text")
    timer:Setup("EXHAUSTION")
    check(timer.StatusBar._fill == ns.FLAT and timer.StatusBar._fillColor[1] == ns.C.gold[1],
        "reused fatigue timer keeps its themed appearance")
end

do
    MultiCastFlyoutFrame = CreateFrame("Frame", "MultiCastFlyoutFrame", UIParent)
    MultiCastFlyoutFrame.top = MultiCastFlyoutFrame:CreateTexture()
    local button = CreateFrame("Button", "MultiCastActionButton1", MultiCastFlyoutFrame)
    button.icon, button.overlay = button:CreateTexture(), button:CreateTexture()
    button.HotKey, button.Count, button.Name, button.cooldown = false, false, false, false
    MultiCastFlyoutFrame.buttons = { button }
    MultiCastFlyoutFrameOpenButton = CreateFrame("Button", "MultiCastFlyoutFrameOpenButton", MultiCastFlyoutFrame)
    M.fire("SPELLS_CHANGED")
    check(button.fuiPanel and button.overlay:GetAlpha() == 0 and MultiCastFlyoutFrame.fuiPanel
        and MultiCastFlyoutFrame.top:GetAlpha() == 0 and MultiCastFlyoutFrameOpenButton.fuiTotemArrow,
        "native totem flyout uses themed panels and keeps its buttons")
    LootFrame = CreateFrame("Frame", "LootFrame", UIParent)
    LootFrameElementMixin = { Init = function() end }
    M.fire("LOOT_OPENED")
    local row = CreateFrame("Frame", nil, LootFrame)
    row.NameFrame, row.BorderFrame = row:CreateTexture(), row:CreateTexture()
    row.Item = CreateFrame("Button", nil, row)
    LootFrameElementMixin.Init(row)
    check(LootFrame.fuiPanel and row.fuiPanel and row.Item.fuiLootEdge
        and row.NameFrame:GetAlpha() == 0 and row.BorderFrame:GetAlpha() == 0,
        "loot rows use themed panels and retain their native item button")
    LootFrame, LootFrameElementMixin = nil, nil
end
do
    local originalBool = C_CVar.GetCVarBool
    local oldNum, oldLoot, oldModified = GetNumLootItems, LootSlot, IsModifiedClick
    local oldCan, oldCost, oldMoney, oldRepair = CanMerchantRepair, GetRepairAllCost, GetMoney, RepairAllItems
    local looted, repairs, modifier, money = {}, 0, false, 100
    C_CVar.GetCVarBool = function() return true end
    GetNumLootItems = function() return 2 end
    LootSlot = function(slot) looted[#looted + 1] = slot end
    IsModifiedClick = function() return modifier end
    ns.O().qolQuickLoot = true; M.fire("LOOT_OPENED")
    check(#looted == 2 and looted[1] == 2, "quick loot takes slots when auto loot is enabled")
    modifier = true; M.fire("LOOT_OPENED")
    check(#looted == 2, "the auto-loot modifier preserves manual looting")
    ns.O().qolQuickLoot = false
    CanMerchantRepair = function() return true end
    GetRepairAllCost = function() return 40, true end
    GetMoney = function() return money end
    RepairAllItems = function(guild) if not guild then repairs = repairs + 1 end end
    ns.O().qolAutoRepair = true; M.fire("MERCHANT_SHOW")
    money = 10; M.fire("MERCHANT_SHOW")
    check(repairs == 1, "auto repair uses personal funds only when affordable")
    ns.O().qolAutoRepair = false
    C_CVar.GetCVarBool = originalBool
    GetNumLootItems, LootSlot, IsModifiedClick = oldNum, oldLoot, oldModified
    CanMerchantRepair, GetRepairAllCost, GetMoney, RepairAllItems = oldCan, oldCost, oldMoney, oldRepair
end
do
    local saved = { AcceptQuest, IsQuestCompletable, CompleteQuest, GetNumQuestChoices, GetQuestReward, IsShiftKeyDown }
    local accepted, completed, rewarded, choices, shift = 0, 0, 0, 0, false
    AcceptQuest = function() accepted = accepted + 1 end
    IsQuestCompletable = function() return true end
    CompleteQuest = function() completed = completed + 1 end
    GetNumQuestChoices = function() return choices end
    GetQuestReward = function(index) if index == 0 then rewarded = rewarded + 1 end end
    IsShiftKeyDown = function() return shift end
    M.fire("QUEST_DETAIL"); M.fire("QUEST_PROGRESS"); M.fire("QUEST_COMPLETE")
    check(accepted == 0 and completed == 0 and rewarded == 0, "quest automation is off by default")
    ns.O().qolAutoQuestAccept, ns.O().qolAutoQuestTurnIn = true, true
    M.fire("QUEST_DETAIL"); M.fire("QUEST_PROGRESS"); M.fire("QUEST_COMPLETE")
    choices = 2; M.fire("QUEST_COMPLETE")
    shift = true; M.fire("QUEST_DETAIL"); M.fire("QUEST_PROGRESS"); M.fire("QUEST_COMPLETE")
    check(accepted == 1 and completed == 1 and rewarded == 1, "quest automation pauses on Shift and never picks a reward")
    ns.O().qolAutoQuestAccept, ns.O().qolAutoQuestTurnIn = false, false
    AcceptQuest, IsQuestCompletable, CompleteQuest, GetNumQuestChoices, GetQuestReward, IsShiftKeyDown = unpack(saved)
end
ns.SetupOptions()
do
    local previousClass = UnitClass
    UnitClass = function() return "Warrior", "WARRIOR", 1 end
    ns.TrainerGuide:Open()
    check(ns.TrainerGuide.frame and ns.TrainerGuide.frame:IsShown() and ns.TrainerGuide.frame.tabs.lowranks,
        "the standalone class training guide opens with a low-rank tab")
    check(ns.TrainerGuide.frame.title:GetText():find("Warrior") and ns.TrainerGuide.frame.rows[1].entry and ns.TrainerGuide.frame.rows[1].entry.header,
        "training spells are grouped under the current class")
    do
        local guide = ns.TrainerGuide
        for _, button in pairs(guide.frame.classButtons) do
            button.icon.SetVertexColor = function(self, r, g, b) self._trainerShade = { r, g, b } end
        end
        guide:Render()
        check(guide.frame.classButtons[1].icon._trainerShade[1] == 1
            and guide.frame.classButtons[8].icon._trainerShade[1] == 0.4,
            "the player's class stays bright while other trainer class icons are dim")
    end
    M.testTrainerGroups = function()
        local guide = ns.TrainerGuide
        local priorPage, priorMode, priorClass = guide.page, guide.mode, guide.viewClass
        guide.page, guide.mode, guide.viewClass = "spells", "all", 1
        local rows = guide:BuildDisplayLines({
            {name="Learnable",level=4,available=true},
            {name="Quest spell",level=4,available=true,quest=true},
            {name="Unknown knowledge",level=4,available=true,knownUnknown=true},
            {name="Later",level=8,available=false},
        })
        check(rows[1].headerColor=="ready" and rows[2].name=="Learnable" and rows[3].headerColor=="level" and rows[4].name=="Quest spell" and rows[5].name=="Unknown knowledge" and rows[6].level==8, "trainer puts definitely learnable spells first and keeps quest and unknown spells in level groups")
        guide.viewClass=8; rows=guide:BuildDisplayLines({{name="Other class",level=4,available=true}})
        check(rows[1].headerColor=="level", "other classes never claim that spells are available now")
        guide.page, guide.mode, guide.viewClass = priorPage, priorMode, priorClass
    end
    M.testTrainerGroups(); M.testTrainerGroups = nil
    ns.TrainerGuide.frame.classButtons[8]:Click()
    check(ns.TrainerGuide.frame.title:GetText():find("Mage")
        and ns.TrainerGuide.frame.classButtons[8].fuiPanel.bright
        and ns.TrainerGuide.frame.classButtons[8].icon._trainerShade[1] == 0.4,
        "other class icons remain clickable, with the selected class outlined")
    do
        local guide = ns.TrainerGuide.frame
        local s = guide.smooth
        check(s and #guide.rows == 14 and guide.rows[1]:GetParent() == s.content and guide.scrollbar == s.scrollbar,
            "the training guide list scrolls through a clipped strip with a spare row")
        if s and s.maxPixel > 0 then
            guide.body:GetScript("OnMouseWheel")(guide.body, -1)
            check(s.target == math.min(36, s.maxPixel) and s.pixel == 0, "a wheel notch over the training guide glides")
            ns.Encyclopedia:FinishSmoothScroll()
            check(s.pixel == math.min(36, s.maxPixel) and ns.TrainerGuide.offset == math.min(1, s.maxOffset),
                "the training guide lands on the next row")
            ns.TrainerGuide.offset = 0; ns.TrainerGuide:Render()
        end
    end
    ns.TrainerGuide.frame.classButtons[1]:Click()
    ns.TrainerGuide.frame.pages.weapons:Click()
    check(ns.TrainerGuide.frame.rows[1].entry and ns.TrainerGuide.frame.rows[1].entry.toggle,
        "the weapon page shows expandable skill categories")
    ns.TrainerGuide.frame.rows[1]:Click()
    check(ns.TrainerGuide.frame.rows[2].entry and ns.TrainerGuide.frame.rows[2].entry.kind == "location",
        "expanding a weapon shows its trainer locations")
    do
        local oldMap, destination = ns.Encyclopedia.ShowLocation, nil
        ns.Encyclopedia.ShowLocation = function(mapID, x, y) destination = { mapID, x, y }; return true end
        local location = ns.TrainerGuide.frame.rows[2].entry
        ns.TrainerGuide.frame.rows[2].map:Click()
        check(destination and destination[1] == location.mapID and destination[2] == location.x and destination[3] == location.y,
            "trainer map buttons pass the recorded location to the encyclopedia")
        ns.Encyclopedia.ShowLocation = oldMap; ns.TrainerGuide:Open()
    end
    ns.TrainerGuide.frame.pages.quests:Click()
    check(ns.TrainerGuide.frame.rows[1].entry and ns.TrainerGuide.frame.rows[1].entry.toggle,
        "the class quest page shows expandable milestones")
    ns.TrainerGuide.frame.rows[1]:Click()
    check(ns.TrainerGuide.frame.rows[2].entry and ns.TrainerGuide.frame.rows[2].entry.kind == "quest",
        "expanding a milestone shows its quest chain")
    ns.TrainerGuide.frame.pages.pets:Click(); ns.TrainerGuide.frame.petTabs.trainers:Click()
    check(ns.TrainerGuide.frame.rows[1].entry and ns.TrainerGuide.frame.rows[1].entry.kind == "location",
        "the pet trainer page shows faction trainer locations")
    ns.TrainerGuide:Open()
    UnitClass = previousClass
end
do
    local previousClass = UnitClass
    UnitClass = function() return "Hunter", "HUNTER", 3 end
    local id = UnitGUID("player")
    ns.db.trainerPetRanks = ns.db.trainerPetRanks or {}
    ns.db.trainerPetRanks[id] = { ranks = { Bite = { [2] = true } } }
    local details = ns.Encyclopedia.Details({ kind = "petRank", extra = "Bite", data = { rank = 2, learnFrom = {} } })
    check(details:find("Your hunter: Known", 1, true), "pet ability details show the current hunter's confirmed rank")
    UnitClass = previousClass
end
ns.OpenOptions()
local settingsWindow = ns.optionsWindow
check(settingsWindow and settingsWindow:IsShown() and #settingsWindow.tabs == 6,
    "Forever UI opens a categorized settings window")
check(settingsWindow.heading:GetText() == "General & QoL", "settings start with general and quality of life")
settingsWindow.tabs[3]:Click()
check(settingsWindow.heading:GetText() == "Healing & Dispels", "category buttons switch settings pages")
settingsWindow.content._scripts.OnMouseWheel(settingsWindow.content, -1)
check(settingsWindow.offset == 0 and settingsWindow.smooth.target == 44, "a wheel notch over the settings glides instead of jumping")
ns.Encyclopedia:FinishSmoothScroll()
check(settingsWindow.offset == 1, "long settings categories scroll without changing pages")
settingsWindow.scrollbar:GetScript("OnValueChanged")(settingsWindow.scrollbar, 2 * 44 + 10)
do
    local _, _, _, _, settingsShift = settingsWindow.smooth.content:GetPoint()
    check(settingsWindow.offset == 2 and settingsShift == 10 and #settingsWindow.rows == 10
        and settingsWindow.rows[1]:GetParent() == settingsWindow.smooth.content, "dragging the settings scrollbar moves the list by pixel")
end
settingsWindow.tabs[1]:Click()
local quickRow
for _, row in ipairs(settingsWindow.rows) do if row.entry and row.entry.name == "Quicker auto loot" then quickRow = row end end
if quickRow then
    local before = ns.Opt("qolQuickLoot")
    quickRow.action:Click()
    check(ns.Opt("qolQuickLoot") ~= before, "categorized setting toggles the original option")
    quickRow.action:Click()
else check(false, "quick loot setting is available in its category") end
settingsWindow:Hide()
do
    local previousSource, previousGold = OneForAll, ForeverGold
    MOCK.independentReference = ns.IndependentReference; ns.IndependentReference = nil
    OneForAll = {
        MAP_IDS = { Westfall = 1436 },
        BOSS_LEVELS = { [1763] = "20" }, BOSS_TYPES = { [1763] = "Humanoid" },
        GetDropChance = function(dungeon, boss, id) if dungeon == "The Deadmines" and boss == "Gilnid" and id == 100 then return 34, 120, false end end,
        GEAR_LOC_SLOTS = { INVTYPE_HEAD = { 1 } },
        GearCanUse = function() return true end,
        GearValue = { Change = function(id) if id == 101 then return "up", 5 end end },
        GearIndex = function() return { { id = 101, name = "Test Helmet", loc = "INVTYPE_HEAD", cid = 4, sub = 2, lvl = 1, src = "Test Armor" } } end,
        DUNGEON_LOADSCREENS = { deadmines = { 131833, 0.03, 0.97, 0.2, 0.8, 2.089, 0.5, 0.5, 1 } },
        DUNGEONS = { { key = "deadmines", name = "The Deadmines", level = "15-24", area = "Westfall", mapZone = "Westfall", mapX = 42, mapY = 71, icon = "dungeon-icon",
            bosses = { { name = "Gilnid", npcID = 1763, fallbackIcon = "gilnid-portrait", loot = { { id = 100, name = "Blueprint: Anvil", slot = "Recipe", quality = 2 } } },
                { name = "VanCleef", npcID = 639, fallbackIcon = "vancleef-portrait", loot = { { id = 102, name = "Test Sword", slot = "Sword" } } } },
            quests = { { id = 10, name = "A dungeon quest", level = 18, rewards = { { id = 100, name = "Blueprint: Anvil" } } } } },
            { key = "raid40", name = "Test Raid Forty", raid = true, size = 40, level = "60", bosses = {}, quests = {} },
            { key = "raid60", name = "Test Raid Ten", raid = true, size = 10, level = "60", bosses = {}, quests = {} },
            { key = "raidunknown", name = "Test Raid Unknown", raid = true, level = "60", bosses = {}, quests = {} } },
        PET_FAMILIES = { { name = "Cat", icon = "cat-icon", role = "Offense", diet = { "Meat" }, modifiers = { health = "1.00", armor = "1.05", damage = "1.07" }, abilities = { "Prowl" },
            tames = { { name = "Test Cat", npcID = 555, level = "4-5", zone = "Durotar" } } } },
        PET_ABILITIES = { { name = "Prowl", icon = "prowl-icon", families = { "Cat" }, ranks = {} } },
        PET_RARES = { { name = "Rare Cat", npcID = 556, family = "Cat", level = "10", zone = "Mulgore" } },
        PROFESSION_TRAINERS = { Blacksmithing = { { 1, "Test Trainer", "Smith", "H", 1411, 42, 71, "Durotar" } } },
        BOOKS = { { set = "starter", name = "Test Book", itemId = 9999, zone = "Westfall", x = 42, y = 71 } },
        CAMPING_PROFESSIONS = { { profession = "Blacksmithing", items = { { id = 900, name = "Test Camp Anvil", skill = 20, effect = "Test buff", reagents = "Copper" } } } },
        MERCHANT_RECIPES = { { profession = "Blacksmithing", name = "Anvil", cost = 45 } },
        SkillUp = { HasAuctionator = function() return false end,
            Plan = function() return { cost = 200, steps = { { kind = "craft", from = 1, to = 75, safe = 74, r = { s = 123, n = "Anvil" } } }, mats = {} } end,
            Profit = function() return { { r = { s = 123, n = "Anvil" }, profit = 100 } } end },
        PROFESSION_RECIPES = { Blacksmithing = { { s = 123, n = "Anvil", cat = "Camping", fav = true,
            req = 140, ri = 100, rn = "Blueprint: Anvil", r = { { 2841, 5, "Bronze Bar" } }, src = { d = { { 1763, "Gilnid", "The Deadmines" } } } },
            { s = 124, n = "Blade", req = 150, r = { { 2835, 1, "Rough Stone" } } } },
            Enchanting = { { s = 7418, n = "Head Stamina", ri = 400, rn = "Formula: Head Stamina", src = { v = { { 8, "Test Vendor", "Orgrimmar", fac = "H" } }, d = { { 9, "Test Mob", "Durotar" } } } } } },
        ARMORY_SETS = { { id = 99, n = "Test Armor", g = "raid", sub = "Tier 1", st = 1, cls = { "HUNTER" }, arm = "Mail", b = { { 2, "Bonus" } },
            i = { { 100, "Blueprint: Anvil" }, { 101, "Test Helmet", "Head" } } } },
        ARMORY_REPUTATION = { { id = 21, n = "Booty Bay", v = {{ 12, "Test Vendor", 1420, 42, 71, "Westfall" }}, i = {{ 99101, "Test Helm", "Head", 2, 123, 4, "gear" }, { 99102, "Test Formula", nil, 1, 124, 5, "recipe" }} } },
    }
    ForeverGold = { RecipeKnownBy = function() return { "Xeon Mana" } end }
    ns.OpenEncyclopedia()
    local enc = ns.Encyclopedia
    do -- built behind the loading screen, so opening doesn't freeze the game
        check(enc.timings and enc.timings.warm and enc.timings.open and enc.timings.open.build < 1,
            "the encyclopedia is built at the loading screen, not on open")
        local built, rebuild = 0, enc.RefreshData
        enc.RefreshData = function(...) built = built + 1; return rebuild(...) end
        enc.window:Hide(); ns.OpenEncyclopedia()
        enc.RefreshData = rebuild
        check(built == 0 and enc.window:IsShown(), "opening again reuses the built entries")
        enc.window:Hide(); M.fire("PLAYER_ENTERING_WORLD")
        local catalog = enc.itemCatalogCache
        check(enc.gearLoaded and catalog and catalog.revision == enc.entryRevision and #catalog.entries > 0,
            "the gear index and the Items list are ready before the Items page is first shown")
        local inOrder = true
        for i = 2, #catalog.entries do
            local a, b = catalog.entries[i - 1], catalog.entries[i]
            local an, bn = a.name:lower(), b.name:lower()
            if bn < an or (an == bn and b.key < a.key) then inOrder = false end
        end
        check(inOrder, "the Items list is in name order without sorting it again")
        ns.OpenEncyclopedia()
    end
    do -- every fixed-row list glides like the Armory
        check(enc.smooth.list and enc.smooth.library and enc.smooth.rep and enc.smooth.boss and enc.smooth.set
            and enc.smooth.reagents and enc.smooth.helper and enc.smooth.search and enc.smooth.wish
            and #enc.window.rows == 12 and enc.window.rows[1]:GetParent() == enc.smooth.list.content,
            "every Encyclopedia list scrolls through a clipped strip with a spare row")
        local pane = CreateFrame("Frame", nil, UIParent)
        local rows = {}
        for i = 1, 4 do rows[i] = CreateFrame("Button", nil, pane); rows[i]:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 36) end
        local drawn = 0
        local s = enc.SmoothList("fuiTest", { pane = pane, rows = rows, step = 36, top = 6, refresh = function() drawn = drawn + 1 end })
        local whole = enc.SmoothSync(s, 0, 10)
        check(whole == 0 and s.visible == 3 and s.maxPixel == 7 * 36 and s.maxOffset == 6 and rows[1]:GetParent() == s.content
            and select(5, rows[2]:GetPoint()) == -42, "a smooth list keeps its rows' places and knows how far it scrolls")
        pane:GetScript("OnMouseWheel")(pane, -1)
        check(s.target == 36 and s.pixel == 0, "a wheel notch glides instead of jumping")
        enc.SmoothStep(s, 0.02)
        local _, _, _, _, shift = s.content:GetPoint()
        check(s.pixel > 0 and s.pixel < 36 and math.abs(shift - s.pixel) < 0.01 and drawn == 0,
            "between rows the strip moves without drawing the list again")
        enc:FinishSmoothScroll()
        check(s.pixel == 36 and drawn == 1, "landing on the next row draws it once")
        whole = enc.SmoothSync(s, 0, 10)
        check(whole == 1, "the list draws from the row the glide reached")
        s.scrollbar:GetScript("OnValueChanged")(s.scrollbar, 7 * 36)
        whole = enc.SmoothSync(s, 1, 10)
        _, _, _, _, shift = s.content:GetPoint()
        check(whole == 6 and shift == 36, "at the end the spare row shows the last item in full")
        whole = enc.SmoothSync(s, 0, 10)
        check(whole == 0 and s.pixel == 0, "an offset set elsewhere (a filter, a new page) moves the list there")
        enc.smooth.fuiTest = nil
        local w, oldCurrent = enc.window, enc.current
        enc.current = nil
        check(w.detailText:GetParent() == w.detailClip and not w.detailNext:IsShown(), "entry text sits in a clipped strip instead of pages")
        enc.detailPixel, enc.detailTarget, enc.detailMaxPixel = 0, nil, 100
        w.detail:GetScript("OnMouseWheel")(w.detail, -1)
        check(enc.detailTarget == 39 and enc.detailPixel == 0, "a wheel notch over entry text glides")
        enc:FinishSmoothScroll()
        local _, anchor, _, _, textY = w.detailText:GetPoint()
        check(enc.detailPixel == 39 and anchor == w.detailClip and textY == 39 and w.detail.scrollbar.fuiMaximum == 100,
            "entry text moves by pixel with the scroll bar in step")
        w.detail.scrollbar:GetScript("OnValueChanged")(w.detail.scrollbar, 100)
        _, _, _, _, textY = w.detailText:GetPoint()
        check(enc.detailPixel == 100 and textY == 100, "the entry text scroll bar drags by pixel")
        enc.current, enc.detailTextKey = oldCurrent, nil; enc:Render()
    end
    do local formatted = enc.FormatMoney(295731)
    check(formatted:find("29|TInterface\\MoneyFrame\\UI%-GoldIcon") and formatted:find("57|TInterface\\MoneyFrame\\UI%-SilverIcon")
        and formatted:find("31|TInterface\\MoneyFrame\\UI%-CopperIcon"), "prices format into gold, silver and copper coin icons")
    check(enc.FormatMoney(0):find("0|TInterface\\MoneyFrame\\UI%-CopperIcon"), "zero prices use a copper coin icon") end
    check(enc.window:IsShown() and #enc:Find("All", "anvil") >= 4, "encyclopedia searches all linked categories")
    local tabPoint, tabOwner, tabAnchor, tabX, tabY = enc.window.tabs.Dungeons:GetPoint()
    check(not enc.window.tabs.All and not enc.window.tabs.Camping and not enc.window.tabs.Favor
        and tabPoint == "TOPLEFT" and tabOwner == enc.window and tabAnchor == "TOPLEFT" and tabX == 132 and tabY == -83,
        "main encyclopedia categories appear across the top without All, Camping or Favor")
    local _, _, _, firstX = enc.window.tabs.Armory:GetPoint()
    local _, _, _, lastX = enc.window.tabs.NPCs:GetPoint()
    check(firstX == 18 and lastX == 816 and select(4, enc.window.tabs.Items:GetPoint()) == 930 and enc.window.tabs.Quests, "top tabs include Quests, NPCs and Items")
    check(enc.window.tabs.Armory.icon._texture:find("encyclopedia%-tab%-armory")
        and enc.window.tabs["Library Books"].icon._texture:find("encyclopedia%-tab%-library"), "encyclopedia categories use their custom icons")
    do
        local legend = enc.window.iconLegendText
        check(legend:IsShown() and legend:GetText():find("Drop chance",1,true) and not enc.window.iconLegendButton,
            "the contextual icon legend stays visible in the encyclopedia footer")
        enc.window.tabs.NPCs:Click()
        check(legend:GetText():find("npc%-role%-vendor") and legend:GetText():find("npc%-role%-trainer") and legend:GetText():find("npc%-role%-quest"),
            "switching tabs updates the legend with the actual NPC role icons")
        enc.window.tabs.Quests:Click()
        check(legend:GetText():find("Horde",1,true) and legend:GetText():find("Alliance",1,true) and legend:GetText():find("Completed",1,true),
            "quest legend explains faction icons and status colors")
        for _, category in ipairs({ "Armory", "Dungeons", "Professions", "Reputations", "Pets", "Library Books", "Quests", "NPCs", "Items" }) do
            enc.window.UpdateIconLegend(category)
            check(legend:GetText() ~= "", category .. " has a contextual legend")
        end
        enc.window.tabs.Dungeons:Click()
    end
    local dPoint, _, _, dX, dY = enc.window.instanceTabs.dungeon:GetPoint()
    local rPoint, _, _, rX, rY = enc.window.instanceTabs.raid:GetPoint()
    local lPoint, _, _, lX, lY = enc.window.levelTabs[10]:GetPoint()
    check(dPoint == "TOPLEFT" and rPoint == "TOPLEFT" and lPoint == "TOPLEFT" and dX == 18 and rX == 18 and lX == 18
        and dY > rY and rY > lY, "dungeons, raids and level brackets stack in the left sidebar")
    check(enc.window.rows[1].entry and enc.window.rows[1].entry.kind == "dungeonGroup" and enc.window.rows[2].entry.kind == "dungeon", "dungeon browser groups instances by level")
    check(enc.window.list:IsShown() and enc.window.list:GetWidth() == 864 and not enc.window.detail:IsShown(), "dungeon browse list fills the right side")
    enc.window.levelTabs[10]:Click()
    check(enc.window.rows[2].entry and enc.window.rows[2].entry.name == "The Deadmines" and enc.window.rows[2].sub:GetText():find("15%-24"),
        "level bracket shows a dungeon row with level and location")
    enc.window.levelToggle:Click()
    check(not enc.window.levelTabs[10]:IsShown() and enc.levelGroup == 10 and enc.window.rows[2].entry.name == "The Deadmines",
        "level brackets collapse without clearing the selected filter")
    enc.window.levelToggle:Click()
    check(enc.window.levelTabs[10]:IsShown(), "level brackets can be expanded again")
    enc.window.rows[1]:Click()
    check(enc.collapsedLevels["dungeon:10"] and not enc.window.rows[2]:IsShown() and enc.levelGroup == 10, "instance level group collapses without clearing its filter")
    enc.window.rows[1]:Click()
    check(enc.window.rows[2].entry and enc.window.rows[2].entry.name == "The Deadmines", "instance level group expands again")
    enc.window.instanceTabs.raid:Click()
    check(enc.window.rows[1].entry.data.groupKey == "raid:10" and enc.window.rows[2].entry.name == "Test Raid Ten"
        and enc.window.rows[3].entry.data.groupKey == "raid:40" and enc.window.rows[4].entry.name == "Test Raid Forty"
        and enc.window.rows[5].entry.data.groupKey == "raid:unknown", "raids appear under their player counts, with unknown sizes separate")
    check(not enc.window.levelTabs[10]:IsShown() and enc.window.raidSizeTabs[2].sizeFilter == 10
        and enc.window.raidSizeTabs[3].sizeFilter == 40, "raid size filters replace dungeon level filters")
    enc.window.rows[1]:Click()
    check(enc.collapsedLevels["raid:10"] and enc.window.rows[2].entry.data.groupKey == "raid:40", "raid size group collapses")
    enc.window.raidSizeTabs[3]:Click()
    check(enc.raidSize == 40 and enc.window.rows[2].entry.name == "Test Raid Forty", "raid size filter selects its group")
    enc.window.rows[2]:Click()
    check(enc.current.name == "Test Raid Forty" and enc.window.detail:GetWidth() == 864 and not enc.window.list:IsShown()
        and enc.window.bossBack.text:GetText() == "< Raids", "raid opens its own full-width page with a raid back button")
    enc.window.bossBack:Click()
    check(enc.raidSize == 40 and enc.window.list:IsShown() and not enc.window.detail:IsShown(), "returning from a raid preserves its size filter")
    enc.window.instanceTabs.dungeon:Click()
    enc.window.levelTabs[10]:Click()
    enc.query = "gilnid"; enc:Render()
    check(enc.window.rows[2].entry and enc.window.rows[2].entry.name == "The Deadmines", "search finds a dungeon by its boss")
    enc.query = ""; enc:Render()
    check(enc.window.rows[2].icon:IsShown() and enc.window.rows[2].icon._texture == 131833, "dungeon row uses loading-screen art")
    local texture, left, right, top, bottom = enc.DungeonArt(enc.window.rows[2].entry.data, 70, 32)
    check(texture == 131833 and left >= 0.03 and right <= 0.97 and top >= 0.2 and bottom <= 0.8,
        "loading-screen crop stays within the source image")
    check(enc.DungeonArt({ key = "missing" }, 70, 32) == nil, "missing artwork has a clean fallback")
    enc.window.rows[2]:Click()
    check(not enc.window.list:IsShown() and enc.window.detail:IsShown() and enc.window.detail:GetWidth() == 864
        and enc.window.bossBack:IsShown(), "opening a dungeon shows its full-width page and back button")
    do
    local oldMap, oldPoint, oldTrack, oldWorldMap = C_Map, UiMapPoint, C_SuperTrack, WorldMapFrame
    local waypoint, tracking
    WorldMapFrame = CreateFrame("Frame", nil, UIParent); WorldMapFrame:Hide()
    function WorldMapFrame:SetMapID(id) self.mapID = id end
    UiMapPoint = { CreateFromCoordinates = function(mapID, x, y) return { mapID = mapID, x = x, y = y } end }
    C_Map = { SetUserWaypoint = function(point) waypoint = point end }
    C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) tracking = on end }
    enc:Render(); enc.window.dungeonMap:Click()
    check(waypoint and waypoint.mapID == 1436 and waypoint.x == 0.42 and waypoint.y == 0.71 and tracking,
        "dungeon waypoint uses the recorded entrance coordinates")
    check(WorldMapFrame:IsShown() and WorldMapFrame.mapID == 1436, "map action opens the correct zone as well as setting its marker")
    C_Map, UiMapPoint, C_SuperTrack, WorldMapFrame = oldMap, oldPoint, oldTrack, oldWorldMap
    end
    check(enc.window.dungeonOverview:IsShown() and enc.window.dungeonOverview.info:GetText():find("Westfall", 1, true),
        "dungeon overview separates location and key facts from the description")
    enc.window.dungeonTabs.Quests:Click()
    check(enc.window.dungeonList:IsShown() and enc.window.dungeonList.rows[1].entry and enc.window.dungeonList.rows[1].entry.kind == "quest", "each dungeon has its own full-height quest list")
    check(enc.window.dungeonList.rows[1].icon._texture:find("encyclopedia%-quest") and enc.window.dungeonList.rows[1].text:GetText():find("[18]", 1, true),
        "quest links show the custom icon and recorded level")
    do
        local quest = enc.window.dungeonList.rows[1].guideQuest
        enc.window.dungeonList.rows[1]:Click()
        check(quest and ns.InstanceGuide.frame:IsShown() and ns.InstanceGuide.view == "Quests"
            and ns.InstanceGuide.dungeon == enc.current.data and ns.InstanceGuide.entry.id == quest.id and not enc.window:IsShown(),
            "clicking a dungeon quest opens the corresponding Instance Guide quest")
        ns.InstanceGuide.frame:Hide(); enc.window:Show(); enc:Render()
    end
    enc.window.dungeonTabs.Bosses:Click()
    check(enc.window.rows[1].entry and enc.window.rows[1].entry.kind == "boss" and enc.window.bossPane:IsShown(), "each dungeon has its own ordered boss list and loot pane")
    check(enc.window.list:IsShown() and enc.window.list:GetWidth() == 300 and enc.window.detail:GetWidth() == 552,
        "boss page fits boss list and loot side by side")
    check(enc.window.rows[1].icon._texture == "gilnid-portrait" and enc.window.bossPane.meta:GetText():find("20", 1, true)
        and enc.window.bossPane.meta:GetText():find("Humanoid", 1, true), "boss portrait, level and creature type are displayed")
    check(enc.window.instanceHeader:IsShown() and enc.window.instanceHeader.title:GetText() == "The Deadmines"
        and enc.window.instanceHeader.art._texture == 131833, "instance header displays its name and loading-screen artwork")
    check(enc.window.rows[1].entry.name == "Gilnid" and enc.window.rows[2].entry.name == "VanCleef"
        and enc.window.rows[2].icon._texture == "vancleef-portrait", "bosses retain source order and individual portraits")
    check(enc.window.bossPane.rows[1].chance:GetText() == "34%" and enc.window.bossPane.rows[1].dropKills == 120,
        "boss loot displays the observed drop chance and preserves its evidence")
    enc.window.rows[2]:Click()
    check(enc.window.bossPane.name:GetText() == "VanCleef" and enc.window.bossPane.rows[1].chance:GetText() == "?",
        "selecting another boss updates loot and leaves unknown chances unknown")
    enc.window.rows[1]:Click()
    enc.window.bossPane.rows[1]:Click()
    check(enc.current.kind == "item", "clicking boss loot opens the item")
    enc:Back()
    check(enc.dungeonView == "Bosses" and enc.boss and enc.boss.name == "Gilnid" and enc.window.bossPane:IsShown(),
        "back from loot restores the selected dungeon boss")
    enc.window.dungeonTabs.Loot:Click()
    check(enc.window.dungeonList.rows[1].entry and enc.window.dungeonList.rows[1].entry.kind == "item" and not enc.window.linksNext:IsShown(), "dungeon loot uses a scrollable grid without pages")
    local oldItemAPI = C_Item
    C_Item = { GetItemIconByID = function(id) return "item-icon-" .. id end }
    enc:Render()
    check(enc.window.dungeonList.rows[1].icon._texture == "item-icon-100", "item links use the item icon")
    C_Item = oldItemAPI
    do
        local links = enc.current.links
        local originalCount = #links
        for i = 1, 22 do
            links[#links + 1] = {kind="item", category="Armory", key="item:fake" .. i, name=string.format("Extra loot %02d", i), data={id=900000+i}, links={}}
        end
        enc:Render()
        check(enc.window.dungeonList.rows[18]:IsShown() and enc.window.dungeonList.scrollbar.fuiMaximum > 0,
            "long loot lists fill the panel and offer a draggable scrollbar")
        enc.window.dungeonList.scrollbar._scripts.OnValueChanged(enc.window.dungeonList.scrollbar, enc.window.dungeonList.scrollbar.fuiMaximum)
        check(enc.dungeonListOffset > 0 and enc.window.dungeonList.rows[1].entry ~= nil,
            "dragging the loot scrollbar reaches additional items")
        while #links > originalCount do table.remove(links) end
        enc:Render()
        local oldClass, oldFaction = UnitClass, UnitFactionGroup
        UnitClass = function() return "Paladin", "PALADIN" end
        UnitFactionGroup = function() return "Horde" end
        links[#links + 1] = {kind="quest", key="quest:class-test", name="Other class", data={id=998001, class="ROGUE", side="Both"}, links={}}
        enc.window.dungeonTabs.Quests:Click()
        local foundOther = false
        for _, row in ipairs(enc.window.dungeonList.rows) do if row.entry and row.entry.name == "Other class" then foundOther = true end end
        check(not foundOther, "the encyclopedia dungeon quest tab hides quests for other classes")
        table.remove(links)
        UnitClass, UnitFactionGroup = oldClass, oldFaction
    end
    enc.window.tabs.Pets:Click()
    check(enc.window.rows[1].entry and enc.window.rows[1].entry.kind == "family", "pet browser starts with families")
    check(enc.window.petPane:IsShown() and enc.window.petPane.name:GetText() == "Cat"
        and enc.window.petPane.summary:GetText():find("Meat", 1, true) and enc.window.petPane.modifiers:GetText():find("1.07", 1, true),
        "pet family dashboard shows diet, role and modifiers")
    check(enc.window.petPane.abilities[1].entry.name == "Prowl" and enc.window.petPane.tames[1].entry.name == "Test Cat"
        and enc.window.petPane.showAll.text:GetText():find("2", 1, true), "family dashboard shows abilities and tame locations")
    enc.window.petPane.abilities[1]:Click()
    check(enc.window.rows[1].entry and enc.window.rows[1].entry.name == "Prowl", "pet abilities are filtered to the selected family")
    enc:Back()
    enc.window.petPane.showAll:Click()
    check(enc.petFilter == "tame" and enc.window.rows[1].entry and enc.window.rows[2].entry
        and enc.window.rows[1].entry.data.family == "Cat" and enc.window.rows[2].entry.data.family == "Cat", "show all opens the family tame list")
    enc.window.petTabs.rare:Click()
    check(enc.window.rows[1].entry and enc.window.rows[1].entry.name == "Rare Cat", "rare tames have a dedicated filter")
    enc.window.petTabs.family:Click()
    enc.query = "test cat"; enc:Render()
    check(enc.window.rows[1].entry and enc.window.rows[1].entry.name == "Cat", "pet family search finds related beasts")
    enc.query = ""; enc:Render()
    enc.window.tabs.Professions:Click()
    check(enc.window.profOverview:IsShown() and enc.window.profNav.Blacksmithing:IsShown(), "professions opens overview with profession sidebar")
    local savedProfessions, savedProfessionInfo, savedMap, savedFaction, savedPoint, savedTrack = GetProfessions, GetProfessionInfo, C_Map, UnitFactionGroup, UiMapPoint, C_SuperTrack
    GetProfessions = function() return 1 end
    GetProfessionInfo = function() return "Blacksmithing", "smith-icon", 63, 75 end
    UnitFactionGroup = function() return "Horde" end
    local trainerWaypoint
    C_Map = { GetBestMapForUnit = function() return 1411 end, GetPlayerMapPosition = function() return { x = 0.4, y = 0.7 } end,
        SetUserWaypoint = function(point) trainerWaypoint = point end }
    UiMapPoint = { CreateFromCoordinates = function(mapID, x, y) return { mapID = mapID, x = x, y = y } end }
    C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
    enc:Render()
    check(enc.window.profOverview.your[1].text:GetText() == "Blacksmithing" and enc.window.profOverview.your[1].sub:GetText() == "Skill 63/75",
        "profession overview shows current skill")
    enc.window.profOverview.trainers[2]:Click()
    check(trainerWaypoint and trainerWaypoint.mapID == 1411 and trainerWaypoint.x == 0.42, "profession trainer sets a waypoint")
    GetProfessions, GetProfessionInfo, C_Map, UnitFactionGroup, UiMapPoint, C_SuperTrack = savedProfessions, savedProfessionInfo, savedMap, savedFaction, savedPoint, savedTrack
    enc.window.profOverview.cards.Blacksmithing:Click()
    check(enc.profName == "Blacksmithing" and enc.window.rows[1].entry and enc.window.rows[1].entry.kind == "recipe", "profession card opens its recipes")
    do local searchPoint, searchParent, _, searchX, searchY = enc.window.search:GetPoint()
    check(searchPoint == "TOPLEFT" and searchParent == enc.window and searchX == 180 and searchY == -157 and enc.window.recipeKnownFilter:IsShown(),
        "profession search and knowledge filter sit above the recipe list") end
    enc.query = "rough stone"; enc:Render()
    check(enc.window.rows[1].entry and enc.window.rows[1].entry.name == "Blade", "recipe search matches reagent names")
    enc.query = ""; enc:Render()
    OneForAll.GetProfessionState = function() return { scanned = true, known = { [123] = true } } end
    enc.window.recipeKnownFilter:Click()
    check(enc.window.rows[1].entry and enc.window.rows[1].entry.name == "Anvil" and not enc.window.rows[2]:IsShown(), "learned filter uses the current character scan")
    enc.window.recipeKnownFilter:Click()
    check(enc.window.rows[1].entry and enc.window.rows[1].entry.name == "Blade" and not enc.window.rows[2]:IsShown(), "not learned filter uses the current character scan")
    enc.window.recipeKnownFilter:Click()
    OneForAll.GetProfessionState = nil
    check(enc.window.rows[2]:IsShown(), "all filter restores the full recipe list")
    enc.window.recipeKnownFilter:Click(); enc.window.recipeKnownFilter:Click()
    check(not enc.window.rows[1]:IsShown() and enc.window.source:GetText():find("Open this character's profession", 1, true),
        "unscanned recipes are not mislabeled as unlearned")
    enc.window.recipeKnownFilter:Click()
    check(enc.window.recipePane:IsShown() and enc.window.recipePane.reagents[1].text:GetText():find("Bronze Bar", 1, true), "recipe page shows reagents")
    enc.window.recipePane.favorite:Click(); enc.window.profViews.favorites:Click()
    check(enc.window.rows[1].entry and enc.window.rows[1].entry.name == "Anvil", "recipe favorites are selectable")
    enc.window.profViews.skill:Click()
    check(enc.window.profHelper:IsShown() and enc.window.profHelper.rows[1].text:GetText():find("Anvil", 1, true), "skill-up helper shows computed route")
    local oldGoldPrice, oldBuyout, oldProvider, oldPlan = ForeverGold.AHPrice, ForeverGold.IsBuyout, OneForAll.SkillUp.AHPrice, OneForAll.SkillUp.Plan
    local seenBuyout, seenBid
    ForeverGold.AHPrice = function() return 7 end
    ForeverGold.IsBuyout = function(id) return id == 1 end
    OneForAll.SkillUp.AHPrice = function() return 30 end
    OneForAll.SkillUp.Plan = function() seenBuyout = OneForAll.SkillUp.AHPrice(1); seenBid = OneForAll.SkillUp.AHPrice(2); return { cost = 0, steps = {}, mats = {} } end
    local provider = OneForAll.SkillUp.AHPrice
    enc.window.profHelper.recalculate:Click()
    check(seenBuyout == 7 and seenBid == 30 and OneForAll.SkillUp.AHPrice == provider, "skill-up uses Forever Gold buyouts and restores the original price provider")
    OneForAll.SkillUp.Plan = function() error("simulated planning failure") end
    enc.window.profHelper.recalculate:Click()
    check(OneForAll.SkillUp.AHPrice == provider and enc.window.profHelper.summary:GetText():find("error", 1, true), "price provider is restored when planning fails")
    ForeverGold.AHPrice, ForeverGold.IsBuyout, OneForAll.SkillUp.AHPrice, OneForAll.SkillUp.Plan = oldGoldPrice, oldBuyout, oldProvider, oldPlan
    enc.window.profViews.profit:Click()
    check(enc.window.profHelper:IsShown() and enc.window.profHelper.rows[1].text:GetText():find("profit", 1, true), "profit page displays estimated profit")
    enc.window.profNav.Camping:Click()
    check(enc.selected == "Professions" and enc.profFilter == "Camping" and enc.window.rows[1].entry.kind == "campingGroup", "camping groups objects by profession")
    enc.window.rows[1]:Click()
    check(enc.window.rows[2].entry and enc.window.rows[2].entry.name == "Test Camp Anvil", "camping group expands its objects")
    enc.window.profNav.Favor:Click()
    check(enc.profFilter == "Favor" and enc.window.favorOverview:IsShown(), "Merchant's Favor shows its overview")
    enc.window.favorOverview.cards.Blacksmithing:Click()
    check(enc.profView == "favor" and enc.window.rows[1].entry and enc.window.rows[1].entry.kind == "favor", "Favor card opens profession Favor recipes")
    check(enc.window.recipePane.info:GetText():find("45 Merchant's Favor", 1, true), "Favor recipe displays its recorded cost")
    enc.window.tabs.Armory:Click()
    check(enc.window.planner:IsShown() and enc.window.armorTabs.raid:IsShown(), "armory opens the gear planner with set categories")
    check(not enc.plannerSlot and enc.plannerLastSlotID == 1 and enc.window.planner.slots[1].fuiPanel.bright
        and enc.window.planner.allSlots.fuiPanel.bright and enc.window.planner.allSlots.check:IsShown(), "all slots is checked by default while head is highlighted")
    enc.window.planner.allSlots:Click()
    check(enc.plannerSlot == "Head" and not enc.window.planner.allSlots.check:IsShown(), "turning off all slots selects head by default")
    enc.window.planner.allSlots:Click()
    check(enc.window.profSearchHint:IsShown() and enc.window.profSearchHint:GetText() == "Search items...", "armory has an in-place item search field")
    enc.window.planner.slots[1]:Click()
    check(enc.plannerSlot == "Head" and enc.window.planner.rows[1].entry and enc.window.planner.rows[1].entry.name == "Test Helmet", "gear planner filters items by equipment slot")
    enc.window.planner.allSlots:Click()
    check(enc.plannerSlot == nil, "All slots opens the overview")
    enc.window.planner.allSlots:Click()
    check(enc.plannerSlot == "Head", "All slots restores the previously selected slot")
    do
        local candidates = {}
        for i = 1, 4 do candidates[#candidates + 1] = { name = "Head " .. i, percent = 100-i, entry = { data = { gear = { loc = "HEAD" } } } } end
        for i = 1, 4 do candidates[#candidates + 1] = { name = "Chest " .. i, percent = 80-i, entry = { data = { gear = { loc = "CHEST" } } } } end
        local limited = enc.TopUpgradesPerSlot(candidates, { HEAD = { 1 }, CHEST = { 5 } })
        check(#limited == 6 and limited[1].name == "Head 1" and limited[3].name == "Head 3" and limited[4].name == "Chest 1" and limited[6].name == "Chest 3",
            "the overview keeps the three best scored upgrades per slot in slot order")
        local page = enc.PlannerPage(limited, 0, true)
        check(page[1].heading and not page[2].heading and page[4].heading, "overview labels the start of each equipment category")
        local tail = enc.PlannerPage(limited, enc.PlannerMaxOffset(limited, true), true)
        check(tail[1].heading and tail[#tail].candidate.name == "Chest 3", "scrolling retains a heading and reaches the last upgrade")
        check(enc.ItemUnavailable({ data = { id = 211857 } }) and not enc.ItemUnavailable({ data = { id = 220446 } })
            and not enc.ItemUnavailable({ data = { id = 99999999 } }), "only items explicitly marked unavailable are excluded")
        check(not enc.ItemUnavailable({data={id=211857, observed=true}}), "conflicting tracker observations remain visible for review")
        check(not enc.ItemUnavailable({data={id=215369}}), "conflicting Wowhead availability and source information stays visible")
        check(enc.byKey["item:215369"] and enc.Details(enc.byKey["item:215369"]):find("Availability needs review", 1, true), "conflicting item details explain the uncertainty")
        local classicItem = enc.byKey["item:182"]
        local hasClassicSource = false
        for _, source in ipairs(classicItem and classicItem.data.sourceLinks or {}) do
            if source.entry and source.entry.name == "Garrick Padfoot" and source.note and source.note:find("Classic reference", 1, true) then hasClassicSource = true end
        end
        check(hasClassicSource, "supplemental Classic source links are present and labelled")
        check(not enc.ArmoryEquipment({ data = { slot = "Non-equippable" } }) and not enc.ArmoryEquipment({ data = { slot = "Bag" } })
            and enc.ArmoryEquipment({ data = { slot = "Head" } }), "non-equipment is excluded from the gear planner")
    end
    do
        local original, calls = OneForAll.GearValue.Change, 0
        OneForAll.GearValue.Change = function(id) calls = calls + 1; return original(id) end
        enc.plannerCache, enc.gearChangeMemo = nil, nil; enc:Render(); local before = calls
        enc.window.planner.rows[1]:GetScript("OnMouseWheel")(enc.window.planner.rows[1], -1); enc:FinishPlannerScroll()
        check(before > 0 and calls == before, "scrolling reuses cached gear recommendations")
        OneForAll.GearValue.Change = original
    end
    do
        local oldAfter, oldCached, oldRequest, oldIcon, oldChange = C_Timer.After, C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID, C_Item.GetItemIconByID, OneForAll.GearValue.Change
        local callbacks, ready, requested = {}, false, {}
        C_Timer.After = function(delay, fn) callbacks[#callbacks + 1] = { delay = delay, fn = fn } end
        C_Item.IsItemDataCachedByID = function(id) return id ~= 988001 and id ~= 988002 or ready end
        C_Item.RequestLoadItemDataByID = function(id) requested[id] = true end
        C_Item.GetItemIconByID = function() return 134400 end
        OneForAll.GearValue.Change = function() return "up", 5 end
        local data = enc.window.planner.rows[1].entry.data; local originalID = data.id
        data.id = 988001; enc.plannerVerdicts = nil; enc.plannerCache, enc.itemPollPending, enc.itemRefreshPending, enc.plannerScrollTime = nil, nil, nil, nil; enc.window:Show(); enc:Render()
        check(requested[988001] and enc.window.planner.resultsInfo:GetText():find("item data loading", 1, true), "uncached recommendation requests item data")
        ready = true; enc.itemEvents:GetScript("OnEvent")(enc.itemEvents, "ITEM_DATA_LOAD_RESULT", 988001, true)
        for _, callback in ipairs(callbacks) do if callback.delay == 0.25 then callback.fn(); break end end
        check(enc.window.planner.rows[1].entry and enc.window.planner.rows[1].entry.data.id == 988001, "item completion event automatically refreshes the armory")
        callbacks, ready, enc.itemPollPending = {}, false, nil; data.id = 988002; enc.plannerCache, enc.plannerVerdicts = nil, nil; enc:Render()
        ready = true; for _, callback in ipairs(callbacks) do if callback.delay == 1 then callback.fn(); break end end
        check(requested[988002] and enc.window.planner.rows[1].entry and enc.window.planner.rows[1].entry.data.id == 988002, "armory recovers automatically if the completion event is missed")
        data.id = originalID; C_Timer.After, C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID, C_Item.GetItemIconByID, OneForAll.GearValue.Change = oldAfter, oldCached, oldRequest, oldIcon, oldChange
        enc.plannerCache, enc.itemPollPending, enc.itemRefreshPending = nil, nil, nil; enc:Render()
    end
    do
        local oldAfter, oldIcon, oldChange, oldClock = C_Timer.After, C_Item.GetItemIconByID, OneForAll.GearValue.Change, MOCK.clock
        local callbacks, additions = {}, {}
        C_Timer.After = function(delay, fn) callbacks[#callbacks + 1] = { delay = delay, fn = fn } end
        C_Item.GetItemIconByID = function() return 134400 end
        OneForAll.GearValue.Change = function() return "up", 5 end
        for i = 1, 9 do
            local entry = { kind = "item", category = "Armory", key = "item:" .. (990000 + i), name = "Test scroll " .. i, data = { id = 990000 + i, slot = "Head", gear = { loc = "INVTYPE_HEAD", cid = 4, sub = 2, lvl = 1 } }, links = {} }
            enc.entries[#enc.entries + 1] = entry; enc.byKey[entry.key] = entry; additions[#additions + 1] = entry
        end
        enc.plannerCache, enc.plannerShown, enc.plannerOffset, enc.plannerScrollTime = nil, nil, 0, nil; enc:Render()
        enc.window.planner.rows[1]:GetScript("OnMouseWheel")(enc.window.planner.rows[1], -1); enc:FinishPlannerScroll()
        local anchor = enc.window.planner.rows[1].entry.key
        local inserted = { kind = "item", category = "Armory", key = "item:990100", name = "A newly loaded item", data = { id = 990100, slot = "Head", gear = { loc = "INVTYPE_HEAD", cid = 4, sub = 2, lvl = 1 } }, links = {} }
        enc.entries[#enc.entries + 1] = inserted; enc.byKey[inserted.key] = inserted; additions[#additions + 1] = inserted
        enc.gearDataRevision = (enc.gearDataRevision or 0) + 1; enc:Render()
        check(enc.window.planner.rows[1].entry.key == anchor and enc.window.planner.resultsInfo:GetText():find("updating after scrolling", 1, true), "incoming items do not change visible rows during scrolling")
        MOCK.clock = oldClock + 1; for _, callback in ipairs(callbacks) do if callback.delay == 0.8 then callback.fn(); break end end
        local found = false; for _, candidate in ipairs(enc.plannerShown.candidates) do if candidate.entry == inserted then found = true end end
        check(found and enc.window.planner.rows[1].entry.key == anchor, "loaded items appear after scrolling while preserving the top item")
        for _, entry in ipairs(additions) do enc.byKey[entry.key] = nil end
        for i = #enc.entries, 1, -1 do if enc.entries[i].key:find("item:990", 1, true) == 1 then table.remove(enc.entries, i) end end
        C_Timer.After, C_Item.GetItemIconByID, OneForAll.GearValue.Change, MOCK.clock = oldAfter, oldIcon, oldChange, oldClock
        enc.plannerCache, enc.plannerShown, enc.plannerOffset, enc.plannerScrollTime, enc.plannerUpdateScheduled = nil, nil, 0, nil, nil; enc:Render()
    end
    do
        -- the client's item cache drops items as others load: a scored item
        -- keeps its place instead of the total cycling on every refresh
        local oldCached, oldChange, oldRequest = C_Item.IsItemDataCachedByID, OneForAll.GearValue.Change, C_Item.RequestLoadItemDataByID
        local evicted, calls = false, 0
        C_Item.RequestLoadItemDataByID = function() end
        OneForAll.GearValue.Change = function() calls = calls + 1; return "up", 5 end
        enc.gearChangeMemo, enc.gearFacts, enc.gearFilterMemo = nil, nil, nil
        enc.plannerCache, enc.plannerShown, enc.plannerOffset, enc.plannerScrollTime = nil, nil, 0, nil; enc:Render()
        local before, firstCalls = #enc.plannerShown.candidates, calls
        C_Item.IsItemDataCachedByID = function() return evicted end
        evicted = false
        enc.gearDataRevision = (enc.gearDataRevision or 0) + 1; enc.plannerCache = nil; enc:Render()
        check(before > 0 and #enc.plannerShown.candidates == before and calls == firstCalls
            and not enc.window.planner.resultsInfo:GetText():find("item data loading", 1, true),
            "armory keeps scored items when the client's item cache drops them")
        C_Item.IsItemDataCachedByID, OneForAll.GearValue.Change, C_Item.RequestLoadItemDataByID = oldCached, oldChange, oldRequest
        enc.gearChangeMemo, enc.plannerCache, enc.plannerShown = nil, nil, nil; enc:Render()
    end
    do
        -- smooth scrolling: a wheel notch glides, the bar drags pixel by pixel,
        -- and an item whose score was cleared by an event keeps its last one
        local oldChange, oldIcon, oldCached, oldRequest = OneForAll.GearValue.Change, C_Item.GetItemIconByID, C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID
        local additions = {}
        C_Item.GetItemIconByID = function() return 134400 end
        C_Item.RequestLoadItemDataByID = function() end
        OneForAll.GearValue.Change = function() return "up", 5 end
        for i = 1, 9 do
            local entry = { kind = "item", category = "Armory", key = "item:" .. (991000 + i), name = "Glide test " .. i, data = { id = 991000 + i, slot = "Head", gear = { loc = "INVTYPE_HEAD", cid = 4, sub = 2, lvl = 1 } }, links = {} }
            enc.entries[#enc.entries + 1] = entry; enc.byKey[entry.key] = entry; additions[#additions + 1] = entry
        end
        enc.plannerVerdicts, enc.gearChangeMemo, enc.plannerCache, enc.plannerShown, enc.plannerOffset, enc.plannerScrollTime = nil, nil, nil, nil, 0, nil
        enc.plannerPixel, enc.plannerTarget = 0, nil; enc:Render()
        local planner = enc.window.planner
        planner.rows[1]:GetScript("OnMouseWheel")(planner.rows[1], -1)
        check(enc.plannerTarget == 49 and planner.glide:IsShown() and enc.plannerPixel == 0, "a wheel notch starts a glide instead of jumping")
        planner.glide:GetScript("OnUpdate")(planner.glide, 0.016)
        local _, _, _, _, y = planner.rows[1]:GetPoint()
        check(enc.plannerPixel > 0 and enc.plannerPixel < 49 and math.abs(y - enc.plannerPixel) < 0.01, "mid-glide the top row is part scrolled out: " .. tostring(enc.plannerPixel))
        planner.glide:GetScript("OnUpdate")(planner.glide, 1); planner.glide:GetScript("OnUpdate")(planner.glide, 1)
        check(enc.plannerPixel == 49 and enc.plannerOffset == 1 and not planner.glide:IsShown(), "the glide lands one row down")
        planner.scrollbar:GetScript("OnValueChanged")(planner.scrollbar, 20)
        _, _, _, _, y = planner.rows[1]:GetPoint()
        check(enc.plannerPixel == 20 and y == 20, "the scroll bar moves the list pixel by pixel")

        local before = #enc.plannerShown.candidates
        OneForAll.GearValue.Change = function() return nil end
        C_Item.IsItemDataCachedByID = function() return false end
        OneForAll.GearValue.gen = (OneForAll.GearValue.gen or 0) + 1
        enc.plannerCache, enc.plannerScrollTime = nil, nil; enc:Render()
        check(#enc.plannerShown.candidates == before, "items keep their last score while the engine reloads them")

        for _, entry in ipairs(additions) do enc.byKey[entry.key] = nil end
        for i = #enc.entries, 1, -1 do if enc.entries[i].key:find("item:991", 1, true) == 1 then table.remove(enc.entries, i) end end
        OneForAll.GearValue.Change, C_Item.GetItemIconByID, C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID = oldChange, oldIcon, oldCached, oldRequest
        enc.plannerVerdicts, enc.gearChangeMemo, enc.plannerCache, enc.plannerShown, enc.plannerOffset, enc.plannerPixel = nil, nil, nil, nil, 0, 0; enc:Render()
    end
    check(enc.IsTestName("QAEnchant Gloves +5 Fishing") and enc.IsTestName("Fishing Pole (JEFFTEST)") and enc.IsTestName("DEBUG Samophlange Manual Page")
        and enc.IsTestName("DND FLAG The Dread Citadel - Naxxramas") and not enc.IsTestName("Test of Faith") and not enc.IsTestName("The Gordok Taste Test")
        and not enc.IsTestName("Quaint Ring") and enc.IsTestName("Ring of Critical Testing 2")
        and enc.IsTestName("TestBoots - Puffed Mail Green") and enc.IsTestName("Potion of Tradeskill Testing - Level 60")
        and not enc.IsTestName("Field Testing Kit") and not enc.IsTestName("Testament of Hope")
        and not enc.IsTestName("Contest Winner's Tabard") and enc.IsTestName("Hidden Boots (DNT)")
        and enc.IsTestName("Template Vellum [DNT]") and enc.IsTestName("NOT USED")
        and enc.IsTestName("Template Item") and enc.IsTestName("Internal Warrior Equipment Kit L25")
        and enc.IsTestName("Ribbon Pole Debug Target") and not enc.IsTestName("Unused Scraping Vial")
        and not enc.IsTestName("Stormwind Armor Marker") and not enc.IsTestName("Unstable Trigger") and not enc.IsTestName("Templar Boots"), "developer test items are recognised without catching real names")
    do
        local real = { kind = "item", name = "Blump Family Fishing Pole", data = { id = 12225, slot = "Two-Hand", gear = { loc = "INVTYPE_2HWEAPON" }, reference = {} } }
        local copy = { kind = "item", name = "Blump Family Fishing Pole", data = { id = 12221, slot = "Two-Hand", reference = { estimated = true } } }
        local other = { kind = "item", name = "Darkwood Fishing Pole", data = { id = 6366, slot = "Two-Hand" } }
        local list = enc.DedupeItems({ copy, other, real })
        check(#list == 2 and list[1] == real and list[2] == other, "an item listed twice shows once, as the copy with gear data")
    end
    do
        local oldTooltip = C_TooltipInfo
        C_TooltipInfo = { GetItemByID = function() return { lines = { { leftText = "Increases your fishing skill by 5." } } } end }
        check(enc.ProfessionBonus(990200), "profession bonus is identified from the item tooltip")
        C_TooltipInfo.GetItemByID = function() return { lines = {} } end
        check(enc.ProfessionBonus(990200), "a temporarily empty tooltip does not remove a confirmed profession bonus")
        C_TooltipInfo = oldTooltip
    end
    enc.window.planner.rows[1].star:Click(); check(enc.window.wishMenu:IsShown() and enc.window.wishMenu.rows[1].text:GetText():find("Wishlist", 1, true), "plus button opens wishlist choices"); enc.window.wishMenu.rows[1]:Click()
    check(enc.WishlistHas(101), "gear planner saves wishlist items")
    local savedUnitGUID = UnitGUID
    UnitGUID = function() return "DifferentCharacter" end
    check(not enc.WishlistHas(101), "wishlists are separate per character")
    UnitGUID = savedUnitGUID
    enc.window.planner.wishlist:Click()
    check(enc.window.planner.rows[1].entry and enc.window.planner.rows[1].entry.name == "Test Helmet", "wishlist shows saved items")
    enc:RefreshData(); enc:Render()
    check(enc.WishlistHas(101) and enc.window.planner.rows[1].entry and enc.window.planner.rows[1].entry.data.id == 101,
        "wishlist survives a reference-data refresh")
    local triedOn
    enc.window.planner.model.TryOn = function(_, id) triedOn = id end
    enc.window.planner.rows[1].preview:Click()
    check(triedOn == 101, "gear planner can preview a recorded item on the model")
    do
        enc.window.planner.setName:SetText("Dungeon build"); enc.window.planner.createSet:Click()
        check(enc.activeGearSet == "Dungeon build" and not enc.WishlistHas(101), "new named gear set starts separately from the default wishlist")
        enc.window.planner.suggested:Click(); enc.window.planner.rows[1].star:Click(); enc.window.wishMenu.rows[2]:Click(); enc.window.planner.wishlist:Click()
        check(enc.WishlistHas(101) and enc.window.planner.rows[1].entry.data.id == 101, "gear set stores selected wishlist items")
        enc.window.planner.suggested:Click(); enc.window.planner.rows[1].star:Click()
        check(enc.window.wishMenu.rows[1].status:GetText() == "Added" and enc.window.wishMenu.rows[2].status:GetText() == "Added", "wishlist menu identifies each set already containing the item")
        enc.window.wishMenu:Hide(); enc.window.planner.wishlist:Click()
        check(enc.window.planner.rows[1].star.text:GetText() == "Remove", "wishlist exposes an explicit remove button")
        enc.window.planner.rows[1].star:Click()
        check(not enc.WishlistHas(101), "remove clears the item from the selected set")
        enc.window.planner.setSelector:Click()
        check(enc.WishlistHas(101), "removing from a set preserves the default wishlist")
        enc.window.planner.setSelector:Click()
        enc.window.planner.suggested:Click(); enc.window.planner.rows[1].star:Click(); enc.window.wishMenu.rows[2]:Click(); enc.window.planner.wishlist:Click()
        enc.window.planner.setName:SetText("Raid build"); enc.window.planner.renameSet:Click()
        check(enc.activeGearSet == "Raid build" and enc.WishlistHas(101), "renaming a gear set preserves its contents")
        enc.window.planner.setName:SetText("Another set"); enc.window.planner.createSet:Click()
        enc.window.planner.setName:SetText("Raid build"); enc.window.planner.renameSet:Click()
        check(enc.activeGearSet == "Another set", "renaming cannot overwrite an existing gear set")
        enc.window.planner.deleteSet:Click()
        check(enc.activeGearSet == "Another set" and enc.window.planner.deleteSet.text:GetText() == "Confirm", "deleting a gear set requires confirmation")
        enc.window.planner.deleteSet:Click()
        check(not enc.activeGearSet and enc.WishlistHas(101), "deleting a gear set returns to and preserves the default wishlist")
        enc.window.planner.setSelector:Click()
        check(enc.activeGearSet == "Raid build" and enc.WishlistHas(101), "renamed gear set remains selectable")
        enc.window.planner.setSelector:Click(); check(not enc.activeGearSet and enc.WishlistHas(101), "switching sets preserves the original wishlist")
    end
    do
        local oldTooltip = C_TooltipInfo
        enc.window.planner.suggested:Click(); enc.window.planner.filterChoices["cloth:type"]:Click()
        check(not enc.window.planner.rows[1]:IsShown(), "armor type filter excludes other armor")
        enc.window.planner.filterChoices["leather:type"]:Click()
        check(enc.window.planner.rows[1].entry and enc.window.planner.rows[1].entry.data.id == 101, "armor type filter includes matching armor")
        C_TooltipInfo = { GetItemByID = function() return { lines = { { leftText = "Increases smelting speed of copper, tin and iron ore by 25%." } } } end }
        enc.window.planner.filterChoices["profession:type"]:Click()
        check(enc.window.planner.rows[1].entry and enc.window.planner.rows[1].entry.data.id == 101, "profession bonuses include unique smelting speed effects")
        enc.window.planner.filterChoices["all:type"]:Click(); enc.window.planner.filterChoices["quest:source"]:Click()
        check(not enc.window.planner.rows[1]:IsShown(), "quest source filter excludes unrelated gear")
        enc.window.planner.filterChoices["all:source"]:Click()
        enc.window.planner.minLevel:SetText("2"); enc.window.planner.maxLevel:SetText("5"); enc.window.planner.minLevel:GetScript("OnEnterPressed")(enc.window.planner.minLevel)
        check(not enc.window.planner.rows[1]:IsShown(), "custom minimum level filters lower-level gear")
        enc.window.planner.allLevels:Click()
        check(enc.gearLevelMode == "all" and enc.window.planner.minLevel:GetText() == "1" and enc.window.planner.maxLevel:GetText() == "60" and enc.plannerSlot == "Head",
            "All sets only the level range to 1–60 and preserves the selected slot")
        enc.window.planner.myLevel:Click(); C_TooltipInfo = oldTooltip
    end
    do
        local oldID, oldLink, oldInstant, oldItemAPI = GetInventoryItemID, GetInventoryItemLink, GetItemInfoInstant, C_Item
        C_Item = nil
        GetInventoryItemID = function(_, slot) if slot == 1 then return 101 end end
        GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:101:0:0:0|h[Test Helmet]|h" end end
        GetItemInfoInstant = function(id) if id == 101 then return id, nil, nil, "INVTYPE_HEAD", nil, 4, 1 end end
        OneForAll.ENCHANT_OPTIONS = {
            { e = 41, n = "Head Stamina", p = "Enchanting", s = 7418, req = 1, c = 4, t = 2, m = 2 },
            { e = 42, n = "Wrong slot", p = "Enchanting", s = 7419, c = 4, t = 1024, m = 2 },
        }
        OneForAll.ENCHANTS = { [41] = { "+3 Stamina" } }
        OneForAll.GearValue.EnchantValue = function(id) if id == 41 then return 5 end end
        OneForAll.GearValue.Total = function() return 100 end
        enc.window.planner.suggested:Click()
        check(enc.window.planner.slots[1].enchant:IsShown() and enc.window.planner.slots[1].enchant.text:GetText() == "+", "compatible equipped slot shows an enchant button")
        enc.window.planner.slots[1].enchant:Click()
        check(enc.window.planner.rows[1].enchant and enc.window.planner.rows[1].enchant.n == "Head Stamina"
            and not enc.window.planner.rows[2]:IsShown() and enc.window.planner.rows[1].sub:GetText():find("+5.0%%"), "enchant list filters compatibility and displays comparable value")
        check(enc.window.planner.rows[1].enchantInfo:GetText():find("Xeon Mana", 1, true) and enc.window.planner.rows[1].enchantInfo:GetText():find("Test Vendor", 1, true),
            "enchant row shows recorded crafters and acquisition source")
        local details = enc.EnchantDetails(OneForAll.ENCHANT_OPTIONS[1])
        check(details.characters[1] == "Xeon Mana" and details.sources[1]:find("Test Vendor", 1, true) and details.sources[2]:find("Test Mob", 1, true),
            "enchant detail preserves all recorded vendor and drop sources")
        local missing = enc.EnchantDetails({ n = "Unknown enchant", s = 987654, p = "Enchanting" })
        check(missing.sources[1] == "Source not recorded", "missing enchant acquisition data is explicit")
        enc.window.planner.rows[1].star:Click(); enc.window.wishMenu.rows[1]:Click(); enc.window.planner.wishlist:Click()
        check(enc.window.planner.rows[1].enchant and enc.window.planner.rows[1].enchant.n == "Head Stamina", "enchant wishlist shows the saved enhancement")
        local options = OneForAll.ENCHANT_OPTIONS
        OneForAll.ENCHANT_OPTIONS = nil; enc.window.planner.allSlots:Click()
        check(enc.window.planner.rows[1].enchant and enc.window.planner.rows[1].enchant.n == "Head Stamina", "saved enhancements remain visible when reference options are unavailable")
        OneForAll.ENCHANT_OPTIONS = options; enc.window.planner.slots[1].enchant:Click(); enc.window.planner.wishlist:Click()
        enc.window.planner.rows[1].star:Click()
        check(not enc.window.planner.rows[1]:IsShown(), "wishlist remove button removes the saved enhancement")
        GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:101:41:0:0|h[Test Helmet]|h" end end
        enc:Render()
        check(enc.window.planner.slots[1].enchant.icon:IsShown() and enc.window.planner.slots[1].enchant.text:GetText() == "", "equipped enchant replaces the plus with an icon")
        GetInventoryItemID, GetInventoryItemLink, GetItemInfoInstant, C_Item = oldID, oldLink, oldInstant, oldItemAPI
        OneForAll.ENCHANT_OPTIONS, OneForAll.ENCHANTS = nil, nil
        enc.window.planner.suggested:Click(); enc.window.planner.allSlots:Click()
    end
    enc.window.armorTabs.raid:Click()
    check(enc.setClass == "PALADIN", "armory defaults to the player's class")
    enc.window.setControls.classes.HUNTER:Click()
    check(enc.setGroup == "raid" and enc.window.rows[1].entry and enc.window.rows[1].entry.name == "Test Armor" and enc.window.setPane:IsShown(), "raid sets sidebar opens the raid set list")
    check(enc.window.rows[1].icon:IsShown() and enc.window.setControls.subs[1].text:GetText() == "Tier 1", "set list uses piece icons and tier buttons")
    check(enc.window.setPane.pieces[1].entry and enc.window.setPane.bonuses:GetText():find("Bonus", 1, true), "set page shows pieces and bonuses")
    enc.window.setControls.classes.MAGE:Click()
    check(not enc.window.setPane:IsShown(), "set class filter excludes sets for other classes")
    enc.window.setControls.classes.ALL:Click()
    check(not enc.window.armorTabs.armor and not enc.window.armorTabs.item and not enc.window.armorTabs.set and not enc.window.armorPath:IsShown(), "redundant armory tabs and breadcrumb are removed")
    enc.window.tabs.Reputations:Click()
    check(enc.window.rows[1].entry and enc.window.rows[1].entry.kind == "faction" and enc.window.repPane:IsShown(), "reputations show the faction list and selected details")
    check(enc.window.repPane.vendors[1].vendor and enc.window.repPane.rows[2].reward[2] == "Test Helm", "reputation details include vendors and grouped rewards")
    M.testReputationTracking = function()
        local old = C_Reputation
        local factionID = enc.current.data.id
        local tracked = nil
        C_Reputation = {
            GetNumFactions = function() return 1 end,
            GetFactionDataByIndex = function() return { factionID = tracked == false and 999999 or factionID } end,
            GetFactionDataByID = function() return { reaction = 4, currentReactionThreshold = 0, nextReactionThreshold = 3000, currentStanding = 200 } end,
            GetWatchedFactionData = function() return tracked and { factionID = tracked } end,
            SetWatchedFactionByID = function(id) tracked = id end,
        }
        tracked = false; enc:Render()
        check(enc.window.repPane.standing:GetText():find("Not in your reputation list", 1, true), "unlisted factions do not show default reputation as confirmed")
        tracked = nil; enc:Render(); enc.window.repPane.track:Click()
        check(tracked == factionID and enc.window.repPane.track.text:GetText() == "Tracked", "track selects the listed faction with the client API")
        C_Reputation = old
    end
    M.testReputationTracking(); M.testReputationTracking = nil
    enc.window.repPane.filters.Recipes:Click()
    check(enc.window.repPane.rows[2].reward[2] == "Test Formula", "reputation reward filter selects recipes")
    enc.window.tabs["Library Books"]:Click()
    check(enc.window.libraryPane:IsShown() and enc.window.libraryPane.rows[2].book.name == "Test Book", "library shows books in grouped full-width rows")
    OneForAll.BOOK_REWARD_TIERS = {{ books = "10 books", quest = "Test reward", items = {{ 99103, "Test Pendant", 2, "Neck" }} }}
    enc.window.bookHelp:Click()
    check(enc.window.bookHelpPane:IsShown() and enc.window.bookHelpPane.tiers[1].items[1].item[2] == "Test Pendant", "library help shows recorded reward tiers")
    OneForAll.GetBookState = function() return "missing" end; enc:Render()
    check(enc.window.libraryPane.rows[2].text:GetText() == "Missing", "library shows missing status")
    enc.window.libraryPane.rows[2]:Click("RightButton")
    check(enc.window.libraryPane.rows[2].text:GetText() == "Manual", "library keeps a distinct manual completion mark")
    OneForAll.GetBookState = nil
    enc.window.libraryPane.rows[1]:Click()
    check(not enc.window.libraryPane.rows[2].book, "library sets can be collapsed")
    do
        local oldTooltip, oldItemInfo, oldQuestInfo = C_TooltipInfo, C_Item.GetItemInfo, OneForAll.QuestInfo
        C_TooltipInfo = { GetItemByID = function() return { lines = { { leftText = "Test Helmet" }, { leftText = "+5 Strength", leftColor = { r = 0, g = 1, b = 0 } }, { leftText = "Two-Hand", rightText = "Mace" }, {leftText = "Line 4"}, {leftText = "Line 5"}, {leftText = "Line 6"}, {leftText = "Line 7"}, {leftText = "Line 8"}, {leftText = "Line 9"}, {leftText = "Line 10"}, {leftText = "Line 11"}, {leftText = "Line 12"} } } end }
        C_Item.GetItemInfo = function(id) return "Test Helmet", "item:" .. id, 2, 12, 8 end
        OneForAll.QuestInfo = function(id) return { id = id, name = "Test reward quest", lvl = 10, req = 8, giver = "Test giver", loc = { mapID = 1411, x = 42, y = 71 } } end
        local itemEntry = enc.byKey["item:101"]; itemEntry.data.gear.qid = 9999977; itemEntry.data.gear.src = "Quest: Test reward quest"
        enc:OpenEntry(itemEntry)
        check(enc.window.itemWish.text:GetText() == "+" and enc.window.detailText:GetText():find("Required level to wear: 8", 1, true) and enc.window.detailText:GetText():find("+5 Strength", 1, true), "item detail shows tooltip and actual required level")
        check(enc.window.itemTooltip:IsShown() and not enc.window.detailText:IsShown() and not enc.window.detailNext:IsShown()
            and enc.window.itemTooltip.text:GetText():find("Line 12", 1, true) and enc.window.itemTooltip.text:GetText():find("|cff00ff00+5 Strength|r", 1, true)
            and enc.window.itemTooltip.text:GetText():find("Two-Hand    Mace", 1, true), "item pane shows the entire colored client tooltip without paging")
        local linkedQuest = false; for _, b in ipairs(enc.window.relatedButtons) do if b.entry and b.entry.kind == "quest" and b.entry.name == "Test reward quest" then linkedQuest = true end end
        check(linkedQuest, "quest reward links to its recorded quest")
        enc.window.itemWish:Click(); check(enc.window.wishMenu:IsShown(), "item detail plus opens the wishlist menu"); enc.window.wishMenu:Hide()
        C_TooltipInfo, C_Item.GetItemInfo, OneForAll.QuestInfo = oldTooltip, oldItemInfo, oldQuestInfo
        itemEntry.data.gear.qid = nil
    end
    local recipes = enc:Find("Professions", "anvil")
    enc:OpenEntry(recipes[1])
    local bossEntry = enc:Find("Dungeons", "gilnid")[1]
    local itemEntry = enc:Find("Armory", "blueprint: anvil")[1]
    local questEntry = enc:Find("Dungeons", "dungeon quest")[1]
    check(enc.window.recipePane.info:GetText():find("Xeon Mana", 1, true) ~= nil and bossEntry and itemEntry and questEntry,
        "recipe detail shows saved crafters and searchable boss, item and quest records")
    do
        local output=enc.byKey["item:101"];local original=recipes[1].links
        local oldIcon=C_Item.GetItemIconByID
        C_Item.GetItemIconByID=function(id) return "test-item-icon-"..id end
        recipes[1].links={output,itemEntry};enc.recipeLinkPage=1;enc:Render()
        local first,second=enc.window.recipePane.related[1],enc.window.recipePane.related[2]
        check(first.entry==output and first.icon:IsShown() and first.icon._texture=="test-item-icon-101"
            and second.entry==itemEntry and second.icon:IsShown() and second.icon._texture=="test-item-icon-100",
            "recipe related buttons show the output and plan item icons")
        second:Click();check(enc.current==itemEntry, "recipe related plan remains clickable with its icon")
        enc:Back();recipes[1].links=original;C_Item.GetItemIconByID=oldIcon;enc.recipeLinkPage=1;enc:Render()
    end
    do
        local favorSource
        for _,src in ipairs(itemEntry.data.sourceLinks or {}) do if src.kind=="Merchant's Favor" then favorSource=src end end
        check(favorSource and favorSource.entry.kind=="favor" and favorSource.entry.favorCost==45
            and favorSource.note:find("45",1,true), "plan item links to its recorded Merchant's Favor source and cost")
        enc:OpenEntry(itemEntry)
        local favorButton
        for _,b in ipairs(enc.window.relatedButtons) do if b.sourceKind=="Merchant's Favor" then favorButton=b end end
        if not favorButton and enc.window.linksNext:IsShown() then enc.window.linksNext:Click();for _,b in ipairs(enc.window.relatedButtons) do if b.sourceKind=="Merchant's Favor" then favorButton=b end end end
        check(favorButton and favorButton.icon:IsShown() and favorButton.icon._texture:find("Coin_01",1,true), "Merchant's Favor source uses the coin icon")
        if favorButton then favorButton:Click() end
        check(enc.current==favorSource.entry and enc.profView=="favor", "Merchant's Favor source opens its profession entry")
        enc:Back();enc:Back()
    end
    local bossLink
    for _, b in ipairs(enc.window.recipePane.related) do if b.entry == bossEntry then bossLink = b end end
    if not bossLink then enc.window.recipePane.more:Click(); for _, b in ipairs(enc.window.recipePane.related) do if b.entry == bossEntry then bossLink = b end end end
    if bossLink then bossLink:Click() end
    check(enc.current == bossEntry and enc.selected == "Dungeons", "related link navigates to its boss")
    enc:Back()
    check(enc.current.kind == "recipe", "back returns to the recipe")
    local hasSet, hasQuest, hasBoss, hasRecipe = false, false, false, false
    for _, entry in ipairs(itemEntry.links) do
        hasSet = hasSet or entry.kind == "set"; hasQuest = hasQuest or entry.kind == "quest"
        hasBoss = hasBoss or entry.kind == "boss"; hasRecipe = hasRecipe or entry.kind == "recipe"
    end
    check(hasSet and hasQuest and hasBoss and hasRecipe, "item IDs connect sets, quests, bosses and recipes in both directions")
    ns.IndependentReference = MOCK.independentReference
    enc.gearLoaded = false; enc:LoadGearIndex()
    check(enc.gearLoaded and #ns.IndependentReference.GearIndex() > 1000, "standalone gear index is used even while OneForAll is installed")
    OneForAll = nil; enc:RefreshData(); enc:Render()
    do
        local plan=enc.byKey["item:251354"];local reported
        for _,src in ipairs(plan and plan.data.sourceLinks or {}) do if src.kind=="Merchant's Favor" then reported=src end end
        check(reported and reported.note:find("Player-reported",1,true) and reported.entry.favorCost==nil,
            "Crusader's Chain Helm favor report stays distinct and has no invented cost")
        M.testFavorVendors = function()
        local checked, linked, missing = 0, 0, 0
        for profession, rows in pairs(ns.IndependentReference.PROFESSION_RECIPES or {}) do
            for _, recipe in ipairs(rows) do
                local item = recipe.ri and enc.byKey["item:"..recipe.ri]
                local favor
                for _, source in ipairs(item and item.data.sourceLinks or {}) do if source.kind=="Merchant's Favor" then favor=source end end
                if favor and favor.favorCost ~= nil then
                    checked=checked+1
                    for _, vendor in ipairs(recipe.src and recipe.src.v or {}) do
                        local found
                        for _, source in ipairs(item.data.sourceLinks or {}) do
                            if source.kind=="Vendor" and source.entry.data.id==vendor[1] and source.favorCost==favor.favorCost then found=source end
                        end
                        if found then linked=linked+1 else missing=missing+1 end
                    end
                end
            end
        end
        check(checked >= 300 and linked >= 600 and missing==0, "all recorded Favor recipe vendors link by NPC ID with their recorded cost")
        for _, itemID in ipairs({249534,249536,249529,249530,249532}) do
            local item=enc.byKey["item:"..itemID];local horde,alliance,favor
            for _, source in ipairs(item and item.data.sourceLinks or {}) do
                if source.kind=="Merchant's Favor" then favor=source end
                if source.kind=="Vendor" and source.entry.data.id==248199 then horde=source end
                if source.kind=="Vendor" and source.entry.data.id==256732 then alliance=source end
            end
            check(favor and favor.favorCost==240 and horde and horde.favorCost==240 and alliance and alliance.favorCost==240,
                "researched enchanting formula "..itemID.." links both vendors at 240 Favor")
        end
        for itemID,expected in pairs({[250998]=180,[285289]=30,[285290]=60,[285291]=90,[251426]=90,[289560]=180}) do
            local item=enc.byKey["item:"..itemID];local favor, vendors=nil,0
            for _, source in ipairs(item and item.data.sourceLinks or {}) do
                if source.kind=="Merchant's Favor" then favor=source end
                if source.kind=="Vendor" and source.favorCost==expected then vendors=vendors+1 end
            end
            check(favor and favor.favorCost==expected and vendors>=2, "audited recipe "..itemID.." has price and both vendors")
        end
        for id, ref in pairs(ns.FavorVendors) do
            local npc=enc.byKey["npc:"..id];local loc=enc.QuestPage.NpcLocation(npc)
            check(npc and npc.name==ref[2] and loc and loc.mapID==ref[4] and loc.x==ref[5] and loc.y==ref[6],
                "Favor vendor "..ref[2].." uses the audited map location")
        end
        for _,itemID in ipairs({264221,264222,250996}) do
            local item=enc.byKey["item:"..itemID];local caution
            for _, source in ipairs(item and item.data.sourceLinks or {}) do
                if source.kind=="Merchant's Favor" then caution=source end
            end
            check(caution and caution.uncertain and caution.note:find("not seen",1,true),
                "disputed vendor stock is labelled for "..itemID)
        end
        local uncertain=enc.byKey["item:264221"];enc:OpenEntry(uncertain)
        local warning;for _,row in ipairs(enc.window.relatedButtons) do if row.sourceUncertain and row.text:GetText():find("Unconfirmed",1,true) then warning=true end end
        check(warning, "uncertain vendor stock is visible on the item page")
        local source;for _,row in ipairs(uncertain.data.sourceLinks or {}) do if row.kind=="Merchant's Favor" then source=row end end
        if source then enc:OpenEntry(source.entry) end
        check(enc.window.recipePane.info:GetText():find("Not seen at Favor vendors; other sources unknown",1,true),
            "recipe detail distinguishes missing vendor stock from unavailable everywhere")
        enc:Back();enc:Back()
        local beneris,alynsia=enc.byKey["npc:248199"],enc.byKey["npc:256732"]
        local hordeLoc=enc.QuestPage.NpcLocation(beneris);local allyLoc=enc.QuestPage.NpcLocation(alynsia)
        check(hordeLoc and hordeLoc.mapID==1413 and hordeLoc.x==49.68 and hordeLoc.y==29.8
            and allyLoc and allyLoc.mapID==1433 and allyLoc.x==11.21 and allyLoc.y==71.5,
            "enchanting Favor vendors use corrected recorded map coordinates")
        local example=enc.byKey["item:251369"]
        enc:OpenEntry(example)
        local horde,alliance,costRow
        for _, row in ipairs(enc.window.relatedButtons) do
            if row.sourceKind=="Vendor" and row.sourceFaction=="Horde" then horde=row end
            if row.sourceKind=="Vendor" and row.sourceFaction=="Alliance" then alliance=row end
            if row.sourceKind=="Merchant's Favor" then costRow=row end
        end
        check(horde and alliance and horde.text:GetText():find("30 Favor",1,true) and alliance.text:GetText():find("30 Favor",1,true)
            and costRow and costRow.text:GetText():find("30 Favor",1,true), "plan sources show vendor faction and Favor price")
        if horde then horde:Click() end
        check(enc.current and enc.current.kind=="npc" and enc.current.data.id==248197
            and enc.QuestPage.NpcLocation(enc.current), "clicking a Favor vendor opens its NPC page with its recorded location")
        enc:Back();enc:Back()
        end
        M.testFavorVendors(); M.testFavorVendors = nil
        local hammer = enc.byKey["item:17182"]
        local eye, base = false, false
        for _, related in ipairs(hammer and hammer.links or {}) do
            if related.key == "item:17204" then eye = true elseif related.key == "item:17193" then base = true end
        end
        check(hammer and enc.ItemSourceLabel(hammer) == "Combined" and hammer.data.sourceSummary:find("Eye of Sulfuras", 1, true) and eye and base,
            "Sulfuras records its combination source and links both components without OneForAll")
        check(enc.ItemSourceLabel({data={sourceTypes="crafted,drop"}}) == "Crafted / Drop" and enc.ItemSourceLabel({data={}}) == "Source unknown",
            "source labels distinguish known acquisition types from unknown")
    end
    local localItem = enc.byKey["item:277203"]
    local localQuest = enc.byKey["quest:wowhead:78150"]
    check(enc.sourceAvailable and not enc.legacyAvailable and localItem and localQuest,
        "curated Wowhead records remain available without OneForAll")
    check(localItem and localItem.data.reference and localItem.data.reference.itemLevel == 23 and localItem.links[1] == localQuest,
        "Wowhead items retain their provenance and linked quest without OneForAll")
    check(localQuest.data.rewardKeys and localQuest.data.rewardKeys[localItem.key], "quest reward records retain their reward items")
    M.testQuestStartLocation = function()
        local oldQuestDB, oldNpcDB, oldLoader = QuestDB, NpcDB, QuestieLoader
        QuestDB = { startedBy = function() return { { 42 }, nil, nil } end }
        NpcDB = { spawns = function() return { [14] = { { 43.5, 67.2 } } } end }
        QuestieLoader = { ImportModule = function() return { GetUiMapIdByAreaId = function(_, area) if area == 14 then return 1411 end end } end }
        local loc = enc.QuestStartLocation({data={id=123}})
        check(loc and loc.npcID == 42 and loc.mapID == 1411 and loc.x == 43.5 and loc.y == 67.2, "quest start uses the Questie NPC's mapped spawn")
        QuestDB.startedBy = function() return { nil, nil, { 55 } } end
        check(not enc.QuestStartLocation({data={id=123}}), "item-start quests do not invent an NPC waypoint")
        QuestDB, NpcDB, QuestieLoader = oldQuestDB, oldNpcDB, oldLoader
    end
    M.testQuestStartLocation(); M.testQuestStartLocation = nil
    check(localItem and enc.Details(localItem):find("Wowhead Forever", 1, true), "item details identify the reference source")
    check(enc.byKey["quest:wowhead:82208"] and enc.byKey["item:277254"] and enc.byKey["item:277258"] and enc.byKey["item:277260"], "third library quest and its three rewards are bundled")
    check(enc.byKey["item:277254"].data.reference.requiredLevel == 40 and enc.byKey["quest:wowhead:82208"].data.required == 35, "item and quest level requirements stay distinct")
    check(enc.byKey["quest:wowhead:84394"] and enc.byKey["npc:5497"] and enc.byKey["npc:7825"] and enc.byKey["item:281637"] and enc.byKey["item:281636"] and enc.byKey["item:277202"], "fourth library tier includes its NPCs and rewards")
    check(enc.Details(enc.byKey["item:281636"]):find("unconfirmed", 1, true), "uncertain reward association is disclosed")
    check(enc.Details(enc.byKey["item:285331"]):find("10 drops in 12 kills", 1, true), "drop sample is identified as uncertain")
    local npc = enc.byKey["npc:211022"]
    local quest2 = enc.byKey["quest:wowhead:79536"]
    local ring = enc.byKey["item:281634"]
    local function containsLink(a, b)
        for _, linked in ipairs(a and a.links or {}) do if linked == b then return true end end
        return false
    end
    check(containsLink(enc.byKey["npc:5828"], enc.byKey["item:285331"]), "curated rare NPC links to its drop without OneForAll")
    check(ns.NpcReferenceData and #ns.NpcReferenceData.npcs >= 10000 and enc.byKey["npc:3"] and enc.byKey["npc:3"].data.npcReference,
        "standalone NPC index imports the attributed Everlook and Classic reference snapshots")
    check(enc.byKey["npc:3"].data.type == "Undead", "NPC entries retain their recorded creature type for role icons")
    M.testNPCPortraits = function()
        check(enc.IsHiddenNPC("Searing Totem",{type="Totem"}) and enc.IsHiddenNPC("Odd Totem",{type="Not specified"})
            and enc.IsHiddenNPC("PvP A-Mid Credit Marker",{}) and enc.IsHiddenNPC("<TXT>Crown Guard Capture Quest Doodad",{})
            and enc.IsHiddenNPC("Silithus Dust Turnin Quest Doodad Horde",{}) and enc.IsHiddenNPC("Blackwing Spell Marker",{})
            and enc.IsHiddenNPC("Invisible Stalker",{}) and enc.IsHiddenNPC("Generic Bunny",{}) and enc.IsHiddenNPC("Ouro Spawner",{})
            and not enc.IsHiddenNPC("Target Dummy",{type="Mechanical"}) and not enc.IsHiddenNPC("Grethok the Controller",{type="Humanoid"})
            and not enc.IsHiddenNPC("Zzarc' Vul",{type="Humanoid"})
            and not enc.IsHiddenNPC("Harken Windtotem",{type="Humanoid"}) and not enc.IsHiddenNPC("Gnarlpine Totemic",{type="Humanoid"}), "totem objects and internal markers are excluded without hiding NPC names containing Totem")
        check(not enc.byKey["npc:15001"] and not enc.byKey["npc:17689"] and not enc.byKey["npc:13916"], "internal NPC markers and classified totems are excluded at import")
        enc:LoadGearIndex()
        check(#enc:Find("All", "Ring of Critical Testing")==0 and #enc:Find("All", "TestBoots - Puffed Mail Green")==0
            and #enc:Find("All", "PvP A-Mid Credit Marker")==0 and #enc:Find("All", "<TXT>Crown Guard Capture Quest Doodad")==0, "internal test items and markers are absent from global search")
        check(#enc:Find("All", "Hidden Boots (DNT)")==0 and #enc:Find("All", "NOT USED")==0
            and #enc:Find("All", "Invisible Stalker")==0 and #enc:Find("All", "Campfire Marker")==0, "additional internal item and NPC helpers are absent from global search")
        check(#enc:Find("All", "Ribbon Pole Debug Target")==0 and #enc:Find("All", "Unused Scraping Vial")>0
            and #enc:Find("All", "Stormwind Armor Marker")>0, "debug helpers are hidden without removing real quest items")
        local hiddenNPCs, hiddenItems = 0, 0
        for _, entry in ipairs(enc.entries) do
            if entry.kind == "npc" and enc.IsHiddenNPC(entry.name, entry.data) then hiddenNPCs = hiddenNPCs + 1 end
            if entry.kind == "item" and enc.IsTestName(entry.name) then hiddenItems = hiddenItems + 1 end
        end
        check(hiddenNPCs == 0 and hiddenItems == 0, "all loaded NPCs and items are free of the identified internal entries")
        check(enc.NpcTypeIcon({type="Beast", family="Wolf"}):find("npc%-type%-beast") and enc.NpcTypeIcon({type="Beast", family="Bear"}):find("npc%-type%-beast"), "creatures of one type share its icon")
        check(enc.NpcTypeIcon({type="Undead"}):find("npc%-type%-undead") and enc.NpcTypeIcon({type="HUMANOID"}):find("npc%-type%-humanoid"), "NPC type icons are case insensitive")
        check(enc.NpcTypeIcon({type="Non-combat Pet"}):find("npc%-type%-pet") and enc.NpcTypeIcon({}):find("npc%-type%-unknown"), "pets and unknown creature types have appropriate icons")
        local roles=enc.NpcRoles({vendor=true,trainer=true,questGiver=true})
        check(roles.vendor and roles.trainer and roles.quest, "NPC service badges can all be shown together")
        roles=enc.NpcRoles({title="Alchemy Trainer"});check(roles.trainer and not roles.vendor and not roles.quest, "trainer titles provide a role without guessing other services")
        local oldSelected, oldQuery, oldCurrent, oldOffset = enc.selected, enc.query, enc.current, enc.offset
        local record=enc.byKey["npc:3"].data
        local oldVendor, oldTrainer, oldQuest, oldTitle=record.vendor,record.trainer,record.questGiver,record.title
        record.vendor,record.trainer,record.questGiver,record.title=true,true,true,""
        enc.selected,enc.query,enc.current,enc.offset="NPCs","Flesh Eater",nil,0
        enc.directoryFilters=enc.directoryFilters or {};enc.directoryFilters.NPCs={kind="all"};enc:Render()
        local selectedRow;for _,row in ipairs(enc.window.rows) do if row.entry==enc.byKey["npc:3"] then selectedRow=row end end
        check(selectedRow and selectedRow.portraitBorder:IsShown() and selectedRow.npcBadges.vendor:IsShown() and selectedRow.npcBadges.trainer:IsShown() and selectedRow.npcBadges.quest:IsShown(), "NPC directory renders the gold portrait frame and all recorded service badges")
        check(selectedRow.npcBadges.vendor:GetWidth()==23 and selectedRow.npcBadges.vendor.icon._texture:find("npc%-role%-vendor")
            and selectedRow.npcBadges.trainer.icon._texture:find("npc%-role%-trainer")
            and selectedRow.npcBadges.quest.icon._texture:find("npc%-role%-quest"), "larger badges use the dedicated vendor, trainer and quest icons")
        check(selectedRow.icon._texture:find("npc%-type%-undead"), "NPC directory displays its generic type icon rather than a portrait")
        record.vendor,record.trainer,record.questGiver=false,false,false;enc:Render()
        do -- scrolling the "Dungeon bosses" list doesn't re-check every NPC per row
            local savedQuery=enc.query;enc.query="";enc.directoryFilters.NPCs={kind="boss"};enc:Render()
            local checks,matches=0,enc.DirectoryMatches
            enc.DirectoryMatches=function(...) checks=checks+1;return matches(...) end
            enc.offset=1;enc:Render();enc.offset=0;enc:Render()
            enc.DirectoryMatches=matches
            check(checks==0,"the NPC dungeon-boss list is filtered once, not on every scroll step")
            enc.directoryFilters.NPCs={kind="vendor"};enc:Render()
            local vendors=true;for _,row in ipairs(enc.window.rows) do if row:IsShown() and row.entry and not enc:DirectoryMatches(row.entry) then vendors=false end end
            check(vendors,"changing the NPC filter still filters again")
            enc.directoryFilters.NPCs={kind="all"};enc.query=savedQuery;enc:Render()
        end
        check(not selectedRow.npcBadges.vendor:IsShown() and not selectedRow.npcBadges.trainer:IsShown() and not selectedRow.npcBadges.quest:IsShown(), "reused rows clear badges for NPCs without those services")
        record.vendor,record.trainer,record.questGiver,record.title=oldVendor,oldTrainer,oldQuest,oldTitle
        enc.selected,enc.query,enc.current,enc.offset=oldSelected,oldQuery,oldCurrent,oldOffset;enc:Render()
    end
    M.testNPCPortraits(); M.testNPCPortraits=nil
    check(ns.IndependentReference.GearValue and ns.IndependentReference.SkillUp and #ns.IndependentReference.GearIndex() > 1000, "standalone gear and profession engines have indexed data")
    check(enc.independentAvailable and #enc:Find("Dungeons", "Wailing Caverns") > 0 and #enc:Find("Pets", "Bat") > 0 and #enc:Find("Professions", "Elixir of Minor Defense") > 0 and #enc:Find("Reputations", "Argent Dawn") > 0 and #enc:Find("Library Books", "Dalaran Digest") > 0, "dungeons, pets, recipes, reputation and books work without OneForAll")
    check(enc.byKey["dungeon:wc"] and enc.DungeonArt(enc.byKey["dungeon:wc"].data, 70, 32) == 131882, "standalone dungeons retain game loading-screen art")
    M.testLordaeron = function()
        local oldFaction, oldClass = UnitFactionGroup, UnitClass
        UnitFactionGroup = function() return "Horde" end
        UnitClass = function() return "Paladin", "PALADIN" end
        local instance = enc.byKey["dungeon:lordaeron"]
        local guide = ns.InstanceGuide
        guide.chainCache = {}; guide.chainOpen = {}
        local chainCount, stepCount = 0, 0
        for _, row in ipairs(guide:QuestRows(instance.data)) do
            if row.quest.name == "Unending Torment" then
                chainCount = chainCount + 1
                if row.chain then stepCount = #row.chain end
            end
        end
        check(chainCount == 1 and stepCount == 5, "Ruins of Lordaeron's five Unending Torment steps form one recorded chain")
        enc:OpenEntry(instance); enc.window.dungeonTabs.Quests:Click()
        local seen, duplicate, root, rootCount = {}, false, nil, 0
        for _, row in ipairs(enc.window.dungeonList.rows) do
            if row:IsShown() and row.entry then
                local id = tonumber(row.entry.data.id)
                if id and seen[id] then duplicate = true end
                if id then seen[id] = true end
                if row.entry.name == "Unending Torment" then root, rootCount = row, rootCount + 1 end
            end
        end
        check(not duplicate and rootCount == 1 and root.text:GetText():find("Chain (5)", 1, true),
            "encyclopedia dungeon list deduplicates source links and identifies the single quest chain")
        local originalStatus, originalPresentation, originalColor = enc.QuestPage.Status, enc.QuestPage.Presentation, root.text.SetTextColor
        root.text.SetTextColor = function(self, r, g, b) self.testColor = {r,g,b} end
        for _, state in ipairs({{"Completed","5ee879"},{"In progress","ffd15a"},{"Not recorded","ff6969"},{"Unknown","a9a9a9"}}) do
            enc.QuestPage.Status = function() return state[1] end
            enc.QuestPage.Presentation = function() return state[1], state[2] end
            enc:Render()
            check(math.abs(root.text.testColor[1] - tonumber(state[2]:sub(1,2),16)/255) < .001,
                "dungeon quest color follows " .. state[1])
        end
        root.text.SetTextColor, enc.QuestPage.Status, enc.QuestPage.Presentation = originalColor, originalStatus, originalPresentation
        enc:Render()
        if root then root:Click() end
        check(guide.frame:IsShown() and guide.dungeon == instance.data and guide.entry.id == 97288
            and guide.chainOpen[97288], "quest chain opens the correct dungeon and expanded chain in Instance Guide")
        guide.frame:Hide(); enc.window:Show(); enc:Back()
        UnitFactionGroup, UnitClass = oldFaction, oldClass
        guide.chainCache = {}
    end
    M.testLordaeron(); M.testLordaeron = nil
    check(enc.DropInfo({name = "Wailing Caverns"}, {name = "Lord Serpentis"}, 6469) == 17, "standalone boss drops retain reference rates")
    check(enc.byKey["item:60"] and enc.byKey["quest:bulk:6"] and containsLink(enc.byKey["item:60"], enc.byKey["quest:bulk:6"]), "bulk quest reward remains linked without OneForAll")
    check(npc and quest2 and ring and containsLink(npc, localQuest) and containsLink(localQuest, npc)
        and containsLink(npc, quest2) and containsLink(quest2, ring) and containsLink(ring, quest2),
        "NPCs, quests and reward items link in both directions by ID")
    check(#enc:Find("NPCs", "Undercity") >= 2 and #enc:Find("Quests", "Friend of the Library") >= 4,
        "NPC zone search and similarly named quests work without OneForAll")
    enc.window.tabs.Quests:Click(); check(enc.selected == "Quests", "quest tab opens")
    do
        local controls = enc.window.directoryFilters
        check(enc.QuestPage.frame:IsShown() and not controls:IsShown(), "quests use the dedicated category, list and detail layout")
        local classQuest = { name = "Trial", data = { level = 16, classes = "Druid", repeatable = false }, links = {} }
        local repeatQuest = { name = "Gather again", data = { level = 20, repeatable = true }, links = {} }
        controls.kind:Click()
        check(enc:DirectoryMatches(classQuest) and not enc:DirectoryMatches(repeatQuest), "class filter uses recorded class restrictions")
        controls.kind:Click()
        controls.kind:Click()
        check(enc:DirectoryMatches({ name = "Attunement to the Core", data = { level = 60 }, links = {} }), "attunement name filter identifies matching titles")
        controls.clear:Click(); controls.min:SetText("10"); controls.min._scripts.OnTextChanged(controls.min); controls.max:SetText("18"); controls.max._scripts.OnTextChanged(controls.max)
        check(enc:DirectoryMatches(classQuest) and not enc:DirectoryMatches(repeatQuest) and not enc:DirectoryMatches({ name = "Unknown", data = {}, links = {} }), "level filter excludes out-of-range and unknown levels")
        enc.window.tabs.NPCs:Click()
        check(controls.kind.text:GetText() == "All NPCs" and controls.min:GetText() == "", "NPC filters are separate from quest filters")
        controls.kind:Click()
        check(enc:DirectoryMatches({ name = "Vendor", data = { vendor = true }, links = {} }) and not enc:DirectoryMatches({ name = "Unknown", data = {}, links = {} }), "vendor filter uses recorded vendor data")
        controls.kind:Click()
        check(enc:DirectoryMatches({ name = "Trainer", data = { title = "Mage Trainer" }, links = {} }), "trainer filter uses recorded titles")
        controls.kind:Click()
        check(enc:DirectoryMatches({ name = "Quest giver", data = { questGiver = true }, links = {} }), "quest giver filter uses recorded starters")
        enc.window.tabs.Quests:Click(); controls.clear:Click()
    end
    check(enc.QuestPage.frame:IsShown() and not enc.window.list:IsShown() and not enc.window.detail:IsShown(), "quest directory replaces the old flat layout")
    check(select(1, enc.window.list.scrollbar:GetPoint()) == "TOPLEFT" and select(2, enc.window.list.scrollbar:GetPoint()) == enc.window.list and select(3, enc.window.list.scrollbar:GetPoint()) == "TOPRIGHT", "shared scrollbar sits outside the list")
    enc.window.list.scrollbar.SetValue = function(self, value) self.testValue = value end
    ns.UpdateListScrollbar(enc.window.list.scrollbar, 0, 5)
    check(enc.window.list.scrollbar.testValue == 0, "scrollbars start at the top")
    check(enc.window.list.scrollbar.fuiPanel and #enc.window.list.scrollbar.fuiPanel.lines == 4, "shared scrollbar has a themed border")
    check(enc.window.closeButton and enc.window.closeButton:GetScript("OnClick") and not enc.window.closeButton.text, "encyclopedia uses a native close button")
    enc.globalQuery = "Owen Thadd"; enc:RenderGlobalSearch()
    check(enc.window.globalSearch:IsShown() and enc.window.globalResults.rows[1].entry == npc, "global search finds an NPC from the quest tab")
    enc.window.tabs.NPCs:Click(); enc:RenderGlobalSearch()
    check(enc.window.globalSearch:IsShown() and enc.window.globalResults.rows[1].entry == npc, "global search remains available across tabs")
    enc.globalQuery = ""; enc:RenderGlobalSearch(); enc.window.tabs.Quests:Click()
    enc:OpenEntry(localQuest); enc:OpenEntry(npc); check(enc.selected == "NPCs" and enc.current == npc, "related NPC opens in its tab")
    enc:Back(); check(enc.selected == "Quests" and enc.current == localQuest, "back returns to the linked quest")
    check(enc.window.relatedTitle:GetText() == "REWARDS & RELATED" and enc.window.relatedButtons[1].text:GetText():find("Reward", 1, true), "quest details label linked items as rewards")
    check(enc.window.questMap:IsShown(), "quest details expose the start map action")
    M.testReagentAndScroll = function()
        local material
        for _, entry in ipairs(enc.entries) do if entry.kind == "item" and entry.data.usedIn and #entry.data.usedIn > 0 then material = entry; break end end
        check(material ~= nil, "reagent uses are indexed")
        if material then
            enc:OpenEntry(material)
            check(enc.window.itemSourcesTab:IsShown() and enc.window.itemUsedTab:IsShown(), "reagent sources and uses have separate tabs")
            enc.window.itemUsedTab:Click()
            check(enc.window.relatedButtons[1].entry and enc.window.relatedButtons[1].entry.kind == "recipe", "used-in tab shows linked recipes")
        end
        enc.window.tabs.Items:Click(); enc.offset = 20; enc:Render()
        local scrolled = enc.window.rows[1].entry
        if scrolled then enc.window.rows[1]:Click(); check(enc.offset == 20, "opening an item keeps its list scroll position"); enc:Back(); check(enc.offset == 20, "back restores a scrolled list position") end
        enc.window.tabs.Quests:Click(); enc.offset = 15; enc:Render()
        local chosen = enc.window.rows[1].entry
        if chosen then enc.window.rows[1]:Click(); check(enc.offset == 15, "opening a quest preserves the quest list position"); enc:Back(); check(enc.offset == 15, "back restores the quest list position") end
    end
    M.testReagentAndScroll(); M.testReagentAndScroll = nil

    enc.selected = "Armory"; enc.armorFilter = "planner"; enc.plannerMode = "suggested"; enc.plannerSlot = nil; enc.plannerEnchant = nil
    enc.query = "Scholarly Pendant"; enc.plannerOffset = 0; enc.plannerCache, enc.plannerShown = nil, nil; enc:Render()
    check(enc.window.planner.rows[1].entry == localItem, "curated items can be found in armory search without OneForAll")
    M.testItemCatalog = function()
        local sample = { kind = "item", category = "Armory", key = "item:990876", name = "Sample Copper Bundle",
            data = { id = 990876, slot = "Non-equippable", itemClass = "Trade Goods", quality = 1, sourceTypes = "vendor", reference = { itemLevel = 1, requiredLevel = 0 } }, links = {} }
        local duplicate = { kind = "item", category = "Armory", key = "item:990877", name = sample.name,
            data = { id = 990877, slot = "Non-equippable", itemClass = "Trade Goods", quality = 1, sourceTypes = "vendor", reference = { itemLevel = 1, requiredLevel = 0 } }, links = {} }
        enc.entries[#enc.entries+1] = sample; enc.entries[#enc.entries+1] = duplicate; enc.byKey[sample.key] = sample; enc.byKey[duplicate.key] = duplicate
        enc.entryRevision = (enc.entryRevision or 0) + 1
        enc.window.tabs.Items:Click(); enc.query = "Sample Copper Bundle"; enc:Render()
        check(enc.window.itemTabs["Trade Goods"]:IsShown() and enc.window.rows[1].entry == sample and not enc.window.rows[2]:IsShown(),
            "Items shows non-equippable items in the catalogue and collapses matching duplicates")
        check(enc.window.rows[1].sub:GetText():find("Vendor", 1, true), "item list displays the recorded acquisition type")
        local before = #M.dressed
        M.ctrl = true; enc.window.rows[1]:Click("LeftButton"); M.ctrl = false
        check(#M.dressed == before + 1 and M.dressed[#M.dressed] == "item:990876" and enc.current ~= sample,
            "control-left-click previews an item without opening its page")
        sample.data.sourceLinks = { { entry = npc, kind = "Vendor" }, { entry = localQuest, kind = "Quest" } }
        sample.links = { npc, localQuest }
        enc.window.rows[1]:Click()
        check(enc.selected == "Items" and enc.current == sample and not enc.window.itemWish:IsShown(), "item details stay in Items and do not offer a gear wishlist for materials")
        M.ctrl = true; enc.window.itemPreviewHeader:Click("LeftButton"); M.ctrl = false
        check(M.dressed[#M.dressed] == "item:990876" and enc.current == sample, "control-left-click on an item header previews it")
        check(enc.window.relatedButtons[1].entry == npc and enc.window.relatedButtons[1].text:GetText():find("Vendor", 1, true)
            and enc.window.relatedButtons[2].entry == localQuest and enc.window.relatedButtons[2].text:GetText():find("Quest", 1, true),
            "item sources are separate clickable vendor and quest rows")
        enc.window.relatedButtons[1]:Click(); check(enc.current == npc, "clicking an item source opens the linked NPC")
        enc:Back(); enc.window.relatedButtons[2]:Click(); check(enc.current == localQuest, "clicking an item source opens the linked quest")
        enc:Back()
        enc.window.itemTabs["Weapon"]:Click(); check(not enc.window.rows[1]:IsShown(), "item categories narrow the catalogue")
        enc.window.itemTabs["Trade Goods"]:Click(); check(enc.window.rows[1].entry == sample, "the trade goods category finds its matching item")
        enc.window.itemQuality:Click(); enc.window.itemQuality:Click()
        check(enc.itemQuality == 1 and enc.window.rows[1].entry == sample, "item catalogue filters by quality")
        enc.itemQuality = nil; enc.itemGroup = "all"; enc.itemKnownSources = nil
        enc.byKey[sample.key], enc.byKey[duplicate.key] = nil, nil
        for i = #enc.entries, 1, -1 do if enc.entries[i] == sample or enc.entries[i] == duplicate then table.remove(enc.entries, i) end end
        enc.entryRevision = enc.entryRevision + 1
    end
    M.testItemCatalog(); M.testItemCatalog = nil
    M.testQuestDirectory = function()
        local page, quest = enc.QuestPage, enc.questByID[6]
        local savedDB, savedLog, savedText, savedLevel = QuestDB, C_QuestLog, GetQuestLogQuestText, UnitLevel
        local discovery=enc.questByID[97198];local special=enc.questByID[78150];local oldQuest=enc.questByID[9321]
        check(discovery and discovery.data.zone=="Blackmaw Hold" and discovery.data.starts=="Muln Earthfury" and discovery.data.location.mapID==1412 and discovery.data.level==59, "research fills missing dungeon category, giver and checked start location")
        check(special and special.data.zone=="Special" and page.Matches(special,"other",nil,{},""), "special quests remain outside the zone list")
        check(oldQuest and oldQuest.data.zone=="Ironforge" and oldQuest.data.discovery.zoneNote, "a multi-location Classic quest is marked as one recorded start area")
        check(not page.Matches(discovery,"zone",nil,{},"") and page.Matches(discovery,"dungeon",nil,{},"","dungeon:blackmaw"), "researched dungeon quests appear under their dungeon")
        local uncategorised=0;for _,row in ipairs(enc.entries) do if page.Matches(row,"zone",nil,{},"") and not (row.data.zone and row.data.zone~="") then uncategorised=uncategorised+1 end end
        check(uncategorised==0, "all previously unknown zone records have a reference category")
        check(quest and quest.data.classic and quest.data.classic.objectives and quest.data.classic.rewards, "classic quest objectives and reward choices are available as reference data")
        C_QuestLog = {
            GetLogIndexForQuestID = function(id) if id == 6 then return 1 end end,
            IsQuestFlaggedCompleted = function(id) return id == 2 end,
            GetQuestObjectives = function(id) if id == 6 then return {{text="Live objective 1/2",finished=false}} end end,
        }
        QuestDB=nil;page.showSources=true;page.statusCache={}
        local researched={};for _,line in ipairs(page.Details(discovery)) do researched[#researched+1]=line.text or line.heading or "" end
        local researchedText=table.concat(researched,"\n");local researchedMap=enc.QuestStartLocation(discovery)
        check(researchedText:find("Retrieve a Blackmaw Ritual Totem",1,true) and researchedText:find("Muln Earthfury",1,true) and researchedText:find("Reputation: Earthen Ring",1,true) and researchedText:find("EverlookDB",1,true) and researchedMap and researchedMap.mapID==1412, "researched quest details and source attribution work without Questie")
        local disputed=enc.questByID[95204];local notes={};for _,line in ipairs(page.Details(disputed)) do notes[#notes+1]=line.text or line.heading or "" end
        check(table.concat(notes,"\n"):find("Minimum level: Everlook 15; older Questie snapshot 16",1,true), "conflicting reference minimum levels remain visible")
        QuestDB = {
            questLevel = function(id) if id == 6 then return 8 end end,
            requiredLevel = function(id) if id == 6 then return 3 end end,
            objectivesText = function() return {"Questie reference objective"} end,
            startedBy = function() return {{5828}} end,
            preQuestSingle = function() return {2} end,
            nextQuestInChain = function() return 7 end,
            reputationReward = function() return {{21,250}} end,
        }
        local factionName=page.FactionName(72)
        check(factionName=="Stormwind", "unlisted faction 72 resolves to Stormwind")
        local oldRep=C_Reputation
        C_Reputation={GetFactionDataByID=function(id) if id==123456 then return {name="Example Faction"} end end}
        check(page.FactionName(123456)=="Example Faction", "quest reputation uses the game client faction name when available")
        C_Reputation=oldRep
        local oldRepReward=QuestDB.reputationReward
        QuestDB.reputationReward=function() return {{72,100}} end
        local repLines={};for _,row in ipairs(page.Details(quest)) do repLines[#repLines+1]=row.text or "" end
        check(table.concat(repLines,"\n"):find("Reputation: Stormwind +100",1,true), "quest reward displays the faction name instead of faction 72")
        QuestDB.reputationReward=oldRepReward
        page.statusCache={}
        check(page.Status(quest)=="In progress" and page.Status(enc.questByID[2])=="Completed", "quest status uses the current quest log")
        page.showSources=true
        local details=page.Details(quest);local lines={};for _,row in ipairs(details) do lines[#lines+1]=row.text or row.heading or "" end;local text=table.concat(lines,"\n")
        local starter;for _,row in ipairs(details) do if row.target and row.target.key=="npc:5828" then starter=true end end
        check(text:find("Live objective 1/2",1,true) and text:find("Choose:",1,true) and text:find("Alternative prerequisite:",1,true) and text:find("Sources:",1,true) and text:find("QuestieDB",1,true) and text:find("Reputation:",1,true) and starter, "quest details combine live objectives, reward choices, NPCs, reputation, chains and grouped sources")
        page.showSources=false;details=page.Details(quest);lines={};for _,row in ipairs(details) do lines[#lines+1]=row.text or row.heading or "" end;text=table.concat(lines,"\n");check(not text:find("QuestieDB",1,true) and text:find("ABOUT THIS INFORMATION",1,true), "reference labels stay in a separate expandable section")
        GetQuestLogQuestText=function(index) if index==1 then return "Live quest story", "Bring the pick back." end end
        details=page.Details(quest);lines={};for _,row in ipairs(details) do lines[#lines+1]=row.text or row.heading or "" end;text=table.concat(lines,"\n");check(text:find("Live quest story",1,true) and text:find("Bring the pick back.",1,true), "active quest goal and description come from the live quest log")
        GetQuestLogQuestText=nil
        C_QuestLog.IsComplete=function(id) return id==6 end;page.statusCache={};check(page.Status(quest)=="Ready to turn in", "completed objectives are distinguished from turned-in quests")
        C_QuestLog.GetLogIndexForQuestID=function() return nil end;page.statusCache={};details=page.Details(quest);lines={};for _,row in ipairs(details) do lines[#lines+1]=row.text or row.heading or "" end;text=table.concat(lines,"\n")
        check(page.Status(quest)=="Not recorded" and text:find("Questie reference objective",1,true), "unknown quests use Questie objectives without inventing player progress")
        QuestDB=nil;page.statusCache={};page.showSources=true;details=page.Details(quest);lines={};for _,row in ipairs(details) do lines[#lines+1]=row.text or row.heading or "" end;check(table.concat(lines,"\n"):find("Classic reference",1,true), "quest page works without QuestieDB and labels fallback data")
        do
            local oldNpcDB,oldLoader=NpcDB,QuestieLoader;NpcDB=nil;QuestieLoader=nil;page.npcQuestIndex=nil
            local gornek=enc.byKey["npc:3143"]
            local location=page.NpcLocation(gornek)
            local starts,ends=page.NpcQuests(gornek)
            local foundStart,foundEnd=false,false
            for _,entry in ipairs(starts) do if entry.data.id==788 then foundStart=true end end
            for _,entry in ipairs(ends) do if entry.data.id==788 then foundEnd=true end end
            check(location and location.mapID==1411 and location.x==42.1 and location.y==68.3
                and foundStart and foundEnd, "standalone quest-pin import connects Gornek's location and both quest roles")
            local creature=enc.byKey["npc:3"];local creatureLoc=page.NpcLocation(creature)
            check(creatureLoc and creatureLoc.mapID==1431 and creatureLoc.x==25.06 and creatureLoc.provider=="QuestieDB base reference",
                "standalone QuestieDB snapshot supplies non-quest NPC positions")
            local guard=enc.byKey["npc:271866"];local guardStarts=page.NpcQuests(guard);local extra=false
            for _,entry in ipairs(guardStarts) do if entry.data.id==99267 then extra=true end end
            check(guard and extra, "standalone QuestieDB snapshot adds NPC quests missing from prior references")
            local abigail,magenius=enc.byKey["npc:2118"],enc.byKey["npc:3351"]
            local aStock,mStock=page.NpcSales(abigail),page.NpcSales(magenius)
            local function hasItem(list,id)
                for _,entry in ipairs(list) do if entry.data.id==id then return true end end
            end
            check(abigail and hasItem(aStock,12226) and hasItem(aStock,2901),
                "Abigail's shop contains her recorded Crispy Bat Wing recipe and mining pick")
            check(hasItem(aStock,277113) and hasItem(aStock,277114) and hasItem(aStock,277115) and hasItem(aStock,4536),
                "Abigail's recorded Forever stock includes the profession pouches and apple")
            check(magenius and hasItem(mStock,17031) and hasItem(mStock,17030),
                "Magenius's shop contains recorded teleportation runes and ankhs")
            local dropOnly={kind="item",key="item:drop-only",name="Drop only",data={sourceLinks={{kind="Drop",entry=magenius}}}}
            local oldLinks=magenius.links;magenius.links={dropOnly}
            check(#page.NpcSales(magenius)==0, "NPC drops are not presented as shop stock")
            magenius.links=oldLinks
            local prevCurrent,prevSelected=enc.current,enc.selected
            enc.current,enc.selected=abigail,"NPCs";enc:Render()
            local pane=page.npcPane
            check(pane and pane.tabs.sells:IsShown() and page.npcView=="sells"
                and pane.columns.starts.title:GetText():find("Sells",1,true) and pane.columns.starts.rows[1].entry,
                "a vendor without recorded quests opens a clickable stock list by default")
            local item=pane.columns.starts.rows[1].entry
            pane.columns.starts.rows[1]:Click()
            check(enc.current==item and enc.selected=="Items", "clicking vendor stock opens the item page")
            enc.current,enc.selected=abigail,"NPCs";enc:Render()
            pane.tabs.quests:Click()
            check(pane.columns.starts.empty:GetText()=="No quests recorded." and pane.columns.starts.empty:IsShown(),
                "quest-giver status does not invent undocumented quests")
            enc.current,enc.selected=prevCurrent,prevSelected;enc:Render()
            NpcDB,QuestieLoader=oldNpcDB,oldLoader;page.npcQuestIndex=nil
        end
        do
            local oldEntries,oldIndex,oldDB,oldNpcDB,oldLoader,oldCurrent,oldSelected,oldQuery=enc.entries,enc.questByID,QuestDB,NpcDB,QuestieLoader,enc.current,enc.selected,enc.query
            local savedRelations=ns.NpcQuestRelations;ns.NpcQuestRelations=nil
            local trainer,grelin=enc.byKey["npc:3967"],enc.byKey["npc:786"]
            check(trainer and page.NpcRoleIcon(trainer.data):find("ArmorKit",1,true), "leatherworking trainer uses the leatherworking icon")
            local a={kind="quest",category="Quests",key="quest:test-npc-a",name="Starts here",data={id=99101,level=8},links={}}
            local b={kind="quest",category="Quests",key="quest:test-npc-b",name="Ends here",data={id=99102,level=9,starts="Grelin Whitebeard",turnin="Aayndia Floralwind"},links={}}
            local c={kind="quest",category="Quests",key="quest:test-npc-c",name="Discovery quest",data={id=99103,level=10,discovery={giverID=3967,turninID=3967}},links={}}
            local d={kind="quest",category="Quests",key="quest:test-npc-d",name="Item starts quest",data={id=99104,starts="Aayndia Floralwind"},links={}}
            enc.entries={trainer,grelin,a,b,c,d};enc.questByID={[99101]=a,[99102]=b,[99103]=c,[99104]=d}
            QuestDB={startedBy=function(id) if id==99101 then return {{3967}} elseif id==99104 then return {nil,nil,{55}} end end,
                finishedBy=function(id) if id==99101 then return {{786}} end end}
            local starts,turnins=page.NpcQuests(trainer)
            check(#starts==2 and starts[1]==a and starts[2]==c and #turnins==2 and turnins[1]==b and turnins[2]==c,
                "NPC quest lists separate starts and turn-ins from IDs, discoveries and unique names, without inventing item starts")
            ns.NpcQuestRelations={quests={[99101]={name="Starts here",starts={3967},turnins={786},startKnown=true,turninKnown=true},
                [99104]={name="Item starts quest",starts={},turnins={3967},startKnown=true,turninKnown=true},
                [99106]={name="Additional reference quest",starts={3967},turnins={},startKnown=true,level=12}},
                locations={[3967]={mapID=1440,x=40,y=65}}}
            QuestDB=nil;page.npcQuestIndex=nil
            starts,turnins=page.NpcQuests(trainer)
            check(#starts==3 and starts[1]==a and starts[2]==c and starts[3].data.id==99106 and #turnins==3,
                "standalone NPC relationships include extra quests without Questie and do not misidentify an item starter")
            local savedLoc=page.NpcLocation(trainer)
            check(savedLoc and savedLoc.mapID==1440 and savedLoc.x==40, "NPC location falls back to a recorded independent coordinate")
            do
                local oldSnapshot=ns.NpcLocationsData
                ns.NpcLocationsData={npcs={[3967]={name="Aayndia Floralwind",mapID=1440,x=36,y=52,starts={99107,99104}}},
                    quests={[99107]={name="Snapshot-only quest",level=13,starts={3967}},[99104]={name="Item starts quest"}}}
                ns.NpcQuestRelations.locations={};page.npcQuestIndex=nil
                local p=page.NpcLocation(trainer);local extra=page.NpcQuests(trainer)
                local added,itemStart=false,false;local extraEntry
                for _,e in ipairs(extra) do if e.data.id==99107 then added=true;extraEntry=e elseif e.data.id==99104 then itemStart=true end end
                check(p and p.x==36 and added and not itemStart, "standalone Questie snapshot adds matching locations and quests without inventing item starters")
                local linked=false;for _,detail in ipairs(page.Details(extraEntry)) do if detail.target==trainer and detail.text:find("Starts:",1,true) then linked=true end end
                check(linked, "a snapshot-only quest opens with a clickable starter NPC")
                ns.NpcLocationsData.npcs[3967].name="Different NPC"
                extra=page.NpcQuests(trainer);added=false
                for _,e in ipairs(extra) do if e.data.id==99107 then added=true end end
                check(not added, "standalone Questie snapshot ignores mismatched NPC names")
                ns.NpcLocationsData=oldSnapshot;ns.NpcQuestRelations.locations={[3967]={mapID=1440,x=40,y=65}};page.npcQuestIndex=nil
            end
            do
                local oldSource=ns.IndependentReference
                local oldSnapshot=ns.NpcLocationsData;ns.NpcLocationsData=nil
                ns.IndependentReference={PROFESSION_TRAINERS={Leatherworking={{3967,"Aayndia Floralwind","Expert Leatherworker","A",1440,45.2,62.3}}}}
                ns.NpcQuestRelations={quests={},locations={},areaMaps={[14]=1440}}
                local p=page.NpcLocation(trainer)
                check(p and p.mapID==1440 and p.x==45.2, "independent trainer coordinates match NPC ID and name")
                local impostor={name="Other NPC",data={id=3967}}
                check(page.NpcLocation(impostor)==nil, "NPC coordinates are not borrowed when the name differs")
                NpcDB={name=function() return "Aayndia Floralwind" end,spawns=function() return {[14]={{43.5,67.2}}} end};QuestieLoader=nil
                p=page.NpcLocation(trainer)
                check(p and p.mapID==1440 and p.x==43.5, "QuestieDB spawn locations work with the bundled area map without Questie")
                QuestieLoader={ImportModule=function() return {GetUiMapIdByAreaId=function() return 0 end} end}
                p=page.NpcLocation(trainer)
                check(p and p.x==45.2, "suppressed Questie map areas do not use the fallback area mapping")
                ns.IndependentReference=oldSource;ns.NpcLocationsData=oldSnapshot;NpcDB=nil
                ns.NpcQuestRelations={quests={[99101]={name="Starts here",starts={3967},turnins={786},startKnown=true,turninKnown=true},
                    [99104]={name="Item starts quest",starts={},turnins={3967},startKnown=true,turninKnown=true},
                    [99106]={name="Additional reference quest",starts={3967},turnins={},startKnown=true,level=12}},locations={[3967]={mapID=1440,x=40,y=65}}}
            end
            QuestDB={startedBy=function(id) if id==99101 then return {{3967}} elseif id==99104 then return {nil,nil,{55}} elseif id==99105 then return {{3967}} end end,
                finishedBy=function(id) if id==99101 then return {{786}} end end,
                name=function(id) if id==99105 then return "Extra recorded quest" end end,questLevel=function(id) if id==99105 then return 11 end end}
            NpcDB={questStarts=function() return {99105} end};page.npcQuestIndex=nil
            starts=page.NpcQuests(trainer)
            check(#starts==4 and starts[3].data.id==99105 and starts[3].category=="Quests",
                "Questie NPC records include clickable quests missing from the encyclopedia snapshot")
            ns.NpcQuestRelations=nil;page.npcQuestIndex=nil
            NpcDB={spawns=function(id) if id==3967 then return {[14]={{43.5,67.2}}} end end}
            QuestieLoader={ImportModule=function() return {GetUiMapIdByAreaId=function(_,id) if id==14 then return 1440 end end} end}
            local loc=page.NpcLocation(trainer)
            check(loc and loc.mapID==1440 and loc.x==43.5 and loc.y==67.2, "NPC location uses recorded spawn coordinates")
            local oldMapInfo=C_Map.GetMapInfo
            C_Map.GetMapInfo=function(id) if id==1440 then return {name="Ashenvale"} end return oldMapInfo and oldMapInfo(id) end
            enc.current,enc.selected,enc.query=trainer,"NPCs","";enc:Render()
            local pane=page.npcPane
            check(pane and pane:IsShown() and pane.role:GetText()=="Expert Leatherworker" and pane.roleIcon._texture:find("ArmorKit",1,true)
                and pane.location:GetText():find("Ashenvale",1,true) and pane.map:IsShown() and pane.source.text:GetText():find("3967",1,true),
                "NPC profile prioritizes profession and recorded location with sources in their own footer")
            check(pane.columns.starts.title:GetText():find("2",1,true) and pane.columns.turnins.title:GetText():find("2",1,true)
                and pane.columns.starts.rows[1].entry==a and pane.columns.turnins.rows[1].entry==b,
                "NPC page shows separate clickable start and turn-in lists")
            local oldLinks,oldIcon=trainer.links,C_Item.GetItemIconByID
            local linkedItem={kind="item",key="item:test-npc-icon",name="Linked item",data={id=99123},links={}}
            trainer.links={linkedItem};C_Item.GetItemIconByID=function(id) return "test-npc-item-"..id end
            pane.tabs.other:Click()
            check(pane.columns.starts.rows[1].icon._texture=="test-npc-item-99123", "NPC other links use the linked item's icon")
            trainer.links,C_Item.GetItemIconByID=oldLinks,oldIcon;pane.tabs.quests:Click()
            local oldMap,destination=enc.ShowLocation,nil;enc.ShowLocation=function(id,x,y) destination={id,x,y} end;pane.map:Click();enc.ShowLocation=oldMap
            check(destination and destination[1]==1440 and destination[2]==43.5, "NPC map button uses the recorded position")
            pane.columns.starts.rows[1]:Click()
            check(enc.selected=="Quests" and enc.current==a and page.frame:IsShown(), "clicking an NPC quest opens the matching quest page")
            C_Map.GetMapInfo=oldMapInfo
            ns.NpcQuestRelations=savedRelations
            enc.entries,enc.questByID,QuestDB,NpcDB,QuestieLoader,enc.current,enc.selected,enc.query=oldEntries,oldIndex,oldDB,oldNpcDB,oldLoader,oldCurrent,oldSelected,oldQuery
            page.npcQuestIndex=nil;enc:Render()
        end
        do
            local grelin=enc.byKey["npc:786"]; local other=enc.byKey["npc:5828"]
            check(grelin and grelin.name=="Grelin Whitebeard" and other, "reference NPC entries exist for quest links")
            local example={kind="quest",category="Quests",key="quest:npc-test",name="NPC link test",data={id=6,starts="Grelin Whitebeard",turnin="Grelin Whitebeard"},links={}}
            local start,finish
            for _,row in ipairs(page.Details(example)) do
                if row.text and row.text:find("^Starts:") then start=row end
                if row.text and row.text:find("^Turn in:") then finish=row end
            end
            check(start and finish and start.target==grelin and finish.target==grelin and start.npc==grelin.data,
                "unique fallback names resolve to the correct NPC and carry its type for the icon")
            local savedEntries=enc.entries
            enc.entries={{kind="npc",name="Duplicate",data={id=1}},{kind="npc",name="Duplicate",data={id=2}}}
            local ambiguous={kind="quest",name="Ambiguous giver",data={starts="Duplicate"},links={}}
            local ambiguousStart;for _,row in ipairs(page.Details(ambiguous)) do if row.text and row.text:find("^Starts:") then ambiguousStart=row end end
            check(ambiguousStart and not ambiguousStart.target, "duplicate NPC names are not linked to an arbitrary entry")
            enc.entries=savedEntries
            example.data.discovery={giverID=786,turninID=5828}
            for _,row in ipairs(page.Details(example)) do
                if row.text and row.text:find("^Starts:") then start=row end
                if row.text and row.text:find("^Turn in:") then finish=row end
            end
            check(start.target==grelin and finish.target==other and finish.text:find(other.name,1,true),
                "explicit start and turn-in IDs take precedence over stale names")
            example.data.discovery=nil
            local oldCurrent,oldSelected=enc.current,enc.selected
            enc.current,enc.selected=example,"Quests";page.detailOffset=0;enc:Render()
            local npcRow
            for _,row in ipairs(page.frame.details) do if row:IsShown() and row.target==grelin then npcRow=row;break end end
            check(npcRow and npcRow.icon._texture:find("npc%-type%-humanoid") and npcRow.npcBorder:IsShown()
                and npcRow.npcBadges.quest:IsShown(), "quest NPC row shows the same portrait and role badge as the NPC directory")
            npcRow:Click()
            check(enc.selected=="NPCs" and enc.current==grelin, "clicking a quest NPC opens its exact encyclopedia entry")
            enc:Back();enc.current,enc.selected=oldCurrent,oldSelected;enc:Render()
        end
        QuestDB={questLevel=function(id) if id==6 then return 8 end end,requiredLevel=function(id) if id==6 then return 3 end end}
        check(page.Matches(quest,"zone",quest.data.zone,{min="8",max="8"},"garrick") and not page.Matches(quest,"zone",quest.data.zone,{min="9"},""), "quest filters use Questie level and local search")
        UnitLevel=function() return 10 end
        QuestDB.requiredClasses=function() return 1 end
        local eligibility={data={id=6,side="Both"}}
        local label, color, reason=page.Presentation(eligibility,"Not recorded")
        check(label=="Unavailable (class)" and color=="a9a9a9" and reason and page.Presentation(eligibility,"Completed")=="Completed", "reference class restrictions are grey without overriding completed quests")
        QuestDB.requiredClasses=function() return 2 end
        label,color=page.Presentation(eligibility,"Not recorded");check(label=="Not completed" and color=="ff6969", "uncompleted eligible quests are red")
        label,color=page.Presentation(eligibility,"Completed");check(label=="Completed" and color=="5ee879", "completed quests are green")
        label,color=page.Presentation(eligibility,"In progress");check(label=="In progress" and color=="ffd15a", "in-progress quests are yellow")
        label,color=page.Presentation(eligibility,"Unknown");check(label=="Unknown" and color=="a9a9a9", "unknown progress remains distinct from incomplete")
        eligibility.data.side="Alliance";label,color=page.Presentation(eligibility,"Not recorded");check(label=="Unavailable (faction)" and color=="a9a9a9", "other-faction quests are grey")
        eligibility.data.side="Both";QuestDB.requiredLevel=function() return 20 end;label,color=page.Presentation(eligibility,"Not recorded");check(label=="Requires level 20" and color=="a9a9a9", "quests above the recorded minimum level are grey")
        QuestDB.requiredLevel=function(id) if id==6 then return 3 end end
        local rows=page.BuildRows({quest},"zone",quest.data.zone,{},"");check(rows[1] and rows[1].heading and rows[2] and rows[2].entry==quest, "zone quests have collapsible level categories")
        local oldDurotar=ns.IndependentReference.MAP_IDS.Durotar;ns.IndependentReference.MAP_IDS.Durotar=1411
        check(page.ZoneMapID("Northshire Valley")==1429 and page.ZoneMapID("Deathknell")==1420 and page.ZoneMapID("Coldridge Valley")==1426, "starter-area artwork uses the parent zone map")
        check(page.ZoneMapID("Dalaran")==1416 and page.ZoneMapID("City of Dalaran")==1416, "Dalaran uses its Alterac Mountains parent map artwork")
        local oldEnum,oldMapInfo,oldMicro=Enum,C_Map.GetMapInfo,ns.IndependentReference.MAP_IDS["Test microzone"]
        Enum={UIMapType={Micro=5,Zone=3,Continent=2}};ns.IndependentReference.MAP_IDS["Test microzone"]=9991
        C_Map.GetMapInfo=function(id) if id==9991 then return {mapType=5,parentMapID=9992} elseif id==9992 then return {mapType=3,parentMapID=9993} elseif id==9993 then return {mapType=2} end end
        check(page.ZoneMapID("Test microzone")==9992, "client microzone ancestry stops at its parent zone")
        Enum,C_Map.GetMapInfo,ns.IndependentReference.MAP_IDS["Test microzone"]=oldEnum,oldMapInfo,oldMicro
        local zoned={kind="quest",category="Quests",name="A Durotar quest",data={id=6,zone="Durotar",level=8}}
        local unknown={kind="quest",category="Quests",name="A mystery quest",data={id=7,zone="Unknown new zone",level=8}}
        page.zoneTreeOpen={};page.zoneBracketClosed={};page.zoneTreeVersion=(page.zoneTreeVersion or 0)+1
        local subzone={kind="quest",category="Quests",name="A Northshire quest",data={id=8,zone="Northshire Valley"}}
        local subzoneRows=page.BuildZoneTree({subzone},{},"")
        check(#subzoneRows==1 and subzoneRows[1].bracket==0, "zone level brackets start collapsed")
        page.zoneBracketClosed={[0]=false,[-1]=false};page.zoneTreeVersion=page.zoneTreeVersion+1
        subzoneRows=page.BuildZoneTree({subzone},{},"")
        check(subzoneRows[2] and subzoneRows[2].zoneHeader=="Northshire Valley" and subzoneRows[2].mapID==1429 and subzoneRows[1].bracket==0, "subzones retain their names while inheriting parent artwork and level range")
        local sharedPlaces={};for _,zone in ipairs({"Timbermaw Hold","Deeprun Tram","Blackrock Mountain"}) do sharedPlaces[#sharedPlaces+1]={kind="quest",category="Quests",name=zone,data={zone=zone}} end
        local sharedRows=page.BuildZoneTree(sharedPlaces,{},"");local sharedFound={};for _,row in ipairs(sharedRows) do if row.zoneHeader then sharedFound[row.zoneHeader]=row end end
        check(sharedFound["Timbermaw Hold"].mapID==1448 and sharedFound["Deeprun Tram"].mapID==1453 and sharedFound["Blackrock Mountain"].mapID==1427 and sharedRows[1].bracket==-1 and sharedFound["Deeprun Tram"].mapNote, "multi-zone locations use labelled entrance maps without inventing a level range")
        local progressEntries={
            {kind="quest",category="Quests",name="First",data={id=2,zone="Durotar"}},
            {kind="quest",category="Quests",name="Second",data={id=6,zone="Durotar"}},
            {kind="quest",category="Quests",name="Third",data={id=7,zone="Durotar"}},
        }
        page.statusCache={};page.statusVersion=(page.statusVersion or 0)+1
        local progressRows=page.BuildZoneTree(progressEntries,{},"Second")
        check(progressRows[2].progress.completed==1 and progressRows[2].progress.total==3, "zone progress uses completed quests over all recorded zone quests even when searching")
        C_QuestLog.IsQuestFlaggedCompleted=function(id) return id==2 or id==7 end
        page.statusCache={};page.statusVersion=page.statusVersion+1
        progressRows=page.BuildZoneTree(progressEntries,{},"Second")
        check(progressRows[2].progress.completed==2 and progressRows[2].progress.total==3, "zone progress refreshes when quest status changes")
        C_QuestLog.IsQuestFlaggedCompleted=function(id) return id==2 end;page.statusCache={};page.statusVersion=page.statusVersion+1
        local tree,nav=page.BuildZoneTree({zoned,unknown},{},"")
        check(tree[1] and tree[1].bracket==0 and tree[2] and tree[2].zoneHeader=="Durotar" and tree[3] and tree[3].bracket==-1 and nav[1].bracket=="all", "zone directory groups zones by known range and keeps unknown ranges separate")
        page.zoneTreeOpen.Durotar=true;page.zoneTreeVersion=page.zoneTreeVersion+1;tree=page.BuildZoneTree({zoned,unknown},{},"",0)
        check(tree[3] and tree[3].entry==zoned and #tree==3, "expanding a zone shows its quests and selecting a bracket narrows the list")
        page.zoneBracketClosed[0]=true;page.zoneTreeVersion=page.zoneTreeVersion+1;tree=page.BuildZoneTree({zoned},{},"")
        check(#tree==1 and tree[1].bracket==0, "collapsing a level bracket hides its zones")
        page.zoneBracketClosed={};page.zoneTreeOpen={};page.zoneTreeVersion=page.zoneTreeVersion+1;ns.IndependentReference.MAP_IDS.Durotar=oldDurotar
        local sorts={}
        for _,zone in ipairs({"Tailoring","Treasure Map","Warsong Gulch","Blackrock Depths"}) do sorts[zone]={kind="quest",category="Quests",name=zone,data={zone=zone},links={}} end
        check(not page.Matches(sorts.Tailoring,"zone",nil,{},"") and page.Matches(sorts.Tailoring,"profession",nil,{},""), "profession sorts stay out of the zone browser")
        check(not page.Matches(sorts["Treasure Map"],"zone",nil,{},"") and page.Matches(sorts["Treasure Map"],"other",nil,{},""), "treasure-map sorts remain accessible under other quests")
        check(not page.Matches(sorts["Warsong Gulch"],"zone",nil,{},"") and page.Matches(sorts["Warsong Gulch"],"pvp",nil,{},""), "battleground quests have their own category")
        local rawDungeon=sorts["Blackrock Depths"];local rawInstances=page.BuildInstances({rawDungeon})
        check(not page.Matches(rawDungeon,"zone",nil,{},"") and rawInstances[2] and page.Matches(rawDungeon,"dungeon",nil,{},"",rawInstances[2].dungeon), "instance sorts remain accessible even without an existing dungeon link")
        local dungeon={kind="dungeon",key="dungeon:example",name="Example",data={}};local original={kind="quest",links={dungeon}};local grouped={kind="quest",category="Quests",name="Linked",data={level=5},links={original}}
        local instances=page.BuildInstances({grouped});check(instances[1] and instances[2] and instances[2].dungeon==dungeon.key and page.Matches(grouped,"dungeon",nil,{},"",dungeon.key), "dungeon navigation groups quests by their linked instance")
        enc.window.tabs.Quests:Click();page.category="zone";page.zone=quest.data.zone;page.offset=0;enc.current=quest;enc:Render()
        check(page.frame:IsShown() and page.frame.title:GetText()==quest.name and not enc.window.list:IsShown(), "quest selection opens in the dedicated detail pane")
        local savedEntries=enc.entries;local factionQuest={kind="quest",category="Quests",key="quest:test",name="Faction test",data={id=6,zone="Durotar",side="H"}}
        enc.entries={factionQuest};page.zoneBracket="all";page.zoneTreeOpen={Durotar=true};page.zoneBracketClosed={[0]=false};page.zoneTreeVersion=page.zoneTreeVersion+1;page.offset=0;enc:Render()
        local factionRow;for _,row in ipairs(page.frame.rows) do if row.entry==factionQuest then factionRow=row end end
        check(factionRow and factionRow.factionText:GetText()=="Horde" and factionRow.factionIcon:IsShown() and not factionRow.factionIcon2:IsShown(), "quest rows show the Horde faction marker and label")
        factionQuest.data.side="Both";enc:Render();check(factionRow.factionText:GetText()=="Both" and factionRow.factionIcon:IsShown() and factionRow.factionIcon2:IsShown(), "both-faction quests show both markers")
        factionQuest.data.side=nil;enc:Render();check(factionRow.factionText:GetText()=="Unknown" and not factionRow.factionIcon:IsShown() and not factionRow.factionIcon2:IsShown(), "unknown quest factions are not guessed")
        check(page.Faction({data={side="A"}})=="Alliance" and page.Faction({data={side="H"}})=="Horde", "short faction codes are expanded")
        enc.entries=savedEntries;page.zoneTreeOpen={};page.zoneTreeVersion=page.zoneTreeVersion+1;enc:Render()
        local oldLayers,oldTiles=C_Map.GetMapArtLayers,C_Map.GetMapArtLayerTextures
        C_Map.GetMapArtLayers=function() return {{layerWidth=512,layerHeight=256,tileWidth=256,tileHeight=256}} end
        C_Map.GetMapArtLayerTextures=function() return {123,456} end
        local art=page.frame.rows[1].zoneArt;page.PaintZoneArt(art,1411)
        check(art:IsShown() and art.tiles[1]:IsShown() and art.tiles[2]:IsShown() and art.tiles[2]._texture==456, "zone thumbnails stitch client map tiles")
        page.PaintZoneArt(art,nil);check(not art:IsShown(), "missing zone artwork does not display a stale image")
        C_Map.GetMapArtLayers,C_Map.GetMapArtLayerTextures=oldLayers,oldTiles
        check(page.frame.list.scrollbar.fuiPanel and page.frame.detail.scrollbar.fuiPanel, "quest lists use themed draggable scrollbars")
        QuestDB.objectivesText=function() return {string.rep("A long quest objective ",10)} end
        page.detailOffset=0;enc:Render()
        local expanded=false
        for _,row in ipairs(page.frame.details) do if row:IsShown() and row.text:GetText():find("A long quest objective",1,true) then expanded=row:GetHeight()>30 end end
        check(expanded, "long quest objectives have enough vertical space")
        page.showSources=false;page.detailOffset=page.frame.detail.scrollbar.fuiMaximum;enc:Render()
        local sourcesButton;for _,row in ipairs(page.frame.details) do if row:IsShown() and row.toggleSources then sourcesButton=row end end
        if sourcesButton then sourcesButton:Click() end
        check(sourcesButton and page.showSources, "the quest source section can be expanded")
        do
            check(enc.smooth.questList and enc.smooth.questZones and #page.frame.rows == 10 and #page.frame.zoneRows == 6
                and page.frame.rows[1]:GetParent() == enc.smooth.questList.content, "quest and zone lists glide with a spare row")
            page.detailOffset=0;enc:Render()
            local maxPixel=page.detailMaxPixel or 0
            page.frame.detail:GetScript("OnMouseWheel")(page.frame.detail,-1)
            check(maxPixel>0 and page.detailTarget==math.min(36,maxPixel) and page.detailPixel==0, "a wheel notch over quest details glides")
            page:FinishScroll()
            local shown;for _,row in ipairs(page.frame.details) do if row:IsShown() then shown=row;break end end
            local _,_,_,_,y=shown:GetPoint()
            check(page.detailPixel==math.min(36,maxPixel) and y>-0.01 and y<=page.detailPixel, "quest details move by pixel, part of the top line scrolled out")
            page.frame.detail.scrollbar:GetScript("OnValueChanged")(page.frame.detail.scrollbar,maxPixel)
            check(page.detailPixel==maxPixel and page.frame.detail.scrollbar.fuiMaximum==math.floor(maxPixel+0.5), "the quest detail scroll bar drags by pixel to the end")
        end
        local originalSetText = GameTooltip.SetText
        local tooltipArgs, tooltipText
        GameTooltip.SetText = function(_, text, ...) tooltipText = text; tooltipArgs = select("#", ...) end
        local row = page.frame.rows[1]; row.tip = "A quest tooltip"; row:GetScript("OnEnter")(row)
        check(tooltipText == "A quest tooltip" and tooltipArgs == 0, "quest hover tooltip uses the client's SetText signature")
        GameTooltip.SetText = originalSetText
        C_QuestLog,QuestDB,GetQuestLogQuestText,UnitLevel=savedLog,savedDB,savedText,savedLevel;page.statusCache={};page.category="zone";page.zone=nil;page.zoneInitialized=false;page.showSources=false
    end
    M.testQuestDirectory(); M.testQuestDirectory = nil
    M.testAdditionalSources = function()
        local food, target, chest, boxed = enc.byKey["item:117"], enc.byKey["item:422"], false, false
        for _, source in ipairs(food and food.data.sourceLinks or {}) do
            if source.kind == "Object" and source.entry.data.id == 2843 and source.note:find("verification", 1, true) then chest = source.entry end
        end
        for _, source in ipairs(target and target.data.sourceLinks or {}) do
            if source.kind == "Container" and source.entry.data.id == 16882 and source.note:find("verification", 1, true) then boxed = true end
        end
        check(chest and boxed, "object and container sources are linked with uncertainty notes")
        if chest then
            enc:OpenEntry(chest)
            check(enc.current == chest and enc.selected == "Items" and enc.Details(chest):find("need verification", 1, true), "object source opens an honest reference page")
            enc:Back()
        end
    end
    M.testAdditionalSources(); M.testAdditionalSources = nil
    M.testAuctionImport = function()
        local oldGold = ForeverGold
        local prices = { [99123456] = {p=30,q=0,t=1234}, [99123457] = {p=0,q=1,t=1234}, [8827] = {p=25,q=2,t=1234} }
        local realm, listeners = { prices=prices,lastScan=1234 }, {}
        ForeverGold = {
            db = { items = { [99123456] = {n="Auction Discovery",q=2,c=7,l=1}, [99123457] = {n="Invalid Listing",c=7} } },
            R = function() return realm end,
            LastPrice = function(id) local r=prices[id]; if r then return r.p,r.t end end,
            Listen = function(event, callback) listeners[event] = callback end,
        }
        enc:RefreshData()
        local found = enc.byKey["item:99123456"]
        check(found and found.data.auctionObserved and found.data.itemClass == "Trade Goods" and found.data.sourceLabel == "Seen on auction house", "previously listed items absent from the reference catalogue are imported")
        check(not enc.byKey["item:99123457"], "invalid auction records do not create entries")
        check(not enc.ItemUnavailable({data={id=8827}}), "an auction observation keeps a Wowhead-unavailable item visible")
        check(enc.byKey["item:8827"] and enc.Details(enc.byKey["item:8827"]):find("Forever Gold recorded an auction listing", 1, true), "availability conflict explains the auction observation")
        check(enc.Details(found):find("Previously listed on your auction house", 1, true), "past listing is disclosed without guaranteeing availability")
        ns.OpenEncyclopedia()
        local rebuilds, rebuild = 0, enc.RefreshData
        enc.RefreshData = function(...) rebuilds = rebuilds + 1; return rebuild(...) end
        prices[99123457].p = 20; realm.lastScan = 1235
        if listeners.PRICES_UPDATED then listeners.PRICES_UPDATED() end
        check(enc.byKey["item:99123457"], "a later auction scan refreshes the open encyclopedia")
        prices[99123458] = {p=4,q=1,t=1236}; ForeverGold.db.items[99123458] = {n="Partial Scan Discovery",c=7}
        ForeverGold.scan = { lastResult = {at=1236} }
        if listeners.PRICES_UPDATED then listeners.PRICES_UPDATED() end
        check(enc.byKey["item:99123458"], "a partial scan refreshes discoveries even without a new full-scan timestamp")
        ns.OpenEncyclopedia()
        enc.RefreshData = rebuild
        check(rebuilds == 0, "a scan adds its new items without rebuilding every reference entry")
        local at, sorted = nil, true
        for i, e in ipairs(enc.entries) do
            if e.key == "item:99123458" then at = i end
            if i > 1 then
                local a, b = enc.entries[i - 1].name:lower(), e.name:lower()
                if a > b then sorted = false end
            end
        end
        check(at and sorted, "items from a scan are slotted into name order")
        ForeverGold = oldGold
    end
    M.testAuctionImport(); M.testAuctionImport = nil
    enc.window:Hide()
    OneForAll, ForeverGold = previousSource, previousGold
end
check(#ns.errors == 0, "still no errors: " .. tostring(ns.errors[1]))

do -- the audit's fixes
    local oldPlayer, oldKnown, oldBook = IsPlayerSpell, IsSpellKnown, C_SpellBook
    IsPlayerSpell, IsSpellKnown = nil, nil
    C_SpellBook = { IsSpellKnown = function(id) return id == 9787 end }
    check(ns.SpellKnown(9787) and not ns.SpellKnown(9788) and not ns.SpellKnown(nil),
        "spells are known through C_SpellBook when the old globals are gone")
    IsPlayerSpell, IsSpellKnown, C_SpellBook = oldPlayer, oldKnown, oldBook

    ns.Err("test", "boom"); ns.Err("test", "boom"); ns.Err("test", "boom")
    check(#ns.errors == 1 and ns.errors[1] == "test: boom  (x3)" and ns.db.lastErrors == ns.errors,
        "a repeating error is counted once and kept in the saved settings")
    ns.Err("test", "other")
    check(#ns.errors == 2 and ns.errors[1] == "test: other", "a new error goes on top")
    for i = #ns.errors, 1, -1 do table.remove(ns.errors, i) end

    local registered = {}
    for _, f in ipairs(M.frames or {}) do registered[f] = true end
    local ok = pcall(ns.On, "FUI_TEST_EVENT", function() end)
    check(ok, "registering an event never throws")
end

do -- Passive Favor vendor checks must never mistake an incomplete list for absence.
    local oldGuid, oldRealm, oldMerchant, oldPrint = UnitGUID, GetRealmName, M.merchant, ns.Print
    local oldCostInfo, oldCostItem = GetMerchantItemCostInfo, GetMerchantItemCostItem
    local vendor = 248200
    UnitGUID = function(unit) if unit == "npc" then return "Creature-0-0-0-0-" .. vendor .. "-0000000000" end end
    GetRealmName = function() return "Vendor test realm" end
    local messages = {}
    ns.Print = function(text) messages[#messages + 1] = text end
    M.merchant = { {264221}, {} }
    M.fire("MERCHANT_SHOW"); M.fire("MERCHANT_UPDATE")
    local note, found = ns.FavorVendorObservation(264221)
    check(found and note:find("Fizzlefuse: shown", 1, true), "vendor check records a visibly stocked schematic")
    check(not ns.FavorVendorObservation(264222), "unloaded merchant entries do not imply a missing recipe")
    GetMerchantItemCostInfo = function() return 1 end
    GetMerchantItemCostItem = function() return 123, 50, nil, "Other Currency" end
    M.fire("MERCHANT_UPDATE")
    note = ns.FavorVendorObservation(264221)
    check(note and not note:find("50 Favor", 1, true), "unrelated currencies are never recorded as Favor")
    GetMerchantItemCostInfo = function() return 2 end
    GetMerchantItemCostItem = function(_, component)
        if component == 1 then return 123, 50, nil, "Other Currency" end
        return 456, 270, nil, "Merchant's Favor"
    end
    M.fire("MERCHANT_UPDATE")
    note = ns.FavorVendorObservation(264221)
    check(note and note:find("270 Favor plus other costs", 1, true),
        "vendor check records the identified Favor price and other costs")
    check(messages[#messages]:find("270 Favor", 1, true), "a late-loaded Favor price is reported in chat")
    M.merchant = { {264221}, {1234} }
    M.fire("MERCHANT_UPDATE")
    note, found = ns.FavorVendorObservation(264222)
    check(not found and note and note:find("not shown", 1, true) and note:find("filters or reputation", 1, true),
        "complete vendor checks label missing items as not shown, with limits")
    M.fire("MERCHANT_CLOSED")
    M.merchant = { {264222} }; M.fire("MERCHANT_UPDATE")
    note, found = ns.FavorVendorObservation(264222)
    check(not found and note and note:find("not shown", 1, true), "a closed merchant cannot overwrite the observation")
    vendor = 248196; M.merchant = { {250996} }
    M.fire("MERCHANT_SHOW"); M.fire("MERCHANT_UPDATE")
    note, found = ns.FavorVendorObservation(250996)
    check(found and note:find("Apothecary Durelle: shown", 1, true), "alchemy vendor check records the potion recipe")
    check(#messages >= 2, "vendor results are reported in chat")
    ns.Encyclopedia:SyncData()
    local entry = ns.Encyclopedia.byKey["item:264221"]
    local source
    for _, link in ipairs(entry and entry.data.sourceLinks or {}) do
        if link.kind == "Merchant's Favor" then source = link end
    end
    check(source and source.note:find("Fizzlefuse: shown", 1, true) and not source.uncertain,
        "the encyclopedia includes a recorded vendor sighting")
    check(source and source.note:find("270 Favor plus other costs", 1, true),
        "the encyclopedia shows the observed vendor-specific Favor cost")
    M.fire("MERCHANT_CLOSED")
    GetRealmName = function() return "A different realm" end
    check(not ns.FavorVendorObservation(250996), "vendor observations are scoped to their realm")
    UnitGUID, GetRealmName, M.merchant, ns.Print = oldGuid, oldRealm, oldMerchant, oldPrint
    GetMerchantItemCostInfo, GetMerchantItemCostItem = oldCostInfo, oldCostItem
    ns.db.favorVendorChecks["Vendor test realm"] = nil
end

do -- Camelot reputation and skill rows are recycled and use different frame types.
    local oldRep, oldSkills, oldMixin = ReputationFrame, SkillsFrame, ScrollBoxListMixin
    local oldItem, oldButton, oldName = MerchantItem1, MerchantItem1ItemButton, MerchantItem1NameFrame
    local function progress(kind)
        local bar = CreateFrame(kind, nil, UIParent)
        bar.FillArea = CreateFrame("Frame", nil, bar)
        bar.Fill = bar:CreateTexture()
        bar.Fill.GetAtlas = function(self) return self._atlas end
        bar.Fill.SetTexture = function(self, texture) self._texture, self._atlas = texture, nil end
        bar.Fill.SetVertexColor = function(self, r, g, b) self._vertex = {r, g, b} end
        bar.Fill:SetAtlas("common-stat-bar-blue")
        bar.SetFillPercent = function(self, value) self._percent = value end
        return bar
    end
    local repBar, skillBar, detailBar = progress("Frame"), progress("StatusBar"), progress("StatusBar")
    local repRow, skillRow = { Content = { ReputationBar = repBar } }, { Content = { SkillsBar = skillBar } }
    local function box(row)
        return {
            ForEachFrame = function(_, callback) callback(row) end,
            RegisterCallback = function(self, _, callback, owner) self.callback, self.owner = callback, owner end,
        }
    end
    ScrollBoxListMixin = { Event = { OnInitializedFrame = "row" } }
    ReputationFrame = { ScrollBox = box(repRow) }
    SkillsFrame = { ScrollBox = box(skillRow), SkillDetailFrame = { RankBar = detailBar } }
    M.fire("UPDATE_FACTION")
    check(repBar.fuiPageBar and skillBar.fuiPageBar and detailBar.fuiPageBar,
        "reputation Frame bars and the actual SkillsFrame bars are styled")
    check(repBar.Fill._texture == ns.FLAT and repBar.Fill._vertex[3] == 0.76,
        "the native blue progress fill is made flat and remains blue")
    repBar.Fill:SetAtlas("common-stat-bar-green"); repBar:SetFillPercent(0.5)
    check(repBar.Fill._texture == ns.FLAT and repBar.Fill._vertex[2] == 0.66 and repBar._percent == 0.5,
        "recycled progress bars retain Blizzard's new value and reaction colour")
    local nextBar = progress("Frame")
    ReputationFrame.ScrollBox.callback(ReputationFrame.ScrollBox.owner, { Content = { ReputationBar = nextBar } })
    check(nextBar.fuiPageBar ~= nil, "newly initialized scroll rows are styled")
    MerchantItem1 = CreateFrame("Frame", "MerchantItem1", UIParent)
    MerchantItem1.SlotTexture = MerchantItem1:CreateTexture()
    MerchantItem1NameFrame = MerchantItem1:CreateTexture()
    MerchantItem1ItemButton = CreateFrame("Button", "MerchantItem1ItemButton", MerchantItem1)
    M.fire("MERCHANT_SHOW")
    check(MerchantItem1.fuiPanel and MerchantItem1ItemButton.fuiMerchantEdge
        and MerchantItem1.SlotTexture._alpha == 0 and MerchantItem1NameFrame._alpha == 0,
        "vendor item rows receive the theme while their original button stays present")
    do
        local oldFrame, oldBG, oldCount = MerchantFrame, BuybackBG, GetNumBuybackItems
        local oldMoney, oldSecond = MerchantItem1MoneyFrame, MerchantItem2
        local oldBuybackUpdate, oldMerchantUpdate = MerchantFrame_UpdateBuybackInfo, MerchantFrame_UpdateMerchantInfo
        MerchantFrame = CreateFrame("Frame", nil, UIParent); MerchantFrame.selectedTab = 2
        BuybackBG = MerchantFrame:CreateTexture()
        GetNumBuybackItems = function() return 1 end
        local label = MerchantItem1:CreateFontString(); MerchantItem1.Name = label
        label:SetSize(100, 30); label:SetPoint("LEFT", MerchantItem1, "LEFT", 40, 0)
        label.GetWordWrap = function(self) return self._wrap ~= false end
        label.SetWordWrap = function(self, wrap) self._wrap = wrap end
        MerchantItem1MoneyFrame = CreateFrame("Frame", nil, MerchantItem1)
        MerchantItem1MoneyFrame:SetPoint("BOTTOMLEFT", MerchantItem1, "BOTTOMLEFT", 40, 1)
        MerchantItem1ItemButton:SetPoint("TOPLEFT", MerchantItem1, "TOPLEFT", 0, 0)
        local clicked = false
        MerchantItem1ItemButton:SetScript("OnClick", function() clicked = true end)
        MerchantItem2 = CreateFrame("Frame", "MerchantItem2", UIParent)
        MerchantFrame_UpdateBuybackInfo = function() MerchantFrame.selectedTab = 2 end
        MerchantFrame_UpdateMerchantInfo = function() MerchantFrame.selectedTab = 1 end
        M.fire("MERCHANT_SHOW")
        MerchantFrame_UpdateBuybackInfo()
        M.fire("MERCHANT_UPDATE")
        local _, _, _, nameX, nameY = label:GetPoint()
        local _, _, _, priceX, priceY = MerchantItem1MoneyFrame:GetPoint()
        local _, _, _, iconX, iconY = MerchantItem1ItemButton:GetPoint()
        check(BuybackBG:GetAlpha() == 0 and nameX == 46 and nameY == -5
            and priceX == 46 and priceY == 5 and iconX == 4 and iconY == -4
            and label:GetHeight() == 14 and label._wrap == false,
            "buyback cards align icon, one-line name and price on the dark background")
        check(not MerchantItem2.fuiPanel.bg:IsShown(), "empty buyback cards have no visible outline")
        MerchantItem1ItemButton:Click()
        check(clicked, "the buyback item keeps its original click handler")
        MerchantFrame_UpdateMerchantInfo()
        local _, _, _, restoredX = label:GetPoint()
        check(restoredX == 40 and label:GetHeight() == 30 and label._wrap
            and MerchantItem2.fuiPanel.bg:IsShown(), "merchant tab restores its original layout")
        MerchantFrame, BuybackBG, GetNumBuybackItems = oldFrame, oldBG, oldCount
        MerchantItem1MoneyFrame, MerchantItem2 = oldMoney, oldSecond
        MerchantFrame_UpdateBuybackInfo, MerchantFrame_UpdateMerchantInfo = oldBuybackUpdate, oldMerchantUpdate
    end
    ReputationFrame, SkillsFrame, ScrollBoxListMixin = oldRep, oldSkills, oldMixin
    MerchantItem1, MerchantItem1ItemButton, MerchantItem1NameFrame = oldItem, oldButton, oldName
end

do
    -- /fui perf: frame times and each addon's share, from the game's addon profiler
    local oldProf, oldNum, oldInfo = C_AddOnProfiler, C_AddOns.GetNumAddOns, C_AddOns.GetAddOnInfo
    local oldLoaded = C_AddOns.IsAddOnLoaded
    local per = { ForeverUI = 0.2, OpenMap = 1.5, Questie = 0.6 }
    local order = { "ForeverUI", "OpenMap", "Questie" }
    C_AddOnProfiler = {
        IsEnabled = function() return true end,
        GetAddOnMetric = function(name) return per[name] or 0 end,
        GetOverallMetric = function() return 2.3 end,
        GetApplicationMetric = function() return 3.5 end,
    }
    C_AddOns.GetNumAddOns = function() return #order end
    C_AddOns.GetAddOnInfo = function(i) return order[i] end
    C_AddOns.IsAddOnLoaded = function() return true end
    ForeverUIDB.perfLog = nil
    local oldOM = OpenMap
    local stitch = { closeSteps = { culling = { ms = 0.3, worst = 9 }, sea = { ms = 0.01, worst = 0.1 } } }
    OpenMap = { MapStitch = stitch }
    SlashCmdList.FOREVERUI("perf 2")
    check(stitch.closeSteps.culling.worst == 0 and type(stitch.bench) == "table",
        "/fui perf starts OpenMap's step timings afresh and turns on its part timings")
    stitch.closeSteps.culling.worst = 12.5
    stitch.bench["every addon's pins rescaled"] = 40
    for _ = 1, 30 do M.update(0.1) end
    local run = ForeverUIDB.perfLog and ForeverUIDB.perfLog[1]
    check(run and run.openMapSteps[1].name == "culling" and run.openMapSteps[1].worst == 12.5 and #run.openMapSteps == 1
        and run.openMapParts[1].ms == 2 and stitch.bench == nil and run.hitches == 20,
        "/fui perf keeps OpenMap's slowest steps and parts, and counts frames over 33 ms")
    OpenMap = oldOM
    check(run and run.frames >= 19 and math.abs(run.frameMs - 100) < 0.01 and math.abs(run.addonsMs - 2.3) < 0.01
        and math.abs(run.gameMs - 3.5) < 0.01, "/fui perf records frame times and the addons' share")
    check(run and run.top[1].name == "OpenMap" and math.abs(run.top[1].avg - 1.5) < 0.01 and run.top[3].name == "ForeverUI",
        "/fui perf ranks the addons by time a frame")
    local before = #ForeverUIDB.perfLog
    local oldMap = WorldMapFrame
    WorldMapFrame = { IsShown = function() return false end }
    SlashCmdList.FOREVERUI("perf map 2")
    for _ = 1, 30 do M.update(0.1) end
    check(#ForeverUIDB.perfLog == before, "/fui perf map waits for the map to open")
    WorldMapFrame = oldMap
    SlashCmdList.FOREVERUI("perf")
    SlashCmdList.FOREVERUI("perf 2")
    for _ = 1, 30 do M.update(0.1) end
    check(#ForeverUIDB.perfLog == before + 1, "/fui perf again stops a run, and the next one starts afresh")
    C_AddOnProfiler, C_AddOns.GetNumAddOns, C_AddOns.GetAddOnInfo, C_AddOns.IsAddOnLoaded = oldProf, oldNum, oldInfo, oldLoaded
end

M.testOptionalLeadIn = function()
    local oldFaction = UnitFactionGroup
    UnitFactionGroup = function() return "Horde" end
    local bfd
    for _, d in ipairs(ns.IndependentReference.DUNGEONS) do if d.key == "bfd" then bfd = d end end
    ns.InstanceGuide.chainCache = {}; ns.InstanceGuide.chainOpen = {[6562]=true}
    local first, second
    for _, row in ipairs(ns.InstanceGuide:QuestRows(bfd)) do
        if row.quest.id == 6562 then first = row end
        if row.quest.id == 6563 then second = row end
    end
    check(first and second and first.optionalLeadIn and second.optionalLeadIn,
        "Blackfathom's optional lead-in is distinguished from a required prerequisite")
    UnitFactionGroup = oldFaction; ns.InstanceGuide.chainCache = {}; ns.InstanceGuide.chainOpen = {}
end
M.testOptionalLeadIn(); M.testOptionalLeadIn = nil
M.testFlightTimer = function()
    local flight, oldTaxi, oldClock = ns.FlightTimer, UnitOnTaxi, M.clock
    local riding = false
    UnitOnTaxi = function() return riding end
    M.clock = 100; flight:Select("Orgrimmar", "Thunder Bluff"); riding = true; flight:Update()
    check(flight.frame:IsShown() and flight.frame.time:GetText():find("learning", 1, true), "first flight displays elapsed time while learning")
    M.clock = 160; riding = false; flight:Update()
    check(not flight.frame:IsShown() and flight.active == nil, "arrival hides the flight timer and records the route")
    M.clock = 200; flight:Select("Orgrimmar", "Thunder Bluff"); riding = true; flight:Update(); M.clock = 210; flight:Update()
    check(flight.frame.time:GetText():find("~0:50 remaining", 1, true), "repeat flight shows a learned remaining time")
    riding = false; M.clock = 260; flight:Update()
    flight:Select("Thunder Bluff", "Orgrimmar"); riding = true; M.clock = 300; flight:Update()
    check(flight.frame.time:GetText():find("learning", 1, true), "reverse direction learns independently")
    riding = false; flight:Update(); UnitOnTaxi, M.clock = oldTaxi, oldClock
end
M.testFlightTimer(); M.testFlightTimer = nil
if failed > 0 then
    M.realPrint("FAILED: " .. failed)
    error("Forever UI: " .. failed .. " checks failed")
else
    M.realPrint("ALL CHECKS PASSED")
end


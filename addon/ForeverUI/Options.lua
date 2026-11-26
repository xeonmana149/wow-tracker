-- Forever UI - its page in the game's Options window (Options > AddOns >
-- Forever UI), built from the game's own checkboxes, sliders and buttons.

local _, ns = ...

local category
local sections, currentSection = {}, nil
local sectionNames = {
    ["Encyclopedia"] = "General & QoL", ["Quality of life"] = "General & QoL",
    ["Pieces"] = "UI Modules", ["Healing frames"] = "Healing & Dispels",
    ["Nameplates"] = "Nameplates", ["Look"] = "Appearance & Layout",
    ["Damage meter"] = "Damage Meter", ["Micro menu layout"] = "Appearance & Layout",
    ["Where things sit"] = "Appearance & Layout",
}
local sectionDescriptions = {
    ["General & QoL"] = "Encyclopedia access and optional conveniences.",
    ["UI Modules"] = "Choose which parts of the interface Forever UI replaces.",
    ["Healing & Dispels"] = "Group frames, click casting and dispels.",
    ["Nameplates"] = "Threat, aura and nameplate display options.",
    ["Appearance & Layout"] = "Colors, menu layout and positions.",
    ["Damage Meter"] = "Damage meter behavior in instances.",
}
local window
local function add(entry)
    if currentSection then currentSection.entries[#currentSection.entries + 1] = entry end
end

local function header(layout, text, tooltip)
    local name = sectionNames[text] or text
    for _, section in ipairs(sections) do if section.name == name then currentSection = section; return end end
    currentSection = { name = name, description = sectionDescriptions[name] or tooltip, entries = {} }
    sections[#sections + 1] = currentSection
end

local function button(layout, name, text, onClick, tooltip)
    add({ kind = "button", name = name, caption = text, run = onClick, tooltip = tooltip })
end

local function check(cat, key, name, tooltip, onChange)
    local setting = Settings.RegisterProxySetting(cat, "FOREVERUI_" .. key:upper(), Settings.VarType.Boolean, name,
        ns.Opt(key) and true or false,
        function() return ns.Opt(key) and true or false end,
        function(v)
            ns.O()[key] = v and true or false
            if onChange then onChange(v) end
        end)
    add({ kind = "check", name = name, tooltip = tooltip, get = function() return ns.Opt(key) and true or false end,
        set = function(v) ns.O()[key] = v and true or false; if onChange then onChange(v) end end })
end

local function slide(cat, key, name, tooltip, lo, hi, step, label, onChange)
    local setting = Settings.RegisterProxySetting(cat, "FOREVERUI_" .. key:upper(), Settings.VarType.Number, name,
        tonumber(ns.Opt(key)) or lo,
        function() return tonumber(ns.Opt(key)) or lo end,
        function(v)
            ns.O()[key] = v
            if onChange then onChange(v) end
        end)
    add({ kind = "number", name = name, tooltip = tooltip, low = lo, high = hi, step = step, format = label,
        get = function() return tonumber(ns.Opt(key)) or lo end,
        set = function(v) ns.O()[key] = v; if onChange then onChange(v) end end })
end

local function pct(v)
    return math.floor(v * 100 + 0.5) .. "%"
end

local pendingCVars = {}
local function applyCVars()
    for name, value in pairs(pendingCVars) do
        local ok, result = pcall(C_CVar.SetCVar, name, value)
        if not ok or result == false then ns.Print("the game did not allow the " .. name .. " setting to change.") end
        pendingCVars[name] = nil
    end
end

local function setCVar(name, value)
    pendingCVars[name] = tostring(value)
    ns.WhenSafe(applyCVars)
end

local function cvarCheck(cat, cvar, name)
    if not (C_CVar and type(C_CVar.GetCVarBool) == "function" and type(C_CVar.SetCVar) == "function") then return end
    local ok, value = pcall(C_CVar.GetCVarBool, cvar)
    if not ok or ns.Secret(value) or type(value) ~= "boolean" then return end
    local setting = Settings.RegisterProxySetting(cat, "FOREVERUI_CVAR_" .. cvar:upper(), Settings.VarType.Boolean, name, value,
        function() local success, current = pcall(C_CVar.GetCVarBool, cvar); return success and current == true end,
        function(v)
            setCVar(cvar, v and "1" or "0")
        end)
    add({ kind = "check", name = name, get = function()
        local success, current = pcall(C_CVar.GetCVarBool, cvar)
        return success and not ns.Secret(current) and current == true
    end, set = function(v) setCVar(cvar, v and "1" or "0") end })
end

local function cvarSlider(cat, cvar, name, tooltip, lo, hi, step)
    if not (C_CVar and type(C_CVar.GetCVar) == "function" and type(C_CVar.SetCVar) == "function") then return end
    local ok, value = pcall(C_CVar.GetCVar, cvar)
    if not ok or ns.Secret(value) then return end
    value = tonumber(value)
    if not value then return end
    local setting = Settings.RegisterProxySetting(cat, "FOREVERUI_CVAR_" .. cvar:upper(), Settings.VarType.Number, name, value,
        function()
            local success, current = pcall(C_CVar.GetCVar, cvar)
            if not success or ns.Secret(current) then return value end
            return tonumber(current) or value
        end,
        function(v) setCVar(cvar, v) end)
    add({ kind = "number", name = name, tooltip = tooltip, low = lo, high = hi, step = step, format = pct,
        get = function() local success, v = pcall(C_CVar.GetCVar, cvar); return success and not ns.Secret(v) and tonumber(v) or value end,
        set = function(v) setCVar(cvar, v) end })
end

local function needsReload()
    ns.Print("that takes effect after a /reload.")
end

function ns.SetupOptions()
    if category or not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then
        return
    end
    local cat, layout = Settings.RegisterVerticalLayoutCategory("Forever UI")
    category = cat

    header(layout, "Encyclopedia", "Browse the connected reference library.")
    button(layout, "Forever Encyclopedia", "Open", function() if ns.OpenEncyclopedia then ns.OpenEncyclopedia() end end,
        "Browse dungeons, pets, recipes, camping, reputation and equipment sets.")
    button(layout, "Instance Guide", "Open", function() if ns.InstanceGuide then ns.InstanceGuide:Toggle() end end,
        "Browse dungeon and raid bosses, quests and entrance locations.")

    header(layout, "Quality of life", "Optional conveniences. Turn off overlapping features in other addons first.")
    button(layout, "Class training", "Open", function() if ns.TrainerGuide then ns.TrainerGuide:Open() end end, "Browse your class spells and ranks without buying them.")
    cvarCheck(cat, "autoLootDefault", "Auto loot")
    check(cat, "qolQuickLoot", "Quicker auto loot", "Loot available items together when auto loot is active. Your auto-loot modifier still opens the loot window.")
    check(cat, "qolAutoRepair", "Repair at merchants", "Repair using your own gold when you visit a repair merchant. Does not use guild funds.")
    check(cat, "qolAutoJunk", "Sell junk at merchants", "Automatically sell items marked as junk using Forever Gold's keep and ignored-bag rules. Requires Forever Gold.")
    check(cat, "qolAutoQuestAccept", "Accept quests automatically", "Take every quest an NPC offers, one after another, as soon as you talk to them. Repeatable, daily and grey quests are left to you. Hold Shift to pause.")
    check(cat, "qolAutoQuestTurnIn", "Turn in quests automatically", "Hand in every finished quest at an NPC, one after another, when no reward choice is needed. Hold Shift to pause.")
    check(cat, "qolCameraZoom", "Farther camera zoom", "Increase the maximum camera distance. Turning this off restores the previous setting if it has not changed elsewhere.", ns.ApplyCameraZoom)
    check(cat, "qolQuestVendor", "Mark valuable quest rewards", "Show a gold coin on the reward choice with the highest known vendor value. You still choose the reward.", function() if ns.MarkQuestRewards then ns.MarkQuestRewards() end end)
    check(cat, "qolQuestSparkles", "Quest loot sparkles", "Enable the game's loot glow. This can also illuminate quest NPCs and may require a restart when switched off.", ns.ApplyQuestSparkles)
    check(cat, "qolNodeGlow", "Herb and ore sparkles", "Highlight the nearby interact target when it is a herb or ore you can gather. The required interaction settings are restored when disabled.", function(v) if ns.NodeGlow then ns.NodeGlow.Apply(v) end end)
    check(cat, "qolQuestMarks", "Quest marks on nameplates", "Show quest progress on supported nameplates. Turn off similar marks in other addons to avoid duplicates.", function() if ns.QuestMarks then ns.QuestMarks:Refresh() end end)
    check(cat, "qolLowRankCheck", "Check action-bar spell ranks", "After learning spells, offer a list of lower ranks on your bars. You choose whether to replace them; macros are not changed.")
    button(layout, "Kept spell ranks", "Reset", function() if ns.TrainerGuide then ns.TrainerGuide:ClearKeptRanks() end end, "Include deliberately kept lower ranks in future checks again.")
    check(cat, "qolQuestXP", "Completed quest XP", "Show known XP from completed quests on the XP bar. Quest rewards still need to be turned in.", function()
        local xp = ns.modules.xpbar
        if xp and xp.built then xp:Update() end
    end)

    header(layout, "Pieces", "Each part of the screen Forever UI replaces. Switching one takes a /reload.")
    for _, m in ipairs(ns.modules) do
        check(cat, m.key, m.name, "Use Forever UI's " .. m.name:lower() .. " (after a /reload).", needsReload)
    end
    header(layout, "Healing frames", "Group frames, click casting and dispels.")
    button(layout, "Healing bindings", "Configure", function()
        local healing = ns.modules.healing
        if healing and healing.built then healing:ShowConfig() else ns.Print("enable Healing frames and reload first.") end
    end, "Choose click-cast spells for this character.")
    button(layout, "Dispels (Decursive)", "Show / hide", function()
        local dispel = ns.modules.dispel
        if dispel and dispel.built then dispel:Toggle() else ns.Print("enable Dispel indicators and reload first.") end
    end, "Show or hide the dispel panel for this character, even before learning a dispel.")
    button(layout, "Move dispel squares", "Move mode", function()
        if SettingsPanel and SettingsPanel.Close then pcall(SettingsPanel.Close, SettingsPanel) end
        ns.ToggleMoveMode(true)
    end, "Drag Dispels independently. Right-click its move handle to reset the position.")
    check(cat, "dispelSound", "Dispel alert sound", "Play a short sound when a new effect you can dispel appears. Uses the game's sound effects volume.")
    check(cat, "healPets", "Show pets in healing frames", "Include party and raid pets. Takes effect after a reload.", needsReload)
    local function updateHealing()
        local healing = ns.modules.healing
        if healing and healing.built then ns.WhenSafe(function() healing:Refresh() end) end
    end
    check(cat, "healSolo", "Show healing frames while solo", "Show your own frame outside a group for practice and setup.", updateHealing)
    check(cat, "healTargets", "Show friendly target and focus", "Add click-cast frames for friendly target and focus above the group. Enable solo display to use them outside a group.", updateHealing)
    check(cat, "healReplaceParty", "Replace the native party frames", "Use the healing frames in place of the game's party frames.", updateHealing)
    check(cat, "healDeficit", "Show missing health", "Display missing health instead of the percentage on healing frames.", updateHealing)
    check(cat, "healPower", "Show group power", "Show each member's available resource under their health.", updateHealing)
    check(cat, "healClassColor", "Color group health by class", "Use class colors on healing-frame health bars.", updateHealing)
    check(cat, "healRoleColor", "Color healers and tanks", "Show healers in yellow and tanks in red when the game provides group roles. Overrides class colors for those roles.", updateHealing)
    check(cat, "healThreat", "Show group threat", "Mark members who have significant enemy threat when the game provides it.", updateHealing)
    check(cat, "healDispelButtons", "Dispels above portraits", "Show learned dispel spells above each healing-frame portrait.", updateHealing)
    check(cat, "healAuraTimers", "Healing aura timers", "Show remaining time on tracked healing-frame auras when available.", updateHealing)
    check(cat, "healAbsorbs", "Show healing absorbs", "Show damage shields and account for heal absorbs when the client provides them.", updateHealing)
    slide(cat, "healScale", "Healing frame size", "Scale the healing group and raid frames.", 0.7, 1.5, 0.05, pct, updateHealing)
    slide(cat, "healWidth", "Healing frame width", "Width of each party and raid member button.", 100, 200, 5, tostring, updateHealing)
    slide(cat, "healHeight", "Healing frame height", "Height of each party and raid member button.", 22, 40, 2, tostring, updateHealing)
    slide(cat, "healRaidRows", "Raid members per column", "Arrange the raid and its pets in columns with this many rows.", 5, 10, 1, tostring, updateHealing)
    button(layout, "Healing aura tracking", "Configure", function()
        local healing = ns.modules.healing
        if healing and healing.built then healing:ShowAuraConfig() else ns.Print("enable Healing frames and reload first.") end
    end, "Choose which helpful effects or specific spell IDs appear on healing frames.")
    button(layout, "Custom spell indicators", "Configure", function()
        if ns.CustomAuras and ns.CustomAuras.frame then ns.CustomAuras:ShowConfig() end
    end, "Track your buffs, target debuffs and spell cooldowns by spell ID. Move them in Edit Mode.")
    button(layout, "Healing and nameplate profiles", "Manage", function()
        local healing = ns.modules.healing
        if healing and healing.built then healing:ShowProfiles() else ns.Print("enable Healing frames and reload first.") end
    end, "Save, load, or delete this character's healing and nameplate settings.")

    header(layout, "Nameplates")
    local function updatePlates()
        local plates = ns.modules.nameplates
        if plates and plates.built and plates.ApplyOptions then plates:ApplyOptions() end
    end
    check(cat, "plateThreat", "Color nameplates by threat", "Use threat colors when the game provides threat data.", updatePlates)
    check(cat, "plateThreatText", "Nameplate threat label", "Show a threat status label as well as the threat color.", updatePlates)
    check(cat, "plateThreatPercent", "Show threat percentage", "Show a percentage in the threat label when the client provides it.", updatePlates)
    check(cat, "plateTank", "Use tank threat colors", "Treat high threat as safe even if the game has not assigned you the tank role.", updatePlates)
    check(cat, "plateBorder", "Gold nameplate borders", "Show the gold outline on accessible nameplate health bars.", updatePlates)
    check(cat, "plateHealthText", "Nameplate health percentage", "Show health percentage when the game makes health values available.", updatePlates)
    check(cat, "plateTarget", "Highlight targeted nameplate", "Show a gold line on your current target's nameplate.", updatePlates)
    check(cat, "plateFocus", "Mark focus nameplate", "Mark your focus on accessible nameplates.", updatePlates)
    check(cat, "plateTargetOfTarget", "Show nameplate target", "Show who each visible unit is targeting, when the game provides it.", updatePlates)
    check(cat, "plateCast", "Theme nameplate cast bars", "Use a flat fill and gold edge while keeping the game's cast and interrupt indicators.", updatePlates)
    check(cat, "plateAuras", "Auras on nameplates", "Show selected helpful or harmful effects on accessible nameplates.", updatePlates)
    slide(cat, "plateAuraSize", "Nameplate aura size", "Size of aura icons on accessible nameplates.", 12, 24, 1, tostring, updatePlates)
    slide(cat, "plateAuraCount", "Nameplate aura count", "Maximum number of matching harmful effects shown.", 1, 5, 1, tostring, updatePlates)
    check(cat, "plateAuraTimers", "Nameplate aura timers", "Show remaining time when the game provides an aura's expiration.", updatePlates)
    button(layout, "Nameplate aura tracking", "Configure", function()
        local healing = ns.modules.healing
        if healing and healing.ShowPlateAuraConfig then healing:ShowPlateAuraConfig() end
    end, "Choose helpful or harmful effects, or a list of spell IDs.")
    cvarCheck(cat, "nameplateShowEnemies", "Show enemy nameplates")
    cvarCheck(cat, "nameplateShowFriends", "Show friendly nameplates")
    cvarCheck(cat, "nameplateMotion", "Stack nameplates")
    cvarSlider(cat, "nameplateGlobalScale", "Nameplate size", "Scale nameplates using the game's own setting.", 0.5, 2, 0.05)

    header(layout, "Look")
    slide(cat, "edge", "Gold edge strength", "How strong the thin gold edge around everything is.", 0.15, 1, 0.05, pct, ns.Restyle)
    slide(cat, "dark", "Panel darkness", "How dark the panels behind things are.", 0.4, 1, 0.02, pct, ns.Restyle)
    check(cat, "xpText", "Numbers on the XP bar", "Always show the numbers; otherwise only when you hover it.", function()
        local m = ns.modules.xpbar
        if m and m.built then m:Update() end
    end)
    check(cat, "microFade", "Fade the micro menu and bags", "They fade back until you mouse over them.")
    check(cat, "microLabels", "Show micro menu labels", "Show text next to the custom icons; otherwise hover an icon for its name. After a /reload.", needsReload)
    header(layout, "Damage meter")
    check(cat, "meterInstanceOpen", "Open Damage Done in instances", "Expand the main meter and switch it to Damage Done when entering a dungeon or raid.")
    check(cat, "meterInstanceReset", "Reset meter on instance entry", "Clear all damage meter sessions when entering a dungeon or raid. Reloading inside does not reset them.")
    header(layout, "Micro menu layout")
    check(cat, "microFit", "Fit micro menu beside XP bar", "Fill the space to the left of the XP bar. Turn off to use the button width and height sliders. After a /reload.", needsReload)
    slide(cat, "microColumns", "Columns", "Number of columns; rows adjust automatically. After a /reload.", 1, 12, 1, tostring, needsReload)
    slide(cat, "microWidth", "Button width", "Width of each cell. After a /reload.", 45, 150, 1, tostring, needsReload)
    slide(cat, "microHeight", "Button height", "Height of each cell. After a /reload.", 30, 70, 1, tostring, needsReload)
    slide(cat, "microGap", "Button spacing", "Space between cells. After a /reload.", 0, 12, 1, tostring, needsReload)
    slide(cat, "microIcon", "Icon size", "Size of the icon within its cell. After a /reload.", 18, 48, 1, tostring, needsReload)
    slide(cat, "microScale", "Menu scale", "Scale the whole menu. After a /reload.", 0.5, 1.5, 0.05, pct, needsReload)
    check(cat, "hideBagBar", "Hide the bag bar", "Hide the on-screen bag buttons; your existing bag key binding still opens the inventory. After a /reload.", needsReload)
    check(cat, "noGameMenu", "No game menu button", "Takes the game menu button off the micro menu (Esc still opens it; frame rate and latency are on the minimap). After a /reload.", needsReload)
    slide(cat, "mapSize", "Minimap size", "How big the square minimap is (after a /reload).", 100, 320, 10,
        function(v) return tostring(math.floor(v)) end, needsReload)

    header(layout, "Where things sit")
    button(layout, "Move UI elements", "Move mode", function()
        if SettingsPanel and SettingsPanel.Close then pcall(SettingsPanel.Close, SettingsPanel) end
        ns.ToggleMoveMode(true)
    end, "Drag everything where you want it. Also /fui move.")
    button(layout, "Reset UI positions", "Reset", ns.ResetPositions, "Every piece back where it started. Also /fui reset.")

    if layout and layout.AddInitializer and CreateSettingsButtonInitializer then
        layout:AddInitializer(CreateSettingsButtonInitializer("Forever UI", "Open settings", function()
            if SettingsPanel and SettingsPanel.Close then pcall(SettingsPanel.Close, SettingsPanel) end
            ns.OpenOptions()
        end, "Open the Forever UI settings window.", false))
    end
    Settings.RegisterAddOnCategory(cat)
end

local function control(parent, text, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 26)
    ns.Panel(b, { edge = 0.8 })
    b.text = ns.Text(b, 11, ns.C.bright)
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 0.85, 0.48, 0.12)
    return b
end

local function buildWindow()
    local f = CreateFrame("Frame", "ForeverUISettingsWindow", UIParent)
    f:SetSize(760, 540)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    ns.RememberWindow(f, "settings")
    ns.Panel(f, { alpha = 1.1, edge = 1 })
    local title = ns.Text(f, 17, ns.C.bright)
    title:SetPoint("TOPLEFT", 18, -16)
    title:SetText("Forever UI")
    local close = control(f, "X", 28)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() f:Hide() end)
    local heading = ns.Text(f, 16, ns.C.bright)
    heading:SetPoint("TOPLEFT", 192, -55)
    local subtitle = ns.Text(f, 10, ns.C.muted)
    subtitle:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -5)
    subtitle:SetWidth(535)
    subtitle:SetJustifyH("LEFT")
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 190, -96)
    content:SetSize(550, 400)
    f.content, f.heading, f.subtitle = content, heading, subtitle
    f.tabs, f.rows, f.offset, f.selected = {}, {}, 0, 1
    -- the list glides like the Encyclopedia lists (see E.SmoothList below)
    local function wheel(_, delta)
        local E = ns.Encyclopedia
        if f.smooth and E then E.SmoothWheel(f.smooth, delta) return end
        f.offset = f.offset - delta
        f:Render()
    end
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", wheel)
    for i, section in ipairs(sections) do
        local tab = control(f, section.name, 160)
        tab:SetPoint("TOPLEFT", 15, -56 - (i - 1) * 35)
        tab:SetScript("OnClick", function() f.selected, f.offset = i, 0; f:Render() end)
        f.tabs[i] = tab
    end
    for i = 1, 10 do -- 9 visible plus a spare for smooth scrolling
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(550, 42)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * 44)
        row:EnableMouse(true)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", wheel)
        row.name = ns.Text(row, 12)
        row.name:SetPoint("TOPLEFT", 8, -3)
        row.name:SetWidth(352)
        row.name:SetJustifyH("LEFT")
        row.description = ns.Text(row, 9, ns.C.muted)
        row.description:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
        row.description:SetWidth(352)
        row.description:SetHeight(22)
        row.description:SetJustifyH("LEFT")
        row.description:SetJustifyV("TOP")
        row.action = control(row, "", 100)
        row.action:SetPoint("RIGHT", -18, 0)
        row.minus = control(row, "-", 26)
        row.minus:SetPoint("RIGHT", -121, 0)
        row.plus = control(row, "+", 26)
        row.plus:SetPoint("RIGHT", -18, 0)
        row.value = ns.Text(row, 11, ns.C.bright)
        row.value:SetPoint("RIGHT", row.plus, "LEFT", -4, 0)
        row.value:SetWidth(65)
        row.value:SetJustifyH("CENTER")
        for _, b in ipairs({ row.action, row.minus, row.plus }) do
            b:EnableMouseWheel(true)
            b:SetScript("OnMouseWheel", wheel)
            b:SetScript("OnEnter", function(self)
                if row.entry and row.entry.tooltip and GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(row.entry.name, 1, 0.82, 0)
                    GameTooltip:AddLine(row.entry.tooltip, 1, 1, 1, true)
                    GameTooltip:Show()
                end
            end)
            b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        end
        row.action:SetScript("OnClick", function()
            local e = row.entry
            if not e then return end
            if e.kind == "check" then e.set(not e.get()) else e.run() end
            f:Render()
        end)
        local function adjust(direction)
            local e = row.entry
            if not e then return end
            local v = math.max(e.low, math.min(e.high, e.get() + direction * e.step))
            e.set(v)
            f:Render()
        end
        row.minus:SetScript("OnClick", function() adjust(-1) end)
        row.plus:SetScript("OnClick", function() adjust(1) end)
        row:SetScript("OnEnter", function(self)
            if row.entry and row.entry.tooltip and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(row.entry.name, 1, 0.82, 0)
                GameTooltip:AddLine(row.entry.tooltip, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        f.rows[i] = row
    end
    -- a wheel notch glides one row, the scroll bar drags by pixel, rows clip
    local E = ns.Encyclopedia
    if E and E.SmoothList then
        f.smooth = E.SmoothList("settings", { pane = content, rows = f.rows, step = 44, top = 0, refresh = function() f:Render() end })
        f.scrollbar = f.smooth.scrollbar
    else
        f.scrollbar = ns.ListScrollbar(content, function(value) f.offset = value; f:Render() end)
    end
    local hint = ns.Text(f, 10, ns.C.muted)
    hint:SetPoint("BOTTOMLEFT", 198, 16)
    f.hint = hint
    function f:Render()
        local section = sections[self.selected]
        if not section then return end
        self.offset = math.max(0, math.min(self.offset, math.max(0, #section.entries - #self.rows)))
        if self.smooth then self.offset = ns.Encyclopedia.SmoothSync(self.smooth, self.offset, #section.entries)
        else ns.UpdateListScrollbar(self.scrollbar, self.offset, math.max(0, #section.entries - #self.rows)) end
        heading:SetText(section.name)
        subtitle:SetText(section.description or "")
        for i, tab in ipairs(self.tabs) do
            tab.fuiPanel.bright = i == self.selected
            ns.PaintPanel(tab)
        end
        for i, row in ipairs(self.rows) do
            local e = section.entries[i + self.offset]
            row.entry = e
            row:SetShown(e ~= nil)
            if e then
                row.name:SetText(e.name)
                row.description:SetText(e.tooltip or "")
                local numeric = e.kind == "number"
                row.action:SetShown(not numeric)
                row.minus:SetShown(numeric); row.plus:SetShown(numeric); row.value:SetShown(numeric)
                if numeric then
                    local v = e.get()
                    row.value:SetText(e.format and e.format(v) or tostring(v))
                elseif e.kind == "check" then
                    row.action.text:SetText(e.get() and "On" or "Off")
                    row.action.fuiPanel.bright = e.get()
                    ns.PaintPanel(row.action)
                else
                    row.action.text:SetText(e.caption)
                    row.action.fuiPanel.bright = false
                    ns.PaintPanel(row.action)
                end
            end
        end
        hint:SetText(#section.entries > #self.rows and ("Scroll for more  |  " .. (self.offset + 1) .. "–" .. math.min(#section.entries, self.offset + #self.rows) .. " of " .. #section.entries) or "Hover over an option for details.")
    end
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "ForeverUISettingsWindow") end
    f:Hide()
    return f
end

function ns.OpenOptions()
    if not category then ns.SetupOptions() end
    if not category then ns.Print("Settings are unavailable right now."); return end
    if not window then window = buildWindow(); ns.optionsWindow = window end
    window:Render()
    window:Show()
end

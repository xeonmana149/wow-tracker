-- Secure group frames with per-character click-casting bindings.
local _, ns = ...
local KEYS, ORDER = {}, {}
local MODS = { "", "shift-", "ctrl-", "alt-", "ctrl-shift-", "alt-shift-", "alt-ctrl-", "alt-ctrl-shift-" }
local BUTTONS = { "left", "right", "middle", "button4", "button5" }
local ROLE_ICONS = {
    TANK = "Interface\\AddOns\\ForeverUI\\Art\\heal-role-tank.tga",
    DAMAGER = "Interface\\AddOns\\ForeverUI\\Art\\heal-role-damage.tga",
    HEALER = "Interface\\AddOns\\ForeverUI\\Art\\heal-role-healer.tga",
}
for _, modifier in ipairs(MODS) do
    for i, button in ipairs(BUTTONS) do
        local key = modifier .. button
        KEYS[key] = { modifier .. "type" .. i, modifier .. "spell" .. i,
            modifier .. "item" .. i, modifier .. "macro" .. i }
        ORDER[#ORDER + 1] = key
    end
end

local function parseAction(value)
    if type(value) ~= "string" or value == "" then return end
    local simple = value:lower()
    if simple == "target" or simple == "focus" or simple == "assist" or simple == "togglemenu" then return simple end
    local prefix, argument = value:match("^(%a+):%s*(.-)%s*$")
    if prefix and argument ~= "" then
        prefix = prefix:lower()
        if prefix == "spell" or prefix == "item" or prefix == "macro" then return prefix, argument end
    end
    return "spell", value
end

local m = ns.Module("healing", "Healing frames", function(self)
    self.rows = {}
    local timer = CreateFrame("Frame", nil, UIParent)
    local elapsed = 0
    timer:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.5 then elapsed = 0; self:UpdateRanges() end
    end)
    self.rangeTimer = timer
    ns.On("PLAYER_TARGET_CHANGED", function() self:UpdateUnits("target") end)
    ns.On("PLAYER_FOCUS_CHANGED", function() self:UpdateUnits("focus") end)
    ns.OnOptional("ROLE_CHANGED_INFORM", function() self:UpdateUnits() end)
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_ROLES_ASSIGNED", "SPELLS_CHANGED", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION", "UNIT_NAME_UPDATE", "UNIT_CONNECTION", "UNIT_AURA", "UNIT_FLAGS", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_THREAT_SITUATION_UPDATE", "INCOMING_RESURRECT_CHANGED" }) do
        ns.On(event, function(_, unit)
            if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_HEAL_PREDICTION" or event == "UNIT_NAME_UPDATE" or event == "UNIT_CONNECTION" or event == "UNIT_AURA" or event == "UNIT_FLAGS" or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" or event == "UNIT_THREAT_SITUATION_UPDATE" or event == "INCOMING_RESURRECT_CHANGED" then
                self:UpdateUnits(unit)
            else
                self:Refresh()
            end
        end)
    end
    -- Some clients do not expose both absorb events; keep the rest of the
    -- healing module available if an optional event is unsupported.
    for _, event in ipairs({ "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED" }) do
        ns.OnOptional(event, function(_, unit) self:UpdateUnits(unit) end)
    end
    self:Refresh()
end)

local function updateRange(r)
    local inRange = true
    if type(UnitInRange) == "function" then
        local ok, yes, checked = pcall(UnitInRange, r.unit)
        if ok and not ns.Secret(yes) and not ns.Secret(checked) and checked and not yes then inRange = false end
    end
    r.bar:SetAlpha(inRange and 1 or 0.45)
    r.predict:SetAlpha(r.hasPrediction and (inRange and 1 or 0.45) or 0)
    r.absorb:SetAlpha(r.hasAbsorb and (inRange and 1 or 0.45) or 0)
    if r.power then r.power:SetAlpha(r.hasPower and (inRange and 1 or 0.45) or 0) end
end

function m:UpdateRanges()
    local now = type(GetTime) == "function" and GetTime()
    if ns.Secret(now) or type(now) ~= "number" then now = nil end
    for _, r in ipairs(self.rows) do
        if not r.IsVisible or r:IsVisible() then
            updateRange(r)
            for i, label in ipairs(r.buffTimes or {}) do
                local expiration = r.buffs[i].fuiExpiration
                if ns.Opt("healAuraTimers") and now and type(expiration) == "number" and expiration > now then
                    local remaining = expiration - now
                    label:SetText(remaining >= 60 and (math.ceil(remaining / 60) .. "m") or tostring(math.ceil(remaining)))
                    label:Show()
                else label:Hide() end
            end
        end
    end
end

local function characterKey()
    return ns.HealingCharacterKey()
end

local function auraTooltipData(unit, index, filter)
    if not (C_TooltipInfo and type(C_TooltipInfo.GetUnitAura) == "function") then return false end
    local ok, info = pcall(C_TooltipInfo.GetUnitAura, unit, index, filter)
    if not ok or ns.Secret(info) then return false end
    if info == nil then return true, nil end
    if type(info) ~= "table" then return false end
    return true, info
end

local function addAuraDescription(unit, index, filter, aura, auraName, tooltipInfo)
    local added = false
    if tooltipInfo or (C_TooltipInfo and type(C_TooltipInfo.GetUnitAura) == "function") then
        local ok, info = true, tooltipInfo
        if not info then ok, info = auraTooltipData(unit, index, filter) end
        if ok and not ns.Secret(info) and type(info) == "table" then
            local lines = info.lines
            if not ns.Secret(lines) and type(lines) == "table" then
                for i = 2, math.min(#lines, 5) do
                    local line = lines[i]
                    if not ns.Secret(line) and type(line) == "table" then
                        local text = line.leftText
                        if not ns.Secret(text) and type(text) == "string" and text ~= "" and text ~= auraName then
                            GameTooltip:AddLine("   " .. text, 0.75, 0.75, 0.75, true)
                            added = true
                        end
                    end
                end
            end
        end
    end
    if not added and C_Spell and type(C_Spell.GetSpellDescription) == "function" then
        local id = aura.spellId
        if not ns.Secret(id) and type(id) == "number" then
            local ok, description = pcall(C_Spell.GetSpellDescription, id)
            if ok and not ns.Secret(description) and type(description) == "string" and description ~= "" then
                GameTooltip:AddLine("   " .. description, 0.75, 0.75, 0.75, true)
                added = true
            end
        end
    end
    if not added then GameTooltip:AddLine("   Description unavailable", 0.55, 0.55, 0.55, true) end
end

function m:ShowAuraTooltip(row, onlyFilter, owner)
    if not GameTooltip or type(row) ~= "table" then return end
    GameTooltip:SetOwner(owner or row, "ANCHOR_RIGHT")
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end
    local ok, name = pcall(UnitName, row.unit)
    if not ok or ns.Secret(name) or type(name) ~= "string" or name == "" then name = row.unit end
    GameTooltip:SetText(name, ns.C.bright[1], ns.C.bright[2], ns.C.bright[3])
    local now = type(GetTime) == "function" and GetTime()
    if ns.Secret(now) or type(now) ~= "number" then now = nil end
    for _, section in ipairs({ { "Buffs", "HELPFUL" }, { "Debuffs", "HARMFUL" } }) do
      if not onlyFilter or onlyFilter == section[2] then
        GameTooltip:AddLine(section[1], ns.C.bright[1], ns.C.bright[2], ns.C.bright[3])
        local count, unavailable = 0, false
        do
            for i = 1, 20 do
                local got, aura = false, nil
                if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
                    got, aura = pcall(C_UnitAuras.GetAuraDataByIndex, row.unit, i, section[2])
                end
                local info
                if not got or ns.Secret(aura) or (type(aura) == "table" and (ns.Secret(aura.name) or type(aura.name) ~= "string" or aura.name == "")) then
                    local tooltipOK
                    tooltipOK, info = auraTooltipData(row.unit, i, section[2])
                    if tooltipOK and info and not ns.Secret(info.lines) and type(info.lines) == "table" then
                        local first = info.lines[1]
                        local text = type(first) == "table" and not ns.Secret(first) and first.leftText
                        if not ns.Secret(text) and type(text) == "string" and text ~= "" then aura = { name = text }; got = true end
                    end
                    if not got or ns.Secret(aura) or type(aura) ~= "table" or ns.Secret(aura.name) or type(aura.name) ~= "string" or aura.name == "" then
                        -- A successfully enumerated fallback ends normally on nil;
                        -- an initial denied lookup is not proof of an empty list.
                        if tooltipOK and info == nil and count > 0 then break end
                        unavailable = true; break
                    end
                end
                if aura == nil then break end
                if type(aura) ~= "table" then unavailable = true; break end
                local auraName = aura.name
                if ns.Secret(auraName) or type(auraName) ~= "string" or auraName == "" then
                    unavailable = true
                else
                    local detail = {}
                    local stacks, expires = aura.applications, aura.expirationTime
                    if not ns.Secret(stacks) and type(stacks) == "number" and stacks > 1 then detail[#detail + 1] = stacks .. " stacks" end
                    if now and not ns.Secret(expires) and type(expires) == "number" and expires > now then
                        local seconds = expires - now
                        detail[#detail + 1] = seconds >= 60 and (math.ceil(seconds / 60) .. "m") or (math.ceil(seconds) .. "s")
                    end
                    local suffix = #detail > 0 and ("  (" .. table.concat(detail, ", ") .. ")") or ""
                    local icon = aura.icon
                    local iconText = ""
                    if not ns.Secret(icon) and (type(icon) == "number" or type(icon) == "string") then
                        iconText = "|T" .. tostring(icon) .. ":16:16|t "
                    end
                    GameTooltip:AddLine(iconText .. auraName .. suffix, section[2] == "HARMFUL" and 1 or 0.9,
                        section[2] == "HARMFUL" and 0.55 or 0.9, section[2] == "HARMFUL" and 0.45 or 0.9)
                    addAuraDescription(row.unit, i, section[2], aura, auraName, info)
                    count = count + 1
                end
            end
        end
        if count == 0 and not unavailable then GameTooltip:AddLine("None", 0.6, 0.6, 0.6) end
        if unavailable then GameTooltip:AddLine("Can't read effects right now", 0.6, 0.6, 0.6) end
        if count == 20 then GameTooltip:AddLine("More effects may be present.", 0.6, 0.6, 0.6) end
      end
    end
    GameTooltip:Show()
end

local function makeRow(parent, unit, column, line, friendlyOnly)
    local r = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    r:SetSize(120, 25)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", column * 123, -line * 28)
    r:SetAttribute("unit", unit)
    for i = 1, 5 do r:SetAttribute("*unit" .. i, unit) end
    -- These buttons listen for mouse-up. Do not inherit the action-bar
    -- key-down CVar or mouse-up casts can silently fail.
    r:SetAttribute("useOnKeyDown", false)
    r:SetAttribute("checkselfcast", false)
    r:SetAttribute("checkfocuscast", false)
    r:SetAttribute("checkmouseovercast", false)
    r:RegisterForClicks("AnyUp")
    r:EnableMouse(true)
    if friendlyOnly then
        RegisterStateDriver(r, "visibility", "[@" .. unit .. ",exists,help] show; hide")
    else
        RegisterUnitWatch(r)
    end
    r:SetScript("OnEnter", function(self)
        m:ShowAuraTooltip(self)
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    ns.Panel(r)
    local portraitButton = CreateFrame("Button", nil, r, "SecureActionButtonTemplate")
    portraitButton:SetSize(25, 25)
    portraitButton:SetPoint("RIGHT", r, "LEFT", -3, 0)
    portraitButton:SetAttribute("unit", unit)
    portraitButton:SetAttribute("type1", "target")
    portraitButton:SetAttribute("useOnKeyDown", false)
    portraitButton:RegisterForClicks("LeftButtonUp")
    ns.Panel(portraitButton)
    local portrait = portraitButton:CreateTexture(nil, "ARTWORK")
    portrait:SetPoint("TOPLEFT", 2, -2)
    portrait:SetPoint("BOTTOMRIGHT", -2, 2)
    portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    -- A small, non-interactive badge keeps the portrait's target click intact.
    local roleBadge = portraitButton:CreateTexture(nil, "OVERLAY", nil, 4)
    roleBadge:SetSize(14, 14)
    roleBadge:SetPoint("BOTTOMRIGHT", portraitButton, "BOTTOMRIGHT", 1, -1)
    roleBadge:SetColorTexture(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], 0.85)
    local roleBackground = portraitButton:CreateTexture(nil, "OVERLAY", nil, 5)
    roleBackground:SetPoint("TOPLEFT", roleBadge, "TOPLEFT", 1, -1)
    roleBackground:SetPoint("BOTTOMRIGHT", roleBadge, "BOTTOMRIGHT", -1, 1)
    roleBackground:SetColorTexture(0.08, 0.07, 0.06, 0.96)
    local roleIcon = portraitButton:CreateTexture(nil, "OVERLAY", nil, 6)
    roleIcon:SetPoint("TOPLEFT", roleBackground, "TOPLEFT")
    roleIcon:SetPoint("BOTTOMRIGHT", roleBackground, "BOTTOMRIGHT")
    roleBadge:Hide(); roleBackground:Hide(); roleIcon:Hide()
    portraitButton:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetUnit then GameTooltip:SetUnit(unit) end
            if GameTooltip.AddLine then GameTooltip:AddLine("Left-click to target", 1, 0.82, 0) end
            GameTooltip:Show()
        end
    end)
    portraitButton:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    local absorb = CreateFrame("StatusBar", nil, r)
    absorb:SetPoint("TOPLEFT", 2, -2)
    absorb:SetPoint("BOTTOMRIGHT", -2, 12)
    absorb:SetFrameLevel(r:GetFrameLevel() + 1)
    absorb:SetStatusBarTexture(ns.FLAT)
    absorb:SetStatusBarColor(0.35, 0.65, 0.90, 0.75)
    local predict = CreateFrame("StatusBar", nil, r)
    predict:SetPoint("TOPLEFT", 2, -2)
    predict:SetPoint("BOTTOMRIGHT", -2, 12)
    predict:SetFrameLevel(r:GetFrameLevel() + 2)
    predict:SetStatusBarTexture(ns.FLAT)
    predict:SetStatusBarColor(0.65, 0.91, 0.55, 0.65)
    local bar = CreateFrame("StatusBar", nil, r)
    bar:SetPoint("TOPLEFT", 2, -2)
    bar:SetPoint("BOTTOMRIGHT", -2, 12)
    bar:SetFrameLevel(r:GetFrameLevel() + 3)
    bar:SetStatusBarTexture(ns.FLAT)
    bar:SetStatusBarColor(0.31, 0.68, 0.29, 0.7)
    -- On restricted clients, predicted amounts can be secret values. Anchor
    -- an amount bar to the live health fill and clip it to the frame, so the
    -- values can go straight to the status bar without Lua arithmetic.
    local clip = CreateFrame("Frame", nil, r)
    clip:SetPoint("TOPLEFT", r, "TOPLEFT", 2, -2)
    clip:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -2, 12)
    clip:SetFrameLevel(r:GetFrameLevel() + 4)
    if clip.EnableMouse then clip:EnableMouse(false) end
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    local secretPredict = CreateFrame("StatusBar", nil, clip)
    secretPredict:SetStatusBarTexture(ns.FLAT)
    secretPredict:SetStatusBarColor(0.65, 0.91, 0.55, 0.8)
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if fill then
        secretPredict:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
        secretPredict:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
    end
    secretPredict:Hide()
    for _, part in ipairs({ absorb, predict, bar, secretPredict }) do
        if part.EnableMouse then part:EnableMouse(false) end
    end
    local powerBack = r:CreateTexture(nil, "BACKGROUND")
    powerBack:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 2, 2)
    powerBack:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -2, 2)
    powerBack:SetHeight(8)
    powerBack:SetColorTexture(0.04, 0.04, 0.04, 0.95)
    local power = CreateFrame("StatusBar", nil, r)
    power:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 2, 2)
    power:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -2, 2)
    power:SetHeight(8)
    power:SetFrameLevel(r:GetFrameLevel() + 4)
    power:SetStatusBarTexture(ns.FLAT)
    local powerText = ns.Text(power, 8)
    powerText:SetPoint("CENTER")
    local threat = r:CreateTexture(nil, "OVERLAY", nil, 4)
    threat:SetPoint("TOPLEFT", 1, -1)
    threat:SetPoint("BOTTOMLEFT", 1, 1)
    threat:SetWidth(3)
    threat:SetColorTexture(0.95, 0.27, 0.16, 0)
    local label = ns.Text(bar, 10)
    label:SetPoint("LEFT", 4, 0)
    label:SetWidth(76)
    label:SetJustifyH("LEFT")
    local status = ns.Text(bar, 9, ns.C.muted)
    status:SetPoint("BOTTOMRIGHT", -3, 2)
    local function auraArea(filter, top)
        local area = CreateFrame("Button", nil, r)
        area:SetSize(29, 11)
        area:SetPoint(top and "TOPLEFT" or "BOTTOMLEFT", r, top and "TOPRIGHT" or "BOTTOMRIGHT", 3, top and -1 or 1)
        ns.Panel(area, { alpha = 0.9, edge = 0.65 })
        local mark = area:CreateTexture(nil, "OVERLAY")
        mark:SetPoint("TOPLEFT", 1, -1); mark:SetPoint("BOTTOMLEFT", 1, 1); mark:SetWidth(2)
        if top then mark:SetColorTexture(0.30, 0.75, 0.38, 1) else mark:SetColorTexture(0.95, 0.30, 0.22, 1) end
        area:SetScript("OnEnter", function(self) m:ShowAuraTooltip(r, filter, self) end)
        area:SetScript("OnLeave", function(self) if not self.pinned and GameTooltip then GameTooltip:Hide() end end)
        area:SetScript("OnClick", function(self)
            self.pinned = not self.pinned
            if self.pinned then m:ShowAuraTooltip(r, filter, self) elseif GameTooltip then GameTooltip:Hide() end
        end)
        return area
    end
    local helpful = auraArea("HELPFUL", true)
    local harmful = auraArea("HARMFUL", false)
    local harmfulIcon = harmful:CreateTexture(nil, "ARTWORK")
    harmfulIcon:SetSize(8, 8); harmfulIcon:SetPoint("LEFT", 4, 0); harmfulIcon:Hide()
    local buffs, stacks, times = {}, {}, {}
    for i = 1, 3 do
        local icon = helpful:CreateTexture(nil, "OVERLAY", nil, 3)
        icon:SetSize(8, 8)
        icon:SetPoint("LEFT", 3 + (i - 1) * 8, 0)
        icon:Hide()
        buffs[i] = icon
        local count = ns.Text(helpful, 8)
        count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
        count:Hide()
        stacks[i] = count
        local time = ns.Text(helpful, 8, ns.C.bright)
        time:SetPoint("CENTER", icon, "CENTER")
        time:Hide()
        times[i] = time
    end
    local debuff = r:CreateTexture(nil, "OVERLAY", nil, 3)
    debuff:SetPoint("TOPLEFT", 2, -2)
    debuff:SetPoint("TOPRIGHT", -2, -2)
    debuff:SetHeight(2)
    debuff:SetColorTexture(0, 0, 0, 0)
    if power.EnableMouse then power:EnableMouse(false) end
    r.unit, r.bar, r.label, r.status, r.debuff, r.predict, r.buffs, r.power, r.threat, r.buffStacks, r.buffTimes, r.absorb, r.portraitButton, r.portrait = unit, bar, label, status, debuff, predict, buffs, power, threat, stacks, times, absorb, portraitButton, portrait
    r.secretPredict, r.predictFill = secretPredict, fill
    r.powerText = powerText
    r.roleBadge, r.roleBackground, r.roleIcon = roleBadge, roleBackground, roleIcon
    r.helpfulArea, r.harmfulArea, r.harmfulIcon = helpful, harmful, harmfulIcon
    return r
end

function m:InitialPartyPosition(holder)
    if ns.db.healPartyPositionV1 then return end
    -- Apply this requested move once; later drags remain under the user's control.
    ns.db.healPartyPositionV1 = true
    ns.db.pos.healing = nil
    local uiScale = UIParent:GetEffectiveScale()
    if type(uiScale) ~= "number" or uiScale <= 0 then return end
    for _, name in ipairs({ "PartyFrame", "CompactPartyFrame" }) do
        local party = _G[name]
        if type(party) == "table" and type(party.GetLeft) == "function" and type(party.GetTop) == "function"
            and type(party.GetWidth) == "function" and type(party.GetHeight) == "function"
            and type(party.GetEffectiveScale) == "function" and not (party.IsForbidden and party:IsForbidden()) then
            local ok, left, top, width, height, scale = pcall(function()
                return party:GetLeft(), party:GetTop(), party:GetWidth(), party:GetHeight(), party:GetEffectiveScale()
            end)
            if ok and not ns.Secret(left) and not ns.Secret(top) and not ns.Secret(width) and not ns.Secret(height) and not ns.Secret(scale)
                and type(left) == "number" and type(top) == "number" and type(width) == "number" and width > 0
                and type(height) == "number" and height > 0 and type(scale) == "number" and scale > 0 then
                local size = math.max(0.7, math.min(1.5, tonumber(ns.Opt("healScale")) or 1))
                local frameScale = holder:GetEffectiveScale()
                if ns.Secret(frameScale) or type(frameScale) ~= "number" or frameScale <= 0 then return end
                local holderScale = frameScale * size / uiScale
                local rowHeight = math.max(22, math.min(40, tonumber(ns.Opt("healHeight")) or 25))
                local portraitWidth = math.min(28, rowHeight) + 3
                ns.db.pos.healing = { x = left * scale / uiScale + (portraitWidth + holder:GetWidth() / 2) * holderScale,
                    y = top * scale / uiScale - holder:GetHeight() * holderScale / 2 }
                return
            end
        end
    end
end

function m:Build()
    if self.holder or type(RegisterUnitWatch) ~= "function" or type(RegisterStateDriver) ~= "function" then return end
    local f = CreateFrame("Frame", "ForeverUIHealing", UIParent, "SecureHandlerStateTemplate")
    f:SetSize(120, 8)
    self:InitialPartyPosition(f)
    ns.Place(f, "healing", "Healing frames", { "TOPLEFT", "TOPLEFT", 32, -180 }, nil,
        { scaleOption = "healScale", scaleMin = 0.7, scaleMax = 1.5, onScale = function() m:Refresh() end })
    -- The invisible anchor carries the secure unit buttons; only the small
    -- corner handle accepts movement input.
    f:SetMovable(true)
    f:EnableMouse(false)
    local handle = CreateFrame("Button", nil, f)
    handle:SetSize(14, 14)
    handle:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 1)
    ns.Panel(handle, { alpha = 0.9, edge = 0.7 })
    -- A small gold four-way grip, built from the same flat textures and
    -- palette used by the other Forever UI controls.
    handle.fuiGrip = {}
    for _, shape in ipairs({ { 8, 1, 0, 0 }, { 1, 8, 0, 0 },
        { 2, 2, -3, 0 }, { 2, 2, 3, 0 }, { 2, 2, 0, 3 }, { 2, 2, 0, -3 } }) do
        local part = handle:CreateTexture(nil, "OVERLAY")
        part:SetSize(shape[1], shape[2])
        part:SetPoint("CENTER", shape[3], shape[4])
        part:SetColorTexture(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3], 1)
        handle.fuiGrip[#handle.fuiGrip + 1] = part
    end
    local hover = handle:CreateTexture(nil, "HIGHLIGHT")
    hover:SetPoint("TOPLEFT", 1, -1)
    hover:SetPoint("BOTTOMRIGHT", -1, 1)
    hover:SetColorTexture(1, 0.85, 0.48, 0.12)
    handle.fuiLock = {}
    for _, shape in ipairs({ { 6, 4, 0, -2 }, { 1, 3, -2, 1 },
        { 1, 3, 2, 1 }, { 5, 1, 0, 3 } }) do
        local part = handle:CreateTexture(nil, "OVERLAY", nil, 2)
        part:SetSize(shape[1], shape[2])
        part:SetPoint("CENTER", shape[3], shape[4])
        part:SetColorTexture(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3], 1)
        handle.fuiLock[#handle.fuiLock + 1] = part
    end
    handle.fuiLockMark = handle.fuiLock[1]
    local function updateLockAppearance()
        local locked = ns.db.healMoveLocked and true or false
        for _, part in ipairs(handle.fuiLock) do part:SetShown(locked) end
        for _, part in ipairs(handle.fuiGrip) do part:SetShown(not locked) end
    end
    updateLockAppearance()
    self.moveHandle = handle
    handle:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(ns.db.healMoveLocked and "Healing frames locked. Right-click to unlock."
                or "Hold to move healing frames. Right-click to lock.")
            GameTooltip:Show()
        end
    end)
    handle:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    local function finishDrag()
        if not f.fuiDragging then return end
        local x, y = f:GetCenter()
        f:StopMovingOrSizing()
        f.fuiDragging = nil
        local frameScale, uiScale = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
        if type(x) == "number" and type(y) == "number" and type(frameScale) == "number"
            and type(uiScale) == "number" and uiScale > 0 then
            local ratio = frameScale / uiScale
            ns.db.pos.healing = { x = x * ratio, y = y * ratio }
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
            if f.SetUserPlaced then f:SetUserPlaced(false) end
        else
            ns.Print("couldn't save the healing frame position; try again.")
        end
    end
    handle:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or ns.db.healMoveLocked or ns.moving or (InCombatLockdown and InCombatLockdown()) then return end
        self.holdToken = (self.holdToken or 0) + 1
        local token = self.holdToken
        self.holding = true
        C_Timer.After(0.45, function()
            if not self.holding or self.holdToken ~= token or ns.db.healMoveLocked or ns.moving
                or (InCombatLockdown and InCombatLockdown()) or not self:IsShown()
                or (IsMouseButtonDown and not IsMouseButtonDown("LeftButton")) then return end
            f:StartMoving()
            f.fuiDragging = true
        end)
    end)
    handle:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            self.holding = false
            if f.fuiDragging then ns.WhenSafe(finishDrag) end
            ns.db.healMoveLocked = not ns.db.healMoveLocked
            updateLockAppearance()
            if GameTooltip and GameTooltip:IsShown() then
                GameTooltip:SetText(ns.db.healMoveLocked and "Healing frames locked. Right-click to unlock."
                    or "Hold to move healing frames. Right-click to lock.")
            end
            return
        end
        if button ~= "LeftButton" then return end
        self.holding = false
        if f.fuiDragging then ns.WhenSafe(finishDrag) end
    end)
    handle:SetScript("OnHide", function(self)
        self.holding = false
        if f.fuiDragging then ns.WhenSafe(finishDrag) end
    end)
    local party = CreateFrame("Frame", nil, f, "SecureHandlerStateTemplate")
    local raid = CreateFrame("Frame", nil, f, "SecureHandlerStateTemplate")
    self.partyHolder, self.raidHolder = party, raid
    for _, child in ipairs({ party, raid }) do child:SetSize(1, 1); child:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0) end
    self.visibilityDriver = ns.Opt("healSolo") and "show" or "[group] show; hide"
    RegisterStateDriver(f, "visibility", self.visibilityDriver)
    RegisterStateDriver(party, "visibility", "[group:raid] hide; show")
    RegisterStateDriver(raid, "visibility", "[group:raid] show; hide")
    for i = 0, 4 do self.rows[#self.rows + 1] = makeRow(party, i == 0 and "player" or "party" .. i, 0, i) end
    for i = 1, 40 do self.rows[#self.rows + 1] = makeRow(raid, "raid" .. i, math.floor((i - 1) / 8), (i - 1) % 8) end
    if ns.Opt("healPets") then
        self.rows[#self.rows + 1] = makeRow(party, "pet", 1, 0)
        for i = 1, 4 do self.rows[#self.rows + 1] = makeRow(party, "partypet" .. i, 1, i) end
        for i = 1, 40 do self.rows[#self.rows + 1] = makeRow(raid, "raidpet" .. i, 5 + math.floor((i - 1) / 8), (i - 1) % 8) end
    end
    local targets = CreateFrame("Frame", nil, f, "SecureHandlerStateTemplate")
    targets:SetSize(120, 53)
    targets:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 3)
    self.targetHolder = targets
    self.targetDriver = ns.Opt("healTargets") and "show" or "hide"
    RegisterStateDriver(targets, "visibility", self.targetDriver)
    self.rows[#self.rows + 1] = makeRow(targets, "target", 0, 0, true)
    self.rows[#self.rows + 1] = makeRow(targets, "focus", 0, 1, true)
    self.holder = f
    local dispel = ns.modules.dispel
    if dispel and dispel.AttachHealing then dispel:AttachHealing() end
end

local DISPEL_TYPES = { "Magic", "Curse", "Poison", "Disease" }

-- One secure button per unit maps different learned spells to mouse buttons.
-- Aura updates only change the visual indicator, not its combat actions.
function m:ConfigureDispelButtons()
    if InCombatLockdown and InCombatLockdown() then return end
    local dispel = ns.modules.dispel
    local spells = ns.Opt("healDispelButtons") and dispel and dispel.built and dispel.spells or {}
    local groups, byName = {}, {}
    for _, kind in ipairs(DISPEL_TYPES) do
        local name = spells[kind]
        if type(name) == "string" and name ~= "" then
            local group = byName[name]
            if not group then group = { spell = name, kinds = {} }; byName[name] = group; groups[#groups + 1] = group end
            group.kinds[#group.kinds + 1] = kind
        end
    end
    self.dispelGroups = groups
    for _, r in ipairs(self.rows) do
        if #groups > 0 and not r.dispelButton then
            local button = CreateFrame("Button", nil, r.portraitButton, "SecureActionButtonTemplate")
            button:SetSize(12, 12)
            button:SetAttribute("unit", r.unit)
            button:SetAttribute("useOnKeyDown", false)
            button:RegisterForClicks("AnyUp")
            ns.Panel(button, { alpha = 0.95, edge = 0.8 })
            button.fill = button:CreateTexture(nil, "ARTWORK")
            button.fill:SetAllPoints(button)
            button.label = ns.Text(button, 8)
            button.label:SetPoint("CENTER")
            button:SetScript("OnEnter", function(self)
                if GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText("Dispel")
                    for i, group in ipairs(self.fuiGroups or {}) do
                        local clicks = { "Left", "Right", "Middle", "Button 4" }
                        GameTooltip:AddLine(clicks[i] .. ": " .. group.spell .. " (" .. table.concat(group.kinds, ", ") .. ")", 1, 0.82, 0)
                    end
                    GameTooltip:Show()
                end
            end)
            button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            r.dispelButton = button
        end
        local button = r.dispelButton
        if button then
            button.fuiGroups = groups
            for i = 1, 4 do
                local group = groups[i]
                button:SetAttribute("type" .. i, group and "spell" or nil)
                button:SetAttribute("spell" .. i, group and group.spell or nil)
            end
            button.label:SetText("D")
            button:SetShown(#groups > 0)
        end
    end
end

-- Secure unit buttons may only be resized or re-anchored outside combat.
function m:ApplyLayout()
    if not self.holder or (InCombatLockdown and InCombatLockdown()) then return end
    local width = math.max(100, math.min(200, tonumber(ns.Opt("healWidth")) or 120))
    local height = math.max(22, math.min(40, tonumber(ns.Opt("healHeight")) or 25))
    local perColumn = math.floor(math.max(5, math.min(10, tonumber(ns.Opt("healRaidRows")) or 8)))
    local dispelCount = #(self.dispelGroups or {})
    local dispelGap = dispelCount > 0 and 13 or 0
    local signature = width .. ":" .. height .. ":" .. perColumn .. ":" .. dispelCount
    if self.layoutSignature == signature then return end
    self.holder:SetWidth(width)
    if self.targetHolder then self.targetHolder:SetSize(width, 2 * height + 3 + dispelGap) end
    for _, child in ipairs({ self.partyHolder, self.raidHolder }) do
        child:ClearAllPoints()
        child:SetPoint("TOPLEFT", self.holder, "TOPLEFT", 0, -dispelGap)
    end
    local raidColumns = math.ceil(40 / perColumn)
    for _, r in ipairs(self.rows) do
        local unit = r.unit
        local raidIndex = unit:match("^raid(%d+)$")
        local raidPetIndex = unit:match("^raidpet(%d+)$")
        local partyIndex = unit:match("^party(%d+)$")
        local partyPetIndex = unit:match("^partypet(%d+)$")
        local column, line = 0, 0
        if raidIndex or raidPetIndex then
            local index = tonumber(raidIndex or raidPetIndex) - 1
            column = math.floor(index / perColumn) + (raidPetIndex and raidColumns or 0)
            line = index % perColumn
        elseif partyIndex or partyPetIndex then
            line = tonumber(partyIndex or partyPetIndex)
            column = partyPetIndex and 1 or 0
        elseif unit == "pet" then column = 1
        elseif unit == "focus" then line = 1 end
        local portraitSize = math.min(28, height)
        r.portraitButton:SetSize(portraitSize, portraitSize)
        r:SetSize(width, height)
        r.secretPredict:SetWidth(width - 4)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", r:GetParent(), "TOPLEFT", column * (width + portraitSize + 38), -line * (height + 3 + dispelGap))
        r.label:SetWidth(width - 44)
        if r.dispelButton and dispelCount > 0 then
            local button = r.dispelButton
            button:SetSize(portraitSize, 11)
            button:ClearAllPoints()
            button:SetPoint("BOTTOMLEFT", r.portraitButton, "TOPLEFT", 0, 1)
        end
    end
    self.layoutSignature = signature
end

-- Keep native unit buttons intact while preventing invisible party buttons
-- from intercepting clicks. All changes are deferred until out of combat.
function m:UpdatePartyReplacement()
    if InCombatLockdown and InCombatLockdown() then return end
    self.nativeParties = self.nativeParties or {}
    local replace = ns.Opt("healReplaceParty")
    for _, name in ipairs({ "PartyFrame", "CompactPartyFrame" }) do
        local party = _G[name]
        if type(party) == "table" and not (party.IsForbidden and party:IsForbidden()) then
            local saved = self.nativeParties[party]
            if replace then
                if not saved then saved = { buttons = {} }; self.nativeParties[party] = saved end
                if saved.alpha == nil and party.GetAlpha then saved.alpha = party:GetAlpha() end
                if party.SetAlpha then party:SetAlpha(0) end
                for i = 1, name == "PartyFrame" and 4 or 5 do
                    local member = type(party.GetPartyMemberFrame) == "function" and party:GetPartyMemberFrame(i)
                        or party["MemberFrame" .. i] or _G[name .. "Member" .. i]
                    if name == "PartyFrame" and not member then member = _G["PartyMemberFrame" .. i] end
                    if type(member) == "table" and type(member.EnableMouse) == "function"
                        and not (member.IsForbidden and member:IsForbidden()) then
                        if saved.buttons[member] == nil then
                            local enabled = type(member.IsMouseEnabled) == "function" and member:IsMouseEnabled()
                            if enabled == nil then enabled = true end
                            saved.buttons[member] = enabled and true or false
                        end
                        member:EnableMouse(false)
                    end
                end
            elseif saved then
                if saved.alpha ~= nil and party.SetAlpha then party:SetAlpha(saved.alpha) end
                for member, enabled in pairs(saved.buttons) do
                    if type(member.EnableMouse) == "function" and not (member.IsForbidden and member:IsForbidden()) then member:EnableMouse(enabled) end
                end
                self.nativeParties[party] = nil
            end
        end
    end
end

function m:UpdateUnits(unit)
    for _, r in ipairs(self.rows) do
        if not unit or unit == r.unit then
            r.hasPrediction = false
            r.hasAbsorb = false
            if type(SetPortraitTexture) == "function" then pcall(SetPortraitTexture, r.portrait, r.unit) end
            local c
            local role
            if type(UnitGroupRolesAssigned) == "function" and not r.unit:find("pet") then
                local roleOK, value = pcall(UnitGroupRolesAssigned, r.unit)
                if roleOK and not ns.Secret(value) and type(value) == "string" then role = value end
            end
            local icon = role and ROLE_ICONS[role]
            if icon then
                r.roleIcon:SetTexture(icon)
                r.roleBadge:Show(); r.roleBackground:Show(); r.roleIcon:Show()
            else
                r.roleBadge:Hide(); r.roleBackground:Hide(); r.roleIcon:Hide()
            end
            if ns.Opt("healClassColor") and type(UnitClass) == "function" then
                local classOK, _, token = pcall(UnitClass, r.unit)
                if classOK and not ns.Secret(token) and type(token) == "string" and type(RAID_CLASS_COLORS) == "table" then c = RAID_CLASS_COLORS[token] end
            end
            if ns.Opt("healRoleColor") then
                if role == "TANK" then c = { r = 0.86, g = 0.22, b = 0.18 }
                elseif role == "HEALER" then c = { r = 0.95, g = 0.78, b = 0.25 } end
            end
            if type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
                r.bar:SetStatusBarColor(c.r, c.g, c.b, 0.7)
            else r.bar:SetStatusBarColor(0.31, 0.68, 0.29, 0.7) end
            local hasPower = false
            local powerPercent = ""
            if ns.Opt("healPower") and type(UnitPower) == "function" and type(UnitPowerMax) == "function" then
                local okValue, value = pcall(UnitPower, r.unit)
                local okMax, maximum = pcall(UnitPowerMax, r.unit)
                if okValue and okMax and not ns.Secret(value) and not ns.Secret(maximum)
                    and type(value) == "number" and type(maximum) == "number" and maximum > 0 then
                    r.power:SetMinMaxValues(0, maximum); r.power:SetValue(value); hasPower = true
                    powerPercent = math.floor(value * 100 / maximum + 0.5) .. "%"
                elseif okValue and okMax and (ns.Secret(value) or ns.Secret(maximum)) then
                    hasPower = pcall(function() r.power:SetMinMaxValues(0, maximum); r.power:SetValue(value) end)
                end
                local color
                if type(UnitPowerType) == "function" then
                    local okType, index, token = pcall(UnitPowerType, r.unit)
                    if okType and not ns.Secret(index) and not ns.Secret(token) and type(PowerBarColor) == "table" then
                        color = PowerBarColor[token] or PowerBarColor[index]
                    end
                end
                if type(color) == "table" and type(color.r) == "number" and type(color.g) == "number" and type(color.b) == "number" then
                    r.power:SetStatusBarColor(color.r, color.g, color.b, 1)
                else r.power:SetStatusBarColor(0.25, 0.45, 0.85, 1) end
            end
            r.hasPower = hasPower
            r.powerText:SetText(powerPercent)
            local hasThreat = false
            if ns.Opt("healThreat") and type(UnitThreatSituation) == "function" then
                local okThreat, level = pcall(UnitThreatSituation, r.unit)
                hasThreat = okThreat and not ns.Secret(level) and type(level) == "number" and level >= 2
            end
            r.threat:SetColorTexture(0.95, 0.27, 0.16, hasThreat and 1 or 0)
            local ok, name = pcall(UnitName, r.unit)
            if ok and ns.Secret(name) then
                local shown = pcall(r.label.SetText, r.label, name)
                if not shown then r.label:SetText(r.unit) end
            elseif ok and type(name) == "string" then r.label:SetText(name)
            else r.label:SetText(r.unit) end
            local status = ""
            if type(UnitHealth) == "function" and type(UnitHealthMax) == "function" then
                local healthOK, health = pcall(UnitHealth, r.unit)
                local maxOK, maximum = pcall(UnitHealthMax, r.unit)
                if healthOK and maxOK and not ns.Secret(health) and not ns.Secret(maximum)
                    and type(health) == "number" and type(maximum) == "number" and maximum > 0 then
                    r.bar:SetMinMaxValues(0, maximum)
                    r.bar:SetValue(health)
                    if ns.Opt("healDeficit") then
                        local missing = math.max(0, maximum - health)
                        status = missing > 0 and ("-" .. math.floor(missing + 0.5)) or ""
                    else
                        status = math.floor(health * 100 / maximum + 0.5) .. "%"
                    end
                    local incoming = 0
                    if type(UnitGetIncomingHeals) == "function" then
                        local ok, value = pcall(UnitGetIncomingHeals, r.unit)
                        if ok and not ns.Secret(value) and type(value) == "number" then incoming = math.max(0, value) end
                    end
                    local shields = 0
                    if ns.Opt("healAbsorbs") then
                        if type(UnitGetTotalHealAbsorbs) == "function" then
                            local got, value = pcall(UnitGetTotalHealAbsorbs, r.unit)
                            if got and not ns.Secret(value) and type(value) == "number" then incoming = math.max(0, incoming - value) end
                        end
                        if type(UnitGetTotalAbsorbs) == "function" then
                            local got, value = pcall(UnitGetTotalAbsorbs, r.unit)
                            if got and not ns.Secret(value) and type(value) == "number" then shields = math.max(0, value) end
                        end
                    end
                    r.predict:SetMinMaxValues(0, maximum)
                    r.predict:SetValue(math.min(maximum, health + incoming))
                    r.hasPrediction = incoming > 0
                    r.secretPredict:Hide()
                    if incoming > 0 then status = status .. "  +" .. math.floor(incoming + 0.5) end
                    r.absorb:SetMinMaxValues(0, maximum)
                    r.absorb:SetValue(math.min(maximum, health + incoming + shields))
                    r.hasAbsorb = shields > 0
                elseif healthOK and maxOK and (ns.Secret(health) or ns.Secret(maximum)) then
                    -- Restricted values may be passed straight to status bars,
                    -- but must never be inspected or used in Lua arithmetic.
                    pcall(function() r.bar:SetMinMaxValues(0, maximum); r.bar:SetValue(health) end)
                    r.hasPrediction = false
                    pcall(r.predict.SetValue, r.predict, 0)
                    pcall(r.absorb.SetValue, r.absorb, 0)
                    r.secretPredict:Hide()
                    if r.predictFill and type(CreateUnitHealPredictionCalculator) == "function"
                        and type(UnitGetDetailedHealPrediction) == "function" then
                        pcall(function()
                            if not self.healCalculator then self.healCalculator = CreateUnitHealPredictionCalculator() end
                            UnitGetDetailedHealPrediction(r.unit, "player", self.healCalculator)
                            local incoming = self.healCalculator:GetIncomingHeals()
                            r.secretPredict:SetMinMaxValues(0, maximum)
                            r.secretPredict:SetValue(incoming)
                            r.secretPredict:Show()
                        end)
                    end
                end
            end
            if type(UnitIsConnected) == "function" then
                local ok, connected = pcall(UnitIsConnected, r.unit)
                if ok and not ns.Secret(connected) and connected == false then status = "Offline" end
            end
            if status ~= "Offline" and type(UnitIsDeadOrGhost) == "function" then
                local ok, dead = pcall(UnitIsDeadOrGhost, r.unit)
                if ok and not ns.Secret(dead) and dead then status = "Dead" end
            end
            if status == "Dead" and type(UnitHasIncomingResurrection) == "function" then
                local ok, incoming = pcall(UnitHasIncomingResurrection, r.unit)
                if ok and not ns.Secret(incoming) and incoming then status = "Resurrect" end
            end
            r.status:SetText(status)
            updateRange(r)
            local dispel = ns.modules.dispel
            local color
            if dispel and dispel.Curable then local kind; kind, color = dispel:Curable(r.unit) end
            if color then r.debuff:SetColorTexture(color[1], color[2], color[3], 1)
            else r.debuff:SetColorTexture(0, 0, 0, 0) end
            local found = dispel and dispel.Scan and dispel:Scan(r.unit) or {}
            local button = r.dispelButton
            if button then
                local active
                for i, group in ipairs(button.fuiGroups or {}) do
                    for _, kind in ipairs(group.kinds) do if found[kind] then active = i; break end end
                    if active then break end
                end
                local labels = { "L", "R", "M", "4" }
                button.label:SetText(active and labels[active] or "D")
                button.fill:SetColorTexture(0.86, 0.27, 0.16, active and 0.85 or 0.16)
            end
            for _, icon in ipairs(r.buffs) do icon:Hide(); icon.fuiExpiration = nil end
            r.harmfulIcon:Hide()
            if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
                local auraOK, aura = pcall(C_UnitAuras.GetAuraDataByIndex, r.unit, 1, "HARMFUL")
                if auraOK and not ns.Secret(aura) and type(aura) == "table" then
                    local texture = aura.icon
                    if not ns.Secret(texture) and (type(texture) == "number" or type(texture) == "string") then
                        r.harmfulIcon:SetTexture(texture); r.harmfulIcon:Show()
                    end
                end
            end
            for _, count in ipairs(r.buffStacks) do count:Hide() end
            for _, time in ipairs(r.buffTimes) do time:Hide() end
            local tracked, kinds = {}, {}
            if self.TrackedAuras then tracked, kinds = self:TrackedAuras(r.unit) end
            local helpfulIndex = 0
            for i, aura in ipairs(tracked) do
                local texture = aura.icon
                if not ns.Secret(texture) and (type(texture) == "number" or type(texture) == "string") then
                  if kinds and kinds[i] == "HARMFUL" then
                    r.harmfulIcon:SetTexture(texture); r.harmfulIcon:Show()
                  else
                    helpfulIndex = helpfulIndex + 1
                    r.buffs[helpfulIndex]:SetTexture(texture)
                    r.buffs[helpfulIndex]:Show()
                    local expiration = aura.expirationTime
                    if not ns.Secret(expiration) and type(expiration) == "number" and expiration > 0 then
                        r.buffs[helpfulIndex].fuiExpiration = expiration
                    end
                    local count = aura.applications
                    if not ns.Secret(count) and type(count) == "number" and count > 1 then
                        r.buffStacks[helpfulIndex]:SetText(tostring(count)); r.buffStacks[helpfulIndex]:Show()
                    end
                  end
                end
            end
            -- If no configured effect is visible, still preview the first
            -- helpful aura so the indicator doesn't imply there are none.
            local auraConfig = self.GetAuraConfig and self:GetAuraConfig()
            if helpfulIndex == 0 and (not auraConfig or auraConfig.mode ~= "off")
                and C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
                local okAura, aura = pcall(C_UnitAuras.GetAuraDataByIndex, r.unit, 1, "HELPFUL")
                if okAura and not ns.Secret(aura) and type(aura) == "table" then
                    local icon = aura.icon
                    if not ns.Secret(icon) and (type(icon) == "number" or type(icon) == "string") then
                        r.buffs[1]:SetTexture(icon); r.buffs[1]:Show()
                    end
                end
            end
            if GameTooltip and type(GameTooltip.IsOwned) == "function" then
                local owned, isOwned = pcall(GameTooltip.IsOwned, GameTooltip, r)
                if owned and not ns.Secret(isOwned) and isOwned then self:ShowAuraTooltip(r) end
            end
        end
    end
end

function m:Refresh()
    if InCombatLockdown and InCombatLockdown() then self:UpdateUnits(); return end
    self:Build()
    if not self.holder then return end
    self:UpdatePartyReplacement()
    self:ConfigureDispelButtons()
    self:ApplyLayout()
    local scale = tonumber(ns.Opt("healScale")) or 1
    self.holder:SetScale(math.max(0.7, math.min(1.5, scale)))
    local dispel = ns.modules.dispel
    if dispel and dispel.ApplyLayout then dispel:ApplyLayout() end
    local visibility = ns.Opt("healSolo") and "show" or "[group] show; hide"
    if self.visibilityDriver ~= visibility then
        RegisterStateDriver(self.holder, "visibility", visibility)
        self.visibilityDriver = visibility
    end
    local targetVisibility = ns.Opt("healTargets") and "show" or "hide"
    if self.targetHolder and self.targetDriver ~= targetVisibility then
        RegisterStateDriver(self.targetHolder, "visibility", targetVisibility)
        self.targetDriver = targetVisibility
    end
    local key = characterKey()
    local bindings = key and ns.db.healBindings and ns.db.healBindings[key] or {}
    for _, r in ipairs(self.rows) do
        for command, attributes in pairs(KEYS) do
            local action, value = parseAction(bindings[command])
            r:SetAttribute(attributes[1], action or ((command == "left") and "target" or nil))
            r:SetAttribute(attributes[2], action == "spell" and value or nil)
            r:SetAttribute(attributes[3], action == "item" and value or nil)
            r:SetAttribute(attributes[4], action == "macro" and value or nil)
        end
    end
    self:UpdateUnits()
end

function m:SetBinding(command, spell)
    if not command or not KEYS[command] or not spell or spell == "" then
        ns.Print("use /fui healbind left Spell Name; use item:Name, macro:Name, target, focus, assist, or clear.")
        return
    end
    if InCombatLockdown and InCombatLockdown() then ns.Print("change healing bindings after combat."); return end
    local key = characterKey()
    if not key then ns.Print("could not identify this character yet."); return end
    ns.db.healBindings = ns.db.healBindings or {}
    ns.db.healBindings[key] = ns.db.healBindings[key] or {}
    if spell:lower() == "clear" then ns.db.healBindings[key][command] = nil
    else ns.db.healBindings[key][command] = spell end
    self:Refresh()
    ns.Print("healing " .. command .. " set to " .. spell .. ".")
end

-- Suggestions only fill blank editor fields and are never applied until Save.
local SUGGESTIONS = {
    SHAMAN = { { "shift-left", 331 }, { "shift-right", 8004 } },
    DRUID = { { "shift-left", 5185 }, { "shift-right", 8936 }, { "ctrl-left", 774 } },
    PRIEST = { { "shift-left", 2050 }, { "shift-right", 2061 }, { "ctrl-left", 17 } },
    PALADIN = { { "shift-left", 635 }, { "shift-right", 19750 } },
}
function m:SuggestBindings()
    if not self.config then return 0 end
    local ok, _, class = pcall(UnitClass, "player")
    if not ok or ns.Secret(class) or type(class) ~= "string" then return 0 end
    local count = 0
    for _, item in ipairs(SUGGESTIONS[class] or {}) do
        local input, known = self.config.inputs[item[1]], false
        for _, fn in ipairs({ IsPlayerSpell or false, IsSpellKnown or false, (C_SpellBook and C_SpellBook.IsSpellKnown) or false }) do
            if type(fn) == "function" then
                local got, value = pcall(fn, item[2])
                if got and not ns.Secret(value) and value == true then known = true; break end
            end
        end
        if input and input:GetText():match("^%s*$") and known then
            local name
            if C_Spell and type(C_Spell.GetSpellName) == "function" then
                local got, value = pcall(C_Spell.GetSpellName, item[2])
                if got and not ns.Secret(value) and type(value) == "string" then name = value end
            end
            if name and name ~= "" then input:SetText(name); count = count + 1 end
        end
    end
    return count
end

function m:DropBindingSpell(input)
    if InCombatLockdown and InCombatLockdown() then ns.Print("change healing bindings after combat."); return false end
    if type(GetCursorInfo) ~= "function" or not input then return false end
    local ok, kind, index, book, spellID = pcall(GetCursorInfo)
    if not ok or ns.Secret(kind) or kind ~= "spell" then return false end
    local name, rank
    if not ns.Secret(spellID) and type(spellID) == "number" and C_Spell and type(C_Spell.GetSpellName) == "function" then
        local got, value = pcall(C_Spell.GetSpellName, spellID)
        if got and not ns.Secret(value) and type(value) == "string" then name = value end
        if type(C_Spell.GetSpellSubtext) == "function" then
            local subOK, subtext = pcall(C_Spell.GetSpellSubtext, spellID)
            if subOK and not ns.Secret(subtext) and type(subtext) == "string" and subtext ~= "" then rank = subtext end
        end
    end
    if (not name or not rank) and not ns.Secret(index) and not ns.Secret(book) and type(GetSpellBookItemName) == "function" then
        local got, value, subtext = pcall(GetSpellBookItemName, index, book)
        if not name and got and not ns.Secret(value) and type(value) == "string" then name = value end
        if got and not ns.Secret(subtext) and type(subtext) == "string" and subtext ~= "" then rank = subtext end
    end
    if not name or name == "" then ns.Print("could not identify the dragged spell."); return false end
    input:SetText(rank and (name .. "(" .. rank .. ")") or name)
    if type(ClearCursor) == "function" then ClearCursor() end
    return true
end

function m:ShowConfig()
    if not self.config then
        local f = CreateFrame("Frame", "ForeverUIHealingConfig", UIParent)
        f:SetSize(390, 388)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        ns.Panel(f, { alpha = 1.1 })
        f.TitleContainer = CreateFrame("Frame", nil, f)
        f.TitleContainer:SetPoint("TOPLEFT")
        f.TitleContainer:SetPoint("TOPRIGHT")
        f.TitleContainer:SetHeight(29)
        local title = ns.Text(f, 14, ns.C.bright)
        title:SetPoint("TOPLEFT", 14, -12)
        title:SetText("Healing bindings")
        local hint = ns.Text(f, 10, ns.C.muted)
        hint:SetPoint("TOPLEFT", 14, -34)
        hint:SetText("Drag a spell onto a field, or enter a spell, item, macro or action.")
        f.inputs = {}
        f.captions = {}
        for i, command in ipairs(ORDER) do
            local y = -57 - ((i - 1) % 10) * 27
            local caption = ns.Text(f, 11)
            caption:SetPoint("TOPLEFT", 14, y - 4)
            caption:SetText(command)
            f.captions[command] = caption
            local input = CreateFrame("EditBox", nil, f)
            input:SetSize(200, 21)
            input:SetPoint("TOPRIGHT", -18, y)
            input:SetFontObject(ChatFontNormal)
            input:SetTextInsets(5, 5, 0, 0)
            ns.Panel(input, { alpha = 0.8, edge = 0.6 })
            input:SetAutoFocus(false)
            input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            input:SetScript("OnReceiveDrag", function(self) m:DropBindingSpell(self) end)
            input:SetScript("OnMouseUp", function(self, button)
                if button == "LeftButton" then m:DropBindingSpell(self) end
            end)
            f.inputs[command] = input
        end
        local pageLabel = ns.Text(f, 10, ns.C.muted)
        pageLabel:SetPoint("BOTTOMLEFT", 49, 19)
        local function page(number)
            f.page = math.max(1, math.min(4, number))
            pageLabel:SetText("Page " .. f.page .. " / 4")
            for i, command in ipairs(ORDER) do
                local visible = math.floor((i - 1) / 10) + 1 == f.page
                f.inputs[command]:SetShown(visible)
                f.captions[command]:SetShown(visible)
            end
        end
        for i, symbol in ipairs({ "<", ">" }) do
            local nav = CreateFrame("Button", nil, f)
            nav:SetSize(22, 22)
            nav:SetPoint("BOTTOMLEFT", i == 1 and 15 or 118, 12)
            ns.Panel(nav)
            local text = ns.Text(nav, 12, ns.C.bright)
            text:SetPoint("CENTER")
            text:SetText(symbol)
            nav:SetScript("OnClick", function() page(f.page + (i == 1 and -1 or 1)) end)
        end
        page(1)
        local suggest = CreateFrame("Button", nil, f)
        f.suggest = suggest
        suggest:SetSize(120, 25)
        suggest:SetPoint("BOTTOMLEFT", 150, 12)
        ns.Panel(suggest)
        local suggestionText = ns.Text(suggest, 10, ns.C.bright)
        suggestionText:SetPoint("CENTER")
        suggestionText:SetText("Suggest spells")
        suggest:SetScript("OnClick", function()
            if InCombatLockdown and InCombatLockdown() then ns.Print("change healing bindings after combat."); return end
            local count = m:SuggestBindings()
            ns.Print(count > 0 and ("suggested " .. count .. " learned spell(s); press Save to apply.") or "no additional learned spells to suggest.")
        end)
        local save = CreateFrame("Button", nil, f)
        f.save = save
        save:SetSize(100, 25)
        save:SetPoint("BOTTOMRIGHT", -14, 12)
        ns.Panel(save, { bright = true })
        local saveText = ns.Text(save, 11, ns.C.bright)
        saveText:SetPoint("CENTER")
        saveText:SetText("Save")
        save:SetScript("OnClick", function()
            if InCombatLockdown and InCombatLockdown() then ns.Print("change healing bindings after combat."); return end
            local key = characterKey()
            if not key then ns.Print("could not identify this character yet."); return end
            ns.db.healBindings = ns.db.healBindings or {}
            local bindings = {}
            for _, command in ipairs(ORDER) do
                local value = f.inputs[command]:GetText():gsub("^%s+", ""):gsub("%s+$", "")
                if value ~= "" then bindings[command] = value end
            end
            ns.db.healBindings[key] = bindings
            m:Refresh()
            f:Hide()
            ns.Print("healing bindings saved for this character.")
        end)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        f.CloseButton = close
        close:SetSize(26, 24)
        close:SetPoint("TOPRIGHT", -5, -5)
        close:SetScript("OnClick", function() f:Hide() end)
        if ns.MakeWindowMovable then ns.MakeWindowMovable(f, "ForeverUIHealingConfig") end
        f:Hide()
        self.config = f
    end
    local key = characterKey()
    local values = key and ns.db.healBindings and ns.db.healBindings[key] or {}
    for _, command in ipairs(ORDER) do self.config.inputs[command]:SetText(values[command] or "") end
    self.config:Show()
end

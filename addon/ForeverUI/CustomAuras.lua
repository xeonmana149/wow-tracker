-- Compact personal spell indicators. These are display-only; no combat
-- action or automatic spell casting is performed.
local _, ns = ...
local A = {}
ns.CustomAuras = A

local function characterKey()
    local name = UnitName and UnitName("player")
    local realm = GetRealmName and GetRealmName() or ""
    if ns.Secret(name) or ns.Secret(realm) or type(name) ~= "string" or type(realm) ~= "string" then return end
    return realm .. ":" .. name
end

function A:Rules()
    local key = characterKey()
    return key and ns.db.customAuras and ns.db.customAuras[key] or {}
end

function A:Save(text)
    local key = characterKey()
    if not key then return false, "Character information is unavailable." end
    local rules = {}
    for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" then
            local kind, id, unit = line:lower():match("^(%a+)%s+(%d+)%s*(%a*)$")
            id = tonumber(id)
            if not id or id < 1 or (kind ~= "buff" and kind ~= "debuff" and kind ~= "cooldown")
                or (unit ~= "" and unit ~= "player" and unit ~= "target") then
                return false, "Use: buff 123 player, debuff 123 target, or cooldown 123."
            end
            if #rules >= 12 then return false, "Choose up to 12 indicators." end
            rules[#rules + 1] = { kind = kind, id = id, unit = unit ~= "" and unit or (kind == "debuff" and "target" or "player") }
        end
    end
    ns.db.customAuras = ns.db.customAuras or {}
    ns.db.customAuras[key] = rules
    self:Refresh()
    return true
end

local function safeAura(rule, cache)
    if not (C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function") then return end
    local filter = rule.kind == "buff" and "HELPFUL" or "HARMFUL"
    local key = rule.unit .. ":" .. filter
    if cache[key] then return cache[key][rule.id] end
    local found = {}
    cache[key] = found
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, rule.unit, i, filter)
        if not ok or ns.Secret(aura) or type(aura) ~= "table" then break end
        local id = aura.spellId
        if not ns.Secret(id) and type(id) == "number" then found[id] = aura end
    end
    return found[rule.id]
end

function A:Refresh()
    if not self.frame then return end
    local rules, cache = self:Rules(), {}
    for i, cell in ipairs(self.cells) do
        local rule, active, remaining = rules[i], false, nil
        if rule and rule.kind == "cooldown" and C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
            local ok, cd = pcall(C_Spell.GetSpellCooldown, rule.id)
            if ok and not ns.Secret(cd) and type(cd) == "table" then
                local start, duration = cd.startTime, cd.duration
                if not ns.Secret(start) and not ns.Secret(duration) and type(start) == "number" and type(duration) == "number" then
                    remaining = math.max(0, start + duration - GetTime()); active = remaining > 1.5
                end
            end
        elseif rule then
            local aura = safeAura(rule, cache)
            if aura then
                active = true
                local expiry = aura.expirationTime
                if not ns.Secret(expiry) and type(expiry) == "number" and expiry > 0 then remaining = math.max(0, expiry - GetTime()) end
            end
        end
        if rule then
            local icon
            if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
                local ok, value = pcall(C_Spell.GetSpellTexture, rule.id)
                if ok and not ns.Secret(value) then icon = value end
            end
            cell.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        end
        cell:SetShown(rule ~= nil and active)
        if remaining and remaining > 0 then
            cell.timer:SetText(remaining >= 60 and (math.ceil(remaining / 60) .. "m") or tostring(math.ceil(remaining)))
        else cell.timer:SetText("") end
    end
end

function A:ShowConfig()
    if not self.config then
        local f = CreateFrame("Frame", "ForeverUICustomAuraConfig", UIParent)
        f:SetSize(430, 240); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); ns.Panel(f)
        f.TitleContainer = CreateFrame("Frame", nil, f)
        f.TitleContainer:SetPoint("TOPLEFT"); f.TitleContainer:SetPoint("TOPRIGHT"); f.TitleContainer:SetHeight(29)
        local title = ns.Text(f.TitleContainer, 15, ns.C.bright); title:SetPoint("TOPLEFT", 12, -12); title:SetText("Custom indicators")
        local hint = ns.Text(f, 10, ns.C.muted); hint:SetPoint("TOPLEFT", 12, -38); hint:SetWidth(405)
        hint:SetText("One per line: buff 123 player, debuff 123 target, or cooldown 123. Use spell IDs; up to 12.")
        local edit = CreateFrame("EditBox", nil, f); edit:SetSize(400, 110); edit:SetPoint("TOPLEFT", 12, -70)
        edit:SetFontObject(ChatFontNormal); edit:SetTextInsets(5, 5, 5, 5); edit:SetAutoFocus(false)
        if edit.SetMultiLine then edit:SetMultiLine(true) end
        ns.Panel(edit, { alpha = 0.8, edge = 0.6 }); f.edit = edit
        local info = ns.Text(f, 10, ns.C.muted); info:SetPoint("BOTTOMLEFT", 12, 42); info:SetWidth(405); f.info = info
        local save = CreateFrame("Button", nil, f); save:SetSize(100, 24); save:SetPoint("BOTTOMRIGHT", -12, 10); ns.Panel(save)
        local text = ns.Text(save, 11, ns.C.bright); text:SetPoint("CENTER"); text:SetText("Save")
        save:SetScript("OnClick", function()
            local ok, err = A:Save(edit:GetText())
            if ok then f:Hide() else f.info:SetText(err) end
        end)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetSize(24, 24); close:SetPoint("TOPRIGHT", -4, -4); f.CloseButton = close
        close:SetScript("OnClick", function() f:Hide() end)
        if ns.MakeWindowMovable then ns.MakeWindowMovable(f, "ForeverUICustomAuraConfig") end
        self.config = f
    end
    local lines = {}
    for _, r in ipairs(self:Rules()) do lines[#lines + 1] = r.kind .. " " .. r.id .. " " .. r.unit end
    self.config.edit:SetText(table.concat(lines, "\n")); self.config.info:SetText(""); self.config:Show()
end

ns.Module("customauras", "Custom indicators", function()
    local f = CreateFrame("Frame", "ForeverUICustomAuras", UIParent)
    f:SetSize(12 * 34, 32); f:EnableMouse(false)
    ns.Place(f, "customAuras", "Custom indicators", { "CENTER", "CENTER", 0, 150 })
    A.frame, A.cells = f, {}
    for i = 1, 12 do
        local cell = CreateFrame("Frame", nil, f); cell:SetSize(30, 30); cell:SetPoint("LEFT", f, "LEFT", (i - 1) * 34, 0); ns.Panel(cell)
        cell.icon = cell:CreateTexture(nil, "ARTWORK"); cell.icon:SetPoint("TOPLEFT", 2, -2); cell.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        cell.timer = ns.Text(cell, 10, ns.C.text, "OVERLAY"); cell.timer:SetPoint("CENTER"); cell:Hide(); A.cells[i] = cell
    end
    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt) elapsed = elapsed + dt; if elapsed >= 0.2 then elapsed = 0; A:Refresh() end end)
    for _, event in ipairs({ "UNIT_AURA", "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED" }) do
        ns.On(event, function() A:Refresh() end)
    end
    A:Refresh()
end)

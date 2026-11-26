-- Clickable dispel indicators. Unit and spell attributes are configured only
-- outside combat; aura changes affect textures, never protected attributes.
local _, ns = ...
local TYPES = { "Magic", "Curse", "Poison", "Disease" }
local COLOR = {
    Magic = { 0.38, 0.65, 1 }, Curse = { 0.72, 0.45, 0.90 },
    Poison = { 0.37, 0.78, 0.40 }, Disease = { 0.78, 0.57, 0.28 },
}
local ALERT = "Interface\\AddOns\\ForeverUI\\Art\\dispel-alert.ogg"
-- Prefer broader spells when learned; use spell names supplied by the client.
local SPELLS = {
    PALADIN = { Magic = { 4987 }, Poison = { 4987, 1152 }, Disease = { 4987, 1152 } },
    PRIEST = { Magic = { 988, 527 }, Disease = { 552, 528 } },
    DRUID = { Curse = { 2782 }, Poison = { 2893, 8946 } },
    MAGE = { Curse = { 475 } },
    SHAMAN = { Poison = { 526 }, Disease = { 2870 } },
}

local function known(id)
    for _, fn in ipairs({ IsPlayerSpell or false, IsSpellKnown or false, (C_SpellBook and C_SpellBook.IsSpellKnown) or false }) do
        if type(fn) == "function" then
            local ok, result = pcall(fn, id)
            if ok and not ns.Secret(result) and result == true then return true end
        end
    end
    return false
end

local function spellName(id)
    if C_Spell and type(C_Spell.GetSpellName) == "function" then
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if ok and not ns.Secret(name) and type(name) == "string" and name ~= "" then return name end
    end
end

local function available()
    local _, class = UnitClass("player")
    if ns.Secret(class) or type(class) ~= "string" then return {} end
    local list = SPELLS[class]
    local result = {}
    if not list then return result end
    for _, kind in ipairs(TYPES) do
        for _, id in ipairs(list[kind] or {}) do
            local name = known(id) and spellName(id)
            if name then result[kind] = name; break end
        end
    end
    return result
end

local function characterKey()
    local name = UnitName("player")
    local realm = GetRealmName and GetRealmName() or ""
    if ns.Secret(name) or ns.Secret(realm) or type(name) ~= "string" or name == "" or type(realm) ~= "string" then return end
    return realm .. ":" .. name
end

local function scan(unit)
    local found = {}
    if not (C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function") then return found end
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
        if not ok or ns.Secret(aura) or type(aura) ~= "table" then break end
        local kind = aura.dispelName
        if not ns.Secret(kind) and type(kind) == "string" and COLOR[kind] then found[kind] = true end
    end
    return found
end

local m = ns.Module("dispel", "Dispel indicators", function(self)
    self.rows = {}
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED", "GROUP_ROSTER_UPDATE", "UNIT_AURA" }) do
        ns.On(event, function(_, unit)
            if event == "UNIT_AURA" then self:UpdateAuras(unit) else self:Refresh() end
        end)
    end
    self:Refresh()
end)

function m:Curable(unit)
    local found, learned = scan(unit), self.spells or {}
    for _, kind in ipairs(TYPES) do
        if found[kind] and learned[kind] then return kind, COLOR[kind] end
    end
end

function m:Scan(unit)
    return scan(unit)
end

local function row(parent, unit, column, line)
    local r = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    r:SetSize(10, 10)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", column * 12, -line * 12)
    r:SetAttribute("unit", unit)
    r:SetAttribute("useOnKeyDown", false)
    r:RegisterForClicks("AnyUp")
    RegisterUnitWatch(r)
    ns.Panel(r, { alpha = 0.8, edge = 0.7 })
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("TOPLEFT", 1, -1)
    r.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    -- Only the visual overlay pulses; the secure target and spell attributes
    -- stay fixed throughout combat.
    r.flash = r:CreateTexture(nil, "OVERLAY")
    r.flash:SetPoint("TOPLEFT", r.icon, "TOPLEFT")
    r.flash:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT")
    r.flash:SetColorTexture(0.87, 0.55, 1, 0.65)
    r.flash:Hide()
    r.hover = r:CreateTexture(nil, "HIGHLIGHT")
    r.hover:SetPoint("TOPLEFT", 1, -1)
    r.hover:SetPoint("BOTTOMRIGHT", -1, 1)
    r.hover:SetColorTexture(1, 0.85, 0.48, 0.12)
    r.unit = unit
    r.column, r.line = column, line
    r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local name = UnitName(self.unit)
        GameTooltip:SetText(not ns.Secret(name) and name or self.unit, 1, 0.82, 0)
        if self.activeKind then GameTooltip:AddLine("Can dispel: " .. self.activeKind, 1, 1, 1) end
        if not self.actions or #self.actions == 0 then
            GameTooltip:AddLine("No supported dispel spell available on this character.", 0.7, 0.7, 0.7, true)
        end
        for i, spell in ipairs(self.actions or {}) do
            GameTooltip:AddLine(({ "Left click: ", "Right click: ", "Middle click: ", "Button 4: " })[i] .. spell, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

-- Keep five equal squares in a compact row above the portrait and healing bar.
-- Raid members use additional rows; unit watches hide unoccupied squares.
function m:ApplyLayout()
    if not self.holder or (InCombatLockdown and InCombatLockdown()) then return end
    local width = math.max(100, math.min(200, tonumber(ns.Opt("healWidth")) or 120))
    local height = math.max(22, math.min(40, tonumber(ns.Opt("healHeight")) or 25))
    local span = width + math.min(28, height) + 3
    local size = math.min(18, math.floor((span - 16) / 5))
    local step = size + 4
    local lines = IsInRaid and IsInRaid() and 8 or 1
    self.holder:SetSize(5 * size + 4 * 4, lines * size + (lines - 1) * 4)
    local healing = ns.modules.healing
    local scale = healing and healing.holder and healing.holder:GetScale() or 1
    self.holder:SetScale(scale)
    for _, r in ipairs(self.rows) do
        r:SetSize(size, size)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", r:GetParent(), "TOPLEFT", r.column * step, -r.line * step)
    end
end

function m:AttachHealing()
    if not self.holder or (InCombatLockdown and InCombatLockdown()) then return end
    if ns.db.pos and ns.db.pos.dispel then return end
    local healing = ns.modules.healing
    local portrait = healing and healing.rows and healing.rows[1] and healing.rows[1].portraitButton
    if portrait then
        self.holder:ClearAllPoints()
        self.holder:SetPoint("BOTTOMLEFT", portrait, "TOPLEFT", 0, 4)
    end
end

function m:Build()
    if self.holder or type(RegisterUnitWatch) ~= "function" or type(RegisterStateDriver) ~= "function" then return end
    local f = CreateFrame("Frame", "ForeverUIDispel", UIParent)
    f:SetSize(38, 26)
    ns.Panel(f, { noBg = true, edge = 0 })
    ns.Place(f, "dispel", "Dispels", { "CENTER", "CENTER", -320, 120 }, nil, { noResize = true }) -- sized with the healing frames
    self.holder = f
    f:SetScript("OnUpdate", function(_, elapsed) self:UpdateFlash(elapsed) end)
    local party = CreateFrame("Frame", nil, f, "SecureHandlerStateTemplate")
    party:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    party:SetSize(1, 1)
    local raid = CreateFrame("Frame", nil, f, "SecureHandlerStateTemplate")
    raid:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    raid:SetSize(1, 1)
    RegisterStateDriver(party, "visibility", "[group:raid] hide; show")
    RegisterStateDriver(raid, "visibility", "[group:raid] show; hide")
    for i = 0, 4 do
        self.rows[#self.rows + 1] = row(party, i == 0 and "player" or "party" .. i, i, 0)
    end
    for i = 1, 40 do
        self.rows[#self.rows + 1] = row(raid, "raid" .. i, (i - 1) % 5, math.floor((i - 1) / 5))
    end
    if not ns.db.compactDispelV1 then ns.db.opts.healDispelButtons = false; ns.db.compactDispelV1 = true end
    self:AttachHealing()
end

function m:UpdateAuras(unit)
    local newlyCurable = false
    for _, r in ipairs(self.rows) do
        if not unit or unit == r.unit then
            local kind = self:Curable(r.unit)
            if kind and kind ~= r.activeKind then newlyCurable = true end
            r.activeKind = kind
            r.icon:SetColorTexture(0.56, 0.28, 0.76, kind and 0.85 or 0)
            r.flash:SetShown(kind ~= nil)
        end
    end
    self.hasCurable = false
    for _, r in ipairs(self.rows) do if r.activeKind then self.hasCurable = true; break end end
    if newlyCurable and self.holder and self.holder:IsShown() and ns.Opt("dispelSound")
        and type(PlaySoundFile) == "function" then
        local now = GetTime and GetTime()
        if not ns.Secret(now) and type(now) == "number" and (not self.lastAlert or now - self.lastAlert >= 1) then
            self.lastAlert = now
            pcall(PlaySoundFile, ALERT, "SFX")
        end
    end
end

function m:UpdateFlash(elapsed)
    if not self.hasCurable then return end
    self.flashTime = ((self.flashTime or 0) + (elapsed or 0)) % 1.2
    local opacity = 0.12 + 0.78 * (0.5 + 0.5 * math.sin(self.flashTime * 2 * math.pi / 1.2))
    for _, r in ipairs(self.rows) do
        if r.activeKind then r.flash:SetAlpha(opacity) end
    end
end

function m:Refresh()
    if InCombatLockdown and InCombatLockdown() then
        self:UpdateAuras()
        return
    end
    local spells = available()
    self.spells = spells
    self:Build()
    if not self.holder then return end
    self:ApplyLayout()
    for _, r in ipairs(self.rows) do
        local actions, seen = {}, {}
        for _, kind in ipairs(TYPES) do
            local name = spells[kind]
            if name and not seen[name] then actions[#actions + 1] = name; seen[name] = true end
        end
        r.actions = actions
        for i = 1, 4 do
            local name = actions[i]
            r:SetAttribute("type" .. i, name and "spell" or nil)
            r:SetAttribute("spell" .. i, name)
        end
    end
    local key = characterKey()
    local hidden = key and ns.db.dispelHidden and ns.db.dispelHidden[key]
    self.holder:SetShown(not hidden)
    self:UpdateAuras()
end

function m:Toggle()
    if InCombatLockdown and InCombatLockdown() then ns.Print("show or hide the dispel panel after combat."); return false end
    local key = characterKey()
    if not key then ns.Print("could not identify this character yet."); return false end
    ns.db.dispelHidden = ns.db.dispelHidden or {}
    local hidden = not ns.db.dispelHidden[key]
    ns.db.dispelHidden[key] = hidden or nil
    self:Refresh()
    ns.Print(hidden and "dispel panel hidden." or "dispel panel shown.")
    return true
end

-- Forever UI - your buffs and debuffs.
--
-- The game's own buff and debuff frames (so cancelling a buff with a
-- right-click, the dispel colours and Edit Mode's layout all keep working).
-- Each icon goes square with the gold hairline; a debuff keeps the game's
-- colour for its type, hugging the icon. Durations go small and muted.

local _, ns = ...

local function styleAura(b)
    if type(b) ~= "table" or b.fuiStyled then
        return false
    end
    local icon = b.Icon
    -- private aura anchors share the list; they have no icon texture
    if type(icon) ~= "table" or not icon.SetTexCoord then
        return false
    end
    b.fuiStyled = true
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local edge = CreateFrame("Frame", nil, b)
    edge:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    ns.Panel(edge, { noBg = true })
    b.fuiEdge = edge

    -- the debuff type colour, a 2px frame round the icon
    local border = b.DebuffBorder
    if border and border.SetPoint then
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
        border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    end
    -- a weapon enchant: the bright hairline instead of the purple ring
    if b.TempEnchantBorder then
        b.TempEnchantBorder:SetAlpha(0)
    end

    local dur = b.Duration
    if dur and dur.GetFont then
        local font, _, flags = dur:GetFont()
        if font then dur:SetFont(font, 9, flags or "OUTLINE") end
    end
    local count = b.Count
    if count and count.SetPoint then
        count:ClearAllPoints()
        count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 2)
    end
    local function auraType(self)
        local p = self.fuiEdge and self.fuiEdge.fuiPanel
        if p then
            p.bright = self.auraType == "TempEnchant"
            ns.PaintPanel(self.fuiEdge)
        end
    end
    if b.UpdateAuraType then
        hooksecurefunc(b, "UpdateAuraType", auraType)
    end
    auraType(b)
    return true
end

local m = ns.Module("auras", "Buffs and debuffs", function(m)
    m.buttons = {}
    local function styleAll()
        for _, name in ipairs({ "BuffFrame", "DebuffFrame" }) do
            local frame = _G[name]
            for _, b in ipairs(type(frame) == "table" and frame.auraFrames or {}) do
                if styleAura(b) then
                    table.insert(m.buttons, b)
                end
            end
        end
    end
    styleAll()
    -- Edit Mode can add icons when you raise the icon limit
    for _, name in ipairs({ "BuffFrame", "DebuffFrame" }) do
        local frame = _G[name]
        if type(frame) == "table" and frame.UpdateAuraButtons then
            hooksecurefunc(frame, "UpdateAuraButtons", styleAll)
        end
    end
end)

-- Forever UI - the XP and reputation bar.
--
-- One thin bar above the action bars: earned XP turns blue while rested,
-- ticks every 10%), and a slimmer reputation bar on top of it while you
-- watch a faction. At max level only the reputation bar is left, and with
-- no faction watched, nothing. Replaces the game's own status bars.

local _, ns = ...
local floor, max, min = math.floor, math.max, math.min

local XP_H, REP_H = 14, 8
local ACTION_PREFIXES = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }

-- Measure on-screen button bounds in UIParent units. Vertical and distant
-- bars should not stretch the XP bar across the whole screen.
local function actionBounds()
    local uiScale = UIParent:GetEffectiveScale()
    local height = UIParent:GetHeight()
    if type(uiScale) ~= "number" or uiScale <= 0 or type(height) ~= "number" then return end
    local left, right, top, bottom
    for _, prefix in ipairs(ACTION_PREFIXES) do
        local a, b = _G[prefix .. "1"], _G[prefix .. "12"]
        if a and b then
            pcall(function()
                if not a:IsVisible() or not b:IsVisible() then return end
                local ax, ay = a:GetCenter()
                local bx, by = b:GetCenter()
                local al, ar, at = a:GetLeft(), a:GetRight(), a:GetTop()
                local bl, br, bt = b:GetLeft(), b:GetRight(), b:GetTop()
                local as, bs = a:GetEffectiveScale() / uiScale, b:GetEffectiveScale() / uiScale
                if not (ax and ay and bx and by and al and ar and at and bl and br and bt) then return end
                ax, ay, bx, by = ax * as, ay * as, bx * bs, by * bs
                if math.abs(bx - ax) < math.abs(by - ay) or math.max(ay, by) > height * 0.4 then return end
                local l, r, t = min(al * as, bl * bs), max(ar * as, br * bs), max(at * as, bt * bs)
                left, right, top = min(left or l, l), max(right or r, r), max(top or t, t)
                local ab, bb = a:GetBottom(), b:GetBottom()
                if type(ab) == "number" and type(bb) == "number" then
                    local edge = min(ab * as, bb * bs)
                    bottom = min(bottom or edge, edge)
                end
            end)
        end
    end
    return left, right, top, bottom
end
ns.ActionBarBounds = actionBounds

local function commas(n)
    local s = tostring(floor(n or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

local function atMaxLevel()
    if GameRulesUtil and GameRulesUtil.IsPlayerAtEffectiveMaxLevel then
        local ok, v = pcall(GameRulesUtil.IsPlayerAtEffectiveMaxLevel)
        if ok then
            return v
        end
    end
    local cap = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
    return UnitLevel("player") >= cap
end

local function xpOff()
    return atMaxLevel() or (IsXPUserDisabled and IsXPUserDisabled())
end

-- Only count XP the client actually supplies for complete quests; no guessed
-- values for uncached rewards. Nil means the reward has not loaded yet.
local function completedQuestXP()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo
        and C_QuestLog.IsComplete and GetQuestLogRewardXP) then return 0, 0 end
    local ok, count = pcall(C_QuestLog.GetNumQuestLogEntries)
    if not ok or ns.Secret(count) or type(count) ~= "number" then return 0, 0 end
    local total, quests = 0, 0
    for i = 1, count do
        local found, info = pcall(C_QuestLog.GetInfo, i)
        if found and not ns.Secret(info) and type(info) == "table" and not info.isHeader
            and not ns.Secret(info.questID) and type(info.questID) == "number" then
            local checked, complete = pcall(C_QuestLog.IsComplete, info.questID)
            if checked and not ns.Secret(complete) and complete then
                local received, amount = pcall(GetQuestLogRewardXP, info.questID)
                if received and not ns.Secret(amount) and type(amount) == "number" and amount > 0 then
                    total, quests = total + amount, quests + 1
                end
            end
        end
    end
    return total, quests
end

-- The watched faction, or nil: name, standing text, colour, value in the
-- current standing, its size.
local function watched()
    if not (C_Reputation and C_Reputation.GetWatchedFactionData) then
        return nil
    end
    local d = C_Reputation.GetWatchedFactionData()
    if not d or (d.factionID or 0) == 0 then
        return nil
    end
    local lo, hi, v = d.currentReactionThreshold or 0, d.nextReactionThreshold or 1, d.currentStanding or 0
    local label = _G["FACTION_STANDING_LABEL" .. tostring(d.reaction)] or ""
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[d.reaction] or { r = 0.25, g = 0.6, b = 0.3 }
    local size = max(1, hi - lo)
    return { name = d.name or "", standing = label, c = c, value = min(size, max(0, v - lo)), size = size, done = hi <= lo }
end

local function bar(parent, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(h)
    ns.Panel(f, { alpha = 1.1 })
    f.fill = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.fill:SetPoint("TOPLEFT", 1, -1)
    f.fill:SetPoint("BOTTOMLEFT", 1, 1)
    f.rest = f:CreateTexture(nil, "ARTWORK", nil, 2)
    f.rest:SetPoint("TOPLEFT", f.fill, "TOPLEFT")
    f.rest:SetPoint("BOTTOMRIGHT", f.fill, "BOTTOMRIGHT")
    f.rest:Hide()
    f.text = ns.Text(f, h >= 12 and 10 or 9)
    f.text:SetPoint("CENTER", 0, 0)
    return f
end

local function setFill(f, frac, restFrac)
    local w = max(0, (f:GetWidth() or 0) - 2)
    frac = min(1, max(0, frac or 0))
    f.fill:SetWidth(max(0.001, w * frac))
    f.fill:SetShown(frac > 0)
    if restFrac and restFrac > 0 and frac > 0 then
        f.rest:Show()
    else
        f.rest:Hide()
    end
end

local m = ns.Module("xpbar", "XP bar", function(m)
    -- Leave Blizzard's layout-managed status bar under its original parent.
    -- Reparenting it to our hidden frame can interfere with Edit Mode's
    -- action-bar layout when the client refreshes that layout on level-up.
    -- Hiding the artwork keeps the native layout and anchors intact.
    if type(StatusTrackingBarManager) == "table" then
        if StatusTrackingBarManager.SetAlpha then StatusTrackingBarManager:SetAlpha(0) end
        if StatusTrackingBarManager.EnableMouse then StatusTrackingBarManager:EnableMouse(false) end
    end

    local holder = CreateFrame("Frame", "ForeverUIXPBar", UIParent)
    holder:SetFrameStrata("LOW")
    m.holder = holder
    holder:SetHeight(XP_H)
    holder:SetWidth(UIParent:GetWidth() * 0.7)

    local xp = bar(holder, XP_H)
    xp:SetPoint("BOTTOMLEFT")
    xp:SetPoint("BOTTOMRIGHT")
    local C = ns.C
    -- Draw one consistent hairline above the bar artwork so it stays visible
    -- against both the earned fill and the empty track.
    xp.edge = {}
    for i = 1, 4 do
        xp.fuiPanel.lines[i]:Hide()
        local line = xp:CreateTexture(nil, "OVERLAY", nil, 6)
        line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.65)
        xp.edge[i] = line
    end
    xp.edge[1]:SetPoint("TOPLEFT"); xp.edge[1]:SetPoint("TOPRIGHT"); xp.edge[1]:SetHeight(1)
    xp.edge[2]:SetPoint("BOTTOMLEFT"); xp.edge[2]:SetPoint("BOTTOMRIGHT"); xp.edge[2]:SetHeight(1)
    xp.edge[3]:SetPoint("TOPLEFT"); xp.edge[3]:SetPoint("BOTTOMLEFT"); xp.edge[3]:SetWidth(1)
    xp.edge[4]:SetPoint("TOPRIGHT"); xp.edge[4]:SetPoint("BOTTOMRIGHT"); xp.edge[4]:SetWidth(1)
    xp.fill:SetColorTexture(C.xp[1], C.xp[2], C.xp[3], 1)
    xp.rest:SetColorTexture(0.22, 0.46, 0.79, 1)
    xp.quest = xp:CreateTexture(nil, "ARTWORK", nil, 2)
    xp.quest:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    xp.quest:Hide()
    xp.questSheen = xp:CreateTexture(nil, "ARTWORK", nil, 3)
    xp.questSheen:SetColorTexture(1, 0.91, 0.72, 0.18)
    xp.questSheen:SetPoint("TOPLEFT", xp.quest, "TOPLEFT")
    xp.questSheen:SetPoint("TOPRIGHT", xp.quest, "TOPRIGHT")
    xp.questSheen:SetHeight(2)
    xp.questSheen:Hide()
    xp.questShade = xp:CreateTexture(nil, "ARTWORK", nil, 3)
    xp.questShade:SetColorTexture(0.02, 0.01, 0.03, 0.22)
    xp.questShade:SetPoint("BOTTOMLEFT", xp.quest, "BOTTOMLEFT")
    xp.questShade:SetPoint("BOTTOMRIGHT", xp.quest, "BOTTOMRIGHT")
    xp.questShade:SetHeight(2)
    xp.questShade:Hide()
    -- Light and shadow follow the earned fill, leaving the empty track quiet.
    xp.sheen = xp:CreateTexture(nil, "ARTWORK", nil, 3)
    xp.sheen:SetColorTexture(1, 0.91, 0.72, 0.18)
    xp.sheen:SetPoint("TOPLEFT", xp.fill, "TOPLEFT")
    xp.sheen:SetPoint("TOPRIGHT", xp.fill, "TOPRIGHT")
    xp.sheen:SetHeight(2)
    xp.shade = xp:CreateTexture(nil, "ARTWORK", nil, 3)
    xp.shade:SetColorTexture(0.02, 0.01, 0.03, 0.22)
    xp.shade:SetPoint("BOTTOMLEFT", xp.fill, "BOTTOMLEFT")
    xp.shade:SetPoint("BOTTOMRIGHT", xp.fill, "BOTTOMRIGHT")
    xp.shade:SetHeight(2)
    xp.ticks = {}
    for i = 1, 9 do
        local t = xp:CreateTexture(nil, "ARTWORK", nil, 4)
        t:SetColorTexture(0, 0, 0, 0.32)
        t:SetWidth(1)
        t:SetPoint("TOP", xp, "TOPLEFT", 0, -1)
        t:SetPoint("BOTTOM", xp, "BOTTOMLEFT", 0, 1)
        xp.ticks[i] = t
    end
    m.xp = xp
    xp:SetScript("OnSizeChanged", function() m:Update() end)

    local rep = bar(holder, REP_H)
    rep:SetPoint("BOTTOMLEFT", xp, "TOPLEFT", 0, -1)
    rep:SetPoint("BOTTOMRIGHT", xp, "TOPRIGHT", 0, -1)
    m.rep = rep

    for _, f in ipairs({ xp, rep }) do
        f:EnableMouse(true)
        f:SetScript("OnEnter", function(self)
            m.hover = self
            m:Update()
            m:Tooltip(self)
        end)
        f:SetScript("OnLeave", function()
            m.hover = nil
            m:Update()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end
    -- click the reputation bar: the reputation window, to pick a faction
    rep:SetScript("OnMouseUp", function()
        if ToggleCharacter then
            pcall(ToggleCharacter, "ReputationFrame")
        end
    end)

    ns.Place(holder, "xpbar", "XP bar", { "BOTTOM", "BOTTOM", 0, 160 })

    -- Follow changes to the native bars, including their Edit Mode layout.
    -- A manually moved XP bar keeps its chosen height, while matching the
    -- action bars' horizontal edges.
    local elapsed = 0
    holder:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.5 then elapsed = 0; m:UpdateLayout() end
    end)

    for _, e in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_UPDATE_RESTING",
        "UPDATE_FACTION", "PLAYER_ENTERING_WORLD", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED", "QUEST_LOG_UPDATE",
        "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_DATA_LOAD_RESULT" }) do
        ns.On(e, function() m:Update() end)
    end
    m:Update()
end)

function m:UpdateLayout()
    if not self.holder then return end
    local left, right, top = actionBounds()
    if not (left and right and top and right > left) then return end
    local holder = self.holder
    local width = right - left
    if math.abs((holder:GetWidth() or 0) - width) > 0.01 then
        holder:SetWidth(width)
        self:Update()
    end
    if not ns.moving then
        local saved = ns.db.pos.xpbar
        local x = (left + right) / 2
        local y = saved and saved.y or top + 2
        local point = saved and "CENTER" or "BOTTOM"
        if type(y) ~= "number" then return end
        if not self.layoutX or math.abs(self.layoutX - x) > 0.01 or math.abs(self.layoutY - y) > 0.01
            or self.layoutPoint ~= point then
            holder:ClearAllPoints()
            holder:SetPoint(point, UIParent, "BOTTOMLEFT", x, y)
            if saved then saved.x = x end
            self.layoutX, self.layoutY, self.layoutPoint = x, y, point
        end
    else
        self.layoutX, self.layoutY, self.layoutPoint = nil, nil, nil
    end
end

function m:Update()
    if not self.holder then
        return
    end
    local holder, xp, rep = self.holder, self.xp, self.rep
    local showXP = not xpOff()
    local r = watched()

    xp:SetShown(showXP)
    if showXP then
        local cur, top = UnitXP("player") or 0, max(1, UnitXPMax("player") or 1)
        local rested = GetXPExhaustion and GetXPExhaustion() or 0
        setFill(xp, cur / top, (rested or 0) / top)
        local w = (xp:GetWidth() or 0)
        local questXP, questCount = 0, 0
        if ns.Opt("qolQuestXP") then questXP, questCount = completedQuestXP() end
        self.questXP, self.questCount = questXP, questCount
        local inner = max(0, w - 2)
        local start = min(1, max(0, cur / top))
        local finish = min(1, max(start, (cur + questXP) / top))
        xp.quest:ClearAllPoints()
        xp.quest:SetPoint("TOPLEFT", xp, "TOPLEFT", 1 + inner * start, -1)
        xp.quest:SetPoint("BOTTOMLEFT", xp, "BOTTOMLEFT", 1 + inner * start, 1)
        xp.quest:SetWidth(max(0.001, inner * (finish - start)))
        xp.quest:SetShown(finish > start)
        xp.questSheen:SetShown(finish > start)
        xp.questShade:SetShown(finish > start)
        for i, t in ipairs(xp.ticks) do
            t:ClearAllPoints()
            t:SetPoint("TOP", xp, "TOPLEFT", w * i / 10, -1)
            t:SetPoint("BOTTOM", xp, "BOTTOMLEFT", w * i / 10, 1)
        end
        local line = "Level " .. UnitLevel("player") .. "    " .. commas(cur) .. " / " .. commas(top)
            .. " XP (" .. floor(cur / top * 100) .. "%)"
        if (rested or 0) > 0 then
            line = line .. "    " .. commas(rested) .. " rested"
        end
        xp.text:SetText(line)
        xp.text:SetShown(ns.Opt("xpText") or self.hover == xp)
    end

    rep:ClearAllPoints()
    if showXP then
        rep:SetPoint("BOTTOMLEFT", xp, "TOPLEFT", 0, -1)
        rep:SetPoint("BOTTOMRIGHT", xp, "TOPRIGHT", 0, -1)
        rep:SetHeight(REP_H)
    else
        -- at max level the reputation bar takes the XP bar's place and size
        rep:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT")
        rep:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT")
        rep:SetHeight(XP_H)
    end
    rep:SetShown(r ~= nil)
    if r then
        rep.fill:SetColorTexture(r.c.r, r.c.g, r.c.b, 1)
        setFill(rep, r.done and 1 or r.value / r.size)
        rep.text:SetText(r.name .. "    " .. r.standing .. (r.done and "" or ("    " .. commas(r.value) .. " / " .. commas(r.size))))
        rep.text:SetShown(self.hover == rep or not showXP and ns.Opt("xpText"))
    end
    holder:SetHeight((showXP and XP_H or 0) + (r and (showXP and REP_H - 1 or XP_H) or 0))
    holder:SetShown(showXP or r ~= nil)
end

function m:Tooltip(f)
    if not GameTooltip then
        return
    end
    GameTooltip:SetOwner(f, "ANCHOR_TOP")
    if f == self.rep then
        local r = watched()
        if r then
            GameTooltip:AddLine(r.name, 1, 0.82, 0)
            GameTooltip:AddLine(r.standing .. (r.done and "" or ("  " .. commas(r.value) .. " / " .. commas(r.size))), 1, 1, 1)
            GameTooltip:AddLine("Click: the reputation window, to watch another faction.", 0.7, 0.7, 0.7)
        end
    else
        local cur, top = UnitXP("player") or 0, max(1, UnitXPMax("player") or 1)
        local rested = GetXPExhaustion and GetXPExhaustion() or 0
        GameTooltip:AddLine("Level " .. UnitLevel("player"), 1, 0.82, 0)
        GameTooltip:AddLine(commas(cur) .. " / " .. commas(top) .. " XP, " .. commas(top - cur) .. " to go", 1, 1, 1)
        if (rested or 0) > 0 then
            GameTooltip:AddLine(commas(rested) .. " rested XP (double XP from kills)", 0.55, 0.65, 1)
        end
        if (self.questXP or 0) > 0 then
            GameTooltip:AddLine(commas(self.questXP) .. " XP from " .. self.questCount .. " completed quest" .. (self.questCount == 1 and "" or "s") .. " (known rewards)", 0.89, 0.75, 0.42)
        end
    end
    GameTooltip:Show()
end

function m:Restyle()
    self:Update()
end

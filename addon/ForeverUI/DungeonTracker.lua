-- Track quests for a selected dungeon or raid, independently of other addons.
local _, ns = ...
local T = {}
-- The header strip matches the other top-of-screen bars (2026-11-26): the
-- damage meter's title row and Forever Gold's farming tracker are both 22
-- high with 16px controls, 2 apart and 3 in from the edge.
local HEADER_H = 22
ns.DungeonQuestTracker = T

local function safe(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, result = pcall(fn, ...)
    if ok and not ns.Secret(result) then return result end
end

-- Dungeon records are shared with the guide and tracker. Old Fire-Eye's
-- existing record applies to the three instances in its weapon quest chain.
function T:Quests(dungeon)
    if not dungeon then return {} end
    local quests = dungeon.quests or {}
    if dungeon.key ~= "sfk" and dungeon.key ~= "bfd" then return quests end
    for _, q in ipairs(quests) do if q.id == 95140 then return quests end end
    for _, source in ipairs(ns.IndependentReference and ns.IndependentReference.DUNGEONS or {}) do
        if source.key == "deadmines" then
            for _, q in ipairs(source.quests or {}) do
                if q.id == 95140 then
                    local combined = {}; for _, item in ipairs(quests) do combined[#combined + 1] = item end
                    combined[#combined + 1] = q
                    return combined
                end
            end
        end
    end
    return quests
end

local classBits = { WARRIOR=1, PALADIN=2, HUNTER=4, ROGUE=8, PRIEST=16, DEATHKNIGHT=32, SHAMAN=64, MAGE=128, WARLOCK=256, MONK=512, DRUID=1024 }
local referenceQuests
local function referenceQuest(quest)
    local id = tonumber(quest.id)
    if not id then return end
    if not referenceQuests then
        referenceQuests = {}
        for _, record in ipairs(ns.BulkReferenceData and ns.BulkReferenceData.quests or {}) do
            if record.id then referenceQuests[record.id] = record end
        end
    end
    local record = referenceQuests[id]
    if record and type(record.name) == "string" and type(quest.name) == "string" and record.name:lower() == quest.name:lower() then return record end
end
local function classAllowed(restriction, class)
    if type(restriction) == "string" then
        local found, allowed = false, false
        for token in restriction:upper():gmatch("[%a]+") do
            if classBits[token] then found = true; if token == class then allowed = true end end
        end
        if found then return allowed end
    elseif type(restriction) == "table" then
        local found, allowed = false, false
        for _, token in pairs(restriction) do
            if type(token) == "string" and classBits[token:upper()] then found = true; if token:upper() == class then allowed = true end end
        end
        if found then return allowed end
    end
end

function T:QuestVisible(quest)
    local faction = safe(UnitFactionGroup, "player")
    faction = type(faction) == "string" and faction:lower() or nil
    local side = tostring(quest.side or ""):lower()
    if faction and side ~= "" and side ~= "both" and side ~= faction
        and not (side == "h" and faction == "horde") and not (side == "a" and faction == "alliance") then return false end
    local class
    if type(UnitClass) == "function" then
        local ok, _, token = pcall(UnitClass, "player")
        if ok and not ns.Secret(token) and type(token) == "string" then class = token:upper() end
    end
    if class then
        local result = classAllowed(quest.class or quest.classOnly or quest.classes, class)
        if result ~= nil then return result end
        local record = referenceQuest(quest)
        if record then result = classAllowed(record.classes, class); if result == nil then result = classAllowed(record.zone, class) end end
        if result ~= nil then return result end
        local mask = safe(QuestDB and QuestDB.requiredClasses, tonumber(quest.id))
        local bit = classBits[class]
        if type(mask) == "number" and mask > 0 and bit then return math.floor(mask / bit) % 2 == 1 end
    end
    return true
end

local function characterKey()
    return safe(UnitGUID, "player") or safe(UnitName, "player") or "unknown"
end

function T:GetTracked()
    local settings = ns.db and ns.db.dungeonTracking
    return type(settings) == "table" and settings[characterKey()] or nil
end

function T:SetTracked(key)
    if not ns.db then return end
    ns.db.dungeonTracking = ns.db.dungeonTracking or {}
    ns.db.dungeonTracking[characterKey()] = key
    self.offset = 0
    self.dismissed = key == nil
    self:Refresh()
end

function T:Read()
    local ref = ns.IndependentReference
    local selected = self:GetTracked()
    local dungeon
    if selected then
        for _, d in ipairs(ref and ref.DUNGEONS or {}) do
            if d.key == selected then dungeon = d; break end
        end
    end
    local instance, kind = false, nil
    if type(IsInInstance) == "function" then
        local ok, a, b = pcall(IsInInstance)
        if ok and not ns.Secret(a) and not ns.Secret(b) then instance, kind = a, b end
    end
    if not dungeon and instance and (kind == "party" or kind == "raid") then
        local name = safe(GetInstanceInfo)
        if type(name) == "string" then
            for _, d in ipairs(ref and ref.DUNGEONS or {}) do
                if d.name == name or d.short == name then dungeon = d; break end
            end
        end
    end
    if not dungeon then return end
    local log = C_QuestLog
    local n = log and safe(log.GetNumQuestLogEntries)
    local active = {}
    for i = 1, type(n) == "number" and n or 0 do
        local info = safe(log.GetInfo, i)
        if type(info) == "table" and not ns.Secret(info.questID) and type(info.questID) == "number" then
            active[info.questID] = info
        end
    end
    local rows, total, done, unknown, seen = {}, 0, 0, false, {}
    for _, q in ipairs(self:Quests(dungeon)) do
        local id = tonumber(q.id)
        if id and self:QuestVisible(q) and not seen[id] then
            seen[id] = true; total = total + 1
            local page = ns.Encyclopedia and ns.Encyclopedia.QuestPage
            local status = page and page.Status({data=q}) or "Unknown"
            if active[id] then
                local complete = safe(log.IsComplete, id)
                -- Some clients expose completion on the log entry instead.
                if complete == nil and not ns.Secret(active[id].isComplete) then complete = active[id].isComplete end
                status = (complete == true or complete == 1) and "Ready to turn in" or "In progress"
            end
            if status == "Completed" then done = done + 1 elseif status == "Unknown" then unknown = true end
            local presentation = page and page.Presentation and page.Presentation({data=q}, status)
            local unavailable = type(presentation) == "string" and (presentation:find("^Unavailable") ~= nil or presentation:find("^Requires level") ~= nil)
            local note = type(q.note) == "string" and q.note:lower() or ""
            local reference = referenceQuest(q)
            local classic = q.classic or (reference and reference.classic) or {}
            local chain = note:find("part %d") ~= nil or note:find("quest chain", 1, true) ~= nil
                or (tonumber(classic.previous) or 0) > 0 or (tonumber(classic.next) or 0) > 0
            local inside = type(q.starts) == "string" and q.starts:lower():find("inside " .. dungeon.name:lower(), 1, true) ~= nil
            rows[#rows + 1] = { title = q.name or "Dungeon quest", quest = q, dungeon = dungeon, status = status, chain = chain, inside = inside, unavailable = unavailable }
            if status == "Ready to turn in" then
                rows[#rows + 1] = { title = "Ready to turn in", objective = true, status = status }
            else
                local objectives = active[id] and safe(log.GetQuestObjectives, id)
                if type(objectives) == "table" then for _, objective in ipairs(objectives) do
                    if not ns.Secret(objective) and type(objective) == "table" and not ns.Secret(objective.text) and type(objective.text) == "string" then
                        rows[#rows + 1] = { title = objective.text, objective = true, done = not ns.Secret(objective.finished) and objective.finished == true }
                    end
                end end
            end
        end
    end
    return dungeon.name, rows, done, total, unknown
end

function T:Refresh()
    if not self.frame then return end
    if self.dismissed then self.frame:Hide(); return end
    local name, rows, done, total, unknown = self:Read()
    if not name or not rows then self.frame:Hide(); return end
    if #rows == 0 then
        if not self:GetTracked() then self.frame:Hide(); return end
        rows[1] = { title = "No applicable quests recorded." }
    end
    self.title:SetText((total and total > 0 and ((unknown and "?" or tostring(done)) .. "/" .. total .. "  ") or "") .. name)
    local count = self.collapsed and 0 or math.min(#rows, #self.lines)
    self.offset = math.max(0, math.min(self.offset or 0, math.max(0, #rows - #self.lines)))
    for i, fs in ipairs(self.lines) do
        local row = rows[self.offset + i]
        local button = self.rowButtons[i]
        button.row = row
        if i <= count then
            local statusIcon = row.status == "Completed" and "complete" or row.status == "Unknown" and "unknown" or "quest"
            button.statusIcon:SetShown(row.quest ~= nil)
            button.statusIcon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\tracker-" .. statusIcon)
            if row.status == "Completed" then button.statusIcon:SetVertexColor(0.35, 0.85, 0.4)
            elseif row.unavailable or row.status == "Unknown" then button.statusIcon:SetVertexColor(0.6, 0.6, 0.6)
            else button.statusIcon:SetVertexColor(0.9, 0.69, 0.3) end
            button.chainIcon:SetShown(row.chain == true)
            button.insideIcon:SetShown(row.inside == true)
            local icons = (row.chain and 1 or 0) + (row.inside and 1 or 0)
            button.chainIcon:ClearAllPoints(); button.chainIcon:SetPoint("RIGHT", row.inside and -17 or 0, 0)
            -- Quest rows are the headers; indent their objective/status rows
            -- so the relationship remains clear in the compact tracker.
            local indent = row.objective and 10 or 0
            fs:ClearAllPoints(); fs:SetPoint("LEFT", button, "LEFT", 20 + indent, 0)
            fs:SetWidth(222 - icons * 17 - indent)
            local font, size, flags = fs:GetFont()
            local wanted = row.quest and 11 or 10
            if font and size ~= wanted then fs:SetFont(font, wanted, flags or "") end
            button.questBackground:SetShown(row.quest ~= nil)
            fs:SetText(row.title)
            if row.status == "Completed" or row.done or (row.objective and row.status == "Ready to turn in") then fs:SetTextColor(0.35, 0.85, 0.4)
            elseif row.unavailable then fs:SetTextColor(ns.C.muted[1], ns.C.muted[2], ns.C.muted[3])
            elseif row.status == "In progress" or row.status == "Ready to turn in" then fs:SetTextColor(1, 0.82, 0.25)
            else fs:SetTextColor(ns.C.text[1], ns.C.text[2], ns.C.text[3]) end
            button:Show(); fs:Show()
        else button:Hide(); fs:Hide() end
    end
    local overflow = not self.collapsed and #rows > count
    self.more:SetText(overflow and ((self.offset + 1) .. "–" .. (self.offset + count) .. " / " .. #rows .. "  •  Scroll") or "")
    self.frame:SetHeight(HEADER_H + (count > 0 and 3 or 0) + count * 18 + (overflow and 16 or 0))
    self.frame:Show()
end

local function headerButton(parent)
    local b = CreateFrame("Button", nil, parent); b:SetSize(16, 16); ns.Panel(b, { alpha = 0.9 })
    local hover = b:CreateTexture(nil, "HIGHLIGHT"); hover:SetPoint("TOPLEFT", 1, -1); hover:SetPoint("BOTTOMRIGHT", -1, 1)
    hover:SetColorTexture(1, 0.85, 0.48, 0.12)
    return b
end
local function lineIcon(button, width, height)
    local line = button:CreateTexture(nil, "OVERLAY", nil, 7); line:SetPoint("CENTER"); line:SetSize(width, height)
    line:SetColorTexture(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3], 1)
    return line
end

ns.Module("dungeontracker", "Dungeon quest tracker", function()
    local f = CreateFrame("Frame", "ForeverUIDungeonQuestTracker", UIParent)
    f:SetSize(260, HEADER_H); ns.Panel(f); ns.Place(f, "dungeonQuestTracker", "Dungeon quests", { "TOPRIGHT", "TOPRIGHT", -30, -210 })
    f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) T.offset = math.max(0, (T.offset or 0) - delta * 3); T:Refresh() end)
    local header = CreateFrame("Button", nil, f); header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT"); header:SetHeight(HEADER_H)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if InCombatLockdown and InCombatLockdown() then return end
        f:StartMoving(); T.dragging = true
    end)
    header:SetScript("OnDragStop", function()
        if not T.dragging then return end
        T.dragging = nil; f:StopMovingOrSizing()
        if f.SetUserPlaced then f:SetUserPlaced(false) end
        local x, y = f:GetCenter(); local scale = f:GetEffectiveScale(); local uiScale = UIParent:GetEffectiveScale()
        if not ns.Secret(x) and not ns.Secret(y) and not ns.Secret(scale) and not ns.Secret(uiScale)
            and type(x) == "number" and type(y) == "number" and type(scale) == "number" and type(uiScale) == "number" and uiScale > 0 then
            ns.db.pos.dungeonQuestTracker = { x = x * scale / uiScale, y = y * scale / uiScale }
        end
    end)
    local guideIcon = header:CreateTexture(nil, "ARTWORK"); guideIcon:SetSize(14, 14); guideIcon:SetPoint("LEFT", 6, 0)
    guideIcon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\instance-guide")
    T.title = ns.Text(header, 12, ns.C.bright); T.title:SetPoint("LEFT", 24, 0); T.title:SetWidth(180); T.title:SetJustifyH("LEFT")
    T.title:SetWordWrap(false)
    T.collapsed = ns.db.dungeonTrackerCollapsed == true
    -- Close on the far right, fold beside it: the same order and size as
    -- the farming tracker, with the damage meter's gold-line "-"/"+".
    local close
    local okClose, red = pcall(CreateFrame, "Button", nil, header, "UIPanelCloseButton")
    if okClose and red then
        close = red; close:SetSize(16, 16)
        for _, state in ipairs({ { "SetNormalAtlas", "RedButton-Exit" }, { "SetPushedAtlas", "RedButton-exit-pressed" },
            { "SetDisabledAtlas", "RedButton-Exit-Disabled" }, { "SetHighlightAtlas", "RedButton-Highlight" } }) do
            if type(close[state[1]]) == "function" then pcall(close[state[1]], close, state[2]) end
        end
    else
        close = headerButton(header)
        local closeText = ns.Text(close, 11, ns.C.bright); closeText:SetPoint("CENTER"); closeText:SetText("×")
    end
    close:ClearAllPoints(); close:SetPoint("TOPRIGHT", -3, -3)
    local collapse = headerButton(header); collapse:SetPoint("RIGHT", close, "LEFT", -2, 0)
    lineIcon(collapse, 8, 2)
    local plus = lineIcon(collapse, 2, 8); plus:SetShown(T.collapsed)
    collapse:SetScript("OnClick", function() T.collapsed = not T.collapsed; ns.db.dungeonTrackerCollapsed = T.collapsed; plus:SetShown(T.collapsed); T:Refresh() end)
    header:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Instance quests", 1, 0.82, 0, 1)
        GameTooltip:AddLine("Drag to move. Green check: completed; gold !: active or not completed; grey ?: unknown. Chain: recorded quest chain. Gate: starts inside the instance.", 1, 1, 1, true); GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    close:SetScript("OnClick", function() T:SetTracked(nil) end)
    T.lines, T.rowButtons, T.header, T.collapse = {}, {}, header, collapse
    for i = 1, 12 do
        local row = CreateFrame("Button", nil, f); row:SetSize(244, 18); row:SetPoint("TOPLEFT", 8, -(HEADER_H + 2) - (i - 1) * 18)
        row.questBackground = row:CreateTexture(nil, "BACKGROUND")
        row.questBackground:SetAllPoints(); row.questBackground:SetColorTexture(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], 0.07)
        local highlight = row:CreateTexture(nil, "HIGHLIGHT"); highlight:SetAllPoints(); highlight:SetColorTexture(1, 0.82, 0.3, 0.12)
        row.statusIcon = row:CreateTexture(nil, "ARTWORK"); row.statusIcon:SetSize(15, 15); row.statusIcon:SetPoint("LEFT", 0, 0)
        row.chainIcon = row:CreateTexture(nil, "ARTWORK"); row.chainIcon:SetSize(15, 15); row.chainIcon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\tracker-chain"); row.chainIcon:SetVertexColor(0.9, 0.69, 0.3)
        row.insideIcon = row:CreateTexture(nil, "ARTWORK"); row.insideIcon:SetSize(15, 15); row.insideIcon:SetPoint("RIGHT"); row.insideIcon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\dungeons-minimal")
        local text = ns.Text(row, 10, ns.C.text); text:SetPoint("LEFT", 20, 0); text:SetWidth(222); text:SetJustifyH("LEFT"); text:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            local info, guide = self.row, ns.InstanceGuide
            if not (info and info.quest and info.dungeon and guide) then return end
            guide:Build(); guide.dungeon, guide.entry, guide.view, guide.entryOffset = info.dungeon, info.quest, "Quests", 0
            guide.frame:Show(); guide:Render()
        end)
        row:SetScript("OnEnter", function(self)
            local info = self.row
            if not (info and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(info.title or "Quest", 1, 0.82, 0, 1)
            if info.status then GameTooltip:AddLine(info.status, 1, 1, 1) end
            if info.chain then GameTooltip:AddLine("Part of a recorded quest chain", 0.8, 0.8, 0.8) end
            if info.inside then GameTooltip:AddLine("Starts inside the instance", 0.8, 0.8, 0.8) end
            if info.quest then GameTooltip:AddLine("Click to open quest details", 1, 0.82, 0) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        T.lines[i], T.rowButtons[i] = text, row
    end
    T.more = ns.Text(f, 9, ns.C.muted); T.more:SetPoint("BOTTOMLEFT", 8, 3)
    T.frame = f; f:Hide()
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN" }) do
        local eventName = event
        ns.On(event, function()
            if eventName == "ZONE_CHANGED_NEW_AREA" then T.dismissed = false end
            local page = ns.Encyclopedia and ns.Encyclopedia.QuestPage
            if page then page.statusCache = {} end
            T:Refresh()
        end)
    end
    T:Refresh()
end)

-- Quest objective marks use client tooltip data and the attributed QuestieDB
-- drop snapshot. Unknown or restricted data is left unmarked.
local _, ns = ...
local marks = {}
ns.QuestMarks = marks
local kinds = {}

local function normalize(text) return text:lower():gsub("[%d%p%s]", "") end
function marks:ReadLog()
    kinds = {}
    local log = C_QuestLog
    if not (log and log.GetNumQuestLogEntries and log.GetInfo and log.GetQuestObjectives) then return end
    local ok, count = pcall(log.GetNumQuestLogEntries)
    if not ok or ns.Secret(count) or type(count) ~= "number" then return end
    for index = 1, count do
        local success, info = pcall(log.GetInfo, index)
        if success and type(info) == "table" and not ns.Secret(info) and not ns.Secret(info.isHeader) and not info.isHeader and not ns.Secret(info.questID) and info.questID then
            local got, objectives = pcall(log.GetQuestObjectives, info.questID)
            if got and type(objectives) == "table" and not ns.Secret(objectives) then
                for _, objective in ipairs(objectives) do
                    if type(objective) == "table" and not ns.Secret(objective) and type(objective.text) == "string" and not ns.Secret(objective.text)
                        and not ns.Secret(objective.type) and (objective.type == "monster" or objective.type == "item") then kinds[normalize(objective.text)] = objective.type end
                end
            end
        end
    end
end

local function lootObjective(unit)
    if not (UnitGUID and C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetQuestObjectives) then return end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or type(guid) ~= "string" or ns.Secret(guid) then return end
    local id = tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
    local ref = ns.IndependentReference; local list = id and ref and ref.QUEST_DROPS and ref.QUEST_DROPS[id]
    if type(list) ~= "string" then return end
    for questID, itemID in list:gmatch("(%d+):(%d+)") do
        questID, itemID = tonumber(questID), tonumber(itemID)
        local got, index = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
        if got and not ns.Secret(index) and type(index) == "number" and index > 0 then
            local itemName
            if C_Item and C_Item.GetItemNameByID then local valid, name = pcall(C_Item.GetItemNameByID, itemID); if valid and not ns.Secret(name) then itemName = name end end
            local success, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
            if success and type(objectives) == "table" and not ns.Secret(objectives) and type(itemName) == "string" then
                for _, objective in ipairs(objectives) do
                    if type(objective) == "table" and not ns.Secret(objective) and not ns.Secret(objective.type) and objective.type == "item" and not ns.Secret(objective.finished) and objective.finished == false
                        and type(objective.text) == "string" and not ns.Secret(objective.text) and objective.text:find(itemName, 1, true) then
                        local a, b = objective.numFulfilled, objective.numRequired
                        if not ns.Secret(a) and not ns.Secret(b) and type(a) == "number" and type(b) == "number" and a < b then return "item", a .. "/" .. b end
                    end
                end
            end
        end
    end
end

function marks:Objective(unit)
    local tooltipType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective
    if tooltipType and C_TooltipInfo and C_TooltipInfo.GetUnit then
        local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
        if ok and type(data) == "table" and not ns.Secret(data) and type(data.lines) == "table" and not ns.Secret(data.lines) then
            for _, line in ipairs(data.lines) do
                if type(line) == "table" and not ns.Secret(line) then
                    if TooltipUtil and TooltipUtil.SurfaceArgs and not ns.Secret(line.leftText) and line.leftText == nil then pcall(TooltipUtil.SurfaceArgs, line) end
                    local text = line.leftText
                    if not ns.Secret(line.type) and line.type == tooltipType and type(text) == "string" and not ns.Secret(text) then
                        local have, need = text:match("(%d+)%s*/%s*(%d+)"); have, need = tonumber(have), tonumber(need)
                        if have and need and have < need then
                            local kind = kinds[normalize(text)]
                            if not kind and (text:lower():find("slain", 1, true) or text:lower():find("killed", 1, true)) then kind = "monster" end
                            return kind or "quest", have .. "/" .. need
                        end
                    end
                end
            end
        end
    end
    return lootObjective(unit)
end

local function safeBar(bar)
    if not bar then return false end
    if bar.IsForbidden then local ok, forbidden = pcall(bar.IsForbidden, bar); if not ok or ns.Secret(forbidden) or forbidden then return false end end
    if InCombatLockdown and InCombatLockdown() then
        if not bar.IsProtected then return false end
        local ok, protected = pcall(bar.IsProtected, bar)
        if not ok or ns.Secret(protected) or protected then return false end
    end
    return true
end
function marks:Update(unit)
    local module = ns.modules and ns.modules.nameplates
    local data = module and module.units and module.units[unit]
    local bar = data and data.bar
    if not safeBar(bar) then return end
    local mark = bar.fuiQuestMark
    if not ns.Opt("qolQuestMarks") then if mark then mark:Hide() end; return end
    local kind, progress = self:Objective(unit)
    if not kind then if mark then mark:Hide() end; return end
    if not mark then
        if InCombatLockdown and InCombatLockdown() then return end
        mark = CreateFrame("Frame", nil, bar); mark:SetSize(20, 20); mark:SetPoint("RIGHT", bar, "LEFT", -4, 0)
        mark:SetFrameLevel((bar:GetFrameLevel() or 0) + 5)
        mark.icon = mark:CreateTexture(nil, "ARTWORK"); mark.icon:SetAllPoints()
        mark.text = ns.Text(mark, 9, ns.C.text, "OVERLAY"); mark.text:SetPoint("TOP", mark, "BOTTOM", 0, 0)
        bar.fuiQuestMark = mark
    end
    mark.icon:SetTexture(kind == "monster" and "Interface\\Cursor\\Attack" or kind == "item" and "Interface\\Cursor\\Pickup" or "Interface\\GossipFrame\\AvailableQuestIcon")
    mark.text:SetText(progress); mark:Show()
end
function marks:Refresh()
    if ns.Opt("qolQuestMarks") then self:ReadLog() end
    local module = ns.modules and ns.modules.nameplates
    for unit in pairs(module and module.units or {}) do self:Update(unit) end
end
local pending
local function queue()
    if not ns.Opt("qolQuestMarks") then return end
    if pending then return end; pending = true
    local function run() pending = false; marks:Refresh() end
    if C_Timer and C_Timer.After then C_Timer.After(0.15, run) else run() end
end
for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do ns.On(event, queue) end
ns.On("NAME_PLATE_UNIT_REMOVED", function(_, unit) local module = ns.modules and ns.modules.nameplates; local data = module and module.units and module.units[unit]; if data and data.bar and data.bar.fuiQuestMark then data.bar.fuiQuestMark:Hide() end end)

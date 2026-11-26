-- Small, opt-in conveniences. Keep independent of the screen skin modules.
local _, ns = ...

function ns.ApplyCameraZoom()
    ns.WhenSafe(function()
        local get = (C_CVar and C_CVar.GetCVar) or GetCVar
        local set = (C_CVar and C_CVar.SetCVar) or SetCVar
        if not (get and set and ns.db) then return end
        local ok, current = pcall(get, "cameraDistanceMaxZoomFactor")
        if not ok or ns.Secret(current) or current == nil then return end
        local saved = ns.db.cameraZoomOriginal
        if ns.Opt("qolCameraZoom") then
            if not saved then ns.db.cameraZoomOriginal = tostring(current) end
            local changed, result = pcall(set, "cameraDistanceMaxZoomFactor", "4")
            if not changed or result == false then changed, result = pcall(set, "cameraDistanceMaxZoomFactor", "2.6") end
            if changed and result ~= false then
                local got, actual = pcall(get, "cameraDistanceMaxZoomFactor")
                if got and actual and not ns.Secret(actual) then ns.db.cameraZoomApplied = tostring(actual) end
            end
        elseif saved then
            if ns.db.cameraZoomApplied and tostring(current) == ns.db.cameraZoomApplied then pcall(set, "cameraDistanceMaxZoomFactor", saved) end
            ns.db.cameraZoomOriginal, ns.db.cameraZoomApplied = nil, nil
        end
    end)
end
ns.On("PLAYER_LOGIN", ns.ApplyCameraZoom)

function ns.ApplyQuestSparkles()
    ns.WhenSafe(function()
        local get, set = (C_CVar and C_CVar.GetCVar) or GetCVar, (C_CVar and C_CVar.SetCVar) or SetCVar
        if not (get and set and ns.db) then return end
        local ok, current = pcall(get, "outlineModeShowLootEffectWhenDisabled")
        if not ok or current == nil or ns.Secret(current) then return end
        if ns.Opt("qolQuestSparkles") then
            if ns.db.questSparkleOriginal == nil then ns.db.questSparkleOriginal = tostring(current) end
            pcall(set, "outlineModeShowLootEffectWhenDisabled", "1")
        elseif ns.db.questSparkleOriginal ~= nil then
            if tostring(current) == "1" then pcall(set, "outlineModeShowLootEffectWhenDisabled", ns.db.questSparkleOriginal) end
            ns.db.questSparkleOriginal = nil
            ns.Print("Quest glow may require a game restart to fully switch off.")
        end
    end)
end
ns.On("PLAYER_LOGIN", ns.ApplyQuestSparkles)

-- Reward values are advisory. Wait until every choice has a cached price so
-- the marker never implies an incomplete comparison is the best one.
function ns.MarkQuestRewards()
    local groups, enabled = {}, ns.Opt("qolQuestVendor")
    for _, name in ipairs({ "QuestInfoRewardsFrame", "MapQuestInfoRewardsFrame" }) do
        local frame = _G[name]
        if frame and type(frame.RewardButtons) == "table" then
            groups[#groups + 1] = { buttons = frame.RewardButtons, log = name == "MapQuestInfoRewardsFrame" or (QuestInfoFrame and QuestInfoFrame.questLog == true) }
        end
    end
    for _, group in ipairs(groups) do
        local values, best, missing = {}, 0, false
        for _, b in ipairs(group.buttons) do
            if b.fuiVendorCoin then b.fuiVendorCoin:Hide() end
            if enabled and b.IsShown and b:IsShown() and b.type == "choice" and b.GetID then
                local id = b:GetID()
                local linkFn = group.log and GetQuestLogItemLink or GetQuestItemLink
                local infoFn = group.log and GetQuestLogChoiceInfo or GetQuestItemInfo
                local ok, link, count = false, nil, 1
                if linkFn then ok, link = pcall(linkFn, "choice", id) end
                if ok and link and not ns.Secret(link) and infoFn then
                    local got, _, _, amount
                    if group.log then got, _, _, amount = pcall(infoFn, id) else got, _, _, amount = pcall(infoFn, "choice", id) end
                    if got and type(amount) == "number" and not ns.Secret(amount) then count = math.max(1, amount) end
                end
                local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
                local price
                if ok and link and getInfo then
                    local data = { pcall(getInfo, link) }
                    if data[1] and type(data[12]) == "number" and not ns.Secret(data[12]) then price = data[12] end
                end
                if price == nil then missing = true else
                    local value = price * count; values[#values + 1] = { button = b, value = value }; best = math.max(best, value)
                end
            end
        end
        if not missing and #values >= 2 and best > 0 then
            for _, entry in ipairs(values) do
                if entry.value == best then
                    local b = entry.button
                    if not b.fuiVendorCoin then
                        b.fuiVendorCoin = b:CreateTexture(nil, "OVERLAY", nil, 7); b.fuiVendorCoin:SetSize(14, 14)
                        b.fuiVendorCoin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
                        b.fuiVendorCoin:SetPoint("TOPRIGHT", b.Icon or b, "TOPRIGHT", -1, -1)
                    end
                    b.fuiVendorCoin:Show()
                end
            end
        end
    end
end

local questRewardsPending
local function queueQuestRewards()
    if questRewardsPending then return end
    questRewardsPending = true
    local function update() questRewardsPending = false; ns.MarkQuestRewards() end
    if C_Timer and C_Timer.After then C_Timer.After(0.1, update) else update() end
end
local hookedQuestDisplay
local function hookQuestDisplay()
    if not hookedQuestDisplay and type(QuestInfo_Display) == "function" and type(hooksecurefunc) == "function" then
        hooksecurefunc("QuestInfo_Display", queueQuestRewards); hookedQuestDisplay = true
    end
end
ns.On("ADDON_LOADED", hookQuestDisplay)
ns.On("PLAYER_LOGIN", hookQuestDisplay)
for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_LOG_UPDATE", "GET_ITEM_INFO_RECEIVED" }) do ns.On(event, queueQuestRewards) end

local function questAutomationEnabled(option)
    if not ns.Opt(option) then return false end
    if IsShiftKeyDown then
        local ok, shift = pcall(IsShiftKeyDown)
        if not ok or ns.Secret(shift) or shift then return false end
    end
    return true
end

-- Quests at an NPC, one after another (2026-11-26: "accept all in a row
-- automatically" - before, an NPC offering more than one quest, or a quest
-- beside other dialogue options, was left alone). Each time the NPC's list
-- opens - and it opens again after every accept or turn-in - the next quest
-- is picked: finished turn-ins first, then new quests. Covers both the
-- gossip window (C_GossipInfo) and the classic quest greeting window
-- (QUEST_GREETING). Never picks a non-quest dialogue option.
--
-- Left alone: repeatable and daily quests, grey (trivial) quests, and
-- turn-ins that aren't finished. A quest picked in the last 15 seconds isn't
-- picked again, so one the game won't give you (a full quest log) can't loop.
-- Hold Shift to pause.
local REPICK_AFTER = 15
local picked = {}
ns.QuestAutoPicked = picked
local function now() return (GetTime and GetTime()) or 0 end
local function recentlyPicked(id)
    local at = picked[id]
    return at ~= nil and now() - at < REPICK_AFTER
end
local function yes(v) return v == true or v == 1 end

-- Repeatable or daily? nil when nothing says (treated as a normal quest).
local function repeatable(id, info)
    if type(info) == "table" then
        if ns.Secret(info.repeatable) or ns.Secret(info.isRepeatable) or ns.Secret(info.frequency) then return true end
        if yes(info.repeatable) or yes(info.isRepeatable) then return true end
        if type(info.frequency) == "number" and info.frequency ~= 0 then return true end
    end
    if type(id) == "number" and C_QuestLog and C_QuestLog.IsRepeatableQuest then
        local ok, value = pcall(C_QuestLog.IsRepeatableQuest, id)
        if not ok or ns.Secret(value) then return true end
        if yes(value) then return true end
    end
    return false
end

local function questOk(id, info)
    if ns.Secret(id) or type(id) ~= "number" or id <= 0 or recentlyPicked(id) then return false end
    if type(info) == "table" and (ns.Secret(info.isTrivial) or yes(info.isTrivial)) then return false end
    return not repeatable(id, info)
end
-- Kept for the old name some tests use.
local function gossipQuestSafe(quest)
    return type(quest) == "table" and not ns.Secret(quest) and questOk(quest.questID, quest)
end

local function pick(id, choose, arg)
    picked[id] = now()
    local ok, result = pcall(choose, arg)
    if not ok or result == false then picked[id] = nil end
    return ok and result ~= false
end

local function autoGossipQuest()
    local accept, turnIn = questAutomationEnabled("qolAutoQuestAccept"), questAutomationEnabled("qolAutoQuestTurnIn")
    if not (accept or turnIn) then return end
    local gossip = C_GossipInfo
    if not (gossip and gossip.GetActiveQuests and gossip.GetAvailableQuests) then return end
    local okActive, active = pcall(gossip.GetActiveQuests)
    local okAvailable, available = pcall(gossip.GetAvailableQuests)
    if not (okActive and okAvailable) or ns.Secret(active) or ns.Secret(available)
        or type(active) ~= "table" or type(available) ~= "table" then return end
    if turnIn and gossip.SelectActiveQuest then
        for _, quest in ipairs(active) do
            if type(quest) == "table" and not ns.Secret(quest) and not ns.Secret(quest.isComplete) and yes(quest.isComplete)
                and gossipQuestSafe(quest) then
                if pick(quest.questID, gossip.SelectActiveQuest, quest.questID) then return end
            end
        end
    end
    if accept and gossip.SelectAvailableQuest then
        for _, quest in ipairs(available) do
            if gossipQuestSafe(quest) then
                if pick(quest.questID, gossip.SelectAvailableQuest, quest.questID) then return end
            end
        end
    end
end
ns.On("GOSSIP_SHOW", autoGossipQuest)

-- The classic quest greeting: quests by position in the list.
local function questComplete(id)
    if type(id) ~= "number" then return false end
    for _, fn in ipairs({ C_QuestLog and C_QuestLog.IsComplete, IsQuestComplete }) do
        if type(fn) == "function" then
            local ok, done = pcall(fn, id)
            if ok and not ns.Secret(done) then return yes(done) end
        end
    end
    return false
end
local function autoGreetingQuest()
    local accept, turnIn = questAutomationEnabled("qolAutoQuestAccept"), questAutomationEnabled("qolAutoQuestTurnIn")
    if not (accept or turnIn) then return end
    if turnIn and type(GetNumActiveQuests) == "function" and type(SelectActiveQuest) == "function"
        and type(GetActiveQuestID) == "function" then
        local ok, n = pcall(GetNumActiveQuests)
        if ok and not ns.Secret(n) and type(n) == "number" then
            for i = 1, n do
                local got, id = pcall(GetActiveQuestID, i)
                if got and questOk(id) and questComplete(id) then
                    if pick(id, SelectActiveQuest, i) then return end
                end
            end
        end
    end
    if accept and type(GetNumAvailableQuests) == "function" and type(SelectAvailableQuest) == "function" then
        local ok, n = pcall(GetNumAvailableQuests)
        if not ok or ns.Secret(n) or type(n) ~= "number" then return end
        for i = 1, n do
            local info, id = {}, nil
            if type(GetAvailableQuestInfo) == "function" then
                local got, isTrivial, frequency, isRepeatable, _, questID = pcall(GetAvailableQuestInfo, i)
                if got then
                    info = { isTrivial = isTrivial, frequency = frequency, isRepeatable = isRepeatable }
                    id = questID
                end
            end
            -- No quest ID from this client: the title stands in, so the
            -- 15-second memory still works.
            if (id == nil or id == 0) and type(GetAvailableTitle) == "function" then
                local got, title = pcall(GetAvailableTitle, i)
                if got and type(title) == "string" and not ns.Secret(title) then
                    if not recentlyPicked(title) and not (ns.Secret(info.isTrivial) or yes(info.isTrivial))
                        and not repeatable(nil, info) then
                        if pick(title, SelectAvailableQuest, i) then return end
                    end
                end
            elseif questOk(id, info) then
                if pick(id, SelectAvailableQuest, i) then return end
            end
        end
    end
end
ns.On("QUEST_GREETING", autoGreetingQuest)

ns.On("QUEST_DETAIL", function()
    if questAutomationEnabled("qolAutoQuestAccept") and type(AcceptQuest) == "function" then pcall(AcceptQuest) end
end)

ns.On("QUEST_PROGRESS", function()
    if not questAutomationEnabled("qolAutoQuestTurnIn") or type(IsQuestCompletable) ~= "function" or type(CompleteQuest) ~= "function" then return end
    local ok, complete = pcall(IsQuestCompletable)
    if ok and not ns.Secret(complete) and (complete == true or complete == 1) then pcall(CompleteQuest) end
end)

ns.On("QUEST_COMPLETE", function()
    if not questAutomationEnabled("qolAutoQuestTurnIn") or type(GetNumQuestChoices) ~= "function" or type(GetQuestReward) ~= "function" then return end
    local ok, choices = pcall(GetNumQuestChoices)
    if ok and not ns.Secret(choices) and type(choices) == "number" and choices == 0 then pcall(GetQuestReward, 0) end
end)

ns.On("LOOT_OPENED", function()
    if not ns.Opt("qolQuickLoot") or not (GetNumLootItems and LootSlot) then return end
    local getAuto = C_CVar and C_CVar.GetCVarBool or GetCVarBool
    if not getAuto then return end
    local ok, enabled = pcall(getAuto, "autoLootDefault")
    if not ok or ns.Secret(enabled) then return end
    local modified = IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") or false
    if ns.Secret(modified) or (not not enabled) == (not not modified) then return end
    local count = GetNumLootItems()
    if ns.Secret(count) or type(count) ~= "number" then return end
    for slot = count, 1, -1 do pcall(LootSlot, slot) end
end)

ns.On("MERCHANT_SHOW", function()
    if not ns.Opt("qolAutoRepair") or not (CanMerchantRepair and GetRepairAllCost and GetMoney and RepairAllItems) then return end
    if not CanMerchantRepair() then return end
    local cost, allowed = GetRepairAllCost()
    local money = GetMoney()
    if ns.Secret(cost) or ns.Secret(allowed) or ns.Secret(money)
        or type(cost) ~= "number" or type(money) ~= "number" or not allowed or cost <= 0 then return end
    if money < cost then
        ns.Print("not enough gold to repair your equipment.")
        return
    end
    local ok = pcall(RepairAllItems, false)
    if not ok then ns.Print("the game could not repair your equipment.") end
end)

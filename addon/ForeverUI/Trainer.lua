-- Read-only class spell guide using the attributed independent reference data.
local _, ns = ...
local ref = ns.IndependentReference
local trainer = { page = "spells", mode = "all", offset = 0, expanded = {} }
ns.TrainerGuide = trainer
local classes = {
    {1, "WARRIOR", "Warrior", "INV_Sword_27"}, {2, "PALADIN", "Paladin", "Spell_Holy_HolyBolt"},
    {3, "HUNTER", "Hunter", "INV_Weapon_Bow_07"}, {4, "ROGUE", "Rogue", "INV_ThrowingKnife_04"},
    {5, "PRIEST", "Priest", "Spell_Holy_PowerWordShield"}, {7, "SHAMAN", "Shaman", "Spell_Nature_Lightning"},
    {8, "MAGE", "Mage", "Spell_Frost_FrostBolt02"}, {9, "WARLOCK", "Warlock", "Spell_Shadow_ShadowBolt"},
    {11, "DRUID", "Druid", "Ability_Druid_Maul"},
}
local function playerClass()
    if UnitClass then local ok, _, _, id = pcall(UnitClass, "player"); if ok and not ns.Secret(id) then return id end end
end
local function classInfo(id)
    for _, class in ipairs(classes) do if class[1] == id then return class end end
end
local function money(copper)
    if type(copper) ~= "number" or copper < 0 then return "?" end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t" end
    if s > 0 then parts[#parts + 1] = s .. "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t" end
    return table.concat(parts, " ")
end

local function knownSpell(id)
    local attempted = false
    for _, fn in ipairs({ IsPlayerSpell or false, IsSpellKnown or false, (C_SpellBook and C_SpellBook.IsSpellKnown) or false }) do
        if fn then
            local ok, value = pcall(fn, id)
            if ok and not ns.Secret(value) and (type(value) == "boolean" or value == 1 or value == 0) then
                attempted = true; if value == true or value == 1 then return true end
            end
        end
    end
    if attempted then return false end
end

local function petStore()
    if type(ns.db) ~= "table" then return nil end
    local id
    if UnitGUID then local ok, value = pcall(UnitGUID, "player"); if ok and not ns.Secret(value) and type(value) == "string" and value ~= "" then id = value end end
    if not id and UnitFullName then local ok, name, realm = pcall(UnitFullName, "player"); if ok and not ns.Secret(name) and type(name) == "string" and not ns.Secret(realm) then id = tostring(realm or "") .. ":" .. name end end
    if not id then return nil end
    ns.db.trainerPetRanks = ns.db.trainerPetRanks or {}
    ns.db.trainerPetRanks[id] = ns.db.trainerPetRanks[id] or { ranks = {} }
    local saved = ns.db.trainerPetRanks[id]; saved.ranks = saved.ranks or {}
    return saved
end

local function addPetRank(name, rank)
    local saved = petStore()
    if not (saved and type(name) == "string" and type(rank) == "number" and rank > 0) then return false end
    saved.ranks[name] = saved.ranks[name] or {}
    if saved.ranks[name][rank] then return false end
    saved.ranks[name][rank] = true; return true
end

function trainer:PetRankStatus(name, rank)
    if playerClass() ~= 3 then return nil end
    local saved = petStore()
    if not saved then return nil end
    return saved.ranks[name] and saved.ranks[name][rank] and "Known" or "Not recorded"
end

local function petAliases()
    local aliases = {}
    for _, ability in ipairs(ref and ref.PET_ABILITIES or {}) do aliases[ability.name] = ability.name end
    local spellName = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
    if spellName then
        for id, info in pairs(ref and ref.PET_TEACH_SPELLS or {}) do
            if type(info) == "table" and info[1] and not aliases["#" .. info[1]] then
                local ok, value = pcall(spellName, id)
                if ok and not ns.Secret(value) and type(value) == "string" and value ~= "" then aliases[value] = info[1]; aliases["#" .. info[1]] = true end
            end
        end
    end
    return aliases
end

function trainer:ImportPetRanks()
    local old, saved = _G.OneForAllCharDB, petStore()
    if not (saved and type(old) == "table" and type(old.petAbilities) == "table") then return end
    if saved.imported then return end
    local aliases = petAliases()
    for name, ranks in pairs(old.petAbilities) do
        local canonical = aliases[name]
        if canonical then
            if type(ranks) == "number" then addPetRank(canonical, ranks)
            elseif type(ranks) == "table" then for rank, value in pairs(ranks) do if value and tonumber(rank) then addPetRank(canonical, tonumber(rank)) end end end
        end
    end
    saved.imported = true
end

-- Beast Training only lists ranks relevant to the current pet; merge what it
-- confirms instead of treating absent ranks as unknown or removing them.
function trainer:ScanBeastTraining()
    if playerClass() ~= 3 or not (GetCraftDisplaySkillLine and GetNumCrafts and GetCraftInfo) then return end
    local ok, line = pcall(GetCraftDisplaySkillLine)
    if not ok or ns.Secret(line) or type(line) ~= "string" or line == "" then return end
    local ownName
    local spellName = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
    if spellName then local got, value = pcall(spellName, 5149); if got and not ns.Secret(value) then ownName = value end end
    if line ~= "Beast Training" and line ~= BEAST_TRAINING and line ~= ownName then return end
    local got, count = pcall(GetNumCrafts)
    if not got or ns.Secret(count) or type(count) ~= "number" or count <= 0 then return end
    local aliases, changed = petAliases(), false
    for index = 1, count do
        local valid, name, sub, kind = pcall(GetCraftInfo, index)
        if valid and not ns.Secret(name) and not ns.Secret(sub) and not ns.Secret(kind) and type(name) == "string" and kind ~= "header" then
            local canonical = aliases[name]
            local rank = type(sub) == "string" and tonumber(sub:match("(%d+)"))
            if canonical and not rank then
                for _, ability in ipairs(ref and ref.PET_ABILITIES or {}) do
                    if ability.name == canonical and type(ability.ranks) == "table" and #ability.ranks == 1 then rank = tonumber(ability.ranks[1].rank) or 1; break end
                end
            end
            if canonical and rank and addPetRank(canonical, rank) then changed = true end
        end
    end
    local saved = petStore(); if saved then saved.scanned = true end
    if changed and self.frame and self.frame:IsShown() then self:Render() end
end

function trainer:ScanKnownPetSpells()
    if playerClass() ~= 3 then return end
    local hits, total = {}, 0
    for id, info in pairs(ref and ref.PET_TEACH_SPELLS or {}) do
        total = total + 1
        if type(info) == "table" and knownSpell(id) == true then hits[#hits + 1] = info end
    end
    -- Some clients report every ID as known. Such a scan proves nothing.
    if total == 0 or #hits > total * 0.9 then return end
    local changed = false
    for _, info in ipairs(hits) do if addPetRank(info[1], info[2]) then changed = true end end
    if changed and self.frame and self.frame:IsShown() then self:Render() end
end

function trainer:BuildList()
    local ownClass, raceID, level = playerClass()
    local classID = self.viewClass or ownClass
    local own = classID == ownClass
    if UnitRace then local ok, _, _, id = pcall(UnitRace, "player"); if ok and not ns.Secret(id) then raceID = id end end
    if UnitLevel then local ok, value = pcall(UnitLevel, "player"); if ok and not ns.Secret(value) then level = value end end
    level = type(level) == "number" and level or 1
    local spells = ref and ref.TRAINER_SPELLS and ref.TRAINER_SPELLS[classID] or {}
    local highest, knowledge = {}, {}
    for _, spell in ipairs(spells) do
        local known = own and knownSpell(spell[2]); if own then knowledge[spell[2]] = known end
        if known then highest[spell[3]] = math.max(highest[spell[3]] or -1, tonumber(spell[4]) or 0) end
    end
    -- The client replaces Bear Form in the spellbook with Dire Bear Form.
    if knowledge[9634] then knowledge[5487] = true end
    local rows = {}
    for _, spell in ipairs(spells) do
        local required, id, name, rank, mask, talent, icon, quest = unpack(spell)
        required, rank, mask = tonumber(required) or 1, tonumber(rank) or 0, tonumber(mask) or 0
        local bit = type(raceID) == "number" and ((raceID == 95 and 32) or (raceID == 96 and 33) or (raceID - 1))
        local raceOK = not own or mask == 0 or not bit or math.floor(mask / 2 ^ bit) % 2 == 1
        local known = knowledge[id] == true or (highest[name] ~= nil and highest[name] >= rank)
        local available = required <= level
        if raceOK and not known and (self.mode == "all" or self.mode == "available" and available or self.mode == "upcoming" and not available) then
            rows[#rows + 1] = { id = id, name = name, rank = rank, level = required, icon = icon, quest = quest,
                talent = talent and true or false, knownUnknown = own and knowledge[id] == nil, available = available,
                cost = ns.db and ns.db.trainerCosts and ns.db.trainerCosts[classID] and ns.db.trainerCosts[classID][id] }
        end
    end
    table.sort(rows, function(a, b) if a.level ~= b.level then return a.level < b.level end if a.name ~= b.name then return a.name < b.name end return a.rank < b.rank end)
    return rows, level
end

function trainer:BuildLowRanks()
    local classID
    if UnitClass then local ok, _, _, id = pcall(UnitClass, "player"); if ok and not ns.Secret(id) then classID = id end end
    local spells = ref and ref.TRAINER_SPELLS and ref.TRAINER_SPELLS[classID] or {}
    local byID, best = {}, {}
    for _, spell in ipairs(spells) do
        local id, name, rank = spell[2], spell[3], tonumber(spell[4]) or 0
        byID[id] = spell
        if rank > 0 and knownSpell(id) == true and (not best[name] or rank > best[name][4]) then best[name] = spell end
    end
    local rows, seen, kept = {}, {}, self:KeptRanks()
    if type(GetActionInfo) ~= "function" then return rows end
    for _, range in ipairs({ {1, 120}, {145, 180} }) do
        for slot = range[1], range[2] do
            local ok, kind, id = pcall(GetActionInfo, slot)
            if ok and not ns.Secret(kind) and not ns.Secret(id) and kind == "spell" then
                local current = byID[id]; local higher = current and best[current[3]]
                if current and higher and not kept[id] and (tonumber(current[4]) or 0) > 0 and higher[4] > current[4] then
                    local row = seen[id]
                    if not row then
                        row = { id = id, name = current[3], rank = current[4], icon = higher[7], newID = higher[2], newRank = higher[4], slots = {} }
                        rows[#rows + 1], seen[id] = row, row
                    end
                    row.slots[#row.slots + 1] = slot
                end
            end
        end
    end
    table.sort(rows, function(a, b) if a.name == b.name then return a.rank < b.rank end return a.name < b.name end)
    return rows
end

function trainer:KeptRanks()
    local id
    if UnitGUID then local ok, value = pcall(UnitGUID, "player"); if ok and type(value) == "string" and not ns.Secret(value) and value ~= "" then id = value end end
    if not (id and ns.db) then self.sessionKeeps = self.sessionKeeps or {}; return self.sessionKeeps end
    ns.db.trainerRankKeeps = ns.db.trainerRankKeeps or {}; ns.db.trainerRankKeeps[id] = ns.db.trainerRankKeeps[id] or {}
    return ns.db.trainerRankKeeps[id]
end
function trainer:ClearKeptRanks()
    local kept = self:KeptRanks(); for id in pairs(kept) do kept[id] = nil end
    self.notifiedRanks = {}
    if self.frame and self.frame:IsShown() then self:Render() end
    ns.Print("Kept spell ranks will be included in the next check.")
end
function trainer:ImportKeptRanks()
    local old = type(_G.OneForAllDB) == "table" and type(_G.OneForAllDB.qol) == "table" and _G.OneForAllDB.qol.lowRankKeep
    if type(old) ~= "table" or not (ns.db and UnitGUID) then return end
    local ok, id = pcall(UnitGUID, "player")
    if not ok or ns.Secret(id) or type(id) ~= "string" or id == "" then return end
    ns.db.trainerRankImports = ns.db.trainerRankImports or {}
    if ns.db.trainerRankImports[id] then return end
    local classID, valid = playerClass(), {}
    for _, spell in ipairs(ref and ref.TRAINER_SPELLS and ref.TRAINER_SPELLS[classID] or {}) do valid[spell[2]] = true end
    if not next(valid) then return end
    local kept = self:KeptRanks()
    for spellID, value in pairs(old) do
        local number = tonumber(spellID)
        if value and number and valid[number] then kept[number] = true end
    end
    ns.db.trainerRankImports[id] = true
end

local function faction()
    if UnitFactionGroup then local ok, value = pcall(UnitFactionGroup, "player"); if ok and not ns.Secret(value) then if value == "Horde" then return "H" elseif value == "Alliance" then return "A" end end end
end
local function factionMatches(side)
    local player = faction()
    return not player or not side or side:find(player, 1, true) ~= nil
end
local function locationRow(t, icon)
    return { kind = "location", name = t.name, description = (t.city or "Unknown zone") .. (t.x and t.y and ("  •  " .. t.x .. ", " .. t.y) or ""),
        icon = "Interface\\Icons\\" .. icon, mapID = t.map, x = t.x, y = t.y, npcID = t.npc }
end

function trainer:BuildWeaponLines()
    local rows, class = {}, classInfo(self.viewClass or playerClass())
    local token = class and class[2]; local own = class and class[1] == playerClass()
    for _, sub in ipairs(ref and ref.CLASS_WEAPONS and ref.CLASS_WEAPONS[token] or {}) do
        local spellID = ref.WEAPON_SKILL_SPELL and ref.WEAPON_SKILL_SPELL[sub]
        local label = ref.WEAPON_SKILL_NAME and ref.WEAPON_SKILL_NAME[sub] or ("Weapon " .. sub)
        local icon = ref.WEAPON_SKILL_ICON and ref.WEAPON_SKILL_ICON[sub] or "INV_Sword_04"
        local trainers = {}
        for _, candidate in ipairs(ref.WEAPON_TRAINERS or {}) do
            if factionMatches(candidate.side) then for _, skill in ipairs(candidate.skills or {}) do if skill == sub then trainers[#trainers + 1] = candidate; break end end end
        end
        local known = own and spellID and knownSpell(spellID)
        local key = "weapon:" .. token .. ":" .. sub
        rows[#rows + 1] = { header = true, toggle = key, text = label .. (known and "  •  Known" or "") .. "  •  " .. #trainers .. " trainer(s)" }
        if self.expanded[key] then
            if #trainers == 0 then rows[#rows + 1] = { kind = "note", name = "No faction trainer recorded", description = "This skill may be learned another way.", icon = "Interface\\Icons\\" .. icon } end
            for _, candidate in ipairs(trainers) do rows[#rows + 1] = locationRow(candidate, icon) end
        end
    end
    return rows
end

function trainer:BuildPetLines()
    local rows = {}
    if self.petView == "trainers" then
        for _, candidate in ipairs(ref and ref.PET_TRAINERS or {}) do
            if factionMatches(candidate.side) then rows[#rows + 1] = locationRow(candidate, "Ability_Hunter_BeastTraining") end
        end
        table.sort(rows, function(a, b) return a.description < b.description end)
        return rows
    end
    local spells = {}
    for id, info in pairs(ref and ref.PET_TEACH_SPELLS or {}) do
        if type(info) == "table" then spells[tostring(info[1]) .. ":" .. tostring(info[2])] = id end
    end
    for _, ability in ipairs(ref and ref.PET_ABILITIES or {}) do
        if ability.source == "trainer" then
            for _, rank in ipairs(ability.ranks or {}) do
                local spellID = spells[ability.name .. ":" .. tostring(rank.rank)]
                local saved = playerClass() == 3 and petStore()
                local known = saved and saved.ranks[ability.name] and saved.ranks[ability.name][rank.rank]
                rows[#rows + 1] = { kind = "petAbility", id = spellID, name = ability.name, rank = rank.rank or 0,
                    level = rank.level or 1, icon = "Interface\\Icons\\" .. (ability.icon or "Ability_Hunter_BeastTraining"),
                    description = (known and "Known  •  " or "Not recorded  •  ") .. tostring(rank.tp or 0) .. " training points",
                    detail = rank.desc or ability.effect, encyclopediaKey = "ability:" .. ability.name }
            end
        end
    end
    table.sort(rows, function(a, b) if a.level ~= b.level then return a.level < b.level end if a.name ~= b.name then return a.name < b.name end return a.rank < b.rank end)
    return rows
end

local function fields(text)
    local result = {}; for value in (text .. "|"):gmatch("(.-)|") do result[#result + 1] = value end; return result
end
local function raceAllowed(mask, own)
    if not own or not mask or mask == 0 then return true end
    if not UnitRace then return true end
    local ok, _, _, id = pcall(UnitRace, "player")
    if not ok or ns.Secret(id) or type(id) ~= "number" then return true end
    local bit = id == 95 and 32 or id == 96 and 33 or id - 1
    return math.floor(mask / 2 ^ bit) % 2 == 1
end
local function questState(id, own)
    if not own then return "Reference" end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local ok, value = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
        if ok and not ns.Secret(value) and value == true then return "Quest flagged complete" end
    end
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local ok, index = pcall(C_QuestLog.GetLogIndexForQuestID, id)
        if ok and not ns.Secret(index) and type(index) == "number" and index > 0 then return "In quest log" end
    end
    return "Status not confirmed"
end
local function prerequisiteNames(ids)
    local labels = {}
    local quests = ref and ref.CLASS_QUESTS and ref.CLASS_QUESTS.quests or {}
    for value in tostring(ids or ""):gmatch("%d+") do
        local id = tonumber(value); local raw = quests[id]; local name = type(raw) == "string" and raw:match("^[^|]+")
        labels[#labels + 1] = name and (name .. " [" .. id .. "]") or ("Quest " .. id)
    end
    return table.concat(labels, ", ")
end

function trainer:BuildQuestLines()
    local rows, class = {}, classInfo(self.viewClass or playerClass())
    local data = ref and ref.CLASS_QUESTS
    local own = class and class[1] == playerClass()
    if not (data and data.milestones and data.quests and class) then return rows end
    for _, milestone in ipairs(data.milestones[class[2]] or {}) do
        local key = "quest:" .. class[2] .. ":" .. milestone[1]
        rows[#rows + 1] = { header = true, toggle = key, text = "Level " .. milestone[2] .. "  •  " .. milestone[1] }
        if self.expanded[key] then
            local selected, order = {}, {}
            for value in tostring(milestone[4] or ""):gmatch("%d+") do
                local id = tonumber(value); local raw = data.quests[id]
                if type(raw) == "string" then
                    local v = fields(raw)
                    if raceAllowed(tonumber(v[3]), own) then
                        selected[id] = { kind = "quest", questID = id, name = v[1], level = tonumber(v[2]) or milestone[2],
                            preAny = v[4], preAll = v[5], giver = v[6], mapID = tonumber(v[7]), x = tonumber(v[8]), y = tonumber(v[9]),
                            alternateGivers = v[10], icon = "Interface\\GossipFrame\\AvailableQuestIcon", description = questState(id, own) .. (v[6] ~= "" and ("  •  " .. v[6]) or "") }
                        order[#order + 1] = id
                    end
                end
            end
            local visited, visiting = {}, {}
            local function visit(id)
                if visited[id] or visiting[id] or not selected[id] then return end
                visiting[id] = true
                for dep in (selected[id].preAny .. "/" .. selected[id].preAll):gmatch("%d+") do visit(tonumber(dep)) end
                visiting[id] = nil; visited[id] = true; rows[#rows + 1] = selected[id]
            end
            for _, id in ipairs(order) do visit(id) end
            if #order == 0 then rows[#rows + 1] = {kind="note", name="No matching quests recorded", description="Race or quest details are unavailable.", icon="Interface\\GossipFrame\\AvailableQuestIcon"} end
        end
    end
    return rows
end

function trainer:BuildDisplayLines(list)
    local lines, previous={},nil
    local groupSpells=self.page=="spells" and self.mode~="lowranks"
    local ownClass=playerClass();local own=type(ownClass)=="number" and (self.viewClass or ownClass)==ownClass
    if groupSpells and own then
        local ready={}
        for _,entry in ipairs(list) do
            if entry.available and not entry.quest and not entry.talent and not entry.knownUnknown then ready[#ready+1]=entry end
        end
        if #ready>0 then lines[#lines+1]={header=true,text="Available now",headerColor="ready"};for _,entry in ipairs(ready) do lines[#lines+1]=entry end end
    end
    for _,entry in ipairs(list) do
        local ready=groupSpells and own and entry.available and not entry.quest and not entry.talent and not entry.knownUnknown
        if not ready then
            if (groupSpells or self.page=="pets" and self.petView~="trainers") and previous~=entry.level then
                lines[#lines+1]={header=true,level=entry.level,headerColor="level"};previous=entry.level
            end
            lines[#lines+1]=entry
        end
    end
    return lines
end

local function makeButton(parent, caption, width)
    local b = CreateFrame("Button", nil, parent); b:SetSize(width, 26); ns.Panel(b, { edge = 0.8 })
    b.text = ns.Text(b, 11, ns.C.text); b.text:SetPoint("CENTER"); b.text:SetText(caption)
    local hover = b:CreateTexture(nil, "HIGHLIGHT"); hover:SetAllPoints(); hover:SetColorTexture(1, 0.85, 0.48, 0.12)
    return b
end

function trainer:Render()
    if not self.frame then return end
    local list, f = {}, self.frame
    if self.page == "spells" and self.mode == "lowranks" then list = self:BuildLowRanks()
    elseif self.page == "spells" then list = self:BuildList()
    elseif self.page == "weapons" then list = self:BuildWeaponLines()
    elseif self.page == "quests" then list = self:BuildQuestLines()
    elseif self.page == "pets" then list = self:BuildPetLines() end
    local ownClass = playerClass()
    local currentClass = self.viewClass or ownClass; local class = classInfo(currentClass)
    f.title:SetText("Class trainer  •  " .. (class and class[3] or "Unknown"))
    local subtitle = self.page == "weapons" and "Choose a weapon skill to find faction trainers"
        or self.page == "quests" and "Expand a milestone to see its quest branches and prerequisites"
        or self.page == "pets" and (self.petView == "trainers" and "Pet trainers for your faction" or "Pet trainer abilities; open the encyclopedia for more")
        or self.mode == "lowranks" and (#list .. " lower ranks  •  click to pick up, right-click to keep")
        or (currentClass == playerClass() and "Spells and ranks you have not learned yet" or "Class spell reference; knowledge is not tracked for this class")
    f.subtitle:SetText(subtitle)
    for page, button in pairs(f.pages) do button.fuiPanel.bright = page == self.page; ns.PaintPanel(button) end
    for mode, button in pairs(f.tabs) do button:SetShown(self.page == "spells"); button.fuiPanel.bright = mode == self.mode; ns.PaintPanel(button) end
    for mode, button in pairs(f.petTabs) do button:SetShown(self.page == "pets"); button.fuiPanel.bright = mode == (self.petView or "abilities"); ns.PaintPanel(button) end
    for id, button in pairs(f.classButtons) do
        button.fuiPanel.bright = id == currentClass
        ns.PaintPanel(button)
        -- The border indicates which class is being browsed; the icon's
        -- brightness identifies the character's actual class independently.
        local shade = ownClass and id ~= ownClass and 0.4 or 1
        if button.icon and button.icon.SetVertexColor then button.icon:SetVertexColor(shade, shade, shade) end
    end
    local lines=self:BuildDisplayLines(list)
    self.offset = math.max(0, math.min(self.offset, math.max(0, #lines - #f.rows)))
    if f.smooth then self.offset = ns.Encyclopedia.SmoothSync(f.smooth, self.offset, #lines)
    else ns.UpdateListScrollbar(f.scrollbar, self.offset, math.max(0, #lines - #f.rows)) end
    for i, row in ipairs(f.rows) do
        local entry = lines[self.offset + i]; row.entry = entry; row:SetShown(entry ~= nil)
        if entry then
            row.icon:SetShown(not entry.header); row.description:SetShown(not entry.header); row.price:SetShown(not entry.header)
            row.map:SetShown(not entry.header and entry.mapID and entry.x and entry.y and true or false); row.map.entry = entry
            row.fuiPanel.bright = entry.header and true or false; ns.PaintPanel(row)
            if entry.header then
                row.title:ClearAllPoints(); row.title:SetText((entry.toggle and (self.expanded[entry.toggle] and "−  " or "+  ") or "") .. (entry.text or ("Level " .. entry.level))); row.title:SetPoint("LEFT", row, "LEFT", 12, 0)
                if entry.headerColor=="ready" then row.title:SetTextColor(0.32,1,0.43)
                elseif entry.headerColor=="level" then row.title:SetTextColor(1,0.34,0.30)
                else row.title:SetTextColor(ns.C.bright[1],ns.C.bright[2],ns.C.bright[3]) end
            else
                row.title:SetTextColor(ns.C.text[1],ns.C.text[2],ns.C.text[3])
                row.title:ClearAllPoints(); row.title:SetPoint("TOPLEFT", 40, -3)
                row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.title:SetText(entry.name .. (entry.rank and entry.rank > 0 and "  •  Rank " .. entry.rank or ""))
                if entry.newID then row.description:SetText("Higher rank " .. entry.newRank .. "  •  " .. #entry.slots .. " action slot(s)"); row.price:SetText("")
                elseif entry.kind then
                    row.description:SetText(entry.description or "")
                    row.price:SetText(entry.kind == "quest" and ("Lvl " .. tostring(entry.level or "?")) or "")
                else
                    local note = entry.quest and "Class quest" or entry.talent and "Talent required" or entry.knownUnknown and "Knowledge unavailable" or entry.available and "Trainer" or "Upcoming"
                    row.description:SetText(note)
                    row.price:SetText(entry.quest and "Quest" or entry.cost ~= nil and money(entry.cost) or "?")
                end
            end
        end
    end
    f.empty:SetText(self.page == "spells" and self.mode == "lowranks" and "No lower spell ranks found on your action bars." or "No entries recorded in this category.")
    f.empty:SetShown(#list == 0)
end

function trainer:Open()
    if not self.frame then
        local f = CreateFrame("Frame", "ForeverUITrainerGuide", UIParent); self.frame = f
        f:SetSize(500, 680); f:SetPoint("CENTER", UIParent, "CENTER", 140, 0); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end); f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        ns.RememberWindow(f, "trainerGuide")
        ns.Panel(f, { alpha = 1, edge = 1 })
        f.title = ns.Text(f, 18, ns.C.bright); f.title:SetPoint("TOPLEFT", 16, -15)
        f.subtitle = ns.Text(f, 10, ns.C.muted); f.subtitle:SetPoint("TOPLEFT", 16, -39)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetSize(28, 28); close:SetPoint("TOPRIGHT", -8, -8)
        f.classButtons = {}
        for i, class in ipairs(classes) do
            local b = CreateFrame("Button", nil, f); b:SetSize(39, 39); b:SetPoint("TOPLEFT", 12 + (i - 1) * 44, -61); ns.Panel(b, { edge = 0.8 })
            b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 3, -3); b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
            local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class[2]]
            if coords then b.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"); b.icon:SetTexCoord(unpack(coords))
            else b.icon:SetTexture("Interface\\Icons\\" .. class[4]) end
            b:SetScript("OnClick", function() trainer.viewClass, trainer.offset = class[1], 0; if trainer.mode == "lowranks" then trainer.mode = "all" end; trainer:Render() end)
            b:SetScript("OnEnter", function(self) if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(class[3]); GameTooltip:Show() end end)
            b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            f.classButtons[class[1]] = b
        end
        f.pages = {}
        for i, spec in ipairs({ {"spells", "Spells"}, {"weapons", "Weapons"}, {"quests", "Class quests"}, {"pets", "Pet training"} }) do
            local b = makeButton(f, spec[2], 111); b:SetPoint("TOPLEFT", 12 + (i - 1) * 115, -109); f.pages[spec[1]] = b
            b:SetScript("OnClick", function() trainer.page, trainer.offset = spec[1], 0; trainer:Render() end)
        end
        f.tabs = {}
        for i, spec in ipairs({ {"available", "Available"}, {"upcoming", "Upcoming"}, {"all", "Unlearned"}, {"lowranks", "Low ranks"} }) do
            local b = makeButton(f, spec[2], 111); b:SetPoint("TOPLEFT", 12 + (i - 1) * 115, -141); f.tabs[spec[1]] = b
            b:SetScript("OnClick", function() trainer.mode, trainer.offset = spec[1], 0; if spec[1] == "lowranks" then trainer.viewClass = playerClass() end; trainer:Render() end)
        end
        f.petTabs = {}
        for i, spec in ipairs({ {"abilities", "Abilities"}, {"trainers", "Trainers"} }) do
            local b = makeButton(f, spec[2], 111); b:SetPoint("TOPLEFT", 12 + (i - 1) * 115, -141); f.petTabs[spec[1]] = b
            b:SetScript("OnClick", function() trainer.petView, trainer.offset = spec[1], 0; trainer:Render() end)
        end
        local body = CreateFrame("Frame", nil, f); body:SetPoint("TOPLEFT", 12, -178); body:SetSize(462, 470); f.body = body; f.rows = {}
        f.empty = ns.Text(body, 11, ns.C.muted); f.empty:SetPoint("TOPLEFT", 8, -10); f.empty:SetText("No spells recorded in this category.")
        for i = 1, 14 do -- 13 visible plus a spare for smooth scrolling
            local row = CreateFrame("Button", nil, body); row:SetSize(458, 34); row:SetPoint("TOPLEFT", 0, -(i - 1) * 36); ns.Panel(row, { edge = 0.4 })
            row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(28, 28); row.icon:SetPoint("LEFT", 4, 0)
            row.title = ns.Text(row, 11, ns.C.text); row.title:SetPoint("TOPLEFT", 40, -3); row.title:SetWidth(315); row.title:SetJustifyH("LEFT")
            row.description = ns.Text(row, 10, ns.C.muted); row.description:SetPoint("TOPLEFT", 40, -19); row.description:SetWidth(315); row.description:SetJustifyH("LEFT")
            row.price = ns.Text(row, 11, ns.C.bright); row.price:SetPoint("RIGHT", row, "RIGHT", -34, 0); row.price:SetWidth(70); row.price:SetJustifyH("RIGHT")
            row.map = CreateFrame("Button", nil, row); row.map:SetSize(24, 24); row.map:SetPoint("RIGHT", row, "RIGHT", -5, 0)
            row.map.icon = row.map:CreateTexture(nil, "ARTWORK"); row.map.icon:SetAllPoints(); row.map.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
            row.map:SetScript("OnClick", function(self)
                local e, encyclopedia = self.entry, ns.Encyclopedia
                if e and encyclopedia and encyclopedia.ShowLocation and encyclopedia.ShowLocation(e.mapID, e.x, e.y) then
                    trainer.frame:Hide(); trainer.opened = false
                end
            end)
            row.map:SetScript("OnEnter", function(self) if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Show location on map"); GameTooltip:Show() end end)
            row.map:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            row:SetScript("OnEnter", function(self)
                local e = self.entry
                if not (e and GameTooltip) then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if e.id and not e.kind and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(e.id) else GameTooltip:SetText(e.name or e.text or "Details") end
                if e.detail and GameTooltip.AddLine then GameTooltip:AddLine(e.detail, 1, 1, 1, true) end
                if e.giver and e.giver ~= "" and GameTooltip.AddLine then GameTooltip:AddLine("Quest giver: " .. e.giver, 1, 1, 1, true) end
                if e.preAny and e.preAny ~= "" and GameTooltip.AddLine then GameTooltip:AddLine("Requires one of: " .. prerequisiteNames(e.preAny), 1, 1, 1, true) end
                if e.preAll and e.preAll ~= "" and GameTooltip.AddLine then GameTooltip:AddLine("Requires all of: " .. prerequisiteNames(e.preAll), 1, 1, 1, true) end
                if e.alternateGivers and e.alternateGivers ~= "" and GameTooltip.AddLine then GameTooltip:AddLine("Other givers: " .. e.alternateGivers:gsub("~", "  •  "):gsub(";", ", "), 1, 1, 1, true) end
                if e.kind == "quest" and GameTooltip.AddLine then GameTooltip:AddLine("Click to open the quest in the encyclopedia when available.", 0.8, 0.7, 0.4, true) end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnClick", function(self, mouse)
                local entry = self.entry
                if not entry then return end
                if entry.toggle then trainer.expanded[entry.toggle] = not trainer.expanded[entry.toggle] or nil; trainer:Render(); return end
                if entry.kind == "quest" or entry.encyclopediaKey or entry.npcID then
                    local encyclopedia = ns.Encyclopedia
                    if encyclopedia and encyclopedia.RefreshData then
                        if not next(encyclopedia.byKey or {}) then encyclopedia:RefreshData() end
                        local target = entry.questID and (encyclopedia.byKey["quest:bulk:" .. entry.questID] or encyclopedia.byKey["quest:wowhead:" .. entry.questID] or encyclopedia.byKey["quest:" .. entry.questID])
                            or entry.encyclopediaKey and encyclopedia.byKey[entry.encyclopediaKey]
                            or entry.npcID and encyclopedia.byKey["npc:" .. entry.npcID]
                        if target and ns.OpenEncyclopedia then
                            local key = target.key
                            ns.OpenEncyclopedia(); encyclopedia:OpenEntry(encyclopedia.byKey[key] or target); return
                        end
                    end
                    if entry.kind == "quest" then ns.Print("This quest is not yet in the encyclopedia; hover for the recorded details.") end
                    return
                end
                if not entry.newID then return end
                if mouse == "RightButton" then
                    trainer:KeptRanks()[entry.id] = true
                    ns.Print("Keeping " .. entry.name .. " rank " .. entry.rank .. ".")
                    trainer:Render(); return
                end
                if InCombatLockdown and InCombatLockdown() then ns.Print("Leave combat before picking up a spell."); return end
                if GetCursorInfo and GetCursorInfo() then ns.Print("Clear your cursor before picking up a spell."); return end
                local pickup = (C_Spell and C_Spell.PickupSpell) or PickupSpell
                if pickup then local ok = pcall(pickup, entry.newID); if not ok then ns.Print("The game could not pick up that spell.") end
                else ns.Print("Spell pickup is unavailable on this client.") end
            end)
            row:EnableMouseWheel(true); row:SetScript("OnMouseWheel", function(_, delta) trainer.offset = trainer.offset - delta; trainer:Render() end); f.rows[i] = row
        end
        -- glides like the Encyclopedia lists: a wheel notch slides one row,
        -- the scroll bar drags by pixel, rows clip at the edges
        local E = ns.Encyclopedia
        if E and E.SmoothList then
            f.smooth = E.SmoothList("trainerGuide", { pane = body, rows = f.rows, step = 36, top = 0, refresh = function() trainer:Render() end })
            f.scrollbar = f.smooth.scrollbar
        else
            f.scrollbar = ns.ListScrollbar(body, function(value) trainer.offset = value; trainer:Render() end)
            body:EnableMouseWheel(true); body:SetScript("OnMouseWheel", function(_, delta) trainer.offset = trainer.offset - delta; trainer:Render() end)
        end
        if UISpecialFrames then table.insert(UISpecialFrames, "ForeverUITrainerGuide") end
    end
    if self.frame:IsShown() and self.opened then self.frame:Hide(); self.opened = false else self.opened = true; self.frame:Show(); self:Render() end
end

local function layoutTrainerButton(book)
    if InCombatLockdown and InCombatLockdown() then return end
    local b, system = book.fuiTrainerButton, book.CategoryTabSystem
    if not b then return end
    local icon
    for _, tab in ipairs(type(system) == "table" and type(system.tabs) == "table" and system.tabs or {}) do
        if type(tab) == "table" and type(tab.Icon) == "table" and (not tab.IsShown or tab:IsShown()) then icon = tab.Icon end
    end
    local width, height = 40, 40
    if icon and icon.GetSize then
        local w, h = icon:GetSize()
        if not ns.Secret(w) and type(w) == "number" and w > 0 then width = w end
        if not ns.Secret(h) and type(h) == "number" and h > 0 then height = h end
    end
    b:SetSize(width, height)
    b:ClearAllPoints()
    if icon then b:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    elseif system then b:SetPoint("LEFT", system, "RIGHT", 8, 0)
    else b:SetPoint("TOPRIGHT", book, "TOPRIGHT", -45, -35) end
end

-- OneForAll may still be installed while its data is being migrated. Its
-- trainer tab occupies this exact position, so hide just that duplicate tab.
local function hideOtherTrainerButton(frame)
    local other = frame and frame.ofaTrainerButton
    if type(other) ~= "table" or (other.IsForbidden and other:IsForbidden()) then return end
    if not other.fuiTrainerHideHook and other.HookScript then
        other.fuiTrainerHideHook = true
        other:HookScript("OnShow", function(self)
            ns.WhenSafe(function() if self.Hide then self:Hide() end end)
        end)
    end
    if other.EnableMouse then other:EnableMouse(false) end
    if other.Hide then other:Hide() end
end

function ns.AddTrainerButton(frame)
    local book = frame and frame.SpellBookFrame
    if not (book and book.CreateTexture) then return end
    ns.WhenSafe(function()
        if not book.fuiTrainerButton then
            local b = CreateFrame("Button", nil, book)
            book.fuiTrainerButton = b
            ns.Panel(b, { alpha = 0.9, edge = 0.9 })
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
            b.icon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\training-minimal.tga")
            local highlight = b:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints(b); highlight:SetColorTexture(1, 0.85, 0.48, 0.14)
            b:SetFrameLevel((book:GetFrameLevel() or 0) + 8)
            b:SetScript("OnClick", function() trainer:Open() end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Training", ns.C.bright[1], ns.C.bright[2], ns.C.bright[3])
                GameTooltip:AddLine("Browse spells, ranks, trainers and class quests.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            if book.HookScript then
                book:HookScript("OnShow", function()
                    ns.WhenSafe(function() layoutTrainerButton(book); hideOtherTrainerButton(frame) end)
                end)
            end
        end
        layoutTrainerButton(book)
        hideOtherTrainerButton(frame)
    end)
end

-- Fees are not supplied by the bundled spell database. Record only services
-- whose spell ID can be identified by the client at an actual class trainer.
local scanTip, trainerOpen, scanned, scanPending
function trainer:ScanTrainerCosts()
    if not trainerOpen or scanned or not (GetNumTrainerServices and GetTrainerServiceCost) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if IsTradeskillTrainer then local ok, tradeskill = pcall(IsTradeskillTrainer); if not ok or ns.Secret(tradeskill) or tradeskill then return end end
    local ok, count = pcall(GetNumTrainerServices)
    if not ok or ns.Secret(count) or type(count) ~= "number" or count <= 0 then return end
    local classID = playerClass(); local valid = {}
    for _, spell in ipairs(ref and ref.TRAINER_SPELLS and ref.TRAINER_SPELLS[classID] or {}) do valid[spell[2]] = true end
    if not scanTip then scanTip = CreateFrame("GameTooltip", "ForeverUITrainerScanTip", UIParent, "GameTooltipTemplate") end
    if not (scanTip.SetOwner and scanTip.SetTrainerService and scanTip.GetSpell) then return end
    local saved, found = {}, 0
    for index = 1, count do
        local read, id = pcall(function()
            scanTip:SetOwner(UIParent, "ANCHOR_NONE"); scanTip:SetTrainerService(index)
            local _, spellID = scanTip:GetSpell(); scanTip:Hide(); return spellID
        end)
        if read and type(id) == "number" and not ns.Secret(id) and valid[id] then
            local costOK, cost = pcall(GetTrainerServiceCost, index)
            if costOK and type(cost) == "number" and not ns.Secret(cost) and cost >= 0 then saved[id] = cost; found = found + 1 end
        end
    end
    if found > 0 then
        ns.db.trainerCosts = ns.db.trainerCosts or {}; ns.db.trainerCosts[classID] = ns.db.trainerCosts[classID] or {}
        for id, cost in pairs(saved) do ns.db.trainerCosts[classID][id] = cost end
        scanned = true
        if self.frame and self.frame:IsShown() then self:Render() end
    end
end
local function queueTrainerScan()
    if scanPending or not trainerOpen or scanned then return end
    scanPending = true
    local function run() scanPending = false; trainer:ScanTrainerCosts() end
    if C_Timer and C_Timer.After then C_Timer.After(0.5, run) else run() end
end
local function importTrainerCosts()
    local old = type(_G.OneForAllDB) == "table" and _G.OneForAllDB.trainerCosts
    if type(old) ~= "table" or type(ns.db) ~= "table" then return end
    for _, class in ipairs(classes) do
        local observed = old[class[2]]
        if type(observed) == "table" then
            local valid = {}; for _, spell in ipairs(ref and ref.TRAINER_SPELLS and ref.TRAINER_SPELLS[class[1]] or {}) do valid[spell[2]] = true end
            for key, value in pairs(observed) do
                local id = type(key) == "string" and tonumber(key:match("^#(%d+)$"))
                local cost = type(value) == "table" and value.c
                if id and valid[id] and type(cost) == "number" and not ns.Secret(cost) and cost >= 0 then
                    ns.db.trainerCosts = ns.db.trainerCosts or {}; ns.db.trainerCosts[class[1]] = ns.db.trainerCosts[class[1]] or {}
                    if ns.db.trainerCosts[class[1]][id] == nil then ns.db.trainerCosts[class[1]][id] = cost end
                end
            end
        end
    end
end
ns.On("TRAINER_SHOW", function() trainerOpen, scanned = true, false; queueTrainerScan() end)
ns.On("TRAINER_UPDATE", queueTrainerScan)
ns.On("TRAINER_CLOSED", function() trainerOpen, scanned = false, false end)

ns.On("ADDON_LOADED", function() if PlayerSpellsFrame then ns.AddTrainerButton(PlayerSpellsFrame) end end)
local petScanPending, beastScanNeeded
local function queuePetScan(beast)
    if playerClass() ~= 3 then return end
    if beast then beastScanNeeded = true end
    if petScanPending then return end
    petScanPending = true
    local function run()
        petScanPending = false
        if beastScanNeeded then beastScanNeeded = false; trainer:ScanBeastTraining() end
        trainer:ScanKnownPetSpells()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.5, run) else run() end
end

local rankTimer, learnedDuringTrainer = 0, false
function trainer:NotifyLowRanks()
    if not ns.Opt("qolLowRankCheck") or trainerOpen then return end
    self.notifiedRanks = self.notifiedRanks or {}
    local list, hasNew = self:BuildLowRanks(), false
    for _, entry in ipairs(list) do
        local key = tostring(entry.id) .. ":" .. tostring(entry.newID)
        if not self.notifiedRanks[key] then hasNew = true end
    end
    if not hasNew then return end
    for _, entry in ipairs(list) do self.notifiedRanks[tostring(entry.id) .. ":" .. tostring(entry.newID)] = true end
    if self.frame and self.frame:IsShown() then
        if self.page == "spells" and self.mode == "lowranks" then self:Render()
        else ns.Print("Lower-rank spells found. Open Training > Low ranks to review them.") end
    else
        self.page, self.mode, self.viewClass, self.offset = "spells", "lowranks", playerClass(), 0
        self:Open()
    end
end
local function queueRankCheck(delay)
    if not ns.Opt("qolLowRankCheck") then return end
    rankTimer = rankTimer + 1
    local token = rankTimer
    local function run()
        if token ~= rankTimer or not ns.Opt("qolLowRankCheck") or trainerOpen then return end
        ns.WhenSafe(function() if token == rankTimer and ns.Opt("qolLowRankCheck") and not trainerOpen then trainer:NotifyLowRanks() end end)
    end
    if C_Timer and C_Timer.After then C_Timer.After(delay, run) else run() end
end

ns.On("PLAYER_LOGIN", function()
    importTrainerCosts(); trainer:ImportPetRanks(); trainer:ImportKeptRanks(); queuePetScan(false)
    if PlayerSpellsFrame then ns.AddTrainerButton(PlayerSpellsFrame) end
end)
ns.OnOptional("CRAFT_SHOW", function() queuePetScan(true) end)
ns.OnOptional("CRAFT_UPDATE", function() queuePetScan(true) end)
ns.On("SPELLS_CHANGED", function()
    queuePetScan(false)
    if trainerOpen then learnedDuringTrainer = true else queueRankCheck(4) end
    if trainer.frame and trainer.frame:IsShown() then trainer:Render() end
end)
ns.On("TRAINER_CLOSED", function()
    if learnedDuringTrainer then learnedDuringTrainer = false; queueRankCheck(1) end
end)
ns.On("PLAYER_LEVEL_UP", function()
    if not trainerOpen then queueRankCheck(4) end
    if trainer.frame and trainer.frame:IsShown() then trainer:Render() end
end)

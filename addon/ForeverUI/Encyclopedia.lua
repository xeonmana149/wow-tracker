-- Forever Encyclopedia: read-only adapters for the player's installed data.
-- Uses an attributed standalone reference snapshot; OneForAll is optional.
local _, ns = ...
local E = { entries = {}, byKey = {}, selected = "Dungeons", instanceFilter = "dungeon", collapsedLevels = {}, profFilter = "Professions", petFilter = "family", armorFilter = "set", query = "", offset = 0, history = {} }
ns.Encyclopedia = E
E.questDirectoryOptions = { { "all", "All quests" }, { "class", "Class quests" }, { "class_self", "My class quests" }, { "attunement", "Attunement in name" }, { "dungeon", "Linked to dungeon" }, { "repeatable", "Repeatable" } }
E.npcDirectoryOptions = { { "all", "All NPCs" }, { "vendor", "Vendors" }, { "trainer", "Trainers" }, { "questgiver", "Quest givers" }, { "boss", "Dungeon bosses" } }
local categories = { "Armory", "Dungeons", "Professions", "Reputations", "Pets", "Library Books", "Quests", "NPCs", "Items" }
local function referenceSource()
    if type(ns.IndependentReference) == "table" then return ns.IndependentReference end
    if type(_G.OneForAll) == "table" then return _G.OneForAll end
end
local function engineSource()
    if ns.IndependentReference and ns.IndependentReference.GearValue and ns.IndependentReference.SkillUp then return ns.IndependentReference end
    return referenceSource()
end
local categoryIcons = { Armory = "armory", Dungeons = "dungeons", Professions = "professions", Reputations = "reputations", Pets = "pets", ["Library Books"] = "library" }
local professionOrder = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring", "Cooking", "First Aid" }
local professionIcons = { Alchemy = "trade_alchemy", Blacksmithing = "trade_blacksmithing", Enchanting = "trade_engraving", Engineering = "trade_engineering", Leatherworking = "inv_misc_armorkit_17", Tailoring = "trade_tailoring", Cooking = "inv_misc_food_15", ["First Aid"] = "spell_holy_sealofsacrifice", Mining = "trade_mining", Herbalism = "spell_nature_naturetouchgrow", Skinning = "inv_misc_pelt_wolf_01", Fishing = "trade_fishing" }
local function setSections(entries, group)
    local sections, seen = {}, {}
    for _, entry in ipairs(entries) do if entry.kind == "set" and entry.data.g == group then
        local name = entry.data.sub or "Other"; if not seen[name] then seen[name] = true; sections[#sections + 1] = name end
    end end
    local function order(name)
        if name:find("Forever Tier 1", 1, true) then return 1 end
        local tier = name:match("^Tier%s+(%d+)"); if tier then return 10 + tonumber(tier) * 10 end
        if name:find("Molten Core", 1, true) then return 25 end
        if name:find("Onyxia", 1, true) then return 26 end
        if name:find("Zul'Gurub", 1, true) then return 27 end
        if name:find("Ruins of Ahn", 1, true) then return 35 end
        if name:find("Temple of Ahn", 1, true) then return 36 end
        return 100
    end
    table.sort(sections, function(a, b) local x, y = order(a), order(b); return x == y and a < b or x < y end)
    return sections
end
local function setSectionLabel(name)
    if name:find("Forever Tier 1", 1, true) then return "Forever T1" end
    return name:match("^(Tier%s+%d+)") or name
end
local confirmedProfessionBonuses = {}
local function professionBonus(id)
    if confirmedProfessionBonuses[id] then return true end
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return false end
    local ok, tip = pcall(C_TooltipInfo.GetItemByID, id)
    if not ok or type(tip) ~= "table" or type(tip.lines) ~= "table" or #tip.lines == 0 then return nil end
    for _, line in ipairs(tip.lines) do
        for _, value in ipairs({ line.leftText or "", line.rightText or "" }) do
            if type(value) == "string" and not ns.Secret(value) then
                local text = value:lower()
                local profession = text:find("fishing", 1, true) or text:find("mining", 1, true) or text:find("smelt", 1, true) or text:find("herbalism", 1, true) or text:find("skinning", 1, true) or text:find("alchemy", 1, true) or text:find("blacksmith", 1, true) or text:find("enchant", 1, true) or text:find("engineer", 1, true) or text:find("leatherwork", 1, true) or text:find("tailor", 1, true) or text:find("cooking", 1, true) or text:find("first aid", 1, true) or text:find("gather", 1, true)
                if profession and (text:find("+", 1, true) or text:find("increas", 1, true) or text:find("speed", 1, true) or text:find("faster", 1, true) or text:find("skill", 1, true) or text:find("bonus", 1, true) or text:find("reduc", 1, true)) then confirmedProfessionBonuses[id] = true; return true end
            end
        end
    end
    return false
end
E.ProfessionBonus = professionBonus
local function gearMatchesFilters(gear, id, sourceFilter, typeFilter)
    if not gear then return not sourceFilter and not typeFilter end
    if gear.sourceKinds and (sourceFilter == "quest" or sourceFilter == "dungeon" or sourceFilter == "raid" or sourceFilter == "crafted") then
        if not gear.sourceKinds[sourceFilter] then return false end
    else
        if sourceFilter == "quest" and not gear.qid then return false end
        if sourceFilter == "dungeon" and not (gear.d and not gear.qid and not gear.d.raid) then return false end
        if sourceFilter == "raid" and not (gear.d and not gear.qid and gear.d.raid) then return false end
        if sourceFilter == "crafted" and not (gear.prof and not gear.d and not gear.qid) then return false end
    end
    if sourceFilter == "boe" then
        local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        if not info then return false end
        local data = { pcall(info, id) }; if not data[1] or data[15] ~= 2 then return false end
    end
    local armor = { cloth = 1, leather = 2, mail = 3, plate = 4 }
    if armor[typeFilter] then return gear.cid == 4 and gear.sub == armor[typeFilter] end
    if typeFilter == "shield" then return gear.cid == 4 and gear.sub == 6 end
    if typeFilter == "onehand" then return gear.cid == 2 and (gear.loc == "INVTYPE_WEAPON" or gear.loc == "INVTYPE_WEAPONMAINHAND" or gear.loc == "INVTYPE_WEAPONOFFHAND") end
    if typeFilter == "twohand" then return gear.cid == 2 and gear.loc == "INVTYPE_2HWEAPON" end
    if typeFilter == "ranged" then return gear.cid == 2 and (gear.loc == "INVTYPE_RANGED" or gear.loc == "INVTYPE_RANGEDRIGHT" or gear.loc == "INVTYPE_THROWN") end
    if typeFilter == "profession" then return professionBonus(id) end
    return true
end
local function candidateIdentity(candidate)
    if candidate and candidate.entry then return candidate.entry.key end
    local option = candidate and candidate.enchant
    if option then return "enchant:" .. tostring(option.s or option.i or option.e or "") end
end
local function anchoredOffset(previous, current, offset)
    if not previous or not offset or offset <= 0 then return offset or 0 end
    local key = candidateIdentity(previous[offset + 1])
    if key then for i, candidate in ipairs(current) do if candidateIdentity(candidate) == key then return i - 1 end end end
    return offset
end
E.AnchoredPlannerOffset = anchoredOffset
local function schedulePlannerUpdate()
    if E.plannerUpdateScheduled or not (C_Timer and C_Timer.After) then return end
    E.plannerUpdateScheduled = true
    C_Timer.After(0.8, function()
        E.plannerUpdateScheduled = nil
        if not (E.window and E.window:IsShown() and E.selected == "Armory" and E.armorFilter == "planner") then return end
        if GetTime and E.plannerScrollTime and GetTime() - E.plannerScrollTime < 0.75 then schedulePlannerUpdate() else E:Render() end
    end)
end

local function playerProfessions()
    local result = {}
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return result end
    local ok, a, b, c, d, e, g = pcall(GetProfessions)
    if not ok then return result end
    local indices = { a or false, b or false, c or false, d or false, e or false, g or false }
    for i = 1, 6 do
        if indices[i] then
            local ok, name, icon, skill, maximum = pcall(GetProfessionInfo, indices[i])
            if ok and name and not ns.Secret(name) then result[#result + 1] = { name = name, icon = icon, skill = skill, maximum = maximum } end
        end
    end
    return result
end

local function formatMoney(copper)
    local value = tonumber(copper)
    if not value then return "Unknown" end
    local sign = value < 0 and "-" or ""
    value = math.floor(math.abs(value) + 0.5)
    local gold, silver, remaining = math.floor(value / 10000), math.floor(value / 100) % 100, value % 100
    local parts = {}
    local function coin(amount, name) parts[#parts + 1] = amount .. "|TInterface\\MoneyFrame\\UI-" .. name .. "Icon:12:12:2:0|t" end
    if gold > 0 then coin(gold, "Gold") end
    if silver > 0 then coin(silver, "Silver") end
    if remaining > 0 or #parts == 0 then coin(remaining, "Copper") end
    return sign .. table.concat(parts, " ")
end
E.FormatMoney = formatMoney

local function recipeKnown(entry, state)
    local data = entry and entry.data or {}
    if state and type(state.known) == "table" and data.s and state.known[data.s] then return true end
    local gold, player = _G.ForeverGold, nil
    if UnitName then local ok, value = pcall(UnitName, "player"); if ok and type(value) == "string" and not ns.Secret(value) then player = value:match("^[^%-]+") end end
    if player and gold and type(gold.RecipeKnownBy) == "function" then
        local ok, known = pcall(gold.RecipeKnownBy, entry.extra, entry.name)
        if ok and type(known) == "table" then for _, name in ipairs(known) do if type(name) == "string" and name:match("^[^%-]+") == player then return true end end end
    end
    if state and state.scanned then return false end
    return nil
end

-- Item, quest and dungeon links: who to link an item to, by id/key, so
-- opening an item doesn't walk all ~36,000 entries. Built on first use,
-- kept up to date by add(), rebuilt when the entries are rebuilt.
local function indexSource(idx, e, pos)
    local kind, d = e.kind, e.data
    idx.pos[e] = pos
    if type(d) ~= "table" then return end
    if kind == "quest" then
        if d.id ~= nil then idx.quest[d.id] = e end -- the last one wins, as before
    elseif kind == "dungeon" then
        local byData = idx.dungeonData[d]; if not byData then byData = {}; idx.dungeonData[d] = byData end; byData[#byData + 1] = e
        local k = d.key == nil and "\0nil" or d.key
        local byKey = idx.dungeonKey[k]; if not byKey then byKey = {}; idx.dungeonKey[k] = byKey end; byKey[#byKey + 1] = e
    elseif kind == "boss" then
        local k = tostring(e.name) .. "\1" .. tostring(e.extra)
        local list = idx.boss[k]; if not list then list = {}; idx.boss[k] = list end; list[#list + 1] = e
    end
end
local function sourceIndex()
    local idx = E.sourceIdx
    if idx and idx.entries == E.entries then return idx end
    idx = { entries = E.entries, pos = {}, quest = {}, dungeonData = {}, dungeonKey = {}, boss = {} }
    for i, e in ipairs(E.entries) do indexSource(idx, e, i) end
    E.sourceIdx = idx
    return idx
end

-- The game's own data ships developer leftovers: "QAEnchant Gloves +5
-- Fishing", "Fishing Pole (JEFFTEST)", "DEBUG ... Page", "DND FLAG ...".
-- Real names ("Test of Faith", "The Gordok Taste Test") never match.
local function isTestName(name)
    local lower = name:lower()
    return name:find("^QA%u") or name:find("^Test%u") or name:find("TEST", 1, true) or name:find("DEBUG", 1, true)
        or name:find("PLACEHOLDER", 1, true) or name:find("^DND ") or name:find("[PH]", 1, true)
        or lower:find("^ring of critical testing%f[%A]") or lower:find("^potion of tradeskill testing%f[%A]")
        or lower:find("%f[%a]debug%f[%A]")
        or lower:find("%f[%a]dnt%f[%A]") or lower == "not used" or lower == "template item"
        or lower:find("^internal %a+ equipment kit l%d+")
end
E.IsTestName = isTestName

local function isHiddenNPC(name, data)
    if type(name) ~= "string" then return false end
    local lower = name:lower()
    local kind = type(data) == "table" and tostring(data.type or ""):lower() or ""
    if lower:find("^<txt>") or lower:find(" credit marker", 1, true) or lower:find(" quest doodad", 1, true)
        or lower:find(" spell marker", 1, true) or lower == "campfire marker"
        or lower == "invisible stalker" or lower == "invisible bunny" or lower == "generic bunny"
        or lower == "orphan spell visual invisible holder" or lower == "rtc player dummy"
        or lower == "call for help trigger" or lower == "ouro spawner" then return true end
    if kind == "totem" then return true end
    -- Unclassified totem objects are hidden, without removing humanoids whose
    -- names contain Totem or their legitimate Totemic titles.
    return (kind == "" or kind == "other" or kind == "not specified" or kind == "unspecified")
        and lower:find("%f[%a]totem%f[%A]") ~= nil
end
E.IsHiddenNPC = isHiddenNPC

local function add(category, kind, id, name, data, extra)
    if type(name) ~= "string" or name == "" or isTestName(name) or (kind == "npc" and (isHiddenNPC(name, data) or (E.hiddenNPCIds and E.hiddenNPCIds[tonumber(id)]))) then return end
    local key = kind .. ":" .. tostring(id or name)
    local e = { category = category, kind = kind, key = key, name = name, data = data, extra = extra, links = {} }
    E.entries[#E.entries + 1] = e
    if not E.byKey[key] then E.byKey[key] = e end
    -- searches made before this entry existed are out of date
    E.entryRevision = (E.entryRevision or 0) + 1
    local idx = E.sourceIdx
    if idx and idx.entries == E.entries then indexSource(idx, e, #E.entries) end
    return e
end

-- Links both ways, once. A vendor can have hundreds of items: a set of
-- what's already linked instead of reading the list each time (rebuilt if
-- anything else added to the list).
local function linkOne(x, y)
    local links, set = x.links, x.fuiLinked
    if not set or set.n ~= #links then
        set = { n = #links }
        for _, entry in ipairs(links) do set[entry] = true end
        x.fuiLinked = set
    end
    if set[y] then return end
    links[#links + 1] = y
    set[y], set.n = true, #links
end
local function link(a, b)
    if not a or not b or a == b then return end
    linkOne(a, b); linkOne(b, a)
end
local function linkItemSource(itemEntry, target, kind, chance, note, metadata)
    if not itemEntry or not target then return end
    link(itemEntry, target)
    local data = itemEntry.data
    data.sourceLinks, data.sourceLinkKeys = data.sourceLinks or {}, data.sourceLinkKeys or {}
    local key = kind .. ":" .. target.key
    if not data.sourceLinkKeys[key] then
        data.sourceLinkKeys[key] = true
        data.sourceLinks[#data.sourceLinks + 1] = { entry = target, kind = kind, chance = chance, note = note,
            favorCost = metadata and metadata.favorCost, faction = metadata and metadata.faction,
            uncertain = metadata and metadata.uncertain }
    end
    if kind == "Quest" and target.kind == "quest" then
        local q = target.data
        q.rewardEntries, q.rewardKeys = q.rewardEntries or {}, q.rewardKeys or {}
        if not q.rewardKeys[itemEntry.key] then q.rewardKeys[itemEntry.key] = true; q.rewardEntries[#q.rewardEntries + 1] = itemEntry end
    end
end
local function linkReagent(itemEntry, recipe)
    if not itemEntry or not recipe then return end
    link(itemEntry, recipe)
    local d = itemEntry.data
    d.usedIn, d.usedInKeys = d.usedIn or {}, d.usedInKeys or {}
    if not d.usedInKeys[recipe.key] then d.usedInKeys[recipe.key] = true; d.usedIn[#d.usedIn + 1] = recipe end
end
local function itemRelatedEntries(entry)
    local out, seen = {}, {}
    for _, source in ipairs(entry.data.sourceLinks or {}) do
        out[#out + 1] = source; seen[source.entry] = true
    end
    for _, related in ipairs(entry.links or {}) do
        if not seen[related] and not (entry.data.usedInKeys and entry.data.usedInKeys[related.key]) then out[#out + 1] = { entry = related }; seen[related] = true end
    end
    return out
end
E.ItemRelatedEntries = itemRelatedEntries
-- A name lowercased once (sorting compares names thousands of times).
local function lowerName(e)
    if e.fuiLowerName ~= e.name or not e.fuiLower then e.fuiLowerName, e.fuiLower = e.name, tostring(e.name or ""):lower() end
    return e.fuiLower
end
local function sortByName(list)
    table.sort(list, function(a, b) return lowerName(a) < lowerName(b) end)
end
-- The reference lists some items twice under two ids (an unused copy beside
-- the real one, e.g. two "Blump Family Fishing Pole"s): one row per name and
-- slot, preferring the copy with gear data over an estimated record.
local function itemRank(e)
    local data = e.data or {}
    local ref = type(data.reference) == "table" and data.reference
    return (data.gear and 2 or 0) + ((ref and ref.estimated) and 0 or 1)
end
local function dedupeItems(list, entryOf)
    local kept, at = {}, {}
    for _, value in ipairs(list) do
        local e = entryOf and entryOf(value) or value
        if type(e) ~= "table" or e.kind ~= "item" then kept[#kept + 1] = value
        else
            local key = lowerName(e) .. "\1" .. tostring(e.data.slot or (e.data.gear and e.data.gear.loc) or "")
            local i = at[key]
            if not i then kept[#kept + 1] = value; at[key] = #kept
            elseif itemRank(e) > itemRank(entryOf and entryOf(kept[i]) or kept[i]) then kept[i] = value end
        end
    end
    return kept
end
E.DedupeItems = dedupeItems

local function itemAvailability(entry)
    local id = entry and entry.data and entry.data.id
    local data = ns.BulkReferenceData and ns.BulkReferenceData.availability
    return id and type(data) == "table" and data[id] or nil
end
-- A recorded auction listing shows the item was listed at the time of that
-- scan; it may no longer be listed or obtainable today.
local function auctionObservation(id)
    local gold = _G.ForeverGold
    if type(id) ~= "number" or type(gold) ~= "table" or type(gold.LastPrice) ~= "function" then return nil end
    local ok, price, seen = pcall(gold.LastPrice, id)
    if not ok or type(price) ~= "number" or ns.Secret(price) or price <= 0 or type(seen) ~= "number" or ns.Secret(seen) or seen <= 0 then return nil end
    return seen
end
E.AuctionObservation = auctionObservation
local function auctionObservationText(id)
    local seen = auctionObservation(id)
    if not seen then return nil end
    local label = nil
    if type(date) == "function" then local ok, value = pcall(date, "%Y-%m-%d", seen); if ok and type(value) == "string" and not ns.Secret(value) then label = value end end
    return "Previously listed on your auction house" .. (label and (" (" .. label .. ")") or "") .. "; current availability can change."
end
local function itemUnavailable(entry)
    local evidence = itemAvailability(entry)
    -- An observed tooltip does not prove current obtainability, but it is a
    -- disagreement worth retaining for review instead of silently hiding.
    return evidence and evidence.status == "unavailable" and not (entry.data and entry.data.observed) and not auctionObservation(entry.data.id) or false
end
E.ItemUnavailable = itemUnavailable
local function availabilityText(evidence, observed, auctionSeen)
    if auctionSeen then
        return "Availability needs review: Forever Gold recorded an auction listing, but Wowhead's status is " .. evidence.status .. " (checked " .. evidence.checkedAt .. ")."
    elseif evidence.status == "contested" then
        return "Availability needs review: " .. (evidence.reason or "conflicting source information") .. " (checked " .. evidence.checkedAt .. ")."
    elseif evidence.status == "unavailable" then
        return "Wowhead marked this unavailable (checked " .. evidence.checkedAt .. ")." .. (observed and " Tracker also observed item data; availability needs review." or "")
    end
    return "Wowhead has not confirmed this item in Forever (checked " .. evidence.checkedAt .. ")."
end
local function availabilityTag(evidence)
    if not evidence then return "" end
    if evidence.status == "contested" then return "  •  Availability uncertain" end
    if evidence.status == "unconfirmed" then return "  •  Unconfirmed" end
    return ""
end

local function itemSourceLabel(entry)
    local d = entry and entry.data or {}
    if d.sourceLabel then return d.sourceLabel end
    local ref, gear = d.reference or {}, d.gear or {}
    local types = tostring(d.sourceTypes or ref.sourceTypes or "")
    local labels = {}
    for token in types:gmatch("[^,]+") do
        local name = ({ drop = "Drop", crafted = "Crafted", quest = "Quest", vendor = "Vendor", container = "Container", object = "Object", combined = "Combined" })[token:match("^%s*(.-)%s*$")]
        if name then labels[#labels + 1] = name end
    end
    if type(d.sourceLinks) == "table" then
        local seen = {}; for _, name in ipairs(labels) do seen[name] = true end
        local hadTypes = #labels > 0
        for _, source in ipairs(d.sourceLinks) do
            local name = source.kind == "Boss" and "Drop" or source.kind
            if name == "Merchant's Favor" and source.uncertain then
                name = "Merchant's Favor (stock unconfirmed)"
            elseif name == "Merchant's Favor" and source.note and source.note:find("Player%-reported") then
                name = "Merchant's Favor (reported)"
            end
            -- A recipe taught by a plan is a relationship, not a way to acquire it.
            if name and name ~= "Teaches" and (not hadTypes or source.kind == "Merchant's Favor") and not seen[name] then
                labels[#labels + 1] = name; seen[name] = true
            end
        end
    end
    if #labels == 0 then
        if gear.prof then labels[#labels + 1] = "Crafted" elseif gear.qid or (ref.questIds and #ref.questIds > 0) then labels[#labels + 1] = "Quest"
        elseif gear.d then labels[#labels + 1] = "Drop"
        elseif d.bulkSources and #d.bulkSources > 0 then labels[#labels + 1] = d.bulkSources[1]:match("^(Vendor):") or d.bulkSources[1]:match("^(Drop):") or "Source recorded" end
    end
    return #labels > 0 and table.concat(labels, " / ") or "Source unknown"
end
E.ItemSourceLabel = itemSourceLabel

local function armoryEquipment(entry)
    local d = entry and entry.data or {}
    local slot = tostring(d.slot or ""):lower()
    if slot == "non-equippable" or slot == "bag" or slot == "ammo" then return false end
    local loc = d.gear and d.gear.loc
    if loc == "INVTYPE_NON_EQUIP" or loc == "INVTYPE_BAG" or loc == "INVTYPE_AMMO" or loc == "INVTYPE_QUIVER" then return false end
    return true -- unknown is not proof that an item cannot be equipped
end
E.ArmoryEquipment = armoryEquipment

local function previewItem(entry, mouse)
    if not entry or entry.kind ~= "item" or (mouse and mouse ~= "LeftButton") then return false end
    local ctrl = IsControlKeyDown and IsControlKeyDown()
    if not ctrl and IsModifiedClick then ctrl = IsModifiedClick("DRESSUP") end
    if not ctrl then return false end
    local show = DressUpItemLink or DressUpLink
    if type(show) ~= "function" or not entry.data or not entry.data.id then return false end
    pcall(show, "item:" .. tostring(entry.data.id))
    return true
end
E.PreviewItem = previewItem

-- Only collapse records with matching descriptive facts. Similar names alone
-- are not enough: distinct quest variants can have different effects or levels.
local catalogKeyOf
local function catalogKey(entry)
    -- built once per entry; worked out again only if what it reads changes
    local d = entry.data or {}
    local ref = d.reference
    local stamp = entry.fuiCatalogStamp
    if stamp and stamp[1] == entry.name and stamp[2] == d.slot and stamp[3] == ref and stamp[4] == d.quality and stamp[5] == d.itemClass then return entry.fuiCatalogKey end
    local key = catalogKeyOf(entry)
    entry.fuiCatalogKey, entry.fuiCatalogStamp = key, { entry.name, d.slot, ref, d.quality, d.itemClass }
    return key
end
function catalogKeyOf(entry)
    local d, ref = entry.data or {}, entry.data and entry.data.reference or {}
    ref = type(ref) == "table" and ref or {}
    local stats = type(ref.stats) == "table" and table.concat(ref.stats, ";") or ""
    if not ref.itemLevel and not ref.effect and not ref.effects and stats == "" then return entry.key end
    return table.concat({ lowerName(entry), tostring(d.slot or ""), tostring(d.itemClass or ref.itemClass or ""),
        tostring(d.itemSubclass or ref.subclass or ""), tostring(d.quality or ref.quality or ""),
        tostring(ref.requiredLevel or ""), tostring(ref.itemLevel or ""), tostring(ref.effect or ""),
        type(ref.effects) == "table" and table.concat(ref.effects, ";") or "", stats }, "\1")
end

-- The all-slots overview is deliberately small. Candidate scores have already
-- been compared with the player's gear; keep the best three for each slot.
local function topUpgradesPerSlot(candidates, slotMap)
    local counts, out = {}, {}
    for _, candidate in ipairs(candidates) do
        local data = candidate.entry and candidate.entry.data or {}
        local loc = data.gear and data.gear.loc
        local slots = loc and slotMap and slotMap[loc]
        local slot = candidate.comparedSlot or (slots and slots[1])
        -- Rings and trinkets share a comparison group: the engine compares
        -- against the weaker equipped item, rather than rating both separately.
        if slot == 12 then slot = 11 elseif slot == 14 then slot = 13 end
        local group = slot and tostring(slot) or tostring(data.slot or loc or "unknown")
        if (counts[group] or 0) < 3 then
            counts[group] = (counts[group] or 0) + 1
            candidate.overviewSlot = slot or 999
            candidate.overviewGroup = group
            out[#out + 1] = candidate
        end
    end
    table.sort(out, function(a, b)
        local order = { [1]=1, [2]=2, [3]=3, [15]=4, [5]=5, [9]=6, [10]=7, [6]=8, [7]=9, [8]=10, [11]=11, [13]=12, [16]=13, [17]=14, [18]=15 }
        local ao, bo = order[a.overviewSlot] or 999, order[b.overviewSlot] or 999
        if ao ~= bo then return ao < bo end
        if a.overviewGroup ~= b.overviewGroup then return a.overviewGroup < b.overviewGroup end
        local as, bs = a.percent or a.rankValue or 0, b.percent or b.rankValue or 0
        if as ~= bs then return as > bs end
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)
    return out
end
E.TopUpgradesPerSlot = topUpgradesPerSlot

local plannerSlotNames = { [1]="Head", [2]="Neck", [3]="Shoulder", [15]="Back", [5]="Chest", [9]="Wrist", [10]="Hands", [6]="Waist", [7]="Legs", [8]="Feet", [11]="Finger", [13]="Trinket", [16]="Main Hand", [17]="Off Hand", [18]="Ranged" }
local function plannerPage(candidates, offset, grouped)
    local rows, used, previous = {}, 0, nil
    for index = offset + 1, math.min(#candidates, offset + 8) do
        local candidate = candidates[index]
        local heading = grouped and (not previous or previous.overviewGroup ~= candidate.overviewGroup)
        local height = 49 + (heading and 17 or 0)
        if used + height > 319 then break end
        rows[#rows + 1] = { candidate = candidate, y = used + (heading and 17 or 0), heading = heading }
        used, previous = used + height, candidate
    end
    return rows
end
local function plannerMaxOffset(candidates, grouped)
    if not grouped then return math.max(0, #candidates - 6) end
    local used, count, nextGroup = 0, 0, nil
    for index = #candidates, 1, -1 do
        local group = candidates[index].overviewGroup
        local height = 49 + (group ~= nextGroup and 17 or 0)
        if used + height > 319 or count == 8 then break end
        used, count, nextGroup = used + height, count + 1, group
    end
    return math.max(0, #candidates - count)
end
E.PlannerPage, E.PlannerMaxOffset = plannerPage, plannerMaxOffset

----------------------------------------------------------------------
-- Smooth scrolling for the fixed-row lists
----------------------------------------------------------------------
-- Each list keeps its whole-row offset (E.offset, E.bookOffset...), so its
-- render code is unchanged. Its rows sit in a clipped strip that is shifted
-- by the part of a row in between, and every list builds one spare row
-- below the visible ones so a part-scrolled list has no gap at the bottom.
-- A wheel notch glides one row; the scroll bar moves pixel by pixel.
E.smooth = {}

function E.SmoothList(name, spec)
    local pane, rows, step, top = spec.pane, spec.rows, spec.step, spec.top
    local s = { name = name, pane = pane, rows = rows, step = step, refresh = spec.refresh,
        pixel = 0, maxPixel = 0, maxOffset = 0, visible = #rows - 1 }
    local clip = CreateFrame("Frame", nil, pane)
    clip:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -top); clip:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, -top)
    clip:SetHeight(s.visible * step)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    local content = CreateFrame("Frame", nil, clip); content:SetSize(1, 1)
    content:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
    local function wheel(_, delta) E.SmoothWheel(s, delta) end
    for _, row in ipairs(rows) do
        local point, relative, relativePoint, x, y = row:GetPoint(1)
        -- the short form SetPoint("TOPLEFT", x, y) may come back unexpanded
        if type(relative) == "number" then x, y, relativePoint = relative, relativePoint, point end
        row:SetParent(content); row:ClearAllPoints()
        row:SetPoint(point or "TOPLEFT", content, relativePoint or "TOPLEFT", x or 0, y or 0)
        if row.EnableMouseWheel then row:EnableMouseWheel(true); row:SetScript("OnMouseWheel", wheel) end
    end
    pane:EnableMouseWheel(true); pane:SetScript("OnMouseWheel", wheel)
    local glide = CreateFrame("Frame", nil, pane); glide:Hide()
    glide:SetScript("OnUpdate", function(_, elapsed) E.SmoothStep(s, elapsed) end)
    s.clip, s.content, s.glide, s.wheel = clip, content, glide, wheel
    s.scrollbar = ns.ListScrollbar(pane, function(value) E.SmoothJump(s, value) end)
    pane.scrollbar = s.scrollbar
    E.smooth[name] = s
    return s
end

-- Called by a list's render code with its clamped whole-row offset and its
-- item count. Returns the whole-row offset to draw and places the strip.
-- An offset set from outside (a filter, a new entry) moves the list there.
function E.SmoothSync(s, offset, total, visible)
    if not s then return offset end
    local step = s.step
    visible = visible or (#s.rows - 1)
    s.visible = visible
    s.clip:SetHeight(math.max(1, visible * step))
    s.maxOffset = math.max(0, (tonumber(total) or 0) - visible - 1)
    s.maxPixel = math.max(0, (tonumber(total) or 0) - visible) * step
    offset = math.max(0, math.floor(tonumber(offset) or 0))
    if offset ~= s.shownOffset then s.pixel, s.target = offset * step, nil; s.glide:Hide() end
    s.pixel = math.max(0, math.min(s.pixel, s.maxPixel))
    if s.target then s.target = math.max(0, math.min(s.target, s.maxPixel)) end
    local whole = math.min(math.floor(s.pixel / step), s.maxOffset)
    s.shownOffset = whole
    E.SmoothPlace(s, whole)
    return whole
end

function E.SmoothPlace(s, whole)
    local shift = math.max(0, s.pixel - (whole or s.shownOffset or 0) * s.step)
    s.content:ClearAllPoints()
    s.content:SetPoint("TOPLEFT", s.pane, "TOPLEFT", 0, shift)
    ns.UpdateListScrollbar(s.scrollbar, math.floor(s.pixel + 0.5), math.floor(s.maxPixel + 0.5))
end

-- Only a new whole row needs the list drawn again; in between, the strip moves.
function E.SmoothApply(s)
    local whole = math.min(math.floor(s.pixel / s.step), s.maxOffset)
    if whole ~= s.shownOffset then s.refresh() else E.SmoothPlace(s, whole) end
end

function E.SmoothStep(s, elapsed)
    local target = s.target
    if not target then s.glide:Hide(); return end
    local diff = target - s.pixel
    if math.abs(diff) < 0.5 then s.pixel, s.target = target, nil; s.glide:Hide()
    else s.pixel = s.pixel + diff * math.min(1, (tonumber(elapsed) or 0) * 18) end
    E.SmoothApply(s)
end

function E.SmoothWheel(s, delta)
    s.target = math.max(0, math.min(s.maxPixel, (s.target or s.pixel) - (tonumber(delta) or 0) * s.step))
    s.glide:Show()
end

function E.SmoothJump(s, value)
    s.pixel, s.target = math.max(0, math.min(s.maxPixel, tonumber(value) or 0)), nil
    s.glide:Hide()
    E.SmoothApply(s)
end

-- The entry text on the detail page scrolls by pixel inside a clipped strip.
-- Gliding only moves the text; the page is not drawn again.
function E.PlaceDetailText()
    local f = E.window
    if not (f and f.detailClip and f.detail and f.detail.scrollbar) then return end
    local maxPixel = E.detailMaxPixel or 0
    local pixel = math.max(0, math.min(E.detailPixel or 0, maxPixel)); E.detailPixel = pixel
    if E.detailTarget then E.detailTarget = math.max(0, math.min(E.detailTarget, maxPixel)) end
    f.detailText:ClearAllPoints(); f.detailText:SetPoint("TOPLEFT", f.detailClip, "TOPLEFT", 0, pixel)
    ns.UpdateListScrollbar(f.detail.scrollbar, math.floor(pixel + 0.5), math.floor(maxPixel + 0.5))
end

-- lands every glide at once (the tests)
function E:FinishSmoothScroll()
    for _, s in pairs(self.smooth) do
        if s.target then s.pixel, s.target = s.target, nil; s.glide:Hide(); E.SmoothApply(s) end
    end
    if self.detailTarget then
        self.detailPixel, self.detailTarget = self.detailTarget, nil
        if self.window and self.window.detailGlide then self.window.detailGlide:Hide() end
        E.PlaceDetailText()
    end
    local tooltip = self.window and self.window.itemTooltip
    if tooltip and tooltip.target and tooltip.land then tooltip.land() end
end

-- Smooth scrolling: where every row sits, in pixels from the top of the list
-- (a row is 49 high, 17 more with a slot heading above it). Worked out once
-- per list and kept on it.
local PLANNER_VIEW = 319
local function plannerLayout(candidates, grouped)
    local layout = candidates.fuiLayout
    if layout and layout.grouped == grouped and layout.n == #candidates then return layout end
    layout = { grouped = grouped, n = #candidates, y = {}, h = {}, heading = {} }
    local used, previous = 0, nil
    for i, candidate in ipairs(candidates) do
        local heading = grouped and (not previous or previous.overviewGroup ~= candidate.overviewGroup) or false
        local height = 49 + (heading and 17 or 0)
        layout.y[i], layout.h[i], layout.heading[i] = used, height, heading
        used, previous = used + height, candidate
    end
    layout.total = used
    candidates.fuiLayout = layout
    return layout
end
-- The rows showing at pixel offset px (the first and last may be cut off by
-- the list's edge), and the index of the first.
local function plannerPixelPage(candidates, layout, px)
    local y, h = layout.y, layout.h
    local low, high = 1, #candidates
    while low < high do -- the first row whose bottom is below the top edge
        local mid = math.floor((low + high) / 2)
        if y[mid] + h[mid] > px then high = mid else low = mid + 1 end
    end
    local rows = {}
    for index = low, #candidates do
        if y[index] >= px + PLANNER_VIEW or #rows == 8 then break end
        rows[#rows + 1] = { candidate = candidates[index], y = y[index] - px + (layout.heading[index] and 17 or 0), heading = layout.heading[index] }
    end
    return rows, low
end
E.PlannerLayout, E.PlannerPixelPage, E.PLANNER_VIEW = plannerLayout, plannerPixelPage, PLANNER_VIEW

local function item(id, name)
    if type(id) ~= "number" or id <= 0 or not name then return end
    return E.byKey["item:" .. id] or add("Armory", "item", id, name, { id = id })
end

local function wishKey()
    if UnitGUID then local ok, id = pcall(UnitGUID, "player"); if ok and type(id) == "string" and not ns.Secret(id) and id ~= "" then return id end end
    local name, realm
    if UnitFullName then local ok, n, r = pcall(UnitFullName, "player"); if ok and not ns.Secret(n) and not ns.Secret(r) then name, realm = n, r end end
    if not name and UnitName then local ok, n, r = pcall(UnitName, "player"); if ok and not ns.Secret(n) and not ns.Secret(r) then name, realm = n, r end end
    return tostring(realm or "") .. ":" .. tostring(name or "player")
end
local function wishlistFor(setName)
    ns.db = ns.db or {}; ns.db.encyclopediaWishlists = ns.db.encyclopediaWishlists or {}
    local key = wishKey(); ns.db.encyclopediaWishlists[key] = ns.db.encyclopediaWishlists[key] or {}
    if setName then
        ns.db.encyclopediaGearSets = ns.db.encyclopediaGearSets or {}; ns.db.encyclopediaGearSets[key] = ns.db.encyclopediaGearSets[key] or {}
        local sets = ns.db.encyclopediaGearSets[key]; sets[setName] = sets[setName] or {}; return sets[setName]
    end
    return ns.db.encyclopediaWishlists[key]
end
local function wishlist() return wishlistFor(E.activeGearSet) end
local function gearSetNames()
    local sets = ns.db and ns.db.encyclopediaGearSets and ns.db.encyclopediaGearSets[wishKey()] or {}
    local names = {}; for name in pairs(sets) do names[#names + 1] = name end; table.sort(names); return names
end
local function wishHas(id) return id and wishlist()[tostring(id)] ~= nil end
local function wishToggle(entry)
    local id = entry and entry.data and entry.data.id
    if not id then return end
    local w, key = wishlist(), tostring(id)
    if w[key] then w[key] = nil else w[key] = { name = entry.name, slot = entry.data.slot } end
end
E.WishlistHas, E.ToggleWishlist = wishHas, wishToggle
local itemIcon
local function enchantKey(option)
    if option.s then return "enchant:spell:" .. tostring(option.s) end
    if option.i then return "enchant:item:" .. tostring(option.i) end
    if option.e then return "enchant:effect:" .. tostring(option.e) end
end
function E:ImportLegacyWishlist()
    local old = type(_G.OneForAllCharDB) == "table" and _G.OneForAllCharDB.wishlist
    if type(old) ~= "table" or not next(old) or type(ns.db) ~= "table" then return end
    local character = wishKey()
    ns.db.encyclopediaWishImports = ns.db.encyclopediaWishImports or {}
    if ns.db.encyclopediaWishImports[character] then return end
    local target, unresolved = wishlistFor(), {}
    local source = ns.IndependentReference
    for key, wanted in pairs(old) do
        if wanted then
            local id = not ns.Secret(key) and (type(key) == "number" or type(key) == "string") and tonumber(key)
            if id and id > 0 and id == math.floor(id) then
                local newKey = tostring(id)
                if not target[newKey] then
                    local name
                    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
                    if info then local ok, value = pcall(info, id); if ok and type(value) == "string" and not ns.Secret(value) then name = value end end
                    target[newKey] = { name = name or ("Item " .. id) }
                end
            elseif type(key) == "string" then
                local kind, number = key:match("^ench:([si])(%d+)$"); number = tonumber(number)
                local matched
                if number then for _, option in ipairs(source and source.ENCHANT_OPTIONS or {}) do
                    if (kind == "s" and option.s == number) or (kind == "i" and option.i == number) then matched = option; break end
                end end
                if matched then
                    local newKey = enchantKey(matched)
                    if newKey and not target[newKey] then
                        target[newKey] = { name = matched.n, enchant = true, option = { n = matched.n, e = matched.e, s = matched.s, i = matched.i, p = matched.p, req = matched.req, st = matched.st, src = matched.src } }
                    end
                else unresolved[key] = true end
            end
        end
    end
    if next(unresolved) then
        ns.db.encyclopediaLegacyWishUnresolved = ns.db.encyclopediaLegacyWishUnresolved or {}
        ns.db.encyclopediaLegacyWishUnresolved[character] = unresolved
        ns.Print("Some OneForAll wishlist entries could not be matched; their IDs were saved for later recovery.")
    end
    ns.db.encyclopediaWishImports[character] = true
end
ns.On("PLAYER_LOGIN", function() E:ImportLegacyWishlist() end)
ns.On("UPDATE_FACTION", function() if E.window and E.window:IsShown() and E.selected == "Reputations" then E:Render() end end)
local function toggleEnchantWish(option)
    local key = enchantKey(option); if not key then return end
    local saved = wishlist()
    if saved[key] then saved[key] = nil else saved[key] = { name = option.n, enchant = true, option = { n = option.n, e = option.e, s = option.s, i = option.i, p = option.p, req = option.req, st = option.st, src = option.src } } end
end
local inventoryTypes = { INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_BODY = 4, INVTYPE_CHEST = 5, INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_FINGER = 11, INVTYPE_TRINKET = 12, INVTYPE_WEAPON = 13, INVTYPE_SHIELD = 14, INVTYPE_RANGED = 15, INVTYPE_CLOAK = 16, INVTYPE_2HWEAPON = 17, INVTYPE_ROBE = 20, INVTYPE_WEAPONMAINHAND = 21, INVTYPE_WEAPONOFFHAND = 22, INVTYPE_HOLDABLE = 23, INVTYPE_THROWN = 25, INVTYPE_RANGEDRIGHT = 26 }
local function maskHas(mask, index)
    mask = tonumber(mask) or 0
    return mask == 0 or index and math.floor(mask / 2 ^ index) % 2 == 1
end
local function equippedEnchant(slot)
    if not GetInventoryItemLink then return nil end
    local ok, link = pcall(GetInventoryItemLink, "player", slot)
    if not ok or type(link) ~= "string" or ns.Secret(link) then return nil end
    local id = tonumber(link:match("item:%-?%d+:(%d+)"))
    return id and id > 0 and id or nil
end
local function enchantOptions(slot)
    local source = referenceSource()
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not (source and type(source.ENCHANT_OPTIONS) == "table" and GetInventoryItemID and instant) then return {}, nil end
    local ok, id = pcall(GetInventoryItemID, "player", slot)
    if not ok or type(id) ~= "number" or ns.Secret(id) then return {}, nil end
    local success, _, _, _, location, _, class, subclass = pcall(instant, id)
    if not success or ns.Secret(location) or ns.Secret(class) or ns.Secret(subclass) then return {}, id end
    local inventoryType, options = inventoryTypes[location], {}
    if inventoryType then
        for _, option in ipairs(source.ENCHANT_OPTIONS) do
            if option.c == class and maskHas(option.t, inventoryType) and maskHas(option.m, subclass or 0) then options[#options + 1] = option end
        end
    end
    return options, id
end
local function enchantIcon(option)
    if option.i then return itemIcon(option.i) end
    local spellIcon = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
    if option.s and spellIcon then local ok, icon = pcall(spellIcon, option.s); if ok and icon and not ns.Secret(icon) then return icon end end
    return "Interface\\Icons\\Trade_Engraving"
end

local function enchantDetails(option)
    local recipe = option.p and option.s and E.byKey["recipe:" .. option.p .. ":" .. tostring(option.s)]
    local data = recipe and recipe.data
    local characters, seen, sources = {}, {}, {}
    local function addCharacter(name)
        if type(name) ~= "string" or name == "" then return end
        local key = name:lower():match("^[^%-]+")
        if key and not seen[key] then seen[key] = true; characters[#characters + 1] = name end
    end
    local gold = _G.ForeverGold
    local goldAvailable = type(gold) == "table" and type(gold.RecipeKnownBy) == "function"
    if goldAvailable and option.p and (recipe or option.n) then
        local ok, known = pcall(gold.RecipeKnownBy, option.p, recipe and recipe.name or option.n)
        if ok and type(known) == "table" then for _, name in ipairs(known) do addCharacter(name) end end
    end
    local source = referenceSource()
    if option.p and option.s and source and type(source.GetProfessionState) == "function" then
        local ok, state = pcall(source.GetProfessionState, option.p)
        if ok and type(state) == "table" and type(state.known) == "table" and state.known[option.s] and UnitName then
            local gotName, name = pcall(UnitName, "player")
            if gotName and not ns.Secret(name) then addCharacter(name) end
        end
    end
    table.sort(characters)
    if option.src and option.src ~= "" then sources[#sources + 1] = tostring(option.src) end
    if data then
        if data.start then sources[#sources + 1] = "Known when you learn " .. option.p
        elseif not data.ri and not data.fav and not option.src then sources[#sources + 1] = "Profession trainer" end
        if data.fav then sources[#sources + 1] = "Merchant's Favor" .. (recipe.favorCost and (" (" .. recipe.favorCost .. " Favor)") or "") end
        local src = data.src or {}
        for _, vendor in ipairs(src.v or {}) do
            sources[#sources + 1] = "Vendor: " .. tostring(vendor[2] or "Unknown") .. (vendor[3] and (", " .. vendor[3]) or "") .. (vendor.fac and (" [" .. vendor.fac .. "]") or "")
        end
        for _, drop in ipairs(src.d or {}) do sources[#sources + 1] = "Drop: " .. tostring(drop[2] or "Unknown") .. (drop[3] and (", " .. drop[3]) or "") end
        if src.dn and src.dn > #(src.d or {}) then sources[#sources + 1] = "Additional drop sources are not listed here." end
        for _, quest in ipairs(src.qs or {}) do sources[#sources + 1] = "Quest: " .. tostring(quest[2] or quest.name or "Unknown") end
        if data.rn then sources[#sources + 1] = "Recipe item: " .. data.rn end
    end
    if #sources == 0 then sources[1] = "Source not recorded" end
    return { recipe = recipe, characters = characters, sources = sources, goldAvailable = goldAvailable }
end
E.EnchantDetails = enchantDetails
local function recipeFavorites()
    ns.db = ns.db or {}; ns.db.encyclopediaRecipeFavorites = ns.db.encyclopediaRecipeFavorites or {}
    local key = wishKey(); ns.db.encyclopediaRecipeFavorites[key] = ns.db.encyclopediaRecipeFavorites[key] or {}
    return ns.db.encyclopediaRecipeFavorites[key]
end
local function bookStatus(book)
    local source = referenceSource()
    local saved = ns.db and ns.db.encyclopediaBooks and ns.db.encyclopediaBooks[wishKey()]
    if saved and saved[tostring(book.itemId or book.name)] then return "Manually marked turned in" end
    if source and type(source.GetBookState) == "function" then
        local ok, state = pcall(source.GetBookState, source, book)
        local labels = { done = "Turned in", manual = "Manually marked turned in", bag = "In bags", bank = "In bank", questflag = "Quest flagged", missing = "Missing" }
        if ok and labels[state] then return labels[state] end
    end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and book.questId then
        local ok, value = pcall(C_QuestLog.IsQuestFlaggedCompleted, book.questId)
        if ok and not ns.Secret(value) and value == true then return "Quest flagged" end
    end
    if GetItemCount and book.itemId then
        local ok, count = pcall(GetItemCount, book.itemId, false)
        if ok and type(count) == "number" and not ns.Secret(count) and count > 0 then return "In bags" end
        ok, count = pcall(GetItemCount, book.itemId, true)
        if ok and type(count) == "number" and not ns.Secret(count) and count > 0 then return "In bank" end
    end
    return "Not recorded"
end
local function factionStanding(id)
    -- GetFactionDataByID can return a default standing for factions that do
    -- not appear in the player's reputation list. Only present that standing
    -- as the player's when it is actually listed (collapsed headers can hide
    -- entries, so absence is not proof the faction is undiscovered).
    if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
        local ok, count = pcall(C_Reputation.GetNumFactions)
        if ok and type(count) == "number" and not ns.Secret(count) then
            local found = false
            for index = 1, count do
                local good, row = pcall(C_Reputation.GetFactionDataByIndex, index)
                if good and type(row) == "table" and not ns.Secret(row.factionID) and row.factionID == id then found = true; break end
            end
            if not found then return nil, nil, nil, "unlisted" end
        end
    end
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local ok, data = pcall(C_Reputation.GetFactionDataByID, id)
        if ok and type(data) == "table" and not ns.Secret(data.reaction) and type(data.reaction) == "number" then
            local lo, hi, value = data.currentReactionThreshold, data.nextReactionThreshold, data.currentStanding
            if type(lo) == "number" and type(hi) == "number" and type(value) == "number" and not ns.Secret(lo) and not ns.Secret(hi) and not ns.Secret(value) then
                return data.reaction, value - lo, hi - lo
            end
            return data.reaction
        end
    end
    if GetFactionInfoByID then
        local ok, name, _, rank, lo, hi, value = pcall(GetFactionInfoByID, id)
        if ok and name and type(rank) == "number" and not ns.Secret(rank) then
            if type(lo) == "number" and type(hi) == "number" and type(value) == "number" and not ns.Secret(lo) and not ns.Secret(hi) and not ns.Secret(value) then return rank, value - lo, hi - lo end
            return rank
        end
    end
end
local function standingName(rank)
    local defaults = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
    return rank and (_G["FACTION_STANDING_LABEL" .. rank] or defaults[rank]) or "Not met yet"
end
local function standingColor(rank)
    if rank == 5 then return 0.35, 0.9, 0.4 end
    if rank == 6 then return 0.3, 0.65, 1 end
    if rank == 7 then return 0.75, 0.4, 1 end
    if rank == 8 then return 1, 0.6, 0.2 end
    return ns.C.muted[1], ns.C.muted[2], ns.C.muted[3]
end
-- Coordinates in the reference datasets are percentages, while the map API uses 0..1.
local function showLocation(mapID, x, y)
    if not mapID or type(x) ~= "number" or type(y) ~= "number" or x < 0 or x > 100 or y < 0 or y > 100 then
        ns.Print("No reliable map location is available for this entry."); return false
    end
    if InCombatLockdown and InCombatLockdown() then ns.Print("Open the map location after leaving combat."); return false end
    local function referenceMap()
        local source = referenceSource()
        if source and type(source.ShowOnMap) == "function" then
            local ok, result = pcall(source.ShowOnMap, source, { mapID = mapID, x = x, y = y })
            if ok and result ~= false then if E.window then E.window:Hide() end; return true end
        end
        return false
    end
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
        if referenceMap() then return true end
        ns.Print("Map waypoints are unavailable on this client."); return false
    end
    local ok, point = pcall(UiMapPoint.CreateFromCoordinates, mapID, x / 100, y / 100)
    if not ok or not point then ns.Print("Could not create a map waypoint for this location."); return false end
    local sent, result = pcall(C_Map.SetUserWaypoint, point)
    if not sent or result == false then if referenceMap() then return true end; ns.Print("Could not set a map waypoint for this location."); return false end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
    if not WorldMapFrame then
        if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_WorldMap")
        elseif LoadAddOn then pcall(LoadAddOn, "Blizzard_WorldMap") end
    end
    local map = WorldMapFrame
    if map then
        if E.window then E.window:Hide() end
        if ShowUIPanel then pcall(ShowUIPanel, map) elseif map.Show then pcall(map.Show, map) end
        if map.SetMapID then pcall(map.SetMapID, map, mapID) end
    else ns.Print("Waypoint set. Open the world map to see it.") end
    return true
end
E.ShowLocation = showLocation
local function questStartLocation(entry)
    local d = entry and entry.data or {}
    if d.location and d.location.mapID and type(d.location.x) == "number" and type(d.location.y) == "number" then return d.location end
    local quest, npc = _G.QuestDB, _G.NpcDB
    if not (d.id and npc and type(npc.spawns) == "function") then return end
    local starters
    if quest and type(quest.startedBy)=="function" then local ok, data=pcall(quest.startedBy,d.id);if ok and type(data)=="table" then starters=data end end
    if (not starters or type(starters[1])~="table" or #starters[1]==0) and d.discovery and d.discovery.giverID then starters={{d.discovery.giverID}} end
    if not starters or type(starters[1])~="table" then return end
    local loader = _G.QuestieLoader
    if not (loader and type(loader.ImportModule) == "function") then return end
    local good, zones = pcall(loader.ImportModule, loader, "ZoneDB")
    if not good or not zones or type(zones.GetUiMapIdByAreaId) ~= "function" then return end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local desired = faction == "Horde" and "H" or faction == "Alliance" and "A" or nil
    for _, id in ipairs(starters[1]) do
        local allowed = true
        if desired and type(npc.friendlyToFaction) == "function" then
            local read, side = pcall(npc.friendlyToFaction, id)
            if read and type(side) == "string" and not side:find(desired, 1, true) then allowed = false end
        end
        local found, spawns = false, nil
        if allowed then found, spawns = pcall(npc.spawns, id) end
        if found and type(spawns) == "table" then
            local areaIDs = {}; for area in pairs(spawns) do if type(area) == "number" then areaIDs[#areaIDs + 1] = area end end; table.sort(areaIDs)
            for _, area in ipairs(areaIDs) do
                local mapped, mapID = pcall(zones.GetUiMapIdByAreaId, zones, area)
                if mapped and type(mapID) == "number" and mapID > 0 and type(spawns[area]) == "table" then
                    for _, pos in ipairs(spawns[area]) do
                        if type(pos) == "table" and type(pos[1]) == "number" and type(pos[2]) == "number" and pos[1] >= 0 and pos[1] <= 100 and pos[2] >= 0 and pos[2] <= 100 then
                            return { mapID = mapID, x = pos[1], y = pos[2], npcID = id }
                        end
                    end
                end
            end
        end
    end
end
E.QuestStartLocation = questStartLocation
-- OneForAll's planner is synchronous. Use Forever Gold's buyout observations
-- during this calculation only, then restore the provider even if it errors.
local function withGoldPrices(engine, fn, ...)
    local gold, original = _G.ForeverGold, engine and engine.AHPrice
    if not (engine and type(fn) == "function") then return false end
    if gold and type(gold.AHPrice) == "function" and type(gold.IsBuyout) == "function" then
        engine.AHPrice = function(id)
            local valid, buyout = pcall(gold.IsBuyout, id)
            if valid and buyout then
                local ok, price = pcall(gold.AHPrice, id)
                if ok and type(price) == "number" and not ns.Secret(price) and price > 0 then return price end
            end
            if type(original) == "function" then return original(id) end
        end
    end
    local results = { pcall(fn, ...) }
    engine.AHPrice = original
    return unpack(results)
end

local function dungeonLevel(dungeon)
    return tonumber(tostring(dungeon.level or ""):match("%d+")) or tonumber(dungeon.minLevel)
end

local function raidSize(dungeon)
    local size = tonumber(dungeon.size)
    return size and size > 0 and size or "unknown"
end

-- OneForAll supplies the game texture and its picture bounds. Crop around
-- the supplied focus without stretching the artwork in the wide row.
local function dungeonArt(dungeon, width, height)
    local source = referenceSource()
    local info = source and source.DUNGEON_LOADSCREENS and source.DUNGEON_LOADSCREENS[dungeon.key]
    if type(info) ~= "table" or not info[1] then return end
    local l, r, t, b, aspect = info[2], info[3], info[4], info[5], info[6]
    if type(l) ~= "number" or type(r) ~= "number" or type(t) ~= "number" or type(b) ~= "number"
        or type(aspect) ~= "number" or aspect <= 0 or r <= l or b <= t then return end
    local fx, fy = tonumber(info[7]) or 0.5, tonumber(info[8]) or 0.5
    local zoom = math.max(0.01, math.min(1, tonumber(info[9]) or 1))
    local centerX = math.max(l, math.min(r, l + (r - l) * fx))
    local centerY = math.max(t, math.min(b, t + (b - t) * fy))
    local cropW, cropH = (r - l) * zoom, (b - t) * zoom
    local targetAspect = width / height
    if targetAspect > aspect then cropH = cropH * aspect / targetAspect
    else cropW = cropW * targetAspect / aspect end
    local left = math.max(l, math.min(r - cropW, centerX - cropW / 2))
    local top = math.max(t, math.min(b - cropH, centerY - cropH / 2))
    return info[1], left, left + cropW, top, top + cropH
end
E.DungeonArt = dungeonArt

local function dungeonMatches(dungeon, query)
    local text = (tostring(dungeon.name or "") .. " " .. tostring(dungeon.area or "") .. " " .. tostring(dungeon.mapZone or "")):lower()
    if text:find(query, 1, true) then return true end
    for _, boss in ipairs(dungeon.bosses or {}) do
        if tostring(boss.name or ""):lower():find(query, 1, true) then return true end
    end
    return false
end

local function bossInfo(boss)
    local source = referenceSource()
    if not source or not boss then return nil, nil, nil end
    local function get(name)
        if type(source[name]) ~= "function" then return end
        local ok, value = pcall(source[name], source, boss)
        if ok and not ns.Secret(value) then return value end
    end
    local level = get("GetBossLevel") or (source.BOSS_LEVELS and (source.BOSS_LEVELS[boss.npcID] or source.BOSS_LEVELS[boss.name]))
    local kind = get("GetBossType") or (source.BOSS_TYPES and source.BOSS_TYPES[boss.npcID])
    local rank = get("GetBossRank") or (boss.rare and "Rare" or nil)
    return level, kind, rank
end

local function bossPortrait(texture, dungeon, boss, fallback)
    local source = referenceSource()
    if source and source.UI and type(source.UI.setBossPortrait) == "function" and not fallback then
        local ok = pcall(source.UI.setBossPortrait, texture, dungeon, boss)
        if ok then return end
    end
    if boss.customIcon then texture:SetTexture(boss.customIcon); return end
    local display = boss.displayID
    if source and type(source.GetLearnedBossDisplay) == "function" then
        local ok, learned = pcall(source.GetLearnedBossDisplay, source, boss)
        if ok and type(learned) == "number" and learned > 0 then display = learned end
    end
    if type(display) == "number" and display > 0 and type(SetPortraitTextureFromCreatureDisplayID) == "function" then
        local ok = pcall(SetPortraitTextureFromCreatureDisplayID, texture, display)
        if ok then return end
    end
    texture:SetTexture(boss.fallbackIcon or fallback or "Interface\\Icons\\INV_Misc_QuestionMark")
end

-- NPC directory uses one gold icon per recorded creature type. Boss and
-- tame entries elsewhere keep their own portraits.
local NPC_TYPE_ICONS = {
    humanoid="humanoid", beast="beast", undead="undead", demon="demon", dragonkin="dragonkin",
    elemental="elemental", critter="critter", mechanical="mechanical", giant="giant", totem="totem",
    aquatic="aquatic", ["non-combat pet"]="pet", ["non combat pet"]="pet", pet="pet", ["wild pet"]="pet",
    ["gas cloud"]="elemental",
}
function E.NpcTypeIcon(data)
    local kind = type(data) == "table" and data.type
    if (type(kind) ~= "string" or kind == "" or kind:lower() == "not specified" or kind:lower() == "unspecified") and type(data) == "table" then
        local source = referenceSource()
        if source and type(source.GetBossType) == "function" then
            local ok, observed = pcall(source.GetBossType, source, data)
            if ok and not ns.Secret(observed) and type(observed) == "string" then kind = observed end
        end
    end
    kind = type(kind) == "string" and kind:lower() or ""
    return "Interface\\AddOns\\ForeverUI\\Art\\npc-type-" .. (NPC_TYPE_ICONS[kind] or "unknown")
end

local function npcRoles(data)
    data = data or {}
    local title = tostring(data.title or ""):lower()
    return {
        vendor = data.vendor == true or title:find("merchant", 1, true) ~= nil or title:find("vendor", 1, true) ~= nil,
        trainer = data.trainer == true or title:find("trainer", 1, true) ~= nil,
        quest = data.questGiver == true,
    }
end
E.NpcRoles = npcRoles

local function npcPortrait(texture, entry)
    texture:SetTexture(E.NpcTypeIcon(entry and entry.data))
end

local questIcon = "Interface\\AddOns\\ForeverUI\\Art\\encyclopedia-quest"
local pendingItemIcons, failedItemData, itemAttempts = {}, {}, {}
local iconEvents
local function requestItem(id)
    if id and C_Item and C_Item.RequestLoadItemDataByID and not pendingItemIcons[id] and not failedItemData[id] then
        if (itemAttempts[id] or 0) >= 3 then failedItemData[id] = true; return false end
        itemAttempts[id] = (itemAttempts[id] or 0) + 1
        pendingItemIcons[id] = GetTime and GetTime() or 0
        if not iconEvents then
            iconEvents = CreateFrame("Frame"); E.itemEvents = iconEvents
            pcall(iconEvents.RegisterEvent, iconEvents, "GET_ITEM_INFO_RECEIVED")
            pcall(iconEvents.RegisterEvent, iconEvents, "ITEM_DATA_LOAD_RESULT")
            iconEvents:SetScript("OnEvent", function(_, _, itemID, success)
                if pendingItemIcons[itemID] or (failedItemData[itemID] and success ~= false) then
                    pendingItemIcons[itemID] = nil; if success == false then failedItemData[itemID] = true else failedItemData[itemID], itemAttempts[itemID] = nil, nil end
                    E.gearDataRevision = (E.gearDataRevision or 0) + 1
                    if not E.itemRefreshPending and E.window and E.window:IsShown() then
                        E.itemRefreshPending = true
                        local function refresh() E.itemRefreshPending = nil; if E.window and E.window:IsShown() then E:Render() end end
                        if C_Timer and C_Timer.After then C_Timer.After(0.25, refresh) else refresh() end
                    end
                end
            end)
        end
        local ok, result = pcall(C_Item.RequestLoadItemDataByID, id)
        if not ok or result == false then pendingItemIcons[id] = nil; failedItemData[id] = true; return false end
        return true
    end
end
local function pollPendingItems()
    if E.itemPollPending or not (C_Timer and C_Timer.After) then return end
    E.itemPollPending = true
    C_Timer.After(1, function()
        E.itemPollPending = nil
        if not (E.window and E.window:IsShown() and E.selected == "Armory" and E.armorFilter == "planner") then return end
        local changed, pending, now = false, false, GetTime and GetTime() or 0
        for id, started in pairs(pendingItemIcons) do
            local ready = false
            if C_Item and C_Item.IsItemDataCachedByID then local ok, value = pcall(C_Item.IsItemDataCachedByID, id); ready = ok and value == true end
            if ready or now - started >= 4 then
                pendingItemIcons[id] = nil; if not ready and (itemAttempts[id] or 0) >= 3 then failedItemData[id] = true end; changed = true
            else pending = true end
        end
        if changed then E.gearDataRevision = (E.gearDataRevision or 0) + 1; E:Render()
        elseif pending then pollPendingItems() end
    end)
end
itemIcon = function(id)
    local icon
    if C_Item and C_Item.GetItemIconByID then local ok, value = pcall(C_Item.GetItemIconByID, id); if ok and not ns.Secret(value) then icon = value end end
    if not icon and GetItemIcon then local ok, value = pcall(GetItemIcon, id); if ok and not ns.Secret(value) then icon = value end end
    if not icon then requestItem(id) end
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function itemQuality(entry, fallback)
    local data = entry and entry.data or {}; local gear = data.gear
    local quality = fallback or data.quality or (gear and gear.q)
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if info and data.id then local ok, _, _, value = pcall(info, data.id); if ok and type(value) == "number" and not ns.Secret(value) then quality = value end end
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color then return color.r, color.g, color.b end
    return ns.C.text[1], ns.C.text[2], ns.C.text[3]
end
local function itemRequiredLevel(id)
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if info and id then local ok, _, _, _, _, level = pcall(info, id); if ok and type(level) == "number" and not ns.Secret(level) then return level end end
end

local function entryIcon(texture, entry)
    texture._ofaNpc = nil
    texture:SetTexCoord(0, 1, 0, 1)
    if not entry then texture:Hide(); return false end
    local kind, data = entry.kind, entry.data or {}
    if kind == "quest" then texture:SetTexture(questIcon)
    elseif kind == "object" then texture:SetTexture("Interface\\Icons\\INV_Box_01")
    elseif kind == "book" then texture:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    elseif kind == "campObject" then texture:SetTexture(data.icon or itemIcon(data.id))
    elseif kind == "recipe" or kind == "camping" or kind == "favor" then
        local source = referenceSource(); local icon
        if source and type(source.RecipeIcon) == "function" then local ok, value = pcall(source.RecipeIcon, data); if ok and not ns.Secret(value) then icon = value end end
        texture:SetTexture(icon or (data.i and itemIcon(data.i)) or data.ic or "Interface\\Icons\\INV_Misc_QuestionMark")
    elseif kind == "item" then
        local icon = itemIcon(data.id)
        if icon == "Interface\\Icons\\INV_Misc_QuestionMark" and data.icon and data.icon ~= 0 then icon = type(data.icon) == "string" and (data.icon:find("\\") and data.icon or ("Interface\\Icons\\" .. data.icon)) or data.icon end
        texture:SetTexture(icon)
    elseif kind == "set" then
        local piece = data.i and data.i[1]; local icon = piece and itemIcon(piece[1]) or "Interface\\Icons\\INV_Misc_QuestionMark"
        if icon == "Interface\\Icons\\INV_Misc_QuestionMark" and piece and piece[5] then icon = type(piece[5]) == "string" and (piece[5]:find("\\") and piece[5] or ("Interface\\Icons\\" .. piece[5])) or piece[5] end
        texture:SetTexture(icon)
    elseif (kind == "family" or kind == "ability") and data.icon then texture:SetTexture("Interface\\Icons\\" .. data.icon)
    elseif kind == "boss" or kind == "tame" or kind == "npc" then
        local dungeon
        for _, related in ipairs(entry.links or {}) do if related.kind == "dungeon" then dungeon = related.data; break end end
        if kind == "npc" then npcPortrait(texture, entry) else bossPortrait(texture, dungeon, data) end
    elseif kind == "dungeon" then
        local image, l, r, t, b = dungeonArt(data, 40, 24)
        if not image then texture:Hide(); return false end
        texture:SetTexture(image); texture:SetTexCoord(l, r, t, b)
    else texture:Hide(); return false end
    texture:Show(); return true
end
E.EntryIcon = entryIcon

local function entryLabel(entry)
    if entry.kind == "quest" then return "[" .. tostring(entry.data.level or "?") .. "]  " .. entry.name end
    return entry.name
end

local function dropInfo(dungeon, boss, id)
    local source = referenceSource()
    if not source or not id then return end
    if type(source.GetDropChance) == "function" then
        local ok, chance, kills, scaled = pcall(source.GetDropChance, dungeon.name, boss.name, id)
        if ok and not ns.Secret(chance) and type(chance) == "number" then return chance, kills, scaled end
    end
    local dungeonDrops = source.DUNGEON_DROP_CHANCE and source.DUNGEON_DROP_CHANCE[dungeon.name]
    local bossDrops = dungeonDrops and dungeonDrops[boss.name]
    local chance = bossDrops and bossDrops[id]
    if type(chance) ~= "number" then return end
    for _, row in ipairs(source.DUNGEON_DROP_FOREVER or {}) do
        if row[1] == dungeon.name and row[2] == boss.name and row[3] == id then return chance, row[4], row[5] end
    end
    return chance
end
E.DropInfo = dropInfo

function E:RefreshData()
    self.plannerCache, self.plannerShown = nil, nil
    local currentKey = self.current and self.current.key
    local bossKey = self.boss and self.boss.key
    self.entries, self.byKey, self.gearLoaded = {}, {}, false
    self.hiddenNPCIds = {}
    for _, record in ipairs(ns.NpcReferenceData and ns.NpcReferenceData.npcs or {}) do
        if record.id and isHiddenNPC(record.name, record) then self.hiddenNPCIds[record.id] = true end
    end
    local source = referenceSource()
    local reference = ns.ReferenceData
    self.legacyAvailable = type(_G.OneForAll) == "table"
    self.independentAvailable = type(ns.IndependentReference) == "table"
    self.referenceAvailable = type(reference) == "table" and reference.game == "wow-forever" and reference.schemaVersion == 1
    self.sourceAvailable = self.legacyAvailable or self.independentAvailable or self.referenceAvailable
    if not self.sourceAvailable then self.current, self.history = nil, {}; return end
    source = type(source) == "table" and source or {}
    local bossesByID, bossesByName = {}, {}
    local favorCosts, favorVendorLinks = {}, {}
    for _, record in ipairs(source.MERCHANT_RECIPES or {}) do favorCosts[tostring(record.profession) .. "|" .. tostring(record.name)] = record.cost end
    for _, dungeon in ipairs(source.DUNGEONS or {}) do
        local dungeonEntry = add("Dungeons", "dungeon", dungeon.key or dungeon.name, dungeon.name, dungeon)
        for _, boss in ipairs(dungeon.bosses or {}) do
            local bossEntry = add("Dungeons", "boss", tostring(dungeon.key or dungeon.name) .. ":" .. tostring(boss.npcID or boss.name), boss.name, boss, dungeon.name)
            link(dungeonEntry, bossEntry)
            if bossEntry then
                if boss.npcID then bossesByID[boss.npcID] = bossEntry end
                bossesByName[tostring(boss.name) .. "|" .. tostring(dungeon.name)] = bossEntry
            end
            for _, loot in ipairs(boss.loot or {}) do linkItemSource(item(loot.id, loot.name), bossEntry, "Boss") end
        end
        local dungeonQuests = ns.DungeonQuestTracker and ns.DungeonQuestTracker:Quests(dungeon) or dungeon.quests or {}
        for _, quest in ipairs(dungeonQuests) do
            local questEntry = add("Dungeons", "quest", tostring(dungeon.key or dungeon.name) .. ":" .. tostring(quest.id or quest.name), quest.name, quest, dungeon.name)
            link(dungeonEntry, questEntry)
            for _, reward in ipairs(quest.rewards or {}) do linkItemSource(item(reward.id, reward.name), questEntry, "Quest") end
            for _, reward in ipairs(quest.alsoRewards or {}) do linkItemSource(item(reward.id, reward.name), questEntry, "Quest") end
        end
        for _, loot in ipairs(dungeon.trashLoot or {}) do link(dungeonEntry, item(loot.id, loot.name)) end
    end
    local families, abilities, tames = {}, {}, {}
    local function tame(beast, familyName)
        if type(beast) ~= "table" or not beast.name then return end
        local id = beast.npcID and tostring(beast.npcID) or (beast.name .. "|" .. tostring(beast.zone or ""))
        local entry = tames[id]
        if not entry then
            local family = families[familyName or beast.family]
            local familyIcon = family and family.data.icon and ("Interface\\Icons\\" .. family.data.icon)
            local data = { npcID = beast.npcID, displayID = beast.displayID, customIcon = beast.customIcon, fallbackIcon = beast.fallbackIcon or beast.icon or familyIcon, family = familyName or beast.family, level = beast.level,
                zone = beast.zone, mapID = beast.mapID, x = beast.x, y = beast.y, teachings = {} }
            entry = add("Pets", "tame", id, beast.name, data, data.family)
            tames[id] = entry
        else
            local d = entry.data
            d.family = d.family or familyName or beast.family
            if not d.zone then d.zone = beast.zone end
            if not d.mapID then d.mapID, d.x, d.y = beast.mapID, beast.x, beast.y end
            entry.extra = d.family
        end
        if beast.why then entry.data.note = beast.why end
        link(entry, families[entry.data.family])
        return entry
    end
    for _, family in ipairs(source.PET_FAMILIES or {}) do
        families[family.name] = add("Pets", "family", family.name, family.name, family)
    end
    for _, family in ipairs(source.PET_FAMILIES or {}) do
        for _, beast in ipairs(family.tames or {}) do tame(beast, family.name) end
        for _, beast in ipairs((source.PET_TAMES_EXTRA or {})[family.name] or {}) do tame(beast, family.name) end
    end
    for _, beast in ipairs(source.PET_RARES or {}) do local rare = tame(beast, beast.family); if rare then rare.data.rare = true end end
    for _, ability in ipairs(source.PET_ABILITIES or {}) do
        local entry = add("Pets", "ability", ability.name, ability.name, ability, "Pet ability")
        abilities[ability.name] = entry
        for _, familyName in ipairs(ability.families or {}) do
            if familyName == "All families" then
                for _, family in pairs(families) do link(entry, family) end
            else link(entry, families[familyName]) end
        end
        for _, rank in ipairs(ability.ranks or {}) do
            local rankEntry = add("Pets", "petRank", ability.name .. ":" .. tostring(rank.rank),
                ability.name .. " — Rank " .. tostring(rank.rank), rank, ability.name)
            link(entry, rankEntry)
            for _, beast in ipairs(rank.learnFrom or {}) do
                local beastEntry = tame(beast, beast.family)
                if beastEntry then
                    link(rankEntry, beastEntry)
                    beastEntry.data.teachings[#beastEntry.data.teachings + 1] = ability.name .. " rank " .. tostring(rank.rank)
                end
            end
        end
    end
    for _, family in ipairs(source.PET_FAMILIES or {}) do
        for _, name in ipairs(family.abilities or {}) do link(families[family.name], abilities[name]) end
        for _, name in ipairs(family.trainer or {}) do link(families[family.name], abilities[name]) end
    end
    for profession, recipes in pairs(source.PROFESSION_RECIPES or {}) do
        add("Professions", "profession", profession, profession, { name = profession })
        for _, recipe in ipairs(recipes) do
            if type(recipe) == "table" and recipe.n then
                local id = tostring(profession) .. ":" .. tostring(recipe.s or recipe.n)
                local rec = add("Professions", "recipe", id, recipe.n, recipe, profession)
                local recipeID = tonumber(recipe.ri)
                local audit = ns.FavorRecipeAudited and ns.FavorRecipeAudited[recipeID]
                local cost = (audit and audit.cost) or favorCosts[profession .. "|" .. recipe.n]
                local report = ns.FavorRecipeReports and ns.FavorRecipeReports[recipeID]
                local caution = ns.FavorRecipeCautions and ns.FavorRecipeCautions[recipeID]
                local observation, observedAtVendor
                if ns.FavorVendorObservation then observation, observedAtVendor = ns.FavorVendorObservation(recipeID) end
                if observation then caution = (caution and (caution .. " ") or "") .. observation end
                if rec then rec.favorCost, rec.favorReport, rec.favorCaution = cost, report, caution end
                if recipe.cat == "Camping" then link(rec, add("Camping", "camping", id, recipe.n, recipe, profession)) end
                local plan = item(recipe.ri, recipe.rn)
                if recipe.fav or cost ~= nil or report then
                    local favor = add("Favor", "favor", id, recipe.n, recipe, profession)
                    if favor then favor.favorCost, favor.favorReport, favor.favorCaution = cost, report, caution end
                    link(rec, favor)
                    local note = report or (cost and ("Costs " .. tostring(cost) .. " Merchant's Favor according to the recipe reference.") or "Merchant's Favor recipe; cost not recorded.")
                    if caution then note = note .. " " .. caution end
                    linkItemSource(plan, favor, "Merchant's Favor", nil, note, { favorCost = cost, uncertain = caution ~= nil and not observedAtVendor })
                    local vendors, seen = {}, {}
                    local function addVendor(v)
                        if type(v) ~= "table" or not tonumber(v[1]) then return end
                        local vendorID = tonumber(v[1])
                        v = (ns.FavorVendors and ns.FavorVendors[vendorID]) or v
                        if seen[vendorID] or type(v[2]) ~= "string" or v[2] == "" then return end
                        seen[vendorID] = true; vendors[#vendors + 1] = v
                        favorVendorLinks[#favorVendorLinks + 1] = { vendor = v, plan = plan, recipe = rec, favor = favor, cost = cost, report = report, caution = caution }
                    end
                    for _, vendor in ipairs((recipe.fav or cost ~= nil) and recipe.src and recipe.src.v or {}) do addVendor(vendor) end
                    for _, vendorID in ipairs(ns.FavorRecipeVendorEvidence and ns.FavorRecipeVendorEvidence[recipeID] or {}) do
                        addVendor(ns.FavorVendors and ns.FavorVendors[vendorID])
                    end
                    for _, vendorID in ipairs(audit and audit.vendors or {}) do addVendor(ns.FavorVendors and ns.FavorVendors[vendorID]) end
                    if #vendors > 0 then if rec then rec.favorVendors = vendors end; if favor then favor.favorVendors = vendors end end
                end
                linkItemSource(item(recipe.i, recipe.n), rec, "Crafted")
                linkItemSource(plan, rec, "Teaches")
                for _, reagent in ipairs(recipe.r or {}) do linkReagent(item(reagent[1], reagent[3]), rec) end
            end
        end
    end
    for _, group in ipairs(source.CAMPING_PROFESSIONS or {}) do
        for _, obj in ipairs(group.items or {}) do
            local entry = add("Camping", "campObject", tostring(group.profession) .. ":" .. tostring(obj.id or obj.name), obj.name, obj, group.profession)
            if entry and obj.id then link(entry, item(obj.id, obj.name)) end
        end
    end
    for _, faction in ipairs(source.ARMORY_REPUTATION or {}) do
        local factionEntry = add("Reputations", "faction", faction.id or faction.n, faction.n, faction)
        for _, reward in ipairs(faction.i or {}) do linkItemSource(item(reward[1], reward[2]), factionEntry, "Reputation") end
    end
    for _, set in ipairs(source.ARMORY_SETS or {}) do
        local setEntry = add("Armory", "set", set.id or set.n, set.n, set)
        for _, piece in ipairs(set.i or {}) do
            local pieceEntry = item(piece[1], piece[2])
            if pieceEntry and type(set.arm) == "string" and type(piece[3]) == "string" then
                pieceEntry.data.armorType = pieceEntry.data.armorType or set.arm
                pieceEntry.data.slot = pieceEntry.data.slot or piece[3]
            end
            if pieceEntry then
                pieceEntry.data.slot = pieceEntry.data.slot or piece[3]
                pieceEntry.data.icon = pieceEntry.data.icon or piece[5]
            end
            link(setEntry, pieceEntry)
        end
    end
    for _, book in ipairs(source.BOOKS or {}) do
        local entry = add("Library Books", "book", book.itemId or book.name, book.name, book, book.zone)
        if entry then link(entry, item(book.itemId, book.name)) end
    end
    for _, entry in ipairs(self.entries) do
        local src = entry.data.src
        if type(src) == "table" and type(src.d) == "table" then
            for _, drop in ipairs(src.d) do
                if type(drop) == "table" then
                    link(entry, bossesByID[drop[1]] or bossesByName[tostring(drop[2]) .. "|" .. tostring(drop[3])])
                end
            end
        end
    end
    local questIndex, npcIndex = {}, {}
    local legacyCount = #self.entries
    if self.referenceAvailable then
        for _, record in ipairs(reference.npcs or {}) do
            npcIndex[record.id] = add("NPCs", "npc", record.id, record.name, {
                id = record.id, npcID = record.id, displayID = record.displayID, title = record.title, level = record.level, maxLevel = record.maxLevel, side = record.side,
                type = record.type, zone = record.zone, classification = record.classification, reference = record,
            })
            link(npcIndex[record.id], tames[tostring(record.id)])
        end
        for _, record in ipairs(reference.quests or {}) do
            local data = { id = record.id, level = record.level, required = record.required, side = record.side, starts = record.starts, turnin = record.turnin, classes = record.classes, repeatable = record.repeatable, reference = record }
            local quest = add("Quests", "quest", "wowhead:" .. record.id, record.name, data)
            questIndex[record.id] = quest
            for _, npcID in ipairs(record.npcIds or {}) do link(quest, npcIndex[npcID]) end
        end
        for _, record in ipairs(reference.items or {}) do
            local entry = item(record.id, record.name)
            if entry then
                entry.data.reference = record
                entry.data.slot = entry.data.slot or record.slot
                entry.data.icon = entry.data.icon or record.icon
                for _, questID in ipairs(record.questIds or {}) do linkItemSource(entry, questIndex[questID], "Quest") end
                for _, npcID in ipairs(record.npcIds or {}) do linkItemSource(entry, npcIndex[npcID], "NPC") end
            end
        end
        -- Quest reward links are also built from the quest side, so sources
        -- need not repeat every relationship on both records.
        for _, record in ipairs(reference.quests or {}) do
            for _, itemID in ipairs(record.rewardIds or {}) do linkItemSource(self.byKey["item:" .. itemID], questIndex[record.id], "Quest") end
        end
    end
    -- Merge by ID and matching name, preserving curated records and marking
    -- baseline references rather than claiming every NPC is available here.
    local npcReference = ns.NpcReferenceData
    if type(npcReference) == "table" then
        for _, record in ipairs(npcReference.npcs or {}) do
            local entry = npcIndex[record.id]
            if not entry then
                local data = { id=record.id, npcID=record.id, npcReference=record,
                    reference={ provider=record.classicOnly and "WoW Forever Friends (Classic baseline)" or "EverlookDB (client and community references)", url=record.url } }
                entry = add("NPCs", "npc", record.id, record.name, data)
                npcIndex[record.id] = entry
                link(entry, tames[tostring(record.id)])
            end
            if entry then
                local data = entry.data
                if tostring(entry.name or ""):lower() == tostring(record.name or ""):lower() then
                    data.npcReference = record
                    for _, field in ipairs({"title", "level", "maxLevel", "type", "family", "zone", "displayID", "classification"}) do
                        if data[field] == nil or data[field] == "" or data[field] == 0 then data[field] = record[field] end
                    end
                    data.vendor = data.vendor or record.vendor
                    data.trainer = data.trainer or record.trainer
                    data.questGiver = data.questGiver or record.questGiver
                else
                    data.npcReferenceConflict = record.name
                end
            end
        end
        -- The curated quests were built before the wider NPC index existed.
        for _, record in ipairs(reference and reference.quests or {}) do
            for _, npcID in ipairs(record.npcIds or {}) do link(questIndex[record.id], npcIndex[npcID]) end
        end
    end
    local bulk = ns.BulkReferenceData
    if type(bulk) == "table" then
        for _, record in ipairs(bulk.quests or {}) do
            if not questIndex[record.id] then
                local data = { id = record.id, level = record.level, required = record.required, side = record.side, zone = record.zone,
                    starts = record.starts, turnin = record.turnin, classes = record.classes, repeatable = record.repeatable, classic = record.classic, reference = { provider = "Forever KB (community quest data)", verifiedAt = bulk.generatedAt } }
                questIndex[record.id] = add("Quests", "quest", "bulk:" .. record.id, record.name, data)
            else
                local data = questIndex[record.id].data
                data.zone, data.classes = data.zone or record.zone, data.classes or record.classes
                data.classic = record.classic
                if data.repeatable == nil then data.repeatable = record.repeatable end
            end
        end
        for _, record in ipairs(bulk.npcs or {}) do
            if not npcIndex[record.id] then
                npcIndex[record.id] = add("NPCs", "npc", record.id, record.name, { id = record.id, npcID = record.id, zone = record.zone, title = record.title, level = record.level, maxLevel = record.maxLevel, vendor = record.vendor, questGiver = record.questGiver,
                    reference = { provider = "Forever KB (community source data)", verifiedAt = bulk.generatedAt } })
                link(npcIndex[record.id], tames[tostring(record.id)])
            else
                local data = npcIndex[record.id].data
                data.npcID = data.npcID or record.id
                data.title, data.level, data.maxLevel = data.title or record.title, data.level or record.level, data.maxLevel or record.maxLevel
                data.vendor, data.questGiver = data.vendor or record.vendor, data.questGiver or record.questGiver
            end
        end
        local objectIndex = {}
        for _, record in ipairs(bulk.objects or {}) do
            objectIndex[record.id] = add("Items", "object", record.id, record.name, {
                id = record.id, zone = record.zone,
                reference = { provider = "Forever KB (community object data)", verifiedAt = bulk.generatedAt },
            })
        end
        for _, record in ipairs(bulk.items or {}) do
            local entry = item(record.id, record.name)
            if entry then
                local curated = entry.data.reference
                if not curated or record.provider == "Tracker observations + Forever KB" then
                    if curated then record.note = curated.note; record.url = curated.url end
                    entry.data.reference = record
                    if record.provider == "Tracker observations + Forever KB" then entry.name = record.name end
                elseif record.conflicts then curated.conflicts = record.conflicts end
                entry.data.slot = entry.data.slot or record.slot
                entry.data.icon = entry.data.icon or record.icon
                entry.data.quality = record.quality
                entry.data.itemClass, entry.data.itemSubclass = record.itemClass, record.subclass
                entry.data.sourceTypes, entry.data.observed = record.sourceTypes, record.observed
                entry.data.sourceSummary = record.sourceSummary
            end
        end
        for _, edge in ipairs(bulk.edges or {}) do
            local entry = self.byKey["item:" .. tostring(edge[1])]
            if edge[2] == "q" then linkItemSource(entry, questIndex[edge[3]], "Quest", nil, "Community reference; verify in Forever")
            elseif edge[2] == "n" then
                local npc = npcIndex[edge[3]]
                linkItemSource(entry, npc, edge[4] == "vendor" and "Vendor" or "Drop", edge[5], "Community reference; verify in Forever")
                if entry and npc then
                    local data = entry.data
                    data.bulkSourceCount = (data.bulkSourceCount or 0) + 1
                    data.bulkSources = data.bulkSources or {}
                    if #data.bulkSources < 8 then
                        local label = edge[4] == "vendor" and "Vendor" or "Drop"
                        local chance = type(edge[5]) == "number" and ("  •  " .. tostring(edge[5]) .. "% (community estimate)") or ""
                        data.bulkSources[#data.bulkSources + 1] = label .. ": " .. npc.name .. (npc.data.zone and npc.data.zone ~= "" and (" — " .. npc.data.zone) or "") .. chance
                    end
                end
            end
        end
        for _, edge in ipairs(bulk.objectEdges or {}) do
            linkItemSource(self.byKey["item:" .. tostring(edge[1])], objectIndex[edge[2]], "Object", edge[3], "Community reference; location and availability need verification in Forever")
        end
        for _, edge in ipairs(bulk.containerEdges or {}) do
            linkItemSource(self.byKey["item:" .. tostring(edge[1])], self.byKey["item:" .. tostring(edge[2])], "Container", nil, "Community reference; contents need verification in Forever")
        end
        for _, edge in ipairs(bulk.craftEdges or {}) do
            local recipe = self.byKey["recipe:" .. tostring(edge[3]) .. ":" .. tostring(edge[2])]
            if recipe and recipe.data.i == edge[1] then
                linkItemSource(self.byKey["item:" .. tostring(edge[1])], recipe, "Crafted", nil, "Community reference; verify recipe availability in Forever")
            end
        end
        -- Additional source relations are Classic references, not proof that
        -- an NPC currently drops or sells this item in Forever.
        for _, edge in ipairs(bulk.classicEdges or {}) do
            local entry, npc = self.byKey["item:" .. tostring(edge[1])], npcIndex[edge[3]]
            if entry and npc then
                local label = edge[4] == "vendor" and "Vendor" or "Drop"
                local note = "Classic reference: WoW Forever Friends / CMaNGOS; verify in Forever"
                linkItemSource(entry, npc, label, nil, note)
                local data = entry.data
                data.bulkSourceCount = (data.bulkSourceCount or 0) + 1
                data.bulkSources = data.bulkSources or {}
                if #data.bulkSources < 8 then data.bulkSources[#data.bulkSources + 1] = label .. ": " .. npc.name .. " (Classic reference)" end
            end
        end
        -- Wowhead Forever describes the level-60 legendary as an item
        -- combination, not as a direct drop or a blacksmithing recipe.
        local sulfuras = self.byKey["item:17182"]
        if sulfuras then
            sulfuras.data.sourceTypes, sulfuras.data.sourceLabel = "crafted", "Combined"
            sulfuras.data.sourceSummary = "Combine Eye of Sulfuras (Ragnaros, Molten Core) with a crafted Sulfuron Hammer."
            link(sulfuras, self.byKey["item:17204"]); link(sulfuras, self.byKey["item:17193"])
        end
    end
    -- Surface the currently installed dungeon reference records as well, retaining
    -- their existing pages and links. Only merge records by a real numeric ID.
    for i = 1, legacyCount do
        local original = self.entries[i]
        local data = original.data
        if original.kind == "quest" then
            local id = tonumber(data.id)
            local entry = id and questIndex[id]
            if not entry then
                entry = add("Quests", "quest", "legacy:" .. original.key, original.name, data, original.extra)
                if id then questIndex[id] = entry end
            end
            link(entry, original)
            for _, related in ipairs(original.links) do link(entry, related) end
        elseif original.kind == "boss" and tonumber(data.npcID) then
            local id = tonumber(data.npcID)
            local entry = npcIndex[id]
            if not entry then
                entry = add("NPCs", "npc", id, original.name, data, original.extra)
                npcIndex[id] = entry
            end
            if entry then
                link(entry, original)
                entry.data.npcID = entry.data.npcID or id
                entry.data.displayID = entry.data.displayID or data.displayID
                for _, related in ipairs(original.links) do link(entry, related) end
            end
        end
    end
    -- Fill missing classifications only, retaining their external provenance.
    local discoveries=ns.QuestDiscoveryData
    if type(discoveries)=="table" and type(discoveries.records)=="table" then
        for id,record in pairs(discoveries.records) do
            local entry=questIndex[id]
            if entry and type(record)=="table" and type(record.name)=="string" and entry.name:lower()==record.name:lower() then
                local d=entry.data;d.discovery=record
                if not d.zone or d.zone=="" then d.zone=record.zone or record.category end
                if (not tonumber(d.level) or tonumber(d.level)<=0) and record.level then d.level=record.level end
                if (not tonumber(d.required) or tonumber(d.required)<=0) and record.required then d.required=record.required end
                if (not d.side or d.side=="") and record.side then d.side=record.side end
                if (not d.starts or d.starts=="") and record.starts then d.starts=record.starts end
                if (not d.turnin or d.turnin=="") and record.turnin then d.turnin=record.turnin end
                if record.giverID then link(entry,npcIndex[record.giverID]) end
                if record.turninID then link(entry,npcIndex[record.turninID]) end
                if not d.location and type(record.location)=="table" and type(record.location.mapID)=="number" and type(record.location.x)=="number" and type(record.location.y)=="number" then
                    d.location={mapID=record.location.mapID,x=record.location.x,y=record.location.y,provider="Cross-checked quest references"}
                end
                -- Explicit coordinates already recorded for the giver, not the
                -- quest's objective zone or an arbitrary turn-in location.
                if not d.location and type(d.starts)=="string" then
                    local place,x,y=d.starts:match(",%s*(.-)%s*%(([%d%.]+),%s*([%d%.]+)%)%s*$")
                    local mapID=place and source.MAP_IDS and source.MAP_IDS[place];x,y=tonumber(x),tonumber(y)
                    if type(mapID)=="number" and x and y and x>=0 and x<=100 and y>=0 and y<=100 then d.location={mapID=mapID,x=x,y=y,provider="OneForAll quest reference"} end
                end
            end
        end
    end
    -- Resolve vendors only after all NPC sources have been merged. Use their
    -- recorded IDs, rather than guessing a profession's vendor by name.
    for _, relation in ipairs(favorVendorLinks) do
        local v, id = relation.vendor, tonumber(relation.vendor[1])
        local npc = npcIndex[id]
        if npc and npc.name:lower() ~= v[2]:lower() then npc = nil end
        if not npc and not npcIndex[id] then
            npc = add("NPCs", "npc", id, v[2], { id = id, npcID = id, zone = v[3], vendor = true,
                reference = { provider = "Profession recipe vendor reference" } })
            npcIndex[id] = npc
        end
        if npc then
            local d = npc.data
            d.vendor, d.zone = true, d.zone or v[3]
            if not d.location and type(v[4]) == "number" and type(v[5]) == "number" and type(v[6]) == "number"
                and v[5] >= 0 and v[5] <= 100 and v[6] >= 0 and v[6] <= 100 then
                d.location = { mapID = v[4], x = v[5], y = v[6], provider = "Profession recipe vendor reference" }
            end
            local side = v.fac == "H" and "Horde" or v.fac == "A" and "Alliance" or nil
            local note = relation.report or (relation.cost and (tostring(relation.cost) .. " Merchant's Favor") or "Favor cost not recorded")
            if relation.caution then note = note .. ". " .. relation.caution end
            local observedHere
            if ns.FavorVendorObservation then local _; _, observedHere = ns.FavorVendorObservation(tonumber(relation.recipe.data.ri), id) end
            linkItemSource(relation.plan, npc, "Vendor", nil, note, { favorCost = relation.cost, faction = side, uncertain = relation.caution ~= nil and not observedHere })
            link(relation.recipe, npc); link(relation.favor, npc)
        end
    end
    -- Extra Forever community stock complements the Classic vendor links;
    -- verify the NPC identity rather than attaching stock to a reused ID.
    for id, record in pairs(ns.VendorStockEvidence or {}) do
        local npc = npcIndex[id]
        if npc and type(record.name) == "string" and npc.name:lower() == record.name:lower() then
            for _, itemID in ipairs(record.items or {}) do
                linkItemSource(self.byKey["item:" .. tostring(itemID)], npc, "Vendor", nil,
                    "WoW Forever community vendor reference; verify current stock in game")
            end
        end
    end
    self:MergeAuctionItems()
    table.sort(self.entries, function(a, b)
        local an, bn = lowerName(a), lowerName(b)
        if an == bn then return a.key < b.key end
        return an < bn
    end)
    self.questByID = questIndex
    self.current = currentKey and self.byKey[currentKey] or nil
    self.boss = bossKey and self.byKey[bossKey] or nil
    local history = {}
    for _, state in ipairs(self.history) do
        local entry = state.entry and self.byKey[state.entry.key]
        if entry or not state.entry then state.entry = entry; history[#history + 1] = state end
    end
    self.history = history
end

-- Add auction IDs missing from the snapshot. No prices, character names
-- or realm details are copied; records stay in Forever Gold's database.
-- Run by RefreshData, and on its own after a scan (only the new IDs are added,
-- the ~40,000 reference entries are not built again). Returns how many it added.
function E:MergeAuctionItems()
    local gold, added = _G.ForeverGold, 0
    if type(gold) == "table" and type(gold.db) == "table" and type(gold.db.items) == "table" and type(gold.R) == "function" then
        local ok, realm = pcall(gold.R)
        local classes = { [0]="Consumable", [1]="Container", [2]="Weapon", [3]="Gem", [4]="Armor", [5]="Reagent", [7]="Trade Goods", [9]="Recipe", [12]="Quest", [13]="Key" }
        local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        if ok and type(realm) == "table" and type(realm.prices) == "table" then
            for id, rec in pairs(realm.prices) do
                local cached = gold.db.items[id]
                if type(id) == "number" and id > 0 and not self.byKey["item:" .. id] and type(rec) == "table" and type(cached) == "table" and type(cached.n) == "string" and cached.n ~= "" and auctionObservation(id) then
                    local entry = item(id, cached.n)
                    if entry then
                        added = added + 1
                        local d = entry.data
                        d.auctionObserved, d.sourceLabel = true, "Seen on auction house"
                        d.quality, d.itemClass = cached.q, classes[cached.c] or "Other"
                        d.reference = { provider = "Forever Gold auction observation", note = "Previously listed; current availability can change.", requiredLevel = cached.l }
                        if type(instant) == "function" then
                            local success, _, _, _, loc, icon = pcall(instant, id)
                            if success and type(loc) == "string" and not ns.Secret(loc) then
                                if loc == "" or loc == "INVTYPE_NON_EQUIP" then d.slot = "Non-equippable" elseif loc == "INVTYPE_BAG" or loc == "INVTYPE_QUIVER" then d.slot = "Bag" end
                            end
                            if success and icon and not ns.Secret(icon) then d.icon = icon end
                        end
                    end
                end
            end
        end
    end
    return added
end

local function entryOrder(a, b)
    local an, bn = lowerName(a), lowerName(b)
    if an == bn then return a.key < b.key end
    return an < bn
end
-- After a scan: add the newly seen auction items to the sorted list in place.
-- A few are slotted in by name; a big batch is cheaper sorted once.
function E:MergeNewAuctionItems()
    local entries = self.entries
    local before = #entries
    self.sourceIdx = nil -- positions move; rebuilt on next use
    local added = self:MergeAuctionItems()
    if added == 0 then return 0 end
    self.plannerCache, self.plannerShown = nil, nil
    if added > 64 then table.sort(entries, entryOrder); return added end
    local fresh = {}
    for i = #entries, before + 1, -1 do fresh[#fresh + 1] = entries[i]; entries[i] = nil end
    for _, e in ipairs(fresh) do
        local lo, hi = 1, #entries + 1
        while lo < hi do
            local mid = math.floor((lo + hi) / 2)
            if entryOrder(entries[mid], e) then lo = mid + 1 else hi = mid end
        end
        table.insert(entries, lo, e)
    end
    return added
end

function E:LoadGearIndex()
    if self.gearLoaded then return end
    if not self.gearEvents then
        local events = CreateFrame("Frame"); self.gearEvents = events
        for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_TALENT_UPDATE", "UNIT_STATS" }) do pcall(events.RegisterEvent, events, event) end
        events:SetScript("OnEvent", function(_, event, unit)
            if event == "UNIT_STATS" and unit ~= "player" then return end
            E.plannerCache = nil
            if not E.gearRefreshPending and E.window and E.window:IsShown() and E.selected == "Armory" and E.armorFilter == "planner" then
                E.gearRefreshPending = true
                local function refresh() E.gearRefreshPending = nil; if E.window and E.window:IsShown() and E.selected == "Armory" and E.armorFilter == "planner" then E:Render() end end
                if C_Timer and C_Timer.After then C_Timer.After(0.25, refresh) else refresh() end
            end
        end)
    end
    local source = engineSource()
    if not (source and type(source.GearIndex) == "function") then return end
    local ok, index = pcall(source.GearIndex)
    if not ok or type(index) ~= "table" then return end
    self.gearLoaded = true
    local before = #self.entries
    local slotNames = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Finger", [12] = "Finger", [13] = "Trinket", [14] = "Trinket", [15] = "Back", [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged" }
    for _, gear in ipairs(index) do
        if gear.id and gear.name then
            local entry = item(gear.id, gear.name)
            if entry then
                entry.data.gear = gear
                local slots = source.GEAR_LOC_SLOTS and source.GEAR_LOC_SLOTS[gear.loc]
                entry.data.slot = entry.data.slot or (slots and slotNames[slots[1]])
                entry.data.icon = entry.data.icon or gear.icon
            end
        end
    end
    -- gear only the index knows was added at the end: keep the list in name
    -- order, so the item pages never have to sort it again
    if #self.entries > before then table.sort(self.entries, entryOrder); self.sourceIdx = nil end
    -- slots and armour types just arrived: lists built before this are stale
    self.entryRevision = (self.entryRevision or 0) + 1
end

function E:LinkItemSources(entry)
    local gear, source = entry and entry.data and entry.data.gear, referenceSource()
    if not gear or not source then return end
    -- the same links as walking every entry, in the same order, from the index
    local idx, quest = sourceIndex(), nil
    if gear.qid then quest = idx.quest[gear.qid] end
    if gear.d then
        local found, seen = {}, {}
        local function take(list) for _, e in ipairs(list or {}) do if not seen[e] then seen[e] = true; found[#found + 1] = e end end end
        take(idx.dungeonData[gear.d])
        take(idx.dungeonKey[gear.d.key == nil and " nil" or gear.d.key])
        if gear.boss then take(idx.boss[tostring(gear.boss) .. "" .. tostring(gear.d.name)]) end
        table.sort(found, function(a, b) return (idx.pos[a] or 0) < (idx.pos[b] or 0) end)
        for _, e in ipairs(found) do linkItemSource(entry, e, e.kind == "boss" and "Boss" or "Dungeon") end
    end
    if gear.prof and gear.ps then linkItemSource(entry, self.byKey["recipe:" .. gear.prof .. ":" .. tostring(gear.ps)], "Crafted") end
    if gear.qid and not quest and type(source.QuestInfo) == "function" then
        local ok, info = pcall(source.QuestInfo, gear.qid)
        if ok and type(info) == "table" and info.name then quest = add("Armory", "quest", "reference:" .. tostring(gear.qid), info.name, { id = gear.qid, level = info.lvl, required = info.req, side = info.side, starts = info.giver, location = info.loc }) end
    end
    linkItemSource(entry, quest, "Quest")
end

-- What a search looks at, lowercased once per entry (and again only if the
-- name changes) instead of on every redraw.
local REAGENT_KINDS = { recipe = true, favor = true, camping = true }
local function searchText(e)
    if e.fuiFindName ~= e.name or not e.fuiFind then
        e.fuiFindName = e.name
        e.fuiFind = (e.name .. " " .. tostring(e.extra or "") .. " " .. tostring(e.data.zone or "")):lower()
        e.fuiFindR = nil
    end
    return e.fuiFind
end
local function reagentText(e)
    if not e.fuiFindR then
        local parts = { searchText(e) }
        for _, reagent in ipairs(e.data.r or {}) do parts[#parts + 1] = tostring(reagent[3] or ""):lower() end
        e.fuiFindR = table.concat(parts, " ")
    end
    return e.fuiFindR
end
-- Entries by category, in their original order.
local function categoryList(self, category)
    if category == "All" then return self.entries end
    local lists = self.byCategory
    if not lists or lists.entries ~= self.entries or lists.revision ~= self.entryRevision then
        lists = { entries = self.entries, revision = self.entryRevision }
        for _, e in ipairs(self.entries) do
            local list = lists[e.category]; if not list then list = {}; lists[e.category] = list end
            list[#list + 1] = e
        end
        self.byCategory = lists
    end
    return lists[category] or {}
end
function E:Find(category, query)
    query = tostring(query or ""):lower():match("^%s*(.-)%s*$")
    -- scrolling redraws the same search: answer it from the last results
    local cache = self.findCache
    if not cache or cache.entries ~= self.entries or cache.revision ~= self.entryRevision or cache.size > 48 then
        cache = { entries = self.entries, revision = self.entryRevision, size = 0, results = {} }
        self.findCache = cache
    end
    local key = tostring(category) .. "" .. query
    local found = cache.results[key]
    if not found then
        found = {}
        for _, e in ipairs(categoryList(self, category)) do
            if query == "" then found[#found + 1] = e
            else
                local text = REAGENT_KINDS[e.kind] and reagentText(e) or searchText(e)
                if text:find(query, 1, true) then found[#found + 1] = e end
            end
        end
        cache.results[key], cache.size = found, cache.size + 1
    end
    -- a copy: callers sort and filter what they get
    local result = {}
    for i = 1, #found do result[i] = found[i] end
    return result
end
-- One category's entries, in order, not copied: the same table until the
-- entries change, so callers can cache on it. Read only.
function E:CategoryEntries(category)
    return categoryList(self, category)
end

local function linesFor(e)
    if not e then return "Select an entry to see its details." end
    local d, out = e.data, {}
    local function line(label, value)
        if value ~= nil and value ~= "" then out[#out + 1] = label .. ": " .. tostring(value) end
    end
    if e.kind == "dungeon" then
        line("Level", d.level); line("Location", d.area); line("Territory", d.territory)
        if d.mapX and d.mapY then line("Entrance", string.format("%s %.1f, %.1f%s", d.mapZone or "", d.mapX, d.mapY, d.coordsUnverified and " (unverified)" or "")) end
        if d.description then out[#out + 1] = "\n" .. d.description end
        out[#out + 1] = "\nBosses and loot:"
        for _, b in ipairs(d.bosses or {}) do
            out[#out + 1] = tostring(b.name or "Unknown boss")
            for _, item in ipairs(b.loot or {}) do out[#out + 1] = "  • " .. tostring(item.name or "Unknown item") end
        end
        out[#out + 1] = "\nQuests:"
        for _, q in ipairs(d.quests or {}) do
            out[#out + 1] = tostring(q.name or "Unknown quest") .. (q.required and ("  •  requires " .. q.required) or "")
            if q.starts then out[#out + 1] = "  Starts: " .. q.starts end
            if q.turnin then out[#out + 1] = "  Turn in: " .. q.turnin end
            for _, reward in ipairs(q.rewards or {}) do out[#out + 1] = "  Reward: " .. tostring(reward.name or "Unknown") end
        end
    elseif e.kind == "boss" then
        line("Dungeon", e.extra)
        if d.description then out[#out + 1] = "\n" .. d.description end
        out[#out + 1] = "\nRecorded loot:"
        for _, loot in ipairs(d.loot or {}) do out[#out + 1] = "  " .. tostring(loot.name or "Unknown item") end
        if d.worldDropsOnly then out[#out + 1] = "Only world drops recorded." end
    elseif e.kind == "npc" then
        line("Title", d.title); line("Level", d.level); line("Classification", d.classification); line("Type", d.type); line("Faction", d.side); line("Zone", d.zone or e.extra)
        line("NPC ID", d.id or d.npcID)
        if d.npcReference then out[#out + 1] = d.npcReference.classicOnly and "Classic reference; availability in Forever is not confirmed." or "EverlookDB client/community reference; availability in Forever may need verification." end
        if d.npcReference and d.npcReference.nameConflict then line("Classic source name differs", d.npcReference.nameConflict) end
        if d.npcReferenceConflict then line("Other source name differs", d.npcReferenceConflict) end
        out[#out + 1] = "Related quests, drops and instances appear below when recorded."
    elseif e.kind == "object" then
        line("Object ID", d.id); line("Zone", d.zone)
        out[#out + 1] = "Community reference object. Location, contents and availability need verification in Forever."
    elseif e.kind == "quest" then
        line("Dungeon", e.extra); line("Quest level", d.level); line("Required level", d.required); line("Faction", d.side)
        line("Class", d.class); line("Starts", d.starts); line("Objective", d.objective); line("Turn in", d.turnin)
        line("Prerequisite", d.prereq); line("Rewards", type(d.rewardSummary) == "string" and d.rewardSummary or nil)
        for _, reward in ipairs(d.rewards or {}) do out[#out + 1] = "  Reward: " .. tostring(reward.name or "Unknown item") end
    elseif e.kind == "item" then
        local availability = itemAvailability(e)
        if availability then
            out[#out + 1] = availabilityText(availability, d.observed, auctionObservation(d.id))
        end
        local auctionText = auctionObservationText(d.id)
        if auctionText then out[#out + 1] = auctionText end
        local hasTooltip = false
        if C_TooltipInfo and C_TooltipInfo.GetItemByID then
            local ok, tip = pcall(C_TooltipInfo.GetItemByID, d.id)
            if ok and type(tip) == "table" and type(tip.lines) == "table" then
                for _, info in ipairs(tip.lines) do
                    local left, right = info.leftText, info.rightText
                    if type(left) == "string" and not ns.Secret(left) and left ~= "" then
                        local text = left
                        if type(right) == "string" and not ns.Secret(right) and right ~= "" then text = text .. "    " .. right end
                        out[#out + 1] = text; hasTooltip = true
                    end
                end
            end
        end
        if not hasTooltip then
            local ref = d.reference
            if ref then
                out[#out + 1] = (ref.provider or "Wowhead Forever") .. " reference snapshot:"
                line("Item level", ref.itemLevel); line("Binding", ref.binding); line("Slot", ref.slot)
                for _, stat in ipairs(ref.stats or {}) do out[#out + 1] = stat end
                if ref.effect then out[#out + 1] = ref.effect end
                for _, effect in ipairs(ref.effects or {}) do out[#out + 1] = effect end
            else out[#out + 1] = "Item tooltip data is still loading or unavailable." end
            requestItem(d.id)
        end
        local required = itemRequiredLevel(d.id)
        local refRequired = d.reference and d.reference.requiredLevel
        table.insert(out, 1, not armoryEquipment(e) and "Not equippable" or required and (required > 0 and ("Required level to wear: " .. required) or "No level requirement to wear") or refRequired and ("Required level to wear: " .. refRequired .. " (reference)") or "Required level to wear: not loaded")
        if d.gear and d.gear.src and d.gear.src ~= "" then table.insert(out, 2, "Source: " .. d.gear.src) end
        line("Item ID", d.id)
        if d.bulkSources and #d.bulkSources > 0 then
            out[#out + 1] = "Community source records (may differ in Forever):"
            for _, source in ipairs(d.bulkSources) do out[#out + 1] = source end
            if d.bulkSourceCount > #d.bulkSources then out[#out + 1] = "More sources are available under Related." end
        elseif d.sourceSummary and d.sourceSummary ~= "" then
            out[#out + 1] = "Recorded source: " .. d.sourceSummary
        end
        local gold = _G.ForeverGold
        if type(gold) == "table" and type(gold.AHPrice) == "function" and type(gold.IsBuyout) == "function" then
            local ok, price = pcall(gold.AHPrice, d.id); local checked, buyout = pcall(gold.IsBuyout, d.id)
            if ok and checked and buyout and type(price) == "number" and not ns.Secret(price) and price > 0 then line("Last recorded auction buyout", formatMoney(price)) end
        end
        if d.reference then
            line("Reference note", d.reference.note)
            if d.reference.estimated then out[#out + 1] = "Some stats are estimated from Classic data and may differ in Forever." end
            for _, conflict in ipairs(d.reference.conflicts or {}) do out[#out + 1] = "Source difference: " .. conflict end
        end
        out[#out + 1] = "Related quests, bosses, reputations, recipes and sets are listed below when recorded."
    elseif e.kind == "book" then
        line("Zone", d.zone); line("Location", d.subzone); line("Object", d.container)
        if d.x and d.y then line("Coordinates", string.format("%.1f, %.1f", d.x, d.y)) end
        line("Location confidence", d.status); line("Notes", d.note)
    elseif e.kind == "campObject" then
        line("Profession", e.extra); line("Skill", d.skill); line("Effect", d.effect); line("Materials", d.reagents)
    elseif e.kind == "family" then
        line("Role", d.role); line("Diet", table.concat(d.diet or {}, ", "))
        line("Abilities", table.concat(d.abilities or {}, ", "))
        if type(d.modifiers) == "table" then
            line("Health multiplier", d.modifiers.health); line("Armor multiplier", d.modifiers.armor); line("Damage multiplier", d.modifiers.damage)
        end
        if d.note then out[#out + 1] = "\n" .. d.note end
        out[#out + 1] = "\nKnown tame locations:"
        for _, t in ipairs(d.tames or {}) do out[#out + 1] = "  " .. tostring(t.name) .. "  " .. tostring(t.level or "?") .. "  —  " .. tostring(t.zone or "Unknown") end
        out[#out + 1] = "More tames and abilities are available under Related."
    elseif e.kind == "ability" then
        line("Source", d.source); line("Families", table.concat(d.families or {}, ", "))
        if d.effect then out[#out + 1] = "\n" .. d.effect end
        out[#out + 1] = "\nRanks:"
        for _, rank in ipairs(d.ranks or {}) do
            local status = ns.TrainerGuide and ns.TrainerGuide:PetRankStatus(e.name, rank.rank)
            out[#out + 1] = "  Rank " .. tostring(rank.rank) .. (rank.level and (" — level " .. rank.level) or "")
                .. (rank.tp and (", " .. rank.tp .. " training points") or "")
                .. (status and ("  •  " .. status) or "")
            if rank.desc then out[#out + 1] = "    " .. rank.desc end
        end
    elseif e.kind == "petRank" then
        line("Ability", e.extra); line("Rank", d.rank); line("Required pet level", d.level); line("Training points", d.tp)
        local status = ns.TrainerGuide and ns.TrainerGuide:PetRankStatus(e.extra, d.rank)
        if status then line("Your hunter", status) end
        if d.desc then out[#out + 1] = "\n" .. d.desc end
        out[#out + 1] = "\nBeasts that teach this rank:"
        if #(d.learnFrom or {}) == 0 then out[#out + 1] = "  None listed; check its source." end
        for _, beast in ipairs(d.learnFrom or {}) do
            out[#out + 1] = "  " .. tostring(beast.name) .. " — " .. tostring(beast.zone or "Unknown") .. " (" .. tostring(beast.level or "?") .. ")"
        end
    elseif e.kind == "tame" then
        line("Family", d.family); line("Level", d.level); line("Zone", d.zone)
        if d.x and d.y then line("Coordinates", string.format("%.1f, %.1f", d.x, d.y)) end
        if d.note then out[#out + 1] = "\n" .. d.note end
        if #(d.teachings or {}) > 0 then line("Can teach", table.concat(d.teachings, ", ")) end
    elseif e.kind == "rare" then
        line("Family", d.family); line("Level", d.level); line("Zone", d.zone)
        if d.x and d.y then line("Coordinates", string.format("%.1f, %.1f", d.x, d.y)) end
        if d.why then out[#out + 1] = "\n" .. d.why end
    elseif e.kind == "profession" then
        out[#out + 1] = "Choose Recipes, Camping or Favor above the list to browse " .. e.name .. "."
    elseif e.kind == "recipe" or e.kind == "camping" or e.kind == "favor" then
        line("Profession", e.extra); line("Required skill", d.req or "Unknown")
        if d.rn then line("Recipe", d.rn) end
        if d.fav or e.favorCost ~= nil or e.favorReport then
            out[#out + 1] = e.favorCost and ("Merchant's Favor: " .. tostring(e.favorCost)) or e.favorReport or "Merchant's Favor (cost not recorded)"
            if e.favorCaution then out[#out + 1] = e.favorCaution end
        end
        local gold = _G.ForeverGold
        if type(gold) == "table" and type(gold.RecipeKnownBy) == "function" then
            local ok, known = pcall(gold.RecipeKnownBy, e.extra, d.n)
            if ok and type(known) == "table" and #known > 0 then line("Known by", table.concat(known, ", "))
            else out[#out + 1] = "Known by: not recorded — open each character's profession to check" end
        else out[#out + 1] = "Known by: unavailable (Forever Gold not loaded)" end
        out[#out + 1] = "\nMaterials:"
        for _, r in ipairs(d.r or {}) do out[#out + 1] = "  " .. tostring(r[2] or 1) .. " × " .. tostring(r[3] or ("Item " .. tostring(r[1]))) end
        if type(d.src) == "table" then
            for _, drop in ipairs(d.src.d or {}) do out[#out + 1] = "\nDrop: " .. tostring(drop[2] or "Unknown") .. " — " .. tostring(drop[3] or "Unknown location") end
            for _, vendor in ipairs(d.src.v or {}) do out[#out + 1] = "\nVendor: " .. tostring(vendor[2] or "Unknown") .. " — " .. tostring(vendor[3] or "Unknown location") end
        end
    elseif e.kind == "faction" then
        out[#out + 1] = "Rewards:"
        for _, reward in ipairs(d.i or {}) do
            local standing = reward[6] and (_G["FACTION_STANDING_LABEL" .. tostring(reward[6])] or ("Standing " .. tostring(reward[6])))
            out[#out + 1] = "  " .. tostring(reward[2] or "Unknown") .. (standing and (" — " .. standing) or "")
        end
    elseif e.kind == "set" then
        line("Type", d.sub or d.g); line("Armor", d.arm); line("Level", d.lv)
        out[#out + 1] = "\nSet bonuses:"
        for _, bonus in ipairs(d.b or {}) do out[#out + 1] = "  " .. tostring(bonus[1]) .. " pieces: " .. tostring(bonus[2]) end
        out[#out + 1] = "\nPieces:"
        for _, item in ipairs(d.i or {}) do out[#out + 1] = "  " .. tostring(item[2]) end
    end
    local ref = d.reference
    out[#out + 1] = ref and ("\nSource: " .. tostring(ref.provider or "Wowhead Forever") .. " (snapshot " .. tostring(ref.verifiedAt) .. ")") or "\nSource: OneForAll reference data (GPL snapshot or installed addon)"
    return table.concat(out, "\n")
end
E.Details = linesFor

-- Reproduce every readable client tooltip line, including its colors. The
-- header is already shown by the detail pane, so omit the repeated item name.
local function itemTooltipText(entry)
    local d, out = entry.data, {}
    local ok, tip = false, nil
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then ok, tip = pcall(C_TooltipInfo.GetItemByID, d.id) end
    local function colored(text, color)
        if type(text) ~= "string" or ns.Secret(text) or text == "" then return "" end
        if type(color) == "table" and not ns.Secret(color) then
            local r, g, b = color.r, color.g, color.b
            if type(r) == "number" and type(g) == "number" and type(b) == "number" and not ns.Secret(r) and not ns.Secret(g) and not ns.Secret(b) then
                return string.format("|cff%02x%02x%02x", math.floor(math.max(0, math.min(1, r)) * 255 + 0.5), math.floor(math.max(0, math.min(1, g)) * 255 + 0.5), math.floor(math.max(0, math.min(1, b)) * 255 + 0.5)) .. text .. "|r"
            end
        end
        return text
    end
    if ok and type(tip) == "table" and type(tip.lines) == "table" then
        for index, line in ipairs(tip.lines) do
            local left, right = line.leftText, line.rightText
            if type(left) == "string" and not ns.Secret(left) and left ~= "" and not (index == 1 and left == entry.name) then
                local row = colored(left, line.leftColor)
                if type(right) == "string" and not ns.Secret(right) and right ~= "" then row = row .. "    " .. colored(right, line.rightColor) end
                out[#out + 1] = row
            end
        end
    end
    if #out == 0 then requestItem(d.id); return linesFor(entry) end
    local availability = itemAvailability(entry)
    if availability then out[#out + 1] = "\n" .. availabilityText(availability, d.observed, auctionObservation(d.id)) end
    local auctionText = auctionObservationText(d.id)
    if auctionText then out[#out + 1] = auctionText end
    -- Linked sources are listed as individually clickable rows below the
    -- tooltip; keep the text fallback for records that lack links.
    local source = not (d.sourceLinks and #d.sourceLinks > 0) and (d.sourceSummary or (d.gear and d.gear.src)) or nil
    if not source and not (d.sourceLinks and #d.sourceLinks > 0) and type(d.bulkSources) == "table" and #d.bulkSources > 0 then source = table.concat(d.bulkSources, "\n", 1, math.min(3, #d.bulkSources)) end
    if source and source ~= "" then out[#out + 1] = "\n|cffffd166Source:|r " .. source end
    return table.concat(out, "\n")
end
E.ItemTooltipText = itemTooltipText

-- Filters intentionally show only recorded or clearly identifiable data.
function E:DirectoryMatches(entry)
    local d = entry.data or {}
    local filter = self.directoryFilters and self.directoryFilters[self.selected] or {}
    local minimum, maximum = tonumber(filter.min), tonumber(filter.max)
    if minimum or maximum then
        local low, high = tonumber(d.level), tonumber(d.maxLevel) or tonumber(d.level)
        if not low or low <= 0 or (minimum and high < minimum) or (maximum and low > maximum) then return false end
    end
    local kind = filter.kind or "all"
    if self.selected == "Quests" and filter.side and filter.side ~= "all" then
        local side = tostring(d.side or ""):lower()
        if side ~= filter.side and side ~= "both" then return false end
    end
    if kind == "all" then return true end
    if self.selected == "Quests" then
        local classZones = { warrior=true, paladin=true, hunter=true, rogue=true, priest=true, shaman=true, mage=true, warlock=true, druid=true }
        local zone = tostring(d.zone or ""):lower()
        if kind == "class" then return (type(d.classes) == "string" and d.classes ~= "") or classZones[zone] or false end
        if kind == "class_self" then
            local _, class = UnitClass("player"); class = type(class) == "string" and not ns.Secret(class) and class:lower() or ""
            return class ~= "" and (zone == class or (type(d.classes) == "string" and d.classes:lower():find(class, 1, true) ~= nil))
        end
        if kind == "attunement" then return entry.name:lower():find("attunement", 1, true) ~= nil end
        if kind == "repeatable" then return d.repeatable == true end
        if kind == "dungeon" then for _, e in ipairs(entry.links or {}) do if e.kind == "dungeon" then return true end end end
    else
        local title = tostring(d.title or ""):lower()
        if kind == "vendor" then return d.vendor == true or title:find("merchant", 1, true) ~= nil or title:find("vendor", 1, true) ~= nil end
        if kind == "trainer" then return d.trainer == true or title:find("trainer", 1, true) ~= nil end
        if kind == "questgiver" then return d.questGiver == true end
        if kind == "boss" then for _, e in ipairs(entry.links or {}) do if e.kind == "boss" then return true end end end
    end
    return false
end

local function button(parent, label, width, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height); ns.Panel(b, { edge = 0.8 })
    b.text = ns.Text(b, 11, ns.C.text); b.text:SetPoint("CENTER"); b.text:SetText(label)
    local hover = b:CreateTexture(nil, "HIGHLIGHT"); hover:SetAllPoints(); hover:SetColorTexture(1, 0.85, 0.48, 0.12)
    return b
end

local function build()
    local f = CreateFrame("Frame", "ForeverUIEncyclopedia", UIParent)
    f:SetSize(1064, 600); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    ns.RememberWindow(f, "encyclopedia")
    ns.Panel(f, { alpha = 1.1, edge = 1 })
    local titleIcon = f:CreateTexture(nil, "ARTWORK"); titleIcon:SetSize(25, 25); titleIcon:SetPoint("TOPLEFT", 18, -10); titleIcon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\encyclopedia")
    local title = ns.Text(f, 18, ns.C.bright); title:SetPoint("LEFT", titleIcon, "RIGHT", 8, 0); title:SetText("Forever Encyclopedia")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetSize(28, 28); close:SetPoint("TOPRIGHT", -10, -8)
    for _, state in ipairs({ { "SetNormalAtlas", "RedButton-Exit" }, { "SetPushedAtlas", "RedButton-exit-pressed" }, { "SetDisabledAtlas", "RedButton-Exit-Disabled" }, { "SetHighlightAtlas", "RedButton-Highlight" } }) do
        if type(close[state[1]]) == "function" then pcall(close[state[1]], close, state[2]) end
    end
    close:SetScript("OnClick", function() f:Hide() end); f.closeButton = close
    local back = button(f, "Back", 64, 25); back:SetPoint("TOPLEFT", 18, -49)
    back:SetScript("OnClick", function() E:Back() end)
    local settings = button(f, "Settings & QoL", 136, 25); settings:SetPoint("LEFT", back, "RIGHT", 6, 0)
    settings.icon = settings:CreateTexture(nil, "ARTWORK"); settings.icon:SetSize(18, 18); settings.icon:SetPoint("LEFT", 6, 0); settings.icon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\meter-settings")
    settings.text:ClearAllPoints(); settings.text:SetPoint("LEFT", settings, "LEFT", 28, 0)
    settings:SetScript("OnClick", function() f:Hide(); if ns.OpenOptions then ns.OpenOptions() end end)
    f.settings = settings
    local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    search:SetSize(210, 24); search:SetPoint("TOPRIGHT", -58, -48); search:SetAutoFocus(false)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnTextChanged", function(self)
        E.query = self:GetText() or ""; E.offset, E.plannerOffset = 0, 0
        if E.selected == "Items" and C_Timer and C_Timer.After then
            local query = E.query
            C_Timer.After(0.2, function() if E.selected == "Items" and E.query == query then E:Render() end end)
        else E:Render() end
    end)
    f.search = search
    local globalSearch = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    globalSearch:SetSize(210, 24); globalSearch:SetPoint("TOPRIGHT", -58, -48); globalSearch:SetAutoFocus(false)
    globalSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus(); self:SetText("") end)
    f.globalSearch = globalSearch
    local globalHint = ns.Text(globalSearch, 10, ns.C.muted); globalHint:SetPoint("LEFT", globalSearch, "LEFT", 4, 0); globalHint:SetText("Search all tabs...")
    f.globalHint = globalHint
    local globalResults = CreateFrame("Frame", nil, f); globalResults:SetSize(390, 302); globalResults:SetPoint("TOPRIGHT", globalSearch, "BOTTOMRIGHT", 0, -3)
    globalResults:SetFrameStrata("TOOLTIP"); ns.Panel(globalResults, { alpha = 1, edge = 1 }); globalResults.rows = {}; globalResults.offset = 0
    globalResults.empty = ns.Text(globalResults, 11, ns.C.muted); globalResults.empty:SetPoint("TOPLEFT", 10, -12); globalResults.empty:SetText("No matching entries")
    for i = 1, 9 do
        local row = button(globalResults, "", 370, 34); row:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 36)
        row.text:ClearAllPoints(); row.text:SetPoint("LEFT", 36, 0); row.text:SetWidth(325); row.text:SetJustifyH("LEFT")
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(26, 26); row.icon:SetPoint("LEFT", 5, 0)
        row:SetScript("OnClick", function(self, mouse)
            if self.entry and not previewItem(self.entry, mouse) then local entry = self.entry; globalSearch:SetText(""); globalSearch:ClearFocus(); E:OpenEntry(entry) end
        end)
        globalResults.rows[i] = row
    end
    E.SmoothList("search", { pane = globalResults, rows = globalResults.rows, step = 36, top = 6, refresh = function() E:RenderGlobalSearch() end })
    f.globalResults = globalResults; globalResults:Hide()
    globalSearch:SetScript("OnTextChanged", function(self)
        E.globalQuery = self:GetText() or ""; globalResults.offset = 0; E:RenderGlobalSearch()
    end)
    local searchLabel = ns.Text(f, 10, ns.C.muted)
    searchLabel:SetPoint("RIGHT", search, "LEFT", -8, 0)
    searchLabel:SetText("Search this tab")
    f.searchLabel = searchLabel
    local searchHint = ns.Text(search, 10, ns.C.muted); searchHint:SetPoint("LEFT", search, "LEFT", 4, 0); searchHint:SetText("Search recipes or materials..."); searchHint:Hide(); f.profSearchHint = searchHint
    local source = ns.Text(f, 10, ns.C.muted); source:SetPoint("BOTTOMLEFT", 18, 12); source:SetWidth(1014); source:SetJustifyH("LEFT")
    f.source = source
    -- Always-visible, compact legend, with a separate line for source notes.
    local art = "Interface\\AddOns\\ForeverUI\\Art\\"
    local function icon(path) return "|T" .. path .. ":15:15|t " end
    local legends = {
        ["Armory"] = "+ Wishlist   + by slot: enhancements   " .. icon(art .. "encyclopedia-quest") .. "Quest reward   % Estimated upgrade",
        ["Dungeons"] = icon(art .. "encyclopedia-quest") .. "Quest   + Wishlist   % Drop chance   Map: location",
        ["Professions"] = "☆ Favorite   + Wishlist   Map: vendor location   Knowledge: last recorded scan",
        ["Reputations"] = "|cff59e666Friendly|r   |cff4da6ffHonored|r   |cffbf66ffRevered|r   |cffff9933Exalted|r   Map: vendor location",
        ["Pets"] = "Pet portrait: family or tame   Ability icon: family ability   Map: tame location",
        ["Library Books"] = "|cff59e666Turned in|r   |cffff5959Missing|r   In bags / bank: owned   Map: location",
        ["Quests"] = icon(art .. "encyclopedia-quest") .. "Quest   " .. icon("Interface\\TargetingFrame\\UI-PVP-Horde") .. "Horde   " .. icon("Interface\\TargetingFrame\\UI-PVP-Alliance") .. "Alliance   |cff5ee879Completed|r   |cffffd15aIn progress|r   |cffff6969Not completed|r   |cffaaaaaaUnavailable / unknown|r",
        ["NPCs"] = icon(art .. "npc-role-vendor") .. "Vendor   " .. icon(art .. "npc-role-trainer") .. "Trainer   " .. icon(art .. "npc-role-quest") .. "Quest giver   " .. icon(art .. "npc-type-humanoid") .. "Creature type",
        ["Items"] = "+ Wishlist   " .. icon(art .. "encyclopedia-quest") .. "Related quest   Name color: quality   Map: source location",
    }
    f.iconLegendText = ns.Text(f, 10, ns.C.muted)
    f.iconLegendText:SetPoint("BOTTOMLEFT", 18, 31); f.iconLegendText:SetWidth(1014); f.iconLegendText:SetJustifyH("LEFT")
    if f.iconLegendText.SetWordWrap then f.iconLegendText:SetWordWrap(false) end
    function f.UpdateIconLegend(category) f.iconLegendText:SetText(legends[category] or "") end
    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetPoint("TOPLEFT", 18, -122); sidebar:SetSize(150, 420)
    ns.Panel(sidebar, { edge = 0.35, alpha = 0.5 })
    f.sidebar = sidebar
    f.tabs = {}
    for i, name in ipairs(categories) do
        local tab = button(f, name, 110, 29); tab:SetPoint("TOPLEFT", f, "TOPLEFT", 18 + (i - 1) * 114, -83)
        tab.icon = tab:CreateTexture(nil, "ARTWORK"); tab.icon:SetSize(19, 19); tab.icon:SetPoint("LEFT", 5, 0)
        local icon = name == "Quests" and "encyclopedia-quest" or name == "NPCs" and "character-minimal" or name == "Items" and "bags-minimal" or ("encyclopedia-tab-" .. categoryIcons[name])
        tab.icon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\" .. icon)
        tab.text:ClearAllPoints(); tab.text:SetPoint("LEFT", tab, "LEFT", 28, 0); tab.text:SetWidth(78); tab.text:SetJustifyH("LEFT")
        tab:SetScript("OnClick", function()
            if f.wishMenu then f.wishMenu:Hide() end
            E.selected, E.offset, E.current, E.profFilter = name, 0, nil, "Professions"
            E.profName, E.petFamily, E.petFilter, E.armorType, E.armorSlot, E.setGroup, E.armorFilter, E.repSide, E.instanceFilter, E.levelGroup, E.raidSize = nil, nil, "family", nil, nil, nil, "set", nil, "dungeon", nil, nil
            if name == "Armory" then
                E.armorFilter, E.plannerSlot, E.plannerSlotID, E.plannerEnchant, E.plannerOffset = "planner", nil, nil, nil, 0
                E.plannerLastSlot, E.plannerLastSlotID = E.plannerLastSlot or "Head", E.plannerLastSlotID or 1
                if not E.setClassInitialized then local ok, _, class = pcall(UnitClass or function() end, "player"); if ok and type(class) == "string" and not ns.Secret(class) then E.setClass = class end; E.setClassInitialized = true end
            end
            E.query = ""
            if f.search:GetText() ~= "" then f.search:SetText("") end
            E:Render()
        end)
        f.tabs[name] = tab
    end
    f.profTabs = {}
    f.bookTabs = {}
    for i, spec in ipairs({ { "all", "All books" }, { "starter", "Set 1 • Level 20" }, { "l35", "Set 2 • Level 35" }, { "l45", "Set 3 • Level 45" }, { "l60", "Set 4 • Level 60" } }) do
        local b = button(f, spec[2], 150, 27); b:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -218 - (i - 1) * 31)
        b.baseLabel = spec[2]
        b:SetScript("OnClick", function() E.bookSet, E.current, E.offset, E.bookOffset = spec[1] ~= "all" and spec[1] or nil, nil, 0, 0; E:Render() end)
        f.bookTabs[spec[1]] = b
    end
    f.bookProgress = ns.Text(f, 10, ns.C.muted); f.bookProgress:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -133); f.bookProgress:SetWidth(142); f.bookProgress:SetJustifyH("LEFT")
    f.bookLegend = ns.Text(f, 10, ns.C.muted); f.bookLegend:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -384); f.bookLegend:SetWidth(140); f.bookLegend:SetJustifyH("LEFT"); f.bookLegend:SetText("Turned in\nManual\nIn bags\nIn bank\nQuest flagged\nMissing\n\nRight-click a book to mark it turned in.")
    f.bookHelp = button(f, "What can I do?", 150, 27); f.bookHelp:SetPoint("TOPLEFT", 18, -187)
    f.instanceTabs = {}
    for i, spec in ipairs({ { "dungeon", "Dungeons" }, { "raid", "Raids" } }) do
        local filter = button(f, spec[2], 150, 27); filter:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -122 - (i - 1) * 33)
        filter.icon = filter:CreateTexture(nil, "ARTWORK"); filter.icon:SetSize(20, 20); filter.icon:SetPoint("LEFT", 5, 0); filter.icon:SetTexture("Interface\\Icons\\" .. (spec[1] == "dungeon" and "INV_Misc_Bone_HumanSkull_01" or "INV_Misc_Head_Dragon_01"))
        filter.text:ClearAllPoints(); filter.text:SetPoint("LEFT", filter, "LEFT", 31, 0); filter.text:SetJustifyH("LEFT")
        filter:SetScript("OnClick", function() E.instanceFilter, E.levelGroup, E.raidSize, E.offset, E.current = spec[1], nil, nil, 0, nil; E:Render() end)
        f.instanceTabs[spec[1]] = filter
    end
    local instanceHeader = CreateFrame("Frame", nil, f)
    instanceHeader:SetPoint("TOPLEFT", 180, -122); instanceHeader:SetSize(864, 74)
    ns.Panel(instanceHeader, { edge = 0.5 })
    f.instanceHeader = instanceHeader
    instanceHeader.art = instanceHeader:CreateTexture(nil, "ARTWORK")
    instanceHeader.art:SetSize(100, 30); instanceHeader.art:SetPoint("TOPLEFT", 122, -4)
    instanceHeader.title = ns.Text(instanceHeader, 15, ns.C.bright)
    instanceHeader.title:SetPoint("TOPLEFT", 232, -5); instanceHeader.title:SetWidth(420); instanceHeader.title:SetJustifyH("LEFT")
    instanceHeader.meta = ns.Text(instanceHeader, 10, ns.C.muted)
    instanceHeader.meta:SetPoint("TOPLEFT", 232, -23); instanceHeader.meta:SetWidth(570); instanceHeader.meta:SetJustifyH("LEFT")
    f.bossBack = button(instanceHeader, "< Dungeons", 108, 25); f.bossBack:SetPoint("TOPLEFT", 6, -6)
    f.bossBack:SetScript("OnClick", function() E.current, E.boss, E.dungeonView, E.offset = nil, nil, "Overview", 0; E:Render() end)
    f.bossCount = ns.Text(instanceHeader, 10, ns.C.muted); f.bossCount:SetPoint("RIGHT", instanceHeader, "RIGHT", -12, 19)
    f.levelToggle = button(f, "Level brackets  −", 150, 27); f.levelToggle:SetPoint("TOPLEFT", 18, -200)
    f.levelToggle:SetScript("OnClick", function() E.levelExpanded = E.levelExpanded == false; E:Render() end)
    f.levelTabs = {}
    for i, spec in ipairs({ { 0, "Any lvl" }, { 10, "10–19" }, { 20, "20–29" }, { 30, "30–39" }, { 40, "40–49" }, { 50, "50+" } }) do
        local filter = button(f, spec[2], 150, 27)
        filter:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -233 - (i - 1) * 33)
        filter.baseLabel = spec[2]
        filter:SetScript("OnClick", function()
            E.levelGroup, E.offset, E.current = spec[1] ~= 0 and spec[1] or nil, 0, nil
            if E.levelGroup then E.collapsedLevels[E.instanceFilter .. ":" .. E.levelGroup] = nil end
            E:Render()
        end)
        f.levelTabs[spec[1]] = filter
    end
    f.raidSizeTabs = {}
    for i = 1, 9 do
        local filter = button(f, "", 150, 27)
        filter:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -233 - (i - 1) * 33)
        filter:SetScript("OnClick", function(self)
            E.raidSize, E.offset, E.current = self.sizeFilter ~= 0 and self.sizeFilter or nil, 0, nil
            if E.raidSize then E.collapsedLevels["raid:" .. tostring(E.raidSize)] = nil end
            E:Render()
        end)
        f.raidSizeTabs[i] = filter
    end
    local profBack = button(f, "< Professions", 150, 27); profBack:SetPoint("TOPLEFT", 18, -122)
    profBack:SetScript("OnClick", function() E.profName, E.current, E.offset, E.profFilter = nil, nil, 0, "Professions"; E:Render() end)
    f.profBack = profBack
    for i, spec in ipairs({ { "Professions", "Recipes" }, { "Camping", "Camping" }, { "Favor", "Favor" } }) do
        local filter = button(f, spec[2], 150, 27)
        filter:SetPoint("TOPLEFT", 18, -155 - (i - 1) * 33)
        filter:SetScript("OnClick", function() E.profFilter, E.offset, E.current = spec[1], 0, nil; E:Render() end)
        f.profTabs[spec[1]] = filter
    end
    f.profNav = {}
    local professionNav = { { "overview", "Overview" } }
    for _, name in ipairs(professionOrder) do professionNav[#professionNav + 1] = { name, name } end
    professionNav[#professionNav + 1] = { "Camping", "Camping Buffs" }
    professionNav[#professionNav + 1] = { "Favor", "Merchant's Favor" }
    for i, spec in ipairs(professionNav) do
        local b = button(f, spec[2], 150, 27); b:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -122 - (i - 1) * 30)
        local icon = professionIcons[spec[1]] or (spec[1] == "overview" and "inv_misc_book_09") or (spec[1] == "Camping" and "spell_fire_campfire") or (spec[1] == "Favor" and "inv_misc_coin_01")
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(19, 19); b.icon:SetPoint("LEFT", 5, 0); b.icon:SetTexture("Interface\\Icons\\" .. icon)
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", b, "LEFT", 30, 0); b.text:SetWidth(116); b.text:SetJustifyH("LEFT")
        b:SetScript("OnClick", function()
            E.profName = spec[1] ~= "overview" and spec[1] ~= "Camping" and spec[1] ~= "Favor" and spec[1] or nil
            E.profFilter = (spec[1] == "Camping" or spec[1] == "Favor") and spec[1] or "Professions"
            E.profView, E.profPlan, E.profProfit = "recipes", nil, nil
            E.recipeKnownFilter = "all"
            E.current, E.offset, E.query = nil, 0, ""
            if f.search:GetText() ~= "" then f.search:SetText("") end
            E:Render()
        end)
        f.profNav[spec[1]] = b
    end
    f.profViews = {}
    for i, spec in ipairs({ { "recipes", "All recipes" }, { "favorites", "Favorites" }, { "skill", "Skill-up" }, { "profit", "Profit" }, { "favor", "Merchant's Favor" } }) do
        local b = button(f, spec[2], 145, 27); b:SetPoint("TOPLEFT", f, "TOPLEFT", 180 + (i - 1) * 149, -122)
        b:SetScript("OnClick", function() E.profView, E.current, E.offset, E.profPlan, E.profProfit = spec[1], nil, 0, nil, nil; E:Render() end)
        f.profViews[spec[1]] = b
    end
    f.recipeKnownFilter = button(f, "All recipes", 99, 24); f.recipeKnownFilter:SetPoint("TOPLEFT", f, "TOPLEFT", 381, -157)
    f.recipeKnownFilter:SetScript("OnClick", function()
        local current = E.recipeKnownFilter or "all"
        E.recipeKnownFilter = current == "all" and "learned" or current == "learned" and "unlearned" or "all"
        E.offset, E.current = 0, nil; E:Render()
    end)
    f.recipeKnownFilter:SetScript("OnEnter", function(self)
        if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Recipe knowledge"); GameTooltip:AddLine("Click to cycle All, Learned and Not learned. Open your profession first; scans can be incomplete.", 1, 1, 1, true); GameTooltip:Show() end
    end)
    f.recipeKnownFilter:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.petTabs = {}
    for i, spec in ipairs({ { "family", "Families", "Ability_Hunter_BeastTaming" }, { "ability", "Abilities", "Ability_Hunter_BeastTraining" }, { "rare", "Rare Tames", "INV_Misc_Head_Tiger_01" } }) do
        local filter = button(f, spec[2], 150, 27); filter:SetPoint("TOPLEFT", 18, -122 - (i - 1) * 33)
        filter.icon = filter:CreateTexture(nil, "ARTWORK"); filter.icon:SetSize(20, 20); filter.icon:SetPoint("LEFT", 5, 0); filter.icon:SetTexture("Interface\\Icons\\" .. spec[3])
        filter.text:ClearAllPoints(); filter.text:SetPoint("LEFT", filter, "LEFT", 31, 0); filter.text:SetWidth(114); filter.text:SetJustifyH("LEFT")
        filter:SetScript("OnClick", function()
            E.petFilter, E.offset, E.current = spec[1], 0, nil
            E.petFamily = nil
            E:Render()
        end)
        f.petTabs[spec[1]] = filter
    end
    f.itemTabs = {}
    local itemGroups = { { "all", "All items", "INV_Misc_Bag_08" }, { "Weapon", "Weapons", "INV_Sword_04" },
        { "Armor", "Armor", "INV_Chest_Chain_05" }, { "Consumable", "Consumables", "INV_Potion_93" },
        { "Trade Goods", "Trade goods", "INV_Ingot_02" }, { "Recipe", "Recipes", "INV_Scroll_03" },
        { "Quest", "Quest items", "INV_Misc_Note_01" }, { "Container", "Containers", "INV_Box_01" },
        { "Key", "Keys", "INV_Misc_Key_01" }, { "other", "Other", "INV_Misc_QuestionMark" } }
    for i, spec in ipairs(itemGroups) do
        local b = button(f, spec[2], 150, 27); b:SetPoint("TOPLEFT", 18, -122 - (i - 1) * 30)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(20, 20); b.icon:SetPoint("LEFT", 5, 0); b.icon:SetTexture("Interface\\Icons\\" .. spec[3])
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 31, 0); b.text:SetWidth(114); b.text:SetJustifyH("LEFT")
        b:SetScript("OnClick", function() E.itemGroup, E.offset, E.current = spec[1], 0, nil; E:Render() end)
        f.itemTabs[spec[1]] = b
    end
    f.itemQuality = button(f, "Quality: All", 138, 24); f.itemQuality:SetPoint("TOPLEFT", 342, -122)
    local qualities = { "All", "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary" }
    f.itemQuality:SetScript("OnClick", function() E.itemQuality = ((E.itemQuality or -1) + 2) % #qualities - 1; E.offset, E.current = 0, nil; E:Render() end)
    f.itemQuality.labels = qualities
    f.itemSources = button(f, "Sources: All", 140, 24); f.itemSources:SetPoint("TOPLEFT", 492, -122)
    f.itemSources:SetScript("OnClick", function() E.itemKnownSources = not E.itemKnownSources; E.offset, E.current = 0, nil; E:Render() end)
    f.armorTabs = {}
    local armorNavIcons = { planner = "INV_Misc_Note_05", raid = "INV_Helmet_08", dungeon = "INV_Chest_Cloth_05", pvp = "INV_BannerPVP_02", crafted = "Trade_BlackSmithing", world = "INV_Misc_Map_01" }
    for i, spec in ipairs({ { "planner", "Gear Planner" }, { "raid", "Raid Sets" }, { "dungeon", "Dungeon Sets" }, { "pvp", "PvP Sets" }, { "crafted", "Crafted Sets" }, { "world", "World Sets" } }) do
        local filter = button(f, spec[2], 150, 27); filter:SetPoint("TOPLEFT", 18, -122 - (i - 1) * 30)
        filter.icon = filter:CreateTexture(nil, "ARTWORK"); filter.icon:SetSize(20, 20); filter.icon:SetPoint("LEFT", 5, 0); filter.icon:SetTexture("Interface\\Icons\\" .. armorNavIcons[spec[1]])
        filter.text:ClearAllPoints(); filter.text:SetPoint("LEFT", filter, "LEFT", 31, 0); filter.text:SetWidth(115); filter.text:SetJustifyH("LEFT")
        filter:SetScript("OnClick", function()
            local isGroup = spec[1] == "raid" or spec[1] == "dungeon" or spec[1] == "pvp" or spec[1] == "crafted" or spec[1] == "world"
            E.armorFilter, E.armorType, E.armorSlot, E.setGroup, E.offset, E.current = isGroup and "set" or spec[1], nil, nil, isGroup and spec[1] or nil, 0, nil
            if spec[1] == "planner" then
                E.plannerSlot, E.plannerSlotID, E.plannerEnchant, E.plannerOffset = nil, nil, nil, 0
                E.plannerLastSlot, E.plannerLastSlotID = E.plannerLastSlot or "Head", E.plannerLastSlotID or 1
            end
            E.setSub, E.setSubPage, E.setPieceOffset = nil, 1, 0
            E.query = ""; if f.search:GetText() ~= "" then f.search:SetText("") end
            E:Render()
        end)
        f.armorTabs[spec[1]] = filter
    end
    f.armorBack = button(f, "< Back", 150, 27); f.armorBack:SetPoint("TOPLEFT", 18, -398)
    f.armorBack:SetScript("OnClick", function()
        if E.armorSlot then E.armorSlot = nil elseif E.armorType then E.armorType = nil else E.setGroup = nil end
        E.current, E.offset = nil, 0; E:Render()
    end)
    f.armorPath = ns.Text(f, 10, ns.C.muted); f.armorPath:SetPoint("BOTTOMLEFT", f.armorBack, "TOPLEFT", 4, 4)
    f.armorPath:SetWidth(142); f.armorPath:SetJustifyH("LEFT")
    f.repBack = button(f, "< Factions", 150, 27); f.repBack:SetPoint("TOPLEFT", 18, -122)
    f.repBack:SetScript("OnClick", function() E.repSide, E.current, E.offset = nil, nil, 0; E:Render() end)
    f.repPath = ns.Text(f, 10, ns.C.muted); f.repPath:SetPoint("TOPLEFT", f.repBack, "BOTTOMLEFT", 4, -8)
    f.repPath:SetWidth(142); f.repPath:SetJustifyH("LEFT")
    local campingHeader = CreateFrame("Frame", nil, f); campingHeader:SetPoint("TOPLEFT", 180, -122); campingHeader:SetSize(864, 57); f.campingHeader = campingHeader
    local campingIcon = campingHeader:CreateTexture(nil, "ARTWORK"); campingIcon:SetSize(20, 20); campingIcon:SetPoint("TOPLEFT", 8, -3); campingIcon:SetTexture("Interface\\Icons\\Spell_Fire_CampFire")
    local campingTitle = ns.Text(campingHeader, 13, ns.C.bright); campingTitle:SetPoint("TOPLEFT", 35, -5); campingTitle:SetText("Camping Buffs & Profession Objects")
    local campingDescription = ns.Text(campingHeader, 10, ns.C.muted); campingDescription:SetPoint("TOPLEFT", 8, -25); campingDescription:SetWidth(840); campingDescription:SetJustifyH("LEFT"); campingDescription:SetText("Expand a profession to see its camping objects. Rest at a campfire to receive applicable buffs. Camping features share a 60-minute cooldown; beta values may change.")
    local directoryFilters = CreateFrame("Frame", nil, f); directoryFilters:SetPoint("TOPLEFT", 18, -122); directoryFilters:SetSize(1026, 32); f.directoryFilters = directoryFilters
    local label = ns.Text(directoryFilters, 10, ns.C.muted); label:SetPoint("LEFT", 4, 0); label:SetText("Level")
    local function levelBox(x, key)
        local box = CreateFrame("EditBox", nil, directoryFilters, "InputBoxTemplate"); box:SetSize(42, 23); box:SetPoint("LEFT", x, 0); box:SetAutoFocus(false)
        if box.SetNumeric then box:SetNumeric(true) end; if box.SetMaxLetters then box:SetMaxLetters(3) end
        box:SetScript("OnTextChanged", function(self)
            if directoryFilters.syncing then return end
            E.directoryFilters = E.directoryFilters or {}; local state = E.directoryFilters[E.selected]
            if state then state[key] = self:GetText(); E.offset, E.current = 0, nil; E:Render() end
        end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return box
    end
    directoryFilters.min = levelBox(42, "min"); directoryFilters.max = levelBox(101, "max")
    local dash = ns.Text(directoryFilters, 11, ns.C.muted); dash:SetPoint("LEFT", 88, 0); dash:SetText("–")
    directoryFilters.kind = button(directoryFilters, "", 225, 24); directoryFilters.kind:SetPoint("LEFT", 160, 0)
    directoryFilters.kind:SetScript("OnClick", function()
        local state = E.directoryFilters[E.selected]; local options = E.selected == "Quests" and E.questDirectoryOptions or E.npcDirectoryOptions
        local nextIndex = 1; for i, v in ipairs(options) do if v[1] == state.kind then nextIndex = i % #options + 1; break end end
        state.kind, E.offset, E.current = options[nextIndex][1], 0, nil; E:Render()
    end)
    directoryFilters.side = button(directoryFilters, "", 132, 24); directoryFilters.side:SetPoint("LEFT", directoryFilters.kind, "RIGHT", 6, 0)
    directoryFilters.side:SetScript("OnClick", function()
        local state = E.directoryFilters.Quests; local sides = { "all", "horde", "alliance" }
        for i, side in ipairs(sides) do if (state.side or "all") == side then state.side = sides[i % #sides + 1]; break end end
        E.offset, E.current = 0, nil; E:Render()
    end)
    local note = ns.Text(directoryFilters, 10, ns.C.muted); note:SetPoint("LEFT", directoryFilters.side, "RIGHT", 10, 0); note:SetText("Click to change filters • recorded data only")
    directoryFilters.clear = button(directoryFilters, "Clear", 65, 24); directoryFilters.clear:SetPoint("RIGHT", -3, 0)
    directoryFilters.clear:SetScript("OnClick", function() E.directoryFilters[E.selected] = { kind = "all" }; E.offset, E.current = 0, nil; E:Render() end)
    f.rows = {}
    local function scroll(_, delta) E.offset = E.offset - delta; E:Render() end
    local list = CreateFrame("Frame", nil, f); list:SetPoint("TOPLEFT", 180, -122); list:SetSize(300, 420)
    ns.Panel(list, { edge = 0.5 }); list:EnableMouseWheel(true); list:SetScript("OnMouseWheel", scroll)
    f.list = list
    for i = 1, 12 do
        local r = button(list, "", 288, 34); r:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 36)
        r.text:ClearAllPoints(); r.text:SetPoint("LEFT", 8, 0); r.text:SetWidth(268); r.text:SetJustifyH("LEFT")
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(70, 32); r.icon:SetPoint("LEFT", 1, 0); r.icon:Hide()
        r.portraitBorder = CreateFrame("Frame", nil, r); r.portraitBorder:SetAllPoints(r.icon); r.portraitBorder:EnableMouse(false)
        ns.Panel(r.portraitBorder, { noBg = true, edge = 0.7 }); r.portraitBorder:Hide()
        r.npcBadges = {}
        for index, spec in ipairs({ {"vendor", "npc-role-vendor"}, {"trainer", "npc-role-trainer"}, {"quest", "npc-role-quest"} }) do
            local badge = CreateFrame("Frame", nil, r); badge:SetSize(23, 23); badge:SetPoint("RIGHT", r, "RIGHT", -4 - (index - 1) * 25, 0); badge:EnableMouse(false)
            ns.Panel(badge, { edge = 0.65, alpha = 0.9 })
            badge.icon = badge:CreateTexture(nil, "OVERLAY"); badge.icon:SetPoint("TOPLEFT", 1, -1); badge.icon:SetPoint("BOTTOMRIGHT", -1, 1)
            badge.icon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\" .. spec[2]); badge:Hide(); r.npcBadges[spec[1]] = badge
        end
        r.sub = ns.Text(r, 9, ns.C.muted); r.sub:SetWidth(268); r.sub:SetJustifyH("LEFT")
        r.count = ns.Text(r, 10, ns.C.muted); r.count:SetPoint("RIGHT", r, "RIGHT", -10, 0); r.count:SetWidth(150); r.count:SetJustifyH("RIGHT")
        r.chevron = ns.Text(r, 12, ns.C.bright); r.chevron:SetPoint("LEFT", r, "LEFT", 8, 0)
        r.diet = ns.Text(r, 9, ns.C.muted); r.diet:SetPoint("RIGHT", r, "RIGHT", -8, 0); r.diet:SetWidth(128); r.diet:SetJustifyH("RIGHT"); r.diet:Hide()
        r.questStartMap = button(r, "Map", 38, 22); r.questStartMap:SetPoint("RIGHT", -3, 0)
        r.questStartMap:SetScript("OnClick", function() local loc = questStartLocation(r.entry); if loc then showLocation(loc.mapID, loc.x, loc.y) else ns.Print("No recorded NPC start location for this quest.") end end)
        r.questStartMap:Hide()
        if r.sub.SetWordWrap then r.sub:SetWordWrap(false) end
        if r.text.SetWordWrap then r.text:SetWordWrap(false) end
        r:EnableMouseWheel(true); r:SetScript("OnMouseWheel", scroll)
        r:SetScript("OnClick", function(_, mouse)
            if not r.entry then return end
            if previewItem(r.entry, mouse) then return end
            if r.entry.kind == "dungeonGroup" then
                local key = r.entry.data.groupKey
                E.collapsedLevels[key] = not E.collapsedLevels[key] or nil
                E:Render()
            elseif r.entry.kind == "campingGroup" then
                E.campingOpen = E.campingOpen or {}; local key = r.entry.data.profession
                E.campingOpen[key] = not E.campingOpen[key] or nil; E:Render()
            elseif E.selected == "Pets" and E.petFilter == "family" and r.entry.kind == "family" then
                E.current, E.petFamily = r.entry, r.entry.name; E:Render()
            elseif E.selected == "Reputations" and r.entry.kind == "faction" then
                E.current, E.repOffset, E.repVendorPage = r.entry, 0, 1; E:Render()
            elseif E.current and E.current.kind == "dungeon" and E.dungeonView == "Bosses" then
                E.boss, E.bossLootOffset = r.entry, 0; E:Render()
            else E:OpenEntry(r.entry) end
        end)
        r:SetScript("OnEnter", function(self)
            if self.entry and self.entry.kind == "npc" and GameTooltip then
                local roles = npcRoles(self.entry.data); local labels = {}
                if roles.vendor then labels[#labels + 1] = "Vendor" end
                if roles.trainer then labels[#labels + 1] = "Trainer" end
                if roles.quest then labels[#labels + 1] = "Quest giver" end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.entry.name)
                if #labels > 0 then GameTooltip:AddLine(table.concat(labels, "  •  "), 1, 0.82, 0, true) end
                GameTooltip:Show()
            elseif self.entry and self.entry.kind == "item" and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, self.entry.data.id) end
                GameTooltip:Show()
            elseif self.entry and self.entry.kind == "set" and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.entry.name)
                GameTooltip:AddLine(self.entry.data.sub or "Set", 1, 0.82, 0, true)
                GameTooltip:AddLine(self.entry.data.st == 0 and "Not available in Forever according to the reference data." or self.entry.data.st == 2 and "Source not confirmed." or "Select to see pieces and bonuses.", 1, 1, 1, true); GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        f.rows[i] = r
    end
    local detail = CreateFrame("Frame", nil, f); detail:SetPoint("TOPLEFT", 492, -122); detail:SetSize(552, 420)
    ns.Panel(detail, { edge = 0.5 })
    f.detail = detail
    local library = CreateFrame("Frame", nil, f); library:SetPoint("TOPLEFT", 180, -122); library:SetSize(864, 420); ns.Panel(library, { edge = 0.5 }); f.libraryPane = library
    library.heading = ns.Text(library, 10, ns.C.bright); library.heading:SetPoint("TOPLEFT", 10, -8); library.heading:SetText("STATUS                       BOOK TITLE                                              TERRITORY          ZONE / COORDINATES                 ACTIONS")
    local function bookScroll(_, delta) E.bookOffset = (E.bookOffset or 0) - delta; E:Render() end
    library:EnableMouseWheel(true); library:SetScript("OnMouseWheel", bookScroll); library.rows = {}
    for i = 1, 12 do
        local row = button(library, "", 848, 33); row:SetPoint("TOPLEFT", 8, -28 - (i - 1) * 35)
        row.text:ClearAllPoints(); row.text:SetPoint("LEFT", 8, 0); row.text:SetWidth(122); row.text:SetJustifyH("LEFT")
        row.name = ns.Text(row, 11, ns.C.text); row.name:SetPoint("LEFT", 135, 0); row.name:SetWidth(310); row.name:SetJustifyH("LEFT")
        row.territory = ns.Text(row, 10, ns.C.muted); row.territory:SetPoint("LEFT", 450, 0); row.territory:SetWidth(72); row.territory:SetJustifyH("LEFT")
        row.zone = ns.Text(row, 10, ns.C.muted); row.zone:SetPoint("LEFT", 530, 0); row.zone:SetWidth(238); row.zone:SetJustifyH("LEFT")
        if row.name.SetWordWrap then row.name:SetWordWrap(false); row.zone:SetWordWrap(false) end
        row.map = button(row, "Map", 52, 24); row.map:SetPoint("RIGHT", -5, 0)
        row.map:SetScript("OnClick", function(self)
            local book, source = self:GetParent().book, referenceSource()
            local mapID = book and source and source.MAP_IDS and source.MAP_IDS[book.zone]
            if book then showLocation(mapID, book.x, book.y) end
        end)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self, mouse)
            if self.group then E.bookFolded = E.bookFolded or {}; E.bookFolded[self.group] = not E.bookFolded[self.group] or nil; E:Render()
            elseif self.book and mouse == "RightButton" then
                ns.db.encyclopediaBooks = ns.db.encyclopediaBooks or {}; local key = wishKey(); ns.db.encyclopediaBooks[key] = ns.db.encyclopediaBooks[key] or {}
                local marks, id = ns.db.encyclopediaBooks[key], tostring(self.book.itemId or self.book.name); marks[id] = not marks[id] or nil; E:Render()
            end
        end)
        row:SetScript("OnEnter", function(self) if self.book and GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.book.name); GameTooltip:AddLine(bookStatus(self.book), 1, 1, 1); GameTooltip:AddLine("Right-click to toggle a manual turn-in mark.", 1, 0.82, 0, true); GameTooltip:Show() end end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        row:EnableMouseWheel(true); row:SetScript("OnMouseWheel", bookScroll); library.rows[i] = row
    end
    local help = CreateFrame("Frame", nil, f); help:SetSize(650, 500); help:SetPoint("CENTER", f, "CENTER", 0, 0); help:SetFrameStrata("DIALOG"); help:SetFrameLevel(f:GetFrameLevel() + 20); help:EnableMouse(true); ns.Panel(help, { alpha = 1.1, edge = 1 }); f.bookHelpPane = help
    local helpIcon = help:CreateTexture(nil, "ARTWORK"); helpIcon:SetSize(36, 36); helpIcon:SetPoint("TOPLEFT", 18, -14); helpIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    local helpTitle = ns.Text(help, 16, ns.C.bright); helpTitle:SetPoint("TOPLEFT", 64, -16); helpTitle:SetText("Library Books")
    local helpSub = ns.Text(help, 10, ns.C.muted); helpSub:SetPoint("TOPLEFT", 64, -37); helpSub:SetText("Turn-ins, rewards and librarian locations")
    local helpClose = button(help, "X", 26, 24); helpClose:SetPoint("TOPRIGHT", -10, -10); helpClose:SetScript("OnClick", function() help:Hide() end)
    local turnIn = ns.Text(help, 12, ns.C.bright); turnIn:SetPoint("TOPLEFT", 20, -66); turnIn:SetText("Turn in")
    local librarians = {
        { "Garion Wendell", "Alliance", "Stormwind City, Mage Quarter", 1453, 37.6, 80.8 },
        { "Owen Thadd", "Horde", "Undercity, Magic Quarter", 1458, 73.4, 33.0 },
    }
    for i, librarian in ipairs(librarians) do
        local row = button(help, "", 610, 36); row:SetPoint("TOPLEFT", 20, -84 - (i - 1) * 40)
        row.text:ClearAllPoints(); row.text:SetPoint("TOPLEFT", 8, -5); row.text:SetWidth(500); row.text:SetJustifyH("LEFT"); row.text:SetText(librarian[1] .. "  (" .. librarian[2] .. ")")
        local location = ns.Text(row, 10, ns.C.muted); location:SetPoint("BOTTOMLEFT", 8, 4); location:SetText(librarian[3] .. string.format("  %.1f, %.1f", librarian[5], librarian[6]))
        local map = button(row, "Map", 50, 24); map:SetPoint("RIGHT", -5, 0)
        map:SetScript("OnClick", function()
            showLocation(librarian[4], librarian[5], librarian[6])
        end)
    end
    local helpBody = ns.Text(help, 10, ns.C.muted); helpBody:SetPoint("TOPLEFT", 20, -169); helpBody:SetWidth(610); helpBody:SetJustifyH("LEFT"); helpBody:SetText("Turn in each different book. Each reward tier is a separate librarian quest; choose one item per tier. Mages can also unlock Research Access / Study.")
    help.tiers = {}
    for i = 1, 3 do
        local tier = {}; tier.heading = ns.Text(help, 11, ns.C.bright); tier.heading:SetPoint("TOPLEFT", 20, -215 - (i - 1) * 71); tier.heading:SetWidth(610); tier.heading:SetJustifyH("LEFT"); tier.items = {}
        for j = 1, 3 do
            local b = button(help, "", 198, 42); b:SetPoint("TOPLEFT", 20 + (j - 1) * 204, -234 - (i - 1) * 71)
            b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(30, 30); b.icon:SetPoint("LEFT", 5, 0)
            b.text:ClearAllPoints(); b.text:SetPoint("TOPLEFT", 40, -5); b.text:SetWidth(153); b.text:SetJustifyH("LEFT")
            b.sub = ns.Text(b, 9, ns.C.muted); b.sub:SetPoint("BOTTOMLEFT", 40, 5); b.sub:SetWidth(153); b.sub:SetJustifyH("LEFT"); if b.sub.SetWordWrap then b.sub:SetWordWrap(false); b.text:SetWordWrap(false) end
            b:SetScript("OnEnter", function(self) if self.item and GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, self.item[1]) else GameTooltip:SetText(self.item[2]); GameTooltip:AddLine(self.item[4] or "", 1, 1, 1, true) end; GameTooltip:Show() end end)
            b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            b:SetScript("OnClick", function(self) if self.item and IsModifiedClick and IsModifiedClick("DRESSUP") and DressUpItemLink then pcall(DressUpItemLink, "item:" .. self.item[1]) end end)
            tier.items[j] = b
        end
        help.tiers[i] = tier
    end
    local note = ns.Text(help, 10, ns.C.muted); note:SetPoint("TOPLEFT", 20, -433); note:SetWidth(610); note:SetJustifyH("LEFT"); note:SetText("The third tier's book count is not confirmed. Rewards may change. Ctrl-click an item to try it on.")
    local okay = button(help, "Okay", 120, 26); okay:SetPoint("BOTTOM", 0, 13); okay:SetScript("OnClick", function() help:Hide() end)
    help:Hide()
    f.bookHelp:SetScript("OnClick", function()
        local source = referenceSource(); local tiers = source and source.BOOK_REWARD_TIERS or {}
        for i, view in ipairs(help.tiers) do
            local tier = tiers[i]; view.heading:SetShown(tier ~= nil or i == 1)
            view.heading:SetText(tier and (tostring(tier.books or "Books") .. "  -  " .. tostring(tier.quest or "Reward") .. (tier.req and tier.req > 1 and (", requires level " .. tier.req) or "")) or "Reward details are unavailable in the reference data.")
            for j, b in ipairs(view.items) do local reward = tier and tier.items and tier.items[j]; b.item = reward; b:SetShown(reward ~= nil); if reward then b.icon:SetTexture(itemIcon(reward[1])); b.text:SetText(reward[2]); b.sub:SetText(reward[4] or "") end end
        end
        help:Show()
    end)
    local rep = CreateFrame("Frame", nil, detail); rep:SetAllPoints(); f.repPane = rep
    rep.title = ns.Text(rep, 15, ns.C.bright); rep.title:SetPoint("TOPLEFT", 12, -10)
    rep.standing = ns.Text(rep, 10, ns.C.text); rep.standing:SetPoint("TOPLEFT", 12, -34)
    rep.bar = CreateFrame("Frame", nil, rep); rep.bar:SetPoint("TOPLEFT", 12, -51); rep.bar:SetSize(320, 10); ns.Panel(rep.bar, { edge = 0.5 })
    rep.bar.fill = rep.bar:CreateTexture(nil, "ARTWORK"); rep.bar.fill:SetPoint("TOPLEFT", 1, -1); rep.bar.fill:SetHeight(8); rep.bar.fill:SetColorTexture(0.8, 0.58, 0.2, 1)
    rep.track = button(rep, "Track", 62, 22); rep.track:SetPoint("LEFT", rep.bar, "RIGHT", 8, 0)
    rep.track:SetScript("OnClick", function()
        local id = E.current and E.current.kind == "faction" and E.current.data.id
        if not id or not factionStanding(id) then ns.Print("This faction is not in your current reputation list. Expand its header or discover it first."); return end
        if C_Reputation and C_Reputation.SetWatchedFactionByID then
            local ok = pcall(C_Reputation.SetWatchedFactionByID, id)
            if ok then E:Render(); return end
        end
        ns.Print("Tracking this reputation is unavailable on this client.")
    end)
    rep.vendorsTitle = ns.Text(rep, 11, ns.C.bright); rep.vendorsTitle:SetPoint("TOPLEFT", 12, -68); rep.vendorsTitle:SetText("Vendors")
    rep.vendors = {}
    for i = 1, 3 do
        local row = button(rep, "", 525, 19); row:SetPoint("TOPLEFT", 12, -84 - (i - 1) * 20)
        row.text:ClearAllPoints(); row.text:SetPoint("LEFT", 5, 0); row.text:SetWidth(465); row.text:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(self)
            local v = self.vendor
            if v then showLocation(v[3], v[4], v[5]) end
        end); rep.vendors[i] = row
    end
    rep.nextVendor = button(rep, "More", 52, 19); rep.nextVendor:SetPoint("TOPRIGHT", -12, -65); rep.nextVendor:SetScript("OnClick", function() E.repVendorPage = (E.repVendorPage or 1) + 1; E:Render() end)
    rep.rewardTitle = ns.Text(rep, 11, ns.C.bright); rep.rewardTitle:SetPoint("TOPLEFT", 12, -149); rep.rewardTitle:SetText("Rewards")
    rep.filters = {}
    for i, label in ipairs({ "All", "Gear", "Recipes", "Other" }) do
        local b = button(rep, label, 82, 22); b:SetPoint("TOPRIGHT", -12 - (4 - i) * 86, -144)
        b:SetScript("OnClick", function() E.repFilter, E.repOffset = label, 0; E:Render() end); rep.filters[label] = b
    end
    local function repScroll(_, delta) E.repOffset = (E.repOffset or 0) - delta; E:Render() end
    rep:EnableMouseWheel(true); rep:SetScript("OnMouseWheel", repScroll); rep.rows = {}
    for i = 1, 8 do
        local row = button(rep, "", 526, 32); row:SetPoint("TOPLEFT", 12, -174 - (i - 1) * 34)
        row.categoryFill = row:CreateTexture(nil, "BACKGROUND"); row.categoryFill:SetAllPoints(); row.categoryFill:SetColorTexture(0.62, 0.42, 0.16, 0.18)
        row.categoryAccent = row:CreateTexture(nil, "ARTWORK"); row.categoryAccent:SetPoint("TOPLEFT", 0, -1); row.categoryAccent:SetPoint("BOTTOMLEFT", 0, 1); row.categoryAccent:SetWidth(3); row.categoryAccent:SetColorTexture(0.86, 0.65, 0.3, 1)
        row.text:ClearAllPoints(); row.text:SetPoint("LEFT", 8, 0); row.text:SetWidth(495); row.text:SetJustifyH("LEFT")
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(26, 26); row.icon:SetPoint("LEFT", 4, 0)
        row:EnableMouseWheel(true); row:SetScript("OnMouseWheel", repScroll)
        row:SetScript("OnClick", function(self)
            if self.group then E.repFolded = E.repFolded or {}; E.repFolded[self.group] = not E.repFolded[self.group] or nil; E:Render()
            elseif self.reward then local id, name = self.reward[1], self.reward[2]; local entry = E.byKey["item:" .. tostring(id)] or item(id, name); if entry then E:OpenEntry(entry) end end
        end)
        row:SetScript("OnEnter", function(self) if self.reward and GameTooltip and GameTooltip.SetItemByID then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); pcall(GameTooltip.SetItemByID, GameTooltip, self.reward[1]); GameTooltip:Show() end end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end); rep.rows[i] = row
    end
    f.detailTitle = ns.Text(detail, 15, ns.C.bright); f.detailTitle:SetPoint("TOPLEFT", 12, -12); f.detailTitle:SetWidth(526); f.detailTitle:SetJustifyH("LEFT")
    f.detailIcon = detail:CreateTexture(nil, "ARTWORK"); f.detailIcon:SetSize(24, 24); f.detailIcon:SetPoint("TOPLEFT", 12, -8)
    f.itemPreviewHeader = CreateFrame("Button", nil, detail); f.itemPreviewHeader:SetPoint("TOPLEFT", 8, -5); f.itemPreviewHeader:SetSize(470, 30)
    f.itemPreviewHeader:SetScript("OnClick", function(_, mouse) previewItem(E.current, mouse) end)
    f.itemWish = button(detail, "☆", 30, 25); f.itemWish:SetPoint("TOPRIGHT", -10, -5)
    f.questMap = button(detail, "Quest map", 90, 25); f.questMap:SetPoint("TOPRIGHT", -10, -5)
    f.questMap:SetScript("OnClick", function() local loc = questStartLocation(E.current); if loc then showLocation(loc.mapID, loc.x, loc.y) else ns.Print("No recorded NPC start location for this quest.") end end)
    f.itemWish:SetScript("OnClick", function() if E.current and E.current.kind == "item" then wishToggle(E.current); E:Render() end end)
    f.bookMark = button(detail, "Mark turned in", 145, 25); f.bookMark:SetPoint("BOTTOMLEFT", 12, 8)
    f.bookMark:SetScript("OnClick", function()
        if not E.current or E.current.kind ~= "book" then return end
        ns.db.encyclopediaBooks = ns.db.encyclopediaBooks or {}; local key = wishKey()
        ns.db.encyclopediaBooks[key] = ns.db.encyclopediaBooks[key] or {}
        local books, id = ns.db.encyclopediaBooks[key], tostring(E.current.data.itemId or E.current.name)
        books[id] = not books[id] or nil; E:Render()
    end)
    f.bookMap = button(detail, "Set waypoint", 120, 25); f.bookMap:SetPoint("LEFT", f.bookMark, "RIGHT", 6, 0)
    f.bookMap:SetScript("OnClick", function()
        local book = E.current and E.current.data; local source = referenceSource()
        local mapID = book and source and source.MAP_IDS and source.MAP_IDS[book.zone]
        if book then showLocation(mapID, book.x, book.y) end
    end)
    f.detailText = ns.Text(detail, 11, ns.C.text); f.detailText:SetPoint("TOPLEFT", 12, -42); f.detailText:SetWidth(526); f.detailText:SetHeight(190); f.detailText:SetJustifyH("LEFT"); f.detailText:SetJustifyV("TOP")
    -- the whole entry text sits in a clipped strip and scrolls by pixel
    f.detailClip = CreateFrame("Frame", nil, detail); f.detailClip:SetPoint("TOPLEFT", 12, -42); f.detailClip:SetSize(526, 190)
    if f.detailClip.SetClipsChildren then f.detailClip:SetClipsChildren(true) end
    f.detailText:SetParent(f.detailClip)
    f.dungeonTabs = {}
    for i, name in ipairs({ "Overview", "Bosses", "Loot", "Quests" }) do
        local tab = button(instanceHeader, name, 100, 24)
        tab:SetPoint("TOPLEFT", 6 + (i - 1) * 104, -44)
        tab:SetScript("OnClick", function()
            E.dungeonView, E.linkPage, E.detailPage, E.offset, E.bossLootOffset = name, 1, 1, 0, 0
            if name == "Bosses" then
                E.boss = nil
                for _, entry in ipairs(E.current and E.current.links or {}) do if entry.kind == "boss" then E.boss = entry; break end end
            end
            E:Render()
        end)
        f.dungeonTabs[name] = tab
    end
    local mapButton = button(instanceHeader, "Waypoint", 80, 24)
    mapButton:SetPoint("TOPRIGHT", -6, -44)
    mapButton:SetScript("OnClick", function()
        local d = E.current and E.current.data
        local source = referenceSource()
        local mapID = d and source and source.MAP_IDS and source.MAP_IDS[d.mapZone]
        local success = d and showLocation(mapID, d.mapX, d.mapY)
        if success then ns.Print("waypoint set for " .. E.current.name .. (d.coordsUnverified and " (coordinates unverified)." or ".")) end
    end)
    f.dungeonMap = mapButton
    local bossPane = CreateFrame("Frame", nil, detail)
    bossPane:SetPoint("TOPLEFT", 12, -12); bossPane:SetPoint("BOTTOMRIGHT", -12, 8)
    local portrait = bossPane:CreateTexture(nil, "ARTWORK"); portrait:SetSize(54, 54); portrait:SetPoint("TOPLEFT", 2, -2)
    bossPane.portrait = portrait
    bossPane.name = ns.Text(bossPane, 15, ns.C.bright); bossPane.name:SetPoint("TOPLEFT", 68, -5); bossPane.name:SetWidth(430); bossPane.name:SetJustifyH("LEFT")
    bossPane.meta = ns.Text(bossPane, 10, ns.C.muted); bossPane.meta:SetPoint("TOPLEFT", 68, -28); bossPane.meta:SetWidth(430); bossPane.meta:SetJustifyH("LEFT")
    bossPane.empty = ns.Text(bossPane, 11, ns.C.muted); bossPane.empty:SetPoint("TOPLEFT", 10, -76); bossPane.empty:SetWidth(480); bossPane.empty:SetJustifyH("LEFT")
    bossPane.rows = {}
    local function scrollLoot(_, delta) E.bossLootOffset = (E.bossLootOffset or 0) - delta; E:Render() end
    bossPane:EnableMouseWheel(true); bossPane:SetScript("OnMouseWheel", scrollLoot)
    for i = 1, 7 do
        local row = button(bossPane, "", 514, 38); row:SetPoint("TOPLEFT", 2, -71 - (i - 1) * 40)
        row.text:ClearAllPoints(); row.text:SetPoint("TOPLEFT", 42, -5); row.text:SetWidth(350); row.text:SetJustifyH("LEFT")
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(30, 30); row.icon:SetPoint("LEFT", 5, 0)
        row.sub = ns.Text(row, 9, ns.C.muted); row.sub:SetPoint("BOTTOMLEFT", 42, 5); row.sub:SetWidth(350); row.sub:SetJustifyH("LEFT")
        row.star = button(row, "☆", 25, 24); row.star:SetPoint("RIGHT", -4, 0)
        row.star:SetScript("OnClick", function(self) local loot = self:GetParent().loot; local entry = loot and E.byKey["item:" .. tostring(loot.id)]; if entry then wishToggle(entry); E:Render() end end)
        row.chance = ns.Text(row, 10, ns.C.text); row.chance:SetPoint("RIGHT", -34, 0); row.chance:SetJustifyH("RIGHT")
        row:EnableMouseWheel(true); row:SetScript("OnMouseWheel", scrollLoot)
        row:SetScript("OnClick", function(self, mouse) if self.loot then local entry = E.byKey["item:" .. tostring(self.loot.id)]; if entry and not previewItem(entry, mouse) then E:OpenEntry(entry) end end end)
        row:SetScript("OnEnter", function(self)
            if not self.loot or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.loot.id and GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, self.loot.id) end
            if self.dropChance then
                local origin = self.dropKills and "WoW Forever observations" or "Classic data; Forever may differ"
                GameTooltip:AddLine("Drop chance: " .. tostring(self.dropChance) .. "% (" .. origin .. ")", 1, 0.82, 0, true)
                if self.dropKills and self.dropKills > 0 then GameTooltip:AddLine(tostring(self.dropKills) .. " observed kills", 1, 1, 1) end
                if self.dropScaled then GameTooltip:AddLine("Source reports adjusted counts.", 1, 1, 1, true) end
            else GameTooltip:AddLine("Drop chance unknown", 0.7, 0.7, 0.7) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        bossPane.rows[i] = row
    end
    bossPane.counter = ns.Text(bossPane, 10, ns.C.muted); bossPane.counter:SetPoint("BOTTOMLEFT", 5, 3)
    bossPane:Hide(); f.bossPane = bossPane
    local petPane = CreateFrame("Frame", nil, detail); petPane:SetAllPoints(detail); f.petPane = petPane
    petPane.portrait = petPane:CreateTexture(nil, "ARTWORK"); petPane.portrait:SetSize(66, 66); petPane.portrait:SetPoint("TOPLEFT", 14, -12)
    petPane.name = ns.Text(petPane, 16, ns.C.bright); petPane.name:SetPoint("TOPLEFT", 94, -12); petPane.name:SetWidth(420); petPane.name:SetJustifyH("LEFT")
    petPane.summary = ns.Text(petPane, 11, ns.C.text); petPane.summary:SetPoint("TOPLEFT", 94, -37); petPane.summary:SetWidth(420); petPane.summary:SetHeight(54); petPane.summary:SetJustifyH("LEFT"); petPane.summary:SetJustifyV("TOP")
    local modifiers = CreateFrame("Frame", nil, petPane); modifiers:SetPoint("TOPLEFT", 12, -101); modifiers:SetSize(250, 113); ns.Panel(modifiers, { edge = 0.45 })
    petPane.modifiersTitle = ns.Text(modifiers, 12, ns.C.bright); petPane.modifiersTitle:SetPoint("TOPLEFT", 10, -8); petPane.modifiersTitle:SetText("Modifiers")
    petPane.modifiers = ns.Text(modifiers, 11, ns.C.text); petPane.modifiers:SetPoint("TOPLEFT", 10, -30); petPane.modifiers:SetWidth(228); petPane.modifiers:SetHeight(72); petPane.modifiers:SetJustifyH("LEFT"); petPane.modifiers:SetJustifyV("TOP")
    local abilities = CreateFrame("Frame", nil, petPane); abilities:SetPoint("TOPLEFT", 272, -101); abilities:SetSize(268, 113); ns.Panel(abilities, { edge = 0.45 })
    local abilitiesTitle = ns.Text(abilities, 12, ns.C.bright); abilitiesTitle:SetPoint("TOPLEFT", 10, -8); abilitiesTitle:SetText("Family abilities")
    petPane.abilities = {}
    for i = 1, 4 do
        local b = button(abilities, "", 248, 18); b:SetPoint("TOPLEFT", 10, -26 - (i - 1) * 20)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(16, 16); b.icon:SetPoint("LEFT", 2, 0)
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", b, "LEFT", 22, 0); b.text:SetWidth(220); b.text:SetJustifyH("LEFT")
        b:SetScript("OnClick", function(self)
            if self.more then E.petFilter, E.current, E.offset = "ability", nil, 0; E:Render()
            elseif self.entry then E:OpenEntry(self.entry) end
        end)
        petPane.abilities[i] = b
    end
    local locations = CreateFrame("Frame", nil, petPane); locations:SetPoint("TOPLEFT", 12, -225); locations:SetSize(528, 181); ns.Panel(locations, { edge = 0.45 })
    local locationsTitle = ns.Text(locations, 12, ns.C.bright); locationsTitle:SetPoint("TOPLEFT", 10, -8); locationsTitle:SetText("Where to tame")
    petPane.showAll = button(locations, "Show all", 94, 21); petPane.showAll:SetPoint("TOPRIGHT", -8, -5)
    petPane.showAll:SetScript("OnClick", function() E.petFilter, E.offset, E.current = "tame", 0, nil; E:Render() end)
    petPane.tames = {}
    for i = 1, 4 do
        local b = button(locations, "", 508, 29); b:SetPoint("TOPLEFT", 10, -30 - (i - 1) * 33)
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", b, "LEFT", 8, 0); b.text:SetWidth(300); b.text:SetJustifyH("LEFT")
        b.zone = ns.Text(b, 10, ns.C.muted); b.zone:SetPoint("RIGHT", b, "RIGHT", -48, 0); b.zone:SetWidth(150); b.zone:SetJustifyH("RIGHT")
        b.map = button(b, "Map", 37, 23); b.map:SetPoint("RIGHT", -3, 0)
        b.map:SetScript("OnClick", function(self)
            local tame = self:GetParent().entry; local data = tame and tame.data
            if data then showLocation(data.mapID, data.x, data.y) end
        end)
        b:SetScript("OnClick", function(self, mouse) if self.entry and not previewItem(self.entry, mouse) then E:OpenEntry(self.entry) end end)
        petPane.tames[i] = b
    end
    petPane:Hide()
    local profOverview = CreateFrame("Frame", nil, f); profOverview:SetPoint("TOPLEFT", 180, -122); profOverview:SetSize(864, 420); ns.Panel(profOverview, { edge = 0.5 }); f.profOverview = profOverview
    local function section(parent, label, x, y)
        local title = ns.Text(parent, 12, ns.C.bright); title:SetPoint("TOPLEFT", x, y); title:SetText(label); return title
    end
    section(profOverview, "Your professions", 12, -10)
    profOverview.your = {}
    for i = 1, 4 do
        local b = button(profOverview, "", 202, 40); b:SetPoint("TOPLEFT", 12 + (i - 1) * 212, -31)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(30, 30); b.icon:SetPoint("LEFT", 5, 0)
        b.text:ClearAllPoints(); b.text:SetPoint("TOPLEFT", 42, -5); b.text:SetWidth(154); b.text:SetJustifyH("LEFT")
        b.sub = ns.Text(b, 9, ns.C.muted); b.sub:SetPoint("BOTTOMLEFT", 42, 5); b.sub:SetWidth(154); b.sub:SetJustifyH("LEFT")
        b:SetScript("OnClick", function(self) if self.profession and E.byKey["profession:" .. self.profession] then E:OpenEntry(E.byKey["profession:" .. self.profession]) end end)
        profOverview.your[i] = b
    end
    profOverview.noProfessions = ns.Text(profOverview, 10, ns.C.muted); profOverview.noProfessions:SetPoint("TOPLEFT", 12, -45); profOverview.noProfessions:SetText("No professions recorded on this character.")
    section(profOverview, "All professions", 12, -82)
    profOverview.cards = {}
    for i, name in ipairs(professionOrder) do
        local b = button(profOverview, "", 202, 40); b:SetPoint("TOPLEFT", 12 + ((i - 1) % 4) * 212, -103 - math.floor((i - 1) / 4) * 46)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(30, 30); b.icon:SetPoint("LEFT", 5, 0); b.icon:SetTexture("Interface\\Icons\\" .. professionIcons[name])
        b.text:ClearAllPoints(); b.text:SetPoint("TOPLEFT", 42, -5); b.text:SetWidth(154); b.text:SetJustifyH("LEFT"); b.text:SetText(name)
        b.sub = ns.Text(b, 9, ns.C.muted); b.sub:SetPoint("BOTTOMLEFT", 42, 5); b.sub:SetWidth(154); b.sub:SetJustifyH("LEFT")
        b:SetScript("OnClick", function() local entry = E.byKey["profession:" .. name]; if entry then E:OpenEntry(entry) end end)
        profOverview.cards[name] = b
    end
    section(profOverview, "Other", 12, -202)
    for i, spec in ipairs({ { "Camping", "Camping Buffs" }, { "Favor", "Merchant's Favor" } }) do
        local b = button(profOverview, spec[2], 270, 34); b:SetPoint("TOPLEFT", 12 + (i - 1) * 280, -222)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(26, 26); b.icon:SetPoint("LEFT", 5, 0)
        b.icon:SetTexture("Interface\\Icons\\" .. (spec[1] == "Camping" and "spell_fire_campfire" or "inv_misc_coin_01"))
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", b, "LEFT", 38, 0); b.text:SetWidth(224); b.text:SetJustifyH("LEFT")
        b:SetScript("OnClick", function() E.profNavChoice = nil; E.profName, E.profFilter, E.current, E.offset = nil, spec[1], nil, 0; E:Render() end)
    end
    section(profOverview, "Trainers in your zone", 12, -270)
    profOverview.trainerText = ns.Text(profOverview, 10, ns.C.muted); profOverview.trainerText:SetPoint("TOPLEFT", 12, -291); profOverview.trainerText:SetWidth(830); profOverview.trainerText:SetHeight(100); profOverview.trainerText:SetJustifyH("LEFT"); profOverview.trainerText:SetJustifyV("TOP")
    profOverview.trainers = {}
    for i, name in ipairs({ "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring", "Cooking", "First Aid", "Fishing", "Herbalism", "Mining", "Skinning" }) do
        local b = button(profOverview, "", 274, 25); b:SetPoint("TOPLEFT", 12 + ((i - 1) % 3) * 280, -291 - math.floor((i - 1) / 3) * 28)
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", b, "LEFT", 5, 0); b.text:SetWidth(262); b.text:SetJustifyH("LEFT")
        b.profession = name
        b:SetScript("OnClick", function(self)
            local tr = self.trainer
            if tr then showLocation(tr[5], tr[6], tr[7]) end
        end)
        profOverview.trainers[i] = b
    end
    profOverview:Hide()
    local favorOverview = CreateFrame("Frame", nil, f); favorOverview:SetPoint("TOPLEFT", 180, -122); favorOverview:SetSize(864, 420); ns.Panel(favorOverview, { edge = 0.5 }); f.favorOverview = favorOverview
    section(favorOverview, "Favor recipes by profession", 12, -10)
    favorOverview.cards = {}
    for i, name in ipairs(professionOrder) do
        local b = button(favorOverview, "", 202, 40); b:SetPoint("TOPLEFT", 12 + ((i - 1) % 4) * 212, -32 - math.floor((i - 1) / 4) * 46)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(30, 30); b.icon:SetPoint("LEFT", 5, 0); b.icon:SetTexture("Interface\\Icons\\" .. professionIcons[name])
        b.text:ClearAllPoints(); b.text:SetPoint("TOPLEFT", 42, -5); b.text:SetWidth(154); b.text:SetJustifyH("LEFT"); b.text:SetText(name)
        b.sub = ns.Text(b, 9, ns.C.muted); b.sub:SetPoint("BOTTOMLEFT", 42, 5); b.sub:SetWidth(154); b.sub:SetJustifyH("LEFT")
        b:SetScript("OnClick", function() E.profName, E.profFilter, E.profView, E.current, E.offset = name, "Professions", "favor", nil, 0; E:Render() end)
        favorOverview.cards[name] = b
    end
    section(favorOverview, "How to get Merchant's Favor", 12, -132)
    local favorIntro = ns.Text(favorOverview, 9, ns.C.muted); favorIntro:SetPoint("TOPLEFT", 12, -150); favorIntro:SetWidth(830); favorIntro:SetJustifyH("LEFT"); favorIntro:SetText("Find a Waylaid Crate, fill one complete material bundle, then deliver the sealed crate to your faction's supply representative.")
    local guideBox = CreateFrame("Frame", nil, favorOverview); guideBox:SetPoint("TOPLEFT", 12, -174); guideBox:SetSize(405, 152); ns.Panel(guideBox, { edge = 0.5 })
    section(guideBox, "How it works", 8, -6)
    favorOverview.guide = ns.Text(guideBox, 9, ns.C.text); favorOverview.guide:SetPoint("TOPLEFT", 8, -23); favorOverview.guide:SetWidth(389); favorOverview.guide:SetHeight(123); favorOverview.guide:SetJustifyH("LEFT"); favorOverview.guide:SetJustifyV("TOP")
    local hubBox = CreateFrame("Frame", nil, favorOverview); hubBox:SetPoint("TOPLEFT", 12, -333); hubBox:SetSize(405, 71); ns.Panel(hubBox, { edge = 0.5 })
    favorOverview.hubTitle = ns.Text(hubBox, 11, ns.C.bright); favorOverview.hubTitle:SetPoint("TOPLEFT", 8, -6); favorOverview.hubTitle:SetWidth(330); favorOverview.hubTitle:SetJustifyH("LEFT")
    favorOverview.hubText = ns.Text(hubBox, 9, ns.C.text); favorOverview.hubText:SetPoint("TOPLEFT", 8, -25); favorOverview.hubText:SetWidth(325); favorOverview.hubText:SetJustifyH("LEFT")
    favorOverview.hubMap = button(hubBox, "Map", 55, 24); favorOverview.hubMap:SetPoint("RIGHT", -8, 0)
    favorOverview.hubMap:SetScript("OnClick", function(self) local hub = self.hub; local source = referenceSource(); local map = hub and source and source.MAP_IDS and source.MAP_IDS[hub.zone]; if hub then showLocation(map, hub.handinX or hub.x, hub.handinY or hub.y) end end)
    local rewardsBox = CreateFrame("Frame", nil, favorOverview); rewardsBox:SetPoint("TOPLEFT", 435, -174); rewardsBox:SetSize(405, 230); ns.Panel(rewardsBox, { edge = 0.5 })
    section(rewardsBox, "Crate rewards", 8, -6)
    local labels = ns.Text(rewardsBox, 9, ns.C.muted); labels:SetPoint("TOPLEFT", 8, -23); labels:SetText("Crate                                      Level       Reward")
    favorOverview.rewardRows = {}
    for i = 1, 7 do
        local row = CreateFrame("Frame", nil, rewardsBox); row:SetPoint("TOPLEFT", 5, -39 - (i - 1) * 26); row:SetSize(395, 25); ns.Panel(row, { edge = 0.25 })
        row.name = ns.Text(row, 9, ns.C.text); row.name:SetPoint("TOPLEFT", 5, -3); row.name:SetWidth(230); row.name:SetJustifyH("LEFT")
        row.note = ns.Text(row, 8, ns.C.muted); row.note:SetPoint("BOTTOMLEFT", 5, 2); row.note:SetWidth(230); row.note:SetJustifyH("LEFT"); if row.note.SetWordWrap then row.note:SetWordWrap(false) end
        row.level = ns.Text(row, 9, ns.C.text); row.level:SetPoint("LEFT", 248, 0); row.level:SetWidth(45); row.level:SetJustifyH("LEFT")
        row.reward = ns.Text(row, 9, ns.C.bright); row.reward:SetPoint("LEFT", 300, 0); row.reward:SetWidth(90); row.reward:SetJustifyH("LEFT")
        favorOverview.rewardRows[i] = row
    end
    favorOverview:Hide()
    local planner = CreateFrame("Frame", nil, f); planner:SetPoint("TOPLEFT", 180, -122); planner:SetSize(864, 420); f.planner = planner
    local modelPanel = CreateFrame("Frame", nil, planner); modelPanel:SetPoint("TOPLEFT", 0, 0); modelPanel:SetSize(370, 420); ns.Panel(modelPanel, { edge = 0.5 })
    local model = CreateFrame("DressUpModel", nil, modelPanel); model:SetPoint("TOPLEFT", 46, -30); model:SetPoint("BOTTOMRIGHT", -46, 45)
    if model.SetUnit then pcall(model.SetUnit, model, "player") end
    modelPanel:SetScript("OnShow", function() if model.SetUnit then pcall(model.SetUnit, model, "player") end end)
    planner.model = model
    planner.modelTitle = ns.Text(modelPanel, 12, ns.C.bright); planner.modelTitle:SetPoint("TOP", 0, -9)
    planner.reset = button(modelPanel, "Reset", 60, 23); planner.reset:SetPoint("BOTTOMRIGHT", -7, 8)
    planner.reset:SetScript("OnClick", function() if model.SetUnit then pcall(model.SetUnit, model, "player") end end)
    local slotData = { {1,"Head"}, {2,"Neck"}, {3,"Shoulder"}, {15,"Back"}, {5,"Chest"}, {4,"Shirt"}, {19,"Tabard"}, {9,"Wrist"}, {10,"Hands"}, {6,"Waist"}, {7,"Legs"}, {8,"Feet"}, {11,"Finger"}, {12,"Finger"}, {13,"Trinket"}, {14,"Trinket"}, {16,"Main Hand"}, {17,"Off Hand"}, {18,"Ranged"} }
    planner.slots = {}
    for i, spec in ipairs(slotData) do
        local b = button(modelPanel, "", 32, 32)
        if i <= 8 then b:SetPoint("TOPLEFT", 7, -37 - (i - 1) * 39)
        elseif i <= 16 then b:SetPoint("TOPRIGHT", -7, -37 - (i - 9) * 39)
        else b:SetPoint("BOTTOM", modelPanel, "BOTTOM", (i - 18) * 40, 7) end
        b.slotID, b.slotName = spec[1], spec[2]
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b:SetScript("OnClick", function(self) E.plannerSlot, E.plannerSlotID, E.plannerLastSlot, E.plannerLastSlotID, E.plannerEnchant, E.plannerOffset = self.slotName, self.slotID, self.slotName, self.slotID, nil, 0; E:Render() end)
        b:SetScript("OnEnter", function(self) if GameTooltip and GameTooltip.SetInventoryItem then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetInventoryItem("player", self.slotID); GameTooltip:Show() end end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        local enchant = button(modelPanel, "+", 17, 17); enchant.slotID, enchant.slotName = spec[1], spec[2]
        if i <= 8 then enchant:SetPoint("BOTTOMLEFT", b, "BOTTOMRIGHT", 2, 0)
        elseif i <= 16 then enchant:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT", -2, 0)
        else enchant:SetPoint("BOTTOM", b, "TOP", 0, 2) end
        if enchant.SetFrameLevel and model.GetFrameLevel then enchant:SetFrameLevel((model:GetFrameLevel() or 1) + 5) end
        enchant.icon = enchant:CreateTexture(nil, "ARTWORK"); enchant.icon:SetPoint("TOPLEFT", 2, -2); enchant.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        enchant:SetScript("OnClick", function(self)
            E.plannerSlot, E.plannerSlotID, E.plannerLastSlot, E.plannerLastSlotID, E.plannerEnchant, E.plannerOffset = self.slotName, self.slotID, self.slotName, self.slotID, self.slotID, 0
            E.plannerMode = "suggested"
            E.query = ""; if f.search:GetText() ~= "" then f.search:SetText("") end; E:Render()
        end)
        enchant:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local id = equippedEnchant(self.slotID); local source = referenceSource(); local info = id and source and source.ENCHANTS and source.ENCHANTS[id]
            GameTooltip:SetText(id and (info and info[1] or "Enchanted") or "Not enchanted")
            GameTooltip:AddLine("Click to browse compatible enchants and item enhancements.", 1, 1, 1, true); GameTooltip:Show()
        end)
        enchant:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        enchant:Hide(); b.enchant = enchant
        planner.slots[i] = b
    end
    local results = CreateFrame("Frame", nil, planner); results:SetPoint("TOPLEFT", 382, 0); results:SetSize(482, 420); ns.Panel(results, { edge = 0.5 }); planner.results = results
    planner.resultsTitle = ns.Text(results, 13, ns.C.bright); planner.resultsTitle:SetPoint("TOPLEFT", 10, -10)
    planner.resultsTitle:Hide()
    planner.suggested = button(results, "Suggested", 100, 23); planner.suggested:SetPoint("TOPLEFT", 10, -8)
    planner.wishlist = button(results, "Wishlist", 100, 23); planner.wishlist:SetPoint("LEFT", planner.suggested, "RIGHT", 6, 0)
    planner.suggested:SetScript("OnClick", function() E.plannerMode, E.plannerOffset, E.deleteGearSetPending = "suggested", 0, nil; E:Render() end)
    planner.wishlist:SetScript("OnClick", function() E.plannerMode, E.plannerOffset, E.deleteGearSetPending = "wishlist", 0, nil; E:Render() end)
    planner.setSelector = button(results, "Wishlist", 110, 23); planner.setSelector:SetPoint("TOPLEFT", 10, -37)
    planner.setSelector:SetScript("OnEnter", function(self) if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Click to switch gear sets"); GameTooltip:AddLine("Stars save items to the selected set.", 1, 1, 1, true); GameTooltip:Show() end end)
    planner.setSelector:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    planner.setSelector:SetScript("OnClick", function()
        local names, nextName = gearSetNames(), nil
        if not E.activeGearSet then nextName = names[1] else for i, name in ipairs(names) do if name == E.activeGearSet then nextName = names[i + 1]; break end end end
        E.activeGearSet, E.plannerOffset, E.deleteGearSetPending = nextName, 0, nil; E:Render()
    end)
    planner.setName = CreateFrame("EditBox", nil, results, "InputBoxTemplate"); planner.setName:SetSize(110, 23); planner.setName:SetPoint("LEFT", planner.setSelector, "RIGHT", 8, 0); planner.setName:SetAutoFocus(false)
    planner.setNameHint = ns.Text(planner.setName, 10, ns.C.muted); planner.setNameHint:SetPoint("LEFT", planner.setName, "LEFT", 4, 0); planner.setNameHint:SetText("Set name")
    planner.setName:SetScript("OnTextChanged", function(self) planner.setNameHint:SetShown((self:GetText() or "") == "") end)
    planner.setName:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    planner.createSet = button(results, "Create", 65, 23); planner.createSet:SetPoint("LEFT", planner.setName, "RIGHT", 5, 0)
    planner.createSet:SetScript("OnClick", function()
        local name = (planner.setName:GetText() or ""):match("^%s*(.-)%s*$")
        if name == "" then ns.Print("Enter a name for the gear set."); return end
        name = name:sub(1, 32); ns.db.encyclopediaGearSets = ns.db.encyclopediaGearSets or {}; local key = wishKey()
        ns.db.encyclopediaGearSets[key] = ns.db.encyclopediaGearSets[key] or {}
        if ns.db.encyclopediaGearSets[key][name] then ns.Print("That gear set already exists; select it using the set button."); return end
        ns.db.encyclopediaGearSets[key][name] = {}; E.activeGearSet, E.plannerOffset, E.deleteGearSetPending = name, 0, nil; planner.setName:SetText(""); planner.setName:ClearFocus(); E:Render()
    end)
    planner.renameSet = button(results, "Rename", 65, 23); planner.renameSet:SetPoint("LEFT", planner.createSet, "RIGHT", 5, 0)
    planner.renameSet:SetScript("OnClick", function()
        local old = E.activeGearSet; local sets = ns.db and ns.db.encyclopediaGearSets and ns.db.encyclopediaGearSets[wishKey()]
        if not old or not sets or not sets[old] then ns.Print("Select a named gear set to rename."); return end
        local name = (planner.setName:GetText() or ""):match("^%s*(.-)%s*$"):sub(1, 32)
        if name == "" then ns.Print("Enter a new name for the gear set."); return end
        if name ~= old and sets[name] then ns.Print("That gear set name is already in use."); return end
        if name ~= old then sets[name], sets[old] = sets[old], nil end
        E.activeGearSet, E.deleteGearSetPending = name, nil; planner.setName:SetText(""); planner.setName:ClearFocus(); E:Render()
    end)
    planner.deleteSet = button(results, "Delete", 60, 23); planner.deleteSet:SetPoint("LEFT", planner.renameSet, "RIGHT", 5, 0)
    planner.deleteSet:SetScript("OnClick", function()
        local name = E.activeGearSet; local sets = ns.db and ns.db.encyclopediaGearSets and ns.db.encyclopediaGearSets[wishKey()]
        if not name or not sets or not sets[name] then ns.Print("Select a named gear set to delete."); return end
        if E.deleteGearSetPending ~= name then E.deleteGearSetPending = name; E:Render(); return end
        sets[name] = nil; E.activeGearSet, E.plannerOffset, E.deleteGearSetPending = nil, 0, nil; E:Render()
    end)
    planner.filters = CreateFrame("Frame", nil, results); planner.filters:SetPoint("TOPLEFT", 10, -37); planner.filters:SetSize(450, 25)
    local levelLabel = ns.Text(planner.filters, 10, ns.C.bright); levelLabel:SetPoint("LEFT", 0, 0); levelLabel:SetText("Level")
    planner.minLevel = CreateFrame("EditBox", nil, planner.filters, "InputBoxTemplate"); planner.minLevel:SetSize(42, 23); planner.minLevel:SetPoint("LEFT", 41, 0); planner.minLevel:SetAutoFocus(false); planner.minLevel:SetNumeric(true)
    local dash = ns.Text(planner.filters, 10, ns.C.muted); dash:SetPoint("LEFT", 87, 0); dash:SetText("–")
    planner.maxLevel = CreateFrame("EditBox", nil, planner.filters, "InputBoxTemplate"); planner.maxLevel:SetSize(42, 23); planner.maxLevel:SetPoint("LEFT", 102, 0); planner.maxLevel:SetAutoFocus(false); planner.maxLevel:SetNumeric(true)
    local function applyLevels()
        local low, high = tonumber(planner.minLevel:GetText()), tonumber(planner.maxLevel:GetText())
        if low and high and low > high then ns.Print("Minimum level must not exceed maximum level."); return end
        E.gearMin, E.gearMax, E.gearLevelMode, E.plannerOffset = low, high, "custom", 0; E:Render()
    end
    for _, box in ipairs({ planner.minLevel, planner.maxLevel }) do box:SetScript("OnEnterPressed", function(self) applyLevels(); self:ClearFocus() end); box:SetScript("OnEditFocusLost", applyLevels); box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end) end
    planner.myLevel = button(planner.filters, "My level", 68, 23); planner.myLevel:SetPoint("LEFT", 151, 0)
    planner.myLevel:SetScript("OnClick", function() E.gearMin, E.gearMax, E.gearLevelMode, E.plannerOffset = 1, nil, "player", 0; E:Render() end)
    planner.allLevels = button(planner.filters, "All", 40, 23); planner.allLevels:SetPoint("LEFT", 225, 0)
    planner.allLevels:SetScript("OnClick", function() E.gearMin, E.gearMax, E.gearLevelMode, E.plannerOffset = 1, 60, "all", 0; E:Render() end)
    planner.filterButton = button(planner.filters, "Filters", 82, 23); planner.filterButton:SetPoint("LEFT", 271, 0)
    local filterMenu = CreateFrame("Frame", nil, results); filterMenu:SetPoint("TOPLEFT", planner.filters, "BOTTOMLEFT", 0, -3); filterMenu:SetSize(450, 205); filterMenu:SetFrameLevel(results:GetFrameLevel() + 15); ns.Panel(filterMenu, { alpha = 1.1, edge = 1 }); planner.filterMenu = filterMenu
    local choices = {
        { "All sources", "source", "all" }, { "Bind on Equip", "source", "boe" }, { "Quest rewards", "source", "quest" }, { "Dungeon drops", "source", "dungeon" }, { "Raid drops", "source", "raid" }, { "Crafted", "source", "crafted" },
        { "All equipment types", "type", "all" }, { "Cloth", "type", "cloth" }, { "Leather", "type", "leather" }, { "Mail", "type", "mail" }, { "Plate", "type", "plate" }, { "One-hand weapons", "type", "onehand" }, { "Two-hand weapons", "type", "twohand" }, { "Ranged weapons", "type", "ranged" }, { "Shields", "type", "shield" }, { "Profession bonuses", "type", "profession" },
    }
    planner.filterChoices = {}
    for i, choice in ipairs(choices) do
        local col, row = i <= 6 and 0 or 1, i <= 6 and i - 1 or i - 7
        local b = button(filterMenu, choice[1], 215, 19); b:SetPoint("TOPLEFT", 6 + col * 222, -5 - row * 20)
        b:SetScript("OnClick", function() if choice[2] == "source" then E.gearSource = choice[3] ~= "all" and choice[3] or nil else E.gearType = choice[3] ~= "all" and choice[3] or nil end; E.plannerOffset = 0; filterMenu:Hide(); E:Render() end)
        planner.filterChoices[choice[3] .. ":" .. choice[2]] = b
    end
    planner.filterButton:SetScript("OnClick", function() filterMenu:SetShown(not filterMenu:IsShown()) end); filterMenu:Hide()
    planner.resultsInfo = ns.Text(results, 10, ns.C.muted); planner.resultsInfo:SetPoint("TOPLEFT", 10, -38); planner.resultsInfo:SetWidth(458); planner.resultsInfo:SetJustifyH("LEFT")
    planner.allSlots = button(results, "All slots", 88, 23); planner.allSlots:SetPoint("LEFT", planner.wishlist, "RIGHT", 6, 0)
    planner.allSlots.check = planner.allSlots:CreateTexture(nil, "OVERLAY"); planner.allSlots.check:SetSize(16, 16); planner.allSlots.check:SetPoint("LEFT", 3, 0); planner.allSlots.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    planner.allSlots:SetScript("OnClick", function()
        if E.plannerSlot then
            E.plannerLastSlot, E.plannerLastSlotID = E.plannerSlot, E.plannerSlotID
            E.plannerSlot, E.plannerSlotID = nil, nil
        else E.plannerSlot, E.plannerSlotID = E.plannerLastSlot or "Head", E.plannerLastSlotID or 1 end
        E.plannerEnchant, E.plannerOffset = nil, 0; E:Render()
    end)
    planner.allSlots:SetScript("OnEnter", function(self) if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("All slots"); GameTooltip:AddLine("Shows up to three suggested upgrades per slot. Click again to return to the selected slot. Searches and profession bonus filters show all matches.", 1, 1, 1, true); GameTooltip:Show() end end)
    planner.allSlots:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    planner.rows = {}
    -- The rows live in a clipped strip, so a row half scrolled out is cut at
    -- the edge instead of drawing over the filters above.
    local listClip = CreateFrame("Frame", nil, results)
    listClip:SetPoint("TOPLEFT", 0, -91); listClip:SetPoint("TOPRIGHT", 0, -91); listClip:SetHeight(PLANNER_VIEW)
    if listClip.SetClipsChildren then listClip:SetClipsChildren(true) end
    planner.listClip = listClip
    -- A wheel notch glides one row (about a tenth of a second), instead of
    -- jumping a whole row at once.
    local glide = CreateFrame("Frame", nil, planner); glide:Hide(); planner.glide = glide
    glide:SetScript("OnUpdate", function(self, elapsed)
        local target, current = E.plannerTarget, E.plannerPixel or 0
        if not target then self:Hide(); return end
        local diff = target - current
        if math.abs(diff) < 0.5 then current, E.plannerTarget = target, nil; self:Hide()
        else current = current + diff * math.min(1, (tonumber(elapsed) or 0) * 18) end
        E.plannerPixel = current; E.plannerScrollTime = GetTime and GetTime() or E.plannerScrollTime
        E:Render()
    end)
    local function plannerScroll(_, delta)
        E.plannerTarget = math.max(0, (E.plannerTarget or E.plannerPixel or 0) - (tonumber(delta) or 0) * 49)
        E.plannerScrollTime = GetTime and GetTime() or nil
        glide:Show()
    end
    -- lands any glide at once (the tests; a click that needs the final rows)
    function E:FinishPlannerScroll()
        if self.plannerTarget then self.plannerPixel, self.plannerTarget = self.plannerTarget, nil end
        if self.window and self.window.planner and self.window.planner.glide then self.window.planner.glide:Hide() end
        self:Render()
    end
    results:EnableMouseWheel(true); results:SetScript("OnMouseWheel", plannerScroll)
    for i = 1, 8 do
        local b = button(listClip, "", 460, 40); b:SetPoint("TOPLEFT", 10, -65 - (i - 1) * 43)
        b.groupLabel = ns.Text(b, 10, ns.C.bright); b.groupLabel:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 2, 3); b.groupLabel:SetWidth(76); b.groupLabel:SetJustifyH("LEFT")
        b.groupLine = b:CreateTexture(nil, "ARTWORK"); b.groupLine:SetPoint("LEFT", b.groupLabel, "RIGHT", 4, 0); b.groupLine:SetSize(362, 1)
        b.groupLine:SetColorTexture(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], 0.45)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(30, 30); b.icon:SetPoint("LEFT", 5, 0)
        b.text:ClearAllPoints(); b.text:SetPoint("TOPLEFT", 42, -5); b.text:SetWidth(310); b.text:SetJustifyH("LEFT")
        b.questMark = b:CreateTexture(nil, "ARTWORK"); b.questMark:SetSize(14, 14); b.questMark:SetTexture(questIcon)
        b.sub = ns.Text(b, 9, ns.C.muted); b.sub:SetPoint("BOTTOMLEFT", 42, 5); b.sub:SetWidth(310); b.sub:SetJustifyH("LEFT")
        b.enchantInfo = ns.Text(b, 9, ns.C.muted); b.enchantInfo:SetPoint("BOTTOMLEFT", 42, 4); b.enchantInfo:SetWidth(350); b.enchantInfo:SetJustifyH("LEFT")
        if b.enchantInfo.SetWordWrap then b.enchantInfo:SetWordWrap(false) end
        if b.sub.SetWordWrap then b.sub:SetWordWrap(false) end
        b.star = button(b, "", 25, 24); b.star:SetPoint("RIGHT", -4, 0)
        b.star.icon = b.star:CreateTexture(nil, "ARTWORK"); b.star.icon:SetSize(18, 18); b.star.icon:SetPoint("CENTER")
        b.star:SetScript("OnClick", function(self) local row = self:GetParent(); if row.enchant then toggleEnchantWish(row.enchant) elseif row.entry then wishToggle(row.entry) end; E:Render() end)
        b.star:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.saved and "Remove from wishlist" or "Add to wishlist")
            GameTooltip:Show()
        end)
        b.star:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        b.preview = button(b, "Try on", 54, 24); b.preview:SetPoint("RIGHT", b.star, "LEFT", -3, 0)
        b.preview:SetScript("OnClick", function(self) local entry = self:GetParent().entry; if entry and model.TryOn then pcall(model.TryOn, model, entry.data.id) end end)
        b:EnableMouseWheel(true); b:SetScript("OnMouseWheel", plannerScroll)
        b:SetScript("OnClick", function(self, mouse)
            if previewItem(self.entry, mouse) then return end
            if self.enchant then
                local option = self.enchant
                local recipe = option.p and option.s and E.byKey["recipe:" .. option.p .. ":" .. option.s]
                local entry = recipe or option.i and E.byKey["item:" .. option.i]
                if entry then E:OpenEntry(entry) end
            elseif self.entry then E:OpenEntry(self.entry) end
        end)
        b:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.enchant then
                local o = self.enchant; GameTooltip:SetText(o.n or "Enhancement")
                local source = referenceSource(); local data = source and source.ENCHANTS and source.ENCHANTS[o.e]
                if data and data[1] then GameTooltip:AddLine(data[1], 1, 1, 1, true) end
                if o.p then GameTooltip:AddLine(o.p .. (o.req and (" " .. o.req) or ""), 1, 0.82, 0) end
                local details = enchantDetails(o)
                if #details.characters > 0 then GameTooltip:AddLine("Known by: " .. table.concat(details.characters, ", "), 0.5, 1, 0.5, true)
                else GameTooltip:AddLine(details.goldAvailable and "Known by: no character recorded; open each profession to update" or "Known by: character recipe data unavailable", 0.75, 0.75, 0.75, true) end
                for _, location in ipairs(details.sources) do GameTooltip:AddLine(location, 1, 1, 1, true) end
                if o.st == 0 then GameTooltip:AddLine("Not available in Forever according to the reference data.", 1, 0.4, 0.3, true) end
            elseif self.entry and GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, self.entry.data.id) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        planner.rows[i] = b
    end
    planner:Hide()
    local setControls = CreateFrame("Frame", nil, f); setControls:SetPoint("TOPLEFT", 180, -122); setControls:SetSize(864, 90); f.setControls = setControls
    setControls.classes = {}
    local classSpecs = { { "ALL", "All classes" }, { "WARRIOR", "War" }, { "PALADIN", "Pal" }, { "HUNTER", "Hun" }, { "ROGUE", "Rog" }, { "PRIEST", "Pri" }, { "SHAMAN", "Sha" }, { "MAGE", "Mag" }, { "WARLOCK", "Wlk" }, { "DRUID", "Dru" } }
    for i, spec in ipairs(classSpecs) do
        local b = button(setControls, spec[2], i == 1 and 82 or 43, 26)
        b:SetPoint("TOPLEFT", i == 1 and 0 or 88 + (i - 2) * 46, 0)
        local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[spec[1]]
        if coords then
            b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(22, 22); b.icon:SetPoint("CENTER")
            b.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"); b.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4]); b.text:SetText("")
        end
        b:SetScript("OnEnter", function(self) if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(spec[1] == "ALL" and "All classes" or spec[1]); GameTooltip:Show() end end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        b:SetScript("OnClick", function() E.setClass, E.current, E.offset = spec[1] ~= "ALL" and spec[1] or nil, nil, 0; E:Render() end)
        setControls.classes[spec[1]] = b
    end
    setControls.available = button(setControls, "Hide unavailable", 135, 26); setControls.available:SetPoint("TOPRIGHT", 0, 0)
    setControls.available:SetScript("OnClick", function() E.hideUnavailable, E.current, E.offset = not E.hideUnavailable, nil, 0; E:Render() end)
    setControls.subs = {}
    for i = 1, 10 do
        local b = button(setControls, "", 166, 25); b:SetPoint("TOPLEFT", ((i - 1) % 5) * 170, -32 - math.floor((i - 1) / 5) * 28)
        b:SetScript("OnClick", function(self) E.setSub, E.current, E.offset = self.sub, nil, 0; E:Render() end)
        setControls.subs[i] = b
    end
    setControls.next = button(setControls, ">", 36, 25); setControls.next:SetPoint("TOPRIGHT", 0, -32)
    setControls.next:SetScript("OnClick", function() E.setSubPage = (E.setSubPage or 1) + 1; E:Render() end); setControls.next:Hide()
    setControls:Hide()
    local setPane = CreateFrame("Frame", nil, detail); setPane:SetAllPoints(detail); f.setPane = setPane
    setPane.title = ns.Text(setPane, 14, ns.C.bright); setPane.title:SetPoint("TOPLEFT", 12, -9); setPane.title:SetWidth(520); setPane.title:SetJustifyH("LEFT")
    setPane.meta = ns.Text(setPane, 10, ns.C.muted); setPane.meta:SetPoint("TOPLEFT", 12, -30); setPane.meta:SetWidth(520); setPane.meta:SetJustifyH("LEFT")
    setPane.status = ns.Text(setPane, 10, ns.C.text); setPane.status:SetPoint("TOPLEFT", 12, -47); setPane.status:SetWidth(520); setPane.status:SetJustifyH("LEFT")
    setPane.owned = ns.Text(setPane, 10, ns.C.text); setPane.owned:SetPoint("TOPLEFT", 12, -64); setPane.owned:SetWidth(520); setPane.owned:SetJustifyH("LEFT")
    setPane.pieces = {}
    local function setScroll(_, delta) E.setPieceOffset = (E.setPieceOffset or 0) - delta; E:Render() end
    setPane:EnableMouseWheel(true); setPane:SetScript("OnMouseWheel", setScroll)
    for i = 1, 6 do
        local b = button(setPane, "", 520, 30); b:SetPoint("TOPLEFT", 12, -85 - (i - 1) * 32)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(24, 24); b.icon:SetPoint("LEFT", 4, 0)
        b.text:ClearAllPoints(); b.text:SetPoint("TOPLEFT", 34, -3); b.text:SetWidth(435); b.text:SetJustifyH("LEFT")
        b.sub = ns.Text(b, 9, ns.C.muted); b.sub:SetPoint("BOTTOMLEFT", 34, 3); b.sub:SetWidth(435); b.sub:SetJustifyH("LEFT")
        b.star = button(b, "☆", 25, 24); b.star:SetPoint("RIGHT", -4, 0); b.star:SetScript("OnClick", function(self) local entry = self:GetParent().entry; if entry then wishToggle(entry); E:Render() end end)
        b:SetScript("OnClick", function(self, mouse) if self.entry and not previewItem(self.entry, mouse) then E:OpenEntry(self.entry) end end)
        b:SetScript("OnEnter", function(self) if self.entry and GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, self.entry.data.id) end; GameTooltip:Show() end end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        b:EnableMouseWheel(true); b:SetScript("OnMouseWheel", setScroll)
        setPane.pieces[i] = b
    end
    setPane.bonuses = ns.Text(setPane, 10, ns.C.text); setPane.bonuses:SetPoint("TOPLEFT", 12, -250); setPane.bonuses:SetWidth(405); setPane.bonuses:SetHeight(55); setPane.bonuses:SetJustifyH("LEFT"); setPane.bonuses:SetJustifyV("TOP")
    setPane.bonusNext = button(setPane, "More bonuses", 100, 20); setPane.bonusNext:SetPoint("TOPRIGHT", -12, -250)
    setPane.bonusNext:SetScript("OnClick", function() E.bonusPage = (E.bonusPage or 1) + 1; E:Render() end)
    setPane:Hide()
    local recipePane = CreateFrame("Frame", nil, detail); recipePane:SetAllPoints(detail); f.recipePane = recipePane
    recipePane.title = ns.Text(recipePane, 14, ns.C.bright); recipePane.title:SetPoint("TOPLEFT", 12, -10); recipePane.title:SetWidth(470); recipePane.title:SetJustifyH("LEFT")
    recipePane.favorite = button(recipePane, "☆", 30, 25); recipePane.favorite:SetPoint("TOPRIGHT", -10, -5)
    recipePane.favorite:SetScript("OnClick", function() if E.current then local fav = recipeFavorites(); fav[E.current.extra .. ":" .. tostring(E.current.data.s or E.current.name)] = not fav[E.current.extra .. ":" .. tostring(E.current.data.s or E.current.name)] or nil; E:Render() end end)
    recipePane.vendor = button(recipePane, "Vendor map", 90, 25); recipePane.vendor:SetPoint("RIGHT", recipePane.favorite, "LEFT", -5, 0)
    recipePane.vendor:SetScript("OnClick", function(self)
        local vendor = self.vendor
        if vendor then showLocation(vendor[4], vendor[5], vendor[6]) end
    end)
    recipePane.info = ns.Text(recipePane, 10, ns.C.text); recipePane.info:SetPoint("TOPLEFT", 12, -38); recipePane.info:SetWidth(510); recipePane.info:SetHeight(110); recipePane.info:SetJustifyH("LEFT"); recipePane.info:SetJustifyV("TOP")
    local reagentsTitle = ns.Text(recipePane, 12, ns.C.bright); reagentsTitle:SetPoint("TOPLEFT", 12, -155); reagentsTitle:SetText("Reagents")
    recipePane.reagents = {}
    for i = 1, 5 do
        local b = button(recipePane, "", 520, 29); b:SetPoint("TOPLEFT", 12, -177 - (i - 1) * 32)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(23, 23); b.icon:SetPoint("LEFT", 4, 0)
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", b, "LEFT", 32, 0); b.text:SetWidth(470); b.text:SetJustifyH("LEFT")
        b:SetScript("OnClick", function(self, mouse) if self.entry and not previewItem(self.entry, mouse) then E:OpenEntry(self.entry) end end)
        recipePane.reagents[i] = b
    end
    recipePane.counter = ns.Text(recipePane, 9, ns.C.muted); recipePane.counter:SetPoint("BOTTOMLEFT", 12, 5)
    recipePane.related = {}
    for i = 1, 2 do
        local b = button(recipePane, "", 220, 22); b:SetPoint("BOTTOMLEFT", 12 + (i - 1) * 225, 24)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(18, 18); b.icon:SetPoint("LEFT", 3, 0)
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", b, "LEFT", 25, 0); b.text:SetWidth(190); b.text:SetJustifyH("LEFT"); if b.text.SetWordWrap then b.text:SetWordWrap(false) end
        b:SetScript("OnClick", function(self, mouse) if self.entry and not previewItem(self.entry, mouse) then E:OpenEntry(self.entry) end end)
        b:SetScript("OnEnter", function(self) if self.entry and GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.entry.name, 1, 0.82, 0); GameTooltip:Show() end end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        recipePane.related[i] = b
    end
    recipePane.more = button(recipePane, ">", 38, 22); recipePane.more:SetPoint("BOTTOMRIGHT", -12, 24)
    recipePane.more:SetScript("OnClick", function() E.recipeLinkPage = (E.recipeLinkPage or 1) + 1; E:Render() end)
    local function reagentScroll(_, delta) E.reagentOffset = (E.reagentOffset or 0) - delta; E:Render() end
    recipePane:EnableMouseWheel(true); recipePane:SetScript("OnMouseWheel", reagentScroll)
    for _, b in ipairs(recipePane.reagents) do b:EnableMouseWheel(true); b:SetScript("OnMouseWheel", reagentScroll) end
    recipePane:Hide()
    local helper = CreateFrame("Frame", nil, f); helper:SetPoint("TOPLEFT", 180, -157); helper:SetSize(864, 385); ns.Panel(helper, { edge = 0.5 }); f.profHelper = helper
    helper.title = ns.Text(helper, 14, ns.C.bright); helper.title:SetPoint("TOPLEFT", 12, -10)
    helper.summary = ns.Text(helper, 10, ns.C.muted); helper.summary:SetPoint("TOPLEFT", 12, -34); helper.summary:SetWidth(830); helper.summary:SetHeight(47); helper.summary:SetJustifyH("LEFT"); helper.summary:SetJustifyV("TOP")
    helper.targets = {}
    helper.recalculate = button(helper, "Recalculate", 90, 24); helper.recalculate:SetPoint("TOPRIGHT", -252, -7)
    helper.recalculate:SetScript("OnClick", function() E.profPlan, E.profProfit, E.helperOffset = nil, nil, 0; E:Render() end)
    for i, target in ipairs({ 75, 150, 225, 300 }) do
        local b = button(helper, tostring(target), 55, 24); b:SetPoint("TOPRIGHT", -12 - (4 - i) * 59, -7)
        b:SetScript("OnClick", function() E.profTarget, E.profPlan, E.helperOffset = target, nil, 0; E:Render() end)
        helper.targets[i] = b
    end
    helper.rows = {}
    local function helperScroll(_, delta) E.helperOffset = (E.helperOffset or 0) - delta; E:Render() end
    helper:EnableMouseWheel(true); helper:SetScript("OnMouseWheel", helperScroll)
    for i = 1, 9 do
        local b = button(helper, "", 840, 32); b:SetPoint("TOPLEFT", 12, -85 - (i - 1) * 35)
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", b, "LEFT", 8, 0); b.text:SetWidth(820); b.text:SetJustifyH("LEFT")
        b:SetScript("OnClick", function(self) if self.entry then E:OpenEntry(self.entry) end end)
        b:EnableMouseWheel(true); b:SetScript("OnMouseWheel", helperScroll)
        helper.rows[i] = b
    end
    helper:Hide()
    local itemTooltip = CreateFrame("ScrollFrame", nil, detail); itemTooltip:SetPoint("TOPLEFT", 12, -42); itemTooltip:SetSize(518, 200); ns.Panel(itemTooltip, { edge = 0.5, alpha = 0.8 })
    itemTooltip.content = CreateFrame("Frame", nil, itemTooltip); itemTooltip.content:SetSize(508, 200); itemTooltip:SetScrollChild(itemTooltip.content)
    itemTooltip.text = ns.Text(itemTooltip.content, 13, ns.C.text); itemTooltip.text:SetPoint("TOPLEFT", 8, -7); itemTooltip.text:SetWidth(492); itemTooltip.text:SetJustifyH("LEFT"); itemTooltip.text:SetJustifyV("TOP")
    local function itemScroll(value)
        itemTooltip.offset = math.max(0, math.min(itemTooltip.maximum or 0, value or 0))
        itemTooltip:SetVerticalScroll(itemTooltip.offset)
        if itemTooltip.scrollbar then ns.UpdateListScrollbar(itemTooltip.scrollbar, itemTooltip.offset, itemTooltip.maximum) end
    end
    local itemGlide = CreateFrame("Frame", nil, itemTooltip); itemGlide:Hide()
    function itemTooltip.land() if itemTooltip.target then local target = itemTooltip.target; itemTooltip.target = nil; itemGlide:Hide(); itemScroll(target) end end
    itemGlide:SetScript("OnUpdate", function(self, elapsed)
        local target, current = itemTooltip.target, itemTooltip.offset or 0
        if not target then self:Hide(); return end
        local diff = target - current
        if math.abs(diff) < 0.5 then itemTooltip.land()
        else itemScroll(current + diff * math.min(1, (tonumber(elapsed) or 0) * 18)) end
    end)
    local function itemWheel(delta)
        itemTooltip.target = math.max(0, math.min(itemTooltip.maximum or 0, (itemTooltip.target or itemTooltip.offset or 0) - (tonumber(delta) or 0) * 36))
        itemGlide:Show()
    end
    itemTooltip:EnableMouseWheel(true); itemTooltip:SetScript("OnMouseWheel", function(_, delta) itemWheel(delta) end)
    itemTooltip:EnableMouse(true); itemTooltip:SetScript("OnMouseUp", function(_, mouse) previewItem(E.current, mouse) end)
    itemTooltip.scrollbar = ns.ListScrollbar(itemTooltip, function(value) itemTooltip.target = nil; itemGlide:Hide(); itemScroll(value) end); itemTooltip:Hide(); f.itemTooltip = itemTooltip
    local previous = button(detail, "<", 27, 26); previous:SetPoint("TOPRIGHT", -112, -240)
    local nextPage = button(detail, ">", 27, 26); nextPage:SetPoint("TOPRIGHT", -12, -240)
    local page = ns.Text(detail, 10, ns.C.muted); page:SetPoint("RIGHT", nextPage, "LEFT", -4, 0); page:SetWidth(65); page:SetJustifyH("CENTER")
    local function detailScroll(delta) E.detailPage = (E.detailPage or 1) + delta; E:Render() end
    previous:SetScript("OnClick", function() detailScroll(-1) end)
    nextPage:SetScript("OnClick", function() detailScroll(1) end)
    local textGlide = CreateFrame("Frame", nil, detail); textGlide:Hide(); f.detailGlide = textGlide
    textGlide:SetScript("OnUpdate", function(self, elapsed)
        local target = E.detailTarget
        if not target then self:Hide(); return end
        local diff = target - (E.detailPixel or 0)
        if math.abs(diff) < 0.5 then E.detailPixel, E.detailTarget = target, nil; self:Hide()
        else E.detailPixel = (E.detailPixel or 0) + diff * math.min(1, (tonumber(elapsed) or 0) * 18) end
        E.PlaceDetailText()
    end)
    local function textWheel(delta)
        E.detailTarget = math.max(0, math.min(E.detailMaxPixel or 0, (E.detailTarget or E.detailPixel or 0) - (tonumber(delta) or 0) * 39))
        textGlide:Show()
    end
    detail:EnableMouseWheel(true); detail:SetScript("OnMouseWheel", function(_, delta) if E.current and E.current.kind == "item" then itemWheel(delta) else textWheel(delta) end end)
    f.detailPageText, f.detailPrevious, f.detailNext = page, previous, nextPage
    local relatedTitle = ns.Text(detail, 10, ns.C.muted); relatedTitle:SetPoint("BOTTOMLEFT", 12, 132); relatedTitle:SetText("RELATED")
    f.relatedTitle, f.relatedButtons = relatedTitle, {}
    f.itemSourcesTab = button(detail, "Sources", 88, 22); f.itemSourcesTab:SetPoint("BOTTOMLEFT", 12, 131)
    f.itemUsedTab = button(detail, "Used in", 88, 22); f.itemUsedTab:SetPoint("LEFT", f.itemSourcesTab, "RIGHT", 5, 0)
    f.itemSourcesTab:SetScript("OnClick", function() E.itemLinksView, E.linkPage = "sources", 1; E:Render() end)
    f.itemUsedTab:SetScript("OnClick", function() E.itemLinksView, E.linkPage = "used", 1; E:Render() end)
    f.itemSourcesTab:Hide(); f.itemUsedTab:Hide()
    for i = 1, 6 do
        local b = button(detail, "", 258, 25)
        b:SetPoint("BOTTOMLEFT", 12 + ((i - 1) % 2) * 266, 98 - math.floor((i - 1) / 2) * 29)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(22, 22); b.icon:SetPoint("LEFT", 3, 0)
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", b, "LEFT", 29, 0); b.text:SetJustifyH("LEFT")
        b.text:SetWidth(223); if b.text.SetWordWrap then b.text:SetWordWrap(false) end
        b:SetScript("OnClick", function(_, mouse) if b.entry and not previewItem(b.entry, mouse) then E:OpenEntry(b.entry) end end)
        b:SetScript("OnEnter", function(self)
            if self.entry and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.entry.name, 1, 0.82, 0)
                GameTooltip:AddLine(self.sourceKind or self.entry.category, 1, 1, 1)
                if self.sourceNote then GameTooltip:AddLine(self.sourceNote, 0.8, 0.8, 0.8, true) end
                if self.sourceChance then GameTooltip:AddLine(tostring(self.sourceChance) .. "% (community estimate; Forever may differ)", 0.8, 0.8, 0.8, true) end
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        f.relatedButtons[i] = b
    end
    local linksPrev = button(detail, "<", 27, 22); linksPrev:SetPoint("BOTTOMLEFT", 12, 8)
    local linksNext = button(detail, ">", 27, 22); linksNext:SetPoint("LEFT", linksPrev, "RIGHT", 68, 0)
    local linksPage = ns.Text(detail, 10, ns.C.muted); linksPage:SetPoint("LEFT", linksPrev, "RIGHT", 3, 0); linksPage:SetWidth(62); linksPage:SetJustifyH("CENTER")
    linksPrev:SetScript("OnClick", function() E.linkPage = (E.linkPage or 1) - 1; E:Render() end)
    linksNext:SetScript("OnClick", function() E.linkPage = (E.linkPage or 1) + 1; E:Render() end)
    f.linksPrev, f.linksNext, f.linksPage = linksPrev, linksNext, linksPage
    -- Dungeon loot and quests use the full panel, with a scrollable grid instead
    -- of the six related-entry buttons used by ordinary detail pages.
    local dungeonList = CreateFrame("Frame", nil, detail)
    dungeonList:SetPoint("TOPLEFT", 12, -42); dungeonList:SetSize(822, 286)
    dungeonList.rows = {}; f.dungeonList = dungeonList
    local function dungeonListScroll(_, delta)
        E.dungeonListOffset = (E.dungeonListOffset or 0) - (tonumber(delta) or 0)
        E:Render()
    end
    dungeonList:EnableMouseWheel(true); dungeonList:SetScript("OnMouseWheel", dungeonListScroll)
    dungeonList.scrollbar = ns.ListScrollbar(dungeonList, function(value) E.dungeonListOffset = math.floor(value + 0.5); E:Render() end)
    for i = 1, 18 do
        local row = button(dungeonList, "", 404, 28)
        row:SetPoint("TOPLEFT", ((i - 1) % 2) * 410, -math.floor((i - 1) / 2) * 31)
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(24, 24); row.icon:SetPoint("LEFT", 3, 0)
        row.text:ClearAllPoints(); row.text:SetPoint("LEFT", 33, 0); row.text:SetWidth(365); row.text:SetJustifyH("LEFT")
        if row.text.SetWordWrap then row.text:SetWordWrap(false) end
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self, mouse)
            if self.guideQuest and E.current and ns.InstanceGuide and ns.InstanceGuide.OpenQuest then
                ns.InstanceGuide:OpenQuest(E.current.data, self.guideQuest)
            elseif self.entry and not previewItem(self.entry, mouse) then E:OpenEntry(self.entry) end
        end)
        row:SetScript("OnEnter", function(self)
            if self.entry and GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.entry.name); GameTooltip:Show() end
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        row:EnableMouseWheel(true); row:SetScript("OnMouseWheel", dungeonListScroll)
        dungeonList.rows[i] = row
    end
    dungeonList:Hide()
    local overview = CreateFrame("Frame", nil, detail); overview:SetAllPoints(); f.dungeonOverview = overview
    overview.heading = ns.Text(overview, 15, ns.C.bright); overview.heading:SetPoint("TOPLEFT", 14, -14); overview.heading:SetText("At a glance")
    overview.info = ns.Text(overview, 11, ns.C.text); overview.info:SetPoint("TOPLEFT", 14, -45); overview.info:SetWidth(830); overview.info:SetJustifyH("LEFT"); overview.info:SetJustifyV("TOP")
    overview.descriptionTitle = ns.Text(overview, 12, ns.C.bright); overview.descriptionTitle:SetPoint("TOPLEFT", 14, -120); overview.descriptionTitle:SetText("About this instance")
    overview.description = ns.Text(overview, 11, ns.C.text); overview.description:SetPoint("TOPLEFT", 14, -144); overview.description:SetWidth(830); overview.description:SetHeight(120); overview.description:SetJustifyH("LEFT"); overview.description:SetJustifyV("TOP")
    overview.hint = ns.Text(overview, 10, ns.C.muted); overview.hint:SetPoint("BOTTOMLEFT", 14, 14); overview.hint:SetText("Explore the bosses, loot and quests using the tabs above.")
    overview:Hide()
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "ForeverUIEncyclopedia") end
    local wishMenu = CreateFrame("Frame", nil, f); wishMenu:SetSize(220, 194); wishMenu:SetFrameStrata("DIALOG"); wishMenu:SetFrameLevel(f:GetFrameLevel() + 40); wishMenu:SetClampedToScreen(true); wishMenu:EnableMouse(true); ns.Panel(wishMenu, { alpha = 1.1, edge = 1 }); f.wishMenu = wishMenu
    local menuTitle = ns.Text(wishMenu, 11, ns.C.bright); menuTitle:SetPoint("TOPLEFT", 8, -7); menuTitle:SetText("Choose a wishlist")
    local menuClose = button(wishMenu, "X", 22, 20); menuClose:SetPoint("TOPRIGHT", -4, -3); menuClose:SetScript("OnClick", function() wishMenu:Hide() end)
    wishMenu.rows = {}; wishMenu.offset = 0
    function wishMenu:Refresh()
        local names = gearSetNames(); local rows = { false }; for _, name in ipairs(names) do rows[#rows + 1] = name end
        self.offset = math.max(0, math.min(self.offset or 0, math.max(0, #rows - #self.rows)))
        self.offset = E.SmoothSync(E.smooth.wish, self.offset, #rows)
        local key = self.entry and self.entry.data and self.entry.data.id and tostring(self.entry.data.id) or self.enchant and enchantKey(self.enchant)
        for i, b in ipairs(self.rows) do
            local name = rows[i + self.offset]; local exists = name ~= nil; b:SetShown(exists); b.setName = name or nil
            if exists and key then
                local added = wishlistFor(b.setName)[key] ~= nil
                b.text:SetText(b.setName or "Wishlist"); b.status:SetText(added and "Added" or "Add")
                if added then b.status:SetTextColor(0.35, 0.9, 0.4) else b.status:SetTextColor(ns.C.muted[1], ns.C.muted[2], ns.C.muted[3]) end
            end
        end
    end
    for i = 1, 8 do
        local b = button(wishMenu, "", 201, 21); b:SetPoint("TOPLEFT", 5, -27 - (i - 1) * 23)
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 6, 0); b.text:SetWidth(132); b.text:SetJustifyH("LEFT"); if b.text.SetWordWrap then b.text:SetWordWrap(false) end
        b.status = ns.Text(b, 9, ns.C.muted); b.status:SetPoint("RIGHT", -6, 0); b.status:SetWidth(52); b.status:SetJustifyH("RIGHT")
        b:SetScript("OnClick", function(self)
            local entry, option = wishMenu.entry, wishMenu.enchant
            local key = entry and entry.data and entry.data.id and tostring(entry.data.id) or option and enchantKey(option)
            if not key then return end
            local saved = wishlistFor(self.setName)
            if saved[key] then saved[key] = nil
            elseif entry then saved[key] = { name = entry.name, slot = entry.data.slot }
            elseif option then saved[key] = { name = option.n, enchant = true, option = { n = option.n, e = option.e, s = option.s, i = option.i, p = option.p, req = option.req, st = option.st, src = option.src } } end
            wishMenu:Hide(); E:Render()
        end)
        b:SetScript("OnEnter", function(self) if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.setName or "Wishlist"); GameTooltip:AddLine(self.status:GetText() == "Added" and "Click to remove from this list." or "Click to add to this list.", 1, 1, 1, true); GameTooltip:Show() end end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        b:EnableMouseWheel(true); b:SetScript("OnMouseWheel", function(_, delta) wishMenu.offset = wishMenu.offset - delta; wishMenu:Refresh() end)
        wishMenu.rows[i] = b
    end
    E.SmoothList("wish", { pane = wishMenu, rows = wishMenu.rows, step = 23, top = 27, refresh = function() wishMenu:Refresh() end }); wishMenu:Hide()
    f:HookScript("OnHide", function() wishMenu:Hide() end)
    local function wishlistButton(b, resolve)
        b.text:SetText("+"); if b.icon then b.icon:Hide() end
        b:SetScript("OnEnter", function(self) if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.removeCurrent and "Remove from this list" or "Add to a wishlist"); GameTooltip:AddLine(self.removeCurrent and "Other wishlists and gear sets are unchanged." or "Choose a wishlist or gear set.", 1, 1, 1, true); GameTooltip:Show() end end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        b:SetScript("OnClick", function(self)
            local entry, option = resolve(self); if not entry and not option then return end
            if self.removeCurrent then
                local key = entry and entry.data and entry.data.id and tostring(entry.data.id) or option and enchantKey(option)
                if key then wishlist()[key] = nil; E:Render() end
                return
            end
            wishMenu.entry, wishMenu.enchant, wishMenu.offset = entry, option, 0
            wishMenu:ClearAllPoints(); local _, y = self:GetCenter(); local height = UIParent:GetHeight()
            if y and height and height > 0 and y > height * 0.65 then wishMenu:SetPoint("TOPRIGHT", self, "BOTTOMLEFT", -4, 0)
            else wishMenu:SetPoint("BOTTOMRIGHT", self, "TOPLEFT", -4, 0) end
            wishMenu:Refresh(); wishMenu:Show()
        end)
    end
    wishlistButton(f.itemWish, function() return E.current and E.current.kind == "item" and E.current or nil end)
    for _, row in ipairs(bossPane.rows) do wishlistButton(row.star, function(self) local loot = self:GetParent().loot; return loot and E.byKey["item:" .. tostring(loot.id)] end) end
    for _, row in ipairs(setPane.pieces) do wishlistButton(row.star, function(self) return self:GetParent().entry end) end
    for _, row in ipairs(planner.rows) do wishlistButton(row.star, function(self) local parent = self:GetParent(); return parent.entry, parent.enchant end) end
    local function redraw() E:Render() end
    E.SmoothList("list", { pane = f.list, rows = f.rows, step = 36, top = 6, refresh = redraw })
    f.detail.scrollbar = ns.ListScrollbar(f.detail, function(value) E.detailPixel, E.detailTarget = value, nil; f.detailGlide:Hide(); E.PlaceDetailText() end)
    E.SmoothList("library", { pane = f.libraryPane, rows = f.libraryPane.rows, step = 35, top = 28, refresh = redraw })
    E.SmoothList("rep", { pane = f.repPane, rows = f.repPane.rows, step = 34, top = 174, refresh = redraw })
    E.SmoothList("boss", { pane = f.bossPane, rows = f.bossPane.rows, step = 40, top = 71, refresh = redraw })
    E.SmoothList("set", { pane = f.setPane, rows = f.setPane.pieces, step = 32, top = 85, refresh = redraw })
    E.SmoothList("reagents", { pane = f.recipePane, rows = f.recipePane.reagents, step = 32, top = 177, refresh = redraw })
    E.SmoothList("helper", { pane = f.profHelper, rows = f.profHelper.rows, step = 35, top = 85, refresh = redraw })
    -- the scroll bar moves the list pixel by pixel as it's dragged
    planner.scrollbar = ns.ListScrollbar(results, function(value) E.plannerPixel, E.plannerTarget = value, nil; planner.glide:Hide(); E.plannerScrollTime = GetTime and GetTime() or nil; E:Render() end)
    f:Hide(); return f
end

-- The Items page list: one row per distinct item, in name order. Cached until
-- the entries or the filters change; built ahead at the loading screen.
function E:ItemCatalog(entries)
    local group, query, quality = self.itemGroup or "all", self.query or "", self.itemQuality
    local cache = self.itemCatalogCache
    if not cache or cache.revision ~= self.entryRevision or cache.group ~= group or cache.query ~= query or cache.quality ~= quality or cache.known ~= self.itemKnownSources then
        local list, seen = {}, {}
        local known = { Weapon=true, Armor=true, Consumable=true, ["Trade Goods"]=true, Recipe=true, Quest=true, Container=true, Key=true }
        for _, entry in ipairs(entries) do if entry.kind == "item" and not itemUnavailable(entry) then
            local d = entry.data; local class = d.itemClass or (d.reference and d.reference.itemClass) or ""
            local ref = type(d.reference) == "table" and d.reference or {}
            local hasSource = (type(d.sourceTypes) == "string" and d.sourceTypes ~= "") or (type(ref.sourceTypes) == "string" and ref.sourceTypes ~= "")
                or (type(ref.questIds) == "table" and #ref.questIds > 0) or (type(ref.npcIds) == "table" and #ref.npcIds > 0)
                or (type(d.bulkSources) == "table" and #d.bulkSources > 0) or (type(d.sourceLinks) == "table" and #d.sourceLinks > 0)
            if (not quality or quality < 0 or (d.quality or ref.quality) == quality) and (not self.itemKnownSources or hasSource)
                and (group == "all" or group == class or (group == "other" and not known[class])) then
                local key = catalogKey(entry); local index = seen[key]
                if not index then list[#list + 1] = entry; seen[key] = #list
                else
                    local previous = list[index]
                    local rank = itemRank(entry) + (entry.data.observed and 4 or 0) + (hasSource and 1 or 0)
                    local old = previous.data
                    local oldRank = itemRank(previous) + (old.observed and 4 or 0) + (old.sourceTypes and old.sourceTypes ~= "" and 1 or 0)
                    if rank > oldRank then list[index] = entry end
                end
            end
        end end
        -- the entries are kept in name order, so this list nearly is too
        -- (a duplicate swapped for a better copy can sit out of place among
        -- same-named items): put those few right instead of sorting ~30,000
        local function before(a, b) local an, bn = lowerName(a), lowerName(b); return an == bn and a.key < b.key or an < bn end
        local moves = 0
        for i = 2, #list do
            local value, j = list[i], i - 1
            if before(value, list[j]) then
                while j >= 1 and before(value, list[j]) do list[j + 1] = list[j]; j = j - 1; moves = moves + 1 end
                list[j + 1] = value
                if moves > 4000 then table.sort(list, before); break end
            end
        end
        cache = { revision = self.entryRevision, group = group, query = query, quality = quality, known = self.itemKnownSources, entries = list }; self.itemCatalogCache = cache
    end
    return cache.entries
end

function E:RenderGlobalSearch()
    local f = self.window
    if not f or not f.globalResults then return end
    local pane = f.globalResults
    local query = tostring(self.globalQuery or ""):match("^%s*(.-)%s*$")
    f.globalHint:SetShown(query == "")
    pane:SetShown(query ~= "")
    if query == "" then return end
    if not self.gearLoaded and referenceSource() then self:LoadGearIndex() end
    local found, results = self:Find("All", query), {}
    for _, entry in ipairs(found) do if entry.kind ~= "item" or not itemUnavailable(entry) then results[#results + 1] = entry end end
    pane.offset = math.max(0, math.min(pane.offset or 0, math.max(0, #results - #pane.rows)))
    pane.offset = E.SmoothSync(E.smooth.search, pane.offset, #results)
    pane.empty:SetShown(#results == 0)
    for i, row in ipairs(pane.rows) do
        local entry = results[i + pane.offset]; row.entry = entry; row:SetShown(entry ~= nil)
        if entry then
            entryIcon(row.icon, entry)
            row.text:SetText(entryLabel(entry) .. "  •  " .. tostring(entry.category))
        end
    end
end

function E:Render()
    local f = self.window
    if not f then return end
    f.UpdateIconLegend(self.selected)
    local professions = self.selected == "Professions"
    local pets, armory, instances, reputations = self.selected == "Pets", self.selected == "Armory", self.selected == "Dungeons", self.selected == "Reputations"
    local books, itemDirectory = self.selected == "Library Books", self.selected == "Items"
    local directory = self.selected == "Quests" or self.selected == "NPCs"
    local isDungeon = instances and self.current and self.current.kind == "dungeon"
    local bossMode = isDungeon and self.dungeonView == "Bosses"
    local browsingInstances = instances and not self.current
    local browsingCamping = professions and not self.profName and self.profFilter == "Camping" and not self.current
    local setView = armory and self.armorFilter == "set" and self.setGroup ~= nil
    local searching = (self.query or ""):match("%S") ~= nil
    if itemDirectory then self:LoadGearIndex() end
    local category = itemDirectory and "Armory" or professions and self.profName and self.profView == "favor" and "Favor" or professions and (self.profName or self.profFilter ~= "Professions") and self.profFilter or self.selected
    local entries = armory and self.armorFilter == "planner" and {} or self:Find(category, self.query)
    if itemDirectory then
        entries = self:ItemCatalog(entries)
    end
    if directory then
        self.directoryFilters = self.directoryFilters or {}; self.directoryFilters[self.selected] = self.directoryFilters[self.selected] or { kind = "all" }
        -- The filtered list is kept until the entries, search or filter change:
        -- scrolling redraws the list every row, and walking ~10,000 NPCs' links
        -- for "Dungeon bosses" each time made the scroll bar judder.
        local state = self.directoryFilters[self.selected]
        local key = table.concat({ tostring(self.selected), tostring(self.query or ""), tostring(self.entries), tostring(self.entryRevision),
            tostring(state.kind), tostring(state.min), tostring(state.max), tostring(state.side) }, "\1")
        local memo = self.directoryMemo
        if not memo or memo.key ~= key then
            local filtered = {}; for _, entry in ipairs(entries) do if self:DirectoryMatches(entry) then filtered[#filtered + 1] = entry end end
            memo = { key = key, list = filtered }; self.directoryMemo = memo
        end
        -- a copy: the code below may sort what it gets
        local list = {}; for i = 1, #memo.list do list[i] = memo.list[i] end; entries = list
    end
    if bossMode then
        local bosses = {}
        for _, entry in ipairs(self.current.links) do if entry.kind == "boss" then bosses[#bosses + 1] = entry end end
        entries = bosses
        if self.boss then
            local found = false
            for _, boss in ipairs(bosses) do if boss == self.boss then found = true; break end end
            if not found then self.boss = nil end
        end
        if not self.boss then self.boss = bosses[1] end
    elseif instances then
        local dungeons = {}
        local query = tostring(self.query or ""):lower():match("^%s*(.-)%s*$")
        for _, entry in ipairs(self.entries) do
            if entry.kind == "dungeon" and ((self.instanceFilter == "raid") == (entry.data.raid and true or false)) then
                local level = dungeonLevel(entry.data)
                local inGroup = self.instanceFilter == "raid" and (not self.raidSize or raidSize(entry.data) == self.raidSize)
                    or self.instanceFilter ~= "raid" and (not self.levelGroup or (level and (self.levelGroup == 50 and level >= 50
                    or self.levelGroup ~= 50 and level >= self.levelGroup and level < self.levelGroup + 10))
                    )
                if inGroup and (query == "" or dungeonMatches(entry.data, query)) then dungeons[#dungeons + 1] = entry end
            end
        end
        table.sort(dungeons, function(a, b)
            local al, bl = self.instanceFilter == "raid" and raidSize(a.data) or dungeonLevel(a.data), self.instanceFilter == "raid" and raidSize(b.data) or dungeonLevel(b.data)
            if type(al) ~= "number" then al = 999 end
            if type(bl) ~= "number" then bl = 999 end
            if al == bl then return lowerName(a) < lowerName(b) end
            return al < bl
        end)
        local groups, order = {}, {}
        for _, dungeon in ipairs(dungeons) do
            local level = dungeonLevel(dungeon.data)
            local bucket = self.instanceFilter == "raid" and raidSize(dungeon.data) or (level and (level >= 50 and 50 or math.floor(level / 10) * 10) or "unknown")
            if not groups[bucket] then groups[bucket] = {}; order[#order + 1] = bucket end
            groups[bucket][#groups[bucket] + 1] = dungeon
        end
        entries = {}
        for _, bucket in ipairs(order) do
            local groupKey = self.instanceFilter .. ":" .. tostring(bucket)
            local label
            if self.instanceFilter == "raid" then label = bucket == "unknown" and "Unknown raid size" or (bucket .. " players")
            else label = bucket == "unknown" and "Level unknown" or bucket == 50 and "Levels 50+" or ("Levels " .. bucket .. "–" .. (bucket + 9)) end
            entries[#entries + 1] = { kind = "dungeonGroup", name = label, data = { groupKey = groupKey, count = #groups[bucket] }, links = {} }
            if not self.collapsedLevels[groupKey] then
                for _, dungeon in ipairs(groups[bucket]) do entries[#entries + 1] = dungeon end
            end
        end
    end
    if professions then
        local professionState
        if self.profName and referenceSource() and type(referenceSource().GetProfessionState) == "function" then
            local ok, state = pcall(referenceSource().GetProfessionState, self.profName)
            if ok and type(state) == "table" then professionState = state end
        end
        self.recipeScanAvailable = professionState and professionState.scanned and true or false
        local filtered = {}
        for _, entry in ipairs(entries) do
            local known = self.profName and entry.kind ~= "profession" and recipeKnown(entry, professionState)
            local knowledgeOK = not self.profName or not self.recipeKnownFilter or self.recipeKnownFilter == "all"
                or self.recipeKnownFilter == "learned" and known == true or self.recipeKnownFilter == "unlearned" and known == false
            if (not self.profName and (entry.kind == "profession" or searching or self.profFilter ~= "Professions")) or
                (self.profName and entry.kind ~= "profession" and entry.extra == self.profName
                    and knowledgeOK and (self.profView ~= "favorites" or recipeFavorites()[entry.extra .. ":" .. tostring(entry.data.s or entry.name)])) then filtered[#filtered + 1] = entry end
        end
        if self.profName then table.sort(filtered, function(a, b) local ar, br = tonumber(a.data.req) or 0, tonumber(b.data.req) or 0; return ar == br and a.name < b.name or ar < br end) end
        entries = filtered
        if not self.profName and self.profFilter == "Camping" and referenceSource() and type(referenceSource().CAMPING_PROFESSIONS) == "table" and not searching then
            entries = {}; self.campingOpen = self.campingOpen or {}
            for _, group in ipairs(referenceSource().CAMPING_PROFESSIONS) do
                entries[#entries + 1] = { kind = "campingGroup", name = group.profession, data = { profession = group.profession, count = #(group.items or {}) }, links = {} }
                if self.campingOpen[group.profession] then
                    for _, object in ipairs(group.items or {}) do
                        local entry = self.byKey["campObject:" .. tostring(group.profession) .. ":" .. tostring(object.id or object.name)]
                        if entry then entries[#entries + 1] = entry end
                    end
                end
            end
        end
        if self.profName and self.profView ~= "skill" and self.profView ~= "profit" then
            local found = false
            for _, entry in ipairs(entries) do if entry == self.current then found = true; break end end
            if not found then self.current, self.reagentOffset = entries[1], 0 end
        end
    elseif pets then
        if self.petFilter == "family" and searching then
            local families = {}
            for _, match in ipairs(entries) do
                if match.kind == "family" then families[match.name] = true end
                if match.kind == "tame" and match.data.family then families[match.data.family] = true end
                if match.kind == "ability" then for _, name in ipairs(match.data.families or {}) do
                    if name == "All families" then for _, family in ipairs(self.entries) do if family.kind == "family" then families[family.name] = true end end
                    else families[name] = true end
                end end
            end
            entries = {}
            for _, entry in ipairs(self.entries) do if entry.kind == "family" and families[entry.name] then entries[#entries + 1] = entry end end
        end
        local filtered = {}
        for _, entry in ipairs(entries) do
            if self.petFilter == "family" and entry.kind == "family" then
                filtered[#filtered + 1] = entry
            elseif self.petFilter == "rare" and entry.kind == "tame" and entry.data.rare then
                filtered[#filtered + 1] = entry
            elseif self.petFilter == "tame" and entry.kind == "tame" and entry.data.family == self.petFamily then
                filtered[#filtered + 1] = entry
            elseif self.petFilter == "ability" and entry.kind == "ability" then
                if not self.petFamily then filtered[#filtered + 1] = entry
                else for _, rel in ipairs(entry.links) do
                    if rel.kind == "family" and rel.name == self.petFamily then filtered[#filtered + 1] = entry; break end
                end end
            end
        end
        entries = filtered
        if self.petFilter == "tame" or self.petFilter == "rare" then
            table.sort(entries, function(a, b)
                local al = tonumber(tostring(a.data.level or ""):match("%d+")) or 999
                local bl = tonumber(tostring(b.data.level or ""):match("%d+")) or 999
                return al == bl and a.name < b.name or al < bl
            end)
        end
        if self.petFilter == "family" then
            local found = false
            for _, entry in ipairs(entries) do if entry == self.current then found = true; break end end
            if not found then self.current = entries[1] end
            self.petFamily = self.current and self.current.name or nil
        end
    elseif books then
        local filtered = {}
        for _, entry in ipairs(entries) do if entry.kind == "book" and (not self.bookSet or entry.data.set == self.bookSet) then filtered[#filtered + 1] = entry end end
        entries = filtered
    elseif reputations then
        local filtered = {}
        for _, entry in ipairs(entries) do
            if entry.kind == "faction" then filtered[#filtered + 1] = entry end
        end
        table.sort(filtered, function(a, b) return a.name < b.name end)
        entries = filtered
        local found = false; for _, entry in ipairs(entries) do if entry == self.current then found = true; break end end
        if not found then self.current, self.repOffset, self.repVendorPage = entries[1], 0, 1 end
    elseif armory then
        if not self.setClassInitialized then local ok, _, class = pcall(UnitClass or function() end, "player"); if ok and type(class) == "string" and not ns.Secret(class) then self.setClass = class end; self.setClassInitialized = true end
        if setView then
            local choices = setSections(self.entries, self.setGroup); local valid = false
            for _, choice in ipairs(choices) do if choice == self.setSub then valid = true; break end end
            if not valid then self.setSub, self.setSubPage = choices[1], 1 end
        end
        -- the same list for the same filters: scrolling reuses it
        local armorKey = table.concat({ tostring(self.armorFilter), tostring(self.setGroup), tostring(self.setClass), tostring(self.hideUnavailable),
            tostring(self.setSub), tostring(self.armorType), tostring(self.armorSlot), tostring(self.query), tostring(searching) }, "")
        local memo = self.armorMemo
        if memo and memo.key == armorKey and memo.entries == self.entries and memo.revision == self.entryRevision then
            local copy = {}; for i = 1, #memo.list do copy[i] = memo.list[i] end; entries = copy
        else
        local filtered, groups = {}, {}
        local query = (self.query or ""):lower()
        local function group(kind, name, data)
            if name and name ~= "" and not groups[name] then
                groups[name] = true
                filtered[#filtered + 1] = { category = "Armory", kind = kind, key = kind .. ":" .. name, name = name, data = data, links = {} }
            end
        end
        -- every set and item is in Armory: no need to look through the rest
        for _, entry in ipairs(self.armorFilter == "planner" and {} or categoryList(self, "Armory")) do
            if self.armorFilter == "set" and entry.kind == "set" then
                local name = entry.data.g or "Other"
                if self.setGroup then
                    local classOK = not self.setClass or #(entry.data.cls or {}) == 0
                    if not classOK then for _, cls in ipairs(entry.data.cls or {}) do if cls == self.setClass then classOK = true; break end end end
                    if name == self.setGroup and classOK and (not self.hideUnavailable or entry.data.st ~= 0)
                        and (not self.setSub or self.setSub == (entry.data.sub or "Other"))
                        and (query == "" or lowerName(entry):find(query, 1, true)) then filtered[#filtered + 1] = entry end
                elseif searching then
                    if lowerName(entry):find(query, 1, true) then filtered[#filtered + 1] = entry end
                else group("setGroup", name, { group = name }) end
            elseif self.armorFilter == "armor" and entry.kind == "item" then
                local typ, slot = entry.data.armorType, entry.data.slot
                if typ and slot then
                    if not self.armorType and searching then
                        if lowerName(entry):find(query, 1, true) then filtered[#filtered + 1] = entry end
                    elseif not self.armorType then group("armorType", typ, { armorType = typ })
                    elseif typ == self.armorType and not self.armorSlot then group("armorSlot", slot, { armorType = typ, slot = slot })
                    elseif typ == self.armorType and slot == self.armorSlot
                        and (query == "" or lowerName(entry):find(query, 1, true)) then filtered[#filtered + 1] = entry end
                end
            elseif self.armorFilter == "item" and entry.kind == "item" and query ~= ""
                and lowerName(entry):find(query, 1, true) then filtered[#filtered + 1] = entry end
        end
        sortByName(filtered)
        filtered = dedupeItems(filtered)
        self.armorMemo ={ key = armorKey, entries = self.entries, revision = self.entryRevision, list = filtered }
        local copy = {}; for i = 1, #filtered do copy[i] = filtered[i] end; entries = copy
        end
        if setView then
            local found = false
            for _, entry in ipairs(entries) do if entry == self.current then found = true; break end end
            if not found then self.current, self.setPieceOffset = entries[1], 0 end
        end
    end
    local recipeSearch = professions and self.profName and self.profView ~= "skill" and self.profView ~= "profit"
    local visibleRows = setView and 8 or (bossMode or recipeSearch or browsingCamping) and 9 or (directory or itemDirectory) and 10 or #f.rows - 1
    self.offset = math.max(0, math.min(self.offset, math.max(0, #entries - visibleRows)))
    self.offset = E.SmoothSync(self.smooth.list, self.offset, #entries, visibleRows)
    for name, tab in pairs(f.tabs) do tab.fuiPanel.bright = name == self.selected; ns.PaintPanel(tab) end
    for name, tab in pairs(f.itemTabs) do tab:SetShown(itemDirectory); tab.fuiPanel.bright = name == (self.itemGroup or "all"); ns.PaintPanel(tab) end
    f.itemQuality:SetShown(itemDirectory); f.itemSources:SetShown(itemDirectory)
    if itemDirectory then
        f.itemQuality.text:SetText("Quality: " .. f.itemQuality.labels[(self.itemQuality or -1) + 2])
        f.itemSources.text:SetText(self.itemKnownSources and "Source recorded" or "Sources: All")
    end
    for name, tab in pairs(f.instanceTabs) do
        tab:SetShown(instances); tab.fuiPanel.bright = name == self.instanceFilter; ns.PaintPanel(tab)
    end
    f.levelToggle:SetShown(instances)
    local raidMode = self.instanceFilter == "raid"
    f.levelToggle.text:SetText((raidMode and "Raid size  " or "Level brackets  ") .. (self.levelExpanded == false and "+" or "−"))
    local counts = { [0] = 0, [10] = 0, [20] = 0, [30] = 0, [40] = 0, [50] = 0 }
    if instances then
        for _, entry in ipairs(self.entries) do
            if entry.kind == "dungeon" and ((self.instanceFilter == "raid") == (entry.data.raid and true or false)) then
                counts[0] = counts[0] + 1
                local level = dungeonLevel(entry.data)
                local bucket = level and (level >= 50 and 50 or math.floor(level / 10) * 10)
                if bucket and counts[bucket] then counts[bucket] = counts[bucket] + 1 end
            end
        end
    end
    for level, tab in pairs(f.levelTabs) do
        tab:SetShown(instances and not raidMode and self.levelExpanded ~= false)
        tab.text:SetText(tab.baseLabel .. "  (" .. tostring(counts[level] or 0) .. ")")
        tab.fuiPanel.bright = (self.levelGroup or 0) == level; ns.PaintPanel(tab)
    end
    local raidCounts, sizeList, sizeSeen = { [0] = 0 }, {}, {}
    if instances and raidMode then
        for _, entry in ipairs(self.entries) do
            if entry.kind == "dungeon" and entry.data.raid then
                local size = raidSize(entry.data)
                raidCounts[0] = raidCounts[0] + 1
                raidCounts[size] = (raidCounts[size] or 0) + 1
                if not sizeSeen[size] then sizeSeen[size] = true; sizeList[#sizeList + 1] = size end
            end
        end
        table.sort(sizeList, function(a, b)
            if a == "unknown" then return false end
            if b == "unknown" then return true end
            return a < b
        end)
    end
    for i, tab in ipairs(f.raidSizeTabs) do
        local size = i == 1 and 0 or sizeList[i - 1]
        tab.sizeFilter = size
        tab:SetShown(instances and raidMode and self.levelExpanded ~= false and size ~= nil)
        if size ~= nil then
            local label = size == 0 and "All raids" or size == "unknown" and "Unknown size" or (size .. " players")
            tab.text:SetText(label .. "  (" .. tostring(raidCounts[size] or 0) .. ")")
            tab.fuiPanel.bright = (self.raidSize or 0) == size; ns.PaintPanel(tab)
        end
    end
    f.instanceHeader:SetShown(isDungeon and true or false)
    f.bossBack:SetShown(isDungeon and true or false); f.bossCount:SetShown(bossMode and true or false)
    f.bossBack.text:SetText(self.instanceFilter == "raid" and "< Raids" or "< Dungeons")
    f.bossCount:SetText("Bosses  |  " .. #entries)
    if isDungeon then
        local data = self.current.data
        f.instanceHeader.title:SetText(self.current.name)
        f.instanceHeader.meta:SetText("Level " .. tostring(data.level or "?") .. "  |  " .. tostring(data.area or data.mapZone or "Unknown") .. "  |  " .. tostring(data.territory or "Unknown"))
        local image, left, right, top, bottom = dungeonArt(data, 100, 30)
        f.instanceHeader.art:SetShown(image ~= nil)
        if image then f.instanceHeader.art:SetTexture(image); f.instanceHeader.art:SetTexCoord(left, right, top, bottom) end
    end
    f.profBack:Hide()
    for name, tab in pairs(f.profTabs) do
        tab:Hide()
        tab.fuiPanel.bright = name == self.profFilter
        ns.PaintPanel(tab)
    end
    for name, tab in pairs(f.profNav) do
        tab:SetShown(professions)
        tab.fuiPanel.bright = name == (self.profName or (self.profFilter ~= "Professions" and self.profFilter or "overview")); ns.PaintPanel(tab)
    end
    local bookCounts, bookDone, manualCount, bookOwned, totalBooks = {}, {}, 0, 0, 0
    if books then for _, entry in ipairs(self.entries) do if entry.kind == "book" then
        local set = entry.data.set or "unknown"; totalBooks = totalBooks + 1; bookCounts[set] = (bookCounts[set] or 0) + 1
        local status = bookStatus(entry.data)
        if status == "Turned in" or status == "Manually marked turned in" then manualCount = manualCount + 1; bookDone[set] = (bookDone[set] or 0) + 1 end
        if status == "Turned in" or status == "Manually marked turned in" or status == "In bags" or status == "In bank" then bookOwned = bookOwned + 1 end
    end end end
    for name, tab in pairs(f.bookTabs) do
        tab:SetShown(books); tab.fuiPanel.bright = name == (self.bookSet or "all"); ns.PaintPanel(tab)
        tab.text:SetText(name == "all" and "All books" or (tab.baseLabel .. "  " .. (bookDone[name] or 0) .. "/" .. (bookCounts[name] or 0)))
    end
    f.bookProgress:SetShown(books); f.bookProgress:SetText("Turned in  " .. manualCount .. " / " .. totalBooks .. "\nOwned or turned in  " .. bookOwned .. " / " .. totalBooks)
    f.bookLegend:SetShown(books); f.bookHelp:SetShown(books)
    if not books then f.bookHelpPane:Hide() end
    for name, tab in pairs(f.profViews) do
        tab:SetShown(professions and self.profName ~= nil)
        tab.fuiPanel.bright = name == (self.profView or "recipes"); ns.PaintPanel(tab)
    end
    for name, tab in pairs(f.petTabs) do
        tab:SetShown(pets); tab.fuiPanel.bright = name == self.petFilter; ns.PaintPanel(tab)
    end
    local nestedArmor = armory and (self.armorType ~= nil or self.setGroup ~= nil)
    for name, tab in pairs(f.armorTabs) do
        tab:SetShown(armory); tab.fuiPanel.bright = name == self.armorFilter or self.armorFilter == "set" and name == self.setGroup; ns.PaintPanel(tab)
    end
    f.armorBack:SetShown(nestedArmor and not setView and true or false); f.armorPath:SetShown(nestedArmor and not setView and true or false)
    f.armorPath:SetText(self.armorSlot and (self.armorType .. " / " .. self.armorSlot) or self.armorType or self.setGroup or "")
    f.repBack:Hide()
    f.repPath:Hide()
    f.repPath:SetText(self.repSide or "")
    f.setControls:SetShown(setView)
    if setView then
        local controls, subs = f.setControls, setSections(self.entries, self.setGroup)
        for name, b in pairs(controls.classes) do b.fuiPanel.bright = name == (self.setClass or "ALL"); ns.PaintPanel(b) end
        controls.available.text:SetText(self.hideUnavailable and "✓ Hide unavailable" or "Hide unavailable")
        local pages = math.max(1, math.ceil(#subs / #controls.subs))
        self.setSubPage = ((self.setSubPage or 1) - 1) % pages + 1
        for i, b in ipairs(controls.subs) do
            local sub = subs[(self.setSubPage - 1) * #controls.subs + i]; b.sub = sub; b:SetShown(sub ~= nil)
            if sub then b.text:SetText(setSectionLabel(sub)); b.fuiPanel.bright = self.setSub == sub; ns.PaintPanel(b) end
        end
        controls.next:SetShown(pages > 1)
    end
    f.list:ClearAllPoints()
    local professionDetail = professions and self.profName ~= nil
    f.search:ClearAllPoints()
    if itemDirectory then f.search:SetPoint("TOPLEFT", f, "TOPLEFT", 180, -122); f.search:SetSize(152, 24)
    elseif recipeSearch then f.search:SetPoint("TOPLEFT", f, "TOPLEFT", 180, -157); f.search:SetSize(195, 24)
    elseif armory and self.armorFilter == "planner" then f.search:SetPoint("TOPRIGHT", f.planner.results, "TOPRIGHT", -8, -8); f.search:SetSize(153, 23); f.search:SetFrameLevel(f.planner.results:GetFrameLevel() + 10)
    else f.search:SetPoint("TOPRIGHT", f, "TOPRIGHT", -58, -48); f.search:SetSize(210, 24) end
    f.search:SetShown(itemDirectory or recipeSearch or (armory and self.armorFilter == "planner"))
    f.searchLabel:Hide()
    f.searchLabel:SetText(armory and self.armorFilter == "planner" and "Search items" or "Search this tab")
    f.profSearchHint:SetText((itemDirectory or armory and self.armorFilter == "planner") and "Search items..." or "Search recipes or materials...")
    f.profSearchHint:SetShown((itemDirectory or recipeSearch or armory and self.armorFilter == "planner") and (self.query or "") == "")
    f.recipeKnownFilter:SetShown(recipeSearch and true or false)
    local filterLabels = { all = "All recipes", learned = "Learned", unlearned = "Not learned" }
    f.recipeKnownFilter.text:SetText(filterLabels[self.recipeKnownFilter or "all"])
    f.sidebar:SetShown(not reputations and not directory)
    f.directoryFilters:SetShown(directory)
    if directory then
        local state = self.directoryFilters[self.selected]
        f.directoryFilters.syncing = true
        if f.directoryFilters.min:GetText() ~= (state.min or "") then f.directoryFilters.min:SetText(state.min or "") end
        if f.directoryFilters.max:GetText() ~= (state.max or "") then f.directoryFilters.max:SetText(state.max or "") end
        f.directoryFilters.syncing = false
        local options = self.selected == "Quests" and self.questDirectoryOptions or self.npcDirectoryOptions
        for _, option in ipairs(options) do if option[1] == state.kind then f.directoryFilters.kind.text:SetText(option[2]); break end end
        f.directoryFilters.side:SetShown(self.selected == "Quests")
        local sides = { all = "All factions", horde = "Horde + Both", alliance = "Alliance + Both" }
        f.directoryFilters.side.text:SetText(sides[state.side or "all"])
    end
    f.campingHeader:SetShown(browsingCamping)
    f.list:SetPoint("TOPLEFT", f, "TOPLEFT", (reputations or directory) and 18 or 180, (directory or itemDirectory) and -160 or setView and -230 or bossMode and -202 or recipeSearch and -188 or browsingCamping and -179 or professionDetail and -157 or -122)
    f.list:SetHeight((directory or itemDirectory) and 382 or setView and 312 or bossMode and 340 or recipeSearch and 354 or browsingCamping and 363 or professionDetail and 385 or 420)
    f.list:SetWidth((browsingInstances or browsingCamping) and 864 or 300)
    f.list:SetShown(not books and (not isDungeon or bossMode))
    f.detail:ClearAllPoints()
    f.detail:SetPoint("TOPLEFT", f, "TOPLEFT", (reputations or directory) and 330 or isDungeon and not bossMode and 180 or 492, (directory or itemDirectory) and -160 or setView and -230 or isDungeon and -202 or professionDetail and -157 or -122)
    f.detail:SetSize((reputations or directory) and 714 or isDungeon and not bossMode and 864 or 552, (directory or itemDirectory) and 382 or setView and 312 or isDungeon and 340 or professionDetail and 385 or 420)
    f.detail:SetShown(not books and not browsingInstances and not browsingCamping)
    local bookEntry = books and self.current and self.current.kind == "book"
    local itemEntry = self.current and self.current.kind == "item"
    f.itemTooltip:SetShown(itemEntry and true or false)
    f.itemPreviewHeader:SetShown(itemEntry and true or false)
    if itemEntry then f.itemPreviewHeader:SetWidth(math.max(100, f.detail:GetWidth() - 68)) end
    f.itemWish:SetShown(itemEntry and armoryEquipment(self.current) and true or false)
    f.questMap:SetShown(self.current and self.current.kind == "quest" and true or false)
    f.bookMark:SetShown(bookEntry and true or false)
    f.bookMap:SetShown(bookEntry and true or false)
    if bookEntry then
        local saved = ns.db and ns.db.encyclopediaBooks and ns.db.encyclopediaBooks[wishKey()]
        local marked = saved and saved[tostring(self.current.data.itemId or self.current.name)]
        f.bookMark.text:SetText(marked and "Undo manual mark" or "Mark turned in")
    end
    f.detailTitle:SetWidth(isDungeon and not bossMode and 838 or directory and 688 or 526)
    f.detailTitle:SetShown(not isDungeon)
    f.detailText:SetWidth(isDungeon and not bossMode and 838 or directory and 688 or 526)
    local relatedWidth = isDungeon and not bossMode and 414 or directory and 339 or 258
    for i, b in ipairs(f.relatedButtons) do
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", f.detail, "BOTTOMLEFT", 12 + ((i - 1) % 2) * (relatedWidth + 8), 98 - math.floor((i - 1) / 2) * 29)
        b:SetWidth(relatedWidth); b.text:SetWidth(relatedWidth - 36)
    end
    for i, row in ipairs(f.rows) do
        local rowWidth = (browsingInstances or browsingCamping) and 852 or directory and 274 or 288
        row:SetWidth(rowWidth)
        local entry = i <= visibleRows + 1 and entries[i + self.offset] or nil; row.entry = entry; row:SetShown(entry ~= nil)
        row.questStartMap:SetShown(entry and entry.kind == "quest" and true or false)
        local showNPC = entry and entry.kind == "npc" and directory and self.selected == "NPCs"
        row.portraitBorder:SetShown(showNPC and true or false)
        local roles = showNPC and E.NpcRoles(entry.data) or {}
        local badgeCount = 0
        for _, key in ipairs({"vendor", "trainer", "quest"}) do
            local badge = row.npcBadges[key]; badge:SetShown(roles[key] and true or false)
            if roles[key] then badge:ClearAllPoints(); badge:SetPoint("RIGHT", row, "RIGHT", -4 - badgeCount * 25, 0); badgeCount = badgeCount + 1 end
        end
        if entry then
            row.diet:Hide(); row.count:Hide(); row.chevron:Hide(); row.icon:ClearAllPoints(); row.icon:SetPoint("LEFT", row, "LEFT", 1, 0)
            if entry.kind == "item" then row.text:SetTextColor(itemQuality(entry))
            elseif entry.kind == "set" and entry.data.i and entry.data.i[1] then row.text:SetTextColor(itemQuality(nil, entry.data.i[1][4]))
            else row.text:SetTextColor(ns.C.text[1], ns.C.text[2], ns.C.text[3]) end
            row.sub:SetTextColor(ns.C.muted[1], ns.C.muted[2], ns.C.muted[3])
            row.text:ClearAllPoints()
            if entry.kind == "campingGroup" then
                row.icon:SetSize(26, 26); row.icon:ClearAllPoints(); row.icon:SetPoint("LEFT", row, "LEFT", 25, 0); row.icon:SetTexture("Interface\\Icons\\" .. (professionIcons[entry.name] or "inv_misc_questionmark")); row.icon:Show()
                row.chevron:SetText(self.campingOpen[entry.name] and "−" or "+"); row.chevron:Show()
                row.count:SetText(entry.data.count .. " camping objects"); row.count:Show(); row.sub:Hide()
                row.text:SetPoint("LEFT", row, "LEFT", 60, 0); row.text:SetWidth(rowWidth - 225); row.text:SetText(entry.name)
            elseif browsingCamping and entry.kind == "campObject" then
                row.icon:SetSize(26, 26); row.icon:ClearAllPoints(); row.icon:SetPoint("LEFT", row, "LEFT", 40, 0); entryIcon(row.icon, entry)
                row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 74, -3); row.text:SetWidth(rowWidth - 85); row.text:SetText(entry.name .. (entry.data.skill and ("  •  Skill " .. entry.data.skill) or ""))
                row.sub:ClearAllPoints(); row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 74, 3); row.sub:SetWidth(rowWidth - 85); row.sub:SetText(entry.data.effect or "Effect not recorded"); row.sub:Show()
            elseif instances and entry.kind == "dungeonGroup" then
                row.icon._ofaNpc = nil; row.icon:Hide(); row.sub:Hide()
                row.text:SetPoint("LEFT", row, "LEFT", 8, 0); row.text:SetWidth(rowWidth - 20)
                row.text:SetText((self.collapsedLevels[entry.data.groupKey] and "+  " or "−  ") .. entry.name .. "  (" .. entry.data.count .. ")")
            elseif bossMode then
                row.icon:SetSize(28, 28); row.icon:SetShown(true)
                bossPortrait(row.icon, self.current.data, entry.data)
                row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 38, -3); row.text:SetWidth(242)
                row.text:SetText(tostring(i + self.offset) .. ".  " .. entry.name)
                local level, kind = bossInfo(entry.data)
                row.sub:ClearAllPoints(); row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 38, 3); row.sub:SetWidth(242)
                row.sub:SetText("Level " .. tostring(level or "?") .. (kind and ("  •  " .. kind) or "")); row.sub:Show()
            elseif instances then
                row.icon._ofaNpc = nil -- do not let a late portrait update replace a reused dungeon thumbnail
                row.icon:SetSize(70, 32)
                local image, left, right, top, bottom = dungeonArt(entry.data, 70, 32)
                local hasArt = image ~= nil
                row.icon:SetShown(hasArt)
                if hasArt then row.icon:SetTexture(image); row.icon:SetTexCoord(left, right, top, bottom) end
                local inset = hasArt and 78 or 8
                row.text:SetPoint("TOPLEFT", row, "TOPLEFT", inset, -3)
                row.text:SetWidth(rowWidth - inset - 190)
                row.text:SetText(entry.name)
                row.sub:ClearAllPoints(); row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", inset, 3)
                row.sub:SetWidth(rowWidth - inset - 190)
                if ns.InstanceGuide then
                    local done, total, unknown = ns.InstanceGuide:QuestProgress(entry.data)
                    if total > 0 and not unknown then
                        if done == total then
                            row.count:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t  All quests completed")
                            row.count:SetTextColor(0.35, 0.85, 0.4)
                        else
                            row.count:SetText("|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t  " .. done .. "/" .. total .. " quests completed")
                            row.count:SetTextColor(1, 0.82, 0.25)
                        end
                        row.count:Show()
                    elseif total > 0 then
                        row.count:SetText("Quest progress unknown"); row.count:SetTextColor(ns.C.muted[1], ns.C.muted[2], ns.C.muted[3]); row.count:Show()
                    end
                end
                local sizeText = entry.data.raid and (raidSize(entry.data) == "unknown" and "Size unknown  •  " or (raidSize(entry.data) .. " players  •  ")) or ""
                row.sub:SetText(sizeText .. "Level " .. tostring(entry.data.level or "?") .. "  •  " .. tostring(entry.data.mapZone or entry.data.area or "Unknown") .. "  •  " .. tostring(entry.data.territory or "Unknown"))
                row.sub:Show()
            elseif setView and entry.kind == "set" then
                row.icon:SetSize(28, 28); entryIcon(row.icon, entry)
                row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 36, -3); row.text:SetWidth(242); row.text:SetText(entry.name)
                row.sub:ClearAllPoints(); row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 36, 3); row.sub:SetWidth(242)
                local owned, pieces = 0, entry.data.i or {}
                if GetItemCount then for _, piece in ipairs(pieces) do local ok, count = pcall(GetItemCount, piece[1], true); if ok and type(count) == "number" and not ns.Secret(count) and count > 0 then owned = owned + 1 end end end
                row.sub:SetText((GetItemCount and (owned .. " / " .. #pieces .. " owned") or (#pieces .. " pieces")) .. "  •  " .. (entry.data.arm or "Any armor") .. (entry.data.lv and ("  •  Lvl " .. entry.data.lv) or "")); row.sub:Show()
            elseif reputations and entry.kind == "faction" then
                row.icon:Hide(); row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -3); row.text:SetWidth(268); row.text:SetText(entry.name)
                row.sub:ClearAllPoints(); row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 3); row.sub:SetWidth(268)
                local rank, _, _, state = factionStanding(entry.data.id); row.sub:SetText((state == "unlisted" and "Not in reputation list" or standingName(rank)) .. "  •  " .. #(entry.data.i or {}) .. " rewards"); row.sub:Show()
                row.sub:SetTextColor(standingColor(rank))
            elseif books and entry.kind == "book" then
                row.icon:SetSize(28, 28); entryIcon(row.icon, entry)
                row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 36, -3); row.text:SetWidth(242); row.text:SetText(entry.name)
                row.sub:ClearAllPoints(); row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 36, 3); row.sub:SetWidth(242)
                local book, status = entry.data, bookStatus(entry.data)
                row.sub:SetText(status .. "  •  " .. tostring(book.zone or "Unknown")); row.sub:Show()
            elseif itemDirectory and entry.kind == "item" then
                row.icon:SetSize(28, 28); entryIcon(row.icon, entry)
                row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 36, -3); row.text:SetWidth(242); row.text:SetText(entry.name)
                row.sub:ClearAllPoints(); row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 36, 3); row.sub:SetWidth(242)
                local data = entry.data; local ref = type(data.reference) == "table" and data.reference or {}
                local itemClass = data.itemClass or ref.itemClass or "Item"; if itemClass == "" then itemClass = "Item" end
                local availability = itemAvailability(entry)
                local level = tonumber(ref.requiredLevel)
                row.sub:SetText(itemClass .. "  •  " .. itemSourceLabel(entry) .. (level and level > 0 and ("  •  Level " .. level) or "") .. availabilityTag(availability)); row.sub:Show()
            elseif professions and (entry.kind == "recipe" or entry.kind == "camping" or entry.kind == "favor") then
                row.icon:SetSize(28, 28); entryIcon(row.icon, entry)
                row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 36, -3); row.text:SetWidth(242); row.text:SetText(entry.name)
                row.sub:ClearAllPoints(); row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 36, 3); row.sub:SetWidth(242)
                row.sub:SetText("Skill " .. tostring(entry.data.req or "?") .. (entry.favorCost and ("  •  " .. entry.favorCost .. " Favor" .. (entry.favorCaution and " (unconfirmed)" or "")) or entry.data.fav and "  •  Favor" or "")); row.sub:Show()
            elseif pets and entry.kind == "family" then
                row.icon:SetSize(28, 28); entryIcon(row.icon, entry)
                row.text:SetPoint("LEFT", row, "LEFT", 36, 0); row.text:SetWidth(112); row.text:SetText(entry.name)
                row.diet:SetText(table.concat(entry.data.diet or {}, ", ")); row.diet:Show(); row.sub:Hide()
            else
                row.icon:SetSize(entry.kind == "dungeon" and 40 or 28, 28)
                local hasIcon = entryIcon(row.icon, entry)
                local inset = hasIcon and (entry.kind == "dungeon" and 47 or 36) or 8
                row.text:SetPoint("LEFT", row, "LEFT", inset, 0)
                local badgeSpace = 0
                if showNPC and badgeCount > 0 then badgeSpace = badgeCount * 25 + 8 end
                row.text:SetWidth(rowWidth - inset - (entry.kind == "quest" and 46 or badgeSpace > 0 and badgeSpace or 8))
                row.text:SetText(entryLabel(entry) .. (not directory and entry.extra and ("  —  " .. entry.extra) or ""))
                row.sub:Hide()
            end
            row.fuiPanel.bright = bossMode and self.boss == entry or self.current and self.current.key == entry.key
            ns.PaintPanel(row)
        end
    end
    local emptyTitle = "Choose an entry"
    if armory and self.armorFilter == "item" and self.query == "" then emptyTitle = "Search for an item"
    elseif pets and self.petFilter ~= "family" and not self.petFamily and not searching then emptyTitle = "Choose a family first" end
    local detailHasIcon = not isDungeon and entryIcon(f.detailIcon, self.current)
    if isDungeon then f.detailIcon:Hide() end
    f.detailTitle:ClearAllPoints(); f.detailTitle:SetPoint("TOPLEFT", f.detail, "TOPLEFT", detailHasIcon and 42 or 12, -12)
    f.detailTitle:SetWidth(directory and (detailHasIcon and 650 or 688) or (detailHasIcon and 490 or 526))
    f.detailTitle:SetText(self.current and entryLabel(self.current) or emptyTitle)
    if itemEntry then f.detailTitle:SetTextColor(itemQuality(self.current)) else f.detailTitle:SetTextColor(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3]) end
    local detailFont, _, detailFlags = f.detailText:GetFont(); if detailFont then f.detailText:SetFont(detailFont, itemEntry and 13 or 11, detailFlags or "") end
    for name, tab in pairs(f.dungeonTabs) do
        tab:SetShown(isDungeon and true or false)
        tab.fuiPanel.bright = name == (self.dungeonView or "Overview")
        ns.PaintPanel(tab)
    end
    local d = isDungeon and self.current.data
    local source = referenceSource()
    local canWaypoint = d and source and source.MAP_IDS and source.MAP_IDS[d.mapZone] and d.mapX and d.mapY
    f.dungeonMap:SetShown(canWaypoint and true or false)
    f.detailClip:ClearAllPoints()
    f.detailClip:SetPoint("TOPLEFT", f.detailTitle:GetParent(), "TOPLEFT", 12, isDungeon and -12 or -42)
    local dungeonListMode = isDungeon and (self.dungeonView == "Loot" or self.dungeonView == "Quests")
    local dungeonOverviewMode = isDungeon and not bossMode and not dungeonListMode
    f.detailClip:SetSize(isDungeon and not bossMode and 838 or directory and 688 or 526, dungeonListMode and 32 or isDungeon and 162 or 190)
    local detailText = linesFor(self.current)
    if not self.current and armory and self.armorFilter == "armor" then
        detailText = "Choose an armor type, then a slot. This first pass includes items whose type and slot are recorded in the set data. Other items can be found with Find items."
    end
    if isDungeon then
        local d = self.current.data
        if self.dungeonView == "Bosses" then
            detailText = "Bosses in " .. self.current.name .. "\nChoose a boss below to see its loot.\nRecorded bosses: " .. #(d.bosses or {})
        elseif self.dungeonView == "Loot" then
            detailText = "Loot  •  Select an item for its details"
        elseif self.dungeonView == "Quests" then
            detailText = "Quests  •  Select a quest to open it in Instance Guide"
        else
            detailText = "Level: " .. tostring(d.level or "Unknown") .. "\nLocation: " .. tostring(d.area or "Unknown")
                .. "\nTerritory: " .. tostring(d.territory or "Unknown")
            if d.mapX and d.mapY then detailText = detailText .. "\nEntrance: " .. string.format("%s %.1f, %.1f%s", d.mapZone or "", d.mapX, d.mapY, d.coordsUnverified and " (unverified)" or "") end
            if d.description then detailText = detailText .. "\n" .. d.description end
            detailText = detailText .. "\nChoose Bosses, Loot or Quests above to explore this dungeon."
        end
    end
    local detailLines = {}
    for line in detailText:gmatch("[^\n]+") do detailLines[#detailLines + 1] = line end
    local genericDetail = self.current and not books and not reputations and not setView and not bossMode
        and not (pets and self.petFilter == "family" and self.current.kind == "family")
        and not (professions and (self.current.kind == "recipe" or self.current.kind == "camping" or self.current.kind == "favor") and self.profView ~= "skill" and self.profView ~= "profit")
    f.detailText:SetHeight(0); f.detailText:SetText(table.concat(detailLines, "\n"))
    -- a new entry or view starts at the top; otherwise the position is kept
    local textKey = tostring(self.current and self.current.key) .. "|" .. tostring(self.dungeonView) .. "|" .. tostring(self.selected)
    if textKey ~= self.detailTextKey then self.detailTextKey, self.detailPixel, self.detailTarget = textKey, 0, nil; f.detailGlide:Hide() end
    local textHeight = tonumber(f.detailText:GetStringHeight()) or 0
    self.detailMaxPixel = genericDetail and not itemEntry and math.max(0, math.ceil(textHeight) - (isDungeon and 162 or 190)) or 0
    E.PlaceDetailText()
    f.detailPrevious:Hide(); f.detailNext:Hide(); f.detailPageText:Hide()
    if itemEntry then
        local pane = f.itemTooltip
        if pane.itemKey ~= self.current.key then pane.itemKey, pane.offset, pane.target = self.current.key, 0, nil end
        local width = math.max(200, f.detail:GetWidth() - 34)
        local height = math.max(80, f.detail:GetHeight() - (#(self.current.links or {}) > 0 and 198 or 58))
        pane:SetSize(width, height); pane.content:SetWidth(width - 10); pane.text:SetWidth(width - 26)
        pane.text:SetHeight(0); pane.text:SetText(itemTooltipText(self.current))
        local textHeight = pane.text:GetStringHeight() or 0
        pane.content:SetHeight(math.max(height, textHeight + 16))
        pane.maximum = math.max(0, math.ceil(textHeight + 16 - height)); pane.offset = math.min(pane.offset or 0, pane.maximum)
        pane:SetVerticalScroll(pane.offset); ns.UpdateListScrollbar(pane.scrollbar, pane.offset, pane.maximum)
    end
    local hasUsedIn = itemEntry and self.current.data.usedIn and #self.current.data.usedIn > 0
    f.itemSourcesTab:SetShown(hasUsedIn and true or false); f.itemUsedTab:SetShown(hasUsedIn and true or false)
    f.itemSourcesTab.fuiPanel.bright = self.itemLinksView ~= "used"; ns.PaintPanel(f.itemSourcesTab)
    f.itemUsedTab.fuiPanel.bright = self.itemLinksView == "used"; ns.PaintPanel(f.itemUsedTab)
    local links = itemEntry and itemRelatedEntries(self.current) or self.current and self.current.links or {}
    if hasUsedIn and self.itemLinksView == "used" then
        links = {}; for _, recipe in ipairs(self.current.data.usedIn) do links[#links + 1] = { entry = recipe, kind = "Recipe" } end
    elseif self.current and self.current.kind == "quest" then
        local rewards, seen = {}, {}
        for _, reward in ipairs(self.current.data.rewardEntries or {}) do rewards[#rewards + 1] = reward; seen[reward] = true end
        for _, related in ipairs(links) do if not seen[related] then rewards[#rewards + 1] = related end end
        links = rewards
    end
    local dungeonGuideRows = {}
    if isDungeon then
        local filtered, seen = {}, {}
        if self.dungeonView == "Quests" and ns.InstanceGuide and ns.InstanceGuide.QuestRows then
            -- The guide is the authority for faction/class eligibility and chains.
            -- Each root represents a chain; its steps are opened in the guide.
            for _, questRow in ipairs(ns.InstanceGuide:QuestRows(d)) do
                local q = questRow.quest
                local id = q and tonumber(q.id)
                if questRow.depth == 0 and id and not seen[id] then
                    seen[id] = true
                    local entry = self.byKey["quest:" .. tostring(d.key or d.name) .. ":" .. id]
                        or (self.questByID and self.questByID[id])
                        or {category="Dungeons", kind="quest", key="quest:guide:" .. id, name=q.name, data=q, links={}}
                    filtered[#filtered + 1] = entry
                    dungeonGuideRows[entry] = questRow
                end
            end
        end
        for _, entry in ipairs(links) do
            if (self.dungeonView == "Bosses" and entry.kind == "boss") or (self.dungeonView == "Quests" and not (ns.InstanceGuide and ns.InstanceGuide.QuestRows) and entry.kind == "quest" and (not ns.DungeonQuestTracker or ns.DungeonQuestTracker:QuestVisible(entry.data)) and not seen[tonumber(entry.data.id) or entry.key]) then
                if self.dungeonView == "Quests" then seen[tonumber(entry.data.id) or entry.key] = true end
                filtered[#filtered + 1] = entry
            elseif self.dungeonView == "Loot" then
                if entry.kind == "item" and not seen[entry.key] then seen[entry.key] = true; filtered[#filtered + 1] = entry end
                if entry.kind == "boss" then
                    for _, drop in ipairs(entry.links) do
                        if drop.kind == "item" and not seen[drop.key] then seen[drop.key] = true; filtered[#filtered + 1] = drop end
                    end
                end
            end
        end
        if self.dungeonView == "Loot" then sortByName(filtered) end
        links = filtered
    end
    local linkPages = math.max(1, math.ceil(#links / #f.relatedButtons))
    self.linkPage = math.max(1, math.min(self.linkPage or 1, linkPages))
    f.relatedTitle:SetShown(#links > 0 and not hasUsedIn)
    f.relatedTitle:SetText(itemEntry and "SOURCES & RELATED" or self.current and self.current.kind == "quest" and "REWARDS & RELATED" or isDungeon and (self.dungeonView == "Bosses" and "BOSSES" or self.dungeonView == "Loot" and "LOOT" or "QUESTS") or "RELATED")
    for i, b in ipairs(f.relatedButtons) do
        local row = links[(self.linkPage - 1) * #f.relatedButtons + i]
        local entry = itemEntry and row and row.entry or row
        b.sourceKind, b.sourceChance, b.sourceNote = itemEntry and row and row.kind or nil, itemEntry and row and row.chance or nil, itemEntry and row and row.note or nil
        b.sourceCost, b.sourceFaction = itemEntry and row and row.favorCost or nil, itemEntry and row and row.faction or nil
        b.sourceUncertain = itemEntry and row and row.uncertain or nil
        b.entry = entry; b:SetShown(entry ~= nil)
        if entry then
            b.icon:SetSize(entry.kind == "dungeon" and 32 or 22, 22)
            if entry.kind == "item" then b.text:SetTextColor(itemQuality(entry)) else b.text:SetTextColor(ns.C.text[1], ns.C.text[2], ns.C.text[3]) end
            local hasIcon = entryIcon(b.icon, entry)
            if b.sourceKind == "Merchant's Favor" then b.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01"); b.icon:Show(); hasIcon = true end
            local inset = hasIcon and (entry.kind == "dungeon" and 40 or 29) or 8
            b.text:ClearAllPoints(); b.text:SetPoint("LEFT", b, "LEFT", inset, 0); b.text:SetWidth(relatedWidth - inset - 6)
        local reward = self.current and self.current.kind == "quest" and self.current.data.rewardKeys and self.current.data.rewardKeys[entry.key]
        local qualifier = b.sourceNote and (b.sourceNote:find("Player-reported", 1, true) and " (reported)" or b.sourceNote:find("Classic reference", 1, true) and " (Classic)" or b.sourceNote:find("Community reference", 1, true) and " (reference)") or ""
        local sourceLabel = b.sourceKind and (b.sourceKind .. qualifier .. "  •  ") or ""
        if b.sourceFaction and b.sourceKind then sourceLabel = b.sourceKind .. " (" .. b.sourceFaction .. ")  •  " end
        if b.sourceUncertain then sourceLabel = "Unconfirmed  •  " .. sourceLabel end
        local price = b.sourceCost ~= nil and (tostring(b.sourceCost) .. " Favor  •  ") or ""
        b.text:SetText((reward and "Reward  •  " or sourceLabel) .. price .. entryLabel(entry))
        else b.icon._ofaNpc = nil; b.icon:Hide() end
    end
    f.linksPage:SetText(self.linkPage .. " / " .. linkPages)
    f.linksPrev:SetShown(linkPages > 1); f.linksNext:SetShown(linkPages > 1); f.linksPage:SetShown(linkPages > 1)
    f.dungeonList:SetShown(dungeonListMode and true or false)
    f.dungeonOverview:SetShown(dungeonOverviewMode and true or false)
    if dungeonListMode or dungeonOverviewMode then
        f.relatedTitle:Hide(); f.linksPrev:Hide(); f.linksNext:Hide(); f.linksPage:Hide()
        for _, b in ipairs(f.relatedButtons) do b:Hide() end
    end
    if dungeonListMode then
        local list = f.dungeonList
        local key = tostring(self.current.key) .. "|" .. self.dungeonView
        if self.dungeonListKey ~= key then self.dungeonListKey, self.dungeonListOffset = key, 0 end
        local maximum = math.max(0, math.ceil(#links / 2) - 9)
        self.dungeonListOffset = math.max(0, math.min(self.dungeonListOffset or 0, maximum))
        ns.UpdateListScrollbar(list.scrollbar, self.dungeonListOffset, maximum)
        for i, row in ipairs(list.rows) do
            local entry = links[self.dungeonListOffset * 2 + i]
            local questRow = entry and dungeonGuideRows[entry]
            row.entry, row.guideQuest = entry, questRow and questRow.quest or nil
            row:SetShown(entry ~= nil)
            if entry then
                entryIcon(row.icon, entry)
                if entry.kind == "item" then row.text:SetTextColor(itemQuality(entry))
                elseif questRow and self.QuestPage then
                    local statusEntry = {data=questRow.quest}
                    local status = self.QuestPage.Status(statusEntry)
                    local _, color = self.QuestPage.Presentation(statusEntry, status)
                    color = type(color) == "string" and color or "a9a9a9"
                    row.text:SetTextColor((tonumber(color:sub(1,2),16) or 169)/255, (tonumber(color:sub(3,4),16) or 169)/255, (tonumber(color:sub(5,6),16) or 169)/255)
                else row.text:SetTextColor(ns.C.text[1], ns.C.text[2], ns.C.text[3]) end
                row.text:SetText(entryLabel(entry) .. (questRow and questRow.chain and ("  •  Chain (" .. #questRow.chain .. ")") or ""))
            else row.icon:Hide() end
        end
    elseif dungeonOverviewMode then
        local overview = f.dungeonOverview
        f.detailText:Hide()
        local entrance = d.mapX and d.mapY and string.format("%s  %.1f, %.1f%s", d.mapZone or "", d.mapX, d.mapY, d.coordsUnverified and " (unverified)" or "") or "Not recorded"
        local count = 0
        if ns.InstanceGuide then local _, total = ns.InstanceGuide:QuestProgress(d); count = total end
        overview.info:SetText("Level  " .. tostring(d.level or "Unknown") .. "     •     Location  " .. tostring(d.area or "Unknown")
            .. "\nTerritory  " .. tostring(d.territory or "Unknown") .. "     •     Entrance  " .. entrance
            .. "\nBosses  " .. tostring(#(d.bosses or {})) .. "     •     Your faction and class quests  " .. tostring(count))
        overview.description:SetText(d.description or "No description recorded yet.")
    end
    f.bossPane:SetShown(bossMode and true or false)
    if bossMode then
        f.detailText:Hide(); f.detailPrevious:Hide(); f.detailNext:Hide(); f.detailPageText:Hide()
        f.relatedTitle:Hide(); f.linksPrev:Hide(); f.linksNext:Hide(); f.linksPage:Hide()
        for _, b in ipairs(f.relatedButtons) do b:Hide() end
        local pane, selected = f.bossPane, self.boss
        local boss = selected and selected.data
        pane.portrait:SetShown(boss ~= nil)
        pane.name:SetText(boss and selected.name or "No bosses recorded")
        if boss then
            bossPortrait(pane.portrait, self.current.data, boss)
            local level, kind, rank = bossInfo(boss)
            pane.meta:SetText("Level " .. tostring(level or "?") .. "  |  " .. tostring(kind or "Type unknown") .. (rank and ("  |  " .. tostring(rank)) or ""))
        else pane.meta:SetText("") end
        local loot = boss and boss.loot or {}
        local maximum = math.max(0, #loot - #pane.rows)
        self.bossLootOffset = math.max(0, math.min(self.bossLootOffset or 0, maximum))
        self.bossLootOffset = E.SmoothSync(self.smooth.boss, self.bossLootOffset, #loot)
        pane.empty:SetText(boss and (boss.worldDropsOnly and "Only world drops are recorded for this boss." or "No boss-specific loot recorded.") or "")
        pane.empty:SetShown(boss ~= nil and #loot == 0)
        for i, row in ipairs(pane.rows) do
            local lootItem = loot[i + self.bossLootOffset]
            row.loot = lootItem; row:SetShown(lootItem ~= nil)
            if lootItem then
                row.text:SetText(lootItem.name or "Unknown item")
                local quality = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[lootItem.quality]
                if quality then row.text:SetTextColor(quality.r, quality.g, quality.b)
                else row.text:SetTextColor(ns.C.text[1], ns.C.text[2], ns.C.text[3]) end
                row.sub:SetText(lootItem.slot or "")
                row.icon:SetTexture(itemIcon(lootItem.id))
                row.dropChance, row.dropKills, row.dropScaled = dropInfo(self.current.data, boss, lootItem.id)
                row.chance:SetText(row.dropChance and (tostring(row.dropChance) .. "%") or "?")
            end
        end
        pane.counter:SetText(#loot > #pane.rows - 1 and ("Scroll loot  •  " .. (self.bossLootOffset + 1) .. "–" .. math.min(#loot, self.bossLootOffset + #pane.rows - 1) .. " of " .. #loot) or "")
    else
        f.detailText:SetShown(not itemEntry and not dungeonOverviewMode)
    end
    local familyView = pets and self.petFilter == "family" and self.current and self.current.kind == "family"
    f.petPane:SetShown(familyView and true or false)
    if familyView then
        f.detailTitle:Hide(); f.detailIcon:Hide(); f.detailText:Hide(); f.detailPrevious:Hide(); f.detailNext:Hide(); f.detailPageText:Hide()
        f.relatedTitle:Hide(); f.linksPrev:Hide(); f.linksNext:Hide(); f.linksPage:Hide()
        for _, b in ipairs(f.relatedButtons) do b:Hide() end
        local pane, family = f.petPane, self.current
        local data = family.data
        entryIcon(pane.portrait, family); pane.name:SetText(family.name)
        pane.summary:SetText("Diet: " .. table.concat(data.diet or {}, ", ") .. "\nRole: " .. tostring(data.role or "Unknown")
            .. "\nSpecial: " .. tostring(data.specialTrait or data.trait or data.note or "None recorded"))
        local mod = data.modifiers or {}
        pane.modifiers:SetText("Health   ×" .. tostring(mod.health or "?") .. "\nArmor    ×" .. tostring(mod.armor or "?") .. "\nDamage  ×" .. tostring(mod.damage or "?"))
        local abilities = {}
        for _, name in ipairs(data.abilities or {}) do
            for _, related in ipairs(family.links or {}) do if related.kind == "ability" and related.name == name then abilities[#abilities + 1] = related; break end end
        end
        for i, b in ipairs(pane.abilities) do
            local more = i == 4 and #abilities > 4
            local ability = not more and abilities[i] or nil
            b.entry, b.more = ability, more; b:SetShown(ability ~= nil or more)
            if ability then entryIcon(b.icon, ability); b.text:SetText(ability.name)
            else b.icon:Hide(); if more then b.text:SetText("+ " .. (#abilities - 3) .. " more abilities") end end
        end
        local tames = {}
        for _, related in ipairs(family.links or {}) do if related.kind == "tame" then tames[#tames + 1] = related end end
        table.sort(tames, function(a, b)
            local al = tonumber(tostring(a.data.level or ""):match("%d+")) or 999
            local bl = tonumber(tostring(b.data.level or ""):match("%d+")) or 999
            return al == bl and a.name < b.name or al < bl
        end)
        pane.showAll.text:SetText("Show all (" .. #tames .. ")")
        for i, b in ipairs(pane.tames) do
            local tame = tames[i]; b.entry = tame; b:SetShown(tame ~= nil)
            if tame then
                b.text:SetText(tame.name .. "  (" .. tostring(tame.data.level or "?") .. ")"); b.zone:SetText(tame.data.zone or "Unknown")
                b.map:SetShown(tame.data.mapID and tame.data.x and tame.data.y and true or false)
            end
        end
    end
    local showSet = setView and self.current and self.current.kind == "set"
    f.setPane:SetShown(showSet and true or false)
    if showSet then
        f.detailTitle:Hide(); f.detailIcon:Hide(); f.detailText:Hide(); f.detailPrevious:Hide(); f.detailNext:Hide(); f.detailPageText:Hide()
        f.relatedTitle:Hide(); f.linksPrev:Hide(); f.linksNext:Hide(); f.linksPage:Hide()
        for _, b in ipairs(f.relatedButtons) do b:Hide() end
        local pane, set = f.setPane, self.current.data
        pane.title:SetText(self.current.name)
        pane.meta:SetText(table.concat({ set.sub or "Set", set.arm or "Any armor", set.lv and ("Level " .. set.lv) or "Level unknown", #(set.cls or {}) > 0 and table.concat(set.cls, ", ") or "All classes" }, "  •  "))
        pane.status:SetText(set.st == 0 and "Not available in Forever according to the reference data" or set.st == 2 and "Source not yet confirmed" or set.st == 1 and "Available according to reference data" or "Availability not recorded")
        local pieces, owned = set.i or {}, 0
        if GetItemCount then for _, piece in ipairs(pieces) do if piece[1] then local ok, count = pcall(GetItemCount, piece[1], true); if ok and type(count) == "number" and not ns.Secret(count) and count > 0 then owned = owned + 1 end end end end
        pane.owned:SetText(GetItemCount and ("Owned " .. owned .. " / " .. #pieces .. "  •  scroll pieces") or (#pieces .. " pieces  •  ownership unavailable"))
        self.setPieceOffset = math.max(0, math.min(self.setPieceOffset or 0, math.max(0, #pieces - #pane.pieces)))
        self.setPieceOffset = E.SmoothSync(self.smooth.set, self.setPieceOffset, #pieces)
        for i, b in ipairs(pane.pieces) do
            local piece = pieces[i + self.setPieceOffset]
            local entry = piece and piece[1] and (self.byKey["item:" .. piece[1]] or item(piece[1], piece[2] or ("Item " .. piece[1])))
            b.entry = entry; b:SetShown(entry ~= nil)
            if entry then
                entry.data.slot = entry.data.slot or piece[3]; entry.data.icon = entry.data.icon or piece[5]
                entryIcon(b.icon, entry); b.text:SetText(entry.name)
                b.text:SetTextColor(itemQuality(entry, piece[4]))
                b.sub:SetText(tostring(piece[3] or "Unknown slot") .. (type(piece[6]) == "table" and piece[6][1] and ("  •  " .. piece[6][1]) or ""))
            end
        end
        local bonuses, all = { "Set bonuses" }, set.b or {}
        local bonusPages = math.max(1, math.ceil(#all / 2)); self.bonusPage = ((self.bonusPage or 1) - 1) % bonusPages + 1
        for i = (self.bonusPage - 1) * 2 + 1, math.min(#all, self.bonusPage * 2) do local bonus = all[i]; bonuses[#bonuses + 1] = tostring(bonus[1]) .. " pieces: " .. tostring(bonus[2]) end
        if #bonuses == 1 then bonuses[#bonuses + 1] = "No bonuses recorded." end
        pane.bonuses:SetText(table.concat(bonuses, "\n"))
        pane.bonusNext:SetShown(bonusPages > 1)
    end
    local showRecipe = professions and self.current and (self.current.kind == "recipe" or self.current.kind == "camping" or self.current.kind == "favor") and self.profView ~= "skill" and self.profView ~= "profit"
    f.recipePane:SetShown(showRecipe and true or false)
    if showRecipe then
        f.detailTitle:Hide(); f.detailIcon:Hide(); f.detailText:Hide(); f.detailPrevious:Hide(); f.detailNext:Hide(); f.detailPageText:Hide()
        f.relatedTitle:Hide(); f.linksPrev:Hide(); f.linksNext:Hide(); f.linksPage:Hide(); for _, b in ipairs(f.relatedButtons) do b:Hide() end
        local pane, entry, data = f.recipePane, self.current, self.current.data
        pane.title:SetText(entry.name)
        local faction
        if UnitFactionGroup then local ok, value = pcall(UnitFactionGroup, "player"); if ok then faction = value == "Horde" and "H" or value == "Alliance" and "A" or nil end end
        local vendor
        for _, v in ipairs(entry.favorVendors or (data.src and data.src.v) or {}) do if v[4] and v[5] and v[6] and (not v.fac or not faction or v.fac == faction) then vendor = v; break end end
        pane.vendor.vendor = vendor; pane.vendor:SetShown(vendor ~= nil)
        local favKey = entry.extra .. ":" .. tostring(data.s or entry.name)
        pane.favorite.text:SetText(recipeFavorites()[favKey] and "★" or "☆")
        local info = { "Profession: " .. tostring(entry.extra or "Unknown"), "Required skill: " .. tostring(data.req or "Unknown") }
        if data.rn then info[#info + 1] = "Recipe: " .. data.rn end
        if data.fav or entry.favorCost ~= nil or entry.favorReport then
            info[#info + 1] = entry.favorCost and ((entry.favorCaution and "Reference cost: " or "Cost: ") .. entry.favorCost .. " Merchant's Favor") or entry.favorReport and "Merchant's Favor (player-reported; cost unverified)" or "Merchant's Favor recipe (cost unavailable)"
            if entry.favorCaution then
                local observed = ns.FavorVendorObservation and ns.FavorVendorObservation(tonumber(data.ri))
                info[#info + 1] = observed or "Not seen at Favor vendors; other sources unknown."
            end
        end
        if data.src and type(data.src.d) == "table" and data.src.d[1] then info[#info + 1] = "Drop: " .. tostring(data.src.d[1][2] or "Unknown") .. "  •  " .. tostring(data.src.d[1][3] or "Unknown") end
        local namedVendor = vendor or (entry.favorVendors and entry.favorVendors[1]) or (data.src and type(data.src.v) == "table" and data.src.v[1])
        if namedVendor then info[#info + 1] = "Vendor: " .. tostring(namedVendor[2] or "Unknown") .. (namedVendor[3] and (" • " .. namedVendor[3]) or "") end
        local gold = _G.ForeverGold
        if gold and type(gold.RecipeKnownBy) == "function" then local ok, chars = pcall(gold.RecipeKnownBy, entry.extra, entry.name); if ok and type(chars) == "table" and #chars > 0 then info[#info + 1] = "Known by: " .. table.concat(chars, ", ") end end
        pane.info:SetText(table.concat(info, "\n"))
        local reagents = data.r or {}; self.reagentOffset = math.max(0, math.min(self.reagentOffset or 0, math.max(0, #reagents - #pane.reagents)))
        self.reagentOffset = E.SmoothSync(self.smooth.reagents, self.reagentOffset, #reagents)
        for i, b in ipairs(pane.reagents) do
            local reagent = reagents[i + self.reagentOffset]; b:SetShown(reagent ~= nil); b.entry = reagent and self.byKey["item:" .. tostring(reagent[1])]
            if reagent then
                b.icon:SetTexture(itemIcon(reagent[1])); local have
                if GetItemCount then local ok, value = pcall(GetItemCount, reagent[1]); if ok and not ns.Secret(value) then have = value end end
                b.text:SetText(tostring(reagent[3] or ("Item " .. tostring(reagent[1]))) .. "  •  " .. tostring(have or "?") .. " / " .. tostring(reagent[2] or 1))
            end
        end
        pane.counter:SetText(#reagents > #pane.reagents - 1 and ("Scroll for all " .. #reagents .. " reagents") or "")
        local related = {}
        for _, linked in ipairs(entry.links or {}) do
            local isReagent = false
            if linked.kind == "item" then for _, reagent in ipairs(data.r or {}) do if reagent[1] == linked.data.id then isReagent = true; break end end end
            if not isReagent then related[#related + 1] = linked end
        end
        local pages = math.max(1, math.ceil(#related / #pane.related)); self.recipeLinkPage = ((self.recipeLinkPage or 1) - 1) % pages + 1
        for i, b in ipairs(pane.related) do
            local linked = related[(self.recipeLinkPage - 1) * #pane.related + i]; b.entry = linked; b:SetShown(linked ~= nil)
            if linked then
                local hasIcon = entryIcon(b.icon, linked)
                local inset = hasIcon and 25 or 7
                b.text:ClearAllPoints(); b.text:SetPoint("LEFT", b, "LEFT", inset, 0); b.text:SetWidth(220 - inset - 5)
                b.text:SetText(linked.name)
                if linked.kind == "item" then b.text:SetTextColor(itemQuality(linked)) else b.text:SetTextColor(ns.C.text[1], ns.C.text[2], ns.C.text[3]) end
            else b.icon:Hide() end
        end
        pane.more:SetShown(pages > 1)
    end
    f.libraryPane:SetShown(books)
    if books then
        local rows, sets = {}, { { "starter", "Set 1 - Level 20" }, { "l35", "Set 2 - Level 35" }, { "l45", "Set 3 - Level 45" }, { "l60", "Set 4 - Level 60" } }
        self.bookFolded = self.bookFolded or {}
        for _, spec in ipairs(sets) do
            local group = {}; for _, entry in ipairs(entries) do if entry.data.set == spec[1] then group[#group + 1] = entry end end
            if not self.bookSet or self.bookSet == spec[1] then
                rows[#rows + 1] = { group = spec[1], name = spec[2], count = #group }
                if not self.bookFolded[spec[1]] then for _, entry in ipairs(group) do rows[#rows + 1] = { book = entry.data } end end
            end
        end
        self.bookOffset = math.max(0, math.min(self.bookOffset or 0, math.max(0, #rows - #f.libraryPane.rows)))
        self.bookOffset = E.SmoothSync(self.smooth.library, self.bookOffset, #rows)
        for i, row in ipairs(f.libraryPane.rows) do
            local data = rows[i + self.bookOffset]; row:SetShown(data ~= nil); row.book, row.group = data and data.book, data and data.group
            row.name:SetText(""); row.territory:SetText(""); row.zone:SetText(""); row.map:Hide()
            if data and data.group then
                row.text:SetWidth(820); row.text:SetText((self.bookFolded[data.group] and "+  " or "−  ") .. data.name .. "     " .. (bookDone[data.group] or 0) .. " / " .. (bookCounts[data.group] or 0) .. " turned in")
            elseif data then
                local book, source = data.book, referenceSource(); local status = bookStatus(book)
                row.text:SetWidth(122); row.text:SetText(status == "Manually marked turned in" and "Manual" or status); row.name:SetText(book.name or "Unknown book")
                if status == "Missing" then row.text:SetTextColor(1, 0.25, 0.22)
                elseif status == "Turned in" or status == "Manually marked turned in" then row.text:SetTextColor(0.35, 0.9, 0.4)
                else row.text:SetTextColor(ns.C.text[1], ns.C.text[2], ns.C.text[3]) end
                local territory = source and source.TERRITORY_BY_ZONE and source.TERRITORY_BY_ZONE[book.zone]
                row.territory:SetText(territory or "Unknown")
                row.zone:SetText(tostring(book.zone or "Unknown") .. (book.x and book.y and string.format("  %.1f, %.1f", book.x, book.y) or ""))
                row.map:SetShown(source and source.MAP_IDS and source.MAP_IDS[book.zone] and book.x and book.y and true or false)
            end
            if data and data.group then row.text:SetTextColor(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3]) end
        end
    end
    local repView = reputations and self.current and self.current.kind == "faction"
    f.repPane:SetShown(repView and true or false)
    if repView then
        f.detailTitle:Hide(); f.detailIcon:Hide(); f.detailText:Hide(); f.detailPrevious:Hide(); f.detailNext:Hide(); f.detailPageText:Hide()
        f.relatedTitle:Hide(); f.linksPrev:Hide(); f.linksNext:Hide(); f.linksPage:Hide(); for _, b in ipairs(f.relatedButtons) do b:Hide() end
        local pane, faction = f.repPane, self.current.data
        for _, row in ipairs(pane.vendors) do row:SetWidth(687); row.text:SetWidth(627) end
        for _, row in ipairs(pane.rows) do row:SetWidth(688); row.text:SetWidth(650) end
        pane.title:SetText(self.current.name)
        local rank, value, maximum, state = factionStanding(faction.id)
        local watched
        if C_Reputation and C_Reputation.GetWatchedFactionData then local ok, data = pcall(C_Reputation.GetWatchedFactionData); if ok and type(data) == "table" and not ns.Secret(data.factionID) then watched = data.factionID == faction.id end end
        pane.track.text:SetText(watched and "Tracked" or "Track"); pane.track.fuiPanel.bright = watched and true or false; ns.PaintPanel(pane.track)
        pane.standing:SetText(state == "unlisted" and "Not in your reputation list (or its header is collapsed)" or "Your standing: " .. standingName(rank) .. (value and maximum and maximum > 0 and ("  (" .. value .. " / " .. maximum .. ")") or ""))
        pane.standing:SetTextColor(standingColor(rank))
        local fraction = value and maximum and maximum > 0 and math.max(0, math.min(1, value / maximum)) or 0
        pane.bar.fill:SetWidth(math.max(0.01, 318 * fraction)); pane.bar.fill:SetShown(fraction > 0)
        local vendors = faction.v or {}; local pages = math.max(1, math.ceil(#vendors / 3)); self.repVendorPage = ((self.repVendorPage or 1) - 1) % pages + 1
        pane.nextVendor:SetShown(pages > 1)
        for i, row in ipairs(pane.vendors) do
            local vendor = vendors[(self.repVendorPage - 1) * 3 + i]; row.vendor = vendor; row:SetShown(vendor ~= nil)
            if vendor then row.text:SetText(tostring(vendor[2] or "Unknown vendor") .. "  •  " .. tostring(vendor[6] or "Location unknown") .. (vendor[4] and vendor[5] and ("  " .. vendor[4] .. ", " .. vendor[5]) or "")) end
        end
        for name, b in pairs(pane.filters) do b.fuiPanel.bright = name == (self.repFilter or "All"); ns.PaintPanel(b) end
        local groups, order, view = {}, {}, {}; self.repFolded = self.repFolded or {}
        for _, reward in ipairs(faction.i or {}) do
            local kind = tostring(reward[7] or ""):lower(); local isRecipe = kind:find("recipe", 1, true) ~= nil; local isGear = kind:find("gear", 1, true) ~= nil or (reward[3] and reward[3] ~= "" and not isRecipe)
            local filter = self.repFilter or "All"
            if filter == "All" or filter == "Recipes" and isRecipe or filter == "Gear" and isGear or filter == "Other" and not isRecipe and not isGear then
                local level = tonumber(reward[6]) or 0; if not groups[level] then groups[level] = {}; order[#order + 1] = level end; groups[level][#groups[level] + 1] = reward
            end
        end
        table.sort(order)
        for _, level in ipairs(order) do
            local key = tostring(faction.id or faction.n) .. ":" .. level; view[#view + 1] = { group = key, label = level > 0 and standingName(level + 1) or "Standing not recorded", level = level }
            if not self.repFolded[key] then for _, reward in ipairs(groups[level]) do view[#view + 1] = { reward = reward } end end
        end
        self.repOffset = math.max(0, math.min(self.repOffset or 0, math.max(0, #view - #pane.rows)))
        self.repOffset = E.SmoothSync(self.smooth.rep, self.repOffset, #view)
        for i, row in ipairs(pane.rows) do
            local data = view[i + self.repOffset]; row:SetShown(data ~= nil); row.group, row.reward = data and data.group, data and data.reward
            row.categoryFill:SetShown(data and data.group and true or false); row.categoryAccent:SetShown(data and data.group and true or false)
            row.fuiPanel.bright = data and data.group and true or false; ns.PaintPanel(row)
            row.icon:SetShown(data and data.reward and true or false); row.text:ClearAllPoints()
            if data and data.group then row.text:SetPoint("LEFT", row, "LEFT", 8, 0); row.text:SetText((self.repFolded[data.group] and "+  " or "−  ") .. data.label .. (rank and data.level > 0 and rank < data.level + 1 and "  •  Not reached yet" or "")); row.text:SetTextColor(standingColor(data.level + 1))
            elseif data then row.icon:SetTexture(data.reward[5] or itemIcon(data.reward[1])); row.text:SetPoint("LEFT", row, "LEFT", 36, 0); row.text:SetText(tostring(data.reward[2] or "Unknown reward") .. (data.reward[3] and ("  •  " .. data.reward[3]) or "")); row.text:SetTextColor(ns.C.text[1], ns.C.text[2], ns.C.text[3]) end
        end
    end
    local sourceLabel = "Sources: tracker, Forever KB, Wowhead, WoW Forever Friends / CMaNGOS (Classic), and OneForAll reference snapshot"
    f.source:SetText(self.sourceAvailable and (sourceLabel .. "  •  " .. #entries .. " results")
        or "Reference data is unavailable. Check the Forever UI installation.")
    if itemDirectory and self.sourceAvailable then f.source:SetText(#entries .. " items  •  Availability is unknown where no source is recorded.") end
    if recipeSearch and self.recipeKnownFilter and self.recipeKnownFilter ~= "all" then
        f.source:SetText(self.recipeScanAvailable and "Knowledge based on your last profession scan, which may be incomplete." or "Open this character's profession to record recipes before filtering.")
    end
    local showProfOverview = professions and not self.profName and self.profFilter == "Professions" and not searching
    f.profOverview:SetShown(showProfOverview)
    if showProfOverview then
        f.list:Hide(); f.detail:Hide()
        local overview, skills = f.profOverview, playerProfessions()
        overview.noProfessions:SetShown(#skills == 0)
        for i, b in ipairs(overview.your) do
            local info = skills[i]; b:SetShown(info ~= nil); b.profession = info and info.name
            if info then
                b.text:SetText(info.name); b.sub:SetText("Skill " .. tostring(info.skill or "?") .. "/" .. tostring(info.maximum or "?"))
                b.icon:SetTexture(info.icon or (professionIcons[info.name] and "Interface\\Icons\\" .. professionIcons[info.name]) or "Interface\\Icons\\INV_Misc_QuestionMark")
            end
        end
        for name, b in pairs(overview.cards) do
            local recipes = referenceSource() and referenceSource().PROFESSION_RECIPES and referenceSource().PROFESSION_RECIPES[name]
            local label = recipes and (#recipes .. " recipes") or "Recipe data unavailable"
            local gold, player = _G.ForeverGold, nil
            if UnitName then local ok, value = pcall(UnitName, "player"); if ok and value and not ns.Secret(value) then player = value:match("^[^%-]+") end end
            if recipes and player and type(gold) == "table" and type(gold.RecipeKnownBy) == "function" then
                local known = 0
                for _, recipe in ipairs(recipes) do
                    if recipe.n then
                        local ok, characters = pcall(gold.RecipeKnownBy, name, recipe.n)
                        if ok and type(characters) == "table" then
                            for _, character in ipairs(characters) do if type(character) == "string" and character:match("^[^%-]+") == player then known = known + 1; break end end
                        end
                    end
                end
                label = label .. "  |  " .. known .. " recorded"
            end
            b.sub:SetText(label)
        end
        local mapID, faction
        if C_Map and C_Map.GetBestMapForUnit then local ok, value = pcall(C_Map.GetBestMapForUnit, "player"); if ok then mapID = value end end
        if UnitFactionGroup then local ok, value = pcall(UnitFactionGroup, "player"); if ok then faction = value == "Horde" and "H" or value == "Alliance" and "A" or nil end end
        local px, py
        if mapID and C_Map and C_Map.GetPlayerMapPosition then
            local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
            if ok and pos then if pos.GetXY then px, py = pos:GetXY() else px, py = pos.x, pos.y end end
        end
        overview.trainerText:Hide()
        for _, b in ipairs(overview.trainers) do
            local best, distance
            for _, tr in ipairs(referenceSource() and referenceSource().PROFESSION_TRAINERS and referenceSource().PROFESSION_TRAINERS[b.profession] or {}) do
                if tr[5] == mapID and (not faction or tostring(tr[4] or ""):find(faction, 1, true)) then
                    local dx, dy = px and tr[6] - px * 100 or 0, py and tr[7] - py * 100 or 0
                    local d = dx * dx + dy * dy
                    if not distance or d < distance then best, distance = tr, d end
                end
            end
            b.trainer = best; b.text:SetText(b.profession .. ": " .. (best and best[2] or "No trainer recorded here"))
        end
    end
    local showFavor = professions and not self.profName and self.profFilter == "Favor" and not searching
    f.favorOverview:SetShown(showFavor)
    if showFavor then
        f.list:Hide(); f.detail:Hide()
        local source = referenceSource()
        local favorCounts = {}
        for _, entry in ipairs(self.entries or {}) do
            if entry.category == "Favor" and entry.kind == "favor" then favorCounts[entry.extra] = (favorCounts[entry.extra] or 0) + 1 end
        end
        for name, b in pairs(f.favorOverview.cards) do
            b.sub:SetText((favorCounts[name] or 0) .. " Favor recipes")
        end
        local steps = {}
        for i, text in ipairs(source and source.CRATE_STEPS or {}) do steps[#steps + 1] = i .. ". " .. text end
        if #steps == 0 then steps[1] = "Favor guide data unavailable." end
        f.favorOverview.guide:SetText(table.concat(steps, "\n"))
        local faction = UnitFactionGroup and UnitFactionGroup("player")
        local hub = source and source.TRADE_HUBS and source.TRADE_HUBS[faction]
        f.favorOverview.hubTitle:SetText(hub and hub.name or "Supply representative")
        f.favorOverview.hubText:SetText(hub and ((hub.place or "") .. ", " .. (hub.zone or "") .. "\nTurn-in: " .. (hub.handin or "Unknown")) or "Location unavailable for this faction.")
        f.favorOverview.hubMap.hub = hub; f.favorOverview.hubMap:SetShown(hub and source.MAP_IDS and source.MAP_IDS[hub.zone] and true or false)
        for i, view in ipairs(f.favorOverview.rewardRows) do
            local reward = source and source.FAVOR_GUIDE and source.FAVOR_GUIDE[i]; view:SetShown(reward ~= nil)
            if reward then view.name:SetText(reward.tier or "Unknown"); view.note:SetText(reward.note or ""); view.level:SetText(reward.level or "?"); view.reward:SetText(reward.reward or "Unknown") end
        end
    end
    local helperMode = professions and self.profName and (self.profView == "skill" or self.profView == "profit")
    f.profHelper:SetShown(helperMode and true or false)
    if helperMode then
        f.list:Hide(); f.detail:Hide()
        local helper, source = f.profHelper, engineSource()
        local skillEngine = source and source.SkillUp
        local lines = {}
        local gold, scanStamp, scanStatus = _G.ForeverGold
        if gold and type(gold.R) == "function" then local ok, realm = pcall(gold.R); if ok and type(realm) == "table" then scanStamp = realm.lastScan end end
        if self.profScanStamp ~= scanStamp then self.profPlan, self.profProfit, self.profScanStamp = nil, nil, scanStamp end
        if gold and type(gold.ScanStatus) == "function" then local ok, status = pcall(gold.ScanStatus); if ok and type(status) == "string" then scanStatus = status end end
        helper.title:SetText(self.profName .. (self.profView == "skill" and "  •  Skill-up helper" or "  •  Profit"))
        for _, b in ipairs(helper.targets) do b:SetShown(self.profView == "skill") end
        if not skillEngine then helper.summary:SetText("The planning engine is unavailable. Check the Forever UI installation.")
        elseif self.profView == "skill" then
            if not self.profPlan then
                local current = 1
                for _, p in ipairs(playerProfessions()) do if p.name == self.profName then current = tonumber(p.skill) or 1 end end
                local target = self.profTarget or math.min(300, math.max(75, math.ceil((current + 1) / 75) * 75))
                local ok, plan, why, reached = withGoldPrices(skillEngine, skillEngine.Plan, self.profName, { from = current, to = target, ah = true, vendor = true, fresh = true })
                self.profPlan = { plan = ok and plan or nil, why = ok and why or "error", reached = reached, from = current, target = target }
            end
            local state, plan = self.profPlan, self.profPlan.plan
            local hasGold = _G.ForeverGold and type(_G.ForeverGold.AHPrice) == "function" and type(_G.ForeverGold.IsBuyout) == "function"
            local prices = hasGold and "Forever Gold's last buyouts, vendor prices and estimates" or type(skillEngine.HasAuctionator) == "function" and skillEngine.HasAuctionator() and "Auctionator and vendor prices" or "Vendor prices and estimates; auction prices unavailable"
            prices = prices .. "  •  skill-up chances are estimates"
            if plan then
                local cost = formatMoney(plan.cost)
                helper.summary:SetText("Skill " .. state.from .. " to " .. state.target .. "  •  Estimated cost " .. cost .. "\n" .. prices .. (plan.guessed and "  •  includes estimated prices" or "") .. (scanStatus and ("\n" .. scanStatus) or ""))
                for _, step in ipairs(plan.steps or {}) do
                    if step.kind == "craft" then lines[#lines + 1] = { text = tostring(step.from) .. "–" .. tostring(step.to) .. "   " .. tostring(step.r and step.r.n or "Unknown recipe") .. "   ×" .. tostring(step.safe or "?"), entry = step.r and self.byKey["recipe:" .. self.profName .. ":" .. tostring(step.r.s or step.r.n)] }
                    else lines[#lines + 1] = { text = "Train " .. tostring(step.rank or "next rank") .. " at skill " .. tostring(step.at or "?") } end
                end
                local materials = {}; for id, mat in pairs(plan.mats or {}) do materials[#materials + 1] = { id = id, data = mat } end
                table.sort(materials, function(a, b) return tostring(a.id) < tostring(b.id) end)
                if #materials > 0 then lines[#lines + 1] = { text = "Materials" } end
                for _, mat in ipairs(materials) do local entry = self.byKey["item:" .. tostring(mat.id)]; lines[#lines + 1] = { text = (entry and entry.name or ("Item " .. tostring(mat.id))) .. "  •  need " .. tostring(mat.data.need or 0) .. "  •  have " .. tostring(mat.data.have or 0), entry = entry } end
            else helper.summary:SetText("Could not build a route (" .. tostring(state.why or "no data") .. "). " .. prices) end
        else
            if not self.profProfit then local ok, list = withGoldPrices(skillEngine, skillEngine.Profit, self.profName, false); self.profProfit = ok and list or {} end
            local hasGold = _G.ForeverGold and type(_G.ForeverGold.AHPrice) == "function" and type(_G.ForeverGold.IsBuyout) == "function"
            helper.summary:SetText("Estimated profit after auction cut; " .. (hasGold and "uses Forever Gold's last buyouts, with Auctionator as a fallback." or type(skillEngine.HasAuctionator) == "function" and skillEngine.HasAuctionator() and "uses Auctionator prices." or "auction prices unavailable.") .. (scanStatus and ("\n" .. scanStatus) or ""))
            for _, result in ipairs(self.profProfit) do
                local value = formatMoney(result.profit)
                lines[#lines + 1] = { text = tostring(result.r and result.r.n or "Unknown") .. "  •  profit " .. value .. (result.guess and "  •  estimated materials" or ""), entry = result.r and self.byKey["recipe:" .. self.profName .. ":" .. tostring(result.r.s or result.r.n)] }
            end
        end
        self.helperOffset = math.max(0, math.min(self.helperOffset or 0, math.max(0, #lines - #helper.rows)))
        self.helperOffset = E.SmoothSync(self.smooth.helper, self.helperOffset, #lines)
        for i, b in ipairs(helper.rows) do local row = lines[i + self.helperOffset]; b.entry = row and row.entry; b:SetShown(row ~= nil); if row then b.text:SetText(row.text) end end
    end
    local showPlanner = armory and self.armorFilter == "planner"
    f.planner:SetShown(showPlanner)
    if showPlanner then
        f.list:Hide(); f.detail:Hide()
        local planner = f.planner
        self.plannerLastSlot, self.plannerLastSlotID = self.plannerLastSlot or "Head", self.plannerLastSlotID or 1
        local source = engineSource()
        local name, level = "Character", nil
        if UnitName then local ok, value = pcall(UnitName, "player"); if ok and value and not ns.Secret(value) then name = value end end
        if UnitLevel then local ok, value = pcall(UnitLevel, "player"); if ok and value and not ns.Secret(value) then level = value end end
        self.gearLevelMode = self.gearLevelMode or "player"
        local minGearLevel = (self.gearLevelMode == "player" or self.gearLevelMode == "all") and 1 or self.gearLevelMode == "custom" and self.gearMin or nil
        local maxGearLevel = self.gearLevelMode == "player" and level or self.gearLevelMode == "all" and 60 or self.gearLevelMode == "custom" and self.gearMax or nil
        planner.modelTitle:SetText(name .. (level and ("  •  Level " .. level) or ""))
        for _, b in ipairs(planner.slots) do
            local icon
            if GetInventoryItemTexture then local ok, value = pcall(GetInventoryItemTexture, "player", b.slotID); if ok and not ns.Secret(value) then icon = value end end
            b.icon:SetTexture(icon or "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. b.slotName:gsub(" ", ""))
            local options = enchantOptions(b.slotID)
            local current = equippedEnchant(b.slotID)
            b.enchant:SetShown(#options > 0)
            local currentOption
            if current then for _, option in ipairs(options) do if option.e == current then currentOption = option; break end end end
            b.enchant.icon:SetShown(current ~= nil)
            if current then b.enchant.icon:SetTexture(currentOption and enchantIcon(currentOption) or "Interface\\Icons\\Trade_Engraving") end
            b.enchant.text:SetText(current and "" or "+")
            b.enchant.fuiPanel.bright = self.plannerEnchant == b.slotID; ns.PaintPanel(b.enchant)
            b.fuiPanel.bright = (self.plannerSlotID or self.plannerLastSlotID) == b.slotID and not self.plannerEnchant; ns.PaintPanel(b)
        end
        self:LoadGearIndex()
        local candidates, waiting = {}, 0
        local query = tostring(self.query or ""):lower():match("^%s*(.-)%s*$")
        local mode = self.plannerMode or "suggested"
        local engine = source and source.GearValue
        local class, side
        if UnitClass then local ok, _, value = pcall(UnitClass, "player"); if ok then class = value end end
        if UnitFactionGroup then local ok, value = pcall(UnitFactionGroup, "player"); if ok then side = value == "Horde" and "H" or value == "Alliance" and "A" or nil end end
        local classBits = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
        local w = wishlist()
        local equipment = {}
        if GetInventoryItemLink then for slot = 1, 18 do local ok, link = pcall(GetInventoryItemLink, "player", slot); equipment[slot] = ok and type(link) == "string" and not ns.Secret(link) and link or "" end end
        local baseKey = table.concat({ query, mode, tostring(self.plannerSlot or ""), tostring(self.plannerSlotID or ""), tostring(self.plannerEnchant or ""), tostring(self.gearSource or ""), tostring(self.gearType or ""), tostring(minGearLevel or ""), tostring(maxGearLevel or ""), tostring(level or ""), tostring(class or ""), tostring(side or ""), tostring(engine and engine.Change), tostring(C_Item), table.concat(equipment, ";") }, "|")
        local cacheKey = baseKey .. "|" .. tostring(self.gearDataRevision or 0)
        local cacheable = mode == "suggested" and not self.plannerEnchant
        local cachedResult = cacheable and self.plannerCache and self.plannerCache.key == cacheKey and self.plannerCache.source == source and self.plannerCache.engine == engine and self.plannerCache
        -- Mid-scroll, newly loaded item data waits: the rows on screen stay
        -- and the list is worked out once, after scrolling stops.
        local scrollDeferred = false
        if cacheable and not cachedResult and C_Timer and C_Timer.After and GetTime and self.plannerScrollTime
            and GetTime() - self.plannerScrollTime < 0.75 then
            local shown = self.plannerShown
            if shown and shown.key == baseKey and shown.source == source and shown.engine == engine then
                schedulePlannerUpdate(); scrollDeferred = true
                cachedResult = { candidates = shown.candidates, waiting = shown.waiting or 0 }
            end
        end
        if cachedResult then
            candidates, waiting = cachedResult.candidates, cachedResult.waiting
        else
        if mode == "wishlist" then
            for key, saved in pairs(w) do
                local id = tonumber(key)
                if id and not self.byKey["item:" .. id] then local entry = item(id, type(saved) == "table" and saved.name or ("Item " .. id)); if entry and type(saved) == "table" then entry.data.slot = saved.slot end end
            end
        end
        if self.plannerEnchant then
            local options, itemID = enchantOptions(self.plannerEnchant)
            local worn = equippedEnchant(self.plannerEnchant)
            local currentFound = false
            for _, option in ipairs(options) do if option.e == worn then currentFound = true; break end end
            if worn and not currentFound and mode ~= "wishlist" then
                local info = source and source.ENCHANTS and source.ENCHANTS[worn]
                options[#options + 1] = { e = worn, n = info and info[1] or "Current enchant" }
            end
            local currentValue, total
            if engine and type(engine.EnchantValue) == "function" then
                if worn then local ok, value = pcall(engine.EnchantValue, worn, self.plannerEnchant, itemID); if ok and type(value) == "number" and not ns.Secret(value) then currentValue = value end else currentValue = 0 end
                if type(engine.Total) == "function" then local ok, value = pcall(engine.Total); if ok and type(value) == "number" and not ns.Secret(value) and value > 0 then total = value end end
            end
            for _, option in ipairs(options) do
                local key = enchantKey(option)
                if key and (mode ~= "wishlist" or wishHas(key)) and (query == "" or tostring(option.n or ""):lower():find(query, 1, true)) then
                    local percent
                    if currentValue and total and type(engine.EnchantValue) == "function" then
                        local ok, value = pcall(engine.EnchantValue, option.e, self.plannerEnchant, itemID)
                        if ok and type(value) == "number" and not ns.Secret(value) then percent = (value - currentValue) / total * 100 end
                    end
                    candidates[#candidates + 1] = { enchant = option, name = option.n or "Unknown enhancement", percent = percent, worn = option.e == worn }
                end
            end
        elseif mode == "wishlist" then
            local found = {}
            for _, option in ipairs(source and source.ENCHANT_OPTIONS or {}) do
                local key = enchantKey(option)
                if key and wishHas(key) and not found[key] and not self.plannerSlot and (query == "" or tostring(option.n or ""):lower():find(query, 1, true)) then
                    candidates[#candidates + 1] = { enchant = option, name = option.n or "Unknown enhancement" }; found[key] = true
                end
            end
            for key, saved in pairs(w) do
                if type(saved) == "table" and saved.enchant and saved.option and not found[key] and not self.plannerSlot
                    and (query == "" or tostring(saved.name or ""):lower():find(query, 1, true)) then
                    candidates[#candidates + 1] = { enchant = saved.option, name = saved.name or "Unknown enhancement" }
                end
            end
        end
        local requests = 0
        -- item facts (required level, filter matches) never change; scores
        -- last until the gear, weights, spec or level change (engine.gen)
        self.gearFacts = self.gearFacts or {}
        self.gearFilterMemo = self.gearFilterMemo or {}
        local gearFacts, gearFilterMemo = self.gearFacts, self.gearFilterMemo
        -- the engine rebuilds its weights lazily (and moves gen on) during the
        -- first score after a talent or level event: do that now, before the
        -- keys below are taken, not halfway through the list
        if engine and type(engine.SpecName) == "function" then pcall(engine.SpecName) end
        self.gearLastKnown = self.gearLastKnown or {}
        local lastKnown = self.gearLastKnown
        local scoreKey = table.concat({ tostring(engine), tostring(engine and engine.gen), tostring(level or ""), tostring(class or ""), table.concat(equipment, ";") }, "|")
        if not self.gearChangeMemo or self.gearChangeMemo.key ~= scoreKey then self.gearChangeMemo = { key = scoreKey, results = {} } end
        local changeMemo = self.gearChangeMemo.results
        local isCached = C_Item and C_Item.IsItemDataCachedByID
        local function itemCached(id)
            if not isCached then return true end
            local ok, value = pcall(isCached, id)
            return ok and value == true
        end
        local candidateEntries = self.entries
        if self.plannerEnchant then candidateEntries = {}
        elseif mode == "wishlist" then candidateEntries = {}; for key in pairs(w) do local id = tonumber(key); local entry = id and self.byKey["item:" .. id]; if entry then candidateEntries[#candidateEntries + 1] = entry end end end
        -- Each item's verdict (its row, or none) is kept while the filters,
        -- gear and weights stay the same. A refresh after item data arrives
        -- then only looks again at the items still waiting for data, instead
        -- of judging every item while you scroll.
        local verdictKey = cacheable and (baseKey .. "|" .. tostring(engine and engine.gen)) or nil
        if not verdictKey then self.plannerVerdicts = nil
        elseif not self.plannerVerdicts or self.plannerVerdicts.key ~= verdictKey then self.plannerVerdicts = { key = verdictKey, v = {} } end
        local verdicts = verdictKey and self.plannerVerdicts.v
        local pendingEntry, newRows = false, 0
        for _, entry in ipairs(candidateEntries) do
            local verdict = verdicts and verdicts[entry]
            if verdict ~= nil then
                if verdict then candidates[#candidates + 1] = verdict end
            elseif entry.kind == "item" and armoryEquipment(entry) and (mode == "wishlist" or not itemUnavailable(entry)) then
                local before = #candidates
                pendingEntry = false
                local gear = entry.data.gear
                local fits = not self.plannerSlot or entry.data.slot == self.plannerSlot
                if self.plannerSlotID and gear and source and source.GEAR_LOC_SLOTS then
                    fits = false; for _, slot in ipairs(source.GEAR_LOC_SLOTS[gear.loc] or {}) do if slot == self.plannerSlotID then fits = true; break end end
                end
                local matches = fits and (query == "" or entry.name:lower():find(query, 1, true))
                if matches and mode == "wishlist" and wishHas(entry.data.id) then
                    candidates[#candidates + 1] = { entry = entry, name = entry.name }
                elseif matches and mode ~= "wishlist" and query ~= "" and entry.data.reference and (not gear or not engine)
                    and entry.data.slot ~= "Non-equippable" and entry.data.slot ~= "" then
                    local required = itemRequiredLevel(entry.data.id) or tonumber(entry.data.reference.requiredLevel)
                    if required then required = math.max(1, required) end
                    local inRange = not required or (not minGearLevel or required >= minGearLevel) and (not maxGearLevel or required <= maxGearLevel)
                    if inRange and not self.gearSource and not self.gearType then candidates[#candidates + 1] = { entry = entry, name = entry.name } end
                elseif matches and mode ~= "wishlist" and gear and engine and type(engine.Change) == "function" and source and type(source.GearCanUse) == "function" then
                    local usable, canUse = pcall(source.GearCanUse, gear.loc, gear.cid, gear.sub)
                    local classOK = not gear.cls or gear.cls == 0 or class and classBits[class] and math.floor(gear.cls / classBits[class]) % 2 == 1
                    local sideOK = not gear.side or gear.side == "" or side and gear.side == side
                    local id = entry.data.id
                    local knownRequired = type(gear.req) == "number" and math.max(1, gear.req, tonumber(gear.qreq) or 0) or nil
                    local inKnownRange = not knownRequired or ((not minGearLevel or knownRequired >= minGearLevel) and (not maxGearLevel or knownRequired <= maxGearLevel))
                    if usable and canUse and classOK and sideOK and inKnownRange then
                        -- The client's item cache is small: loading the next 40
                        -- items pushes earlier ones out. Each item's answer is
                        -- kept once known, so a pushed-out item still counts and
                        -- the list settles instead of cycling between totals.
                        local facts = gearFacts[id]
                        if not facts and itemCached(id) then
                            local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
                            local required
                            if info then local ok, _, _, _, _, minLevel = pcall(info, id); if ok then required = tonumber(minLevel) end end
                            facts = { required = math.max(1, required or tonumber(gear.req) or tonumber(gear.lvl) or 0, tonumber(gear.qreq) or 0) }
                            gearFacts[id] = facts
                        end
                        local function needData()
                            pendingEntry = true
                            if not failedItemData[id] and C_Item and C_Item.RequestLoadItemDataByID then
                                if requests < 40 and requestItem(id) then requests = requests + 1 end
                                if not failedItemData[id] then waiting = waiting + 1 end
                            end
                        end
                        if not facts then
                            needData()
                        elseif (not minGearLevel or facts.required >= minGearLevel) and (not maxGearLevel or facts.required <= maxGearLevel) then
                            local filterKey = id .. "\1" .. tostring(self.gearSource) .. "\1" .. tostring(self.gearType)
                            local matchesFilter = gearFilterMemo[filterKey]
                            if matchesFilter == nil and itemCached(id) then
                                matchesFilter = gearMatchesFilters(gear, id, self.gearSource, self.gearType)
                                if matchesFilter ~= nil then gearFilterMemo[filterKey] = matchesFilter end
                            end
                            if matchesFilter == nil then
                                needData()
                            elseif matchesFilter then
                                if self.gearType == "profession" then candidates[#candidates + 1] = { entry = entry, name = entry.name }
                                else
                                    local result = changeMemo[id]
                                    if result == nil and itemCached(id) then
                                        local ok, kind, percent, comparedSlot = pcall(engine.Change, id)
                                        if not ok then result = false
                                        elseif kind then
                                            local rankValue
                                            if kind == "new" and percent == nil and type(engine.Upgrade) == "function" then
                                                local valid, value = pcall(engine.Upgrade, id)
                                                if valid and type(value) == "number" and not ns.Secret(value) then rankValue = value end
                                            end
                                            result = { kind = kind, percent = not ns.Secret(percent) and percent or nil, comparedSlot = not ns.Secret(comparedSlot) and comparedSlot or nil, rankValue = rankValue }
                                        end
                                        if result ~= nil then changeMemo[id] = result; lastKnown[id] = result end
                                    end
                                    -- A talent, level or gear event clears the engine's scores;
                                    -- an item the game has since dropped from its cache can't be
                                    -- scored again until it reloads. Its last score stands in
                                    -- meanwhile, so it doesn't vanish and come back.
                                    if result == nil then needData(); result = lastKnown[id] end
                                    if result and (result.kind == "up" or result.kind == "new") then
                                        candidates[#candidates + 1] = { entry = entry, name = entry.name, percent = result.percent, kind = result.kind, comparedSlot = result.comparedSlot, rankValue = result.rankValue }
                                    end
                                end
                            end
                        end
                    end
                end
                if verdicts and not pendingEntry then
                    local judged = candidates[before + 1] or false
                    verdicts[entry] = judged
                    -- a newly judged item (in or out) can change the list
                    newRows = newRows + 1
                end
            elseif verdicts then
                verdicts[entry] = false
            end
        end
        -- no new rows since the last time: the same sorted list
        local reuse = verdicts and newRows == 0 and self.plannerVerdicts.final
        if reuse then candidates = reuse else
        if not self.plannerEnchant then candidates = dedupeItems(candidates, function(c) return c.entry end) end
        table.sort(candidates, function(a, b)
            if self.plannerEnchant and a.worn ~= b.worn then return a.worn and true or false end
            if mode ~= "wishlist" and (a.percent or a.rankValue or 0) ~= (b.percent or b.rankValue or 0) then return (a.percent or a.rankValue or 0) > (b.percent or b.rankValue or 0) end
            -- lowercased once per row, not on every comparison
            local an, bn = a.fuiLower, b.fuiLower
            if not an then an = (a.name or ""):lower(); a.fuiLower = an end
            if not bn then bn = (b.name or ""):lower(); b.fuiLower = bn end
            if an == bn then return tostring(candidateIdentity(a) or "") < tostring(candidateIdentity(b) or "") end
            return an < bn
        end)
        if mode == "suggested" and not self.plannerSlot and not self.plannerEnchant and query == "" and self.gearType ~= "profession" and engine then
            candidates = topUpgradesPerSlot(candidates, source and source.GEAR_LOC_SLOTS)
        end
        if verdicts then self.plannerVerdicts.final = candidates end
        end
        if cacheable then self.plannerCache = { key = cacheKey, source = source, engine = engine, candidates = candidates, waiting = waiting } end
        end
        if cacheable and waiting > 0 then pollPendingItems() end
        local deferred = scrollDeferred
        if cacheable then
            local shown = self.plannerShown
            local sameView = shown and shown.key == baseKey and shown.source == source and shown.engine == engine
            if sameView and shown.candidates ~= candidates then
                local activeScroll = GetTime and self.plannerScrollTime and GetTime() - self.plannerScrollTime < 0.75
                if activeScroll and C_Timer and C_Timer.After then
                    schedulePlannerUpdate(); candidates, deferred = shown.candidates, true
                else
                    self.plannerOffset = anchoredOffset(shown.candidates, candidates, self.plannerOffset)
                end
            end
            if not deferred then self.plannerShown = { key = baseKey, source = source, engine = engine, candidates = candidates, waiting = waiting } end
        else self.plannerShown = nil end
        local isWishlist = mode == "wishlist"
        planner.filters:SetShown(not isWishlist); if isWishlist then planner.filterMenu:Hide() end
        if not planner.minLevel.HasFocus or not planner.minLevel:HasFocus() then planner.minLevel:SetText(minGearLevel and tostring(minGearLevel) or "") end
        if not planner.maxLevel.HasFocus or not planner.maxLevel:HasFocus() then planner.maxLevel:SetText(maxGearLevel and tostring(maxGearLevel) or "") end
        planner.myLevel.fuiPanel.bright = self.gearLevelMode == "player"; ns.PaintPanel(planner.myLevel)
        planner.allLevels.fuiPanel.bright = self.gearLevelMode == "all"; ns.PaintPanel(planner.allLevels)
        planner.filterButton.text:SetText((self.gearSource or self.gearType) and "Filters *" or "Filters")
        for key, b in pairs(planner.filterChoices) do local choice, category = key:match("^(.-):(.*)$"); b.fuiPanel.bright = category == "source" and choice == (self.gearSource or "all") or category == "type" and choice == (self.gearType or "all"); ns.PaintPanel(b) end
        planner.setSelector:SetShown(isWishlist); planner.setName:SetShown(isWishlist); planner.createSet:SetShown(isWishlist)
        planner.renameSet:SetShown(isWishlist and self.activeGearSet ~= nil); planner.deleteSet:SetShown(isWishlist and self.activeGearSet ~= nil)
        planner.deleteSet.text:SetText(self.deleteGearSetPending == self.activeGearSet and self.activeGearSet and "Confirm" or "Delete")
        planner.setSelector.text:SetText(self.activeGearSet or "Wishlist"); planner.setSelector.text:SetWidth(104)
        planner.resultsInfo:ClearAllPoints(); planner.resultsInfo:SetPoint("TOPLEFT", 10, -66)
        local groupedOverview = mode == "suggested" and not self.plannerSlot and not self.plannerEnchant and query == "" and self.gearType ~= "profession" and engine ~= nil
        -- Positions are in pixels (smooth scrolling); plannerOffset stays the
        -- index of the top row for everything else (filters reset it to 0,
        -- new data keeps the top item in place). When something else moved
        -- it, the list starts from that row.
        local layout = E.PlannerLayout(candidates, groupedOverview)
        local maxPixel = math.max(0, layout.total - E.PLANNER_VIEW)
        local wanted = math.max(0, math.floor(self.plannerOffset or 0))
        if wanted ~= self.plannerShownOffset then
            self.plannerPixel, self.plannerTarget = layout.y[wanted + 1] or (wanted > 0 and maxPixel or 0), nil
        elseif wanted == 0 and self.plannerShownList ~= candidates and not self.plannerTarget then
            self.plannerPixel = 0 -- a different list (a filter): from its very top
        end
        self.plannerPixel = math.max(0, math.min(self.plannerPixel or 0, maxPixel))
        if self.plannerTarget then self.plannerTarget = math.max(0, math.min(self.plannerTarget, maxPixel)) end
        local page, first = E.PlannerPixelPage(candidates, layout, self.plannerPixel)
        self.plannerOffset = #candidates > 0 and first - 1 or 0
        self.plannerShownOffset, self.plannerShownList = self.plannerOffset, candidates
        ns.UpdateListScrollbar(planner.scrollbar, math.floor(self.plannerPixel + 0.5), math.floor(maxPixel + 0.5))
        planner.suggested.fuiPanel.bright = mode ~= "wishlist"; ns.PaintPanel(planner.suggested)
        planner.wishlist.fuiPanel.bright = mode == "wishlist"; ns.PaintPanel(planner.wishlist)
        planner.allSlots.fuiPanel.bright = not self.plannerSlot and not self.plannerEnchant; ns.PaintPanel(planner.allSlots)
        planner.allSlots.check:SetShown(planner.allSlots.fuiPanel.bright)
        planner.resultsInfo:SetText((self.plannerEnchant and ("Enhancements: " .. tostring(self.plannerSlot)) or self.plannerSlot or "All slots") .. "  •  " .. (mode == "wishlist" and (#candidates .. " saved items")
            or self.plannerEnchant and (#candidates .. " compatible options")
            or not engine and (query ~= "" and (#candidates .. " reference matches (not scored)") or "Item data is loading or no comparable gear is available") or (#candidates .. (self.gearType == "profession" and " profession items" or " possible upgrades (estimates)") .. (waiting > 0 and "  •  item data loading" or deferred and "  •  updating after scrolling" or ""))))
        for i, b in ipairs(planner.rows) do
            local visible = page[i]; local candidate = visible and visible.candidate; local entry = candidate and candidate.entry
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", planner.listClip, "TOPLEFT", 10, -(visible and visible.y or 0)); b:SetHeight(46); b:SetWidth(446)
            b.groupLabel:SetShown(visible and visible.heading and true or false); b.groupLine:SetShown(visible and visible.heading and true or false)
            if visible and visible.heading then b.groupLabel:SetText(plannerSlotNames[candidate.overviewSlot] or (entry and entry.data.slot) or "Other") end
            local option = candidate and candidate.enchant
            b.entry, b.enchant = entry, option; b:SetShown(candidate ~= nil); b.preview:SetShown(entry ~= nil)
            b.star.removeCurrent = isWishlist
            b.star:SetWidth(isWishlist and 60 or 25); b.star.text:SetText(isWishlist and "Remove" or "+")
            b.text:SetWidth(isWishlist and 245 or 310); b.sub:SetWidth(isWishlist and 245 or 310); b.enchantInfo:SetWidth(isWishlist and 245 or 350)
            local gearInfo = entry and entry.data.gear; b.questMark:SetShown(gearInfo and gearInfo.qid and true or false)
            b.enchantInfo:SetShown(option ~= nil)
            b.sub:ClearAllPoints(); b.sub:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 42, option and 18 or 5)
            if option then
                b.icon:SetTexture(enchantIcon(option)); b.text:SetText(option.n or "Unknown enhancement"); b.text:SetTextColor(ns.C.text[1], ns.C.text[2], ns.C.text[3])
                local effect = source and source.ENCHANTS and source.ENCHANTS[option.e]
                local label = effect and effect[1] or option.src or "Effect not recorded"
                if option.p then label = label .. "  •  " .. option.p .. (option.req and (" " .. option.req) or "") end
                if option.st == 0 then label = label .. "  •  unavailable" end
                if candidate.worn then label = label .. "  •  equipped" elseif candidate.percent then label = label .. string.format("  •  %+.1f%%", candidate.percent) end
                local details = enchantDetails(option)
                local known = #details.characters > 0 and table.concat(details.characters, ", ") or details.goldAvailable and "not recorded" or "data unavailable"
                b.enchantInfo:SetText("Known: " .. known .. "  •  " .. details.sources[1])
                b.sub:SetText(label); b.star:SetShown((isWishlist or not candidate.worn) and enchantKey(option) ~= nil)
            elseif entry then
                entryIcon(b.icon, entry); b.text:SetText(entry.name); b.text:SetTextColor(itemQuality(entry))
                local gear = entry.data.gear
                if gear and gear.qid then local width = b.text.GetStringWidth and b.text:GetStringWidth() or 0; b.questMark:ClearAllPoints(); b.questMark:SetPoint("TOPLEFT", b, "TOPLEFT", math.min(42 + (tonumber(width) or 0) + 4, 330), -5) end
                local required = itemRequiredLevel(entry.data.id) or (entry.data.reference and tonumber(entry.data.reference.requiredLevel))
                local availability = itemAvailability(entry)
                b.sub:SetText((entry.data.slot or "Unknown slot") .. (required and required > 0 and ("  •  Requires level " .. required) or not required and "  •  Level unknown" or "") .. availabilityTag(availability) .. (gear and gear.src and ("  •  " .. gear.src) or "")
                    .. (candidate.percent and string.format("  •  +%.1f%%", candidate.percent) or candidate.kind == "new" and "  •  empty slot" or ""))
                b.star:SetShown(true)
            end
        end
    end
end

function E:OpenEntry(entry, preferredCategory)
    if entry and entry.kind == "item" then self:LoadGearIndex(); self:LinkItemSources(entry) end
    if self.window then self.history[#self.history + 1] = { entry = self.current, selected = self.selected, profFilter = self.profFilter, profName = self.profName,
        petFilter = self.petFilter, petFamily = self.petFamily, instanceFilter = self.instanceFilter, levelGroup = self.levelGroup, raidSize = self.raidSize, profView = self.profView,
        dungeonView = self.dungeonView, bossKey = self.boss and self.boss.key, bossLootOffset = self.bossLootOffset,
        repSide = self.repSide, armorFilter = self.armorFilter, armorType = self.armorType,
        armorSlot = self.armorSlot, setGroup = self.setGroup, query = self.query,
        offset = self.offset, detailPage = self.detailPage, linkPage = self.linkPage, plannerOffset = self.plannerOffset, plannerPixel = self.plannerPixel,
        reagentOffset = self.reagentOffset, setPieceOffset = self.setPieceOffset, repOffset = self.repOffset, bookOffset = self.bookOffset, itemLinksView = self.itemLinksView } end
    if entry.kind == "setGroup" or entry.kind == "armorType" or entry.kind == "armorSlot" or entry.kind == "repGroup" then
        if entry.kind == "setGroup" then self.setGroup = entry.data.group
        elseif entry.kind == "armorType" then self.armorType = entry.data.armorType
        elseif entry.kind == "repGroup" then self.repSide = entry.data.side
        else self.armorSlot = entry.data.slot end
        self.current, self.offset = nil, 0; self:Render(); return
    end
    local isProfession = entry.category == "Professions" or entry.category == "Camping" or entry.category == "Favor"
    local keepItems = self.selected == "Items" and entry.kind == "item"
    local targetCategory = entry.kind == "item" and preferredCategory == "Items" and "Items" or keepItems and "Items" or isProfession and "Professions" or entry.category
    local keepOffset = targetCategory == self.selected
    self.itemLinksView = "sources"
    self.current, self.selected, self.offset, self.detailPage, self.linkPage, self.dungeonView = entry, targetCategory, keepOffset and self.offset or 0, 1, 1, "Overview"
    if isProfession then
        self.profName = entry.kind == "profession" and entry.name or entry.extra
        self.profFilter = entry.kind == "profession" and "Professions" or entry.category
        self.profView = entry.kind == "favor" and "favor" or "recipes"
    elseif entry.kind == "family" then
        self.petFamily, self.petFilter = entry.name, "family"
    elseif entry.kind == "ability" then
        self.petFilter = "ability"
    elseif entry.kind == "tame" and entry.data.family then
        self.petFamily, self.petFilter = entry.data.family, self.petFilter == "rare" and "rare" or "tame"
    elseif entry.kind == "dungeon" then
        self.instanceFilter = entry.data.raid and "raid" or "dungeon"
    elseif entry.kind == "faction" then
        self.repSide = entry.data.side == "H" and "Horde" or entry.data.side == "A" and "Alliance" or "Both factions"
    elseif entry.kind == "set" then
        self.armorFilter, self.setGroup, self.armorType, self.armorSlot, self.setPieceOffset = "set", entry.data.g or "Other", nil, nil, 0
    elseif entry.kind == "item" then
        self.armorFilter, self.setGroup, self.armorType, self.armorSlot = "item", nil, nil, nil
    end
    if not keepOffset then self.query = entry.kind == "item" and entry.name or "" end
    if self.window.search:GetText() ~= self.query then self.window.search:SetText(self.query) end
    self:Render()
end
function E:Back()
    local last = table.remove(self.history)
    if not last then return end
    self.current, self.selected = last.entry, last.selected
    self.profFilter = last.profFilter or "Professions"
    self.profView = last.profView or "recipes"
    self.profName, self.petFamily, self.petFilter = last.profName, last.petFamily, last.petFilter or "family"
    self.instanceFilter, self.levelGroup, self.raidSize, self.repSide = last.instanceFilter or "dungeon", last.levelGroup, last.raidSize, last.repSide
    self.dungeonView, self.boss, self.bossLootOffset = last.dungeonView or "Overview", last.bossKey and self.byKey[last.bossKey] or nil, last.bossLootOffset or 0
    self.armorFilter, self.armorType, self.armorSlot, self.setGroup = last.armorFilter or "set", last.armorType, last.armorSlot, last.setGroup
    self.query = last.query
    if self.window.search:GetText() ~= self.query then self.window.search:SetText(self.query) end
    self.offset, self.detailPage, self.linkPage = last.offset, last.detailPage or 1, last.linkPage or 1
    self.plannerOffset, self.plannerPixel, self.plannerTarget = last.plannerOffset, last.plannerPixel, nil
    self.plannerShownOffset = last.plannerOffset
    self.reagentOffset, self.setPieceOffset, self.repOffset, self.bookOffset = last.reagentOffset, last.setPieceOffset, last.repOffset, last.bookOffset
    self.itemLinksView = last.itemLinksView or "sources"
    self:Render()
end
-- The reference data only changes when a source appears or goes (OneForAll
-- installed or removed): build the ~40,000 entries once, not on every open.
local function dataSignature()
    return tostring(referenceSource()) .. "|" .. tostring(ns.ReferenceData) .. "|" .. tostring(ns.IndependentReference) .. "|" .. tostring(_G.OneForAll) .. "|" .. tostring(_G.ForeverGold)
end
-- A new auction scan only adds the items it newly saw (E:MergeNewAuctionItems).
local function auctionSignature()
    local gold = _G.ForeverGold
    local stamp = nil
    if type(gold) == "table" and type(gold.R) == "function" then local ok, realm = pcall(gold.R); if ok and type(realm) == "table" then stamp = realm.lastScan end end
    local scan = type(gold) == "table" and type(gold.scan) == "table" and gold.scan.lastResult or nil
    local scanStamp = type(scan) == "table" and scan.at or nil
    return tostring(stamp) .. "|" .. tostring(scanStamp)
end
-- Brings the entries up to date; true when anything changed.
function E:SyncData()
    local signature, auction = dataSignature(), auctionSignature()
    if self.dataSignature ~= signature or not next(self.byKey) then
        self:RefreshData()
        self.dataSignature, self.auctionStamp = signature, auction
        return true
    end
    if self.auctionStamp == auction then return false end
    self.auctionStamp = auction
    -- prices moved: lists built from them are stale
    self.plannerCache, self.plannerShown = nil, nil
    self:MergeNewAuctionItems()
    self.entryRevision = (self.entryRevision or 0) + 1
    return true
end
function E:ListenForPrices()
    local gold = _G.ForeverGold
    if type(gold) ~= "table" or type(gold.Listen) ~= "function" or self.goldListener == gold then return end
    self.goldListener = gold
    -- closed: the next open catches up instead
    pcall(gold.Listen, "PRICES_UPDATED", function()
        if E.window and E.window:IsShown() and E:SyncData() then E:Render() end
    end)
end
-- How long the last open and warm-up took, in ms (ForeverUIDB.encyclopediaTimings),
-- to find what is slow in game without guessing.
local function noteTimings(name, timings)
    E.timings = E.timings or {}; E.timings[name] = timings
    if type(ForeverUIDB) == "table" then ForeverUIDB.encyclopediaTimings = E.timings end
end
local function clock() return type(debugprofilestop) == "function" and debugprofilestop() or 0 end
-- Build the entries and the window behind the loading screen: the first open
-- is then instant instead of a half-second freeze. Later loading screens only
-- catch up on new auction scans.
function E:Warm()
    local t0 = clock()
    self:SyncData()
    local t1 = clock()
    -- the gear index the Items and Armory pages read (otherwise loaded on
    -- their first visit, a visible hitch)
    if self.sourceAvailable and not self.gearLoaded and referenceSource() then self:LoadGearIndex() end
    -- and the Items page list (one row per distinct item out of ~40,000)
    -- and where each item comes from (read when an item is opened)
    if self.sourceAvailable then self:ItemCatalog(self:Find("Armory", self.query)); sourceIndex() end
    local t2 = clock()
    if self.sourceAvailable and not self.window and not (InCombatLockdown and InCombatLockdown()) then self.window = build() end
    noteTimings("warm", { data = t1 - t0, gear = t2 - t1, build = clock() - t2 })
end
ns.On("PLAYER_ENTERING_WORLD", function() E:ListenForPrices(); E:Warm() end)
-- Any page that takes longer than a frame to draw is noted with its time
-- (ForeverUIDB.encyclopediaTimings.slow), so a stutter in game can be traced.
do
    local render = E.Render
    function E:Render(...)
        local t0 = clock()
        local a, b, c = render(self, ...)
        local ms = clock() - t0
        if ms > 16 then
            local page = tostring(self.selected) .. (self.current and (" / " .. tostring(self.current.kind)) or "")
            local slow = self.timings and self.timings.slow or {}
            local last = slow[page]
            slow[page] = { ms = math.floor(ms + 0.5), worst = math.floor(math.max(ms, last and last.worst or 0) + 0.5), count = (last and last.count or 0) + 1 }
            noteTimings("slow", slow)
        end
        return a, b, c
    end
end
function ns.OpenEncyclopedia()
    E:ListenForPrices()
    local t0 = clock()
    E:SyncData()
    local t1 = clock()
    if not E.window then E.window = build() end
    local t2 = clock()
    E:Render(); E.window:Show()
    noteTimings("open", { data = t1 - t0, build = t2 - t1, render = clock() - t2 })
end

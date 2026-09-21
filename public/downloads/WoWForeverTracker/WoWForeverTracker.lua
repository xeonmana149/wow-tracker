-- WoW Forever Tracker companion addon
--
-- Design notes (read these before "fixing" something that looks odd):
--  * An earlier version of this comment claimed SavedVariables don't
--    persist on this client - that was WRONG, and was corrected after
--    /wft savetest confirmed a value written before a full logout was still
--    there after logging back in (2026-09-20). SavedVariables DO save to
--    disk here, same as any normal client, just only on logout or /reload
--    (never continuously while playing) - see the "Automatic periodic
--    sync" section below for what that enables.
--  * The client throws an error and aborts the whole file if you register an
--    event name it doesn't know, so every RegisterEvent call is wrapped in
--    pcall.
--  * A lot of "classic" API (GetItemInfo, GetSpellInfo, GetTalentInfo, etc.)
--    does not exist on this client; the beta runs on the retail API surface
--    instead. Every single game-function call in this file goes through
--    safeGet()/pcall so a missing or renamed function just quietly produces
--    no data for that field instead of breaking the addon.
--  * The talent/legacy trait reader (collectTraits) is EXPERIMENTAL. The
--    beta's trait tree/node IDs aren't publicly documented yet, so it dumps
--    raw node IDs and ranks rather than guessing talent names. Run
--    "/wft traits" and send the printed output back if it looks empty or
--    wrong so the mapping can be improved.

local ADDON_NAME = ...

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------

-- Calls a global function by name through pcall. Returns nil (and prints
-- nothing) if the function doesn't exist or errors, so every collector below
-- degrades gracefully instead of breaking the whole export.
local function safeGet(fnName, ...)
    local fn = _G[fnName]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, r1, r2, r3, r4, r5, r6 = pcall(fn, ...)
    if not ok then
        return nil
    end
    return r1, r2, r3, r4, r5, r6
end

-- Same idea but for a function value you already have in hand (e.g. one
-- pulled out of a C_* table), rather than a global name.
local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        return false, nil
    end
    local ok, r1 = pcall(fn, ...)
    if not ok then
        return false, nil
    end
    return true, r1
end

-- Tries a combat-rating style function under its classic global name first,
-- then falls back to the equivalent C_PaperDollInfo function if the client
-- moved it there instead. Some Forever builds may expose either.
local function getCombatChance(kind)
    local v = safeGet("Get" .. kind .. "Chance")
    if v ~= nil then
        return v
    end
    local PD = _G.C_PaperDollInfo
    if PD and type(PD["Get" .. kind .. "Chance"]) == "function" then
        local ok, r = safeCall(PD["Get" .. kind .. "Chance"])
        if ok then
            return r
        end
    end
    return nil
end

----------------------------------------------------------------------
-- Minimal JSON encoder (WoW addons can't require external Lua libraries,
-- so this is hand-rolled and deliberately simple).
----------------------------------------------------------------------

local function jsonEscape(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return s
end

local function isArrayTable(t)
    local n = 0
    for k in pairs(t) do
        n = n + 1
        if type(k) ~= "number" then
            return false
        end
    end
    return n == #t
end

local jsonEncode
jsonEncode = function(v)
    local vt = type(v)
    if v == nil then
        return "null"
    elseif vt == "boolean" then
        return v and "true" or "false"
    elseif vt == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            return "0"
        end
        return tostring(v)
    elseif vt == "string" then
        return '"' .. jsonEscape(v) .. '"'
    elseif vt == "table" then
        if isArrayTable(v) then
            local parts = {}
            for i = 1, #v do
                parts[i] = jsonEncode(v[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            local n = 0
            for k, val in pairs(v) do
                n = n + 1
                parts[n] = '"' .. jsonEscape(tostring(k)) .. '":' .. jsonEncode(val)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        return "null"
    end
end

----------------------------------------------------------------------
-- Data collectors
----------------------------------------------------------------------

local function collectBasic()
    local data = {}
    data.name = safeGet("UnitName", "player")
    local full = safeGet("UnitFullName", "player")
    if full then
        data.fullName = full
    end
    data.race = safeGet("UnitRace", "player")
    data.class = safeGet("UnitClass", "player")
    local faction = safeGet("UnitFactionGroup", "player")
    data.faction = faction
    data.level = safeGet("UnitLevel", "player")
    data.guild = safeGet("GetGuildInfo", "player")
    data.money = safeGet("GetMoney")
    data.realm = safeGet("GetRealmName")
    return data
end

local STAT_NAMES = { [1] = "strength", [2] = "agility", [3] = "stamina", [4] = "intellect", [5] = "spirit" }

local function collectStats()
    local stats = {}

    for statID, name in pairs(STAT_NAMES) do
        local base, effective = safeGet("UnitStat", "player", statID)
        if effective ~= nil then
            stats[name] = effective
        elseif base ~= nil then
            stats[name] = base
        end
    end

    local apBase, apPos, apNeg = safeGet("UnitAttackPower", "player")
    if apBase ~= nil then
        stats.attackPower = apBase + (apPos or 0) + (apNeg or 0)
    end

    stats.maxHealth = safeGet("UnitHealthMax", "player")
    stats.maxMana = safeGet("UnitPowerMax", "player", 0)

    local speed = safeGet("GetUnitSpeed", "player")
    if speed ~= nil then
        stats.moveSpeedYardsPerSec = speed
        -- 7 yards/sec is the standard 100% run speed baseline.
        stats.moveSpeedPercent = math.floor((speed / 7) * 100 + 0.5)
    end

    local armorBase, armorEffective = safeGet("UnitArmor", "player")
    stats.armor = armorEffective or armorBase

    local defBase, defEffective = safeGet("UnitDefense", "player")
    stats.defense = defEffective or defBase

    -- UnitDamage already accounts for your currently equipped weapon and
    -- any buffs, so this is the same min/max shown on the character panel.
    local dmgMin, dmgMax = safeGet("UnitDamage", "player")
    if dmgMin ~= nil then
        stats.mainHandMin = dmgMin
        stats.mainHandMax = dmgMax
    end

    stats.critChancePercent = getCombatChance("Crit")
    stats.dodgeChancePercent = getCombatChance("Dodge")
    stats.parryChancePercent = getCombatChance("Parry")
    stats.blockChancePercent = getCombatChance("Block")

    -- Hit chance vs. an equal-level target and vs. a boss-level target isn't
    -- exposed anywhere as a single number pre-level-cap; it's what shows up
    -- in the weapon-skill tooltip in game. We're not attempting to derive it
    -- here - keep typing those two numbers into the website by hand, per the
    -- earlier chat about this exact limitation.

    -- Resistances. Classic-era school indices are 0 Physical(armor already
    -- captured above), 1 Holy, 2 Fire, 3 Nature, 4 Frost, 5 Shadow, 6 Arcane.
    -- Forever's beta may not match this exactly, so this exports every index
    -- 0-6 raw and labels the ones we're fairly confident about; double check
    -- the labeled ones against your character sheet the first time you use
    -- this, and fix the mapping in this file's RESIST_SCHOOLS table if any
    -- are wrong for your build.
    local RESIST_SCHOOLS = { [1] = "holy", [2] = "fire", [3] = "nature", [4] = "frost", [5] = "shadow", [6] = "arcane" }
    local resist = {}
    for i = 0, 6 do
        local v = safeGet("GetResistance", i)
        if v == nil then
            v = safeGet("UnitResistance", "player", i)
        end
        if v ~= nil then
            local label = RESIST_SCHOOLS[i]
            if label then
                resist[label] = v
            end
            resist["raw_" .. i] = v
        end
    end
    stats.resistances = resist

    return stats
end

local function collectProfessions()
    local profs = {}
    -- On a normal client GetProfessions() returns exactly 5 values in a
    -- fixed order (primary1, primary2, archaeology, fishing, cooking).
    -- WoW Forever doesn't have Archaeology at all, but does have First
    -- Aid (which a normal client doesn't return from this call at all),
    -- so this server's build almost certainly doesn't match that fixed
    -- layout. Rather than name fixed slots and risk dropping whichever
    -- one doesn't match - the same bug that silently dropped Cooking -
    -- every non-nil value this call returns, in whatever position, is
    -- treated as a real profession index. safeGet reads up to 6 return
    -- values, one more than a normal client ever uses here, to leave
    -- room for an extra slot like First Aid.
    local r1, r2, r3, r4, r5, r6 = safeGet("GetProfessions")
    local indices = {}
    if r1 then table.insert(indices, r1) end
    if r2 then table.insert(indices, r2) end
    if r3 then table.insert(indices, r3) end
    if r4 then table.insert(indices, r4) end
    if r5 then table.insert(indices, r5) end
    if r6 then table.insert(indices, r6) end
    for _, idx in ipairs(indices) do
        local name, _icon, skillLevel, maxSkillLevel = safeGet("GetProfessionInfo", idx)
        if name then
            table.insert(profs, { name = name, skill = skillLevel, maxSkill = maxSkillLevel })
        end
    end
    return profs
end

local SLOT_NAMES = {
    [1] = "head", [2] = "neck", [3] = "shoulder", [4] = "shirt", [5] = "chest",
    [6] = "waist", [7] = "legs", [8] = "feet", [9] = "wrist", [10] = "hands",
    [11] = "finger1", [12] = "finger2", [13] = "trinket1", [14] = "trinket2",
    [15] = "back", [16] = "mainHand", [17] = "offHand", [18] = "ranged", [19] = "tabard",
}

-- The item link's own bracketed text is the item name (color-coded links
-- look like "|cffffffff|Hitem:...|h[Item Name]|h|r"), which is readable
-- without GetItemInfo.
local function extractItemName(link)
    if not link then
        return nil
    end
    local name = link:match("%[(.-)%]")
    return name or link
end

-- The link's own color code tells us the item's real quality color
-- (grey/white/green/blue/purple/orange), e.g. "|cff1eff00|Hitem:...".
-- The code is 8 hex digits (alpha + RRGGBB) - we only want the RRGGBB part.
local function extractItemColor(link)
    if not link then
        return nil
    end
    local argb = link:match("|c(%x%x%x%x%x%x%x%x)")
    return argb and argb:sub(3) or nil
end

-- A hidden tooltip we reuse to read each equipped item's real tooltip text.
-- GetItemInfo doesn't work on this client, but SetInventoryItem still fills
-- in a normal tooltip with server-supplied data (armor, stat bonuses,
-- durability, etc.), so scanning its font strings gets us real item stats
-- without needing the missing item-cache API.
local scanTip
do
    local ok, tip = pcall(CreateFrame, "GameTooltip", "WFTScanTooltip", nil, "GameTooltipTemplate")
    if ok then
        scanTip = tip
    end
end

-- Tooltip text can contain WoW's inline markup for textures/atlases/colors
-- (things like "|A:coin-copper:14:14:2:0|a" on the Sell Price line, or
-- "|cffffffff...|r" for colored text). GetText() returns that markup as
-- literal characters instead of rendering it, so strip it before exporting.
local function stripMarkup(text)
    if not text then
        return text
    end
    -- The coin icons on the Sell Price line are worth keeping as a
    -- recognizable marker instead of just deleting - the website turns
    -- {gold}/{silver}/{copper} into a real coin icon.
    text = text:gsub("|A:coin%-gold:[^|]*|a", "{gold}")
    text = text:gsub("|A:coin%-silver:[^|]*|a", "{silver}")
    text = text:gsub("|A:coin%-copper:[^|]*|a", "{copper}")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

-- Returns the tooltip's text lines, plus the item's quality color read
-- straight off the first line's font color. This beta client's item links
-- don't carry the usual "|cffRRGGBB" color code (GetInventoryItemLink
-- returns a bare "[Item Name]" with nothing else), but the tooltip's name
-- line is still colored correctly by the client, so reading its actual
-- rendered color works where parsing the link string doesn't.
local function scanSlotTooltip(slotID)
    if not scanTip then
        return {}, nil
    end
    local lines = {}
    local qualityColor
    local ok = pcall(function()
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
        scanTip:ClearLines()
        scanTip:SetInventoryItem("player", slotID)
    end)
    if not ok then
        return lines, nil
    end
    for i = 1, 30 do
        local left = _G["WFTScanTooltipTextLeft" .. i]
        if not left then
            break
        end
        if i == 1 then
            local okColor, r, g, b = pcall(left.GetTextColor, left)
            if okColor and r then
                qualityColor = string.format(
                    "%02x%02x%02x",
                    math.floor(r * 255 + 0.5),
                    math.floor(g * 255 + 0.5),
                    math.floor(b * 255 + 0.5)
                )
            end
        end
        local leftText = stripMarkup(left:GetText())
        if leftText and leftText ~= "" then
            local right = _G["WFTScanTooltipTextRight" .. i]
            local rightText = stripMarkup(right and right:GetText())
            if rightText and rightText ~= "" and rightText ~= leftText then
                table.insert(lines, leftText .. "  " .. rightText)
            else
                table.insert(lines, leftText)
            end
        end
    end
    return lines, qualityColor
end

local function collectGear()
    local gear = {}
    for slotID, slotName in pairs(SLOT_NAMES) do
        local link = safeGet("GetInventoryItemLink", "player", slotID)
        if link then
            local tooltip, qualityColor = scanSlotTooltip(slotID)
            -- GetInventoryItemTexture gives us the item's real icon as a
            -- numeric Blizzard file ID (confirmed via testing - it does NOT
            -- need the missing item-cache API). The website resolves this
            -- ID to an actual icon image using a bundled fileID->name
            -- lookup table, the same one community WoW tools use.
            local icon = safeGet("GetInventoryItemTexture", "player", slotID)
            gear[slotName] = {
                link = link,
                name = extractItemName(link),
                color = qualityColor or extractItemColor(link),
                tooltip = #tooltip > 0 and tooltip or nil,
                icon = icon,
            }
        end
    end
    return gear
end

-- Resolves a talent's real name straight from the game, given the spellID
-- its entry points to. This is server-truth (the same name shown on the
-- actual tooltip), not a guess - it needs no lookup table at all. Tries the
-- retail C_Spell API first (this client's primary surface), then falls
-- back to the older global GetSpellInfo in case a build exposes that
-- instead.
local function getSpellName(spellID)
    if not spellID then
        return nil
    end
    local CSpell = _G.C_Spell
    if CSpell and type(CSpell.GetSpellInfo) == "function" then
        local ok, info = safeCall(CSpell.GetSpellInfo, spellID)
        if ok and info and info.name then
            return info.name
        end
    end
    local name = safeGet("GetSpellInfo", spellID)
    if name then
        return name
    end
    return nil
end

-- EXPERIMENTAL: talents and Legacy both run on the retail trait system
-- (C_Traits) on this client. Each node's chosen entry points at a real
-- Blizzard spellID, which getSpellName() above resolves to the actual name
-- shown in game - so unlike earlier versions of this addon, a talent's NAME
-- no longer needs manual confirmation at all.
--
-- What still needs figuring out per class is which of the three old-style
-- trees (e.g. a Paladin's Holy/Protection/Retribution) a node belongs to,
-- since this client draws all three side by side on one merged canvas and
-- only exposes a single treeID for the lot. /wft treedump was used to map
-- out where each tree's nodes sit on that canvas (by posX), and confirmed
-- points anchor the bands below. TREE_BANDS only ever grows from a real
-- /wft treedump plus a confirmed talent in that range - never a guess - and
-- a class with no entry here just reports nodes without a tree (same as
-- "unknown" always has), so nothing gets written to the wrong tree.
-- Every class below was mapped the same way, 2026-09-20: a /wft treedump
-- (now with real talent names resolved per node - see collectTreeDump)
-- was checked node-by-node against known classic talent names for that
-- class (e.g. "Bloodthirst"/"Cruelty" only ever being Warrior Fury
-- talents), not against spellID numbers alone - spellID-based guessing is
-- exactly what mislabeled a Warrior's Fury talent as Rogue Combat
-- earlier, since this server reuses spellIDs for its own custom talents.
-- Every class's three trees landed in the same even-thirds posX split
-- (0-4000 / 4000-8000 / 8000-999999) and in the same left-to-right order
-- as their real in-game tab order, which is what every band below is
-- checked against.
local TREE_BANDS = {
    Paladin = {
        -- All three confirmed by name from a friend's /wft treedump,
        -- 2026-09-20 (52 nodes): Holy Shock/Holy Power/Illumination in
        -- the low band, Reckoning/Holy Shield/Redoubt in the mid band,
        -- Seal of Command/Vindication/Conviction in the high band.
        { min = 0, max = 4000, tree = "Holy" }, -- anchor: Improved Holy Strike, posX 1020 (learned, 2/2)
        { min = 4000, max = 8000, tree = "Protection" },
        { min = 8000, max = 999999, tree = "Retribution" }, -- anchor: Deflection, posX 9680 (learned, 3/5)
    },
    Warrior = {
        -- All three confirmed by name from a friend's /wft treedump,
        -- 2026-09-20 (54 nodes): Mortal Strike/Deep Wounds/Sweeping
        -- Strikes in the low band, Bloodthirst/Death Wish/Enrage in the
        -- mid band, Shield Slam/Last Stand/Defiance in the high band.
        { min = 0, max = 4000, tree = "Arms" },
        { min = 4000, max = 8000, tree = "Fury" }, -- anchor: Cruelty, posX 6220 (learned, 5/5)
        { min = 8000, max = 999999, tree = "Protection" },
    },
    Shaman = {
        -- Confirmed by name from a friend's /wft treedump, 2026-09-20 (48
        -- nodes): Lava Burst/Elemental Fury/Convection in the low band,
        -- Stormstrike/Flurry/Maelstrom Weapon in the mid band, Riptide/
        -- Mana Tide Totem/Healing Way in the high band.
        { min = 0, max = 4000, tree = "Elemental" },
        { min = 4000, max = 8000, tree = "Enhancement" },
        { min = 8000, max = 999999, tree = "Restoration" },
    },
    Mage = {
        -- Confirmed by name from a friend's /wft treedump, 2026-09-20 (56
        -- nodes): Arcane Power/Arcane Mind/Presence of Mind in the low
        -- band, Combustion/Pyroblast/Ignite in the mid band, Ice Barrier/
        -- Ice Block/Frostbolt in the high band.
        { min = 0, max = 4000, tree = "Arcane" },
        { min = 4000, max = 8000, tree = "Fire" },
        { min = 8000, max = 999999, tree = "Frost" },
    },
    Hunter = {
        -- Confirmed by name from a friend's /wft treedump, 2026-09-20 (51
        -- nodes): Bestial Wrath/Frenzy/Unleashed Fury in the low band,
        -- Mortal Shots/Trueshot Aura/Careful Aim in the mid band,
        -- Deterrence/Survivalist/Entrapment in the high band.
        { min = 0, max = 4000, tree = "Beast Mastery" },
        { min = 4000, max = 8000, tree = "Marksmanship" },
        { min = 8000, max = 999999, tree = "Survival" },
    },
    Rogue = {
        -- Confirmed by name from a friend's /wft treedump, 2026-09-20 (53
        -- nodes): Cold Blood/Seal Fate/Malice in the low band, Adrenaline
        -- Rush/Blade Flurry/Improved Sinister Strike in the mid band,
        -- Premeditation/Ghostly Strike/Master of Deception in the high
        -- band. Relentless Strikes (posX 1020, low band) is Assassination
        -- on this server, not Combat like in vanilla WoW - a reminder that
        -- this server's own tree layout is what's confirmed here, not
        -- vanilla's, whenever the two differ.
        { min = 0, max = 4000, tree = "Assassination" },
        { min = 4000, max = 8000, tree = "Combat" },
        { min = 8000, max = 999999, tree = "Subtlety" },
    },
    Priest = {
        -- Confirmed by name from a friend's /wft treedump, 2026-09-20 (54
        -- nodes): Power Infusion/Inner Focus/Meditation in the low band,
        -- Spirit of Redemption/Holy Nova/Divine Fury in the mid band,
        -- Shadowform/Vampiric Embrace/Mind Flay in the high band.
        { min = 0, max = 4000, tree = "Discipline" },
        { min = 4000, max = 8000, tree = "Holy" },
        { min = 8000, max = 999999, tree = "Shadow" },
    },
    Warlock = {
        -- Confirmed by name from a friend's /wft treedump, 2026-09-20 (51
        -- nodes): Siphon Life/Nightfall/Shadow Mastery in the low band,
        -- Master Demonologist/Soul Link/Demonic Sacrifice in the mid band,
        -- Ruin/Shadowburn/Conflagrate in the high band.
        { min = 0, max = 4000, tree = "Affliction" },
        { min = 4000, max = 8000, tree = "Demonology" },
        { min = 8000, max = 999999, tree = "Destruction" },
    },
    Druid = {
        -- Confirmed by name from a friend's /wft treedump, 2026-09-20 (49
        -- nodes): Nature's Grace/Moonfury/Moonkin Form in the low band,
        -- Feral Charge/Mangle/Leader of the Pack in the mid band,
        -- Swiftmend/Tranquility/Gift of Nature in the high band.
        { min = 0, max = 4000, tree = "Balance" },
        { min = 4000, max = 8000, tree = "Feral Combat" },
        { min = 8000, max = 999999, tree = "Restoration" },
    },
}

local function classifyTree(class, posX)
    local bands = class and TREE_BANDS[class]
    if not (bands and posX) then
        return nil
    end
    for _, band in ipairs(bands) do
        if posX >= band.min and posX < band.max then
            return band.tree
        end
    end
    return nil
end

-- Manual override/fallback, kept only for the rare case automatic name or
-- tree resolution above can't figure something out (e.g. a client build
-- without C_Spell, or a class with no TREE_BANDS entry yet). Never guessed
-- into - only ever added from a real, confirmed in-game report.
local KNOWN_TRAIT_NAMES = {}

local function collectTraits()
    local out = { experimental = true, configs = {} }

    local CTraits = _G.C_Traits
    if not CTraits then
        out.error = "C_Traits is not available on this client"
        return out
    end

    local class = safeGet("UnitClass", "player")

    local configIDs = {}
    local CClassTalents = _G.C_ClassTalents
    if CClassTalents and type(CClassTalents.GetActiveConfigID) == "function" then
        local ok, id = safeCall(CClassTalents.GetActiveConfigID)
        if ok and id then
            table.insert(configIDs, id)
        end
    end

    if #configIDs == 0 then
        out.error = "No active trait config found. Open your Talents (and Legacy) panel once this session, then try again."
        return out
    end

    for _, configID in ipairs(configIDs) do
        local okInfo, configInfo = safeCall(CTraits.GetConfigInfo, configID)
        local entry = { configID = configID, nodes = {} }
        if okInfo and configInfo and configInfo.treeIDs then
            for _, treeID in ipairs(configInfo.treeIDs) do
                local okNodes, nodeIDs = safeCall(CTraits.GetTreeNodes, treeID)
                if okNodes and nodeIDs then
                    for _, nodeID in ipairs(nodeIDs) do
                        local okNode, nodeInfo = safeCall(CTraits.GetNodeInfo, configID, nodeID)
                        if okNode and nodeInfo and nodeInfo.ranksPurchased and nodeInfo.ranksPurchased > 0 then
                            local entryID
                            if nodeInfo.activeEntry then
                                entryID = nodeInfo.activeEntry.entryID
                            end

                            -- nodeInfo.activeEntry only carries entryID and
                            -- rank on this client (confirmed via /wft
                            -- nodeinfo) - NOT a definitionID, despite that
                            -- seeming like the obvious next field. The real
                            -- definitionID has to be looked up separately
                            -- through GetEntryInfo, same as /wft treedump
                            -- already does successfully.
                            local definitionID, spellID
                            if entryID and type(CTraits.GetEntryInfo) == "function" then
                                local okEntry, entryInfo = safeCall(CTraits.GetEntryInfo, configID, entryID)
                                if okEntry and entryInfo then
                                    definitionID = entryInfo.definitionID
                                    if definitionID and type(CTraits.GetDefinitionInfo) == "function" then
                                        local okDef, defInfo = safeCall(CTraits.GetDefinitionInfo, definitionID)
                                        if okDef and defInfo then
                                            spellID = defInfo.spellID
                                        end
                                    end
                                end
                            end

                            local resolvedName = getSpellName(spellID)
                            local resolvedTree = classifyTree(class, nodeInfo.posX)
                            local known = entryID and KNOWN_TRAIT_NAMES[entryID]

                            table.insert(entry.nodes, {
                                treeID = treeID,
                                nodeID = nodeID,
                                rank = nodeInfo.ranksPurchased,
                                maxRank = nodeInfo.maxRanks,
                                entryID = entryID,
                                definitionID = definitionID,
                                spellID = spellID,
                                name = resolvedName or (known and known.talent) or nil,
                                tree = resolvedTree or (known and known.tree) or nil,
                            })
                        end
                    end
                end
            end
        else
            entry.error = "Could not read config info for this config ID"
        end
        table.insert(out.configs, entry)
    end

    return out
end

local function buildExport()
    local out = {}
    local tocversion = select(4, safeGet("GetBuildInfo"))
    local okDate, timestamp = safeCall(_G.date, "%Y-%m-%d %H:%M:%S")
    out.meta = {
        addonVersion = "1.0.0",
        tocversion = tocversion,
        exportedAt = okDate and timestamp or nil,
    }
    out.basic = collectBasic()
    out.stats = collectStats()
    out.professions = collectProfessions()
    out.gear = collectGear()
    local okTraits, traits = pcall(collectTraits)
    out.traits = okTraits and traits or { error = "collectTraits crashed: " .. tostring(traits) }
    return out
end

----------------------------------------------------------------------
-- Sync data storage
----------------------------------------------------------------------
-- There used to also be a periodic-forced-/reload "auto-sync" system here
-- (a timer that reloaded the UI every N minutes purely to flush fresh data
-- to disk sooner). It's been removed - it didn't reliably work, and it's
-- not needed anyway: WoW already writes SavedVariables to disk on every
-- normal logout or /reload, which the hooks below already write fresh data
-- into every single time, with zero setup or slash commands required.

local function ensureSyncDB()
    WFTSyncDB = WFTSyncDB or {}
    return WFTSyncDB
end

-- Builds a fresh export and stores it in SavedVariables (WFTSyncDB.json) so
-- it's there next time this file gets saved to disk. This does NOT by
-- itself write to disk - that only happens on logout or /reload.
local function writeSyncExport()
    local ok, data = pcall(buildExport)
    if not ok then
        return false
    end
    -- Sanity check: if the game hands back 0 max health, your character
    -- data almost certainly isn't finished loading yet (e.g. this fired
    -- right at login/logout before stats were calculated). Saving that
    -- would silently overwrite good data on the website with zeros, so
    -- skip this write entirely and try again next time instead.
    if not data.stats or not data.stats.maxHealth or data.stats.maxHealth <= 0 then
        return false
    end
    local ok2, json = pcall(jsonEncode, data)
    if not ok2 then
        return false
    end
    local db = ensureSyncDB()
    db.json = json
    local okDate, dateStr = safeCall(_G.date, "%Y-%m-%d %H:%M:%S")
    db.lastWrittenAt = okDate and dateStr or nil
    return true
end

local syncVarsFrame = CreateFrame("Frame")
pcall(syncVarsFrame.RegisterEvent, syncVarsFrame, "ADDON_LOADED")
syncVarsFrame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        ensureSyncDB()
    end
end)

----------------------------------------------------------------------
-- Copy/paste export window
----------------------------------------------------------------------

local exportFrame

local function showExportWindow(text)
    if not exportFrame then
        local f = CreateFrame("Frame", "WFTExportFrame", UIParent)
        f:SetSize(520, 420)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        if type(f.SetBackdrop) == "function" then
            pcall(f.SetBackdrop, f, {
                bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
                edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
                tile = true,
                tileSize = 32,
                edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 },
            })
        else
            -- No backdrop API on this client build; fall back to a plain
            -- texture so the window is at least visible.
            local bg = f:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0.85)
        end

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -16)
        title:SetText("WoW Forever Tracker - Export")

        local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        sub:SetPoint("TOP", title, "BOTTOM", 0, -6)
        sub:SetText("Ctrl+A then Ctrl+C to copy, then paste it into the website.")

        local scroll = CreateFrame("ScrollFrame", "WFTExportScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 20, -60)
        scroll:SetPoint("BOTTOMRIGHT", -36, 44)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(440)
        edit:SetAutoFocus(true)
        edit:SetScript("OnEscapePressed", function()
            f:Hide()
        end)
        scroll:SetScrollChild(edit)
        f.editBox = edit

        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)

        exportFrame = f
    end

    exportFrame.editBox:SetText(text)
    exportFrame.editBox:HighlightText()
    exportFrame:Show()
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------

local PROBE_LIST = {
    "UnitName", "UnitFullName", "UnitRace", "UnitClass", "UnitFactionGroup", "UnitLevel",
    "GetGuildInfo", "GetMoney", "UnitStat", "UnitAttackPower", "UnitHealthMax", "UnitPowerMax",
    "GetUnitSpeed", "UnitArmor", "UnitDefense", "UnitDamage",
    "GetCritChance", "GetDodgeChance", "GetParryChance", "GetBlockChance",
    "GetResistance", "UnitResistance", "GetProfessions", "GetProfessionInfo", "GetInventoryItemLink",
    "C_Traits", "C_ClassTalents", "C_CurrencyInfo", "ToggleLegacySystemUI", "C_PaperDollInfo",
}

local function cmdProbe()
    print("|cffffcc00WFT probe - what this client actually has:|r")
    for _, name in ipairs(PROBE_LIST) do
        local v = _G[name]
        local kind = type(v)
        print(("  %s: %s"):format(name, v == nil and "MISSING" or kind))
    end
end

local function cmdExport()
    local ok, data = pcall(buildExport)
    if not ok then
        print("|cffff0000WFT error building export:|r " .. tostring(data))
        return
    end
    local ok2, json = pcall(jsonEncode, data)
    if not ok2 then
        print("|cffff0000WFT error encoding JSON:|r " .. tostring(json))
        return
    end
    -- Also refresh the auto-sync copy, so a manual export keeps the
    -- SavedVariables copy just as current as the copy/paste box.
    local db = ensureSyncDB()
    db.json = json
    local okDate, dateStr = safeCall(_G.date, "%Y-%m-%d %H:%M:%S")
    db.lastWrittenAt = okDate and dateStr or nil
    showExportWindow(json)
end

-- Diagnostic-only: prints EVERY field on a table, recursing into nested
-- tables (like nodeInfo.activeEntry), so we can see exactly what the game
-- gives us for a node - in particular whether it includes any kind of grid
-- position (row/column, posX/posY, etc.) that could let talent names be
-- matched automatically instead of confirmed one at a time by hand. This
-- never feeds into the real export; it only prints to the chat window.
local function dumpTable(t, indent, seen)
    indent = indent or "    "
    seen = seen or {}
    if seen[t] then
        print(indent .. "(already printed above, skipping to avoid a loop)")
        return
    end
    seen[t] = true

    -- Sort keys so the output is stable and easy to read/paste.
    local keys = {}
    for k in pairs(t) do
        table.insert(keys, k)
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)

    for _, k in ipairs(keys) do
        local v = t[k]
        if type(v) == "table" then
            print(("%s%s: (table)"):format(indent, tostring(k)))
            dumpTable(v, indent .. "    ", seen)
        else
            print(("%s%s: %s (%s)"):format(indent, tostring(k), tostring(v), type(v)))
        end
    end
end

-- /wft nodeinfo - walks every learned (ranksPurchased > 0) node exactly like
-- collectTraits does, but instead of building the tidy export table, dumps
-- the COMPLETE raw table C_Traits.GetNodeInfo() returns for each one. Run
-- this once and paste the output back so we can see if there's a row/column
-- (or similar) field we could use for automatic name-matching.
local function cmdNodeInfo()
    local CTraits = _G.C_Traits
    if not CTraits then
        print("|cffff0000WFT nodeinfo:|r C_Traits is not available on this client.")
        return
    end

    local configID
    local CClassTalents = _G.C_ClassTalents
    if CClassTalents and type(CClassTalents.GetActiveConfigID) == "function" then
        local ok, id = safeCall(CClassTalents.GetActiveConfigID)
        if ok and id then
            configID = id
        end
    end
    if not configID then
        print("|cffff0000WFT nodeinfo:|r No active trait config found. Open Talents/Legacy once this session, then try again.")
        return
    end

    local okInfo, configInfo = safeCall(CTraits.GetConfigInfo, configID)
    if not (okInfo and configInfo and configInfo.treeIDs) then
        print("|cffff0000WFT nodeinfo:|r Could not read config info for config " .. tostring(configID))
        return
    end

    print("|cffffcc00WFT nodeinfo (diagnostic) - config " .. tostring(configID) .. ":|r")
    local printed = 0
    for _, treeID in ipairs(configInfo.treeIDs) do
        local okNodes, nodeIDs = safeCall(CTraits.GetTreeNodes, treeID)
        if okNodes and nodeIDs then
            for _, nodeID in ipairs(nodeIDs) do
                local okNode, nodeInfo = safeCall(CTraits.GetNodeInfo, configID, nodeID)
                if okNode and nodeInfo and nodeInfo.ranksPurchased and nodeInfo.ranksPurchased > 0 then
                    printed = printed + 1
                    print(("  treeID %s, nodeID %s:"):format(tostring(treeID), tostring(nodeID)))
                    dumpTable(nodeInfo)

                    -- Also try GetNodeCost / GetEntryInfo if they exist - the
                    -- position data might live there instead of on nodeInfo.
                    if nodeInfo.activeEntry and nodeInfo.activeEntry.entryID then
                        if type(CTraits.GetEntryInfo) == "function" then
                            local okEntry, entryInfo = safeCall(CTraits.GetEntryInfo, configID, nodeInfo.activeEntry.entryID)
                            if okEntry and entryInfo then
                                print("    GetEntryInfo(" .. tostring(nodeInfo.activeEntry.entryID) .. "):")
                                dumpTable(entryInfo, "        ")
                            end
                        end
                    end
                end
            end
        end
    end
    if printed == 0 then
        print("  No learned nodes found (ranksPurchased > 0). Spend a talent point, then try again.")
    end
end

-- /wft treedump - like nodeinfo, but walks EVERY node in every tree on your
-- active config, whether you've put a point in it or not, and puts the
-- whole thing in the copy/paste export window (same as /wft export) instead
-- of printing it, since a full class tree can be a hundred-plus nodes. This
-- is purely diagnostic data for figuring out whether talentsforever.com's
-- row/col positions can be matched against this client's posX/posY, so a
-- talent import can eventually be fully automatic - it's never written to
-- your character or the website on its own.
local function collectTreeDump()
    local CTraits = _G.C_Traits
    if not CTraits then
        return { error = "C_Traits is not available on this client" }
    end

    local configID
    local CClassTalents = _G.C_ClassTalents
    if CClassTalents and type(CClassTalents.GetActiveConfigID) == "function" then
        local ok, id = safeCall(CClassTalents.GetActiveConfigID)
        if ok and id then
            configID = id
        end
    end
    if not configID then
        return { error = "No active trait config found. Open Talents/Legacy once this session, then try again." }
    end

    local okInfo, configInfo = safeCall(CTraits.GetConfigInfo, configID)
    if not (okInfo and configInfo and configInfo.treeIDs) then
        return { error = "Could not read config info for config " .. tostring(configID) }
    end

    local out = { configID = configID, trees = {} }
    for _, treeID in ipairs(configInfo.treeIDs) do
        local treeOut = { treeID = treeID, nodes = {} }
        local okNodes, nodeIDs = safeCall(CTraits.GetTreeNodes, treeID)
        if okNodes and nodeIDs then
            for _, nodeID in ipairs(nodeIDs) do
                local okNode, nodeInfo = safeCall(CTraits.GetNodeInfo, configID, nodeID)
                if okNode and nodeInfo then
                    local entries = {}
                    for _, entryID in ipairs(nodeInfo.entryIDs or {}) do
                        local entryOut = { entryID = entryID }
                        if type(CTraits.GetEntryInfo) == "function" then
                            local okEntry, entryInfo = safeCall(CTraits.GetEntryInfo, configID, entryID)
                            if okEntry and entryInfo then
                                entryOut.definitionID = entryInfo.definitionID
                                if type(CTraits.GetDefinitionInfo) == "function" and entryInfo.definitionID then
                                    local okDef, defInfo = safeCall(CTraits.GetDefinitionInfo, entryInfo.definitionID)
                                    if okDef and defInfo then
                                        entryOut.spellID = defInfo.spellID
                                        entryOut.overrideName = defInfo.overrideName
                                        -- Resolves the real talent name right in the dump,
                                        -- so building TREE_BANDS for a new class never again
                                        -- depends on guessing what a spellID "usually" means
                                        -- (this server reuses spellIDs for its own talents,
                                        -- which is exactly what mislabeled Cruelty as a Rogue
                                        -- talent before a Warrior confirmed otherwise).
                                        entryOut.name = getSpellName(defInfo.spellID)
                                    end
                                end
                            end
                        end
                        table.insert(entries, entryOut)
                    end
                    table.insert(treeOut.nodes, {
                        nodeID = nodeID,
                        posX = nodeInfo.posX,
                        posY = nodeInfo.posY,
                        maxRanks = nodeInfo.maxRanks,
                        ranksPurchased = nodeInfo.ranksPurchased,
                        entries = entries,
                    })
                end
            end
        end
        table.insert(out.trees, treeOut)
    end
    return out
end

local function cmdTreeDump()
    local ok, data = pcall(collectTreeDump)
    if not ok then
        print("|cffff0000WFT treedump error:|r " .. tostring(data))
        return
    end
    if data.error then
        print("|cffff0000WFT treedump:|r " .. data.error)
        return
    end
    local ok2, json = pcall(jsonEncode, data)
    if not ok2 then
        print("|cffff0000WFT treedump JSON error:|r " .. tostring(json))
        return
    end
    showExportWindow(json)
end

-- /wft spellprobe - tries every way this addon knows of to resolve a real
-- talent name from a spellID, using entryID 130022's spellID (Improved Holy
-- Strike, confirmed from your own /wft treedump data), and prints exactly
-- what each attempt returns - including raw tables via dumpTable - so we
-- can see which API actually works on this client instead of guessing.
local function cmdSpellProbe()
    local testSpellID = 1310902 -- Improved Holy Strike, from your treedump
    print("|cffffcc00WFT spellprobe - resolving spellID " .. testSpellID .. ":|r")

    local CSpell = _G.C_Spell
    print("  C_Spell exists: " .. tostring(CSpell ~= nil))
    if CSpell then
        local hasGetSpellInfo = type(CSpell.GetSpellInfo) == "function"
        print("  C_Spell.GetSpellInfo exists: " .. tostring(hasGetSpellInfo))
        if hasGetSpellInfo then
            local ok, a, b, c = pcall(CSpell.GetSpellInfo, testSpellID)
            print("  C_Spell.GetSpellInfo(" .. testSpellID .. ") call ok: " .. tostring(ok))
            if ok then
                print("    result type: " .. type(a))
                if type(a) == "table" then
                    dumpTable(a, "    ")
                else
                    print(("    a=%s b=%s c=%s"):format(tostring(a), tostring(b), tostring(c)))
                end
            else
                print("    error: " .. tostring(a))
            end
        end
        if type(CSpell.GetSpellName) == "function" then
            local ok2, name2 = pcall(CSpell.GetSpellName, testSpellID)
            print(("  C_Spell.GetSpellName(%d) ok=%s -> %s"):format(testSpellID, tostring(ok2), tostring(name2)))
        else
            print("  C_Spell.GetSpellName exists: false")
        end
    end

    local g = _G.GetSpellInfo
    print("  global GetSpellInfo exists: " .. tostring(type(g) == "function"))
    if type(g) == "function" then
        local ok3, r1, r2, r3 = pcall(g, testSpellID)
        print(("  global GetSpellInfo(%d) ok=%s r1=%s r2=%s r3=%s"):format(
            testSpellID, tostring(ok3), tostring(r1), tostring(r2), tostring(r3)))
    end

    -- Also check whether the spell tooltip itself has the name - if the
    -- API route is a dead end, we could fall back to scanning a hidden
    -- spell tooltip the same way collectGear scans item tooltips.
    if scanTip and type(scanTip.SetSpellByID) == "function" then
        local ok4 = pcall(function()
            scanTip:SetOwner(UIParent, "ANCHOR_NONE")
            scanTip:ClearLines()
            scanTip:SetSpellByID(testSpellID)
        end)
        if ok4 then
            local left1 = _G["WFTScanTooltipTextLeft1"]
            print("  Tooltip SetSpellByID line 1: " .. tostring(left1 and left1:GetText()))
        else
            print("  Tooltip SetSpellByID(" .. testSpellID .. ") failed")
        end
    else
        print("  scanTip:SetSpellByID exists: false")
    end
end

local function cmdTraits()
    local ok, traits = pcall(collectTraits)
    if not ok then
        print("|cffff0000WFT traits error:|r " .. tostring(traits))
        return
    end
    print("|cffffcc00WFT traits (experimental):|r")
    if traits.error then
        print("  " .. traits.error)
        return
    end
    for _, cfg in ipairs(traits.configs or {}) do
        print(("  config %s: %d learned node(s)"):format(tostring(cfg.configID), #cfg.nodes))
        if cfg.error then
            print("    " .. cfg.error)
        end
        for _, node in ipairs(cfg.nodes) do
            if node.name then
                print(("    %s %d/%d"):format(node.name, node.rank, node.maxRank or node.rank))
            else
                print(("    (unknown talent) entryID %s, rank %d/%d - tell me what this is!"):format(
                    tostring(node.entryID), node.rank, node.maxRank or node.rank))
            end
        end
    end
    if #(traits.configs or {}) == 0 then
        print("  No trait configs found.")
    end
end

-- Tests whether this beta client actually saves WFTTestDB to disk across a
-- FULL logout/login (not just /reload, which can behave differently) - the
-- one real question standing between "manual copy/paste forever" and "a
-- companion program on your PC could sync this automatically". WFTTestDB
-- only exists once ADDON_LOADED has fired for this addon, so it's created
-- there rather than at the top of the file.
local savedVarsFrame = CreateFrame("Frame")
pcall(savedVarsFrame.RegisterEvent, savedVarsFrame, "ADDON_LOADED")
savedVarsFrame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        WFTTestDB = WFTTestDB or {}
    end
end)

local function cmdSaveTest()
    if type(WFTTestDB) ~= "table" then
        print("|cffff0000WFT savetest:|r SavedVariables aren't ready yet - wait a few seconds after login and try again.")
        return
    end

    if WFTTestDB.lastValue then
        print("|cffffcc00WFT savetest - found a previously saved value:|r " .. tostring(WFTTestDB.lastValue))
        print("  (written at " .. tostring(WFTTestDB.lastSavedAt) .. ")")
        print("  If you FULLY logged out and back in since writing that (not just /reload), SavedVariables persistence works here.")
    else
        print("|cffffcc00WFT savetest:|r No previous value found yet.")
    end

    local newValue = "test-" .. tostring(math.random(100000, 999999))
    local okDate, dateStr = safeCall(_G.date, "%Y-%m-%d %H:%M:%S")
    WFTTestDB.lastValue = newValue
    WFTTestDB.lastSavedAt = okDate and dateStr or "unknown time"
    print("|cffffcc00WFT savetest:|r Wrote new value " .. newValue .. ".")
    print("  Now FULLY log out (Log Out to character select, not /reload) and log back in, then run /wft savetest again.")
    print("  If it still shows " .. newValue .. " next time, disk persistence works and real automation is possible.")
end

local function cmdProfDump()
    print("|cffffcc00WFT profdump - raw GetProfessions() return values:|r")
    local r1, r2, r3, r4, r5, r6 = safeGet("GetProfessions")
    local raw = { r1, r2, r3, r4, r5, r6 }
    for i = 1, 6 do
        local idx = raw[i]
        if idx == nil then
            print(("  slot %d: nil"):format(i))
        else
            local name, _icon, skillLevel, maxSkillLevel = safeGet("GetProfessionInfo", idx)
            print(("  slot %d: index %s -> %s (%s/%s)"):format(
                i, tostring(idx), tostring(name), tostring(skillLevel), tostring(maxSkillLevel)
            ))
        end
    end
end

SLASH_WFT1 = "/wft"
SlashCmdList["WFT"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "" or msg == "export" then
        cmdExport()
    elseif msg == "probe" then
        cmdProbe()
    elseif msg == "traits" then
        cmdTraits()
    elseif msg == "nodeinfo" then
        cmdNodeInfo()
    elseif msg == "treedump" then
        cmdTreeDump()
    elseif msg == "spellprobe" then
        cmdSpellProbe()
    elseif msg == "savetest" then
        cmdSaveTest()
    elseif msg == "profdump" then
        cmdProfDump()
    elseif msg == "scan" then
        cmdProbe()
        cmdTraits()
        cmdExport()
    else
        print("|cffffcc00WoW Forever Tracker commands:|r")
        print("  /wft export - open a copy/paste box with your character data")
        print("  /wft probe - list which game functions exist on this client")
        print("  /wft traits - try reading your talent/Legacy trait data")
        print("  /wft nodeinfo - dump raw fields for talents you've learned (diagnostic, for me to look at)")
        print("  /wft treedump - dump position data for every talent in your tree, learned or not (diagnostic, for me to look at)")
        print("  /wft spellprobe - test ways of resolving a talent's real name (diagnostic, for me to look at)")
        print("  /wft savetest - test whether this client saves data to disk across a full logout/login")
        print("  /wft profdump - dump raw GetProfessions() values (diagnostic, for me to look at)")
        print("  /wft scan - run probe, traits and export together")
    end
end

----------------------------------------------------------------------
-- Login message
----------------------------------------------------------------------

local loginFrame = CreateFrame("Frame")
pcall(loginFrame.RegisterEvent, loginFrame, "PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        print("|cff33ff99WoW Forever Tracker|r loaded. Type /wft for commands.")
        -- Write an export right away too, so even a brand new install has
        -- real data in SavedVariables the moment you next log out or
        -- /reload, without needing any slash command first.
        writeSyncExport()
    end
end)

----------------------------------------------------------------------
-- Auto-write on every logout/reload
----------------------------------------------------------------------
-- WoW only ever saves SavedVariables to disk right as you log out or
-- /reload - PLAYER_LOGOUT fires right before that save happens. Writing a
-- fresh export here means the file on disk is always current the moment
-- it's written, with zero manual steps ever needed - no /wft export
-- required first.
local logoutFrame = CreateFrame("Frame")
pcall(logoutFrame.RegisterEvent, logoutFrame, "PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGOUT" then
        writeSyncExport()
    end
end)

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

-- A widget's OWN text, if it's the kind of thing that has any (Button,
-- EditBox, FontString itself). Moved up here (2026-09-27) from the
-- legacyframetreedump diagnostic once it turned out to be needed for real,
-- always-on data collection too (see scanLegacyPointsFromUI further down) -
-- not just for one-off frame-tree dumps.
local function widgetOwnText(widget)
    local ok, text = pcall(function()
        if widget.GetText then
            return widget:GetText()
        end
        return nil
    end)
    if ok and text and text ~= "" then
        return text
    end
    return nil
end

-- GetChildren() only returns child FRAMES - a plain text label is almost
-- always a FontString REGION instead (a name, a number, a description line),
-- which GetChildren() silently skips entirely. GetRegions() is the only way
-- to actually see those.
local function regionTexts(frame, budget)
    local texts = {}
    local ok, regions = pcall(function()
        return { frame:GetRegions() }
    end)
    if not ok or not regions then
        return texts
    end
    for _, r in ipairs(regions) do
        budget.count = budget.count + 1
        if budget.count > 1500 then
            break
        end
        local okType, rt = pcall(function()
            return r.GetObjectType and r:GetObjectType()
        end)
        if okType and rt == "FontString" then
            local t = widgetOwnText(r)
            if t then
                table.insert(texts, t)
            end
        end
    end
    return texts
end

-- Same idea as regionTexts, but for Texture regions instead of FontStrings -
-- added 2026-09-30 to hunt for a Legacy Challenge achievement's real icon
-- after GetAchievementInfo's icon return value was confirmed (via
-- /wft achievementsprobe) to come back nil for every one of the 111 Legacy
-- Challenge achievements on this server, even though the icon clearly does
-- render in the real in-game panel. That means the icon exists somewhere
-- Blizzard's own UI can read it - almost certainly a Texture region sitting
-- right on the achievement's row Button, the same row scanLegacyPointsFromUI
-- already walks to steal the point value off of. GetTexture() on that region
-- returns either a numeric fileID or an "Interface\\..." asset path string,
-- either of which is worth capturing and sending back for a look.
-- 2026-09-30: now also returns each Texture region's own name and size, not
-- just its texture value - confirmed via /wft iconprobe (comparing "Explore
-- Azeroth"/"Explore Eastern Kingdoms"/"Explore Kalimdor", three achievements
-- with visibly different icons) that exactly ONE texture value out of ~16
-- per row actually changes between achievements (237388 / 236759 / 236807) -
-- everything else is shared row decoration (background, border, checkmark,
-- glow) that's IDENTICAL across every achievement row. Name/size is what
-- will let a real collector single that one texture out automatically
-- instead of a human eyeballing a diff every time.
local function regionTextures(frame, budget)
    local textures = {}
    local ok, regions = pcall(function()
        return { frame:GetRegions() }
    end)
    if not ok or not regions then
        return textures
    end
    for _, r in ipairs(regions) do
        budget.count = budget.count + 1
        if budget.count > 1500 then
            break
        end
        local okType, rt = pcall(function()
            return r.GetObjectType and r:GetObjectType()
        end)
        if okType and rt == "Texture" then
            local okTex, tex = pcall(function()
                return r.GetTexture and r:GetTexture()
            end)
            if okTex and tex then
                local okName, name = pcall(function()
                    return r.GetName and r:GetName()
                end)
                local okSize, w, h = pcall(function()
                    return r.GetSize and r:GetSize()
                end)
                table.insert(textures, {
                    texture = tex,
                    name = (okName and name) or nil,
                    width = okSize and w or nil,
                    height = okSize and h or nil,
                })
            end
        end
    end
    return textures
end

-- Same idea but for a function value you already have in hand (e.g. one
-- pulled out of a C_* table), rather than a global name. Every existing
-- caller of this only ever needed a single return value, so this only ever
-- forwarded r1 - fine until /wft statsprobe needed GetAchievementInfo's
-- name/points/description too and they came back silently nil (2026-09-25).
-- Forwards up to 9 return values now, same as safeGet already does.
local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        return false, nil
    end
    local ok, r1, r2, r3, r4, r5, r6, r7, r8, r9 = pcall(fn, ...)
    if not ok then
        return false, nil
    end
    return true, r1, r2, r3, r4, r5, r6, r7, r8, r9
end

-- Recipe entries used to be bare strings (pre-1.3.0), then gained
-- icon/id (1.3.0), then reagents/tooltip (this version). Anything already
-- sitting in WFTSyncDB.recipes from an older build is still in an earlier
-- shape, so every place that reads a recipe entry runs it through this
-- first rather than assuming the current full shape.
local function normalizeRecipeEntry(r)
    if type(r) == "table" then
        return {
            name = r.name,
            icon = r.icon,
            id = r.id,
            reagents = r.reagents,
            tooltip = r.tooltip,
            color = r.color,
        }
    end
    return { name = r }
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

-- Forward-declared: the real function body lives further down (it needs the
-- hidden scanTip tooltip frame, which isn't set up until later in the file)
-- but collectBasic needs to call it, and collectBasic has to stay up here
-- since a bunch of things below it are defined in terms of it. Lua's
-- lexical scoping means a `local` isn't visible to code written before its
-- own declaration, regardless of call order - this forward declaration is
-- what makes that work.
local scanPlayerFullNameFromTooltip

local function collectBasic()
    local data = {}
    -- WoW Forever gives every character a real first+last name (no realms
    -- on this server) and the site requires that full two-word name (a DB
    -- check constraint, characters_name_two_words). Three sources, in order
    -- of trust:
    --   1. The player's own tooltip, IF it actually contains a space - this
    --      is the LIVE, always-correct source, and per Blizzard's own news
    --      post on Forever's naming system the "My Secondary Name"
    --      nameplate option that controls it defaults to ON, so this
    --      should cover most people most of the time without needing to do
    --      anything. Only produces a single word (no space) for a player
    --      who has that option turned off.
    --   2. A manually-confirmed override (/wft setname) - the fallback for
    --      the "option turned off" case above; once set it's used whenever
    --      the tooltip can't supply the full name itself. Doesn't depend on
    --      any client display setting.
    --   3. UnitFullName/UnitName - both confirmed (2026-09-25, /wft
    --      nameprobe) to truncate at the first space on this server, so
    --      this is really just the first name alone. Last resort for a
    --      character with neither of the above; won't by itself satisfy
    --      the site's two-word requirement.
    local full = safeGet("UnitFullName", "player")
    local apiName = full or safeGet("UnitName", "player")
    local override = type(WFTSyncDB) == "table" and WFTSyncDB.nameOverride or nil
    local tooltipName = scanPlayerFullNameFromTooltip and scanPlayerFullNameFromTooltip()
    local hasSpace = tooltipName and tooltipName:find(" ", 1, true)
    data.name = (hasSpace and tooltipName) or override or apiName
    if full then
        data.fullName = full
    end
    data.race = safeGet("UnitRace", "player")
    data.class = safeGet("UnitClass", "player")
    local faction = safeGet("UnitFactionGroup", "player")
    data.faction = faction
    data.level = safeGet("UnitLevel", "player")
    -- Standard Blizzard API, present on every client this project has seen
    -- so far (no probe needed, unlike the item-info/recipe APIs) - XP
    -- within the CURRENT level, not toward the level cap. At the level
    -- cap UnitXPMax returns 0 (no more bar to fill), which the website
    -- treats as "no live XP bar" and falls back to level-out-of-60 instead.
    data.xp = safeGet("UnitXP", "player")
    data.xpMax = safeGet("UnitXPMax", "player")
    data.guild = safeGet("GetGuildInfo", "player")
    data.money = safeGet("GetMoney")
    data.realm = safeGet("GetRealmName")
    -- Confirmed via /wft probe: this client has the older honor-as-a-
    -- resource-bar API (UnitHonor/UnitHonorMax), not the newer currency-
    -- based one - so this is a real current value, not a guess.
    data.honor = safeGet("UnitHonor", "player")
    -- Deaths aren't anything Blizzard's API hands you as a running total
    -- on this server, so they're counted ourselves instead - see the
    -- PLAYER_DEAD handler further down. Lives in WFTSyncDB directly (not
    -- rebuilt by collectBasic), so it only ever counts up from whenever
    -- this version of the addon was first installed - there's no way to
    -- know how many times a character died before that. pvpKills is sent
    -- too but is currently always 0 - see the note near the bottom of
    -- this file for why PvP kill tracking is paused.
    data.deaths = (type(WFTSyncDB) == "table" and WFTSyncDB.deathCount) or 0
    data.pvpKills = (type(WFTSyncDB) == "table" and WFTSyncDB.pvpKillCount) or 0
    -- Total time played, in seconds (2026-09-27, "Addicted" achievement).
    -- Not part of the Statistics-pane sweep (collectStatistics only walks
    -- achievement-linked counters - classic /played data isn't one of
    -- those), so it's fetched separately via RequestTimePlayed()/
    -- TIME_PLAYED_MSG (see that section further down) and cached in
    -- WFTSyncDB, same pattern as deaths/pvpKills above. nil until that
    -- event has fired at least once (this session or a past one, since
    -- it's cached to SavedVariables) - the website skips awarding Addicted
    -- entirely until it sees a real number.
    data.timePlayedSeconds = (type(WFTSyncDB) == "table" and WFTSyncDB.timePlayedTotalSeconds) or nil
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
            -- Recipes are captured separately (see the "Recipes known"
            -- section further down) whenever that profession's trade skill
            -- window is actually opened, and stashed in WFTSyncDB.recipes
            -- keyed by profession name so they carry forward here even
            -- though this collector itself never opens any window.
            local recipeList = nil
            if type(WFTSyncDB) == "table" and type(WFTSyncDB.recipes) == "table" then
                local raw = WFTSyncDB.recipes[name]
                if type(raw) == "table" then
                    recipeList = {}
                    for _, r in ipairs(raw) do
                        table.insert(recipeList, normalizeRecipeEntry(r))
                    end
                end
            end
            table.insert(profs, { name = name, skill = skillLevel, maxSkill = maxSkillLevel, recipes = recipeList })
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

-- Best-effort attempt to read the player's real two-word "First Last" name
-- off their own unit tooltip (line 1) - UnitName/UnitFullName both
-- truncate at the first space on this server (confirmed 2026-09-25 via
-- /wft nameprobe), and the tooltip line only shows the full name when the
-- player has WoW Forever's own "My Secondary Name" nameplate option turned
-- on (see the 2026-09-25 Blizzard news post on the Forever naming system:
-- turning that option off hides the secondary name "in the world" -
-- nameplates and tooltips - though it still appears in chat). So this is
-- opportunistic only, not a real fix - most of the time it'll just return
-- the same truncated single word, which collectBasic() below detects and
-- ignores. The reliable fix is the /wft setname override further down.
scanPlayerFullNameFromTooltip = function()
    if not scanTip then
        return nil
    end
    local ok, text = pcall(function()
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
        scanTip:ClearLines()
        scanTip:SetUnit("player")
        local left = _G["WFTScanTooltipTextLeft1"]
        return left and left:GetText()
    end)
    if ok and text then
        return stripMarkup(text)
    end
    return nil
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
            -- GetInventoryItemID is a separate, older API from
            -- GetInventoryItemLink - it reads the slot's numeric item ID
            -- directly rather than parsing a hyperlink string, so it should
            -- still work even though this beta's item links come back bare
            -- (no "item:12345:..." payload, just literal "[Item Name]" -
            -- see the note on scanSlotTooltip above). Having the real item
            -- ID lets the website match gear against Blizzard's own item
            -- database exactly, instead of guessing from the name text.
            -- Untested on this client build as of 1.6.0 - if it comes back
            -- MISSING on a /wft probe, the website falls back to matching
            -- by name instead.
            local itemID = safeGet("GetInventoryItemID", "player", slotID)
            gear[slotName] = {
                link = link,
                id = itemID,
                name = extractItemName(link),
                color = qualityColor or extractItemColor(link),
                tooltip = #tooltip > 0 and tooltip or nil,
                icon = icon,
            }
        end
    end
    return gear
end

----------------------------------------------------------------------
-- Bag/bank contents - NOT displayed anywhere on the site (nobody asked for
-- a bag-viewer feature). This exists purely to grow and correct the shared
-- item database faster than "only what's equipped" would - see the
-- 2026-09-24 chat: it's every item a real player has ever been seen
-- carrying, fed through the exact same live-tooltip pipeline gear uses, so
-- the item search page fills in without everyone having to equip every
-- single item first.
----------------------------------------------------------------------

-- Every container ID worth trying: backpack (0), the 4 equipped bag slots
-- (1-4), the reagent bag slot retail added (5), the bank's own backpack
-- (-1), bank bag slots (6-11, retail's usual range), and the reagent bank
-- (-3). Every ID is tried independently and safely - one that doesn't exist
-- or isn't accessible on this client/server just reports 0 slots and is
-- skipped, same philosophy as everything else in this file. Bank-related
-- IDs may only actually return contents while the bank window is open in
-- some client versions - untested as of 1.7.0, so don't be surprised if
-- bank items only show up in an export taken right after visiting a bank.
local CONTAINER_IDS_TO_TRY = { 0, 1, 2, 3, 4, 5, -1, 6, 7, 8, 9, 10, 11, -3 }

local function getContainerNumSlots(bagID)
    local CContainer = _G.C_Container
    if CContainer and type(CContainer.GetContainerNumSlots) == "function" then
        local ok, n = safeCall(CContainer.GetContainerNumSlots, bagID)
        if ok and n then
            return n
        end
    end
    return safeGet("GetContainerNumSlots", bagID)
end

-- Retail's C_Container.GetContainerItemID gives the numeric item ID
-- directly - no link-parsing needed, unlike collectGear's workaround for
-- this beta's bare item links.
local function getContainerItemID(bagID, slot)
    local CContainer = _G.C_Container
    if CContainer and type(CContainer.GetContainerItemID) == "function" then
        local ok, id = safeCall(CContainer.GetContainerItemID, bagID, slot)
        if ok then
            return id
        end
    end
    return nil
end

local function getContainerItemIcon(bagID, slot)
    local CContainer = _G.C_Container
    if CContainer and type(CContainer.GetContainerItemInfo) == "function" then
        local ok, info = safeCall(CContainer.GetContainerItemInfo, bagID, slot)
        if ok and info then
            return info.iconFileID
        end
    end
    local icon = safeGet("GetContainerItemInfo", bagID, slot)
    return icon
end

-- Same tooltip-scan trick collectGear uses for equipped items, but pointed
-- at a bag/bank slot via SetBagItem instead of SetInventoryItem.
local function scanContainerSlotTooltip(bagID, slot)
    if not scanTip then
        return {}, nil
    end
    local lines = {}
    local qualityColor
    local ok = pcall(function()
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
        scanTip:ClearLines()
        scanTip:SetBagItem(bagID, slot)
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

-- The bag CONTAINERS themselves (an Apprentice Mining Pack, a Small Green
-- Pouch) are equipped in fixed inventory slots, same category as gear - not
-- container contents, so C_Container's API never sees them. Blizzard
-- exposes the slot IDs as plain numeric globals (not functions), read
-- directly rather than through safeGet. Falls back to the standard
-- classic/retail slot numbers (20-23) if a global isn't defined on this
-- client for some reason.
local BAG_CONTAINER_SLOT_IDS = {}
for _, globalName in ipairs({ "INVSLOT_BAG1", "INVSLOT_BAG2", "INVSLOT_BAG3", "INVSLOT_BAG4", "INVSLOT_REAGENT_BAG" }) do
    local v = _G[globalName]
    if type(v) == "number" then
        table.insert(BAG_CONTAINER_SLOT_IDS, v)
    end
end
if #BAG_CONTAINER_SLOT_IDS == 0 then
    BAG_CONTAINER_SLOT_IDS = { 20, 21, 22, 23 }
end

-- Walks every container worth trying and returns one entry per distinct
-- item ID seen (a stack of 20 Linen Cloth only needs to be captured once -
-- de-duped by id, first copy found wins). No count/location is kept; this
-- is purely "here's an item that exists and here's its real tooltip", not
-- an inventory snapshot.
local function collectContainerItems()
    local out = {}
    local seen = {}

    -- The bag items themselves first (same scan method as collectGear,
    -- since these are regular equipped-item slots).
    for _, slotID in ipairs(BAG_CONTAINER_SLOT_IDS) do
        local link = safeGet("GetInventoryItemLink", "player", slotID)
        if link then
            local itemID = safeGet("GetInventoryItemID", "player", slotID)
            if itemID and not seen[itemID] then
                seen[itemID] = true
                local icon = safeGet("GetInventoryItemTexture", "player", slotID)
                local tooltip, qualityColor = scanSlotTooltip(slotID)
                table.insert(out, {
                    id = itemID,
                    name = extractItemName(link),
                    color = qualityColor or extractItemColor(link),
                    tooltip = #tooltip > 0 and tooltip or nil,
                    icon = icon,
                })
            end
        end
    end

    for _, bagID in ipairs(CONTAINER_IDS_TO_TRY) do
        local okSlots, numSlots = pcall(getContainerNumSlots, bagID)
        if okSlots and numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local okID, itemID = pcall(getContainerItemID, bagID, slot)
                itemID = okID and itemID or nil
                if itemID and not seen[itemID] then
                    seen[itemID] = true
                    local okIcon, icon = pcall(getContainerItemIcon, bagID, slot)
                    icon = okIcon and icon or nil
                    local tooltip, qualityColor = scanContainerSlotTooltip(bagID, slot)
                    -- No item link here (unlike gear), so the name comes
                    -- from the tooltip's own first line instead.
                    local name = tooltip[1]
                    if name then
                        table.insert(out, {
                            id = itemID,
                            name = name,
                            color = qualityColor,
                            tooltip = #tooltip > 0 and tooltip or nil,
                            icon = icon,
                        })
                    end
                end
            end
        end
    end
    return out
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

-- Walks the game's entire Statistics pane (character sheet -> bottom tab -
-- see the 2026-09-25 Wowhead post about it going live in the beta, and
-- /wft statsprobe's diagnostic findings the same day) and returns every
-- single stat this client has, not just a sample - captures everything up
-- front rather than a hand-picked subset, so a future badge/leaderboard
-- idea never needs another addon update just to start collecting a stat
-- that wasn't grabbed before. GetStatisticsCategoryList/GetCategoryInfo/
-- GetCategoryNumAchievements/GetAchievementInfo (for the name) and
-- GetStatistic (for the real current value, as a string - already
-- comma-formatted by the client, "--" if never recorded) are all confirmed
-- present and working on this client. Safe against any of them being
-- missing or erroring (safeCall/safeGet degrade to empty instead of
-- crashing), same as every other collector here.
local function collectStatistics()
    local out = {}

    local getStatCategoryList = _G.GetStatisticsCategoryList
    local getCategoryInfo = _G.GetCategoryInfo
    local getCategoryNum = _G.GetCategoryNumAchievements
    local getAchievementInfo = _G.GetAchievementInfo
    local getStatistic = _G.GetStatistic

    if type(getStatCategoryList) ~= "function" then
        return out
    end

    local okList, catIDs = safeCall(getStatCategoryList)
    if not okList or not catIDs then
        return out
    end

    for _, catID in ipairs(catIDs) do
        local categoryName = tostring(catID)
        if type(getCategoryInfo) == "function" then
            local okInfo, name = safeCall(getCategoryInfo, catID)
            if okInfo and name and name ~= "" then
                categoryName = name
            end
        end

        local numEntries = 0
        if type(getCategoryNum) == "function" then
            local okN, num = safeCall(getCategoryNum, catID, true)
            if okN and type(num) == "number" then
                numEntries = num
            end
        end

        if numEntries > 0 and type(getAchievementInfo) == "function" then
            for i = 1, numEntries do
                local okA, id, name = safeCall(getAchievementInfo, catID, i)
                if okA and id and name and name ~= "" then
                    local value = "--"
                    if type(getStatistic) == "function" then
                        local okV, v = safeCall(getStatistic, id)
                        if okV and v ~= nil then
                            value = tostring(v)
                        end
                    end
                    table.insert(out, {
                        id = id,
                        category = categoryName,
                        name = name,
                        value = value,
                    })
                end
            end
        end
    end

    return out
end

-- "Legacy Challenges" (2026-09-27) - the REAL Blizzard-server Achievements
-- pane (GetCategoryList/GetAchievementInfo/GetAchievementCriteriaInfo), a
-- completely separate API namespace from collectStatistics() above (that's
-- the Statistics tab). Confirmed via the diagnostic-only
-- `/wft achievementsprobe` command (see further down this file) to be small
-- - 111 achievements across 29 categories on this character - and safe to
-- sync wholesale rather than curating a subset, so this is that same
-- collection logic promoted to a real, always-on part of buildExport().
-- LEGACY_ACHIEVEMENTS_MAX is a safety cap only (in case some other
-- character/client exposes a much bigger tree than the one this was tested
-- against) - it should never actually be hit.
local LEGACY_ACHIEVEMENTS_MAX = 600

local function collectLegacyAchievements()
    local out = {}

    local getCategoryList = _G.GetCategoryList
    local getCategoryInfo = _G.GetCategoryInfo
    local getCategoryNum = _G.GetCategoryNumAchievements
    local getAchievementInfo = _G.GetAchievementInfo
    local getNumCriteria = _G.GetAchievementNumCriteria
    local getCriteriaInfo = _G.GetAchievementCriteriaInfo

    if type(getCategoryList) ~= "function" then
        return out
    end
    local okList, catIDs = safeCall(getCategoryList)
    if not okList or not catIDs then
        return out
    end

    for _, catID in ipairs(catIDs) do
        if #out >= LEGACY_ACHIEVEMENTS_MAX then break end

        local categoryName = tostring(catID)
        if type(getCategoryInfo) == "function" then
            local okInfo, name = safeCall(getCategoryInfo, catID)
            if okInfo and name and name ~= "" then
                categoryName = name
            end
        end

        local numEntries = 0
        if type(getCategoryNum) == "function" then
            local okN, num = safeCall(getCategoryNum, catID, true)
            if okN and type(num) == "number" then
                numEntries = num
            end
        end

        if numEntries > 0 and type(getAchievementInfo) == "function" then
            for i = 1, numEntries do
                if #out >= LEGACY_ACHIEVEMENTS_MAX then break end
                -- 10th return value is the achievement's own icon fileID
                -- (2026-09-27, added so the website can show the real
                -- Blizzard icon instead of a generic placeholder) -
                -- GetAchievementInfo's full signature is id, name, points,
                -- completed, month, day, year, description, flags, icon,
                -- rewardText, isGuild, wasEarnedByMe, earnedBy.
                local okA, id, name, points, completed, _month, _day, _year, description, _flags, icon =
                    safeCall(getAchievementInfo, catID, i)
                if okA and id then
                    local row = {
                        id = id,
                        category = categoryName,
                        name = name,
                        completed = completed and true or false,
                        description = description,
                        -- icon is nil from GetAchievementInfo on every Legacy
                        -- Challenge achievement on this server (confirmed
                        -- 2026-09-30 via /wft achievementsprobe's icon check
                        -- - 0/111 came back with a value), even though the
                        -- icon does render in the real in-game panel. So this
                        -- falls back to WFTSyncDB.legacyIconValues, filled in
                        -- by scanLegacyIconsFromUI (see above) reading the
                        -- icon straight off the rendered UI - same
                        -- "builds up as you browse" pattern as uiPoints
                        -- below. The API value is still preferred when
                        -- present, in case a future server patch fixes it.
                        icon = icon or (type(WFTSyncDB) == "table" and type(WFTSyncDB.legacyIconValues) == "table"
                            and name and WFTSyncDB.legacyIconValues[name]) or nil,
                        -- Blizzard's own achievement point value from
                        -- GetAchievementInfo - kept for reference only.
                        -- CONFIRMED WRONG/UNRELATED as of 2026-09-27 (comes
                        -- back 0 for achievements that genuinely award real
                        -- Legacy Points in game) - the website does NOT use
                        -- this for scoring. See uiPoints below for the real
                        -- value.
                        points = points,
                        -- The REAL Legacy Point value, scraped straight off
                        -- the rendered UI (see scanLegacyPointsFromUI above)
                        -- since no API exposes it. nil until this
                        -- achievement's row has actually been seen on screen
                        -- at least once (any character, any session -
                        -- WFTSyncDB.legacyPointValues is keyed by name, not
                        -- per-character) - builds up over time as the Legacy
                        -- Challenges panel gets browsed.
                        uiPoints = (type(WFTSyncDB) == "table" and type(WFTSyncDB.legacyPointValues) == "table"
                            and name and WFTSyncDB.legacyPointValues[name]) or nil,
                    }
                    if type(getNumCriteria) == "function" then
                        local okC, numCriteria = safeCall(getNumCriteria, id)
                        if okC and type(numCriteria) == "number" and numCriteria > 0
                            and type(getCriteriaInfo) == "function" then
                            row.criteria = {}
                            for c = 1, numCriteria do
                                local okCi, criteriaString, _type, critCompleted =
                                    safeCall(getCriteriaInfo, id, c)
                                if okCi then
                                    table.insert(row.criteria, {
                                        text = criteriaString,
                                        completed = critCompleted and true or false,
                                    })
                                end
                            end
                        end
                    end
                    table.insert(out, row)
                end
            end
        end
    end

    return out
end

-- Legacy Points UI scan (2026-09-27) - confirmed via manual frame-tree
-- dumps that the real per-achievement "Legacy Point" value (the shield
-- badge shown in the Legacy Challenges panel) is NOT available through any
-- documented API - GetAchievementInfo's own points field is unrelated and
-- wrong (0 for achievements confirmed to award real points in game), there's
-- no C_Legacy* table, and LegacyTreeData is just the 3 tree-tab definitions,
-- not per-achievement data. The ONLY place this number exists is the
-- rendered UI itself: each achievement row is a Button whose regionTexts are
-- [name, description, description] (the description appears twice), with a
-- child Button whose own regionText is just the point value on its own
-- (e.g. "1"). This walks whatever's currently rendered under
-- LegacySystemFrame and caches every point value it finds by achievement
-- name into WFTSyncDB.legacyPointValues - same "opportunistic capture,
-- builds up over multiple views" pattern as the recipe capture below, since
-- Blizzard only renders whichever rows are currently visible/scrolled to.
-- Hooked to run passively (see the OnUpdate frame right after this) so it
-- fills in on its own as you browse each category tab, with no slash
-- command needed.
local function scanLegacyPointsFromUI()
    local frame = _G.LegacySystemFrame
    if not frame or not frame.IsShown or not frame:IsShown() then
        return 0
    end

    local found = 0
    local budget = { count = 0 }

    local function walk(f, depth)
        if not f or depth > 8 or budget.count > 3000 then
            return
        end
        local ok, children = pcall(function()
            return { f:GetChildren() }
        end)
        if not ok or not children then
            return
        end
        for _, child in ipairs(children) do
            budget.count = budget.count + 1
            if budget.count > 3000 then
                return
            end
            local okType, objType = pcall(function()
                return child.GetObjectType and child:GetObjectType()
            end)
            if okType and objType == "Button" then
                local texts = regionTexts(child, budget)
                if #texts >= 3 and texts[2] == texts[3] then
                    local name = texts[1]
                    local okKids, kids = pcall(function()
                        return { child:GetChildren() }
                    end)
                    if okKids and kids then
                        for _, kid in ipairs(kids) do
                            local okKidType, kidType = pcall(function()
                                return kid.GetObjectType and kid:GetObjectType()
                            end)
                            if okKidType and kidType == "Button" then
                                local kidTexts = regionTexts(kid, budget)
                                if #kidTexts == 1 and tonumber(kidTexts[1]) then
                                    WFTSyncDB = WFTSyncDB or {}
                                    WFTSyncDB.legacyPointValues = WFTSyncDB.legacyPointValues or {}
                                    WFTSyncDB.legacyPointValues[name] = tonumber(kidTexts[1])
                                    found = found + 1
                                end
                            end
                        end
                    end
                end
            end
            walk(child, depth + 1)
        end
    end

    walk(frame, 0)
    return found
end

local legacyPointsScanFrame = CreateFrame("Frame")
local legacyPointsScanElapsed = 0
legacyPointsScanFrame:SetScript("OnUpdate", function(_, elapsed)
    -- scanLegacyPointsFromUI already bails out instantly (IsShown check)
    -- when the panel's closed, but throttling to once/second avoids walking
    -- the whole frame tree every single frame while it IS open.
    legacyPointsScanElapsed = legacyPointsScanElapsed + elapsed
    if legacyPointsScanElapsed < 1 then
        return
    end
    legacyPointsScanElapsed = 0
    pcall(scanLegacyPointsFromUI)
end)

-- Legacy Challenge icons, straight off the rendered UI (2026-09-30) - same
-- workaround as scanLegacyPointsFromUI above, needed for the same reason:
-- GetAchievementInfo's icon return value is confirmed nil for every one of
-- the 111 Legacy Challenge achievements on this server (/wft
-- achievementsprobe's icon check - 0 with an icon value, 111 without), even
-- though the icon clearly renders fine in the real in-game panel. /wft
-- iconprobe was used to find it: each achievement row Button has ~14-16
-- Texture regions, and comparing rows with visibly different icons (Explore
-- Azeroth/Eastern Kingdoms/Kalimdor, and separately the Journeyman/Expert/
-- Artisan Alchemist tiers) showed the exact same set of "decoration" texture
-- IDs on every row (background, border, checkmark, glow, etc.) with EXACTLY
-- ONE value that actually changed between different achievements - that's
-- the real per-achievement icon. This set was confirmed identical across two
-- unrelated categories, so it's hardcoded as an exclude list below: whatever
-- texture ID survives after removing every known-shared one is the icon.
-- Same "opportunistic capture, builds up as you browse" pattern as the point
-- values - only whichever rows are actually on screen get scanned, so this
-- fills in the more of the 111 you've looked at, not necessarily all of them
-- on the first pass.
local LEGACY_ROW_SHARED_TEXTURES = {
    [8419586] = true,
    [8285993] = true,
    [8285995] = true, -- appears multiple times per row, at a few different sizes - still always shared decoration, never the icon
    [8063723] = true,
    [8281590] = true, -- appears twice per row
    [1339312] = true,
    [130750] = true,
    [130751] = true,
    [130752] = true,
    [130753] = true,
    [130755] = true,
}

local function scanLegacyIconsFromUI()
    local frame = _G.LegacySystemFrame
    if not frame or not frame.IsShown or not frame:IsShown() then
        return 0
    end

    local found = 0
    local budget = { count = 0 }

    local function candidateIconFrom(textures)
        -- Collects every texture VALUE on this row that isn't in the known
        -- shared-decoration set, de-duped (the same icon texture can appear
        -- more than once on a row, e.g. a plain copy plus a desaturated
        -- "locked" version). Only commits to a result when exactly one
        -- distinct candidate survives - if zero or several remain, this row
        -- doesn't match the pattern confirmed via /wft iconprobe closely
        -- enough to trust, so it's skipped rather than risking a wrong icon
        -- (a still-missing icon is a much smaller problem than a WRONG one).
        local seen = {}
        local candidates = {}
        for _, t in ipairs(textures) do
            local tex = t.texture
            if type(tex) == "number" and not LEGACY_ROW_SHARED_TEXTURES[tex] and not seen[tex] then
                seen[tex] = true
                table.insert(candidates, tex)
            end
        end
        if #candidates == 1 then
            return candidates[1]
        end
        return nil
    end

    local function walk(f, depth)
        if not f or depth > 8 or budget.count > 3000 then
            return
        end
        local ok, children = pcall(function()
            return { f:GetChildren() }
        end)
        if not ok or not children then
            return
        end
        for _, child in ipairs(children) do
            budget.count = budget.count + 1
            if budget.count > 3000 then
                return
            end
            local okType, objType = pcall(function()
                return child.GetObjectType and child:GetObjectType()
            end)
            if okType and objType == "Button" then
                local texts = regionTexts(child, budget)
                if #texts >= 3 and texts[2] == texts[3] then
                    local name = texts[1]
                    local textures = regionTextures(child, budget)
                    local okKids, kids = pcall(function()
                        return { child:GetChildren() }
                    end)
                    if okKids and kids then
                        for _, kid in ipairs(kids) do
                            for _, t in ipairs(regionTextures(kid, budget)) do
                                table.insert(textures, t)
                            end
                        end
                    end
                    local icon = candidateIconFrom(textures)
                    if icon and name then
                        WFTSyncDB = WFTSyncDB or {}
                        WFTSyncDB.legacyIconValues = WFTSyncDB.legacyIconValues or {}
                        WFTSyncDB.legacyIconValues[name] = icon
                        found = found + 1
                    end
                end
            end
            walk(child, depth + 1)
        end
    end

    walk(frame, 0)
    return found
end

local legacyIconsScanFrame = CreateFrame("Frame")
local legacyIconsScanElapsed = 0
legacyIconsScanFrame:SetScript("OnUpdate", function(_, elapsed)
    legacyIconsScanElapsed = legacyIconsScanElapsed + elapsed
    if legacyIconsScanElapsed < 1 then
        return
    end
    legacyIconsScanElapsed = 0
    pcall(scanLegacyIconsFromUI)
end)

local function buildExport()
    local out = {}
    local tocversion = select(4, safeGet("GetBuildInfo"))
    local okDate, timestamp = safeCall(_G.date, "%Y-%m-%d %H:%M:%S")
    out.meta = {
        addonVersion = "1.8.9",
        tocversion = tocversion,
        exportedAt = okDate and timestamp or nil,
    }
    out.basic = collectBasic()
    out.stats = collectStats()
    out.professions = collectProfessions()
    out.gear = collectGear()
    local okBags, bagItems = pcall(collectContainerItems)
    out.bagItems = okBags and bagItems or nil
    local okTraits, traits = pcall(collectTraits)
    out.traits = okTraits and traits or { error = "collectTraits crashed: " .. tostring(traits) }
    -- Statistics pane data (see collectStatistics above) - never lets a
    -- crash there take down the whole export, same guard as collectTraits.
    local okStats, statistics = pcall(collectStatistics)
    out.statistics = okStats and statistics or nil
    -- Legacy Challenges (see collectLegacyAchievements above) - same
    -- never-crash-the-export guard.
    local okLegacy, legacyAchievements = pcall(collectLegacyAchievements)
    out.legacyAchievements = okLegacy and legacyAchievements or nil
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
    -- Running counters for deaths and PvP kills, incremented by the two
    -- event handlers below. These live here (not rebuilt from a live game
    -- API every export like everything else) because nothing on this
    -- server's client actually tracks them for us.
    WFTSyncDB.deathCount = WFTSyncDB.deathCount or 0
    WFTSyncDB.pvpKillCount = WFTSyncDB.pvpKillCount or 0
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
    "GetInventoryItemID",
    "C_Traits", "C_ClassTalents", "C_CurrencyInfo", "ToggleLegacySystemUI", "C_PaperDollInfo",
    -- Added to check whether main spec / honor / PvP rank / Legacy points
    -- are readable at all on this server's client build, before writing
    -- any real collector code against them (see the chat discussion this
    -- was added for - these are guesses about what MIGHT exist, not
    -- confirmed to work here).
    "GetSpecialization", "GetSpecializationInfo", "GetNumSpecializations",
    "UnitHonor", "UnitHonorMax", "GetHonorCurrency", "UnitPVPRank", "GetPVPRankInfo",
    "GetPVPLifetimeStats", "GetPVPThisWeekStats",
    "WFTLegacyPoints", "GetLegacyPoints", "C_LegacySystem",
}

local function cmdProbe()
    print("|cffffcc00WFT probe - what this client actually has:|r")
    for _, name in ipairs(PROBE_LIST) do
        local v = _G[name]
        local kind = type(v)
        print(("  %s: %s"):format(name, v == nil and "MISSING" or kind))
    end
end

-- Diagnostic-only, added 2026-09-25 after the two-word-name sync error
-- persisted for at least one character even after switching collectBasic()
-- to prefer UnitFullName - need the actual VALUE it returns for THIS
-- character, not just whether the function exists (cmdProbe only checks
-- that). Never touches buildExport()'s real output, so per the version-bump
-- skill this doesn't need a version bump.
local function cmdNameProbe()
    print("|cffffcc00WFT nameprobe:|r")
    local name = safeGet("UnitName", "player")
    print(("  UnitName(player): %s"):format(name == nil and "nil/call failed" or ("[" .. tostring(name) .. "]")))
    local full = safeGet("UnitFullName", "player")
    print(("  UnitFullName(player): %s"):format(full == nil and "nil/call failed" or ("[" .. tostring(full) .. "]")))
    if type(full) == "string" then
        local bytes = {}
        for i = 1, #full do
            table.insert(bytes, string.byte(full, i))
        end
        print(("  UnitFullName length: %d, bytes: %s"):format(#full, table.concat(bytes, ",")))
    end

    -- Both UnitName and UnitFullName came back as just "Xeon" for a
    -- character confirmed to actually be "Xeon Mana" - same client-side
    -- truncation at the first space that some emulator cores hit, since
    -- Blizzard's own client never expected a space in a unit name. A
    -- tooltip is server-rendered text read straight off font strings, not
    -- parsed by that same name code, so it may still show the real full
    -- name even when the unit-name API's don't - same trick this addon
    -- already uses to get real item names/stats around the missing
    -- item-cache API. Reuses the same hidden scanTip this addon already
    -- has set up for item tooltips.
    if scanTip then
        local ok = pcall(function()
            scanTip:SetOwner(UIParent, "ANCHOR_NONE")
            scanTip:ClearLines()
            scanTip:SetUnit("player")
        end)
        if ok then
            print("  Player unit tooltip lines:")
            for i = 1, 6 do
                local left = _G["WFTScanTooltipTextLeft" .. i]
                if not left then
                    break
                end
                local text = left:GetText()
                if text and text ~= "" then
                    print(("    [%d] %s"):format(i, stripMarkup(text)))
                end
            end
        else
            print("  Player unit tooltip: SetUnit(\"player\") failed")
        end
    else
        print("  Player unit tooltip: scanTip not available")
    end
end

-- Records a manually-confirmed "First Last" name into SavedVariables, so
-- collectBasic() can use it forever after regardless of whether
-- UnitFullName/the player's own tooltip can see the real surname (both are
-- unreliable here - see the comment above collectBasic). This is the actual
-- fix for the two-word-name sync failures; the tooltip auto-detect is only
-- a nice-to-have for players who happen to have "My Secondary Name" on.
local function cmdSetName(rest)
    rest = (rest or ""):match("^%s*(.-)%s*$")
    if rest == "" then
        local current = type(WFTSyncDB) == "table" and WFTSyncDB.nameOverride
        if current then
            print(("|cffffcc00WFT:|r your saved full name is currently \"%s\". Run /wft setname First Last to change it."):format(current))
        else
            print("|cffffcc00WFT:|r no full name saved yet. Run /wft setname First Last (e.g. /wft setname Xeon Mana) using your character's real in-game first and last name.")
        end
        return
    end
    local first, last = rest:match("^(%S+)%s+(%S+)$")
    if not first then
        print("|cffff0000WFT:|r that needs to be exactly two words - your character's first name and last name, e.g. /wft setname Xeon Mana")
        return
    end
    if type(WFTSyncDB) ~= "table" then
        WFTSyncDB = {}
    end
    WFTSyncDB.nameOverride = first .. " " .. last
    print(("|cffffcc00WFT:|r saved \"%s %s\" as your full name - every sync from now on will use this."):format(first, last))
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

-- Diagnostic-only, for figuring out if PvP rank is readable at all on this
-- server's client build - GetPVPLifetimeStats existed on the /wft probe
-- list but its return values are unknown without printing them, and
-- UnitPVPRank/GetPVPRankInfo (the normal rank-number APIs) came back
-- missing. Never feeds into the real export.
local function cmdPvpDump()
    print("|cffffcc00WFT pvpdump - raw PvP-related return values:|r")
    local r1, r2, r3, r4, r5, r6 = safeGet("GetPVPLifetimeStats")
    print(("  GetPVPLifetimeStats(): %s, %s, %s, %s, %s, %s"):format(
        tostring(r1), tostring(r2), tostring(r3), tostring(r4), tostring(r5), tostring(r6)
    ))
    local weekR1, weekR2, weekR3 = safeGet("GetPVPThisWeekStats")
    print(("  GetPVPThisWeekStats(): %s, %s, %s"):format(tostring(weekR1), tostring(weekR2), tostring(weekR3)))
end

-- Diagnostic-only, for figuring out whether specs moved to the newer
-- C_SpecializationInfo namespace on this client (GetSpecialization and
-- GetSpecializationInfo came back missing from /wft probe, but
-- GetNumSpecializations didn't - suggesting a partial/renamed API rather
-- than specs being unavailable entirely). Never feeds into the real export.
local function cmdSpecProbe()
    print("|cffffcc00WFT specprobe - looking for a spec API on this client:|r")
    local numSpecs = safeGet("GetNumSpecializations")
    print(("  GetNumSpecializations(): %s"):format(tostring(numSpecs)))

    local CSpec = _G.C_SpecializationInfo
    if type(CSpec) ~= "table" then
        print("  C_SpecializationInfo: MISSING")
    else
        print("  C_SpecializationInfo: table")
        for _, fn in ipairs({ "GetSpecialization", "GetSpecializationInfo", "GetNumSpecializations" }) do
            print(("    C_SpecializationInfo.%s: %s"):format(fn, type(CSpec[fn])))
        end
        if type(CSpec.GetSpecialization) == "function" then
            local ok, specIndex = pcall(CSpec.GetSpecialization)
            print(("  C_SpecializationInfo.GetSpecialization() -> ok=%s, value=%s"):format(tostring(ok), tostring(specIndex)))
            if ok and specIndex and type(CSpec.GetSpecializationInfo) == "function" then
                local okInfo, id, name = pcall(CSpec.GetSpecializationInfo, specIndex)
                print(("  C_SpecializationInfo.GetSpecializationInfo(%s) -> ok=%s, id=%s, name=%s"):format(
                    tostring(specIndex), tostring(okInfo), tostring(id), tostring(name)
                ))
            end
        end
    end
end

----------------------------------------------------------------------
-- Recipes known
----------------------------------------------------------------------
-- Neither the old nor the new profession API can tell you what recipes a
-- character knows without that profession's trade skill window actually
-- being open - there's no "peek at someone's recipe list" call. So this
-- only ever captures whatever's visible the moment the window opens, and
-- recipe data is only ever as fresh as the last time you opened each
-- profession before syncing. Captured recipes are merged into whatever
-- was already known for that profession (never replaced outright), so a
-- partial or differently-ordered read on a later visit can't lose ones
-- seen before.

-- The old (classic-style) trade skill window API only ever lists recipes
-- you already know - there's no way through it to see one you haven't
-- learned, so every non-header entry it returns is known by definition.
-- Every entry this file deals with from here on is a table shaped like
-- { name, icon, id, reagents, tooltip } (icon/id/reagents/tooltip are all
-- optional), never a bare string.

-- Reuses the exact same hidden tooltip and stripMarkup helper that gear
-- tooltips already scan with (see scanTip/scanSlotTooltip above) - this
-- used to create its OWN second "WFTScanTooltip" frame, which was a real
-- bug: CreateFrame with a name already in use re-registers that global
-- name to point at the new frame's child FontStrings, so scanSlotTooltip's
-- own _G["WFTScanTooltipTextLeft"..i] lookups would have started reading
-- (empty/stale) text from this frame instead of gear's, silently breaking
-- gear tooltips. One shared frame, used one call at a time, is correct.
-- Quality color is read straight off the item's name-line color (line 1),
-- same trick scanSlotTooltip uses, since this server's items don't
-- reliably carry it any other way.
local function scanItemTooltip(itemID)
    if not scanTip or not itemID then
        return nil, nil
    end
    local lines = {}
    local qualityColor
    local ok = pcall(function()
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
        scanTip:ClearLines()
        scanTip:SetItemByID(itemID)
    end)
    if not ok then
        return nil, nil
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
        local text = stripMarkup(left:GetText())
        if text and text ~= "" then
            table.insert(lines, text)
        end
    end
    return #lines > 0 and lines or nil, qualityColor
end

-- GetItemInfo/GetItemInfoInstant/GetItemIcon all come back nil for plain
-- classic items on this server's client (confirmed via /wft recipedump -
-- every reagent tested came back with no icon and a fallback "Item #NNNN"
-- name, even for ordinary items like Rough Stone that any client can
-- normally resolve instantly). Tries a couple of newer C_Item equivalents
-- in case this client exposes one of those instead - same "try every
-- plausible name" approach that found the working profession-name API.
local function resolveItemIcon(itemID)
    local icon = safeGet("GetItemIcon", itemID)
    if icon then
        return icon
    end
    local _, _, _, _, instantIcon = safeGet("GetItemInfoInstant", itemID)
    if instantIcon then
        return instantIcon
    end
    local CItem = _G.C_Item
    if type(CItem) == "table" then
        for _, fnName in ipairs({ "GetItemIconByID", "GetItemIcon" }) do
            if type(CItem[fnName]) == "function" then
                local ok, result = pcall(CItem[fnName], itemID)
                if ok and result then
                    return result
                end
            end
        end
    end
    return nil
end

-- The required-reagent list for a recipe, via the modern schematic API
-- confirmed working on this server through /wft recipeschema (2026-09-21):
-- C_TradeSkillUI.GetRecipeSchematic(recipeID, false).reagentSlotSchematics,
-- each slot's FIRST reagent option (a slot can technically offer several
-- interchangeable reagents - there's no site UI yet for "any of these", so
-- the default/first one shown in-game is what's recorded). Also hands back
-- outputItemID, since that's what the tooltip scan needs to run against.
local function collectRecipeReagents(recipeID)
    local CTradeSkillUI = _G.C_TradeSkillUI
    if type(CTradeSkillUI) ~= "table" or type(CTradeSkillUI.GetRecipeSchematic) ~= "function" then
        return nil, nil
    end
    local ok, schematic = pcall(CTradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok or type(schematic) ~= "table" or type(schematic.reagentSlotSchematics) ~= "table" then
        return nil, nil
    end
    local reagents = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        local reagent = type(slot.reagents) == "table" and slot.reagents[1]
        if reagent and reagent.itemID then
            -- SetItemByID + reading the tooltip (the same trick already
            -- relied on for gear and the recipe's own description) DOES
            -- reliably reach this item's real data on this server, even
            -- when GetItemInfo can't - so its first line (the item's own
            -- name) is used ahead of the "Item #NNNN" placeholder.
            local tooltip, color = scanItemTooltip(reagent.itemID)
            local tooltipName = tooltip and tooltip[1]
            local name = safeGet("GetItemInfo", reagent.itemID)
            local icon = resolveItemIcon(reagent.itemID)
            table.insert(reagents, {
                itemID = reagent.itemID,
                name = name or tooltipName or ("Item #" .. reagent.itemID),
                icon = icon,
                quantity = slot.quantityRequired or 1,
                color = color,
            })
        end
    end
    return (#reagents > 0 and reagents or nil), schematic.outputItemID
end

local function collectRecipesFromClassicAPI()
    local numSkills = safeGet("GetNumTradeSkills")
    if not numSkills or numSkills <= 0 then
        return nil
    end
    local recipes = {}
    for i = 1, numSkills do
        local name, skillType = safeGet("GetTradeSkillInfo", i)
        if name and skillType ~= "header" and skillType ~= "subheader" then
            -- GetTradeSkillIcon returns a full "Interface\Icons\Foo" path on
            -- this API, not a fileID - left nil rather than guessing at a
            -- string format nothing else in this file uses.
            table.insert(recipes, { name = name })
        end
    end
    return recipes
end

-- The modern (retail-style) profession API can list recipes you haven't
-- learned yet too (shown greyed out), so each one has to be checked
-- individually through its `learned` field rather than assuming presence
-- in the list means known.
local function collectRecipesFromModernAPI()
    local CTradeSkillUI = _G.C_TradeSkillUI
    if type(CTradeSkillUI) ~= "table" or type(CTradeSkillUI.GetAllRecipeIDs) ~= "function" then
        return nil
    end
    local okIDs, ids = pcall(CTradeSkillUI.GetAllRecipeIDs)
    if not okIDs or type(ids) ~= "table" then
        return nil
    end
    local recipes = {}
    for _, recipeID in ipairs(ids) do
        local okInfo, info = pcall(CTradeSkillUI.GetRecipeInfo, recipeID)
        if okInfo and type(info) == "table" and info.learned and info.name then
            local reagents, outputItemID = collectRecipeReagents(recipeID)
            local tooltip, color = scanItemTooltip(outputItemID)
            table.insert(recipes, {
                name = info.name,
                icon = info.icon,
                id = recipeID,
                reagents = reagents,
                tooltip = tooltip,
                color = color,
            })
        end
    end
    return recipes
end

-- Which profession's window is currently open, so a captured list gets
-- filed under the right profession name. Confirmed via /wft recipeprobe
-- that GetTradeSkillLine is missing entirely on this client (both the old
-- global and the C_TradeSkillUI version) even though C_TradeSkillUI.
-- GetAllRecipeIDs/GetRecipeInfo do exist - so this tries several other
-- ways a modern profession API can expose the open window's name before
-- giving up.
local function currentTradeSkillProfessionName()
    local name = safeGet("GetTradeSkillLine")
    if name then
        return name
    end
    local CTradeSkillUI = _G.C_TradeSkillUI
    if type(CTradeSkillUI) == "table" then
        if type(CTradeSkillUI.GetTradeSkillLine) == "function" then
            local okName, n = pcall(CTradeSkillUI.GetTradeSkillLine)
            if okName and n then
                return n
            end
        end
        -- Dragonflight-era profession API: the currently open profession's
        -- details, if this client has it.
        for _, fnName in ipairs({ "GetBaseProfessionInfo", "GetChildProfessionInfo" }) do
            if type(CTradeSkillUI[fnName]) == "function" then
                local okInfo, info = pcall(CTradeSkillUI[fnName])
                if okInfo and type(info) == "table" then
                    local n = info.professionName or info.name
                    if n then
                        return n
                    end
                end
            end
        end
    end
    return nil
end

-- Runs whenever a trade skill window opens (or on demand via
-- /wft recipescan while one's already open). manualName lets the slash
-- command override auto-detection entirely (e.g. /wft recipescan
-- Blacksmithing) - useful given the auto-detection above already turned
-- out to need several fallbacks on this server; a manual name always
-- works regardless of which API this client actually has. Returns ok,
-- profession-or-error-message, known-count, newly-added-count - mirrored
-- by cmdRecipeScan below so the same function backs both the automatic
-- and manual paths.
local function captureRecipes(manualName)
    local profession = manualName or currentTradeSkillProfessionName()
    if not profession then
        return false, "couldn't tell which profession is open - try /wft recipescan <profession name>, e.g. /wft recipescan Blacksmithing"
    end
    local recipes = collectRecipesFromClassicAPI() or collectRecipesFromModernAPI()
    if not recipes or #recipes == 0 then
        return false, "no recipes found (neither the classic nor modern profession API returned any)"
    end
    local db = ensureSyncDB()
    db.recipes = db.recipes or {}
    -- Rebuilt fresh every scan (rather than mutated in place) so any
    -- pre-1.3.0 bare-string entries get upgraded to the { name, icon, id }
    -- shape here too, not just at export time.
    local knownRaw = db.recipes[profession] or {}
    local known = {}
    local byName = {}
    for _, r in ipairs(knownRaw) do
        local nr = normalizeRecipeEntry(r)
        table.insert(known, nr)
        byName[nr.name] = nr
    end
    local added = 0
    for _, r in ipairs(recipes) do
        local existing = byName[r.name]
        if not existing then
            byName[r.name] = r
            table.insert(known, r)
            added = added + 1
        else
            -- Same recipe seen again - refresh whatever this scan managed
            -- to fill in, without creating a duplicate entry. Reagents and
            -- tooltip text are always taken from the newest scan (an item
            -- info lookup can resolve more completely on a later attempt
            -- once the client's item cache has warmed up); icon/id are
            -- only ever filled in if missing, since those don't change.
            existing.icon = existing.icon or r.icon
            existing.id = existing.id or r.id
            if r.reagents then existing.reagents = r.reagents end
            if r.tooltip then existing.tooltip = r.tooltip end
            if r.color then existing.color = r.color end
        end
    end
    db.recipes[profession] = known
    return true, profession, #known, added
end

local recipeFrame = CreateFrame("Frame")
pcall(recipeFrame.RegisterEvent, recipeFrame, "TRADE_SKILL_SHOW")
recipeFrame:SetScript("OnEvent", function(_, event)
    if event == "TRADE_SKILL_SHOW" then
        -- A short delay: the window firing this event doesn't guarantee
        -- its recipe list has actually finished populating yet on every
        -- client. C_Timer is part of the same retail API surface the rest
        -- of this file already leans on, so it should be safe here too.
        local Timer = _G.C_Timer
        if type(Timer) == "table" and type(Timer.After) == "function" then
            Timer.After(0.5, function()
                pcall(captureRecipes)
            end)
        else
            pcall(captureRecipes)
        end
    end
end)

-- Checks which recipe-listing API this client actually has, without
-- needing a trade skill window open. Diagnostic only - never feeds the
-- real export.
local function cmdRecipeProbe()
    print("|cffffcc00WFT recipeprobe - looking for a recipe-listing API on this client:|r")
    print(("  GetNumTradeSkills: %s"):format(type(_G.GetNumTradeSkills)))
    print(("  GetTradeSkillInfo: %s"):format(type(_G.GetTradeSkillInfo)))
    print(("  GetTradeSkillLine: %s"):format(type(_G.GetTradeSkillLine)))
    local CTradeSkillUI = _G.C_TradeSkillUI
    if type(CTradeSkillUI) ~= "table" then
        print("  C_TradeSkillUI: MISSING")
    else
        print("  C_TradeSkillUI: table")
        for _, fn in ipairs({
            "GetAllRecipeIDs", "GetRecipeInfo", "GetTradeSkillLine",
            "GetBaseProfessionInfo", "GetChildProfessionInfo",
        }) do
            print(("    C_TradeSkillUI.%s: %s"):format(fn, type(CTradeSkillUI[fn])))
        end
    end
    print("  Item-info functions used for reagent name/icon lookups:")
    print(("    GetItemInfo: %s"):format(type(_G.GetItemInfo)))
    print(("    GetItemIcon: %s"):format(type(_G.GetItemIcon)))
    print(("    GetItemInfoInstant: %s"):format(type(_G.GetItemInfoInstant)))
    local CItem = _G.C_Item
    if type(CItem) ~= "table" then
        print("    C_Item: MISSING")
    else
        print("    C_Item: table")
        for _, fn in ipairs({ "GetItemIconByID", "GetItemIcon", "GetItemInfoInstant" }) do
            print(("      C_Item.%s: %s"):format(fn, type(CItem[fn])))
        end
    end
    print("  Open a profession window, then run /wft recipescan to actually try reading it.")
end

-- Checks whether this client can hand back a recipe's tooltip description
-- and reagent list, not just its name - needed before building full
-- tooltip display (with reagents) on the website. Diagnostic only, run
-- with a profession window open; needs at least one recipe already
-- recorded via /wft recipescan first, so it knows a real recipeID to test
-- against instead of guessing at API shape blind - the same "check before
-- assuming" approach recipeprobe used, since GetTradeSkillLine turned out
-- to be missing despite looking like it should exist.
local function cmdRecipeSchema()
    local CTradeSkillUI = _G.C_TradeSkillUI
    if type(CTradeSkillUI) ~= "table" then
        print("|cffff0000WFT recipeschema:|r C_TradeSkillUI is not available on this client.")
        return
    end

    -- Find a recipeID to test with: prefer one already captured (has .id
    -- from a scan taken after this version), otherwise pull the first
    -- learned one straight from GetAllRecipeIDs right now.
    local testID = nil
    local db = type(WFTSyncDB) == "table" and WFTSyncDB.recipes or nil
    if type(db) == "table" then
        for _, list in pairs(db) do
            for _, r in ipairs(list) do
                local nr = normalizeRecipeEntry(r)
                if nr.id then
                    testID = nr.id
                    break
                end
            end
            if testID then break end
        end
    end
    if not testID and type(CTradeSkillUI.GetAllRecipeIDs) == "function" then
        local okIDs, ids = pcall(CTradeSkillUI.GetAllRecipeIDs)
        if okIDs and type(ids) == "table" then
            for _, recipeID in ipairs(ids) do
                local okInfo, info = pcall(CTradeSkillUI.GetRecipeInfo, recipeID)
                if okInfo and type(info) == "table" and info.learned then
                    testID = recipeID
                    break
                end
            end
        end
    end

    if not testID then
        print("|cffff0000WFT recipeschema:|r couldn't find a known recipeID to test with - open a profession window and try /wft recipescan first.")
        return
    end

    print(("|cffffcc00WFT recipeschema:|r testing against recipeID %d"):format(testID))

    print("  Full GetRecipeInfo(id) table:")
    local okInfo, info = pcall(CTradeSkillUI.GetRecipeInfo, testID)
    if okInfo and type(info) == "table" then
        dumpTable(info)
    else
        print("    call failed or returned no table")
    end

    for _, fnName in ipairs({ "GetRecipeSchematic", "GetRecipeReagents", "GetRecipeDescription", "GetRecipeFixedReagents" }) do
        local fn = CTradeSkillUI[fnName]
        print(("  C_TradeSkillUI.%s: %s"):format(fnName, type(fn)))
        if type(fn) == "function" then
            local ok, result = pcall(fn, testID, false)
            if not ok then
                ok, result = pcall(fn, testID)
            end
            if ok and type(result) == "table" then
                print("    result (table):")
                dumpTable(result, "      ")
            elseif ok then
                print(("    result: %s (%s)"):format(tostring(result), type(result)))
            else
                print("    call failed")
            end
        end
    end

    print("  Paste all of the above back so the reagent/description format can be matched to this client.")
end

-- Dumps exactly what's cached for one profession's recipes, reagents
-- included - diagnostic only, run this and paste the output back when
-- something about a recipe (icon, name, color) looks wrong on the website,
-- so we can see the real captured values instead of guessing which API
-- call produced them.
local function cmdRecipeDump(profession)
    if not profession or profession == "" then
        print("|cffff0000WFT recipedump:|r pass a profession name, e.g. /wft recipedump Leatherworking")
        return
    end
    local db = type(WFTSyncDB) == "table" and WFTSyncDB.recipes or nil
    -- Profession names are stored exactly as WoW's own GetProfessionInfo
    -- capitalizes them (e.g. "Blacksmithing"), but it's easy to type one
    -- in lowercase without thinking - matched case-insensitively here so
    -- that doesn't look like "nothing was ever recorded".
    local list, realName
    if type(db) == "table" then
        for name, l in pairs(db) do
            if name:lower() == profession:lower() then
                list, realName = l, name
                break
            end
        end
    end
    if not list or #list == 0 then
        print(("|cffff0000WFT recipedump:|r no recipes recorded yet for %s"):format(profession))
        return
    end
    print(("|cffffcc00WFT recipedump:|r %s has %d recorded recipe(s):"):format(realName, #list))
    dumpTable(list)
end

-- Manually runs the same recipe capture the TRADE_SKILL_SHOW handler runs
-- automatically - use this while a profession window is open, in case
-- that event doesn't fire the way expected on this server. Pass a
-- profession name (e.g. /wft recipescan Blacksmithing) to skip
-- auto-detecting which window is open entirely and file the results under
-- that name directly.
local function cmdRecipeScan(manualName)
    local ok, a, b, c = captureRecipes(manualName)
    if ok then
        print(("|cffffcc00WFT recipescan:|r %s - %d known recipe(s) recorded (%d new this scan)"):format(a, b, c))
    else
        print(("|cffffcc00WFT recipescan:|r couldn't read recipes - %s"):format(tostring(a)))
    end
end

-- Prints the current running death/PvP kill counts, so you can die or get a
-- kill in-game and immediately check whether the counter actually moved,
-- without waiting for a sync to see it show up on the website.
local function cmdCounters()
    local db = ensureSyncDB()
    print("|cffffcc00WFT counters:|r")
    print(("  Deaths: %d"):format(db.deathCount or 0))
    print(("  PvP kills: %d (tracking paused - see the addon file's notes)"):format(db.pvpKillCount or 0))
end

-- /wft statsprobe - see if this client exposes the game's Statistics pane
-- (the character-sheet tab covering combat/PvP/economy/professions/quests/
-- dungeons/emotes totals - see the 2026-09-25 Wowhead post about it going
-- live in the beta). CONFIRMED working 2026-09-25: GetStatisticsCategoryList
-- returns the real stat category tree (Battlegrounds, Wealth, Boss Kills,
-- Consumables, Professions, Combat, Reputation, Deaths, Quests, Skills,
-- Travel, Social, etc. - matches the patch notes almost exactly), and each
-- row's actual current value comes from GetStatistic(id) - NOT from
-- GetAchievementInfo's description field, which for a statistics row just
-- repeats the row's own name rather than a number. This probes every
-- name/shape this addon knows of, walks the category tree, and samples a
-- few rows (name + real value) out of each category. Purely diagnostic:
-- never touches buildExport(), never written to your character or the
-- website on its own.
local STATS_PROBE_GLOBALS = {
    "GetCategoryList", "GetStatisticsCategoryList", "GetCategoryInfo",
    "GetCategoryNumAchievements", "GetAchievementInfo", "GetStatistic",
    "GetAchievementNumCriteria", "GetAchievementCriteriaInfo",
}

-- How many sample rows to pull out of each category - enough to see the
-- shape of the data without the dump becoming unmanageable across what
-- could be a hundred-plus categories (Combat, PvP, Economy, Professions,
-- Quests & Travel, Dungeons & Raids, Emotes, etc. per the patch notes).
local STATS_PROBE_SAMPLE_SIZE = 5

local function collectStatsProbe()
    local out = { globals = {}, cAchievementInfoKeys = nil, categories = {} }

    for _, name in ipairs(STATS_PROBE_GLOBALS) do
        out.globals[name] = (type(_G[name]) == "function") and "function" or "MISSING"
    end

    -- List every key C_AchievementInfo actually has, rather than guessing
    -- modern method names - this client "runs the retail API surface"
    -- (see top-of-file note), and retail moved a lot of the old achievement
    -- globals onto this table, sometimes under renamed methods.
    local CAch = _G.C_AchievementInfo
    if type(CAch) == "table" then
        local keys = {}
        for k, v in pairs(CAch) do
            table.insert(keys, tostring(k) .. " (" .. type(v) .. ")")
        end
        table.sort(keys)
        out.cAchievementInfoKeys = keys
    end

    -- Prefer C_AchievementInfo's versions when they exist, falling back to
    -- the old globals - whichever is actually present on this client wins.
    local getCategoryList = (CAch and CAch.GetCategoryList) or _G.GetCategoryList
    local getStatCategoryList = (CAch and CAch.GetStatisticsCategoryList) or _G.GetStatisticsCategoryList
    local getCategoryInfo = (CAch and CAch.GetCategoryInfo) or _G.GetCategoryInfo
    local getCategoryNum = (CAch and CAch.GetCategoryNumAchievements) or _G.GetCategoryNumAchievements
    local getAchievementInfo = (CAch and CAch.GetAchievementInfo) or _G.GetAchievementInfo
    -- No C_AchievementInfo equivalent showed up in the cAchievementInfoKeys
    -- dump (2026-09-25 run), so this is only ever the plain global.
    local getStatistic = _G.GetStatistic

    -- Walks a list of category IDs, pulling name/parent/count and a small
    -- sample of rows out of each one. GetAchievementInfo's `description`
    -- turned out NOT to hold the stat's number for this client (confirmed
    -- 2026-09-25 - for a statistics row it just repeats the name, e.g.
    -- "Deaths in Alterac Valley" / "Deaths in Alterac Valley") - the actual
    -- current value comes from the separate GetStatistic(id) call instead,
    -- which returns it as a plain (already comma-formatted) string.
    local function walkCategoryIDs(ids, sourceLabel)
        if not ids then return end
        for _, catID in ipairs(ids) do
            local catOut = { id = catID, source = sourceLabel }
            if type(getCategoryInfo) == "function" then
                local ok, name, parentID = safeCall(getCategoryInfo, catID)
                if ok then
                    catOut.name = name
                    catOut.parentID = parentID
                end
            end
            local numEntries
            if type(getCategoryNum) == "function" then
                local okN, num = safeCall(getCategoryNum, catID, true)
                numEntries = okN and num or nil
                catOut.numEntries = numEntries
            end
            if type(getAchievementInfo) == "function" and numEntries and numEntries > 0 then
                catOut.sample = {}
                for i = 1, math.min(STATS_PROBE_SAMPLE_SIZE, numEntries) do
                    local okA, id, name, points, _completed, _month, _day, _year, description =
                        safeCall(getAchievementInfo, catID, i)
                    if okA then
                        local row = {
                            id = id,
                            name = name,
                            points = points,
                            description = description,
                        }
                        if type(getStatistic) == "function" and id then
                            local okV, value = safeCall(getStatistic, id)
                            if okV then
                                row.value = value
                            end
                        end
                        table.insert(catOut.sample, row)
                    end
                end
            end
            table.insert(out.categories, catOut)
        end
    end

    local okList, catIDs = safeCall(getCategoryList)
    if okList then
        walkCategoryIDs(catIDs, "GetCategoryList")
    end
    -- Only walk the statistics list separately if it's actually a different
    -- function - some client builds might fold Statistics into the same
    -- category tree GetCategoryList already returns.
    if getStatCategoryList and getStatCategoryList ~= getCategoryList then
        local okStatList, statIDs = safeCall(getStatCategoryList)
        if okStatList then
            walkCategoryIDs(statIDs, "GetStatisticsCategoryList")
        end
    end

    return out
end

local function cmdStatsProbe()
    print("|cffffcc00WFT statsprobe - checking for a Statistics API on this client:|r")
    local ok, data = pcall(collectStatsProbe)
    if not ok then
        print("|cffff0000WFT statsprobe error:|r " .. tostring(data))
        return
    end

    for _, name in ipairs(STATS_PROBE_GLOBALS) do
        print(("  %s: %s"):format(name, data.globals[name]))
    end
    if data.cAchievementInfoKeys then
        print("  C_AchievementInfo exists - functions/fields on it:")
        for _, k in ipairs(data.cAchievementInfoKeys) do
            print("    " .. k)
        end
    else
        print("  C_AchievementInfo: MISSING")
    end

    print(("  Found %d categor%s total - full detail (names, counts, and a few sample rows from each) is in the export window."):format(
        #data.categories, #data.categories == 1 and "y" or "ies"))
    if #data.categories == 0 then
        print("  Nothing came back at all - either open the character sheet's Statistics tab once this session first, or this client genuinely doesn't expose this API. Send me the full printed output above either way.")
    end

    local ok2, json = pcall(jsonEncode, data)
    if not ok2 then
        print("|cffff0000WFT statsprobe JSON error:|r " .. tostring(json))
        return
    end
    showExportWindow(json)
end

----------------------------------------------------------------------
-- /wft achievementsprobe (2026-09-27) - real Blizzard/server Achievements
-- (the "Novice Spelunker" / "Explore Azeroth" / "Conqueror of the Lair"
-- style entries under the Legacy Challenges panel), NOT the Statistics
-- pane. statsprobe above already confirmed GetCategoryList() (the real
-- achievement category tree) responds on this client - it walks that tree
-- too, just only sampling 5 rows per category and throwing away the
-- `completed` flag, since it was only ever checking whether Statistics
-- worked. This is a dedicated, fuller probe: every achievement in every
-- category (not just 5), with its real completion state AND its
-- per-criteria checklist (the individual dungeon/zone checkmarks seen in
-- the screenshots), so I can see the real ID/name/shape before writing a
-- production collector that would sync this on every export. Purely
-- diagnostic - never touches buildExport() or the website on its own.
-- Capped at ACHIEVEMENTS_PROBE_MAX total achievements dumped in full, so a
-- client that turns out to expose the FULL retail achievement list (tens
-- of thousands of entries) doesn't produce a paste box nobody can use -
-- category names/counts are still printed for everything either way, so
-- scale is visible even if the detail dump gets cut off.
local ACHIEVEMENTS_PROBE_MAX = 400

local function collectAchievementsProbe()
    local out = { categories = {}, achievements = {}, truncated = false, totalAchievements = 0 }

    local getCategoryList = _G.GetCategoryList
    local getCategoryInfo = _G.GetCategoryInfo
    local getCategoryNum = _G.GetCategoryNumAchievements
    local getAchievementInfo = _G.GetAchievementInfo
    local getNumCriteria = _G.GetAchievementNumCriteria
    local getCriteriaInfo = _G.GetAchievementCriteriaInfo

    if type(getCategoryList) ~= "function" then
        return out
    end
    local okList, catIDs = safeCall(getCategoryList)
    if not okList or not catIDs then
        return out
    end

    for _, catID in ipairs(catIDs) do
        local categoryName = tostring(catID)
        if type(getCategoryInfo) == "function" then
            local okInfo, name = safeCall(getCategoryInfo, catID)
            if okInfo and name and name ~= "" then
                categoryName = name
            end
        end

        local numEntries = 0
        if type(getCategoryNum) == "function" then
            local okN, num = safeCall(getCategoryNum, catID, true)
            if okN and type(num) == "number" then
                numEntries = num
            end
        end
        table.insert(out.categories, { id = catID, name = categoryName, numEntries = numEntries })
        out.totalAchievements = out.totalAchievements + numEntries

        if numEntries > 0 and type(getAchievementInfo) == "function" then
            for i = 1, numEntries do
                if #out.achievements >= ACHIEVEMENTS_PROBE_MAX then
                    out.truncated = true
                    break
                end
                -- 2026-09-30: added `icon` (10th return value) so this probe
                -- can actually show whether GetAchievementInfo is returning a
                -- usable icon fileID on this client - this diagnostic never
                -- captured it before, which is why an earlier probe dump
                -- looked like icons were missing when that was really just
                -- this command not asking for them.
                local okA, id, name, points, completed, _month, _day, _year, description, _flags, icon =
                    safeCall(getAchievementInfo, catID, i)
                if okA and id then
                    local row = {
                        id = id,
                        category = categoryName,
                        name = name,
                        completed = completed and true or false,
                        description = description,
                        icon = icon,
                        iconType = type(icon),
                    }
                    if type(getNumCriteria) == "function" then
                        local okC, numCriteria = safeCall(getNumCriteria, id)
                        if okC and type(numCriteria) == "number" and numCriteria > 0
                            and type(getCriteriaInfo) == "function" then
                            row.criteria = {}
                            for c = 1, numCriteria do
                                local okCi, criteriaString, _type, critCompleted =
                                    safeCall(getCriteriaInfo, id, c)
                                if okCi then
                                    table.insert(row.criteria, {
                                        text = criteriaString,
                                        completed = critCompleted and true or false,
                                    })
                                end
                            end
                        end
                    end
                    table.insert(out.achievements, row)
                end
            end
        end
    end

    return out
end

local function cmdAchievementsProbe()
    print("|cffffcc00WFT achievementsprobe - checking the real Achievements API (Legacy Challenges, not Statistics):|r")
    local ok, data = pcall(collectAchievementsProbe)
    if not ok then
        print("|cffff0000WFT achievementsprobe error:|r " .. tostring(data))
        return
    end

    print(("  %d categories, %d achievements total."):format(#data.categories, data.totalAchievements))
    for _, cat in ipairs(data.categories) do
        if cat.numEntries > 0 then
            print(("    %s (id %s): %d"):format(cat.name, tostring(cat.id), cat.numEntries))
        end
    end

    -- 2026-09-30: quick icon summary printed directly to chat, so this can
    -- be checked without having to read the full JSON dump - counts how
    -- many of the achievements actually captured in this probe got a
    -- non-nil icon value back from GetAchievementInfo, and prints the
    -- first few icon values seen (whatever type they came back as) so it's
    -- obvious whether this client is returning real fileIDs, some other
    -- shape (e.g. a texture path string), or nothing at all.
    do
        local withIcon, withoutIcon = 0, 0
        local samples = {}
        for _, a in ipairs(data.achievements) do
            if a.icon ~= nil and a.icon ~= false then
                withIcon = withIcon + 1
                if #samples < 5 then
                    table.insert(samples, ("%s (id %s): %s = %s"):format(a.name, tostring(a.id), a.iconType, tostring(a.icon)))
                end
            else
                withoutIcon = withoutIcon + 1
            end
        end
        print(("  Icon check: %d with an icon value, %d without (of %d sampled)."):format(withIcon, withoutIcon, #data.achievements))
        for _, s in ipairs(samples) do
            print("    " .. s)
        end
    end

    if data.truncated then
        print(("  Full detail capped at %d achievements (there are more) - category counts above are still complete though."):format(ACHIEVEMENTS_PROBE_MAX))
    end
    print("  Full detail (id, category, name, completed, per-criteria checklist) is in the export window - copy/paste the whole thing back.")

    local ok2, json = pcall(jsonEncode, data)
    if not ok2 then
        print("|cffff0000WFT achievementsprobe JSON error:|r " .. tostring(json))
        return
    end
    showExportWindow(json)
end

----------------------------------------------------------------------
-- /wft iconprobe (2026-09-30) - GetAchievementInfo's icon return value is
-- confirmed nil for every one of the 111 Legacy Challenge achievements on
-- this server (achievementsprobe's icon check above, run for real - 0 with
-- an icon value, 111 without). But the icon clearly DOES render in the real
-- in-game Legacy Challenges panel, so it must be readable some other way -
-- this hunts for it the same way scanLegacyPointsFromUI hunts for the real
-- Legacy Point value Blizzard also doesn't expose through the achievement
-- API: by walking the actual rendered UI. Run this with the Legacy
-- Challenges panel OPEN (any category tab, doesn't matter which) - it finds
-- each achievement row the same way scanLegacyPointsFromUI does (a Button
-- whose regionTexts are [name, description, description]) and this time
-- also grabs any Texture-region values sitting on that same row via
-- regionTextures, which is where the icon almost certainly lives even
-- though GetAchievementInfo won't hand it over. Purely diagnostic - never
-- touches buildExport() or WFTSyncDB.
local function collectIconProbe()
    local frame = _G.LegacySystemFrame
    if not frame or not frame.IsShown or not frame:IsShown() then
        return { error = "LegacySystemFrame isn't open - open the Legacy Challenges panel to any category tab first, then run this again." }
    end

    local rows = {}
    local budget = { count = 0 }

    local function walk(f, depth)
        if not f or depth > 8 or budget.count > 3000 or #rows >= 20 then
            return
        end
        local ok, children = pcall(function()
            return { f:GetChildren() }
        end)
        if not ok or not children then
            return
        end
        for _, child in ipairs(children) do
            if #rows >= 20 then return end
            budget.count = budget.count + 1
            if budget.count > 3000 then
                return
            end
            local okType, objType = pcall(function()
                return child.GetObjectType and child:GetObjectType()
            end)
            if okType and objType == "Button" then
                local texts = regionTexts(child, budget)
                if #texts >= 3 and texts[2] == texts[3] then
                    local textures = regionTextures(child, budget)
                    -- Also check the row's immediate child widgets (icons are
                    -- sometimes their own child Frame/Button with the actual
                    -- Texture region one level down, same as the point-value
                    -- button scanLegacyPointsFromUI finds under each row).
                    local okKids, kids = pcall(function()
                        return { child:GetChildren() }
                    end)
                    if okKids and kids then
                        for _, kid in ipairs(kids) do
                            for _, t in ipairs(regionTextures(kid, budget)) do
                                table.insert(textures, t)
                            end
                        end
                    end
                    table.insert(rows, { name = texts[1], textures = textures })
                end
            end
            walk(child, depth + 1)
        end
    end

    walk(frame, 0)
    return { rows = rows }
end

local function cmdIconProbe()
    print("|cffffcc00WFT iconprobe - hunting for the real Legacy Challenge icon in the rendered UI:|r")
    local ok, data = pcall(collectIconProbe)
    if not ok then
        print("|cffff0000WFT iconprobe error:|r " .. tostring(data))
        return
    end
    if data.error then
        print("  " .. data.error)
        return
    end
    if #data.rows == 0 then
        print("  No achievement rows found on screen right now - make sure a category with achievements is actually showing, then try again.")
        return
    end
    for _, row in ipairs(data.rows) do
        if #row.textures == 0 then
            print(("  %s: no Texture regions found."):format(row.name))
        else
            for _, t in ipairs(row.textures) do
                print(("  %s: texture=%s name=%s size=%s x %s"):format(
                    row.name,
                    tostring(t.texture),
                    tostring(t.name),
                    tostring(t.width),
                    tostring(t.height)
                ))
            end
        end
    end
    print("  Copy/paste all of the above lines back.")
end

----------------------------------------------------------------------
-- /wft legacypointsprobe (2026-09-27) - GetAchievementInfo's own `points`
-- field (already captured into every export since 1.8.7) turned out NOT to
-- be the same thing as the "Legacy Points" reward shown by each
-- achievement's shield-badge tooltip in game ("Earn 1 Legacy Point") -
-- proven wrong when achievements the website marked "No Legacy Points"
-- (Lord Valthalak Laid to Rest, Explorer, the Alchemy skill-rank ones) turned
-- out to genuinely award points in game. This hunts for wherever that real
-- number actually comes from instead of guessing again:
--   1. Every key on C_AchievementInfo - a separate, newer API namespace
--      /wft statsprobe already confirmed exists on this client - in case the
--      real points live behind a function there instead of the classic
--      GetAchievementInfo.
--   2. Any global function/table with "legacy" in its name, in case this
--      server added its own dedicated API for this.
--   3. Every achievement's own rewardText string (GetAchievementInfo's 11th
--      return value, never captured before now) in case it's spelled out
--      there as plain text ("Earn 1 Legacy Point") rather than a number
--      anywhere else.
-- Diagnostic only - doesn't touch buildExport()/the real sync data, so no
-- version bump needed (per the version-bump skill's own carve-out).
----------------------------------------------------------------------

local function cmdLegacyPointsProbe()
    print("|cffffcc00WFT legacypointsprobe - hunting for where 'Legacy Points' actually comes from:|r")

    local CAch = _G.C_AchievementInfo
    if CAch then
        local keys = {}
        for k in pairs(CAch) do
            table.insert(keys, tostring(k))
        end
        table.sort(keys)
        print(("  C_AchievementInfo has %d keys:"):format(#keys))
        for _, k in ipairs(keys) do
            print("    " .. k)
        end
    else
        print("  C_AchievementInfo: MISSING")
    end

    local legacyGlobals = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:lower():find("legacy") then
            table.insert(legacyGlobals, k .. " (" .. type(v) .. ")")
        end
    end
    table.sort(legacyGlobals)
    print(("  Global names containing 'legacy': %d"):format(#legacyGlobals))
    for _, g in ipairs(legacyGlobals) do
        print("    " .. g)
    end

    -- Full points/flags/rewardText dump for every achievement, into the
    -- export window (too much to print to chat directly) - copy/paste the
    -- whole thing back so the exact rewardText wording and flags for a
    -- KNOWN point-earner (e.g. "Explorer") can be checked directly.
    local getCategoryList = _G.GetCategoryList
    local getCategoryNum = _G.GetCategoryNumAchievements
    local getAchievementInfo = _G.GetAchievementInfo
    local rows = {}
    if type(getCategoryList) == "function" then
        local okList, catIDs = safeCall(getCategoryList)
        if okList and catIDs then
            for _, catID in ipairs(catIDs) do
                local numEntries = 0
                if type(getCategoryNum) == "function" then
                    local okN, num = safeCall(getCategoryNum, catID, true)
                    if okN and type(num) == "number" then
                        numEntries = num
                    end
                end
                if numEntries > 0 and type(getAchievementInfo) == "function" then
                    for i = 1, numEntries do
                        local okA, id, name, points, completed, _m, _d, _y, description, flags, icon, rewardText =
                            safeCall(getAchievementInfo, catID, i)
                        if okA and id then
                            table.insert(rows, {
                                id = id,
                                name = name,
                                points = points,
                                flags = flags,
                                rewardText = rewardText,
                            })
                        end
                    end
                end
            end
        end
    end
    print(("  Dumped %d achievements' points/flags/rewardText to the export window - copy/paste it back."):format(#rows))

    local ok2, json = pcall(jsonEncode, rows)
    if not ok2 then
        print("|cffff0000WFT legacypointsprobe JSON error:|r " .. tostring(json))
        return
    end
    showExportWindow(json)
end

----------------------------------------------------------------------
-- /wft legacysystemprobe (2026-09-27) - legacypointsprobe's global scan
-- found LEGACY_POINTS_AMOUNT/LEGACY_POINTS_CURR_MAX/LEGACY_POINTS_SEASONAL_CAP
-- and LegacySystemFrame_LoadUI/ToggleLegacySystemUI - that's Blizzard's own
-- built-in "Legacy System" UI module, a completely separate system from the
-- Achievements API this addon has been reading, and it's LAZY-LOADED (not in
-- memory until its panel is opened in game) - which is why nothing from its
-- real API showed up in that scan. This forces it to load, then checks
-- whether an addon and/or new globals appeared, so the real point-value API
-- can be found instead of guessed at again. Diagnostic only, no version bump.
----------------------------------------------------------------------

local function cmdLegacySystemProbe()
    print("|cffffcc00WFT legacysystemprobe - forcing the Legacy System UI to load:|r")

    if type(_G.LegacySystemFrame_LoadUI) == "function" then
        local ok, err = pcall(_G.LegacySystemFrame_LoadUI)
        print("  LegacySystemFrame_LoadUI() called, ok=" .. tostring(ok) .. (ok and "" or (" err=" .. tostring(err))))
    else
        print("  LegacySystemFrame_LoadUI is not a function - trying ToggleLegacySystemUI instead")
        if type(_G.ToggleLegacySystemUI) == "function" then
            local ok, err = pcall(_G.ToggleLegacySystemUI)
            print("  ToggleLegacySystemUI() called, ok=" .. tostring(ok) .. (ok and "" or (" err=" .. tostring(err))))
        end
    end

    local isLoaded = safeGet("IsAddOnLoaded", "Blizzard_LegacySystem")
    print("  Blizzard_LegacySystem addon loaded: " .. tostring(isLoaded))

    -- Common naming patterns Blizzard uses for a system's C_ API table -
    -- checked directly rather than guessed at in isolation, so this prints
    -- a clear yes/no for each rather than silence.
    local candidateTables = {
        "C_LegacySystem", "C_LegacyPoints", "C_LegacyChallenges", "C_LegacyRewardTrack", "C_LegacyReward",
    }
    for _, name in ipairs(candidateTables) do
        local t = _G[name]
        if type(t) == "table" then
            local keys = {}
            for k in pairs(t) do
                table.insert(keys, tostring(k))
            end
            table.sort(keys)
            print("  " .. name .. " EXISTS - keys: " .. table.concat(keys, ", "))
        else
            print("  " .. name .. ": missing")
        end
    end

    -- Full re-scan of every global with "legacy" in its name - compare this
    -- against the list legacypointsprobe already printed; anything new here
    -- only appeared after the force-load above, which is the real API.
    local legacyGlobals = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:lower():find("legacy") then
            table.insert(legacyGlobals, k .. " (" .. type(v) .. ")")
        end
    end
    table.sort(legacyGlobals)
    print(("  Full 'legacy' global list after force-load (%d) - compare against the legacypointsprobe list, anything new is the real API:"):format(#legacyGlobals))
    for _, g in ipairs(legacyGlobals) do
        print("    " .. g)
    end

    if _G.LegacySystemFrame then
        print("  LegacySystemFrame exists as a real frame object (was just a table entry before).")
    end
end

----------------------------------------------------------------------
-- /wft legacytreedatadump (2026-09-27) - legacysystemprobe's re-scan found
-- LegacyTreeData, a plain table (not a mixin/frame like everything else that
-- appeared) - almost certainly Blizzard's own static data mapping each
-- achievement to its Legacy Point value and category structure, shipped
-- with the Legacy System UI module rather than computed per-achievement via
-- an API call. Dumps it (bounded - frames/functions inside are common in
-- Blizzard UI tables and can be huge/self-referential, so this caps depth
-- and entry count rather than doing a raw, unbounded table dump). Diagnostic
-- only, no version bump.
----------------------------------------------------------------------

local function safeDumpValue(v, depth, budget)
    depth = depth or 0
    if depth > 5 or budget.count > 4000 then
        return "<truncated>"
    end
    local t = type(v)
    if t == "table" then
        local out = {}
        local n = 0
        for k, val in pairs(v) do
            n = n + 1
            budget.count = budget.count + 1
            if n > 40 or budget.count > 4000 then
                out["__truncated_after_" .. n .. "_entries"] = true
                break
            end
            out[tostring(k)] = safeDumpValue(val, depth + 1, budget)
        end
        return out
    elseif t == "function" then
        return "<function>"
    elseif t == "userdata" then
        return "<userdata>"
    else
        return v
    end
end

local function cmdLegacyTreeDataDump()
    print("|cffffcc00WFT legacytreedatadump - dumping LegacyTreeData:|r")
    local data = _G.LegacyTreeData
    if type(data) ~= "table" then
        print("  LegacyTreeData is not a table (type=" .. type(data) .. ") - nothing to dump. Run /wft legacysystemprobe first if you haven't this session.")
        return
    end

    local budget = { count = 0 }
    local ok, dumped = pcall(safeDumpValue, data, 0, budget)
    if not ok then
        print("|cffff0000WFT legacytreedatadump error:|r " .. tostring(dumped))
        return
    end

    local ok2, json = pcall(jsonEncode, dumped)
    if not ok2 then
        print("|cffff0000WFT legacytreedatadump JSON error:|r " .. tostring(json))
        return
    end
    print(("  Dumped %d table entries (capped) - copy/paste the export window back."):format(budget.count))
    showExportWindow(json)
end

----------------------------------------------------------------------
-- /wft legacyframetreedump (2026-09-27) - LegacyTreeData turned out to just
-- be the 3 tab definitions (Professions/Adventure/Resourcefulness - a
-- SPENDING tree for points, not the earning side), a dead end for finding
-- per-achievement point values. Rather than keep guessing table names, this
-- walks the REAL, currently-rendered widget tree under LegacySystemFrame
-- (only works while the Legacy Challenges panel is actually open, since
-- Blizzard's modern list UIs pool/recycle row frames - they don't exist
-- until shown) so the actual frame names can be read directly, same
-- philosophy as /fstack. Once we see a real row frame's name (e.g. some
-- "...Row3.PointsText" or a "...ScrollBox"), that's something a future
-- command can query directly instead of guessing. Diagnostic only, no
-- version bump.
----------------------------------------------------------------------

-- widgetOwnText/regionTexts now live up in the shared helpers section near
-- safeGet/safeCall (2026-09-27) - scanLegacyPointsFromUI needs them too, not
-- just this diagnostic.
local function dumpFrameTree(frame, depth, budget, out)
    if not frame or depth > 6 or budget.count > 600 then
        return
    end
    local ok, children = pcall(function()
        return { frame:GetChildren() }
    end)
    if not ok or not children then
        return
    end
    for _, child in ipairs(children) do
        budget.count = budget.count + 1
        if budget.count > 600 then
            table.insert(out, string.rep("  ", depth) .. "...(truncated at 600 widgets)")
            break
        end
        local okName, name = pcall(function()
            return child.GetName and child:GetName()
        end)
        local okType, objType = pcall(function()
            return child.GetObjectType and child:GetObjectType()
        end)
        local ownText = widgetOwnText(child)
        local texts = regionTexts(child, budget)
        local label = ((okName and name) or "<unnamed>") .. " [" .. ((okType and objType) or "?") .. "]"
        if ownText then
            label = label .. ' ownText="' .. ownText .. '"'
        end
        if #texts > 0 then
            label = label .. " regionTexts=[" .. table.concat(texts, " | ") .. "]"
        end
        table.insert(out, string.rep("  ", depth) .. label)
        dumpFrameTree(child, depth + 1, budget, out)
    end
end

local function cmdLegacyFrameTreeDump()
    print("|cffffcc00WFT legacyframetreedump - walking LegacySystemFrame's real widget tree:|r")
    local frame = _G.LegacySystemFrame
    if not frame or type(frame.GetChildren) ~= "function" then
        print("  LegacySystemFrame isn't a real frame yet - run /wft legacysystemprobe first this session.")
        return
    end
    local okShown, shown = pcall(function()
        return frame.IsShown and frame:IsShown()
    end)
    if okShown and not shown then
        print("  LegacySystemFrame isn't currently shown - open the Legacy Challenges panel in game FIRST, then run this command (recycled row frames don't exist until shown).")
        return
    end

    local out = {}
    local budget = { count = 0 }
    local ok, err = pcall(dumpFrameTree, frame, 0, budget, out)
    if not ok then
        print("|cffff0000WFT legacyframetreedump error:|r " .. tostring(err))
        return
    end
    print(("  %d widgets found - copy/paste the export window back."):format(#out))
    showExportWindow(table.concat(out, "\n"))
end

SLASH_WFT1 = "/wft"
SlashCmdList["WFT"] = function(rawMsg)
    -- Kept in its original case (profession names are case-sensitive, e.g.
    -- "Blacksmithing"); everything below that isn't the recipescan
    -- argument compares against the lowercased version instead.
    local raw = (rawMsg or ""):match("^%s*(.-)%s*$")
    local msg = raw:lower()
    if msg == "" or msg == "export" then
        cmdExport()
    elseif msg == "probe" then
        cmdProbe()
    elseif msg == "nameprobe" then
        cmdNameProbe()
    elseif msg == "setname" or msg:match("^setname%s") then
        local rest = raw:match("^%S+%s+(.+)$")
        cmdSetName(rest)
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
    elseif msg == "pvpdump" then
        cmdPvpDump()
    elseif msg == "specprobe" then
        cmdSpecProbe()
    elseif msg == "counters" then
        cmdCounters()
    elseif msg == "statsprobe" then
        cmdStatsProbe()
    elseif msg == "achievementsprobe" then
        cmdAchievementsProbe()
    elseif msg == "iconprobe" then
        cmdIconProbe()
    elseif msg == "legacypointsprobe" then
        cmdLegacyPointsProbe()
    elseif msg == "legacysystemprobe" then
        cmdLegacySystemProbe()
    elseif msg == "legacytreedatadump" then
        cmdLegacyTreeDataDump()
    elseif msg == "legacyframetreedump" then
        cmdLegacyFrameTreeDump()
    elseif msg == "recipeprobe" then
        cmdRecipeProbe()
    elseif msg == "recipeschema" then
        cmdRecipeSchema()
    elseif msg == "recipescan" or msg:match("^recipescan%s") then
        -- Anything after the first word, in its original case - the
        -- optional manual profession name.
        local manualName = raw:match("^%S+%s+(.+)$")
        cmdRecipeScan(manualName)
    elseif msg:match("^recipedump%s") then
        local profession = raw:match("^%S+%s+(.+)$")
        cmdRecipeDump(profession)
    elseif msg == "scan" then
        cmdProbe()
        cmdTraits()
        cmdExport()
    else
        print("|cffffcc00WoW Forever Tracker commands:|r")
        print("  /wft export - open a copy/paste box with your character data")
        print("  /wft probe - list which game functions exist on this client")
        print("  /wft nameprobe - show exactly what UnitName/UnitFullName return for this character (diagnostic, for me to look at)")
        print("  /wft setname First Last - tell the tracker your character's real full name (needed once per character - see /wft nameprobe if you're not sure why)")
        print("  /wft traits - try reading your talent/Legacy trait data")
        print("  /wft nodeinfo - dump raw fields for talents you've learned (diagnostic, for me to look at)")
        print("  /wft treedump - dump position data for every talent in your tree, learned or not (diagnostic, for me to look at)")
        print("  /wft spellprobe - test ways of resolving a talent's real name (diagnostic, for me to look at)")
        print("  /wft savetest - test whether this client saves data to disk across a full logout/login")
        print("  /wft profdump - dump raw GetProfessions() values (diagnostic, for me to look at)")
        print("  /wft pvpdump - dump raw PvP stat values (diagnostic, for me to look at)")
        print("  /wft specprobe - check for a spec API on this client (diagnostic, for me to look at)")
        print("  /wft counters - show your current death count (PvP kill tracking is paused)")
        print("  /wft statsprobe - check for a Statistics-pane API on this client (diagnostic, for me to look at)")
        print("  /wft achievementsprobe - dump the real Achievements/Legacy Challenges tree with completion state and checklists (diagnostic, for me to look at)")
        print("  /wft iconprobe - hunt for a Legacy Challenge achievement's real icon straight off the rendered UI (diagnostic, for me to look at - OPEN the Legacy Challenges panel to a category with achievements first, then run this)")
        print("  /wft legacypointsprobe - hunt for where the in-game 'Legacy Points' number actually comes from (diagnostic, for me to look at)")
        print("  /wft legacysystemprobe - force-load Blizzard's Legacy System UI module and check what API appears (diagnostic, for me to look at - run this with the Legacy Challenges panel closed first)")
        print("  /wft legacytreedatadump - dump LegacyTreeData, found via legacysystemprobe (diagnostic, for me to look at - run legacysystemprobe first this session)")
        print("  /wft legacyframetreedump - dump the real widget names under the Legacy Challenges panel (diagnostic, for me to look at - OPEN the panel in game first, then run this)")
        print("  /wft recipeprobe - check for a recipe-listing API on this client (diagnostic, for me to look at)")
        print("  /wft recipeschema - check whether this client can give back a recipe's reagents/description too, not just its name (diagnostic, for me to look at - run /wft recipescan at least once first)")
        print("  /wft recipescan [profession name] - with a profession window open, try reading its known recipes right now; pass a name (e.g. /wft recipescan Blacksmithing) if it can't tell which one is open")
        print("  /wft recipedump <profession name> - dump everything recorded for one profession's recipes, reagents included (diagnostic, for me to look at)")
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
        -- Kick off the async time-played request (see the section below)
        -- as early as possible, so its reply has time to land before the
        -- next /reload or logout writes an export.
        pcall(_G.RequestTimePlayed)
        -- Write an export right away too, so even a brand new install has
        -- real data in SavedVariables the moment you next log out or
        -- /reload, without needing any slash command first.
        writeSyncExport()
    end
end)

----------------------------------------------------------------------
-- Total time played ("Addicted" achievement, 2026-09-27)
----------------------------------------------------------------------
-- There's no simple GetTimePlayedTotal() - the real API is async: you call
-- RequestTimePlayed() (fired above, at login) and the server replies later
-- with a TIME_PLAYED_MSG event carrying (totalTimeSeconds, levelTimeSeconds).
-- Cached in WFTSyncDB (same pattern as deathCount/pvpKillCount above) so a
-- session that closes before the reply arrives still exports whatever the
-- last known value was, rather than nothing.
local timePlayedFrame = CreateFrame("Frame")
pcall(timePlayedFrame.RegisterEvent, timePlayedFrame, "TIME_PLAYED_MSG")
timePlayedFrame:SetScript("OnEvent", function(_, event, totalTime)
    if event == "TIME_PLAYED_MSG" and type(totalTime) == "number" then
        local db = ensureSyncDB()
        db.timePlayedTotalSeconds = totalTime
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

----------------------------------------------------------------------
-- Death and PvP kill counters
----------------------------------------------------------------------
-- Neither of these has a working running total from Blizzard's API on this
-- server (GetPVPLifetimeStats() came back all zeros/nils in /wft pvpdump),
-- so both are counted here instead, from whichever moment this version of
-- the addon was first installed onward - there's no way to backfill deaths
-- or kills that happened before that. Both counters live in WFTSyncDB (see
-- ensureSyncDB above), so a value bumped here survives the same way
-- everything else does: written to disk on the next logout/reload, and
-- carried forward by every export after that. Check them any time with
-- /wft counters.

local deathFrame = CreateFrame("Frame")
pcall(deathFrame.RegisterEvent, deathFrame, "PLAYER_DEAD")
deathFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_DEAD" then
        local db = ensureSyncDB()
        db.deathCount = (db.deathCount or 0) + 1
    end
end)

-- PvP kill tracking via COMBAT_LOG_EVENT_UNFILTERED was removed here after
-- it was linked to a "WoWForeverTracker has been blocked from an action
-- only available to the Blizzard UI" popup at login (2026-09-21). Nothing
-- in that handler ever called a genuinely protected function - but
-- COMBAT_LOG_EVENT_UNFILTERED handlers are a well-known source of exactly
-- this kind of false-positive taint, since a handler that runs during a
-- Blizzard-secured code path (which can include things happening around
-- login, like auras reapplying) can taint the default UI even while only
-- reading data. Not worth the game becoming unusable over a "nice to
-- have" leaderboard stat, so this is shelved for now - out.basic.pvpKills
-- still gets sent (see collectBasic), it'll just always read 0 until this
-- is revisited with a safer detection method.

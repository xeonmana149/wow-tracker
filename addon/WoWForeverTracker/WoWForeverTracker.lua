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

-- Safe IsShown() check that never throws. Moved up here (2026-10-03) from
-- the pvprankframefind diagnostic once it turned out scanPvpRankFromUI
-- needs it too: the PvP rank panel is a combat-protected frame on this
-- client, and its IsShown() result comes back as a "secret value" that
-- insecure addon code isn't even allowed to boolean-test directly (`if
-- shown then` on it throws "attempt to perform boolean test on a secret
-- value"). Doing that test INSIDE this function's own pcall catches that,
-- and a thrown "can't tell" is treated as "assume shown" rather than
-- "assume hidden" - for a protected frame like this one, refusing to look
-- at it just because we can't prove it's visible would mean never scanning
-- it at all.
local function isShownSafe(widget)
    local ok, result = pcall(function()
        if widget.IsShown and widget:IsShown() then
            return true
        end
        return false
    end)
    if ok then
        return result
    end
    return true
end

-- Same idea but for a function value you already have in hand (e.g. one
-- pulled out of a C_* table), rather than a global name. Every existing
-- caller of this only ever needed a single return value, so this only ever
-- forwarded r1 - fine until /wft statsprobe needed GetAchievementInfo's
-- name/points/description too and they came back silently nil (2026-09-25).
-- Forwards EVERY return value now (2026-11-05, addon 1.9.2). It used to stop
-- at 9, which silently dropped GetAchievementInfo's 10th return - the icon
-- fileID - so every Legacy Challenge synced with no icon.
local function forwardPcall(ok, ...)
    if not ok then
        return false, nil
    end
    return true, ...
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        return false, nil
    end
    return forwardPcall(pcall(fn, ...))
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
    -- {gold}/{silver}/{copper} into a real coin icon. Two different markup
    -- styles have to be handled: the newer atlas form ("|A:coin-gold:...|a")
    -- and this client's actual form, Blizzard's classic texture-path coin
    -- icons ("|TInterface\MoneyFrame\UI-GoldIcon:0|t") - GetMoneyString()
    -- still renders Sell Price with the latter even on this "retail API
    -- surface" beta. Without this second set of patterns, those texture
    -- icons fell through to the generic |T.-|t strip below and vanished
    -- entirely instead of turning into a token (2026-10-02, "why on
    -- equipped gear the coin icons are gone" - confirmed the numbers were
    -- still there, just with no coin marker left for the website to turn
    -- into a dot).
    text = text:gsub("|A:coin%-gold:[^|]*|a", "{gold}")
    text = text:gsub("|A:coin%-silver:[^|]*|a", "{silver}")
    text = text:gsub("|A:coin%-copper:[^|]*|a", "{copper}")
    text = text:gsub("|T.-GoldIcon.-|t", "{gold}")
    text = text:gsub("|T.-SilverIcon.-|t", "{silver}")
    text = text:gsub("|T.-CopperIcon.-|t", "{copper}")
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
-- Statistic ID scan (2026-11-05, addon 1.9.2) - WoW Forever keeps adding
-- statistics, and not every one sits in a category that
-- GetStatisticsCategoryList() returns. So after login the addon checks
-- every achievement ID (a few thousand per frame, so no stutter), keeps
-- the ones flagged as a statistic, and caches the list per game build.
-- collectStatistics() then exports those too, so new statistics reach the
-- website without another addon update.
local STAT_SCAN_MAX_ID = 100000
local STAT_SCAN_PER_FRAME = 4000
local ACHIEVEMENT_FLAG_STATISTIC = 1

local function isStatisticFlag(flags)
    if type(flags) ~= "number" then
        return false
    end
    if type(bit) == "table" and type(bit.band) == "function" then
        return bit.band(flags, ACHIEVEMENT_FLAG_STATISTIC) ~= 0
    end
    return flags % 2 == 1
end

local function statScanBuildKey()
    local version, build, _, toc = safeGet("GetBuildInfo")
    return tostring(version) .. "/" .. tostring(build) .. "/" .. tostring(toc)
end

local function startStatisticIdScan()
    local getAchievementInfo = _G.GetAchievementInfo
    if type(getAchievementInfo) ~= "function" then
        return
    end
    WFTSyncDB = WFTSyncDB or {}
    local key = statScanBuildKey()
    local cached = WFTSyncDB.statIdScan
    if type(cached) == "table" and cached.build == key and type(cached.ids) == "table" then
        return
    end
    local found = {}
    local nextId = 1
    local scanFrame = CreateFrame("Frame")
    scanFrame:SetScript("OnUpdate", function(self)
        local last = math.min(nextId + STAT_SCAN_PER_FRAME - 1, STAT_SCAN_MAX_ID)
        for id = nextId, last do
            local ok, realId, name, _, _, _, _, _, _, flags = pcall(getAchievementInfo, id)
            if ok and realId == id and name and name ~= "" and isStatisticFlag(flags) then
                table.insert(found, id)
            end
        end
        nextId = last + 1
        if nextId > STAT_SCAN_MAX_ID then
            self:SetScript("OnUpdate", nil)
            WFTSyncDB = WFTSyncDB or {}
            WFTSyncDB.statIdScan = { build = key, ids = found }
        end
    end)
end

local function collectStatistics()
    local out = {}
    local seen = {}

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
                    if not seen[id] then
                        seen[id] = true
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
    end

    -- Anything the ID scan found that the category walk above missed
    local scan = type(WFTSyncDB) == "table" and WFTSyncDB.statIdScan
    if type(scan) == "table" and type(scan.ids) == "table" and type(getAchievementInfo) == "function" then
        local getAchievementCategory = _G.GetAchievementCategory
        local categoryNames = {}
        for _, id in ipairs(scan.ids) do
            if not seen[id] then
                local okA, realId, name = safeCall(getAchievementInfo, id)
                if okA and realId and name and name ~= "" then
                    seen[id] = true
                    local categoryName = "Other"
                    if type(getAchievementCategory) == "function" then
                        local okC, catID = safeCall(getAchievementCategory, id)
                        if okC and catID then
                            if categoryNames[catID] == nil then
                                local okInfo, catName = safeCall(getCategoryInfo, catID)
                                categoryNames[catID] = (okInfo and catName and catName ~= "") and catName or false
                            end
                            categoryName = categoryNames[catID] or categoryName
                        end
                    end
                    local value = "--"
                    if type(getStatistic) == "function" then
                        local okV, v = safeCall(getStatistic, id)
                        if okV and v ~= nil then
                            value = tostring(v)
                        end
                    end
                    table.insert(out, { id = id, category = categoryName, name = name, value = value })
                end
            end
        end
    end

    return out
end

-- Statistic change times (1.9.5, 2026-11-09, "can we attach times and
-- dates to statistics?"). The Statistics pane only has current values, so
-- the addon looks at them every few minutes while you play (and 3 seconds
-- after a boss dies) and notes the time whenever a value changed since the
-- last look. WFTSyncDB.statLast holds the values from the last look and
-- WFTSyncDB.statTimes the time (unix seconds) each stat last changed,
-- both keyed by the stat ID as a string. The website uses those times to
-- date its statistic history and first dungeon/raid clears.
--
-- A stat seen for the first time only records its value - there's no
-- earlier value to have changed from.
local function stampStatisticTimes()
    local okC, stats = pcall(collectStatistics)
    if not okC or type(stats) ~= "table" then
        return
    end
    local okT, now = safeCall(_G.time)
    if not okT or type(now) ~= "number" then
        return
    end
    WFTSyncDB = WFTSyncDB or {}
    local last = type(WFTSyncDB.statLast) == "table" and WFTSyncDB.statLast or {}
    local times = type(WFTSyncDB.statTimes) == "table" and WFTSyncDB.statTimes or {}
    for _, s in ipairs(stats) do
        local key = tostring(s.id)
        local previous = last[key]
        if previous ~= nil and previous ~= s.value then
            times[key] = now
        end
        last[key] = s.value
    end
    WFTSyncDB.statLast = last
    WFTSyncDB.statTimes = times
end

-- Reputation (2026-11-05, addon 1.9.2) - every faction on the character's
-- Reputation pane with its standing and progress. Collapsed headers hide
-- their factions from the API, so they're expanded for the read and
-- collapsed again afterwards, leaving the pane as the player had it.
--
-- 1.9.3: newer clients (WoW Forever's 1.60 build among them) dropped the
-- GetNumFactions/GetFactionInfo globals for C_Reputation, whose
-- GetFactionDataByIndex returns a table. 1.9.2 only looked for the globals,
-- so it exported an empty list there. getInfo below turns the table back
-- into GetFactionInfo's return order, so the rest of this works on both.
local function factionApi()
    local rep = _G.C_Reputation
    if type(rep) == "table" and type(rep.GetNumFactions) == "function"
        and type(rep.GetFactionDataByIndex) == "function" then
        local getInfo = function(i)
            local d = rep.GetFactionDataByIndex(i)
            if type(d) ~= "table" then
                return nil
            end
            local hasRep = d.isHeaderWithRep or not d.isHeader
            return d.name, d.description, d.reaction,
                d.currentReactionThreshold, d.nextReactionThreshold, d.currentStanding,
                d.atWarWith, d.canToggleAtWar, d.isHeader, d.isCollapsed,
                hasRep, d.isWatched, d.isChild, d.factionID
        end
        return rep.GetNumFactions, getInfo, rep.ExpandFactionHeader, rep.CollapseFactionHeader
    end
    return _G.GetNumFactions, _G.GetFactionInfo, _G.ExpandFactionHeader, _G.CollapseFactionHeader
end

local function collectReputations()
    local out = {}
    local getNum, getInfo, expand, collapse = factionApi()
    if type(getNum) ~= "function" or type(getInfo) ~= "function" then
        return out
    end

    local expanded = {}
    if type(expand) == "function" then
        local guard = 0
        local i = 1
        while guard < 500 do
            guard = guard + 1
            local okN, num = safeCall(getNum)
            if not okN or type(num) ~= "number" or i > num then
                break
            end
            local okI, name, _, _, _, _, _, _, _, isHeader, isCollapsed = safeCall(getInfo, i)
            if okI and isHeader and isCollapsed then
                pcall(expand, i)
                table.insert(expanded, name)
            end
            i = i + 1
        end
    end

    local header
    local okN, num = safeCall(getNum)
    if okN and type(num) == "number" then
        for i = 1, num do
            local okI, name, _, standingID, barMin, barMax, barValue, _, _, isHeader, _, hasRep, _, isChild, factionID =
                safeCall(getInfo, i)
            if okI and name and name ~= "" then
                if isHeader and not hasRep then
                    header = name
                elseif type(standingID) == "number" then
                    local label = _G["FACTION_STANDING_LABEL" .. standingID]
                    table.insert(out, {
                        id = factionID,
                        name = name,
                        header = header,
                        standing = standingID,
                        standingLabel = type(label) == "string" and label or nil,
                        value = (tonumber(barValue) or 0) - (tonumber(barMin) or 0),
                        max = (tonumber(barMax) or 0) - (tonumber(barMin) or 0),
                        total = tonumber(barValue),
                    })
                end
            end
        end
    end

    -- Put the pane back the way it was
    if type(collapse) == "function" and #expanded > 0 then
        local wanted = {}
        for _, name in ipairs(expanded) do
            wanted[name] = true
        end
        local okN2, num2 = safeCall(getNum)
        if okN2 and type(num2) == "number" then
            for i = num2, 1, -1 do
                local okI, name, _, _, _, _, _, _, _, isHeader = safeCall(getInfo, i)
                if okI and isHeader and wanted[name] then
                    pcall(collapse, i)
                end
            end
        end
    end

    return out
end

-- 1.9.4: the export runs at PLAYER_LOGIN and PLAYER_LOGOUT, and at both
-- moments WoW Forever's client hands back no faction rows, even though
-- the same calls list every faction while you're in the world. So the
-- list is read while playing (see repFrame further down) and kept in
-- WFTSyncDB.reputations, and the export uses the live list when it has
-- rows and that saved copy when it doesn't.
local repSnapshotQuietUntil = 0

local function snapshotReputations()
    local ok, list = pcall(collectReputations)
    -- Expanding and collapsing headers fires UPDATE_FACTION itself, so
    -- ignore that event for a moment after reading, or it would loop
    local okT, now = safeCall(_G.GetTime)
    if okT and type(now) == "number" then
        repSnapshotQuietUntil = now + 2
    end
    if ok and type(list) == "table" and #list > 0 then
        WFTSyncDB = WFTSyncDB or {}
        WFTSyncDB.reputations = list
        return list
    end
    return nil
end

local function exportReputations()
    local live = snapshotReputations()
    if live then
        return live
    end
    return (type(WFTSyncDB) == "table" and type(WFTSyncDB.reputations) == "table")
        and WFTSyncDB.reputations or {}
end

-- PvP (2026-11-05, addon 1.9.2) - honor plus whichever lifetime kill
-- counters this client answers. The site also reads honorable kills and
-- killing blows from the Statistics pane, so nil values here are fine.
local function collectPvp()
    local pvp = {}
    pvp.honor = safeGet("UnitHonor", "player")
    pvp.honorMax = safeGet("UnitHonorMax", "player")
    pvp.honorLevel = safeGet("UnitHonorLevel", "player")
    local hk, dk, highestRank = safeGet("GetPVPLifetimeStats")
    pvp.lifetimeHonorableKills = tonumber(hk)
    pvp.lifetimeDishonorableKills = tonumber(dk)
    pvp.highestRank = tonumber(highestRank)
    local sessionHK, sessionDK = safeGet("GetPVPSessionStats")
    pvp.todayHonorableKills = tonumber(sessionHK)
    pvp.todayDishonorableKills = tonumber(sessionDK)
    -- 1.9.10: honor counted from the game's honor messages since this
    -- version was installed (UnitHonor read 0 after a kill on this client)
    pvp.honorTracked = (type(WFTSyncDB) == "table" and tonumber(WFTSyncDB.honorTracked)) or nil
    return pvp
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

    -- GetCategoryList()/GetAchievementInfo() only return real data once
    -- Blizzard_AchievementUI has loaded - normally that happens the moment
    -- the player opens the in-game Achievements panel. The server added a
    -- level-25 gate on actually OPENING that panel (2026-10, Jordan), which
    -- meant a character below level 25 could never trigger the load and
    -- this function would always come back empty - "Nothing synced yet"
    -- forever, with no way to fix it in-game. The gate blocks showing
    -- AchievementFrame, not loading the addon module behind it, so forcing
    -- the load here - without ever calling AchievementFrame:Show() or
    -- ShowUIPanel - sidesteps the level gate entirely. Safe to call every
    -- sync; IsAddOnLoaded short-circuits it to a no-op once it's loaded.
    if type(_G.IsAddOnLoaded) ~= "function" or not _G.IsAddOnLoaded("Blizzard_AchievementUI") then
        safeCall(_G.LoadAddOn, "Blizzard_AchievementUI")
    end

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
                local okA, id, name, points, completed, month, day, year, description, _flags, icon =
                    safeCall(getAchievementInfo, catID, i)
                if okA and id then
                    -- The day the game says this was completed (addon
                    -- 1.9.2+), so the website can date it properly even
                    -- when it was done long before the addon was installed.
                    -- year comes back as two digits (26 = 2026).
                    local completedDate = nil
                    if completed and type(year) == "number" and type(month) == "number" and type(day) == "number"
                        and month >= 1 and month <= 12 and day >= 1 and day <= 31 then
                        local fullYear = year < 100 and (2000 + year) or year
                        completedDate = ("%04d-%02d-%02d"):format(fullYear, month, day)
                    end
                    local row = {
                        id = id,
                        category = categoryName,
                        name = name,
                        completed = completed and true or false,
                        completedDate = completedDate,
                        description = description,
                        icon = icon,
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

-----------------------------------------------------------------------
-- PvP Rank scanning (2026-10-03)
-----------------------------------------------------------------------
-- There's no working API for this on this server's client (/wft pvpdump
-- confirmed GetPVPLifetimeStats()/GetPVPThisWeekStats() come back mostly
-- nil, and the classic UnitPVPRank/GetPVPRankInfo functions don't exist
-- here at all) - found via /wft pvprankframefind instead that the real
-- "Player vs. Player" panel is a named global frame, _G.PVPRankFrame, with
-- everything we need sitting in plain FontString regions:
--   - a frame with 3 regions: " Season N", the rank's name (e.g.
--     "Civilian"), and "Rank Points: X / Y"
--   - a separate Button nested a couple levels down (next to the rank
--     badge's cooldown-swipe icon) whose own text is just the rank NUMBER
--     (e.g. "0" for Civilian) - this is the one that actually matters,
--     since it's a real number we can compare against the cap, rather than
--     14 rank names we'd have to hand-map ourselves. The panel's own text
--     confirms the cap: "up to a maximum of 24750 for Rank 14", so ranks
--     run 0-14 and 14 is the top.
--
-- Same opportunistic-capture pattern as scanLegacyPointsFromUI: this can
-- only see a number while the player actually has the panel open, so it
-- caches into WFTSyncDB and keeps the HIGHEST rank ever seen (rank is only
-- supposed to go up, but there's no reason to let a weird read knock a
-- cached high value back down).
local function scanPvpRankFromUI()
    local frame = _G.PVPRankFrame
    if not frame or not isShownSafe(frame) then
        return false
    end

    local rankName, rankPoints, rankPointsMax, rankNumber
    local budget = { count = 0 }

    local function walk(f, depth)
        if not f or depth > 8 or budget.count > 2000 then
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
            if budget.count > 2000 then
                return
            end
            local texts = regionTexts(child, budget)
            for _, t in ipairs(texts) do
                local cur, max = t:match("Rank Points:%s*(%d+)%s*/%s*(%d+)")
                if cur and max then
                    rankPoints = tonumber(cur)
                    rankPointsMax = tonumber(max)
                end
            end
            if not rankName and #texts >= 2 then
                -- The rank's display name is whichever region text isn't
                -- the "Season N" label or the "Rank Points: x / y" line -
                -- in the confirmed dump that's the middle one of three,
                -- but matched by exclusion here rather than by position in
                -- case the panel ever reorders or adds a region.
                for _, t in ipairs(texts) do
                    if not t:match("^%s*Season%s+%d+%s*$") and not t:match("Rank Points:") then
                        rankName = t:match("^%s*(.-)%s*$")
                    end
                end
            end
            if not rankNumber then
                local okType, objType = pcall(function()
                    return child.GetObjectType and child:GetObjectType()
                end)
                if okType and objType == "Button" and #texts == 1 and tonumber(texts[1]) then
                    rankNumber = tonumber(texts[1])
                end
            end
            walk(child, depth + 1)
        end
    end

    walk(frame, 0)

    if not rankNumber then
        return false
    end

    WFTSyncDB = WFTSyncDB or {}
    WFTSyncDB.pvpRank = WFTSyncDB.pvpRank or {}
    if not WFTSyncDB.pvpRank.rank or rankNumber > WFTSyncDB.pvpRank.rank then
        WFTSyncDB.pvpRank.rank = rankNumber
        WFTSyncDB.pvpRank.rankName = rankName
    end
    if rankPoints and rankPointsMax then
        WFTSyncDB.pvpRank.points = rankPoints
        WFTSyncDB.pvpRank.pointsMax = rankPointsMax
    end
    return true
end

local pvpRankScanFrame = CreateFrame("Frame")
local pvpRankScanElapsed = 0
pvpRankScanFrame:SetScript("OnUpdate", function(_, elapsed)
    -- Same once/second throttle as legacyPointsScanFrame - scanPvpRankFromUI
    -- already bails out instantly via isShownSafe when the panel's closed.
    pvpRankScanElapsed = pvpRankScanElapsed + elapsed
    if pvpRankScanElapsed < 1 then
        return
    end
    pvpRankScanElapsed = 0
    pcall(scanPvpRankFromUI)
end)

local function buildExport()
    local out = {}
    local tocversion = select(4, safeGet("GetBuildInfo"))
    local okDate, timestamp = safeCall(_G.date, "%Y-%m-%d %H:%M:%S")
    out.meta = {
        addonVersion = "1.9.10",
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
    -- When each statistic last changed (1.9.5) - one last look first, so
    -- a change since the previous look gets this export's time
    pcall(stampStatisticTimes)
    out.statTimes = (type(WFTSyncDB) == "table" and type(WFTSyncDB.statTimes) == "table")
        and WFTSyncDB.statTimes or nil
    -- Legacy Challenges (see collectLegacyAchievements above) - same
    -- never-crash-the-export guard.
    local okLegacy, legacyAchievements = pcall(collectLegacyAchievements)
    out.legacyAchievements = okLegacy and legacyAchievements or nil
    -- PvP rank (see scanPvpRankFromUI above) - this is opportunistic, like
    -- legacyPointValues: it's only populated once the player has actually
    -- opened the Player vs. Player panel at least once this session (or a
    -- previous one - WFTSyncDB persists across sessions), so it's nil
    -- until then rather than a fake 0.
    out.pvpRank = (type(WFTSyncDB) == "table" and type(WFTSyncDB.pvpRank) == "table")
        and WFTSyncDB.pvpRank or nil
    -- Reputation standings and PvP totals (1.9.2) - same never-crash guard
    local okRep, reputations = pcall(exportReputations)
    out.reputations = okRep and reputations or nil
    local okPvp, pvp = pcall(collectPvp)
    out.pvp = okPvp and pvp or nil
    -- PvP kill/death log (1.9.5) - see the PvP kill/death log section. The
    -- whole recent log goes every time; the website skips entries it has
    -- already posted.
    out.pvpEvents = (type(WFTSyncDB) == "table" and type(WFTSyncDB.pvpLog) == "table")
        and WFTSyncDB.pvpLog or nil
    -- Auction House sales/purchases (1.9.5) - see the Auction House section
    out.auctionEvents = (type(WFTSyncDB) == "table" and type(WFTSyncDB.ahLog) == "table")
        and WFTSyncDB.ahLog or nil
    -- Epic+ items won/looted/crafted/traded (1.9.5) - see the Epic and
    -- legendary items section
    out.itemEvents = (type(WFTSyncDB) == "table" and type(WFTSyncDB.itemLog) == "table")
        and WFTSyncDB.itemLog or nil
    -- Duels, boss-kill groups and level-up times (1.9.5)
    if type(WFTSyncDB) == "table" then
        out.duelEvents = type(WFTSyncDB.duelLog) == "table" and WFTSyncDB.duelLog or nil
        out.bossGroups = type(WFTSyncDB.bossGroups) == "table" and WFTSyncDB.bossGroups or nil
        out.levelTimes = type(WFTSyncDB.levelTimes) == "table" and WFTSyncDB.levelTimes or nil
    end
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
                local okA, id, name, points, completed, _month, _day, _year, description =
                    safeCall(getAchievementInfo, catID, i)
                if okA and id then
                    local row = {
                        id = id,
                        category = categoryName,
                        name = name,
                        completed = completed and true or false,
                        description = description,
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

-----------------------------------------------------------------------
-- /wft pvprankframefind (2026-10-03) - we don't know this server's PvP
-- Rank Points panel's frame name the way we know _G.LegacySystemFrame, so
-- legacyframetreedump's "dump one known frame" approach doesn't apply yet.
-- Instead this searches the WHOLE visible UI tree from UIParent downward
-- for any widget whose own text or region text contains "Rank Points" (the
-- label seen in the user's screenshot of the Player vs. Player panel,
-- e.g. "Rank Points: 0 / 750") - same widgetOwnText/regionTexts helpers
-- scanLegacyPointsFromUI and dumpFrameTree already use. For every match it
-- prints the full parent chain (frame names/types from the match up to
-- UIParent) so we can see which frame to point a real scanner at, then
-- dumps that nearest NAMED ancestor's full subtree the same way
-- legacyframetreedump does, piped through the same export window.
--
-- Diagnostic only - doesn't touch buildExport()'s output, so per the
-- version-bump rule this doesn't need a version bump on its own.
----------------------------------------------------------------------

local function framePathName(frame)
    local names = {}
    local current = frame
    local hops = 0
    while current and hops < 15 do
        hops = hops + 1
        local okName, name = pcall(function()
            return current.GetName and current:GetName()
        end)
        local okType, objType = pcall(function()
            return current.GetObjectType and current:GetObjectType()
        end)
        table.insert(names, ((okName and name) or "<unnamed>") .. " [" .. ((okType and objType) or "?") .. "]")
        local okParent, parent = pcall(function()
            return current.GetParent and current:GetParent()
        end)
        current = okParent and parent or nil
    end
    return table.concat(names, " <- ")
end

-- Recursively searches `frame` and its descendants for any widget whose
-- own text or region text contains `needle` (case-insensitive), appending
-- matches to `matches`. Same depth/budget guards as dumpFrameTree so a
-- deep UI tree (UIParent has a LOT under it) can't hang the client.
--
-- IMPORTANT: UIParent's children include every panel the client has ever
-- created, shown or not - the bag frames, auction house, guild frame,
-- mail, every other closed window all live there permanently, hidden.
-- The first version of this recursed into those hidden subtrees too, so
-- the 4000-widget budget was spent on frames nobody can see before the
-- walk ever reached the open PvP panel, and it came back with zero
-- matches even though the panel was clearly open on screen. Fixed by only
-- recursing into a child when IT is shown - a hidden frame's children
-- can't be showing "Rank Points" either, so there's nothing worth
-- descending into, and skipping those subtrees entirely is what makes the
-- remaining budget land on the frames actually on screen.
--
-- 2026-10-03: the real PvP panel turned out to be a combat-protected
-- frame, and this client's secure execution model marks its IsShown()
-- result as a "secret value" that insecure addon code isn't even allowed
-- to boolean-test (`if shown then` itself throws "attempt to perform
-- boolean test on a secret value"). That's confirmation we reached the
-- right frame, not a reason to give up on it - isShownSafe (moved up near
-- widgetOwnText/regionTexts so scanPvpRankFromUI can use it too) does the
-- true/false check INSIDE its own pcall, and treats a thrown "can't tell"
-- as "assume shown" rather than skip, since refusing to recurse into
-- exactly the protected panel we're hunting for would defeat the whole
-- command.
local function findFramesWithText(frame, needle, depth, budget, matches)
    if not frame or depth > 12 or budget.count > 6000 then
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
        if budget.count > 6000 then
            return
        end
        if isShownSafe(child) then
            local ownText = widgetOwnText(child)
            local texts = regionTexts(child, budget)
            local haystack = (ownText or "") .. " " .. table.concat(texts, " ")
            if haystack:lower():find(needle:lower(), 1, true) then
                table.insert(matches, child)
            end
            -- Only descend into frames that are actually on screen - see
            -- the note above. A hidden child is skipped entirely, which is
            -- what keeps this fast enough to reach the open panel at all.
            findFramesWithText(child, needle, depth + 1, budget, matches)
        end
    end
end

local function cmdPvpRankFrameFind()
    print("|cffffcc00WFT pvprankframefind - searching the visible UI for 'Rank Points':|r")
    print("  Open the Player vs. Player panel from your screenshot FIRST, then run this.")

    local matches = {}
    local budget = { count = 0 }
    local ok, err = pcall(findFramesWithText, UIParent, "Rank Points", 0, budget, matches)
    if not ok then
        print("|cffff0000WFT pvprankframefind error:|r " .. tostring(err))
        return
    end

    if #matches == 0 then
        print("  No visible widget contains \"Rank Points\" - make sure the panel is open and showing a rank (not blank/loading), then try again.")
        -- Fallback: list every top-level frame currently shown directly
        -- under UIParent. If the text search still comes up empty with
        -- the panel open, this at least narrows down which top-level
        -- frame IS the PvP panel, so the next attempt can target it by
        -- name directly instead of searching for its text.
        local shownTop = {}
        local okChildren, children = pcall(function()
            return { UIParent:GetChildren() }
        end)
        if okChildren and children then
            for _, child in ipairs(children) do
                if isShownSafe(child) then
                    local okName, name = pcall(function()
                        return child.GetName and child:GetName()
                    end)
                    local okType, objType = pcall(function()
                        return child.GetObjectType and child:GetObjectType()
                    end)
                    table.insert(shownTop, ((okName and name) or "<unnamed>") .. " [" .. ((okType and objType) or "?") .. "]")
                end
            end
        end
        print(("  %d top-level frame(s) currently shown under UIParent - copy/paste the export window back:"):format(#shownTop))
        showExportWindow(table.concat(shownTop, "\n"))
        return
    end

    print(("  %d matching widget(s) found."):format(#matches))

    local out = {}
    local namedAncestor = nil
    for i, match in ipairs(matches) do
        local path = framePathName(match)
        table.insert(out, ("match %d path: %s"):format(i, path))
        if not namedAncestor then
            -- Walk up from this match to the nearest ancestor that actually
            -- has a global name - that's the frame worth dumping in full,
            -- the same way legacyframetreedump dumps LegacySystemFrame.
            local current = match
            local hops = 0
            while current and hops < 15 do
                hops = hops + 1
                local okName, name = pcall(function()
                    return current.GetName and current:GetName()
                end)
                if okName and name then
                    namedAncestor = { frame = current, name = name }
                    break
                end
                local okParent, parent = pcall(function()
                    return current.GetParent and current:GetParent()
                end)
                current = okParent and parent or nil
            end
        end
    end

    table.insert(out, "")
    if namedAncestor then
        table.insert(out, ("Dumping nearest named ancestor: %s"):format(namedAncestor.name))
        local dumpBudget = { count = 0 }
        local dumpOk, dumpErr = pcall(dumpFrameTree, namedAncestor.frame, 0, dumpBudget, out)
        if not dumpOk then
            table.insert(out, "dumpFrameTree error: " .. tostring(dumpErr))
        end
    else
        table.insert(out, "No named ancestor found within 15 hops - every frame in the chain is anonymous.")
    end

    showExportWindow(table.concat(out, "\n"))
end

-----------------------------------------------------------------------
-- /wft legacyiconprobe (2026-09-27) - points are confirmed synced/correct
-- now, but the icon art on the website still shows a blank placeholder for
-- every Legacy Challenge card. achievementBoard.ts's `remoteIcon` field is
-- typed as `number | null` and the `account_legacy_achievements.icon`
-- column is `bigint` (migration-23), both written on the assumption that
-- GetAchievementInfo's 10th return value (`icon`) is always a numeric
-- texture fileID - true for GetItemIcon on this server (items render
-- fine), but never actually confirmed true for GetAchievementInfo
-- specifically. If this server's client hands back a STRING here instead
-- (a texture path or atlas name, as some non-retail clients do for
-- achievements), the bigint column/insert would be the real break. This
-- dumps type() and raw value for a handful of real achievements so we can
-- tell which it is before changing anything.
local function cmdLegacyIconProbe()
    print("|cffffcc00WFT legacyiconprobe - checking what GetAchievementInfo's icon return actually is:|r")
    local getCategoryList = _G.GetCategoryList
    local getCategoryNum = _G.GetCategoryNumAchievements
    local getAchievementInfo = _G.GetAchievementInfo
    if type(getCategoryList) ~= "function" or type(getAchievementInfo) ~= "function" then
        print("  Achievements API not available.")
        return
    end
    local okList, catIDs = safeCall(getCategoryList)
    if not okList or not catIDs then
        print("  GetCategoryList failed.")
        return
    end
    local out = {}
    local checked = 0
    for _, catID in ipairs(catIDs) do
        if checked >= 20 then break end
        local numEntries = 0
        if type(getCategoryNum) == "function" then
            local okN, num = safeCall(getCategoryNum, catID, true)
            if okN and type(num) == "number" then
                numEntries = num
            end
        end
        for i = 1, numEntries do
            if checked >= 20 then break end
            local okA, id, name, _points, _completed, _month, _day, _year, _description, _flags, icon =
                safeCall(getAchievementInfo, catID, i)
            if okA and id then
                checked = checked + 1
                table.insert(out, string.format(
                    "%s | id=%s | icon type=%s | icon value=%s",
                    tostring(name), tostring(id), type(icon), tostring(icon)
                ))
            end
        end
    end
    if #out == 0 then
        print("  No achievements found to sample.")
        return
    end
    print(("  %d achievements sampled - copy/paste the export window back."):format(#out))
    showExportWindow(table.concat(out, "\n"))
end

----------------------------------------------------------------------
-- PvP, rare and death log (1.9.5, reworked 1.9.10 and 1.9.11)
----------------------------------------------------------------------
-- Records players you kill, what killed you, and rares your group kills,
-- with names, levels, classes and races, so the website can post "X
-- killed Y (lvl 24 Orc Warrior)" to the Activity feed.
--
-- None of it uses the combat log. This client doesn't give addons the
-- combat log (1.9.5-1.9.10 listened and never logged a thing), and a
-- combat log handler was what caused the "blocked from an action" popup
-- in September. Instead:
--   * player kills: the game's honor message names each player you get
--     honor for (items section below, pvpLogFrame.onHonor)
--   * rare kills: the XP message names the mob, matched against rares
--     seen on target/mouseover/nameplates (pvpLogFrame.onXp)
--   * your deaths: on PLAYER_DEAD, an empty breath bar means drowned, an
--     empty fatigue bar means fatigue, a fall of a second or more means
--     fell; otherwise the enemy that was targeting you is the killer
--   * /wft pvplog off switches it all off (and /wft pvplog on back)
--
-- Levels: the game only tells an addon another player's level while they
-- are your target, under your mouse, on a nameplate or in your group, so
-- levels are remembered from those moments. A player 10+ levels above you
-- shows as -1 ("??"), and a level never seen is left out.

local PVP_LOG_MAX = 300
local pvpLogFrame = CreateFrame("Frame")
local seenLevels = {} -- guid -> level, from target/mouseover/nameplates
-- Rare mobs (1.9.6, "rare kills"): guid -> { name, level, rank }, noted
-- whenever one is targeted, moused over or shows a nameplate, so a kill
-- can be logged even after it's no longer targeted
local seenRares = {}
local RARE_RANKS = { rare = "Rare", rareelite = "Rare Elite", worldboss = "World Boss" }

-- State lives on the frame because this file is close to Lua's 200-local
-- limit:
--   players[name] = { level, class, race, realm, guid } for every player
--     seen as your target, under your mouse or on a nameplate
--   fallingSince / landedAt / fellFor: the falling watch (GetTime values)
--   breathOutAt / fatigueOutAt: last time the breath / fatigue bar was empty
pvpLogFrame.players = {}
pvpLogFrame.playerCount = 0

local function pvpLogOff()
    return type(WFTSyncDB) == "table" and WFTSyncDB.pvpLogOff
end

-- "Thrall-Stormrage" -> "Thrall"
pvpLogFrame.shortName = function(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return name:match("^([^%-]+)") or name
end

local function rememberRare(unit)
    local okC, rank = safeCall(_G.UnitClassification, unit)
    if not okC or not RARE_RANKS[rank] then
        return
    end
    local okG, guid = safeCall(_G.UnitGUID, unit)
    local okN, name = safeCall(_G.UnitName, unit)
    local okL, level = safeCall(_G.UnitLevel, unit)
    if okG and guid then
        seenRares[guid] = {
            name = okN and name or nil,
            level = (okL and type(level) == "number") and level or nil,
            rank = rank,
        }
    end
end

local function rememberLevel(unit)
    local okP, isPlayer = safeCall(_G.UnitIsPlayer, unit)
    if not okP then
        return
    end
    if not isPlayer then
        rememberRare(unit)
        return
    end
    local okG, guid = safeCall(_G.UnitGUID, unit)
    guid = (okG and type(guid) == "string") and guid or nil
    local okL, level = safeCall(_G.UnitLevel, unit)
    level = (okL and type(level) == "number") and level or nil
    if guid and level then
        seenLevels[guid] = level
    end
    local okN, name, realm = safeCall(_G.UnitName, unit)
    if not okN or type(name) ~= "string" or name == "" then
        return
    end
    local okC, _, cls = safeCall(_G.UnitClass, unit)
    local okR, _, race = safeCall(_G.UnitRace, unit)
    local players = pvpLogFrame.players
    if not players[name] then
        pvpLogFrame.playerCount = pvpLogFrame.playerCount + 1
        if pvpLogFrame.playerCount > 500 then
            players = {}
            pvpLogFrame.players = players
            pvpLogFrame.playerCount = 1
        end
    end
    local known = players[name] or {}
    -- A real level beats "??" (-1, 10+ above you) seen earlier or later
    if level == nil or (level < 0 and known.level and known.level >= 0) then
        level = known.level
    end
    players[name] = {
        level = level,
        class = (okC and type(cls) == "string" and cls ~= "") and cls or known.class,
        race = (okR and type(race) == "string" and race ~= "") and race or known.race,
        realm = (type(realm) == "string" and realm ~= "") and realm or known.realm,
        guid = guid or known.guid,
    }
end

local function levelFor(guid)
    for _, unit in ipairs({ "target", "mouseover", "focus", "targettarget" }) do
        local okG, g = safeCall(_G.UnitGUID, unit)
        if okG and g == guid then
            local okL, level = safeCall(_G.UnitLevel, unit)
            if okL and type(level) == "number" then
                return level
            end
        end
    end
    return seenLevels[guid]
end

local function addToPvpLog(entry)
    local db = ensureSyncDB()
    db.pvpLog = type(db.pvpLog) == "table" and db.pvpLog or {}
    local okT, now = safeCall(_G.time)
    local okZ, zone = safeCall(_G.GetRealZoneText)
    entry.t = okT and now or nil
    entry.zone = okZ and zone or nil
    table.insert(db.pvpLog, entry)
    while #db.pvpLog > PVP_LOG_MAX do
        table.remove(db.pvpLog, 1)
    end
end

-- kind "kill" or "death". guid may be nil (an honor message only names
-- the player); then everything comes from the players cache. extra adds
-- honor and hkRank.
local function recordPvp(kind, guid, name, extra)
    -- GetPlayerInfoByGUID: localizedClass, englishClass, localizedRace,
    -- englishRace, sex, name, realm
    local englishClass, englishRace, infoName, realm
    if guid then
        local okInfo, _, c2, _, r2, _, n, rl = safeCall(_G.GetPlayerInfoByGUID, guid)
        if okInfo then
            englishClass = (type(c2) == "string" and c2 ~= "") and c2 or nil
            englishRace = (type(r2) == "string" and r2 ~= "") and r2 or nil
            infoName = (type(n) == "string" and n ~= "") and n or nil
            realm = rl
        end
    end
    local seen = pvpLogFrame.players[pvpLogFrame.shortName(infoName or name) or ""] or {}
    local level = guid and levelFor(guid) or nil
    if level == nil or (level < 0 and seen.level and seen.level >= 0) then
        level = seen.level
    end
    local entry = {
        kind = kind,
        name = infoName or name,
        realm = (type(realm) == "string" and realm ~= "") and realm or seen.realm,
        level = level,
        class = englishClass or seen.class,
        race = englishRace or seen.race,
    }
    if type(extra) == "table" then
        for k, v in pairs(extra) do
            entry[k] = v
        end
    end
    addToPvpLog(entry)
end

-- A rare your group killed, in the same log as PvP
local function recordRareKill(rare)
    addToPvpLog({
        kind = "rare_kill",
        name = rare.name,
        level = rare.level,
        rank = RARE_RANKS[rare.rank],
    })
end

-- When you die: the enemy targeting you - your own target first, then
-- every nameplate. Returns { guid, name, level, player } or nil.
pvpLogFrame.guessKiller = function()
    local units = { "target" }
    for i = 1, 40 do
        units[#units + 1] = "nameplate" .. i
    end
    for _, unit in ipairs(units) do
        local okE, exists = safeCall(_G.UnitExists, unit)
        local okH, hostile = safeCall(_G.UnitCanAttack, "player", unit)
        local okT, onMe = safeCall(_G.UnitIsUnit, unit .. "target", "player")
        if okE and exists and okH and hostile and okT and onMe then
            local okN, name = safeCall(_G.UnitName, unit)
            if okN and type(name) == "string" and name ~= "" then
                local okP, isPlayer = safeCall(_G.UnitIsPlayer, unit)
                local okG, guid = safeCall(_G.UnitGUID, unit)
                local okL, level = safeCall(_G.UnitLevel, unit)
                pcall(rememberLevel, unit)
                return {
                    guid = (okG and type(guid) == "string") and guid or nil,
                    name = name,
                    level = (okL and type(level) == "number") and level or nil,
                    player = (okP and isPlayer) and true or false,
                }
            end
        end
    end
    return nil
end

-- Falling, breath and fatigue, checked 4 times a second. IsFalling() is
-- still true or only just false when a fall kills you; the mirror timer
-- bars (BREATH, EXHAUSTION) read 0 while you drown or tire out.
pvpLogFrame.watchTick = function()
    local now = GetTime()
    local okF, falling = safeCall(_G.IsFalling)
    if okF and falling then
        pvpLogFrame.fallingSince = pvpLogFrame.fallingSince or now
    elseif pvpLogFrame.fallingSince then
        pvpLogFrame.fellFor = now - pvpLogFrame.fallingSince
        pvpLogFrame.landedAt = now
        pvpLogFrame.fallingSince = nil
    end
    for i = 1, 3 do
        local okM, timer = safeCall(_G.GetMirrorTimerInfo, i)
        if okM and (timer == "BREATH" or timer == "EXHAUSTION") then
            local okP, left = safeCall(_G.GetMirrorTimerProgress, timer)
            if okP and type(left) == "number" and left <= 0 then
                if timer == "BREATH" then
                    pvpLogFrame.breathOutAt = now
                else
                    pvpLogFrame.fatigueOutAt = now
                end
            end
        end
    end
end

pvpLogFrame.startWatch = function()
    local Timer = _G.C_Timer
    if pvpLogFrame.ticker or pvpLogOff() or type(Timer) ~= "table" or type(Timer.NewTicker) ~= "function" then
        return
    end
    pvpLogFrame.ticker = Timer.NewTicker(0.25, function()
        pcall(pvpLogFrame.watchTick)
    end)
end

pvpLogFrame.stopWatch = function()
    if pvpLogFrame.ticker then
        pcall(pvpLogFrame.ticker.Cancel, pvpLogFrame.ticker)
        pvpLogFrame.ticker = nil
    end
end

-- What killed you, if it was the world: "Drowning", "Fatigue", "Falling"
pvpLogFrame.environmentDeath = function()
    local now = GetTime()
    if pvpLogFrame.breathOutAt and now - pvpLogFrame.breathOutAt < 3 then
        return "Drowning"
    end
    if pvpLogFrame.fatigueOutAt and now - pvpLogFrame.fatigueOutAt < 3 then
        return "Fatigue"
    end
    if pvpLogFrame.fallingSince and now - pvpLogFrame.fallingSince >= 1 then
        return "Falling"
    end
    if pvpLogFrame.landedAt and now - pvpLogFrame.landedAt < 1 and (pvpLogFrame.fellFor or 0) >= 1 then
        return "Falling"
    end
    return nil
end

pvpLogFrame.onDeath = function()
    local env = pvpLogFrame.environmentDeath()
    local okL, myLevel = safeCall(_G.UnitLevel, "player")
    myLevel = (okL and type(myLevel) == "number") and myLevel or nil
    if env then
        addToPvpLog({ kind = "death_env", env = env, myLevel = myLevel })
        return
    end
    local hit = pvpLogFrame.guessKiller()
    if hit and hit.player then
        recordPvp("death", hit.guid, hit.name, { myLevel = myLevel })
    elseif hit then
        addToPvpLog({
            kind = "death_pve",
            name = hit.name,
            level = hit.level or (hit.guid and levelFor(hit.guid)) or nil,
            myLevel = myLevel,
        })
    else
        -- Nothing on screen was after you: lava, fire, or something gone
        -- from view - a plain "died in <zone>"
        addToPvpLog({ kind = "death_env", myLevel = myLevel })
    end
end

for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "NAME_PLATE_UNIT_ADDED", "CHAT_MSG_COMBAT_HONOR_GAIN", "CHAT_MSG_COMBAT_XP_GAIN" }) do
    pcall(pvpLogFrame.RegisterEvent, pvpLogFrame, ev)
end
pvpLogFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_TARGET_CHANGED" then
        pcall(rememberLevel, "target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        pcall(rememberLevel, "mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if type(arg1) == "string" then
            pcall(rememberLevel, arg1)
        end
    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        -- onHonor/onXp are set in the items section below, where the
        -- message-template helpers live
        if pvpLogFrame.onHonor then
            pcall(pvpLogFrame.onHonor, arg1)
        end
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        if pvpLogFrame.onXp then
            pcall(pvpLogFrame.onXp, arg1)
        end
    elseif event == "PLAYER_DEAD" then
        if not pvpLogOff() then
            pcall(pvpLogFrame.onDeath)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        pcall(pvpLogFrame.startWatch)
    end
end)

----------------------------------------------------------------------
-- Epic and legendary items (1.9.5, 2026-11-09, "tracking when
-- epics/legendaries are won in dungeon/raid/loot roll. or traded or
-- crafted ... with the roll number too")
----------------------------------------------------------------------
-- Read from the game's own messages rather than the combat log:
--   * loot roll results ("Need Roll - 87 for [item] by Xeon Mana") and
--     "You won: [item]" - the win is logged with your roll and roll type
--   * "You receive loot: [item]" - looted without a roll
--   * "You create: [item]" - crafted
--   * the trade window's items on both sides, logged when the game says
--     the trade completed
-- Each message is matched with the client's own text template (the
-- LOOT_ROLL_* / LOOT_ITEM_* globals), so it works in any client language.
-- Only epic (quality 4) and better is logged. WFTSyncDB.itemLog keeps the
-- most recent ITEM_LOG_MAX; the website posts each once.

local ITEM_LOG_MAX = 300
local itemFrame = CreateFrame("Frame")
local myRolls = {} -- item link -> { roll, rollType, at }
local recentlyWon = {} -- item link -> time, so "You receive loot" after a win isn't logged twice
local trade = { partner = nil, mine = {}, theirs = {} }

-- "Need Roll - %d for %s by %s" -> "^Need Roll %- (%d+) for (.+) by (.+)$"
-- Placeholders (%s, %d, and positional %1$s) are swapped for markers
-- first, then everything else that means something in a Lua pattern is
-- escaped, then the markers become captures.
local function templateToPattern(fmt)
    if type(fmt) ~= "string" then
        return nil
    end
    local p = fmt:gsub("%%%d?%$?s", "\001")
    p = p:gsub("%%%d?%$?d", "\002")
    p = p:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("\001", "(.+)")
    p = p:gsub("\002", "(%%d+)")
    return "^" .. p .. "$"
end

local PATTERNS = {}
local function pattern(name)
    if PATTERNS[name] == nil then
        PATTERNS[name] = templateToPattern(_G[name]) or false
    end
    return PATTERNS[name] or nil
end

-- PvP kills and rare kills from chat (1.9.10) - see the PvP section above.
-- They live here because they use the message-template helpers.
-- Honor: "Thrall dies, honorable kill Rank: Scout (Estimated Honor Points:
-- 12)" names every player you get honor for, killing blow or not, and
-- "You have been awarded 50 honor." is bonus honor with no kill. Every
-- point is added to WFTSyncDB.honorTracked, since the game's own honor
-- value read 0 after a kill on this client.
pvpLogFrame.HONOR_GLOBALS = { "COMBATLOG_HONORGAIN", "COMBATLOG_HONORGAIN_NO_RANK",
    "COMBATLOG_HONORGAIN_EXHAUSTION1", "COMBATLOG_HONORAWARD" }
pvpLogFrame.onHonor = function(msg)
    if type(msg) ~= "string" then
        return
    end
    local name, rank, honor
    local matched = false
    for _, global in ipairs(pvpLogFrame.HONOR_GLOBALS) do
        local p = pattern(global)
        local caps = p and { msg:match(p) } or {}
        if #caps > 0 then
            matched = true
            for _, c in ipairs(caps) do
                if c:match("^%d+$") then
                    honor = tonumber(c)
                elseif global ~= "COMBATLOG_HONORAWARD" then
                    if not name then
                        name = c
                    elseif not rank then
                        rank = c
                    end
                end
            end
            break
        end
    end
    if not matched then
        -- Older/odd wording: the name before " dies", the last number is the honor
        name = msg:match("^(.-) dies")
        honor = tonumber(msg:match("(%d+)%D*$"))
    end
    local db = ensureSyncDB()
    if honor then
        db.honorTracked = (db.honorTracked or 0) + honor
    end
    if not name or db.pvpLogOff then
        return
    end
    local seen = pvpLogFrame.players[pvpLogFrame.shortName(name)] or {}
    recordPvp("kill", seen.guid, name, { honor = honor, hkRank = rank })
end

-- Rares: "Mor'Ladim dies, you gain 450 experience." for a rare seen
-- earlier logs the kill (no XP, e.g. a grey rare, means no entry)
pvpLogFrame.XP_GLOBALS = { "COMBATLOG_XPGAIN_FIRSTPERSON", "COMBATLOG_XPGAIN_FIRSTPERSON_GROUP",
    "COMBATLOG_XPGAIN_FIRSTPERSON_RAID", "COMBATLOG_XPGAIN_EXHAUSTION1", "COMBATLOG_XPGAIN_EXHAUSTION1_GROUP",
    "COMBATLOG_XPGAIN_EXHAUSTION1_RAID", "COMBATLOG_XPGAIN_EXHAUSTION2", "COMBATLOG_XPGAIN_EXHAUSTION2_GROUP",
    "COMBATLOG_XPGAIN_EXHAUSTION2_RAID", "COMBATLOG_XPGAIN_EXHAUSTION4", "COMBATLOG_XPGAIN_EXHAUSTION4_GROUP",
    "COMBATLOG_XPGAIN_EXHAUSTION4_RAID", "COMBATLOG_XPGAIN_EXHAUSTION5", "COMBATLOG_XPGAIN_EXHAUSTION5_GROUP",
    "COMBATLOG_XPGAIN_EXHAUSTION5_RAID" }
pvpLogFrame.onXp = function(msg)
    if type(msg) ~= "string" or next(seenRares) == nil then
        return
    end
    if type(WFTSyncDB) == "table" and WFTSyncDB.pvpLogOff then
        return
    end
    local name
    for _, global in ipairs(pvpLogFrame.XP_GLOBALS) do
        local p = pattern(global)
        local first = p and msg:match(p)
        if first and not first:match("^%d+$") then
            name = first
            break
        end
    end
    name = name or msg:match("^(.-) dies")
    if not name then
        return
    end
    for guid, rare in pairs(seenRares) do
        if rare.name == name then
            seenRares[guid] = nil
            recordRareKill(rare)
            return
        end
    end
end

-- Quality from the item itself where the client has it cached, otherwise
-- from the link's colour (epic purple / legendary orange / artifact gold)
local LINK_COLOR_QUALITY = { a335ee = 4, ff8000 = 5, e6cc80 = 6 }
local function itemQuality(link)
    local ok, _, _, quality = safeCall(_G.GetItemInfo, link)
    if ok and type(quality) == "number" then
        return quality
    end
    local color = type(link) == "string" and link:match("|cff(%x%x%x%x%x%x)")
    return color and LINK_COLOR_QUALITY[color:lower()] or nil
end

local function itemName(link)
    return type(link) == "string" and (link:match("%[(.-)%]") or link) or nil
end

local function itemId(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

local function currentPlace()
    local okI, name, instanceType = safeCall(_G.GetInstanceInfo)
    if okI and name and instanceType and instanceType ~= "none" then
        return name
    end
    local okZ, zone = safeCall(_G.GetRealZoneText)
    return okZ and zone or nil
end

local function isMe(name)
    if type(name) ~= "string" then
        return false
    end
    local okN, me = safeCall(_G.UnitName, "player")
    return name == (_G.YOU or "You") or (okN and (name == me or name:match("^[^-]+") == me))
end

local function recordItem(kind, link, extra)
    local quality = itemQuality(link)
    if type(quality) ~= "number" or quality < 4 then
        return
    end
    local db = ensureSyncDB()
    db.itemLog = type(db.itemLog) == "table" and db.itemLog or {}
    local okT, now = safeCall(_G.time)
    local entry = {
        t = okT and now or nil,
        kind = kind,
        item = itemName(link),
        itemId = itemId(link),
        quality = quality,
        where = currentPlace(),
    }
    for k, v in pairs(extra or {}) do
        entry[k] = v
    end
    table.insert(db.itemLog, entry)
    while #db.itemLog > ITEM_LOG_MAX do
        table.remove(db.itemLog, 1)
    end
end

local ROLL_TYPES = {
    LOOT_ROLL_ROLLED_NEED = "Need",
    LOOT_ROLL_ROLLED_GREED = "Greed",
    LOOT_ROLL_ROLLED_DE = "Disenchant",
}

local function onLootMessage(msg)
    if type(msg) ~= "string" then
        return
    end
    -- Your own roll on an item, kept until the winner is announced
    for global, rollType in pairs(ROLL_TYPES) do
        local p = pattern(global)
        if p then
            local roll, link, who = msg:match(p)
            if roll and isMe(who) then
                myRolls[link] = { roll = tonumber(roll), rollType = rollType, at = GetTime() }
                return
            end
        end
    end
    local p = pattern("LOOT_ROLL_YOU_WON")
    local link = p and msg:match(p)
    if link then
        local mine = myRolls[link]
        myRolls[link] = nil
        recentlyWon[link] = GetTime()
        recordItem("won", link, { roll = mine and mine.roll or nil, rollType = mine and mine.rollType or nil })
        return
    end
    p = pattern("LOOT_ITEM_CREATED_SELF_MULTIPLE")
    local count
    if p then
        link, count = msg:match(p)
    end
    if not link then
        p = pattern("LOOT_ITEM_CREATED_SELF")
        link = p and msg:match(p)
    end
    if link then
        recordItem("crafted", link, { count = tonumber(count) })
        return
    end
    p = pattern("LOOT_ITEM_SELF_MULTIPLE")
    if p then
        link, count = msg:match(p)
    end
    if not link then
        p = pattern("LOOT_ITEM_SELF")
        link = p and msg:match(p)
    end
    if link then
        local won = recentlyWon[link]
        if won and GetTime() - won < 30 then
            recentlyWon[link] = nil
            return
        end
        recordItem("looted", link, { count = tonumber(count) })
    end
end

-- Trades: remember what's in the window on both sides as it changes, and
-- log it when the game reports the trade completed
local function snapshotTrade()
    for i = 1, 7 do
        local okM, mine = safeCall(_G.GetTradePlayerItemLink, i)
        trade.mine[i] = okM and mine or nil
        local okT, theirs = safeCall(_G.GetTradeTargetItemLink, i)
        trade.theirs[i] = okT and theirs or nil
    end
end

local function tradeCompleted()
    local partner = trade.partner
    for i = 1, 7 do
        if trade.mine[i] then
            recordItem("trade_gave", trade.mine[i], { player = partner })
        end
        if trade.theirs[i] then
            recordItem("trade_got", trade.theirs[i], { player = partner })
        end
    end
    trade.mine, trade.theirs = {}, {}
end

for _, ev in ipairs({ "CHAT_MSG_LOOT", "TRADE_SHOW", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED",
    "TRADE_ACCEPT_UPDATE", "UI_INFO_MESSAGE" }) do
    pcall(itemFrame.RegisterEvent, itemFrame, ev)
end
itemFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_LOOT" then
        pcall(onLootMessage, (...))
    elseif event == "TRADE_SHOW" then
        local okN, partner = safeCall(_G.UnitName, "NPC")
        trade = { partner = okN and partner or nil, mine = {}, theirs = {} }
        pcall(snapshotTrade)
    elseif event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_TARGET_ITEM_CHANGED"
        or event == "TRADE_ACCEPT_UPDATE" then
        pcall(snapshotTrade)
    elseif event == "UI_INFO_MESSAGE" then
        -- (messageType, message) on newer clients, (message) on older ones
        local a, b = ...
        local done = _G.ERR_TRADE_COMPLETE
        if done and (a == done or b == done) then
            pcall(tradeCompleted)
        end
    end
end)

----------------------------------------------------------------------
-- Duels (1.9.5, 2026-11-09)
----------------------------------------------------------------------
-- The game announces every finished duel in system chat:
-- DUEL_WINNER_KNOCKOUT "%1$s has defeated %2$s in a duel" and
-- DUEL_WINNER_RETREAT "%2$s has fled from %1$s in a duel" (%1 is always
-- the winner). Only duels you were in are logged, with the opponent and
-- whether you won. The website keeps the running record per opponent.

local DUEL_LOG_MAX = 200
local duelFrame = CreateFrame("Frame")

-- Pattern plus which argument each capture is, since the "fled" message
-- names the loser first
local function duelPattern(global)
    local fmt = _G[global]
    if type(fmt) ~= "string" then
        return nil
    end
    local order = {}
    for n in fmt:gmatch("%%(%d)%$s") do
        table.insert(order, tonumber(n))
    end
    if #order ~= 2 then
        order = { 1, 2 }
    end
    return templateToPattern(fmt), order
end

local function onSystemMessage(msg)
    if type(msg) ~= "string" then
        return
    end
    for _, global in ipairs({ "DUEL_WINNER_KNOCKOUT", "DUEL_WINNER_RETREAT" }) do
        local p, order = duelPattern(global)
        if p then
            local a, b = msg:match(p)
            if a and b then
                local args = {}
                args[order[1]], args[order[2]] = a, b
                local winner, loser = args[1], args[2]
                local won = isMe(winner)
                if not won and not isMe(loser) then
                    return
                end
                local db = ensureSyncDB()
                db.duelLog = type(db.duelLog) == "table" and db.duelLog or {}
                local okT, now = safeCall(_G.time)
                table.insert(db.duelLog, {
                    t = okT and now or nil,
                    won = won,
                    fled = global == "DUEL_WINNER_RETREAT",
                    opponent = won and loser or winner,
                    zone = currentPlace(),
                })
                while #db.duelLog > DUEL_LOG_MAX do
                    table.remove(db.duelLog, 1)
                end
                return
            end
        end
    end
end

pcall(duelFrame.RegisterEvent, duelFrame, "CHAT_MSG_SYSTEM")
duelFrame:SetScript("OnEvent", function(_, _, msg)
    pcall(onSystemMessage, msg)
end)

-- Who was in your group at each boss kill (1.9.5), so a first dungeon/raid
-- clear on the website can say who it was with. Called from the boss-kill
-- events further down.
local BOSS_GROUP_MAX = 100
local function recordBossGroup(boss)
    if type(boss) ~= "string" or boss == "" then
        return
    end
    local members = {}
    local okR, inRaid = safeCall(_G.IsInRaid)
    local okN, count = safeCall(_G.GetNumGroupMembers)
    count = okN and type(count) == "number" and count or 0
    local prefix = (okR and inRaid) and "raid" or "party"
    local last = prefix == "raid" and count or math.min(count, 4)
    for i = 1, last do
        local okU, name = safeCall(_G.UnitName, prefix .. i)
        if okU and type(name) == "string" and name ~= "" and not isMe(name) then
            table.insert(members, name)
        end
    end
    local db = ensureSyncDB()
    db.bossGroups = type(db.bossGroups) == "table" and db.bossGroups or {}
    local okT, now = safeCall(_G.time)
    -- ENCOUNTER_END and BOSS_KILL can both fire for one kill
    local prev = db.bossGroups[#db.bossGroups]
    if prev and prev.boss == boss and okT and prev.t and now - prev.t < 60 then
        return
    end
    table.insert(db.bossGroups, { t = okT and now or nil, boss = boss, where = currentPlace(), members = members })
    while #db.bossGroups > BOSS_GROUP_MAX do
        table.remove(db.bossGroups, 1)
    end
end

-- Level-ups (1.9.5): the exact time and total played time of each one.
-- Played time is only reported at login (TIME_PLAYED_MSG), so it's that
-- figure plus however long you've been online since.
local levelFrame = CreateFrame("Frame")
local playedBase, playedBaseAt
pcall(levelFrame.RegisterEvent, levelFrame, "TIME_PLAYED_MSG")
pcall(levelFrame.RegisterEvent, levelFrame, "PLAYER_LEVEL_UP")
levelFrame:SetScript("OnEvent", function(_, event, a)
    if event == "TIME_PLAYED_MSG" and type(a) == "number" then
        playedBase, playedBaseAt = a, GetTime()
    elseif event == "PLAYER_LEVEL_UP" and type(a) == "number" then
        local db = ensureSyncDB()
        db.levelTimes = type(db.levelTimes) == "table" and db.levelTimes or {}
        local okT, now = safeCall(_G.time)
        db.levelTimes[tostring(a)] = {
            t = okT and now or nil,
            played = playedBase and math.floor(playedBase + (GetTime() - playedBaseAt)) or nil,
        }
    end
end)

----------------------------------------------------------------------
-- Auction House sales and purchases (1.9.5, 2026-11-09, "how about
-- auction house tracking like big sales or big buys maybe 50 gold+?")
----------------------------------------------------------------------
-- Every sale and won auction arrives as mail, and the game gives addons an
-- "invoice" for those mails: sale or purchase, the item, the price and the
-- other player. Read whenever the mailbox updates, so a sale is logged the
-- next time you open a mailbox. Everything is logged here; the website
-- decides which are big enough to post (50g+).
--
-- The game doesn't say when a mail arrived, only how many days it has
-- left. Auction mail lasts 30 days, so arrival = now - (30 - daysLeft)
-- days, worked out once when the mail is first seen and kept from then on.
--
-- Some clients only fill in an invoice after the mail's text has been
-- fetched, which marks it read - so that's done only for Auction House
-- mail, only when the invoice came back empty.

local AH_LOG_MAX = 300
local AH_MAIL_DAYS = 30
local ahFrame = CreateFrame("Frame")
local ahScanQueued = false

local function scanAuctionMail()
    local okN, num = safeCall(_G.GetInboxNumItems)
    if not okN or type(num) ~= "number" or num == 0 then
        return
    end
    local db = ensureSyncDB()
    db.ahLog = type(db.ahLog) == "table" and db.ahLog or {}
    db.ahSeen = type(db.ahSeen) == "table" and db.ahSeen or {}
    local okT, now = safeCall(_G.time)
    if not okT or type(now) ~= "number" then
        return
    end

    for i = 1, num do
        local okH, _, _, sender, subject, _, _, daysLeft = safeCall(_G.GetInboxHeaderInfo, i)
        local okI, invoiceType, itemName, playerName, bid, _, _, _, _, _, _, count =
            safeCall(_G.GetInboxInvoiceInfo, i)
        if okH and (not okI or not invoiceType) and type(sender) == "string" and sender:find("Auction House") then
            pcall(_G.GetInboxText, i)
            okI, invoiceType, itemName, playerName, bid, _, _, _, _, _, _, count =
                safeCall(_G.GetInboxInvoiceInfo, i)
        end
        if okH and okI and (invoiceType == "seller" or invoiceType == "buyer")
            and type(bid) == "number" and bid > 0 and type(daysLeft) == "number" then
            local arrived = math.floor(now - (AH_MAIL_DAYS - daysLeft) * 86400)
            -- Same mail on a later scan: same item/player/price, arrival
            -- within the hour (daysLeft keeps ticking down between scans)
            local key = table.concat({ invoiceType, tostring(itemName), tostring(playerName), tostring(bid),
                tostring(math.floor(arrived / 3600)) }, "|")
            local keyPrev = table.concat({ invoiceType, tostring(itemName), tostring(playerName), tostring(bid),
                tostring(math.floor(arrived / 3600) - 1) }, "|")
            if not db.ahSeen[key] and not db.ahSeen[keyPrev] then
                db.ahSeen[key] = arrived
                -- Quantity: the invoice's own count where the client gives
                -- one, else the attached item's stack (purchases only)
                local qty = type(count) == "number" and count or nil
                if not qty and invoiceType == "buyer" then
                    local okA, _, _, _, attachedCount = safeCall(_G.GetInboxItem, i, 1)
                    if okA and type(attachedCount) == "number" then
                        qty = attachedCount
                    end
                end
                -- Quality, so epics/legendaries post whatever the price:
                -- from the attached item's link on a purchase, else by name
                -- (works once the client has seen the item)
                local okL, link = safeCall(_G.GetInboxItemLink, i, 1)
                local quality = itemQuality((okL and link) or itemName)
                table.insert(db.ahLog, {
                    t = arrived,
                    kind = invoiceType == "seller" and "sale" or "purchase",
                    item = itemName,
                    count = qty,
                    player = playerName,
                    price = bid,
                    quality = quality,
                })
                while #db.ahLog > AH_LOG_MAX do
                    table.remove(db.ahLog, 1)
                end
            end
        end
    end

    -- Forget dedupe keys for mail that has long expired
    for key, arrived in pairs(db.ahSeen) do
        if type(arrived) ~= "number" or now - arrived > (AH_MAIL_DAYS + 2) * 86400 then
            db.ahSeen[key] = nil
        end
    end
end

pcall(ahFrame.RegisterEvent, ahFrame, "MAIL_INBOX_UPDATE")
ahFrame:SetScript("OnEvent", function()
    -- MAIL_INBOX_UPDATE fires in bursts while the mailbox loads - read once
    -- it settles
    if ahScanQueued then
        return
    end
    local Timer = _G.C_Timer
    if type(Timer) == "table" and type(Timer.After) == "function" then
        ahScanQueued = true
        Timer.After(1, function()
            ahScanQueued = false
            pcall(scanAuctionMail)
        end)
    else
        pcall(scanAuctionMail)
    end
end)

-- Statistic change times (1.9.5) - see stampStatisticTimes. Every 5
-- minutes while out of combat, and 3 seconds after a boss dies (so a first
-- dungeon/raid clear gets the minute it happened, not the next sync).
local statTimesFrame = CreateFrame("Frame")
local statTicker
local function queueStatStamp(delay)
    local Timer = _G.C_Timer
    if type(Timer) == "table" and type(Timer.After) == "function" then
        Timer.After(delay, function()
            pcall(stampStatisticTimes)
        end)
    end
end
pcall(statTimesFrame.RegisterEvent, statTimesFrame, "PLAYER_ENTERING_WORLD")
pcall(statTimesFrame.RegisterEvent, statTimesFrame, "ENCOUNTER_END")
pcall(statTimesFrame.RegisterEvent, statTimesFrame, "BOSS_KILL")
statTimesFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ENCOUNTER_END" then
        local _, encounterName, _, _, success = ...
        if success == 1 or success == true then
            pcall(recordBossGroup, encounterName)
            queueStatStamp(3)
        end
    elseif event == "BOSS_KILL" then
        local _, encounterName = ...
        pcall(recordBossGroup, encounterName)
        queueStatStamp(3)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- First look a little after loading in (records starting values)
        queueStatStamp(15)
        local Timer = _G.C_Timer
        if not statTicker and type(Timer) == "table" and type(Timer.NewTicker) == "function" then
            statTicker = Timer.NewTicker(300, function()
                local okC, inCombat = safeCall(_G.InCombatLockdown)
                if okC and inCombat then
                    return
                end
                pcall(stampStatisticTimes)
            end)
        end
    end
end)

-- /wft pvplog [on|off] - show the last few entries, or switch logging
local function cmdPvpLog(arg)
    local db = ensureSyncDB()
    if arg == "off" then
        db.pvpLogOff = true
        pvpLogFrame.stopWatch()
        print("|cffffcc00WFT:|r PvP kill/death logging is |cffff6666off|r. /wft pvplog on to turn it back on.")
        return
    elseif arg == "on" then
        db.pvpLogOff = nil
        pvpLogFrame.startWatch()
        print("|cffffcc00WFT:|r PvP kill/death logging is |cff66ff66on|r.")
        return
    end
    local log = type(db.pvpLog) == "table" and db.pvpLog or {}
    print(("|cffffcc00WFT PvP log:|r %s, %d entries, %d honor tracked"):format(
        db.pvpLogOff and "off" or "on", #log, db.honorTracked or 0))
    local verbs = { kill = "killed", death = "killed by", death_pve = "killed by", rare_kill = "killed rare",
        death_env = "died" }
    for i = math.max(1, #log - 4), #log do
        local e = log[i]
        print(("  %s %s %s lvl %s %s %s%s"):format(
            e.t and date("%d %b %H:%M", e.t) or "?", verbs[e.kind] or tostring(e.kind),
            tostring(e.name or e.env or ""), e.level == -1 and "??" or tostring(e.level or "?"),
            tostring(e.race or ""), tostring(e.class or ""), e.honor and (" +" .. e.honor .. " honor") or ""))
    end
end

----------------------------------------------------------------------
-- Sync button (1.9.7, 2026-11-09, "a small ui in game that says sync?
-- and every 30 minutes it goes red or something as a reminder and if you
-- press it, it just reloads the game")
----------------------------------------------------------------------
-- The game only writes this addon's data to disk on logout or /reload, so
-- the button is a one-click /reload that the tray app then syncs.
--   * the time since the last sync (this UI load) is shown on it; it turns
--     amber after the reminder time (30 min by default) and red at double
--     that, with a gentle pulse
--   * greyed out in combat; inside a dungeon or raid it asks first
--   * the tooltip lists what's waiting to sync and whether you're in a
--     safe spot (inn or city)
--   * it glows for a while after something worth sharing - a level-up, a
--     boss kill, an epic item, a rare kill - and when you rest in an inn or
--     city with something waiting
--   * drag to move; right-click locks/unlocks; /wft sync for the rest
-- Settings live in WFTSyncDB.syncButton (per character).
--
-- Wrapped in do ... end: the main file is close to Lua's limit of 200
-- top-level locals, so only cmdSync is visible outside.

local cmdSync
do
local SYNC_GLOW_SECONDS = 30
local syncSessionStart = time()
local syncBtn
local syncGlowUntil = 0
local syncLastSeen -- what was waiting at the last check, to spot new things
local syncWasResting = false
local syncChatNotified = 0 -- how many reminder intervals have been announced

local function syncSettings()
    local db = ensureSyncDB()
    db.syncButton = type(db.syncButton) == "table" and db.syncButton or {}
    local s = db.syncButton
    if type(s.remind) ~= "number" or s.remind < 1 then
        s.remind = 30
    end
    return s
end

-- Entries in a log stamped at or after the last sync
local function countSince(log, test)
    if type(log) ~= "table" then
        return 0
    end
    local n = 0
    for _, e in ipairs(log) do
        if type(e) == "table" and type(e.t) == "number" and e.t >= syncSessionStart and (not test or test(e)) then
            n = n + 1
        end
    end
    return n
end

-- What's happened since the last sync, by type
local function syncWaiting()
    local db = type(WFTSyncDB) == "table" and WFTSyncDB or {}
    local w = {
        kills = countSince(db.pvpLog, function(e) return e.kind == "kill" end),
        deaths = countSince(db.pvpLog, function(e)
            return e.kind == "death" or e.kind == "death_pve" or e.kind == "death_env"
        end),
        rares = countSince(db.pvpLog, function(e) return e.kind == "rare_kill" end),
        epics = countSince(db.itemLog),
        duels = countSince(db.duelLog),
        clears = countSince(db.bossGroups),
        level = nil,
    }
    if type(db.levelTimes) == "table" then
        for lvl, info in pairs(db.levelTimes) do
            local n = tonumber(lvl)
            if n and type(info) == "table" and type(info.t) == "number" and info.t >= syncSessionStart
                and (not w.level or n > w.level) then
                w.level = n
            end
        end
    end
    return w
end

local function plural(n, word)
    return ("%d %s%s"):format(n, word, n == 1 and "" or "s")
end

local function syncWaitingText(w)
    local parts = {}
    if w.level then table.insert(parts, "level " .. w.level) end
    if w.clears > 0 then table.insert(parts, plural(w.clears, "boss kill")) end
    if w.rares > 0 then table.insert(parts, plural(w.rares, "rare kill")) end
    if w.epics > 0 then table.insert(parts, plural(w.epics, "epic item")) end
    if w.kills > 0 then table.insert(parts, plural(w.kills, "PvP kill")) end
    if w.duels > 0 then table.insert(parts, plural(w.duels, "duel")) end
    if w.deaths > 0 then table.insert(parts, plural(w.deaths, "death")) end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

-- The things worth a glow, as one number per kind
local function syncHighlights(w)
    return (w.level or 0), w.clears, w.rares, w.epics
end

local function minutesSinceSync()
    return math.floor((time() - syncSessionStart) / 60)
end

local function inCombat()
    local ok, v = safeCall(_G.InCombatLockdown)
    return ok and v
end

local function inInstance()
    local ok, v = safeCall(_G.IsInInstance)
    return ok and v
end

local function isResting()
    local ok, v = safeCall(_G.IsResting)
    return ok and v
end

-- The "Sync now?" box inside dungeons is the addon's own frame, NOT
-- Blizzard's StaticPopup (1.9.9 fix). 1.9.7 wrote to the shared
-- StaticPopupDialogs table, which tainted it: Blizzard code that reads it
-- (the Escape menu, the character window) then ran as "addon code" and was
-- blocked - "tried to call the protected function SpellStopCasting()" and
-- "attempt to compare a secret number value". Nothing here touches a
-- Blizzard global.
local syncConfirm

local function syncConfirmButton(parent, text, x, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(90, 22)
    b:SetPoint("BOTTOM", parent, "BOTTOM", x, 12)
    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.55, 0.42, 0.15, 1)
    local bg = b:CreateTexture(nil, "BORDER")
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.15, 0.15, 0.15, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.12)
    local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function showSyncConfirm()
    if not syncConfirm then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(300, 110)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        local border = f:CreateTexture(nil, "BACKGROUND")
        border:SetAllPoints()
        border:SetColorTexture(0.55, 0.42, 0.15, 1)
        local bg = f:CreateTexture(nil, "BORDER")
        bg:SetPoint("TOPLEFT", 1, -1)
        bg:SetPoint("BOTTOMRIGHT", -1, 1)
        bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
        local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("TOP", f, "TOP", 0, -14)
        text:SetWidth(270)
        text:SetText("Sync now?\n\nThis reloads your game - you'll get a short loading screen inside the dungeon.")
        syncConfirmButton(f, "Sync", -50, function()
            f:Hide()
            if not inCombat() then
                ReloadUI()
            end
        end)
        syncConfirmButton(f, "Not now", 50, function()
            f:Hide()
        end)
        syncConfirm = f
    end
    syncConfirm:Show()
end

local function doSync()
    if inCombat() then
        print("|cffffcc00WFT:|r Can't sync in combat - try again once you're out.")
        return
    end
    if inInstance() then
        showSyncConfirm()
        return
    end
    ReloadUI()
end

local function syncShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("WoW Forever Tracker - Sync")
    local mins = minutesSinceSync()
    GameTooltip:AddLine(mins < 1 and "Last synced just now" or ("Last synced " .. mins .. "m ago"), 1, 1, 1)
    local waiting = syncWaitingText(syncWaiting())
    if waiting then
        GameTooltip:AddLine("Waiting: " .. waiting, 1, 0.82, 0, true)
    else
        GameTooltip:AddLine("Nothing new waiting yet", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine(" ")
    if inCombat() then
        GameTooltip:AddLine("Can't sync in combat.", 1, 0.3, 0.3)
    elseif isResting() then
        GameTooltip:AddLine("You're in a safe spot - good time to sync.", 0.3, 1, 0.3, true)
    else
        GameTooltip:AddLine("Make sure you're somewhere safe when syncing - you're out in the open.", 1, 0.6, 0.2, true)
    end
    if inInstance() then
        GameTooltip:AddLine("In a dungeon - you'll be asked to confirm.", 1, 0.82, 0, true)
    end
    GameTooltip:AddLine(" ")
    local s = syncSettings()
    GameTooltip:AddLine("Click: reload to sync", 0.6, 0.6, 0.6)
    GameTooltip:AddLine(s.locked and "Right-click: unlock to move" or "Drag to move - right-click: lock", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("/wft sync for more options", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function syncRefresh()
    if not syncBtn then
        return
    end
    local s = syncSettings()
    local mins = minutesSinceSync()
    local r, g, b = 0.15, 0.15, 0.15
    local due = 0
    if mins >= s.remind * 2 then
        r, g, b, due = 0.55, 0.08, 0.08, 2
    elseif mins >= s.remind then
        r, g, b, due = 0.6, 0.38, 0.05, 1
    end
    syncBtn.due = due

    -- Chat reminder (1.9.8, "add a sync reminder to the general chat too")
    -- - a line in your own chat window each time another reminder interval
    -- passes (30m, 60m, 90m...). Only you see it; nothing is sent to any
    -- channel. /wft sync chat off turns it off.
    local intervals = math.floor(mins / s.remind)
    if intervals > syncChatNotified then
        syncChatNotified = intervals
        if not s.chatOff then
            local waiting = syncWaitingText(syncWaiting())
            print(("|cffffcc00WFT:|r It's been %dm since your last sync%s. Click the |cffffcc00Sync|r button or type /wft sync when you're somewhere safe."):format(
                mins, waiting and (" - waiting: " .. waiting) or ""))
        end
    end
    syncBtn.bg:SetColorTexture(r, g, b, 0.9)
    syncBtn.label:SetText(mins < 1 and "Sync" or ("Sync  |cffcccccc" .. mins .. "m|r"))
    if inCombat() then
        syncBtn.label:SetTextColor(0.5, 0.5, 0.5)
    else
        syncBtn.label:SetTextColor(1, 0.82, 0)
    end

    -- Glow: something worth sharing just happened, or you've just walked
    -- into an inn or city with something waiting
    local w = syncWaiting()
    local now = GetTime()
    local lvl, clears, rares, epics = syncHighlights(w)
    if syncLastSeen then
        if lvl > syncLastSeen[1] or clears > syncLastSeen[2] or rares > syncLastSeen[3] or epics > syncLastSeen[4] then
            syncGlowUntil = now + SYNC_GLOW_SECONDS
        end
    end
    syncLastSeen = { lvl, clears, rares, epics }
    local resting = isResting()
    if resting and not syncWasResting and syncWaitingText(w) then
        syncGlowUntil = now + SYNC_GLOW_SECONDS
    end
    syncWasResting = resting
end

local function syncSavePosition()
    local point, _, relPoint, x, y = syncBtn:GetPoint(1)
    local s = syncSettings()
    s.point, s.relPoint, s.x, s.y = point, relPoint, x, y
end

local function createSyncButton()
    if syncBtn then
        return
    end
    local s = syncSettings()
    local b = CreateFrame("Button", "WFTSyncButton", UIParent)
    b:SetSize(84, 22)
    b:SetFrameStrata("MEDIUM")
    b:SetClampedToScreen(true)
    b:SetMovable(true)
    b:EnableMouse(true)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    if s.point then
        b:SetPoint(s.point, UIParent, s.relPoint or s.point, s.x or 0, s.y or 0)
    else
        b:SetPoint("TOP", UIParent, "TOP", 0, -12)
    end

    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.55, 0.42, 0.15, 1)
    b.bg = b:CreateTexture(nil, "BORDER")
    b.bg:SetPoint("TOPLEFT", 1, -1)
    b.bg:SetPoint("BOTTOMRIGHT", -1, 1)
    b.glow = b:CreateTexture(nil, "ARTWORK")
    b.glow:SetPoint("TOPLEFT", -3, 3)
    b.glow:SetPoint("BOTTOMRIGHT", 3, -3)
    b.glow:SetColorTexture(1, 0.85, 0.3, 0.35)
    b.glow:SetBlendMode("ADD")
    b.glow:Hide()
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("CENTER")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.12)

    b:SetScript("OnDragStart", function(self)
        if not syncSettings().locked then
            self.dragging = true
            self:StartMoving()
        end
    end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        pcall(syncSavePosition)
        -- Letting go after a drag can also count as a click - never reload
        -- because the button was moved
        self.droppedAt = GetTime()
        self.dragging = false
    end)
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            local st = syncSettings()
            st.locked = not st.locked
            print("|cffffcc00WFT:|r Sync button " .. (st.locked and "locked." or "unlocked - drag it to move."))
            if GameTooltip:IsOwned(self) then
                syncShowTooltip(self)
            end
        elseif not self.dragging and GetTime() - (self.droppedAt or 0) > 0.3 then
            doSync()
        end
    end)
    b:SetScript("OnEnter", syncShowTooltip)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Pulse when due, glow after a highlight; cheap enough to run every frame
    local acc = 0
    b:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + elapsed
        local t = GetTime()
        if self.due and self.due > 0 then
            local speed = self.due == 2 and 4 or 2
            self.bg:SetAlpha(0.65 + 0.35 * math.abs(math.sin(t * speed)))
        else
            self.bg:SetAlpha(1)
        end
        if t < syncGlowUntil then
            self.glow:Show()
            self.glow:SetAlpha(0.4 + 0.6 * math.abs(math.sin(t * 3)))
        else
            self.glow:Hide()
        end
        if acc >= 2 then
            acc = 0
            pcall(syncRefresh)
        end
    end)

    syncBtn = b
    syncRefresh()
    if s.hidden then
        b:Hide()
    end
end

-- /wft sync [now|hide|show|lock|unlock|reset|remind <minutes>]
function cmdSync(arg, value)
    local s = syncSettings()
    if arg == nil or arg == "" or arg == "now" then
        doSync()
    elseif arg == "hide" then
        s.hidden = true
        if syncBtn then syncBtn:Hide() end
        print("|cffffcc00WFT:|r Sync button hidden. /wft sync show to bring it back.")
    elseif arg == "show" then
        s.hidden = false
        createSyncButton()
        syncBtn:Show()
        print("|cffffcc00WFT:|r Sync button shown.")
    elseif arg == "lock" or arg == "unlock" then
        s.locked = arg == "lock"
        print("|cffffcc00WFT:|r Sync button " .. (s.locked and "locked." or "unlocked - drag it to move."))
    elseif arg == "reset" then
        s.point, s.relPoint, s.x, s.y = nil, nil, nil, nil
        if syncBtn then
            syncBtn:ClearAllPoints()
            syncBtn:SetPoint("TOP", UIParent, "TOP", 0, -12)
        end
        print("|cffffcc00WFT:|r Sync button moved back to the top of the screen.")
    elseif arg == "chat" then
        if value == "off" or value == "on" then
            s.chatOff = value == "off"
        else
            s.chatOff = not s.chatOff
        end
        print("|cffffcc00WFT:|r Sync reminders in chat " .. (s.chatOff and "off." or "on."))
    elseif arg == "remind" then
        local n = tonumber(value)
        if n and n >= 1 then
            s.remind = math.floor(n)
            pcall(syncRefresh)
            print(("|cffffcc00WFT:|r Sync reminder set to %d minutes."):format(s.remind))
        else
            print("|cffffcc00WFT:|r Usage: /wft sync remind 15 (minutes)")
        end
    else
        print("|cffffcc00WFT:|r /wft sync - reload to sync now")
        print("  /wft sync hide | show | lock | unlock | reset")
        print("  /wft sync remind <minutes> - when the button turns amber (red at double)")
        print("  /wft sync chat on | off - the reminder line in your chat window")
    end
end

local syncFrame = CreateFrame("Frame")
pcall(syncFrame.RegisterEvent, syncFrame, "PLAYER_LOGIN")
pcall(syncFrame.RegisterEvent, syncFrame, "PLAYER_REGEN_DISABLED")
pcall(syncFrame.RegisterEvent, syncFrame, "PLAYER_REGEN_ENABLED")
pcall(syncFrame.RegisterEvent, syncFrame, "PLAYER_UPDATE_RESTING")
syncFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        pcall(createSyncButton)
    else
        pcall(syncRefresh)
    end
end)
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
    elseif msg == "pvplog" or msg:match("^pvplog%s") then
        cmdPvpLog(msg:match("^pvplog%s+(%S+)"))
    elseif msg == "statsprobe" then
        cmdStatsProbe()
    elseif msg == "achievementsprobe" then
        cmdAchievementsProbe()
    elseif msg == "legacypointsprobe" then
        cmdLegacyPointsProbe()
    elseif msg == "legacysystemprobe" then
        cmdLegacySystemProbe()
    elseif msg == "legacytreedatadump" then
        cmdLegacyTreeDataDump()
    elseif msg == "legacyframetreedump" then
        cmdLegacyFrameTreeDump()
    elseif msg == "pvprankframefind" then
        cmdPvpRankFrameFind()
    elseif msg == "legacyiconprobe" then
        cmdLegacyIconProbe()
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
    elseif msg == "sync" or msg:match("^sync%s") then
        cmdSync(msg:match("^sync%s+(%S+)"), msg:match("^sync%s+%S+%s+(%S+)"))
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
        print("  /wft pvplog - show your last PvP kills/deaths; /wft pvplog off (or on) to switch logging")
        print("  /wft specprobe - check for a spec API on this client (diagnostic, for me to look at)")
        print("  /wft counters - show your current death count (PvP kill tracking is paused)")
        print("  /wft statsprobe - check for a Statistics-pane API on this client (diagnostic, for me to look at)")
        print("  /wft achievementsprobe - dump the real Achievements/Legacy Challenges tree with completion state and checklists (diagnostic, for me to look at)")
        print("  /wft legacypointsprobe - hunt for where the in-game 'Legacy Points' number actually comes from (diagnostic, for me to look at)")
        print("  /wft legacysystemprobe - force-load Blizzard's Legacy System UI module and check what API appears (diagnostic, for me to look at - run this with the Legacy Challenges panel closed first)")
        print("  /wft legacytreedatadump - dump LegacyTreeData, found via legacysystemprobe (diagnostic, for me to look at - run legacysystemprobe first this session)")
        print("  /wft legacyframetreedump - dump the real widget names under the Legacy Challenges panel (diagnostic, for me to look at - OPEN the panel in game first, then run this)")
        print("  /wft pvprankframefind - search the open PvP panel for 'Rank Points' and dump its frame tree (diagnostic, for me to look at - OPEN the Player vs. Player panel in game first, then run this)")
        print("  /wft legacyiconprobe - check what type/value GetAchievementInfo's icon field actually is (diagnostic, for me to look at)")
        print("  /wft recipeprobe - check for a recipe-listing API on this client (diagnostic, for me to look at)")
        print("  /wft recipeschema - check whether this client can give back a recipe's reagents/description too, not just its name (diagnostic, for me to look at - run /wft recipescan at least once first)")
        print("  /wft recipescan [profession name] - with a profession window open, try reading its known recipes right now; pass a name (e.g. /wft recipescan Blacksmithing) if it can't tell which one is open")
        print("  /wft recipedump <profession name> - dump everything recorded for one profession's recipes, reagents included (diagnostic, for me to look at)")
        print("  /wft sync - reload to sync now; /wft sync help for the sync button's options")
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
        -- Find statistics outside the usual categories (see
        -- startStatisticIdScan) - runs in the background over a few frames
        pcall(startStatisticIdScan)
        -- Write an export right away too, so even a brand new install has
        -- real data in SavedVariables the moment you next log out or
        -- /reload, without needing any slash command first.
        writeSyncExport()
    end
end)

----------------------------------------------------------------------
-- Reputation snapshots (1.9.4) - see snapshotReputations
----------------------------------------------------------------------
-- A few seconds after entering the world (faction data isn't there yet at
-- PLAYER_LOGIN), and again whenever a standing changes, a short moment
-- later so a burst of rep gains is read once.
local repFrame = CreateFrame("Frame")
local repPending = false
local function queueRepSnapshot(delay)
    if repPending then
        return
    end
    local Timer = _G.C_Timer
    if type(Timer) == "table" and type(Timer.After) == "function" then
        repPending = true
        Timer.After(delay, function()
            repPending = false
            pcall(snapshotReputations)
        end)
    else
        pcall(snapshotReputations)
    end
end
pcall(repFrame.RegisterEvent, repFrame, "PLAYER_ENTERING_WORLD")
pcall(repFrame.RegisterEvent, repFrame, "UPDATE_FACTION")
repFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        queueRepSnapshot(5)
    elseif event == "UPDATE_FACTION" then
        local okT, now = safeCall(_G.GetTime)
        if okT and type(now) == "number" and now < repSnapshotQuietUntil then
            return
        end
        queueRepSnapshot(2)
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

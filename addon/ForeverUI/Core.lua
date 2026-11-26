-- Forever UI - a dark-and-gold, minimal replacement for the game's HUD.
--
-- Core: saved settings, events, the shared look (dark panel, 1px gold
-- hairline), keeping the game's own frames where we put them, and /fui.
-- Each piece (XPBar.lua, MicroMenu.lua, Minimap.lua) registers itself with
-- ns.Module and is only built when its switch is on.

local ADDON, ns = ...
ForeverUI = ns
ns.VERSION = "0.2.0"

-- The palette (the mockups' "dark and gold, minimal").
ns.C = {
    gold = { 0.788, 0.643, 0.361 },  -- the hairline, at ns.EdgeAlpha()
    bright = { 0.89, 0.753, 0.416 }, -- what needs you: a target, a proc, an active tab
    dark = { 0.047, 0.039, 0.031 },  -- panels, at ns.PanelAlpha()
    text = { 0.918, 0.875, 0.769 },
    muted = { 0.639, 0.584, 0.467 },
    xp = { 0.478, 0.322, 0.722 },
}

local DEFAULTS = {
    actionbars = true, xpbar = true, micro = true, bags = true, minimap = true, tooltip = true,
    castbar = true, swing = true, auras = true, customauras = true, dungeontracker = true, meter = true, windows = true, characterpage = true, chat = true, targetframe = true, playerframe = true, petframe = true, partyframe = true, dispel = true, healing = true, nameplates = true,
    meterInstanceOpen = true, meterInstanceReset = true,
    qolQuickLoot = false, qolAutoRepair = false, qolAutoJunk = false, qolQuestXP = true,
    qolAutoQuestAccept = false, qolAutoQuestTurnIn = false,
    qolCameraZoom = false, qolQuestVendor = false, qolQuestSparkles = false, qolNodeGlow = false, qolQuestMarks = false,
    qolLowRankCheck = false,
    noGameMenu = true, -- the game menu button off the micro menu (Esc still opens it)
    hideBagBar = true, -- the B key still opens the inventory
    microLabels = false, -- compact icons; tooltips always name the action
    edge = 0.5,      -- hairline strength
    dark = 0.82,     -- panel darkness
    xpText = true,   -- numbers always on the XP bar (else on hover)
    microFade = false,
    healPets = false, healSolo = false, healDeficit = false, healScale = 1, healReplaceParty = true, healTargets = false,
    healWidth = 120, healHeight = 25, healRaidRows = 8,
    healPower = true, healClassColor = false, healRoleColor = true, healThreat = true, healAuraTimers = false, healAbsorbs = true, healDispelButtons = true, dispelSound = true,
    plateThreat = true, plateTank = false, plateBorder = true, plateAuras = false,
    plateAuraSize = 16, plateAuraCount = 3, plateAuraTimers = true, plateHealthText = false, plateTarget = true, plateFocus = false, plateTargetOfTarget = false, plateCast = true, plateThreatText = false, plateThreatPercent = false,
    microFit = true, -- fit beside the XP bar; switch off for manual cell dimensions
    mapSize = 180,
    microColumns = 2, microWidth = 97, microHeight = 35, microGap = 2, microIcon = 31, microScale = 1,
}

function ns.O()
    return ns.db.opts
end

function ns.Opt(key)
    local v = ns.db and ns.db.opts[key]
    if v == nil then
        return DEFAULTS[key]
    end
    return v
end

function ns.EdgeAlpha()
    return tonumber(ns.Opt("edge")) or 0.5
end

function ns.PanelAlpha()
    return tonumber(ns.Opt("dark")) or 0.82
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

local events = CreateFrame("Frame")
local handlers = {}
events:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        local ok, err = pcall(fn, event, ...)
        if not ok then
            ns.Err(event, err)
        end
    end
end)

local function on(event, fn, optional)
    if not handlers[event] then
        -- an event this client doesn't have must not stop the piece asking
        local ok, err = pcall(events.RegisterEvent, events, event)
        if not ok then
            if not optional then
                ns.Err("event " .. tostring(event), err)
            end
            return false
        end
        handlers[event] = {}
    end
    table.insert(handlers[event], fn)
    return true
end
function ns.On(event, fn)
    return on(event, fn, false)
end
-- For events only some clients have (CRAFT_SHOW, older talent events):
-- quietly nothing where this one doesn't.
function ns.OnOptional(event, fn)
    return on(event, fn, true)
end

-- The last errors, newest first. One that keeps repeating (an event handler
-- every frame) is counted instead of pushing the rest out. Kept in the saved
-- settings too, so a session's errors can still be read after logging out.
ns.errors = {}
function ns.Err(where, err)
    local line = tostring(where) .. ": " .. tostring(err)
    local last = ns.errors[1]
    if last and (last == line or last:match("^(.-)  %(x%d+%)$") == line) then
        local n = tonumber(last:match("%(x(%d+)%)$")) or 1
        ns.errors[1] = line .. "  (x" .. (n + 1) .. ")"
    else
        table.insert(ns.errors, 1, line)
        if #ns.errors > 20 then
            table.remove(ns.errors)
        end
    end
    if ns.db then
        ns.db.lastErrors = ns.errors
    end
end

-- Runs fn now, or once combat ends if the frame is one the game protects.
local afterCombat = {}
local queuedAfterCombat = {}
function ns.WhenSafe(fn)
    if InCombatLockdown and InCombatLockdown() then
        if not queuedAfterCombat[fn] then
            queuedAfterCombat[fn] = true
            table.insert(afterCombat, fn)
        end
    else
        fn()
    end
end
ns.On("PLAYER_REGEN_ENABLED", function()
    local list = afterCombat
    afterCombat = {}
    queuedAfterCombat = {}
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn)
        if not ok then
            ns.Err("after combat", err)
        end
    end
end)

----------------------------------------------------------------------
-- The look
----------------------------------------------------------------------

local panels = {}

-- A dark backing with a 1px gold hairline inside its edge. bright: the
-- hairline at full gold (something that needs you).
function ns.Panel(f, opts)
    opts = opts or {}
    local p = f.fuiPanel
    if not p then
        p = { bg = f:CreateTexture(nil, "BACKGROUND", nil, -7), lines = {} }
        p.bg:SetAllPoints()
        for i = 1, 4 do
            p.lines[i] = f:CreateTexture(nil, "BORDER", nil, 7)
        end
        local t, b, l, r = p.lines[1], p.lines[2], p.lines[3], p.lines[4]
        t:SetPoint("TOPLEFT")
        t:SetPoint("TOPRIGHT")
        t:SetHeight(1)
        b:SetPoint("BOTTOMLEFT")
        b:SetPoint("BOTTOMRIGHT")
        b:SetHeight(1)
        l:SetPoint("TOPLEFT")
        l:SetPoint("BOTTOMLEFT")
        l:SetWidth(1)
        r:SetPoint("TOPRIGHT")
        r:SetPoint("BOTTOMRIGHT")
        r:SetWidth(1)
        f.fuiPanel = p
        table.insert(panels, f)
    end
    p.bright = opts.bright
    p.noBg = opts.noBg
    p.alpha = opts.alpha
    p.edge = opts.edge -- the hairline weaker than the rest (an inset)
    ns.PaintPanel(f)
    return p
end

function ns.PaintPanel(f)
    local p = f.fuiPanel
    if not p then
        return
    end
    local C = ns.C
    if p.noBg then
        p.bg:Hide()
    else
        p.bg:Show()
        p.bg:SetColorTexture(C.dark[1], C.dark[2], C.dark[3], (p.alpha or 1) * ns.PanelAlpha())
    end
    local c, a = C.gold, ns.EdgeAlpha() * (p.edge or 1)
    if p.bright then
        c, a = C.bright, 1
    end
    for i = 1, 4 do
        p.lines[i]:SetColorTexture(c[1], c[2], c[3], a)
    end
end

-- A small draggable scrollbar for lists which otherwise use mouse-wheel offsets.
function ns.ListScrollbar(parent, onChange)
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, -6); bar:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 2, 6); bar:SetWidth(8)
    bar:SetOrientation("VERTICAL"); bar:SetMinMaxValues(0, 1); bar:SetValueStep(1)
    if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end
    local track = bar:CreateTexture(nil, "BACKGROUND"); track:SetAllPoints(); track:SetColorTexture(0.08, 0.07, 0.06, 0.9)
    ns.Panel(bar, { noBg = true, edge = 0.65 })
    local thumb = bar:CreateTexture(nil, "ARTWORK"); thumb:SetSize(6, 28); thumb:SetColorTexture(0.76, 0.57, 0.28, 1); bar:SetThumbTexture(thumb)
    bar:SetScript("OnValueChanged", function(self, value)
        if not self.fuiUpdating and type(value) == "number" then onChange(math.floor(value + 0.5)) end
    end)
    bar:Hide(); return bar
end

function ns.UpdateListScrollbar(bar, offset, maximum)
    maximum = math.max(0, maximum or 0)
    bar.fuiUpdating = true; bar.fuiMaximum = maximum; bar:SetMinMaxValues(0, math.max(1, maximum)); bar:SetValue(math.min(maximum, math.max(0, offset or 0))); bar.fuiUpdating = false
    bar:SetShown(maximum > 0)
end

-- The look changed (Options): every panel repainted, every piece told.
function ns.Restyle()
    for _, f in ipairs(panels) do
        ns.PaintPanel(f)
    end
    for _, m in ipairs(ns.modules) do
        if m.built and m.Restyle then
            local ok, err = pcall(m.Restyle, m)
            if not ok then
                ns.Err(m.name, err)
            end
        end
    end
end

function ns.Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", "GameFontHighlightSmall")
    local font, _, flags = fs:GetFont()
    if font then
        fs:SetFont(font, size or 10, flags or "")
    end
    color = color or ns.C.text
    fs:SetTextColor(color[1], color[2], color[3])
    if fs.SetShadowOffset then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.9)
    end
    return fs
end

----------------------------------------------------------------------
-- The game's frames: hidden for good, or kept where we put them
----------------------------------------------------------------------

-- A frame that's never shown: what we take away goes in here, so nothing
-- the game does later (Show, Edit Mode) brings it back.
ns.hider = CreateFrame("Frame")
ns.hider:Hide()

function ns.Stash(frame)
    if type(frame) == "table" and frame.SetParent then
        ns.WhenSafe(function()
            frame:SetParent(ns.hider)
        end)
        return true
    end
    return false
end

-- The game moves some frames back on its own (Edit Mode, vehicles, layout
-- changes). Keep(frame, place) runs place(frame) now and again each time
-- anything else re-anchors it.
function ns.Keep(frame, place)
    if type(frame) ~= "table" or not frame.SetPoint then
        return
    end
    frame.fuiPlace = place
    -- Replacing a placement must reuse its original hook and recursion
    -- guard. A second closure would let the old hook re-enter the new one.
    if frame.fuiApply then
        ns.WhenSafe(frame.fuiApply)
        return
    end
    local busy = false
    local function apply()
        if busy or not frame.fuiPlace then
            return
        end
        busy = true
        local ok, err = pcall(frame.fuiPlace, frame)
        busy = false
        if not ok then
            ns.Err("place", err)
        end
    end
    frame.fuiApply = apply
    if not frame.fuiHooked then
        frame.fuiHooked = true
        hooksecurefunc(frame, "SetPoint", function()
            if busy then
                return
            end
            if frame.IsProtected and frame:IsProtected() and InCombatLockdown() then
                ns.WhenSafe(apply)
            else
                apply()
            end
        end)
    end
    ns.WhenSafe(apply)
end

-- Some of the game's pieces (swing timers, the damage meter) are their own
-- addons: fn() once that one has loaded (now, if it already has).
local waiting = {}
function ns.AfterBlizzard(addon, fn)
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon)
    if loaded then
        local ok, err = pcall(fn)
        if not ok then
            ns.Err(addon, err)
        end
        return
    end
    waiting[addon] = waiting[addon] or {}
    table.insert(waiting[addon], fn)
end
ns.On("ADDON_LOADED", function(_, name)
    local list = waiting[name]
    if not list then
        return
    end
    waiting[name] = nil
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn)
        if not ok then
            ns.Err(name, err)
        end
    end
end)

-- The game hides some numbers from addons in places (a "secret" value);
-- those are left for the game's own code to show.
function ns.Secret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- Names on Forever can share a first name; the player GUID identifies the
-- actual character and remains stable across logins and renames.
function ns.HealingCharacterKey()
    if ns.healingCharacterKey then return ns.healingCharacterKey end
    if type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, "player")
    if ok and not ns.Secret(guid) and type(guid) == "string" and guid ~= "" then
        ns.healingCharacterKey = "guid:" .. guid
        return ns.healingCharacterKey
    end
end

-- Whether the player knows a spell. The old globals (IsPlayerSpell,
-- IsSpellKnown) may be gone; C_SpellBook.IsSpellKnown is this client's.
function ns.SpellKnown(id)
    if type(id) ~= "number" then
        return false
    end
    for _, fn in ipairs({ IsPlayerSpell or false, IsSpellKnown or false, (C_SpellBook and C_SpellBook.IsSpellKnown) or false }) do
        if type(fn) == "function" then
            local ok, value = pcall(fn, id)
            if ok and not ns.Secret(value) and value == true then
                return true
            end
        end
    end
    return false
end

-- Takes a texture of the game's away for good (it can still be shown and
-- animated; it just never draws).
function ns.Bin(region)
    if type(region) == "table" and region.SetParent then
        region:SetParent(ns.hider)
    end
end

ns.FLAT = "Interface\\Buttons\\WHITE8X8"

----------------------------------------------------------------------
-- Pieces
----------------------------------------------------------------------

ns.modules = {}

-- key: the switch in Options; build(m) makes it (once, at login).
function ns.Module(key, name, build)
    local m = { key = key, name = name, build = build }
    table.insert(ns.modules, m)
    ns.modules[key] = m
    return m
end

local function buildAll()
    for _, m in ipairs(ns.modules) do
        if not m.built and ns.Opt(m.key) then
            local ok, err = pcall(m.build, m)
            if ok then
                m.built = true
            else
                ns.Err(m.name, err)
            end
        end
    end
end

ns.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then
        return
    end
    ForeverUIDB = ForeverUIDB or {}
    ns.db = ForeverUIDB
    ns.db.opts = ns.db.opts or {}
    ns.db.pos = ns.db.pos or {}
    -- this session's errors (any from loading the files are already in)
    ns.db.lastErrors = ns.errors
    if not ns.db.minimapSizeReducedOnce then
        -- Apply the requested 10% reduction to an existing chosen size too,
        -- but only once; future user changes remain under their control.
        local previous = tonumber(ns.db.opts.mapSize) or 200
        ns.db.opts.mapSize = math.max(1, math.floor(previous * 0.9 + 0.5))
        ns.db.minimapSizeReducedOnce = true
    end
end)

ns.On("PLAYER_LOGIN", function()
    buildAll()
    if ns.SetupOptions then
        local ok, err = pcall(ns.SetupOptions)
        if not ok then
            ns.Err("options", err)
        end
    end
end)

----------------------------------------------------------------------
-- /fui
----------------------------------------------------------------------

function ns.Print(msg)
    print("|cffe3c06aForever UI:|r " .. msg)
end

SLASH_FOREVERUI1 = "/fui"
SlashCmdList.FOREVERUI = function(msg)
    local original = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    msg = original:lower()
    if msg == "move" then
        ns.ToggleMoveMode()
    elseif msg == "reset" then
        ns.ResetPositions()
    elseif msg == "errors" then
        if #ns.errors == 0 then
            ns.Print("no errors this session.")
        else
            for _, e in ipairs(ns.errors) do
                ns.Print(e)
            end
        end
    elseif msg == "heal" then
        if ns.modules.healing and ns.modules.healing.built then ns.modules.healing:ShowConfig()
        else ns.Print("enable Healing frames in /fui and reload first.") end
    elseif msg == "dispel" then
        if ns.modules.dispel and ns.modules.dispel.built then ns.modules.dispel:Toggle()
        else ns.Print("enable Dispel indicators in Forever UI options and reload first.") end
    elseif msg == "healauras" then
        if ns.modules.healing and ns.modules.healing.built then ns.modules.healing:ShowAuraConfig() end
    elseif msg == "auras" then
        if ns.CustomAuras and ns.CustomAuras.frame then ns.CustomAuras:ShowConfig() end
    elseif msg == "profiles" then
        if ns.modules.healing and ns.modules.healing.built then ns.modules.healing:ShowProfiles() end
    elseif msg == "encyclopedia" or msg == "guide" then
        if ns.OpenEncyclopedia then ns.OpenEncyclopedia() end
    elseif msg == "instance" or msg == "journal" then
        if ns.InstanceGuide then ns.InstanceGuide:Toggle() end
    elseif msg:match("^healbind%s") or msg == "healbind" then
        local binding, spell = original:match("^%S+%s+(%S+)%s*(.*)$")
        if ns.modules.healing and ns.modules.healing.built and ns.modules.healing.SetBinding then
            ns.modules.healing:SetBinding(binding and binding:lower(), spell)
        else
            ns.Print("enable Healing frames in /fui and reload first.")
        end
    elseif msg == "perf" or msg:match("^perf%s") then
        ns.Perf(msg:match("^perf%s+(.+)$"))
    elseif ns.OpenOptions then
        ns.OpenOptions()
    end
end

----------------------------------------------------------------------
-- /fui perf [map] [seconds]: frame time and each addon's share of it, from the
-- game's own addon profiler. "map" counts only frames with the world map open
-- (it waits for the map). Kept in ForeverUIDB.perfLog (the last 5 runs).
----------------------------------------------------------------------

do
    local P = { frame = nil }
    local LAST = Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric.LastTime or 3

    local function mapShown()
        local map = rawget(_G, "WorldMapFrame")
        return map and map.IsShown and map:IsShown() or false
    end

    local function addonNames()
        local list = {}
        local num = (C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns)()
        local info = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
        local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
        for i = 1, num do
            local name = info(i)
            if name and loaded(name) then list[#list + 1] = name end
        end
        return list
    end

    local function percentile(sorted, p)
        if #sorted == 0 then return 0 end
        return sorted[math.max(1, math.min(#sorted, math.floor(#sorted * p + 0.5)))]
    end

    -- OpenMap's own timings over the run, when it's loaded: each step of its view update (worst and
    -- smoothed) and its timed parts (zoom update, every addon's pins rescaled ...), added up a frame
    local function openMapStitch()
        local om = rawget(_G, "OpenMap")
        local S = type(om) == "table" and om.MapStitch
        return type(S) == "table" and S or nil
    end

    local function openMapStart(run)
        local S = openMapStitch()
        if not S then return end
        for _, s in pairs(type(S.closeSteps) == "table" and S.closeSteps or {}) do s.worst = 0 end
        if S.bench == nil then S.bench = {}; run.ownBench = true end
    end

    local function openMapFinish(run, n)
        local S = openMapStitch()
        if not S then return end
        local steps = {}
        for name, s in pairs(type(S.closeSteps) == "table" and S.closeSteps or {}) do
            if (s.worst or 0) >= 0.5 then steps[#steps + 1] = { name = name, worst = s.worst, ms = s.ms } end
        end
        table.sort(steps, function(a, b) return a.worst > b.worst end)
        while #steps > 8 do table.remove(steps) end
        local parts = {}
        if run.ownBench and type(S.bench) == "table" then
            for name, ms in pairs(S.bench) do parts[#parts + 1] = { name = name, ms = ms / n } end
            table.sort(parts, function(a, b) return a.ms > b.ms end)
            S.bench = nil
        end
        return steps, parts
    end

    local function finish(run)
        P.frame:SetScript("OnUpdate", nil)
        P.frame:Hide()
        P.run = nil
        local steps, parts = openMapFinish(run, math.max(1, #run.frames))
        local n = #run.frames
        if n == 0 then ns.Print("perf: no frames recorded.") return end
        local sum = 0
        for _, ms in ipairs(run.frames) do sum = sum + ms end
        table.sort(run.frames)
        local rows = {}
        for i, name in ipairs(run.names) do
            if run.sum[i] > 0 then rows[#rows + 1] = { name = name, avg = run.sum[i] / n, worst = run.max[i] } end
        end
        table.sort(rows, function(a, b) return a.avg > b.avg end)
        local over, hitches = 0, 0
        for _, ms in ipairs(run.frames) do
            if ms > 1000 / 244 then over = over + 1 end
            if ms > 33 then hitches = hitches + 1 end
        end
        local cvar = function(k) local ok, v = pcall(GetCVar, k) return ok and v or "?" end
        local om = rawget(_G, "OpenMapDB")
        local result = {
            at = date("%Y-%m-%d %H:%M:%S"), map = run.onlyMap, frames = n, seconds = run.seconds,
            frameMs = sum / n, p90 = percentile(run.frames, 0.9), p99 = percentile(run.frames, 0.99),
            fps = 1000 / (sum / n), over244 = over, hitches = hitches, openMapSteps = steps, openMapParts = parts,
            addonsMs = run.addons / n, addonsWorst = run.addonsWorst, gameMs = run.app / n,
            maxFPS = cvar("maxFPS"), vsync = cvar("vsync"),
            openMapCap = om and om.worldmap and om.worldmap.mapFpsCap,
            top = {},
        }
        for i = 1, math.min(15, #rows) do result.top[i] = rows[i] end
        ForeverUIDB.perfLog = ForeverUIDB.perfLog or {}
        table.insert(ForeverUIDB.perfLog, 1, result)
        while #ForeverUIDB.perfLog > 5 do table.remove(ForeverUIDB.perfLog) end
        ns.Print(string.format("perf%s: %.0f fps, frame %.2f ms (90%% %.2f, 99%% %.2f); the game's own work %.2f ms, all addons %.2f ms a frame (worst %.1f). maxFPS %s%s.",
            run.onlyMap and " (map open)" or "", result.fps, result.frameMs, result.p90, result.p99, result.gameMs, result.addonsMs, result.addonsWorst,
            result.maxFPS, result.openMapCap and result.openMapCap > 0 and (", OpenMap cap " .. result.openMapCap) or ""))
        for i = 1, math.min(6, #rows) do
            ns.Print(string.format("  %s %.2f ms a frame (worst %.1f)", rows[i].name, rows[i].avg, rows[i].worst))
        end
        if steps and #steps > 0 then
            local list = {}
            for i = 1, math.min(4, #steps) do list[i] = string.format("%s %.1f", steps[i].name, steps[i].worst) end
            ns.Print("  OpenMap's slowest steps (worst ms): " .. table.concat(list, ", "))
        end
        ns.Print(string.format("  frames over 33 ms: %d of %d", hitches, n))
    end

    function ns.Perf(arg)
        local prof = rawget(_G, "C_AddOnProfiler")
        if not (prof and prof.GetAddOnMetric and prof.GetApplicationMetric) then ns.Print("perf: this client has no addon profiler.") return end
        if prof.IsEnabled and not prof.IsEnabled() then ns.Print("perf: the game's addon profiler is off.") return end
        if P.run then ns.Print("perf: stopped.") finish(P.run) return end
        arg = arg or ""
        local onlyMap = arg:find("map") ~= nil
        local seconds = math.min(60, math.max(2, tonumber(arg:match("(%d+)")) or 10))
        local names = addonNames()
        local run = { names = names, sum = {}, max = {}, frames = {}, addons = 0, app = 0, addonsWorst = 0, onlyMap = onlyMap, seconds = seconds, left = seconds }
        for i = 1, #names do run.sum[i], run.max[i] = 0, 0 end
        P.run = run
        openMapStart(run)
        P.frame = P.frame or CreateFrame("Frame")
        P.frame:Show()
        P.frame:SetScript("OnUpdate", function(_, elapsed)
            if onlyMap and not mapShown() then return end
            if run.skip == nil then run.skip = true return end   -- (the frame the map opened on isn't a steady one)
            run.left = run.left - (elapsed or 0)
            run.frames[#run.frames + 1] = (elapsed or 0) * 1000
            run.app = run.app + prof.GetApplicationMetric(LAST)
            local all = prof.GetOverallMetric(LAST)
            run.addons = run.addons + all
            if all > run.addonsWorst then run.addonsWorst = all end
            for i = 1, #names do
                local ms = prof.GetAddOnMetric(names[i], LAST)
                run.sum[i] = run.sum[i] + ms
                if ms > run.max[i] then run.max[i] = ms end
            end
            if run.left <= 0 then finish(run) end
        end)
        ns.Print(onlyMap and string.format("perf: recording %d s while the map's open: do what you want measured.", seconds)
            or string.format("perf: recording %d s.", seconds))
    end
end

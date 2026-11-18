-- Forever Gold - the Farming Session window (was "Kills & Loot")
--
-- The kill and loot tracker in a small window of its own, apart from the
-- main Forever Gold window. It starts as a thin strip and grows downward as
-- kills and loot come in (scrolling once it reaches MAX_LIST). Drag it by
-- its top bar; "-" folds it to the bar alone. It remembers where you put it
-- and whether it was open.
--
--   Kills  - every mob killed this trip with what a kill is worth, and under
--            each one a row of what it drops and how often ("Linen 35%").
--            Click a mob for the details. Gathering is listed node by node.
--   Loot   - everything looted, most valuable first
--   Money  - real money in and out: auction sales, vendor sales, coin, repairs
--
-- All the counting happens in Tracker.lua; this file only shows it.

local _, ns = ...
local floor, max, min = math.floor, math.max, math.min

local W = 286
local MAX_LIST = 440
local SKULL = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
local PICK = "Interface\\Icons\\Trade_Mining"

local win
local view = { tab = "kills", sort = "recent", open = {} }

local function kit()
    return ns.UIKit
end

local function plural(n, word)
    return n .. " " .. word .. (n == 1 and "" or "s")
end

local function pct(r)
    if r <= 0 then
        return "0%"
    elseif r < 0.01 then
        return "<1%"
    end
    return floor(r * 100 + 0.5) .. "%"
end

local SORT_NEXT = { recent = "kills", kills = "value", value = "recent" }
local SORT_LABEL = { recent = "Sort: Recent", kills = "Sort: Kills", value = "Sort: Gold" }

----------------------------------------------------------------------
-- What the tabs show
----------------------------------------------------------------------

local function topDrops(items, n)
    local parts = {}
    for i = 1, min(n, #items) do
        parts[i] = items[i].n .. " " .. ns.ItemName(items[i].id)
    end
    return table.concat(parts, ", ")
end

local function mobDetail(m)
    local G = kit().GREY
    local lines = {}
    lines[#lines + 1] = "Worth per kill: " .. ns.Money(m.perKill) .. G .. "   (" .. ns.Money(m.value) .. " in all)|r"
    if #m.zones > 0 then
        local z = {}
        for i, e in ipairs(m.zones) do
            z[i] = e.name .. (#m.zones > 1 and (" " .. e.n) or "")
        end
        lines[#lines + 1] = "Where: " .. table.concat(z, ", ")
    end
    if m.coin > 0 then
        lines[#lines + 1] = "Coin: " .. ns.Money(m.coin)
    end
    if m.good > 0 then
        local every = max(1, floor(m.k / m.good + 0.5))
        lines[#lines + 1] = "Green or better: " .. m.good .. G .. (every == 1 and " (about every kill)|r" or (" (about 1 in " .. every .. " kills)|r"))
    end
    lines[#lines + 1] = "Kills since your last green or better: " .. m.since
    local life = m.life
    lines[#lines + 1] = G .. "All time: " .. plural(life.k or 0, "kill") .. ", " .. ns.Money(life.v or 0) .. " looted"
        .. ((life.good or 0) > 0 and (", " .. life.good .. " green or better") or "") .. "|r"
    return table.concat(lines, "\n")
end

-- The row of drops under a mob: each item and how often it drops per kill.
local function dropChips(m)
    local chips = {}
    for _, d in ipairs(m.drops) do
        local tip = {
            "Dropped from " .. d.d .. " of " .. plural(m.k, "kill") .. " (" .. pct(d.rate) .. ")",
            pct(d.share) .. " of everything " .. m.name .. " has dropped this trip",
        }
        if d.lifeRate and (m.life.k or 0) > m.k then
            tip[#tip + 1] = "All time: " .. pct(d.lifeRate) .. " over " .. plural(m.life.k, "kill")
        end
        if d.n > 0 then
            tip[#tip + 1] = "You looted " .. d.n .. ", worth " .. ns.StripCodes(ns.Money(d.v)) .. " each"
        end
        chips[#chips + 1] = { id = d.id, text = pct(d.rate), tip = tip }
    end
    return chips
end

local function buildKills()
    local K = kit()
    local rows = {}
    local s = ns.TrackerSummary and ns.TrackerSummary()
    if not s then
        K.Tx(rows, nil, "Start a session, then go farm: kills, loot and gold per hour are counted as you go. Quests aren't counted.")
        return rows
    end
    K.Hd(rows, plural(s.kills, "kill") .. (s.secs > 60 and (K.GREY .. "  " .. floor(s.kills / s.secs * 3600 + 0.5) .. "/hr|r") or ""),
        "streak " .. s.streak .. K.GREY .. ", best " .. s.best .. "|r")
    for _, m in ipairs(ns.TrackerMobs(view.sort)) do
        local name = m.name
        rows[#rows + 1] = { icon = m.drops[1] and ns.Icon(m.drops[1].id) or SKULL,
            title = (view.open[name] and "|cffffd100" or "") .. name .. "|r" .. K.GREY .. " x" .. m.k .. "|r",
            r2 = ns.Money(m.perKill) .. K.GREY .. "/kill|r", r1 = ns.Money(m.value),
            tipTitle = name, tip = function() return { mobDetail(m), " ", K.GREY .. "Click to show or hide the details.|r" } end,
            onClick = function()
                view.open[name] = not view.open[name] or nil
                ns.RefreshTrackerWindow(true)
            end }
        if #m.drops > 0 then
            rows[#rows + 1] = { type = "chips", chips = dropChips(m) }
        end
        if view.open[name] then
            K.Tx(rows, nil, mobDetail(m))
        end
    end
    local nodes = ns.TrackerNodes()
    if #nodes > 0 then
        K.Hd(rows, "Gathering", plural(s.gathers, "gather"))
        for _, e in ipairs(nodes) do
            rows[#rows + 1] = { icon = e.items[1] and ns.Icon(e.items[1].id) or PICK,
                title = e.name .. K.GREY .. " x" .. e.n .. "|r", r2 = ns.TRACK_CAT_LABEL[e.cat] or "", r1 = ns.Money(e.value),
                tipTitle = e.name, onClick = false,
                tip = function()
                    local lines = {}
                    for _, it in ipairs(e.items) do
                        lines[#lines + 1] = { it.n .. " x " .. ns.ItemName(it.id), ns.Money(it.v) }
                    end
                    lines[#lines + 1] = " "
                    lines[#lines + 1] = K.GREY .. "All time: gathered " .. (e.life.n or 0) .. " times, " .. ns.Money(e.life.v or 0) .. "|r"
                    return lines
                end }
            if #e.items > 0 then
                local chips = {}
                for _, it in ipairs(e.items) do
                    chips[#chips + 1] = { id = it.id, text = "x" .. it.n,
                        tip = { it.n .. " from " .. plural(e.n, "gather") .. ", worth " .. ns.StripCodes(ns.Money(it.v)) } }
                end
                rows[#rows + 1] = { type = "chips", chips = chips }
            end
        end
    end
    return rows
end

local function buildLoot()
    local K = kit()
    local rows = {}
    local s = ns.TrackerSummary and ns.TrackerSummary()
    if not s then
        K.Tx(rows, nil, "Nothing looted yet - press Start first.")
        return rows
    end
    K.Hd(rows, "Looted", ns.Money(s.made))
    if s.coin > 0 then
        rows[#rows + 1] = { icon = K.COIN, title = "Coin", r1 = ns.Money(s.coin), onClick = false,
            tip = { "From mobs and chests." } }
    end
    for _, it in ipairs(s.items) do
        rows[#rows + 1] = { id = it.id, title = it.n .. " x " .. ns.ItemName(it.id),
            r2 = it.n > 1 and (ns.Money(it.v / it.n) .. K.GREY .. " ea|r") or "", r1 = ns.Money(it.v) }
    end
    if #s.items == 0 and s.coin == 0 then
        K.Tx(rows, nil, "Nothing yet.")
    end
    return rows
end

local function buildMoney()
    local K = kit()
    local rows = {}
    local s = ns.TrackerSummary and ns.TrackerSummary()
    if not s then
        K.Tx(rows, nil, "Press Start first.")
        return rows
    end
    K.Hd(rows, "Real money in and out", ns.Profit(s.net))
    local inc, out = s.inc or {}, s.out or {}
    local function money(title, tip, v, sign)
        if (v or 0) > 0 then
            rows[#rows + 1] = { icon = K.COIN, title = title, tip = { tip }, onClick = false,
                r1 = sign < 0 and ("|cffff7070-" .. ns.Money(v) .. "|r") or ns.Money(v) }
        end
    end
    money("Coin looted", "From mobs and chests.", s.coin, 1)
    money("Auction sales", "Collected from your mailbox.", inc.ah, 1)
    money("Vendor sales", "Sold to shopkeepers.", inc.vendor, 1)
    money("Other mail", "Mail that wasn't an auction sale.", inc.mail, 1)
    money("Other", "Trades and anything else. Quest rewards aren't counted.", inc.other, 1)
    money("Auction house", "Purchases and deposits.", out.ah, -1)
    money("Vendors", "Purchases and repairs.", out.vendor, -1)
    money("Elsewhere", "Training, flights, postage.", out.other, -1)
    if s.cashIn == 0 and s.cashOut == 0 then
        K.Tx(rows, nil, "No money has changed hands yet.")
    end
    for i = 1, min(15, #s.sold) do
        if i == 1 then
            K.Hd(rows, "Auction sales collected", ns.Money(inc.ah or 0))
        end
        local e = s.sold[i]
        local id = ns.FindItemByName and ns.FindItemByName(e.name)
        rows[#rows + 1] = { id = id, icon = not id and K.COIN or nil, title = e.q .. " x " .. (id and ns.ItemName(id) or e.name),
            r1 = ns.Money(e.v), onClick = false }
    end
    return rows
end

local BUILD = { kills = buildKills, loot = buildLoot, money = buildMoney }

----------------------------------------------------------------------
-- The window
--
-- Idle:      one big "Start session" button.
-- Recording: time, kills, money actually earned and the estimated value of
--            what you looted, then Stop / Save trip / Reset and the tabs.
-- Stopped:   the same, with Start as the main button (it carries on).
-- "-" folds it into a narrow status strip for while you farm.
----------------------------------------------------------------------

local TITLE_H, STATS_H, ROW_H = 22, 36, 24
local STRIP_W = 236

local function state()
    if ns.TrackerRunning and ns.TrackerRunning() then
        return "recording"
    elseif ns.TrackerSummary and ns.TrackerSummary() then
        return "paused"
    end
    return "idle"
end

local STATE_LABEL = { idle = "Idle", recording = "|cff59e659Recording|r", paused = "|cffffd100Stopped|r" }

-- The summary the once-a-second tick reads. Building it walks every item,
-- mob and sale of the trip, so the tick reuses the last one and only moves
-- the clock on. It's rebuilt whenever the window refreshes (a kill, loot,
-- coin or new prices) and every 10 seconds as a safety net.
local tick, tickAt

local function freshSummary()
    tick = ns.TrackerSummary and ns.TrackerSummary()
    tickAt = GetTime()
    return tick
end

local function tickSummary()
    if not tick or GetTime() - (tickAt or 0) >= 10 then
        return freshSummary()
    end
    local secs = ns.TrackerSeconds()
    tick.secs = secs
    tick.perHour = secs > 60 and tick.made / secs * 3600 or nil
    return tick
end

local function headline(s)
    s = s or freshSummary()
    if not s then
        return kit().GREY .. "Idle|r"
    end
    return ns.Duration(max(1, s.secs)) .. "  ·  " .. plural(s.kills, "kill")
        .. (s.perHour and ("  ·  |cffffd100" .. ns.Money(s.perHour) .. "/hr|r") or "")
end

local function fillStats(s)
    s = s or tick or freshSummary()
    if not s or not win then
        return
    end
    local c = win.cells
    c[1].value:SetText(ns.Duration(max(1, s.secs)))
    c[2].value:SetText(tostring(s.kills))
    c[3].value:SetText(ns.Money(s.cashIn or s.coin))
    c[4].value:SetText(ns.Money(max(0, s.made - s.coin)))
    win.rate:SetText(s.perHour and (ns.Money(s.perHour) .. kit().GREY .. " an hour|r")
        or (kit().GREY .. "gold/hr after 1 min|r"))
end

-- The window is pinned by its top-left corner, so a change in height grows
-- or shrinks it downward.
local function pin(f)
    local left, top = f:GetLeft(), f:GetTop()
    if left and top then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        ns.db.opts.trackerPos = { x = floor(left + 0.5), y = floor(top + 0.5) }
    end
end

-- Lays the window out for its state and fits it around its list: just the
-- status strip when folded, otherwise as tall as the rows need.
local function fit(st)
    local folded = ns.db.opts.trackerCollapsed and true or false
    local idle = st == "idle"
    for _, w in ipairs(win.sessionOnly) do
        w:SetShown(not folded and not idle)
    end
    win.sort:SetShown(not folded and not idle and view.tab == "kills")
    win.startBig:SetShown(not folded and idle)
    win.title:SetShown(not folded)
    win.state:SetShown(not folded)
    win.head:SetShown(folded)
    win.list.clip:SetShown(not folded)
    win.fold:SetLabel(folded and "+" or "-")
    if folded then
        win:SetSize(STRIP_W, TITLE_H)
        return
    end
    local chrome = idle and (TITLE_H + ROW_H + 10) or (TITLE_H + STATS_H + ROW_H * 2 + 8)
    win.list.clip:ClearAllPoints()
    win.list.clip:SetPoint("TOPLEFT", win, "TOPLEFT", 4, -chrome)
    win.list.clip:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -4, 4)
    local listH = max(20, min(MAX_LIST, win.list.contentH or 0))
    win.list.viewW = W - 8
    win.list.viewH = listH
    win:SetSize(W, chrome + listH + 4)
    win.list:Apply()
end

function ns.RefreshTrackerWindow(keepScroll)
    if not win or not win:IsShown() then
        return
    end
    local st = state()
    if st == "recording" then
        win.dot:SetColorTexture(0.35, 0.9, 0.35, 1)
    elseif st == "paused" then
        win.dot:SetColorTexture(1, 0.82, 0, 1)
    else
        win.dot:SetColorTexture(0.45, 0.44, 0.42, 1)
    end
    win.state:SetText(STATE_LABEL[st])
    local s = freshSummary()
    win.head:SetText(headline(s))
    win.start:SetLabel(st == "recording" and "Stop" or "Start")
    win.start:SetPrimary(st == "paused")
    win.sort:SetLabel(SORT_LABEL[view.sort])
    for key, b in pairs(win.tabs) do
        b:SetOn(key == view.tab)
    end
    fillStats(s)
    if not ns.db.opts.trackerCollapsed then
        local ok, rows = pcall(BUILD[view.tab])
        if not ok then
            ns.Err("tracker-" .. view.tab, rows)
            rows = { { type = "text", text = "Something went wrong here. Type /gold debug for the details." } }
        end
        win.list.viewW = W - 8
        win.list:SetRows(rows, keepScroll)
    end
    fit(st)
end

local function create()
    local K = kit()
    local C = K.C
    local f = CreateFrame("Frame", "ForeverGoldTracker", UIParent)
    f:SetSize(W, 120)
    local pos = ns.db.opts.trackerPos
    if type(pos) == "table" and pos.x and pos.y then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -80, -220)
    end
    f:SetFrameStrata("MEDIUM")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        pin(self)
    end)
    K.skin(f)

    local bar = K.tex(f, "BORDER", C.panel[1], C.panel[2], C.panel[3], 1)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(TITLE_H - 1)
    f.dot = K.tex(f, "ARTWORK", 0.45, 0.44, 0.42, 1)
    f.dot:SetSize(7, 7)
    f.dot:SetPoint("TOPLEFT", 8, -8)
    f.title = K.label(f, "GameFontNormal", "Farming Session")
    f.title:SetTextColor(C.head[1], C.head[2], C.head[3])
    f.title:SetPoint("TOPLEFT", 20, -5)
    local close = K.button(f, "X", 16, 16, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -3, -3)
    f.fold = K.button(f, "-", 16, 16, function()
        ns.db.opts.trackerCollapsed = not ns.db.opts.trackerCollapsed or nil
        ns.RefreshTrackerWindow(true)
    end)
    f.fold:SetPoint("RIGHT", close, "LEFT", -2, 0)
    f.state = K.label(f, "GameFontHighlightSmall")
    f.state:SetPoint("RIGHT", f.fold, "LEFT", -6, 0)
    f.state:SetJustifyH("RIGHT")
    -- The folded strip's one line.
    f.head = K.label(f, "GameFontHighlightSmall")
    f.head:SetPoint("LEFT", f.dot, "RIGHT", 6, 0)
    f.head:SetPoint("RIGHT", f.fold, "LEFT", -4, 0)
    f.head:SetWordWrap(false)

    f.sessionOnly = {}
    local function session(w)
        f.sessionOnly[#f.sessionOnly + 1] = w
        return w
    end

    f.startBig = K.button(f, "Start session", W - 8, ROW_H, function() ns.TrackerToggle() end)
    f.startBig:SetPoint("TOPLEFT", 4, -(TITLE_H + 6))
    f.startBig:SetPrimary(true)

    -- What matters while you farm: real money apart from the estimate.
    f.cells = {}
    local cellW = floor((W - 8) / 4)
    -- Short captions, each clipped to its own cell, so they can't run into
    -- the next one at a large UI scale. The tooltip on each says it in full.
    local CAPS = {
        { "Time", "How long this session has been recording." },
        { "Kills", "Mobs you've killed this session." },
        { "Earned", "Money actually earned: coin looted plus vendor and auction sales." },
        { "Loot, est.", "Estimated value of the items you've looted (not sold yet)." },
    }
    for i, cap in ipairs(CAPS) do
        local cell = session(CreateFrame("Frame", nil, f))
        cell:SetSize(cellW, STATS_H - 4)
        cell:SetPoint("TOPLEFT", 4 + (i - 1) * cellW, -(TITLE_H + 3))
        cell.caption = K.label(cell, "GameFontDisableSmall", cap[1])
        cell.caption:SetPoint("TOPLEFT", 4, -2)
        cell.caption:SetWidth(cellW - 6)
        cell.caption:SetWordWrap(false)
        cell.caption:SetJustifyH("LEFT")
        cell:EnableMouse(true)
        cell:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(cap[1], 1, 0.82, 0)
            GameTooltip:AddLine(cap[2], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cell.value = K.label(cell, "GameFontHighlight")
        cell.value:SetPoint("TOPLEFT", 4, -15)
        cell.value:SetWidth(cellW - 6)
        cell.value:SetWordWrap(false)
        f.cells[i] = cell
    end
    local rule = session(CreateFrame("Frame", nil, f))
    rule:SetPoint("TOPLEFT", 4, -(TITLE_H + STATS_H))
    rule:SetPoint("TOPRIGHT", -4, -(TITLE_H + STATS_H))
    rule:SetHeight(1)
    K.tex(rule, "BORDER", C.edge[1], C.edge[2], C.edge[3], 0.6):SetAllPoints()

    local y = -(TITLE_H + STATS_H + 4)
    f.start = session(K.button(f, "Stop", 58, 18, function() ns.TrackerToggle() end))
    f.start:SetPoint("TOPLEFT", 4, y)
    f.save = session(K.button(f, "Save trip", 62, 18, function() ns.StopSession() end))
    f.save:SetPoint("LEFT", f.start, "RIGHT", 3, 0)
    f.reset = session(K.button(f, "Reset", 46, 18, function() ns.TrackerReset() end))
    f.reset:SetPoint("LEFT", f.save, "RIGHT", 3, 0)
    f.rate = session(K.label(f, "GameFontHighlightSmall"))
    -- Fills the gap right of Reset and no further, so it shortens instead
    -- of sliding under the buttons.
    f.rate:SetPoint("TOPRIGHT", -6, y - 3)
    f.rate:SetPoint("LEFT", f.reset, "RIGHT", 6, 0)
    f.rate:SetJustifyH("RIGHT")
    f.rate:SetWordWrap(false)

    f.tabs = {}
    local x = 4
    for _, t in ipairs({ { "kills", "Kills" }, { "loot", "Loot" }, { "money", "Money" } }) do
        local key = t[1]
        local b = session(K.button(f, t[2], 56, 18, function()
            view.tab = key
            ns.RefreshTrackerWindow()
        end))
        b:SetPoint("TOPLEFT", x, y - ROW_H)
        f.tabs[key] = b
        x = x + 59
    end
    f.sort = K.button(f, "Sort: Recent", 84, 18, function()
        view.sort = SORT_NEXT[view.sort] or "recent"
        ns.RefreshTrackerWindow()
    end)
    f.sort:SetPoint("TOPRIGHT", -4, y - ROW_H)

    f.list = K.createList(f)
    f.list.compact = true
    f.list.rightW = 64
    f.list.right2W = 74

    -- The clock and the numbers tick every second.
    local since = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since >= 1 then
            since = 0
            local s = tickSummary()
            f.head:SetText(headline(s))
            fillStats(s)
        end
    end)
    f:SetScript("OnShow", function()
        ns.db.opts.trackerShown = true
        ns.Guard("tracker-window", ns.RefreshTrackerWindow)()
    end)
    f:SetScript("OnHide", function()
        ns.db.opts.trackerShown = false
    end)
    f:Hide()
    return f
end

function ns.ShowTrackerWindow()
    if not ns.UIKit then
        return
    end
    if not win then
        win = create()
    end
    win:Show()
end

function ns.ToggleTrackerWindow()
    if win and win:IsShown() then
        win:Hide()
    else
        ns.ShowTrackerWindow()
    end
    if ns.RefreshUI then
        ns.RefreshUI(true)
    end
end

function ns.TrackerWindowShown()
    return win and win:IsShown() and true or false
end

ns.TrackerUI = { view = view }

----------------------------------------------------------------------
-- Keeping it up to date
----------------------------------------------------------------------

ns.Listen("READY", function()
    -- Open again if it was open last time, or if a trip is running.
    if ns.db.opts.trackerShown or (ns.TrackerRunning and ns.TrackerRunning()) then
        ns.Guard("tracker-window", ns.ShowTrackerWindow)()
    end
end)

local wasRunning = false
ns.Listen("SESSION", function()
    local running = ns.TrackerRunning and ns.TrackerRunning()
    -- Starting the tracker brings the window up.
    if running and not wasRunning and not ns.TrackerWindowShown() then
        ns.Guard("tracker-window", ns.ShowTrackerWindow)()
    end
    wasRunning = running
    ns.Later("tracker-window", 0.2, function() ns.RefreshTrackerWindow(true) end)
end)

for _, msg in ipairs({ "PRICES_UPDATED", "ITEMS_UPDATED" }) do
    ns.Listen(msg, function()
        ns.Later("tracker-window", 0.5, function() ns.RefreshTrackerWindow(true) end)
    end)
end

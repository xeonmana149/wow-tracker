-- Forever Gold - the Kills & Loot window
--
-- The kill and loot tracker in a small window of its own, apart from the
-- main Forever Gold window: drag it anywhere by its top bar, resize it from
-- the corner, fold it down to one line with "-". It remembers where you put
-- it and whether it was open.
--
--   Kills  - this trip's kill streak, every mob you've killed (click one for
--            what it's worth, its drops and your all-time numbers), and
--            everything you've gathered, node by node
--   Loot   - everything looted, most valuable first
--   Money  - real money in and out: auction sales, vendor sales, coin, repairs
--
-- All the counting happens in Tracker.lua; this file only shows it.

local _, ns = ...
local floor, max, min = math.floor, math.max, math.min

local W, H = 310, 440
local MIN_H, MAX_H = 200, 900
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

local function zoneText(zones)
    if #zones == 0 then
        return ""
    end
    return zones[1].name .. (#zones > 1 and ("  +" .. (#zones - 1) .. " more") or "")
end

local function mobDetail(m)
    local G = kit().GREY
    local lines = {}
    lines[#lines + 1] = "Worth per kill: " .. ns.Money(m.perKill) .. G .. "   (" .. ns.Money(m.value) .. " in all)|r"
    if m.coin > 0 then
        lines[#lines + 1] = "Coin: " .. ns.Money(m.coin)
    end
    if m.good > 0 then
        local every = max(1, floor(m.k / m.good + 0.5))
        lines[#lines + 1] = "Green or better: " .. m.good .. G .. (every == 1 and " (about every kill)|r" or (" (about 1 in " .. every .. " kills)|r"))
    end
    lines[#lines + 1] = "Kills since your last green or better: " .. m.since
    if #m.items > 0 then
        lines[#lines + 1] = "Drops: " .. topDrops(m.items, 4) .. (#m.items > 4 and (" and " .. (#m.items - 4) .. " more") or "")
    end
    if #m.zones > 1 then
        local z = {}
        for i, e in ipairs(m.zones) do
            z[i] = e.name .. " " .. e.n
        end
        lines[#lines + 1] = "Where: " .. table.concat(z, ", ")
    end
    local life = m.life
    lines[#lines + 1] = G .. "All time: " .. plural(life.k or 0, "kill") .. ", " .. ns.Money(life.v or 0) .. " looted"
        .. ((life.good or 0) > 0 and (", " .. life.good .. " green or better") or "") .. "|r"
    return table.concat(lines, "\n")
end

local function buildKills()
    local K = kit()
    local rows = {}
    local s = ns.TrackerSummary and ns.TrackerSummary()
    if not s then
        K.Tx(rows, "Kills & Loot",
            "Press Start, then go farm. Every kill, everything you loot or gather, and every copper in or out is counted, with your gold per hour at the top. Pause for breaks; logging out pauses it too. Save trip keeps a record on the main window under Make > Farm.")
        return rows
    end
    K.Hd(rows, "This trip", plural(s.kills, "kill"))
    rows[#rows + 1] = { icon = SKULL, title = "Kill streak", sub = "best " .. s.best .. ", ends when you die",
        r1 = "x" .. s.streak, r2 = s.secs > 60 and (floor(s.kills / s.secs * 3600 + 0.5) .. " kills/hr") or "", onClick = false }
    for _, m in ipairs(ns.TrackerMobs(view.sort)) do
        local name = m.name
        rows[#rows + 1] = { icon = m.items[1] and ns.Icon(m.items[1].id) or SKULL,
            title = (view.open[name] and "|cffffd100" or "") .. name .. "|r", sub = zoneText(m.zones),
            r1 = "x" .. m.k, r2 = ns.Money(m.perKill) .. " a kill",
            tipTitle = name, tip = function() return { mobDetail(m), " ", K.GREY .. "Click to show or hide the details here.|r" } end,
            onClick = function()
                view.open[name] = not view.open[name] or nil
                ns.RefreshTrackerWindow(true)
            end }
        if view.open[name] then
            K.Tx(rows, nil, mobDetail(m))
        end
    end
    local nodes = ns.TrackerNodes()
    if #nodes > 0 then
        K.Hd(rows, "Gathering", plural(s.gathers, "gather"))
        for _, e in ipairs(nodes) do
            rows[#rows + 1] = { icon = e.items[1] and ns.Icon(e.items[1].id) or PICK, title = e.name,
                sub = (ns.TRACK_CAT_LABEL[e.cat] or e.cat or "") .. (e.items[1] and (": " .. topDrops(e.items, 2)) or ""),
                r1 = "x" .. e.n, r2 = ns.Money(e.value),
                tipTitle = e.name,
                tip = function()
                    local lines = {}
                    for _, it in ipairs(e.items) do
                        lines[#lines + 1] = { it.n .. " x " .. ns.ItemName(it.id), ns.Money(it.v) }
                    end
                    lines[#lines + 1] = " "
                    lines[#lines + 1] = K.GREY .. "All time: gathered " .. (e.life.n or 0) .. " times, " .. ns.Money(e.life.v or 0) .. "|r"
                    return lines
                end, onClick = false }
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
    K.Tx(rows, nil, K.GREY .. "Valued at what each would fetch today, auction or vendor, whichever pays more.|r")
    if s.coin > 0 then
        rows[#rows + 1] = { icon = K.COIN, title = "Coin", sub = "From mobs and chests", r1 = ns.Money(s.coin), r2 = "", onClick = false }
    end
    for _, it in ipairs(s.items) do
        rows[#rows + 1] = { id = it.id, title = it.n .. " x " .. ns.ItemName(it.id), sub = ns.TRACK_CAT_LABEL[it.cat] or "",
            r1 = ns.Money(it.v), r2 = it.n > 1 and (ns.Money(it.v / it.n) .. " each") or "" }
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
    K.Hd(rows, "Real money", ns.Profit(s.net))
    K.Tx(rows, nil, K.GREY .. "Copper that actually came in or went out while the tracker ran.|r")
    local inc, out = s.inc or {}, s.out or {}
    local function money(title, sub, v, sign)
        if (v or 0) > 0 then
            rows[#rows + 1] = { icon = K.COIN, title = title, sub = sub,
                r1 = sign < 0 and ("|cffff7070-" .. ns.Money(v) .. "|r") or ns.Money(v), r2 = "", onClick = false }
        end
    end
    money("Coin looted", "From mobs and chests", s.coin, 1)
    money("Auction sales", "From your mailbox", inc.ah, 1)
    money("Vendor sales", "Sold to shopkeepers", inc.vendor, 1)
    money("Other mail", "Not an auction sale", inc.mail, 1)
    money("Quests and other", "Anything else that came in", inc.other, 1)
    money("Auction house", "Purchases and deposits", out.ah, -1)
    money("Vendors", "Purchases and repairs", out.vendor, -1)
    money("Elsewhere", "Training, flights, postage", out.other, -1)
    if s.cashIn == 0 and s.cashOut == 0 then
        K.Tx(rows, nil, "No money has changed hands yet.")
    end
    if #s.sold > 0 then
        K.Hd(rows, "Auction sales collected", ns.Money(inc.ah or 0))
        for i = 1, min(15, #s.sold) do
            local e = s.sold[i]
            local id = ns.FindItemByName and ns.FindItemByName(e.name)
            rows[#rows + 1] = { id = id, icon = not id and K.COIN or nil, title = e.q .. " x " .. (id and ns.ItemText(id) or e.name),
                sub = "After the cut", r1 = ns.Money(e.v), r2 = "", onClick = false }
        end
    end
    return rows
end

local BUILD = { kills = buildKills, loot = buildLoot, money = buildMoney }

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------

local function headline()
    local s = ns.TrackerSummary and ns.TrackerSummary()
    if not s then
        return kit().GREY .. "Not started|r"
    end
    return ns.Duration(max(1, s.secs)) .. "   " .. ns.Money(s.made)
        .. (s.perHour and ("   |cffffd100" .. ns.Money(s.perHour) .. "/hr|r") or "")
end

local function savePlace()
    if not win then
        return
    end
    local point, _, relPoint, x, y = win:GetPoint()
    ns.db.opts.trackerPos = { point or "CENTER", relPoint or "CENTER", floor((x or 0) + 0.5), floor((y or 0) + 0.5) }
    ns.db.opts.trackerH = floor(win:GetHeight() + 0.5)
end

local function layout()
    local collapsed = ns.db.opts.trackerCollapsed
    local h = collapsed and 50 or max(MIN_H, min(MAX_H, ns.db.opts.trackerH or H))
    win:SetHeight(h)
    for _, w in ipairs(win.body) do
        w:SetShown(not collapsed)
    end
    win.list.clip:SetShown(not collapsed)
    win.fold:SetLabel(collapsed and "+" or "-")
    win.list.viewW = W - 16
    win.list.viewH = h - 104 - 10
end

function ns.RefreshTrackerWindow(keepScroll)
    if not win or not win:IsShown() then
        return
    end
    local running = ns.TrackerRunning and ns.TrackerRunning()
    local t = ns.Tracker and ns.Tracker()
    win.dot:SetColorTexture(running and 0.25 or 0.5, running and 0.9 or 0.5, running and 0.3 or 0.5, 1)
    win.head:SetText(headline())
    win.start:SetLabel(running and "Pause" or (t and "Resume" or "Start"))
    win.start:SetOn(running)
    win.reset:SetDisabled(not t)
    win.save:SetDisabled(not t)
    win.sort:SetLabel(SORT_LABEL[view.sort])
    win.sort:SetShown(view.tab == "kills" and not ns.db.opts.trackerCollapsed)
    for key, b in pairs(win.tabs) do
        b:SetOn(key == view.tab)
    end
    if ns.db.opts.trackerCollapsed then
        return
    end
    local ok, rows = pcall(BUILD[view.tab])
    if not ok then
        ns.Err("tracker-" .. view.tab, rows)
        rows = { { type = "text", title = "Something went wrong here", text = "Type /gold debug for the details." } }
    end
    win.list:SetRows(rows, keepScroll)
end

local function create()
    local K = kit()
    local f = CreateFrame("Frame", "ForeverGoldTracker", UIParent)
    f:SetSize(W, H)
    local pos = ns.db.opts.trackerPos
    if type(pos) == "table" then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("RIGHT", UIParent, "RIGHT", -80, 40)
    end
    f:SetFrameStrata("MEDIUM")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    if f.SetResizable then
        f:SetResizable(true)
    end
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePlace()
    end)
    K.skin(f, 0.05, 0.05, 0.065, 0.92)

    local bar = K.tex(f, "BORDER", 0.20, 0.15, 0.05, 0.9)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(24)
    f.dot = K.tex(f, "ARTWORK", 0.5, 0.5, 0.5, 1)
    f.dot:SetSize(8, 8)
    f.dot:SetPoint("TOPLEFT", 10, -9)
    local title = K.label(f, "GameFontNormal", "Kills & Loot")
    title:SetPoint("TOPLEFT", 24, -6)
    local close = K.button(f, "X", 20, 18, function()
        f:Hide()
    end)
    close:SetPoint("TOPRIGHT", -4, -4)
    f.fold = K.button(f, "-", 20, 18, function()
        ns.db.opts.trackerCollapsed = not ns.db.opts.trackerCollapsed or nil
        layout()
        ns.RefreshTrackerWindow()
    end)
    f.fold:SetPoint("RIGHT", close, "LEFT", -3, 0)

    f.head = K.label(f, "GameFontHighlight")
    f.head:SetPoint("TOPLEFT", 10, -31)
    f.head:SetWidth(W - 20)
    f.head:SetWordWrap(false)

    f.body = {}
    local function add(w)
        f.body[#f.body + 1] = w
        return w
    end
    f.start = add(K.button(f, "Start", 62, 20, function() ns.TrackerToggle() end))
    f.start:SetPoint("TOPLEFT", 8, -52)
    f.reset = add(K.button(f, "Reset", 52, 20, function() ns.TrackerReset() end))
    f.reset:SetPoint("LEFT", f.start, "RIGHT", 4, 0)
    f.save = add(K.button(f, "Save trip", 70, 20, function() ns.StopSession() end))
    f.save:SetPoint("LEFT", f.reset, "RIGHT", 4, 0)
    f.sort = add(K.button(f, "Sort: Recent", 92, 20, function()
        view.sort = SORT_NEXT[view.sort] or "recent"
        ns.RefreshTrackerWindow()
    end))
    f.sort:SetPoint("TOPRIGHT", -8, -52)

    f.tabs = {}
    local x = 8
    for _, t in ipairs({ { "kills", "Kills" }, { "loot", "Loot" }, { "money", "Money" } }) do
        local key = t[1]
        local b = add(K.button(f, t[2], 70, 20, function()
            view.tab = key
            ns.RefreshTrackerWindow()
        end))
        b:SetPoint("TOPLEFT", x, -78)
        f.tabs[key] = b
        x = x + 74
    end

    f.list = K.createList(f)
    f.list.rightW = 92
    f.list.clip:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -104)
    f.list.clip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 10)

    -- Resize from the bottom-right corner.
    local grip = add(CreateFrame("Button", nil, f))
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    local gt = K.tex(grip, "OVERLAY", 1, 0.82, 0, 0.35)
    gt:SetAllPoints()
    grip:SetScript("OnMouseDown", function()
        if f.StartSizing then
            f:StartSizing("BOTTOM")
        end
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        f:SetWidth(W)
        ns.db.opts.trackerH = max(MIN_H, min(MAX_H, floor(f:GetHeight() + 0.5)))
        savePlace()
        layout()
        ns.RefreshTrackerWindow(true)
    end)

    -- The clock and the gold-per-hour line tick every second.
    local since = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since >= 1 then
            since = 0
            f.head:SetText(headline())
        end
    end)
    f:SetScript("OnShow", function()
        ns.db.opts.trackerShown = true
        ns.Guard("tracker-window", function()
            layout()
            ns.RefreshTrackerWindow()
        end)()
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

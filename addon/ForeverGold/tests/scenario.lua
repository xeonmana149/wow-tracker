local M, ns = MOCK, NS
local out = M.realPrint
local fails = 0
local function check(cond, what)
    if cond then out("  ok   " .. what) else fails = fails + 1; out("  FAIL " .. what) end
end
local function strip(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function dumpRows(title, limit, list)
    out("--- " .. title .. " ---")
    list = list or (ForeverGoldFrame and NS.UI and ForeverGoldFrame.list)
    for i = 1, math.min(list.count, limit or 60) do
        local d = list.rows[i].d
        if d.type == "header" then
            out("  [" .. strip(d.text) .. "]  " .. strip(d.right))
        elseif d.type == "text" then
            out("  # " .. strip(d.title) .. ": " .. strip(d.text):sub(1, 90))
        elseif d.type == "chips" then
            local c = {}
            for _, x in ipairs(d.chips) do c[#c + 1] = ns.ItemName(x.id) .. " " .. strip(x.text) end
            out("      drops: " .. table.concat(c, "  "))
        else
            out("  - " .. strip(d.title) .. "  |  " .. strip(d.sub) .. "  =>  " .. strip(d.r1) .. " / " .. strip(d.r2))
        end
    end
end
-- hover + click every row, the way a curious player would
local function pokeRows(list)
    list = list or ForeverGoldFrame.list
    for i = 1, list.count do
        local r = list.rows[i]
        if not r.d.type then
            r._scripts.OnEnter(r)
            r._scripts.OnLeave(r)
        end
    end
end

out("== login")
M.fire("ADDON_LOADED", "ForeverGold")
M.fire("PLAYER_LOGIN")
M.advance(10)
check(ns.ready, "addon ready")
check(ns.realmKey == "6801-Horde", "price book key " .. tostring(ns.realmKey))
check(ns.Char().name == "Xeon Mana", "full name read: " .. tostring(ns.Char().name))
check(ns.Char().profs.Mining and ns.Char().profs.Mining.skill == 98, "professions read")
check(ns.Char().bags[2770] == 40, "bags read")
check(ForeverGoldMinimapButton ~= nil, "minimap button created")
check(ns.db.opts.fastScan == true and ns.db.opts.dealMin == 500, "new settings default to fast scan on, 5s deal minimum")
ns.db.opts.fastScan = false -- the older sections below exercise the slow scan; fast scan has its own section
check(ns.AuctionUI.UsingOurs(), "our auction window is the default")
ns.db.opts.ahBlizzard = true -- the older sections use the game's auction window; ours has its own section
-- what the price check on each suspicious piece of gear will find:
M.market[12345] = { { 0, 1 }, { 1500, 1 } } -- junk sword: a bid, then a 15s buyout
M.market[12346] = { { 300, 1 }, { 800, 1 } } -- boots: a real 3s buyout
M.market[12347] = { { 0, 1 } }              -- cloak: bids only

out("== window before any data")
SlashCmdList["FOREVERGOLD"]("")
check(ForeverGoldFrame and ForeverGoldFrame:IsShown(), "window opens")
for _, key in ipairs({ "today", "craft", "farm", "bags", "deals", "routes", "tips" }) do
    ns.ShowTab(key)
    pokeRows()
end
ns.ShowTab("today")
dumpRows("Today (no data)", 12)

out("== profession window")
M.openProf = "Blacksmithing"
M.fire("TRADE_SKILL_SHOW")
M.advance(2)
local n = 0
for _ in pairs(ns.Char().recipes.Blacksmithing or {}) do n = n + 1 end
check(n == 8, "learned recipes (8 learned, 1 unlearned skipped): " .. n)
check(#ns.Char().recipes.Blacksmithing[2659].r == 2, "optional reagent slot ignored")
check(ns.Char().recipes.Blacksmithing[2659].y == 2, "bronze yields 2")

out("== auction house scan")
M.fire("AUCTION_HOUSE_SHOW")
M.advance(1.6)
check(ns.scan.active, "auto-scan started")
M.advance(2.5)
check(not ns.scan.active, "scan finished")
check(M.queries == 1 and not M.replicateCalls, "very first scan is the slow, trusted kind (nothing to check a fast one against)")
local R = ns.R()
check(R.lastScan ~= nil and R.lastCount == 21, "21 distinct items recorded: " .. tostring(R.lastCount))
check(#ns.VendorFlips() == 0, "right after a slow scan no gear 'deal' is shown: none is confirmed as a buyout yet")
check(#ns.PendingDeals() == 3, "but the 3 candidates are waiting to be checked: " .. #ns.PendingDeals())
M.advance(20)
check(ns.AHPrice(2853) == 280, "two variants of an item collapse to the lower price")
local _, q = ns.AHPrice(2853)
check(q == 3, "and their quantities add up: " .. tostring(q))
check(ForeverGoldAuctionStrip ~= nil, "auction strip created")
M.advance(30)
check(ns.Char().auctions and #ns.Char().auctions == 1, "owned auctions read")

out("== advice")
local craft = ns.CraftList()
out("  craft groups: good=" .. #craft.good .. " untapped=" .. #craft.untapped .. " bad=" .. #craft.bad .. " unknown=" .. #craft.unknown .. " bound=" .. #craft.bound)
local byName = {}
for _, g in ipairs({ "good", "untapped", "bad", "unknown", "bound" }) do
    for _, e in ipairs(craft[g]) do byName[e.rec.name] = { g = g, e = e } end
end
-- Smelt Copper: ore 40c -> bar 90c*0.95 = 85.5 => +45.5
check(byName["Smelt Copper"].g == "good" and math.abs(byName["Smelt Copper"].e.profit - 45.5) < 0.01, "Smelt Copper profit = 45.5c")
-- Bronze: (copper bar min(90, craft 40)=40 + tin bar min(260, craft 210)=210)/2 = 125; sells 420*.95=399 => +274
check(math.abs(byName["Smelt Bronze"].e.cost - 125) < 0.01, "Bronze cost uses your own smelting: " .. tostring(byName["Smelt Bronze"].e.cost))
check(math.abs(byName["Smelt Bronze"].e.profit - 274) < 0.01, "Bronze profit = 274c")
-- Rough Sharpening Stone: stone 12c -> sells 8c*.95 = 7.6 => loss
check(byName["Rough Sharpening Stone"].g == "bad", "Sharpening stone flagged as a loss")
-- Copper Rod: bar 40 (crafted) + flux: vendor 100 (learned later) vs AH 300 -> static vendor 100
check(byName["Copper Rod"].g == "untapped" and math.abs(byName["Copper Rod"].e.cost - 140) < 0.01, "Copper Rod: nobody selling, cost 140c (vendor flux): " .. tostring(byName["Copper Rod"].e.cost))
check(byName["Gemmed Copper Boots"].g == "bound", "bind-on-pickup craft excluded")
check(byName["Smelt Copper"].e.canMake == 40, "can make 40 copper bars from bags")

local bag = ns.BagAdvice()
out("  bag advice: ah=" .. #bag.ah .. " vendor=" .. #bag.vendor .. " unlisted=" .. #bag.unlisted .. " undercut=" .. #bag.undercut)
check(#bag.undercut == 1, "undercut auction detected (listed 120c each, lowest 90c)")
local vendorIds = {}
for _, b in ipairs(bag.vendor) do vendorIds[b.id] = true end
check(vendorIds[4865] and not vendorIds[6948], "grey junk -> vendor; hearthstone never suggested")

local flips = ns.VendorFlips()
check(ns.VerifyPending() == 0, "every candidate has been checked")
check(#flips == 1 and flips[1].id == 12346 and flips[1].profit == 600, "the one real flip survives: boots, 3s buyout -> vendor pays 9s")
check(ns.AHPrice(12345) == 1500 and ns.IsBuyout(12345), "junk sword: the 4s was a bid; its real buyout is 15s, so it is no deal")
check(ns.R().prices[12347].b == false and not ns.IsBuyout(12347), "bid-only cloak is marked bid-only and never offered as a deal")
ns.db.opts.dealMin = 10000
ns.Fire("PLAYER_CHANGED")
check(#ns.VendorFlips() == 0, "raising the minimum profit to 1g hides the 6s flip")
ns.db.opts.dealMin = 500
ns.Fire("PLAYER_CHANGED")

out("== vendor visit")
M.fire("MERCHANT_SHOW")
M.advance(2)
check(ns.db.vendor[5772] and ns.db.vendor[5772].lim == true, "limited-stock pattern recorded")
local deals = ns.VendorDeals()
check(#deals == 1 and deals[1].id == 5772, "vendor->auction deal: pattern 5s at vendor / 40s at auction (flux's 1s85c is under the 5s minimum)")
check(select(1, ns.VendorBuy(2880)) == 100, "weak flux vendor price learned")

out("== tabs with data")
for _, key in ipairs({ "today", "craft", "farm", "bags", "deals", "routes", "tips" }) do
    ns.ShowTab(key)
    pokeRows()
end
ns.ShowTab("today"); dumpRows("To do", 30)
do
    local F = ForeverGoldFrame
    local tabs = {}
    for _, t in ipairs({ "todo", "sell", "buy", "make" }) do tabs[#tabs + 1] = t end
    local first = 0
    for i = 1, F.list.count do
        if strip(F.list.rows[i].d.title or ""):match("^1%.  ") then first = first + 1 end
    end
    check(first == 1, "To do numbers its list, best first")
    -- the Make switch
    ns.ShowTab("make")
    F.toolbar.buttons[3]._scripts.OnClick(F.toolbar.buttons[3])
    check(ns.UI.makeMode == "routes" and F.plot:IsShown(), "Make > Routes shows the map")
    F.toolbar.buttons[1]._scripts.OnClick(F.toolbar.buttons[1])
    check(ns.UI.makeMode == "craft" and not F.plot:IsShown(), "Make > Craft hides it")
    -- the details pane
    local function paneText()
        local t = { strip(F.pane.title:GetText() or "") }
        for _, f in ipairs(F.pane.fs) do
            if f:IsShown() then t[#t + 1] = strip(f:GetText() or "") end
        end
        return table.concat(t, " | ")
    end
    ns.ShowTab("todo")
    local firstRow
    for i = 1, F.list.count do
        if not F.list.rows[i].d.type then firstRow = firstRow or F.list.rows[i].d end
    end
    check(F.pane:IsShown() and F.list.selected == firstRow, "To do picks its first row for the pane")
    check(F.pane.primary:IsShown() and F.pane.primary.text:GetText() ~= "", "the pane has a main action: "
        .. tostring(F.pane.primary.text:GetText()))
    local chars = 0
    ns.ShowTab("chars")
    check(F.list.rows[2].d.type == "graph" and F.list.rows[2].graph ~= nil, "Characters opens on the gold graph")
    do
        local saved = ns.db.goldLog
        local now = time()
        ns.db.goldLog = { { now - 5 * 86400, 20000 }, { now - 3 * 86400, 50000 }, { now - 86400, 45000 } }
        ns.RefreshUI()
        local g = F.list.rows[2].graph
        check(g.drawn and #g.drawn == 4, "the graph draws the history up to now: " .. tostring(g.drawn and #g.drawn))
        -- hovering: the readout is the balance at the mouse's own moment
        local function hoverAt(frac)
            M.cursorX = g:GetLeft() + 54 + g.scale.pw * frac
            g.hovering, g.lastX = true, nil
            g._scripts.OnUpdate(g)
            return strip((GameTooltip._lines or {})[1] or "")
        end
        check(hoverAt(0.5) == strip(ns.Money(50000)), "halfway along (2.5 days ago) shows the 3-days-ago balance: " .. hoverAt(0.5))
        check(hoverAt(0.1) == strip(ns.Money(20000)), "near the start shows the first balance: " .. hoverAt(0.1))
        check(g.cross:IsShown() and g.dot:IsShown(), "with a crosshair at the mouse")
        g._scripts.OnLeave(g)
        M.cursorX = nil
        local pts, change = ns.GoldHistory(7 * 86400)
        check(change == ns.TotalGold() - 20000, "the week's change is now minus where it started")
        ns.db.goldLog = saved
        ns.RefreshUI()
    end
    for i = 1, F.list.count do
        local d = F.list.rows[i].d
        if d.key and d.key:find("^char:") then
            chars = chars + 1
            check(strip(d.sub):find("Mining 98"), "characters show their professions directly: " .. strip(d.sub))
        end
    end
    check(chars >= 1, "one row per character")
    do
        -- "Each character" swaps the total for one graph per character.
        local eachBtn
        for _, b in ipairs(F.toolbar.buttons) do
            if b:IsShown() and b.text:GetText() == "Each character" then eachBtn = b end
        end
        check(eachBtn ~= nil, "the Characters toolbar has an Each character button")
        eachBtn:GetScript("OnClick")(eachBtn, "LeftButton")
        local graphs, n = 0, 0
        for _ in pairs(ns.db.chars) do n = n + 1 end
        for i = 1, F.list.count do
            if F.list.rows[i].d.type == "graph" then graphs = graphs + 1 end
        end
        check(graphs == n, "one graph per character: " .. graphs .. " for " .. n)
        ns.LogGold()
        check(ns.Char().goldLog and #ns.Char().goldLog >= 1, "the logged-in character's own gold is recorded")
        local pts = ns.GoldHistory(7 * 86400, ns.Char())
        check(#pts >= 1 and pts[#pts][2] == (ns.Char().money or 0), "a character's graph ends at its own gold")
        for _, b in ipairs(F.toolbar.buttons) do
            if b:IsShown() and b.text:GetText() == "All characters" then b:GetScript("OnClick")(b, "LeftButton") end
        end
        check(F.list.rows[2].d.type == "graph" and F.list.rows[2].d.height == 170, "All characters goes back to the one big total graph")
    end
    ns.ShowTab("sell")
    local target
    for i = 1, F.list.count do
        local r = F.list.rows[i]
        if r.d.id == 2840 and not r.d.type then target = r end
    end
    target._scripts.OnClick(target)
    out("  pane: " .. paneText())
    check(F.list.selected.id == 2840 and paneText():find("Est. after the cut") and paneText():find("Auction house cut"),
        "clicking a Sell row shows its sums in the pane")
    check(strip(F.pane.note:GetText()):find("not a guaranteed sale"), "and says they're estimates")
    ns.RefreshUI(true)
    check(F.list.selected.id == 2840, "the pick survives a refresh")
    local h = F:GetHeight()
    check(h >= 360 and h <= 640, "the window fits its content: " .. h)
    F.settingsButton._scripts.OnClick(F.settingsButton)
    check(not F.pane:IsShown(), "settings use the whole width")
    check(ns.UI.tab == "settings" and strip(F.list.rows[1].d.text) == "Selling", "Settings button opens settings, selling first")
    F.settingsButton._scripts.OnClick(F.settingsButton)
    check(ns.UI.tab == "todo", "and closes back to To do")
end
ns.ShowTab("craft"); dumpRows("Craft", 30)
ns.ShowTab("bags"); dumpRows("Bags", 30)
ns.ShowTab("deals"); dumpRows("Deals", 30)
ns.ShowTab("farm"); dumpRows("Farm", 14)

-- tooltip of one craft row
ns.ShowTab("craft")
do
    local list = ForeverGoldFrame.list
    for i = 1, list.count do
        local r = list.rows[i]
        if not r.d.type and strip(r.d.title) == "Bronze Bar" then
            r._scripts.OnEnter(r)
            out("--- tooltip: Bronze Bar ---")
            for _, l in ipairs(GameTooltip._lines) do out("    " .. strip(l)) end
        end
    end
end
-- click a row with the AH open -> searches
do
    local list = ForeverGoldFrame.list
    for i = 1, list.count do
        local r = list.rows[i]
        if not r.d.type and r.d.id == 2841 then r._scripts.OnClick(r) end
    end
    check(M.lastSearch == "Bronze Bar", "clicking a row searches the auction house")
end

out("== item tooltip hook")
GameTooltip._lines = {}
M.tooltipHook(GameTooltip, { id = 2841 })
for _, l in ipairs(GameTooltip._lines) do out("    " .. strip(l)) end
check(#GameTooltip._lines >= 5 and strip(GameTooltip._lines[1]):find("^Vendor") and strip(GameTooltip._lines[2]):find("^Auction")
    and strip(GameTooltip._lines[3]):find("Last scanned"),
    "tooltip adds vendor price, then auction price + when it was scanned + craft cost + profit")
local hide = M.linePreCalls and M.linePreCalls[11]
check(hide and hide(GameTooltip, { type = 11, price = 10 }) == true and hide({}, { type = 11 }) == false,
    "Blizzard's Sell Price line is hidden on GameTooltip only")
GameTooltip._lines = {}
M.tooltipHook(GameTooltip, { id = 2840, lines = { { type = 11, price = 200 } } })
check(strip(GameTooltip._lines[2] or ""):find("stack of 20"), "hovering a stack also shows the stack's vendor value: " .. strip(GameTooltip._lines[2] or ""))
ns.db.opts.tooltip = false
check(hide(GameTooltip, { type = 11 }) == false, "Sell Price line stays when Forever Gold tooltips are off")
ns.db.opts.tooltip = true

out("== second scan: sold-out handling")
M.fire("AUCTION_HOUSE_CLOSED")
table.remove(M.auctions, 13) -- deviate fish sells out
M.advance(3600)
M.fire("AUCTION_HOUSE_SHOW")
M.advance(40)
check(ns.AHPrice(6522) == nil and ns.LastPrice(6522) == 350, "sold-out item: no live price, last price kept")
check(M.queries == 2, "auto-scan ran again after an hour")
M.fire("AUCTION_HOUSE_CLOSED")
M.fire("AUCTION_HOUSE_SHOW")
M.advance(40)
check(M.queries == 2, "no rescan when prices are fresh")

out("== sell: the pricing rules on their own")
do
    local function D(listings, info)
        local ls = {}
        for i, l in ipairs(listings) do ls[i] = { p = l[1], q = l[2], mine = l[3] } end
        info.step = info.step or 1
        return ns.DecidePrice(ls, info)
    end
    local d = D({ { 100, 10 }, { 105, 5 } }, { commodity = true, floor = 50 })
    check(d.ok and d.price == 99 and d.reason == "undercut", "1c under the cheapest: " .. tostring(d.price))
    d = D({ { 40, 1 }, { 100, 50 }, { 105, 20 } }, { commodity = true, floor = 50 })
    check(d.ok and d.price == 99 and #d.lowballs == 1, "a single lowball is ignored, price follows the next listing")
    d = D({ { 40, 30 }, { 100, 50 } }, { commodity = true, floor = 50 })
    check(not d.ok and d.why == "floor" and d.price == 39, "a big cheap wall is real competition; under the floor -> refuse")
    d = D({ { 40, 30 }, { 100, 50 } }, { commodity = true, floor = 30 })
    check(d.ok and d.price == 39, "same wall with a lower floor -> undercut it")
    d = D({ { 90, 5, true }, { 100, 10 } }, { commodity = true, floor = 50 })
    check(d.ok and d.price == 90 and d.reason == "match-self", "your own cheapest listing is matched, not undercut")
    d = D({ { 100, 10 }, { 120, 5, true } }, { commodity = true, floor = 50 })
    check(d.ok and d.price == 99 and d.reason == "undercut", "your dearer listing doesn't stop an undercut of others")
    d = D({}, { commodity = true, floor = 50, usual = 80, usualDays = 3 })
    check(d.ok and d.price == 80 and d.reason == "usual", "nobody selling -> usual price")
    d = D({}, { commodity = true, floor = 50, last = 70 })
    check(d.ok and d.price == 70 and d.reason == "last", "nobody selling, no history -> last price seen")
    d = D({}, { commodity = true, floor = 0 })
    check(not d.ok and d.why == "noref", "nothing to go on -> refuses to guess")
    d = D({}, { commodity = false, floor = 110, cost = 100 })
    check(d.ok and d.reason == "markup" and d.price == 157, "never sold, but you make it -> cost + 50% (" .. tostring(d.price) .. ")")
    d = D({ { 30, 2 }, { 100, 40 } }, { commodity = true, floor = 50, usual = 100, usualDays = 5 })
    check(d.ok and d.price == 99 and #d.lowballs == 1, "way under the usual price in tiny quantity -> lowball")
    d = D({ { 30, 1 } }, { commodity = true, floor = 50, usual = 100, usualDays = 5 })
    check(d.ok and d.price == 100 and d.reason == "usual", "the only listing is a lowball -> price at usual")
    d = D({ { 500, 1 }, { 2000, 1 }, { 2100, 1 } }, { commodity = false, floor = 300 })
    check(d.ok and d.price == 1999, "gear: one silly-cheap piece ignored")
    d = D({ { 300, 10 } }, { commodity = true, floor = 100, step = 100 })
    check(d.ok and d.price == 200, "silver-only pricing steps down a whole silver")
    d = D({ { 1, 10 } }, { commodity = true, floor = 0 })
    check(d.price == 1, "never posts at zero")
end

out("== sell: full flow")
M.fire("AUCTION_HOUSE_CLOSED")
M.posted = {}
ns.OpenSell(2840)
check(ns.SellJob() == nil, "Sell does nothing while the auction window is closed")
M.fire("AUCTION_HOUSE_SHOW"); M.advance(5)

-- Copper Bar: 2 lowballs at 30c, the real market at 90c, your own old listing at 1s20c
M.market[2840] = { { 30, 2 }, { 90, 150 }, { 95, 30 }, { 120, 5, true } }
ns.ShowTab("bags")
do
    local list, clicked = ForeverGoldFrame.list, false
    for i = 1, list.count do
        local r = list.rows[i]
        if r.d.btn and r.d.id == 2840 then
            check(r.btn:IsShown(), "Sell button shown on the row")
            r.btn._scripts.OnClick(r.btn)
            clicked = true
        end
    end
    check(clicked, "found the Copper Bar row with a Sell button")
end
local job = ns.SellJob()
check(job and job.state == "checking" and job.commodity and job.have == 8, "price check started for 8 Copper Bars")
M.advance(1)
job = ns.SellJob()
check(job.state == "ready" and job.decision.ok and job.decision.price == 89, "price = 89c (1c under 90c, lowball skipped): " .. tostring(job.decision.price))
check(job.floor == 45 and job.floorWhy == "cost", "floor = 45c from the cost of the ore: " .. tostring(job.floor))
check(job.qty == 8, "default quantity = what you have, up to one stack")
out("--- sell panel ---")
out("    " .. strip(ForeverGoldSellFrame.title:GetText()) .. "  /  " .. strip(ForeverGoldSellFrame.have:GetText()))
for line in (strip(ForeverGoldSellFrame.body:GetText()) .. "\n"):gmatch("(.-)\n") do if line ~= "" then out("    " .. line) end end
out("    " .. strip(ForeverGoldSellFrame.offer:GetText()))
for line in (strip(ForeverGoldSellFrame.totals:GetText()) .. "\n"):gmatch("(.-)\n") do out("    " .. line) end
local c = ForeverGoldSellFrame.controls
c.minus._scripts.OnClick(c.minus)
check(ns.SellJob().qty == 3, "minus lowers the quantity by 5")
c.all._scripts.OnClick(c.all)
c.duration._scripts.OnClick(c.duration)
check(ns.SellJob().qty == 8 and ns.SellJob().duration == 3 and ns.db.opts.sellDuration == 3, "All + duration buttons work")
check(#M.posted == 0, "nothing posted before pressing Post")
ForeverGoldSellFrame.post._scripts.OnClick(ForeverGoldSellFrame.post)
check(#M.posted == 1 and M.posted[1].kind == "commodity" and M.posted[1].qty == 8 and M.posted[1].price == 89 and M.posted[1].duration == 3, "Post sends 8 x 89c")
check(ns.SellJob().state == "posting", "waiting for the auction house")
M.advance(1)
check(ns.SellJob().state == "done" and ns.db.posts[1].id == 2840, "listed, and remembered")
out("    " .. strip(ForeverGoldSellFrame.body:GetText()))
ForeverGoldSellFrame.post._scripts.OnClick(ForeverGoldSellFrame.post)
check(#M.posted == 1, "pressing again after it's done posts nothing")
ForeverGoldSellFrame.close._scripts.OnClick(ForeverGoldSellFrame.close)
check(ns.SellJob() == nil and not ForeverGoldSellFrame:IsShown(), "panel closes")

-- Tin Bar: the market (2s) is below what the tin ore costs (2s10c) -> refuse
M.market[3576] = { { 200, 40 } }
ns.OpenSell(3576); M.advance(1)
job = ns.SellJob()
check(job.state == "ready" and not job.decision.ok and job.decision.why == "floor" and job.floor == 233, "below the floor (233c): refuses")
out("    " .. strip(ForeverGoldSellFrame.body:GetText()):gsub("\n\n", "\n    "))
ForeverGoldSellFrame.post._scripts.OnClick(ForeverGoldSellFrame.post)
ns.SellPost()
check(#M.posted == 1, "Post is dead when the price is under the floor")
ns.CloseSell()

-- Stale prices are re-checked instead of posted
M.market[2835] = { { 12, 500 } }
ns.OpenSell(2835); M.advance(1)
check(ns.SellJob().decision.price == 11, "Rough Stone priced at 11c")
M.advance(120)
local before = M.searches
ns.SellPost()
check(#M.posted == 1 and M.searches == before + 1 and ns.SellJob().state == "checking", "prices over 90s old are checked again, not posted")
M.advance(1)
ns.SellPost(); M.advance(1)
check(#M.posted == 2 and M.posted[2].price == 11 and M.posted[2].qty == 20, "second press posts one stack (20 of 23)")
ns.CloseSell()

-- The auction house asks "are you sure?"
M.market[2589] = { { 60, 800 } }
M.needConfirm = true
ns.OpenSell(2589); M.advance(1)
ns.SellPost()
M.fire("AUCTION_HOUSE_POST_WARNING"); M.advance(0.1)
check(ns.SellJob().state == "confirm" and M.popupHidden == "AUCTION_HOUSE_POST_WARNING", "confirmation requested; Blizzard's popup replaced by ours")
check(strip(ForeverGoldSellFrame.post.text:GetText()) == "Confirm", "button now says Confirm")
ns.SellPost(); M.advance(1)
check(M.posted[#M.posted].kind == "commodity-confirmed" and M.posted[#M.posted].price == 59 and ns.SellJob().state == "done", "confirmed and listed at 59c")
M.needConfirm = false
ns.CloseSell()

-- A piece of gear (not a commodity)
M.bags[#M.bags + 1] = { 2853, 1 }
M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
M.market[2853] = { { 280, 1 }, { 300, 2 } }
ns.OpenSell(2853); M.advance(1)
job = ns.SellJob()
check(not job.commodity and job.decision.ok and job.decision.price == 279 and job.qty == 1, "gear: 1 x 2s79c")
ns.SellPost(); M.advance(1)
check(M.posted[#M.posted].kind == "item" and M.posted[#M.posted].price == 279, "gear posted with a buyout and no bid")
ns.CloseSell()

-- The auction house never answers the price check
M.searchSilent = true
ns.OpenSell(2840); M.advance(11)
check(ns.SellJob().state == "error", "no answer -> says so instead of guessing")
check(strip(ForeverGoldSellFrame.post.text:GetText()) == "Check again", "button offers Check again")
M.searchSilent = false
ForeverGoldSellFrame.post._scripts.OnClick(ForeverGoldSellFrame.post); M.advance(1)
check(ns.SellJob().state == "ready", "Check again recovers")
-- An error from the auction house while posting
ns.SellPost()
M.fire("AUCTION_HOUSE_SHOW_ERROR", 3)
check(ns.SellJob().state == "error", "a refused post is reported")
M.advance(1)
-- Closing the auction window cancels everything
M.fire("AUCTION_HOUSE_CLOSED")
check(ns.SellJob() == nil, "closing the auction window closes the Sell panel")
M.fire("AUCTION_HOUSE_SHOW"); M.advance(5)
table.remove(M.bags) -- put the bags back how the later tests expect them
M.fire("BAG_UPDATE_DELAYED"); M.advance(1)

out("== post all")
do
    local d = ns.DecidePrice({ { p = 1000, q = 5 } }, { commodity = true, step = 1, floor = 0, undercutPct = 0.05 })
    check(d.ok and d.price == 950, "5% undercut: 1000 -> " .. tostring(d.price))
    local want = #ns.BagAdvice().ah
    local before = #M.posted
    ns.db.opts.postQty = "stack"
    ns.StartPostAll(); M.advance(1)
    local q = ns.PostQueue()
    check(q and #q.ids == want and q.i >= 1, "post all queues everything the Sell tab lists: " .. want)
    out("  panel: " .. strip(ForeverGoldSellFrame.have:GetText()) .. " | " .. strip(ForeverGoldSellFrame.post.text:GetText()))
    check(strip(ForeverGoldSellFrame.post.text:GetText()) == "Post, then next" and ForeverGoldSellFrame.skip:IsShown(),
        "the panel offers Post, then next, and Skip")
    local presses = 0
    while ns.PostQueue() and presses < 40 do
        local job = ns.SellJob()
        if job and job.state == "ready" and job.decision and job.decision.ok then
            ns.SellPost()
            presses = presses + 1
        elseif job and job.state == "confirm" then
            ns.SellPost()
        end
        M.advance(1)
    end
    check(ns.PostQueue() == nil and presses > 0, "post all finishes after " .. presses .. " presses")
    local posted = #M.posted - before
    check(posted == presses, "one listing per press: " .. posted)
    -- linen (35 in bags, stacks of 20) goes up as two listings, 20 then 15
    local linen = {}
    for i = before + 1, #M.posted do
        if M.posted[i].id == 2589 then linen[#linen + 1] = M.posted[i].qty end
    end
    check(table.concat(linen, ",") == "20,15", "a stack at a time: " .. table.concat(linen, ","))
    -- stopping part way
    ns.StartPostAll(); M.advance(1)
    ForeverGoldSellFrame.close._scripts.OnClick(ForeverGoldSellFrame.close)
    check(ns.PostQueue() == nil and ns.SellJob() == nil, "Stop ends post all")
    ns.db.opts.postQty = nil
end

out("== gathering + route")
local spots = { { 0.50, 0.50 }, { 0.40, 0.45 }, { 0.60, 0.40 }, { 0.45, 0.60 }, { 0.52, 0.48 }, { 0.47, 0.42 }, { 0.58, 0.55 } }
for i, s in ipairs(spots) do
    M.player.x, M.player.y = s[1], s[2]
    M.fire("UNIT_SPELLCAST_SENT", "player", i % 2 == 0 and "Tin Vein" or "Copper Vein", "cast", 2575)
    M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 2575)
    M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 2575) -- second swing at the same vein
end
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 2657) -- smelting must not count
M.fishing = true; M.player.x, M.player.y = 0.30, 0.30; M.fire("LOOT_READY"); M.advance(1); M.fishing = false
check(#ns.db.nodes[1413] == 8, "7 veins + 1 fishing spot recorded (repeat swings merged): " .. #ns.db.nodes[1413])
ns.ShowTab("routes"); pokeRows(); dumpRows("Routes", 8)
do
    local F = ForeverGoldFrame
    local P, plotter = F.plot, F.plotter
    local function msg() return strip(P.msg:GetText() or "") end
    local function markerFor(node)
        for i = 1, plotter.usedMarks do
            if plotter.marks[i].node == node then return plotter.marks[i] end
        end
    end
    local function check2(kind) for _, cb in ipairs(P.checks) do if cb.kind == kind then return cb end end end
    ns.UI.routeKinds.ore, ns.UI.routeKinds.herb, ns.UI.routeKinds.fish = true, true, false
    ns.RefreshUI(true)
    check(P:IsShown() and plotter.usedTiles - plotter.pieceTiles == 12 and P.artState == "ok", "the zone's own map is drawn under the spots: "
        .. tostring(plotter.usedTiles) .. " tiles")
    check(plotter.pieceTiles == 12, "explored areas (2 tiles) plus the rest of the zone revealed (10): " .. tostring(plotter.pieceTiles))
    ns.db.opts.revealMap = false
    ns.RefreshUI(true)
    check(plotter.pieceTiles == 2, "with reveal off, only what you've explored: " .. tostring(plotter.pieceTiles))
    ns.db.opts.revealMap = true
    ns.RefreshUI(true)
    check(F.list.rows[1].d.type == "header" and strip(F.list.rows[1].d.text) == "Kalimdor", "zones are grouped by continent")
    check(F.zoneSearch:IsShown(), "with a search box over the list")
    check(F.list.rows[2] and strip(F.list.rows[2].sub:GetText()) == "7 ore veins · 1 fishing spot · No herbs recorded",
        "zone row says what's there: " .. strip(F.list.rows[2] and F.list.rows[2].sub:GetText() or ""))
    check(strip(P.count:GetText()) == "7 matching spots" and msg() == "", "Include row counts matching spots: " .. strip(P.count:GetText()))
    check(strip(P.sum:GetText()):find("^7 stops") and P.start:IsShown() and not P.start.disabled and not P.finish:IsShown(),
        "it previews a loop with Start route before anything starts: " .. strip(P.sum:GetText()))
    check(strip(P.sum:GetText()):find("about [%d,]+ yards$"), "with a rough distance in yards")
    check(strip(P.sub:GetText()):find("^Suggested loop through your recorded gathering spots"), "and says it's only a suggestion")
    check(ns.route == nil, "previewing doesn't start a route")
    -- unticking ore leaves nothing: the map says so
    check2("ore"):Click()
    check(not check2("ore").checked and msg():find("match what's ticked") and msg():find("Ore"), "nothing ticked that's here: " .. msg())
    check(P.start.disabled, "and Start is off")
    check2("ore"):Click()
    -- leave a spot out, then start from another
    local nodes = ns.db.nodes[1413]
    local odd, startAt
    for _, n in ipairs(nodes) do
        if n.k == "ore" then
            if not odd then odd = n elseif not startAt then startAt = n end
        end
    end
    markerFor(odd):Click("LeftButton"); M.advance(1)
    check(odd.skip and strip(P.sum:GetText()):find("^6 stops") and strip(P.count:GetText()):find("1 left out"),
        "clicking a spot leaves it out: " .. strip(P.sum:GetText()) .. " / " .. strip(P.count:GetText()))
    markerFor(startAt):Click("RightButton"); M.advance(1)
    local plan = ns.UI.plan
    check(plan and plan.pts[plan.first] == startAt and markerFor(startAt).tag:GetText() == "Start", "right-click picks where to start")
    -- Save, then Start
    P.save:Click()
    check(ns.db.routes[1413] and ns.db.routes[1413].kinds.ore and ns.db.routes[1413].start, "Save route keeps what's ticked and the start")
    P.start:Click(); M.advance(1)
    check(ns.route and ns.route.n == 6 and ns.route.pts[ns.route.i] == startAt, "Start route follows the previewed loop")
    check(P.pause:IsShown() and P.skip:IsShown() and P.finish:IsShown() and not P.start:IsShown(),
        "running: Pause, Skip stop and End route replace Start")
    check(strip(P.sum:GetText()):find("^Stop 1 of 6"), "with progress: " .. strip(P.sum:GetText()))
    P.skip:Click(); M.advance(1)
    check(strip(P.sum:GetText()):find("^Stop 2 of 6"), "Skip stop moves on: " .. strip(P.sum:GetText()))
    P.pause:Click(); M.advance(1)
    M.update(0.2)
    check(ns.route.paused and strip(P.sum:GetText()):find("paused") and strip(ForeverGoldGuide.line1:GetText()) == "Route paused",
        "Pause holds your place and says so on the arrow")
    local held = ns.route.i
    M.player.x, M.player.y = ns.route.pts[held].x, ns.route.pts[held].y
    M.update(0.5)
    check(ns.route.i == held, "paused routes don't move on when you arrive")
    P.pause:Click(); M.advance(1)
    check(not ns.route.paused and strip(P.pause.text:GetText()) == "Pause", "Resume carries on")
    check(strip(F.status:GetText()):find("^Route running in The Barrens: stop") and not F.scanButton:IsShown(),
        "the footer shows the route and your spots, not auction prices: " .. strip(F.status:GetText()))
    P.finish:Click(); M.advance(1)
    check(ns.route == nil and P.start:IsShown(), "End route goes back to the preview")
    -- the zone menu
    P.zoneBtn:Click()
    check(P.menu:IsShown() and not P.menu.a.disabled, "the zone menu offers to put left-out spots back")
    P.menu.a:Click(); M.advance(1)
    check(not odd.skip and not P.menu:IsShown(), "which it does")
    ns.db.routes[1413] = nil
    ns.UI.routeStart[1413] = nil
    -- forgetting a zone needs a second click
    ns.db.nodes[4242] = { { x = 0.2, y = 0.2, k = "herb", c = 1, t = time() }, { x = 0.3, y = 0.3, k = "herb", c = 1, t = time() } }
    ns.Fire("NODES_UPDATED"); M.advance(1)
    local function search(text)
        F.zoneSearch:SetText(text)
        F.zoneSearch._scripts.OnTextChanged(F.zoneSearch)
        M.advance(1)
        local titles = {}
        for i = 1, F.list.count do
            local d = F.list.rows[i].d
            titles[#titles + 1] = strip(d.type == "header" and ("[" .. (d.text or "") .. "]") or (d.title or d.text or ""))
        end
        return table.concat(titles, " | ")
    end
    check(search("zone 42") == "[Other places] | Zone 4242", "searching finds a zone by name: " .. search("zone 42"))
    check(search("kalim") == "[Kalimdor] | The Barrens", "or every zone on a continent: " .. search("kalim"))
    check(search("nowhere"):find("No zones or continents match"), "and says when nothing matches")
    search("")
    local row4242
    for i = 1, F.list.count do
        if F.list.rows[i].d.key == "zone:4242" then row4242 = F.list.rows[i] end
    end
    row4242._scripts.OnClick(row4242)
    check(ns.UI.routeMap == 4242 and ns.UI.routeKinds.herb, "picking a herb-only zone ticks Herbs")
    check(P.artState == "none" and strip(P.note:GetText()):find("plain grid"), "no map picture: says so and draws a grid")
    P.zoneBtn:Click(); P.menu.c:Click()
    check(ns.db.nodes[4242] and strip(P.menu.text:GetText()):find("^Forget all 2 spots"), "Forget asks first")
    P.menu.b:Click()
    check(ns.db.nodes[4242] and not P.menu:IsShown(), "Keep them keeps them")
    P.zoneBtn:Click(); P.menu.c:Click(); P.menu.a:Click(); M.advance(1)
    check(ns.db.nodes[4242] == nil, "Forget them forgets")
    ns.UI.routeMap = 1413
    -- other tabs don't show any of it (the zone name used to stay on screen)
    ns.ShowTab("chars")
    check(not F.plot:IsShown(), "the map and its zone name hide on other tabs")
    ns.ShowTab("routes")
end
M.player.x, M.player.y = 0.50, 0.505
local route = ns.BuildRoute(1413, { ore = true, herb = true, fish = false })
check(route and route.n == 7, "route through 7 ore spots")
-- the loop should not be longer than the naive recorded order
local function len(pts) local t = 0; for i = 1, #pts do local a, b = pts[i], pts[(i % #pts) + 1]; t = t + math.sqrt(((a.x - b.x) * 1.5) ^ 2 + (a.y - b.y) ^ 2) end return t end
local naive = {}
for i, s in ipairs(spots) do naive[i] = { x = s[1], y = s[2] } end
out(string.format("  route length %.4f vs gathered order %.4f", route.length, len(naive)))
check(route.length <= len(naive) + 1e-9, "route is at least as short as the order you gathered in")
check(M.waypoint ~= nil, "map waypoint set")
check(ForeverGoldGuide and ForeverGoldGuide:IsShown(), "guide arrow shown")
M.update(1.1)
out("  guide: " .. strip(ForeverGoldGuide.line1:GetText()) .. " | " .. strip(ForeverGoldGuide.line2:GetText()))
local st = ns.RouteStatus()
check(st.onMap and st.yards and st.yards > 0, "distance in yards: " .. string.format("%.0f", st.yards or -1))
-- stand due south of the target facing north: arrow should point straight ahead
local pt = route.pts[route.i]
M.player.x, M.player.y, M.player.facing = pt.x, pt.y + 0.05, 0
st = ns.RouteStatus()
check(math.abs(st.angle) < 0.01, "target due north while facing north -> arrow straight ahead")
M.player.facing = math.pi / 2 -- now facing west: target is to the right => negative (clockwise) turn
st = ns.RouteStatus()
check(math.abs(st.angle + math.pi / 2) < 0.01, "facing west -> arrow points right")
local before = route.i
M.player.x, M.player.y = pt.x, pt.y + 0.001
M.update(1.1)
check(ns.route.i ~= before, "arriving advances to the next stop")
ForeverGoldGuide.skip._scripts.OnClick(ForeverGoldGuide.skip)
WorldMapFrame.OnMapChanged(WorldMapFrame)
WorldMapFrame._scripts.OnShow(WorldMapFrame)
do
    local wp = ns.WorldMapPlot()
    check(wp and wp.usedMarks == 8 and wp.usedLines > 0, "world map: every spot and the route: " .. tostring(wp and wp.usedMarks))
    -- OpenMap's stitched map: spots placed through its API, our switch in its menu
    local toggles, events = {}, {}
    OpenMapAPI = {
        IsStitched = function() return true end,
        WorldFromMap = function(m, x, y) if m == 1413 then return 0.4 + x * 0.1, 0.3 + y * 0.1 end end,
        MapFromWorld = function(host, u, v) return (u - 0.4) * 3, (v - 0.3) * 3 end,
        ArtTopLevel = function() return 900 end,
        RegisterCallback = function(owner, event, fn) events[event] = fn end,
        RegisterMenuToggle = function(owner, spec) toggles[spec.id] = spec end,
    }
    M.fire("ADDON_LOADED", "OpenMap")
    ns.RedrawWorldMap()
    check(toggles.spots and toggles.minimap and events.OpenMap_StitchedChanged, "OpenMap gets our switches and tells us when it changes")
    check(wp.usedMarks == 8, "spots drawn on OpenMap's stitched map too")
    toggles.spots.set(false)
    check(wp.usedMarks == 0 and toggles.spots.get() == false and ns.db.opts.worldMapSpots == false, "its switch hides them")
    toggles.spots.set(true)
    OpenMapAPI = nil
    ns.RedrawWorldMap()
    -- the minimap: nearby spots, and the next stop on the edge when it's far
    M.player.x, M.player.y = 0.50, 0.505
    ns.UpdateMinimapPins()
    local near = ns.MinimapPins.used
    check(near >= 2, "minimap shows the spots around you and the next stop: " .. near)
    ns.db.opts.minimapSpots = false
    ns.UpdateMinimapPins()
    check(ns.MinimapPins.used == 0, "and can be switched off")
    ns.db.opts.minimapSpots = true
end
M.player.map = 9999 -- left the zone
M.update(1.1)
out("  guide (other zone): " .. strip(ForeverGoldGuide.line1:GetText()) .. " | " .. strip(ForeverGoldGuide.line2:GetText()))
M.player.map = 1413
ns.StopRoute()
check(M.waypoint == nil and ns.route == nil, "stopping clears the waypoint")

out("== kill and loot tracker")
check(not ns.TrackerWindowShown(), "Kills & Loot window starts closed")
ns.ToggleTrackerWindow()
local TW = ForeverGoldTracker
check(TW and ns.TrackerWindowShown() and ns.db.opts.trackerShown, "Kills & Loot window opens on its own")
dumpRows("Kills (not started)", 3, TW.list)
check(TW.startBig:IsShown() and not TW.reset:IsShown() and not TW.cells[1]:IsShown() and strip(TW.state:GetText()) == "Idle",
    "idle: just Start session, no Reset or Save")
ns.ToggleTrackerWindow()
check(not ns.TrackerWindowShown() and ns.db.opts.trackerShown == false, "and closes again")
ns.TrackerStart()
check(ns.TrackerRunning(), "tracker started")
check(ns.TrackerWindowShown(), "starting the tracker opens the window")
local t0 = M.now
-- a mob you tagged dies in front of you
M.units.target = { guid = "Creature-0-1-2-3-4-0000AAAA", name = "Kolkar Drudge", dead = true }
M.fire("UNIT_HEALTH", "target")
M.fire("UNIT_HEALTH", "target")
-- someone else's kill
M.units.nameplate3 = { guid = "Creature-0-1-2-3-4-0000BBBB", name = "Kolkar Drudge", dead = true, tapDenied = true }
M.fire("UNIT_HEALTH", "nameplate3")
-- a player dying isn't a mob kill
M.units.nameplate4 = { guid = "Player-1-0001", name = "Somebody", dead = true, player = true }
M.fire("UNIT_HEALTH", "nameplate4")
check(ns.Tracker().kills == 1, "one kill: no doubles, not other people's, not players: " .. ns.Tracker().kills)
M.units = {}
-- loot that corpse: 2 linen and some coin
M.loot = { { type = 1, id = 2589, qty = 2, quality = 2, src = "Creature-0-1-2-3-4-0000AAAA" }, { type = 2, src = "Creature-0-1-2-3-4-0000AAAA" },
    { type = 1, id = 5085, qty = 1, quest = true, src = "Creature-0-1-2-3-4-0000AAAA" } }
M.fire("LOOT_READY", true)
M.player.money = M.player.money + 137; M.fire("PLAYER_MONEY")
M.fire("LOOT_SLOT_CLEARED", 1); M.fire("LOOT_SLOT_CLEARED", 2); M.fire("LOOT_SLOT_CLEARED", 3); M.fire("LOOT_CLOSED")
-- opening the same corpse again doesn't count its drops twice
M.loot = { { type = 1, id = 2589, qty = 1, src = "Creature-0-1-2-3-4-0000AAAA" } }
M.fire("LOOT_READY", true); M.fire("LOOT_CLOSED")
-- a corpse we never saw die still counts as a kill when looted
M.loot = { { type = 1, id = 4865, qty = 1, src = "Creature-0-1-2-3-4-0000CCCC" } }
M.fire("LOOT_READY", true); M.fire("LOOT_SLOT_CLEARED", 1); M.fire("LOOT_CLOSED")
check(ns.Tracker().kills == 2, "a looted corpse counts as a kill too")
-- mining a node
M.fire("UNIT_SPELLCAST_SENT", "player", "Copper Vein", "cast-1", 2575)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 2575)
M.loot = { { type = 1, id = 2770, qty = 3, src = "GameObject-0-1-2-3-4-0000DDDD" } }
M.fire("LOOT_READY", true); M.fire("LOOT_SLOT_CLEARED", 1); M.fire("LOOT_CLOSED")
-- a catch
M.fishing = true
M.loot = { { type = 1, id = 6522, qty = 1 } }
M.fire("LOOT_READY", true); M.fire("LOOT_SLOT_CLEARED", 1); M.fire("LOOT_CLOSED")
M.fishing = false
-- an item left in the window isn't counted
M.loot = { { type = 1, id = 2835, qty = 5, src = "GameObject-0-1-2-3-4-0000EEEE" } }
M.fire("LOOT_READY", true); M.fire("LOOT_CLOSED")
M.advance(1)
-- vendor: sell some things, repair
M.fire("MERCHANT_SHOW")
M.player.money = M.player.money + 500; M.fire("PLAYER_MONEY")
M.player.money = M.player.money - 120; M.fire("PLAYER_MONEY")
M.fire("MERCHANT_CLOSED")
-- mailbox: an auction sold
M.fire("MAIL_SHOW")
M.inbox = { { invoice = "seller", item = "Copper Bar", count = 5, money = 950 } }
TakeInboxMoney(1)
M.advance(1)
M.fire("MAIL_CLOSED")
-- money from nowhere in particular (a trade, say)
M.player.money = M.player.money + 300; M.fire("PLAYER_MONEY")
-- a quest turn-in: not farming income
M.fire("QUEST_COMPLETE")
M.player.money = M.player.money + 4000; M.fire("PLAYER_MONEY")
M.fire("QUEST_FINISHED")
M.fire("QUEST_TURNED_IN", 123, 450, 4000)
local tr = ns.Tracker()
check(tr.coin == 137, "coin looted: " .. tostring(tr.coin))
check(tr.loot.mob[2589] == 2 and tr.loot.mob[4865] == 1, "mob drops counted")
check(tr.loot.Mining[2770] == 3, "mined ore counted under Mining")
check(tr.loot.Fishing[6522] == 1, "catch counted under Fishing")
check(not tr.loot.other[2835], "loot left behind isn't counted")
check(tr.inc.vendor == 500 and tr.out.vendor == 120, "vendor sales and repairs")
check(tr.inc.ah == 950 and tr.sold["Copper Bar"] and tr.sold["Copper Bar"].q == 5, "auction sale from the mailbox")
check(tr.inc.other == 300, "other income counted, quest reward left out: " .. tostring(tr.inc.other))
check(not tr.loot.mob[5085], "quest items aren't counted as loot")
check(tr.kills == 2 and tr.mobs["Kolkar Drudge"] == 1, "mob names")
do
    local m = tr.mob["Kolkar Drudge"]
    check(m and m.k == 1 and m.coin == 137 and m.items[2589] == 2, "per-mob kills, coin and drops")
    check(m and m.good == 1 and m.since == 0, "a green drop resets 'kills since your last green'")
    check(m and m.drops[2589] == 1 and not m.drops[5085], "drop counted once per corpse, quest item left out")
    local dm = ns.TrackerMobs("kills")[1]
    check(dm.drops[1] and dm.drops[1].id == 2589 and dm.drops[1].rate == 1 and dm.drops[1].share == 1,
        "drop rate per kill and share of drops")
    local node = tr.nodes["Copper Vein"]
    check(node and node.n == 1 and node.cat == "Mining" and node.items[2770] == 3 and tr.gathers == 1,
        "gathering counted by node name")
    local life = ns.db.life
    check(life.mobs["Kolkar Drudge"].k == 1 and life.mobs["Kolkar Drudge"].v >= 137 and life.nodes["Copper Vein"].n == 1,
        "all-time numbers kept")
    check(tr.streak == 2 and tr.best == 2, "kill streak: " .. tostring(tr.streak))
    M.fire("PLAYER_DEAD")
    check(tr.streak == 0 and tr.best == 2, "dying ends the streak, best is kept")
    local mobs = ns.TrackerMobs("kills")
    check(#mobs == 1 and mobs[1].perKill >= 137 and mobs[1].zones[1], "TrackerMobs: worth per kill and zones")
end
-- time only counts while running
M.advance(1800)
local ran = ns.TrackerSeconds()
ns.TrackerPause()
M.advance(3600)
check(ns.TrackerSeconds() == ran, "paused: the clock stops")
ns.TrackerStart()
M.advance(600)
check(ns.TrackerSeconds() == ran + 600, "resumed: the clock carries on")
-- logging out pauses
M.fire("PLAYER_LOGOUT")
check(not ns.TrackerRunning() and ns.Tracker().autoPaused, "logging out pauses it")
ns.TrackerStart()
local sum = ns.TrackerSummary()
check(sum.made > 137 and math.abs(sum.made - (sum.coin + sum.lootValue)) < 0.01, "made = coin + loot value: " .. sum.made)
check(sum.net == 137 + 500 + 950 + 300 - 120, "real money in minus out: " .. sum.net)
do
    local view = ns.TrackerUI.view
    for _, tab in ipairs({ "kills", "loot", "money" }) do
        TW.tabs[tab]._scripts.OnClick(TW.tabs[tab])
        check(view.tab == tab, "window tab " .. tab)
        dumpRows("Kills & Loot: " .. tab, 40, TW.list)
        pokeRows(TW.list)
    end
    TW.tabs.kills._scripts.OnClick(TW.tabs.kills)
    -- click a mob to fold out its details
    local before = TW.list.count
    for i = 1, TW.list.count do
        local r = TW.list.rows[i]
        if strip(r.d.title):find("Kolkar Drudge") then
            r._scripts.OnClick(r)
            break
        end
    end
    check(TW.list.count == before + 1 and view.open["Kolkar Drudge"], "clicking a mob shows its details")
    dumpRows("Kills (Kolkar Drudge open)", 40, TW.list)
    for _ = 1, 3 do
        TW.sort._scripts.OnClick(TW.sort)
    end
    check(view.sort == "recent", "sort goes round recent, kills, gold")
    TW._scripts.OnDragStop(TW)
    check(type(ns.db.opts.trackerPos) == "table", "window position saved")
    check(not TW.startBig:IsShown() and TW.reset:IsShown() and TW.cells[3]:IsShown()
        and strip(TW.state:GetText()) == "Recording" and TW.start.text:GetText() == "Stop", "recording: stats, Stop, Save and Reset")
    out("  stats: " .. strip(TW.cells[1].value:GetText()) .. " | " .. strip(TW.cells[2].value:GetText()) .. " | "
        .. strip(TW.cells[3].value:GetText()) .. " | " .. strip(TW.cells[4].value:GetText()))
    TW.fold._scripts.OnClick(TW.fold)
    check(ns.db.opts.trackerCollapsed and TW:GetHeight() == 22 and TW:GetWidth() < 286 and TW.head:IsShown(),
        "fold down to a narrow status strip")
    TW.fold._scripts.OnClick(TW.fold)
    check(not ns.db.opts.trackerCollapsed and TW:GetHeight() > 22, "and back")
    M.update(1.1)
    out("  window: " .. strip(TW.head:GetText()))
    check(strip(TW.head:GetText()):find("/hr"), "gold per hour in the window's top line")
end
-- reset keeps it running, from zero
ns.TrackerReset()
check(ns.TrackerRunning() and ns.Tracker().kills == 0 and ns.Tracker().coin == 0, "reset wipes the numbers and keeps running")
M.units.target = { guid = "Creature-0-1-2-3-4-0000FFFF", name = "Plainstrider", dead = true }
M.fire("UNIT_HEALTH", "target")
M.units = {}
M.advance(120)
ns.ToggleSession() -- stop
if TW and TW:IsShown() then
    ns.RefreshTrackerWindow()
    check(TW.start.text:GetText() == "Start" and strip(TW.state:GetText()) == "Stopped", "stopped: the button says Start")
end
ns.ShowTab("farm")
do
    local labels = {}
    for _, b in ipairs(ForeverGoldFrame.toolbar.buttons) do
        if b:IsShown() then labels[#labels + 1] = b.text:GetText() end
    end
    out("  Make > Farm toolbar: " .. table.concat(labels, " | "))
    check(table.concat(labels, "|") == "Craft|Farm|Routes|Farming Session", "Make > Farm toolbar: switch plus the Kills & Loot window")
end
local before = #ns.db.sessions
ns.StopSession()
check(#ns.db.sessions == before + 1 and ns.SessionActive() == nil and ns.db.sessions[1].kills == 1, "trip saved")
ns.RefreshUI(); pokeRows()

out("== options + scroll + misc")
ns.ShowTab("tips"); dumpRows("Tips", 6)
do
    local list = ForeverGoldFrame.list
    local clicked = 0
    for i = 1, list.count do
        local d = list.rows[i].d
        if not d.type and d.onClick and strip(d.title):find("%[on%]") then clicked = clicked + 1; d.onClick(d) break end
    end
    check(clicked == 1 and ns.db.opts.autoScan == false, "settings rows toggle")
    ns.db.opts.autoScan = true
    list.clip._scripts.OnMouseWheel(list.clip, -1)
    check(list.offset > 0, "mouse wheel scrolls")
    list.clip._scripts.OnMouseWheel(list.clip, 1)
end
SlashCmdList["FOREVERGOLD"]("debug")
SlashCmdList["FOREVERGOLD"]("help")
ForeverGold_OnAddonCompartmentClick(); ForeverGold_OnAddonCompartmentClick()
M.fire("PLAYER_LEVEL_UP", 26)
M.advance(5)

out("== interrupted scan must not wipe the price book")
M.fire("AUCTION_HOUSE_CLOSED")
local saved = M.auctions
M.auctions = { saved[1], saved[2] }
M.advance(4000)
M.fire("AUCTION_HOUSE_SHOW"); M.advance(40)
check(M.queries == 3, "the tiny scan did run")
check(ns.AHPrice(2841) == 420, "tiny scan (2 of 20 items) keeps other prices live")
M.fire("AUCTION_HOUSE_CLOSED"); M.advance(4000); M.fire("AUCTION_HOUSE_SHOW"); M.advance(40)
check(ns.AHPrice(2841) == nil, "but two small scans in a row are believed")
M.auctions = saved

out("== fast scan")
-- put the price book back in a known state with one slow scan
M.fire("AUCTION_HOUSE_CLOSED"); M.advance(4000); M.fire("AUCTION_HOUSE_SHOW"); M.advance(40)
check(ns.AHPrice(2841) == 420 and not M.replicateCalls, "slow scan while the fast one is switched off in settings")
ns.db.opts.fastScan = true
M.fire("AUCTION_HOUSE_CLOSED"); M.advance(4000)
local q0 = M.queries
M.fire("AUCTION_HOUSE_SHOW"); M.advance(1.6)
check(ns.scan.active and ns.scan.mode == "replicate", "auto-scan now uses the fast download")
out("  status: " .. ns.ScanStatus())
M.advance(3)
check(not ns.scan.active and M.queries == q0, "finished in a few seconds with no paging at all")
check(ns.R().fastOK == true, "its prices matched the slow scan's, so it is now trusted")
check(ns.AHPrice(2840) == 90 and select(2, ns.AHPrice(2840)) == 150, "stack prices are turned into per-item prices; quantities add up")
check(ns.AHPrice(12345) == 1500 and ns.IsBuyout(12345), "fast scan sees the sword's real 15s buyout, not the 4s bid")
check(ns.AHPrice(12347) == nil, "the bid-only cloak has no buyout price at all")
do
    local f = ns.VendorFlips()
    check(#f == 1 and f[1].id == 12346 and ns.VerifyPending() == 0 and #ns.PendingDeals() == 0, "deals are right immediately - nothing left to double-check")
end
out("  last scan: " .. ns.scan.lastResult.mode .. ", " .. ns.scan.lastResult.n .. " items from " .. ns.scan.lastResult.auctions .. " auctions")

check(ns.R().lastScanInfo and ns.R().lastScanInfo.mode == "replicate" and ns.R().lastScanInfo.arrived
    and ns.R().lastScanInfo.arrived < 3, "how the scan went is saved for /gold debug")

-- inside the game's 15 minute limit Scan says when the fast scan is back
-- instead of starting the minute-long slow one...
M.advance(60)
local printed0 = #M.printed
ns.StartScan(); M.advance(40)
check(M.queries == q0 and M.replicateCalls == 1 and not ns.scan.active, "second scan within 15 minutes doesn't start the slow scan")
check((M.printed[#M.printed] or ""):find("full scan can run again in 1[34]:%d%d") ~= nil and #M.printed > printed0,
    "and says when the full scan is available again")
check(ns.FastScanWait() > 0, "and the wait for the next fast scan is known")
-- ...but the slow scan is still there when asked for
SlashCmdList["FOREVERGOLD"]("scan slow"); M.advance(40)
check(M.queries == q0 + 1 and M.replicateCalls == 1, "/gold scan slow still reads page by page")

-- opening the auction window rescans by itself once prices are 5 minutes old
check(ns.db.opts.autoAge == 300, "auto-rescan age defaults to 5 minutes")
M.fire("AUCTION_HOUSE_CLOSED"); M.advance(120)
local c0, qq = M.replicateCalls, M.queries
M.fire("AUCTION_HOUSE_SHOW"); M.advance(30)
check(M.replicateCalls == c0 and M.queries == qq, "2 minutes old: left alone")
M.fire("AUCTION_HOUSE_CLOSED"); M.advance(240)
M.fire("AUCTION_HOUSE_SHOW"); M.advance(30)
check(M.replicateCalls == c0 and M.queries == qq, "6 minutes old but the fast scan isn't allowed yet: no slow scan forced on you")
M.fire("AUCTION_HOUSE_CLOSED"); M.advance(600)
M.fire("AUCTION_HOUSE_SHOW"); M.advance(30)
check(M.replicateCalls == c0 + 1 and M.queries == qq, "fast scan allowed again: opening the window scans automatically")
M.fire("AUCTION_HOUSE_CLOSED"); M.advance(400)
ns.R().replicateAt = time() - 2000 -- pretend the last scan was a slow one
M.fire("AUCTION_HOUSE_SHOW"); M.advance(30)
check(M.replicateCalls == c0 + 2, "prices 6-7 minutes old and fast scan available: rescans")

-- the download never arrives (another addon used the allowance)
M.fire("AUCTION_HOUSE_CLOSED"); M.advance(1000)
M.repSilent = true
q0 = M.queries
M.fire("AUCTION_HOUSE_SHOW"); ns.StartScan(); M.advance(45)
check(M.queries == q0 and ns.scan.active and ns.scan.mode == "replicate", "a slow download is waited for (45s in, still waiting)")
M.advance(60)
check(M.queries == q0 + 1 and not ns.scan.active and ns.AHPrice(2841) == 420, "no download at all -> falls back to the slow scan by itself")
M.repSilent = false

-- a big auction house whose download takes 30 seconds still gets the fast scan
M.fire("AUCTION_HOUSE_CLOSED"); M.advance(1000)
M.repDelay = 30
q0 = M.queries
M.fire("AUCTION_HOUSE_SHOW"); ns.StartScan(); M.advance(45)
check(M.queries == q0 and not ns.scan.active and ns.scan.lastResult.mode == "replicate"
    and ns.scan.lastResult.arrived >= 29, "download arriving after 30s is used, no slow scan on top")
M.repDelay = nil

-- rows whose item data hasn't loaded yet are waited for
M.fire("AUCTION_HOUSE_CLOSED"); M.advance(1000)
M.repLazy = true
q0 = M.queries
M.fire("AUCTION_HOUSE_SHOW"); ns.StartScan(); M.advance(20)
check(M.queries == q0 and ns.scan.lastResult.mode == "replicate" and ns.AHPrice(2770) == 40, "half-loaded download is re-read, not half-recorded")
M.repLazy = false

-- closing the window mid-download keeps nothing from it
M.fire("AUCTION_HOUSE_CLOSED"); M.advance(1000)
M.fire("AUCTION_HOUSE_SHOW"); ns.StartScan(); M.advance(0.5)
ns.R().prices[2770].p = 41
M.fire("AUCTION_HOUSE_CLOSED")
check(not ns.scan.active and ns.AHPrice(2770) == 41, "window closed mid-download: price book untouched")

-- a client where the download means something different must be caught
M.advance(1000)
ns.R().fastOK = nil
M.repPerUnit = true
q0 = M.queries
M.fire("AUCTION_HOUSE_SHOW"); ns.StartScan(); M.advance(60)
check(ns.R().fastBad == true, "fast scan whose prices are way off is rejected and switched off")
check(M.queries == q0 + 1 and ns.AHPrice(2840) == 90, "the slow scan ran instead and the prices are right")
M.fire("AUCTION_HOUSE_CLOSED"); M.advance(4000)
local calls = M.replicateCalls
M.fire("AUCTION_HOUSE_SHOW"); M.advance(40)
check(M.replicateCalls == calls, "and it stays off afterwards")
M.repPerUnit = false
ns.ShowTab("deals"); dumpRows("Deals (after fast-scan tests)", 8)
ns.ShowTab("tips")
do
    local list = ForeverGoldFrame.list
    for i = 1, list.count do
        local d = list.rows[i].d
        if not d.type and strip(d.title):find("Smallest profit") then d.onClick(d) end
    end
    check(ns.db.opts.dealMin == 2500, "deal minimum setting cycles 5s -> 25s")
end
SlashCmdList["FOREVERGOLD"]("debug")

out("== sale rates from the tracker app")
check(ns.SaleRate(2840) == nil and ns.MarketStatus():find("No sale"), "no data file: no sale rates")
check(ns.R().lastScanBy == "Xeon Mana", "scans remember who did them")
do
    local mine, other = {}, {}
    local n = 0
    for id, r in pairs(ns.R().prices) do
        if r.p and (r.q or 0) > 0 then
            n = n + 1
            mine[id] = string.format("0,-1,0,%d,%d,0", r.p, r.q)
            other[id] = string.format("0,-1,0,%d,1,0", r.p * 3 + 7)
        end
    end
    out("  items with a live price: " .. n)
    mine[2840] = "40,70,95," .. ns.AHPrice(2840) .. ",120,60" -- copper bars fly
    mine[2853] = "0.1,5,0,900,14,2" -- bracers almost never sell
    mine[2589] = "120,64,180," .. (ns.AHPrice(2589) or 150) .. ",400,90" -- linen sells
    mine[2880] = "0,0,0,5000,3,1" -- weak flux listed high, never sells
    ForeverGoldMarket = { v = 1, made = M.now - 300, region = "us", houses = {
        [114] = { t = M.now - 900, hours = 50, items = other },
        [113] = { t = M.now - 900, hours = 50, items = mine },
    } }
end
ns.Fire("PRICES_UPDATED")
local info = ns.MarketInfo()
check(info and info.house == 113, "picks the auction house that matches your own scan: " .. tostring(info and info.house))
check(ns.SaleSpeed(2840) == "fast", "copper bars: sells fast")
check(ns.SaleSpeed(2853) == "rarely", "bracers: rarely sells")
check(ns.SaleSpeed(2770) == nil, "no sales yet after 2 days but under 3: no verdict, not 'rarely'")
ForeverGoldMarket.houses[113].hours = 10; ns.Fire("PRICES_UPDATED")
check(ns.SaleSpeed(2840) == "fast" and ns.SaleSpeed(2853) == nil, "after 10 hours: fast sellers show, nothing is called slow yet")
ForeverGoldMarket.houses[113].hours = 50; ns.Fire("PRICES_UPDATED")
check(strip(ns.SaleText(2840)):find("about 40 a day, 70%% of listings sell"), "plain-English rate: " .. strip(ns.SaleText(2840)))
local rv, how = ns.ResaleValue(2840)
check(how == "sold" and math.abs(rv - 90 * 0.95) < 0.01, "resale value: what it sold for, capped by the cheapest listing now")
check(select(2, ns.ResaleValue(2880)) == "nosale", "listed but never sells: no resale value")
out("  " .. ns.MarketStatus())
-- vendor resale: proven vs unproven
local savedMin = ns.db.opts.dealMin
ns.db.opts.dealMin = 1
ns.db.vendor[2589] = { p = 10, t = M.now }               -- sells for 180 at auction: proven
ns.db.vendor[2880] = { p = 100, t = M.now }              -- listed at 50s, never sells: dropped
ns.db.vendor[2836] = { p = 5, t = M.now }                -- no sale data: unproven
ns.Fire("VENDOR_UPDATED")
local deals = ns.VendorDeals()
local byId = {}
for _, d in ipairs(deals) do byId[d.id] = d end
check(byId[2589] and byId[2589].sure, "vendor item that really sells is a sure deal")
check(not byId[2880], "vendor item that never sells is not a deal")
check(not byId[2836] or not byId[2836].sure, "vendor item with only an asking price is unproven")
check(deals[1].sure, "sure deals listed first")
ns.ShowTab("deals"); dumpRows("Deals (with sale rates)", 40); pokeRows()
ns.db.opts.dealMin = savedMin
-- the merchant chat note only mentions proven ones
local printedBefore = #M.printed
M.merchant = { { 2880, 100, 1, -1 }, { 2589, 10, 1, -1 } }
M.fire("MERCHANT_SHOW"); M.advance(1); M.fire("MERCHANT_CLOSED")
local said = {}
for i = printedBefore + 1, #M.printed do said[#said + 1] = strip(M.printed[i]) end
local joined = table.concat(said, " / ")
check(not joined:find("Weak Flux"), "vendor chat note skips things that never sell: " .. joined)
-- tooltip shows the rate
GameTooltip._lines = {}
M.tooltipHook(GameTooltip, { id = 2840 })
local tip = {}
for _, l in ipairs(GameTooltip._lines) do tip[#tip + 1] = strip(l) end
out("    " .. table.concat(tip, "\n    "))
check(table.concat(tip, " "):find("sells fast") and table.concat(tip, " "):find("Has been selling for"), "tooltip shows sale speed and sold price")
-- crafting ranks by expected profit
ns.ShowTab("craft"); dumpRows("Craft (with sale rates)", 12); pokeRows()
ns.ShowTab("bags"); dumpRows("Bags (with sale rates)", 30); pokeRows()
ns.ShowTab("tips")

out("== prices shared from your other characters")
ns.db.realms["6801-Alliance"] = { prices = { [424242] = { p = 777, q = 3, t = M.now - 120 } }, lastScanBy = "Alt Toon" }
GameTooltip._lines = {}
M.tooltipHook(GameTooltip, { id = 424242 })
local shared = {}
for _, l in ipairs(GameTooltip._lines) do shared[#shared + 1] = strip(l) end
out("    " .. table.concat(shared, "\n    "))
check(table.concat(shared, " "):find("From Alt Toon %(Alliance%)'s scan"), "tooltip shows another character's price and who scanned it")

out("== recipes that use an item")
GameTooltip._lines = {}
M.tooltipHook(GameTooltip, { id = 2589 })
local used = {}
for _, l in ipairs(GameTooltip._lines) do used[#used + 1] = strip(l) end
out("    " .. table.concat(used, "\n    "))
local joinedUse = table.concat(used, " ")
check(joinedUse:find("Used in %d+ recipes:") and joinedUse:find("Tailoring") and joinedUse:find("First Aid"),
    "linen cloth tooltip counts the recipes that use it, by profession")
do
    local _, n = ns.RecipeUseSummary(2589)
    check(n and n >= 10, "linen cloth is used in plenty of recipes: " .. tostring(n))
    check(ns.RecipeUseSummary(99999999) == nil, "an item no recipe uses has no recipe line")
end
IsShiftKeyDown = function() return true end
GameTooltip._lines = {}
M.tooltipHook(GameTooltip, { id = 2589 })
check(#GameTooltip._lines >= #used + 12 and strip(GameTooltip._lines[#used + 1]):find("Bolt of Linen Cloth") == nil and #GameTooltip._lines > #used,
    "holding Shift lists the recipes")
IsShiftKeyDown = nil

out("== vendor-price guard")
check(ns.VendorCheck(2840, 10) == "below", "10c copper bar nets less than the 10c a vendor pays")
check(ns.VendorCheck(2840, 11) == "close", "11c is barely above vendor")
check(ns.VendorCheck(2840, 200) == nil, "2s is fine")
do
    local slot
    for i, b in ipairs(M.bags) do if b[1] == 2840 then slot = i end end
    M.sellPrice = 10
    local sellFrame = {
        GetItem = function() return { slot = slot, IsValid = function() return true end } end,
        PriceInput = { GetAmount = function() return M.sellPrice end },
        UpdatePostState = function() end,
        HookScript = function() end,
    }
    AuctionHouseFrame.ItemSellFrame = sellFrame
    M.fire("AUCTION_HOUSE_SHOW"); M.advance(1)
    sellFrame:UpdatePostState()
    check(sellFrame.fgGuard and sellFrame.fgGuard:IsShown() and strip(sellFrame.fgGuard.text:GetText()):find("Below vendor price"),
        "the auction house's own Sell screen warns below vendor price")
    out("  " .. strip(sellFrame.fgGuard.text:GetText()))
    M.sellPrice = 500
    sellFrame:UpdatePostState()
    check(not sellFrame.fgGuard:IsShown(), "and the warning goes away at a sensible price")
    AuctionHouseFrame.ItemSellFrame = nil
    local real = C_AuctionHouse.GetOwnedAuctions
    C_AuctionHouse.GetOwnedAuctions = function()
        return { { auctionID = 77, itemKey = { itemID = 2840 }, status = 0, quantity = 1, buyoutAmount = 9 },
            { auctionID = 78, itemKey = { itemID = 2840 }, status = 0, quantity = 5, buyoutAmount = 600 } }
    end
    local pb = #M.printed
    M.fire("OWNED_AUCTIONS_UPDATED"); M.fire("OWNED_AUCTIONS_UPDATED")
    local warns = 0
    for i = pb + 1, #M.printed do if strip(M.printed[i]):find("heads up") then warns = warns + 1 end end
    check(warns == 1, "a listing under vendor price is called out once in chat: " .. warns)
    local saved = ns.Char().webAuctions
    check(saved and #saved.list == 2 and saved.list[1].id == 77 and saved.list[2].q == 5 and saved.list[2].b == 600,
        "your auctions are remembered for the website")
    ns.BuildWebExport()
    local web = ns.db.webExport
    local me
    for _, c in ipairs(web and web.chars or {}) do if c.name == ns.Char().name then me = c end end
    check(web and web.v == 1 and me and me.auctions == saved and type(me.money) == "number",
        "web export carries each character's gold and auctions")
    check(web.prices == nil and me.bags == nil and me.recipes == nil, "web export leaves prices, bags and recipes out")
    C_AuctionHouse.GetOwnedAuctions = real
    M.fire("AUCTION_HOUSE_CLOSED")
end

out("")
out("== our own auction window")
do
    local A, P = ns.AuctionUI, ns.Poster
    ns.db.opts.ahBlizzard = nil
    M.fire("AUCTION_HOUSE_SHOW"); M.advance(60)
    local F = ForeverGoldAuctionFrame
    check(F and F:IsShown(), "talking to an auctioneer opens our window")
    check(AuctionHouseFrame._scale == 0.001 and AuctionHouseFrame._alpha == 0 and AuctionHouseFrame._mouse == false,
        "the game's window is shrunk out of the way, not closed")
    check(not (ForeverGoldAuctionStrip and ForeverGoldAuctionStrip:IsShown()), "the strip above the game's window stays hidden")
    check(A.tab == "browse" and F.browse:IsShown() and not F.sell:IsShown(), "it opens on Browse")

    -- Browse: a name search
    A.Search("bar"); M.advance(5)
    local names, allBars = {}, true
    for _, r in ipairs(A.BUY.results) do
        local n = ns.ItemName(r.id)
        names[#names + 1] = n
        if not n:find("Bar") then allBars = false end
    end
    check(#A.BUY.results == 3 and allBars and not A.BUY.searching, "searching 'bar' finds the three bars: " .. table.concat(names, ", "))
    check(M.lastBrowse.searchString == "bar", "the search text reaches the auction house")
    A.Refresh()
    check(F.browse.results.view[1] ~= nil and F.browse.results.rows[1]:IsShown(), "results are listed")

    -- A category
    A.openCategory = nil
    F.browse.cats.onClick({ name = "Trade Goods", top = 2, filters = { { classID = 7 } } }); M.advance(5)
    check(M.lastBrowse.itemClassFilters and M.lastBrowse.itemClassFilters[1].classID == 7 and A.openCategory == 2,
        "picking a category searches it and opens its subcategories")

    -- Deals
    local keepMin = ns.db.opts.dealMin
    ns.db.opts.dealMin = 1
    ns.Fire("PRICES_UPDATED")
    A.ShowDeals()
    local flips = #ns.VendorFlips() + #ns.Bargains()
    check(A.BUY.deals and flips > 0 and #A.BUY.results == flips, "Deals lists the bargains from the last scan: " .. #A.BUY.results)
    A.Refresh()
    check(F.browse.results.rows[1]:IsShown() and strip(F.browse.results.rows[1].cells[5]:GetText()) ~= "", "each deal says why")
    ns.db.opts.dealMin = keepMin
    ns.Fire("PRICES_UPDATED")

    -- Buying stackable goods: quote, then confirm
    M.market[2840] = { { 90, 150 }, { 95, 30 }, { 120, 5, true } }
    A.OpenItem({ id = 2840 }); M.advance(2)
    check(A.BUY.mode == "item" and A.BUY.item.commodity and #A.BUY.listings == 3, "opening Copper Bar lists every price")
    A.BUY.qty = 160
    check(A.CommodityCost(160) == 150 * 90 + 10 * 95, "the cost adds up cheapest first, skipping your own")
    A.Refresh()
    check(strip(F.browse.box.buy.text:GetText()) == "Buy 160", "the buy button says how many")
    M.player.money = 100000
    F.browse.box.buy:Click(); M.advance(1)
    check(A.BUY.buy and A.BUY.buy.state == "quoted" and A.BUY.buy.total == 150 * 90 + 10 * 95, "first click asks for the real price")
    A.Refresh()
    check(strip(F.browse.box.buy.text:GetText()):find("^Confirm: pay"), "then the button asks you to confirm it")
    F.browse.box.buy:Click(); M.advance(1)
    check(#M.bought == 1 and M.bought[1].qty == 160 and A.BUY.buy == nil, "second click buys them")
    check(strip(A.BUY.message or ""):find("^Bought 160"), "and says so: " .. strip(A.BUY.message or ""))
    -- backing out of a quote
    A.OpenItem({ id = 2840 }); M.advance(2)
    A.Buy(); M.advance(1)
    A.CancelBuy()
    check(A.BUY.buy == nil and M.quoteFor == nil and #M.bought == 1, "Cancel backs out of a quote")

    -- Buying gear: pick the listing
    A.OpenItem({ id = 12346 }); M.advance(2)
    check(A.BUY.item and not A.BUY.item.commodity and #A.BUY.listings == 2, "gear lists each auction")
    A.Refresh()
    check(F.browse.box.buy.disabled, "nothing to buy until you pick one")
    F.browse.listings.onClick({ l = A.BUY.listings[1] })
    F.browse.box.buy:Click(); M.advance(1)
    check(#M.bids == 1 and M.bids[1].aid == 1234601 and M.bids[1].amount == 300, "buying gear pays its buyout")
    check(A.BUY.buy == nil and strip(A.BUY.message or ""):find("Bought"), "and finishes")
    M.market[12346] = { { 300, 1, true } }
    A.OpenItem({ id = 12346 }); M.advance(2)
    A.BUY.sel = A.BUY.listings[1]
    A.Buy()
    check(#M.bids == 1, "never buys your own listing")

    -- Elsewhere in the addon, "search the auction house" lands here
    ns.SearchAH("Tin Bar"); M.advance(3)
    check(A.tab == "browse" and A.BUY.query == "Tin Bar" and F.browse.search:GetText() == "Tin Bar", "other search buttons use our Browse tab")

    -- Sell: the proposed listings, then Post, Post, Post
    A.SetTab("sell")
    check(F.sell:IsShown() and #P.entries > 0, "Sell lists what's in your bags: " .. #P.entries)
    local picked = 0
    for _, e in ipairs(P.entries) do if e.picked then picked = picked + 1 end end
    A.Refresh()
    check(picked > 0 and strip(F.sell.side.post.text:GetText()) == "Price check " .. picked .. " items",
        "the big button price-checks the ticked items first: " .. strip(F.sell.side.post.text:GetText()))
    local undercutBefore = P.Setting("undercut")
    F.sell.settings[1]:Click()
    check(P.Setting("undercut") ~= undercutBefore, "the settings bar cycles undercut")
    for _ = 1, #P.UNDERCUT - 1 do F.sell.settings[1]:Click() end
    check(P.Setting("undercut") == undercutBefore, "and round again")
    F.sell.side.post:Click(); M.advance(30)
    check(P.state == "ready", "after the check, listings are ready: " .. tostring(P.state))
    local ready, listings = P.Summary()
    A.Refresh()
    check(strip(F.sell.side.post.text:GetText()):find("^Post %d+ x "), "the button names the next listing: " .. strip(F.sell.side.post.text:GetText()))
    local before = #M.posted
    local queriesBefore = M.ownedQueries or 0
    local presses = 0
    while P.state == "ready" and presses < 40 do
        F.sell.side.post:Click(); M.advance(1)
        presses = presses + 1
    end
    check(P.state == "done" and #M.posted - before == listings and presses == listings,
        "one press per listing until done: " .. presses .. " presses, " .. (#M.posted - before) .. " posted, " .. listings .. " planned")
    local cheap = true
    for i = before + 1, #M.posted do
        local p = M.posted[i]
        local e
        for _, x in ipairs(P.entries) do if x.id == p.id then e = x end end
        local each = p.kind == "item" and (p.price / p.qty) or p.price
        if e and e.lowest and each > e.lowest then cheap = false end
    end
    check(cheap, "nothing posted above the lowest price it saw")
    A.Refresh()
    check(strip(F.sell.side.post.text:GetText()):find("All posted"), "then it says all posted")
    M.advance(5)
    check((M.ownedQueries or 0) - queriesBefore == 1,
        "your auctions are read once after the posting, not after every post: " .. ((M.ownedQueries or 0) - queriesBefore))

    -- The main window's Sell button picks the item in our Sell tab
    local target
    for _, e in ipairs(P.entries) do if e.id == 2840 then target = e end end
    if target then
        target.status = "posted"
        ns.OpenSell(2840); M.advance(5)
        check(A.tab == "sell" and A.sellSel == target and target.picked and P.state ~= "checking",
            "the main window's Sell button checks that one item in our Sell tab: " .. tostring(target.status))
    else
        check(false, "Copper Bar is in the Sell list")
    end

    -- Walking away mid-check doesn't leave items stuck on "Checking..."
    P.entries[1].status = "checking"; P.state = "checking"
    M.fire("AUCTION_HOUSE_CLOSED"); M.advance(1)
    check(P.entries[1].status == "new" and P.state ~= "checking", "closing the auction house mid-check resets it")
    M.fire("AUCTION_HOUSE_SHOW"); M.advance(60)

    -- Browse rows are reused, not rebuilt, when nothing changed
    A.SetTab("browse")
    A.Search("bar"); M.advance(5)
    A.Refresh()
    local calls = M.keyInfoCalls or 0
    for _ = 1, 10 do ns.Fire("SCAN_PROGRESS"); M.advance(1) end
    A.Refresh()
    check((M.keyInfoCalls or 0) == calls, "scan progress and gold changes don't rebuild the Browse list: " .. ((M.keyInfoCalls or 0) - calls))
    A.SetTab("sell")

    -- Auctions: undercut checks and the cancel queue
    M.owned = {
        { auctionID = 601, itemKey = { itemID = 2840 }, status = 0, quantity = 7, buyoutAmount = 100, timeLeftSeconds = 30000 },
        { auctionID = 602, itemKey = { itemID = 3576 }, status = 0, quantity = 3, buyoutAmount = 150, timeLeftSeconds = 30000 },
        { auctionID = 603, itemKey = { itemID = 2589 }, status = 1, quantity = 4, buyoutAmount = 70 },
    }
    M.market[3576] = { { 150, 3, true }, { 200, 40 } }
    A.SetTab("auctions"); M.advance(1)
    check(#P.owned == 3, "Auctions lists your auctions: " .. #P.owned)
    F.mine.side.check:Click(); M.advance(10)
    local st = {}
    for _, a in ipairs(P.owned) do st[a.auctionID] = a.state end
    check(st[601] == "undercut" and st[602] == "cheapest" and st[603] == "sold",
        "live checks mark undercut, cheapest and sold: " .. tostring(st[601]) .. "/" .. tostring(st[602]) .. "/" .. tostring(st[603]))
    A.Refresh()
    check(strip(F.mine.side.cancelNext.text:GetText()) == "Cancel next undercut (1)", "the cancel button counts the undercut ones")
    F.mine.side.cancelNext:Click()
    check(M.cancelled[#M.cancelled] == 601, "it cancels the undercut one, not the cheapest")
    M.owned = { M.owned[2], M.owned[3] }
    M.advance(2)
    check(#P.Undercut() == 0 and P.cancelling == nil, "then nothing is left undercut")
    A.mineSel = P.owned[1]
    A.Refresh()
    check(not F.mine.side.cancelOne.disabled and strip(F.mine.side.body:GetText()):find("Cancelling costs"), "a picked auction shows its cancel cost")
    M.owned = nil

    -- Switching to the game's window and back
    F.blizz:Click()
    check(not F:IsShown() and AuctionHouseFrame._scale == 1 and AuctionHouseFrame._alpha == 1 and ns.db.opts.ahBlizzard,
        "Game's window brings back the game's own")
    check(ForeverGoldAuctionStrip and ForeverGoldAuctionStrip:IsShown() and ForeverGoldAuctionStrip.ours, "with a button to come back")
    ForeverGoldAuctionStrip.ours:Click()
    check(F:IsShown() and AuctionHouseFrame._scale == 0.001 and not ns.db.opts.ahBlizzard and not ForeverGoldAuctionStrip:IsShown(),
        "which switches back to ours")
    M.fire("AUCTION_HOUSE_CLOSED"); M.advance(1)
    check(not F:IsShown() and AuctionHouseFrame._scale == 1 and AuctionHouseFrame._alpha == 1, "walking away closes ours and restores the game's")
    -- the game shows its frame after the event: our hook hides it again
    M.fire("AUCTION_HOUSE_SHOW")
    AuctionHouseFrame:Hide(); AuctionHouseFrame._scale = 1; AuctionHouseFrame:Show()
    check(AuctionHouseFrame._scale == 0.001, "the game's window is hidden again whenever it shows")
    M.fire("AUCTION_HOUSE_CLOSED"); M.advance(1)
end
ForeverGoldMarket = nil
ns.Fire("PRICES_UPDATED")

out("")
out("== chat output")
for _, l in ipairs(M.printed) do out("  > " .. strip(l)) end
out("")
out("== errors recorded by the addon: " .. #ns.errors)
for _, e in ipairs(ns.errors) do out("  ! " .. e) end
local undef = {}
for k in pairs(M.undefined) do undef[#undef + 1] = k end
table.sort(undef)
out("== globals read but not defined in the mock: " .. table.concat(undef, ", "))
out("")
out((fails == 0 and #ns.errors == 0) and "ALL CHECKS PASSED" or ("FAILED: " .. fails .. " checks, " .. #ns.errors .. " errors"))

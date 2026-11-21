local M, ns = MOCK, NS
local out = M.realPrint
local fails = 0
local function check(cond, what)
    if cond then out("  ok   " .. what) else fails = fails + 1; out("  FAIL " .. what) end
end
local function strip(s)
    s = tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    -- coin icons read as letters: 12g 34s
    s = s:gsub("|T[^|]-UI%-GoldIcon[^|]-|t", "g"):gsub("|T[^|]-UI%-SilverIcon[^|]-|t", "s"):gsub("|T[^|]-UI%-CopperIcon[^|]-|t", "c")
    return s
end
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

out("== suspicious prices (gold changing hands)")
do
    local JUNK, BOOTS, LINEN_ID = 12345, 12346, 2589 -- gray sword (vendor 9s), white boots, linen
    ns.Item(JUNK); ns.Item(BOOTS)
    local why = ns.Suspicious(JUNK, 900 * 50)
    check(why and why:find("50x") and why:find("gold"), "a gray item at 50x what a vendor pays is suspicious: " .. tostring(why))
    check(not ns.Suspicious(JUNK, 1500), "a gray item a bit over vendor price isn't")
    check(not ns.Suspicious(BOOTS, 900 * 15), "white gear a fair bit over vendor price isn't")
    local whyBoots = ns.Suspicious(BOOTS, 900 * 50)
    check(whyBoots and whyBoots:find("Plain white gear at 50x", 1, true), "white gear at 50x what a vendor pays is: " .. tostring(whyBoots))
    check(not ns.Suspicious(2589, 13 * 200), "trade goods aren't judged against the vendor price")
    -- A Large Axe any vendor sells for 4s 84c, "selling" for 12g 74s
    local AXE = 12348
    ns.Item(AXE)
    ns.db.vendor[AXE] = { p = 484, t = time(), npc = "Oliver Dwor", zone = "Tirisfal Glades" }
    local whyAxe = ns.Suspicious(AXE, 127400)
    check(whyAxe and whyAxe:find("Any vendor sells this for 4s 84c", 1, true), "a vendor's axe at 263x the shop price is: " .. tostring(whyAxe))
    check(not ns.Suspicious(AXE, 484 * 6), "a few times the shop price isn't (people pay to skip the walk)")
    -- The rest of that list: 23c bracers at 40s, a 2s 84c cudgel at 31s
    ns.db.vendor[2853] = { p = 23, t = time() }
    check(ns.Suspicious(2853, 4000), "23c bracers at 40s are too")
    check(not ns.Suspicious(2853, 230), "but not at 2s 30c")
    ns.db.vendor[2853] = nil
    local P0 = ns.R().prices
    local savedAxe = P0[AXE]
    P0[AXE] = { p = 127400, q = 1, t = time(), b = true }
    ns.Fire("VENDOR_UPDATED")
    check(ns.ResaleValue(AXE) == nil, "and it's worth nothing as a resale price")
    local axeDeal = false
    for _, v in ipairs(ns.VendorDeals()) do if v.id == AXE then axeDeal = true end end
    check(not axeDeal, "so 'buy from a vendor, sell at auction' doesn't offer it")
    P0[AXE] = { p = 1500, q = 1, t = time(), b = true }
    ns.Fire("VENDOR_UPDATED")
    check(ns.ResaleValue(AXE), "a sane listing for it still counts")
    P0[AXE] = savedAxe
    ns.db.vendor[AXE] = nil
    ns.Fire("VENDOR_UPDATED")
    local P = ns.R().prices
    local savedJunk, savedLinen = P[JUNK], P[LINEN_ID]
    local d = ns.Today()
    -- Somebody lists the sword at 300g for days; then a normal one appears.
    P[JUNK] = { p = 1000, q = 1, t = time(), b = true, h = { [d - 3] = 3000000, [d - 2] = 3000000, [d - 1] = 3000000, [d] = 1000 } }
    ns.Fire("PLAYER_CHANGED")
    check(ns.PriceDoubt(JUNK) and ns.PriceDoubt(JUNK):find("gold"), "its 300g 'usual price' isn't trusted")
    local junkBargain = false
    for _, b in ipairs(ns.Bargains()) do if b.id == JUNK then junkBargain = true end end
    check(not junkBargain, "so the normal listing is NOT shown as a 99%-off bargain")
    -- A white item whose daily low swings wildly can't be compared either.
    P[LINEN_ID] = { p = 10, q = 50, t = time(), b = true, h = { [d - 3] = 5000, [d - 2] = 5000, [d - 1] = 5000, [d] = 10 } }
    ns.Fire("PLAYER_CHANGED")
    check(ns.PriceDoubt(LINEN_ID) and ns.PriceDoubt(LINEN_ID):find("swung"), "a price that swung 500x between days isn't trusted")
    local linenBargain = false
    for _, b in ipairs(ns.Bargains()) do if b.id == LINEN_ID then linenBargain = true end end
    check(not linenBargain, "and isn't called a bargain")
    -- Selling: never undercut a gold-trading listing.
    local dd = ns.DecidePrice({ { p = 3000000, q = 1 } }, { id = JUNK, step = 1, usual = 3000000, usualDays = 4, last = 3000000 })
    check(dd.ignored == 1 and not (dd.ok and dd.price and dd.price > 100000),
        "selling your gray: the 300g listing, usual and last price are all ignored: " .. tostring(dd.price))
    local plain = ns.DecidePrice({ { p = 3000000, q = 1 } }, { step = 1 })
    check(plain.reason == "undercut", "(without the item's ID the old behaviour stands)")
    P[JUNK], P[LINEN_ID] = savedJunk, savedLinen
    ns.Fire("PLAYER_CHANGED")
end

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
    check(M.settings.opened == ns.Options.cats.auction:GetID() and ns.UI.tab ~= "settings",
        "the Settings button opens the game's Options at Auction Forever")
    F.helpButton._scripts.OnClick(F.helpButton)
    check(not F.pane:IsShown(), "help uses the whole width")
    check(ns.UI.tab == "settings" and strip(F.list.rows[1].d.text) == "Selling", "the ? button opens tips and help, selling first")
    F.helpButton._scripts.OnClick(F.helpButton)
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
do
    local all = {}
    for _, l in ipairs(GameTooltip._lines) do all[#all + 1] = strip(l) end
    out("    " .. table.concat(all, "\n    "))
    local p = ns.AHPrice(2840)
    local stacks = 0
    for _, l in ipairs(all) do if l:find("stack of 20", 1, true) then stacks = stacks + 1 end end
    check(p and stacks >= 2 and table.concat(all, " "):find(strip(ns.Money(p * 20)), 1, true),
        "the auction price and profits get a total for the stack too: " .. stacks .. " stack lines")
    -- the bag slot under the mouse says how many, even for things a vendor won't buy
    local slot
    for i, b in ipairs(M.bags) do if b[1] == 2840 then slot = i end end
    if slot then
        GameTooltip.GetOwner = function() return { GetBagID = function() return 0 end, GetID = function() return slot end } end
        GameTooltip._lines = {}
        M.tooltipHook(GameTooltip, { id = 2840 })
        local n = M.bags[slot][2]
        local found = false
        for _, l in ipairs(GameTooltip._lines) do if strip(l):find("stack of " .. n, 1, true) then found = true end end
        check(n == 1 or found, "the stack size comes from the bag slot: " .. n)
        GameTooltip.GetOwner = nil
    end
end
-- Recipe items: which of your characters know it already
do
    local me = ns.Char()
    ns.db.chars["Tailor-PvP"] = { name = "Tailor-PvP", profs = { Tailoring = { skill = 150, max = 150, line = 197 } },
        recipes = { Tailoring = { [1] = { n = "Red Woolen Bag", o = 5763, y = 1, r = {} } } }, bags = {} }
    ns.db.chars["Stitch-PvP"] = { name = "Stitch-PvP", profs = { Tailoring = { skill = 75, max = 150, line = 197 } },
        recipes = { Tailoring = { [2] = { n = "Linen Bag", o = 4238, y = 1, r = {} } } }, bags = {} }
    ns.db.chars["Newbie-PvP"] = { name = "Newbie-PvP", profs = { Tailoring = { skill = 5, max = 75, line = 197 } }, recipes = {}, bags = {} }
    ns.Fire("RECIPES_UPDATED")
    GameTooltip._lines = {}
    M.tooltipHook(GameTooltip, { id = 5772 })
    local all = {}
    for _, l in ipairs(GameTooltip._lines) do all[#all + 1] = strip(l) end
    out("    " .. table.concat(all, "\n    "))
    local text = table.concat(all, " | ")
    check(text:find("Already known by: Tailor", 1, true) and text:find("Could learn it: Stitch (75)", 1, true)
        and text:find("Open Tailoring once on Newbie", 1, true) and not text:find("learn it: " .. (me.name or "?"), 1, true),
        "a pattern's tooltip says who knows it, who could learn it, and who to check")
    ns.db.chars["Tailor-PvP"], ns.db.chars["Stitch-PvP"], ns.db.chars["Newbie-PvP"] = nil, nil, nil
    ns.Fire("RECIPES_UPDATED")
end
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

-- Busy, "too fast", and answers that never come: wait it out, and never
-- post the same thing twice.
do
    local SF = ForeverGoldSellFrame
    local function btn() return strip(SF.post.text:GetText()) end
    M.market[2835] = { { 12, 500 } }
    ns.OpenSell(2835); M.advance(1)
    local n0 = #M.posted
    M.throttle = false
    ns.SellPost()
    check(#M.posted == n0 and ns.AHWaiting() and btn() == "Wait...", "busy: nothing is sent and Post says Wait")
    ns.SellPost()
    check(#M.posted == n0, "pressing again while it waits sends nothing")
    M.throttle = nil
    M.fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY"); M.advance(1.1)
    check(not ns.AHWaiting() and btn() == "Post", "once the game says it's ready, Post comes back")

    -- No answer, and nothing left the bags: it didn't go, so it can be tried again.
    M.postSilent = true
    ns.SellPost()
    check(#M.posted == n0 + 1 and ns.SellJob().state == "posting" and btn() == "Posting...", "posting...")
    ns.SellPost()
    check(#M.posted == n0 + 1, "a second click while posting sends nothing")
    M.advance(13)
    local job = ns.SellJob()
    check(job.state == "ready" and (job.message or ""):find("didn't go through"), "no answer, bags unchanged: it says it didn't go")

    -- No answer, but the stack left the bags: it went up, recorded once.
    local posts0 = #ns.db.posts
    ns.SellPost()
    M.bags[3][2] = 3 -- 20 of the 23 Rough Stone have gone
    M.advance(13)
    job = ns.SellJob()
    check(job.state == "done" and (job.message or ""):find("went up") and #ns.db.posts == posts0 + 1,
        "no answer, but the bags show it went: counted as posted")
    M.fire("AUCTION_HOUSE_AUCTION_CREATED"); M.advance(0.1)
    check(#ns.db.posts == posts0 + 1, "a late answer after that isn't counted twice")
    M.bags[3][2] = 23
    ns.CloseSell()

    -- Can't tell (the stack stays locked): stop and say so, then accept a late answer.
    ns.OpenSell(2835); M.advance(1)
    ns.SellPost()
    M.bags[3][4] = true
    M.advance(13 + 8)
    job = ns.SellJob()
    check(job.state == "error" and job.unsure and (job.message or ""):find("Check the Auctions tab"),
        "can't tell whether it went: stops and asks you to check")
    M.bags[3][4] = nil
    M.fire("AUCTION_HOUSE_AUCTION_CREATED"); M.advance(0.1)
    check(ns.SellJob().state == "done" and #ns.db.posts == posts0 + 2, "the late answer still counts it, once")
    ns.CloseSell()

    -- "You are doing that too fast": the post was dropped, so wait, then allow it again.
    ns.OpenSell(2835); M.advance(1)
    ns.SellPost()
    M.fire("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED"); M.advance(0.1)
    check(ns.SellJob().state == "ready" and ns.AHWaiting() and btn() == "Wait...", "too fast: back to ready, but Post waits")
    M.advance(4.2)
    check(not ns.AHWaiting() and btn() == "Post", "the wait runs out by itself")

    -- "The auction house is busy" while posting: the same.
    ns.SellPost()
    M.fire("AUCTION_HOUSE_SHOW_ERROR", Enum.AuctionHouseError.IsBusy); M.advance(0.1)
    check(ns.SellJob().state == "ready" and ns.AHWaiting(), "busy error while posting: checked, back to ready, waiting")
    M.advance(5)
    M.postSilent = nil
    ns.CloseSell()
end

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
-- Find Herbs / Find Minerals only turn on minimap tracking: no spot
M.player.x, M.player.y = 0.10, 0.90
for _, id in ipairs({ 2383, 2580 }) do
    M.fire("UNIT_SPELLCAST_SENT", "player", "", "cast", id)
    M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", id)
end
check(ns.GatherKind(2383) == nil and ns.GatherKind(2580) == nil and ns.GatherKind(2366) == "herb",
    "Find Herbs and Find Minerals aren't gathering; Herb Gathering is")
do -- each spot shows what it gives, not a generic leaf or pickaxe
    local copper = C_Item.GetItemIconByID(2770)
    check(copper and ns.NodeIcon({ k = "ore", n = "Copper Vein" }) == copper
        and ns.NodeIcon({ k = "ore", n = "Ooze Covered Copper Vein" }) == copper, "a copper vein shows Copper Ore")
    local herbIcon = C_Item.GetItemIconByID(2447)
    check(herbIcon and ns.NodeIcon({ k = "herb", n = "Peacebloom" }) == herbIcon
        and ns.NodeIcon({ k = "herb", n = "Wilted Peacebloom" }) == herbIcon, "a Peacebloom (and WoW Forever's Wilted Peacebloom) shows Peacebloom")
    check(ns.NodeIcon({ k = "herb" }) == ns.KINDS.herb.icon and ns.NodeIcon({ k = "herb", n = "Mystery Weed" }) == ns.KINDS.herb.icon
        and ns.NodeIcon({ k = "fish", n = "Fishing spot" }) == ns.KINDS.fish.icon, "unknown, nameless and fishing spots keep the kind's picture")
    -- an item the game hasn't loaded yet gives the question mark (2026-11-21:
    -- an ore vein showed as a "?" for good): the kind's picture until it loads
    local real = C_Item.GetItemIconByID
    C_Item.GetItemIconByID = function() return 134400 end
    check(ns.NodeIcon({ k = "ore", n = "Silver Vein" }) == ns.KINDS.ore.icon, "an ore not loaded yet shows the ore picture, not a question mark")
    C_Item.GetItemIconByID = real
    check(ns.NodeIcon({ k = "ore", n = "Silver Vein" }) == real(2775), "and its own picture once it has loaded")
end
do -- spots an older version saved for Find Herbs (no name) are cleared once
    ns.db.nodes[4343] = { { x = 0.1, y = 0.1, k = "herb", n = "", c = 3, t = time() },
        { x = 0.2, y = 0.2, k = "herb", n = "Peacebloom", c = 1, t = time() },
        { x = 0.3, y = 0.3, k = "ore", c = 1, t = time() } }
    ns.db.nodes[4344] = { { x = 0.5, y = 0.5, k = "herb", c = 1, t = time() } }
    ns.db.opts.findHerbsFixed = nil
    ns.InitDB()
    local left = ns.db.nodes[4343]
    check(#left == 2 and left[1].n == "Peacebloom" and left[2].k == "ore" and ns.db.nodes[4344] == nil and ns.db.opts.findHerbsFixed,
        "nameless herb spots are removed, real herbs and ore are kept")
    ns.db.nodes[4343] = nil
end
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
-- loot beam: a gold column on the game's waypoint marker while on a route
do
    local B = ns.Beam
    M.navDistance = 60
    M.update(0.05)
    local f = B.frame
    check(f and f:IsShown() and f.color[1] == 1 and f.color[3] < 0.2, "on a route: a bright gold beam on the next stop")
    check(f:GetParent() == WorldFrame, "drawn on the world's layer, under nameplates and the UI")
    check(#f.halos == 3 and #f.core == 8 and f.coreRGB[1] > f.color[1] - 0.001 and f.coreRGB[3] > f.color[3],
        "a core lifted towards white, inside three halos, each a run of segments")
    -- A settled reading: the tilt is smoothed over a few frames.
    local function settle(n)
        for _ = 1, n or 12 do M.update(0.05) end
    end
    local function show(label)
        return label .. string.format(" (tilt %.0f deg, %.0f px tall, lean %.1f, pool %.2f)",
            math.deg(f.tilt or 0), f.len or 0, f.dx or 0, f.flat or 0)
    end

    -- The camera is worked out from the marker: check the sums both ways.
    do
        local focal = 450 / (math.tan(math.rad(45)) * 0.75)
        for _, case in ipairs({ { 0.30, 0.2, 60 }, { 0.9, -0.3, 15 }, { -0.1, 0.05, 120 } }) do
            local tilt, bearing, dist = case[1], case[2], case[3]
            local sx, sy = B.Project(tilt, dist * math.cos(bearing), dist * math.sin(bearing), -1.9, 12, focal)
            local t2, b2 = B.SolveCamera(sx, sy, dist, -1.9, 12, focal)
            check(math.abs(t2 - tilt) < 0.01 and math.abs(b2 - bearing) < 0.01,
                string.format("the camera's tilt comes back from where the spot is on screen (%.2f -> %.2f)", tilt, t2))
        end
    end

    -- Put the marker where a camera at this tilt would see the spot.
    local eye = (IsMounted and IsMounted()) and 3.2 or 1.9
    local focal = 450 / (math.tan(math.rad(45)) * 0.75)
    local function seeAt(tilt, bearing, dist)
        local zoom = GetCameraZoom and GetCameraZoom() or 12
        local sx, sy = B.Project(tilt, dist * math.cos(bearing), dist * math.sin(bearing), -eye, zoom, focal)
        M.navX, M.navY, M.navDistance = 800 + sx, 450 + sy, dist
        settle()
    end
    -- Seen from the side: a tall, upright column.
    seeAt(0.12, 0, 25)
    local side = f.len
    check(math.abs(f.tilt - 0.12) < 0.03 and f.dy > 0 and math.abs(f.dx) < 1, show("from the side it stands up straight"))
    check(f.flat < 0.5, show("and its pool on the ground is a thin ellipse"))
    -- Zoomed right out: a spot just ahead, seen nearly side-on, then from above.
    GetCameraZoom = function() return 35 end
    seeAt(0.2, 0, 3)
    local level = f.len
    seeAt(1.2, 0, 3)
    check(math.abs(f.tilt - 1.2) < 0.03 and f.len < level * 0.7 and f.flat > 0.8,
        show("looking down on it from above, it's foreshortened over a round pool"
        .. string.format(" (%.0f px side-on)", level)))
    GetCameraZoom = nil
    -- Looking down, upright things lean outwards towards the sides.
    seeAt(0.9, -0.5, 15)
    local leftLean = f.dx
    seeAt(0.9, 0.5, 15)
    check(leftLean < -1 and f.dx > 1, show("on the left it leans left, on the right it leans right"
        .. string.format(" (%.1f / %.1f)", leftLean, f.dx)))
    -- Nearer parts look wider: looking down, the top is nearer than the foot.
    check(f.topW >= f.coreW, "looking down, its top is a touch wider than its foot")
    seeAt(0.12, 0, 25)
    M.navDistance = 60
    settle()
    local near = f.len
    M.navDistance = 300
    settle()
    check(f:IsShown() and f.len < near, "further away, a shorter beam")
    M.navDistance = 3000
    settle()
    check(f:IsShown() and f.len >= 40 and f.coreW >= 1.6, show("a long way off it still stands out, never a speck"))
    seeAt(0.3, 0, 6)
    check(f.len <= 900 * 0.45 + 0.01 and f.coreW <= 4.5, show("up close it stays slim, never filling the screen"))
    local y1 = select(5, f.motes[1]:GetPoint(1))
    M.advance(0.4); M.update(0.05)
    local y2 = select(5, f.motes[1]:GetPoint(1))
    check(#f.motes == 4 and y1 and y2 and y1 ~= y2, "motes of light drift up the shaft")
    M.navX, M.navY = nil, nil
    M.navOffscreen = true
    M.update(0.05)
    check(not f:IsShown(), "spot off screen: no beam")
    M.navOffscreen = nil
    M.navDistance = 2
    M.update(0.05)
    check(not f:IsShown(), "standing on the spot: the beam fades away")
    M.navDistance = 60
    ns.db.opts.lootBeam = false
    M.update(0.05)
    check(not f:IsShown(), "loot beams can be switched off")
    ns.db.opts.lootBeam = true
    M.update(0.05)
    check(f:IsShown(), "and back on")

    -- One part failing doesn't take the others down, is saved with where
    -- it failed, and is tried again later.
    local soft = B.parts[2]
    local realRun = soft.run
    local calls = 0
    soft.run = function() calls = calls + 1; error("boom") end
    local errsBefore = #ns.errors
    M.update(0.05)
    check(calls == 1 and #ns.errors == errsBefore + 1, "a failing part is caught")
    local saved = ns.db.errorLog and ns.db.errorLog[1]
    check(saved and saved.w == "loot-beam (on the object)" and saved.e:find("boom", 1, true) and saved.v == ns.VERSION
        and saved.e:find(":%d+:") and saved.s and saved.s ~= "", "and saved with the version and where it failed: " .. tostring(saved and saved.e))
    M.update(0.05)
    check(f:IsShown(), "the marker's beam keeps going")
    check(calls == 1, "the failing part waits before trying again")
    M.advance(31)
    M.update(0.05)
    check(calls == 2 and ns.db.errorLog[1].n == 2, "half a minute later it's tried again (same error counted, not repeated)")
    for _ = 1, 4 do M.advance(31); M.update(0.05) end
    local stuck = calls
    M.advance(31); M.update(0.05)
    check(calls == stuck and stuck == 5, "after 5 failures it stays off until /reload")
    soft.run, soft.fails, soft.off = realRun, nil, nil
    M.printed = M.printed or {}
    local printedBefore = #M.printed
    SlashCmdList.FOREVERGOLD("debug")
    local said = {}
    for i = printedBefore + 1, #M.printed do said[#said + 1] = strip(M.printed[i]) end
    local joined = table.concat(said, " / ")
    check(joined:find("saved errors", 1, true) and joined:find("loot-beam (on the object)  (x5): ", 1, true)
        and joined:find("boom", 1, true), "/gold debug shows the saved error, with how often")
    -- These were on purpose: not errors for the end-of-run count.
    for _ = 1, #ns.errors - errsBefore do table.remove(ns.errors, 1) end
    ns.db.errorLog = nil
end
ForeverGoldGuide.skip._scripts.OnClick(ForeverGoldGuide.skip)
WorldMapFrame.OnMapChanged(WorldMapFrame)
WorldMapFrame._scripts.OnShow(WorldMapFrame)
do
    local wp = ns.WorldMapPlot()
    check(wp and wp.usedMarks == 8 and wp.usedLines > 0, "world map: every spot and the route: " .. tostring(wp and wp.usedMarks))
    local mk = wp.marks[1]
    check(not mk.back:IsShown() and mk._mouse, "spot icons have no dark square behind them, and notice the mouse")
    GameTooltip._lines = {}
    mk._scripts.OnEnter(mk)
    local tipHead = strip(GameTooltip._lines[1] or "")
    check(mk.node and tipHead == mk.node.n and strip(GameTooltip._lines[2] or ""):find("gathered"),
        "hovering a spot on the map says what it is: " .. tipHead .. " / " .. strip(GameTooltip._lines[2] or ""))
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

    -- The map's gathering button and its filter
    local mb = ForeverGoldMapButton
    check(mb and mb:IsShown(), "the world map has a gathering button")
    check(mb.icon._texture == "Interface\\AddOns\\ForeverGold\\Icon" and mb.edge._texture == "Interface\\Minimap\\MiniMap-TrackingBorder",
        "it's round with a gold ring like the map's other buttons, showing Forever Gold's logo")
    check(toggles["kind-herb"] and toggles["kind-ore"] and toggles["kind-fish"] and toggles["kind-chest"] and toggles.route,
        "OpenMap's menu has a switch per kind and the route line (each can be starred onto its bar)")
    mb:Click()
    local menu = ForeverGoldMapFilter
    check(menu and menu:IsShown() and #menu.rows == 7, "clicking it opens the filter")
    local all, ores = wp.usedMarks, 0
    for _, n in ipairs(ns.db.nodes[1413]) do if n.k == "ore" then ores = ores + 1 end end
    menu.rows[3]:Click() -- Ore
    check(ores > 0 and wp.usedMarks == all - ores and not ns.MapKindOn("ore") and toggles["kind-ore"].get() == false,
        "untick Ore: only the ore spots go: " .. wp.usedMarks .. " of " .. all)
    toggles["kind-ore"].set(true)
    check(wp.usedMarks == all and ns.MapKindOn("ore") and menu.rows[3].get(), "OpenMap's switch brings them back, and the menu agrees")
    menu.rows[6]:Click() -- Route line
    check(wp.usedLines == 0 and wp.usedMarks == all, "untick Route line: the line goes, the spots stay")
    menu.rows[6]:Click()
    check(wp.usedLines > 0, "and back")
    mb:Click("RightButton")
    check(wp.usedMarks == 0 and ns.db.opts.worldMapSpots == false and toggles.spots.get() == false,
        "right-click: everything off at once")
    mb:Click("RightButton")
    check(wp.usedMarks == all, "right-click again: back on")
    -- A character without Mining doesn't see veins
    M.lostProf = "Mining"
    M.fire("SKILL_LINES_CHANGED")
    M.advance(1.1)
    check(not ns.CanGather("ore") and ns.CanGather("herb") and ns.CanGather("chest")
        and wp.usedMarks == all - ores, "no Mining: the veins leave the map, the rest stay: " .. wp.usedMarks .. " of " .. all)
    ns.db.opts.onlyMyProfs = false
    ns.RedrawWorldMap()
    check(wp.usedMarks == all, "the setting off: every spot again")
    ns.db.opts.onlyMyProfs = true
    M.lostProf = nil
    M.fire("SKILL_LINES_CHANGED")
    M.advance(1.1)
    check(wp.usedMarks == all and ns.CanGather("ore"), "learn Mining: the veins come back")
    mb:Click()
    check(not menu:IsShown(), "clicking the button again closes the filter")
    -- Other addons' round buttons (Krowi_WorldMapButtons) down the top left: ours goes under them
    local function krowiButton(shown)
        local b = CreateFrame("Button", nil, WorldMapFrame)
        b:SetSize(32, 32)
        if not shown then b:Hide() end
        return b
    end
    local krowi = { AnchorPoint = "TOPLEFT", XOffset = 3, YOffset = 0,
        Buttons = { krowiButton(true), krowiButton(true), krowiButton(false), krowiButton(true) } }
    function krowi.SetPoints() end
    LibStub = { GetLibrary = function(_, name, silent) if name == "Krowi_WorldMapButtons-1.4" then return krowi end end }
    ns.RedrawWorldMap()
    local p, _, rp, bx, by = mb:GetPoint()
    check(p == "TOPLEFT" and rp == "TOPLEFT" and bx == 4 and by == -97,
        "with three round buttons on the left, ours sits fourth in their column: " .. tostring(p) .. " " .. tostring(bx) .. "," .. tostring(by))
    mb:Click()
    local mp, mrel, mrp = menu:GetPoint()
    check(menu:IsShown() and mp == "TOPLEFT" and mrel == mb and mrp == "TOPRIGHT", "its filter opens to the right of it")
    mb:Click()
    krowi.Buttons[3]:Show()
    krowi.SetPoints()
    p, _, rp, bx, by = mb:GetPoint()
    check(by == -129, "another round button shows: ours moves down one: " .. tostring(by))
    LibStub = nil
    ns.RedrawWorldMap()
    p = mb:GetPoint()
    check(p == "TOPRIGHT", "without them it goes back to the top right")
    mb:Click()
    mp = menu:GetPoint()
    check(mp == "TOPRIGHT", "and its filter drops down under it")
    mb:Click()
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

-- No route: a white beam on the nearest recorded spot, but never at the
-- cost of something you're tracking yourself.
do
    local B = ns.Beam
    M.player.x, M.player.y = 0.50, 0.505
    M.update(1.1)
    check(B.own and M.waypoint and M.waypoint.uiMapID == 1413 and M.tracking == "waypoint",
        "no route: the nearest spot gets the map pin")
    check(B.frame:IsShown() and B.frame.color == B.COLORS.recorded and B.frame.color[1] > 0.9 and B.frame.color[2] > 0.9,
        "and a white beam")
    local first = B.own.node
    M.player.x, M.player.y = first.x, first.y
    M.update(1.1)
    check(B.own and B.own.node ~= first, "after visiting a spot, the beam moves on to the next nearest")
    M.tracking = "quest"
    M.update(1.1)
    check(B.own == nil and M.waypoint == nil and M.tracking == "quest", "tracking a quest: the beam lets go and tidies its pin away")
    local sets = M.waypointSets
    M.update(1.1)
    check(M.waypointSets == sets and not B.frame:IsShown(), "and leaves the quest alone")
    M.tracking = nil
    M.update(1.1)
    check(B.own ~= nil, "untrack the quest: the beam comes back")
    local mine = UiMapPoint.CreateFromCoordinates(1413, 0.9, 0.1)
    C_Map.SetUserWaypoint(mine)
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    M.update(1.1)
    check(B.own == nil and M.waypoint == mine, "a pin you placed yourself is never moved")
    C_Map.ClearUserWaypoint()
    ns.db.opts.nearestBeam = false
    M.update(1.1)
    check(B.own == nil and M.waypoint == nil, "the white beam can be switched off on its own")
    ns.db.opts.nearestBeam = true
    M.update(1.1)
    -- a route takes over the pin from the white beam
    local r2 = ns.BuildRoute(1413, { ore = true, herb = true })
    local p2 = r2 and r2.pts[r2.i]
    check(p2 and B.own == nil and ns.Beam.TrackingPin(1413, p2.x, p2.y), "starting a route moves the pin to its first stop")
    M.update(1.1)
    check(B.frame:IsShown() and B.frame.color[3] < 0.2, "and the beam turns gold")
    ns.StopRoute()
    C_Map.ClearUserWaypoint()
end

-- Things not recorded yet: the beam hangs off what the game's Interact Key
-- has picked out in front of you, coloured by what it is to you.
do
    local B = ns.Beam
    check(M.cvars.softTargetInteract == "3" and M.cvars.SoftTargetIconGameObject == "1"
        and M.cvars.SoftTargetNameplateInteract == "1" and ns.db.beamCVars and ns.db.beamCVars.softTargetInteract == "1",
        "the game's Interact Key and object icons are switched on, the old settings kept")
    M.player.x, M.player.y = 0.12, 0.88 -- nowhere near a recorded spot
    M.units.softinteract = { guid = "GameObject-0-1-2-3-1731-0001", name = "Copper Vein" }
    -- Its nameplate where a camera tilted down a little would see the top of a vein 6 yards ahead, a bit right.
    local focal = 450 / (math.tan(math.rad(45)) * 0.75)
    local zoom = GetCameraZoom and GetCameraZoom() or 12
    local ptx, pty = B.Project(0.5, 6 * math.cos(0.3), 6 * math.sin(0.3), 1.7 - 1.9, zoom, focal)
    local gx, gy = B.Project(0.5, 6 * math.cos(0.3), 6 * math.sin(0.3), -1.9, zoom, focal)
    M.softPlate.GetCenter = function() return 800 + ptx, 450 + pty + 8 end
    M.softPlate.GetBottom = function() return 450 + pty end
    for _ = 1, 20 do M.update(0.05) end -- the tilt settles
    local f = B.softFrame
    check(f and f:IsShown() and f.color == B.COLORS.new and B.softKind == "new", "an unrecorded vein in front of you: a light blue beam")
    local _, _, srp, sox, soy = f:GetPoint()
    check(srp == "BOTTOM" and soy and math.abs(sox - (gx - ptx)) < 1.5 and math.abs(soy - (gy - pty)) < 1.5 and soy < -3,
        string.format("it stands on the ground under the vein, not on its nameplate up top: %.1f,%.1f (ground %.1f,%.1f)",
            sox or 0, soy or 0, gx - ptx, gy - pty))
    M.units.softinteract = { guid = "GameObject-0-1-2-3-2041-0005", name = "Kingsblood" }
    M.update(0.3)
    check(f:IsShown() and B.softKind == "new", "a herb you've never picked is recognised too")
    M.herbalism = false
    M.fire("SKILL_LINES_CHANGED")
    M.advance(1.1)
    M.update(0.3)
    check(not f:IsShown(), "without Herbalism, no beam on a herb")
    M.herbalism = nil
    M.fire("SKILL_LINES_CHANGED")
    M.advance(1.1)
    M.update(0.3)
    check(f:IsShown(), "with it, the beam is back")
    local ore
    for _, n in ipairs(ns.db.nodes[1413]) do if n.k == "ore" and not ore then ore = n end end
    M.player.x, M.player.y = ore.x, ore.y + 0.0005
    M.units.softinteract = { guid = "GameObject-0-1-2-3-1731-0002", name = ore.n or "Copper Vein" }
    M.update(0.3)
    check(f:IsShown() and f.color == B.COLORS.recorded and B.softNode == ore, "a recorded spot: white")
    local r = ns.BuildRoute(1413, { ore = true, herb = true })
    M.update(0.3)
    check(r and f:IsShown() and f.color == B.COLORS.route and B.softKind == "route", "a stop on the route you're running: gold")
    if B.softNode == ns.route.pts[ns.route.i] then
        check(not (B.frame and B.frame:IsShown()), "the waypoint beam steps aside for the one on the object itself")
    end
    ns.StopRoute()
    C_Map.ClearUserWaypoint()
    M.units.softinteract = { guid = "GameObject-0-1-2-3-99-0003", name = "Mailbox" }
    M.update(0.3)
    check(not f:IsShown(), "a mailbox isn't gatherable: no beam")
    M.units.softinteract = { guid = "Creature-0-1-2-3-4-0004", name = "Copper Vein" }
    M.update(0.3)
    check(not f:IsShown(), "only objects, never a creature that happens to share the name")
    M.units.softinteract = { guid = "GameObject-0-1-2-3-1731-0001", name = "Copper Vein" }
    ns.db.opts.beamUnrecorded = false
    M.update(1.1)
    check(not f:IsShown() and M.cvars.softTargetInteract == "1" and M.cvars.SoftTargetIconGameObject == "0"
        and ns.db.beamCVars == nil, "switching it off hides it and puts the game's settings back")
    ns.db.opts.beamUnrecorded = true
    M.update(1.1)
    check(M.cvars.softTargetInteract == "3" and f:IsShown(), "and on again")
    -- A nameplate the game won't let anyone measure (2026-11-20): the beam
    -- still stands on it, from an estimate, and nothing errors
    local center, errsBefore = M.softPlate.GetCenter, #(ns.db.errorLog or {})
    M.softPlate.GetCenter = function()
        error("NamePlate2:GetCenter(): Action[FrameMeasurement] failed because[Can't measure restricted regions]")
    end
    M.update(0.3)
    local _, anchor = f:GetPoint()
    check(f:IsShown() and anchor == M.softPlate and #(ns.db.errorLog or {}) == errsBefore,
        "a nameplate that can't be measured: the beam still stands on it, no error")
    M.softPlate.GetCenter = center
    M.update(0.3)
    check(f:IsShown(), "and still does once it can be measured again")
    M.units.softinteract = nil
    M.update(1.1)
    check(not f:IsShown(), "nothing picked out: no beam")
    C_Map.ClearUserWaypoint()
end

-- Chests: opening one records where it stood; opening anything else doesn't.
do
    local list = ns.db.nodes[1413]
    local n0 = #list
    M.player.x, M.player.y = 0.31, 0.77
    M.fire("UNIT_SPELLCAST_SENT", "player", "Battered Chest", "Cast-1", 3365)
    M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 3365)
    local last = list[#list]
    check(#list == n0 + 1 and last.k == "chest" and last.n == "Battered Chest", "opening a chest records a chest spot")
    M.player.x, M.player.y = 0.61, 0.27
    M.fire("UNIT_SPELLCAST_SENT", "player", "Supply Crate", "Cast-2", 3365)
    M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 3365)
    check(#list == n0 + 1, "opening a quest crate isn't a chest")
    local z
    for _, zz in ipairs(ns.NodeZones()) do if zz.map == 1413 then z = zz end end
    check(z and z.chest == 1 and ns.ZoneSummary(z):find("1 chest spot"), "zones count their chest spots: " .. (z and ns.ZoneSummary(z) or "?"))
    local m = ns.MatchingNodes(1413, { chest = true })
    check(#m == 1, "a route can be just the chest spots")
    table.remove(list) -- leave the zone as the rest of the run expects it
    ns.Fire("NODES_UPDATED")
end

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

out("== farming: rankings, suggestions, a mob route, luck and the dashboard")
do
    local spotX = { 0.40, 0.43, 0.46, 0.49, 0.52 }
    local serial = 0
    local function killCoyote(drop)
        serial = serial + 1
        M.player.x, M.player.y = spotX[(serial % 5) + 1], 0.30 + (serial % 3) * 0.03
        local guid = string.format("Creature-0-1-2-3-99-%08X", 0xC000 + serial)
        M.units.target = { guid = guid, name = "Coyote", dead = true, level = 11 }
        M.fire("UNIT_HEALTH", "target")
        M.units = {}
        M.loot = { { type = 2, src = guid } }
        if drop then
            table.insert(M.loot, 1, { type = 1, id = 2589, qty = 1, quality = 1, src = guid })
        end
        M.fire("LOOT_READY", true)
        M.player.money = M.player.money + 20; M.fire("PLAYER_MONEY")
        for i = 1, #M.loot do M.fire("LOOT_SLOT_CLEARED", i) end
        M.fire("LOOT_CLOSED")
        M.advance(30)
        M.update(6)
    end
    ns.TrackerStart()
    for _ = 1, 22 do killCoyote(true) end
    local lm = ns.db.life.mobs.Coyote or {}
    lm.z, lm.items = lm.z or {}, lm.items or {}
    check(lm.k == 22 and lm.lo == 11 and lm.hi == 11 and lm.z["The Barrens"] == 22 and lm.coin == 440
        and lm.items[2589] == 22, "all-time: kills, level, zone, coin and items looted")
    check(lm.gapN and lm.gapN >= 20 and lm.spots and lm.spots[1413] and #lm.spots[1413] >= 3,
        "how fast you kill them and where: " .. tostring(lm.gapN) .. " gaps, " .. #(lm.spots[1413] or {}) .. " spots")
    local tr = ns.Tracker()
    check(#tr.tl >= 8, "a point on the session's gold line every minute: " .. #tr.tl)
    local today = ns.db.farmDays[ns.FarmDayKey()]
    check(today and today.s >= 600 and today.v > 0 and today.k >= 21, "today's farming is booked: "
        .. tostring(today and today.s) .. "s, " .. tostring(today and today.v) .. ", " .. tostring(today and today.k) .. " kills")
    check((ns.db.farmFrom.kills or 0) > 0 and (ns.db.farmFrom.coin or 0) >= 400, "and where it came from")
    local s = ns.TrackerSummary()
    check(s.vendorTotal >= 440 + 22 * 13 and s.auctionTotal >= 440 and s.vendorPerHour and s.auctionPerHour,
        "vendor or auction, total and per hour: " .. s.vendorTotal .. " / " .. s.auctionTotal)
    check(s.from.kills > 0 and s.from.coin == 440, "this session's gold by where it came from")

    -- Rankings and suggestions
    local ranked = ns.MobRanking()
    local coyote
    for _, e in ipairs(ranked) do if e.name == "Coyote" then coyote = e end end
    check(coyote and coyote.k == 22 and coyote.speedMeasured and coyote.killsHr > 100 and coyote.killsHr < 130
        and coyote.best and coyote.best.id == 2589 and coyote.best.rate == 1 and coyote.where == "The Barrens",
        "Coyote ranked: per kill, kills an hour measured, best drop, where: "
        .. (coyote and (math.floor(coyote.perKill) .. "c, " .. math.floor(coyote.killsHr) .. "/hr") or "missing"))
    check(not (function() for _, e in ipairs(ranked) do if e.name == "Plainstrider" then return true end end end)(),
        "a mob killed once isn't ranked yet")
    local sugg = ns.FarmSuggestions()
    check(sugg[1] and sugg[1].name == "Coyote" and sugg[1].perHour > 2000, "suggested: farm Coyotes, ~" .. tostring(sugg[1] and math.floor(sugg[1].perHour)))
    M.player.level = 60
    check(#ns.FarmSuggestions() == 0, "not suggested to a character far above them")
    M.player.level = 25

    -- A route through where you killed them
    local plan = ns.PlanMobRoute("Coyote")
    check(plan and plan.n >= 3 and plan.map == 1413 and plan.pts[1].k == "mob" and plan.pts[1].n == "Coyote",
        "a loop through your kill spots: " .. tostring(plan and plan.n))
    local started = ns.StartMobRoute("Coyote")
    check(started and ns.route == started and ns.route.mob == "Coyote" and ns.RouteStatus().name == "Coyote",
        "the route starts, and the guide says what to look for")
    ns.StopRoute()
    C_Map.ClearUserWaypoint()
    check(ns.PlanMobRoute("Nobody") == nil, "no spots: no route")

    -- Save, then a short unlucky session: luck against your own rates
    ns.StopSession()
    check(ns.FarmUsualPerHour() and ns.FarmUsualPerHour() > 0, "your usual gold an hour")
    ns.TrackerStart()
    for _ = 1, 6 do killCoyote(false) end
    local luck = ns.FarmLuck()
    check(luck and luck.pct < -0.3 and luck.kills == 6 and luck.items[1] and luck.items[1].id == 2589
        and luck.items[1].got == 0 and luck.items[1].expected > 5, "six Coyotes and no linen: unlucky, about 6 expected")

    -- Level times
    M.advance(300)
    M.fire("PLAYER_LEVEL_UP", 26)
    M.player.level = 26
    local lv = ns.LevelTimes()
    check(lv[1] and lv[1].level == 25 and lv[1].secs > 0 and lv[1].partial, "a level's time is kept when you level: " .. tostring(lv[1] and lv[1].secs))
    M.player.level = 25

    -- Days farmed
    local fd = ns.FarmDays()
    check(fd.streak >= 1 and fd.best and fd.best.v > 0, "days in a row and your best day")

    -- The dashboard
    ns.ShowTab("farming")
    local list = ForeverGoldFrame.list
    local function has(kind)
        for i = 1, list.count do if list.rows[i].d.type == kind then return true end end
        return false
    end
    dumpRows("Farming: this session", 50)
    check(has("cards") and has("graph") and has("segbar") and has("meter") and has("heat") and not ForeverGoldFrame.pane:IsShown(),
        "this session: stat cards, the gold line, where it came from, luck, the days, full width")
    pokeRows()
    local function toolbarClick(text)
        for _, b in ipairs(ForeverGoldFrame.toolbar.buttons) do
            if b:IsShown() and b.text:GetText() == text then b._scripts.OnClick(b) return true end
        end
        return false
    end
    check(toolbarClick("Overall"), "Overall button")
    dumpRows("Farming: overall", 40)
    check(has("cards") and has("graph") and has("heat"), "overall: cards, gold over time, days")
    pokeRows()
    check(toolbarClick("Mobs"), "Mobs button")
    dumpRows("Farming: mobs", 10)
    local first
    for i = 1, list.count do
        local d = list.rows[i].d
        if not d.type and d.key == "mob:Coyote" then first = d end
    end
    check(first and first.bar == 1 and ForeverGoldFrame.pane:IsShown(), "Mobs: Coyote ranked first, with the details pane")
    local det = first and ns.FarmMobDetail(coyote)
    check(det and det.action and det.action.label:find("Route", 1, true), "its details offer a route")
    toolbarClick("Outside dungeons")
    toolbarClick("Skip green+")
    pokeRows()
    toolbarClick("This session")
    -- Make > Farm and To do suggest it too
    local realUsual = ns.FarmUsualPerHour
    local function farmListed()
        ns.ShowTab("farm")
        for i = 1, list.count do
            if list.rows[i].d.title == "Kill Coyote" then return true end
        end
        return false
    end
    ns.FarmUsualPerHour = function() return 1000 end
    check(farmListed(), "Make > Farm lists Coyotes under your own kills")
    ns.FarmUsualPerHour = function() return 1000000 end
    check(not farmListed(), "but not when your usual farming pays far better")
    ns.FarmUsualPerHour = realUsual
    -- The session window shows vendor against auction
    TW.tabs.loot._scripts.OnClick(TW.tabs.loot)
    local vend = false
    for i = 1, TW.list.count do
        if (TW.list.rows[i].d.title or ""):find("Vendor it all", 1, true) then vend = true end
    end
    check(vend, "Farming Session > Loot: vendor it all vs auction it")
    TW.tabs.kills._scripts.OnClick(TW.tabs.kills)
    TW.stats._scripts.OnClick(TW.stats)
    check(ForeverGoldFrame:IsShown(), "Stats opens the dashboard")
    ns.TrackerReset()
    ns.TrackerPause(true)
    ns.db.track[ns.charKey] = nil
end

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

    -- The scrollbar drags.
    local bar = list.bar
    list.offset = 0; list:Apply()
    check(bar:IsShown() and bar.trackH > bar.size, "the settings list shows a scrollbar")
    M.cursorY = 600
    bar.thumb._scripts.OnMouseDown(bar.thumb, "LeftButton")
    check(bar.dragging, "pressing the thumb starts a drag")
    local function drag()
        bar.thumb._scripts.OnUpdate(bar.thumb, 0.1)
    end
    M.cursorY = 550
    drag()
    local dragged = list.offset
    check(dragged > 0, "dragging the thumb down scrolls the list: " .. tostring(dragged))
    M.cursorY = 525
    drag()
    check(list.offset > dragged, "dragging further scrolls further")
    M.cursorY = 900
    drag()
    check(list.offset == 0, "dragging past the top stops at the top")
    bar.thumb._scripts.OnMouseUp(bar.thumb, "LeftButton")
    M.cursorY = 0
    M.update(0.1)
    check(list.offset == 0 and not bar.dragging, "letting go ends the drag")
    local maxOff = list.contentH - list.viewH
    M.cursorY = 700 - bar.trackH + 2 -- the mock puts the track's top at 700
    bar.track._scripts.OnMouseDown(bar.track, "LeftButton")
    check(math.abs(list.offset - maxOff) < 0.01, "clicking the bottom of the track jumps to the end")
    bar.track._scripts.OnMouseUp(bar.track, "LeftButton")
    M.cursorY = 700 - bar.trackH / 2
    bar.track._scripts.OnMouseDown(bar.track, "LeftButton")
    bar.track._scripts.OnMouseUp(bar.track, "LeftButton")
    check(math.abs(list.offset - maxOff / 2) < maxOff * 0.05, "clicking the middle of the track jumps to the middle")
    M.cursorY = nil
    list.offset = 0; list:Apply()

    -- Long lines wrap and the row grows, instead of being cut off.
    local tall, beam
    for i = 1, list.count do
        local d = list.rows[i].d
        if d.title and strip(d.title):find("Beam on herbs") then
            beam = list.hs[i]
        end
    end
    check(beam and beam > 42, "a long settings line wraps onto a taller row: " .. tostring(beam))

    -- Mailbox settings
    check(ns.db.opts.mailReserve == 0 and ns.db.opts.mailReserveFree, "no gold is held back from mail by default")
    local mailRows = {}
    local inMail = false
    for i = 1, list.count do
        local d = list.rows[i].d
        if d.type == "header" then
            inMail = d.text == "Mailbox"
        elseif inMail and not d.type then
            mailRows[#mailRows + 1] = d
        end
    end
    check(#mailRows == 5, "Settings has a Mailbox section with 5 switches: " .. #mailRows)
    local function mailRow(word)
        for _, d in ipairs(mailRows) do
            if strip(d.title):find(word) then return d end
        end
    end
    local r = mailRow("Ask to send")
    check(r and strip(r.title):find("%[on%]"), "the mailbox ask switch shows on")
    r.onClick(r)
    check(ns.db.opts.mailPrompt == false, "the ask switch turns off from Settings")
    ns.db.opts.mailPrompt = true
    r = mailRow("by itself")
    r.onClick(r)
    check(ns.db.opts.mailAuto == true, "auto-send turns on from Settings")
    ns.db.opts.mailAuto = false
    r = mailRow("spare gold")
    r.onClick(r)
    check(ns.db.opts.mailGold == true, "sending spare gold turns on from Settings")
    ns.db.opts.mailGold = false
    r = mailRow("Keep at least")
    check(r and strip(r.title):find("nothing"), "the reserve shows nothing kept")
    r.onClick(r)
    check(ns.db.opts.mailReserve == 10000, "clicking the reserve steps to 1g")
    ns.db.opts.mailReserve = 0
    r = mailRow("mailbox window")
    r.onClick(r)
    check(ns.db.opts.mailBlizzard == true, "switching to the game's mailbox from Settings")
    ns.ShowTab("tips")
    for i = 1, list.count do
        local d = list.rows[i].d
        if d.title and strip(d.title):find("mailbox window") then d.onClick(d) end
    end
    check(not ns.db.opts.mailBlizzard, "and back to Forever Gold's")
    ns.RefreshUI(true)
end
do
    -- An old saved 5g reserve (the old default) is cleared once; your own stays.
    local saved = ns.db.opts
    saved.mailReserve, saved.mailReserveFree = 50000, nil
    ns.InitDB()
    check(ns.db.opts.mailReserve == 0, "the old 5g default reserve is cleared")
    ns.db.opts.mailReserve = 50000
    ns.InitDB()
    check(ns.db.opts.mailReserve == 50000, "a 5g reserve you set again yourself is kept")
    ns.db.opts.mailReserve = 0
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
IsShiftKeyDown = function() return M.shift end

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

    -- "Vendor pays" only for a proven buyout: a browse's lowest price can be a bid.
    local function dealText(name)
        A.Search(name); M.advance(5)
        A.Refresh()
        for _, row in ipairs(F.browse.results.data) do
            if row.r and ns.ItemName(row.r.id) == name then
                return strip(row.cells.vs or ""), row.hint or ""
            end
        end
    end
    local boots = dealText("Cheap Mail Boots")
    check(boots and boots:find("^Vendor pays"), "a real buyout under vendor price is called a deal: " .. tostring(boots))
    local sword, swordHint = dealText("Worn Junk Sword")
    check(sword == "Maybe - check buyouts" and swordHint:find("bid"),
        "a lowest price that's only a bid isn't called a deal: " .. tostring(sword))

    -- A gray item listed for a fortune (gold changing hands) is left out of the list
    local junkEntry
    for _, a in ipairs(M.auctions) do if a[1] == 12345 then junkEntry = a end end
    local junkPrice = junkEntry[2]
    junkEntry[2] = 3000000
    local hiddenSword = dealText("Worn Junk Sword")
    check(hiddenSword == nil and #F.browse.results.data == 0, "a 300g gray sword isn't listed")
    check(strip(F.browse.state:GetText()):find("1 suspicious hidden", 1, true),
        "the count says it was hidden: " .. strip(F.browse.state:GetText()))
    check((F.browse.results.empty:GetText() or ""):find("gold changing hands", 1, true), "and the empty list says why")
    junkEntry[2] = junkPrice
    check(dealText("Worn Junk Sword") ~= nil and not strip(F.browse.state:GetText()):find("hidden", 1, true),
        "at a normal price it's back, with no hidden note")

    -- Ctrl+click gear: try it on in the dressing room
    dealText("Cheap Mail Boots")
    local bootsRow
    for _, row in ipairs(F.browse.results.rows) do
        if row.d and row.d.id == 12346 then bootsRow = row end
    end
    local dressedBefore, selBefore = #M.dressed, F.browse.results.selected
    M.ctrl = true
    if bootsRow then bootsRow:Click() end
    check(bootsRow and #M.dressed == dressedBefore + 1 and tostring(M.dressed[#M.dressed]):find("item:12346", 1, true)
        and F.browse.results.selected == selBefore, "Ctrl+click on boots tries them on, and doesn't open the listing")
    M.ctrl = false
    check(not ns.TryDressUp(12346), "without Ctrl nothing is tried on")
    M.ctrl = true
    check(not ns.TryDressUp(2589) and #M.dressed == dressedBefore + 1, "Ctrl+click on cloth falls through to the normal click")
    M.ctrl = false

    -- A category
    A.openCategory = nil
    F.browse.cats.onClick({ name = "Trade Goods", top = 2, filters = { { classID = 7 } } }); M.advance(5)
    check(M.lastBrowse.itemClassFilters and M.lastBrowse.itemClassFilters[1].classID == 7 and A.openCategory == 2,
        "picking a category searches it and opens its subcategories")
    F.browse.search:SetText("")
    M.lastBrowse = nil
    F.browse.go:Click(); M.advance(5)
    check(M.lastBrowse and M.lastBrowse.searchString == "" and M.lastBrowse.itemClassFilters
        and M.lastBrowse.itemClassFilters[1].classID == 7, "Search with an empty box lists everything in the picked category")
    A.Refresh()
    check(strip(F.browse.state:GetText()):find("in Trade Goods"), "and says which category: " .. strip(F.browse.state:GetText()))
    F.browse.search:SetText("bar")
    F.browse.go:Click(); M.advance(5)
    check(M.lastBrowse.searchString == "bar" and M.lastBrowse.itemClassFilters, "typed words search inside the category")
    F.browse.cats.onClick(A.BUY.category); M.advance(5)
    check(A.BUY.category == nil and not M.lastBrowse.itemClassFilters and A.openCategory == nil,
        "clicking the picked category again searches everything")
    A.Refresh()
    check(F.browse.cats.selected == nil, "and no category is highlighted")
    F.browse.search:SetText("")

    -- Deals
    local keepMin = ns.db.opts.dealMin
    ns.db.opts.dealMin = 1
    ns.Fire("PRICES_UPDATED")
    A.ShowDeals()
    local flips = #ns.VendorFlips() + #ns.Bargains()
    check(A.BUY.deals and flips > 0 and #A.BUY.results == flips, "Deals lists the bargains from the last scan: " .. #A.BUY.results)
    A.Refresh()
    check(F.browse.results.rows[1]:IsShown() and strip(F.browse.results.rows[1].cells[5]:GetText()) ~= "", "each deal says why")
    -- the Deals tab, searching inside Deals, and clicking Deals again
    A.SetTab("sell")
    F.tabs.deals:Click()
    check(A.tab == "browse" and F.browse:IsShown() and A.BUY.category == "deals" and #A.BUY.results == flips
        and F.tabs.deals.on and not F.tabs.browse.on, "a Deals tab after Auctions opens the deals")
    local first = A.BUY.results[1]
    local firstName = ns.Item(first.id).n
    F.browse.search:SetText(firstName)
    local browsesBefore = M.browseCount or 0
    F.browse.go:Click()
    check(A.BUY.category == "deals" and #A.BUY.results >= 1 and A.BUY.results[1].id == first.id
        and #A.BUY.results < flips + 1 and (M.browseCount or 0) == browsesBefore,
        "Search with Deals picked looks through the deals and stays in Deals: " .. #A.BUY.results .. " for " .. firstName)
    F.browse.search:SetText("")
    local dealsRow
    for _, c in ipairs(F.browse.cats.data or {}) do if c.deals then dealsRow = c end end
    F.browse.cats.onClick(dealsRow or { deals = true })
    A.Refresh()
    check(A.BUY.category == nil and not A.BUY.deals and #A.BUY.results == 0 and F.browse.cats.selected == nil
        and F.tabs.browse.on and not F.tabs.deals.on, "clicking Deals again deselects it")
    F.browse.cats.onClick(dealsRow or { deals = true })
    check(A.BUY.category == "deals", "and once more picks it again")
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

    -- Never stuck on "Buying...": a refusal before the call returns, no
    -- answer at all, and an answer that comes late.
    M.market[12346] = { { 300, 1 }, { 320, 1 } }
    A.OpenItem({ id = 12346 }); M.advance(2)
    M.buyError = Enum.AuctionHouseError.DatabaseError
    F.browse.listings.onClick({ l = A.BUY.listings[1] })
    F.browse.box.buy:Click(); M.advance(0.5)
    A.Refresh()
    check(A.BUY.buy == nil and strip(A.BUY.message or ""):find("Internal auction error"),
        "gear: a refusal that comes before PlaceBid returns ends the buy, in the game's words: " .. strip(A.BUY.message or ""))
    check(not strip(F.browse.box.buy.text:GetText()):find("Buying"), "and the button isn't stuck on Buying")
    M.market[2840] = { { 90, 150 } }
    A.OpenItem({ id = 2840 }); M.advance(2)
    A.BUY.qty = 10
    M.buyError = nil
    A.Buy(); M.advance(1)
    M.buyError = Enum.AuctionHouseError.DatabaseError
    A.Buy(); M.advance(0.5)
    check(A.BUY.buy == nil and strip(A.BUY.message or ""):find("Internal auction error"),
        "stackable: a refusal at confirm ends the buy too")
    M.buyError = nil
    -- an error while the price is being asked for
    A.Buy()
    M.fire("AUCTION_HOUSE_SHOW_ERROR", Enum.AuctionHouseError.IsBusy)
    check(A.BUY.buy == nil and M.quoteFor == nil and strip(A.BUY.message or ""):find("busy"),
        "an error while asking the price ends it and drops the quote")
    M.advance(1)
    -- no answer at all
    M.buySilent = true
    A.OpenItem({ id = 12346 }); M.advance(2)
    local bidsBefore = #M.bids
    F.browse.listings.onClick({ l = A.BUY.listings[1] })
    F.browse.box.buy:Click()
    check(A.BUY.buy and A.BUY.buy.state == "buying", "waiting for the auction house")
    M.advance(A.BUY_WAIT + 1)
    check(A.BUY.buy == nil and strip(A.BUY.message or ""):find("never answered")
        and strip(A.BUY.message or ""):find("mailbox"), "no answer: gives up, says to check the mailbox")
    M.buySilent = false
    -- the answer comes after we gave up
    M.buyLate = true
    bidsBefore = #M.bids
    A.OpenItem({ id = 12346 }); M.advance(2)
    F.browse.listings.onClick({ l = A.BUY.listings[1] })
    F.browse.box.buy:Click()
    M.advance(A.BUY_WAIT + 1)
    check(A.BUY.buy == nil and A.BUY.late, "gave up waiting")
    M.advance(20)
    check(strip(A.BUY.message or ""):find("went through after all"), "a late answer still says it was bought: "
        .. strip(A.BUY.message or ""))
    M.buyLate = false
    check(#M.bids == bidsBefore + 1, "only the one that went through was paid for")
    -- a price that never comes
    M.market[2840] = { { 90, 150 } }
    A.OpenItem({ id = 2840 }); M.advance(2)
    local realStart = C_AuctionHouse.StartCommoditiesPurchase
    C_AuctionHouse.StartCommoditiesPurchase = function(id, qty) M.quoteFor = { id = id, qty = qty } end
    A.Buy()
    M.advance(A.QUOTE_WAIT + 1)
    check(A.BUY.buy == nil and M.quoteFor == nil and strip(A.BUY.message or ""):find("never sent a price"),
        "no price ever comes: lets go and drops the quote")
    C_AuctionHouse.StartCommoditiesPurchase = realStart

    -- Paying well over the usual price asks first.
    local prices = ns.R().prices
    prices[2840] = prices[2840] or {}
    prices[12346] = prices[12346] or {}
    local keepBar, keepBoots = prices[2840].h, prices[12346].h
    prices[2840].h = { [1] = 50, [2] = 50 }
    M.market[2840] = { { 90, 150 } }
    A.OpenItem({ id = 2840 }); M.advance(2)
    A.BUY.qty = 10
    local boughtBefore = #M.bought
    A.Buy(); M.advance(1)
    A.Refresh()
    check(strip(F.browse.box.cost:GetText()):find("80%% over the usual price"), "the quoted price says it's over usual: "
        .. strip(F.browse.box.cost:GetText()))
    F.browse.box.buy:Click()
    check(A.OverpayShown() and #M.bought == boughtBefore and A.BUY.buy and A.BUY.buy.state == "quoted",
        "confirming 80% over usual asks first; nothing bought yet")
    local d = A.OverpayBox()
    check(strip(d.lines[1]:GetText()):find("^80%% more") and strip(d.lines[2]:GetText()):find("usually")
        and strip(d.lines[3]:GetText()):find("more than usual"), "it says how far over, the usual price and the extra: "
        .. strip(d.lines[2]:GetText()) .. " / " .. strip(d.lines[3]:GetText()))
    d.no:Click()
    check(not A.OverpayShown() and #M.bought == boughtBefore and A.BUY.buy and A.BUY.buy.state == "quoted",
        "Don't buy: nothing bought, the quote is still there")
    F.browse.box.buy:Click()
    A.OverpayBox().yes:Click(); M.advance(1)
    check(#M.bought == boughtBefore + 1 and not A.OverpayShown(), "Buy anyway buys them")

    prices[12346].h = { [1] = 100, [2] = 100 }
    M.market[12346] = { { 300, 1 } }
    local function pickBoots()
        A.OpenItem({ id = 12346 }); M.advance(2)
        F.browse.listings.onClick({ l = A.BUY.listings[1] })
    end
    pickBoots()
    local bids0 = #M.bids
    F.browse.box.buy:Click()
    check(A.OverpayShown() and #M.bids == bids0, "gear at 3x its usual price asks first")
    A.OverpayBox().yes:Click(); M.advance(1)
    check(#M.bids == bids0 + 1 and A.BUY.buy == nil, "and Buy anyway buys it")
    pickBoots()
    F.browse.box.buy:Click()
    pickBoots()
    check(not A.OverpayShown(), "opening the item again drops the question")
    A.ConfirmOverpay()
    check(#M.bids == bids0 + 1, "and a stale yes buys nothing")
    prices[12346].h = { [1] = 280, [2] = 280 }
    pickBoots()
    F.browse.box.buy:Click(); M.advance(1)
    check(not A.OverpayShown() and #M.bids == bids0 + 2, "near the usual price it buys straight away")
    prices[12346].h = { [1] = 100, [2] = 100 }
    ns.db.opts.buyConfirm = false
    pickBoots()
    F.browse.box.buy:Click(); M.advance(1)
    check(not A.OverpayShown() and #M.bids == bids0 + 3, "with the setting off it never asks")
    ns.db.opts.buyConfirm = true
    prices[2840].h, prices[12346].h = keepBar, keepBoots

    -- Buyouts and bids side by side, never mixed up: price each vs the whole
    -- auction, the next bid in its own column, bid-only auctions apart.
    M.market[12346] = { { 300, 1, false, 250 }, { 300, 6 }, { 0, 1, false, 90 } }
    A.OpenItem({ id = 12346 }); M.advance(2)
    local L = A.BUY.listings
    check(#L == 2 and L.bids and #L.bids == 1 and L[1].bid == 250 and L.bids[1].bid == 90,
        "buyouts listed, the bid-only auction kept apart, next bids read")
    A.Refresh()
    local rows = F.browse.listings.data
    check(#rows == 3 and strip(rows[3].cells.price) == "Bid only" and strip(rows[3].cells.note) == "Only if you win" and rows[3].dim,
        "the bid-only auction sits at the bottom, dimmed, never a deal")
    local six
    for _, row in ipairs(rows) do if row.l and row.l.q == 6 then six = row end end
    check(six and strip(six.cells.total) == strip(ns.Money(1800)) and strip(six.cells.note):find("^Vendor ")
        and strip(six.cells.note):find("%(%+"), "a stack of 6: the buyout total, and what a vendor pays for all 6: "
        .. (six and strip(six.cells.note) or "?"))
    check(six and six.hint:find("for all 6") and six.hint:find("one auction"), "its tooltip says you buy the whole auction")
    local one = rows[1].l.q == 1 and rows[1] or rows[2]
    check(strip(one.cells.bid) == strip(ns.Money(250)) and one.hint:find("outbids"), "the next bid has its own column, with what it means")
    F.browse.listings.onClick({ l = L.bids[1] })
    A.Refresh()
    check(F.browse.box.buy.disabled and strip(F.browse.box.cost:GetText()):find("^Bid only"), "picking a bid-only auction: no Buy")
    local bidsBefore = #M.bids
    A.Buy()
    check(#M.bids == bidsBefore and strip(A.BUY.message or ""):find("no buyout"), "and Buy refuses it")

    -- Sellers: a column, who lists the most, and who moved since you last looked
    A.seen[12346] = nil
    M.market[12346] = { { 300, 1, false, nil, "Grimbo" }, { 320, 2, false, nil, "Grimbo" }, { 400, 1, false, nil, "Vexa-Stormrage" },
        { 0, 1, false, 90, "Bidder" } }
    A.OpenItem({ id = 12346 }); M.advance(2)
    A.Refresh()
    local function sellerOf(p)
        for _, row in ipairs(F.browse.listings.data) do
            if row.l.p == p then return strip(row.cells.seller), row end
        end
    end
    local function factsText() return strip(F.browse.box.facts:GetText() or "") end
    check(sellerOf(300) == "Grimbo" and sellerOf(400) == "Vexa", "each listing shows its seller (realm left off): " .. tostring(sellerOf(400)))
    local _, vexaRow = sellerOf(400)
    check(vexaRow.hint:find("Seller: Vexa-Stormrage", 1, true), "the tooltip has the full name")
    check(factsText():find("Most listed: Grimbo 3 (2 auctions), Vexa 1", 1, true) and factsText():find("Cheapest: Grimbo", 1, true),
        "the side box says who lists the most and who's cheapest: " .. factsText())
    check(not factsText():find("since you last looked", 1, true), "first look: nothing to compare with")
    M.market[12346] = { { 250, 1, false, nil, "Vexa-Stormrage" }, { 300, 1, false, nil, "Grimbo" }, { 280, 1, false, nil, "Newbie" } }
    A.OpenItem({ id = 12346 }); M.advance(2)
    A.Refresh()
    check(sellerOf(250) == "Vexa cut" and sellerOf(280) == "Newbie new" and sellerOf(300) == "Grimbo",
        "next look: a price cut and a new seller are marked: " .. tostring(sellerOf(250)) .. " / " .. tostring(sellerOf(280)))
    check(factsText():find("Cut their price since you last looked: Vexa", 1, true)
        and factsText():find("New sellers since you last looked: Newbie", 1, true), "and summed up in the side box")
    -- Commodities: several sellers can share one price
    local linenBefore = M.market[2589]
    M.market[2589] = { { 10, 20, false, nil, { "Ann", "Bob", "Cy" } }, { 12, 5, false, nil, "Dee" }, { 13, 5, true } }
    A.OpenItem({ id = 2589 }); M.advance(2)
    A.Refresh()
    local annCell, annRow = sellerOf(10)
    check(annCell == "Ann +2" and annRow.hint:find("3 sellers at this price: Ann, Bob, Cy", 1, true),
        "a price shared by several sellers: " .. tostring(annCell))
    check(sellerOf(13) == "You" and factsText():find("Cheapest: 3 sellers at", 1, true) and factsText():find("Most listed: Dee 5, You 5", 1, true),
        "your own listing says You; a shared price isn't credited to one seller: " .. factsText():gsub("\n", " | "))
    M.market[2589] = linenBefore

    -- A gray item listed for a fortune is tagged, not offered
    local swordBefore = M.market[12345]
    M.market[12345] = { { 1200, 1, false, nil, "Normalguy" }, { 3000000, 1, false, nil, "Goldseller" } }
    A.OpenItem({ id = 12345 }); M.advance(2)
    A.Refresh()
    local _, junkRow = sellerOf(3000000)
    local _, fairRow = sellerOf(1200)
    check(junkRow and strip(junkRow.cells.note) == "Suspicious" and junkRow.hint:find("gold being passed", 1, true),
        "the 300g gray listing is tagged Suspicious, with why")
    check(fairRow and strip(fairRow.cells.note) ~= "Suspicious", "the normal one isn't")
    check(factsText():find("1 suspicious listing", 1, true), "the side box warns about it: " .. factsText():gsub("\n", " | "))
    F.browse.listings.onClick({ l = junkRow.l })
    A.Refresh()
    check(strip(F.browse.box.buy.text:GetText() or ""):find("^Buy anyway") and strip(F.browse.box.cost:GetText()):find("^Suspicious"),
        "picking it: a warning, and the button says Buy anyway")
    M.market[12345] = swordBefore
    M.market[12346] = { { 300, 1, true } }

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

    -- The post queue when the auction house is busy or slow
    do
        local post = F.sell.side.post
        local function label() A.Refresh(); return strip(post.text:GetText()) end
        P.CheckAll(true); M.advance(30)
        check(P.state == "ready", "checked again for the busy tests")
        local n0 = #M.posted
        M.throttle = false
        A.Refresh(); post:Click()
        check(#M.posted == n0 and ns.AHWaiting() and (A.Refresh() or true) and post.disabled and label():find("wait"),
            "busy: nothing sent, the button waits: " .. label())
        A.Refresh(); post:Click()
        check(#M.posted == n0, "clicking the waiting button sends nothing")
        M.throttle = nil
        M.fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY"); M.advance(1.1)
        check(not ns.AHWaiting() and (A.Refresh() or true) and not post.disabled, "ready again")

        -- No answer, bags unchanged: not posted, nothing counted, can go again.
        M.postSilent = true
        A.Refresh(); post:Click()
        local a = P.pending
        local done0 = a and (a.entry.posted or 0)
        A.Refresh(); post:Click()
        check(a and #M.posted == n0 + 1 and P.state == "posting" and (A.Refresh() or true) and post.disabled, "a double click while posting sends one post")
        M.advance(11)
        check(P.state == "ready" and P.pending == nil and (a.entry.posted or 0) == done0
            and (P.message or ""):find("didn't go through"), "no answer, bags unchanged: not counted, can be posted again")
        local recorded = #ns.db.posts
        M.fire("AUCTION_HOUSE_AUCTION_CREATED"); M.advance(0.1)
        check(#ns.db.posts == recorded, "a stray answer with nothing waiting changes nothing")

        -- No answer, but the items left the bags: it went up.
        local slot
        A.Refresh(); post:Click()
        a = P.pending
        for i, b in ipairs(M.bags) do if a and b[1] == a.id then slot = i end end
        local had = slot and M.bags[slot][2]
        if slot then M.bags[slot][2] = had - a.qty end
        M.advance(11)
        check(slot and P.pending == nil and (a.entry.posted or 0) == done0 + 1 and #ns.db.posts == recorded + 1
            and (P.message or ""):find("went up"), "no answer, but the bags show it went: counted once")
        if slot then M.bags[slot][2] = had end

        -- Can't tell: that item is skipped (no second listing), and a late answer still counts it.
        if P.state == "ready" then
            A.Refresh(); post:Click()
            a = P.pending
            for i, b in ipairs(M.bags) do if a and b[1] == a.id then slot = i end end
            local was = a and (a.entry.posted or 0)
            M.bags[slot][4] = true
            M.advance(11 + 8)
            check(a and a.entry.status == "skipped" and P.unsure == a and (a.entry.note or ""):find("Auctions tab"),
                "can't tell whether it went: that item is skipped until you check")
            M.bags[slot][4] = nil
            M.fire("AUCTION_HOUSE_AUCTION_CREATED"); M.advance(0.1)
            check(P.unsure == nil and a.entry.posted == was + 1 and a.entry.status ~= "skipped",
                "a late answer counts it after all")
        end

        -- "Too fast": dropped, checked, back to ready, and the button waits.
        P.CheckAll(true); M.advance(30)
        A.Refresh(); post:Click()
        M.fire("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED"); M.advance(0.1)
        check(P.state == "ready" and P.pending == nil and ns.AHWaiting() and (A.Refresh() or true) and post.disabled and label():find("wait"),
            "too fast: not counted, and Post waits")
        M.advance(4.2)
        check(not ns.AHWaiting() and (A.Refresh() or true) and not post.disabled, "then comes back by itself")
        M.postSilent = nil
        M.advance(5)
    end

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

----------------------------------------------------------------------
-- The mailbox
----------------------------------------------------------------------
out("")
out("== mailbox")
do
    local MB, U = ns.Mail, ns.MailUI
    local me = ns.charKey
    local BANK, HEX, RAIN, FANG, ALLY = "Player-6801-BANK", "Player-6801-HEX", "Player-6801-RAIN", "Player-6801-FANG", "Player-6801-ALLY"
    local LINEN, BOLT, ORE, BAR, LEATHER, PEACE, SILVERLEAF, HEARTH, QUEST, PELT = 2589, 2996, 2770, 2840, 2318, 2447, 765, 6948, 5056, 4865
    local savedBags, savedMoney, savedPick = M.bags, M.player.money, ns.db.opts.postPick
    local function addChar(key, name, class, faction, realm)
        ns.db.chars[key] = { name = name, class = class, level = 20, faction = faction or "Horde",
            realmKey = (realm or "6801") .. "-" .. (faction or "Horde") }
    end
    addChar(BANK, "Xeon Banker", "WARRIOR")
    addChar(HEX, "Xeon Hexspark", "MAGE")
    addChar(RAIN, "Xeon Raincaller", "SHAMAN")
    addChar(FANG, "Xeon Ironfang", "HUNTER")
    addChar(ALLY, "Xeon Lightbringer", "PALADIN", "Alliance")
    addChar("Player-9999-FAR", "Xeon Faraway", "MAGE", "Horde", "9999")
    local function bags(list)
        M.bags = {}
        for i, b in pairs(list) do M.bags[i] = b end
        M.fire("BAG_UPDATE_DELAYED")
    end
    local function line(plan, id) for _, l in ipairs(plan.lines) do if l.id == id then return l end end end
    local function skip(plan, id) for _, s in ipairs(plan.skipped) do if s.id == id then return s.why end end end
    local function sends() return M.MailCount("SendMail") end
    local function shipTo(plan, key) for _, s in ipairs(plan.ships) do if s.to == key then return s end end end
    local function stacksOn() local n = 0; for j = 1, 16 do if M.send.atts[j] then n = n + 1 end end; return n end
    local function anyLocked() for _, b in pairs(M.bags) do if b[4] then return true end end return false end

    -- Characters and the banker
    local names = {}
    for _, c in ipairs(MB.Characters(false)) do names[#names + 1] = c.name end
    check(table.concat(names, ",") == "Xeon Banker,Xeon Hexspark,Xeon Ironfang,Xeon Raincaller",
        "mailable characters: same realm and faction, never you: " .. table.concat(names, ","))
    check(MB.BankerKey() == BANK, "the banker defaults to Xeon Banker")
    check(not MB.SetBanker(ALLY) and not MB.SetBanker("Player-9999-FAR") and MB.BankerKey() == BANK,
        "a character on the other faction or realm can't be the banker")
    check(MB.SetBanker(HEX) and MB.BankerKey() == HEX and ns.db.opts.mailBanker[ns.realmKey] == HEX, "changing the banker is saved")
    MB.SetBanker(BANK)

    -- Presets: offered switched off
    bags({ { HEARTH, 1, true }, { LINEN, 20 }, { LINEN, 15 }, { LINEN, 5 }, { ORE, 40 }, { PEACE, 3 }, { LEATHER, 12 },
        { LEATHER, 4 }, { QUEST, 1, quest = true }, { SILVERLEAF, 9 }, { BOLT, 6 }, { BAR, 8 }, { PELT, 2 } })
    check(MB.AddPresets() == 5, "five suggested rules added")
    check(MB.AddPresets() == 0, "adding them again adds nothing")
    local byCat, allOff = {}, true
    for _, r in ipairs(MB.Rules()) do byCat[r.cat] = r; if r.on then allOff = false end end
    check(allOff, "suggested rules are never switched on by themselves")
    check(byCat.cloth.to == HEX and byCat.cloth.keep == 20 and byCat.herbs.to == RAIN and byCat.herbs.keep == 5
        and byCat.metal.to == me and byCat.metal.keep == 20 and byCat.leather.to == FANG and byCat.leather.keep == 10
        and byCat.stock.to == "banker", "suggested recipients and keep amounts")
    check(#MB.PlanRules().ships == 0, "with every rule off, nothing is planned")
    for _, k in ipairs({ "cloth", "herbs", "metal", "leather" }) do MB.SetRuleOn(byCat[k].id, true) end

    -- Categories, keep amounts across stacks, self-delivery, unmailable items
    local plan = MB.PlanRules()
    check(line(plan, LINEN) and line(plan, LINEN).qty == 20 and line(plan, LINEN).to == HEX,
        "linen: 40 in three stacks, keep 20, so 20 go to Xeon Hexspark")
    check(line(plan, LEATHER) and line(plan, LEATHER).qty == 4, "leather: 16, keep 10, 6 allowed, whole stacks make it 4")
    check(skip(plan, BOLT) == "keep" and skip(plan, PEACE) == "keep", "under the keep amount: stays")
    check(skip(plan, SILVERLEAF) == "stacks", "4 allowed but the only stack is 9: stays (mail never splits a stack)")
    check(skip(plan, ORE) == "self" and skip(plan, BAR) == "self", "ore and bars go to Xeon Mana: that's you, so they stay")
    check(not line(plan, HEARTH) and not line(plan, QUEST) and not line(plan, PELT), "bound, quest and unmatched items aren't planned")
    check(#plan.ships == 2 and shipTo(plan, HEX) and shipTo(plan, FANG) and not shipTo(plan, me), "one mail per recipient, none to you")
    check(plan.postage == 60, "postage shown: 30c a stack: " .. plan.postage)
    local hearthRule = MB.AddRule({ item = HEARTH, to = BANK, on = true }, true)
    check(skip(MB.PlanRules(), HEARTH) == "bound", "an exact-item rule on a soulbound item: can't be mailed")
    MB.DeleteRule(hearthRule.id)

    -- Priority: the first enabled match owns the item
    local linenRule = MB.AddRule({ item = LINEN, to = FANG, keep = 0, on = true }, true)
    plan = MB.PlanRules()
    check(line(plan, LINEN).to == FANG and line(plan, LINEN).qty == 40 and not shipTo(plan, HEX),
        "an exact-item rule above the cloth rule takes all the linen")
    check(#shipTo(plan, FANG).atts == 4, "linen and leather share one mail to the same character")
    MB.MoveRule(linenRule.id, 1)
    check(line(MB.PlanRules(), LINEN).to == HEX, "moved below the cloth rule, it loses the linen")
    MB.MoveRule(linenRule.id, -1)
    MB.SetRuleOn(linenRule.id, false)
    check(line(MB.PlanRules(), LINEN).to == HEX, "a switched-off rule does nothing")
    MB.SetRuleOn(linenRule.id, true)
    MB.SaveRule(linenRule.id, { scope = HEX })
    check(line(MB.PlanRules(), LINEN).to == HEX, "a rule for another character only doesn't run here")
    MB.DeleteRule(linenRule.id)
    check(not MB.FindRule(linenRule.id), "rule deleted")
    local ok, why = MB.SaveRule(byCat.cloth.id, { keep = -3 })
    check(not ok and why, "a negative keep is refused")

    -- Exclusions
    MB.exclude[LINEN] = true
    plan = MB.PlanRules()
    check(line(plan, LINEN).excluded and not shipTo(plan, HEX), "leaving linen out of this send")
    MB.exclude = {}
    MB.SetKept(LEATHER, true)
    plan = MB.PlanRules()
    check(not line(plan, LEATHER) and not shipTo(plan, FANG), "the always-keep list beats every rule")
    MB.SetKept(LEATHER, false)

    -- Designated stock to the banker, and changing the banker
    ns.db.opts.postPick = { [BAR] = true }
    MB.SetRuleOn(byCat.stock.id, true)
    check(skip(MB.PlanRules(), BAR) == "self", "stock that a higher rule keeps here stays here")
    MB.SetRuleOn(byCat.metal.id, false)
    plan = MB.PlanRules()
    check(line(plan, BAR) and line(plan, BAR).to == BANK and line(plan, BAR).qty == 8, "ticked-to-sell stock goes to the banker")
    MB.SetBanker(HEX)
    plan = MB.PlanRules()
    check(line(plan, BAR).to == HEX and #plan.ships == 2, "rules sent to \"Banker\" follow a new banker")
    MB.SetBanker(BANK)
    MB.SetRuleOn(byCat.stock.id, false)

    -- Quick-send to the banker
    local realAdvice, realCraft = ns.BagAdvice, ns.CraftList
    ns.BagAdvice = function() return { ah = { { id = ORE }, { id = LEATHER }, { id = PEACE }, { id = HEARTH }, { id = BOLT } } } end
    ns.CraftList = function() return { good = { { rec = { mine = true, name = "Smelt Copper", reagents = { { ORE, 1 } } } } } } end
    ns.db.opts.postPick = { [BAR] = true, [BOLT] = false }
    ns.db.opts.mailGold = false
    plan = MB.PlanBanker()
    check(not plan.problem and #plan.ships == 1 and plan.ships[1].to == BANK, "quick-send: one mail to Xeon Banker")
    check(line(plan, BAR) and line(plan, BAR).qty == 8, "the stock you ticked to sell goes")
    check(skip(plan, ORE) == "craft", "a material your profitable recipe uses stays")
    check(skip(plan, LEATHER) == "rule" and skip(plan, LINEN) == "rule", "materials a rule sends elsewhere stay out")
    check(skip(plan, HEARTH) == "bound" and not line(plan, BOLT), "soulbound stays; unticked-to-sell stays")
    check(not line(plan, PELT) and not line(plan, SILVERLEAF), "not every unmatched item counts as stock")
    check(plan.gold == 0 and plan.ships[1].money == 0, "gold is off by default")
    ns.db.opts.postPick[ORE] = true
    check(line(MB.PlanBanker(), ORE), "ticking a reserved material to sell sends it anyway")
    ns.db.opts.postPick[ORE] = nil
    ns.db.opts.mailQuickCats = { gems = true }
    bags({ { BAR, 8 }, { 818, 2 } })
    check(line(MB.PlanBanker(), 818), "a category you added to quick-send goes too")
    ns.db.opts.mailQuickCats = nil
    -- Gold, the reserve and postage
    M.player.money = 100000
    ns.db.opts.mailGold, ns.db.opts.mailReserve = true, 50000
    plan = MB.PlanBanker()
    check(plan.gold == 100000 - 50000 - 30 and plan.ships[1].money == plan.gold and plan.after == 50000,
        "spare gold = gold - reserve - postage: " .. tostring(plan.gold))
    ns.db.opts.mailReserve = 99990
    plan = MB.PlanBanker()
    check(plan.gold == 0 and plan.goldNote and plan.warn, "reserve above what postage leaves: no gold, and a warning")
    ns.db.opts.mailReserve = 50000
    MB.SetBanker(me)
    check(MB.PlanBanker().problem, "you can't quick-send to yourself")
    MB.SetBanker(BANK)
    check(MB.PlanCustom({ to = "xeon mana", subject = "hi" }).problem, "custom mail to yourself is refused")

    -- Attachment batching
    local many = {}
    for i = 1, 14 do many[i] = { LINEN, 5 } end
    bags(many)
    MB.SaveRule(byCat.cloth.id, { keep = 0 })
    plan = MB.PlanRules()
    check(#plan.ships == 2 and #plan.ships[1].atts == 12 and #plan.ships[2].atts == 2
        and plan.ships[1].subject:find("(1/2)", 1, true), "14 stacks become mails of 12 and 2")
    MB.SaveRule(byCat.cloth.id, { keep = 20 })

    -- The window
    M.inbox = {}
    M.fire("MAIL_SHOW"); M.advance(2)
    local W = ForeverGoldMailFrame
    check(W and W:IsShown() and MailFrame._scale == 0.001, "our mailbox opens; the game's is hidden")
    check(MB.inboxState == "ready", "inbox read")
    for _, t in ipairs({ "send", "rules", "inbox" }) do U.SetTab(t) end
    U.ToggleBankerPanel(true); U.ToggleBankerPanel(false)
    W.blizz:Click()
    check(not W:IsShown() and MailFrame._scale == 1 and ns.db.opts.mailBlizzard and ForeverGoldMailStrip:IsShown(),
        "Game's mailbox brings the game's back, with a way back")
    ForeverGoldMailStrip.ours:Click()
    check(W:IsShown() and MailFrame._scale == 0.001 and not ns.db.opts.mailBlizzard, "and back to ours")
    MailFrame:Hide(); MailFrame._scale = 1; MailFrame:Show()
    check(MailFrame._scale == 0.001, "the game's mailbox is hidden again whenever it shows")
    -- Leaving one item out by clicking its row
    bags({ { LINEN, 20 }, { LINEN, 15 }, { LINEN, 5 }, { LEATHER, 12 }, { LEATHER, 4 } })
    U.SetTab("send"); U.SetMode("rules")
    local leatherRow
    for _, r in ipairs(W.send.list.rows) do if r.d and r.d.id == LEATHER and r.d.check ~= nil then leatherRow = r end end
    check(leatherRow and leatherRow.d.check == true, "send preview lists leather, ticked")
    leatherRow:Click()
    check(MB.exclude[LEATHER] and not shipTo(U.CurrentPlan(), FANG), "clicking the row leaves it out of this send")
    for _, r in ipairs(W.send.list.rows) do if r.d and r.d.id == LEATHER then leatherRow = r end end
    check(leatherRow.d.check == false, "and its box stays, unticked")
    leatherRow:Click()
    check(not MB.exclude[LEATHER], "click again to put it back")
    U.SetTab("inbox")

    -- Sending: one click per mail, waiting for the server each time
    bags({ { HEARTH, 1, true }, { LINEN, 20 }, { LINEN, 15 }, { LINEN, 5 }, { LEATHER, 12 }, { LEATHER, 4 } })
    M.player.money = 100000
    local before = sends()
    plan = MB.PlanRules()
    check(MB.StartSend(plan), "send started")
    check(not MB.StartSend(plan) and not MB.CollectAll(), "a second send or a collect can't start on top of it")
    check(MB.Q.ships[1].status == "preparing" and M.send.atts[1] and M.send.atts[1].count == 20, "first mail: linen attached")
    M.advance(0.3)
    check(MB.Q.ships[1].status == "ready" and sends() == before, "ready, and nothing sent without a click")
    check(MB.SendNext() and sends() == before + 1, "one click sends it")
    check(not MB.SendNext() and sends() == before + 1, "a double click doesn't send twice")
    check(MB.status.kind == "waiting" and MB.status.text:find("waiting for the server"), "shows waiting for the server")
    M.advance(1.5)
    check(MB.Q.ships[1].status == "sent" and M.sentMail[#M.sentMail].name == "Xeon Hexspark", "confirmed by the server")
    check(MB.Q.ships[2].status == "ready" and M.send.atts[1].id == LEATHER, "the next mail gets ready by itself")
    local second = MB.Q.ships[2]
    MB.SendNext(); M.advance(1)
    check(second.status == "sent" and not MB.Busy() and MB.status.kind == "done", "both sent: done")
    check(MB.Shipments() == nil and MB.status.text:find("new preview", 1, true),
        "and it goes straight on to a new preview: " .. MB.status.text)
    check(M.player.money == 100000 - 60, "postage paid: " .. M.player.money)
    MB.ClearShipments()

    -- The bags change between the preview and the send
    bags({ { LINEN, 20 }, { LINEN, 15 }, { LINEN, 5 } })
    plan = MB.PlanRules()
    M.bags[1] = { LINEN, 10 }
    MB.StartSend(plan); M.advance(0.3)
    local s = MB.Q.ships[1]
    check(s.status == "ready" and s.items[1].qty == 10 and s.changed and stacksOn() == 1,
        "fewer in the bags: re-picked to 10, and it says so: " .. tostring(s.changed))
    MB.Stop()
    check(not MB.Busy() and stacksOn() == 0 and not anyLocked() and s.status == "planned", "Stop takes the attachments back off")
    MB.ClearShipments()
    bags({ { LINEN, 20 }, { LINEN, 15 }, { LINEN, 5 } })
    plan = MB.PlanRules()
    bags({ { LINEN, 15 }, { LINEN, 5 } })
    before = sends()
    MB.StartSend(plan); M.advance(1)
    check(MB.Q.ships[1].status == "skipped" and sends() == before, "nothing left to send after the bags changed: skipped")
    MB.ClearShipments()
    -- An attachment taken off while waiting for the click
    bags({ { LINEN, 20 }, { LINEN, 15 }, { LINEN, 5 } })
    MB.StartSend(MB.PlanRules()); M.advance(0.3)
    ClickSendMailItemButton(1, true) -- someone else takes it off the mail
    check(not MB.SendNext() and MB.Q.ships[1].status == "failed" and sends() == before, "attachments changed: not sent")
    MB.ClearShipments()

    -- A busy server
    M.mailBusy = true
    MB.StartSend(MB.PlanRules()); M.advance(1)
    check(MB.status.kind == "waiting" and stacksOn() == 0, "server busy: waits before attaching anything")
    M.mailBusy = false; M.advance(1)
    check(MB.Q.ships[1].status == "ready", "and carries on when it's free")
    M.mailBusy = true
    check(not MB.SendNext() and sends() == before, "Send while the server is busy does nothing")
    M.mailBusy = false

    -- The server says no
    M.sendMode = "fail"
    MB.SendNext(); M.advance(1)
    check(MB.Q.ships[1].status == "failed" and not MB.Busy() and MB.status.text:find("Cannot find player")
        and sends() == before + 1, "a refusal stops the queue and says why")
    check(stacksOn() == 0 and not anyLocked(), "the items go back to the bags")
    MB.ClearShipments()

    -- No answer: never sent again
    bags({ { LINEN, 20 }, { LINEN, 15 }, { LINEN, 5 } })
    M.sendMode = "silent"
    MB.StartSend(MB.PlanRules()); M.advance(0.3)
    before = sends()
    MB.SendNext(); M.advance(25)
    check(MB.Q.ships[1].status == "failed" and sends() == before + 1, "no answer, items still on the mail: not sent, not retried")
    MB.ClearShipments()
    M.sendMode = "lost"
    MB.StartSend(MB.PlanRules()); M.advance(0.3)
    before = sends()
    MB.SendNext(); M.advance(25)
    check(MB.Q.ships[1].status == "unclear" and MB.status.kind == "unclear" and MB.status.text:find("most likely went out"),
        "no answer, items gone and postage paid: most likely sent, check before resending")
    M.advance(60)
    check(sends() == before + 1 and not MB.Busy(), "a timeout never sends a second time")
    M.fire("MAIL_SEND_SUCCESS")
    check(MB.Q.ships[1].status == "sent", "a late confirmation is accepted")
    M.sendMode = "ok"
    MB.ClearShipments()

    -- The game's own "are you sure?" dialog
    bags({ { LINEN, 20 }, { LINEN, 15 }, { LINEN, 5 } })
    M.sendMode = "silent"
    MB.StartSend(MB.PlanRules()); M.advance(0.3)
    MB.SendNext()
    M.fire("SECURE_TRANSFER_CONFIRM_SEND_MAIL"); M.advance(30)
    check(MB.Q.ships[1].status == "sending" and MB.status.kind == "confirm", "waits while the game asks you to confirm")
    M.fire("SECURE_TRANSFER_CANCEL")
    check(MB.Q.ships[1].status == "cancelled" and not MB.Busy(), "cancelled in the dialog: stopped, nothing sent")
    M.sendMode = "ok"
    MB.ClearShipments()

    -- Delayed replies
    M.sendDelay = 8
    MB.StartSend(MB.PlanRules()); M.advance(0.3)
    before = sends()
    local slow = MB.Q.ships[1]
    MB.SendNext(); M.advance(5)
    check(slow.status == "sending" and sends() == before + 1, "a slow server: still waiting, nothing resent")
    M.advance(5)
    check(slow.status == "sent", "the slow answer arrives and counts")
    M.sendDelay = 0.5
    MB.ClearShipments()

    -- The reserve covers postage
    bags({ { LINEN, 20 }, { LINEN, 15 }, { LINEN, 5 } })
    M.player.money = 50010
    before = sends()
    MB.StartSend(MB.PlanRules()); M.advance(1)
    check(not MB.Busy() and stacksOn() == 0 and sends() == before and MB.status.text:find("under the"),
        "postage that would break the reserve stops before attaching")
    MB.ClearShipments()
    -- Gold with the banker mail, re-checked at the click
    M.player.money = 100000
    ns.db.opts.postPick = { [BAR] = true }
    bags({ { BAR, 8 } })
    MB.StartSend(MB.PlanBanker()); M.advance(0.3)
    M.player.money = 80000
    MB.SendNext(); M.advance(1)
    local last = M.sentMail[#M.sentMail]
    check(last.name == "Xeon Banker" and last.money == 80000 - 50000 - 30 and M.player.money == 50000,
        "gold lowered at the click so the reserve still holds: " .. tostring(last.money))
    ns.db.opts.mailGold = false
    MB.ClearShipments()

    -- The mailbox closes mid-queue
    M.player.money = 100000
    bags({ { LINEN, 20 }, { LINEN, 15 }, { LINEN, 5 }, { LEATHER, 12 }, { LEATHER, 4 } })
    MB.StartSend(MB.PlanRules()); M.advance(0.3)
    M.fire("MAIL_CLOSED")
    check(not MB.Busy() and stacksOn() == 0 and MB.Q.ships[1].status == "planned" and not W:IsShown()
        and MailFrame._scale == 1, "closed while waiting for the click: stopped, items off, windows restored")
    M.fire("MAIL_SHOW"); M.advance(2)
    MB.StartSend(MB.PlanRules()); M.advance(0.3)
    before = sends()
    MB.SendNext()
    M.fire("MAIL_CLOSED"); M.advance(3)
    check(MB.Q.ships[1].status == "sent" and MB.Q.ships[2].status == "planned" and sends() == before + 1 and not MB.Busy(),
        "closed while the server had one: that one is confirmed, nothing more goes")
    MB.ClearShipments()
    M.fire("MAIL_SHOW"); M.advance(2)

    -- The send tab's button
    bags({ { LINEN, 20 }, { LINEN, 15 }, { LINEN, 5 } })
    U.SetTab("send"); U.SetMode("rules")
    before = sends()
    W.send.side.send:Click(); M.advance(0.3)
    check(MB.Q.ships and MB.Q.ships[1].status == "ready", "the Send button starts and prepares the first mail")
    W.send.side.send:Click()
    check(sends() == before + 1, "the next press sends it")
    W.send.side.send:Click()
    check(sends() == before + 1, "pressing while waiting sends nothing")
    M.advance(1)
    MB.ClearShipments()
    U.SetMode("banker"); U.SetMode("custom")
    U.form.to = "Xeon Banker"; U.form.picks = { ["0:2"] = true }; U.Refresh()
    local panelH = 610 - 128 - 30
    check(W.send.list:GetHeight() + 190 + 22 <= panelH and W.send.list.visible * 40 + 4 <= W.send.list:GetHeight(),
        "custom mail: the list is shorter so it stays inside the window: " .. W.send.list:GetHeight())
    plan = U.CurrentPlan()
    check(not plan.problem and #plan.ships == 1 and plan.ships[1].atts[1].count == 15, "custom mail: picked stack attached")
    U.form.picks = { ["0:2"] = true, ["0:3"] = true }; U.form.moneyText = "2.5"; U.Refresh()
    plan = U.CurrentPlan()
    check(plan.ships[1].money == 25000 and #plan.ships[1].atts == 2, "custom mail: typed gold and two stacks")
    U.form.cod = true; U.Refresh()
    plan = U.CurrentPlan()
    check(plan.ships[1].cod == 25000 and plan.ships[1].money == 0, "C.O.D. instead of sending gold")
    U.form = { picks = {} }
    U.SetMode("banker")
    check(W.send.list:GetHeight() == panelH - 72 - 40 and W.send.list.visible == 8, "other send methods: the list is full height again")

    -- Asked when the mailbox opens, if the rules have mail to send
    bags({ { LINEN, 20 }, { LINEN, 15 }, { LINEN, 5 } })
    M.fire("MAIL_CLOSED"); M.advance(1)
    before = sends()
    M.fire("MAIL_SHOW"); M.advance(2)
    check(U.PromptShown() and not MB.Busy() and sends() == before, "opening the mailbox asks about the rules' mail, sends nothing")
    local pl = W.prompt.box.lines[1]:GetText() or ""
    check(pl:find("Xeon Hexspark", 1, true) ~= nil and pl:find("Linen Cloth x20", 1, true) ~= nil,
        "the box says who gets what (the rule keeps 20): " .. pl)
    check((W.prompt.box.send.text:GetText() or ""):find("Send now (1 mail)", 1, true) ~= nil, "a Send now button")
    W.prompt.box.later:Click()
    check(not U.PromptShown() and not MB.Busy(), "Not now closes it")
    M.fire("MAIL_CLOSED"); M.advance(1)
    M.fire("MAIL_SHOW"); M.advance(2)
    W.prompt.box.send:Click(); M.advance(0.3)
    check(not U.PromptShown() and U.tab == "send" and U.mode == "rules" and MB.Busy() == "send"
        and MB.Q.ships[1].status == "ready" and sends() == before, "Send now gets the first mail ready, still waiting for your click")
    MB.Stop(); MB.ClearShipments()
    M.fire("MAIL_CLOSED"); M.advance(1)
    M.fire("MAIL_SHOW"); M.advance(2)
    W.prompt.box.review:Click()
    check(not U.PromptShown() and not MB.Busy() and U.tab == "send" and U.mode == "rules", "Review first only shows the preview")
    ns.db.opts.mailPrompt = false
    M.fire("MAIL_CLOSED"); M.advance(1)
    M.fire("MAIL_SHOW"); M.advance(2)
    check(not U.PromptShown(), "switched off: no box")
    ns.db.opts.mailPrompt = true
    bags({ { BAR, 1 } })
    M.fire("MAIL_CLOSED"); M.advance(1)
    M.fire("MAIL_SHOW"); M.advance(2)
    check(not U.PromptShown(), "nothing in your bags matches a rule: no box")
    U.SetTab("inbox")

    -- Auto-send on open (opt-in)
    bags({ { LINEN, 20 }, { LINEN, 15 }, { LINEN, 5 } })
    ns.db.opts.mailAuto = true
    M.fire("MAIL_CLOSED"); M.advance(1)
    before = sends()
    M.fire("MAIL_SHOW"); M.advance(2)
    check(MB.Busy() and MB.Q.auto and MB.Q.ships[1].status == "ready" and sends() == before,
        "auto-send gets the first mail ready, but still waits for your click")
    check(not U.PromptShown(), "auto-send on: no box asking as well")
    MB.Stop()
    ns.db.opts.mailAuto = false
    MB.ClearShipments()

    -- The rule editor
    U.SetTab("rules")
    local count = #MB.Rules()
    U.NewRule()
    check(#MB.Rules() == count + 1 and U.draft, "Add rule makes a new one to edit")
    U.draft.cat, U.draft.to, U.draft.keep = "herbs", RAIN, 3
    U.SaveDraft()
    local nr = MB.FindRule(U.draft.id)
    check(nr.cat == "herbs" and nr.to == RAIN and nr.keep == 3, "Save rule saves it")
    U.DeleteDraft()
    check(MB.FindRule(nr.id), "the first Delete only asks")
    U.DeleteDraft()
    check(not MB.FindRule(nr.id), "the second deletes it")

    -- The inbox: collect all, never C.O.D.
    bags({ { LINEN, 5 } })
    M.player.money = 100000
    M.inbox = {
        { sender = "Auction House", subject = "Auction successful: Copper Bar (5)", money = 5000, invoice = "seller", item = "Copper Bar", count = 5 },
        { sender = "Xeon Hexspark", subject = "Herbs", money = 200, items = { { PEACE, 10 }, { SILVERLEAF, 4 } } },
        { sender = "Shady Seller", subject = "Pay me", cod = 2500, items = { { LINEN, 20 } } },
        { sender = "Game Master", subject = "Hello", gm = true, money = 100, items = { { BAR, 1 } } },
        { sender = "Auction House", subject = "Sale pending: Tin Bar", invoice = "seller_temp_invoice", keep = true },
        { sender = "Xeon Banker", subject = "A letter", body = "hi", keep = true },
    }
    M.fire("MAIL_INBOX_UPDATE"); M.advance(1)
    check(#MB.inbox == 6 and MB.inbox[3].restricted == "cod" and MB.inbox[4].restricted == "gm"
        and MB.inbox[5].restricted == "pending", "C.O.D., GM mail and pending sales are marked")
    local money, items, cod = MB.InboxTotals()
    check(money == 5200 and cod == 1, "to collect: 52s (not the GM's): " .. money)
    U.SetTab("inbox")
    for _, r in ipairs(W.inbox.list.rows) do if r.d then r:Click() end end
    check(not MB.TakeAttachment(MB.inbox[3], 1) and not MB.TakeMoney(MB.inbox[3]), "C.O.D. can't be taken here")
    local returned, deleted = M.MailCount("ReturnInboxItem"), M.MailCount("DeleteInboxItem")
    check(MB.CollectAll() and not MB.CollectAll(), "collect all starts once")
    check(not MB.StartSend(MB.PlanRules()), "no send while collecting")
    M.advance(15)
    check(M.player.money == 100000 + 5200 and MB.BagCount(PEACE) == 10 and MB.BagCount(SILVERLEAF) == 4,
        "gold and items collected: " .. M.player.money)
    local codTouched = false
    for _, l in ipairs(M.mailLog) do if l[3] == "Pay me" or l[4] == "Pay me" or l[2] == "Pay me" then codTouched = true end end
    check(not codTouched and not M.codPaid and #M.inbox == 4, "the C.O.D. mail was never touched or paid")
    check(M.MailCount("ReturnInboxItem") == returned and M.MailCount("DeleteInboxItem") == deleted, "nothing returned or deleted")
    check(MB.status.kind == "done" and not MB.Busy(), "done: " .. MB.status.text)
    check(MB.TakeAttachment(MB.inbox[2], 1), "you can take the GM's item yourself")
    M.advance(2)
    check(MB.BagCount(BAR) == 1, "taken")

    -- A take with no answer: stops, never retried
    table.insert(M.inbox, { sender = "Xeon Banker", subject = "Gold", money = 300 })
    M.fire("MAIL_INBOX_UPDATE"); M.advance(1)
    M.takeMode = "silent"
    local takes = M.MailCount("TakeInboxMoney")
    MB.CollectAll(); M.advance(30)
    check(M.MailCount("TakeInboxMoney") == takes + 1 and not MB.Busy() and MB.status.kind == "error",
        "no answer to a take: stopped, not retried: " .. MB.status.text)
    M.takeMode = "ok"
    -- Slow answers are waited for
    M.takeDelay = 4
    takes = M.MailCount("TakeInboxMoney")
    MB.CollectAll(); M.advance(2)
    check(M.MailCount("TakeInboxMoney") == takes + 1 and MB.status.kind == "waiting", "slow server: one take, waiting")
    M.advance(5)
    check(M.player.money == 100000 + 5200 + 300 and not MB.Busy(), "the slow take lands, nothing doubled")
    -- The mailbox closes mid-collect
    table.insert(M.inbox, { sender = "A", subject = "One", money = 10 })
    table.insert(M.inbox, { sender = "B", subject = "Two", money = 20 })
    M.fire("MAIL_INBOX_UPDATE"); M.advance(1)
    takes = M.MailCount("TakeInboxMoney")
    MB.CollectAll(); M.advance(1)
    M.fire("MAIL_CLOSED"); M.advance(10)
    check(M.MailCount("TakeInboxMoney") == takes + 1 and not MB.Busy() and MB.status.text:find("closed"),
        "mailbox closed mid-collect: the one in flight finishes, nothing more")
    M.takeDelay = 0.3
    -- Something else takes mail while we collect
    M.fire("MAIL_SHOW"); M.advance(2)
    takes = M.MailCount("TakeInboxMoney")
    MB.CollectAll()
    ReturnInboxItem(1)
    M.advance(5)
    check(M.MailCount("TakeInboxMoney") == takes + 1 and not MB.Busy() and MB.status.text:find("Another mail action"),
        "another mail action stops the queue after the one in flight")
    -- Full bags
    local full = {}
    for i = 1, 16 do full[i] = { LINEN, 1 } end
    bags(full)
    M.inbox = { { sender = "C", subject = "Stuff", money = 50, items = { { BAR, 2 } } } }
    M.fire("MAIL_INBOX_UPDATE"); M.advance(1)
    MB.CollectAll(); M.advance(5)
    check(MB.status.kind == "error" and MB.status.text:find("bags are full") and #M.inbox == 1 and M.inbox[1].money == 0,
        "bags full: the gold is taken, the item waits")

    M.fire("MAIL_CLOSED"); M.advance(1)
    ns.BagAdvice, ns.CraftList = realAdvice, realCraft
    MB.PlanBanker() -- the real advice runs without errors
    M.bags, M.player.money, ns.db.opts.postPick = savedBags, savedMoney, savedPick
end


out("== options window")
do
    local OPT = ns.Options
    local names = {}
    for _, c in ipairs(M.settings.cats) do
        if c.parent == M.settings.addon then names[#names + 1] = c.name end
    end
    check(M.settings.addon and M.settings.addon.name == "WoW Tracker"
        and table.concat(names, ", ") == "Auction Forever, Bags Forever, Mail Forever, Gathering Forever, Azeroth Radio",
        "Options > AddOns > WoW Tracker, with its pages: " .. table.concat(names, ", "))
    local S = M.settings.settings
    local function count(cat, kind)
        local n = 0
        for _, c in ipairs(cat.controls) do if c.kind == kind then n = n + 1 end end
        return n
    end
    check(count(OPT.cats.auction, "check") >= 4 and count(OPT.cats.auction, "dropdown") == 5 and count(OPT.cats.bags, "slider") == 4
        and count(OPT.cats.gathering, "check") == 9 and count(OPT.cats.mail, "check") == 4,
        "each page has the game's own checkboxes, dropdowns and sliders")
    check(S.FOREVERGOLD_BAGSPLIT:GetValue() == false, "split by bag reads off")
    S.FOREVERGOLD_BAGSPLIT:SetValue(true)
    check(ns.db.opts.bagSplit == true and S.FOREVERGOLD_BAGSPLIT:GetValue() == true, "and switches on")
    ns.db.opts.bagSplit = nil
    S.FOREVERGOLD_BAGALPHAPCT:SetValue(70)
    check(math.abs(ns.db.opts.bagAlpha - 0.7) < 0.001 and S.FOREVERGOLD_BAGALPHAPCT:GetValue() == 70, "the background slider sets 70%")
    ns.db.opts.bagAlpha = nil
    S.FOREVERGOLD_BAGCOLS:SetValue(12)
    check(ns.db.opts.bagCols == 12 and S.FOREVERGOLD_BAGCOLS:GetValue() == 12, "the columns slider")
    ns.db.opts.bagCols = nil
    check(S.FOREVERGOLD_BAGCOLS:GetValue() == 10, "10 columns to start")
    local reserveVals = {}
    for _, c in ipairs(OPT.cats.mail.controls) do
        if c.kind == "dropdown" then for _, o in ipairs(c.options) do reserveVals[#reserveVals + 1] = o.value end end
    end
    check(table.concat(reserveVals, ",") == "0,10000,50000,100000,500000,1000000", "Keep at least: nothing to 100 gold")
    S.FOREVERGOLD_MAILRESERVE:SetValue(10000)
    check(ns.db.opts.mailReserve == 10000, "and it sets the reserve")
    ns.db.opts.mailReserve = 0
    S.FOREVERGOLD_MAILOURS:SetValue(false)
    check(ns.db.opts.mailBlizzard == true and S.FOREVERGOLD_MAILOURS:GetValue() == false, "switch to the game's mailbox")
    S.FOREVERGOLD_MAILOURS:SetValue(true)
    check(not ns.db.opts.mailBlizzard, "and back")
    S.FOREVERGOLD_POSTQTY:SetValue("5")
    check(ns.db.opts.postQty == "5", "selling: each listing holds 5")
    ns.db.opts.postQty = nil
    local radioButton
    for _, c in ipairs(OPT.cats.radio.controls) do if c.kind == "button" then radioButton = c end end
    check(radioButton and radioButton.text == "Show the link", "the Azeroth Radio page links to the radio")
    radioButton.click()
    check(ForeverGoldRadioLink and ForeverGoldRadioLink:IsShown(), "with a box to copy the link from")
    ForeverGoldRadioLink:Hide()
    SlashCmdList.FOREVERGOLD("settings")
    check(M.settings.opened == OPT.cats.auction:GetID(), "/gold settings opens it too")
    M.combat = true
    M.settings.opened = nil
    OPT.Open("bags")
    check(M.settings.opened == nil, "not in combat")
    M.combat = false
end

out("== mail: scrolls")
do
    local MB = ns.Mail
    check(MB.CAT.scrolls and MB.InCategory("scrolls", 211780) and not MB.InCategory("scrolls", 954)
        and not MB.InCategory("scrolls", 858) and not MB.InCategory("scrolls", 2447),
        "the Comprehension scrolls group takes the mage's scrolls only, not stat scrolls, potions or herbs")
    check(MB.CAT.scrolls.icon == 211780, "with a Comprehension scroll's own icon")
    local found
    for _, o in ipairs(ns.MailUI.MatchOptions()) do if o.value == "scrolls" then found = o end end
    check(found and found.text == "Comprehension scrolls", "and it's offered when you make a rule")
    local r = MB.AddRule({ cat = "scrolls", to = "banker", on = true, keep = 0, scope = "account" })
    check(r and r.cat == "scrolls" and MB.SaveRule(r.id, { cat = "scrolls", keep = 2 }), "a Scrolls rule can be made and edited")
    MB.DeleteRule(r.id)
end

out("== bag window")
do
    local BU = ns.BagUI
    local BV = BU.bank
    local savedBags, savedMoney = M.bags, M.player.money
    M.bags = { { 6948, 1, true }, { 2770, 40 }, { 2835, 23 }, { 2771, 12 }, { 4865, 6 }, { 2840, 8 }, { 2589, 35 }, { 2775, 2 }, { 3576, 4 } }
    M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
    -- B opens the game's bags; ours follow and the game's stay out of sight
    OpenAllBags(); M.advance(0.5)
    local win = BU.win
    check(win and win:IsShown() and ContainerFrameCombinedBags:GetParent() ~= UIParent,
        "opening your bags shows Forever Gold's window; the game's bag frame is tucked away")
    check(strip(win.title:GetText()) == "Xeon Mana's Inventory" and strip(win.sub:GetText()) == "",
        "titled with your name: " .. strip(win.title:GetText()))
    check(strip(win.slots:GetText()) == "9 / 16  7 free", "the footer counts slots: " .. strip(win.slots:GetText()))
    local cells = BU.Cells()
    check(#cells == 16 and cells[2].live and cells[2].id == 2770 and cells[2].count == 40, "your bags are read live, slot by slot")
    local function buttonFor(bag, slot)
        for _, f in ipairs(M.frames) do
            if f._shown and f.fgCell and f.fgCell.live and f.fgCell.bag == bag and f.fgCell.slot == slot then return f end
        end
    end
    local copper = buttonFor(0, 2)
    check(copper and copper._count == 40 and copper._icon and copper:GetID() == 2 and copper:GetParent():GetID() == 0,
        "each item is the game's own bag button: its slot as its ID, its bag as its holder's ID")
    -- search takes the title's place
    win.searchBtn:Click()
    check(win.searchBox:IsShown() and not win.title:IsShown(), "Search opens in place of the title")
    win.searchBox:SetText("ore"); win.searchBox._scripts.OnTextChanged(win.searchBox)
    check(not buttonFor(0, 2).fgDim:IsShown() and buttonFor(0, 1).fgDim:IsShown(), "searching 'ore' dims everything but the ore")
    win.searchBtn:Click()
    check(not win.searchBox:IsShown() and win.title:IsShown() and BU.search == "" and not buttonFor(0, 1).fgDim:IsShown(),
        "clicking Search again puts the title back and clears it")
    -- one big inventory, or split by bag; empty slots on or off
    ns.db.opts.bagSplit = true; BU.Refresh()
    check(#BU.Cells() == 16 and buttonFor(0, 2) ~= nil, "split by bag still shows every item")
    ns.db.opts.bagSplit = nil
    -- new loot gathers at the bottom
    M.newItems["0:3"] = true; BU.Refresh()
    local _, _, _, _, sy0 = buttonFor(0, 3):GetPoint()
    local _, _, _, _, cy0 = buttonFor(0, 2):GetPoint()
    check(sy0 == cy0, "new loot stays where it is by default (it flashes instead)")
    ns.db.opts.bagNew = true; BU.Refresh()
    local _, _, _, _, sy = buttonFor(0, 3):GetPoint()
    local _, _, _, _, cy = buttonFor(0, 2):GetPoint()
    ns.db.opts.bagNew = nil
    check(sy < cy - 39, "a new item sits in the New loot row under the bags: " .. tostring(sy) .. " vs " .. tostring(cy))
    win:Hide(); OpenAllBags(); M.advance(0.5)
    check(next(M.newItems) == nil, "closing your bags clears what's new")
    -- banker marks are mail rules
    local MB = ns.Mail
    BU.ToggleMark(2770)
    local rule = BU.BankerRule(2770)
    check(rule and rule.on and rule.to == "banker" and BU.IsMarked(2770) and MB.Rules()[1] == rule,
        "To banker adds an item rule at the top of the mail rules")
    BU.Refresh()
    check(strip(win.markCount:GetText()) == "1" and buttonFor(0, 2).fgMark:IsShown(), "the stack shows the mark; the footer counts it")
    BU.ToggleMark(2770)
    check(not BU.BankerRule(2770) and not BU.IsMarked(2770), "and toggling it again removes the rule")
    -- unmarking keeps it away from the banker, even where a group rule or quick-send would send it
    ns.db.opts.mailNoBanker = nil
    local metalRule = { id = -1, on = true, cat = "metal", to = "banker", keep = 0, scope = "account" }
    check(MB.Allocate(MB.ScanBags(), { metalRule })[2771].rule == metalRule, "an Ore & bars rule to the banker would send the tin")
    local function bankerLists(id)
        for _, l in ipairs(MB.PlanBanker().lines) do if l.id == id then return true end end
        return false
    end
    local savedPick = ns.db.opts.postPick
    ns.db.opts.postPick = { [2771] = true }
    check(bankerLists(2771), "and so would quick-send, as auction stock you ticked to sell")
    BU.ToggleMark(2771); BU.ToggleMark(2771)
    check(MB.Allocate(MB.ScanBags(), { metalRule })[2771].rule == nil and not bankerLists(2771),
        "after you mark and unmark it, neither sends it to the banker")
    ns.db.opts.postPick = savedPick
    BU.ToggleMark(2771)
    check(not MB.IsBankerBlocked(2771) and BU.IsMarked(2771), "marking it again lifts that")
    BU.ToggleMark(2771)
    ns.db.opts.mailNoBanker = nil
    -- Shift+right-click a stack: to banker (and back)
    M.shift = true
    local tin = buttonFor(0, 4)
    tin._scripts.OnClick(tin, "RightButton")
    check(BU.IsMarked(2771), "Shift+right-click marks a stack for the banker")
    StackSplitFrame:Show()
    buttonFor(0, 4)._scripts.OnClick(buttonFor(0, 4), "RightButton")
    check(not BU.IsMarked(2771) and not StackSplitFrame:IsShown(), "and again unmarks it (the stack-split box the game opens is shut)")
    M.shift = false
    local texts = {}
    for _, r in ipairs(BU.ItemRows({ id = 2770, live = true })) do texts[#texts + 1] = strip(r.text) end
    check(table.concat(texts, "|"):find("Never mail this", 1, true), "the item menu offers Never mail: " .. table.concat(texts, " | "))
    -- sort uses the game's own
    BU.Sort()
    check(M.sorted == 1, "Sort uses the game's own sort")
    -- junk is grayed out and toned down
    check(buttonFor(0, 5)._desat == true and buttonFor(0, 5).fgJunk:IsShown() and not buttonFor(0, 2).fgJunk:IsShown()
        and not buttonFor(0, 2)._desat, "the gray Ruined Pelt is grayed out and toned down; the copper isn't")
    local function clickRow(rows, start)
        for _, r in ipairs(rows) do
            if strip(r.text):find(start, 1, true) == 1 then r.onClick(); return true end
        end
    end
    check(clickRow(BU.ItemRows({ id = 2835, q = 1, live = true }), "Mark as junk") and buttonFor(0, 3).fgJunk:IsShown()
        and buttonFor(0, 3)._desat, "Mark as junk tones down any item")
    local junkIds = {}
    for _, c in ipairs(BU.Junk()) do junkIds[c.id] = true end
    check(junkIds[2835] and junkIds[4865], "and Sell junk would sell it too")
    check(clickRow(BU.ItemRows({ id = 4865, q = 0, live = true }), "Not junk") and not buttonFor(0, 5).fgJunk:IsShown()
        and not BU.IsJunk(4865, 0), "Not junk keeps a gray item bright (and unsold)")
    BU.SetJunk(2835, nil); BU.SetJunk(4865, nil)

    -- the bag bar
    M.extraBags[1] = { size = 4, fam = 32, id = 22250, icon = 133640, items = { [1] = { 765, 5 } } } -- a herb bag
    M.extraBags[2] = { size = 6, fam = 0, id = 4500, icon = 133650, items = {} }                     -- an ordinary bag
    M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
    BU.Refresh()
    local function barButton(V, bag)
        for _, b in ipairs(V._bagBtns) do if b:IsShown() and b.bag == bag then return b end end
    end
    check(barButton(BU, 0) and barButton(BU, 1) and barButton(BU, 2) and barButton(BU, 3),
        "the bag bar shows the backpack, each bag, and your empty bag slots")
    check(BU.Family(BU._info[1]).name == "Herb bag" and buttonFor(1, 2).fgTint:IsShown() and not buttonFor(0, 10).fgTint:IsShown(),
        "a herb bag's empty slots are tinted green; ordinary ones aren't")
    do
        local _, _, _, _, herbY = buttonFor(1, 1):GetPoint()
        local lowest = 0
        for slot = 1, 6 do
            local _, _, _, _, yy = buttonFor(2, slot):GetPoint()
            lowest = math.min(lowest, yy)
        end
        local named = false
        for _, h in ipairs(BU._heads) do
            if h.left:IsShown() and strip(h.left:GetText()) == "Bag 1" and strip(h.right:GetText()) == "1 / 4" then named = true end
        end
        check(herbY < lowest - 41 and named, "special bags get their own row under the rest, named: " .. herbY .. " vs " .. lowest)
        local _, _, _, _, bag2Y = buttonFor(2, 1):GetPoint()
        check(bag2Y > herbY, "ordinary bags stay in the one big grid")
        ns.db.opts.bagSpecialRows = false; BU.Refresh()
        local _, _, _, _, mixedY = buttonFor(1, 1):GetPoint()
        check(mixedY > herbY, "turned off, the herb bag is mixed back in")
        ns.db.opts.bagSpecialRows = nil; BU.Refresh()
    end
    check(ns.Char().inv.bags.info[1].fam == 32, "and the bag's kind is saved, so your alts' herb bags are tinted too")
    local herbBtn = barButton(BU, 1)
    herbBtn._scripts.OnEnter(herbBtn)
    check(buttonFor(1, 1).fgGlow:IsShown() and buttonFor(1, 3).fgGlow:IsShown() and not buttonFor(0, 2).fgGlow:IsShown(),
        "hovering a bag lights up its own slots")
    herbBtn._scripts.OnLeave(herbBtn)
    check(not buttonFor(1, 1).fgGlow:IsShown(), "and stops when you move away")
    herbBtn:Click("LeftButton")
    check(BU.IsHidden(1) and buttonFor(1, 1) == nil and buttonFor(0, 2) ~= nil, "clicking a bag hides its slots")
    barButton(BU, 1):Click("LeftButton")
    check(not BU.IsHidden(1) and buttonFor(1, 1) ~= nil, "clicking it again shows them")
    BU.ShowOnly(1)
    check(BU.IsHidden(0) and BU.IsHidden(2) and not BU.IsHidden(1) and buttonFor(0, 2) == nil, "Show only this bag")
    BU.ShowOnly(1)
    check(not BU.IsHidden(0) and not BU.IsHidden(2), "and again shows them all")
    -- right-click: the game's own bag settings
    local function rowTexts(rows)
        local t = {}
        for _, r in ipairs(rows) do t[#t + 1] = strip(r.text) end
        return table.concat(t, "|")
    end
    local herbRows = rowTexts(BU.BagRows(BU, 1))
    check(herbRows:find("Hide its slots", 1, true) and not herbRows:find("Equipment", 1, true) and herbRows:find("Sell junk", 1, true),
        "a herb bag's menu: hide, ignore, but no 'assign to' (like the game): " .. herbRows)
    local rows2 = BU.BagRows(BU, 2)
    check(rowTexts(rows2):find("Assign to bag:|Equipment|Consumables|Profession Goods|Junk|Quest Items|Reagents", 1, true),
        "an ordinary bag can be assigned: " .. rowTexts(rows2))
    for _, r in ipairs(rows2) do if strip(r.text) == "Equipment" then r.onClick() end end
    check(M.bagFlags["2:" .. Enum.BagSlotFlags.ClassEquipment] == true, "Assign to Equipment uses the game's own bag setting")
    check(rowTexts(BU.BagRows(BU, 3)):find("No bag here", 1, true), "an empty bag slot says so")
    NUM_REAGENTBAG_SLOTS = 1
    BU.Refresh()
    check(BU.BagName(5) == "Empty reagent bag slot" and BU.BagName(3) == "Empty bag slot"
        and rowTexts(BU.BagRows(BU, 5)):find("No reagent bag here", 1, true), "the last slot is the reagent bag slot, and says so")
    NUM_REAGENTBAG_SLOTS = nil
    BU.Refresh()
    local backRows = BU.BagRows(BU, 0)
    for _, r in ipairs(backRows) do if strip(r.text) == "Sell junk" then r.onClick() end end
    check(M.backpackNoJunk == true and #BU.Junk() == 0, "Ignore this bag: Sell junk - the Sell junk button leaves the backpack alone")
    BU.SetIgnored(0, "junk", false)
    M.cursor = 4500
    barButton(BU, 2):Click("LeftButton")
    check(M.putInBag[1] == 32 and not BU.IsHidden(2), "dropping an item on a bag in the bar puts it in that bag")
    M.cursor = nil
    M.extraBags = {}
    M.fire("BAG_UPDATE_DELAYED"); M.advance(1)

    -- the bank: talking to a banker opens our bank window (and your bags) instead of the game's
    check(BankFrame:GetParent() ~= UIParent, "the game's bank frame is kept out of sight, before it ever shows")
    win:Hide()
    M.bankOpen = true
    BankFrame:Show() -- the game shows its frame (under our hidden parent): the visit stays open
    M.fire("BANKFRAME_OPENED"); M.advance(1)
    local me = ns.Char()
    check(me.inv.bank and me.inv.bank.size == 8 and #me.inv.bank.slots == 2 and me.bank[2589] == 20 and me.bank[818] == 2,
        "the bank's tab is saved when you visit it")
    check(BV.win and BV.win:IsShown() and win:IsShown() and BU.IsLive(BV) and buttonFor(6, 1) ~= nil and not M.gameBankHidOnUs,
        "at the banker our bank window opens, live, beside your bags")
    check(strip(BV.win.title:GetText()) == "Xeon Mana's Bank" and strip(win.title:GetText()) == "Xeon Mana's Inventory",
        "two windows: the bank and the inventory")
    -- its bag bar: the bank itself, then its bag slots, locked until bought
    local mainBtn = barButton(BV, 6)
    check(mainBtn and BU.BagName(6, BV) == "Bank" and BV._info[6].icon == ns.Inv.BANK_ICON,
        "the first button is the bank itself, with the game's bank icon (not a ?)")
    local locked = {}
    for _, b in ipairs(BV._bagBtns) do if b:IsShown() and b.locked then locked[#locked + 1] = b end end
    check(#locked == 7 and locked[1].nextUp and not locked[2].nextUp and locked[1].lock:IsShown(),
        "7 bank bag slots locked; the first is the next to buy")
    check(BV.win.buy:IsShown() and strip(BV.win.buyCost:GetText()) == "Cost: 1g", "Cost: 1g and a Purchase button, as the game's bank shows")
    do
        local n = BV._cols
        local gridW = 8 * 2 + n * 39 - 2
        check(n >= 10 and BV.win:GetWidth() == gridW and gridW >= BV._barW,
            "the slots fill the window to its right edge, however wide the bar of locked slots makes it ("
            .. n .. " columns, " .. BV.win:GetWidth() .. " wide)")
    end
    BV.win.buy:Click()
    check(M.popup and M.popup.which == "CONFIRM_BUY_BANK_TAB" and M.popup.data.bankType == Enum.BankType.Character,
        "Purchase asks with the game's own confirm")
    StaticPopupDialogs.CONFIRM_BUY_BANK_TAB.OnAccept(nil, M.popup.data)
    M.bankBag = { 4500, 10 }
    M.fire("BANK_TABS_CHANGED", Enum.BankType.Character); M.advance(1)
    local bagBtn = barButton(BV, 7)
    check(M.bankBought == 1 and bagBtn and BV._info[7].slot == 2 and BU.BagName(7, BV) == "Red Linen Bag"
        and BV._info[7].icon == 133600 + 4500 % 100, "the bought slot shows the bag in it, by its own name and icon")
    check(#me.inv.bank.order == 2 and me.inv.bank.size == 18 and me.inv.bank.bankSlots.bought == 2,
        "and the save keeps it, with the slots bought")
    M.picked = {}
    bagBtn._scripts.OnDragStart(bagBtn)
    check(M.picked[1] and M.picked[1][1] == Enum.BagIndex.Characterbanktab and M.picked[1][2] == 2,
        "dragging a bank bag picks it up from its bank bag slot")
    M.cursor = nil
    BU.Sort(BV)
    check(M.bankSorted == Enum.BankType.Character, "and Sort in it sorts the bank")
    -- leaving the banker closes what it opened
    M.fire("BANKFRAME_CLOSED"); M.bankOpen = false; M.advance(1)
    check(not BV.win:IsShown() and not win:IsShown(), "walking away closes the bank window and the bags it opened")
    BU.OpenBank()
    check(not BU.IsLive(BV) and strip(BV.win.sub:GetText()) == "" and not BV.win.buy:IsShown(),
        "away from it, the bank shows the saved copy, without Purchase: " .. strip(BV.win.sub:GetText()))
    local lockedSaved = 0
    for _, b in ipairs(BV._bagBtns) do if b:IsShown() and b.locked then lockedSaved = lockedSaved + 1 end end
    check(lockedSaved == 6 and BU.BagName(7, BV) == "Red Linen Bag", "the saved bank still shows its bag and the locked slots")
    local bankCells = BU.Cells(BV)
    check(#bankCells == 18 and bankCells[1].id == 2589 and bankCells[2].empty and bankCells[3].id == 818,
        "in its real slots, gaps included")
    local arts, shownArts = 0, 0
    for i = 1, BV._usedBg do
        if BV._bgs[i].art:IsShown() then shownArts = shownArts + 1 end
        arts = arts + 1
    end
    local emptySaved = 0
    for _, c in ipairs(bankCells) do if not c.id then emptySaved = emptySaved + 1 end end
    check(shownArts == emptySaved and shownArts > 0,
        "its empty slots show the same slot picture as the live bank (" .. shownArts .. " of " .. arts .. ")")
    -- closing our window at the banker ends the visit, like the game's
    M.bankOpen = true
    M.fire("BANKFRAME_OPENED"); M.advance(1)
    BV.win:Hide()
    check(M.bankClosedByUs == 1 and not M.bankOpen, "closing the bank window at the banker ends the visit")
    M.advance(1)
    M.bankTabs = { { ID = 6, name = "Tab 1" } }
    M.bankBag = nil
    win:Show()
    -- right-click the portrait: your bank, in its own window (and again to close it)
    BV.win:Hide()
    win.who:Click("RightButton")
    check(BV.win:IsShown() and (BV.char or ns.charKey) == ns.charKey, "right-clicking the portrait opens your bank beside your bags")
    win.who:Click("RightButton")
    check(not BV.win:IsShown(), "and right-clicking it again closes it")
    -- another character, offline
    ns.db.chars["Alt-PvP"] = { name = "Alt-PvP", class = "MAGE", money = 123456, bags = { [2589] = 7 },
        inv = { bags = { size = 4, at = time() - 300, sizes = { [0] = 4 }, order = { 0 },
            slots = { { 0, 1, 2589, 7, 1, false, false }, { 0, 3, 765, 3, 1, false, false } } } } }
    local altRow
    for _, r in ipairs(BU.PickerRows()) do if r.key == "Alt-PvP" then altRow = r end end
    check(altRow ~= nil, "the picker lists your other characters")
    altRow.onClick()
    local altCells = BU.Cells()
    check(BU.char == "Alt-PvP" and #altCells == 4 and altCells[1].id == 2589 and altCells[2].empty and not altCells[1].live
        and strip(win.title:GetText()) == "Alt's Inventory", "their bags, from the last save")
    check(buttonFor(0, 2) == nil and not win.sort:IsShown(), "your own (live) buttons are put away, and there's nothing to sort")
    local altArt = 0
    for i = 1, BU._usedBg do if BU._bgs[i].art:IsShown() then altArt = altArt + 1 end end
    check(altArt == 2 and strip(win.sub:GetText()) == "",
        "their empty slots show the same slot picture as your own, and no SAVED note (" .. altArt .. " empty)")
    win.who:Click("RightButton")
    check(BV.win:IsShown() and BV.char == "Alt-PvP" and BV.win.note:IsShown(), "their bank isn't saved yet: its window says so")
    BV.win:Hide()
    -- tooltips: who has it
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    ns.InventoryTooltip(GameTooltip, 2589)
    local tipText = table.concat(GameTooltip._lines or {}, " / ")
    check(tipText:find("Your characters have 62", 1, true) and tipText:find("Alt", 1, true) and tipText:find("35 bags, 20 bank", 1, true),
        "item tooltips say who has it: " .. strip(tipText))
    -- junk at a vendor
    BU.Pick(nil, "bags")
    M.fire("MERCHANT_SHOW"); M.advance(0.2)
    check(win.junk:IsShown() and strip(win.junk.text:GetText()):find("^Sell junk"), "at a vendor: a Sell junk button")
    M.used = {}
    BU.SellJunk(); M.advance(1)
    check(#M.used == 1 and M.used[1][1] == 0 and M.used[1][2] == 5, "it sells the gray Ruined Pelt and nothing else")
    M.fire("MERCHANT_CLOSED"); M.advance(0.2)
    check(not win.junk:IsShown(), "gone when you leave the vendor")
    local ah, vendor = BU.Worth(BU.Cells())
    check(ah >= vendor and vendor > 0, "the footer knows what your bags are worth: " .. ah .. " / " .. vendor)
    -- the cog opens Options > Bags Forever
    win.settings:Click()
    check(M.settings.opened == ns.Options.cats.bags:GetID(), "the bag window's cog opens Options at Bags Forever")
    check(win.sort.icon._atlas == "bags-button-autosort-up", "the sort button wears the game's Cleanup broom")
    win.sort._scripts.OnMouseDown(win.sort)
    check(win.sort.icon._atlas == "bags-button-autosort-down", "and presses in")
    win.sort._scripts.OnMouseUp(win.sort)
    -- see-through background
    local alphaRow
    for _, r in ipairs(BU.SettingsRows()) do if strip(r.text):find("^Background: 50%%") then alphaRow = r end end
    check(alphaRow ~= nil, "Settings has a background transparency row, at 50% to start")
    alphaRow.onClick()
    check(ns.db.opts.bagAlpha == 0.4 and math.abs(win.bg:GetAlpha() - 0.4) < 0.001, "clicking it makes the background more see-through (40%)")
    ns.db.opts.bagAlpha = nil
    -- money everywhere shows coin icons
    local m = ns.Money(10797)
    check(m:find("UI-GoldIcon", 1, true) and m:find("UI-SilverIcon", 1, true) and strip(m) == "1g 7s" and ns.StripCodes(m) == "1g 7s",
        "money shows coin icons (plain text still reads 1g 7s)")
    -- closing ours closes the game's too, so B works next time
    BU.Close(); M.advance(0.2)
    check(not ContainerFrameCombinedBags:IsShown(), "closing the window closes the game's bags too")
    ToggleAllBags(); M.advance(0.2)
    check(win:IsShown(), "and B opens it again")
    ToggleAllBags(); M.advance(0.2)
    check(not win:IsShown(), "and closes it")
    -- switching it off gives the game its bags back
    ns.db.opts.bagUI = false; BU.Uninstall()
    check(ContainerFrameCombinedBags:GetParent() == UIParent, "turned off, the game's bags are back where they were")
    OpenAllBags(); M.advance(0.2)
    check(not win:IsShown(), "and ours stays shut")
    CloseAllBags(); M.advance(0.2)
    ns.db.opts.bagUI = true; BU.Install()
    ns.db.chars["Alt-PvP"] = nil
    ns.db.opts.bagHidden = nil
    ns.db.opts.mailNoBanker = nil
    ns.db.opts.bagJunk = nil
    BU.char, BU.where = nil, "bags"
    M.bags, M.player.money = savedBags, savedMoney
    M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
end

out("== bag window: item slots, keyring, faces, guild bank")
do
    local BU = ns.BagUI
    local savedBags = M.bags
    M.bags = { { 774, 3 }, { 4865, 2 }, { 12348, 1 }, { 2589, 5 }, { 6948, 1, true }, { 5000, 1 } }
    M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
    BU.Open(); BU.Refresh()
    local function btn(bag, slot)
        for _, f in ipairs(M.frames) do
            if f._shown and f.fgCell and f.fgCell.live and f.fgCell.bag == bag and f.fgCell.slot == slot then return f end
        end
    end
    local mal = btn(0, 1)
    check(mal and mal.fgColor:IsShown() and mal.fgWhy == "quality" and mal.fgColor.g == 1,
        "an uncommon gem glows green at its edges (Color by quality)")
    check(btn(0, 6).fgWhy == "quest" and btn(0, 6).fgColor.r == 1 and btn(0, 6).fgColor.g > 0.8, "a quest item glows gold")
    check(btn(0, 2).fgCoin:IsShown() and not mal.fgCoin:IsShown(), "junk gets a little gold coin in its corner")
    M.cantUse[12348] = true
    BU.ResetUnusable(); BU.Refresh()
    local axe = btn(0, 3)
    check(axe.fgWhy == "unusable" and axe.fgColor.r == 1 and axe.fgColor.g < 0.2, "gear you can't use glows red")
    M.cantUse[774] = true -- red text on a gem's tooltip (like "Locked" on a lockbox)
    BU.ResetUnusable(); BU.Refresh()
    check(btn(0, 1).fgWhy ~= "unusable", "but only gear and recipes: red text on anything else doesn't count")
    M.cantUse[774] = nil
    BU.ResetUnusable(); BU.Refresh()
    M.pawnUp = { ["0:3"] = true }
    BU.Refresh()
    check(btn(0, 3).fgUp:IsShown() and not mal.fgUp:IsShown(), "Pawn's upgrades get a green arrow")
    M.pawnUp, M.cantUse = nil, {}
    BU.ResetUnusable()
    M.newItems["0:4"] = true
    BU.Refresh()
    local cloth = btn(0, 4)
    local _, _, _, _, newY = cloth:GetPoint()
    local _, _, _, _, oldY = mal:GetPoint()
    check(cloth.fgNewF:IsShown() and newY == oldY, "new loot flashes where it is (no row of its own)")
    cloth._scripts.OnEnter(cloth)
    check(not cloth.fgNewF:IsShown() and not cloth.fgCell.new and not M.newItems["0:4"], "and stops once you hover it")
    ns.db.opts.bagQuality = false
    BU.Refresh()
    check(not btn(0, 1).fgColor:IsShown(), "Color by quality off: no glow")
    ns.db.opts.bagQuality = nil
    BU.Refresh()
    ns.db.opts.bagGlow = 100
    BU.Refresh()
    check(math.abs(btn(0, 1).fgColor.a - 0.8) < 1e-9, "Glow brightness 100%: 80% strength, a touch under full")
    ns.db.opts.bagGlow = nil
    -- every slot glowed blue (2026-11-21): the template's store highlight starts shown
    local blue = 0
    for _, bb in ipairs(BU._live) do
        if bb.BattlepayItemTexture and bb.BattlepayItemTexture:IsShown() then blue = blue + 1 end
        if bb.BagIndicator and bb.BagIndicator:IsShown() then blue = blue + 1 end
    end
    check(#BU._live > 0 and btn(0, 1).BattlepayItemTexture ~= nil and blue == 0,
        "no slot shows the game's blue store highlight (" .. blue .. " lit)")
    check(cloth.fgNew.b == 1 and cloth.fgNew.r < 0.5, "new loot glows blue")
    BU.HighlightBag(BU, 0)
    check(btn(0, 1).fgGlow:IsShown() and btn(0, 1).fgGlow.b < 1 and btn(0, 1).fgGlow.r == 1 and btn(0, 1).fgGlow.t[1]._gradient ~= nil,
        "hovering a bag lights its slots' edges warm white (blue is new loot only), fading toward the middle")
    BU.HighlightBag(BU, nil)
    -- the bag-hover glow only lasts while the mouse is on that bag (2026-11-21:
    -- a whole bag stayed lit blue after the mouse had left)
    local barBtn
    for _, bb in ipairs(BU._bagBtns) do if bb:IsShown() and bb.bag == 0 then barBtn = bb end end
    barBtn.IsMouseOver = function() return true end
    barBtn._scripts.OnEnter(barBtn)
    BU.Refresh()
    check(btn(0, 1).fgGlow:IsShown(), "hovering a bag keeps its slots lit through a refresh")
    barBtn.IsMouseOver = function() return false end -- left without the game saying so
    BU.Refresh()
    check(not btn(0, 1).fgGlow:IsShown() and BU.hot == nil, "once the mouse has gone, the next refresh puts them out")
    barBtn.IsMouseOver = function() return true end
    barBtn._scripts.OnEnter(barBtn)
    barBtn:Hide()
    barBtn._scripts.OnHide(barBtn)
    check(not btn(0, 1).fgGlow:IsShown() and BU.hot == nil, "and so does the bag's button going away under the mouse")
    barBtn.IsMouseOver = nil
    BU.Refresh()
    -- moving an item shows at once, not after the half-second bag rescan
    M.bags[1], M.bags[2] = M.bags[2], M.bags[1]
    M.fire("BAG_UPDATE_DELAYED"); M.advance(0.02)
    check(btn(0, 1).fgCell.id == 4865 and btn(0, 2).fgCell.id == 774, "a moved item shows in its new slot on the next frame")
    M.bags[1], M.bags[2] = M.bags[2], M.bags[1]
    M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
    -- money: soulbound and bind-on-pickup things count at a vendor, never at auction
    local a1, v1 = BU.Worth({ { id = 2589, count = 1, bound = true } })
    check(a1 == 0 and v1 == 13, "a soulbound item counts at a vendor, not at auction")
    local a2, v2 = BU.Worth({ { id = 900001, count = 1 } })
    check(a2 == 0 and v2 == 401 and ns.Untradeable(900001) and not ns.Untradeable(2589),
        "nor does a bind-on-pickup one")
    -- the keyring
    M.keyring = { size = 4, items = { [1] = { 5001, 1 } } }
    M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
    BU.Refresh()
    check(BU.win.keys:IsShown() and BU.win.keys.used == 1 and BU.win.keys.size == 4,
        "the keyring sits at the right end of the bag bar")
    check(btn(Enum.BagIndex.Keyring, 1) == nil, "its slots stay hidden until you click it")
    BU.win.keys:Click()
    check(btn(Enum.BagIndex.Keyring, 1) ~= nil and ns.db.opts.bagKeys == true, "click it: a Keyring row with your keys")
    local slotsText = strip(BU.win.slots:GetText())
    check(slotsText:find("^6 / 16"), "keys don't count toward your bag slots: " .. slotsText)
    check(ns.Char().inv.bags.sizes[Enum.BagIndex.Keyring] == 4, "and the keyring is saved with your bags")
    BU.win.keys:Click()
    ns.db.opts.bagKeys = nil
    M.keyring = nil
    -- faces
    check(ns.Char().race == "Orc" and ns.Char().sex == 2, "each character's race and gender are saved, for their face")
    check(BU.win.who.icon._atlas == "raceicon-orc-male", "the portrait shows your character's face")
    check(ns.Inv.FaceText(ns.Char()):find("raceicon%-orc%-male"), "and tooltips put each character's face by their name")
    local faceRow
    for _, r in ipairs(BU.PickerRows()) do if r.key == ns.charKey then faceRow = r end end
    check(faceRow and faceRow.face and faceRow.face.race == "Orc", "the character list shows faces too")
    -- the window: the game's close button, bare icons, fitted width
    check(BU.win.close:GetWidth() == 22 and BU.win.sort:GetWidth() == 20 and BU.win.searchBtn:GetWidth() == 16,
        "the gold-X close button, and search, sort and settings at their icon size")
    ns.db.opts.bagCols = 8
    BU.Refresh()
    check(BU.win:GetWidth() < 340, "8 columns: the window fits them, no wasted space (" .. BU.win:GetWidth() .. ")")
    ns.db.opts.bagCols = nil
    ns.db.opts.bagScale = 0.8
    BU.Refresh()
    check(BU.win:GetScale() == 0.8, "the Scale slider sizes the window")
    ns.db.opts.bagScale = nil
    BU.Refresh()
    -- the guild bank
    M.guild = { name = "Forever Friends", tabs = {
        { name = "Mats", icon = 133000, items = { [1] = { 2589, 20 }, [5] = { 818, 2 } } },
        { name = "Gear", icon = 133001, items = {} } } }
    M.fire("GUILDBANKFRAME_OPENED"); M.advance(1)
    M.fire("GUILDBANKFRAME_CLOSED"); M.advance(1)
    local gkey = ns.Char().guild
    check(M.guildQueried == 2 and gkey and ns.db.guilds[gkey].tabs[1].slots[2][2] == 818,
        "the guild bank is saved each visit, every tab you can see")
    BU.Refresh()
    check(BU.win.tabGuild:IsShown(), "a Guild bank tab down the side of your bags")
    BU.Pick(nil, "guild")
    local BV = BU.bank
    check(BV.win:IsShown() and BV.where == "guild" and strip(BV.win.title:GetText()) == "Forever Friends Bank",
        "it opens in the bank window: " .. strip(BV.win.title:GetText()))
    local gc = BU.Cells(BV)
    check(#gc == 196 and gc[1].id == 2589 and gc[5].id == 818 and BU.BagName(101, BV) == "Mats",
        "its tabs, 98 slots each, by name")
    BU.Pick(nil, "bank")
    check(BV.where == "bank", "and Bank switches it back")
    BV.win:Hide()
    ns.db.guilds = nil
    ns.Char().guild = nil
    M.guild = nil
    M.bags = savedBags
    M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
end

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

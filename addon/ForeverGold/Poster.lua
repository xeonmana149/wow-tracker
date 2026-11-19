-- Forever Gold - the post queue and the cancel queue
--
-- The logic behind the auction window's Sell and Auctions tabs (the window
-- itself is AuctionUI.lua).
--
-- Post queue: every item in your bags you've ticked is price-checked one at
-- a time, and each gets a proposed listing from your settings (undercut,
-- how many go in each listing, how many listings, how long). Then the Post
-- button posts the next proposed listing each time you click it. The game
-- only lets an addon post as the direct result of a click, so nothing here
-- ever posts by itself.
--
-- Cancel queue: your auctions are checked against the cheapest listing that
-- isn't yours, and "Cancel next undercut" cancels them one click at a time,
-- so you can relist them lower.
--
-- Prices are decided by ns.DecidePrice (Sell.lua): never below your floor
-- (what a vendor pays or what it costs to make, plus the cut), lowballs
-- ignored, never undercutting yourself.

local _, ns = ...
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local AH = C_AuctionHouse
local CUT = ns.AH_CUT
local STALE = 5 * 60    -- re-check an item's price if it's older than this when posting
local LOOKUP_WAIT = 8   -- seconds to wait for the auction house to answer a price check

local GREY = "|cff9a9a9a"

local P = { entries = {}, state = "idle", owned = {}, ownedState = "idle" }
ns.Poster = P

local function plural(n, word)
    return n .. " " .. word .. (n == 1 and "" or "s")
end

local function opts()
    return ns.db.opts
end

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------

P.UNDERCUT = { { "copper", "1 copper" }, { "1%", "1%" }, { "5%", "5%" } }
P.QTY = { { "stack", "A full stack" }, { "10", "10" }, { "5", "5" }, { "one", "1" }, { "all", "Everything" } }
P.CAP = { { "all", "All of it" }, { "1", "1 listing" }, { "2", "2 listings" }, { "3", "3 listings" }, { "5", "5 listings" } }
P.DURATION = { { 1, "12 hours" }, { 2, "24 hours" }, { 3, "48 hours" } }
local UNDERCUT_PCT = { copper = 0, ["1%"] = 0.01, ["5%"] = 0.05 }

local function labelOf(list, value)
    for _, v in ipairs(list) do
        if v[1] == value then
            return v[2]
        end
    end
    return list[1][2]
end

local function nextOf(list, value)
    for i, v in ipairs(list) do
        if v[1] == value then
            return (list[i + 1] or list[1])[1]
        end
    end
    return list[1][1]
end

function P.Setting(which)
    local o = opts()
    if which == "undercut" then
        return o.postUndercut or "copper", labelOf(P.UNDERCUT, o.postUndercut or "copper")
    elseif which == "qty" then
        return o.postQty or "stack", labelOf(P.QTY, o.postQty or "stack")
    elseif which == "cap" then
        return o.postCap or "all", labelOf(P.CAP, o.postCap or "all")
    elseif which == "duration" then
        return o.sellDuration or 2, labelOf(P.DURATION, o.sellDuration or 2)
    end
end

-- Moves a setting to its next value and re-plans everything already checked.
function P.CycleSetting(which)
    local o = opts()
    if which == "undercut" then
        o.postUndercut = nextOf(P.UNDERCUT, o.postUndercut or "copper")
    elseif which == "qty" then
        o.postQty = nextOf(P.QTY, o.postQty or "stack")
    elseif which == "cap" then
        o.postCap = nextOf(P.CAP, o.postCap or "all")
    elseif which == "duration" then
        o.sellDuration = nextOf(P.DURATION, o.sellDuration or 2)
    end
    for _, e in ipairs(P.entries) do
        if e.listings then
            P.Plan(e)
        end
    end
    ns.Fire("POSTER")
end

----------------------------------------------------------------------
-- Money typed by hand: "1g 20s 5c", "1.5g", "90c", "90" (copper)
----------------------------------------------------------------------

function ns.ParseMoney(text)
    if type(text) ~= "string" then
        return nil
    end
    local s = text:lower():gsub(",", "")
    local total, found = 0, false
    for num, unit in s:gmatch("(%d+%.?%d*)%s*([gsc]?)") do
        local n = tonumber(num)
        if n then
            found = true
            if unit == "g" then
                total = total + n * 10000
            elseif unit == "s" then
                total = total + n * 100
            else
                total = total + n
            end
        end
    end
    if not found then
        return nil
    end
    return floor(total + 0.5)
end

----------------------------------------------------------------------
-- Bags
----------------------------------------------------------------------

function ns.FindInBags(id)
    if not (C_Container and ItemLocation and ItemLocation.CreateFromBagAndSlot) then
        return nil, 0
    end
    local first, count = nil, 0
    local last = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0)
    for bag = 0, last do
        local slots = ns.try(C_Container.GetContainerNumSlots, bag) or 0
        for slot = 1, slots do
            local info = ns.try(C_Container.GetContainerItemInfo, bag, slot)
            if type(info) == "table" and info.itemID == id and not info.isBound and not info.isLocked then
                count = count + (info.stackCount or 1)
                if not first then
                    first = ItemLocation:CreateFromBagAndSlot(bag, slot)
                end
            end
        end
    end
    return first, count
end

local function throttleReady()
    local ok, ready = pcall(AH.IsThrottledMessageSystemReady)
    return (not ok) or ready
end

----------------------------------------------------------------------
-- Price lookups: one item at a time, in order
--
-- Each lookup is { id =, key =, commodity = }, and its callback gets the
-- listings ({ p = price each, q = quantity, mine = true|nil }, cheapest
-- first) or nil if the auction house didn't answer.
----------------------------------------------------------------------

local lookups, current = {}, nil

function ns.AHBusy()
    return current ~= nil or #lookups > 0 or P.state == "posting" or P.state == "confirm" or P.state == "verify"
end

local function readListings(l)
    local out = {}
    if l.commodity then
        local n = ns.try(AH.GetNumCommoditySearchResults, l.id) or 0
        for i = 1, min(n, 80) do
            local r = ns.try(AH.GetCommoditySearchResultInfo, l.id, i)
            if type(r) == "table" and r.unitPrice and r.unitPrice > 0 then
                out[#out + 1] = { p = r.unitPrice, q = r.quantity or 1,
                    mine = (r.containsOwnerItem or r.containsAccountItem) and true or nil,
                    -- How much of this price tier is yours (the rest is someone else's).
                    own = r.numOwnerItems or ((r.containsOwnerItem or r.containsAccountItem) and (r.quantity or 1) or 0),
                    sellers = r.totalNumberOfOwners, owner = r.owners and r.owners[1], left = r.timeLeftSeconds }
            end
        end
    else
        local n = ns.try(AH.GetNumItemSearchResults, l.key) or 0
        -- Auctions with no buyout are kept apart in out.bids: you only get
        -- them by winning the bid, so they're never a price to buy at or to
        -- undercut. The list itself is buyouts only.
        out.bidOnly, out.bids = 0, {}
        for i = 1, min(n, 80) do
            local r = ns.try(AH.GetItemSearchResultInfo, l.key, i)
            if type(r) == "table" then
                local q = max(1, r.quantity or 1)
                local mine = (r.containsOwnerItem or r.containsAccountItem) and true or nil
                -- The next bid that would be accepted, for the whole auction.
                local bid = r.minBid or r.bidAmount
                bid = (bid and bid > 0) and bid or nil
                if r.buyoutAmount and r.buyoutAmount > 0 then
                    out[#out + 1] = { p = r.buyoutAmount / q, q = q, mine = mine, own = mine and q or 0,
                        aid = r.auctionID, buyout = r.buyoutAmount, bid = bid, owner = r.owners and r.owners[1],
                        left = r.timeLeftSeconds, band = r.timeLeft, link = r.itemLink }
                else
                    out.bidOnly = out.bidOnly + 1
                    out.bids[#out.bids + 1] = { bidOnly = true, q = q, bid = bid, mine = mine, aid = r.auctionID,
                        left = r.timeLeftSeconds, band = r.timeLeft, link = r.itemLink }
                end
            end
        end
        table.sort(out.bids, function(a, b) return (a.bid or 0) < (b.bid or 0) end)
    end
    table.sort(out, function(a, b) return a.p < b.p end)
    return out
end

local pump

local function finishLookup(listings)
    local l = current
    current = nil
    if l then
        local ok, err = pcall(l.callback, listings)
        if not ok then
            ns.Err("lookup", err)
        end
    end
    C_Timer.After(0.15, ns.Guard("lookup", pump))
end

pump = function()
    if current or #lookups == 0 or not ns.ahOpen then
        return
    end
    -- A full price scan uses the same allowance; wait for it.
    if (ns.scan and ns.scan.active) or not throttleReady() then
        ns.Later("lookup-pump", 0.5, pump)
        return
    end
    current = table.remove(lookups, 1)
    local sorts = {}
    local SO = Enum and Enum.AuctionHouseSortOrder
    if SO then
        sorts[1] = { sortOrder = current.commodity and SO.Price or (SO.Buyout or SO.Price), reverseSort = false }
    end
    current.asked = GetTime()
    local asked = current.asked
    if not pcall(AH.SendSearchQuery, current.key, sorts, true) then
        finishLookup(nil)
        return
    end
    C_Timer.After(LOOKUP_WAIT, ns.Guard("lookup-timeout", function()
        if current and current.asked == asked then
            finishLookup(nil)
        end
    end))
end

function ns.AHLookup(l, callback)
    l.callback = callback
    lookups[#lookups + 1] = l
    pump()
end

local function cancelLookups()
    lookups, current = {}, nil
end

ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
    if current and current.commodity and itemID == current.id then
        finishLookup(readListings(current))
    end
end)

ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
    if current and not current.commodity and type(itemKey) == "table" and itemKey.itemID == current.id then
        finishLookup(readListings(current))
    end
end)

----------------------------------------------------------------------
-- The post queue
----------------------------------------------------------------------

-- Ticked by you (remembered per item), or else ticked when the Sell tab of
-- the main window says it's worth auctioning.
function P.IsPicked(id, recommended)
    local pick = opts().postPick and opts().postPick[id]
    if pick ~= nil then
        return pick
    end
    return recommended and true or false
end

function P.SetPicked(id, on)
    opts().postPick = opts().postPick or {}
    opts().postPick[id] = on and true or false
    for _, e in ipairs(P.entries) do
        if e.id == id then
            e.picked = on and true or false
        end
    end
    ns.Fire("POSTER")
end

-- Everything in your bags that could go on the auction house, recommended
-- first. Keeps the price checks already done for items still there.
function P.Rebuild()
    local old = {}
    for _, e in ipairs(P.entries) do
        old[e.id] = e
    end
    local c = ns.Char()
    local advice = ns.BagAdvice()
    local rank = {}
    for i, b in ipairs(advice.ah) do
        rank[b.id] = i
    end
    local list, names = {}, {}
    for id, count in pairs(c.bags or {}) do
        if not (c.bound and c.bound[id]) and count > 0 then
            local it = ns.Item(id)
            -- Grey junk never goes to the auction house.
            if not (it and it.q == 0) then
                local e = old[id] or { id = id, status = "new" }
                e.have = count
                e.recommended = rank[id] ~= nil
                e.rank = rank[id]
                e.picked = P.IsPicked(id, e.recommended)
                if e.status == "done" and e.posted and e.posted < (e.posts or 0) then
                    e.status = "ready"
                end
                list[#list + 1] = e
                if not e.rank then
                    names[id] = ns.ItemName(id)
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if (a.rank ~= nil) ~= (b.rank ~= nil) then
            return a.rank ~= nil
        end
        if a.rank and b.rank then
            return a.rank < b.rank
        end
        return names[a.id] < names[b.id]
    end)
    P.entries = list
    return list
end

local function maxStack(id)
    local it = ns.Item(id)
    return (C_Item and ns.try(C_Item.GetItemMaxStackSizeByID, id)) or (it and it.st) or 20
end

-- From the settings: how many go in each listing and how many listings.
function P.Plan(e)
    local d = ns.DecidePrice(e.listings or {}, {
        commodity = e.commodity,
        step = e.step or 1,
        floor = e.floor,
        usual = e.usual,
        usualDays = e.usualDays,
        last = ns.LastPrice(e.id),
        cost = e.cost,
        undercutPct = UNDERCUT_PCT[opts().postUndercut or "copper"] or 0,
    })
    e.decision = d
    if not e.priceSet then
        e.price = d.price
    end
    local have = max(1, e.have or 1)
    local mode = opts().postQty or "stack"
    local per
    if mode == "all" then
        per = have
    elseif mode == "one" then
        per = 1
    elseif not e.commodity then
        -- Gear and other unstackable things go up one per listing.
        per = 1
    elseif mode == "stack" then
        per = min(have, maxStack(e.id))
    else
        per = min(have, tonumber(mode) or 1)
    end
    if not e.perSet then
        e.per = max(1, per)
    end
    local need = ceil(have / e.per)
    local cap = tonumber(opts().postCap or "all")
    e.posts = cap and min(cap, need) or need
    e.posted = e.posted or 0
    e.lowest = nil
    for _, l in ipairs(e.listings or {}) do
        if not l.mine then
            e.lowest = l.p
            break
        end
    end
    if e.status ~= "done" and e.status ~= "skipped" then
        if e.priceSet then
            e.status = (e.price and e.price >= (e.floor or 0)) and "ready" or "floor"
        elseif d.ok then
            e.status = "ready"
        else
            e.status = d.why == "floor" and "floor" or "noprice"
        end
    end
    return e
end

-- Sets up one entry for a price check: where it is, whether it can be sold,
-- and how the auction house knows it.
local function prepare(e)
    local loc, have = ns.FindInBags(e.id)
    if not loc then
        e.status, e.note = "gone", "Not in your bags any more."
        return false
    end
    if AH.IsSellItemValid and not ns.try(AH.IsSellItemValid, loc, false) then
        e.status, e.note = "cantsell", "Can't be sold on the auction house."
        return false
    end
    local status = ns.try(AH.GetItemCommodityStatus, loc)
    local S = Enum and Enum.ItemCommodityStatus or {}
    local COMMODITY, ITEM = S.Commodity or 2, S.Item or 1
    if status ~= COMMODITY and status ~= ITEM then
        e.status, e.note = "error", "The game was still loading this item. Check again."
        return false
    end
    e.commodity = status == COMMODITY
    e.loc = loc
    e.have = have
    if e.commodity then
        e.key = ns.try(AH.MakeItemKey, e.id)
    else
        e.key = ns.try(AH.GetItemKeyFromItem, loc)
        e.have = max(1, ns.try(AH.GetAvailablePostCount, loc) or have)
    end
    if not e.key then
        e.status, e.note = "cantsell", "The auction house wouldn't accept it."
        return false
    end
    e.step = (AH.SupportsCopperValues and ns.try(AH.SupportsCopperValues)) and 1 or 100
    local floorPrice, floorWhy, protects = ns.SellFloor(e.id)
    e.floor, e.floorWhy, e.protects = floorPrice, floorWhy, protects
    e.usual, e.usualDays = ns.UsualPrice(e.id)
    local rec = ns.RecipeFor(e.id)
    e.cost = rec and ns.EvalRecipe(rec).cost or nil
    return true
end

local function checkEntry(e, done)
    e.note = nil
    if not prepare(e) then
        done()
        return
    end
    e.status = "checking"
    ns.AHLookup({ id = e.id, key = e.key, commodity = e.commodity }, function(listings)
        if not listings then
            e.status, e.note = "error", "The auction house didn't answer. Check again."
        else
            e.listings = listings
            e.checkedAt = GetTime()
            P.Plan(e)
        end
        done()
    end)
    ns.Fire("POSTER")
end

-- Price-checks every ticked item that hasn't been checked yet (or all of
-- them again with `again`).
function P.CheckAll(again)
    if not ns.ahOpen then
        ns.Print("open the auction window at an auctioneer first.")
        return
    end
    if P.state == "posting" or P.state == "confirm" or P.state == "verify" then
        return
    end
    P.Rebuild()
    local todo = {}
    for _, e in ipairs(P.entries) do
        if e.picked and (again or not e.checkedAt or e.status == "error" or e.status == "new") then
            if again then
                e.posted, e.priceSet, e.perSet = 0, nil, nil
                e.status = "new"
            end
            todo[#todo + 1] = e
        end
    end
    if #todo == 0 then
        P.state = P.NextEntry() and "ready" or "idle"
        ns.Fire("POSTER")
        return
    end
    P.state = "checking"
    P.checking = { done = 0, total = #todo }
    local i = 0
    local function step()
        i = i + 1
        local e = todo[i]
        if not e or P.state ~= "checking" then
            if P.state == "checking" then
                P.state = P.NextEntry() and "ready" or "done"
            end
            P.checking = nil
            ns.Fire("POSTER")
            return
        end
        P.checking.done = i - 1
        checkEntry(e, function()
            ns.Fire("POSTER")
            step()
        end)
    end
    step()
end

-- Price-checks just one item (the main window's Sell button on a bag row).
function P.CheckOne(e)
    if not e or not ns.ahOpen then
        return
    end
    if P.state == "checking" or P.state == "posting" or P.state == "confirm" or P.state == "verify" then
        return
    end
    e.posted, e.priceSet, e.perSet = 0, nil, nil
    e.status = "new"
    P.state = "checking"
    P.checking = { done = 0, total = 1 }
    checkEntry(e, function()
        if P.state == "checking" then
            P.state = P.NextEntry() and "ready" or "done"
        end
        P.checking = nil
        ns.Fire("POSTER")
    end)
end

function P.StopChecking()
    if P.state == "checking" then
        cancelLookups()
        P.state = P.NextEntry() and "ready" or "idle"
        P.checking = nil
        ns.Fire("POSTER")
    end
end

-- The next listing the Post button will make.
function P.NextEntry()
    for _, e in ipairs(P.entries) do
        if P.Postable(e) then
            return e
        end
    end
    return nil
end

function P.Skip(e)
    e = e or P.NextEntry()
    if e then
        e.status = "skipped"
        if P.state ~= "checking" then
            P.state = P.NextEntry() and "ready" or "done"
        end
        ns.Fire("POSTER")
    end
end

function P.Unskip(e)
    if e and e.status == "skipped" then
        e.status = "new"
        if e.listings then
            P.Plan(e)
        end
        if P.state == "done" or P.state == "idle" then
            P.state = P.NextEntry() and "ready" or P.state
        end
        ns.Fire("POSTER")
    end
end

-- Your own price for one item (copper each), or nil to go back to the
-- proposed one.
function P.SetPrice(e, copper)
    if not e then
        return
    end
    if copper and copper > 0 then
        e.price = floor(copper / (e.step or 1)) * (e.step or 1)
        e.priceSet = true
    else
        e.priceSet = nil
    end
    if e.listings then
        P.Plan(e)
    end
    if P.state == "done" or P.state == "idle" then
        P.state = P.NextEntry() and "ready" or P.state
    end
    ns.Fire("POSTER")
end

function P.SetPer(e, n)
    if not e then
        return
    end
    e.per = max(1, min(e.have or 1, floor(n)))
    e.perSet = true
    P.Plan(e)
    ns.Fire("POSTER")
end

local function recordPost(id, qty, price)
    local posts = ns.db.posts
    if type(posts) ~= "table" then
        posts = {}
        ns.db.posts = posts
    end
    table.insert(posts, 1, { id = id, q = qty, p = price, t = time() })
    posts[201] = nil
end

local function postable(e)
    return e and e.picked and e.status == "ready" and (e.posted or 0) < (e.posts or 0) and (e.have or 0) > 0
end
P.Postable = postable

-- Posts one listing: `target` if it's ready (the row you picked), else the
-- next one in the queue. Only ever called from a click.
local watchPost

function P.PostNext(target)
    if P.state == "confirm" and P.pending then
        if not ns.AHReadyToPost() then
            P.message = "The auction house is busy. Confirm comes back as soon as it's ready."
            ns.Fire("POSTER")
            return
        end
        local a = P.pending
        local ok
        if a.commodity then
            ok = pcall(AH.ConfirmPostCommodity, a.loc, a.duration, a.qty, a.price)
        else
            ok = pcall(AH.ConfirmPostItem, a.loc, a.duration, a.qty, nil, a.price)
        end
        P.state = ok and "posting" or "ready"
        P.message = (not ok) and "The auction house refused the confirmation." or nil
        if ok then
            watchPost(a)
        else
            P.pending = nil
        end
        ns.Fire("POSTER")
        return
    end
    if P.state ~= "ready" then
        return
    end
    local e = postable(target) and target or P.NextEntry()
    if not e then
        P.state = "done"
        ns.Fire("POSTER")
        return
    end
    if GetTime() - (e.checkedAt or 0) > STALE then
        P.message = "The price for " .. ns.ItemName(e.id) .. " was over 5 minutes old, so it's being checked again. Press Post once it's done."
        P.state = "checking"
        checkEntry(e, function()
            P.state = P.NextEntry() and "ready" or "done"
            ns.Fire("POSTER")
        end)
        return
    end
    if not ns.AHReadyToPost() then
        P.message = "The auction house is busy. Post comes back as soon as it's ready."
        ns.Fire("POSTER")
        return
    end
    local loc, have = ns.FindInBags(e.id)
    if not loc then
        e.status, e.note = "gone", "Not in your bags any more."
        P.state = P.NextEntry() and "ready" or "done"
        ns.Fire("POSTER")
        return
    end
    if not e.commodity then
        have = max(1, ns.try(AH.GetAvailablePostCount, loc) or have)
    end
    e.have = min(e.have or have, have)
    local qty = max(1, min(e.per or 1, e.have))
    local duration = opts().sellDuration or 2
    local price = e.price
    local args = { id = e.id, loc = loc, duration = duration, qty = qty, price = price, commodity = e.commodity, entry = e,
        before = ns.BagTotal(e.id) }
    local ok, needsConfirm
    if e.commodity then
        ok, needsConfirm = pcall(AH.PostCommodity, loc, duration, qty, price)
    else
        -- Unstackable things: the buyout is for the one item.
        ok, needsConfirm = pcall(AH.PostItem, loc, duration, qty, nil, price)
    end
    P.pending = args
    if not ok then
        P.message = "The game blocked that post. Try it from the game's own auction window and tell me with /gold debug."
        ns.Err("poster-post", needsConfirm)
        P.pending = nil
        ns.Fire("POSTER")
        return
    end
    P.message = nil
    if needsConfirm then
        P.state = "confirm"
        P.message = "The auction house wants you to confirm this price. Press Post again to confirm."
    else
        P.state = "posting"
        watchPost(args)
    end
    ns.Fire("POSTER")
end

-- The post went up: count it once.
local function posted(a, note)
    if P.pending ~= a and P.unsure ~= a then
        return
    end
    P.pending = nil
    local e = a.entry
    if P.unsure == a then
        -- It turned out fine after all: undo the skip it was given.
        P.unsure = nil
        if e.status == "skipped" then
            e.status, e.note = "ready", nil
        end
    end
    e.posted = (e.posted or 0) + 1
    e.have = max(0, (e.have or 0) - a.qty)
    recordPost(a.id, a.qty, a.price)
    P.lastPosted = { id = a.id, qty = a.qty, price = a.price }
    P.postedCount = (P.postedCount or 0) + 1
    if e.posted >= (e.posts or 0) or e.have <= 0 then
        e.status = "done"
    end
    if P.state == "posting" or P.state == "confirm" or P.state == "verify" or P.state == "ready" or P.state == "done" then
        P.state = P.NextEntry() and "ready" or "done"
    end
    P.message = note
    ns.Fire("POSTER")
end

-- No answer in time, or the auction house may have dropped the post: the
-- bags settle whether it went up before Post can be pressed again, so a slow
-- answer never turns into a second listing.
local function verify(a, why)
    if P.pending ~= a or (P.state ~= "posting" and P.state ~= "verify") then
        return
    end
    P.state = "verify"
    P.message = why
    ns.CheckPostInBags(a, function(went)
        if P.pending ~= a or P.state ~= "verify" then
            return
        end
        if went then
            posted(a, "That one went up - the auction house was just slow to say so.")
            return
        end
        P.pending = nil
        if went == false then
            P.message = "That post didn't go through - nothing left your bags. Press Post when it's ready."
        else
            -- Can't tell: don't risk listing it twice.
            local e = a.entry
            e.status = "skipped"
            e.note = "I couldn't tell whether the last post of this went up. Check the Auctions tab, then Unskip it to post more."
            P.unsure = a
            P.message = "I couldn't tell whether " .. ns.ItemName(a.id) .. " went up, so it's skipped. Check the Auctions tab."
        end
        P.state = P.NextEntry() and "ready" or "done"
        ns.Fire("POSTER")
    end)
    ns.Fire("POSTER")
end

watchPost = function(a)
    a.at = GetTime()
    local stamp = a.at
    C_Timer.After(10, ns.Guard("poster-timeout", function()
        if P.pending == a and a.at == stamp and P.state == "posting" then
            verify(a, "No answer from the auction house yet - checking your bags to see whether it went up...")
        end
    end))
end

ns.On("AUCTION_HOUSE_AUCTION_CREATED", function()
    local a = P.pending
    if a and (P.state == "posting" or P.state == "confirm" or P.state == "verify") then
        posted(a)
    elseif P.unsure then
        posted(P.unsure, "It did go up after all.")
    end
end)

ns.On("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
    if P.pending and P.state == "posting" then
        verify(P.pending, "The auction house said that was too fast. Checking whether the post went through...")
    end
end)

ns.On("AUCTION_HOUSE_SHOW_ERROR", function(err)
    if not (P.pending and P.state == "posting") then
        return
    end
    if ns.AHBusyError(err) then
        verify(P.pending, "The auction house was busy. Checking whether the post went through...")
    else
        P.pending = nil
        P.state = P.NextEntry() and "ready" or "done"
        P.message = "The auction house refused that post - the red message on screen says why."
        ns.Fire("POSTER")
    end
end)

-- The auction house asking "are you sure?" about a price far from normal.
-- Blizzard's own popup only knows about its Sell tab, so ours takes over.
ns.On("AUCTION_HOUSE_POST_WARNING", function()
    if P.pending and P.state == "posting" then
        P.state = "confirm"
        P.message = "The auction house wants you to confirm this price. Press Post again to confirm."
        C_Timer.After(0, function()
            if StaticPopup_Hide then
                pcall(StaticPopup_Hide, "AUCTION_HOUSE_POST_WARNING")
            end
        end)
        ns.Fire("POSTER")
    end
end)

local function postFailed()
    if P.pending and (P.state == "posting" or P.state == "confirm" or P.state == "verify") then
        P.pending = nil
        P.state = P.NextEntry() and "ready" or "done"
        P.message = "The auction house refused that post - the red message on screen says why."
        ns.Fire("POSTER")
    end
end
ns.On("AUCTION_HOUSE_POST_ERROR", postFailed)
ns.On("AUCTION_MULTISELL_FAILURE", postFailed)

-- Plain-English reasons for the proposed price.
function P.Explain(e)
    local lines = {}
    if not e then
        return lines
    end
    if e.status == "checking" then
        return { "Checking what this is selling for right now..." }
    end
    if e.note then
        lines[#lines + 1] = e.note
    end
    local d = e.decision
    if not d then
        if e.status == "new" then
            lines[#lines + 1] = "Not price-checked yet."
        end
        return lines
    end
    local one = (e.step or 1) == 1 and "1 copper" or "1 silver"
    for _, l in ipairs(d.lowballs or {}) do
        lines[#lines + 1] = "|cffffd100Ignoring a lowball:|r " .. l.q .. " at " .. ns.Money(l.p)
            .. ", far below everything else."
    end
    if e.priceSet then
        lines[#lines + 1] = "You set this price yourself."
    elseif d.reason == "undercut" then
        local u = opts().postUndercut or "copper"
        lines[#lines + 1] = "Cheapest other listing: " .. ns.Money(d.competitor.p) .. " (" .. d.competitor.q .. " at that price). "
            .. "Yours goes " .. (u == "copper" and one or u) .. " under it."
    elseif d.reason == "match-self" then
        lines[#lines + 1] = "The cheapest one listed is yours (" .. ns.Money(d.myLow) .. "), so this matches it instead of undercutting you."
    elseif d.reason == "usual" then
        lines[#lines + 1] = "Nobody else is selling this, so it uses the usual price."
    elseif d.reason == "last" then
        lines[#lines + 1] = "Nobody else is selling this, so it uses the last price seen."
    elseif d.reason == "markup" then
        lines[#lines + 1] = "Nobody has sold this before: a guess at 50% over what it costs to make."
    end
    if e.status == "floor" then
        local what = e.floorWhy == "cost" and "it costs to make" or "a vendor pays"
        lines[#lines + 1] = "|cffff6060Not worth posting today.|r Anything under " .. ns.Money(e.floor)
            .. " leaves you worse off than what " .. what .. " (" .. ns.Money(e.protects) .. ")."
    elseif e.status == "noprice" then
        lines[#lines + 1] = "|cffffd100No price to go on.|r Nobody is selling it and it's never been seen. Type a price below to post it anyway."
    elseif e.floor and e.floor > 0 and e.price and e.price >= e.floor then
        lines[#lines + 1] = GREY .. "Floor: " .. ns.StripCodes(ns.Money(e.floor)) .. " (what "
            .. (e.floorWhy == "cost" and "it costs to make" or "a vendor pays") .. ", plus the 5% cut). This clears it.|r"
    end
    return lines
end

-- What you'd get for one listing, and the deposit.
function P.Totals(e)
    if not e or not e.price then
        return nil, nil
    end
    local qty = max(1, min(e.per or 1, e.have or 1))
    local duration = opts().sellDuration or 2
    local deposit
    if e.commodity then
        deposit = ns.try(AH.CalculateCommodityDeposit, e.id, duration, qty)
    elseif e.loc then
        deposit = ns.try(AH.CalculateItemDeposit, e.loc, duration, qty)
    end
    return floor(e.price * qty * (1 - CUT)), deposit, qty
end

----------------------------------------------------------------------
-- Your auctions, and the cancel queue
----------------------------------------------------------------------

-- Price each of one of your auctions. For stackable goods the game gives
-- the price of one; for everything else, the whole auction. Your own post
-- records settle it where they can.
local function ownedEach(id, qty, buyout, commodity)
    if not buyout or buyout <= 0 then
        return nil
    end
    if qty <= 1 then
        return buyout
    end
    for _, p in ipairs(ns.db.posts or {}) do
        if p.id == id and p.q == qty then
            if p.p == buyout then
                return buyout
            elseif p.p * qty == buyout then
                return buyout / qty
            end
        end
    end
    if commodity == nil then
        local it = ns.Item(id)
        commodity = it and (it.st or 1) > 1
    end
    return commodity and buyout or (buyout / qty)
end
P.OwnedEach = ownedEach

function P.QueryOwned()
    if ns.ahOpen and AH.QueryOwnedAuctions then
        P.ownedAsked = GetTime()
        pcall(AH.QueryOwnedAuctions, {})
    end
end

local function refreshOwnedStatus()
    for _, a in ipairs(P.owned) do
        if a.sold then
            a.state = "sold"
        else
            local low = P.lowestOther[a.id]
            if low == nil then
                local price = ns.AHPrice(a.id)
                low = price
                a.fromScan = price ~= nil
            else
                a.fromScan = false
            end
            a.lowest = low
            if not a.each then
                a.state = "bid"
            elseif low == false then
                a.state = "alone"
            elseif not low then
                a.state = "unknown"
            elseif low < a.each - 0.5 then
                a.state = "undercut"
            elseif low <= a.each + 0.5 then
                a.state = "tied"
            else
                a.state = "cheapest"
            end
        end
    end
end

-- Cheapest listing that isn't yours, per item, from live checks this visit.
-- false = nobody else is selling it.
P.lowestOther = {}

ns.On("OWNED_AUCTIONS_UPDATED", function()
    if not ns.ready then
        return
    end
    local list = ns.try(AH.GetOwnedAuctions)
    if type(list) ~= "table" then
        return
    end
    local out = {}
    for _, a in ipairs(list) do
        local key = a.itemKey
        if key and key.itemID then
            local qty = max(1, a.quantity or 1)
            local sold = a.status == 1
            out[#out + 1] = {
                auctionID = a.auctionID,
                id = key.itemID,
                key = key,
                qty = qty,
                each = ownedEach(key.itemID, qty, a.buyoutAmount),
                bid = a.bidAmount,
                left = a.timeLeftSeconds,
                band = a.timeLeft,
                sold = sold,
                link = a.itemLink,
            }
        end
    end
    table.sort(out, function(x, y)
        if x.sold ~= y.sold then
            return not x.sold
        end
        return ns.ItemName(x.id) < ns.ItemName(y.id)
    end)
    P.owned = out
    refreshOwnedStatus()
    ns.Fire("POSTER")
end)

-- Live check of every item you have up, one search each.
function P.CheckOwned()
    if not ns.ahOpen then
        return
    end
    local seen, todo = {}, {}
    for _, a in ipairs(P.owned) do
        if not a.sold and not seen[a.id] then
            seen[a.id] = true
            todo[#todo + 1] = a
        end
    end
    if #todo == 0 then
        return
    end
    P.ownedState = "checking"
    P.ownedChecking = { done = 0, total = #todo }
    for _, a in ipairs(todo) do
        local it = ns.Item(a.id)
        local commodity = it and (it.st or 1) > 1
        local key = commodity and (ns.try(AH.MakeItemKey, a.id) or a.key) or a.key
        ns.AHLookup({ id = a.id, key = key, commodity = commodity }, function(listings)
            P.ownedChecking.done = P.ownedChecking.done + 1
            if listings then
                local low = false
                for _, l in ipairs(listings) do
                    -- A price tier that's only partly yours still has someone else in it.
                    if (l.own or 0) < l.q then
                        low = l.p
                        break
                    end
                end
                P.lowestOther[a.id] = low
            end
            if P.ownedChecking.done >= P.ownedChecking.total then
                P.ownedState = "idle"
            end
            refreshOwnedStatus()
            ns.Fire("POSTER")
        end)
    end
    ns.Fire("POSTER")
end

function P.Undercut()
    local out = {}
    for _, a in ipairs(P.owned) do
        if a.state == "undercut" then
            out[#out + 1] = a
        end
    end
    return out
end

function P.CancelCost(a)
    return a and a.auctionID and ns.try(AH.GetCancelCost, a.auctionID) or nil
end

-- Cancels one auction. Only ever called from a click.
function P.Cancel(a)
    if not a or a.sold or not a.auctionID or P.cancelling then
        return
    end
    if AH.CanCancelAuction and not ns.try(AH.CanCancelAuction, a.auctionID) then
        P.message = "That auction can't be cancelled (it may have a bid on it)."
        ns.Fire("POSTER")
        return
    end
    local ok = pcall(AH.CancelAuction, a.auctionID)
    if not ok then
        P.message = "The game blocked that cancel."
        ns.Fire("POSTER")
        return
    end
    P.cancelling = a.auctionID
    local id = a.auctionID
    C_Timer.After(8, ns.Guard("cancel-timeout", function()
        if P.cancelling == id then
            P.cancelling = nil
            P.QueryOwned()
            ns.Fire("POSTER")
        end
    end))
    ns.Fire("POSTER")
end

function P.CancelNextUndercut()
    local list = P.Undercut()
    if list[1] then
        P.Cancel(list[1])
    end
end

ns.On("AUCTION_CANCELED", function(auctionID)
    if P.cancelling then
        P.cancelling = nil
        P.message = "Cancelled. The items come back to you in the mail."
    end
    for i, a in ipairs(P.owned) do
        if a.auctionID == auctionID then
            table.remove(P.owned, i)
            break
        end
    end
    ns.Fire("POSTER")
    C_Timer.After(1, ns.Guard("owned-refresh", P.QueryOwned))
end)

ns.Listen("AH_CLOSED", function()
    cancelLookups()
    -- A price check cut off by walking away: check it again next visit.
    for _, e in ipairs(P.entries) do
        if e.status == "checking" then
            e.status, e.checkedAt = "new", nil
        end
    end
    P.state = (P.state == "checking" or P.state == "posting" or P.state == "confirm" or P.state == "verify")
        and "idle" or P.state
    P.pending, P.cancelling, P.checking, P.unsure = nil, nil, nil, nil
    P.ownedState = "idle"
    P.lowestOther = {}
    P.message = nil
end)

-- Plain words for each status, for the tables.
P.STATUS = {
    new = { "Not checked", "|cff9a9a9a" },
    checking = { "Checking...", "|cffffd100" },
    ready = { "Ready", "|cff40e060" },
    floor = { "Under your floor", "|cffff6060" },
    noprice = { "No price", "|cffffd100" },
    done = { "Posted", "|cff9a9a9a" },
    skipped = { "Skipped", "|cff9a9a9a" },
    gone = { "Not in bags", "|cff9a9a9a" },
    cantsell = { "Can't auction", "|cff9a9a9a" },
    error = { "Check again", "|cffff6060" },
}

P.OWNED_STATUS = {
    undercut = { "Undercut", "|cffff6060" },
    tied = { "Same as others", "|cffffd100" },
    cheapest = { "Cheapest", "|cff40e060" },
    alone = { "Only one listed", "|cff40e060" },
    unknown = { "Not checked", "|cff9a9a9a" },
    sold = { "Sold - check your mail", "|cff40e060" },
    bid = { "Bid only", "|cff9a9a9a" },
}

-- "3 x 20" for the table.
function P.PlanText(e)
    if not e.per or not e.posts or e.posts == 0 then
        return "-"
    end
    local left = (e.posts or 0) - (e.posted or 0)
    if e.posted and e.posted > 0 then
        return e.posted .. "/" .. e.posts .. " x " .. e.per
    end
    return (left == 1 and "" or (left .. " x ")) .. e.per
end

function P.Summary()
    local ready, listings, worth = 0, 0, 0
    for _, e in ipairs(P.entries) do
        if e.picked and e.status == "ready" then
            ready = ready + 1
            local left = (e.posts or 0) - (e.posted or 0)
            listings = listings + left
            worth = worth + (e.price or 0) * min(e.have or 0, left * (e.per or 1)) * (1 - CUT)
        end
    end
    return ready, listings, floor(worth)
end

-- Forever Gold - one-click selling
--
-- Pressing Sell on a Bags row does this:
--   1. Asks the auction house what that one item is selling for RIGHT NOW
--      (scan prices can be an hour old).
--   2. Works out a price using the rules below.
--   3. Shows the price and the reasoning, and waits for you to press Post.
--
-- The game only lets an addon post an auction as the direct result of a real
-- click, so there is always exactly one click per post - nothing here can
-- post by itself.
--
-- The rules (ns.DecidePrice):
--   * Floor. Never post below what the item costs to make, or below what a
--     vendor pays, plus 5% and the auction house's cut. Under the floor the
--     answer is "not worth selling today" and the Post button stays off.
--   * Lowballs. A tiny quantity listed far below everything else (or far
--     below the usual price) is ignored - it will be bought and gone. You
--     price against the next sensible listing instead.
--   * Never undercut yourself. If the cheapest listing is yours or an alt's,
--     match it.
--   * Otherwise list one step (1 copper where the game allows it) under the
--     cheapest competitor.
--   * Small batches. The default quantity is one stack, or a single item.

local _, ns = ...
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local CUT = ns.AH_CUT
local FLOOR_MARGIN = 1.05
local STALE_AFTER = 90 -- seconds before prices are re-checked
local AH = C_AuctionHouse

local job -- the sale being set up, or nil

local function plural(n, word)
    return n .. " " .. word .. (n == 1 and "" or "s")
end

function ns.SellJob()
    return job
end

----------------------------------------------------------------------
-- The floor: the lowest price that still leaves you ahead
----------------------------------------------------------------------

-- Returns floorPrice, "cost" | "vendor" | nil, theAmountItProtects
function ns.SellFloor(id)
    local vendor = ns.VendorSell(id) or 0
    local cost
    local rec = ns.RecipeFor(id)
    if rec then
        cost = ns.EvalRecipe(rec).cost
    end
    local base, why = vendor, "vendor"
    if cost and cost > vendor then
        base, why = cost, "cost"
    end
    if base <= 0 then
        return 0, nil, 0
    end
    return ceil(base * FLOOR_MARGIN / (1 - CUT)), why, base
end

----------------------------------------------------------------------
-- The decision. A pure function of its inputs, so it can be tested.
--
-- listings: { { p = unit price, q = quantity, mine = true|nil }, ... }
-- info: { commodity, step, floor, usual, usualDays, last, cost }
-- Returns { ok, price, reason, competitor, lowballs, myLow, why }
--   reason: "undercut" | "match-self" | "usual" | "last" | "markup"
--   why (when not ok): "floor" | "noref"
----------------------------------------------------------------------
function ns.DecidePrice(listings, info)
    local step = info.step or 1
    local others, total, myLow = {}, 0, nil
    for _, l in ipairs(listings) do
        if l.mine then
            if not myLow or l.p < myLow then
                myLow = l.p
            end
        else
            others[#others + 1] = l
            total = total + l.q
        end
    end
    table.sort(others, function(a, b) return a.p < b.p end)

    -- Skip up to three lowball tiers at the bottom of the market.
    local small = info.commodity and max(2, floor(total * 0.05)) or 1
    local usualKnown = info.usual and (info.usualDays or 0) >= 3
    local lowballs, i, cum = {}, 1, 0
    while i <= #others and #lowballs < 3 do
        local l = others[i]
        local nextUp = others[i + 1]
        cum = cum + l.q
        local wayUnderUsual = usualKnown and l.p <= info.usual * 0.5
        local wayUnderNext = nextUp and l.p <= nextUp.p * 0.6
        if cum <= small and (wayUnderUsual or wayUnderNext) then
            lowballs[#lowballs + 1] = l
            i = i + 1
        else
            break
        end
    end
    local competitor = others[i]

    local d = { lowballs = lowballs, competitor = competitor, myLow = myLow }
    local target
    if competitor then
        if myLow and myLow <= competitor.p then
            target, d.reason = myLow, "match-self"
        else
            -- Undercut by one step, or by a share of the price if set.
            local by = max(step, floor(competitor.p * (info.undercutPct or 0)))
            target, d.reason = competitor.p - by, "undercut"
        end
    elseif myLow then
        target, d.reason = myLow, "match-self"
    elseif info.usual and (info.usualDays or 0) >= 2 then
        target, d.reason = info.usual, "usual"
    elseif info.last then
        target, d.reason = info.last, "last"
    elseif info.cost and info.cost > 0 then
        target, d.reason = info.cost * 1.5 / (1 - CUT), "markup"
    else
        d.ok, d.why = false, "noref"
        return d
    end

    target = floor(target / step) * step
    if target < step then
        target = step
    end
    d.price = target
    if target < (info.floor or 0) then
        d.ok, d.why = false, "floor"
    else
        d.ok = true
    end
    return d
end

----------------------------------------------------------------------
-- Finding the item in your bags
----------------------------------------------------------------------

local function findInBags(id)
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
-- "The auction house is busy" and "You are doing that too fast"
--
-- The auction house only takes so many requests at once. When it says it's
-- busy or drops a request, posting waits until it says it's ready again
-- (and at least a second), and the Post buttons say "Wait" instead of
-- letting you click straight into another refusal. Shared by the Sell
-- window here and the post queue (Poster.lua).
----------------------------------------------------------------------

local hold = {}

local function refreshPosting()
    ns.Fire("SELL")
    ns.Fire("POSTER")
end

local function holdUntil(t)
    hold.untilT = t
    C_Timer.After(max(0, t - GetTime()) + 0.05, ns.Guard("ah-hold", function()
        if hold.untilT == t then
            hold.untilT, hold.minT = nil, nil
            refreshPosting()
        end
    end))
end

function ns.AHWaiting()
    if hold.untilT and GetTime() < hold.untilT then
        return true
    end
    hold.untilT = nil
    return false
end

-- Hold posting for up to `seconds` (ended early when the game says it's ready).
function ns.AHHold(seconds)
    local now = GetTime()
    local t = now + (seconds or 3)
    hold.minT = max(hold.minT or 0, now + 1)
    if hold.untilT and hold.untilT >= t then
        return
    end
    holdUntil(t)
    refreshPosting()
end

-- True when posting can go ahead now; otherwise starts (or keeps) a wait.
function ns.AHReadyToPost()
    if ns.AHWaiting() then
        return false
    end
    if not throttleReady() then
        ns.AHHold(3)
        return false
    end
    return true
end

-- The auction house errors that mean "not now", rather than "not that".
function ns.AHBusyError(err)
    local E = Enum and Enum.AuctionHouseError
    return (E and err ~= nil and (err == E.IsBusy or err == E.Unavailable or err == E.DatabaseError)) and true or false
end

ns.On("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
    ns.AHHold(4)
end)

ns.On("AUCTION_HOUSE_SHOW_ERROR", function(err)
    if ns.AHBusyError(err) then
        ns.AHHold(4)
    end
end)

ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
    if hold.untilT then
        if hold.minT and hold.minT > GetTime() + 0.05 then
            holdUntil(hold.minT)
        else
            hold.untilT, hold.minT = nil, nil
        end
        refreshPosting()
    end
end)

-- Everything of one item in your bags, locked or not, and whether any of it
-- is locked (the game locks what's being posted until the post settles).
function ns.BagTotal(id)
    if not C_Container then
        return 0, false
    end
    local n, locked = 0, false
    local last = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0)
    for bag = 0, last do
        for slot = 1, ns.try(C_Container.GetContainerNumSlots, bag) or 0 do
            local info = ns.try(C_Container.GetContainerItemInfo, bag, slot)
            if type(info) == "table" and info.itemID == id then
                n = n + (info.stackCount or 1)
                locked = locked or (info.isLocked and true) or false
            end
        end
    end
    return n, locked
end

-- After a post whose answer never came (or that may have been dropped),
-- the bags say whether it went up. `p` = { id =, qty =, before = bag count
-- before posting }. done(true) = it went up, done(false) = it didn't,
-- done(nil) = still can't tell after a few looks.
function ns.CheckPostInBags(p, done, tries)
    tries = tries or 0
    local n, locked = ns.BagTotal(p.id)
    if p.before and n <= p.before - p.qty then
        done(true)
        return
    end
    if p.before and not locked and n >= p.before then
        done(false)
        return
    end
    if not p.before or tries >= 4 then
        done(nil)
        return
    end
    C_Timer.After(1.5, ns.Guard("post-check", function()
        ns.CheckPostInBags(p, done, tries + 1)
    end))
end

----------------------------------------------------------------------
-- Step 1: ask what it sells for right now
----------------------------------------------------------------------

local function sendSearch()
    local sorts = {}
    local SO = Enum and Enum.AuctionHouseSortOrder
    if SO then
        local order = job.commodity and SO.Price or (SO.Buyout or SO.Price)
        sorts[1] = { sortOrder = order, reverseSort = false }
    end
    job.state = "checking"
    job.asked = GetTime()
    job.decision = nil
    local ok = pcall(AH.SendSearchQuery, job.key, sorts, true)
    if not ok then
        job.state, job.message = "error", "The auction house wouldn't run the price check. Close this and try again."
    end
    -- If nothing comes back, say so rather than guess.
    local asked = job.asked
    C_Timer.After(10, ns.Guard("sell-timeout", function()
        if job and job.state == "checking" and job.asked == asked then
            job.state = "error"
            job.message = "The auction house didn't answer the price check. Press Check again."
            ns.Fire("SELL")
        end
    end))
end

-- How much goes in one listing, from Settings: "stack" (one full stack,
-- the default), "10", "5", "all" (everything you have) or "one".
local function defaultQuantity()
    local mode = ns.db.opts.postQty or "stack"
    if mode == "one" then
        return 1
    elseif mode == "all" then
        return max(1, job.have)
    elseif tonumber(mode) then
        return max(1, min(job.have, tonumber(mode)))
    end
    if job.commodity then
        local stack = (C_Item and ns.try(C_Item.GetItemMaxStackSizeByID, job.id)) or 20
        return max(1, min(job.have, stack))
    end
    return 1
end

-- The undercut, from Settings: 1 copper (default), 1% or 5%.
local UNDERCUT = { copper = 0, ["1%"] = 0.01, ["5%"] = 0.05 }
ns.UNDERCUT_STEPS = { "copper", "1%", "5%" }
ns.POST_QTY_STEPS = { "stack", "10", "5", "one", "all" }

local queue -- Post all: { ids, i, posted, skipped = { "name: why" } }

-- Returns true if the sale was set up; otherwise prints why (unless quiet).
function ns.OpenSell(id, quiet)
    AH = C_AuctionHouse
    local function no(msg)
        if not quiet then
            ns.Print(msg)
        end
        return false, msg
    end
    if not ns.ahOpen then
        return no("open the auction window at an auctioneer first, then press Sell.")
    end
    if ns.scan.active then
        return no("I'm still reading prices - press Sell again when the scan finishes.")
    end
    if not (AH and AH.PostItem and AH.PostCommodity and AH.SendSearchQuery) then
        return no("this game client doesn't have the selling functions I need.")
    end
    local loc, have = findInBags(id)
    if not loc then
        return no("I can't find a sellable " .. ns.ItemName(id) .. " in your bags.")
    end
    if AH.IsSellItemValid and not ns.try(AH.IsSellItemValid, loc, false) then
        return no(ns.ItemName(id) .. " can't be sold on the auction house.")
    end
    local status = ns.try(AH.GetItemCommodityStatus, loc)
    local S = Enum and Enum.ItemCommodityStatus or {}
    local COMMODITY, ITEM = S.Commodity or 2, S.Item or 1
    if status ~= COMMODITY and status ~= ITEM then
        return no("the game is still loading that item. Press Sell again in a moment.")
    end
    job = { id = id, loc = loc, have = have, commodity = (status == COMMODITY) }
    if job.commodity then
        job.key = ns.try(AH.MakeItemKey, id)
    else
        job.key = ns.try(AH.GetItemKeyFromItem, loc)
        job.have = max(1, ns.try(AH.GetAvailablePostCount, loc) or 1)
    end
    if not job.key then
        job = nil
        return no("the auction house wouldn't accept that item.")
    end
    job.step = (AH.SupportsCopperValues and ns.try(AH.SupportsCopperValues)) and 1 or 100
    job.duration = ns.db.opts.sellDuration or 2
    job.qty = defaultQuantity()
    sendSearch()
    ns.Fire("SELL")
    return true
end

function ns.CloseSell()
    job = nil
    if queue then
        ns.StopPostAll()
        return
    end
    ns.Fire("SELL")
end

----------------------------------------------------------------------
-- Post all: works through everything the Sell tab says to auction. Each
-- item is price-checked by itself; you press Post once per listing (the
-- game insists on a click for every post). Anything that isn't worth
-- selling today, or that I won't guess a price for, is skipped.
----------------------------------------------------------------------

function ns.PostQueue()
    return queue
end

local function nextInQueue()
    if not queue then
        return
    end
    while true do
        queue.i = queue.i + 1
        local id = queue.ids[queue.i]
        if not id then
            local q = queue
            queue, job = nil, nil
            ns.Print("post all finished: " .. plural(q.posted, "listing") .. " posted"
                .. (#q.skipped > 0 and (", " .. #q.skipped .. " skipped (" .. table.concat(q.skipped, "; ") .. ")") or "") .. ".")
            ns.Fire("SELL")
            return
        end
        local ok, why = ns.OpenSell(id, true)
        if ok then
            return
        end
        queue.skipped[#queue.skipped + 1] = ns.ItemName(id) .. ": " .. (why or "couldn't start")
    end
end

function ns.StartPostAll()
    if queue then
        return
    end
    if not ns.ahOpen then
        ns.Print("open the auction window at an auctioneer first.")
        return
    end
    local ids = {}
    for _, b in ipairs(ns.BagAdvice().ah) do
        ids[#ids + 1] = b.id
    end
    if #ids == 0 then
        ns.Print("nothing in your bags is worth auctioning right now.")
        return
    end
    queue = { ids = ids, i = 0, posted = 0, skipped = {} }
    nextInQueue()
end

function ns.SkipPostAll(reason)
    if not queue then
        return
    end
    if job then
        queue.skipped[#queue.skipped + 1] = ns.ItemName(job.id) .. ": " .. (reason or "skipped")
    end
    job = nil
    nextInQueue()
end

function ns.StopPostAll()
    if not queue then
        return
    end
    local q = queue
    queue, job = nil, nil
    ns.Print("post all stopped after " .. plural(q.posted, "listing") .. ".")
    ns.Fire("SELL")
end

function ns.SellRecheck()
    if job and job.state ~= "posting" and job.state ~= "confirm" and job.state ~= "verify" then
        sendSearch()
        ns.Fire("SELL")
    end
end

----------------------------------------------------------------------
-- Step 2: results arrive, decide a price
----------------------------------------------------------------------

local function readListings()
    local out = {}
    if job.commodity then
        local n = ns.try(AH.GetNumCommoditySearchResults, job.id) or 0
        for i = 1, min(n, 60) do
            local r = ns.try(AH.GetCommoditySearchResultInfo, job.id, i)
            if type(r) == "table" and r.unitPrice and r.unitPrice > 0 then
                out[#out + 1] = { p = r.unitPrice, q = r.quantity or 1,
                    mine = (r.containsOwnerItem or r.containsAccountItem) and true or nil }
            end
        end
    else
        local n = ns.try(AH.GetNumItemSearchResults, job.key) or 0
        for i = 1, min(n, 60) do
            local r = ns.try(AH.GetItemSearchResultInfo, job.key, i)
            if type(r) == "table" and r.buyoutAmount and r.buyoutAmount > 0 then
                local q = max(1, r.quantity or 1)
                out[#out + 1] = { p = r.buyoutAmount / q, q = q,
                    mine = (r.containsOwnerItem or r.containsAccountItem) and true or nil }
            end
        end
    end
    return out
end

local function decide()
    local floorPrice, floorWhy, protects = ns.SellFloor(job.id)
    local usual, days = ns.UsualPrice(job.id)
    local rec = ns.RecipeFor(job.id)
    job.floor, job.floorWhy, job.protects = floorPrice, floorWhy, protects
    job.listings = readListings()
    job.decision = ns.DecidePrice(job.listings, {
        commodity = job.commodity,
        step = job.step,
        floor = floorPrice,
        usual = usual,
        usualDays = days,
        last = ns.LastPrice(job.id),
        cost = rec and ns.EvalRecipe(rec).cost or nil,
        undercutPct = UNDERCUT[ns.db.opts.postUndercut or "copper"] or 0,
    })
    job.checkedAt = GetTime()
    job.state = "ready"
    job.message = nil
    ns.Fire("SELL")
    -- Post all moves straight past anything it shouldn't post.
    if queue and not job.decision.ok then
        local why = job.decision.why == "floor" and "not worth selling today" or "no price to go on"
        C_Timer.After(0.2, ns.Guard("post-all", function() ns.SkipPostAll(why) end))
    end
end

ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
    if job and job.commodity and job.state == "checking" and itemID == job.id then
        decide()
    end
end)

ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
    if job and not job.commodity and job.state == "checking" and type(itemKey) == "table"
        and itemKey.itemID == job.id then
        decide()
    end
end)

----------------------------------------------------------------------
-- Quantity, duration, and the numbers shown before posting
----------------------------------------------------------------------

function ns.SellSetQuantity(n)
    if job then
        job.qty = max(1, min(job.have, floor(n)))
        ns.Fire("SELL")
    end
end

function ns.SellCycleDuration()
    if job then
        job.duration = (job.duration % 3) + 1
        ns.db.opts.sellDuration = job.duration
        ns.Fire("SELL")
    end
end

function ns.SellDurationLabel(index)
    local names = { AUCTION_DURATION_ONE, AUCTION_DURATION_TWO, AUCTION_DURATION_THREE }
    return names[index] or ({ "Short", "Medium", "Long" })[index] or "?"
end

-- Returns deposit (may be nil), whatYouReceiveIfAllSell
function ns.SellTotals()
    if not job or not job.decision or not job.decision.price then
        return nil, nil
    end
    local deposit
    if job.commodity then
        deposit = ns.try(AH.CalculateCommodityDeposit, job.id, job.duration, job.qty)
    else
        deposit = ns.try(AH.CalculateItemDeposit, job.loc, job.duration, job.qty)
    end
    return deposit, job.decision.price * job.qty * (1 - CUT)
end

----------------------------------------------------------------------
-- Step 3: post. Only ever called from a button's click handler.
----------------------------------------------------------------------

local function stillThere()
    local ok, exists = pcall(C_Item.DoesItemExist, job.loc)
    if ok and exists and ns.try(C_Item.GetItemID, job.loc) == job.id then
        return true
    end
    local loc = findInBags(job.id)
    if loc then
        job.loc = loc
        return true
    end
    return false
end

local watchSellPost

function ns.SellPost()
    if not job then
        return
    end
    if job.state == "confirm" then
        -- The auction house asked "are you sure?" - this click is the yes.
        if not ns.AHReadyToPost() then
            job.message = "The auction house is busy. Confirm comes back as soon as it's ready."
            ns.Fire("SELL")
            return
        end
        local a = job.args
        local ok
        if job.commodity then
            ok = pcall(AH.ConfirmPostCommodity, a[1], a[2], a[3], a[4])
        else
            ok = pcall(AH.ConfirmPostItem, a[1], a[2], a[3], nil, a[4])
        end
        job.state = ok and "posting" or "error"
        job.message = (not ok) and "The auction house refused the confirmation." or nil
        if ok then
            watchSellPost()
        end
        ns.Fire("SELL")
        return
    end
    if job.state ~= "ready" or not job.decision or not job.decision.ok then
        return
    end
    if GetTime() - (job.checkedAt or 0) > STALE_AFTER then
        job.message = "Those prices were over a minute old, so I'm checking again. Press Post once more when it's done."
        sendSearch()
        ns.Fire("SELL")
        return
    end
    if not ns.AHReadyToPost() then
        job.message = "The auction house is busy. Post comes back as soon as it's ready."
        ns.Fire("SELL")
        return
    end
    if not stillThere() then
        job.state, job.message = "error", "That item isn't in your bags any more."
        ns.Fire("SELL")
        return
    end
    local price, qty = job.decision.price, job.qty
    job.args = { job.loc, job.duration, qty, price }
    job.before = ns.BagTotal(job.id)
    local ok, needsConfirm
    if job.commodity then
        ok, needsConfirm = pcall(AH.PostCommodity, job.loc, job.duration, qty, price)
    else
        ok, needsConfirm = pcall(AH.PostItem, job.loc, job.duration, qty, nil, price)
    end
    if not ok then
        job.state = "error"
        job.message = "The game blocked that post. Use the normal Sell tab for this item and tell me with /gold debug."
        ns.Err("sell-post", needsConfirm)
    elseif needsConfirm then
        job.state = "confirm"
        job.message = "The auction house wants you to confirm this price. Press Confirm to go ahead."
    else
        job.state = "posting"
        job.message = nil
        watchSellPost()
    end
    ns.Fire("SELL")
end

local sellPosted

-- A post with no answer yet, or one the auction house may have dropped:
-- the bags settle whether it went up before anything can be posted again,
-- so a slow answer never turns into a second listing.
local function verifySellPost(why)
    if not job or (job.state ~= "posting" and job.state ~= "verify") then
        return
    end
    local mine = job
    job.state = "verify"
    job.message = why
    local a = job.args
    ns.CheckPostInBags({ id = job.id, qty = a[3], before = job.before }, function(went)
        if job ~= mine or job.state ~= "verify" then
            return
        end
        if went then
            sellPosted("That one went up - the auction house was just slow to say so.")
        elseif went == false then
            job.state = "ready"
            job.message = "That post didn't go through - nothing left your bags. Press Post when it's ready."
            ns.Fire("SELL")
        else
            job.state = "error"
            job.unsure = true
            job.message = "I couldn't tell whether it was listed. Check the Auctions tab before posting it again."
            ns.Fire("SELL")
        end
    end)
    ns.Fire("SELL")
end

watchSellPost = function()
    job.postedAt = GetTime()
    local stamp, mine = job.postedAt, job
    C_Timer.After(12, ns.Guard("sell-post-timeout", function()
        if job == mine and job.state == "posting" and job.postedAt == stamp then
            verifySellPost("No answer from the auction house yet - checking your bags to see whether it went up...")
        end
    end))
end

ns.On("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
    if job and job.state == "posting" then
        verifySellPost("The auction house said that was too fast. Checking whether the post went through...")
    end
end)

ns.On("AUCTION_HOUSE_AUCTION_CREATED", function()
    if job and (job.state == "posting" or job.state == "confirm" or job.state == "verify" or job.unsure) then
        sellPosted(job.unsure and "It did go up after all." or nil)
    end
end)

sellPosted = function(note)
    local a = job.args
    local posts = ns.db.posts
    if type(posts) ~= "table" then
        posts = {}
        ns.db.posts = posts
    end
    table.insert(posts, 1, { id = job.id, q = a[3], p = a[4], t = time() })
    posts[201] = nil
    job.state = "done"
    job.message = note
    job.unsure = nil
    ns.Print("listed " .. a[3] .. " x " .. ns.ItemText(job.id) .. " at " .. ns.Money(a[4]) .. " each.")
    ns.Fire("SELL")
    if queue then
        queue.posted = queue.posted + 1
        -- More of the same left (posting a stack at a time)? Do the next
        -- stack before moving on. The count is kept here rather than read
        -- back from the bags, which can lag a moment behind the post.
        local id = job.id
        local left = job.have - a[3]
        C_Timer.After(0.6, ns.Guard("post-all", function()
            if not queue then
                return
            end
            if left > 0 and (ns.db.opts.postQty or "stack") == "stack" and ns.OpenSell(id, true) then
                job.have = min(job.have, left)
                job.qty = min(job.qty, job.have)
                return
            end
            job = nil
            nextInQueue()
        end))
    end
    -- Your auctions are read again a few seconds after the last post (see
    -- readOwnedSoon below); one read per post used up the allowance and made
    -- the next Post find the auction house busy.
end

-- The auction house asking "are you sure?". Blizzard's own popup for this
-- only knows about posts made from its Sell tab, so ours takes over.
ns.On("AUCTION_HOUSE_POST_WARNING", function()
    if job and (job.state == "posting" or job.state == "confirm") then
        job.state = "confirm"
        job.message = "The auction house wants you to confirm this price. Press Confirm to go ahead."
        C_Timer.After(0, function()
            if StaticPopup_Hide then
                pcall(StaticPopup_Hide, "AUCTION_HOUSE_POST_WARNING")
            end
        end)
        ns.Fire("SELL")
    end
end)

local function postFailed()
    if job and (job.state == "posting" or job.state == "confirm") then
        job.state = "error"
        job.message = "The auction house refused that post - the red message on screen says why."
        ns.Fire("SELL")
    end
end
ns.On("AUCTION_HOUSE_POST_ERROR", postFailed)
ns.On("AUCTION_MULTISELL_FAILURE", postFailed)
ns.On("AUCTION_HOUSE_SHOW_ERROR", function(err)
    if not (job and job.state == "posting") then
        return
    end
    if ns.AHBusyError(err) then
        -- "Busy" means it most likely didn't go, but the bags have the last word.
        verifySellPost("The auction house was busy. Checking whether the post went through...")
    else
        postFailed()
    end
end)

ns.Listen("AH_CLOSED", function()
    if queue then
        ns.StopPostAll()
    elseif job then
        ns.CloseSell()
    end
end)

----------------------------------------------------------------------
-- The explanation shown in the Sell panel, as a list of plain sentences
----------------------------------------------------------------------

function ns.SellExplain()
    local lines = {}
    if not job then
        return lines
    end
    if job.state == "checking" then
        lines[1] = "Checking what this is selling for right now..."
        return lines
    end
    local d = job.decision
    if not d then
        return lines
    end
    local one = job.step == 1 and "1 copper" or "1 silver"

    for _, l in ipairs(d.lowballs) do
        lines[#lines + 1] = "|cffffd100Ignoring a lowball:|r " .. l.q .. " listed at " .. ns.Money(l.p)
            .. ", far below everything else. Those will be snapped up - you could buy them yourself."
    end

    if d.reason == "undercut" then
        lines[#lines + 1] = "The cheapest one for sale is " .. ns.Money(d.competitor.p) .. " (" .. d.competitor.q
            .. " at that price)." .. (d.ok and (" Yours goes up " .. one .. " cheaper so it sells first.") or "")
    elseif d.reason == "match-self" then
        lines[#lines + 1] = "The cheapest one listed is already yours (" .. ns.Money(d.myLow)
            .. "). I'll match your own price rather than undercut you."
    elseif d.reason == "usual" then
        lines[#lines + 1] = "Nobody else is selling this right now, so I'm using its usual price."
    elseif d.reason == "last" then
        lines[#lines + 1] = "Nobody else is selling this right now, so I'm using the last price I saw."
    elseif d.reason == "markup" then
        lines[#lines + 1] = "Nobody has sold this before, so this is a guess: 50% more than it costs to make. If it doesn't sell, try lower next time."
    end

    local floorWhat = job.floorWhy == "cost" and "it costs to make" or "a vendor pays"
    if d.ok then
        if job.floor and job.floor > 0 then
            lines[#lines + 1] = "|cff9a9a9aYour floor is " .. ns.StripCodes(ns.Money(job.floor)) .. " (what "
                .. floorWhat .. ", plus the 5% cut). This price clears it.|r"
        end
    elseif d.why == "floor" then
        lines[#lines + 1] = "|cffff7070Not worth selling today.|r The going price would be " .. ns.Money(d.price)
            .. ", but anything under " .. ns.Money(job.floor) .. " leaves you worse off than what " .. floorWhat
            .. " (" .. ns.Money(job.protects) .. ")."
        if job.floorWhy == "vendor" then
            lines[#lines + 1] = "Sell it to a vendor instead, or wait for the price to recover."
        else
            lines[#lines + 1] = "Wait for the price to recover, or use it yourself."
        end
    elseif d.why == "noref" then
        lines[#lines + 1] = "|cffffd100I won't guess this one.|r Nobody is selling it and I've never seen a price for it. Use the auction window's own Sell tab and choose a price you're happy with."
    end
    return lines
end

----------------------------------------------------------------------
-- Vendor-price guard
--
-- The Sell button already refuses to go under what a vendor pays. This
-- covers everything else:
--   * the auction house's own Sell screen: a red warning under the window
--     while the price you've typed nets less than a vendor pays
--   * any listing at all (Blizzard's screen, Auctionator, anything): when
--     your auctions are read, each one under vendor price is called out
--     once in chat, so you can cancel it
-- Nothing is blocked or changed - it only warns.
----------------------------------------------------------------------

local GUARD_CLOSE = 1.10 -- within 10% of the vendor price: "barely worth it"

-- Returns "below" | "close" | nil, vendorPrice, netEach
function ns.VendorCheck(id, priceEach)
    local vendor = id and ns.VendorSell(id)
    if not vendor or vendor <= 0 or not priceEach or priceEach <= 0 then
        return nil
    end
    local net = priceEach * (1 - ns.AH_CUT)
    if net <= vendor then
        return "below", vendor, net
    elseif net <= vendor * GUARD_CLOSE then
        return "close", vendor, net
    end
    return nil, vendor, net
end

local function guardText(level, vendor, net)
    if level == "below" then
        return "|cffff5050Below vendor price!|r A vendor pays " .. ns.Money(vendor) .. " each. At this price you'd get only "
            .. ns.Money(math.floor(net)) .. " after the auction house's 5%. Sell it to a vendor instead."
    end
    return "|cffffa040Barely above vendor price.|r A vendor pays " .. ns.Money(vendor) .. " each; this nets you "
        .. ns.Money(math.floor(net)) .. ". Only worth it if it sells fast."
end

local function banner(frame)
    if frame.fgGuard then
        return frame.fgGuard
    end
    local b = CreateFrame("Frame", nil, frame)
    b:SetSize(420, 44)
    b:SetPoint("TOPLEFT", AuctionHouseFrame or frame, "BOTTOMLEFT", 0, -2)
    b:SetFrameStrata("HIGH")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.02, 0.02, 0.92)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("TOPLEFT", 8, -6)
    b.text:SetPoint("BOTTOMRIGHT", -8, 6)
    b.text:SetJustifyH("LEFT")
    b.text:SetJustifyV("MIDDLE")
    b:Hide()
    frame.fgGuard = b
    return b
end

local function checkSellFrame(frame)
    local b = banner(frame)
    local loc = frame.GetItem and frame:GetItem()
    local id = loc and loc.IsValid and loc:IsValid() and C_Item and ns.try(C_Item.GetItemID, loc)
    local price = frame.PriceInput and frame.PriceInput.GetAmount and frame.PriceInput:GetAmount()
    local level, vendor, net = ns.VendorCheck(id, price)
    if level then
        b.text:SetText(guardText(level, vendor, net))
        b:Show()
    else
        b:Hide()
    end
end

local hookedSell = false
local function hookSellFrames()
    if hookedSell or not AuctionHouseFrame or type(hooksecurefunc) ~= "function" then
        return
    end
    for _, key in ipairs({ "ItemSellFrame", "CommoditiesSellFrame" }) do
        local frame = AuctionHouseFrame[key]
        if type(frame) == "table" and type(frame.UpdatePostState) == "function" then
            hooksecurefunc(frame, "UpdatePostState", ns.Guard("vendor-guard", checkSellFrame))
            frame:HookScript("OnHide", function(f)
                if f.fgGuard then
                    f.fgGuard:Hide()
                end
            end)
            hookedSell = true
        end
    end
end

ns.On("AUCTION_HOUSE_SHOW", function()
    C_Timer.After(0, ns.Guard("vendor-guard-hook", hookSellFrames))
end)

-- Any new listing: read your auctions shortly after so the check below runs.
-- Once per burst of posting, a few seconds after the last post: each read
-- uses the same allowance as posting, and one per post made the next Post
-- click find the auction house busy.
local ownedAfterPost = 0
local function readOwnedSoon()
    ownedAfterPost = ownedAfterPost + 1
    local mine = ownedAfterPost
    C_Timer.After(3, function()
        if mine ~= ownedAfterPost or not ns.ahOpen then
            return
        end
        if ns.AHBusy and ns.AHBusy() then
            readOwnedSoon()
            return
        end
        pcall(AH.QueryOwnedAuctions, {})
    end)
end

ns.On("AUCTION_HOUSE_AUCTION_CREATED", function()
    if AH and AH.QueryOwnedAuctions then
        readOwnedSoon()
    end
end)

local warned = {}
ns.On("OWNED_AUCTIONS_UPDATED", function()
    if not ns.ready then
        return
    end
    local list = ns.try(AH.GetOwnedAuctions)
    if type(list) ~= "table" then
        return
    end
    -- Remember them for the website's undercut check (see Web.lua).
    local mine = {}
    for _, a in ipairs(list) do
        local key = a.itemKey
        if key and key.itemID and a.auctionID then
            mine[#mine + 1] = {
                id = a.auctionID,
                item = key.itemID,
                q = math.max(1, a.quantity or 1),
                b = a.buyoutAmount or 0,
                st = a.status or 0,
                tl = a.timeLeftSeconds,
            }
        end
    end
    ns.Char().webAuctions = { t = time(), list = mine }
    for _, a in ipairs(list) do
        local key = a.itemKey
        local qty = math.max(1, a.quantity or 1)
        if key and key.itemID and a.auctionID and not warned[a.auctionID] and (a.status == nil or a.status == 0)
            and a.buyoutAmount and a.buyoutAmount > 0 then
            -- Blizzard's docs don't say whether buyoutAmount is per item or
            -- for the whole stack, so judge by the larger reading: a warning
            -- then always means it really is under vendor price.
            local each = a.buyoutAmount
            local level, vendor, net = ns.VendorCheck(key.itemID, each)
            if level == "below" then
                warned[a.auctionID] = true
                ns.Print("|cffff5050heads up:|r you have " .. qty .. " x " .. ns.ItemText(key.itemID) .. " listed at "
                    .. (qty > 1 and "no more than " or "") .. ns.Money(each) .. " each. A vendor pays " .. ns.Money(vendor)
                    .. " - after the auction cut you'd get at most " .. ns.Money(math.floor(net))
                    .. ". Cancel it in the auction house's Auctions tab and vendor it instead.")
            end
        end
    end
end)

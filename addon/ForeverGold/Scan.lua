-- Forever Gold - auction house scanner
--
-- There are two ways to read the auction house, and this file uses both.
--
-- FAST: "send me every auction" (C_AuctionHouse.ReplicateItems). One request,
--   the whole auction house arrives in a single download, and every price in
--   it is a real buyout. The game only allows it once every 15 minutes.
--
-- SLOW: a "browse" search with an empty search box, fetched page by page.
--   Works any time, but takes far longer, and each row only says "lowest
--   price", which for gear can be a BID that nobody can simply buy. Those
--   are flagged as unconfirmed and double-checked one by one afterwards (see
--   the verifier at the bottom) before the Deals tab is allowed to show them.
--
-- A scan picks FAST whenever it's allowed, and falls back to SLOW if the
-- download doesn't arrive or doesn't look right.
--
-- Trust but verify: the first fast scan on a realm is compared against the
-- prices a slow scan already found. If the two disagree wildly the fast scan
-- is thrown away and switched off, so a client quirk can't quietly fill the
-- price book with nonsense.
--
-- Nothing in this file ever buys, bids, posts or cancels. It only reads.

local _, ns = ...
local floor, max, min = math.floor, math.max, math.min

local scan = { active = false, count = 0 }
ns.scan = scan
ns.ahOpen = false

local AH = C_AuctionHouse
local ticker

local FAST_COOLDOWN = 15 * 60 + 10 -- the game's limit, plus a little slack
-- Seconds to wait for the download to arrive. A big auction house (250,000
-- auctions) can take well over 12 seconds to come down; giving up early used
-- the 15 minute allowance AND then ran the slow scan on top.
local FAST_WAIT = 60
local FRAME_BUDGET = 30            -- milliseconds of reading per frame
local MIN_COMPARE = 8              -- items needed to sanity-check a fast scan

-- The exact variant (item level / suffix) behind each unconfirmed price from
-- the last slow scan, so the verifier can look that one up. Not saved.
scan.keys = {}

local function throttleReady()
    if not AH or not AH.IsThrottledMessageSystemReady then
        return true
    end
    local ok, ready = pcall(AH.IsThrottledMessageSystemReady)
    return (not ok) or ready
end

local function hasFullResults()
    local ok, full = pcall(AH.HasFullBrowseResults)
    return ok and full
end

-- price is for ONE item. isBuyout = we know it can be bought outright.
local function addListing(id, price, qty, isBuyout, key)
    if not id or not price or price <= 0 then
        return
    end
    qty = qty or 0
    local a = scan.agg[id]
    if not a then
        a = { p = price, q = qty, c = qty, b = isBuyout or nil, k = key }
        scan.agg[id] = a
        scan.count = scan.count + 1
    else
        a.q = a.q + qty
        if qty > a.c then
            a.c = qty
        end
        if price < a.p then
            a.p = price
            a.k = key
        end
    end
end

local finish, startBrowse

----------------------------------------------------------------------
-- FAST: one big download
----------------------------------------------------------------------

-- Compares a finished fast scan with prices already in the book.
-- "ok" = they agree, "bad" = they don't, "unknown" = not enough to compare.
local function checkAgainstBook()
    local prices = ns.R().prices
    local now = time()
    local ratios = {}
    for id, a in pairs(scan.agg) do
        -- Only things sold in stacks: those are where a "price per stack"
        -- versus "price per item" mix-up would show.
        if (a.c or 1) >= 5 then
            local r = prices[id]
            if r and r.p and r.p > 0 and (r.q or 0) > 0 and r.t and now - r.t < 3 * 86400 then
                ratios[#ratios + 1] = a.p / r.p
            end
        end
    end
    if #ratios < MIN_COMPARE then
        return "unknown"
    end
    table.sort(ratios)
    local median = ratios[floor((#ratios + 1) / 2)]
    if median >= 0.4 and median <= 2.5 then
        return "ok"
    end
    return "bad", median
end

local function finishReplicate()
    local R = ns.R()
    local verdict, median = checkAgainstBook()
    if verdict == "ok" then
        R.fastOK = true
        R.fastBad = nil
        finish(true)
        return
    end
    if verdict == "unknown" and R.fastOK then
        finish(true)
        return
    end
    if verdict == "bad" then
        R.fastBad = true
        scan.note = "The fast scan's prices didn't match what I'd seen (off by about "
            .. string.format("%.1f", median or 0) .. "x), so I've switched it off and used the slow scan."
    end
    -- Not proven yet: do it the slow way this once.
    startBrowse()
end

local function processReplicate()
    if not scan.active or scan.mode ~= "replicate" or scan.repBusy then
        return
    end
    local n = ns.try(AH.GetNumReplicateItems) or 0
    if n == 0 then
        return
    end
    scan.repBusy = true
    if not scan.gotList then
        scan.arrived = GetTime() - (scan.asked or GetTime())
    end
    scan.gotList = true
    scan.agg, scan.count = {}, 0
    scan.auctions = n
    scan.passes = (scan.passes or 0) + 1
    local i, missing = 0, 0
    local clock = debugprofilestop
    local function step()
        if not scan.active or scan.mode ~= "replicate" then
            return
        end
        -- Work for a few hundredths of a second, then let the game draw a
        -- frame, so even a huge auction house doesn't freeze the screen.
        -- (Called directly, not through pcall per row: this loop runs a
        -- quarter of a million times, and ns.Guard catches any error.)
        local t0 = clock and clock() or 0
        local done = 0
        local get = AH.GetReplicateItemInfo
        while i < n do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = get(i)
            i = i + 1
            done = done + 1
            if itemID and itemID > 0 then
                if buyout and buyout > 0 and count and count > 0 then
                    addListing(itemID, buyout / count, count, true)
                end
            else
                missing = missing + 1
            end
            if clock then
                if done % 500 == 0 and clock() - t0 > FRAME_BUDGET then
                    break
                end
            elseif done >= 5000 then
                break
            end
        end
        scan.done = i
        scan.lastProgress = GetTime()
        ns.Fire("SCAN_PROGRESS")
        if i < n then
            C_Timer.After(0, ns.Guard("replicate", step))
            return
        end
        scan.repBusy = false
        if missing > n * 0.03 and scan.passes < 3 then
            -- A lot of rows had no item yet; the list is still filling in.
            C_Timer.After(2, ns.Guard("replicate", processReplicate))
        else
            finishReplicate()
        end
    end
    step()
end

local function startReplicate()
    scan.mode = "replicate"
    scan.agg, scan.sigs, scan.count = {}, {}, 0
    scan.lastProgress = GetTime()
    scan.asked = GetTime()
    scan.repBusy, scan.gotList, scan.passes, scan.done, scan.auctions = false, false, 0, 0, nil
    ns.R().replicateAt = time()
    if not pcall(AH.ReplicateItems) then
        startBrowse()
        return
    end
    ns.Fire("SCAN_PROGRESS")
end

----------------------------------------------------------------------
-- SLOW: browse, page by page
----------------------------------------------------------------------

local function ingest(results)
    if type(results) ~= "table" then
        return
    end
    for i = 1, #results do
        local r = results[i]
        local key = r and r.itemKey
        if key and key.itemID and (key.battlePetSpeciesID or 0) == 0 then
            -- The same row can be delivered more than once; count it once.
            local sig = key.itemID .. ":" .. (key.itemLevel or 0) .. ":" .. (key.itemSuffix or 0)
            if not scan.sigs[sig] then
                scan.sigs[sig] = true
                addListing(key.itemID, r.minPrice, r.totalQuantity, false, key)
            end
        end
    end
end

local function requestMore()
    if not scan.active or scan.mode ~= "browse" then
        return
    end
    if throttleReady() then
        scan.wantMore = false
        scan.lastRequest = GetTime()
        scan.pages = (scan.pages or 0) + 1
        pcall(AH.RequestMoreBrowseResults)
    else
        scan.wantMore = true
    end
end

local function onBrowse(added)
    if not scan.active or scan.mode ~= "browse" then
        return
    end
    if added then
        ingest(added)
    else
        ingest(ns.try(AH.GetBrowseResults))
    end
    scan.lastProgress = GetTime()
    ns.Fire("SCAN_PROGRESS")
    if hasFullResults() then
        -- An "all done" with nothing in it right after asking is just the
        -- previous search's leftovers; wait for real results.
        if scan.count > 0 or GetTime() - scan.asked > 4 then
            finish(true)
        end
    else
        requestMore()
    end
end

local function qualityFilters()
    local out = {}
    local E = Enum and Enum.AuctionHouseFilter
    if E then
        for _, k in ipairs({ "PoorQuality", "CommonQuality", "UncommonQuality", "RareQuality", "EpicQuality",
            "LegendaryQuality", "ArtifactQuality" }) do
            if E[k] then
                out[#out + 1] = E[k]
            end
        end
    end
    return out
end

startBrowse = function()
    scan.mode = "browse"
    scan.agg, scan.sigs, scan.count = {}, {}, 0
    scan.lastProgress = GetTime()
    scan.lastRequest = GetTime()
    scan.asked = GetTime()
    scan.wantMore = false
    scan.pages = 1
    local sorts = {}
    local SO = Enum and Enum.AuctionHouseSortOrder
    if SO then
        sorts[1] = { sortOrder = SO.Price, reverseSort = false }
        sorts[2] = { sortOrder = SO.Name, reverseSort = false }
    end
    local ok = pcall(AH.SendBrowseQuery, {
        searchString = "",
        sorts = sorts,
        minLevel = 0,
        maxLevel = 0,
        filters = qualityFilters(),
    })
    if not ok then
        finish(false)
    end
    ns.Fire("SCAN_PROGRESS")
end

----------------------------------------------------------------------
-- Watchdog: keeps a scan moving and makes sure it always ends
----------------------------------------------------------------------

local function watchdog()
    if not scan.active then
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        return
    end
    local now = GetTime()
    local idle = now - (scan.lastProgress or now)
    if scan.mode == "browse" then
        if scan.wantMore then
            requestMore()
        elseif idle > 5 and now - (scan.lastRequest or 0) > 5 then
            if scan.count > 0 and hasFullResults() then
                finish(true)
                return
            end
            requestMore()
        end
        if idle > 30 then
            finish(false)
            return
        end
    else
        if not scan.gotList and now - scan.asked > FAST_WAIT then
            -- Nothing arrived. Most likely the 15 minute limit (another addon
            -- or another character may have used it). Go the slow way.
            scan.note = "The fast download wasn't available just now, so I used the slow scan."
            startBrowse()
            return
        end
        if scan.gotList and idle > 45 then
            startBrowse()
            return
        end
    end
    ns.Fire("SCAN_PROGRESS")
end

----------------------------------------------------------------------
-- Finishing
----------------------------------------------------------------------

local function queryOwned()
    if ns.ahOpen and AH and AH.QueryOwnedAuctions and not scan.active then
        pcall(AH.QueryOwnedAuctions, {})
    end
end

finish = function(complete, quiet)
    if not scan.active then
        return
    end
    scan.active = false
    scan.wantMore = false
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    -- Half a fast download is worse than none: an item's cheapest auction
    -- may be in the half that wasn't read. Throw it away.
    if scan.mode == "replicate" and not complete then
        scan.agg, scan.count = {}, 0
    end
    local n = scan.count
    local R = ns.R()
    local took = GetTime() - (scan.started or GetTime())
    if n == 0 then
        if not quiet then
            ns.Print("the auction house didn't send any prices. Close and reopen the auction window, then press Scan again.")
        end
        ns.Fire("SCAN_DONE")
        return
    end
    -- A scan that came back much smaller than the last full one was probably
    -- interrupted (for example by a search typed mid-scan). Keep what it
    -- found, but don't conclude that everything else has sold out...
    local plausible = complete and (not R.lastCount or n >= R.lastCount * 0.5)
    if complete and not plausible then
        -- ...unless it happens twice running, in which case the auction
        -- house really has shrunk.
        R.smallScans = (R.smallScans or 0) + 1
        if R.smallScans >= 2 then
            plausible = true
        end
    end
    if plausible then
        R.smallScans = 0
    end
    ns.RecordPrices(scan.agg, plausible)
    if plausible or n >= 300 then
        R.lastScan = time()
        R.lastScanBy = ns.Char().name
    end
    if plausible then
        R.lastCount = n
    end
    local ids = {}
    scan.keys = {}
    for id, a in pairs(scan.agg) do
        ids[#ids + 1] = id
        if a.k then
            scan.keys[id] = a.k
        end
    end
    ns.WarmItems(ids)
    scan.lastResult = { mode = scan.mode, n = n, complete = plausible, took = took, pages = scan.pages,
        auctions = scan.mode == "replicate" and scan.auctions or nil, arrived = scan.arrived,
        passes = scan.mode == "replicate" and scan.passes or nil, note = scan.note, at = time() }
    -- Kept between sessions so /gold debug can say how scans have been going.
    R.lastScanInfo = scan.lastResult
    scan.agg, scan.sigs = {}, {}
    local secs = max(1, floor(took + 0.5))
    if plausible then
        ns.Print("prices updated - " .. ns.Commas(n) .. " different items in " .. secs .. " seconds"
            .. (scan.mode == "replicate" and " (fast scan)" or "") .. ". Type |cffffffff/gold|r for advice.")
    elseif not quiet then
        ns.Print("scan stopped early, but I saved the " .. ns.Commas(n) .. " prices I got. Press Scan to finish the job.")
    end
    if scan.note then
        ns.Print(scan.note)
        scan.note = nil
    end
    ns.Fire("PRICES_UPDATED")
    ns.Fire("SCAN_DONE")
    C_Timer.After(1.5, ns.Guard("owned", queryOwned))
    C_Timer.After(3, ns.Guard("verify", function() ns.VerifyDeals() end))
end

----------------------------------------------------------------------
-- Starting
----------------------------------------------------------------------

-- Is the fast download allowed right now?
local function fastAllowed(R)
    if not ns.db.opts.fastScan or R.fastBad then
        return false
    end
    if not (AH.ReplicateItems and AH.GetNumReplicateItems and AH.GetReplicateItemInfo) then
        return false
    end
    if time() - (R.replicateAt or 0) < FAST_COOLDOWN then
        return false
    end
    -- Until it has been proven on this realm, it needs recent slow-scan
    -- prices to be checked against.
    if not R.fastOK and not (R.lastScan and time() - R.lastScan < 3 * 86400) then
        return false
    end
    return true
end

-- The fast scan would be used, it's only waiting out the game's 15 minutes.
local function fastWaitingOnly(R)
    if not ns.db.opts.fastScan or R.fastBad then
        return false
    end
    if not (AH.ReplicateItems and AH.GetNumReplicateItems and AH.GetReplicateItemInfo) then
        return false
    end
    if not R.fastOK and not (R.lastScan and time() - R.lastScan < 3 * 86400) then
        return false
    end
    return time() - (R.replicateAt or 0) < FAST_COOLDOWN
end
ns.FastWaitingOnly = function() return AH and fastWaitingOnly(ns.R()) end

-- mode: nil = pick the fastest allowed, "replicate" = force fast, "browse" = force slow
function ns.StartScan(mode)
    if scan.active then
        return
    end
    AH = C_AuctionHouse
    if not AH or not AH.SendBrowseQuery then
        ns.Print("this game client doesn't have the auction functions I need.")
        return
    end
    if not ns.ahOpen then
        ns.Print("talk to an auctioneer first - I can only read prices while the auction window is open.")
        return
    end
    if ns.SellJob and ns.SellJob() then
        ns.Print("finish or cancel the Sell panel first.")
        return
    end
    local R = ns.R()
    if not mode and not fastAllowed(R) and fastWaitingOnly(R) then
        -- The slow scan takes a minute or more; the fast one is a short wait
        -- away. Say so instead of starting the slow one.
        local wait = ns.FastScanWait()
        ns.Print(string.format("the full scan can run again in %d:%02d (the game allows one every 15 minutes). ",
            floor(wait / 60), wait % 60)
            .. (R.lastScan and ("Prices are from " .. ns.Ago(R.lastScan) .. ". ") or "")
            .. "To read page by page now instead, type |cffffffff/gold scan slow|r.")
        return
    end
    scan.active = true
    scan.started = GetTime()
    scan.arrived = nil
    scan.note = nil
    scan.pages = nil
    if ticker then
        ticker:Cancel()
    end
    ticker = C_Timer.NewTicker(0.25, ns.Guard("scan-watchdog", watchdog))

    if mode == "replicate" then
        R.fastBad = nil
        startReplicate()
    elseif mode ~= "browse" and fastAllowed(R) then
        startReplicate()
    else
        startBrowse()
    end
end

function ns.StopScan()
    if scan.active then
        finish(false)
    end
end

-- Seconds until the fast scan may be used again (0 = now).
function ns.FastScanWait()
    local left = FAST_COOLDOWN - (time() - (ns.R().replicateAt or 0))
    return left > 0 and left or 0
end

-- One line describing the scanner, for the status bars.
function ns.ScanStatus()
    if scan.active then
        local secs = floor(GetTime() - (scan.started or GetTime()))
        if scan.mode == "replicate" then
            if not scan.gotList then
                return "Downloading the whole auction house... (" .. secs .. "s)", true
            end
            return "Reading auctions... " .. ns.Commas(scan.done or 0) .. " of " .. ns.Commas(scan.auctions or 0)
                .. " (" .. secs .. "s)", true
        end
        return "Reading prices... " .. ns.Commas(scan.count) .. " items so far (" .. secs .. "s)", true
    end
    local R = ns.R()
    if not R.lastScan then
        return "No prices yet - visit an auctioneer.", false
    end
    return "Prices read " .. ns.Ago(R.lastScan) .. " (" .. ns.Commas(ns.PriceCount()) .. " items for sale)", false
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
    onBrowse(nil)
end)

ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(added)
    onBrowse(type(added) == "table" and added or {})
end)

ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
    if scan.active and scan.wantMore then
        requestMore()
    end
    if ns.VerifyNext then
        ns.VerifyNext()
    end
end)

ns.On("AUCTION_HOUSE_BROWSE_FAILURE", function()
    if scan.active and scan.mode == "browse" then
        finish(false)
    end
end)

ns.On("REPLICATE_ITEM_LIST_UPDATE", function()
    if scan.active and scan.mode == "replicate" and not scan.repBusy and not scan.gotList then
        scan.lastProgress = GetTime()
        -- Prices and counts are usable straight away; no need to wait for
        -- every item's name to load.
        ns.Later("replicate-process", 0.2, processReplicate)
    end
end)

-- Should opening the auction window start a scan by itself?
-- Yes once the prices are older than the chosen age (5 minutes by default),
-- as long as the fast scan is allowed. The slow scan takes over your auction
-- window for a while, so it is only started automatically when the prices
-- are at least 15 minutes old.
local function autoScanDue()
    if not ns.db.opts.autoScan then
        return false
    end
    local R = ns.R()
    if not R.lastScan then
        return true
    end
    local age = time() - R.lastScan
    local wanted = ns.db.opts.autoAge or 300
    if age < wanted then
        return false
    end
    if fastAllowed(R) then
        return true
    end
    -- Never start the slow scan just because the fast one is a few minutes away.
    if fastWaitingOnly(R) then
        return false
    end
    return age >= max(wanted, 15 * 60)
end

ns.On("AUCTION_HOUSE_SHOW", function()
    ns.ahOpen = true
    ns.Fire("AH_SHOW")
    if autoScanDue() then
        C_Timer.After(1.5, ns.Guard("autoscan", function()
            if ns.ahOpen and not scan.active and not (ns.SellJob and ns.SellJob()) then
                ns.StartScan()
            end
        end))
    end
end)

ns.On("AUCTION_HOUSE_CLOSED", function()
    ns.ahOpen = false
    if scan.active then
        local had = scan.count
        finish(false, true)
        ns.Print(had > 0 and "the auction window closed, so the scan stopped early."
            or "the auction window closed before any prices arrived.")
    end
    ns.Fire("AH_CLOSED")
end)

-- Your own auctions, so the Bags tab can warn you when you've been undercut.
ns.On("OWNED_AUCTIONS_UPDATED", function()
    if not ns.ready then
        return
    end
    local list = ns.try(AH.GetOwnedAuctions)
    if type(list) ~= "table" then
        return
    end
    local mine = {}
    for _, a in ipairs(list) do
        local key = a.itemKey
        if key and key.itemID and (a.status == nil or a.status == 0) and a.buyoutAmount and a.buyoutAmount > 0 then
            local qty = max(1, a.quantity or 1)
            mine[#mine + 1] = { id = key.itemID, q = qty, p = a.buyoutAmount / qty }
        end
    end
    ns.Char().auctions = mine
    ns.Char().auctionsAt = time()
    ns.Fire("BAGS_UPDATED")
end)

----------------------------------------------------------------------
-- The verifier
--
-- After a slow scan, a piece of gear's "lowest price" might be a bid. Before
-- the Deals tab shows it, look that one item up and find its cheapest real
-- buyout. If it has none, it is marked bid-only and never shown as a deal.
-- Only a handful of the most promising candidates are checked, one at a
-- time, while the auction window is open.
----------------------------------------------------------------------

local verify = { queue = {}, current = nil, checked = 0 }
local VERIFY_LIMIT = 40

function ns.VerifyPending()
    return #verify.queue + (verify.current and 1 or 0)
end

local function verifyDone(id, best, isCommodity)
    local rec = ns.R().prices[id]
    if rec then
        if isCommodity then
            rec.b = true
        elseif best then
            rec.p, rec.b = best, true
        else
            rec.b = false
        end
    end
    verify.current = nil
    ns.Later("verify-refresh", 1.0, function() ns.Fire("PRICES_UPDATED") end)
    C_Timer.After(0.3, ns.Guard("verify", function() ns.VerifyNext() end))
end

function ns.VerifyNext()
    if verify.current or not ns.ahOpen or scan.active or (ns.SellJob and ns.SellJob()) then
        return
    end
    -- The auction window's own price checks and posts go first; try later.
    if ns.AHBusy and ns.AHBusy() then
        ns.Later("verify-wait", 3, ns.VerifyNext)
        return
    end
    local id = table.remove(verify.queue, 1)
    if not id then
        return
    end
    local key = scan.keys[id]
    if not key then
        return ns.VerifyNext()
    end
    if not throttleReady() then
        table.insert(verify.queue, 1, id)
        return -- AUCTION_HOUSE_THROTTLED_SYSTEM_READY calls back in
    end
    verify.current = { id = id, key = key }
    verify.checked = verify.checked + 1
    local SO = Enum and Enum.AuctionHouseSortOrder
    local sorts = SO and { { sortOrder = SO.Buyout or SO.Price, reverseSort = false } } or {}
    if not pcall(AH.SendSearchQuery, key, sorts, false) then
        verify.current = nil
        return
    end
    C_Timer.After(5, ns.Guard("verify", function()
        if verify.current and verify.current.id == id then
            verify.current = nil
            ns.VerifyNext()
        end
    end))
end

-- Queues the best unconfirmed deal candidates for checking.
function ns.VerifyDeals()
    if not ns.ahOpen or scan.active or not ns.PendingDeals then
        return
    end
    local queued = {}
    for _, id in ipairs(verify.queue) do
        queued[id] = true
    end
    for _, id in ipairs(ns.PendingDeals()) do
        if #verify.queue >= VERIFY_LIMIT then
            break
        end
        if not queued[id] and scan.keys[id] and not (verify.current and verify.current.id == id) then
            verify.queue[#verify.queue + 1] = id
        end
    end
    ns.VerifyNext()
end

ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
    local cur = verify.current
    if not cur or type(itemKey) ~= "table" or itemKey.itemID ~= cur.id then
        return
    end
    local n = ns.try(AH.GetNumItemSearchResults, cur.key) or 0
    local best
    for i = 1, min(n, 60) do
        local r = ns.try(AH.GetItemSearchResultInfo, cur.key, i)
        if type(r) == "table" and r.buyoutAmount and r.buyoutAmount > 0 then
            local unit = r.buyoutAmount / max(1, r.quantity or 1)
            if not best or unit < best then
                best = unit
            end
        end
    end
    verifyDone(cur.id, best, false)
end)

ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
    local cur = verify.current
    if cur and itemID == cur.id then
        -- Stackable goods can't be bid on, so the price was a buyout all along.
        verifyDone(cur.id, nil, true)
    end
end)

-- New item facts (vendor values) can reveal more candidates.
ns.Listen("ITEMS_UPDATED", function()
    if ns.ahOpen and not scan.active then
        ns.Later("verify-deals", 2, function() ns.VerifyDeals() end)
    end
end)

ns.Listen("AH_CLOSED", function()
    verify.queue, verify.current = {}, nil
end)

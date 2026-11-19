-- Forever Gold - the auction window
--
-- Talking to an auctioneer opens this window instead of the game's own.
-- Three tabs, like the game's:
--   Browse    search or pick a category; each result shows its usual price,
--             how it compares and how fast it sells. Click one to see every
--             listing and buy (stackable goods: any amount; gear: the one
--             you pick). Deals finds the bargains from your last scan.
--   Sell      the post queue (Poster.lua): tick what to sell, price-check it,
--             then press Post once per listing.
--   Auctions  your auctions with live undercut checks, and one-click-each
--             cancelling of the undercut ones.
-- "Game's window" switches back to Blizzard's auction window (remembered);
-- a button above that window switches back here.
--
-- The game's window is still open underneath (closing it would close the
-- auction house), just shrunk to nothing and invisible. Escape, walking
-- away and the X all close the auction house as normal.

local _, ns = ...
local floor, max, min = math.floor, math.max, math.min

local K = ns.UIKit
local C = K.C
local tex, skin, label, button, setIcon, edgeFor = K.tex, K.skin, K.label, K.button, K.setIcon, K.edgeFor
local GREY = K.GREY
local AH = C_AuctionHouse
local P = ns.Poster
local CUT = ns.AH_CUT

local W, H = 1000, 560
local TOP = 78       -- where the tab content starts
local FOOT = 34      -- footer height
local ROW_H = 22
local SIDE_W = 280   -- the right-hand panel on Sell and Auctions

local A = { tab = "browse" }
ns.AuctionUI = A
local win

local function plural(n, word)
    return n .. " " .. word .. (n == 1 and "" or "s")
end

----------------------------------------------------------------------
-- Building blocks: a sortable table, a text box, a side panel
----------------------------------------------------------------------

local function tip(self)
    local d = self.d
    if not d or not GameTooltip then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if d.link and GameTooltip.SetHyperlink then
        pcall(GameTooltip.SetHyperlink, GameTooltip, d.link)
    elseif d.id then
        pcall(GameTooltip.SetItemByID, GameTooltip, d.id)
    elseif d.tip then
        GameTooltip:SetText(d.tip, 1, 1, 1, 1, true)
    else
        GameTooltip:Hide()
        return
    end
    -- Anything cut short in a narrow column, in full.
    for _, fs in pairs(self.cells or {}) do
        if fs.IsTruncated and fs:IsTruncated() then
            local text = fs:GetText()
            if text and text ~= "" then
                GameTooltip:AddLine(text, 1, 1, 1, true)
            end
        end
    end
    if d.hint then
        GameTooltip:AddLine(d.hint, 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function untip()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

-- cols: { { key =, title =, w = (nil = the rest), right = true, icon = true, check = true, sort = true } }
-- data rows: { key =, id =, link =, icon =, cells = { [colKey] = text }, sv = { [colKey] = sortValue },
--              checked =, dim = }
local function newTable(parent, w, h, cols)
    local t = CreateFrame("Frame", nil, parent)
    t:SetSize(w, h)
    skin(t, 0.045, 0.043, 0.04, 1, C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 1)
    t.cols, t.data, t.view, t.rows, t.offset = cols, {}, {}, {}, 0
    t.visible = floor((h - 24) / ROW_H)
    local fixed = 0
    for _, c in ipairs(cols) do
        fixed = fixed + (c.w or 0)
    end
    local x = 6
    for _, c in ipairs(cols) do
        c.x = x
        c.width = c.w or max(60, w - 18 - fixed)
        x = x + c.width
    end

    local head = CreateFrame("Frame", nil, t)
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetSize(w - 2, 22)
    tex(head, "BACKGROUND", C.panel[1], C.panel[2], C.panel[3], 1):SetAllPoints()
    t.heads = {}
    for i, c in ipairs(cols) do
        local b = CreateFrame("Button", nil, head)
        b:SetPoint("TOPLEFT", c.x - 1, 0)
        b:SetSize(c.width, 22)
        b.text = label(b, "GameFontNormalSmall", c.title or "")
        b.text:SetTextColor(C.head[1], C.head[2], C.head[3])
        b.text:SetPoint(c.right and "RIGHT" or "LEFT", c.right and -6 or (c.icon and 24 or 2), 0)
        if c.sort then
            b:SetScript("OnClick", function()
                if t.sortKey == c.key then
                    t.sortAsc = not t.sortAsc
                else
                    t.sortKey, t.sortAsc = c.key, not c.right
                end
                t:SetData(t.data, true)
            end)
        end
        t.heads[i] = b
    end

    t.thumb = tex(t, "OVERLAY", C.edge[1], C.edge[2], C.edge[3], 0.9)
    t.thumb:SetWidth(3)
    t.empty = label(t, "GameFontDisable")
    t.empty:SetPoint("TOP", 0, -60)
    t.empty:SetWidth(w - 60)
    t.empty:SetJustifyH("CENTER")

    local function rowClick(r, which)
        if not r.d then
            return
        end
        if (r.d.id or r.d.link) and ns.TryDressUp(r.d.id, r.d.link) then
            return
        end
        if r.d.id and IsShiftKeyDown and IsShiftKeyDown() then
            local _, link = ns.try(C_Item.GetItemInfo, r.d.id)
            link = r.d.link or link
            if link and ChatEdit_InsertLink then
                pcall(ChatEdit_InsertLink, link)
            end
            return
        end
        t.selected = r.d.key
        t:Render()
        if t.onClick then
            local ok, err = pcall(t.onClick, r.d, which)
            if not ok then
                ns.Err("table", err)
            end
        end
    end

    for i = 1, t.visible do
        local r = CreateFrame("Button", nil, t)
        r:SetSize(w - 8, ROW_H)
        r:SetPoint("TOPLEFT", 1, -23 - (i - 1) * ROW_H)
        r.band = tex(r, "BACKGROUND", 1, 1, 1, i % 2 == 0 and 0.022 or 0)
        r.band:SetAllPoints()
        r.sel = tex(r, "BACKGROUND", 1, 0.92, 0.75, 0.08)
        r.sel:SetAllPoints()
        r.bar = tex(r, "ARTWORK", C.goldEdge[1], C.goldEdge[2], C.goldEdge[3], 1)
        r.bar:SetPoint("TOPLEFT")
        r.bar:SetPoint("BOTTOMLEFT")
        r.bar:SetWidth(2)
        local hl = tex(r, "HIGHLIGHT", 1, 1, 1, 0.05)
        hl:SetAllPoints()
        r.cells = {}
        for j, c in ipairs(cols) do
            if c.check then
                local cb = CreateFrame("Button", nil, r)
                cb:SetSize(16, 16)
                cb:SetPoint("LEFT", c.x + 2, 0)
                skin(cb, 0.02, 0.02, 0.02, 1, C.btnEdge[1], C.btnEdge[2], C.btnEdge[3], 1)
                cb.mark = tex(cb, "ARTWORK", C.goldEdge[1], C.goldEdge[2], C.goldEdge[3], 1)
                cb.mark:SetPoint("TOPLEFT", 4, -4)
                cb.mark:SetPoint("BOTTOMRIGHT", -4, 4)
                cb:SetScript("OnClick", function()
                    if r.d and t.onCheck then
                        local ok, err = pcall(t.onCheck, r.d)
                        if not ok then
                            ns.Err("table-check", err)
                        end
                    end
                end)
                r.check = cb
            else
                if c.icon then
                    r.iconEdge = r:CreateTexture(nil, "BORDER")
                    r.icon = r:CreateTexture(nil, "ARTWORK")
                    r.icon:SetSize(18, 18)
                    r.icon:SetPoint("LEFT", c.x + 2, 0)
                    r.iconEdge:SetPoint("TOPLEFT", r.icon, "TOPLEFT", -1, 1)
                    r.iconEdge:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 1, -1)
                end
                local fs = label(r, "GameFontHighlightSmall")
                fs:SetWordWrap(false)
                fs:SetJustifyH(c.right and "RIGHT" or "LEFT")
                local inset = c.icon and 24 or 2
                fs:SetPoint("LEFT", c.x + inset, 0)
                fs:SetWidth(c.width - inset - 6)
                r.cells[j] = fs
            end
        end
        r:SetScript("OnClick", rowClick)
        if r.RegisterForClicks then
            r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        end
        r:SetScript("OnEnter", tip)
        r:SetScript("OnLeave", untip)
        t.rows[i] = r
    end

    t:EnableMouseWheel(true)
    t:SetScript("OnMouseWheel", function(_, delta)
        t.offset = t.offset - delta * 3
        t:Render()
    end)

    function t:SetData(data, keep)
        self.data = data or {}
        local view = {}
        for i, d in ipairs(self.data) do
            view[i] = d
        end
        local key = self.sortKey
        if key then
            local asc = self.sortAsc
            table.sort(view, function(a, b)
                local x, y = a.sv and a.sv[key], b.sv and b.sv[key]
                if x == nil and y == nil then
                    return false
                elseif x == nil then
                    return false
                elseif y == nil then
                    return true
                end
                if type(x) ~= type(y) then
                    x, y = tostring(x), tostring(y)
                end
                if asc then
                    return x < y
                end
                return x > y
            end)
        end
        self.view = view
        if not keep then
            self.offset = 0
        end
        self:Render()
    end

    function t:Render()
        local n = #self.view
        local maxOff = max(0, n - self.visible)
        self.offset = max(0, min(self.offset, maxOff))
        for i = 1, self.visible do
            local r = self.rows[i]
            local d = self.view[i + self.offset]
            r.d = d
            if d then
                r:Show()
                local on = self.selected ~= nil and d.key == self.selected
                r.sel:SetShown(on)
                r.bar:SetShown(on)
                if r.icon then
                    if d.id or d.icon then
                        setIcon(r.icon, d.icon or ns.Icon(d.id))
                        edgeFor(r.iconEdge, d.id)
                        r.icon:Show()
                        r.iconEdge:Show()
                    else
                        r.icon:Hide()
                        r.iconEdge:Hide()
                    end
                end
                if r.check then
                    r.check.mark:SetShown(d.checked and true or false)
                    r.check:SetShown(d.checked ~= nil)
                end
                for j, c in ipairs(self.cols) do
                    local fs = r.cells[j]
                    if fs then
                        local text = d.cells and d.cells[c.key]
                        fs:SetText(text ~= nil and tostring(text) or "")
                        if d.dim then
                            fs:SetAlpha(0.5)
                        else
                            fs:SetAlpha(1)
                        end
                    end
                end
            else
                r:Hide()
            end
        end
        self.empty:SetShown(n == 0)
        if maxOff > 0 then
            local trackH = self:GetHeight() - 26
            local size = max(20, trackH * self.visible / n)
            self.thumb:SetHeight(size)
            self.thumb:ClearAllPoints()
            self.thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", -2, -24 - (trackH - size) * (self.offset / maxOff))
            self.thumb:Show()
        else
            self.thumb:Hide()
        end
        for i, c in ipairs(self.cols) do
            local arrow = (self.sortKey == c.key) and (self.sortAsc and " ^" or " v") or ""
            self.heads[i].text:SetText((c.title or "") .. arrow)
        end
    end

    function t:SetEmpty(text)
        self.empty:SetText(text or "")
    end
    return t
end

local function newEdit(parent, w, onEnter)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w, 22)
    skin(e, 0.02, 0.02, 0.02, 1, C.btnEdge[1], C.btnEdge[2], C.btnEdge[3], 1)
    if e.SetFontObject and _G.GameFontHighlight then
        e:SetFontObject(_G.GameFontHighlight)
    end
    e:SetAutoFocus(false)
    e:SetTextInsets(6, 6, 0, 0)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if onEnter then
            local ok, err = pcall(onEnter, self:GetText() or "")
            if not ok then
                ns.Err("edit", err)
            end
        end
    end)
    return e
end

local function newSide(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(SIDE_W, H - TOP - FOOT - 8)
    s:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -TOP)
    skin(s, C.panel[1], C.panel[2], C.panel[3], 1, C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 1)
    s.iconEdge = s:CreateTexture(nil, "BORDER")
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetSize(32, 32)
    s.icon:SetPoint("TOPLEFT", 10, -10)
    s.iconEdge:SetPoint("TOPLEFT", s.icon, "TOPLEFT", -1, 1)
    s.iconEdge:SetPoint("BOTTOMRIGHT", s.icon, "BOTTOMRIGHT", 1, -1)
    s.title = label(s, "GameFontHighlight")
    s.title:SetPoint("TOPLEFT", 50, -10)
    s.title:SetWidth(SIDE_W - 60)
    s.title:SetWordWrap(false)
    s.sub = label(s, "GameFontHighlightSmall")
    s.sub:SetPoint("TOPLEFT", 50, -27)
    s.sub:SetWidth(SIDE_W - 60)
    s.sub:SetWordWrap(false)
    s.body = label(s, "GameFontHighlightSmall")
    s.body:SetPoint("TOPLEFT", 10, -52)
    s.body:SetWidth(SIDE_W - 20)
    s.body:SetJustifyV("TOP")
    s.body:SetWordWrap(true)
    function s:SetItem(id, title, sub)
        if id then
            setIcon(self.icon, ns.Icon(id))
            edgeFor(self.iconEdge, id)
            self.icon:Show()
            self.iconEdge:Show()
            self.title:SetPoint("TOPLEFT", 50, -10)
        else
            self.icon:Hide()
            self.iconEdge:Hide()
            self.title:SetPoint("TOPLEFT", 10, -10)
        end
        self.title:SetText(title or "")
        self.sub:SetText(sub or "")
    end
    return s
end

local function timeLeftText(secs, band)
    if secs and secs > 0 then
        local h = floor(secs / 3600)
        if h >= 1 then
            return h .. "h " .. floor((secs % 3600) / 60) .. "m"
        end
        return max(1, floor(secs / 60)) .. "m"
    end
    local names = { [0] = "Under 30m", [1] = "30m - 2h", [2] = "2h - 12h", [3] = "Over 12h" }
    return band and names[band] or "-"
end

-- Prices that make no sense (see ns.Suspicious in Prices.lua).
local SUSPICIOUS = "|cffff7070Suspicious|r"
local SUSPICIOUS_HISTORY = "|cffff9a5aSuspicious price history|r"

local function usualText(id)
    local usual, days = ns.UsualPrice(id)
    if usual and (days or 0) >= 2 then
        return usual
    end
    return nil
end

-- How a price compares with the usual one, coloured: green when cheap.
local function versus(price, usual)
    if not price or not usual or usual <= 0 then
        return "", nil
    end
    local pct = floor((price / usual - 1) * 100 + 0.5)
    if pct <= -15 then
        return "|cff40e060" .. pct .. "%|r", pct
    elseif pct >= 20 then
        return "|cffff6060+" .. pct .. "%|r", pct
    end
    return GREY .. (pct > 0 and "+" or "") .. pct .. "%|r", pct
end

----------------------------------------------------------------------
-- Browse and buy
----------------------------------------------------------------------

-- `dirty`: the result rows need building again (new results or new prices);
-- otherwise a refresh only redraws the rows already built.
local BUY = { mode = "list", results = {}, query = "", dirty = true }
A.BUY = BUY

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

local function keyInfo(key)
    local info = key and ns.try(AH.GetItemKeyInfo, key)
    return type(info) == "table" and info or nil
end

local function buyMsg(text)
    BUY.message = text
    ns.Fire("POSTER")
end

-- A browse search: text, a category from the game's list, or both.
function A.Search(text, category)
    if not ns.ahOpen then
        return
    end
    if ns.scan and ns.scan.active then
        buyMsg("Wait for the price scan to finish, then search.")
        return
    end
    BUY.query = text or ""
    BUY.category = category
    BUY.mode, BUY.item, BUY.deals = "list", nil, nil
    BUY.results, BUY.seen = {}, {}
    BUY.dirty = true
    BUY.searching = true
    BUY.message = nil
    local SO = Enum and Enum.AuctionHouseSortOrder
    local sorts = {}
    if SO then
        sorts[1] = { sortOrder = SO.Price, reverseSort = false }
        sorts[2] = { sortOrder = SO.Name, reverseSort = false }
    end
    local filters = qualityFilters()
    if category and category.implicitFilter then
        filters[#filters + 1] = category.implicitFilter
    end
    local ok = pcall(AH.SendBrowseQuery, {
        searchString = BUY.query,
        sorts = sorts,
        minLevel = 0,
        maxLevel = 0,
        filters = filters,
        itemClassFilters = category and category.filters or nil,
    })
    if not ok then
        BUY.searching = false
        buyMsg("The auction house wouldn't run that search.")
        return
    end
    BUY.asked = GetTime()
    ns.Fire("POSTER")
end

local function addResults(list)
    if type(list) ~= "table" then
        return
    end
    for _, r in ipairs(list) do
        local key = r.itemKey
        if key and key.itemID then
            local sig = key.itemID .. ":" .. (key.itemLevel or 0) .. ":" .. (key.itemSuffix or 0) .. ":" .. (key.battlePetSpeciesID or 0)
            if not BUY.seen[sig] then
                BUY.seen[sig] = true
                BUY.dirty = true
                BUY.results[#BUY.results + 1] = { key = key, id = key.itemID, qty = r.totalQuantity or 0,
                    price = r.minPrice, mine = r.containsOwnerItem }
            end
        end
    end
end

local function onBrowse(added)
    if not BUY.searching then
        return
    end
    if ns.scan and ns.scan.active then
        -- A price scan took over the search; its results aren't ours.
        BUY.searching = false
        buyMsg("A price scan started, so the search stopped. Search again once it's done.")
        return
    end
    if added then
        addResults(added)
    else
        BUY.results, BUY.seen = {}, {}
        BUY.dirty = true
        addResults(ns.try(AH.GetBrowseResults))
    end
    local full = ns.try(AH.HasFullBrowseResults)
    if full or #BUY.results >= 500 then
        BUY.searching = false
    elseif ns.try(AH.IsThrottledMessageSystemReady) ~= false then
        pcall(AH.RequestMoreBrowseResults)
    end
    ns.Later("auction-ui", 0.1, function() A.Refresh() end)
end

ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function() onBrowse(nil) end)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(added) onBrowse(type(added) == "table" and added or {}) end)
ns.On("AUCTION_HOUSE_BROWSE_FAILURE", function()
    if BUY.searching then
        BUY.searching = false
        buyMsg("The search failed. Try again in a moment.")
    end
end)

-- Our own list: everything the last scan found under vendor price or well
-- under its usual price.
function A.ShowDeals()
    BUY.mode, BUY.item, BUY.category = "list", nil, "deals"
    BUY.deals = true
    BUY.results = {}
    BUY.dirty = true
    BUY.message = nil
    for _, f in ipairs(ns.VendorFlips()) do
        BUY.results[#BUY.results + 1] = { id = f.id, qty = f.listed or 0, price = f.price,
            why = "|cff40e060Vendor pays " .. ns.StripCodes(ns.Money(f.vendor)) .. "|r", profit = f.profit }
    end
    if ns.Bargains then
        for _, b in ipairs(ns.Bargains()) do
            local price, listed = ns.AHPrice(b.id)
            BUY.results[#BUY.results + 1] = { id = b.id, qty = listed or 0, price = price or b.price,
                why = "|cff40e060Well under usual|r", profit = b.profit }
        end
    end
    if #BUY.results == 0 then
        BUY.message = ns.R().lastScan and "No deals in your last scan. Scan again later - they come and go."
            or "Deals come from a price scan. Press Scan prices first."
    end
    A.Refresh()
end

-- One item: every listing, cheapest first.
function A.OpenItem(r, keepMessage)
    if not r or not r.id then
        return
    end
    local info = r.key and keyInfo(r.key)
    local it = ns.Item(r.id)
    local commodity
    if info then
        commodity = info.isCommodity
    else
        commodity = it and (it.st or 1) > 1
    end
    local key = r.key
    if not key or commodity then
        key = ns.try(AH.MakeItemKey, r.id)
    end
    if not key and ns.scan and ns.scan.keys then
        key = ns.scan.keys[r.id]
    end
    if not key then
        buyMsg("The auction house wouldn't look that item up.")
        return
    end
    BUY.mode = "item"
    BUY.item = { id = r.id, key = key, commodity = commodity and true or false, link = info and info.battlePetLink }
    BUY.listings = nil
    BUY.sel = nil
    BUY.qty = 1
    BUY.buy = nil
    if not keepMessage then
        BUY.message = nil
    end
    A.Refresh()
    local item = BUY.item
    ns.AHLookup({ id = r.id, key = key, commodity = item.commodity }, function(listings)
        if BUY.item ~= item then
            return
        end
        if listings then
            A.MarkSellerMoves(r.id, listings)
        end
        BUY.listings = listings or {}
        if not listings then
            BUY.message = "The auction house didn't answer. Click the item again."
        end
        A.Refresh()
    end)
end

----------------------------------------------------------------------
-- Sellers: who's listing what, and what changed since you last looked
----------------------------------------------------------------------

local function shortName(name)
    return (tostring(name or ""):gsub("%-.*$", ""))
end

-- One seller per row, unless several people sell at that exact price (commodities).
local function soleOwner(l)
    if l.mine and (l.sellers or 1) <= 1 then
        return "You"
    end
    if (l.sellers or 1) > 1 or not l.owner or l.owner == "" then
        return nil
    end
    return l.owner
end
A.SoleOwner = soleOwner

-- Compares these listings with the last ones you saw for this item (this
-- session) and marks each row: "new" for a seller who wasn't there,
-- "cut" for one now asking less than their cheapest before.
A.seen = {}
function A.MarkSellerMoves(id, listings)
    local now = {}
    local function note(list)
        for _, l in ipairs(list or {}) do
            local o = soleOwner(l)
            if o and o ~= "You" and l.p then
                now[o] = min(now[o] or math.huge, l.p)
            elseif o and o ~= "You" then
                now[o] = now[o] or math.huge
            end
        end
    end
    note(listings)
    note(listings.bids)
    local prev = A.seen[id]
    if prev then
        local function mark(list)
            for _, l in ipairs(list or {}) do
                local o = soleOwner(l)
                if o and o ~= "You" then
                    if prev[o] == nil then
                        l.move = "new"
                    elseif l.p and prev[o] ~= math.huge and l.p < prev[o] - 0.5 and l.p <= now[o] then
                        l.move = "cut"
                    end
                end
            end
        end
        mark(listings)
        mark(listings.bids)
    end
    A.seen[id] = now
end

local MOVE_TEXT = { new = "|cffffd100 new|r", cut = "|cffff7070 cut|r" }

local function sellerCell(l)
    local o = soleOwner(l)
    local text
    if o == "You" then
        text = "|cffffffffYou|r"
    elseif o then
        text = shortName(o)
    elseif (l.sellers or 1) > 1 then
        text = shortName(l.owner ~= "" and l.owner or "?") .. GREY .. " +" .. (l.sellers - 1) .. "|r"
    else
        text = GREY .. "?|r"
    end
    return text .. (MOVE_TEXT[l.move] or "")
end

local function sellerHint(l)
    if (l.sellers or 1) > 1 then
        local names = {}
        for k, n in ipairs(l.owners or {}) do
            if k > 6 then break end
            names[#names + 1] = n
        end
        local more = l.sellers - #names
        return l.sellers .. " sellers at this price" .. (#names > 0 and (": " .. table.concat(names, ", ")
            .. (more > 0 and (" and " .. more .. " more") or "")) or "") .. "."
    end
    local o = soleOwner(l)
    local h = o == "You" and "Your auction." or (o and ("Seller: " .. o .. ".")) or "The seller's name hasn't loaded yet."
    if l.move == "new" then
        h = h .. " New since you last looked at this item."
    elseif l.move == "cut" then
        h = h .. " They've lowered their price since you last looked."
    end
    return h
end

function A.RefreshItem()
    if BUY.item then
        local r = { id = BUY.item.id, key = BUY.item.key }
        A.OpenItem(r, true)
    end
end

-- Cheapest-first cost of `qty` from other people's listings.
local function commodityCost(qty)
    local left, total = qty, 0
    for _, l in ipairs(BUY.listings or {}) do
        local avail = l.q - (l.own or 0)
        if avail > 0 then
            local take = min(avail, left)
            total = total + take * l.p
            left = left - take
            if left <= 0 then
                return total, true
            end
        end
    end
    return total, false
end
A.CommodityCost = commodityCost

local function available()
    local n = 0
    for _, l in ipairs(BUY.listings or {}) do
        n = n + max(0, l.q - (l.own or 0))
    end
    return n
end

-- The buy button. Stackable goods take two clicks (ask the price, then
-- confirm it); gear is one click on the listing you picked. Only ever
-- called from a click.
function A.Buy()
    local item = BUY.item
    if not item or not BUY.listings then
        return
    end
    if item.commodity then
        local b = BUY.buy
        if b and b.state == "quoted" then
            if not pcall(AH.ConfirmCommoditiesPurchase, item.id, b.qty) then
                BUY.buy = nil
                buyMsg("The purchase was refused.")
                return
            end
            b.state = "buying"
            ns.Fire("POSTER")
            return
        end
        if b then
            return
        end
        local qty = max(1, min(BUY.qty or 1, available()))
        if not pcall(AH.StartCommoditiesPurchase, item.id, qty) then
            buyMsg("The game blocked that purchase.")
            return
        end
        BUY.buy = { state = "quoting", qty = qty, id = item.id, at = GetTime() }
        BUY.message = nil
        ns.Fire("POSTER")
        return
    end
    local l = BUY.sel
    if l and l.bidOnly then
        buyMsg("That auction has no buyout - you can only bid on it.")
        return
    end
    if not l or not l.aid or l.mine or not l.buyout then
        buyMsg("Pick a listing first.")
        return
    end
    if GetMoney() < (l.buyout or 0) then
        buyMsg("You don't have enough gold for that one.")
        return
    end
    if not pcall(AH.PlaceBid, l.aid, l.buyout) then
        buyMsg("The game blocked that purchase.")
        return
    end
    BUY.buy = { state = "buying", aid = l.aid, at = GetTime() }
    BUY.message = nil
    ns.Fire("POSTER")
end

function A.CancelBuy()
    if BUY.buy and BUY.item and BUY.item.commodity and BUY.buy.state ~= "buying" then
        pcall(AH.CancelCommoditiesPurchase)
    end
    BUY.buy = nil
    ns.Fire("POSTER")
end

ns.On("COMMODITY_PRICE_UPDATED", function(unitPrice, totalPrice)
    local b = BUY.buy
    if b and b.state == "quoting" then
        b.state, b.unit, b.total = "quoted", unitPrice, totalPrice
        ns.Fire("POSTER")
    end
end)

ns.On("COMMODITY_PRICE_UNAVAILABLE", function()
    if BUY.buy then
        BUY.buy = nil
        buyMsg("Not enough left at those prices any more. The list has been refreshed.")
        A.RefreshItem()
    end
end)

local function bought(text)
    BUY.buy = nil
    BUY.sel = nil
    buyMsg("|cff40e060" .. text .. "|r")
    C_Timer.After(0.5, ns.Guard("buy-refresh", A.RefreshItem))
end

ns.On("COMMODITY_PURCHASE_SUCCEEDED", function()
    local b = BUY.buy
    if b and b.state == "buying" then
        bought("Bought " .. b.qty .. " for " .. ns.StripCodes(ns.Money(b.total or 0)) .. ". It's in your mailbox.")
    end
end)

ns.On("COMMODITY_PURCHASE_FAILED", function()
    if BUY.buy then
        BUY.buy = nil
        buyMsg("The purchase failed - someone may have bought them first.")
        A.RefreshItem()
    end
end)

ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function()
    local b = BUY.buy
    if b and b.state == "buying" and b.aid then
        bought("Bought. It's in your mailbox.")
    end
end)

ns.On("AUCTION_HOUSE_SHOW_ERROR", function()
    if BUY.buy and BUY.buy.state == "buying" then
        BUY.buy = nil
        buyMsg("The auction house refused that - the red message on screen says why.")
        A.RefreshItem()
    end
end)

----------------------------------------------------------------------
-- The game's categories, for the Browse tab's left column
----------------------------------------------------------------------

local function categoryList()
    local out = { { name = "|cffffd100Deals|r", deals = true, tip = "Bargains from your last price scan: under vendor price, or well under the usual price." } }
    if type(AuctionCategories) ~= "table" then
        return out
    end
    for i, c in ipairs(AuctionCategories) do
        if type(c) == "table" and c.name and not c.isToken then
            out[#out + 1] = { name = c.name, filters = c.filters, implicitFilter = c.implicitFilter, top = i }
            if A.openCategory == i and type(c.subCategories) == "table" then
                for j, s in ipairs(c.subCategories) do
                    out[#out + 1] = { name = "   " .. s.name, filters = s.filters, implicitFilter = s.implicitFilter,
                        top = i, sub = j }
                end
            end
        end
    end
    return out
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------

local tabs = {}

local function setTab(key)
    A.tab = key
    for k, b in pairs(tabs) do
        b:SetOn(k == key)
    end
    win.browse:SetShown(key == "browse")
    win.sell:SetShown(key == "sell")
    win.mine:SetShown(key == "auctions")
    if key == "sell" then
        if P.state ~= "checking" and P.state ~= "posting" and P.state ~= "confirm" and P.state ~= "verify" then
            P.Rebuild()
        end
    elseif key == "auctions" then
        P.QueryOwned()
    end
    A.Refresh()
end
A.SetTab = setTab

local function headerButton(f, text, w, onClick, tipText)
    local b = button(f, text, w, 22, onClick)
    if tipText then
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(tipText, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", untip)
    end
    return b
end

local function buildBrowse(f)
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", 0, 0)
    p:SetSize(W, H)
    local listH = H - TOP - FOOT - 8

    p.cats = newTable(p, 170, listH, { { key = "name", title = "Categories" } })
    p.cats:SetPoint("TOPLEFT", 12, -TOP)
    p.cats.onClick = function(d)
        if d.deals then
            A.openCategory = nil
            A.ShowDeals()
            return
        end
        if d.sub == nil then
            A.openCategory = (A.openCategory == d.top) and nil or d.top
        end
        A.Search(p.search:GetText() or "", d)
    end

    local x0 = 12 + 170 + 8
    local rightW = W - x0 - 12
    p.search = newEdit(p, 260, function(text) A.Search(text, nil) end)
    p.search:SetPoint("TOPLEFT", x0, -TOP)
    p.go = button(p, "Search", 70, 22, function() A.Search(p.search:GetText() or "", nil) end)
    p.go:SetPoint("LEFT", p.search, "RIGHT", 6, 0)
    p.go:SetPrimary(true)
    p.back = button(p, "< Back to results", 120, 22, function()
        BUY.mode, BUY.item, BUY.buy = "list", nil, nil
        A.Refresh()
    end)
    p.back:SetPoint("LEFT", p.go, "RIGHT", 6, 0)
    p.state = label(p, "GameFontHighlightSmall")
    p.state:SetPoint("TOPRIGHT", -14, -TOP - 5)
    p.state:SetJustifyH("RIGHT")

    local tableH = listH - 30
    p.results = newTable(p, rightW, tableH, {
        { key = "name", title = "Item", icon = true, sort = true },
        { key = "qty", title = "Available", w = 70, right = true, sort = true },
        { key = "price", title = "Lowest", w = 96, right = true, sort = true },
        { key = "usual", title = "Usual", w = 90, right = true, sort = true },
        { key = "vs", title = "Deal", w = 150, sort = true },
        { key = "sells", title = "Sells", w = 120, sort = true },
    })
    p.results:SetPoint("TOPLEFT", x0, -TOP - 30)
    p.results.onClick = function(d) A.OpenItem(d.r) end

    -- One item's listings, with the buy box beside it.
    local listW = rightW - SIDE_W + 0
    p.item = CreateFrame("Frame", nil, p)
    p.item:SetPoint("TOPLEFT", x0, -TOP - 30)
    p.item:SetSize(rightW, tableH)
    p.listings = newTable(p.item, rightW - 236, tableH, {
        { key = "price", title = "Buyout each", w = 84, right = true, sort = true },
        { key = "qty", title = "Qty", w = 40, right = true, sort = true },
        { key = "total", title = "Buyout total", w = 84, right = true },
        { key = "bid", title = "Next bid", w = 74, right = true },
        { key = "left", title = "Time left", w = 58 },
        { key = "seller", title = "Seller", w = 92, sort = true },
        { key = "note", title = "" },
    })
    p.listings:SetPoint("TOPLEFT", 0, 0)
    p.listings.onClick = function(d)
        BUY.sel = d.l
        A.Refresh()
    end
    local box = CreateFrame("Frame", nil, p.item)
    box:SetSize(228, tableH)
    box:SetPoint("TOPRIGHT", 0, 0)
    skin(box, C.panel[1], C.panel[2], C.panel[3], 1, C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 1)
    box.iconEdge = box:CreateTexture(nil, "BORDER")
    box.icon = box:CreateTexture(nil, "ARTWORK")
    box.icon:SetSize(32, 32)
    box.icon:SetPoint("TOPLEFT", 10, -10)
    box.iconEdge:SetPoint("TOPLEFT", box.icon, "TOPLEFT", -1, 1)
    box.iconEdge:SetPoint("BOTTOMRIGHT", box.icon, "BOTTOMRIGHT", 1, -1)
    box.title = label(box, "GameFontHighlight")
    box.title:SetPoint("TOPLEFT", 50, -12)
    box.title:SetWidth(170)
    box.title:SetWordWrap(false)
    box.facts = label(box, "GameFontHighlightSmall")
    box.facts:SetPoint("TOPLEFT", 10, -52)
    box.facts:SetWidth(208)
    box.facts:SetJustifyV("TOP")
    box.facts:SetWordWrap(true)
    box.qtyLabel = label(box, "GameFontHighlightSmall", "How many:")
    box.qtyLabel:SetPoint("BOTTOMLEFT", 10, 104)
    box.qty = newEdit(box, 60, function(text)
        BUY.qty = max(1, floor(tonumber(text) or 1))
        A.Refresh()
    end)
    box.qty:SetPoint("LEFT", box.qtyLabel, "RIGHT", 6, 0)
    box.max = button(box, "Max", 44, 22, function()
        BUY.qty = max(1, available())
        A.Refresh()
    end)
    box.max:SetPoint("LEFT", box.qty, "RIGHT", 4, 0)
    box.cost = label(box, "GameFontHighlightSmall")
    box.cost:SetPoint("BOTTOMLEFT", 10, 76)
    box.cost:SetWidth(208)
    box.cost:SetWordWrap(true)
    box.buy = button(box, "Buy", 208, 28, function() A.Buy() end)
    box.buy:SetPoint("BOTTOMLEFT", 10, 40)
    box.buy:SetPrimary(true)
    box.cancel = button(box, "Cancel", 208, 22, function() A.CancelBuy() end)
    box.cancel:SetPoint("BOTTOMLEFT", 10, 12)
    p.box = box
    return p
end

local function settingButton(parent, which, w)
    local b = button(parent, "", w, 22, function() P.CycleSetting(which) end)
    b.which = which
    return b
end

local function buildSell(f)
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", 0, 0)
    p:SetSize(W, H)
    local tableW = W - 24 - SIDE_W - 8
    local listH = H - TOP - FOOT - 8 - 30
    p.list = newTable(p, tableW, listH, {
        { key = "pick", title = "", w = 24, check = true },
        { key = "name", title = "Item", icon = true, sort = true },
        { key = "have", title = "Have", w = 46, right = true, sort = true },
        { key = "plan", title = "Listings", w = 70, right = true },
        { key = "price", title = "Price each", w = 90, right = true, sort = true },
        { key = "lowest", title = "Lowest now", w = 90, right = true, sort = true },
        { key = "status", title = "Status", w = 104, sort = true },
    })
    p.list:SetPoint("TOPLEFT", 12, -TOP)
    p.list.onCheck = function(d)
        P.SetPicked(d.e.id, not d.e.picked)
    end
    p.list.onClick = function(d, which)
        if which == "RightButton" then
            P.SetPicked(d.e.id, not d.e.picked)
            return
        end
        A.sellSel = d.e
        A.Refresh()
    end

    -- The settings every proposed listing follows.
    local bar = CreateFrame("Frame", nil, p)
    bar:SetSize(tableW, 24)
    bar:SetPoint("TOPLEFT", p.list, "BOTTOMLEFT", 0, -6)
    local x = 0
    p.settings = {}
    for _, s in ipairs({ { "undercut", "Undercut", 118 }, { "qty", "Per listing", 150 }, { "cap", "Listings", 128 },
        { "duration", "Lasts", 112 } }) do
        local b = settingButton(bar, s[1], s[3])
        b:SetPoint("LEFT", x, 0)
        b.caption = s[2]
        p.settings[#p.settings + 1] = b
        x = x + s[3] + 4
    end

    local side = newSide(p)
    p.side = side
    side.body:SetHeight(side:GetHeight() - 52 - 180)
    side.priceLabel = label(side, "GameFontHighlightSmall", "Price each:")
    side.priceLabel:SetPoint("BOTTOMLEFT", 10, 150)
    side.price = newEdit(side, 120, function(text)
        local e = A.SellShown()
        if e then
            P.SetPrice(e, ns.ParseMoney(text))
        end
    end)
    side.price:SetPoint("LEFT", side.priceLabel, "RIGHT", 6, 0)
    side.reset = button(side, "Auto", 50, 22, function()
        local e = A.SellShown()
        if e then
            P.SetPrice(e, nil)
        end
    end)
    side.reset:SetPoint("LEFT", side.price, "RIGHT", 4, 0)
    side.perLabel = label(side, "GameFontHighlightSmall", "Per listing:")
    side.perLabel:SetPoint("BOTTOMLEFT", 10, 122)
    side.minus = button(side, "-", 24, 22, function()
        local e = A.SellShown()
        if e then
            P.SetPer(e, (e.per or 1) - (e.commodity and 5 or 1))
        end
    end)
    side.minus:SetPoint("LEFT", side.perLabel, "RIGHT", 6, 0)
    side.per = label(side, "GameFontNormal")
    side.per:SetPoint("LEFT", side.minus, "RIGHT", 4, 0)
    side.per:SetWidth(40)
    side.per:SetJustifyH("CENTER")
    side.plus = button(side, "+", 24, 22, function()
        local e = A.SellShown()
        if e then
            P.SetPer(e, (e.per or 1) + (e.commodity and 5 or 1))
        end
    end)
    side.plus:SetPoint("LEFT", side.per, "RIGHT", 4, 0)
    side.totals = label(side, "GameFontHighlightSmall")
    side.totals:SetPoint("BOTTOMLEFT", 10, 76)
    side.totals:SetWidth(SIDE_W - 20)
    side.totals:SetWordWrap(true)
    side.post = button(side, "Post", SIDE_W - 20 - 70, 30, function()
        if P.state == "ready" or P.state == "confirm" then
            P.PostNext(A.SellShown())
        elseif P.state ~= "checking" and P.state ~= "posting" and P.state ~= "verify" then
            P.CheckAll(P.state == "done")
        end
    end)
    side.post:SetPoint("BOTTOMLEFT", 10, 38)
    side.post:SetPrimary(true)
    side.skip = button(side, "Skip", 64, 30, function()
        if P.state == "checking" then
            P.StopChecking()
            return
        end
        local e = A.SellShown()
        if e and e.status == "skipped" then
            P.Unskip(e)
        else
            P.Skip(e)
        end
        A.sellSel = nil
    end)
    side.skip:SetPoint("LEFT", side.post, "RIGHT", 6, 0)
    side.check = button(side, "Price check everything again", SIDE_W - 20, 22, function() P.CheckAll(true) end)
    side.check:SetPoint("BOTTOMLEFT", 10, 10)
    return p
end

local function buildMine(f)
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", 0, 0)
    p:SetSize(W, H)
    local tableW = W - 24 - SIDE_W - 8
    p.list = newTable(p, tableW, H - TOP - FOOT - 8, {
        { key = "name", title = "Item", icon = true, sort = true },
        { key = "qty", title = "Qty", w = 46, right = true, sort = true },
        { key = "each", title = "Price each", w = 92, right = true, sort = true },
        { key = "lowest", title = "Lowest other", w = 92, right = true, sort = true },
        { key = "left", title = "Time left", w = 74, sort = true },
        { key = "status", title = "Status", w = 104, sort = true },
    })
    p.list:SetPoint("TOPLEFT", 12, -TOP)
    p.list.onClick = function(d)
        A.mineSel = d.a
        A.Refresh()
    end
    local side = newSide(p)
    p.side = side
    side.body:SetHeight(side:GetHeight() - 52 - 116)
    side.cancelNext = button(side, "Cancel next undercut", SIDE_W - 20, 30, function() P.CancelNextUndercut() end)
    side.cancelNext:SetPoint("BOTTOMLEFT", 10, 76)
    side.cancelOne = button(side, "Cancel this auction", SIDE_W - 20, 24, function() P.Cancel(A.mineSel) end)
    side.cancelOne:SetPoint("BOTTOMLEFT", 10, 44)
    side.check = button(side, "Check prices now", SIDE_W - 20, 24, function() P.CheckOwned() end)
    side.check:SetPoint("BOTTOMLEFT", 10, 12)
    return p
end

local function createWindow()
    local f = CreateFrame("Frame", "ForeverGoldAuctionFrame", UIParent)
    f:SetSize(W, H)
    local pos = ns.db.opts.ahPos
    if type(pos) == "table" and pos.x and pos.y then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -104)
    end
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, top = self:GetLeft(), self:GetTop()
        if left and top then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            ns.db.opts.ahPos = { x = floor(left + 0.5), y = floor(top + 0.5) }
        end
    end)
    skin(f)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(30, 30)
    icon:SetPoint("TOPLEFT", 10, -5)
    icon:SetTexture(K.LOGO)
    local title = label(f, K.SERIF_L, "Auction House")
    title:SetTextColor(C.goldText[1], C.goldText[2], C.goldText[3])
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    f.money = label(f, "GameFontHighlight")
    f.money:SetPoint("LEFT", title, "RIGHT", 18, 0)

    local close = button(f, "X", 24, 22, function() A.Close() end)
    close:SetPoint("TOPRIGHT", -8, -8)
    f.blizz = headerButton(f, "Game's window", 104, function() A.UseBlizzard() end,
        "Switch to the game's own auction window. A button above it switches back.")
    f.blizz:SetPoint("RIGHT", close, "LEFT", -6, 0)
    f.advice = headerButton(f, "Advice", 64, function() ns.ToggleUI() end, "Open the main Forever Gold window.")
    f.advice:SetPoint("RIGHT", f.blizz, "LEFT", -6, 0)
    f.scan = headerButton(f, "Scan prices", 92, function() ns.StartScan() end,
        "Read every price on the auction house, for the deals, the advice and your price history.")
    f.scan:SetPoint("RIGHT", f.advice, "LEFT", -6, 0)

    local rule = tex(f, "BORDER", C.edge[1], C.edge[2], C.edge[3], 0.7)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 12, -70)
    rule:SetPoint("TOPRIGHT", -12, -70)
    local x = 12
    for _, t in ipairs({ { "browse", "Browse" }, { "sell", "Sell" }, { "auctions", "Auctions" } }) do
        local key = t[1]
        local b = button(f, t[2], 100, 24, function() setTab(key) end)
        b:SetPoint("TOPLEFT", x, -42)
        tabs[key] = b
        x = x + 104
    end

    f.footRule = tex(f, "BORDER", C.edge[1], C.edge[2], C.edge[3], 0.5)
    f.footRule:SetHeight(1)
    f.footRule:SetPoint("BOTTOMLEFT", 12, FOOT)
    f.footRule:SetPoint("BOTTOMRIGHT", -12, FOOT)
    f.status = label(f, "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", 14, 11)
    f.status:SetWidth(W / 2 - 20)
    f.status:SetWordWrap(false)
    f.message = label(f, "GameFontHighlightSmall")
    f.message:SetPoint("BOTTOMRIGHT", -14, 11)
    f.message:SetWidth(W / 2 - 20)
    f.message:SetJustifyH("RIGHT")
    f.message:SetWordWrap(false)

    f.browse = buildBrowse(f)
    f.sell = buildSell(f)
    f.mine = buildMine(f)
    f:Hide()
    return f
end

----------------------------------------------------------------------
-- Filling it in
----------------------------------------------------------------------

-- Is a search result's lowest price a real buyout? For gear it can be just a
-- bid. Stackable goods have no bids; gear counts only if the last price scan
-- found a buyout at this same price.
local function verifiedBuyout(r, info)
    if not r.price then
        return false
    end
    if info and info.isCommodity then
        return true
    end
    if not ns.IsBuyout(r.id) then
        return false
    end
    if info and info.isCommodity == false then
        local rec = ns.R().prices[r.id]
        return (rec and rec.p and math.abs(rec.p - r.price) < 1) and true or false
    end
    return true
end
A.VerifiedBuyout = verifiedBuyout

local function refreshBrowse()
    local p = win.browse
    local cats = {}
    for i, c in ipairs(categoryList()) do
        c.key = "cat" .. i
        c.cells = { name = c.name }
        if (c.deals and BUY.category == "deals") or (type(BUY.category) == "table" and BUY.category.top == c.top
            and BUY.category.sub == c.sub) then
            p.cats.selected = c.key
        end
        cats[i] = c
    end
    p.cats:SetData(cats, true)

    local inItem = BUY.mode == "item" and BUY.item
    p.results:SetShown(not inItem)
    p.item:SetShown(inItem and true or false)
    p.back:SetShown(inItem and true or false)
    if BUY.searching then
        p.state:SetText("Searching... " .. #BUY.results .. " found")
    elseif inItem then
        p.state:SetText("")
    else
        p.state:SetText(#BUY.results > 0 and plural(#BUY.results, "result") or "")
    end

    if not inItem then
        p.results:SetEmpty(BUY.searching and "Searching..."
            or (BUY.query ~= "" or BUY.category) and "Nothing found."
            or "Search by name, pick a category, or try Deals for the bargains from your last scan.")
        if not BUY.dirty then
            p.results:Render()
            return
        end
        BUY.dirty = false
        local rows = {}
        for i, r in ipairs(BUY.results) do
            local info = r.key and keyInfo(r.key)
            local name = (info and info.itemName) or ns.ItemName(r.id)
            local usual = usualText(r.id)
            local vs, pct = versus(r.price, usual)
            local vendor = ns.VendorSell(r.id)
            local hint
            local odd = r.price and ns.Suspicious(r.id, r.price)
            local doubt = not odd and ns.PriceDoubt(r.id)
            if odd then
                vs = SUSPICIOUS
                hint = odd
            elseif vendor and r.price and vendor > r.price and verifiedBuyout(r, info) then
                vs = "|cff40e060Vendor pays " .. ns.StripCodes(ns.Money(vendor)) .. "|r"
                hint = "A vendor pays " .. ns.StripCodes(ns.Money(vendor)) .. " each, more than the "
                    .. ns.StripCodes(ns.Money(r.price)) .. " buyout. Buy it and sell it to any vendor."
            elseif vendor and r.price and vendor > r.price then
                -- The lowest price in a search can be a bid, not a buyout.
                vs = GREY .. "Maybe - check buyouts|r"
                hint = "The " .. ns.StripCodes(ns.Money(r.price)) .. " here may only be a bid, which you get only if"
                    .. " nobody outbids you. A vendor pays " .. ns.StripCodes(ns.Money(vendor))
                    .. " each. Click to see the real buyout prices."
            elseif doubt and pct then
                -- Its usual price is junk: no "under usual" from that.
                vs = SUSPICIOUS_HISTORY
                hint = doubt
            elseif r.why then
                vs = r.why
            elseif pct then
                vs = vs .. GREY .. (pct < 0 and " under usual" or (pct > 0 and " over usual" or " = usual")) .. "|r"
            end
            if not hint and usual and r.price and pct then
                hint = "Usually sells for " .. ns.StripCodes(ns.Money(usual)) .. ". This is "
                    .. (pct < 0 and (-pct .. "% cheaper.") or pct > 0 and (pct .. "% dearer.") or "the usual price.")
            end
            local sells = ns.SaleText and ns.SaleText(r.id, true) or ""
            rows[i] = {
                key = "r" .. i, id = r.id, icon = info and info.iconFileID, r = r,
                cells = { name = name .. (r.mine and (GREY .. "  (yours)|r") or ""),
                    qty = r.qty and r.qty > 0 and ns.Commas(r.qty) or "-",
                    price = r.price and ns.Money(r.price) or "-",
                    usual = usual and ns.Money(usual) or GREY .. "-|r",
                    vs = vs, sells = sells or "" },
                sv = { name = name, qty = r.qty or 0, price = r.price or 0, usual = usual or 0,
                    vs = pct or (r.profit and -1000 - r.profit) or 0, sells = ns.SpeedWeight and ns.SpeedWeight(r.id) or 0 },
                hint = (hint and (hint .. "\n") or "") .. "Click to see every listing and buy.",
            }
        end
        p.results:SetData(rows, true)
        return
    end

    local item = BUY.item
    local id = item.id
    local rows = {}
    local vendor = ns.VendorSell(id)
    local usual = usualText(id)
    -- A usual price built from nonsense listings isn't compared with.
    local doubt = ns.PriceDoubt(id)
    if doubt then
        usual = nil
    end
    local oddCount = 0
    local function money(c)
        return ns.StripCodes(ns.Money(floor(c + 0.5)))
    end
    for i, l in ipairs(BUY.listings or {}) do
        local note = ""
        -- Gear is bought a whole auction at a time, so the deal is the whole
        -- stack: what you pay against what a vendor pays for all of it.
        local total = item.commodity and (l.p * l.q) or (l.buyout or l.p * l.q)
        local hint
        local odd = ns.Suspicious(id, l.p)
        if odd then
            oddCount = oddCount + 1
            note = SUSPICIOUS
            hint = odd
        elseif l.mine and (l.own or 0) >= l.q then
            note = GREY .. "Yours|r"
        elseif vendor and vendor > l.p then
            if item.commodity or l.q == 1 then
                note = "|cff40e060Vendor pays " .. money(vendor) .. (l.q > 1 and " each" or "") .. "|r"
            else
                note = "|cff40e060Vendor " .. money(vendor * l.q) .. " (+" .. money(vendor * l.q - total) .. ")|r"
            end
            hint = "A vendor pays " .. money(vendor) .. " each" .. (l.q > 1 and (", " .. money(vendor * l.q) .. " for "
                .. l.q) or "") .. ". " .. (item.commodity and "Buying these" or "This buyout") .. " costs "
                .. money(total) .. (l.q > 1 and (" for " .. l.q) or "") .. "."
        elseif usual then
            note = (versus(l.p, usual))
        end
        if not item.commodity then
            local whole = l.q > 1 and ("Buyout " .. money(total) .. " for all " .. l.q .. " (" .. money(l.p)
                .. " each). The game sells it as one auction.") or ("Buyout " .. money(total) .. ".")
            hint = (hint and (hint .. "\n") or "") .. whole
            if l.bid then
                hint = hint .. "\nOr bid " .. money(l.bid) .. ", but you only get it if nobody outbids you before it ends."
            end
        end
        hint = (hint and (hint .. "\n") or "") .. sellerHint(l)
        rows[#rows + 1] = {
            key = "l" .. i, l = l, link = l.link, hint = hint,
            cells = { price = ns.Money(l.p), qty = ns.Commas(l.q), total = ns.Money(total),
                bid = l.bid and (GREY .. money(l.bid) .. "|r") or "",
                left = item.commodity and "" or timeLeftText(l.left, l.band), seller = sellerCell(l), note = note },
            sv = { price = l.p, qty = l.q, seller = (soleOwner(l) or "~"):lower() .. string.format("%016.2f", l.p) },
            dim = l.mine and (l.own or 0) >= l.q,
        }
        if BUY.sel == l then
            p.listings.selected = rows[#rows].key
        end
    end
    -- Bid-only auctions last, apart: no buyout, so never a deal.
    for i, l in ipairs(BUY.listings and BUY.listings.bids or {}) do
        local odd = l.bid and ns.Suspicious(id, l.bid / max(1, l.q))
        if odd then
            oddCount = oddCount + 1
        end
        rows[#rows + 1] = {
            key = "b" .. i, l = l, link = l.link, dim = true,
            hint = (odd and (odd .. "\n") or "") .. "No buyout: you can only bid" .. (l.bid and (" (next bid " .. money(l.bid) .. " for "
                .. (l.q > 1 and ("all " .. l.q) or "it") .. ")") or "") .. ". You only get it if nobody outbids"
                .. " you before it ends, so it's never counted as a deal.\n" .. sellerHint(l),
            cells = { price = GREY .. "Bid only|r", qty = ns.Commas(l.q), total = GREY .. "-|r",
                bid = l.bid and money(l.bid) or "-", left = timeLeftText(l.left, l.band), seller = sellerCell(l),
                note = odd and SUSPICIOUS or (GREY .. (l.mine and "Yours" or "Only if you win") .. "|r") },
            sv = { price = 1e12, qty = l.q, seller = (soleOwner(l) or "~"):lower() .. "~" },
        }
        if BUY.sel == l then
            p.listings.selected = rows[#rows].key
        end
    end
    if not BUY.sel then
        p.listings.selected = nil
    end
    p.listings:SetEmpty(BUY.listings and "Nobody is selling this right now." or "Looking it up...")
    p.listings:SetData(rows, true)

    local box = p.box
    setIcon(box.icon, ns.Icon(id))
    edgeFor(box.iconEdge, id)
    box.title:SetText(ns.ItemName(id))
    local facts = {}
    if oddCount > 0 then
        facts[#facts + 1] = "|cffff7070" .. plural(oddCount, "suspicious listing") .. ":|r priced like gold changing"
            .. " hands, not a real sale. Don't buy " .. (oddCount == 1 and "it" or "them") .. "."
    end
    if doubt then
        facts[#facts + 1] = "|cffff9a5aSuspicious price history.|r " .. doubt
    elseif usual then
        facts[#facts + 1] = "Usual price: " .. ns.Money(usual)
    end
    if vendor and vendor > 0 then
        facts[#facts + 1] = "A vendor pays: " .. ns.Money(vendor)
    end
    local rec = ns.RecipeFor(id)
    local e = rec and ns.EvalRecipe(rec)
    if e and e.cost then
        facts[#facts + 1] = "Costs you to make: " .. ns.Money(e.cost)
    end
    local sale = ns.SaleText and ns.SaleText(id)
    if sale then
        facts[#facts + 1] = "Sells: " .. sale
    end
    -- Who's selling: the most listed, the cheapest, and what moved.
    local tally, order, cheapest = {}, {}, nil
    local newOnes, cuts = {}, {}
    for _, l in ipairs(BUY.listings or {}) do
        local o = soleOwner(l)
        if not cheapest and not l.mine and (l.sellers or 1) > 1 then
            cheapest = { name = l.sellers .. " sellers", p = l.p }
        end
        if o then
            local name = o == "You" and "You" or shortName(o)
            local t = tally[name]
            if not t then
                t = { name = name, q = 0, n = 0 }
                tally[name] = t
                order[#order + 1] = t
            end
            t.q, t.n = t.q + l.q, t.n + 1
            if not cheapest and not l.mine then
                cheapest = { name = name, p = l.p }
            end
            if l.move == "new" and not newOnes[name] then
                newOnes[name] = true
                newOnes[#newOnes + 1] = name
            elseif l.move == "cut" and not cuts[name] then
                cuts[name] = true
                cuts[#cuts + 1] = name
            end
        end
    end
    table.sort(order, function(a, b)
        if a.q ~= b.q then return a.q > b.q end
        return a.name < b.name
    end)
    if #order > 0 then
        local parts = {}
        for k = 1, min(3, #order) do
            local t = order[k]
            parts[k] = t.name .. " " .. ns.Commas(t.q) .. (t.n > 1 and (GREY .. " (" .. t.n .. " auctions)|r") or "")
        end
        facts[#facts + 1] = "Most listed: " .. table.concat(parts, ", ")
    end
    if cheapest then
        facts[#facts + 1] = "Cheapest: " .. cheapest.name .. " at " .. ns.Money(cheapest.p) .. (item.commodity and " each" or "")
    end
    if #cuts > 0 then
        facts[#facts + 1] = "|cffff7070Cut their price|r since you last looked: " .. table.concat(cuts, ", ")
    end
    if #newOnes > 0 then
        facts[#facts + 1] = "|cffffd100New sellers|r since you last looked: " .. table.concat(newOnes, ", ")
    end
    if BUY.listings and BUY.listings.bidOnly and BUY.listings.bidOnly > 0 then
        facts[#facts + 1] = GREY .. plural(BUY.listings.bidOnly, "bid-only auction") .. " at the bottom of the list."
            .. " They have no buyout, so they only count if you win the bid.|r"
    end
    box.facts:SetText(table.concat(facts, "\n"))

    local b = BUY.buy
    box.cancel:SetShown(b ~= nil and b.state ~= "buying")
    box.qtyLabel:SetShown(item.commodity)
    box.qty:SetShown(item.commodity)
    box.max:SetShown(item.commodity)
    if item.commodity then
        local have = available()
        BUY.qty = max(1, min(BUY.qty or 1, max(1, have)))
        if not box.qty:HasFocus() then
            box.qty:SetText(tostring(BUY.qty))
        end
        local total, enough = commodityCost(BUY.qty)
        if b and b.state == "quoted" then
            box.cost:SetText("Price confirmed: " .. ns.Money(b.total or 0) .. " for " .. b.qty
                .. GREY .. " (" .. ns.StripCodes(ns.Money(floor((b.total or 0) / max(1, b.qty)))) .. " each)|r")
            box.buy:SetLabel("Confirm: pay " .. ns.StripCodes(ns.Money(b.total or 0)))
            box.buy:SetDisabled(false)
        elseif b then
            box.cost:SetText(b.state == "buying" and "Buying..." or "Asking the auction house for the final price...")
            box.buy:SetLabel(b.state == "buying" and "Buying..." or "Checking price...")
            box.buy:SetDisabled(true)
        else
            box.cost:SetText(have == 0 and "None for sale from anyone else."
                or ("About " .. ns.Money(total) .. GREY .. " for " .. BUY.qty .. (enough and "" or " (not that many listed)") .. "|r"))
            box.buy:SetLabel("Buy " .. BUY.qty)
            box.buy:SetDisabled(have == 0 or GetMoney() < total)
        end
    else
        local l = BUY.sel
        if b then
            box.cost:SetText("Buying...")
            box.buy:SetLabel("Buying...")
            box.buy:SetDisabled(true)
        elseif l and l.bidOnly then
            box.cost:SetText(GREY .. "Bid only" .. (l.bid and (": next bid " .. ns.StripCodes(ns.Money(l.bid))) or "")
                .. ". This window only buys outright; bid from the game's own Buy tab.|r")
            box.buy:SetLabel("Buy")
            box.buy:SetDisabled(true)
        elseif l and l.aid and not l.mine then
            local odd = ns.Suspicious(item.id, l.p)
            box.cost:SetText((odd and ("|cffff7070Suspicious price - almost certainly gold changing hands, not a real"
                .. " sale.|r\n") or "") .. l.q .. " for " .. ns.Money(l.buyout or 0))
            box.buy:SetLabel((odd and "Buy anyway: " or "Buy now: ") .. ns.StripCodes(ns.Money(l.buyout or 0)))
            box.buy:SetDisabled(GetMoney() < (l.buyout or 0))
        else
            box.cost:SetText(GREY .. "Click a listing to buy it.|r")
            box.buy:SetLabel("Buy")
            box.buy:SetDisabled(true)
        end
    end
end

-- The Sell tab's right panel shows the row you picked, or else the next
-- listing in the queue.
function A.SellShown()
    local e = A.sellSel
    if e then
        for _, x in ipairs(P.entries) do
            if x == e then
                return e
            end
        end
        A.sellSel = nil
    end
    return P.NextEntry() or P.entries[1]
end

local function refreshSell()
    local p = win.sell
    local rows = {}
    local shown = A.SellShown()
    for i, e in ipairs(P.entries) do
        local st = P.STATUS[e.status] or P.STATUS.new
        local name = ns.ItemName(e.id)
        rows[i] = {
            key = "e" .. e.id, id = e.id, e = e, checked = e.picked,
            cells = { name = name .. (e.recommended and "" or (GREY .. "  (not suggested)|r")),
                have = tostring(e.have or 0),
                plan = e.picked and e.decision and P.PlanText(e) or "",
                price = e.price and e.picked and ns.Money(e.price) or "",
                lowest = e.lowest and ns.Money(e.lowest) or (e.listings and GREY .. "none|r" or ""),
                status = e.picked and (st[2] .. st[1] .. "|r") or (GREY .. "Not posting|r") },
            sv = { name = name, have = e.have or 0, price = e.price or 0, lowest = e.lowest or 0, status = st[1] },
            dim = not e.picked or e.status == "done" or e.status == "skipped",
            hint = "Tick to include it. Click to see its listing on the right.",
        }
    end
    p.list.selected = shown and ("e" .. shown.id) or nil
    p.list:SetEmpty("Nothing in your bags can go on the auction house.")
    p.list:SetData(rows, true)

    for _, b in ipairs(p.settings) do
        local _, text = P.Setting(b.which)
        b:SetLabel(b.caption .. ": " .. text)
    end

    local side = p.side
    local e = shown
    if e then
        local ready = P.Postable(e)
        local sub
        if e.decision and e.price then
            local qty = max(1, min(e.per or 1, e.have or 1))
            sub = qty .. " x at " .. ns.Money(e.price) .. " each"
        else
            sub = GREY .. "You have " .. (e.have or 0) .. "|r"
        end
        side:SetItem(e.id, ns.ItemName(e.id), sub)
        local lines = P.Explain(e)
        if e.posts and e.posts > 0 and e.decision then
            lines[#lines + 1] = GREY .. "Listing " .. min(e.posts, (e.posted or 0) + 1) .. " of " .. e.posts
                .. (e.posted and e.posted > 0 and (" (" .. e.posted .. " posted)") or "") .. "|r"
        end
        if not e.picked then
            lines[#lines + 1] = GREY .. "Not ticked, so it won't be posted. Tick it on the left to include it.|r"
        end
        side.body:SetText(table.concat(lines, "\n\n"))
        if not side.price:HasFocus() then
            side.price:SetText(e.price and ns.StripCodes(ns.Money(e.price)) or "")
        end
        side.per:SetText(tostring(e.per or "-"))
        local get, deposit, qty = P.Totals(e)
        if get and e.decision then
            side.totals:SetText("This listing: " .. ns.Money(get) .. GREY .. " after the 5% cut if it sells.|r"
                .. (deposit and ("\n" .. GREY .. "Deposit " .. ns.StripCodes(ns.Money(deposit)) .. ", lost if it doesn't sell.|r") or ""))
        else
            side.totals:SetText("")
        end
        local editable = e.decision ~= nil and e.status ~= "done"
        side.price:SetShown(editable)
        side.priceLabel:SetShown(editable)
        side.reset:SetShown(editable and e.priceSet and true or false)
        side.minus:SetShown(editable)
        side.plus:SetShown(editable)
        side.per:SetShown(editable)
        side.perLabel:SetShown(editable)
        side.skip:SetLabel(e.status == "skipped" and "Unskip" or "Skip")
        side.skip:SetDisabled(not (ready or e.status == "skipped" or P.state == "checking"))
    else
        side:SetItem(nil, "Nothing to post", "")
        side.body:SetText("Items you can auction show up here when they're in your bags.")
        for _, w in ipairs({ side.price, side.priceLabel, side.reset, side.minus, side.plus, side.per, side.perLabel }) do
            w:Hide()
        end
        side.totals:SetText("")
        side.skip:SetDisabled(true)
    end

    local picked = 0
    for _, x in ipairs(P.entries) do
        if x.picked then
            picked = picked + 1
        end
    end
    local post = side.post
    if P.state == "checking" then
        local c = P.checking
        post:SetLabel(c and ("Checking " .. min(c.total, c.done + 1) .. " of " .. c.total .. "...") or "Checking...")
        post:SetDisabled(true)
        side.skip:SetLabel("Stop")
        side.skip:SetDisabled(false)
    elseif P.state == "posting" then
        post:SetLabel("Posting...")
        post:SetDisabled(true)
    elseif P.state == "verify" then
        post:SetLabel("Checking it went up...")
        post:SetDisabled(true)
    elseif (P.state == "confirm" or (P.state == "ready" and P.NextEntry())) and ns.AHWaiting() then
        -- The auction house said busy / too fast: wait it out, don't click into another refusal.
        post:SetLabel("Busy - wait a moment...")
        post:SetDisabled(true)
    elseif P.state == "confirm" then
        post:SetLabel("Confirm post")
        post:SetDisabled(false)
    elseif P.state == "ready" and P.NextEntry() then
        local n = P.Postable(e) and e or P.NextEntry()
        local qty = max(1, min(n.per or 1, n.have or 1))
        post:SetLabel("Post " .. qty .. " x " .. ns.ItemName(n.id))
        post:SetDisabled(false)
    elseif P.state == "done" then
        post:SetLabel("All posted - check again")
        post:SetDisabled(picked == 0)
    else
        post:SetLabel(picked > 0 and ("Price check " .. plural(picked, "item")) or "Tick something to sell")
        post:SetDisabled(picked == 0)
    end
    post:SetPrimary(true)
    side.check:SetDisabled(P.state == "checking" or P.state == "posting" or P.state == "confirm"
        or P.state == "verify" or picked == 0)

    local ready, listings, worth = P.Summary()
    if P.state == "checking" or P.state == "ready" or P.state == "done" then
        win.statusExtra = listings > 0 and (plural(listings, "listing") .. " ready, about " .. ns.StripCodes(ns.Money(worth))
            .. " after the cut") or (P.postedCount and (plural(P.postedCount, "listing") .. " posted this visit") or nil)
    else
        win.statusExtra = nil
    end
end

local function refreshMine()
    local p = win.mine
    local rows = {}
    local undercut, sold, active = 0, 0, 0
    for i, a in ipairs(P.owned) do
        local st = P.OWNED_STATUS[a.state or "unknown"] or P.OWNED_STATUS.unknown
        local name = ns.ItemName(a.id)
        if a.state == "undercut" then
            undercut = undercut + 1
        end
        if a.sold then
            sold = sold + 1
        else
            active = active + 1
        end
        local lowest = ""
        if a.lowest == false then
            lowest = GREY .. "nobody|r"
        elseif a.lowest then
            lowest = ns.Money(a.lowest) .. (a.fromScan and (GREY .. "*|r") or "")
        end
        rows[i] = {
            key = "a" .. (a.auctionID or i), id = a.id, link = a.link, a = a,
            cells = { name = name, qty = tostring(a.qty), each = a.each and ns.Money(a.each) or GREY .. "bid|r",
                lowest = lowest, left = a.sold and "" or timeLeftText(a.left, a.band), status = st[2] .. st[1] .. "|r" },
            sv = { name = name, qty = a.qty, each = a.each or 0, lowest = a.lowest or 0, left = a.left or 0, status = st[1] },
            dim = a.sold,
        }
        if A.mineSel == a then
            p.list.selected = rows[i].key
        end
    end
    if A.mineSel then
        local still = false
        for _, a in ipairs(P.owned) do
            still = still or a == A.mineSel
        end
        if not still then
            A.mineSel = nil
            p.list.selected = nil
        end
    end
    p.list:SetEmpty("You have no auctions up.")
    p.list:SetData(rows, true)

    local side = p.side
    local a = A.mineSel
    local lines = {}
    if a then
        side:SetItem(a.id, ns.ItemName(a.id), a.qty .. " x " .. (a.each and (ns.Money(a.each) .. " each") or "bid only"))
        local st = P.OWNED_STATUS[a.state or "unknown"]
        lines[#lines + 1] = st[2] .. st[1] .. "|r"
        if a.state == "undercut" then
            lines[#lines + 1] = "Someone else is selling it for " .. ns.Money(a.lowest) .. ". Cancel it and post it again from the Sell tab once it's back from the mail."
        end
        local cost = P.CancelCost(a)
        if cost and cost > 0 and not a.sold then
            lines[#lines + 1] = GREY .. "Cancelling costs " .. ns.StripCodes(ns.Money(cost)) .. " (your deposit isn't returned).|r"
        end
    else
        side:SetItem(nil, "Your auctions", plural(active, "active") .. (sold > 0 and (", " .. sold .. " sold") or ""))
        lines[#lines + 1] = undercut > 0 and ("|cffff6060" .. plural(undercut, "auction") .. " undercut.|r Cancel them one at a time with the button below, then post them again from the Sell tab.")
            or "Nothing undercut that I know of."
        lines[#lines + 1] = GREY .. "Prices marked * are from your last scan. Check prices now for live ones.|r"
    end
    side.body:SetText(table.concat(lines, "\n\n"))
    side.cancelNext:SetLabel(undercut > 0 and ("Cancel next undercut (" .. undercut .. ")") or "Nothing undercut")
    side.cancelNext:SetDisabled(undercut == 0 or P.cancelling ~= nil)
    side.cancelNext:SetPrimary(undercut > 0)
    side.cancelOne:SetDisabled(not a or a.sold or P.cancelling ~= nil)
    if P.ownedState == "checking" and P.ownedChecking then
        side.check:SetLabel("Checking " .. P.ownedChecking.done .. " of " .. P.ownedChecking.total .. "...")
        side.check:SetDisabled(true)
    else
        side.check:SetLabel("Check prices now")
        side.check:SetDisabled(active == 0)
    end
end

-- Just the header and footer: your gold and the scan's progress.
local function refreshHead()
    win.money:SetText(ns.Money(GetMoney() or 0))
    local scanText, scanning = ns.ScanStatus()
    win.scan:SetDisabled(scanning)
    win.scan:SetLabel(scanning and "Scanning..." or "Scan prices")
    return scanText
end

function A.RefreshHead()
    if not win or not win:IsShown() then
        return
    end
    local scanText = refreshHead()
    if A.tab ~= "sell" then
        win.status:SetText(scanText or "")
    end
end

function A.Refresh()
    if not win or not win:IsShown() then
        return
    end
    local scanText = refreshHead()
    if A.tab == "browse" then
        refreshBrowse()
    elseif A.tab == "sell" then
        refreshSell()
    else
        refreshMine()
    end
    win.status:SetText(A.tab == "sell" and win.statusExtra or scanText or "")
    local msg = (A.tab == "browse" and BUY.message) or P.message or ""
    win.message:SetText(msg)
end

----------------------------------------------------------------------
-- Taking over from the game's window
----------------------------------------------------------------------

local blizzScale

local function hideBlizzard()
    local f = AuctionHouseFrame
    if not f then
        return
    end
    if not blizzScale then
        blizzScale = f:GetScale() or 1
    end
    f:SetScale(0.001)
    f:SetAlpha(0)
    f:EnableMouse(false)
end

local function restoreBlizzard()
    local f = AuctionHouseFrame
    if not f or not blizzScale then
        return
    end
    f:SetScale(blizzScale)
    f:SetAlpha(1)
    f:EnableMouse(true)
    blizzScale = nil
end

function A.UsingOurs()
    return not ns.db.opts.ahBlizzard
end

function A.IsShown()
    return win ~= nil and win:IsShown()
end

local hooked = false
local function hookBlizzard()
    if hooked or not AuctionHouseFrame then
        return
    end
    hooked = true
    AuctionHouseFrame:HookScript("OnShow", function()
        if A.UsingOurs() then
            hideBlizzard()
        end
    end)
end

function A.Open()
    if not ns.ahOpen then
        return
    end
    hookBlizzard()
    hideBlizzard()
    if ns.HideAuctionStrip then
        ns.HideAuctionStrip()
    end
    if not win then
        win = createWindow()
    end
    win:Show()
    setTab(A.tab or "browse")
end

function A.Close()
    if C_AuctionHouse and C_AuctionHouse.CloseAuctionHouse then
        pcall(C_AuctionHouse.CloseAuctionHouse)
    end
    if win then
        win:Hide()
    end
end

function A.UseBlizzard()
    ns.db.opts.ahBlizzard = true
    if win then
        win:Hide()
    end
    restoreBlizzard()
    if ns.ShowAuctionStrip then
        ns.ShowAuctionStrip()
    end
end

function A.UseOurs()
    ns.db.opts.ahBlizzard = nil
    A.Open()
end

ns.Listen("AH_SHOW", function()
    BUY.mode, BUY.item, BUY.buy, BUY.message = "list", nil, nil, nil
    if A.UsingOurs() then
        A.Open()
        -- The game shows its own window a moment later; hide it again then.
        C_Timer.After(0, ns.Guard("auction-hide", hideBlizzard))
    end
end)

ns.Listen("AH_CLOSED", function()
    BUY.searching, BUY.buy = false, nil
    if win then
        win:Hide()
    end
    restoreBlizzard()
end)

ns.Listen("POSTER", function()
    ns.Later("auction-ui", 0.05, function() A.Refresh() end)
end)

-- New prices or item names: the Browse rows need building again.
for _, msg in ipairs({ "SCAN_DONE", "PRICES_UPDATED", "ITEMS_UPDATED" }) do
    ns.Listen(msg, function()
        BUY.dirty = true
        if A.IsShown() then
            ns.Later("auction-ui", 0.2, function() A.Refresh() end)
        end
    end)
end

ns.Listen("BAGS_UPDATED", function()
    if A.IsShown() and A.tab == "sell" then
        if P.state ~= "checking" and P.state ~= "posting" and P.state ~= "confirm" and P.state ~= "verify" then
            P.Rebuild()
        end
        ns.Later("auction-ui", 0.2, function() A.Refresh() end)
    end
end)

-- These only change the header (the scan's progress, your gold).
ns.Listen("SCAN_PROGRESS", function()
    ns.Later("auction-ui-head", 0.25, function() A.RefreshHead() end)
end)

ns.On("PLAYER_MONEY", function()
    if A.IsShown() then
        ns.Later("auction-ui-head", 0.2, function() A.RefreshHead() end)
    end
end)

-- The rest of the addon's "search the auction house for this" and "post
-- all" go to this window when it's the one in use.
local searchBlizzard = ns.SearchAH
function ns.SearchAH(name)
    if A.IsShown() then
        if not name then
            return
        end
        setTab("browse")
        win.browse.search:SetText(name)
        A.Search(name, nil)
        return
    end
    return searchBlizzard(name)
end

-- The main window's Sell button on a bag row: pick that item on our Sell
-- tab and price-check it, instead of the older one-item seller (whose
-- searches would collide with this window's).
local openSellOld = ns.OpenSell
function ns.OpenSell(id, quiet)
    if not A.IsShown() then
        return openSellOld(id, quiet)
    end
    setTab("sell")
    local e
    for _, x in ipairs(P.entries) do
        if x.id == id then
            e = x
        end
    end
    if not e then
        if not quiet then
            ns.Print(ns.ItemName(id) .. " can't go on the auction house from your bags.")
        end
        return false
    end
    if not e.picked then
        P.SetPicked(id, true)
    end
    A.sellSel = e
    P.CheckOne(e)
    A.Refresh()
    return true
end

local postAllOld = ns.StartPostAll
function ns.StartPostAll()
    if A.IsShown() then
        setTab("sell")
        P.CheckAll(false)
        return
    end
    return postAllOld()
end

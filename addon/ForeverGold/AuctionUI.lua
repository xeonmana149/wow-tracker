-- Forever Gold - the auction window
--
-- Talking to an auctioneer opens this window instead of the game's own.
-- Auction house pages:
--   Browse    search or pick a category; each result shows its usual price,
--             how it compares and how fast it sells. Click one to see every
--             listing and buy (stackable goods: any amount; gear: the one
--             you pick). Deals finds the bargains from your last scan.
--   Sell list the post queue (Poster.lua): tick what to sell, price-check it,
--             then press Post once per listing.
--   Sell item price-check and post one selected item without changing the list.
--   Auctions  your auctions with live undercut checks, and one-click-each
--             cancelling of the undercut ones.
--   Deals     Browse's Deals category, a click away: the bargains from your
--             last scan (Search there looks through them).
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
local ART = "Interface\\AddOns\\ForeverGold\\Art\\"
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

-- A personal item-level note, kept with this realm and faction rather than
-- with the price scan (which can be replaced). This is not a report.
function A.IsManuallyFlagged(id)
    local flags = ns.R().suspiciousItems
    return type(flags) == "table" and flags[id] == true
end

function A.SetManuallyFlagged(id, flagged)
    if type(id) ~= "number" or id <= 0 then return end
    local realm = ns.R()
    if type(realm.suspiciousItems) ~= "table" then realm.suspiciousItems = {} end
    realm.suspiciousItems[id] = flagged and true or nil
end

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
        GameTooltip:SetText(d.tip, 1, 1, 1, 1)
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

    t.bar = K.scrollBar(t, function(o)
        t.offset = floor(o + 0.5)
        t:Render()
    end)
    t.bar.track:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, -24)
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
        self.bar:Update(self.offset, maxOff, n > 0 and self.visible / n or 1, self:GetHeight() - 26)
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
A.dealFilters = { kind = "all", speed = "all" }
local QUALITIES = { { "PoorQuality", "Poor" }, { "CommonQuality", "Common" },
    { "UncommonQuality", "Uncommon" }, { "RareQuality", "Rare" }, { "EpicQuality", "Epic" },
    { "LegendaryQuality", "Legendary" }, { "ArtifactQuality", "Artifact" } }
A.filters = { qualities = {}, flags = {} }
for _, q in ipairs(QUALITIES) do A.filters.qualities[q[1]] = true end

local function qualityFilters()
    local out = {}
    local E = Enum and Enum.AuctionHouseFilter
    if E then
        for _, q in ipairs(QUALITIES) do
            if A.filters.qualities[q[1]] and E[q[1]] ~= nil then out[#out + 1] = E[q[1]] end
        end
        for _, key in ipairs({ "UsableOnly", "UncollectedOnly", "ExactMatch" }) do
            if A.filters.flags[key] and E[key] ~= nil then out[#out + 1] = E[key] end
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
    if category == "deals" then
        -- Deals picked: Search looks through the deals (2026-11-21)
        return A.ShowDeals(text)
    end
    if ns.scan and ns.scan.active then
        buyMsg("Wait for the price scan to finish, then search.")
        return
    end
    local p = win and win.browse
    local function readLevel(field)
        local value = field and (field:GetText() or "") or ""
        value = value:match("^%s*(.-)%s*$")
        if value == "" then return 0 end
        if not value:match("^%d+$") or tonumber(value) > 999 then return nil end
        return tonumber(value)
    end
    local minLevel, maxLevel = readLevel(p and p.minLevel), readLevel(p and p.maxLevel)
    if not minLevel or not maxLevel or (minLevel > 0 and maxLevel > 0 and minLevel > maxLevel) then
        buyMsg("Enter a valid level range (minimum must not exceed maximum).")
        return
    end
    local anyQuality = false
    for _, q in ipairs(QUALITIES) do if A.filters.qualities[q[1]] then anyQuality = true end end
    if not anyQuality then buyMsg("Select at least one item quality."); return end
    BUY.query = text or ""
    BUY.category = category
    BUY.mode, BUY.item, BUY.deals = "list", nil, nil
    BUY.results, BUY.seen, BUY.oddHidden = {}, {}, 0
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
        minLevel = minLevel,
        maxLevel = maxLevel,
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
        BUY.results, BUY.seen, BUY.oddHidden = {}, {}, 0
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
-- under its usual price. text: only the deals whose name has it.
local function nameHas(id, text)
    if text == "" then
        return true
    end
    local it = ns.Item(id)
    local name = (it and it.n) or (C_Item and C_Item.GetItemNameByID and ns.try(C_Item.GetItemNameByID, id)) or ""
    return name:lower():find(text, 1, true) ~= nil
end

function A.ShowDeals(text)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    BUY.mode, BUY.item, BUY.category = "list", nil, "deals"
    BUY.deals = true
    BUY.query = text
    BUY.searching = false
    BUY.results, BUY.oddHidden = {}, 0
    BUY.dirty = true
    BUY.message = nil
    local filters = A.dealFilters
    local maxText = win and win.browse and win.browse.dealMax and (win.browse.dealMax:GetText() or "") or ""
    maxText = maxText:match("^%s*(.-)%s*$")
    local maximum = maxText ~= "" and ns.ParseMoney(maxText) or nil
    if maxText ~= "" and (not maximum or maximum <= 0) then
        BUY.message = "Enter a valid maximum price, such as 50s or 2g 30s."
        A.Refresh()
        return
    end
    local function matches(id, price, kind)
        if filters.kind ~= "all" and filters.kind ~= kind then return false end
        if maximum and (not price or price > maximum) then return false end
        if filters.speed ~= "all" then
            local speed = ns.SaleSpeed and ns.SaleSpeed(id) or nil
            if (speed or "unknown") ~= filters.speed then return false end
        end
        return nameHas(id, text)
    end
    for _, f in ipairs(ns.VendorFlips()) do
        if matches(f.id, f.price, "vendor") then
            BUY.results[#BUY.results + 1] = { id = f.id, qty = f.listed or 0, price = f.price,
                why = "|cff40e060Vendor pays " .. ns.StripCodes(ns.Money(f.vendor)) .. "|r", profit = f.profit }
        end
    end
    if ns.Bargains then
        for _, b in ipairs(ns.Bargains()) do
            local price, listed = ns.AHPrice(b.id)
            if matches(b.id, price or b.price, "under") then
                BUY.results[#BUY.results + 1] = { id = b.id, qty = listed or 0, price = price or b.price,
                    why = "|cff40e060Well under usual|r", profit = b.profit }
            end
        end
    end
    if #BUY.results == 0 then
        BUY.message = (text ~= "" or filters.kind ~= "all" or filters.speed ~= "all" or maxText ~= "") and "No deals match these filters."
            or ns.R().lastScan and "No deals in your last scan. Scan again later - they come and go."
            or "Deals come from a price scan. Press Scan prices first."
    end
    A.Refresh()
end

-- Clicking the picked Deals category again: nothing picked, an empty list
-- (or a search of everything, if there's text in the box).
function A.LeaveDeals(text)
    text = text or ""
    if text:match("%S") then
        return A.Search(text, nil)
    end
    BUY.mode, BUY.item, BUY.category, BUY.deals = "list", nil, nil, nil
    BUY.query, BUY.results, BUY.seen, BUY.oddHidden = "", {}, {}, 0
    BUY.dirty = true
    BUY.message = nil
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
    if A.HideOverpay then
        A.HideOverpay()
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

-- How long to wait for the auction house to answer before giving up.
A.QUOTE_WAIT, A.BUY_WAIT = 10, 15

-- The server can drop a request without answering. Don't sit on
-- "Buying..." forever: after a while, let go and refresh the listings.
local function watch(b, wait)
    C_Timer.After(wait, ns.Guard("buy-timeout", function()
        if BUY.buy ~= b then
            return
        end
        BUY.buy = nil
        if b.state == "buying" then
            BUY.late = b
            buyMsg("The auction house never answered, so it may or may not have gone through. Check your mailbox"
                .. " before buying again - the list has been refreshed.")
        else
            pcall(AH.CancelCommoditiesPurchase)
            buyMsg("The auction house never sent a price. Nothing was bought - try again.")
        end
        A.RefreshItem()
    end))
end

----------------------------------------------------------------------
-- Paying well over the usual price asks first
----------------------------------------------------------------------

A.OVERPAY_PCT = 20   -- this much over the usual price per item...
A.OVERPAY_MIN = 100  -- ...and at least this much extra in all (copper)

-- How far over its usual price a purchase is, or nil when it isn't, or
-- when there's no usual price worth comparing with.
function A.Overpay(id, unit, qty)
    if ns.db.opts.buyConfirm == false or not unit or unit <= 0 then
        return nil
    end
    local usual = usualText(id)
    if not usual or usual <= 0 or (ns.PriceDoubt and ns.PriceDoubt(id)) then
        return nil
    end
    qty = max(1, qty or 1)
    local pct = floor((unit / usual - 1) * 100 + 0.5)
    local extra = floor((unit - usual) * qty + 0.5)
    if pct >= A.OVERPAY_PCT and extra >= A.OVERPAY_MIN then
        return { pct = pct, usual = usual, unit = unit, qty = qty, extra = extra, total = floor(unit * qty + 0.5) }
    end
    return nil
end

local ask
local function hideAsk()
    if ask then
        ask:Hide()
        ask.token = nil
    end
end
A.HideOverpay = hideAsk

local function buildAsk()
    local cover = CreateFrame("Frame", nil, win)
    cover:SetAllPoints()
    cover:SetFrameLevel(win:GetFrameLevel() + 40)
    cover:EnableMouse(true)
    cover.shade = tex(cover, "BACKGROUND", 0, 0, 0, 0.55)
    cover.shade:SetAllPoints()
    local d = CreateFrame("Frame", nil, cover)
    d:SetSize(400, 176)
    d:SetPoint("CENTER", 0, 20)
    d:SetFrameLevel(cover:GetFrameLevel() + 2)
    skin(d)
    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(32, 32)
    d.icon:SetPoint("TOPLEFT", 16, -14)
    d.title = label(d, "GameFontNormalLarge", "Pay more than usual?")
    d.title:SetTextColor(1, 0.44, 0.44)
    d.title:SetPoint("TOPLEFT", 58, -16)
    d.title:SetWidth(326)
    d.title:SetWordWrap(false)
    d.name = label(d, "GameFontHighlightSmall")
    d.name:SetPoint("TOPLEFT", 58, -36)
    d.name:SetWidth(326)
    d.name:SetWordWrap(false)
    d.lines = {}
    for i = 1, 3 do
        local l = label(d, "GameFontHighlight")
        l:SetPoint("TOPLEFT", 16, -60 - (i - 1) * 20)
        l:SetWidth(368)
        l:SetWordWrap(false)
        d.lines[i] = l
    end
    d.yes = button(d, "Buy anyway", 150, 26, function() A.ConfirmOverpay() end)
    d.yes:SetPoint("BOTTOMLEFT", 16, 14)
    d.no = button(d, "Don't buy", 110, 26, function() hideAsk() end)
    d.no:SetPoint("LEFT", d.yes, "RIGHT", 8, 0)
    d.no:SetPrimary(true)
    cover.box = d
    cover:Hide()
    return cover
end

-- token: the quote or listing this question is about; if it's gone by the
-- time you answer, nothing is bought.
function A.AskOverpay(o, id, token)
    if not win then
        return false
    end
    ask = ask or buildAsk()
    local d = ask.box
    setIcon(d.icon, ns.Icon(id))
    d.name:SetText(ns.ItemName(id) .. (o.qty > 1 and (GREY .. "  x" .. o.qty .. "|r") or ""))
    local each = o.qty > 1 and " each" or ""
    d.lines[1]:SetText("|cffff7070" .. o.pct .. "% more|r than its usual price.")
    d.lines[2]:SetText("You'd pay " .. ns.Money(o.unit) .. each .. GREY .. "  -  usually " .. ns.StripCodes(ns.Money(o.usual))
        .. each .. "|r")
    d.lines[3]:SetText("That's about " .. ns.Money(o.extra) .. " more than usual, " .. ns.Money(o.total) .. " in all.")
    d.yes:SetLabel("Buy anyway: " .. ns.StripCodes(ns.Money(o.total)))
    ask.token = token
    ask:Show()
    return true
end

function A.OverpayShown()
    return ask ~= nil and ask:IsShown()
end

function A.OverpayBox()
    return ask and ask.box
end

function A.ConfirmOverpay()
    local token = ask and ask.token
    hideAsk()
    if token and (token == BUY.buy or token == BUY.sel) then
        A.Buy(true)
    end
end

-- The buy button. Stackable goods take two clicks (ask the price, then
-- confirm it); gear is one click on the listing you picked. Only ever
-- called from a click. The state is set before asking the game, because
-- the game can refuse (AUCTION_HOUSE_SHOW_ERROR) before the call returns.
-- Paying well over the usual price asks first; confirmed = you said yes.
function A.Buy(confirmed)
    local item = BUY.item
    if not item or not BUY.listings then
        return
    end
    if item.commodity then
        local b = BUY.buy
        if b and b.state == "quoted" then
            if not confirmed then
                local o = A.Overpay(item.id, (b.total or 0) / max(1, b.qty), b.qty)
                if o and A.AskOverpay(o, item.id, b) then
                    return
                end
            end
            b.state, b.at = "buying", GetTime()
            BUY.late = nil
            ns.Fire("POSTER")
            if not pcall(AH.ConfirmCommoditiesPurchase, item.id, b.qty) then
                if BUY.buy == b then
                    BUY.buy = nil
                end
                buyMsg("The purchase was refused.")
                return
            end
            if BUY.buy == b then
                watch(b, A.BUY_WAIT)
            end
            return
        end
        if b then
            return
        end
        local qty = max(1, min(BUY.qty or 1, available()))
        b = { state = "quoting", qty = qty, id = item.id, at = GetTime() }
        BUY.buy, BUY.message, BUY.late = b, nil, nil
        ns.Fire("POSTER")
        if not pcall(AH.StartCommoditiesPurchase, item.id, qty) then
            if BUY.buy == b then
                BUY.buy = nil
            end
            buyMsg("The game blocked that purchase.")
            return
        end
        if BUY.buy == b and b.state == "quoting" then
            watch(b, A.QUOTE_WAIT)
        end
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
    if not confirmed then
        local o = A.Overpay(item.id, l.p, l.q)
        if o and A.AskOverpay(o, item.id, l) then
            return
        end
    end
    local b = { state = "buying", aid = l.aid, at = GetTime() }
    BUY.buy, BUY.message, BUY.late = b, nil, nil
    ns.Fire("POSTER")
    if not pcall(AH.PlaceBid, l.aid, l.buyout) then
        if BUY.buy == b then
            BUY.buy = nil
        end
        buyMsg("The game blocked that purchase.")
        return
    end
    if BUY.buy == b then
        watch(b, A.BUY_WAIT)
    end
end

function A.CancelBuy()
    hideAsk()
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
    elseif not b and BUY.late and BUY.late.qty then
        -- The answer came after we stopped waiting.
        b, BUY.late = BUY.late, nil
        bought("It went through after all: bought " .. b.qty .. " for " .. ns.StripCodes(ns.Money(b.total or 0))
            .. ". It's in your mailbox.")
    end
end)

ns.On("COMMODITY_PURCHASE_FAILED", function()
    if BUY.buy then
        BUY.buy = nil
        buyMsg("The purchase failed - someone may have bought them first.")
        A.RefreshItem()
    end
end)

ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(aid)
    local b = BUY.buy
    if b and b.state == "buying" and b.aid then
        bought("Bought. It's in your mailbox.")
    elseif not b and BUY.late and BUY.late.aid and (aid == nil or aid == BUY.late.aid) then
        BUY.late = nil
        bought("It went through after all: bought. It's in your mailbox.")
    end
end)

-- The game's own words for an auction house error ("Internal auction error").
local function errorText(err)
    local U = AuctionHouseUtil
    local text = U and U.GetErrorText and ns.try(U.GetErrorText, err)
    return type(text) == "string" and text ~= "" and text or nil
end

-- A refusal at any step of a purchase (asking the price, or paying) ends it.
ns.On("AUCTION_HOUSE_SHOW_ERROR", function(err)
    local b = BUY.buy
    if not b then
        return
    end
    BUY.buy = nil
    if b.state ~= "buying" then
        pcall(AH.CancelCommoditiesPurchase)
    end
    local why = errorText(err)
    buyMsg("The auction house refused that" .. (why and (": " .. why) or "") .. ". The list has been refreshed.")
    A.RefreshItem()
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

-- Which tab button is lit: Deals while Browse shows the deals.
local function litTabs()
    local onDeals = A.tab == "browse" and BUY.category == "deals"
    for k, b in pairs(tabs) do
        b:SetOn((k == "deals" and onDeals) or (k == A.tab and not onDeals))
    end
end

local function setTab(key)
    if P.pending and (P.state == "confirm" or P.state == "posting" or P.state == "verify")
        and ((A.tab == "single" and key ~= "single") or (A.tab == "sell" and key ~= "sell")) then
        P.message = "Finish the current auction post before changing tabs."
        A.Refresh()
        return
    end
    if key == "deals" then
        A.tab = "browse"
        win.browse:SetShown(true)
        win.sell:SetShown(false)
        win.single:SetShown(false)
        win.mine:SetShown(false)
        A.openCategory = nil
        if win.browse.search then
            win.browse.search:SetText("")
        end
        A.ShowDeals()
        litTabs()
        return
    end
    A.tab = key
    for k, b in pairs(tabs) do
        b:SetOn(k == key)
    end
    win.browse:SetShown(key == "browse")
    win.sell:SetShown(key == "sell")
    win.single:SetShown(key == "single")
    win.mine:SetShown(key == "auctions")
    if key == "sell" or key == "single" then
        if P.state ~= "checking" and P.state ~= "posting" and P.state ~= "confirm" and P.state ~= "verify" then
            P.Rebuild()
        end
    elseif key == "auctions" then
        P.QueryOwned()
    end
    A.Refresh()
end
A.SetTab = setTab

-- Shift-clicking a bag item fills the search, but never submits a query.
function A.SearchFromBag(id, link)
    if not (A.IsShown() and ns.ahOpen and id) then return false end
    local edit = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if edit and (not edit.HasFocus or edit:HasFocus()) then return false end
    local name = type(link) == "string" and link:match("|h%[(.-)%]|h")
    if not name and ns.ItemName then name = ns.ItemName(id) end
    if not name or name == "" or name:match("^Item #") then return false end
    setTab("browse")
    A.openCategory = nil
    BUY.category, BUY.deals, BUY.item, BUY.mode = nil, nil, nil, "list"
    BUY.results, BUY.seen, BUY.oddHidden = {}, {}, 0
    BUY.query, BUY.searching, BUY.dirty = "", false, true
    win.browse.search:SetText(name)
    A.Refresh()
    return true
end

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
    -- The category you picked stays picked: Search (even with an empty box)
    -- looks inside it. Click it again to search everything.
    local function picked()
        return (type(BUY.category) == "table" or BUY.category == "deals") and BUY.category or nil
    end
    p.cats.onClick = function(d)
        if d.deals then
            A.openCategory = nil
            if BUY.category == "deals" then
                A.LeaveDeals(p.search:GetText() or "") -- clicked again: deselect it
            else
                A.ShowDeals(p.search:GetText() or "")
            end
            return
        end
        local cur = picked()
        if cur and cur.top == d.top and cur.sub == d.sub then
            if d.sub == nil then
                A.openCategory = nil
            end
            A.Search(p.search:GetText() or "", nil)
            return
        end
        if d.sub == nil then
            A.openCategory = d.top
        end
        A.Search(p.search:GetText() or "", d)
    end

    local x0 = 12 + 170 + 8
    local rightW = W - x0 - 12
    p.search = newEdit(p, 260, function(text) A.Search(text, picked()) end)
    p.search:SetPoint("TOPLEFT", x0, -TOP)
    p.go = button(p, "Search", 70, 22, function() A.Search(p.search:GetText() or "", picked()) end)
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

    p.filters = CreateFrame("Frame", nil, p)
    p.filters:SetPoint("TOPLEFT", x0, -TOP - 30)
    p.filters:SetSize(rightW, 52)
    p.dealFilters = CreateFrame("Frame", nil, p)
    p.dealFilters:SetPoint("TOPLEFT", x0, -TOP - 30)
    p.dealFilters:SetSize(rightW, 52)
    local dealTypes = { { "all", "All deals" }, { "vendor", "Below vendor" }, { "under", "Below usual" } }
    local dealSpeeds = { { "all", "Any speed" }, { "fast", "Sells fast" }, { "steady", "Sells steadily" },
        { "slow", "Sells slowly" }, { "rarely", "Rarely sells" }, { "unknown", "Speed unknown" } }
    local function cycleFilter(key, options, control)
        for i, spec in ipairs(options) do
            if A.dealFilters[key] == spec[1] then
                local nextSpec = options[i % #options + 1]
                A.dealFilters[key] = nextSpec[1]; control:SetLabel(nextSpec[2]); break
            end
        end
        A.ShowDeals(p.search:GetText() or "")
    end
    p.dealKind = button(p.dealFilters, "All deals", 112, 22, function() cycleFilter("kind", dealTypes, p.dealKind) end)
    p.dealKind:SetPoint("TOPLEFT", 0, 0)
    p.dealSpeed = button(p.dealFilters, "Any speed", 116, 22, function() cycleFilter("speed", dealSpeeds, p.dealSpeed) end)
    p.dealSpeed:SetPoint("LEFT", p.dealKind, "RIGHT", 5, 0)
    local maxLabel = label(p.dealFilters, "GameFontHighlightSmall", "Max each:")
    maxLabel:SetPoint("LEFT", p.dealSpeed, "RIGHT", 8, 0)
    p.dealMax = newEdit(p.dealFilters, 90, function() A.ShowDeals(p.search:GetText() or "") end)
    p.dealMax:SetPoint("LEFT", maxLabel, "RIGHT", 5, 0)
    p.dealClear = button(p.dealFilters, "Clear filters", 90, 22, function()
        A.dealFilters.kind, A.dealFilters.speed = "all", "all"
        p.dealKind:SetLabel("All deals"); p.dealSpeed:SetLabel("Any speed"); p.dealMax:SetText("")
        A.ShowDeals(p.search:GetText() or "")
    end)
    p.dealClear:SetPoint("LEFT", p.dealMax, "RIGHT", 8, 0)
    local dealNote = label(p.dealFilters, "GameFontHighlightSmall", "Prices and sell speeds are estimates from the latest available data.")
    dealNote:SetPoint("TOPLEFT", 0, -30)
    local levelLabel = label(p.filters, "GameFontHighlightSmall", "Level")
    levelLabel:SetPoint("TOPLEFT", 0, -5)
    p.minLevel = newEdit(p.filters, 42, function() A.Search(p.search:GetText() or "", picked()) end)
    p.minLevel:SetPoint("TOPLEFT", 39, 0)
    local dash = label(p.filters, "GameFontHighlightSmall", "–")
    dash:SetPoint("LEFT", p.minLevel, "RIGHT", 4, 0)
    p.maxLevel = newEdit(p.filters, 42, function() A.Search(p.search:GetText() or "", picked()) end)
    p.maxLevel:SetPoint("LEFT", p.minLevel, "RIGHT", 16, 0)
    if p.minLevel.SetNumeric then p.minLevel:SetNumeric(true); p.maxLevel:SetNumeric(true) end
    if p.minLevel.SetMaxLetters then p.minLevel:SetMaxLetters(3); p.maxLevel:SetMaxLetters(3) end
    p.flagButtons = {}
    local flagX = 150
    for _, spec in ipairs({ { "UsableOnly", "Usable", 70 }, { "UncollectedOnly", "Uncollected", 98 },
        { "ExactMatch", "Exact match", 96 } }) do
        local key, title, buttonWidth = spec[1], spec[2], spec[3]
        if Enum and Enum.AuctionHouseFilter and Enum.AuctionHouseFilter[key] ~= nil then
            local b = button(p.filters, title, buttonWidth, 22, function()
                A.filters.flags[key] = not A.filters.flags[key]
                p.flagButtons[key]:SetPrimary(A.filters.flags[key])
            end)
            b:SetPoint("TOPLEFT", flagX, 0)
            b:SetPrimary(A.filters.flags[key] and true or false)
            p.flagButtons[key] = b
            flagX = flagX + buttonWidth + 5
        end
    end
    p.clearFilters = button(p.filters, "Clear filters", 90, 22, function()
        p.minLevel:SetText(""); p.maxLevel:SetText("")
        for key, b in pairs(p.flagButtons) do A.filters.flags[key] = false; b:SetPrimary(false) end
        for _, q in ipairs(QUALITIES) do
            A.filters.qualities[q[1]] = true
            if p.qualityButtons[q[1]] then p.qualityButtons[q[1]]:SetPrimary(true) end
        end
    end)
    p.clearFilters:SetPoint("TOPRIGHT", 0, 0)
    local qualityLabel = label(p.filters, "GameFontHighlightSmall", "Quality")
    qualityLabel:SetPoint("TOPLEFT", 0, -31)
    p.qualityButtons = {}
    local qualityX = 50
    for _, q in ipairs(QUALITIES) do
        local key, title = q[1], q[2]
        if Enum and Enum.AuctionHouseFilter and Enum.AuctionHouseFilter[key] ~= nil then
            local buttonWidth = 12 + #title * 7
            local b = button(p.filters, title, buttonWidth, 22, function()
                A.filters.qualities[key] = not A.filters.qualities[key]
                p.qualityButtons[key]:SetPrimary(A.filters.qualities[key])
            end)
            b:SetPoint("TOPLEFT", qualityX, -26)
            b:SetPrimary(A.filters.qualities[key])
            p.qualityButtons[key] = b
            qualityX = qualityX + buttonWidth + 4
        end
    end

    local tableH = listH - 86
    p.results = newTable(p, rightW, tableH, {
        { key = "name", title = "Item", icon = true, sort = true },
        { key = "qty", title = "Available", w = 70, right = true, sort = true },
        { key = "price", title = "Lowest", w = 96, right = true, sort = true },
        { key = "usual", title = "Usual", w = 90, right = true, sort = true },
        { key = "vs", title = "Deal", w = 150, sort = true },
        { key = "sells", title = "Sells", w = 120, sort = true },
    })
    p.results:SetPoint("TOPLEFT", x0, -TOP - 86)
    p.results.onClick = function(d, which)
        if which == "RightButton" then
            A.SetManuallyFlagged(d.r.id, not A.IsManuallyFlagged(d.r.id))
            BUY.dirty = true
            A.Refresh()
            return
        end
        A.OpenItem(d.r)
    end

    -- One item's listings, with the buy box beside it.
    local listW = rightW - SIDE_W + 0
    p.item = CreateFrame("Frame", nil, p)
    p.item:SetPoint("TOPLEFT", x0, -TOP - 86)
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
    box.flag = button(box, "Flag as suspicious", 208, 22, function()
        if not BUY.item then return end
        local id = BUY.item.id
        A.SetManuallyFlagged(id, not A.IsManuallyFlagged(id))
        BUY.dirty = true
        A.Refresh()
    end)
    box.flag:SetPoint("TOPLEFT", 10, -48)
    box.flag:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Personal item flag", 1, 0.82, 0, 1)
        GameTooltip:AddLine("Mark this item as potentially involved in gold farming. Applies to the item on this realm and faction, not a particular seller or listing. Click again to remove. This does not report anyone or alter prices.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    box.flag:SetScript("OnLeave", untip)
    box.facts = label(box, "GameFontHighlightSmall")
    box.facts:SetPoint("TOPLEFT", 10, -77)
    box.facts:SetWidth(208)
    box.facts:SetJustifyV("TOP")
    box.facts:SetWordWrap(true)
    box.qtyLabel = label(box, "GameFontHighlightSmall", "How many:")
    -- Sits on top of the price text (box.cost, below), so a warning line
    -- like "143% over the usual price" pushes it up instead of covering it.
    -- (Anchored once box.cost exists.)
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
    box.qtyLabel:SetPoint("BOTTOMLEFT", box.cost, "TOPLEFT", 0, 14)
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
        { key = "sells", title = "Sell rate", w = 80, sort = true },
        { key = "status", title = "Status", w = 92, sort = true },
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
        local selected = A.SellShown()
        if P.state == "confirm" then
            P.PostNext(selected)
        elseif P.CanPostAnyway(selected) then
            P.PostNext(selected, true)
        elseif P.state == "ready" then
            P.PostNext(selected)
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
    side.check = button(side, "Price check everything again", SIDE_W - 20, 22, function() P.CheckAll(true, true) end)
    side.check:SetPoint("BOTTOMLEFT", 10, 10)
    return p
end

-- One selected item uses the same live pricing and protected-posting engine,
-- but its temporary entry never changes the saved choices in the sell list.
local function buildSingle(f)
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", 0, 0); p:SetSize(W, H)
    local leftW = 376
    p.bagList = newTable(p, leftW - 20, 200, {
        { key = "name", title = "Choose an item", icon = true, sort = true },
        { key = "have", title = "Have", w = 55, right = true, sort = true },
    })
    p.bagList:SetPoint("TOPLEFT", 22, -TOP - 94)
    p.bagList:SetFrameLevel(p:GetFrameLevel() + 15)
    p.bagList:Hide()
    local function selectItem(item)
        if P.state == "checking" or P.state == "posting" or P.state == "confirm" or P.state == "verify" then
            P.message = "Finish or stop the current price check or post first."
            A.Refresh(); return false
        end
        if not item then return false end
        p.bagList:Hide()
        A.singleSel = { id = item.id, have = item.have, picked = true, status = "new" }
        P.CheckOne(A.singleSel)
        A.Refresh()
        return true
    end
    p.bagList.onClick = function(d) selectItem(d.e) end
    local drop = CreateFrame("Button", nil, p)
    drop:SetPoint("TOPLEFT", 12, -TOP); drop:SetSize(leftW, 64)
    skin(drop, C.panel[1], C.panel[2], C.panel[3], 1, C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 1)
    drop.icon = drop:CreateTexture(nil, "ARTWORK"); drop.icon:SetPoint("LEFT", 10, 0); drop.icon:SetSize(44, 44)
    drop.icon:SetTexture(ART .. "bag-inventory.tga")
    drop.text = label(drop, "GameFontHighlight", "Drag an item from your bags here")
    drop.text:SetPoint("LEFT", 64, 0); drop.text:SetWidth(leftW - 76); drop.text:SetWordWrap(true)
    local hover = tex(drop, "HIGHLIGHT", 1, 0.82, 0.3, 0.1); hover:SetAllPoints()
    local function receiveItem()
        if type(GetCursorInfo) ~= "function" then return end
        local kind, id = ns.try(GetCursorInfo)
        if kind ~= "item" or type(id) ~= "number" then
            P.message = "Pick up an item from your bags first."
            A.Refresh(); return
        end
        if P.state == "checking" or P.state == "posting" or P.state == "confirm" or P.state == "verify" then
            P.message = "Finish or stop the current price check or post first."
            A.Refresh(); return
        end
        local item
        for _, entry in ipairs(P.entries) do if entry.id == id then item = entry; break end end
        if not item then
            P.message = "That item isn't available to sell from your bags."
            A.Refresh(); return
        end
        -- Return the item to its bag before the price-check engine locates it.
        -- Never pick up, move, or consume the stack ourselves.
        if type(ClearCursor) ~= "function" then
            P.message = "Couldn't return the item to your bags."
            A.Refresh(); return
        end
        local cleared = pcall(ClearCursor)
        if not cleared or (CursorHasItem and ns.try(CursorHasItem)) then
            P.message = "Couldn't return the item to your bags."
            A.Refresh(); return
        end
        selectItem(item)
    end
    drop:SetScript("OnReceiveDrag", receiveItem)
    drop:SetScript("OnClick", function() if CursorHasItem and ns.try(CursorHasItem) then receiveItem() end end)
    p.drop = drop
    local side = CreateFrame("Frame", nil, p); p.side = side
    side:SetPoint("TOPLEFT", drop, "BOTTOMLEFT", 0, -7); side:SetSize(leftW, H - TOP - FOOT - 71)
    skin(side, C.panel[1], C.panel[2], C.panel[3], 1, C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 1)
    side.choose = button(side, "Choose from bags", 150, 24, function()
        p.bagList:SetShown(not p.bagList:IsShown())
    end)
    side.choose:SetPoint("TOPLEFT", 10, -10)
    side.rate = label(side, "GameFontHighlightSmall", ""); side.rate:SetPoint("LEFT", side.choose, "RIGHT", 10, 0)
    side.rate:SetWidth(leftW - 180); side.rate:SetWordWrap(false)
    side.perLabel = label(side, "GameFontNormal", "Quantity")
    side.perLabel:SetPoint("TOPLEFT", 16, -55)
    local function setQuantity(text)
        local e, n = A.singleSel, tonumber(text)
        if e and e.listings and n then P.SetPer(e, n) end
        A.Refresh()
    end
    side.per = newEdit(side, 110, setQuantity)
    side.per:SetScript("OnEditFocusLost", function(self) setQuantity(self:GetText() or "") end)
    side.per:SetPoint("TOPLEFT", 145, -49)
    side.max = button(side, "Max", 70, 22, function()
        local e = A.singleSel; if e and e.listings then P.SetPer(e, e.have or 1) end
    end)
    side.max:SetPoint("LEFT", side.per, "RIGHT", 8, 0)
    side.priceLabel = label(side, "GameFontNormal", "Buyout per item")
    side.priceLabel:SetPoint("TOPLEFT", 16, -94)
    local function setPrice()
        local e = A.singleSel
        if not e or not e.listings then return end
        local g = tonumber(side.gold:GetText()) or 0
        local s = tonumber(side.silver:GetText()) or 0
        local c = tonumber(side.copper:GetText()) or 0
        P.SetPrice(e, max(0, floor(g)) * 10000 + max(0, floor(s)) * 100 + max(0, floor(c)))
        A.Refresh()
    end
    side.gold = newEdit(side, 55, setPrice); side.gold:SetPoint("TOPLEFT", 145, -88)
    side.silver = newEdit(side, 50, setPrice); side.silver:SetPoint("LEFT", side.gold, "RIGHT", 5, 0)
    side.copper = newEdit(side, 50, setPrice); side.copper:SetPoint("LEFT", side.silver, "RIGHT", 5, 0)
    for _, field in ipairs({ side.gold, side.silver, side.copper }) do
        field:SetScript("OnEditFocusLost", setPrice)
    end
    for _, field in ipairs({ side.per, side.gold, side.silver, side.copper }) do
        if field.SetNumeric then field:SetNumeric(true) end
    end
    local coinLabels = { { side.gold, "Gold" }, { side.silver, "Silver" }, { side.copper, "Copper" } }
    for _, c in ipairs(coinLabels) do
        local t = label(side, "GameFontDisableSmall", c[2]); t:SetPoint("TOP", c[1], "BOTTOM", 0, -2)
    end
    side.reset = button(side, "Auto price", 90, 22, function() if A.singleSel and A.singleSel.listings then P.SetPrice(A.singleSel, nil) end end)
    side.reset:SetPoint("TOPLEFT", 145, -130)
    side.durationLabel = label(side, "GameFontNormal", "Duration"); side.durationLabel:SetPoint("TOPLEFT", 16, -169)
    side.duration = button(side, "", 130, 22, function() P.CycleSetting("duration") end)
    side.duration:SetPoint("TOPLEFT", 145, -164)
    side.depositLabel = label(side, "GameFontNormal", "Deposit"); side.depositLabel:SetPoint("TOPLEFT", 16, -207)
    side.deposit = label(side, "GameFontHighlight", "—"); side.deposit:SetPoint("TOPLEFT", 145, -207)
    side.totalLabel = label(side, "GameFontNormal", "Total buyout"); side.totalLabel:SetPoint("TOPLEFT", 16, -236)
    side.total = label(side, "GameFontHighlight", "—"); side.total:SetPoint("TOPLEFT", 145, -236)
    side.after = label(side, "GameFontHighlightSmall", ""); side.after:SetPoint("TOPLEFT", 145, -257)
    side.body = label(side, "GameFontHighlightSmall", ""); side.body:SetPoint("TOPLEFT", 16, -282)
    side.body:SetWidth(leftW - 32); side.body:SetHeight(40); side.body:SetWordWrap(true)
    side.post = button(side, "Create auction", 225, 30, function()
        local e = A.singleSel
        if not e then return end
        if P.state == "confirm" and P.pending and P.pending.entry == e then P.PostNext(e)
        elseif P.CanPostAnyway(e) then P.PostNext(e, true)
        elseif P.state == "ready" and P.Postable(e) then P.PostNext(e) end
    end)
    side.post:SetPoint("BOTTOMLEFT", 16, 12); side.post:SetPrimary(true)
    side.check = button(side, "Check", 70, 28, function()
        if P.state == "checking" then P.StopChecking()
        elseif A.singleSel then P.CheckOne(A.singleSel) end
    end)
    side.check:SetPoint("LEFT", side.post, "RIGHT", 8, 0)
    local rightW = W - leftW - 36
    p.list = newTable(p, rightW, H - TOP - FOOT, {
        { key = "bid", title = "Bid (stack)", w = 120, right = true, sort = true },
        { key = "buyout", title = "Buyout (stack)", w = 135, right = true, sort = true },
        { key = "each", title = "Each", w = 105, right = true, sort = true },
        { key = "qty", title = "Qty", w = 45, right = true, sort = true },
        { key = "seller", title = "Seller", sort = true },
    })
    p.list:SetPoint("TOPLEFT", drop, "TOPRIGHT", 12, 0)
    p.list.sortKey, p.list.sortAsc = "each", true
    p.list.onClick = function(d)
        if A.singleSel and d.listing and d.listing.p and P.state ~= "checking" and P.state ~= "posting"
            and P.state ~= "confirm" and P.state ~= "verify" then
            P.SetPrice(A.singleSel, d.listing.p)
        end
    end
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
    icon:SetTexture(K.AUCTION)
    local title = label(f, K.SERIF_L, "Auction House")
    title:SetTextColor(C.goldText[1], C.goldText[2], C.goldText[3])
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    f.money = label(f, "GameFontHighlight")
    f.money:SetPoint("LEFT", title, "RIGHT", 18, 0)

    local close = K.closeButton(f, 24, 24, function() A.Close() end)
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
    for _, t in ipairs({ { "browse", "Browse", "bag-search.tga" }, { "sell", "Sell list", "gold-auction.tga" },
        { "single", "Sell item", "gold-auction.tga" },
        { "auctions", "Auctions", "auction-listings.tga" }, { "deals", "Deals", "auction-deals.tga" } }) do
        local key = t[1]
        local b = button(f, t[2], 110, 24, function() setTab(key) end)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(18, 18)
        b.icon:SetPoint("LEFT", 6, 0)
        b.icon:SetTexture(ART .. t[3])
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
        b.text:SetPoint("RIGHT", -4, 0)
        b.text:SetJustifyH("CENTER")
        b:SetPoint("TOPLEFT", x, -42)
        tabs[key] = b
        x = x + 114
    end
    f.tabs = tabs

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
    f.single = buildSingle(f)
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
    p.cats.selected = nil
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
    p.filters:SetShown(not inItem and not BUY.deals)
    p.dealFilters:SetShown(not inItem and BUY.deals and true or false)
    p.results:SetShown(not inItem)
    p.item:SetShown(inItem and true or false)
    p.back:SetShown(inItem and true or false)
    local where = type(BUY.category) == "table" and BUY.category.name
        and (" in " .. ns.StripCodes(BUY.category.name):gsub("^%s+", ""))
        or BUY.category == nil and " (all categories)" or ""
    -- Gray and white things listed for a fortune are gold changing hands
    -- (see ns.Suspicious): nobody should buy them, so they're left out of
    -- the list, and the count above it says how many were.
    local function stateText()
        local shown = #BUY.results - (BUY.oddHidden or 0)
        local hidden = (BUY.oddHidden or 0) > 0 and (GREY .. "(" .. BUY.oddHidden .. " suspicious hidden)|r") or ""
        if BUY.searching then
            return "Searching" .. where .. "... " .. shown .. " found  " .. hidden
        end
        local text = shown > 0 and (plural(shown, "result") .. where) or ""
        return text .. (text ~= "" and hidden ~= "" and "  " or "") .. hidden
    end
    p.state:SetText(inItem and "" or stateText())

    if not inItem then
        local function emptyText()
            if BUY.searching then
                return "Searching..."
            elseif (BUY.oddHidden or 0) > 0 then
                return plural(BUY.oddHidden, "item") .. " found, all priced like gold changing hands between accounts"
                    .. " (a gray or white item listed for many times what it's worth). Hidden - don't buy them."
            elseif BUY.query ~= "" or BUY.category then
                return "Nothing found."
            end
            return "Search by name, pick a category, or try Deals for the bargains from your last scan."
        end
        p.results:SetEmpty(emptyText())
        if not BUY.dirty then
            p.results:Render()
            return
        end
        BUY.dirty = false
        local rows = {}
        local hidden = 0
        local function addRow(r)
            local i = #rows + 1
            local info = r.key and keyInfo(r.key)
            local name = (info and info.itemName) or ns.ItemName(r.id)
            local usual = usualText(r.id)
            local vs, pct = versus(r.price, usual)
            local vendor = ns.VendorSell(r.id)
            local hint
            local doubt = ns.PriceDoubt(r.id)
            if vendor and r.price and vendor > r.price and verifiedBuyout(r, info) then
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
            if A.IsManuallyFlagged(r.id) then
                vs = "|cffff9a5aFlagged by you|r"
                hint = "You marked this item as potentially suspicious. This is your personal note."
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
                hint = (hint and (hint .. "\n") or "") .. "Click to see listings. Right-click to flag or clear your flag.",
            }
        end
        for _, r in ipairs(BUY.results) do
            if r.price and ns.Suspicious(r.id, r.price) then
                hidden = hidden + 1
            else
                addRow(r)
            end
        end
        BUY.oddHidden = hidden
        p.state:SetText(stateText())
        p.results:SetEmpty(emptyText())
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
    local manualFlag = A.IsManuallyFlagged(id)
    box.flag.text:SetText(manualFlag and "Remove suspicious flag" or "Flag as suspicious")
    local facts = {}
    if manualFlag then
        facts[#facts + 1] = "|cffff9a5aFlagged by you.|r This is your personal note for this item."
    end
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
    -- The overpay question is about a quote or listing that's gone: drop it.
    if ask and ask:IsShown() and ask.token ~= b and ask.token ~= BUY.sel then
        hideAsk()
    end
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
            local o = A.Overpay(item.id, (b.total or 0) / max(1, b.qty), b.qty)
            box.cost:SetText((o and ("|cffff7070" .. o.pct .. "% over the usual price|r\n") or "")
                .. "Price confirmed: " .. ns.Money(b.total or 0) .. " for " .. b.qty
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
            local o = not odd and A.Overpay(item.id, l.p, l.q)
            box.cost:SetText((odd and ("|cffff7070Suspicious price - almost certainly gold changing hands, not a real"
                .. " sale.|r\n") or "") .. (o and ("|cffff7070" .. o.pct .. "% over the usual price|r\n") or "")
                .. l.q .. " for " .. ns.Money(l.buyout or 0))
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
        local speed, rate = ns.SaleSpeed(e.id)
        local sells = speed and rate and type(rate.through) == "number" and rate.through >= 0
            and (ns.SPEEDS[speed].color .. tostring(rate.through) .. "%|r")
            or speed and ns.SaleText(e.id, true) or (GREY .. "Unknown|r")
        rows[i] = {
            key = "e" .. e.id, id = e.id, e = e, checked = e.picked,
            cells = { name = name .. (e.recommended and "" or (GREY .. "  (not suggested)|r")),
                have = tostring(e.have or 0),
                plan = e.picked and e.decision and P.PlanText(e) or "",
                price = e.price and e.picked and ns.Money(e.price) or "",
                lowest = e.lowest and ns.Money(e.lowest) or (e.listings and GREY .. "none|r" or ""),
                sells = sells,
                status = e.picked and (st[2] .. st[1] .. "|r") or (GREY .. "Not posting|r") },
            sv = { name = name, have = e.have or 0, price = e.price or 0, lowest = e.lowest or 0,
                sells = speed and rate and rate.through or -1, status = st[1] },
            dim = not e.picked or e.status == "done" or e.status == "skipped",
            hint = (ns.SaleText(e.id) or "Sell rate unknown: not enough market data.")
                .. "\nTick to include it. Click to see its listing on the right.",
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
    elseif (P.state == "confirm" or P.CanPostAnyway(e) or (P.state == "ready" and P.NextEntry())) and ns.AHWaiting() then
        -- The auction house said busy / too fast: wait it out, don't click into another refusal.
        post:SetLabel("Busy - wait a moment...")
        post:SetDisabled(true)
    elseif P.state == "confirm" then
        post:SetLabel("Confirm post")
        post:SetDisabled(false)
    elseif P.CanPostAnyway(e) then
        post:SetLabel("Post anyway: " .. ns.StripCodes(ns.Money(e.price)) .. " each")
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
        or P.state == "verify" or #P.entries == 0)

    local ready, listings, worth = P.Summary()
    if P.state == "checking" or P.state == "ready" or P.state == "done" then
        win.statusExtra = listings > 0 and (plural(listings, "listing") .. " ready, about " .. ns.StripCodes(ns.Money(worth))
            .. " after the cut") or (P.postedCount and (plural(P.postedCount, "listing") .. " posted this visit") or nil)
    else
        win.statusExtra = nil
    end
end

-- Listing prices need every denomination, including copper on gold amounts.
local function singleMoney(value)
    if type(value) ~= "number" then return GREY .. "—|r" end
    value = floor(value + 0.5)
    local gold, silver, copper = floor(value / 10000), floor(value / 100) % 100, value % 100
    local pieces = {}
    if gold > 0 then pieces[#pieces + 1] = ns.Commas(gold) .. ns.COIN_ICONS.g end
    if silver > 0 then pieces[#pieces + 1] = silver .. ns.COIN_ICONS.s end
    if copper > 0 or #pieces == 0 then pieces[#pieces + 1] = copper .. ns.COIN_ICONS.c end
    return table.concat(pieces, " ")
end

local function refreshSingle()
    local p, e = win.single, A.singleSel
    local rows = {}
    for _, item in ipairs(P.entries) do
        local speed, rate = ns.SaleSpeed(item.id)
        local sellText = speed and rate and type(rate.through) == "number" and rate.through >= 0
            and (ns.SPEEDS[speed].color .. rate.through .. "%|r")
            or speed and ns.SaleText(item.id, true) or (GREY .. "Unknown|r")
        rows[#rows + 1] = { key = "i" .. item.id, id = item.id, e = item,
            cells = { name = ns.ItemName(item.id), have = tostring(item.have or 0), sells = sellText },
            sv = { name = ns.ItemName(item.id), have = item.have or 0, sells = speed and rate and rate.through or -1 },
            hint = (ns.SaleText(item.id) or "Sell rate unknown: not enough market data.") .. "\nClick to price-check this item." }
    end
    p.bagList.selected = e and "i" .. e.id or nil
    p.bagList:SetEmpty("No auctionable items in your bags.")
    p.bagList:SetData(rows, true)
    local side = p.side
    local busy = P.state == "checking" or P.state == "posting" or P.state == "confirm" or P.state == "verify"
    local auctions = {}
    if e then
        setIcon(p.drop.icon, ns.Icon(e.id))
        p.drop.text:SetText(ns.ItemName(e.id) .. "\n" .. GREY .. "You have " .. tostring(e.have or 0) .. "  •  Drag another item here|r")
        local lines = P.Explain(e)
        side.body:SetText(table.concat(lines, "\n"))
        side.rate:SetText(ns.SaleText(e.id, "mid") or (GREY .. "Sell rate unknown|r"))
        local editable = e.listings ~= nil and e.status ~= "done" and not busy
        for _, field in ipairs({ side.per, side.gold, side.silver, side.copper }) do
            field:EnableMouse(editable)
            field:SetAlpha(editable and 1 or 0.5)
        end
        side.max:SetDisabled(not editable); side.reset:SetDisabled(not editable)
        if not side.per:HasFocus() then side.per:SetText(tostring(e.per or 1)) end
        local amount = e.price and floor(e.price) or 0
        if not side.gold:HasFocus() then side.gold:SetText(e.price and tostring(floor(amount / 10000)) or "") end
        if not side.silver:HasFocus() then side.silver:SetText(e.price and tostring(floor(amount / 100) % 100) or "") end
        if not side.copper:HasFocus() then side.copper:SetText(e.price and tostring(amount % 100) or "") end
        local receive, deposit, qty = P.Totals(e)
        side.deposit:SetText(deposit and singleMoney(deposit) or (GREY .. "Unknown|r"))
        side.total:SetText(receive and singleMoney(floor(e.price * qty)) or (GREY .. "—|r"))
        side.after:SetText(receive and ("After 5% cut: " .. singleMoney(receive)) or "")
        local function addListing(l, i, bidOnly)
            local q = l.q or 1
            local total = l.buyout or (l.p and floor(l.p * q + 0.5))
            auctions[#auctions + 1] = { key = (bidOnly and "b" or "a") .. i, listing = l,
                cells = { bid = l.bid and singleMoney(l.bid) or GREY .. "—|r",
                    buyout = total and singleMoney(total) or GREY .. "Bid only|r",
                    each = l.p and singleMoney(l.p) or GREY .. "—|r", qty = tostring(q),
                    seller = l.mine and "You" or (l.owner or (l.sellers and tostring(l.sellers) .. " sellers") or "—") },
                sv = { bid = l.bid, buyout = total, each = l.p, qty = q, seller = l.owner or "" },
                tip = bidOnly and "Bid only" or "Current auction",
                hint = bidOnly and "This auction has no buyout." or "Click to use this price per item." }
        end
        for i, l in ipairs(e.listings or {}) do addListing(l, i, false) end
        for i, l in ipairs(e.listings and e.listings.bids or {}) do addListing(l, i, true) end
    else
        p.drop.icon:SetTexture(ART .. "bag-inventory.tga")
        p.drop.text:SetText("Drag an item from your bags here")
        side.body:SetText("Choose an item to check current auctions and prepare a listing.")
        side.rate:SetText(""); side.deposit:SetText("—"); side.total:SetText("—"); side.after:SetText("")
        for _, field in ipairs({ side.per, side.gold, side.silver, side.copper }) do
            field:EnableMouse(false); field:SetAlpha(0.5); if not field:HasFocus() then field:SetText("") end
        end
        side.max:SetDisabled(true); side.reset:SetDisabled(true)
    end
    p.list:SetEmpty(not e and "Choose an item to see current auctions."
        or P.state == "checking" and "Checking current auctions..."
        or not e.listings and "Prices unavailable. Try checking again."
        or "No current auctions found.")
    p.list:SetData(auctions, true)
    local _, duration = P.Setting("duration")
    side.duration:SetLabel("Lasts: " .. duration); side.duration:SetDisabled(busy)
    side.check:SetLabel(P.state == "checking" and "Stop" or "Recheck")
    side.check:SetDisabled(not e or (busy and P.state ~= "checking"))
    if P.state == "checking" then side.post:SetLabel("Checking..."); side.post:SetDisabled(true)
    elseif P.state == "posting" then side.post:SetLabel("Posting..."); side.post:SetDisabled(true)
    elseif P.state == "verify" then side.post:SetLabel("Checking post..."); side.post:SetDisabled(true)
    elseif P.state == "confirm" and P.pending and P.pending.entry == e then
        side.post:SetLabel("Confirm post"); side.post:SetDisabled(ns.AHWaiting())
    elseif P.CanPostAnyway(e) then side.post:SetLabel("Post anyway"); side.post:SetDisabled(ns.AHWaiting())
    elseif P.state == "ready" and P.Postable(e) then side.post:SetLabel("Post listing"); side.post:SetDisabled(ns.AHWaiting())
    else side.post:SetLabel("Post listing"); side.post:SetDisabled(true) end
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
    win.scan:SetLabel(scanning and ("Scan " .. (ns.ScanElapsed() or "0:00")) or "Scan prices")
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
    litTabs()
    if A.tab == "browse" then
        refreshBrowse()
    elseif A.tab == "sell" then
        refreshSell()
    elseif A.tab == "single" then
        refreshSingle()
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
    BUY.category, BUY.deals, A.openCategory = nil, nil, nil
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
    if A.IsShown() and (A.tab == "sell" or A.tab == "single") then
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

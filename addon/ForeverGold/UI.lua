-- Forever Gold - the window
--
-- One window, seven tabs, every row a plain sentence with a number on the
-- right. Built from bare frames and textures only (no Blizzard templates),
-- so there is nothing here that depends on which templates this client has.

local _, ns = ...
local floor, max, min = math.floor, math.max, math.min

local UI = {}
ns.UI = UI

local W, H = 860, 560
local COIN = "Interface\\Icons\\INV_Misc_Coin_01"
local GREY = "|cff9a9a9a"
local CUT = ns.AH_CUT

----------------------------------------------------------------------
-- Small building blocks
----------------------------------------------------------------------

local function tex(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

local function skin(f, r, g, b, a, er, eg, eb, ea)
    local bg = tex(f, "BACKGROUND", r, g, b, a)
    bg:SetAllPoints()
    f.bg = bg
    er, eg, eb, ea = er or 0.45, eg or 0.36, eb or 0.12, ea or 1
    local top = tex(f, "BORDER", er, eg, eb, ea)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(1)
    local bottom = tex(f, "BORDER", er, eg, eb, ea)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(1)
    local left = tex(f, "BORDER", er, eg, eb, ea)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(1)
    local right = tex(f, "BORDER", er, eg, eb, ea)
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetWidth(1)
end

local function label(parent, font, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    if text then
        fs:SetText(text)
    end
    return fs
end

local function button(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h or 24)
    skin(b, 0.20, 0.16, 0.07, 1, 0.55, 0.44, 0.15, 1)
    local hl = tex(b, "HIGHLIGHT", 1, 0.82, 0, 0.18)
    hl:SetAllPoints()
    b.text = label(b, "GameFontNormalSmall", text)
    b.text:SetPoint("CENTER")
    b.onClick = onClick
    b:SetScript("OnClick", function(self)
        if self.disabled or not self.onClick then
            return
        end
        local ok, err = pcall(self.onClick, self)
        if not ok then
            ns.Err("button", err)
        end
    end)
    function b:SetLabel(t)
        self.text:SetText(t or "")
    end
    function b:SetOn(on)
        if on then
            self.bg:SetColorTexture(0.42, 0.33, 0.08, 1)
        else
            self.bg:SetColorTexture(0.20, 0.16, 0.07, 1)
        end
    end
    function b:SetDisabled(d)
        self.disabled = d and true or false
        if d then
            self.text:SetTextColor(0.5, 0.5, 0.5)
        else
            self.text:SetTextColor(1, 0.82, 0)
        end
    end
    return b
end

local function setFont(fs, name)
    local font = _G[name]
    if font then
        fs:SetFontObject(font)
    end
end

local function setIcon(texture, icon)
    texture:SetTexture(icon or 134400)
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
end

function ns.SearchAH(name)
    if not name or not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        return
    end
    pcall(function()
        AuctionHouseFrame.SearchBar:SetSearchText(name)
        AuctionHouseFrame.SearchBar:StartSearch()
    end)
end

local function insertLink(id)
    local ok, _, link = pcall(C_Item.GetItemInfo, id)
    if not ok or not link then
        return
    end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        pcall(ChatFrameUtil.InsertLink, link)
    elseif ChatEdit_InsertLink then
        pcall(ChatEdit_InsertLink, link)
    end
end

----------------------------------------------------------------------
-- Scrolling list with rows of different heights
----------------------------------------------------------------------

local RIGHT_W = 200

local function rowEnter(self)
    local d = self.d
    if not d or d.type or not GameTooltip then
        return
    end
    if not pcall(GameTooltip.SetOwner, GameTooltip, self, "ANCHOR_CURSOR_RIGHT") then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    end
    local tip = d.tip
    if type(tip) == "function" then
        local ok, result = pcall(tip)
        tip = ok and result or nil
    end
    if tip then
        GameTooltip:SetText(d.tipTitle or d.title or "", 1, 0.82, 0)
        for _, line in ipairs(tip) do
            if type(line) == "table" then
                GameTooltip:AddDoubleLine(line[1], line[2], 0.9, 0.9, 0.9, 1, 1, 1)
            else
                GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true)
            end
        end
        if d.id then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Shift-click: link it in chat" .. (ns.ahOpen and ".  Click: search the auction house." or "."),
                0.55, 0.55, 0.55, true)
        end
    elseif d.id then
        pcall(GameTooltip.SetItemByID, GameTooltip, d.id)
    else
        GameTooltip:Hide()
        return
    end
    GameTooltip:Show()
end

local function rowLeave()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

local function rowClick(self)
    local d = self.d
    if not d then
        return
    end
    if d.onClick then
        local ok, err = pcall(d.onClick, d)
        if not ok then
            ns.Err("row", err)
        end
        return
    end
    if d.id then
        if IsShiftKeyDown and IsShiftKeyDown() then
            insertLink(d.id)
        elseif ns.ahOpen then
            ns.SearchAH(ns.ItemName(d.id))
        end
    end
end

local function newRow(list)
    local r = CreateFrame("Button", nil, list.content)
    r.hl = tex(r, "HIGHLIGHT", 1, 1, 1, 0.07)
    r.hl:SetAllPoints()
    r.band = tex(r, "BACKGROUND", 1, 0.82, 0, 0.10)
    r.band:SetAllPoints()
    r.sep = tex(r, "BORDER", 1, 1, 1, 0.06)
    r.sep:SetPoint("BOTTOMLEFT")
    r.sep:SetPoint("BOTTOMRIGHT")
    r.sep:SetHeight(1)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(30, 30)
    r.icon:SetPoint("TOPLEFT", 6, -6)
    r.title = label(r, "GameFontHighlight")
    r.sub = label(r, "GameFontHighlightSmall")
    r.r1 = label(r, "GameFontHighlight")
    r.r1:SetJustifyH("RIGHT")
    r.r2 = label(r, "GameFontDisableSmall")
    r.r2:SetJustifyH("RIGHT")
    r.r1:SetWordWrap(false)
    r.r2:SetWordWrap(false)
    r.body = label(r, "GameFontHighlightSmall")
    r.body:SetJustifyV("TOP")
    r.btn = button(r, "", 54, 22)
    r.btn:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    r.btn:Hide()
    r:SetScript("OnEnter", rowEnter)
    r:SetScript("OnLeave", rowLeave)
    r:SetScript("OnClick", rowClick)
    r.list = list
    return r
end

-- Fills a row from its description and returns the height it needs.
local function renderRow(r, d, width)
    local RIGHT_W = (r.list and r.list.rightW) or RIGHT_W
    r.d = d
    r:SetWidth(width)
    r.icon:Hide()
    r.band:Hide()
    r.sub:SetText("")
    r.r1:SetText("")
    r.r2:SetText("")
    r.body:SetText("")
    r.body:Hide()
    r.btn:Hide()
    r.title:ClearAllPoints()
    r.sub:ClearAllPoints()
    r.r1:ClearAllPoints()
    r.r2:ClearAllPoints()
    r.title:SetWordWrap(false)
    r.sub:SetWordWrap(false)

    if d.type == "header" then
        r.band:Show()
        setFont(r.title, "GameFontNormal")
        r.title:SetPoint("LEFT", 8, 0)
        r.title:SetWidth(width - RIGHT_W - 20)
        r.title:SetText(d.text or "")
        r.r1:SetPoint("RIGHT", -10, 0)
        r.r1:SetWidth(RIGHT_W)
        r.r1:SetText(d.right or "")
        r:EnableMouse(false)
        return 26
    elseif d.type == "text" then
        local y = -8
        setFont(r.title, "GameFontNormal")
        if d.title and d.title ~= "" then
            r.title:SetPoint("TOPLEFT", 8, y)
            r.title:SetWidth(width - 20)
            r.title:SetText(d.title)
            y = y - 18
        else
            r.title:SetText("")
        end
        r.body:Show()
        r.body:ClearAllPoints()
        r.body:SetPoint("TOPLEFT", 8, y)
        r.body:SetWidth(width - 24)
        r.body:SetWordWrap(true)
        r.body:SetText(d.text or "")
        local h = r.body:GetStringHeight() or 14
        r:EnableMouse(false)
        return floor(-y + h + 10)
    end

    r:EnableMouse(true)
    r.icon:Show()
    setIcon(r.icon, d.icon or (d.id and ns.Icon(d.id)))
    if d.dim then
        r.icon:SetAlpha(0.45)
    else
        r.icon:SetAlpha(1)
    end
    -- An optional action button (for example "Sell") sits at the far right
    -- and pushes the numbers left.
    local pad, rightW = 10, RIGHT_W
    if d.btn then
        pad, rightW = 70, RIGHT_W - 40
        r.btn:SetLabel(d.btn.label)
        r.btn.onClick = function() d.btn.onClick(d) end
        r.btn:Show()
    end
    setFont(r.title, "GameFontHighlight")
    r.title:SetPoint("TOPLEFT", 44, -6)
    r.title:SetWidth(width - 44 - rightW - pad - 4)
    r.title:SetText(d.title or "")
    r.sub:SetPoint("TOPLEFT", 44, -23)
    r.sub:SetWidth(width - 44 - rightW - pad - 4)
    r.sub:SetText(d.sub and (GREY .. d.sub .. "|r") or "")
    r.r1:SetPoint("TOPRIGHT", -pad, -6)
    r.r1:SetWidth(rightW)
    r.r1:SetText(d.r1 or "")
    r.r2:SetPoint("TOPRIGHT", -pad, -24)
    r.r2:SetWidth(rightW)
    r.r2:SetText(d.r2 or "")
    return 42
end

local MAX_ROWS = 400

local function createList(parent)
    local list = { rows = {}, ys = {}, hs = {}, count = 0, offset = 0, contentH = 0 }
    local clip = CreateFrame("Frame", nil, parent)
    clip:SetClipsChildren(true)
    list.clip = clip
    local content = CreateFrame("Frame", nil, clip)
    content:SetSize(10, 10)
    content:SetPoint("TOPLEFT", 0, 0)
    list.content = content
    list.thumb = tex(clip, "OVERLAY", 1, 0.82, 0, 0.45)
    list.thumb:SetWidth(3)

    function list:Apply()
        local viewH = self.viewH or 0
        local maxOffset = max(0, self.contentH - viewH)
        self.offset = max(0, min(self.offset, maxOffset))
        self.content:ClearAllPoints()
        self.content:SetPoint("TOPLEFT", 0, self.offset)
        for i = 1, self.count do
            local y, h = self.ys[i], self.hs[i]
            self.rows[i]:SetShown(y + h > self.offset and y < self.offset + viewH)
        end
        for i = self.count + 1, #self.rows do
            self.rows[i]:Hide()
        end
        if maxOffset > 0 and viewH > 0 then
            local size = max(24, viewH * viewH / self.contentH)
            self.thumb:SetHeight(size)
            self.thumb:ClearAllPoints()
            self.thumb:SetPoint("TOPRIGHT", self.clip, "TOPRIGHT", 0, -(viewH - size) * (self.offset / maxOffset))
            self.thumb:Show()
        else
            self.thumb:Hide()
        end
    end

    function list:SetRows(data, keepScroll)
        local width = max(100, (self.viewW or 100) - 8)
        local y, n = 0, min(#data, MAX_ROWS)
        for i = 1, n do
            local r = self.rows[i]
            if not r then
                r = newRow(self)
                self.rows[i] = r
            end
            local h = renderRow(r, data[i], width)
            r:SetHeight(h)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
            self.ys[i], self.hs[i] = y, h
            y = y + h
        end
        self.count = n
        self.contentH = y
        self.content:SetSize(width, max(10, y))
        if not keepScroll then
            self.offset = 0
        end
        self:Apply()
    end

    clip:EnableMouseWheel(true)
    clip:SetScript("OnMouseWheel", function(_, delta)
        list.offset = list.offset - delta * 84
        list:Apply()
    end)
    return list
end

----------------------------------------------------------------------
-- Row helpers used by the tab builders
----------------------------------------------------------------------

local function Hd(rows, text, right)
    rows[#rows + 1] = { type = "header", text = text, right = right }
end

local function Tx(rows, title, text)
    rows[#rows + 1] = { type = "text", title = title, text = text }
end

-- The same building blocks, for the other windows (TrackerUI.lua).
ns.UIKit = { tex = tex, skin = skin, label = label, button = button, setIcon = setIcon,
    createList = createList, Hd = Hd, Tx = Tx, GREY = GREY, COIN = COIN, rowLeave = rowLeave }

local SRC = { vendor = "from a vendor", ah = "auction house", craft = "you make it", old = "last price seen" }

local function plural(n, word)
    return n .. " " .. word .. (n == 1 and "" or "s")
end

local function craftTip(e)
    local rec = e.rec
    local lines = {}
    lines[#lines + 1] = rec.prof .. " recipe, known by " .. table.concat(rec.chars, ", ") .. "."
    lines[#lines + 1] = " "
    if e.parts then
        lines[#lines + 1] = "Materials for one craft" .. (rec.yield > 1 and (" (makes " .. rec.yield .. ")") or "") .. ":"
        for _, p in ipairs(e.parts) do
            lines[#lines + 1] = { "  " .. p.qty .. " x " .. ns.ItemName(p.id),
                ns.Money(p.each * p.qty) .. "  " .. GREY .. (SRC[p.src] or "") .. "|r" }
        end
        lines[#lines + 1] = { "Cost to make one", ns.Money(e.cost) }
    elseif e.missing then
        lines[#lines + 1] = "I don't have a price for " .. ns.ItemName(e.missing)
            .. " yet, so I can't work out the cost. It may not be on the auction house."
    end
    if e.price then
        lines[#lines + 1] = { "Lowest auction price", ns.Money(e.price) }
        lines[#lines + 1] = { "Auction house keeps 5%", "-" .. ns.Money(e.price * CUT) }
        if e.profit then
            lines[#lines + 1] = { "Profit on each one", ns.Profit(e.profit) }
        end
    elseif e.last then
        lines[#lines + 1] = { "None for sale now. Last seen at", ns.Money(e.last) }
    else
        lines[#lines + 1] = "I have never seen one of these on the auction house."
    end
    if e.vendor and e.vendor > 0 then
        lines[#lines + 1] = { "A vendor pays", ns.Money(e.vendor) }
    end
    lines[#lines + 1] = " "
    if e.bop then
        lines[#lines + 1] = "This binds to you when made, so it can't be sold to other players."
    elseif e.profit and e.profit > 0 then
        lines[#lines + 1] = "|cff40e060Worth making.|r Even buying every material, you come out ahead."
        if e.listed and e.listed >= 20 then
            lines[#lines + 1] = e.listed .. " are already listed, so expect to be undercut. Sell a few at a time."
        elseif e.listed and e.listed <= 3 then
            lines[#lines + 1] = "Only " .. e.listed .. " listed - very little competition."
        end
    elseif e.profit then
        lines[#lines + 1] = "|cffff7070Don't make this to sell.|r The materials are worth more than the finished item - sell the materials instead."
    elseif e.cost then
        lines[#lines + 1] = "Nobody is selling this. That is either an open niche or something nobody wants. List one or two and see."
    end
    if e.vendorProfit and e.vendorProfit > 0 then
        lines[#lines + 1] = "|cff40e060A vendor pays more than it costs to make|r (" .. ns.Profit(e.vendorProfit)
            .. " each) - guaranteed money, no auction needed."
    end
    if not e.bop then
        local sale = ns.SaleText and ns.SaleText(rec.out)
        if sale then
            local r = ns.SaleRate(rec.out)
            lines[#lines + 1] = "Auction house: " .. sale .. "."
            if r and r.avg > 0 then
                lines[#lines + 1] = { "Has actually been selling for", ns.Money(r.avg) }
            end
            if e.demand == "rarely" then
                lines[#lines + 1] = "|cffff7070Hardly any of these sell|r, whatever the price says. Make one to test before making more."
            end
        elseif e.demand == "slow" then
            lines[#lines + 1] = "Weapons and armour sell slowly. You may need to relist a few times."
        end
    end
    if e.approx then
        lines[#lines + 1] = GREY .. "Some material prices are estimates.|r"
    end
    if e.canMake then
        lines[#lines + 1] = "You can make " .. e.canMake .. " right now from your bags."
    end
    return lines
end

local function craftRow(e, mode)
    local rec = e.rec
    local d = { id = rec.out, title = ns.ItemText(rec.out), tipTitle = ns.ItemName(rec.out),
        tip = function() return craftTip(e) end }
    local who = rec.mine and rec.prof or (rec.prof .. " on " .. (rec.chars[1] or "an alt"))
    if mode == "good" or mode == "bad" then
        local speed = ns.SaleText and ns.SaleText(rec.out, true)
        d.sub = "Costs " .. ns.Money(e.cost) .. GREY .. " to make, sells for |r" .. ns.Money(e.price) .. GREY
            .. "  -  " .. (e.listed or 0) .. " listed  -  " .. (speed and (speed .. GREY .. "  -  ") or "") .. who
        d.r1 = ns.Profit(e.profit)
        d.r2 = mode == "good" and (e.margin and (floor(e.margin * 100 + 0.5) .. "% margin, each") or "profit each")
            or "loss on each one"
        if mode == "good" and e.canMake and e.canMake > 0 then
            d.r2 = "each  -  you can make " .. e.canMake
        end
    elseif mode == "untapped" then
        d.sub = "Costs " .. ns.Money(e.cost) .. GREY .. " to make  -  " .. (e.last and ("last seen at |r"
            .. ns.Money(e.last) .. GREY) or "never seen for sale") .. "  -  " .. who
        d.r1 = "|cffffd100no sellers|r"
        d.r2 = "try listing one"
    elseif mode == "bound" then
        d.sub = "Binds when made - can't be sold  -  " .. who
        d.dim = true
    else
        d.sub = "No price yet for " .. ns.ItemName(e.missing or 0) .. "  -  " .. who
        d.dim = true
    end
    return d
end

----------------------------------------------------------------------
-- Tab: To do - every quick win, best first, with one click to act
----------------------------------------------------------------------

local function charactersRow(rows)
    local chars = {}
    for _, ch in pairs(ns.db.chars) do
        chars[#chars + 1] = ch
    end
    table.sort(chars, function(a, b) return (a.seen or 0) > (b.seen or 0) end)
    local names = {}
    for i = 1, min(4, #chars) do
        names[i] = chars[i].name or "?"
    end
    rows[#rows + 1] = { icon = COIN,
        title = table.concat(names, ", ") .. (#chars > 4 and (" and " .. (#chars - 4) .. " more") or ""),
        sub = "Hover for each one's gold, level and professions",
        onClick = false, tipTitle = "Your characters",
        tip = function()
            local lines = {}
            for _, ch in ipairs(chars) do
                local profs = {}
                for pname, p in pairs(ch.profs or {}) do
                    profs[#profs + 1] = pname .. " " .. (p.skill or 0)
                end
                table.sort(profs)
                lines[#lines + 1] = { (ch.name or "?") .. "  level " .. (ch.level or "?"), ns.Money(ch.money or 0) }
                lines[#lines + 1] = GREY .. "    " .. (#profs > 0 and table.concat(profs, ", ") or "no professions seen yet")
                    .. ", seen " .. ns.Ago(ch.seen) .. "|r"
            end
            return lines
        end }
end

local function firstNames(list, n, getId)
    local names = {}
    for i = 1, min(n, #list) do
        names[i] = ns.ItemName(getId(list[i]))
    end
    return table.concat(names, ", ") .. (#list > n and " and more" or "")
end

local function buildTodo()
    local rows = {}
    local c = ns.Char()
    local R = ns.R()
    local name = c.name or "you"

    if not R.lastScan then
        Tx(rows, "Start here",
            "Walk up to any auctioneer and open the auction window. I read every price automatically. After that, this page lists exactly what "
            .. name .. " should do to make gold, best first.")
    elseif time() - R.lastScan > 12 * 3600 then
        Tx(rows, "Your prices are getting old", "They were last read " .. ns.Ago(R.lastScan)
            .. ". Next time you pass an auctioneer I'll refresh them automatically.")
    end
    local missing = ns.MissingRecipeProfessions()
    if #missing > 0 then
        Tx(rows, "Show me your recipes", "Open your " .. table.concat(missing, ", ")
            .. " window once (click the profession in your spellbook) so I can tell you what's worth crafting.")
    end

    if R.lastScan then
        local bag = ns.BagAdvice()
        if #bag.undercut > 0 then
            rows[#rows + 1] = { icon = ns.Icon(bag.undercut[1].id),
                title = "|cffff7070Relist " .. plural(#bag.undercut, "auction") .. "|r - someone undercut you",
                sub = firstNames(bag.undercut, 3, function(u) return u.id end) .. ". Theirs sells first. Click to see them.",
                onClick = function() ns.ShowTab("sell") end }
        end

        -- Quick wins: gold you can have in the next few minutes.
        local todo = {}
        local function add(value, d)
            if value and value > 0 then
                todo[#todo + 1] = { value = value, d = d }
            end
        end

        local flips = ns.VendorFlips()
        if #flips > 0 then
            add(flips.total, { icon = ns.Icon(flips[1].id),
                title = "Buy " .. plural(#flips, "auction") .. " and sell " .. (#flips == 1 and "it" or "them") .. " to a vendor",
                sub = "Listed for less than any shopkeeper pays: " .. firstNames(flips, 2, function(f) return f.id end)
                    .. ". No risk. Click to see them.",
                r1 = ns.Profit(flips.total), r2 = "profit, no risk", onClick = function() ns.ShowTab("buy") end })
        end
        if #bag.ah > 0 then
            add(bag.ahTotal, { icon = ns.Icon(bag.ah[1].id),
                title = "Post " .. plural(#bag.ah, "item") .. " from your bags at auction",
                sub = firstNames(bag.ah, 3, function(b) return b.id end) .. ". Click, then press Sell on each.",
                r1 = ns.Money(bag.ahTotal), r2 = "after the 5% cut", onClick = function() ns.ShowTab("sell") end })
        end
        if #bag.vendor > 0 then
            add(bag.vendorTotal, { icon = ns.Icon(bag.vendor[1].id),
                title = "Sell " .. plural(#bag.vendor, "thing") .. " to any vendor",
                sub = firstNames(bag.vendor, 3, function(b) return b.id end) .. ". The auction house wouldn't pay more.",
                r1 = ns.Money(bag.vendorTotal), r2 = "at any vendor", onClick = function() ns.ShowTab("sell") end })
        end

        local craft = ns.CraftList()
        local picks = {}
        for _, e in ipairs(craft.good) do
            picks[#picks + 1] = e
        end
        table.sort(picks, function(a, b)
            local am, bm = (a.canMake or 0) > 0, (b.canMake or 0) > 0
            if am ~= bm then
                return am
            end
            return (a.rank or a.profit) > (b.rank or b.profit)
        end)
        for i = 1, min(3, #picks) do
            local e = picks[i]
            local d = craftRow(e, "good")
            local n = (e.canMake and e.canMake > 0) and e.canMake or nil
            d.title = "Craft " .. (n and (n .. " x ") or "") .. d.title
            d.sub = (n and "You have the materials. " or "Buy the materials first. ") .. "Costs " .. ns.Money(e.cost)
                .. GREY .. " each to make, sells for |r" .. ns.Money(e.price) .. GREY .. "."
            d.r1 = ns.Profit(e.profit * (n or 1))
            d.r2 = n and "for all of them" or "profit each"
            d.onClick = function() ns.ShowTab("craft") end
            add(e.profit * (n or 1), d)
        end

        local deals = ns.VendorDeals()
        if deals.sure > 0 then
            local v = deals[1]
            add(v.profit, { icon = ns.Icon(v.id),
                title = "Buy " .. ns.ItemName(v.id) .. " from " .. (v.npc or "a vendor") .. ", resell at auction",
                sub = (v.zone and v.zone ~= "" and ("In " .. v.zone .. ". ") or "")
                    .. (deals.sure > 1 and (plural(deals.sure - 1, "more like it") .. ". ") or "") .. "Click to see them.",
                r1 = ns.Profit(v.profit), r2 = "each, after the cut", onClick = function() ns.ShowTab("buy") end })
        end

        table.sort(todo, function(a, b) return a.value > b.value end)
        Hd(rows, "Do these now, best first")
        for i, e in ipairs(todo) do
            e.d.title = "|cffffd100" .. i .. ".|r  " .. e.d.title
            rows[#rows + 1] = e.d
        end
        if #todo == 0 then
            Tx(rows, nil, "Nothing quick right now. Open your bags and profession windows so I know what you have, and check again after your next scan.")
        end

        -- Then: something to do for the next hour.
        local farms = {}
        for _, f in ipairs(ns.FarmList()) do
            if f.ok and f.perHour and #farms < 2 then
                farms[#farms + 1] = f
            end
        end
        if #farms > 0 then
            Hd(rows, "Got an hour? Go farm")
            for _, f in ipairs(farms) do
                rows[#rows + 1] = { icon = f.items[1] and f.items[1].id and ns.Icon(f.items[1].id) or COIN,
                    title = f.farm.title, sub = f.where,
                    r1 = "~" .. ns.Money(f.perHour), r2 = "an hour (rough guess)",
                    onClick = function() ns.ShowTab("farm") end }
            end
        end
        if #craft.untapped > 0 then
            rows[#rows + 1] = { icon = ns.Icon(craft.untapped[1].rec.out),
                title = "Worth a try: " .. plural(#craft.untapped, "recipe") .. " of yours nobody is selling",
                sub = "List one or two and see what sells. Click to see them.",
                onClick = function() ns.ShowTab("craft") end }
        end
    end

    Hd(rows, "Your characters", ns.Money(ns.TotalGold()) .. " in total")
    charactersRow(rows)
    return rows
end

----------------------------------------------------------------------
-- Tab: Craft
----------------------------------------------------------------------

local function buildCraft()
    local rows = {}
    local craft = ns.CraftList()
    if craft.total == 0 then
        Tx(rows, "No recipes yet",
            "Open each of your profession windows once (click the profession in your spellbook). I'll read every recipe you know and show here which ones make money, which lose money, and which nobody else is selling.")
        return rows
    end
    if not ns.R().lastScan then
        Tx(rows, "No prices yet", "I know your recipes, but I need auction prices to judge them. Visit an auctioneer.")
    end
    Tx(rows, nil,
        "Profit = lowest auction price, minus the auction house's 5%, minus the cheapest way to get the materials. Hover a row for the full sum.")

    if #craft.good > 0 then
        Hd(rows, "Worth making to sell", plural(#craft.good, "recipe"))
        for _, e in ipairs(craft.good) do
            rows[#rows + 1] = craftRow(e, "good")
        end
    end
    if #craft.untapped > 0 then
        Hd(rows, "Nobody is selling these - you could be the only one", plural(#craft.untapped, "recipe"))
        for _, e in ipairs(craft.untapped) do
            rows[#rows + 1] = craftRow(e, "untapped")
        end
    end
    if #craft.bad > 0 then
        Hd(rows, "Don't make these to sell - the materials are worth more", plural(#craft.bad, "recipe"))
        for _, e in ipairs(craft.bad) do
            rows[#rows + 1] = craftRow(e, "bad")
        end
    end
    if #craft.unknown > 0 then
        Hd(rows, "Can't judge yet - a material has no price", plural(#craft.unknown, "recipe"))
        for _, e in ipairs(craft.unknown) do
            rows[#rows + 1] = craftRow(e, "unknown")
        end
    end
    if #craft.bound > 0 then
        Hd(rows, "Can't be sold (binds when made)", plural(#craft.bound, "recipe"))
        for _, e in ipairs(craft.bound) do
            rows[#rows + 1] = craftRow(e, "bound")
        end
    end
    return rows
end

----------------------------------------------------------------------
-- Tab: Farm
----------------------------------------------------------------------

local function farmTip(f)
    local lines = { f.farm.how or "", " ", "Where: " .. (f.where or ""), " ", "What you get (rough amounts per hour):" }
    for _, it in ipairs(f.items) do
        local right
        if it.value then
            right = ns.Money(it.value) .. " each " .. GREY .. (it.how == "ah" and "at auction" or "at a vendor") .. "|r"
        else
            right = GREY .. "no price yet|r"
        end
        local rate = it.rate >= 1 and tostring(it.rate) or "rare"
        lines[#lines + 1] = { "  " .. rate .. " x " .. it.name, right }
    end
    lines[#lines + 1] = " "
    lines[#lines + 1] = GREY .. "The per-hour figure is a rough guess, only for comparing farms. The Kills & Loot window (right-click the minimap button) measures your real gold per hour.|r"
    return lines
end

local function buildFarm()
    local rows = {}
    local c = ns.Char()
    local farms = ns.FarmList()
    if not ns.R().lastScan then
        Tx(rows, "No prices yet", "The farms below are sorted properly once I've read the auction house.")
    end
    Hd(rows, "Good for " .. (c.name or "you") .. " right now")
    local any = false
    for _, f in ipairs(farms) do
        if f.ok then
            any = true
            rows[#rows + 1] = { id = f.items[1] and f.items[1].id, title = f.farm.title, sub = f.where,
                tipTitle = f.farm.title, tip = function() return farmTip(f) end,
                r1 = f.perHour and ("~" .. ns.Money(f.perHour)) or (GREY .. "no prices|r"),
                r2 = "per hour (rough guess)", onClick = false }
        end
    end
    if not any then
        Tx(rows, nil, "Nothing matches this character's level and professions yet. See the list below for what opens up next.")
    end
    Hd(rows, "Not yet - needs a higher level or another profession")
    for _, f in ipairs(farms) do
        if not f.ok then
            rows[#rows + 1] = { id = f.items[1] and f.items[1].id, title = f.farm.title, dim = true,
                sub = (f.need or "") .. (f.alt and ("  -  " .. f.alt .. " could do this") or ""),
                tipTitle = f.farm.title, tip = function() return farmTip(f) end,
                r1 = f.perHour and (GREY .. "~|r" .. ns.Money(f.perHour)) or "", r2 = "per hour (rough guess)" }
        end
    end
    if #ns.db.sessions > 0 then
        Hd(rows, "Your measured farming sessions")
        for _, s in ipairs(ns.db.sessions) do
            local top = {}
            for _, t in ipairs(s.top or {}) do
                top[#top + 1] = t[2] .. " " .. ns.ItemName(t[1])
            end
            rows[#rows + 1] = { icon = COIN, id = s.top and s.top[1] and s.top[1][1],
                title = (s.zone or "?") .. GREY .. "  " .. date("%d %b", s.t or 0) .. "  " .. (s.who or "") .. "|r",
                sub = #top > 0 and table.concat(top, ", ") or "",
                r1 = ns.Money((s.v or 0) / max(1, s.secs or 1) * 3600) .. " /hr",
                r2 = ns.Money(s.v or 0) .. " in " .. ns.Duration(s.secs), onClick = false }
        end
    end
    return rows
end

----------------------------------------------------------------------
-- Tab: Bags
----------------------------------------------------------------------

local function sellButton(id)
    return { label = "Sell", onClick = function() ns.OpenSell(id) end }
end

local function buildBags()
    local rows = {}
    local bag = ns.BagAdvice()
    if not ns.R().lastScan then
        Tx(rows, "No prices yet", "Visit an auctioneer and I'll tell you what everything in your bags is worth.")
        return rows
    end
    if #bag.undercut > 0 then
        Hd(rows, "Your auctions that have been undercut")
        for _, u in ipairs(bag.undercut) do
            rows[#rows + 1] = { id = u.id, title = u.count .. " x " .. ns.ItemText(u.id),
                sub = "You listed at " .. ns.Money(u.mine) .. GREY .. " each, the lowest is now |r" .. ns.Money(u.price)
                    .. GREY .. ". Cancel and relist a little under that if you want it to sell.",
                r1 = ns.Money(u.price), r2 = "lowest price now" }
        end
    end
    Hd(rows, "Put these on the auction house", #bag.ah > 0 and (ns.Money(bag.ahTotal) .. " after the cut") or nil)
    if #bag.ah == 0 then
        Tx(rows, nil, "Nothing in your bags is worth auctioning right now.")
    else
        Tx(rows, nil, ns.ahOpen
            and "Press Sell on a row: I check the price right now, pick one that sells without losing you money, and show it to you before anything is posted."
            or "At an auctioneer, the Sell button on each row prices and posts it for you in two clicks.")
    end
    for _, b in ipairs(bag.ah) do
        local speed = ns.SaleText and ns.SaleText(b.id, true)
        local sub = "Lowest price " .. ns.Money(b.price) .. GREY .. " each  -  " .. (b.listed or 0) .. " listed"
            .. (speed and ("  -  |r" .. speed .. GREY) or "")
        if b.craft then
            sub = sub .. "  -  |r|cff40e060worth more made into " .. ns.ItemName(b.craft.rec.out) .. "|r" .. GREY
        else
            sub = sub .. "  -  a vendor would pay only |r" .. ns.Money(b.vendor * b.count)
        end
        local tip = { "Selling these at the lowest current price earns you " .. ns.Money(b.total)
            .. " after the auction house's 5%.",
            "List yours a copper or two under the lowest price so they sell first." }
        local saleLine = ns.SaleText and ns.SaleText(b.id)
        if saleLine then
            tip[#tip + 1] = " "
            tip[#tip + 1] = "Auction house: " .. saleLine .. "."
        end
        if b.craft then
            tip[#tip + 1] = " "
            tip[#tip + 1] = "Or use them: making " .. ns.ItemName(b.craft.rec.out) .. " is profitable right now ("
                .. ns.Profit(b.craft.profit) .. " each)."
        end
        rows[#rows + 1] = { id = b.id, title = b.count .. " x " .. ns.ItemText(b.id), sub = sub,
            tipTitle = ns.ItemName(b.id), tip = tip, r1 = ns.Money(b.total), r2 = "for all, after the cut",
            btn = sellButton(b.id) }
    end
    if #bag.unlisted > 0 then
        Hd(rows, "Nobody is selling these - you'd be the only seller")
        for _, b in ipairs(bag.unlisted) do
            rows[#rows + 1] = { id = b.id, title = b.count .. " x " .. ns.ItemText(b.id),
                sub = b.last and ("Last seen at " .. ns.Money(b.last) .. GREY .. " each. With no competition you can ask a bit more.")
                    or "Never seen for sale. Try one at a price you'd be happy with.",
                r1 = b.last and ns.Money(b.last) or "", r2 = b.last and "last price seen" or "",
                btn = sellButton(b.id) }
        end
    end
    if #bag.vendor > 0 then
        Hd(rows, "Just sell these to a vendor", ns.Money(bag.vendorTotal))
        for _, b in ipairs(bag.vendor) do
            rows[#rows + 1] = { id = b.id, title = b.count .. " x " .. ns.ItemText(b.id),
                sub = "A vendor pays " .. ns.Money(b.vendor) .. GREY .. " each"
                    .. (b.speed == "rarely" and "  -  listed for more at auction, but hardly any sell"
                        or (b.price and "  -  the auction house wouldn't beat that" or "")),
                r1 = ns.Money(b.total), r2 = "at any vendor" }
        end
    end
    return rows
end

----------------------------------------------------------------------
-- Tab: Deals
----------------------------------------------------------------------

local function buildDeals()
    local rows = {}
    if not ns.R().lastScan then
        Tx(rows, "No prices yet", "Deals appear here after your first auction house scan.")
        return rows
    end

    Tx(rows, nil, "Only auctions you can buy outright are shown (never bid-only ones), and only when the profit is at least "
        .. ns.Money(ns.db.opts.dealMin or 500) .. ". Change that amount under Settings (top right).")
    local checking = ns.VerifyPending and ns.VerifyPending() or 0
    if checking > 0 then
        Tx(rows, nil, "|cffffd100Still checking " .. plural(checking, "possible deal")
            .. "|r to make sure they aren't bid-only. Keep the auction window open; they appear here as they pass.")
    else
        local waiting = #ns.PendingDeals()
        if waiting > 0 then
            Tx(rows, nil, GREY .. plural(waiting, "possible deal") .. " on gear couldn't be confirmed as buyouts yet. They're checked automatically the next time you scan at an auctioneer.|r")
        end
    end

    local flips = ns.VendorFlips()
    Hd(rows, "Buy at auction, sell to a vendor - no risk", #flips > 0 and plural(#flips, "item") or nil)
    if #flips == 0 then
        Tx(rows, nil,
            "None right now. These appear when someone lists an item for less than a shopkeeper would pay for it. I check again every scan.")
    else
        Tx(rows, nil,
            "Each of these is listed for less than any vendor pays. Buy it, sell it to a vendor, keep the difference. Click a row while the auction window is open to search for it.")
    end
    for i = 1, min(40, #flips) do
        local f = flips[i]
        rows[#rows + 1] = { id = f.id, title = ns.ItemText(f.id), tipTitle = ns.ItemName(f.id),
            sub = "Listed for " .. ns.Money(f.price) .. GREY .. "  -  any vendor pays |r" .. ns.Money(f.vendor) .. GREY
                .. "  -  " .. f.listed .. " listed",
            tip = { "Buy it for " .. ns.Money(f.price) .. " and sell it to any vendor for " .. ns.Money(f.vendor) .. ".",
                "This is a buyout price, not a bid.",
                "The price shown is the cheapest one; later ones may cost more, so check before buying several." },
            r1 = ns.Profit(f.profit), r2 = "each, guaranteed" }
    end

    local deals = ns.VendorDeals()
    Hd(rows, "Buy from a vendor, sell at auction", deals.sure > 0 and plural(deals.sure, "item") or nil)
    if deals.sure == 0 and #deals > 0 then
        Tx(rows, nil, "None proven yet. The ones below are only LISTED for more - with no sign anyone pays that, since anybody can buy them from the vendor.")
    end
    if #deals == 0 then
        Tx(rows, nil,
            "Nothing yet. Open any vendor while this addon is running and I'll check everything they sell against auction prices. Recipe and supply vendors far from the cities are the best ones to try.")
    end
    local unprovenShown = false
    for i = 1, min(40, #deals) do
        local v = deals[i]
        if not v.sure and not unprovenShown then
            unprovenShown = true
            Hd(rows, "Unproven - listed for more, but nobody may be buying", plural(#deals - deals.sure, "item"))
            Tx(rows, nil, GREY .. "Anyone can buy these from a vendor, so a high asking price on the auction house means little. Once the tracker app has a day or two of sale data, the ones that really sell move up to the list above.|r")
        end
        local tip = { "Buy it from the vendor and list it on the auction house.",
            (v.listed or 0) .. " listed right now. With few sellers, don't flood the market - list one or two." }
        if v.how == "sold" then
            tip[#tip + 1] = "These have actually been selling for about " .. ns.Money(v.net / (1 - CUT)) .. " each."
        elseif v.limited then
            tip[#tip + 1] = "This vendor only stocks a few at a time, which is exactly why other players pay extra."
        else
            tip[#tip + 1] = "|cffff7070Not proven:|r that's only what people are asking. Try ONE before buying more."
        end
        rows[#rows + 1] = { id = v.id, title = ns.ItemText(v.id), tipTitle = ns.ItemName(v.id), dim = not v.sure,
            sub = "Costs " .. ns.Money(v.buy) .. GREY .. " from " .. (v.npc or "a vendor")
                .. (v.zone and v.zone ~= "" and (" in " .. v.zone) or "") .. (v.limited and "  -  limited stock" or "")
                .. (v.how == "sold" and "  -  has sold for |r" or "  -  listed at |r") .. ns.Money(v.price),
            tip = tip, r1 = ns.Profit(v.profit), r2 = v.sure and "each, after the cut" or "if it sells" }
    end

    local bargains = ns.Bargains()
    Hd(rows, "Much cheaper than usual", #bargains > 0 and plural(#bargains, "item") or nil)
    if #bargains == 0 then
        Tx(rows, nil,
            "Nothing yet. I need about three days of scans to learn what things usually cost; after that, anything listed at 60% of its usual price or less shows up here.")
    else
        Tx(rows, nil,
            "These could be bought and relisted at the usual price. This is a gamble, not a sure thing - the price may simply be falling. Start small.")
    end
    for i = 1, min(30, #bargains) do
        local b = bargains[i]
        rows[#rows + 1] = { id = b.id, title = ns.ItemText(b.id), tipTitle = ns.ItemName(b.id),
            sub = "Now " .. ns.Money(b.price) .. GREY .. "  -  usually |r" .. ns.Money(b.usual) .. GREY .. "  ("
                .. b.days .. " days of prices)  -  " .. b.listed .. " listed",
            tip = { "If the price returns to its usual level, buying now and relisting would earn about "
                .. ns.Money(b.profit) .. " each after the cut.",
                "Risk: prices on a new realm often fall for good as more people reach higher levels." },
            r1 = ns.Profit(b.profit), r2 = "each, if it recovers" }
    end
    return rows
end

----------------------------------------------------------------------
-- Tab: Routes
----------------------------------------------------------------------

UI.routeKinds = { ore = true, herb = true, fish = false }

local function selectedRouteMap()
    if UI.routeMap and ns.db.nodes[UI.routeMap] then
        return UI.routeMap
    end
    local here = ns.PlayerMapPos()
    if here and ns.db.nodes[here] then
        return here
    end
    local zones = ns.NodeZones()
    return zones[1] and zones[1].map or nil
end

local function buildRoutes()
    local rows = {}
    local zones = ns.NodeZones()
    if #zones == 0 then
        Tx(rows, "No spots recorded yet",
            "Just play: every ore vein you mine, herb you pick and place you catch a fish is remembered with its exact position. After a lap or two of a zone, come back here and press Build route.\n\nFarm (next to Routes above) tells you which zones to head for.")
        return rows
    end
    local sel = selectedRouteMap()
    local r = ns.route
    if r then
        Tx(rows, "Following a route in " .. ns.MapName(r.map), plural(r.n, "stop")
            .. ". Follow the arrow on your screen; it moves to the next stop when you arrive. Press Skip on the arrow if a spot is empty.")
    else
        Tx(rows, nil,
            "Pick a zone, choose what to include with the buttons above, then press Build route. I'll draw the shortest loop through your spots and point you round it.")
    end
    Hd(rows, "Zones you've gathered in")
    for _, z in ipairs(zones) do
        local parts = {}
        if z.ore > 0 then parts[#parts + 1] = z.ore .. " ore" end
        if z.herb > 0 then parts[#parts + 1] = z.herb .. " herb" end
        if z.fish > 0 then parts[#parts + 1] = z.fish .. " fishing" end
        local mapID = z.map
        rows[#rows + 1] = { icon = COIN,
            title = (mapID == sel and "|cffffd100> " or "") .. z.name .. (mapID == sel and "|r" or ""),
            sub = table.concat(parts, ", "), r1 = plural(z.total, "spot"),
            onClick = function()
                UI.routeMap = mapID
                ns.RefreshUI(true)
            end }
    end
    return rows
end

----------------------------------------------------------------------
-- Tab: Tips
----------------------------------------------------------------------

local function optionRow(rows, key, text)
    local on = ns.db.opts[key]
    rows[#rows + 1] = { icon = COIN, title = (on and "|cff40e060[on]|r  " or "|cffff7070[off]|r  ") .. text,
        sub = "Click to turn " .. (on and "off" or "on"),
        onClick = function()
            ns.db.opts[key] = not ns.db.opts[key]
            ns.RefreshUI(true)
        end }
end

local DEAL_STEPS = { 100, 500, 2500, 10000 }

local function dealMinRow(rows)
    local cur = ns.db.opts.dealMin or 500
    rows[#rows + 1] = { icon = COIN, title = "Smallest profit worth showing on the Buy tab: " .. ns.Money(cur),
        sub = "Click to change (1s, 5s, 25s or 1g)",
        onClick = function()
            local nextStep = DEAL_STEPS[1]
            for i, v in ipairs(DEAL_STEPS) do
                if v == cur then
                    nextStep = DEAL_STEPS[(i % #DEAL_STEPS) + 1]
                end
            end
            ns.db.opts.dealMin = nextStep
            ns.Fire("PLAYER_CHANGED")
            ns.RefreshUI(true)
        end }
end

local AGE_STEPS = { 300, 900, 1800, 3600 }

local function autoAgeRow(rows)
    local cur = ns.db.opts.autoAge or 300
    rows[#rows + 1] = { icon = COIN,
        title = "Rescan when I open the auction house if prices are older than: " .. floor(cur / 60) .. " minutes",
        sub = "Click to change (5, 15, 30 or 60 minutes). The fast scan itself is limited by the game to once every 15 minutes.",
        onClick = function()
            local nextStep = AGE_STEPS[1]
            for i, v in ipairs(AGE_STEPS) do
                if v == cur then
                    nextStep = AGE_STEPS[(i % #AGE_STEPS) + 1]
                end
            end
            ns.db.opts.autoAge = nextStep
            ns.RefreshUI(true)
        end }
end

local function buildTips()
    local rows = {}
    Hd(rows, "Settings")
    optionRow(rows, "autoScan", "Read prices automatically when I open the auction house")
    autoAgeRow(rows)
    optionRow(rows, "fastScan", "Fast scan: download the whole auction house at once (the game allows it every 15 minutes)")
    dealMinRow(rows)
    optionRow(rows, "tooltip", "Show auction prices when I hover over an item")
    optionRow(rows, "waypoint", "Use the game's map waypoint for the next stop on a route")
    Hd(rows, "Sale rates")
    Tx(rows, nil, ns.MarketStatus and ns.MarketStatus() or "")
    local have = ns.AccountProfessions()
    Hd(rows, "Ideas for your professions")
    for _, tip in ipairs(ns.TIPS) do
        if not tip.prof or have[tip.prof] then
            Tx(rows, tip.title .. (tip.prof and (GREY .. "  -  " .. tip.prof .. "|r") or ""), tip.text)
            for _, entry in ipairs(tip.items or {}) do
                local id = ns.Resolve(entry)
                if id then
                    local price, listed = ns.AHPrice(id)
                    local last = ns.LastPrice(id)
                    rows[#rows + 1] = { id = id, title = ns.ItemText(id),
                        sub = price and (listed .. " listed") or (last and "None for sale right now" or "Never seen for sale"),
                        r1 = price and ns.Money(price) or (last and (GREY .. "was|r " .. ns.Money(last)) or ""),
                        r2 = price and "lowest price" or "" }
                end
            end
        end
    end
    Hd(rows, "What the words mean")
    for _, g in ipairs(ns.GLOSSARY) do
        Tx(rows, g[1], g[2])
    end
    return rows
end

----------------------------------------------------------------------
-- Tabs and their toolbars
----------------------------------------------------------------------

-- Make = Craft, Farm and Routes, picked with a switch at the top.
local MAKE_MODES = { { "craft", "Craft", buildCraft }, { "farm", "Farm", buildFarm }, { "routes", "Routes", buildRoutes } }

local function makeMode()
    local m = UI.makeMode
    return (m == "farm" or m == "routes") and m or "craft"
end

local function buildMake()
    for _, m in ipairs(MAKE_MODES) do
        if m[1] == makeMode() then
            return m[3]()
        end
    end
end

local function makeToolbar()
    local bar = {}
    for _, m in ipairs(MAKE_MODES) do
        local key = m[1]
        bar[#bar + 1] = { label = m[2], width = 68, on = makeMode() == key, onClick = function()
            UI.makeMode = key
            ns.RefreshUI()
        end }
    end
    bar[#bar].gap = 24
    local mode = makeMode()
    if mode == "farm" then
        bar[#bar + 1] = { label = "Kills & Loot window", width = 150, on = ns.TrackerWindowShown and ns.TrackerWindowShown(),
            onClick = function() ns.ToggleTrackerWindow() end }
        bar.text = "Measures your real gold per hour."
    elseif mode == "routes" then
        local k = UI.routeKinds
        local function toggle(kind)
            return function()
                k[kind] = not k[kind]
                ns.RefreshUI(true)
            end
        end
        for _, b in ipairs({
            { label = "Ore", width = 56, on = k.ore, onClick = toggle("ore") },
            { label = "Herbs", width = 60, on = k.herb, onClick = toggle("herb") },
            { label = "Fishing", width = 66, on = k.fish, onClick = toggle("fish") },
            { label = "Build route", width = 96, onClick = function()
                local mapID = selectedRouteMap()
                if not mapID then
                    ns.Print("no spots recorded yet - go gather something first.")
                    return
                end
                local route, why = ns.BuildRoute(mapID, { ore = k.ore, herb = k.herb, fish = k.fish })
                if not route then
                    ns.Print(why)
                else
                    ns.Print("route ready: " .. route.n .. " stops in " .. ns.MapName(mapID) .. ". Follow the arrow.")
                end
                ns.RefreshUI(true)
            end },
        }) do
            bar[#bar + 1] = b
        end
        if ns.route then
            bar[#bar + 1] = { label = "Stop route", width = 86, onClick = function()
                ns.StopRoute()
                ns.RefreshUI(true)
            end }
        end
    end
    return bar
end

local TABS = {
    { key = "todo", label = "To do", build = buildTodo },
    { key = "sell", label = "Sell", build = buildBags },
    { key = "buy", label = "Buy", build = buildDeals },
    { key = "make", label = "Make", build = buildMake, toolbar = makeToolbar,
        plot = function() return makeMode() == "routes" end },
}
-- Opened with the Settings button at the top right, not a tab of its own.
local SETTINGS = { key = "settings", label = "Settings", build = buildTips }

-- Older names for the tabs, still used in a few places.
local TAB_ALIAS = { today = { "todo" }, bags = { "sell" }, deals = { "buy" }, tips = { "settings" },
    craft = { "make", "craft" }, farm = { "make", "farm" }, routes = { "make", "routes" } }

----------------------------------------------------------------------
-- The main window
----------------------------------------------------------------------

local main

local function refreshFooter()
    if not main or not main:IsShown() then
        return
    end
    local text = ns.ScanStatus()
    main.status:SetText(text)
    main.scanButton:SetDisabled(not ns.ahOpen or ns.scan.active)
    main.scanButton:SetLabel(ns.scan.active and "Scanning..." or "Scan now")
    main.money:SetText(ns.Money(ns.Char().money or 0))
end

local function refreshToolbar(tab)
    local bar = main.toolbar
    local spec = tab.toolbar and tab.toolbar() or nil
    for _, b in ipairs(bar.buttons) do
        b:Hide()
    end
    if not spec then
        bar:Hide()
        return 0
    end
    bar:Show()
    local x = 0
    for i, s in ipairs(spec) do
        local b = bar.buttons[i]
        if not b then
            b = button(bar, "", 80, 22)
            bar.buttons[i] = b
        end
        b:SetSize(s.width or 80, 22)
        b:SetLabel(s.label)
        b:SetOn(s.on)
        b:SetDisabled(false)
        b.onClick = s.onClick
        b:ClearAllPoints()
        b:SetPoint("LEFT", bar, "LEFT", x, 0)
        b:Show()
        x = x + (s.width or 80) + 6 + (s.gap or 0)
    end
    bar.text:ClearAllPoints()
    bar.text:SetPoint("LEFT", bar, "LEFT", x + 6, 0)
    bar.text:SetText(spec.text or "")
    return 30
end

local function drawPlot()
    if not main or not main.plot:IsShown() then
        return
    end
    local mapID = selectedRouteMap()
    local w, h = main.plot:GetWidth(), main.plot:GetHeight()
    main.plotTitle:SetText(mapID and ns.MapName(mapID) or "")
    main.plotter:Draw(mapID, w, h, 6, UI.routeKinds, true)
end

function ns.RefreshUI(keepScroll)
    if not main or not main:IsShown() then
        return
    end
    local tab = UI.tab == "settings" and SETTINGS or TABS[1]
    for _, t in ipairs(TABS) do
        if t.key == UI.tab then
            tab = t
        end
        t.button:SetOn(t.key == UI.tab)
    end
    main.settingsButton:SetOn(tab == SETTINGS)
    local barH = refreshToolbar(tab)
    local clip = main.list.clip
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", main, "TOPLEFT", 12, -(72 + barH))
    local plot = tab.plot
    if type(plot) == "function" then
        plot = plot()
    end
    if plot then
        clip:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -(12 + 410), 40)
        main.list.viewW = W - 24 - 410
        main.plot:Show()
    else
        clip:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -12, 40)
        main.list.viewW = W - 24
        main.plot:Hide()
    end
    main.list.viewH = H - (72 + barH) - 40
    local ok, rows = pcall(tab.build)
    if not ok then
        ns.Err("tab-" .. tab.key, rows)
        rows = { { type = "text", title = "Something went wrong on this tab",
            text = "The other tabs still work. Type /gold debug to see the details." } }
    end
    main.list:SetRows(rows, keepScroll)
    refreshFooter()
    drawPlot()
end

function ns.ShowTab(key)
    local alias = TAB_ALIAS[key]
    if alias then
        key = alias[1]
        UI.makeMode = alias[2] or UI.makeMode
    end
    UI.tab = key
    if main and main:IsShown() then
        ns.RefreshUI()
    end
end

local function createMain()
    local f = CreateFrame("Frame", "ForeverGoldFrame", UIParent)
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    skin(f, 0.055, 0.055, 0.07, 0.97)
    if UISpecialFrames then
        table.insert(UISpecialFrames, "ForeverGoldFrame")
    end

    local titleIcon = f:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(22, 22)
    titleIcon:SetPoint("TOPLEFT", 12, -9)
    setIcon(titleIcon, COIN)
    local title = label(f, "GameFontNormalLarge", "Forever Gold")
    title:SetPoint("LEFT", titleIcon, "RIGHT", 8, 0)
    f.money = label(f, "GameFontHighlight")
    f.money:SetPoint("TOPRIGHT", -44, -13)
    local close = button(f, "X", 24, 22, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)

    local x = 12
    for _, t in ipairs(TABS) do
        local key = t.key
        local b = button(f, t.label, 92, 24, function() ns.ShowTab(key) end)
        b:SetPoint("TOPLEFT", x, -40)
        t.button = b
        x = x + 96
    end
    f.settingsButton = button(f, "Settings", 80, 24, function()
        ns.ShowTab(UI.tab == "settings" and "todo" or "settings")
    end)
    f.settingsButton:SetPoint("TOPRIGHT", -12, -40)

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 12, -70)
    bar:SetPoint("TOPRIGHT", -12, -70)
    bar:SetHeight(26)
    bar.buttons = {}
    bar.text = label(bar, "GameFontHighlightSmall")
    f.toolbar = bar

    f.list = createList(f)

    local plot = CreateFrame("Frame", nil, f)
    plot:SetSize(396, 264)
    plot:SetPoint("TOPRIGHT", -12, -128)
    skin(plot, 0.02, 0.03, 0.04, 1, 0.3, 0.3, 0.3, 1)
    f.plot = plot
    f.plotter = ns.NewPlotter(plot)
    f.plotTitle = label(f, "GameFontNormal")
    f.plotTitle:SetPoint("BOTTOMLEFT", plot, "TOPLEFT", 0, 6)
    local legend = label(plot, "GameFontDisableSmall",
        "|cfffa9e33ore|r   |cff59e659herbs|r   |cff59a6fffishing|r   |cffff33e6you|r   |cffffd100route|r")
    legend:SetPoint("TOPLEFT", plot, "BOTTOMLEFT", 0, -6)
    local forget = button(plot, "Forget this zone's spots", 170, 22, function()
        local mapID = selectedRouteMap()
        if mapID then
            ns.ForgetZone(mapID)
            UI.routeMap = nil
            ns.RefreshUI()
        end
    end)
    forget:SetPoint("TOPRIGHT", plot, "BOTTOMRIGHT", 0, -24)
    local since = 0
    plot:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since > 1 then
            since = 0
            ns.Guard("plot", drawPlot)()
        end
    end)

    f.status = label(f, "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", 14, 14)
    f.scanButton = button(f, "Scan now", 100, 24, function() ns.StartScan() end)
    f.scanButton:SetPoint("BOTTOMRIGHT", -12, 9)
    f.scanButton:SetScript("OnEnter", function(self)
        if not ns.ahOpen and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Open the auction window at an auctioneer first.", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    f.scanButton:SetScript("OnLeave", rowLeave)

    f:SetScript("OnShow", function() ns.Guard("ui", ns.RefreshUI)() end)
    f:Hide()
    return f
end

function ns.ToggleUI()
    if not main then
        main = createMain()
        UI.tab = UI.tab or "todo"
    end
    if main:IsShown() then
        main:Hide()
    else
        main:Show()
    end
end

----------------------------------------------------------------------
-- The on-screen guide: route arrow + session timer
----------------------------------------------------------------------

local hud

local function drawArrow(angle)
    local a = hud.arrow
    if not angle then
        for _, l in ipairs(a.lines) do l:Hide() end
        return
    end
    -- Straight ahead is up; a positive angle means "turn left".
    local phi = angle + math.pi / 2
    local R = 15
    local tx, ty = math.cos(phi) * R, math.sin(phi) * R
    a.lines[1]:SetStartPoint("CENTER", a, -tx, -ty)
    a.lines[1]:SetEndPoint("CENTER", a, tx, ty)
    for i, off in ipairs({ 2.55, -2.55 }) do
        local l = a.lines[i + 1]
        l:SetStartPoint("CENTER", a, tx, ty)
        l:SetEndPoint("CENTER", a, tx + math.cos(phi + off) * 11, ty + math.sin(phi + off) * 11)
    end
    for _, l in ipairs(a.lines) do l:Show() end
end

-- (The kill and loot tracker has its own window now - see TrackerUI.lua.)
local function updateHUD()
    local st = ns.RouteStatus()
    if not st then
        hud:Hide()
        return
    end
    do
        if st.onMap then
            hud.line1:SetText(st.name)
            hud.line2:SetText((st.yards and (floor(st.yards) .. " yards   ") or "") .. "stop " .. st.index .. " of " .. st.count)
            drawArrow(st.angle)
        else
            hud.line1:SetText("Route in " .. st.zone)
            hud.line2:SetText("Travel there to begin")
            drawArrow(nil)
        end
        hud.skip:Show()
        hud.stop:Show()
    end
    hud.line3:SetText("")
end

local function createHUD()
    local f = CreateFrame("Frame", "ForeverGoldGuide", UIParent)
    f:SetSize(270, 68)
    f:SetPoint("TOP", UIParent, "TOP", 0, -150)
    f:SetFrameStrata("MEDIUM")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    skin(f, 0.04, 0.04, 0.05, 0.78)

    local arrow = CreateFrame("Frame", nil, f)
    arrow:SetSize(44, 44)
    arrow:SetPoint("LEFT", 6, 6)
    arrow.lines = {}
    for i = 1, 3 do
        local l = arrow:CreateLine(nil, "OVERLAY")
        l:SetColorTexture(1, 0.82, 0, 1)
        l:SetThickness(3)
        arrow.lines[i] = l
    end
    f.arrow = arrow

    f.line1 = label(f, "GameFontNormal")
    f.line1:SetPoint("TOPLEFT", 56, -7)
    f.line1:SetWidth(150)
    f.line1:SetWordWrap(false)
    f.line2 = label(f, "GameFontHighlightSmall")
    f.line2:SetPoint("TOPLEFT", 56, -24)
    f.line3 = label(f, "GameFontHighlightSmall")
    f.line3:SetPoint("BOTTOMLEFT", 10, 7)

    f.skip = button(f, "Skip", 40, 18, function() ns.NextStop() end)
    f.skip:SetPoint("TOPRIGHT", -6, -6)
    f.stop = button(f, "Stop", 40, 18, function() ns.StopRoute() end)
    f.stop:SetPoint("TOPRIGHT", -6, -27)

    local since = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since > 0.08 then
            since = 0
            local ok, err = pcall(updateHUD)
            if not ok then
                ns.Err("guide", err)
                f:Hide()
            end
        end
    end)
    return f
end

local function showHUD()
    if not ns.route then
        return
    end
    if not hud then
        hud = createHUD()
    end
    hud:Show()
end

----------------------------------------------------------------------
-- The Sell panel: the price, the reasoning, and the one Post button
----------------------------------------------------------------------

local sellPanel

local function createSellPanel()
    local f = CreateFrame("Frame", "ForeverGoldSellFrame", UIParent)
    f:SetSize(440, 340)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    skin(f, 0.05, 0.05, 0.065, 0.99, 1, 0.82, 0, 0.9)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(34, 34)
    f.icon:SetPoint("TOPLEFT", 14, -14)
    f.title = label(f, "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 58, -14)
    f.title:SetWidth(360)
    f.title:SetWordWrap(false)
    f.have = label(f, "GameFontHighlightSmall")
    f.have:SetPoint("TOPLEFT", 58, -34)

    f.body = label(f, "GameFontHighlightSmall")
    f.body:SetPoint("TOPLEFT", 16, -62)
    f.body:SetWidth(408)
    f.body:SetWordWrap(true)
    f.body:SetJustifyV("TOP")

    f.controls = CreateFrame("Frame", nil, f)
    f.controls:SetSize(408, 24)
    f.controls:SetPoint("BOTTOMLEFT", 16, 112)
    local c = f.controls
    c.qtyLabel = label(c, "GameFontHighlightSmall", "How many:")
    c.qtyLabel:SetPoint("LEFT", 0, 0)
    c.minus = button(c, "-", 24, 22, function()
        local job = ns.SellJob()
        if job then ns.SellSetQuantity(job.qty - (job.commodity and 5 or 1)) end
    end)
    c.minus:SetPoint("LEFT", 70, 0)
    c.qty = label(c, "GameFontNormal")
    c.qty:SetPoint("LEFT", 100, 0)
    c.qty:SetWidth(40)
    c.qty:SetJustifyH("CENTER")
    c.plus = button(c, "+", 24, 22, function()
        local job = ns.SellJob()
        if job then ns.SellSetQuantity(job.qty + (job.commodity and 5 or 1)) end
    end)
    c.plus:SetPoint("LEFT", 146, 0)
    c.all = button(c, "All", 40, 22, function()
        local job = ns.SellJob()
        if job then ns.SellSetQuantity(job.have) end
    end)
    c.all:SetPoint("LEFT", 176, 0)
    c.duration = button(c, "", 150, 22, function() ns.SellCycleDuration() end)
    c.duration:SetPoint("RIGHT", 0, 0)

    f.offer = label(f, "GameFontNormalLarge")
    f.offer:SetPoint("BOTTOMLEFT", 16, 80)
    f.totals = label(f, "GameFontHighlightSmall")
    f.totals:SetPoint("BOTTOMLEFT", 16, 50)
    f.totals:SetWidth(408)
    f.totals:SetWordWrap(true)

    f.post = button(f, "Post", 130, 28, function()
        local job = ns.SellJob()
        if job and job.state == "error" then
            ns.SellRecheck()
        else
            ns.SellPost()
        end
    end)
    f.post:SetPoint("BOTTOMRIGHT", -14, 14)
    f.close = button(f, "Cancel", 90, 28, function() ns.CloseSell() end)
    f.close:SetPoint("BOTTOMLEFT", 14, 14)
    return f
end

local function refreshSellPanel()
    local job = ns.SellJob()
    if not job then
        if sellPanel then
            sellPanel:Hide()
        end
        return
    end
    if not sellPanel then
        sellPanel = createSellPanel()
    end
    local f = sellPanel
    f:Show()
    setIcon(f.icon, ns.Icon(job.id))
    f.title:SetText(ns.ItemText(job.id))
    f.have:SetText(GREY .. "You have " .. job.have .. " to sell|r")

    local d = job.decision
    local parts = ns.SellExplain()
    if job.state == "done" then
        local a = job.args
        parts = { "|cff40e060Listed.|r " .. a[3] .. " x at " .. ns.Money(a[4])
            .. " each. The gold arrives in your mailbox when they sell." }
        if job.have > a[3] then
            parts[#parts + 1] = "You have " .. (job.have - a[3])
                .. " left. Press Sell on the Sell tab again for another batch - small batches attract less undercutting."
        end
    end
    if job.message then
        parts[#parts + 1] = "|cffffd100" .. job.message .. "|r"
    end
    f.body:SetText(table.concat(parts, "\n\n"))

    local canPost = (job.state == "ready" and d and d.ok) and true or false
    f.controls:SetShown(canPost)
    if canPost then
        f.controls.qty:SetText(tostring(job.qty))
        f.controls.duration:SetLabel("Lasts: " .. ns.SellDurationLabel(job.duration))
        f.offer:SetText(job.qty .. " x at " .. ns.Money(d.price) .. " each")
        local deposit, receive = ns.SellTotals()
        local text = "You receive " .. ns.Money(receive) .. GREY .. " if they all sell (after the 5% cut).|r"
        if deposit then
            text = text .. "\n" .. GREY .. "Deposit now: |r" .. ns.Money(deposit) .. GREY
                .. " - returned when it sells, lost if it expires.|r"
        end
        f.totals:SetText(text)
    else
        f.offer:SetText("")
        f.totals:SetText("")
    end

    f.post:Show()
    f.close:SetLabel("Cancel")
    if job.state == "checking" then
        f.post:SetLabel("Checking...")
        f.post:SetDisabled(true)
    elseif job.state == "ready" then
        f.post:SetLabel("Post")
        f.post:SetDisabled(not canPost)
        if not canPost then
            f.close:SetLabel("Close")
        end
    elseif job.state == "confirm" then
        f.post:SetLabel("Confirm")
        f.post:SetDisabled(false)
    elseif job.state == "posting" then
        f.post:SetLabel("Posting...")
        f.post:SetDisabled(true)
    elseif job.state == "done" then
        f.post:Hide()
        f.close:SetLabel("Done")
    else
        f.post:SetLabel("Check again")
        f.post:SetDisabled(false)
    end
end

----------------------------------------------------------------------
-- The strip above the auction window
----------------------------------------------------------------------

local ahPanel

local function refreshAHPanel()
    if not ahPanel then
        return
    end
    local text, active = ns.ScanStatus()
    ahPanel.text:SetText(text)
    ahPanel.scan:SetDisabled(active)
    ahPanel.scan:SetLabel(active and "Scanning..." or "Scan prices")
end

local function createAHPanel()
    if ahPanel then
        ahPanel:Show()
        refreshAHPanel()
        return
    end
    local parent = AuctionHouseFrame or UIParent
    local p = CreateFrame("Frame", "ForeverGoldAuctionStrip", parent)
    p:SetSize(520, 32)
    if AuctionHouseFrame then
        p:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "TOPRIGHT", 0, 3)
    else
        p:SetPoint("TOP", UIParent, "TOP", 0, -70)
    end
    p:SetFrameStrata("HIGH")
    skin(p, 0.055, 0.055, 0.07, 0.95)
    local icon = p:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", 6, 0)
    setIcon(icon, COIN)
    p.text = label(p, "GameFontHighlightSmall")
    p.text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    p.text:SetWidth(290)
    p.text:SetWordWrap(false)
    p.open = button(p, "Advice", 70, 22, function() ns.ToggleUI() end)
    p.open:SetPoint("RIGHT", -6, 0)
    p.scan = button(p, "Scan prices", 96, 22, function() ns.StartScan() end)
    p.scan:SetPoint("RIGHT", p.open, "LEFT", -6, 0)
    ahPanel = p
    refreshAHPanel()
end

----------------------------------------------------------------------
-- Minimap button
----------------------------------------------------------------------

local function placeMinimapButton(b)
    local angle = math.rad(ns.db.opts.minimapAngle or 215)
    local radius = (Minimap:GetWidth() / 2) + 6
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function createMinimapButton()
    if not Minimap or ns.db.opts.hideMinimap then
        return
    end
    local b = CreateFrame("Button", "ForeverGoldMinimapButton", Minimap)
    b:SetSize(24, 24)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 10)
    skin(b, 0, 0, 0, 1, 1, 0.82, 0, 1)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    setIcon(icon, COIN)
    local hl = tex(b, "HIGHLIGHT", 1, 1, 1, 0.25)
    hl:SetAllPoints()
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ns.db.opts.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
            placeMinimapButton(self)
        end)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    if b.RegisterForClicks then
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    b:SetScript("OnClick", function(_, which)
        if which == "RightButton" and ns.ToggleTrackerWindow then
            ns.ToggleTrackerWindow()
        else
            ns.ToggleUI()
        end
    end)
    b:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("Forever Gold", 1, 0.82, 0)
            GameTooltip:AddLine("Click for gold-making advice. Right-click: Kills & Loot. Drag to move.", 1, 1, 1)
            GameTooltip:AddLine(ns.ScanStatus(), 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", rowLeave)
    placeMinimapButton(b)
end

----------------------------------------------------------------------
-- Item tooltips: vendor price, then the auction price under it
----------------------------------------------------------------------

-- Blizzard's own "Sell Price" line is a tooltip line of type SellPrice. We
-- hide it on the tooltips we add to and show our own Vendor line instead,
-- so the vendor and auction prices sit together.
local SELL_PRICE_LINE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice or 11

local function ourTooltip(tooltip)
    return ns.ready and ns.db.opts.tooltip and tooltip and (tooltip == GameTooltip or tooltip == ItemRefTooltip)
end

-- What Blizzard's hidden line said: the price for the whole stack you're
-- hovering (or nil when the item can't be sold to a vendor).
local function stackSellPrice(data)
    if type(data) ~= "table" or type(data.lines) ~= "table" then
        return nil
    end
    for _, line in ipairs(data.lines) do
        if type(line) == "table" and line.type == SELL_PRICE_LINE and type(line.price) == "number" then
            return line.price, line.maxPrice
        end
    end
    return nil
end

local function addVendorLine(tooltip, id, data)
    local each = ns.VendorSell(id)
    local stack = stackSellPrice(data)
    if not each and not stack then
        return
    end
    if not each or (stack and stack < each) then
        each = stack
    end
    tooltip:AddDoubleLine("|cffffd100Vendor|r", ns.Money(each))
    if stack and stack > each then
        local n = floor(stack / each + 0.5)
        tooltip:AddDoubleLine(GREY .. "  stack of " .. n .. "|r", GREY .. ns.Money(stack) .. "|r")
    end
end

-- How old a price is, coloured by how far to trust it: green under half an
-- hour, yellow up to 6 hours, red after that.
local AGE_FRESH, AGE_OK = 30 * 60, 6 * 3600
function ns.AgeColor(t)
    local age = time() - (t or 0)
    if age < AGE_FRESH then
        return "|cff40ff40"
    elseif age < AGE_OK then
        return "|cffffd100"
    end
    return "|cffff4040"
end
local function agoColored(t)
    return ns.AgeColor(t) .. ns.Ago(t) .. "|r" .. GREY
end

local function addTooltipLines(tooltip, data)
    if not ourTooltip(tooltip) or not tooltip.AddDoubleLine then
        return
    end
    local id = type(data) == "table" and data.id or nil
    if type(id) ~= "number" then
        return
    end
    addVendorLine(tooltip, id, data)
    local R = ns.R()
    local by = R.lastScanBy and (" by " .. R.lastScanBy) or ""
    local price, listed, when = ns.AHPrice(id)
    local last, lastT = ns.LastPrice(id)
    if price then
        tooltip:AddDoubleLine("|cffffd100Auction|r  " .. GREY .. listed .. " listed|r", ns.Money(price))
        tooltip:AddLine(GREY .. "Last scanned " .. agoColored(when) .. by .. "|r")
    elseif last then
        tooltip:AddDoubleLine("|cffffd100Auction|r  " .. GREY .. "none listed now, was|r", ns.Money(last))
        tooltip:AddLine(GREY .. "Last seen " .. agoColored(lastT) .. by .. "|r")
    end
    -- A fresher (or the only) price from another of your characters.
    local sp, sq, st, who = ns.SharedPrice(id)
    if sp and (not (price or last) or (st or 0) > (when or lastT or 0) + 3600) then
        tooltip:AddDoubleLine("|cffffd100Auction|r  " .. GREY .. ((sq or 0) > 0 and (sq .. " listed") or "none listed") .. "|r",
            ns.Money(sp))
        tooltip:AddLine(GREY .. "From " .. who .. "'s scan, " .. agoColored(st) .. "|r")
    end
    local sale = ns.SaleText and ns.SaleText(id)
    if sale then
        tooltip:AddLine(sale)
        local r = ns.SaleRate(id)
        if r and r.avg > 0 then
            tooltip:AddDoubleLine("|cffffd100Has been selling for|r", ns.Money(r.avg))
        end
    elseif not (price or last or sp) and ns.SaleRate then
        local r = ns.SaleRate(id)
        if r and r.min > 0 then
            local info = ns.MarketInfo()
            tooltip:AddDoubleLine("|cffffd100Auction|r  " .. GREY .. r.listed .. " listed|r", ns.Money(r.min))
            tooltip:AddLine(GREY .. "From Blizzard's auction data" .. (info and (", " .. agoColored(info.t)) or "") .. "|r")
        end
    end
    -- Which recipes use it, across every profession in the game.
    local useText, useCount, useMine, useList = ns.RecipeUseSummary(id)
    if useText then
        local shift = IsShiftKeyDown and IsShiftKeyDown()
        tooltip:AddLine("|cffffd100Used in " .. useCount .. (useCount == 1 and " recipe" or " recipes") .. ":|r "
            .. useText .. (shift and "" or (GREY .. "  (Shift for list)|r")), 1, 1, 1, true)
        if useMine > 0 then
            tooltip:AddLine(GREY .. "  your characters know " .. (useMine == useCount and "all of them" or useMine) .. "|r")
        end
        if shift then
            local SHOW = 12
            for i = 1, math.min(SHOW, #useList) do
                local e = useList[i]
                local who = ns.RecipeKnownBy(e.prof, e.name)
                tooltip:AddDoubleLine("  " .. (who and "|cff40e060" or "|cffffffff") .. e.name .. "|r",
                    GREY .. e.prof .. (who and (" - " .. who[1]) or "") .. "|r")
            end
            if #useList > SHOW then
                tooltip:AddLine(GREY .. "  and " .. (#useList - SHOW) .. " more|r")
            end
        end
    end
    local rec = ns.RecipeFor(id)
    if rec then
        local e = ns.EvalRecipe(rec)
        if e.cost then
            tooltip:AddDoubleLine("|cffffd100Costs you to make|r", ns.Money(e.cost))
            if e.profit then
                tooltip:AddDoubleLine("|cffffd100Profit if you sell it|r", ns.Profit(e.profit))
            end
        end
    end
end

local function hookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, ns.Guard("tooltip", addTooltipLines))
    end
    -- Returning true from a line pre-call tells Blizzard to skip that line.
    if TooltipDataProcessor and TooltipDataProcessor.AddLinePreCall then
        pcall(TooltipDataProcessor.AddLinePreCall, SELL_PRICE_LINE, function(tooltip)
            return ourTooltip(tooltip) and true or false
        end)
    end
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------

ns.Listen("READY", function()
    UI.tab = "todo"
    ns.Guard("minimap", createMinimapButton)()
    ns.Guard("tooltips", hookTooltips)()
    showHUD()
end)

for _, msg in ipairs({ "PRICES_UPDATED", "BAGS_UPDATED", "RECIPES_UPDATED", "ITEMS_UPDATED", "VENDOR_UPDATED",
    "NODES_UPDATED", "PLAYER_CHANGED" }) do
    ns.Listen(msg, function()
        ns.Later("ui-refresh", 0.4, function() ns.RefreshUI(true) end)
    end)
end

ns.Listen("ROUTE", function()
    showHUD()
    ns.Later("ui-refresh", 0.2, function() ns.RefreshUI(true) end)
end)

ns.Listen("SESSION", function()
    showHUD()
    ns.RefreshUI(true)
end)

ns.Listen("SELL", function()
    refreshSellPanel()
end)

ns.Listen("SCAN_PROGRESS", function()
    refreshAHPanel()
    refreshFooter()
end)

ns.Listen("SCAN_DONE", function()
    refreshAHPanel()
    refreshFooter()
end)

ns.Listen("AH_SHOW", function()
    refreshFooter()
    ns.Later("ui-refresh", 0.4, function() ns.RefreshUI(true) end)
    C_Timer.After(0.4, ns.Guard("auction-strip", createAHPanel))
end)

ns.Listen("AH_CLOSED", function()
    if ahPanel and ahPanel:GetParent() == UIParent then
        ahPanel:Hide()
    end
    refreshFooter()
end)

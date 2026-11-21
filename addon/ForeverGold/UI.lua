-- Forever Gold - the window
--
-- One window: To do, Sell, Buy and Make, plus a Settings page. Every row is
-- a plain sentence with a number on the right. Built from bare frames and textures only (no Blizzard templates),
-- so there is nothing here that depends on which templates this client has.

local _, ns = ...
local floor, max, min = math.floor, math.max, math.min

local UI = { sel = {} }
ns.UI = UI

local W, H = 860, 480
local MIN_H, MAX_H = 360, 640
local PANE_W = 330
local COIN = "Interface\\Icons\\INV_Misc_Coin_01"
-- Forever Gold's own round badge (Icon.tga next to this file).
local LOGO = "Interface\\AddOns\\ForeverGold\\Icon"
local GREY = "|cff9a9a9a"
local CUT = ns.AH_CUT

-- The look: a merchant's ledger. Charcoal panels, aged brass edges, and
-- gold kept for the selected tab and the main action only.
local C = {
    bg = { 0.071, 0.067, 0.062, 1 },
    edge = { 0.34, 0.28, 0.16 },
    panel = { 0.098, 0.094, 0.086, 1 },
    panelEdge = { 0.24, 0.21, 0.16 },
    btn = { 0.145, 0.137, 0.125 },
    btnEdge = { 0.30, 0.27, 0.22 },
    btnText = { 0.87, 0.85, 0.80 },
    gold = { 0.40, 0.30, 0.10 },
    goldEdge = { 0.82, 0.64, 0.28 },
    goldText = { 1, 0.87, 0.50 },
    head = { 0.86, 0.78, 0.60 },
    text = { 0.93, 0.91, 0.87 },
}
ns.THEME = C

----------------------------------------------------------------------
-- Small building blocks
----------------------------------------------------------------------

local function tex(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

local function setEdge(f, r, g, b, a)
    for _, e in ipairs(f.edges or {}) do
        e:SetColorTexture(r, g, b, a or 1)
    end
end

local function skin(f, r, g, b, a, er, eg, eb, ea)
    if not r then
        r, g, b, a = C.bg[1], C.bg[2], C.bg[3], C.bg[4]
    end
    local bg = tex(f, "BACKGROUND", r, g, b, a)
    bg:SetAllPoints()
    f.bg = bg
    if not er then
        er, eg, eb = C.edge[1], C.edge[2], C.edge[3]
    end
    ea = ea or 1
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
    f.edges = { top, bottom, left, right }
end

-- Serif headings (the game's own Morpheus face), falling back to the
-- standard fonts if this client won't make one.
local function makeFont(name, size, fallback)
    if _G[name] then
        return name
    end
    if not CreateFont then
        return fallback
    end
    local ok, font = pcall(CreateFont, name)
    if not ok or not font then
        return fallback
    end
    if not pcall(font.SetFont, font, "Fonts\\MORPHEUS.TTF", size, "") then
        return fallback
    end
    return name
end
local SERIF_L = makeFont("ForeverGoldSerifLarge", 19, "GameFontNormalLarge")
-- Only the window title is decorative; everything you read is the plain face.

-- Quality as an icon border, so item names can stay one quiet colour.
local QUALITY_RGB = { [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 },
    [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 } }

local function edgeFor(texture, id)
    local it = id and ns.Item(id)
    local c = it and QUALITY_RGB[it.q or 1]
    if c then
        texture:SetColorTexture(c[1], c[2], c[3], 0.9)
    else
        texture:SetColorTexture(0.32, 0.30, 0.27, 1)
    end
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
    skin(b, C.btn[1], C.btn[2], C.btn[3], 1, C.btnEdge[1], C.btnEdge[2], C.btnEdge[3], 1)
    local hl = tex(b, "HIGHLIGHT", 1, 0.92, 0.7, 0.10)
    hl:SetAllPoints()
    b.text = label(b, "GameFontNormalSmall", text)
    b.text:SetPoint("CENTER")
    b.text:SetTextColor(C.btnText[1], C.btnText[2], C.btnText[3])
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
    -- Gold when selected (a tab) or when it's the main thing to press.
    local function paint(self)
        local gold = self.on or self.primary
        if gold then
            self.bg:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
            setEdge(self, C.goldEdge[1], C.goldEdge[2], C.goldEdge[3])
        else
            self.bg:SetColorTexture(C.btn[1], C.btn[2], C.btn[3], 1)
            setEdge(self, C.btnEdge[1], C.btnEdge[2], C.btnEdge[3])
        end
        if self.disabled then
            self.text:SetTextColor(0.48, 0.47, 0.45)
        elseif gold then
            self.text:SetTextColor(C.goldText[1], C.goldText[2], C.goldText[3])
        else
            self.text:SetTextColor(C.btnText[1], C.btnText[2], C.btnText[3])
        end
    end
    function b:SetOn(on)
        self.on = on and true or false
        paint(self)
    end
    function b:SetPrimary(p)
        self.primary = p and true or false
        paint(self)
    end
    function b:SetDisabled(d)
        self.disabled = d and true or false
        paint(self)
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

-- A row's second line, in full, when it didn't fit on the row.
local function cutLine(self)
    local fs = self.sub
    if fs and fs.IsTruncated and fs:IsTruncated() then
        local text = fs:GetText()
        if text and text ~= "" then
            return text
        end
    end
    return nil
end

local function rowEnter(self)
    local d = self.d
    if not d or d.type or not GameTooltip then
        return
    end
    if not pcall(GameTooltip.SetOwner, GameTooltip, self, "ANCHOR_CURSOR_RIGHT") then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    end
    local cut = cutLine(self)
    -- With a details pane beside the list, the numbers are there already;
    -- hovering only shows the game's own item tooltip.
    if self.list and self.list.onSelect then
        if d.id then
            pcall(GameTooltip.SetItemByID, GameTooltip, d.id)
            if cut then
                GameTooltip:AddLine(cut, 1, 1, 1, true)
            end
            GameTooltip:Show()
        elseif cut then
            GameTooltip:SetText(d.title or "", 1, 0.82, 0)
            GameTooltip:AddLine(cut, 1, 1, 1, true)
            GameTooltip:Show()
        else
            GameTooltip:Hide()
        end
        return
    end
    local tip = d.tip
    if type(tip) == "function" then
        local ok, result = pcall(tip)
        tip = ok and result or nil
    end
    if tip then
        GameTooltip:SetText(d.tipTitle or d.title or "", 1, 0.82, 0)
        if cut then
            GameTooltip:AddLine(cut, 1, 1, 1, true)
        end
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
        if cut then
            GameTooltip:AddLine(cut, 1, 1, 1, true)
        end
    elseif cut then
        GameTooltip:SetText(d.title or "", 1, 0.82, 0)
        GameTooltip:AddLine(cut, 1, 1, 1, true)
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
    if d.id and ns.TryDressUp(d.id, d.link) then
        return
    end
    if self.list and self.list.onSelect and not d.type then
        -- Click picks the row for the details pane; the pane holds the action.
        if d.id and IsShiftKeyDown and IsShiftKeyDown() then
            insertLink(d.id)
            return
        end
        if d.id and ns.ahOpen then
            ns.SearchAH(ns.ItemName(d.id))
        end
        local ok, err = pcall(self.list.onSelect, d)
        if not ok then
            ns.Err("row", err)
        end
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
    r.hl = tex(r, "HIGHLIGHT", 1, 1, 1, 0.05)
    r.hl:SetAllPoints()
    r.band = tex(r, "BACKGROUND", 1, 1, 1, 0.025)
    r.band:SetAllPoints()
    r.selBg = tex(r, "BACKGROUND", 1, 0.92, 0.75, 0.07)
    r.selBg:SetAllPoints()
    r.selBar = tex(r, "ARTWORK", C.goldEdge[1], C.goldEdge[2], C.goldEdge[3], 1)
    r.selBar:SetPoint("TOPLEFT")
    r.selBar:SetPoint("BOTTOMLEFT")
    r.selBar:SetWidth(2)
    r.sep = tex(r, "BORDER", 1, 1, 1, 0.045)
    r.sep:SetPoint("BOTTOMLEFT")
    r.sep:SetPoint("BOTTOMRIGHT")
    r.sep:SetHeight(1)
    r.iconEdge = r:CreateTexture(nil, "BORDER")
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

-- A strip of small item icons with a label each ("35%"), hovered one at a
-- time: { type = "chips", chips = { { id =, text =, tip = { lines } }, ... }, more = "+3" }
local function chipEnter(self)
    local c = self.c
    if not c or not GameTooltip then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if c.id then
        pcall(GameTooltip.SetItemByID, GameTooltip, c.id)
    end
    for _, line in ipairs(c.tip or {}) do
        GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true)
    end
    GameTooltip:Show()
end

local function chip(r, i)
    r.chips = r.chips or {}
    local c = r.chips[i]
    if not c then
        c = CreateFrame("Button", nil, r)
        c.icon = c:CreateTexture(nil, "ARTWORK")
        c.icon:SetSize(14, 14)
        c.icon:SetPoint("LEFT", 0, 0)
        c.text = label(c, "GameFontHighlightSmall")
        c.text:SetPoint("LEFT", c.icon, "RIGHT", 3, 0)
        c:SetScript("OnEnter", chipEnter)
        c:SetScript("OnLeave", rowLeave)
        r.chips[i] = c
    end
    return c
end

local function renderChips(r, d, width, compact)
    local x = d.indent or (compact and 24 or 44)
    local w = d.chipW or 56
    local n = 0
    for i, cd in ipairs(d.chips or {}) do
        if x + w > width - 4 then
            break
        end
        local c = chip(r, i)
        c.c = cd
        setIcon(c.icon, cd.id and ns.Icon(cd.id) or cd.icon)
        c.text:SetText(cd.text or "")
        c:SetSize(w - 4, 16)
        c:ClearAllPoints()
        c:SetPoint("LEFT", r, "LEFT", x, 0)
        c:Show()
        x = x + w
        n = i
    end
    if n < #(d.chips or {}) then
        r.r1:SetPoint("RIGHT", -6, 0)
        r.r1:SetWidth(40)
        r.r1:SetText(GREY .. "+" .. (#d.chips - n) .. "|r")
    end
    r:EnableMouse(false)
    return compact and 20 or 24
end

-- A line graph of { {time, copper}, ... }: account gold over time.
local function shortGold(v)
    local neg = v < 0 and "-" or ""
    v = math.abs(v)
    if v >= 10000000 then
        return neg .. floor(v / 10000000 + 0.5) .. "k" .. ns.COIN_ICONS.g
    elseif v >= 10000 then
        local g = v / 10000
        return neg .. (g >= 100 and floor(g + 0.5) or floor(g * 10 + 0.5) / 10) .. ns.COIN_ICONS.g
    elseif v >= 100 then
        return neg .. floor(v / 100 + 0.5) .. ns.COIN_ICONS.s
    end
    return neg .. floor(v + 0.5) .. ns.COIN_ICONS.c
end

local GRAPH_LEFT, GRAPH_BOTTOM, GRAPH_MAX_POINTS = 54, 16, 240

local function newGraph(parent)
    local g = CreateFrame("Frame", nil, parent)
    g.bg = tex(g, "BACKGROUND", 0, 0, 0, 0.22)
    g.bg:SetAllPoints()
    g.lines, g.grid, g.ylabels, g.xlabels = {}, {}, {}, {}
    g.empty = label(g, "GameFontDisableSmall")
    g.empty:SetPoint("CENTER")
    g.dot = tex(g, "OVERLAY", C.goldText[1], C.goldText[2], C.goldText[3], 1)
    g.dot:SetSize(7, 7)
    g.dot:Hide()
    -- The crosshair follows the mouse itself, not the nearest recorded point.
    g.cross = g:CreateLine(nil, "OVERLAY")
    g.cross:SetColorTexture(1, 1, 1, 0.35)
    g.cross:SetThickness(1)
    g.cross:Hide()
    g:EnableMouse(true)
    g:SetScript("OnEnter", function(self) self.hovering, self.lastX = true, nil end)
    g:SetScript("OnLeave", function(self)
        self.hovering = false
        self.dot:Hide()
        self.cross:Hide()
        rowLeave()
    end)
    g:SetScript("OnUpdate", function(self)
        local s = self.scale
        if not self.hovering or not s or not GameTooltip then
            return
        end
        local cx = GetCursorPosition() / (self:GetEffectiveScale() or 1) - (self:GetLeft() or 0)
        cx = max(GRAPH_LEFT, min(GRAPH_LEFT + s.pw, cx))
        if self.lastX and math.abs(cx - self.lastX) < 0.5 then
            return
        end
        self.lastX = cx
        -- The balance at that moment: the last one recorded at or before it.
        local t = s.t0 + (s.t1 > s.t0 and (cx - GRAPH_LEFT) / s.pw * (s.t1 - s.t0) or 0)
        local all = self.all
        local lo, hi = 1, #all
        while lo < hi do
            local mid = floor((lo + hi + 1) / 2)
            if all[mid][1] <= t then lo = mid else hi = mid - 1 end
        end
        local v = all[lo][2]
        local y = s.Y(v)
        self.cross:SetStartPoint("BOTTOMLEFT", self, cx, GRAPH_BOTTOM)
        self.cross:SetEndPoint("BOTTOMLEFT", self, cx, GRAPH_BOTTOM + s.ph)
        self.cross:Show()
        self.dot:ClearAllPoints()
        self.dot:SetPoint("CENTER", self, "BOTTOMLEFT", cx, y)
        self.dot:Show()
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        if self.opts and self.opts.duration then
            GameTooltip:SetText(ns.Duration(max(1, floor(t))) .. " in", 1, 1, 1)
            GameTooltip:AddLine(ns.Money(v) .. GREY .. " made so far|r", 1, 1, 1)
            local ref = self.opts.ref
            if ref and ref > 0 then
                GameTooltip:AddLine(GREY .. "Your usual pace: " .. ns.StripCodes(ns.Money(all[1][2] + ref * (t - all[1][1]))) .. "|r", 1, 1, 1)
            end
            GameTooltip:Show()
            return
        end
        GameTooltip:SetText(date("%a %d %b, %H:%M", floor(t)), 1, 1, 1)
        GameTooltip:AddLine(ns.Money(v), 1, 1, 1)
        local change = v - all[1][2]
        if change ~= 0 then
            GameTooltip:AddLine((ns.Profit and ns.Profit(change) or ns.Money(change)) .. GREY .. " since " .. date("%d %b %H:%M", all[1][1]) .. "|r", 1, 1, 1)
        end
        GameTooltip:Show()
    end)

    local function line(list, i, layer)
        local l = list[i]
        if not l then
            l = g:CreateLine(nil, layer or "ARTWORK")
            list[i] = l
        end
        l:Show()
        return l
    end
    local function text(list, i)
        local t = list[i]
        if not t then
            t = label(g, "GameFontDisableSmall")
            list[i] = t
        end
        t:ClearAllPoints()
        t:Show()
        return t
    end

    -- o (optional): { duration = true } for seconds-into-a-session along the
    -- bottom instead of dates; ref = copper a second for a dashed "your
    -- usual" line from the first point; smooth = slopes instead of steps.
    function g:Draw(points, span, o)
        o = o or {}
        self.opts = o
        self.dash = self.dash or {}
        for _, l in ipairs(self.lines) do l:Hide() end
        for _, l in ipairs(self.grid) do l:Hide() end
        for _, l in ipairs(self.dash) do l:Hide() end
        for _, t in ipairs(self.ylabels) do t:Hide() end
        for _, t in ipairs(self.xlabels) do t:Hide() end
        if self.refLabel then self.refLabel:Hide() end
        if self.endLabel then self.endLabel:Hide() end
        self.dot:Hide()
        self.cross:Hide()
        self.drawn, self.scale, self.lastX = {}, nil, nil
        local w, h = self:GetWidth() or 300, self:GetHeight() or 150
        if #points < 2 then
            self.empty:SetText(o.emptyText or "Not enough history yet")
            return
        end
        self.all = points
        self.empty:SetText("")
        -- Thin very long histories so there are never more than a few hundred segments.
        local step = math.ceil(#points / GRAPH_MAX_POINTS)
        local pts = {}
        for i = 1, #points, step do
            pts[#pts + 1] = points[i]
        end
        if pts[#pts] ~= points[#points] then
            pts[#pts + 1] = points[#points]
        end
        local t0, t1 = pts[1][1], pts[#pts][1]
        local vmin, vmax = pts[1][2], pts[1][2]
        for _, p in ipairs(pts) do
            vmin, vmax = min(vmin, p[2]), max(vmax, p[2])
        end
        local refEnd = o.ref and o.ref > 0 and (pts[1][2] + o.ref * (t1 - t0)) or nil
        if refEnd then
            vmax = max(vmax, refEnd)
        end
        local spread = max(vmax - vmin, max(100, vmax * 0.02))
        local mid = (vmax + vmin) / 2
        vmin, vmax = max(0, mid - spread * 0.6), mid + spread * 0.6
        local pw, ph = w - GRAPH_LEFT - 8, h - GRAPH_BOTTOM - 8
        local function X(t) return GRAPH_LEFT + (t1 > t0 and (t - t0) / (t1 - t0) or 1) * pw end
        local function Y(v) return GRAPH_BOTTOM + (v - vmin) / (vmax - vmin) * ph end
        self.scale = { t0 = t0, t1 = t1, pw = pw, ph = ph, Y = Y }
        for i = 0, 2 do
            local v = vmin + (vmax - vmin) * (0.1 + 0.4 * i)
            local y = Y(v)
            local gl = line(self.grid, i + 1, "BORDER")
            gl:SetThickness(1)
            gl:SetColorTexture(1, 1, 1, 0.07)
            gl:SetStartPoint("BOTTOMLEFT", self, GRAPH_LEFT, y)
            gl:SetEndPoint("BOTTOMLEFT", self, w - 8, y)
            local t = text(self.ylabels, i + 1)
            t:SetJustifyH("RIGHT")
            t:SetWidth(GRAPH_LEFT - 8)
            t:SetPoint("RIGHT", self, "BOTTOMLEFT", GRAPH_LEFT - 6, y)
            t:SetText(shortGold(v))
        end
        -- Time along the bottom: start, middle and end.
        local fmt = (t1 - t0) <= 2 * 86400 and "%H:%M" or "%d %b"
        for i, f in ipairs({ 0, 0.5, 1 }) do
            local t = t0 + (t1 - t0) * f
            local xl = text(self.xlabels, i)
            local where = i == 1 and "BOTTOMLEFT" or (i == 3 and "BOTTOMRIGHT" or "BOTTOM")
            xl:SetJustifyH(i == 1 and "LEFT" or (i == 3 and "RIGHT" or "CENTER"))
            xl:SetWidth(90)
            xl:SetPoint(where, self, "BOTTOMLEFT", X(t), 2)
            if o.duration then
                xl:SetText(i == 1 and "Start" or (ns.Duration(max(1, floor(t - t0))) .. (i == 3 and " farming" or "")))
            else
                xl:SetText(date(fmt, floor(t)))
            end
        end
        -- Your usual pace, dashed.
        if refEnd then
            local x0, y0, x1, y1 = X(t0), Y(pts[1][2]), X(t1), Y(refEnd)
            local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
            local n = 0
            local d = 0
            while d < len and n < 200 do
                local e = min(len, d + 6)
                n = n + 1
                local l = line(self.dash, n, "ARTWORK")
                l:SetThickness(1.5)
                l:SetColorTexture(1, 1, 1, 0.35)
                l:SetStartPoint("BOTTOMLEFT", self, x0 + (x1 - x0) * d / len, y0 + (y1 - y0) * d / len)
                l:SetEndPoint("BOTTOMLEFT", self, x0 + (x1 - x0) * e / len, y0 + (y1 - y0) * e / len)
                d = d + 10
            end
            self.refLabel = self.refLabel or label(self, "GameFontDisableSmall")
            self.refLabel:ClearAllPoints()
            self.refLabel:SetPoint("BOTTOMRIGHT", self, "BOTTOMLEFT", x1 - 2, y1 + 3)
            self.refLabel:SetText("Your usual")
            self.refLabel:Show()
        end
        if o.endText then
            self.endLabel = self.endLabel or label(self, "GameFontHighlightSmall")
            self.endLabel:ClearAllPoints()
            self.endLabel:SetPoint("BOTTOMRIGHT", self, "BOTTOMLEFT", X(t1) - 4, Y(pts[#pts][2]) + 4)
            self.endLabel:SetText(o.endText)
            self.endLabel:Show()
        end
        local up = pts[#pts][2] >= pts[1][2]
        local cr, cg, cb = C.goldEdge[1], C.goldEdge[2], C.goldEdge[3]
        if not up then
            cr, cg, cb = 0.85, 0.42, 0.36
        end
        -- Steps, not slopes: your gold holds until the next time it's recorded.
        local used = 0
        local function seg(x1, y1, x2, y2)
            used = used + 1
            local l = line(self.lines, used)
            l:SetThickness(2)
            l:SetColorTexture(cr, cg, cb, 1)
            l:SetStartPoint("BOTTOMLEFT", self, x1, y1)
            l:SetEndPoint("BOTTOMLEFT", self, x2, y2)
        end
        for i, p in ipairs(pts) do
            local x, y = X(p[1]), Y(p[2])
            self.drawn[i] = { x = x, y = y, t = p[1], v = p[2] }
            if i > 1 then
                local prev = self.drawn[i - 1]
                if o.smooth then
                    seg(prev.x, prev.y, x, y)
                else
                    if x > prev.x then
                        seg(prev.x, prev.y, x, prev.y)
                    end
                    if y ~= prev.y then
                        seg(x, prev.y, x, y)
                    end
                end
            end
        end
    end
    return g
end

----------------------------------------------------------------------
-- Dashboard pieces (Farming tab)
--
--   { type = "cards", cards = { { cap =, value =, sub =, tip = }, ... } }
--       a row of stat boxes side by side
--   { type = "segbar", segs = { { value =, color = {r,g,b} }, ... } }
--       one bar split by share
--   { type = "meter", value = -1..1, left =, right = }
--       red-to-green, with a marker (the luck meter)
--   { type = "heat", cells = { { key =, v =, tip = }, ... } (oldest first,
--       whole weeks, Monday first), legend = true }
----------------------------------------------------------------------

local function hideExtras(r)
    for _, k in ipairs({ "cardsF", "segF", "meterF", "heatF" }) do
        if r[k] then
            r[k]:Hide()
        end
    end
    if r.barBg then
        r.barBg:Hide()
        r.barFg:Hide()
    end
end

local function cellEnter(self)
    if not (self.tip and GameTooltip) then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    for i, line in ipairs(self.tip) do
        if i == 1 then
            GameTooltip:SetText(line, 1, 0.82, 0)
        else
            GameTooltip:AddLine(line, 1, 1, 1, true)
        end
    end
    GameTooltip:Show()
end

local function renderCards(r, d, width)
    local f = r.cardsF
    if not f then
        f = CreateFrame("Frame", nil, r)
        f.cards = {}
        r.cardsF = f
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", 6, -6)
    f:SetSize(width - 12, 54)
    f:Show()
    local n = #(d.cards or {})
    local gap = 8
    local cw = n > 0 and floor((width - 12 - gap * (n - 1)) / n) or 0
    for i = 1, max(n, #f.cards) do
        local c = f.cards[i]
        local cd = d.cards[i]
        if cd and not c then
            c = CreateFrame("Frame", nil, f)
            c.bg = tex(c, "BACKGROUND", 0, 0, 0, 0.25)
            c.bg:SetAllPoints()
            c.edge = tex(c, "BORDER", C.goldEdge[1], C.goldEdge[2], C.goldEdge[3], 0.9)
            c.edge:SetPoint("TOPLEFT")
            c.edge:SetPoint("BOTTOMLEFT")
            c.edge:SetWidth(2)
            c.cap = label(c, "GameFontDisableSmall")
            c.cap:SetPoint("TOPLEFT", 10, -6)
            c.value = label(c, "GameFontHighlightLarge")
            c.value:SetPoint("TOPLEFT", 10, -19)
            c.sub = label(c, "GameFontHighlightSmall")
            c.sub:SetPoint("TOPLEFT", 10, -38)
            for _, fs in ipairs({ c.cap, c.value, c.sub }) do
                fs:SetJustifyH("LEFT")
                fs:SetWordWrap(false)
            end
            c:EnableMouse(true)
            c:SetScript("OnEnter", cellEnter)
            c:SetScript("OnLeave", rowLeave)
            f.cards[i] = c
        end
        if c then
            c:SetShown(cd ~= nil)
            if cd then
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", (i - 1) * (cw + gap), 0)
                c:SetSize(cw, 54)
                for _, fs in ipairs({ c.cap, c.value, c.sub }) do
                    fs:SetWidth(cw - 14)
                end
                c.cap:SetText(cd.cap or "")
                c.value:SetText(cd.value or "")
                c.sub:SetText(cd.sub or "")
                c.tip = cd.tip
            end
        end
    end
    r:EnableMouse(false)
    r.sep:Hide()
    return 66
end

local function renderSegbar(r, d, width)
    local f = r.segF
    if not f then
        f = CreateFrame("Frame", nil, r)
        f.bg = tex(f, "BACKGROUND", 1, 1, 1, 0.06)
        f.bg:SetAllPoints()
        f.segs = {}
        r.segF = f
    end
    f:ClearAllPoints()
    f:SetPoint("LEFT", 12, 0)
    f:SetSize(width - 24, 12)
    f:Show()
    local total = 0
    for _, s in ipairs(d.segs or {}) do
        total = total + max(0, s.value or 0)
    end
    local x, used = 0, 0
    local inner = width - 24
    for _, s in ipairs(d.segs or {}) do
        local v = max(0, s.value or 0)
        if total > 0 and v > 0 then
            used = used + 1
            local t = f.segs[used]
            if not t then
                t = f:CreateTexture(nil, "ARTWORK")
                f.segs[used] = t
            end
            local w = max(1, v / total * inner - (used > 1 and 2 or 0))
            t:ClearAllPoints()
            t:SetPoint("LEFT", x + (used > 1 and 2 or 0), 0)
            t:SetSize(w, 12)
            t:SetColorTexture(s.color[1], s.color[2], s.color[3], 1)
            t:Show()
            x = x + v / total * inner
        end
    end
    for i = used + 1, #f.segs do
        f.segs[i]:Hide()
    end
    r:EnableMouse(false)
    r.sep:Hide()
    return 26
end

local METER_STEPS = 24
local function renderMeter(r, d, width)
    local f = r.meterF
    if not f then
        f = CreateFrame("Frame", nil, r)
        f.blocks = {}
        for i = 1, METER_STEPS do
            f.blocks[i] = f:CreateTexture(nil, "ARTWORK")
        end
        f.mid = tex(f, "OVERLAY", 1, 1, 1, 0.5)
        f.mark = tex(f, "OVERLAY", 1, 0.86, 0.45, 1)
        f.left = label(f, "GameFontDisableSmall")
        f.right = label(f, "GameFontDisableSmall")
        r.meterF = f
    end
    local w = min(420, width - 24)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", 12, -6)
    f:SetSize(w, 30)
    f:Show()
    local bw = w / METER_STEPS
    for i, b in ipairs(f.blocks) do
        local k = (i - 0.5) / METER_STEPS -- 0 red .. 1 green
        local rr = k < 0.5 and 0.75 or 0.75 - (k - 0.5) * 1.1
        local gg = k < 0.5 and 0.22 + k * 0.6 or 0.52 + (k - 0.5) * 0.5
        local bb = 0.22 + k * 0.2
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", (i - 1) * bw, 0)
        b:SetSize(bw + 0.5, 6)
        b:SetColorTexture(rr, gg, bb, 0.85)
    end
    f.mid:ClearAllPoints()
    f.mid:SetPoint("TOPLEFT", w / 2 - 0.5, 4)
    f.mid:SetSize(1, 14)
    local v = max(-1, min(1, d.value or 0))
    f.mark:ClearAllPoints()
    f.mark:SetPoint("TOPLEFT", (v + 1) / 2 * w - 1.5, 5)
    f.mark:SetSize(3, 16)
    f.left:ClearAllPoints()
    f.left:SetPoint("TOPLEFT", 0, -12)
    f.left:SetText(d.left or "Less lucky")
    f.right:ClearAllPoints()
    f.right:SetPoint("TOPRIGHT", 0, -12)
    f.right:SetText(d.right or "Luckier")
    r:EnableMouse(false)
    r.sep:Hide()
    return 38
end

local HEAT_CELL, HEAT_GAP = 13, 3
local function renderHeat(r, d, width)
    local f = r.heatF
    if not f then
        f = CreateFrame("Frame", nil, r)
        f.cells = {}
        f.keys = {}
        r.heatF = f
    end
    local cells = d.cells or {}
    local weeks = math.ceil(#cells / 7)
    local step = HEAT_CELL + HEAT_GAP
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", 12, -6)
    f:SetSize(weeks * step, 7 * step)
    f:Show()
    local top = 0
    for _, cd in ipairs(cells) do
        top = max(top, cd.v or 0)
    end
    for i = 1, max(#cells, #f.cells) do
        local c = f.cells[i]
        local cd = cells[i]
        if cd and not c then
            c = CreateFrame("Frame", nil, f)
            c:SetSize(HEAT_CELL, HEAT_CELL)
            c.t = c:CreateTexture(nil, "ARTWORK")
            c.t:SetAllPoints()
            c:EnableMouse(true)
            c:SetScript("OnEnter", cellEnter)
            c:SetScript("OnLeave", rowLeave)
            f.cells[i] = c
        end
        if c then
            c:SetShown(cd ~= nil)
            if cd then
                local col, row = floor((i - 1) / 7), (i - 1) % 7
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", col * step, -row * step)
                local v = cd.v or 0
                if cd.future then
                    c.t:SetColorTexture(1, 1, 1, 0)
                elseif v <= 0 then
                    c.t:SetColorTexture(1, 1, 1, cd.played and 0.16 or 0.07)
                else
                    local k = top > 0 and v / top or 0
                    local lvl = k > 0.75 and 1 or (k > 0.45 and 0.75 or (k > 0.2 and 0.5 or 0.3))
                    c.t:SetColorTexture(C.goldText[1] * lvl + 0.08, C.goldText[2] * lvl + 0.05, C.goldText[3] * lvl * 0.4, 1)
                end
                c.tip = cd.tip
            end
        end
    end
    r:EnableMouse(false)
    r.sep:Hide()
    return 7 * step + 10
end

-- Fills a row from its description and returns the height it needs.
local function renderRow(r, d, width)
    local RIGHT_W = (r.list and r.list.rightW) or RIGHT_W
    local compact = r.list and r.list.compact
    r.d = d
    r:SetWidth(width)
    r.icon:Hide()
    r.iconEdge:Hide()
    r.band:Hide()
    local selected = r.list and r.list.selected == d and not d.type
    r.selBg:SetShown(selected)
    r.selBar:SetShown(selected)
    r.sep:SetShown(d.type ~= "text")
    r.sep:SetColorTexture(1, 1, 1, 0.045)
    r.title:SetTextColor(C.text[1], C.text[2], C.text[3])
    for _, c in ipairs(r.chips or {}) do
        c:Hide()
    end
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

    if r.graph then
        r.graph:Hide()
    end
    hideExtras(r)
    if d.type == "graph" then
        r.title:SetText("")
        r:EnableMouse(false)
        r.sep:Hide()
        local h = d.height or 160
        r.graph = r.graph or newGraph(r)
        r.graph:ClearAllPoints()
        r.graph:SetPoint("TOPLEFT", 8, -6)
        r.graph:SetSize(width - 16, h - 12)
        r.graph:Show()
        r.graph:Draw(d.points or {}, d.span, d.graph)
        return h
    elseif d.type == "cards" then
        r.title:SetText("")
        return renderCards(r, d, width)
    elseif d.type == "segbar" then
        r.title:SetText("")
        return renderSegbar(r, d, width)
    elseif d.type == "meter" then
        r.title:SetText("")
        return renderMeter(r, d, width)
    elseif d.type == "heat" then
        r.title:SetText("")
        return renderHeat(r, d, width)
    elseif d.type == "chips" then
        r.title:SetText("")
        return renderChips(r, d, width, compact)
    elseif d.type == "header" then
        -- A heading on a thin brass rule, no fill.
        r.band:Show()
        r.sep:Show()
        r.sep:SetColorTexture(C.edge[1], C.edge[2], C.edge[3], 0.8)
        setFont(r.title, compact and "GameFontNormalSmall" or "GameFontNormal")
        r.title:SetTextColor(C.head[1], C.head[2], C.head[3])
        r.title:SetPoint("BOTTOMLEFT", compact and 6 or 8, compact and 3 or 5)
        r.title:SetWidth(width - RIGHT_W - 20)
        r.title:SetText(d.text or "")
        r.r1:SetPoint("BOTTOMRIGHT", compact and -6 or -10, compact and 3 or 6)
        r.r1:SetWidth(RIGHT_W + 60)
        r.r1:SetText(d.right and (GREY .. d.right .. "|r") or "")
        r:EnableMouse(false)
        return compact and 18 or 30
    elseif d.type == "text" then
        local y = compact and -4 or -8
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
        return floor(-y + h + (compact and 6 or 10))
    end

    r:EnableMouse(true)
    r.icon:Show()
    setIcon(r.icon, d.icon or (d.id and ns.Icon(d.id)))
    if d.iconCoords then
        r.icon:SetTexCoord(d.iconCoords[1], d.iconCoords[2], d.iconCoords[3], d.iconCoords[4])
    end
    if d.dim then
        r.icon:SetAlpha(0.45)
        r.title:SetTextColor(0.62, 0.61, 0.58)
    else
        r.icon:SetAlpha(1)
    end
    local function placeEdge()
        if d.noIcon then
            r.icon:Hide()
            return
        end
        r.iconEdge:ClearAllPoints()
        r.iconEdge:SetPoint("TOPLEFT", r.icon, "TOPLEFT", -1, 1)
        r.iconEdge:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 1, -1)
        edgeFor(r.iconEdge, d.id)
        r.iconEdge:Show()
    end
    if compact then
        -- One line: small icon, name, then two numbers on the right.
        r.icon:SetSize(16, 16)
        r.icon:ClearAllPoints()
        r.icon:SetPoint("LEFT", 4, 0)
        placeEdge()
        local w1, w2 = RIGHT_W, r.list.right2W or 70
        setFont(r.title, "GameFontHighlightSmall")
        r.title:SetPoint("LEFT", 24, 0)
        r.title:SetWidth(max(40, width - 24 - w1 - w2 - 10))
        r.title:SetText(d.title or "")
        r.r1:SetPoint("RIGHT", -4, 0)
        r.r1:SetWidth(w1)
        r.r1:SetText(d.r1 or "")
        r.r2:SetPoint("RIGHT", -(6 + w1), 0)
        r.r2:SetWidth(w2)
        r.r2:SetText(d.r2 or "")
        return 22
    end
    r.icon:SetSize(30, 30)
    r.icon:ClearAllPoints()
    r.icon:SetPoint("TOPLEFT", 7, -6)
    placeEdge()
    if d.swatch then
        -- A small colour square instead of an icon (a key to a bar above).
        r.icon:SetColorTexture(d.swatch[1], d.swatch[2], d.swatch[3], 1)
        r.icon:SetTexCoord(0, 1, 0, 1)
        r.icon:SetSize(12, 12)
        r.icon:ClearAllPoints()
        r.icon:SetPoint("TOPLEFT", 16, -9)
        r.iconEdge:Hide()
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
    -- An optional bar (share of the best), just left of the numbers.
    local barW = 0
    if d.bar then
        barW = 110
        if not r.barBg then
            r.barBg = tex(r, "ARTWORK", 1, 1, 1, 0.07)
            r.barFg = tex(r, "OVERLAY", 1, 1, 1, 1)
        end
        r.barBg:ClearAllPoints()
        r.barBg:SetPoint("TOPRIGHT", -(pad + rightW + 10), -12)
        r.barBg:SetSize(96, 6)
        r.barBg:Show()
        local bc = d.barColor or C.goldText
        r.barFg:SetColorTexture(bc[1], bc[2], bc[3], 0.9)
        r.barFg:ClearAllPoints()
        r.barFg:SetPoint("TOPLEFT", r.barBg, "TOPLEFT", 0, 0)
        r.barFg:SetSize(max(1, 96 * max(0, min(1, d.bar))), 6)
        r.barFg:Show()
    end
    local tx = (d.noIcon and 12) or (d.swatch and 36) or 46
    setFont(r.title, "GameFontHighlight")
    r.title:SetPoint("TOPLEFT", tx, -6)
    r.title:SetWidth(width - tx - rightW - pad - 4 - barW)
    r.title:SetWordWrap(true)
    if r.title.SetMaxLines then
        r.title:SetMaxLines(2)
    end
    r.title:SetText(d.title or "")
    -- Both lines wrap instead of being cut off; the row grows to fit them.
    local titleH = max(14, r.title:GetStringHeight() or 14)
    local subY = floor(6 + titleH + 3 + 0.5)
    r.sub:SetPoint("TOPLEFT", tx, -subY)
    r.sub:SetWidth(width - tx - rightW - pad - 4 - barW)
    r.sub:SetJustifyV("TOP")
    r.sub:SetWordWrap(true)
    if r.sub.SetMaxLines then
        r.sub:SetMaxLines(4)
    end
    r.sub:SetText(d.sub and (GREY .. d.sub .. "|r") or "")
    r.r1:SetPoint("TOPRIGHT", -pad, -6)
    r.r1:SetWidth(rightW)
    r.r1:SetText(d.r1 or "")
    r.r2:SetPoint("TOPRIGHT", -pad, -24)
    r.r2:SetWidth(rightW)
    r.r2:SetText(d.r2 or "")
    local subH = (d.sub and d.sub ~= "") and (r.sub:GetStringHeight() or 0) or 0
    return max(42, floor(subY + subH + 7 + 0.5))
end

local MAX_ROWS = 400

----------------------------------------------------------------------
-- A scrollbar you can drag
----------------------------------------------------------------------

-- A thin brass bar at a list's right edge. Drag the thumb, or click the
-- track to jump there and keep dragging. The list anchors bar.track by its
-- TOPRIGHT and calls bar:Update(offset, maxOff, shownFraction, trackH)
-- whenever it scrolls; set(offset) is called while you drag.
local function cursorY(frame)
    local _, y = GetCursorPosition()
    local scale = frame:GetEffectiveScale() or 1
    return (y or 0) / (scale > 0 and scale or 1)
end

local function scrollBar(parent, set)
    local bar = { set = set, offset = 0, maxOff = 0, size = 20, trackH = 0 }
    local track = CreateFrame("Frame", nil, parent)
    track:SetSize(10, 10)
    track:SetFrameLevel((parent:GetFrameLevel() or 0) + 6)
    track:EnableMouse(true)
    track.line = tex(track, "BACKGROUND", 1, 1, 1, 0.06)
    track.line:SetPoint("TOPRIGHT", -1, 0)
    track.line:SetPoint("BOTTOMRIGHT", -1, 0)
    track.line:SetWidth(4)
    local thumb = CreateFrame("Frame", nil, track)
    thumb:SetWidth(10)
    thumb:EnableMouse(true)
    thumb.bar = tex(thumb, "OVERLAY", C.edge[1], C.edge[2], C.edge[3], 0.9)
    thumb.bar:SetPoint("TOPRIGHT", -1, 0)
    thumb.bar:SetPoint("BOTTOMRIGHT", -1, 0)
    bar.track, bar.thumb = track, thumb

    local function paint()
        local hot = bar.dragging or thumb.hover
        local c = hot and C.goldEdge or C.edge
        thumb.bar:SetWidth(hot and 6 or 4)
        thumb.bar:SetColorTexture(c[1], c[2], c[3], hot and 1 or 0.9)
    end
    local function stop()
        bar.dragging = nil
        thumb:SetScript("OnUpdate", nil)
        paint()
    end
    local function startDrag()
        local span = bar.trackH - bar.size
        if bar.maxOff <= 0 or span <= 0 then
            return
        end
        bar.dragging = { y = cursorY(track), off = bar.offset, per = bar.maxOff / span }
        paint()
        thumb:SetScript("OnUpdate", function()
            local d = bar.dragging
            if not d then
                return
            end
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
                stop()
                return
            end
            bar.set(max(0, min(bar.maxOff, d.off + (d.y - cursorY(track)) * d.per)))
        end)
    end
    bar.Drag, bar.StopDrag = startDrag, stop
    thumb:SetScript("OnEnter", function()
        thumb.hover = true
        paint()
    end)
    thumb:SetScript("OnLeave", function()
        thumb.hover = nil
        paint()
    end)
    thumb:SetScript("OnMouseDown", function(_, which)
        if which == nil or which == "LeftButton" then
            startDrag()
        end
    end)
    thumb:SetScript("OnMouseUp", stop)
    -- A click on the track puts the thumb's middle under the cursor.
    track:SetScript("OnMouseDown", function(_, which)
        if which ~= nil and which ~= "LeftButton" then
            return
        end
        local span, top = bar.trackH - bar.size, track:GetTop()
        if bar.maxOff <= 0 or span <= 0 or not top then
            return
        end
        local rel = top - cursorY(track)
        bar.set(max(0, min(bar.maxOff, (rel - bar.size / 2) / span * bar.maxOff)))
        startDrag()
    end)
    track:SetScript("OnMouseUp", stop)

    function bar:Update(offset, maxOff, frac, trackH)
        self.offset, self.maxOff, self.trackH = offset or 0, maxOff or 0, trackH or 0
        if self.maxOff <= 0 or self.trackH <= 0 then
            if self.dragging then
                stop()
            end
            track:Hide()
            return
        end
        self.size = max(20, min(self.trackH, self.trackH * (frac or 1)))
        track:SetHeight(self.trackH)
        thumb:SetHeight(self.size)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -(self.trackH - self.size) * (self.offset / self.maxOff))
        track:Show()
    end
    function bar:IsShown()
        return track:IsShown()
    end
    paint()
    track:Hide()
    return bar
end

local function createList(parent)
    local list = { rows = {}, ys = {}, hs = {}, count = 0, offset = 0, contentH = 0 }
    local clip = CreateFrame("Frame", nil, parent)
    clip:SetClipsChildren(true)
    list.clip = clip
    local content = CreateFrame("Frame", nil, clip)
    content:SetSize(10, 10)
    content:SetPoint("TOPLEFT", 0, 0)
    list.content = content
    list.bar = scrollBar(clip, function(o)
        list.offset = o
        list:Apply()
    end)
    list.bar.track:SetPoint("TOPRIGHT", clip, "TOPRIGHT", 0, 0)

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
        self.bar:Update(self.offset, maxOffset, self.contentH > 0 and viewH / self.contentH or 1, viewH)
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
-- Details pane: the selected row's sums and the thing to do about it
----------------------------------------------------------------------

-- What the pane shows for a row. A row can give d.detail (a table, or a
-- function returning one):
--   { lines = { {label, value}, {label, value, total = true}, "a sentence", " ", ... },
--     note = "small print", action = { label =, onClick =, disabled = }, action2 = {...} }
-- Without one, its hover lines (d.tip) and its click or Sell button are used.
local function detailFor(d)
    local det = d.detail
    if type(det) == "function" then
        local ok, result = pcall(det, d)
        det = ok and result or nil
    end
    det = det or {}
    if not det.lines then
        local tip = d.tip
        if type(tip) == "function" then
            local ok, result = pcall(tip)
            tip = ok and result or nil
        end
        det.lines = tip or {}
    end
    if det.action == nil then
        if d.btn then
            det.action = { label = d.btn.label, onClick = function() d.btn.onClick(d) end }
        elseif d.onClick then
            det.action = { label = d.actionLabel or "Show me", onClick = function() d.onClick(d) end }
        elseif d.id and ns.ahOpen then
            det.action = { label = "Search the auction house", onClick = function() ns.SearchAH(ns.ItemName(d.id)) end }
        end
    end
    if det.action2 == nil and d.id then
        det.action2 = { label = "Link in chat", onClick = function() insertLink(d.id) end }
    end
    return det
end

local function createPane(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetWidth(PANE_W)
    skin(p, C.panel[1], C.panel[2], C.panel[3], C.panel[4], C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 1)
    p:SetClipsChildren(true)
    p.iconEdge = p:CreateTexture(nil, "BORDER")
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetSize(36, 36)
    p.icon:SetPoint("TOPLEFT", 14, -14)
    p.iconEdge:SetPoint("TOPLEFT", p.icon, "TOPLEFT", -1, 1)
    p.iconEdge:SetPoint("BOTTOMRIGHT", p.icon, "BOTTOMRIGHT", 1, -1)
    p.title = label(p, "GameFontHighlightLarge")
    p.title:SetTextColor(C.text[1], C.text[2], C.text[3])
    p.title:SetWordWrap(true)
    p.sub = label(p, "GameFontHighlightSmall")
    p.sub:SetJustifyV("TOP")
    p.sub:SetWordWrap(true)
    p.caption = label(p, "GameFontDisableSmall")
    p.value = label(p, "GameFontHighlightLarge")
    p.value:SetJustifyH("RIGHT")
    p.rule = tex(p, "BORDER", C.edge[1], C.edge[2], C.edge[3], 0.6)
    p.rule:SetHeight(1)
    p.note = label(p, "GameFontDisableSmall")
    p.note:SetJustifyV("TOP")
    p.note:SetWordWrap(true)
    p.fs, p.rules = {}, {}
    p.primary = button(p, "", PANE_W - 28, 26)
    p.primary:SetPrimary(true)
    p.secondary = button(p, "", PANE_W - 28, 22)

    local function fs(i)
        local f = p.fs[i]
        if not f then
            f = label(p, "GameFontHighlightSmall")
            f:SetJustifyV("TOP")
            p.fs[i] = f
        end
        f:ClearAllPoints()
        f:SetWordWrap(false)
        f:SetJustifyH("LEFT")
        f:Show()
        return f
    end
    local function rule(i)
        local t = p.rules[i]
        if not t then
            t = tex(p, "BORDER", 1, 1, 1, 0.08)
            t:SetHeight(1)
            p.rules[i] = t
        end
        t:ClearAllPoints()
        t:Show()
        return t
    end
    local function setAction(b, a)
        if not a then
            b:Hide()
            return false
        end
        b:SetLabel(a.label or "")
        b.onClick = a.onClick
        b:SetDisabled(a.disabled or not a.onClick)
        b:Show()
        return true
    end

    -- Fills the pane for row d and returns the height it needs.
    function p:SetRow(d)
        for _, f in ipairs(self.fs) do f:Hide() end
        for _, t in ipairs(self.rules) do t:Hide() end
        local inner = PANE_W - 28
        if not d then
            self.icon:Hide()
            self.iconEdge:Hide()
            self.title:ClearAllPoints()
            self.title:SetPoint("TOPLEFT", 14, -16)
            self.title:SetWidth(inner)
            self.title:SetText("Nothing picked")
            self.sub:ClearAllPoints()
            self.sub:SetPoint("TOPLEFT", 14, -40)
            self.sub:SetWidth(inner)
            self.sub:SetText(GREY .. "Click a row on the left to see its numbers here.|r")
            for _, w in ipairs({ self.caption, self.value, self.note }) do w:SetText("") end
            self.rule:Hide()
            self.primary:Hide()
            self.secondary:Hide()
            return 90
        end
        local det = detailFor(d)
        local hasIcon = (not d.noIcon and (d.icon or d.id)) and true or false
        local tx = hasIcon and 60 or 14
        self.icon:SetShown(hasIcon)
        self.iconEdge:SetShown(hasIcon)
        if hasIcon then
            setIcon(self.icon, d.icon or ns.Icon(d.id))
            if d.iconCoords then
                self.icon:SetTexCoord(d.iconCoords[1], d.iconCoords[2], d.iconCoords[3], d.iconCoords[4])
            end
            edgeFor(self.iconEdge, d.id)
        end
        self.title:ClearAllPoints()
        self.title:SetPoint("TOPLEFT", tx, -15)
        self.title:SetWidth(PANE_W - tx - 14)
        self.title:SetText(det.title or d.tipTitle or d.title or "")
        local y = -15 - max(18, self.title:GetStringHeight() or 18) - 4
        self.sub:ClearAllPoints()
        self.sub:SetPoint("TOPLEFT", tx, y)
        self.sub:SetWidth(PANE_W - tx - 14)
        local sub = det.sub or d.sub
        self.sub:SetText(sub and (GREY .. sub .. "|r") or "")
        if sub then
            y = y - (self.sub:GetStringHeight() or 12) - 4
        end
        y = min(y, hasIcon and -56 or y) - 6

        -- The headline number (what the row shows on the right, bigger),
        -- unless the sums below already end in a total: profit shows once.
        local hasTotal = false
        for _, line in ipairs(det.lines or {}) do
            if type(line) == "table" and line.total then
                hasTotal = true
            end
        end
        local value = not hasTotal and (det.value or d.r1)
        if value and value ~= "" then
            self.value:ClearAllPoints()
            self.value:SetPoint("TOPRIGHT", -14, y)
            self.value:SetWidth(inner)
            self.value:SetText(value)
            self.caption:ClearAllPoints()
            self.caption:SetPoint("TOPLEFT", 14, y - 4)
            self.caption:SetWidth(inner - 110)
            self.caption:SetWordWrap(false)
            self.caption:SetText(det.caption or d.r2 or "")
            y = y - 26
        else
            self.value:SetText("")
            self.caption:SetText("")
        end
        self.rule:ClearAllPoints()
        self.rule:SetPoint("TOPLEFT", 14, y)
        self.rule:SetPoint("TOPRIGHT", -14, y)
        self.rule:Show()
        y = y - 8

        local n, nr = 0, 0
        for _, line in ipairs(det.lines or {}) do
            if type(line) == "table" then
                if line.total then
                    nr = nr + 1
                    local t = rule(nr)
                    t:SetPoint("TOPLEFT", 14, y - 1)
                    t:SetPoint("TOPRIGHT", -14, y - 1)
                    y = y - 4
                end
                n = n + 1
                local l = fs(n)
                setFont(l, line.total and "GameFontHighlight" or "GameFontHighlightSmall")
                l:SetPoint("TOPLEFT", 14, y)
                l:SetWidth(inner - 120)
                l:SetText(line[1] or "")
                n = n + 1
                local v = fs(n)
                setFont(v, line.total and "GameFontHighlight" or "GameFontHighlightSmall")
                v:SetJustifyH("RIGHT")
                v:SetPoint("TOPRIGHT", -14, y)
                v:SetWidth(120)
                v:SetText(line[2] or "")
                y = y - (line.total and 18 or 15)
            elseif line == " " or line == "" then
                y = y - 6
            else
                n = n + 1
                local l = fs(n)
                setFont(l, "GameFontHighlightSmall")
                l:SetWordWrap(true)
                l:SetPoint("TOPLEFT", 14, y)
                l:SetWidth(inner)
                l:SetText(line)
                y = y - (l:GetStringHeight() or 12) - 3
            end
        end
        if det.note then
            y = y - 4
            self.note:ClearAllPoints()
            self.note:SetPoint("TOPLEFT", 14, y)
            self.note:SetWidth(inner)
            self.note:SetText(det.note)
            y = y - (self.note:GetStringHeight() or 12) - 2
        else
            self.note:SetText("")
        end
        y = y - 10
        self.primary:ClearAllPoints()
        if setAction(self.primary, det.action) then
            self.primary:SetPoint("TOPLEFT", 14, y)
            y = y - 30
        end
        self.secondary:ClearAllPoints()
        if setAction(self.secondary, det.action2) then
            self.secondary:SetPoint("TOPLEFT", 14, y)
            y = y - 26
        end
        return floor(-y + 8)
    end
    return p
end

local ESTIMATE = "Estimates from today's prices, before any deposit you lose on auctions that don't sell. A listing is not a guaranteed sale."

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
    createList = createList, scrollBar = scrollBar, Hd = Hd, Tx = Tx, GREY = GREY, COIN = COIN, LOGO = LOGO, rowLeave = rowLeave,
    C = C, SERIF_L = SERIF_L, edgeFor = edgeFor }

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
        lines[#lines + 1] = " "
    elseif e.missing then
        lines[#lines + 1] = "I don't have a price for " .. ns.ItemName(e.missing)
            .. " yet, so I can't work out the cost. It may not be on the auction house."
    end
    if e.price then
        lines[#lines + 1] = { "Lowest auction price", ns.Money(e.price) }
        lines[#lines + 1] = { "Auction house cut (5%)", "-" .. ns.Money(e.price * CUT) }
        if e.profit then
            lines[#lines + 1] = { "Potential profit each", ns.Profit(e.profit), total = true }
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
            lines[#lines + 1] = "Demand unknown, and weapons and armour sell slowly. You may need to relist a few times."
        else
            lines[#lines + 1] = GREY .. "Demand unknown: no sale data for this yet, only what it's listed at.|r"
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
    local d = { id = rec.out, title = ns.ItemName(rec.out), tipTitle = ns.ItemName(rec.out),
        tip = function() return craftTip(e) end,
        detail = function() return { lines = craftTip(e), note = e.profit and ESTIMATE or nil } end }
    local who = rec.mine and rec.prof or (rec.prof .. " on " .. (rec.chars[1] or "an alt"))
    if mode == "good" or mode == "bad" or mode == "slow" then
        local speed = ns.SaleText and ns.SaleText(rec.out, "mid")
        d.sub = "Costs " .. ns.Money(e.cost) .. GREY .. " to make, sells for |r" .. ns.Money(e.price) .. GREY
            .. "  -  " .. (speed and (speed .. GREY .. "  -  ") or ((e.listed or 0) .. " listed  -  ")) .. who
        d.r1 = ns.Profit(e.profit)
        d.r2 = mode ~= "bad" and (e.margin and (floor(e.margin * 100 + 0.5) .. "% margin, each") or "profit each")
            or "loss on each one"
        if mode == "good" and e.canMake and e.canMake > 0 then
            d.r2 = "each  -  you can make " .. e.canMake
        end
        local verdict = mode ~= "bad" and ns.SaleVerdict and ns.SaleVerdict(rec.out)
        if verdict then
            d.r2 = verdict .. GREY .. "  -  " .. ((mode == "good" and e.canMake and e.canMake > 0)
                and ("you can make " .. e.canMake) or "each") .. "|r"
        end
        if mode == "slow" then
            d.dim = true
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

local function firstNames(list, n, getId)
    local names = {}
    for i = 1, min(n, #list) do
        names[i] = ns.ItemName(getId(list[i]))
    end
    return table.concat(names, ", ") .. (#list > n and (" +" .. (#list - n)) or "")
end

local farmTip

-- Pane lines for a list of items: "8 x Copper Bar   7s 20c".
local function itemLines(list, value, n)
    local lines = {}
    for i = 1, min(n or 8, #list) do
        local e = list[i]
        lines[#lines + 1] = { (e.count and (e.count .. " x ") or "") .. ns.ItemName(e.id), value(e) }
    end
    if #list > (n or 8) then
        lines[#lines + 1] = GREY .. "and " .. (#list - (n or 8)) .. " more|r"
    end
    return lines
end

-- How sure we are that something will sell. With sale data: its verdict
-- ("worth listing") and a weight from how much of it sells. Without: a
-- plain "demand unknown" and a low weight, so an expensive listing alone
-- never tops the list.
local function demand(id)
    local verdict = ns.SaleVerdict and ns.SaleVerdict(id)
    if verdict then
        return verdict, ns.SpeedWeight and ns.SpeedWeight(id) or 0.6, true
    end
    return GREY .. "demand unknown|r", 0.3, false
end

local function searchAction(id)
    return ns.ahOpen and { label = "Open auction search", onClick = function() ns.SearchAH(ns.ItemName(id)) end } or false
end

-- Make > Craft with this recipe picked, so the pane shows its materials.
local function viewMaterials(out)
    return { label = "View materials", onClick = function()
        UI.sel["make:craft"] = "item:" .. out
        ns.ShowTab("craft")
    end }
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
            rows[#rows + 1] = { icon = ns.Icon(bag.undercut[1].id), key = "todo:undercut",
                title = "|cffff7070Relist " .. plural(#bag.undercut, "auction") .. "|r",
                sub = "Undercut  ·  " .. firstNames(bag.undercut, 2, function(u) return u.id end),
                onClick = function() ns.ShowTab("sell") end,
                detail = { sub = "Someone listed under you, so theirs sells first. Cancel yours and relist a little under the lowest price.",
                    lines = itemLines(bag.undercut, function(u) return ns.Money(u.price) end),
                    caption = "the lowest prices now",
                    action = { label = "See undercut auctions", onClick = function() ns.ShowTab("sell") end } } }
        end

        -- Quick wins, ranked by what they're worth times how sure they are.
        local todo = {}
        local function add(value, weight, d)
            if value and value > 0 then
                todo[#todo + 1] = { value = value * (weight or 1), d = d }
            end
        end

        local flips = ns.VendorFlips()
        if #flips > 0 then
            local one = #flips == 1
            add(flips.total, 1, { icon = ns.Icon(flips[1].id), key = "todo:flips",
                title = one and ns.ItemName(flips[1].id) or (#flips .. " auctions under vendor price"),
                sub = "Auction  >  vendor  ·  no risk",
                r1 = ns.Profit(flips.total), r2 = "profit, no risk",
                detail = { sub = "Listed for less than any shopkeeper pays. Buy, sell to a vendor, keep the difference.",
                    lines = itemLines(flips, function(f) return ns.Profit(f.profit) end),
                    note = "Profit each: the vendor price minus the cheapest listing. Later listings may cost more, so check before buying several.",
                    action = ns.ahOpen and { label = "Open auction search", onClick = function() ns.SearchAH(ns.ItemName(flips[1].id)) end }
                        or { label = "See all " .. plural(#flips, "flip"), onClick = function() ns.ShowTab("buy") end } } })
        end
        if #bag.ah > 0 then
            add(bag.ahTotal, 0.8, { icon = ns.Icon(bag.ah[1].id), key = "todo:post",
                title = "Post " .. plural(#bag.ah, "item") .. " from your bags",
                sub = "Bags  >  auction house  ·  " .. firstNames(bag.ah, 2, function(b) return b.id end),
                r1 = ns.Money(bag.ahTotal), r2 = "after the 5% cut",
                detail = function()
                    return { lines = itemLines(bag.ah, function(b) return ns.Money(b.total) end), note = ESTIMATE,
                        action = ns.ahOpen and { label = "Post all (" .. #bag.ah .. ")", onClick = function() ns.StartPostAll() end }
                            or { label = "See items to post", onClick = function() ns.ShowTab("sell") end },
                        action2 = ns.ahOpen and { label = "See items to post", onClick = function() ns.ShowTab("sell") end } or false }
                end })
        end
        if #bag.vendor > 0 then
            add(bag.vendorTotal, 1, { icon = ns.Icon(bag.vendor[1].id), key = "todo:vendor",
                title = "Vendor " .. plural(#bag.vendor, "item"),
                sub = "Bags  >  vendor  ·  " .. firstNames(bag.vendor, 2, function(b) return b.id end),
                r1 = ns.Money(bag.vendorTotal), r2 = "at any vendor",
                detail = { sub = "The auction house wouldn't pay more than a shopkeeper for these.",
                    lines = itemLines(bag.vendor, function(b) return ns.Money(b.total) end),
                    action = { label = "See items to vendor", onClick = function() ns.ShowTab("sell") end } } })
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
            local out = e.rec.out
            local n = (e.canMake and e.canMake > 0) and e.canMake or nil
            local verdict, weight = demand(out)
            add(e.profit * (n or 1), weight, { id = out, key = "todo:craft:" .. out,
                title = ns.ItemName(out) .. (n and (GREY .. "  x" .. n .. "|r") or ""),
                sub = "Craft  ·  " .. (n and "materials in your bags" or "buy the materials") .. "  ·  " .. e.rec.prof,
                r1 = ns.Profit(e.profit * (n or 1)), r2 = verdict,
                detail = function()
                    local lines = craftTip(e)
                    if n then
                        lines[#lines + 1] = { "Potential profit, all " .. n, ns.Profit(e.profit * n), total = true }
                    end
                    return { lines = lines, note = ESTIMATE, action = viewMaterials(out), action2 = searchAction(out) }
                end })
        end

        local deals = ns.VendorDeals()
        if deals.sure > 0 then
            local v = deals[1]
            local verdict, weight, known = demand(v.id)
            add(v.profit, weight, { id = v.id, key = "todo:deal:" .. v.id,
                title = ns.ItemName(v.id),
                sub = "Vendor  >  auction house" .. (v.zone and v.zone ~= "" and ("  ·  " .. v.zone) or ""),
                r1 = ns.Profit(v.profit), r2 = known and verdict or ("potential  ·  " .. verdict),
                detail = function()
                    local lines = { { "Vendor sells it for", ns.Money(v.buy) },
                        { v.how == "sold" and "Has sold for" or "Cheapest listing", ns.Money(v.price) },
                        { "Auction house cut (5%)", "-" .. ns.Money(v.price * CUT) },
                        { "Potential profit each", ns.Profit(v.profit), total = true }, " ",
                        { "Vendor", v.npc or "?" }, { "Where", v.zone or "?" },
                        { "Listed on the auction house", tostring(v.listed or 0) }, { "Demand", verdict } }
                    if v.limited then
                        lines[#lines + 1] = "This vendor only stocks a few at a time."
                    end
                    if not known then
                        lines[#lines + 1] = "No sale data yet: that's only what people are asking. Try one before buying more."
                    end
                    local hasSpot = v.map and v.x
                    return { lines = lines, note = ESTIMATE,
                        action = hasSpot and { label = "View vendor location", onClick = function()
                            if ns.SetWaypoint(v.map, v.x, v.y) then
                                ns.Print("map pin set on " .. (v.npc or "the vendor") .. ".")
                            else
                                ns.Print((v.npc or "The vendor") .. " is in " .. (v.zone or "?") .. ".")
                            end
                        end } or { label = "See all vendor deals", onClick = function() ns.ShowTab("buy") end },
                        action2 = searchAction(v.id) }
                end })
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
        -- Your own measured farms that beat the general ones go first.
        local mine = {}
        for _, e in ipairs(ns.FarmSuggestions(2)) do
            if not farms[1] or e.perHour >= (farms[1].perHour or 0) * 0.8 then
                mine[#mine + 1] = e
            end
        end
        if #farms > 0 or #mine > 0 then
            Hd(rows, "Got an hour? Go farm")
            for _, e in ipairs(mine) do
                rows[#rows + 1] = ns.FarmSuggestionRow(e, "todo:mob:")
            end
            for _, f in ipairs(farms) do
                rows[#rows + 1] = { icon = f.items[1] and f.items[1].id and ns.Icon(f.items[1].id) or COIN,
                    key = "todo:farm:" .. f.farm.title, title = f.farm.title, sub = "Farm  ·  " .. (f.where or ""),
                    r1 = "~" .. ns.Money(f.perHour), r2 = "an hour, rough guess",
                    detail = function()
                        return { sub = f.farm.how, lines = farmTip(f),
                            action = { label = "See farming spots", onClick = function() ns.ShowTab("farm") end } }
                    end }
            end
        end
        if #craft.untapped > 0 then
            rows[#rows + 1] = { icon = ns.Icon(craft.untapped[1].rec.out), key = "todo:untapped",
                title = plural(#craft.untapped, "recipe") .. " nobody is selling",
                sub = "Craft  ·  list one or two and see",
                detail = { lines = itemLines(craft.untapped, function(e) return ns.Money(e.cost) end),
                    caption = "cost to make each",
                    note = "Nobody sells these right now: either an open niche or something nobody wants. Demand unknown.",
                    action = { label = "See untried recipes", onClick = function() ns.ShowTab("craft") end } } }
        end
    end

    -- A one-line account summary; the full roster is on Characters.
    local n = 0
    for _ in pairs(ns.db.chars) do
        n = n + 1
    end
    local _, change = ns.GoldHistory(86400)
    Hd(rows, "Account")
    rows[#rows + 1] = { icon = LOGO, key = "todo:account", title = plural(n, "character"),
        sub = "Gold today  " .. (change ~= 0 and ns.Profit(change) or "no change yet"),
        r1 = ns.Money(ns.TotalGold()), r2 = "in total",
        detail = { lines = {}, caption = "all your characters",
            action = { label = "Open Characters", onClick = function() ns.ShowTab("chars") end } } }
    return rows
end

----------------------------------------------------------------------
-- Tab: Characters - gold over time, and everyone on the account
----------------------------------------------------------------------

local PRIMARY = { Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true, Herbalism = true,
    Leatherworking = true, Mining = true, Skinning = true, Tailoring = true, Jewelcrafting = true, Inscription = true }

-- Primary professions first, then the rest (cooking, first aid, fishing).
local function profList(ch)
    local list = {}
    for pname, p in pairs(ch.profs or {}) do
        list[#list + 1] = { name = pname, skill = p.skill or 0, primary = PRIMARY[pname] or false }
    end
    table.sort(list, function(a, b)
        if a.primary ~= b.primary then
            return a.primary
        end
        return a.skill > b.skill
    end)
    return list
end

local GRAPH_RANGES = { { "day", "24 hours", 86400 }, { "week", "7 days", 7 * 86400 },
    { "month", "30 days", 30 * 86400 }, { "all", "All", nil } }

local function graphRange()
    for _, r in ipairs(GRAPH_RANGES) do
        if r[1] == UI.graphRange then
            return r
        end
    end
    return GRAPH_RANGES[2]
end

local function buildChars()
    local rows = {}
    local range = graphRange()
    local chars = {}
    for _, ch in pairs(ns.db.chars) do
        chars[#chars + 1] = ch
    end
    table.sort(chars, function(a, b) return (a.money or 0) > (b.money or 0) end)

    if UI.graphMode == "each" then
        -- One smaller graph per character, richest first.
        for _, ch in ipairs(chars) do
            local pts, change = ns.GoldHistory(range[3], ch)
            Hd(rows, ch.name or "?", ns.Money(ch.money or 0) .. GREY .. "  ·  " .. range[2] .. ": |r"
                .. (#pts > 1 and change ~= 0 and ns.Profit(change) or (GREY .. "no change|r")))
            rows[#rows + 1] = { type = "graph", points = pts, span = range[3], height = 90 }
        end
        Tx(rows, nil, GREY .. "Each character's gold is recorded from this version on, while you play that character.|r")
    else
        local pts, change = ns.GoldHistory(range[3])
        Hd(rows, "Gold over time", "All characters  ·  " .. range[2] .. ":  " .. (#pts > 1 and ns.Profit(change) or "no change yet"))
        rows[#rows + 1] = { type = "graph", points = pts, span = range[3], height = 170 }
        if #pts < 3 then
            Tx(rows, nil, GREY .. "Your gold is recorded from now on, every time it changes, across all your characters. The graph fills in as you play.|r")
        end
    end
    Hd(rows, "Characters", ns.Money(ns.TotalGold()) .. " in total")
    local CLASS_ICONS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
    for _, ch in ipairs(chars) do
        local profs = profList(ch)
        local main, lines = {}, {}
        for _, p in ipairs(profs) do
            if p.primary then
                main[#main + 1] = p.name .. " " .. p.skill
            end
            lines[#lines + 1] = { p.name .. (p.primary and "" or (GREY .. "  secondary|r")), tostring(p.skill) }
        end
        local coords = ch.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[ch.class]
        local className = ch.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[ch.class]
        if #lines == 0 then
            lines[1] = "No professions seen yet. Log in on this character and open its profession windows."
        end
        lines[#lines + 1] = " "
        lines[#lines + 1] = { "Last seen", ns.Ago(ch.seen) }
        rows[#rows + 1] = { icon = coords and CLASS_ICONS or COIN, iconCoords = coords,
            key = "char:" .. (ch.name or "?"),
            title = (ch.name or "?") .. GREY .. "  " .. (ch.level or "?") .. (className and ("  " .. className) or "") .. "|r",
            sub = #main > 0 and table.concat(main, ", ") or (#profs > 0 and "Secondary professions only" or "No professions seen yet"),
            r1 = ns.Money(ch.money or 0), r2 = "gold",
            detail = { lines = lines, caption = "gold on this character", action = false } }
    end
    return rows
end

local function charsToolbar()
    local bar = {}
    for _, r in ipairs(GRAPH_RANGES) do
        local key = r[1]
        bar[#bar + 1] = { label = r[2], width = 70, on = graphRange()[1] == key, onClick = function()
            UI.graphRange = key
            ns.RefreshUI(true)
        end }
    end
    bar[#bar].gap = 12
    local each = UI.graphMode == "each"
    bar[#bar + 1] = { label = "All characters", width = 100, on = not each, onClick = function()
        UI.graphMode = nil
        ns.RefreshUI()
    end }
    bar[#bar + 1] = { label = "Each character", width = 100, on = each, onClick = function()
        UI.graphMode = "each"
        ns.RefreshUI()
    end }
    return bar
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
        "Profit = lowest auction price, minus the auction house's 5%, minus the cheapest way to get the materials. "
        .. "Ranked by profit times how often it actually sells, so a big margin nobody buys sits below a small one that sells every day. Hover a row for the full sum.")

    if #craft.good > 0 then
        Hd(rows, "Worth making to sell", plural(#craft.good, "recipe") .. ", best bet first")
        for _, e in ipairs(craft.good) do
            rows[#rows + 1] = craftRow(e, "good")
        end
    end
    if #craft.slow > 0 then
        Hd(rows, "Profitable on paper, but they hardly sell", plural(#craft.slow, "recipe"))
        for _, e in ipairs(craft.slow) do
            rows[#rows + 1] = craftRow(e, "slow")
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

function farmTip(f)
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
    lines[#lines + 1] = GREY .. "The per-hour figure is a rough guess, only for comparing farms. The Farming Session window (right-click the minimap button) measures your real gold per hour.|r"
    return lines
end

local function buildFarm()
    local rows = {}
    local c = ns.Char()
    local farms = ns.FarmList()
    if not ns.R().lastScan then
        Tx(rows, "No prices yet", "The farms below are sorted properly once I've read the auction house.")
    end
    -- Measured on your own characters first: the mobs that pay best for
    -- this one, with a route through where you killed them.
    local mine = ns.FarmSuggestions(5)
    if #mine > 0 then
        Hd(rows, "From your own kills", "measured, at today's prices")
        for _, e in ipairs(mine) do
            rows[#rows + 1] = ns.FarmSuggestionRow(e)
        end
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
-- Tab: Farming - how your farming is going, and which mobs pay
--
--   This session  the tracker's session as a dashboard
--   Overall       everything measured, the days you farmed, level times
--   Mobs          every mob you've killed enough of, best per kill first
----------------------------------------------------------------------

local FROM = {
    { "kills", "Loot from kills", { 0.95, 0.78, 0.30 }, "What mobs dropped (not greys), at today's prices." },
    { "coin", "Coin off corpses", { 0.86, 0.86, 0.80 }, "Money looted from mobs and chests." },
    { "gather", "Herbs, ore and gathering", { 0.38, 0.80, 0.42 }, "Mining, Herbalism and Skinning." },
    { "fish", "Fishing", { 0.32, 0.60, 0.95 }, "Everything fished up." },
    { "grey", "Greys for the vendor", { 0.55, 0.55, 0.55 }, "Grey items, worth what a vendor pays." },
    { "other", "Chests and other", { 0.82, 0.52, 0.30 }, "Chests, clams and anything else opened." },
}

local function farmView()
    local v = UI.farmView
    return (v == "overall" or v == "mobs") and v or "session"
end

local function vsUsual(perHour, usual)
    if not (perHour and usual and usual > 0) then
        return usual and "" or (GREY .. "your usual shows after a saved trip|r")
    end
    local pct = floor((perHour / usual - 1) * 100 + 0.5)
    if pct >= 0 then
        return "|cff40e060" .. pct .. "% above your usual|r"
    end
    return "|cffff7070" .. -pct .. "% below your usual|r"
end

local function fromRows(rows, from)
    local segs, total = {}, 0
    for _, f in ipairs(FROM) do
        total = total + max(0, from[f[1]] or 0)
    end
    for _, f in ipairs(FROM) do
        segs[#segs + 1] = { value = from[f[1]] or 0, color = f[3] }
    end
    if total <= 0 then
        Tx(rows, nil, "Nothing yet.")
        return
    end
    rows[#rows + 1] = { type = "segbar", segs = segs }
    for _, f in ipairs(FROM) do
        local v = from[f[1]] or 0
        rows[#rows + 1] = { swatch = f[3], title = f[2], key = "from:" .. f[1], onClick = false,
            r1 = v > 0 and ns.Money(v) or (GREY .. "-|r"), r2 = v > 0 and (floor(v / total * 100 + 0.5) .. "%") or "",
            tip = { f[4] } }
    end
end

-- The last ten weeks, Monday first.
local function heatRows(rows)
    local fd = ns.FarmDays()
    local now = time()
    local wd = tonumber(date("%w", now)) or 0
    local monIdx = (wd + 6) % 7
    local start = now - (9 * 7 + monIdx) * 86400
    local cells = {}
    local today = ns.FarmDayKey(now)
    for i = 0, 69 do
        local t = start + i * 86400
        local key = ns.FarmDayKey(t)
        local d = fd.days[key]
        local v = d and d.v or 0
        cells[#cells + 1] = { key = key, v = v, played = d and (d.s or 0) >= 60, future = key > today,
            tip = { date("%a %d %b", t), d and (ns.StripCodes(ns.Money(v)) .. " in " .. ns.Duration(max(1, d.s or 0))
                .. ((d.k or 0) > 0 and (", " .. d.k .. " kills") or "")) or "No farming" } }
    end
    rows[#rows + 1] = { type = "heat", cells = cells }
    local bits = {}
    if fd.streak > 0 then
        bits[#bits + 1] = "|cff40e060" .. fd.streak .. (fd.streak == 1 and " day" or " days") .. " in a row|r"
    end
    bits[#bits + 1] = "Your longest: " .. fd.longest
    if fd.best then
        local y, m, d = fd.best.key:match("^(%d+)-(%d+)-(%d+)$")
        local bt = y and time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
        bits[#bits + 1] = "Best day: " .. ns.Money(fd.best.v) .. (bt and (" on " .. date("%d %b", bt)) or "")
    end
    Tx(rows, nil, table.concat(bits, "   ·   ") .. "\n" .. GREY .. "Brighter is more gold. Only time with the tracker recording counts.|r")
end

local function levelRows(rows)
    local list, cur = ns.LevelTimes()
    local soFar = ns.LevelSoFar()
    if cur then
        rows[#rows + 1] = { noIcon = true, key = "lvl:now", onClick = false,
            title = "Level " .. cur.level .. GREY .. "  (now)|r", sub = cur.partial and "counting since the addon was installed" or nil,
            r1 = ns.Duration(max(1, floor(soFar))), r2 = "so far" }
    end
    for i = 1, min(12, #list) do
        local e = list[i]
        rows[#rows + 1] = { noIcon = true, key = "lvl:" .. e.level, onClick = false,
            title = "Level " .. e.level .. " to " .. (e.level + 1),
            sub = e.partial and "only part of it: the addon arrived mid-level" or nil,
            r1 = ns.Duration(max(1, e.secs)), r2 = e.at and date("%d %b", e.at) or "" }
    end
    if #list == 0 then
        Tx(rows, nil, "Each level's time shows up here after you level, counted while you play.")
    end
end

local function bestMobRows(rows, list, valueOf, extra)
    local top = 0
    for i = 1, min(5, #list) do
        top = max(top, valueOf(list[i]))
    end
    for i = 1, min(5, #list) do
        local m = list[i]
        local d = { title = m.name, key = "best:" .. m.name, onClick = false, bar = top > 0 and valueOf(m) / top or 0,
            icon = m.drops and m.drops[1] and ns.Icon(m.drops[1].id) or "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01" }
        extra(d, m)
        rows[#rows + 1] = d
    end
end

local function farmSession(rows)
    local s = ns.TrackerSummary()
    if not s then
        Tx(rows, "No session recording", "Press Start on the Farming Session window (the button above) and go farm. "
            .. "This page fills in as you go: gold an hour against your usual, where it came from, your luck and your best mobs.")
        Hd(rows, "Days you farmed", "Last 10 weeks")
        heatRows(rows)
        Hd(rows, "How long each level took", "This character, time played")
        levelRows(rows)
        return
    end
    local usual = ns.FarmUsualPerHour(s.started)
    local most = s.mobs[1]
    rows[#rows + 1] = { type = "cards", cards = {
        { cap = "Gold an hour", value = s.perHour and ns.Money(s.perHour) or (GREY .. "after 1 min|r"), sub = vsUsual(s.perHour, usual),
            tip = { "Gold an hour", "What you've made (coin plus loot at today's prices) for the time recorded.",
                usual and ("Your usual: " .. ns.StripCodes(ns.Money(usual)) .. " an hour, from your saved trips.") or nil } },
        { cap = "Gold this session", value = ns.Money(s.made), sub = GREY .. "In " .. ns.Duration(max(1, s.secs)) .. " of farming|r",
            tip = { "Gold this session", "Coin looted plus everything looted, valued the better way to sell it." } },
        { cap = "Kills this session", value = tostring(s.kills),
            sub = GREY .. (s.secs > 60 and (floor(s.kills / s.secs * 3600 + 0.5) .. " kills an hour") or "kills an hour after 1 min") .. "|r" },
        { cap = "Killed most", value = most and most.name or (GREY .. "nobody yet|r"), sub = most and (GREY .. most.n .. " kills|r") or "" },
    } }
    Hd(rows, "Gold this session", usual and "Your gold so far vs. your usual pace" or "Your gold so far")
    local pts = {}
    pts[1] = { 0, 0 }
    for _, p in ipairs(s.timeline or {}) do
        if p[1] > pts[#pts][1] then
            pts[#pts + 1] = { p[1], p[2] }
        end
    end
    if s.secs > pts[#pts][1] then
        pts[#pts + 1] = { s.secs, floor(s.made) }
    end
    rows[#rows + 1] = { type = "graph", points = pts, height = 170,
        graph = { duration = true, smooth = true, ref = usual and usual / 3600 or nil,
            endText = #pts > 1 and (ns.StripCodes(ns.Money(s.made)) .. " so far") or nil,
            emptyText = "The line starts after your first minute." } }
    Hd(rows, "Vendor or auction", "Everything looted this session, both ways")
    rows[#rows + 1] = { icon = COIN, key = "sell:vendor", onClick = false, title = "Sell it all to a vendor",
        sub = "Coin plus what shopkeepers pay for every item",
        r1 = ns.Money(s.vendorTotal), r2 = s.vendorPerHour and (ns.Money(s.vendorPerHour) .. GREY .. " an hour|r") or "" }
    rows[#rows + 1] = { icon = "Interface\\Icons\\INV_Misc_Coin_02", key = "sell:auction", onClick = false,
        title = "Auction it (vendor what has no price)",
        sub = "Coin plus the lowest auction price after the 5% cut",
        r1 = ns.Money(s.auctionTotal), r2 = s.auctionPerHour and (ns.Money(s.auctionPerHour) .. GREY .. " an hour|r") or "" }
    Hd(rows, "Where your gold came from", "This session")
    fromRows(rows, s.from or {})
    Hd(rows, "Best mobs for gold", "Mobs you killed this session")
    local mobs = ns.TrackerMobs("value")
    if #mobs == 0 then
        Tx(rows, nil, "No kills yet.")
    end
    bestMobRows(rows, mobs, function(m) return m.value end, function(d, m)
        d.sub = m.k .. " kills  ·  " .. ns.StripCodes(ns.Money(m.perKill)) .. " a kill"
        d.r1 = ns.Money(m.value)
    end)
    Hd(rows, "Your luck this session", "Your drops vs. your own usual drop rates")
    local luck = ns.FarmLuck()
    if luck then
        local pct = floor(luck.pct * 100 + 0.5)
        rows[#rows + 1] = { noIcon = true, key = "luck", onClick = false,
            title = (pct >= 0 and ("|cff40e060" .. pct .. "% luckier|r") or ("|cffff7070" .. -pct .. "% less lucky|r")),
            sub = "Over " .. luck.kills .. " kills of mobs you've killed before" }
        rows[#rows + 1] = { type = "meter", value = luck.pct }
        for i = 1, min(4, #luck.items) do
            local e = luck.items[i]
            rows[#rows + 1] = { id = e.id, key = "luck:" .. e.id, title = ns.ItemName(e.id), onClick = false,
                r1 = tostring(e.got), r2 = "about " .. (floor(e.expected * 10 + 0.5) / 10) .. " expected" }
        end
    else
        Tx(rows, nil, "Once you've killed " .. 20 .. " of a mob in earlier sessions, this compares what drops now with what usually drops.")
    end
    Hd(rows, "Days you farmed", "Last 10 weeks")
    heatRows(rows)
    Hd(rows, "How long each level took", "This character, time played")
    levelRows(rows)
end

local function farmOverall(rows)
    local o = ns.FarmOverall()
    rows[#rows + 1] = { type = "cards", cards = {
        { cap = "Gold an hour", value = o.perHour and ns.Money(o.perHour) or (GREY .. "-|r"),
            sub = GREY .. "every recorded minute|r" },
        { cap = "Gold farmed", value = ns.Money(o.value), sub = GREY .. "In " .. ns.Duration(max(1, o.secs)) .. " of farming|r",
            tip = { "Gold farmed", "Everything the tracker recorded over the last 120 days." } },
        { cap = "Kills", value = tostring(o.kills), sub = GREY .. "recorded|r" },
        { cap = "Killed most", value = o.most and o.most.name or (GREY .. "nobody yet|r"),
            sub = o.most and (GREY .. o.most.k .. " kills, all time|r") or "" },
    } }
    Hd(rows, "Gold farmed over time", "Day by day, added up")
    local keys = {}
    for key in pairs(ns.db.farmDays or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    local pts, sum = {}, 0
    for _, key in ipairs(keys) do
        local y, m, d = key:match("^(%d+)-(%d+)-(%d+)$")
        local t = y and time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
        if t then
            if #pts == 0 then
                pts[1] = { t - 86400, 0 }
            end
            sum = sum + (ns.db.farmDays[key].v or 0)
            pts[#pts + 1] = { t, sum }
        end
    end
    rows[#rows + 1] = { type = "graph", points = pts, height = 150,
        graph = { smooth = true, emptyText = "Record a session or two and this fills in." } }
    Hd(rows, "Where your gold came from", "Everything recorded")
    fromRows(rows, o.from)
    Hd(rows, "Best mobs for gold", "Per kill, all your characters")
    local ranked = ns.MobRanking()
    if #ranked == 0 then
        Tx(rows, nil, "Mobs are ranked after " .. ns.FARM_RANK_MIN .. " kills with the tracker on.")
    end
    bestMobRows(rows, ranked, function(m) return m.perKill end, function(d, m)
        d.sub = m.k .. " kills" .. (m.where and ("  ·  " .. m.where) or "")
        d.r1 = ns.Money(m.perKill)
        d.r2 = "a kill"
    end)
    Hd(rows, "Days you farmed", "Last 10 weeks")
    heatRows(rows)
    Hd(rows, "How long each level took", "This character, time played")
    levelRows(rows)
end

local function levelText(m)
    if not m.lo then
        return nil
    end
    return "level " .. (m.lo == m.hi and m.lo or (m.lo .. "-" .. m.hi))
end

-- The details pane for a ranked mob: drops, pace, and a route.
local function mobDetail(m)
    local lines = {
        { "Worth a kill", ns.Money(m.perKill), total = true },
        { "Coin a kill", ns.Money(m.coin / max(1, m.k)) },
        { "Kills an hour", floor(m.killsHr + 0.5) .. (m.speedMeasured and "" or GREY .. " (typical)|r") },
        { "Gold an hour", "~" .. ns.Money(m.perHour) },
        { "Killed", m.k .. " times" },
        " ",
    }
    for i = 1, min(8, #m.drops) do
        local d = m.drops[i]
        lines[#lines + 1] = { ns.ItemName(d.id), floor(d.rate * 100 + 0.5) .. "%  " .. GREY .. ns.StripCodes(ns.Money(d.each)) .. "|r" }
    end
    local zones = {}
    for i = 1, min(3, #m.zones) do
        zones[i] = m.zones[i].name
    end
    local canRoute = m.spots >= 2
    return { sub = table.concat(zones, ", ") .. (levelText(m) and ("  ·  " .. levelText(m)) or ""),
        lines = lines,
        caption = "drops: share of kills, worth each",
        note = "Measured on your own characters, at today's prices." .. (m.speedMeasured and "" or " Kills an hour is a typical pace until you've killed a few in a row."),
        action = canRoute and { label = "Route through where you killed them", onClick = function()
            if ns.StartMobRoute(m.name) then
                ns.ShowTab("routes")
            end
        end } or { label = "Kill a few more for a route", disabled = true, onClick = function() end },
        action2 = false }
end
ns.FarmMobDetail = mobDetail

local function farmMobs(rows)
    local ranked = ns.MobRanking({ outside = UI.mobOutside, skipGood = UI.mobSkipGood })
    if #ranked == 0 then
        Tx(rows, "No mobs ranked yet", "Turn on the Farming Session tracker and kill things: every mob you've killed "
            .. ns.FARM_RANK_MIN .. " times shows here, ranked by what a kill is worth at today's prices, with where and how fast.")
        return
    end
    Hd(rows, "Your kills, best per kill first", plural(#ranked, "mob") .. "  ·  coin included")
    local top = ranked[1].perKill
    for i, m in ipairs(ranked) do
        local where = {}
        if m.best then
            where[#where + 1] = "Best drop: " .. ns.ItemName(m.best.id) .. " (" .. floor(m.best.rate * 100 + 0.5) .. "%)"
        end
        if m.where then
            where[#where + 1] = m.where
        end
        if levelText(m) then
            where[#where + 1] = levelText(m)
        end
        if m.inst then
            where[#where + 1] = "dungeon"
        end
        local rank = i <= 3 and ("|cffffd100" .. i .. ".|r ") or (GREY .. i .. ".|r ")
        rows[#rows + 1] = { key = "mob:" .. m.name, title = rank .. m.name,
            id = m.best and m.best.id, sub = table.concat(where, "  ·  "),
            bar = top > 0 and m.perKill / top or 0,
            r1 = ns.Money(m.perKill) .. GREY .. " a kill|r",
            r2 = m.k .. " kills  ·  ~" .. ns.StripCodes(ns.Money(m.perHour)) .. "/hr",
            detail = function() return mobDetail(m) end }
    end
end

local function buildFarming()
    local rows = {}
    local v = farmView()
    if v == "overall" then
        farmOverall(rows)
    elseif v == "mobs" then
        farmMobs(rows)
    else
        farmSession(rows)
    end
    return rows
end

local function farmingToolbar()
    local bar = {}
    for _, m in ipairs({ { "session", "This session" }, { "overall", "Overall" }, { "mobs", "Mobs" } }) do
        local key = m[1]
        bar[#bar + 1] = { label = m[2], width = 92, on = farmView() == key, onClick = function()
            UI.farmView = key
            ns.RefreshUI()
        end }
    end
    bar[#bar].gap = 24
    if farmView() == "mobs" then
        bar[#bar + 1] = { label = "Outside dungeons", width = 120, on = UI.mobOutside and true or false, onClick = function()
            UI.mobOutside = not UI.mobOutside or nil
            ns.RefreshUI()
        end }
        bar[#bar + 1] = { label = "Skip green+", width = 90, on = UI.mobSkipGood and true or false, onClick = function()
            UI.mobSkipGood = not UI.mobSkipGood or nil
            ns.RefreshUI()
        end }
        bar.text = "Ranked after " .. ns.FARM_RANK_MIN .. " kills."
    else
        bar[#bar + 1] = { label = "Farming Session", width = 130, on = ns.TrackerWindowShown and ns.TrackerWindowShown(),
            onClick = function() ns.ToggleTrackerWindow() end }
        bar.text = farmView() == "session" and "Updates as you farm." or "Every recorded minute, all characters."
    end
    return bar
end

-- Suggested farms from your own kills, as rows (Make > Farm and To do).
local function suggestionRow(e, prefix)
    local bits = {}
    if e.where then
        bits[#bits + 1] = e.where
    end
    if levelText(e) then
        bits[#bits + 1] = levelText(e)
    end
    bits[#bits + 1] = floor(e.killsHr + 0.5) .. " kills an hour" .. (e.speedMeasured and "" or " (typical)")
    return { icon = e.best and ns.Icon(e.best.id) or "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
        key = (prefix or "farm:") .. e.name, title = "Kill " .. e.name,
        sub = (prefix and "Farm  ·  " or "") .. table.concat(bits, "  ·  "),
        r1 = "~" .. ns.Money(e.perHour), r2 = e.vsUsual and (e.vsUsual >= 0 and ("|cff40e060+" .. floor(e.vsUsual * 100 + 0.5) .. "%|r vs your usual")
            or "an hour, measured") or "an hour, measured",
        detail = function() return mobDetail(e) end }
end
ns.FarmSuggestionRow = suggestionRow

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
            rows[#rows + 1] = { id = u.id, key = "undercut:" .. u.id, title = u.count .. " x " .. ns.ItemName(u.id),
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
        local speed = ns.SaleText and ns.SaleText(b.id, "mid")
        local sub = "Lowest price " .. ns.Money(b.price) .. GREY .. " each  -  "
            .. (speed and ("|r" .. speed .. GREY) or ((b.listed or 0) .. " listed"))
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
        local function detail()
            local gross = b.total / (1 - CUT)
            local lines = { { "You have", tostring(b.count) }, { "Lowest price each", ns.Money(b.price) },
                { "All of them", ns.Money(gross) }, { "Auction house cut (5%)", "-" .. ns.Money(gross - b.total) },
                { "Est. after the cut", ns.Money(b.total), total = true }, " " }
            if not b.craft and b.vendor and b.vendor > 0 then
                lines[#lines + 1] = { "A vendor would pay", ns.Money(b.vendor * b.count) }
            end
            local r = ns.SaleRate and ns.SaleRate(b.id)
            if r and r.perDay then
                lines[#lines + 1] = { "Sold a day, region", "~" .. floor(r.perDay + 0.5) }
                if r.through and r.through >= 0 then
                    lines[#lines + 1] = { "Listings that sold", r.through .. "%" }
                end
            end
            for i = 2, #tip do
                lines[#lines + 1] = tip[i]
            end
            return { lines = lines, note = ESTIMATE,
                action = ns.ahOpen and { label = "Sell " .. ns.ItemName(b.id), onClick = function() ns.OpenSell(b.id) end }
                    or { label = "Sell (at an auctioneer)", disabled = true } }
        end
        rows[#rows + 1] = { id = b.id, title = b.count .. " x " .. ns.ItemName(b.id), sub = sub,
            tipTitle = ns.ItemName(b.id), tip = tip, detail = detail, r1 = ns.Money(b.total),
            r2 = (ns.SaleVerdict and ns.SaleVerdict(b.id)) or "for all, after the cut",
            btn = sellButton(b.id) }
    end
    if #bag.unlisted > 0 then
        Hd(rows, "Nobody is selling these - you'd be the only seller")
        for _, b in ipairs(bag.unlisted) do
            rows[#rows + 1] = { id = b.id, title = b.count .. " x " .. ns.ItemName(b.id),
                sub = b.last and ("Last seen at " .. ns.Money(b.last) .. GREY .. " each. With no competition you can ask a bit more.")
                    or "Never seen for sale. Try one at a price you'd be happy with.",
                r1 = b.last and ns.Money(b.last) or "", r2 = b.last and "last price seen" or "",
                btn = sellButton(b.id) }
        end
    end
    if #bag.vendor > 0 then
        Hd(rows, "Just sell these to a vendor", ns.Money(bag.vendorTotal))
        for _, b in ipairs(bag.vendor) do
            rows[#rows + 1] = { id = b.id, title = b.count .. " x " .. ns.ItemName(b.id),
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
        rows[#rows + 1] = { id = f.id, title = ns.ItemName(f.id), tipTitle = ns.ItemName(f.id),
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
        local tip = { "Buy it from " .. (v.npc or "the vendor") .. (v.zone and v.zone ~= "" and (" in " .. v.zone) or "")
            .. " for " .. ns.Money(v.buy) .. ", and list it on the auction house"
            .. (v.how == "sold" and " - it has sold for " or " - it's listed at ") .. ns.Money(v.price) .. ".",
            (v.listed or 0) .. " listed right now. With few sellers, don't flood the market - list one or two." }
        if v.how == "sold" then
            tip[#tip + 1] = "These have actually been selling for about " .. ns.Money(v.net / (1 - CUT)) .. " each."
        elseif v.limited then
            tip[#tip + 1] = "This vendor only stocks a few at a time, which is exactly why other players pay extra."
        else
            tip[#tip + 1] = "|cffff7070Not proven:|r that's only what people are asking. Try ONE before buying more."
        end
        rows[#rows + 1] = { id = v.id, title = ns.ItemName(v.id), tipTitle = ns.ItemName(v.id), dim = not v.sure,
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
        rows[#rows + 1] = { id = b.id, title = ns.ItemName(b.id), tipTitle = ns.ItemName(b.id),
            sub = "Now " .. ns.Money(b.price) .. GREY .. "  -  usually |r" .. ns.Money(b.usual) .. GREY .. "  ("
                .. b.days .. " days of prices)  -  " .. b.listed .. " listed",
            tip = { "If the price returns to its usual level, buying now and relisting would earn about "
                .. ns.Profit(b.profit) .. " each after the cut.",
                "Risk: prices on a new realm often fall for good as more people reach higher levels." },
            r1 = ns.Profit(b.profit), r2 = "each, if it recovers" }
    end
    return rows
end

----------------------------------------------------------------------
-- Tab: Routes
----------------------------------------------------------------------

UI.routeKinds = { ore = true, herb = true, fish = false, chest = false }
UI.routeStart = {} -- [mapID] = the spot you chose to start from
UI.zoneMenu = nil  -- nil, "open" or "confirm"

local function selectedRouteMap()
    if UI.routeMap and ns.db.nodes[UI.routeMap] then
        return UI.routeMap
    end
    local here = ns.PlayerMapPos()
    if here and ns.db.nodes[here] and #ns.db.nodes[here] > 0 then
        return here
    end
    local zones = ns.NodeZones()
    return zones[1] and zones[1].map or nil
end

local function zoneInfo(mapID)
    for _, z in ipairs(ns.NodeZones()) do
        if z.map == mapID then
            return z
        end
    end
    return nil
end

-- Picking a zone: bring back its saved settings, and if what's ticked
-- matches none of its spots, tick what it does have.
local function selectZone(mapID)
    UI.routeMap = mapID
    UI.zoneMenu = nil
    local saved = ns.db.routes[mapID]
    local k = UI.routeKinds
    if saved and saved.kinds then
        for _, kind in ipairs(ns.KIND_ORDER) do
            k[kind] = saved.kinds[kind] and true or false
        end
        UI.routeStart[mapID] = UI.routeStart[mapID] or ns.SavedStart(mapID)
    end
    local z = zoneInfo(mapID)
    if z and #ns.MatchingNodes(mapID, k) == 0 then
        for _, kind in ipairs(ns.KIND_ORDER) do
            if (z[kind] or 0) > 0 then
                k[kind] = true
            end
        end
    end
end

-- The suggested loop for the picked zone, worked out again only when the
-- zone, the ticks, the start or the spots change.
local planVersion = 0
local function currentPlan()
    local mapID = selectedRouteMap()
    if not mapID then
        return nil, nil
    end
    local k = UI.routeKinds
    local start = UI.routeStart[mapID]
    local key = mapID .. ":" .. (k.ore and "o" or "") .. (k.herb and "h" or "") .. (k.fish and "f" or "")
        .. (k.chest and "c" or "") .. ":"
        .. planVersion .. ":" .. tostring(start)
    if UI.planKey ~= key then
        UI.planKey = key
        UI.plan, UI.planWhy = ns.PlanRoute(mapID, k, start)
    end
    return UI.plan, UI.planWhy
end

local function routesShown()
    return UI.tab == "make" and UI.makeMode == "routes"
end

ns.Listen("NODES_UPDATED", function()
    planVersion = planVersion + 1
    if routesShown() then
        ns.Later("ui-refresh", 0.2, function() ns.RefreshUI(true) end)
    end
end)

local function mainKind(z)
    local best, bestN = "herb", -1
    for _, kind in ipairs(ns.KIND_ORDER) do
        if (z[kind] or 0) > bestN then
            best, bestN = kind, z[kind] or 0
        end
    end
    return best
end

local function buildRoutes()
    local rows = {}
    local zones = ns.NodeZones()
    if #zones == 0 then
        Tx(rows, "No spots recorded yet",
            "Just play: every ore vein you mine, herb you pick and place you catch a fish is remembered with its exact position. After a lap or two of a zone, come back here and pick it.\n\nFarm (next to Routes above) tells you which zones to head for.")
        return rows
    end
    local sel = selectedRouteMap()
    -- Grouped by continent, filtered by the search box above the list.
    local filter = (UI.zoneFilter or ""):lower():match("^%s*(.-)%s*$")
    local groups, order = {}, {}
    for _, z in ipairs(zones) do
        local cont = ns.ContinentOf(z.map)
        local cname = cont and cont.name or "Other places"
        if filter == "" or z.name:lower():find(filter, 1, true) or cname:lower():find(filter, 1, true) then
            local g = groups[cname]
            if not g then
                g = { name = cname, other = not cont, zones = {}, spots = 0 }
                groups[cname] = g
                order[#order + 1] = g
            end
            g.zones[#g.zones + 1] = z
            g.spots = g.spots + z.total
        end
    end
    if #order == 0 then
        Tx(rows, nil, "No zones or continents match \"" .. (UI.zoneFilter or "") .. "\".")
        return rows
    end
    table.sort(order, function(a, b)
        if a.other ~= b.other then
            return not a.other
        end
        return a.name < b.name
    end)
    for _, g in ipairs(order) do
        Hd(rows, g.name, plural(g.spots, "spot"))
        for _, z in ipairs(g.zones) do
            local mapID = z.map
            local marks = ""
            if ns.route and ns.route.map == mapID then
                marks = "  |cffffd100route on|r"
            elseif ns.db.routes[mapID] then
                marks = GREY .. "  saved|r"
            end
            rows[#rows + 1] = { icon = ns.KINDS[mainKind(z)].icon, key = "zone:" .. mapID, isSel = mapID == sel,
                title = z.name .. marks, sub = ns.ZoneSummary(z),
                onClick = function()
                    selectZone(mapID)
                    ns.RefreshUI(true)
                end }
        end
    end
    return rows
end

----------------------------------------------------------------------
-- Tab: Tips
----------------------------------------------------------------------

local function optionRow(rows, key, text)
    local on = ns.db.opts[key]
    rows[#rows + 1] = { noIcon = true, title = (on and "|cff40e060[on]|r  " or "|cffff7070[off]|r  ") .. text,
        sub = "Click to turn " .. (on and "off" or "on"),
        onClick = function()
            ns.db.opts[key] = not ns.db.opts[key]
            ns.RefreshUI(true)
            if ns.RedrawWorldMap then
                ns.RedrawWorldMap()
            end
        end }
end

local DEAL_STEPS = { 100, 500, 2500, 10000 }

local function dealMinRow(rows)
    local cur = ns.db.opts.dealMin or 500
    rows[#rows + 1] = { noIcon = true, title = "Smallest profit worth showing on the Buy tab: " .. ns.Money(cur),
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
    rows[#rows + 1] = { noIcon = true,
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

-- A setting that steps through a few choices each click.
local function cycleRow(rows, key, steps, default, title, labels, sub)
    local cur = ns.db.opts[key] or default
    rows[#rows + 1] = { noIcon = true, title = title .. ": |cffffd100" .. (labels[cur] or cur) .. "|r",
        sub = sub, onClick = function()
            local nextStep = steps[1]
            for i, v in ipairs(steps) do
                if v == cur then
                    nextStep = steps[(i % #steps) + 1]
                end
            end
            ns.db.opts[key] = nextStep
            ns.RefreshUI(true)
        end }
end

-- Mailbox settings: the same switches as the mailbox window, in one place.
local RESERVE_STEPS = { 0, 10000, 50000, 100000, 500000, 1000000 }

local function mailRefresh()
    ns.RefreshUI(true)
    if ns.MailUI and ns.MailUI.Refresh then
        ns.MailUI.Refresh()
    end
end

local function mailSwitch(rows, on, text, sub, flip)
    rows[#rows + 1] = { noIcon = true, title = (on and "|cff40e060[on]|r  " or "|cffff7070[off]|r  ") .. text,
        sub = sub and (sub .. "  Click to turn " .. (on and "off." or "on.")) or ("Click to turn " .. (on and "off" or "on")),
        onClick = function()
            flip(not on)
            mailRefresh()
        end }
end

local function mailRows(rows)
    local opts = ns.db.opts
    local U = ns.MailUI
    mailSwitch(rows, not opts.mailBlizzard, "Use the Forever Gold mailbox window instead of the game's",
        "Off: the game's own mailbox, with a button above it to switch back.",
        function(on)
            if U and ns.Mail and ns.Mail.open then
                if on then U.UseOurs() else U.UseBlizzard() end
            else
                opts.mailBlizzard = (not on) or nil
            end
        end)
    mailSwitch(rows, opts.mailPrompt ~= false, "Ask to send what my rules match when I open a mailbox",
        "Shows what would go where, with Send now, Review first or Not now.",
        function(on) opts.mailPrompt = on end)
    mailSwitch(rows, opts.mailAuto == true, "Send what my rules match by itself when I open a mailbox",
        "No asking: it starts sending as soon as the mailbox opens.",
        function(on) opts.mailAuto = on end)
    mailSwitch(rows, opts.mailGold == true, "Quick-send to my banker also sends my spare gold",
        "Everything above \"Keep at least\" after postage.",
        function(on) opts.mailGold = on end)
    local cur = (ns.Mail and ns.Mail.Reserve) and ns.Mail.Reserve() or 0
    rows[#rows + 1] = { noIcon = true,
        title = "Keep at least this much gold when mailing: |cffffd100" .. (cur > 0 and ns.Money(cur) or "nothing") .. "|r",
        sub = "Click to change (nothing, 1g, 5g, 10g, 50g or 100g). Postage counts. The mailbox's Send tab takes any amount.",
        onClick = function()
            local nextStep = RESERVE_STEPS[1]
            for i, v in ipairs(RESERVE_STEPS) do
                if v == cur then
                    nextStep = RESERVE_STEPS[(i % #RESERVE_STEPS) + 1]
                end
            end
            opts.mailReserve = nextStep
            mailRefresh()
        end }
    local banker = ns.Mail and ns.Mail.NameOf and ns.Mail.NameOf(ns.Mail.BankerKey())
    Tx(rows, nil, "Your banker" .. (banker and (" is |cffffd100" .. banker .. "|r") or "")
        .. ". Rules, the banker and what quick-send includes are set in the mailbox window (Send and Rules tabs).")
end

local function buildTips()
    local rows = {}
    Hd(rows, "Selling")
    cycleRow(rows, "postUndercut", ns.UNDERCUT_STEPS, "copper", "Undercut the cheapest listing by",
        { copper = "1 copper", ["1%"] = "1%", ["5%"] = "5%" },
        "Click to change. Never goes below your floor, and never undercuts your own auctions.")
    cycleRow(rows, "postQty", ns.POST_QTY_STEPS, "stack", "Each listing holds",
        { stack = "one full stack", ["10"] = "10", ["5"] = "5", all = "everything you have", one = "one item" },
        "Click to change. With one full stack, Post all lists your stacks one at a time.")
    cycleRow(rows, "sellDuration", { 1, 2, 3 }, 2, "Auctions last",
        { [1] = ns.SellDurationLabel(1), [2] = ns.SellDurationLabel(2), [3] = ns.SellDurationLabel(3) },
        "Click to change. Longer costs a bigger deposit.")
    Hd(rows, "Settings")
    optionRow(rows, "autoScan", "Read prices automatically when I open the auction house")
    autoAgeRow(rows)
    optionRow(rows, "fastScan", "Fast scan: download the whole auction house at once (the game allows it every 15 minutes)")
    dealMinRow(rows)
    optionRow(rows, "buyConfirm", "Ask before I buy at 20% or more over an item's usual price")
    optionRow(rows, "tooltip", "Show auction prices when I hover over an item")
    optionRow(rows, "waypoint", "Use the game's map waypoint for the next stop on a route")
    optionRow(rows, "worldMapSpots", "Show my gathering spots and route on the world map (OpenMap too)")
    optionRow(rows, "mapButton", "A gathering button on the world map, to filter herbs, ore, fishing and chests")
    optionRow(rows, "minimapSpots", "Show my gathering spots and the next stop on the minimap")
    optionRow(rows, "onlyMyProfs", "Only show herbs, ore and fishing spots (map, minimap and beams) when this character has Herbalism, Mining or Fishing")
    optionRow(rows, "revealMap", "Draw the whole zone on the Routes map, not just the parts I've explored")
    optionRow(rows, "lootBeam", "Loot beams: gold on a route stop, white on a spot I've recorded, light blue on one I haven't")
    optionRow(rows, "nearestBeam", "With no route running, put a white beam on the nearest spot I've recorded (only when I'm not tracking anything else)")
    optionRow(rows, "beamUnrecorded", "Beam on herbs, veins and chests right in front of me, recorded or not (turns on the game's Interact Key and its icons)")
    Hd(rows, "Bags")
    do
        local on = ns.db.opts.bagUI ~= false
        rows[#rows + 1] = { noIcon = true, title = (on and "|cff40e060[on]|r  " or "|cffff7070[off]|r  ")
            .. "Forever Gold bags: all your bags in one window, your other characters' bags and banks, banker marks and Sell junk",
            sub = "Click to turn " .. (on and "off (the game's own bags come back)" or "on"),
            onClick = function()
                if not ns.BagUI then
                    return
                end
                if on then
                    ns.db.opts.bagUI = false
                    ns.BagUI.Uninstall()
                else
                    ns.BagUI.Enable()
                end
                ns.RefreshUI(true)
            end }
    end
    optionRow(rows, "bagTooltip", "Item tooltips say which of my characters have it, in their bags or bank")
    Hd(rows, "Mailbox")
    mailRows(rows)
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
                    rows[#rows + 1] = { id = id, title = ns.ItemName(id),
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
        bar[#bar + 1] = { label = "Farming Session", width = 130, on = ns.TrackerWindowShown and ns.TrackerWindowShown(),
            onClick = function() ns.ToggleTrackerWindow() end }
        bar.text = "Measures your real gold per hour."
    elseif mode == "routes" then
        -- What to include and the route buttons live with the map, not here.
        bar.text = "Pick a zone; the map previews a loop through your spots."
    end
    return bar
end

local TABS = {
    { key = "todo", label = "To do", build = buildTodo },
    { key = "sell", label = "Sell", build = buildBags,
        toolbar = function()
            if not ns.ahOpen or not ns.R().lastScan then
                return nil
            end
            local n = #ns.BagAdvice().ah
            local busy = ns.PostQueue and ns.PostQueue() ~= nil
            return { { label = busy and "Posting..." or ("Post all (" .. n .. ")"), width = 110,
                onClick = function() ns.StartPostAll() end },
                text = "One click per listing. Undercut and stack size are under Settings." }
        end },
    { key = "buy", label = "Buy", build = buildDeals },
    { key = "make", label = "Make", build = buildMake, toolbar = makeToolbar,
        plot = function() return makeMode() == "routes" end },
    { key = "farming", label = "Farming", build = buildFarming, toolbar = farmingToolbar,
        wide = function() return farmView() ~= "mobs" end },
    { key = "chars", label = "Characters", build = buildChars, toolbar = charsToolbar },
}
-- Opened with the Settings button at the top right, not a tab of its own.
local SETTINGS = { key = "settings", label = "Settings", build = buildTips }

-- Older names for the tabs, still used in a few places.
local TAB_ALIAS = { characters = { "chars" }, today = { "todo" }, bags = { "sell" }, deals = { "buy" }, tips = { "settings" },
    craft = { "make", "craft" }, farm = { "make", "farm" }, routes = { "make", "routes" }, mobs = { "farming" } }

----------------------------------------------------------------------
-- The main window
----------------------------------------------------------------------

local main

-- The Routes page's footer: the route, your spots, when you last gathered.
local function routeFooter()
    local parts = {}
    local r = ns.route
    if r then
        local step, n, lap = ns.RouteProgress(r)
        parts[1] = (r.paused and "Route paused" or "Route running") .. " in " .. ns.MapName(r.map) .. ": stop " .. step
            .. " of " .. n .. (lap > 1 and (", lap " .. lap) or "")
    else
        parts[1] = "No route running"
    end
    local total, last, zones = 0, 0, ns.NodeZones()
    for _, z in ipairs(zones) do
        total = total + z.total
        last = max(last, z.last or 0)
    end
    parts[2] = plural(total, "spot") .. " recorded in " .. plural(#zones, "zone")
    if last > 0 then
        parts[3] = "last gathered " .. ns.Ago(last)
    end
    return table.concat(parts, GREY .. "  ·  |r")
end

local function refreshFooter()
    if not main or not main:IsShown() then
        return
    end
    local routes = routesShown()
    main.status:SetText(routes and routeFooter() or ns.ScanStatus())
    main.scanButton:SetShown(not routes)
    main.scanButton:SetDisabled(not ns.ahOpen or ns.scan.active)
    main.scanButton:SetLabel(ns.scan.active and "Scanning..." or "Scan now")
    main.money:SetText(ns.Money(ns.Char().money or 0))
end

----------------------------------------------------------------------
-- The Routes map panel: what to include, the map, and the route buttons
----------------------------------------------------------------------

local MAP_W, MAP_H = 540, 360
local PANEL_H = 30 + MAP_H + 64

local function withCommas(n)
    local s = tostring(floor(n))
    while true do
        local t, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        s = t
        if k == 0 then
            return s
        end
    end
end

local function kindList(k)
    local out = {}
    for _, kind in ipairs(ns.KIND_ORDER) do
        if k[kind] then
            out[#out + 1] = ns.KINDS[kind].label
        end
    end
    return table.concat(out, " + ")
end

local function routeHere(mapID)
    local r = ns.route
    return r and r.map == mapID and r or nil
end

local function nodeClick(n, which)
    local mapID = selectedRouteMap()
    if not mapID then
        return
    end
    local r = routeHere(mapID)
    if which == "RightButton" then
        if r then
            -- On a running route: go to this stop next.
            for i, p in ipairs(r.pts) do
                if p == n then
                    r.i = i
                    ns.SetRouteWaypoint()
                    ns.Fire("ROUTE")
                    return
                end
            end
            ns.Print("that spot isn't on the route you're running.")
        else
            if n.skip then
                ns.SetNodeSkipped(n, false)
            end
            UI.routeStart[mapID] = n
            ns.RefreshUI(true)
        end
        return
    end
    ns.SetNodeSkipped(n, not n.skip)
end

local function nodeEnter(marker, n)
    if not GameTooltip then
        return
    end
    local kind = ns.KINDS[n.k]
    GameTooltip:SetOwner(marker, "ANCHOR_RIGHT")
    GameTooltip:AddLine(n.n or (kind and kind.label) or "Spot", 1, 0.82, 0)
    GameTooltip:AddLine((kind and kind.one or "spot") .. " - gathered " .. plural(n.c or 1, "time") .. ", last "
        .. ns.Ago(n.t), 0.8, 0.8, 0.8)
    if n.skip then
        GameTooltip:AddLine("Left out of routes.", 1, 0.45, 0.45)
    end
    local r = routeHere(selectedRouteMap())
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: " .. (n.skip and "put it back in the route" or "leave it out of the route")
        .. (r and " (from the next route you start)" or ""), 1, 1, 1)
    GameTooltip:AddLine(r and "Right-click: go here next" or "Right-click: start the route here", 1, 1, 1)
    GameTooltip:Show()
end

local function refreshRoutePanel()
    if not main or not main.plot:IsShown() then
        return
    end
    local P = main.plot
    local mapID = selectedRouteMap()
    local k = UI.routeKinds
    local z = mapID and zoneInfo(mapID)
    -- Writing on the map sits above the spots; the zone menu above everything.
    local base = P.map:GetFrameLevel() or 1
    P.over:SetFrameLevel(base + 12)
    P.menu:SetFrameLevel(base + 20)
    for _, cb in ipairs(P.checks) do
        cb:SetChecked(k[cb.kind])
        cb:SetCount(z and z[cb.kind] or 0)
    end
    local matching, skipped = {}, 0
    if mapID then
        matching, skipped = ns.MatchingNodes(mapID, k)
    end
    P.count:SetText(#matching .. " matching " .. (#matching == 1 and "spot" or "spots")
        .. (skipped > 0 and (GREY .. ", " .. skipped .. " left out|r") or ""))
    P.zoneBtn:SetDisabled(not mapID)

    -- The map
    local r = ns.route
    local plan, why
    if not routeHere(mapID) then
        plan, why = currentPlan()
    end
    local showing = routeHere(mapID) or plan
    local info = main.plotter:Draw(mapID, MAP_W, MAP_H, { kinds = k, route = showing, player = true, size = 13,
        art = true, interactive = true, onClick = nodeClick, onEnter = nodeEnter })
    P.title:SetText(mapID and ns.MapName(mapID) or "")
    P.titleBg:SetShown(mapID ~= nil)
    P.titleBg:SetWidth(max(80, min(300, (P.title:GetStringWidth() or 200) + 16)))
    for _, g in ipairs(P.grid) do
        g:SetShown(info.art ~= "ok" and info.art ~= "loading")
    end

    -- Say why the map looks the way it does, rather than leave it blank.
    local msg
    local total = z and z.total or 0
    if not mapID then
        msg = "No gathering spots recorded yet.\nMine, pick herbs or fish anywhere and they'll show up here."
    elseif total == 0 then
        msg = "No spots recorded in " .. ns.MapName(mapID) .. " yet."
    elseif not (k.ore or k.herb or k.fish) then
        msg = "Nothing is included.\nTick Herbs, Ore or Fishing above to see your spots."
    elseif info.shown == 0 then
        local have = {}
        for _, kind in ipairs(ns.KIND_ORDER) do
            if (z[kind] or 0) > 0 then
                have[#have + 1] = ns.KINDS[kind].label
            end
        end
        msg = "None of this zone's " .. plural(total, "spot") .. " match what's ticked.\nTick " .. table.concat(have, " or ")
            .. " above to see them."
    elseif #matching < 2 and not routeHere(mapID) then
        msg = #matching == 0 and "Every matching spot is left out.\nClick a crossed-out spot to put it back."
            or "Only one matching spot here - a route needs at least two."
    end
    P.msg:SetText(msg or "")
    P.msgBg:SetShown(msg ~= nil)
    if msg then
        P.msgBg:SetSize(min(MAP_W - 40, (P.msg:GetStringWidth() or 300) + 28), (P.msg:GetStringHeight() or 14) + 20)
    end
    local note
    if info.art == "loading" then
        note = "Loading the zone map..."
    elseif info.art == "none" and mapID then
        note = "No map picture for this zone - plain grid"
    end
    P.note:SetText(note or "")
    P.noteBg:SetShown(note ~= nil)
    P.artState = info.art

    -- Below the map: what the route is and what you can do with it.
    for _, b in ipairs(P.buttons) do
        b:Hide()
    end
    if r then
        local step, n, lap = ns.RouteProgress(r)
        local pt = r.pts[r.i]
        local kind = pt and ns.KINDS[pt.k]
        P.sum:SetText("|cffffd100Stop " .. step .. " of " .. n .. "|r" .. (lap > 1 and ("  ·  lap " .. lap) or "")
            .. (r.paused and "  ·  paused" or "") .. (r.map ~= mapID and ("  ·  in " .. ns.MapName(r.map)) or ""))
        P.sub:SetText(r.paused and "Paused: the arrow is hidden until you resume. Your place in the loop is kept."
            or ("Next: " .. ((pt and pt.n) or (kind and kind.one) or "spot")
                .. ". Follow the arrow; it moves on when you arrive. Right-click a stop on the map to go there next."))
        P.pause:SetLabel(r.paused and "Resume" or "Pause")
        P.pause:Show()
        P.skip:SetDisabled(r.paused)
        P.skip:Show()
        P.finish:Show()
    else
        if plan then
            local yards = plan.yards and ("  ·  about " .. withCommas(floor(plan.yards / 10 + 0.5) * 10) .. " yards")
                or ""
            local onRoute = {}
            for _, p in ipairs(plan.pts) do
                onRoute[p.k] = true
            end
            P.sum:SetText("|cffffd100" .. plural(plan.n, "stop") .. "|r  ·  " .. kindList(onRoute) .. yards)
            P.sub:SetText("Suggested loop through your recorded gathering spots. They aren't guaranteed to be up, and the lines and distance are straight-line, so they can cross cliffs or water. Click a stop to leave it out; right-click to start there.")
        else
            P.sum:SetText(mapID and (GREY .. (why or "No route to suggest yet.") .. "|r") or "")
            P.sub:SetText("")
        end
        P.start:SetDisabled(not plan)
        P.start:Show()
        P.save:SetDisabled(not mapID)
        local saved = mapID and ns.db.routes[mapID]
        P.save:SetLabel(saved and "Save again" or "Save route")
        P.save:Show()
    end

    -- The zone menu
    local menu = P.menu
    if UI.zoneMenu and mapID then
        menu:Show()
        local zname = ns.MapName(mapID)
        if UI.zoneMenu == "confirm" then
            menu.text:SetText("Forget all " .. plural(total, "spot") .. " recorded in " .. zname .. "?\nThis can't be undone.")
            menu.a:SetLabel("Forget them")
            menu.a.onClick = function()
                ns.ForgetZone(mapID)
                UI.routeMap, UI.zoneMenu, UI.routeStart[mapID] = nil, nil, nil
                ns.RefreshUI()
            end
            menu.b:SetLabel("Keep them")
            menu.b.onClick = function()
                UI.zoneMenu = nil
                refreshRoutePanel()
            end
            menu.b:SetDisabled(false)
            menu.c:SetLabel("")
            menu.c:Hide()
        else
            menu.text:SetText(zname)
            menu.a:SetLabel("Put back " .. plural(z and z.skipped or 0, "left-out spot"))
            menu.a:SetDisabled(not (z and z.skipped > 0))
            menu.a.onClick = function()
                ns.IncludeAllNodes(mapID)
                UI.zoneMenu = nil
            end
            menu.b:SetLabel(ns.db.routes[mapID] and "Delete saved route" or "No saved route")
            menu.b:SetDisabled(not ns.db.routes[mapID])
            menu.b.onClick = function()
                ns.db.routes[mapID] = nil
                UI.zoneMenu = nil
                ns.RefreshUI(true)
            end
            menu.c:SetLabel("Forget this zone's spots...")
            menu.c.onClick = function()
                UI.zoneMenu = "confirm"
                refreshRoutePanel()
            end
            menu.c:Show()
        end
        menu.a:SetDisabled(UI.zoneMenu ~= "confirm" and not (z and z.skipped > 0))
    else
        menu:Hide()
    end
    P.sig = r and (tostring(r) .. r.i .. tostring(r.paused)) or "none"
end
ns.RefreshRoutePanel = refreshRoutePanel

-- A tick box that can't be misread: a filled gold box with a check mark
-- when on, an empty box and dim text when off.
local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"
local function checkbox(parent, kind, w, onClick)
    local info = ns.KINDS[kind]
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 22)
    b.kind = kind
    local hl = tex(b, "HIGHLIGHT", 1, 0.92, 0.7, 0.08)
    hl:SetAllPoints()
    local box = CreateFrame("Frame", nil, b)
    box:SetSize(16, 16)
    box:SetPoint("LEFT", 2, 0)
    skin(box, C.btn[1], C.btn[2], C.btn[3], 1, C.btnEdge[1], C.btnEdge[2], C.btnEdge[3], 1)
    b.box = box
    b.check = box:CreateTexture(nil, "OVERLAY")
    b.check:SetSize(22, 22)
    b.check:SetPoint("CENTER", 1, 0)
    b.check:SetTexture(CHECK)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 24, 0)
    setIcon(b.icon, info.icon)
    b.text = label(b, "GameFontHighlightSmall", info.label)
    b.text:SetPoint("LEFT", 44, 0)
    b:SetScript("OnClick", function()
        local ok, err = pcall(onClick, kind)
        if not ok then
            ns.Err("button", err)
        end
    end)
    b:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(info.label .. (self.checked and ": included" or ": not included"), 1, 0.82, 0)
            GameTooltip:AddLine(plural(self.count or 0, info.one) .. " recorded in this zone.", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", rowLeave)
    function b:SetChecked(on)
        self.checked = on and true or false
        if on then
            self.box.bg:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
            setEdge(self.box, C.goldEdge[1], C.goldEdge[2], C.goldEdge[3])
            self.text:SetTextColor(C.goldText[1], C.goldText[2], C.goldText[3])
            self.icon:SetAlpha(1)
            if self.icon.SetDesaturated then
                self.icon:SetDesaturated(false)
            end
        else
            self.box.bg:SetColorTexture(0.05, 0.05, 0.05, 1)
            setEdge(self.box, C.btnEdge[1], C.btnEdge[2], C.btnEdge[3])
            self.text:SetTextColor(0.55, 0.54, 0.51)
            self.icon:SetAlpha(0.5)
            if self.icon.SetDesaturated then
                self.icon:SetDesaturated(true)
            end
        end
        self.check:SetShown(self.checked)
    end
    function b:SetCount(n)
        self.count = n
    end
    return b
end

local function createRoutePanel(f)
    local P = CreateFrame("Frame", nil, f)
    P:SetSize(MAP_W, PANEL_H)

    -- Include: [x] Herbs [ ] Ore [ ] Fishing   19 matching spots   [Zone...]
    local inc = label(P, "GameFontNormalSmall", "Include:")
    inc:SetPoint("TOPLEFT", 0, -5)
    P.checks = {}
    local x = 52
    for _, spec in ipairs({ { "herb", 72 }, { "ore", 58 }, { "fish", 82 }, { "chest", 80 } }) do
        local cb = checkbox(P, spec[1], spec[2], function(kind)
            UI.routeKinds[kind] = not UI.routeKinds[kind]
            refreshRoutePanel()
        end)
        cb:SetPoint("TOPLEFT", x, 0)
        x = x + spec[2] + 4
        P.checks[#P.checks + 1] = cb
    end
    P.count = label(P, "GameFontHighlightSmall")
    P.count:SetPoint("TOPLEFT", x + 8, -5)
    P.zoneBtn = button(P, "Zone...", 64, 22, function()
        UI.zoneMenu = not UI.zoneMenu and "open" or nil
        refreshRoutePanel()
    end)
    P.zoneBtn:SetPoint("TOPRIGHT", 0, 0)
    P.count:SetWidth(MAP_W - 64 - 8 - (x + 8))
    P.count:SetWordWrap(false)

    -- The map
    local map = CreateFrame("Frame", nil, P)
    map:SetSize(MAP_W, MAP_H)
    map:SetPoint("TOPLEFT", 0, -30)
    skin(map, 0.05, 0.05, 0.045, 1, C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 1)
    P.map = map
    -- A faint grid for zones with no map picture.
    P.grid = {}
    for i = 1, 5 do
        local v = tex(map, "BORDER", 1, 1, 1, 0.05)
        v:SetWidth(1)
        v:SetPoint("TOP", map, "TOPLEFT", MAP_W * i / 6, 0)
        v:SetPoint("BOTTOM", map, "BOTTOMLEFT", MAP_W * i / 6, 0)
        P.grid[#P.grid + 1] = v
    end
    for i = 1, 3 do
        local hz = tex(map, "BORDER", 1, 1, 1, 0.05)
        hz:SetHeight(1)
        hz:SetPoint("LEFT", map, "TOPLEFT", 0, -MAP_H * i / 4)
        hz:SetPoint("RIGHT", map, "TOPRIGHT", 0, -MAP_H * i / 4)
        P.grid[#P.grid + 1] = hz
    end

    -- Things written on top of the map sit on their own frame above it.
    local over = CreateFrame("Frame", nil, map)
    over:SetAllPoints(map)
    P.over = over
    P.titleBg = tex(over, "BACKGROUND", 0, 0, 0, 0.6)
    P.titleBg:SetPoint("TOPLEFT", 1, -1)
    P.titleBg:SetSize(220, 24)
    P.title = label(over, "GameFontNormal")
    P.title:SetPoint("TOPLEFT", 8, -6)
    P.title:SetTextColor(C.goldText[1], C.goldText[2], C.goldText[3])
    P.msgBg = tex(over, "BACKGROUND", 0, 0, 0, 0.78)
    P.msgBg:SetPoint("CENTER")
    P.msg = label(over, "GameFontHighlight")
    P.msg:SetPoint("CENTER")
    P.msg:SetJustifyH("CENTER")
    P.msg:SetWidth(MAP_W - 80)
    P.msg:SetWordWrap(true)
    -- Map status (loading / no picture) top right, opposite the zone name.
    P.note = label(over, "GameFontHighlightSmall")
    P.note:SetPoint("TOPRIGHT", -8, -7)
    P.note:SetJustifyH("RIGHT")
    P.noteBg = tex(over, "BACKGROUND", 0, 0, 0, 0.6)
    P.noteBg:SetPoint("TOPLEFT", P.note, "TOPLEFT", -6, 5)
    P.noteBg:SetPoint("BOTTOMRIGHT", P.note, "BOTTOMRIGHT", 6, -5)
    -- What the symbols mean, on a band along the bottom.
    local legendBg = tex(over, "BACKGROUND", 0, 0, 0, 0.6)
    legendBg:SetPoint("BOTTOMLEFT", 1, 1)
    legendBg:SetPoint("BOTTOMRIGHT", -1, 1)
    legendBg:SetHeight(20)
    local legend = label(over, "GameFontHighlightSmall",
        "|T" .. ns.KINDS.herb.icon .. ":13|t herb  |T" .. ns.KINDS.ore.icon .. ":13|t ore  |T" .. ns.KINDS.fish.icon
        .. ":13|t fishing  |T" .. ns.KINDS.chest.icon .. ":13|t chest  |TInterface\\Minimap\\MinimapArrow:14|t you  "
        .. "|cffffd100gold ring|r = start / next  crossed out = left out")
    legend:SetPoint("BOTTOMLEFT", 8, 5)
    P.legend = legend

    -- Below the map
    P.sum = label(P, "GameFontHighlight")
    P.sum:SetPoint("TOPLEFT", map, "BOTTOMLEFT", 0, -10)
    P.sum:SetWidth(MAP_W - 252)
    P.sum:SetWordWrap(false)
    P.sub = label(P, "GameFontDisableSmall")
    P.sub:SetPoint("TOPLEFT", map, "BOTTOMLEFT", 0, -32)
    P.sub:SetWidth(MAP_W)
    P.sub:SetWordWrap(true)
    P.sub:SetJustifyV("TOP")

    local function startRoute()
        local plan = currentPlan()
        if not plan then
            return
        end
        UI.planKey = nil -- the plan is now the running route; work out a fresh one next time
        ns.StartRoute(plan)
        UI.zoneMenu = nil
        ns.Print("route started: " .. plan.n .. " stops in " .. ns.MapName(plan.map) .. ". Follow the arrow.")
        ns.RefreshUI(true)
    end
    P.start = button(P, "Start route", 110, 26, startRoute)
    P.start:SetPrimary(true)
    P.start:SetPoint("TOPRIGHT", map, "BOTTOMRIGHT", 0, -6)
    P.save = button(P, "Save route", 90, 26, function()
        local mapID = selectedRouteMap()
        if mapID then
            ns.SaveRoute(mapID, UI.routeKinds, UI.routeStart[mapID])
            ns.Print("saved: " .. ns.MapName(mapID) .. " opens with " .. kindList(UI.routeKinds)
                .. (UI.routeStart[mapID] and " and your chosen start" or "") .. ".")
        end
    end)
    P.save:SetPoint("RIGHT", P.start, "LEFT", -8, 0)
    P.finish = button(P, "End route", 84, 26, function()
        ns.StopRoute()
        ns.RefreshUI(true)
    end)
    P.finish:SetPoint("TOPRIGHT", map, "BOTTOMRIGHT", 0, -6)
    P.skip = button(P, "Skip stop", 80, 26, function() ns.NextStop() end)
    P.skip:SetPoint("RIGHT", P.finish, "LEFT", -6, 0)
    P.pause = button(P, "Pause", 70, 26, function()
        ns.PauseRoute(not (ns.route and ns.route.paused))
    end)
    P.pause:SetPoint("RIGHT", P.skip, "LEFT", -6, 0)
    P.buttons = { P.start, P.save, P.finish, P.skip, P.pause }

    -- The zone menu drops down from its button.
    local menu = CreateFrame("Frame", nil, P)
    menu:SetSize(230, 124)
    menu:SetPoint("TOPRIGHT", P.zoneBtn, "BOTTOMRIGHT", 0, -4)
    skin(menu, C.panel[1], C.panel[2], C.panel[3], 0.98, C.edge[1], C.edge[2], C.edge[3], 1)
    menu.text = label(menu, "GameFontNormalSmall")
    menu.text:SetPoint("TOPLEFT", 10, -8)
    menu.text:SetWidth(210)
    menu.text:SetWordWrap(true)
    menu.a = button(menu, "", 210, 22)
    menu.a:SetPoint("TOPLEFT", 10, -40)
    menu.b = button(menu, "", 210, 22)
    menu.b:SetPoint("TOPLEFT", 10, -66)
    menu.c = button(menu, "", 210, 22)
    menu.c:SetPoint("TOPLEFT", 10, -92)
    menu:Hide()
    P.menu = menu

    -- You move every frame; the rest only changes on events.
    local since, slow = 0, 0
    P:SetScript("OnUpdate", function(_, elapsed)
        since, slow = since + elapsed, slow + elapsed
        if since < 0.1 then
            return
        end
        since = 0
        ns.Guard("plot", function()
            f.plotter:UpdatePlayer()
            local r = ns.route
            local sig = r and (tostring(r) .. r.i .. tostring(r.paused)) or "none"
            if sig ~= P.sig or (P.artState == "loading" and slow > 0.5) then
                slow = 0
                refreshRoutePanel()
            end
        end)()
    end)
    return P
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
    local top = 76 + barH
    local list = main.list
    local plot = tab.plot
    if type(plot) == "function" then
        plot = plot()
    end
    -- List on the left; on the right the route map, or the details of the
    -- picked row. Settings use the whole width.
    local wide = tab.wide
    if type(wide) == "function" then
        wide = wide()
    end
    local withPane = not plot and tab ~= SETTINGS and not wide
    local right = plot and (MAP_W + 12) or (withPane and (PANE_W + 10) or 0)
    list.viewW = W - 24 - right
    list.rightW = (withPane and 150) or (plot and 16) or nil
    list.onSelect = withPane and function(d)
        UI.sel[UI.selKey] = d.key or (d.id and ("item:" .. d.id)) or d.title
        ns.RefreshUI(true)
    end or nil
    main.plot:SetShown(plot and true or false)
    local ok, rows = pcall(tab.build)
    if not ok then
        ns.Err("tab-" .. tab.key, rows)
        rows = { { type = "text", title = "Something went wrong on this tab",
            text = "The other tabs still work. Type /gold debug to see the details." } }
    end

    -- Keep the picked row picked across refreshes; otherwise the first one.
    UI.selKey = tab.key .. (tab.key == "make" and (":" .. makeMode()) or "") .. (tab.key == "farming" and (":" .. farmView()) or "")
    local want, first, picked = UI.sel[UI.selKey], nil, nil
    if withPane then
        for _, d in ipairs(rows) do
            if not d.type then
                first = first or d
                local key = d.key or (d.id and ("item:" .. d.id)) or d.title
                if want and key == want then
                    picked = d
                    break
                end
            end
        end
    elseif plot then
        for _, d in ipairs(rows) do
            if d.isSel then
                picked = d
            end
        end
    end
    list.selected = picked or first
    list:SetRows(rows, keepScroll)

    -- The window is as tall as what's in it, between MIN_H and MAX_H.
    local paneH = withPane and main.pane:SetRow(list.selected) or 0
    -- On Routes the zone list sits under its search box.
    local searchH = plot and 32 or 0
    local body = max(list.contentH + searchH, paneH, plot and PANEL_H or 0, 120)
    H = max(MIN_H, min(MAX_H, top + body + 46))
    main:SetHeight(H)
    list.viewH = H - top - searchH - 46
    local search = main.zoneSearch
    search:SetShown(plot and true or false)
    if plot then
        search:ClearAllPoints()
        search:SetPoint("TOPLEFT", main, "TOPLEFT", 12, -top)
        search:SetSize(list.viewW - 4, 24)
    end
    local clip = list.clip
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", main, "TOPLEFT", 12, -(top + searchH))
    clip:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -(12 + right), 46)
    main.pane:SetShown(withPane)
    if withPane then
        main.pane:ClearAllPoints()
        main.pane:SetPoint("TOPRIGHT", main, "TOPRIGHT", -12, -top)
        main.pane:SetHeight(min(paneH, list.viewH))
    end
    if plot then
        main.plot:ClearAllPoints()
        main.plot:SetPoint("TOPRIGHT", main, "TOPRIGHT", -12, -top)
    end
    list:Apply()
    refreshFooter()
    refreshRoutePanel()
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
    -- Pinned by its top edge so it grows and shrinks downward.
    f:SetPoint("TOP", UIParent, "TOP", 0, -100)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, topY = self:GetLeft(), self:GetTop()
        if left and topY then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, topY)
        end
    end)
    skin(f)
    if UISpecialFrames then
        table.insert(UISpecialFrames, "ForeverGoldFrame")
    end

    local titleIcon = f:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(30, 30)
    titleIcon:SetPoint("TOPLEFT", 10, -5)
    titleIcon:SetTexture(LOGO)
    local title = label(f, SERIF_L, "Forever Gold")
    title:SetTextColor(C.goldText[1], C.goldText[2], C.goldText[3])
    title:SetPoint("LEFT", titleIcon, "RIGHT", 8, 0)
    f.money = label(f, "GameFontHighlight")
    f.money:SetPoint("TOPRIGHT", -44, -14)
    local close = button(f, "X", 24, 22, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)

    -- Tabs sit on a brass rule that runs the width of the window.
    local tabRule = tex(f, "BORDER", C.edge[1], C.edge[2], C.edge[3], 0.7)
    tabRule:SetHeight(1)
    tabRule:SetPoint("TOPLEFT", 12, -66)
    tabRule:SetPoint("TOPRIGHT", -12, -66)
    local x = 12
    for _, t in ipairs(TABS) do
        local key = t.key
        local b = button(f, t.label, 92, 24, function() ns.ShowTab(key) end)
        b:SetPoint("TOPLEFT", x, -42)
        t.button = b
        x = x + 96
    end
    -- Settings live in the game's Options window (Options.lua); tips and
    -- help stay here, behind the "?" button.
    f.settingsButton = button(f, "Settings", 80, 24, function()
        if ns.OpenOptions and ns.OpenOptions("auction") then
            return
        end
        ns.ShowTab(UI.tab == "settings" and "todo" or "settings")
    end)
    f.settingsButton:SetPoint("TOPRIGHT", -12, -42)
    f.helpButton = button(f, "?", 26, 24, function()
        ns.ShowTab(UI.tab == "settings" and "todo" or "settings")
    end)
    f.helpButton:SetPoint("RIGHT", f.settingsButton, "LEFT", -4, 0)

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 12, -74)
    bar:SetPoint("TOPRIGHT", -12, -74)
    bar:SetHeight(26)
    bar.buttons = {}
    bar.text = label(bar, "GameFontHighlightSmall")
    f.toolbar = bar

    f.list = createList(f)
    f.pane = createPane(f)

    -- Make > Routes: the map panel (everything in it is parented to it, so
    -- none of it shows on other tabs).
    local plot = createRoutePanel(f)
    plot:SetPoint("TOPRIGHT", -12, -106)
    plot:Hide()
    f.plot = plot
    f.plotter = ns.NewPlotter(plot.map)

    -- Make > Routes: a search box over the zone list.
    local search = CreateFrame("EditBox", nil, f)
    search:SetSize(260, 24)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    if _G.GameFontHighlightSmall then
        search:SetFontObject(_G.GameFontHighlightSmall)
    end
    search:SetTextInsets(24, 22, 0, 0)
    skin(search, 0.05, 0.05, 0.045, 1, C.btnEdge[1], C.btnEdge[2], C.btnEdge[3], 1)
    local glass = search:CreateTexture(nil, "ARTWORK")
    glass:SetSize(14, 14)
    glass:SetPoint("LEFT", 6, 0)
    glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    search.hint = label(search, "GameFontDisableSmall", "Search zones or continents")
    search.hint:SetPoint("LEFT", 24, 0)
    search.clear = button(search, "x", 18, 18, function()
        search:SetText("")
        search:ClearFocus()
    end)
    search.clear:SetPoint("RIGHT", -3, 0)
    search.clear:Hide()
    search:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        self.hint:SetShown(text == "")
        self.clear:SetShown(text ~= "")
        if text ~= (UI.zoneFilter or "") then
            UI.zoneFilter = text
            ns.Later("zone-search", 0.15, function() ns.RefreshUI() end)
        end
    end)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:Hide()
    f.zoneSearch = search

    local footRule = tex(f, "BORDER", C.edge[1], C.edge[2], C.edge[3], 0.5)
    footRule:SetHeight(1)
    footRule:SetPoint("BOTTOMLEFT", 12, 40)
    footRule:SetPoint("BOTTOMRIGHT", -12, 40)
    f.status = label(f, "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", 14, 15)
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

-- Opens the main window (if it isn't already).
function ns.ShowMain()
    if not (main and main:IsShown()) then
        ns.ToggleUI()
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
        local stop = "stop " .. (st.step or st.index) .. " of " .. st.count
        if st.paused then
            hud.line1:SetText("Route paused")
            hud.line2:SetText(stop .. " - Resume carries on")
            drawArrow(nil)
        elseif st.onMap then
            hud.line1:SetText(st.name)
            hud.line2:SetText((st.yards and (floor(st.yards) .. " yards   ") or "") .. stop)
            drawArrow(st.angle)
        else
            hud.line1:SetText("Route in " .. st.zone)
            hud.line2:SetText("Travel there to begin")
            drawArrow(nil)
        end
        hud.pause:SetLabel(st.paused and "Resume" or "Pause")
        hud.skip:SetDisabled(st.paused)
    end
    hud.line3:SetText("")
end

local function createHUD()
    local f = CreateFrame("Frame", "ForeverGoldGuide", UIParent)
    f:SetSize(284, 70)
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
    f.line2:SetWidth(162)
    f.line2:SetWordWrap(true)
    f.line3 = label(f, "GameFontHighlightSmall")
    f.line3:SetPoint("BOTTOMLEFT", 10, 7)

    f.pause = button(f, "Pause", 54, 18, function() ns.PauseRoute(not (ns.route and ns.route.paused)) end)
    f.pause:SetPoint("TOPRIGHT", -6, -5)
    f.skip = button(f, "Skip", 54, 18, function() ns.NextStop() end)
    f.skip:SetPoint("TOPRIGHT", -6, -26)
    f.stop = button(f, "End", 54, 18, function() ns.StopRoute() end)
    f.stop:SetPoint("TOPRIGHT", -6, -47)

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
    skin(f)

    f.iconEdge = f:CreateTexture(nil, "BORDER")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(34, 34)
    f.icon:SetPoint("TOPLEFT", 14, -14)
    f.iconEdge:SetPoint("TOPLEFT", f.icon, "TOPLEFT", -1, 1)
    f.iconEdge:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", 1, -1)
    f.title = label(f, "GameFontHighlightLarge")
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
    f.post:SetPrimary(true)
    f.close = button(f, "Cancel", 90, 28, function() ns.CloseSell() end)
    f.close:SetPoint("BOTTOMLEFT", 14, 14)
    -- Post all: skip this item and go to the next one.
    f.skip = button(f, "Skip", 70, 28, function() ns.SkipPostAll("skipped") end)
    f.skip:SetPoint("RIGHT", f.post, "LEFT", -8, 0)
    f.skip:Hide()
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
    local q = ns.PostQueue and ns.PostQueue()
    setIcon(f.icon, ns.Icon(job.id))
    edgeFor(f.iconEdge, job.id)
    f.title:SetText(ns.ItemName(job.id))
    f.have:SetText(GREY .. "You have " .. job.have .. " to sell"
        .. (q and ("  -  Post all: item " .. q.i .. " of " .. #q.ids .. ", " .. q.posted .. " posted") or "") .. "|r")
    f.skip:SetShown(q ~= nil and job.state ~= "posting" and job.state ~= "verify")

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
    f.close:SetLabel(q and "Stop" or "Cancel")
    if job.state == "checking" then
        f.post:SetLabel("Checking...")
        f.post:SetDisabled(true)
    elseif ((job.state == "ready" and canPost) or job.state == "confirm") and ns.AHWaiting() then
        -- The auction house said busy / too fast: no clicking into another refusal.
        f.post:SetLabel("Wait...")
        f.post:SetDisabled(true)
    elseif job.state == "ready" then
        f.post:SetLabel(q and "Post, then next" or "Post")
        f.post:SetDisabled(not canPost)
        if not canPost and not q then
            f.close:SetLabel("Close")
        end
    elseif job.state == "confirm" then
        f.post:SetLabel("Confirm")
        f.post:SetDisabled(false)
    elseif job.state == "posting" then
        f.post:SetLabel("Posting...")
        f.post:SetDisabled(true)
    elseif job.state == "verify" then
        f.post:SetLabel("Checking...")
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
    local n = ns.R().lastScan and #ns.BagAdvice().ah or 0
    ahPanel.postAll:SetLabel(n > 0 and ("Post all (" .. n .. ")") or "Post all")
    ahPanel.postAll:SetDisabled(active or n == 0 or (ns.PostQueue and ns.PostQueue() ~= nil))
end

local function createAHPanel()
    -- Our own auction window (AuctionUI.lua) has all of this built in.
    if ns.AuctionUI and ns.AuctionUI.UsingOurs() then
        if ahPanel then
            ahPanel:Hide()
        end
        return
    end
    if ahPanel then
        ahPanel:Show()
        refreshAHPanel()
        return
    end
    local parent = AuctionHouseFrame or UIParent
    local p = CreateFrame("Frame", "ForeverGoldAuctionStrip", parent)
    p:SetSize(746, 32)
    if AuctionHouseFrame then
        p:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "TOPRIGHT", 0, 3)
    else
        p:SetPoint("TOP", UIParent, "TOP", 0, -70)
    end
    p:SetFrameStrata("HIGH")
    skin(p)
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
    p.postAll = button(p, "Post all", 96, 22, function() ns.StartPostAll() end)
    p.postAll:SetPoint("RIGHT", p.scan, "LEFT", -6, 0)
    p.postAll:SetPrimary(true)
    p.postAll:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Post everything the Sell tab says to auction", 1, 0.82, 0)
            GameTooltip:AddLine("Each item is price-checked, then you press Post once per listing (the game needs a click for every post). Anything under your floor is skipped. Undercut and stack size are under Settings.", 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end
    end)
    p.postAll:SetScript("OnLeave", rowLeave)
    p.ours = button(p, "Forever Gold window", 124, 22, function()
        if ns.AuctionUI then
            ns.AuctionUI.UseOurs()
        end
    end)
    p.ours:SetPoint("RIGHT", p.postAll, "LEFT", -6, 0)
    ahPanel = p
    refreshAHPanel()
end

ns.ShowAuctionStrip = createAHPanel
function ns.HideAuctionStrip()
    if ahPanel then
        ahPanel:Hide()
    end
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
    -- Built from the game's own minimap button parts (dark backing, gold
    -- tracking ring, round glow on hover), the same as every other addon's
    -- button, so it matches them on the minimap and in button drawers.
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 10)
    local back = b:CreateTexture(nil, "BACKGROUND")
    back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    back:SetSize(20, 20)
    back:SetPoint("TOPLEFT", 7, -5)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(LOGO)
    icon:SetSize(19, 19)
    icon:SetPoint("TOPLEFT", 6, -5)
    b.icon = icon
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT")
    if b.SetHighlightTexture then
        b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    end
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
            GameTooltip:AddLine("Click for gold-making advice. Right-click: Farming Session. Drag to move.", 1, 1, 1)
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

-- How many are in the stack you're hovering: the bag slot under the
-- tooltip's owner, else worked out from Blizzard's stack sell price.
local function stackCount(tooltip, id, data)
    local owner = tooltip.GetOwner and tooltip:GetOwner()
    if type(owner) == "table" and C_Container and C_Container.GetContainerItemInfo then
        local bag = owner.GetBagID and ns.try(owner.GetBagID, owner)
        if bag == nil and owner.GetParent then
            local parent = owner:GetParent()
            bag = parent and parent.GetID and parent:GetID()
        end
        local slot = owner.GetID and owner:GetID()
        if type(bag) == "number" and type(slot) == "number" and slot > 0 then
            local info = ns.try(C_Container.GetContainerItemInfo, bag, slot)
            if type(info) == "table" and info.itemID == id and (info.stackCount or 0) > 0 then
                return info.stackCount
            end
        end
    end
    local each, stack = ns.VendorSell(id), stackSellPrice(data)
    if each and each > 0 and stack and stack > each then
        return floor(stack / each + 0.5)
    end
    return 1
end

-- "x 20: 1g 40s" under a per-item line, for a stack of n.
local function stackTotal(tooltip, n, each, text)
    if n > 1 and each and each ~= 0 then
        tooltip:AddDoubleLine(GREY .. "  stack of " .. n .. "|r", text and text(each * n) or (GREY .. ns.Money(each * n) .. "|r"))
    end
end

-- A recipe, pattern, plans or formula: which of your characters already
-- know what it teaches, and which have the profession but don't.
local function addRecipeKnownLines(tooltip, id)
    local info = ns.RecipeItem and ns.RecipeItem(id)
    if not info then
        return
    end
    if #info.known > 0 then
        tooltip:AddLine("|cff40e060Already known by:|r " .. table.concat(info.known, ", "), 1, 1, 1, true)
    end
    if #info.can > 0 then
        tooltip:AddLine("|cffffd100Could learn it:|r " .. table.concat(info.can, ", "), 1, 1, 1, true)
    end
    if #info.unread > 0 then
        tooltip:AddLine(GREY .. "Open " .. info.prof .. " once on " .. table.concat(info.unread, ", ")
            .. " to check them too.|r", 1, 1, 1, true)
    end
    if #info.known == 0 and #info.can == 0 and #info.unread == 0 then
        tooltip:AddLine(GREY .. "None of your characters has " .. info.prof .. ".|r", 1, 1, 1, true)
    end
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
    local n = stackCount(tooltip, id, data)
    local R = ns.R()
    local by = R.lastScanBy and (" by " .. R.lastScanBy) or ""
    local price, listed, when = ns.AHPrice(id)
    local last, lastT = ns.LastPrice(id)
    if price then
        tooltip:AddDoubleLine("|cffffd100Auction|r  " .. GREY .. listed .. " listed|r", ns.Money(price))
        stackTotal(tooltip, n, price)
        tooltip:AddLine(GREY .. "Last scanned " .. agoColored(when) .. by .. "|r")
    elseif last then
        tooltip:AddDoubleLine("|cffffd100Auction|r  " .. GREY .. "none listed now, was|r", ns.Money(last))
        stackTotal(tooltip, n, last)
        tooltip:AddLine(GREY .. "Last seen " .. agoColored(lastT) .. by .. "|r")
    end
    if (price or last) and (ns.Suspicious(id, price or last) or ns.PriceDoubt(id)) then
        tooltip:AddLine("|cffff7070Suspicious auction price|r - looks like gold changing hands, not what it's worth.", 1, 1, 1, true)
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
                local m = e.cost > 0 and floor(e.profit / e.cost * 100 + 0.5)
                local pct = m and ("  " .. (m > 0 and "|cff40e060" or m < 0 and "|cffff6060" or GREY) .. m .. "%|r" .. GREY .. " margin|r") or ""
                tooltip:AddDoubleLine("|cffffd100Profit if you craft and sell it|r", ns.Profit(e.profit) .. pct)
                stackTotal(tooltip, n, e.profit, ns.Profit)
            end
        end
    end
    addRecipeKnownLines(tooltip, id)
    -- Auction against vendor: what listing it earns over just vendoring it.
    local ah = price or last or sp
    local vendor = ns.VendorSell(id)
    if ah and vendor and vendor > 0 then
        local gain = ah * (1 - CUT) - vendor
        local pct = floor(gain / vendor * 100 + 0.5)
        if gain > 0 then
            tooltip:AddDoubleLine("|cffffd100Auction over vendor|r  " .. GREY .. "after the 5% cut|r",
                ns.Profit(gain) .. "  |cff40e060+" .. pct .. "%|r")
            stackTotal(tooltip, n, floor(gain + 0.5), ns.Profit)
        else
            tooltip:AddDoubleLine("|cffffd100Auction over vendor|r", "|cffff7070vendor pays more|r")
        end
    end
    -- Where your characters keep it (bags and banks, saved - see Inventory.lua).
    if ns.InventoryTooltip then
        ns.InventoryTooltip(tooltip, id)
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
    refreshAHPanel()
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

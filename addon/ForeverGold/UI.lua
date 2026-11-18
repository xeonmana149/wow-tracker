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

local function rowEnter(self)
    local d = self.d
    if not d or d.type or not GameTooltip then
        return
    end
    if not pcall(GameTooltip.SetOwner, GameTooltip, self, "ANCHOR_CURSOR_RIGHT") then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    end
    -- With a details pane beside the list, the numbers are there already;
    -- hovering only shows the game's own item tooltip.
    if self.list and self.list.onSelect then
        if d.id then
            pcall(GameTooltip.SetItemByID, GameTooltip, d.id)
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
        return neg .. floor(v / 10000000 + 0.5) .. "k g"
    elseif v >= 10000 then
        local g = v / 10000
        return neg .. (g >= 100 and floor(g + 0.5) or floor(g * 10 + 0.5) / 10) .. "g"
    elseif v >= 100 then
        return neg .. floor(v / 100 + 0.5) .. "s"
    end
    return neg .. floor(v + 0.5) .. "c"
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
    g.dot:SetSize(6, 6)
    g.dot:Hide()
    g:EnableMouse(true)
    g:SetScript("OnEnter", function(self) self.hovering = true end)
    g:SetScript("OnLeave", function(self)
        self.hovering = false
        self.dot:Hide()
        rowLeave()
    end)
    g:SetScript("OnUpdate", function(self)
        if not self.hovering or not self.drawn or #self.drawn == 0 or not GameTooltip then
            return
        end
        local cx = GetCursorPosition() / (self:GetEffectiveScale() or 1) - (self:GetLeft() or 0)
        local best, bestD
        for _, p in ipairs(self.drawn) do
            local dist = math.abs(p.x - cx)
            if not bestD or dist < bestD then
                best, bestD = p, dist
            end
        end
        if best and best ~= self.shown then
            self.shown = best
            self.dot:ClearAllPoints()
            self.dot:SetPoint("CENTER", self, "BOTTOMLEFT", best.x, best.y)
            self.dot:Show()
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetText(date("%a %d %b, %H:%M", best.t), 1, 1, 1)
            GameTooltip:AddLine(ns.Money(best.v), 1, 1, 1)
            GameTooltip:Show()
        end
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

    function g:Draw(points, span)
        for _, l in ipairs(self.lines) do l:Hide() end
        for _, l in ipairs(self.grid) do l:Hide() end
        for _, t in ipairs(self.ylabels) do t:Hide() end
        for _, t in ipairs(self.xlabels) do t:Hide() end
        self.dot:Hide()
        self.drawn, self.shown = {}, nil
        local w, h = self:GetWidth() or 300, self:GetHeight() or 150
        if #points < 2 then
            self.empty:SetText("Not enough history yet")
            return
        end
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
        local spread = max(vmax - vmin, max(100, vmax * 0.02))
        local mid = (vmax + vmin) / 2
        vmin, vmax = max(0, mid - spread * 0.6), mid + spread * 0.6
        local pw, ph = w - GRAPH_LEFT - 8, h - GRAPH_BOTTOM - 8
        local function X(t) return GRAPH_LEFT + (t1 > t0 and (t - t0) / (t1 - t0) or 1) * pw end
        local function Y(v) return GRAPH_BOTTOM + (v - vmin) / (vmax - vmin) * ph end
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
        local fmt = (t1 - t0) <= 2 * 86400 and "%H:%M" or "%d %b"
        for i, t in ipairs({ t0, t1 }) do
            local xl = text(self.xlabels, i)
            xl:SetJustifyH(i == 1 and "LEFT" or "RIGHT")
            xl:SetWidth(80)
            xl:SetPoint(i == 1 and "BOTTOMLEFT" or "BOTTOMRIGHT", self, "BOTTOMLEFT", i == 1 and GRAPH_LEFT or (w - 8), 2)
            xl:SetText(date(fmt, t))
        end
        local up = pts[#pts][2] >= pts[1][2]
        local cr, cg, cb = C.goldEdge[1], C.goldEdge[2], C.goldEdge[3]
        if not up then
            cr, cg, cb = 0.85, 0.42, 0.36
        end
        for i, p in ipairs(pts) do
            local x, y = X(p[1]), Y(p[2])
            self.drawn[i] = { x = x, y = y, t = p[1], v = p[2] }
            if i > 1 then
                local prev = self.drawn[i - 1]
                local l = line(self.lines, i - 1)
                l:SetThickness(2)
                l:SetColorTexture(cr, cg, cb, 1)
                l:SetStartPoint("BOTTOMLEFT", self, prev.x, prev.y)
                l:SetEndPoint("BOTTOMLEFT", self, x, y)
            end
        end
    end
    return g
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
        r.graph:Draw(d.points or {}, d.span)
        return h
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
    -- An optional action button (for example "Sell") sits at the far right
    -- and pushes the numbers left.
    local pad, rightW = 10, RIGHT_W
    if d.btn then
        pad, rightW = 70, RIGHT_W - 40
        r.btn:SetLabel(d.btn.label)
        r.btn.onClick = function() d.btn.onClick(d) end
        r.btn:Show()
    end
    local tx = d.noIcon and 12 or 46
    setFont(r.title, "GameFontHighlight")
    r.title:SetPoint("TOPLEFT", tx, -6)
    r.title:SetWidth(width - tx - rightW - pad - 4)
    r.title:SetText(d.title or "")
    r.sub:SetPoint("TOPLEFT", tx, -23)
    r.sub:SetWidth(width - tx - rightW - pad - 4)
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
    list.thumb = tex(clip, "OVERLAY", C.edge[1], C.edge[2], C.edge[3], 0.9)
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
    createList = createList, Hd = Hd, Tx = Tx, GREY = GREY, COIN = COIN, LOGO = LOGO, rowLeave = rowLeave,
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
        if #farms > 0 then
            Hd(rows, "Got an hour? Go farm")
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
    local pts, change = ns.GoldHistory(range[3])
    Hd(rows, "Gold over time", range[2] .. ":  " .. (#pts > 1 and ns.Profit(change) or "no change yet"))
    rows[#rows + 1] = { type = "graph", points = pts, span = range[3], height = 170 }
    if #pts < 3 then
        Tx(rows, nil, GREY .. "Your gold is recorded from now on, every time it changes, across all your characters. The graph fills in as you play.|r")
    end

    local chars = {}
    for _, ch in pairs(ns.db.chars) do
        chars[#chars + 1] = ch
    end
    table.sort(chars, function(a, b) return (a.money or 0) > (b.money or 0) end)
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
    bar.text = "Gold across all your characters."
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
        local tip = { "Buy it from the vendor and list it on the auction house.",
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
    rows[#rows + 1] = { noIcon = true, title = (on and "|cff40e060[on]|r  " or "|cffff7070[off]|r  ") .. text,
        sub = "Click to turn " .. (on and "off" or "on"),
        onClick = function()
            ns.db.opts[key] = not ns.db.opts[key]
            ns.RefreshUI(true)
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

local function buildTips()
    local rows = {}
    Hd(rows, "Selling")
    cycleRow(rows, "postUndercut", ns.UNDERCUT_STEPS, "copper", "Undercut the cheapest listing by",
        { copper = "1 copper", ["1%"] = "1%", ["5%"] = "5%" },
        "Click to change. Never goes below your floor, and never undercuts your own auctions.")
    cycleRow(rows, "postQty", ns.POST_QTY_STEPS, "stack", "Each listing holds",
        { stack = "one full stack", all = "everything you have", one = "one item" },
        "Click to change. With one full stack, Post all lists your stacks one at a time.")
    cycleRow(rows, "sellDuration", { 1, 2, 3 }, 2, "Auctions last",
        { [1] = ns.SellDurationLabel(1), [2] = ns.SellDurationLabel(2), [3] = ns.SellDurationLabel(3) },
        "Click to change. Longer costs a bigger deposit.")
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
    { key = "chars", label = "Characters", build = buildChars, toolbar = charsToolbar },
}
-- Opened with the Settings button at the top right, not a tab of its own.
local SETTINGS = { key = "settings", label = "Settings", build = buildTips }

-- Older names for the tabs, still used in a few places.
local TAB_ALIAS = { characters = { "chars" }, today = { "todo" }, bags = { "sell" }, deals = { "buy" }, tips = { "settings" },
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
    local top = 76 + barH
    local list = main.list
    local plot = tab.plot
    if type(plot) == "function" then
        plot = plot()
    end
    -- List on the left; on the right the route map, or the details of the
    -- picked row. Settings use the whole width.
    local withPane = not plot and tab ~= SETTINGS
    local right = plot and 410 or (withPane and (PANE_W + 10) or 0)
    list.viewW = W - 24 - right
    list.rightW = withPane and 150 or nil
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
    UI.selKey = tab.key .. (tab.key == "make" and (":" .. makeMode()) or "")
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
    end
    list.selected = picked or first
    list:SetRows(rows, keepScroll)

    -- The window is as tall as what's in it, between MIN_H and MAX_H.
    local paneH = withPane and main.pane:SetRow(list.selected) or 0
    local body = max(list.contentH, paneH, plot and 360 or 0, 120)
    H = max(MIN_H, min(MAX_H, top + body + 46))
    main:SetHeight(H)
    list.viewH = H - top - 46
    local clip = list.clip
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", main, "TOPLEFT", 12, -top)
    clip:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -(12 + right), 46)
    main.pane:SetShown(withPane)
    if withPane then
        main.pane:ClearAllPoints()
        main.pane:SetPoint("TOPRIGHT", main, "TOPRIGHT", -12, -top)
        main.pane:SetHeight(min(paneH, list.viewH))
    end
    list:Apply()
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
    f.settingsButton = button(f, "Settings", 80, 24, function()
        ns.ShowTab(UI.tab == "settings" and "todo" or "settings")
    end)
    f.settingsButton:SetPoint("TOPRIGHT", -12, -42)

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 12, -74)
    bar:SetPoint("TOPRIGHT", -12, -74)
    bar:SetHeight(26)
    bar.buttons = {}
    bar.text = label(bar, "GameFontHighlightSmall")
    f.toolbar = bar

    f.list = createList(f)
    f.pane = createPane(f)

    local plot = CreateFrame("Frame", nil, f)
    plot:SetSize(396, 264)
    plot:SetPoint("TOPRIGHT", -12, -132)
    skin(plot, 0.03, 0.03, 0.03, 1, C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 1)
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
    f.skip:SetShown(q ~= nil and job.state ~= "posting")

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
    if ahPanel then
        ahPanel:Show()
        refreshAHPanel()
        return
    end
    local parent = AuctionHouseFrame or UIParent
    local p = CreateFrame("Frame", "ForeverGoldAuctionStrip", parent)
    p:SetSize(620, 32)
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
    b:SetSize(30, 30)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 10)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(LOGO)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(LOGO)
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.35)
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
                local pct = e.cost > 0 and (GREY .. "  " .. floor(e.profit / e.cost * 100 + 0.5) .. "% margin|r") or ""
                tooltip:AddDoubleLine("|cffffd100Profit if you craft and sell it|r", ns.Profit(e.profit) .. pct)
            end
        end
    end
    -- Auction against vendor: what listing it earns over just vendoring it.
    local ah = price or last or sp
    local vendor = ns.VendorSell(id)
    if ah and vendor and vendor > 0 then
        local gain = ah * (1 - CUT) - vendor
        local pct = floor(gain / vendor * 100 + 0.5)
        if gain > 0 then
            tooltip:AddDoubleLine("|cffffd100Auction over vendor|r  " .. GREY .. "after the 5% cut|r",
                ns.Profit(gain) .. GREY .. "  +" .. pct .. "%|r")
        else
            tooltip:AddDoubleLine("|cffffd100Auction over vendor|r", "|cffff7070vendor pays more|r")
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

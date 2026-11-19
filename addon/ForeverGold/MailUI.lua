-- Forever Gold - the mailbox window
--
-- Opening a mailbox shows this window instead of the game's. Three tabs:
--   Inbox            your mail on the left, the one you pick on the right:
--                    take one attachment, take the gold, or collect all
--                    (never C.O.D., GM mail or a sale still pending).
--   Send mail        To banker (quick-send), Apply rules, or Custom mail.
--                    Every mail, stack and copper of postage is shown first;
--                    then one click per mail sends it.
--   Auto-send rules  which materials go to which character, in order.
-- The banker strip stays on top on every tab. "Game's mailbox" switches to
-- Blizzard's window (remembered); a button on that window switches back.
--
-- Like the auction window, the game's mailbox stays open underneath (closing
-- it would close the mailbox), shrunk to nothing and invisible.

local _, ns = ...
local floor, max, min = math.floor, math.max, math.min

local K = ns.UIKit
local C = K.C
local tex, skin, label, button, setIcon, edgeFor = K.tex, K.skin, K.label, K.button, K.setIcon, K.edgeFor
local GREY = K.GREY
local MB = ns.Mail
local plain, plural = MB.Plain, MB.Plural

local W, H = 960, 610
local TOP = 128        -- where the tab content starts
local FOOT = 30
local SIDE_W = 300
local PAD = 12
local LIST_W = W - PAD * 3 - SIDE_W
local CLASS_ICONS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local GREEN, RED, GOLD = "|cff8fd37a", "|cffff7070", "|cffffd100"

local U = { tab = "inbox", mode = "banker", sel = {}, form = { picks = {} } }
ns.MailUI = U
local win

local function tipText(owner, lines, anchor)
    if not GameTooltip then
        return
    end
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    for i, l in ipairs(lines) do
        if i == 1 then
            GameTooltip:SetText(l, 1, 0.82, 0, 1, true)
        else
            GameTooltip:AddLine(l, 0.9, 0.9, 0.9, true)
        end
    end
    GameTooltip:Show()
end

local function untip()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

local function withTip(b, lines)
    b:SetScript("OnEnter", function(self) tipText(self, lines, "ANCHOR_BOTTOM") end)
    b:SetScript("OnLeave", untip)
    return b
end

local function classIcon(t, class)
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        t:SetTexture(CLASS_ICONS)
        t:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        setIcon(t, K.COIN)
    end
end

local function catIcon(key)
    local c = MB.CAT[key or ""]
    if c and c.icon then
        return ns.Icon(c.icon)
    end
    return nil
end

local function ruleIcon(r)
    if r.item then
        return ns.Icon(r.item), r.item
    end
    return catIcon(r.cat) or K.COIN, nil
end

----------------------------------------------------------------------
-- Building blocks
----------------------------------------------------------------------

-- A tick box with a label. b:SetChecked(on), b.checked.
local function checkbox(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 160, 22)
    local hl = tex(b, "HIGHLIGHT", 1, 0.92, 0.7, 0.06)
    hl:SetAllPoints()
    local box = CreateFrame("Frame", nil, b)
    box:SetSize(16, 16)
    box:SetPoint("LEFT", 2, 0)
    skin(box, 0.03, 0.03, 0.03, 1, C.btnEdge[1], C.btnEdge[2], C.btnEdge[3], 1)
    b.box = box
    b.mark = tex(box, "ARTWORK", C.goldEdge[1], C.goldEdge[2], C.goldEdge[3], 1)
    b.mark:SetPoint("TOPLEFT", 4, -4)
    b.mark:SetPoint("BOTTOMRIGHT", -4, 4)
    b.text = label(b, "GameFontHighlightSmall", text)
    b.text:SetPoint("LEFT", 24, 0)
    b.text:SetWidth((w or 160) - 26)
    b.text:SetWordWrap(false)
    function b:SetChecked(on)
        self.checked = on and true or false
        self.mark:SetShown(self.checked)
    end
    function b:SetLabel(t)
        self.text:SetText(t or "")
    end
    b:SetScript("OnClick", function(self)
        if self.disabled then
            return
        end
        self:SetChecked(not self.checked)
        if onClick then
            local ok, err = pcall(onClick, self.checked, self)
            if not ok then
                ns.Err("mail-check", err)
            end
        end
    end)
    b:SetChecked(false)
    return b
end

local function newEdit(parent, w, h, onChange, multi)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w, h or 22)
    skin(e, 0.02, 0.02, 0.02, 1, C.btnEdge[1], C.btnEdge[2], C.btnEdge[3], 1)
    if e.SetFontObject and _G.GameFontHighlightSmall then
        e:SetFontObject(_G.GameFontHighlightSmall)
    end
    e:SetAutoFocus(false)
    e:SetTextInsets(6, 6, multi and 4 or 0, multi and 4 or 0)
    if multi then
        e:SetMultiLine(true)
    end
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self)
        if not multi then
            self:ClearFocus()
        end
    end)
    e:SetScript("OnTextChanged", function(self, user)
        if user and onChange then
            local ok, err = pcall(onChange, self:GetText() or "")
            if not ok then
                ns.Err("mail-edit", err)
            end
        end
    end)
    return e
end

-- Gold typed by hand: "5" or "2.5" is gold; "1g 20s" works too.
local function parseGold(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return 0
    end
    if text:find("[gsc]") then
        return ns.ParseMoney(text)
    end
    local n = tonumber(text)
    return n and floor(n * 10000 + 0.5) or nil
end

local function goldText(copper)
    copper = copper or 0
    if copper % 10000 == 0 then
        return tostring(floor(copper / 10000))
    end
    return string.format("%.2f", copper / 10000):gsub("0+$", "")
end

-- The shared drop-down: a list of choices under a button.
local popup
local function hidePopup()
    if popup then
        popup:Hide()
        popup.owner = nil
    end
end

local POP_ROWS = 14
local function showPopup(owner, options, onPick)
    if popup and popup.owner == owner and popup:IsShown() then
        hidePopup()
        return
    end
    if not popup then
        popup = CreateFrame("Frame", "ForeverGoldMailPopup", UIParent)
        popup:SetFrameStrata("DIALOG")
        popup:SetSize(240, 20)
        skin(popup, C.panel[1], C.panel[2], C.panel[3], 1, C.goldEdge[1], C.goldEdge[2], C.goldEdge[3], 1)
        popup.rows = {}
        for i = 1, POP_ROWS do
            local r = CreateFrame("Button", nil, popup)
            r:SetSize(236, 20)
            r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 20)
            local hl = tex(r, "HIGHLIGHT", 1, 0.92, 0.7, 0.12)
            hl:SetAllPoints()
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(16, 16)
            r.icon:SetPoint("LEFT", 4, 0)
            r.text = label(r, "GameFontHighlightSmall")
            r.text:SetPoint("LEFT", 24, 0)
            r.text:SetWidth(206)
            r.text:SetWordWrap(false)
            r:SetScript("OnClick", function(self)
                local o = self.o
                if not o or o.disabled or o.header then
                    return
                end
                local fn = popup.onPick
                hidePopup()
                if fn then
                    local ok, err = pcall(fn, o.value, o)
                    if not ok then
                        ns.Err("mail-pick", err)
                    end
                end
            end)
            popup.rows[i] = r
        end
        popup:EnableMouseWheel(true)
        popup:SetScript("OnMouseWheel", function(_, delta)
            popup.offset = max(0, min(popup.offset - delta * 3, max(0, #popup.options - POP_ROWS)))
            popup:Render()
        end)
        function popup:Render()
            for i = 1, POP_ROWS do
                local r = self.rows[i]
                local o = self.options[i + self.offset]
                r.o = o
                if o then
                    r:Show()
                    r.text:SetText(o.header and (GREY .. o.text .. "|r") or o.text)
                    if o.coords then
                        r.icon:SetTexture(CLASS_ICONS)
                        r.icon:SetTexCoord(o.coords[1], o.coords[2], o.coords[3], o.coords[4])
                        r.icon:Show()
                    elseif o.icon then
                        setIcon(r.icon, o.icon)
                        r.icon:Show()
                    else
                        r.icon:Hide()
                    end
                    r.text:SetAlpha(o.disabled and 0.5 or 1)
                else
                    r:Hide()
                end
            end
        end
    end
    popup.owner, popup.options, popup.onPick, popup.offset = owner, options, onPick, 0
    popup:SetHeight(4 + 20 * min(POP_ROWS, max(1, #options)))
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    popup:Render()
    popup:Show()
end
U.ShowPopup = showPopup
U.Popup = function() return popup end

local function picker(parent, w, getOptions, onPick)
    local b = button(parent, "", w, 22, nil)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", 8, 0)
    b.text:SetWidth(w - 22)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    local arrow = label(b, "GameFontNormalSmall", "v")
    arrow:SetPoint("RIGHT", -7, 0)
    b.onClick = function(self)
        showPopup(self, getOptions(), onPick)
    end
    return b
end

-- A scrolling list of rows: icon, two lines on the left, two on the right,
-- an optional tick box and up to two small buttons.
-- row data: { key, check = true|false|nil, prio, icon, coords, id, title, sub,
--             r1, r2, dim, b1 = { text, fn, disabled }, b2, tip = {lines},
--             mail = { index, a } }
local function newRows(parent, w, h, rowH, opts)
    opts = opts or {}
    local L = CreateFrame("Frame", nil, parent)
    L:SetSize(w, h)
    skin(L, 0.045, 0.043, 0.04, 1, C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 1)
    L.rows, L.data, L.offset = {}, {}, 0
    L.visible = floor((h - 4) / rowH)
    local iconSize = rowH - 12
    local btnSpace = opts.buttons and 58 or 0
    local x = 10
    if opts.check then
        x = x + 24
    end
    if opts.prio then
        x = x + 16
    end
    local textX = x + iconSize + 10
    for i = 1, L.visible do
        local r = CreateFrame("Button", nil, L)
        r:SetSize(w - 8, rowH)
        r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * rowH)
        r.sel = tex(r, "BACKGROUND", 0.22, 0.20, 0.14, 1)
        r.sel:SetAllPoints()
        r.bar = tex(r, "ARTWORK", C.goldEdge[1], C.goldEdge[2], C.goldEdge[3], 1)
        r.bar:SetPoint("TOPLEFT")
        r.bar:SetPoint("BOTTOMLEFT")
        r.bar:SetWidth(3)
        local line = tex(r, "BORDER", C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 0.8)
        line:SetPoint("BOTTOMLEFT", 6, 0)
        line:SetPoint("BOTTOMRIGHT", -6, 0)
        line:SetHeight(1)
        local hl = tex(r, "HIGHLIGHT", 1, 0.92, 0.7, 0.05)
        hl:SetAllPoints()
        if opts.check then
            local cb = CreateFrame("Button", nil, r)
            cb:SetSize(16, 16)
            cb:SetPoint("LEFT", 10, 0)
            skin(cb, 0.02, 0.02, 0.02, 1, C.btnEdge[1], C.btnEdge[2], C.btnEdge[3], 1)
            cb.mark = tex(cb, "ARTWORK", C.goldEdge[1], C.goldEdge[2], C.goldEdge[3], 1)
            cb.mark:SetPoint("TOPLEFT", 4, -4)
            cb.mark:SetPoint("BOTTOMRIGHT", -4, 4)
            cb:SetScript("OnClick", function()
                if r.d and r.d.check ~= nil and L.onCheck then
                    local ok, err = pcall(L.onCheck, r.d)
                    if not ok then
                        ns.Err("mail-rows", err)
                    end
                end
            end)
            r.check = cb
        end
        if opts.prio then
            r.prio = label(r, "GameFontDisableSmall")
            r.prio:SetPoint("LEFT", x - 14, 0)
        end
        r.iconEdge = r:CreateTexture(nil, "BORDER")
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(iconSize, iconSize)
        r.icon:SetPoint("LEFT", x, 0)
        r.iconEdge:SetPoint("TOPLEFT", r.icon, "TOPLEFT", -1, 1)
        r.iconEdge:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 1, -1)
        r.title = label(r, "GameFontHighlight")
        r.title:SetPoint("TOPLEFT", textX, -(rowH / 2 - 13))
        r.title:SetWidth(w - textX - 150 - btnSpace)
        r.title:SetWordWrap(false)
        r.sub = label(r, "GameFontDisableSmall")
        r.sub:SetPoint("TOPLEFT", textX, -(rowH / 2 + 2))
        r.sub:SetWidth(w - textX - 150 - btnSpace)
        r.sub:SetWordWrap(false)
        r.r1 = label(r, "GameFontHighlight")
        r.r1:SetPoint("TOPRIGHT", -(10 + btnSpace), -(rowH / 2 - 13))
        r.r1:SetWidth(140)
        r.r1:SetJustifyH("RIGHT")
        r.r1:SetWordWrap(false)
        r.r2 = label(r, "GameFontDisableSmall")
        r.r2:SetPoint("TOPRIGHT", -(10 + btnSpace), -(rowH / 2 + 2))
        r.r2:SetWidth(140)
        r.r2:SetJustifyH("RIGHT")
        r.r2:SetWordWrap(false)
        if opts.buttons then
            for j = 1, 2 do
                local b = button(r, "", 24, 20, function(self)
                    local spec = r.d and r.d["b" .. j]
                    if spec and spec.fn and not spec.disabled then
                        spec.fn(r.d)
                    end
                end)
                b:SetPoint("RIGHT", -6 - (2 - j) * 27, 0)
                r["b" .. j] = b
            end
        end
        r:SetScript("OnClick", function(self, which)
            local d = self.d
            if not d then
                return
            end
            if d.id and ns.TryDressUp(d.id) then
                return
            end
            if d.id and IsShiftKeyDown and IsShiftKeyDown() then
                local _, link = ns.try(C_Item.GetItemInfo, d.id)
                if link and ChatEdit_InsertLink then
                    pcall(ChatEdit_InsertLink, link)
                end
                return
            end
            if which == "RightButton" then
                if L.onRight then
                    local ok, err = pcall(L.onRight, d)
                    if not ok then
                        ns.Err("mail-rows", err)
                    end
                end
                return
            end
            if L.onClick then
                local ok, err = pcall(L.onClick, d)
                if not ok then
                    ns.Err("mail-rows", err)
                end
            end
        end)
        if r.RegisterForClicks then
            r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        end
        r:SetScript("OnEnter", function(self)
            local d = self.d
            if not d or not GameTooltip then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local shown = false
            if d.mail and GameTooltip.SetInboxItem then
                shown = pcall(GameTooltip.SetInboxItem, GameTooltip, d.mail.index, d.mail.a)
            elseif d.id then
                shown = pcall(GameTooltip.SetItemByID, GameTooltip, d.id)
            end
            for k, l in ipairs(d.tip or {}) do
                if k == 1 and not shown then
                    GameTooltip:SetText(l, 1, 0.82, 0, 1, true)
                    shown = true
                else
                    GameTooltip:AddLine(l, 0.9, 0.9, 0.9, true)
                end
            end
            if shown then
                GameTooltip:Show()
            else
                GameTooltip:Hide()
            end
        end)
        r:SetScript("OnLeave", untip)
        L.rows[i] = r
    end
    L.thumb = tex(L, "OVERLAY", C.edge[1], C.edge[2], C.edge[3], 0.9)
    L.thumb:SetWidth(3)
    L.empty = label(L, "GameFontDisable")
    L.empty:SetPoint("TOP", 0, -70)
    L.empty:SetWidth(w - 60)
    L.empty:SetJustifyH("CENTER")
    L:EnableMouseWheel(true)
    L:SetScript("OnMouseWheel", function(_, delta)
        L.offset = L.offset - delta * 2
        L:Render()
    end)
    function L:SetData(list, keep)
        self.data = list or {}
        if not keep then
            self.offset = 0
        end
        self:Render()
    end
    function L:Render()
        local n = #self.data
        local maxOff = max(0, n - self.visible)
        self.offset = max(0, min(self.offset, maxOff))
        for i = 1, self.visible do
            local r = self.rows[i]
            local d = self.data[i + self.offset]
            r.d = d
            if d then
                r:Show()
                local on = self.selected ~= nil and d.key == self.selected
                r.sel:SetShown(on)
                r.bar:SetShown(on)
                if d.icon or d.id or d.coords then
                    if d.coords then
                        r.icon:SetTexture(CLASS_ICONS)
                        r.icon:SetTexCoord(d.coords[1], d.coords[2], d.coords[3], d.coords[4])
                    else
                        setIcon(r.icon, d.icon or ns.Icon(d.id))
                    end
                    edgeFor(r.iconEdge, d.id)
                    r.icon:Show()
                    r.iconEdge:Show()
                    if r.icon.SetDesaturated then
                        r.icon:SetDesaturated(d.dim and true or false)
                    end
                else
                    r.icon:Hide()
                    r.iconEdge:Hide()
                end
                if r.check then
                    r.check:SetShown(d.check ~= nil)
                    r.check.mark:SetShown(d.check and true or false)
                end
                if r.prio then
                    r.prio:SetText(d.prio and tostring(d.prio) or "")
                end
                r.title:SetText(d.title or "")
                r.sub:SetText(d.sub or "")
                r.r1:SetText(d.r1 or "")
                r.r2:SetText(d.r2 or "")
                local a = d.dim and 0.55 or 1
                r.title:SetAlpha(a)
                r.r1:SetAlpha(a)
                for j = 1, 2 do
                    local b, spec = r["b" .. j], d["b" .. j]
                    if b then
                        if spec then
                            b:Show()
                            b:SetLabel(spec.text)
                            b:SetDisabled(spec.disabled)
                        else
                            b:Hide()
                        end
                    end
                end
            else
                r:Hide()
            end
        end
        self.empty:SetShown(n == 0)
        if maxOff > 0 then
            local trackH = self:GetHeight() - 6
            local size = max(20, trackH * self.visible / n)
            self.thumb:SetHeight(size)
            self.thumb:ClearAllPoints()
            self.thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", -2, -3 - (trackH - size) * (self.offset / maxOff))
            self.thumb:Show()
        else
            self.thumb:Hide()
        end
    end
    function L:SetEmpty(text)
        self.empty:SetText(text or "")
    end
    -- Shrinks (or grows back, up to the rows it was built with) to fit h.
    function L:SetListHeight(newH)
        if self:GetHeight() == newH then
            return
        end
        self:SetHeight(newH)
        self.visible = min(#self.rows, max(1, floor((newH - 4) / rowH)))
        for i = self.visible + 1, #self.rows do
            self.rows[i]:Hide()
        end
        self.empty:ClearAllPoints()
        self.empty:SetPoint("TOP", 0, -min(70, floor(newH / 3)))
        self:Render()
    end
    return L
end

-- The right-hand panel's frame.
local function newSide(parent, h)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(SIDE_W, h)
    s:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, 0)
    skin(s, C.panel[1], C.panel[2], C.panel[3], 1, C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 1)
    return s
end

local function smallCaps(parent, text)
    local fs = label(parent, "GameFontDisableSmall", text)
    return fs
end

local function heading(parent, text)
    local fs = label(parent, "GameFontNormalLarge", text)
    fs:SetTextColor(C.goldText[1], C.goldText[2], C.goldText[3])
    return fs
end

local function lineTex(parent, y)
    local t = tex(parent, "BORDER", C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 0.9)
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", 12, y)
    t:SetPoint("TOPRIGHT", -12, y)
    return t
end

-- Two labels on one line, left and right.
local function summaryLine(parent, y)
    local l = label(parent, "GameFontDisableSmall")
    l:SetPoint("TOPLEFT", 14, y)
    local r = label(parent, "GameFontHighlightSmall")
    r:SetPoint("TOPRIGHT", -14, y)
    r:SetJustifyH("RIGHT")
    return { l = l, r = r, Set = function(self, a, b) self.l:SetText(a or ""); self.r:SetText(b or "") end }
end

local STATUS_COLOR = { idle = GREY, working = "|cffe6d39a", waiting = "|cffe6d39a", ready = GREEN, confirm = GOLD,
    done = GREEN, error = RED, unclear = RED }

local function statusText()
    local s = MB.status
    if s and s.text and s.text ~= "" then
        return (STATUS_COLOR[s.kind] or "") .. s.text .. "|r", s.kind
    end
    return nil, "idle"
end

----------------------------------------------------------------------
-- The banker strip (on every tab)
----------------------------------------------------------------------

local function bankerLabel()
    local key = MB.BankerKey()
    if not key then
        return nil
    end
    local c = ns.db.chars[key]
    return c and c.name, c and c.class, c and c.faction, key == ns.charKey
end

local function buildBankerStrip(f)
    local s = CreateFrame("Frame", nil, f)
    s:SetPoint("TOPLEFT", PAD, -78)
    s:SetPoint("TOPRIGHT", -PAD, -78)
    s:SetHeight(42)
    skin(s, 0.12, 0.115, 0.10, 1, C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 1)
    s.iconEdge = s:CreateTexture(nil, "BORDER")
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetSize(28, 28)
    s.icon:SetPoint("LEFT", 10, 0)
    s.iconEdge:SetPoint("TOPLEFT", s.icon, "TOPLEFT", -1, 1)
    s.iconEdge:SetPoint("BOTTOMRIGHT", s.icon, "BOTTOMRIGHT", 1, -1)
    s.iconEdge:SetColorTexture(C.goldEdge[1], C.goldEdge[2], C.goldEdge[3], 0.8)
    s.cap = smallCaps(s, "Your banker")
    s.cap:SetPoint("TOPLEFT", 48, -6)
    s.name = label(s, "GameFontHighlight")
    s.name:SetPoint("TOPLEFT", 48, -21)
    s.name:SetWidth(260)
    s.name:SetWordWrap(false)
    s.change = withTip(button(s, "Change banker", 110, 24, function() U.ToggleBankerPanel() end),
        { "Change banker", "Pick which of your characters gets auction stock, and what quick-send includes." })
    s.change:SetPoint("LEFT", 320, 0)
    s.quick = withTip(button(s, "Quick-send to banker", 170, 26, function() U.QuickSend() end),
        { "Quick-send to banker", "Shows exactly what would go to your banker first. Nothing is sent until you press Send on each mail." })
    s.quick:SetPoint("RIGHT", -8, 0)
    s.quick:SetPrimary(true)
    s.note = label(s, "GameFontDisableSmall")
    s.note:SetPoint("RIGHT", s.quick, "LEFT", -12, 0)
    s.note:SetWidth(260)
    s.note:SetJustifyH("RIGHT")
    s.note:SetWordWrap(false)

    -- The banker settings, dropped down under the strip.
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -2)
    p:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -2)
    p:SetHeight(150)
    p:SetFrameLevel((f.GetFrameLevel and f:GetFrameLevel() or 1) + 20)
    skin(p, 0.16, 0.145, 0.11, 1, C.goldEdge[1], C.goldEdge[2], C.goldEdge[3], 1)
    p:EnableMouse(true)
    p.cap = smallCaps(p, "Banker character")
    p.cap:SetPoint("TOPLEFT", 14, -10)
    p.pick = picker(p, 240, function() return U.BankerOptions() end, function(key)
        MB.SetBanker(key)
        U.Refresh()
    end)
    p.pick:SetPoint("TOPLEFT", 14, -26)
    p.help = label(p, "GameFontDisableSmall",
        "Used by quick-send and by rules sent to \"Banker\". Only your characters on this realm and faction are listed.")
    p.help:SetPoint("TOPLEFT", 270, -28)
    p.help:SetWidth(W - 2 * PAD - 300)
    p.cap2 = smallCaps(p, "Quick-send also includes (only if you tick them)")
    p.cap2:SetPoint("TOPLEFT", 14, -62)
    p.cats = {}
    local col, rowY = 0, -80
    for _, c in ipairs(MB.CATS) do
        if not c.stock then
            local key = c.key
            local cb = checkbox(p, c.name, 175, function(on)
                ns.db.opts.mailQuickCats = ns.db.opts.mailQuickCats or {}
                ns.db.opts.mailQuickCats[key] = on and true or nil
                U.Refresh()
            end)
            cb:SetPoint("TOPLEFT", 14 + col * 180, rowY)
            p.cats[key] = cb
            col = col + 1
            if col >= 5 then
                col, rowY = 0, rowY - 24
            end
        end
    end
    p.close = button(p, "Done", 70, 22, function() U.ToggleBankerPanel(false) end)
    p.close:SetPoint("BOTTOMRIGHT", -10, 10)
    p:Hide()
    f.bankerPanel = p
    return s
end

function U.BankerOptions()
    local out = {}
    for _, c in ipairs(MB.Characters(true)) do
        local coords = c.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.class]
        out[#out + 1] = { text = c.name .. (c.self and (GREY .. "  (you)|r") or "") .. GREY .. "  " .. (c.level or "?") .. "|r",
            value = c.key, coords = coords, icon = (not coords) and K.COIN or nil }
    end
    if #out == 0 then
        out[1] = { text = "No characters known yet: log in on each once.", header = true }
    end
    return out
end

function U.ToggleBankerPanel(show)
    if not win then
        return
    end
    local p = win.bankerPanel
    if show == nil then
        show = not p:IsShown()
    end
    p:SetShown(show)
    hidePopup()
    U.Refresh()
end

local function refreshBankerStrip()
    local s = win.strip
    local name, class, faction, isSelf = bankerLabel()
    classIcon(s.icon, class)
    if name then
        s.name:SetText(name .. GREY .. "  " .. (faction or "") .. (isSelf and "  (this character)" or "") .. "|r")
    else
        s.name:SetText(GREY .. "None picked yet|r")
    end
    local busy = MB.Busy()
    s.quick:SetDisabled(not MB.open or busy or not name or isSelf)
    if not name then
        s.note:SetText("Pick a banker to use quick-send.")
    elseif isSelf then
        s.note:SetText("You are the banker.")
    elseif busy then
        s.note:SetText("Busy: one mail action at a time.")
    else
        s.note:SetText("")
    end
    local p = win.bankerPanel
    if p:IsShown() then
        p.pick:SetLabel(name or "Pick a character")
        local cats = ns.db.opts.mailQuickCats or {}
        for key, cb in pairs(p.cats) do
            cb:SetChecked(cats[key])
        end
    end
end

----------------------------------------------------------------------
-- Inbox
----------------------------------------------------------------------

local function expiryText(days)
    days = days or 0
    if days >= 1 then
        return "Expires in " .. plural(floor(days), "day")
    end
    local hours = floor(days * 24)
    return RED .. "Expires in " .. (hours >= 1 and plural(hours, "hour") or "under an hour") .. "|r"
end

local function mailKey(m)
    return m.fp.sender .. "|" .. m.fp.subject .. "|" .. m.index
end

local function mailIcon(m)
    local first = m.items[1]
    if first and first.icon then
        return first.icon, first.id
    end
    if m.money > 0 then
        return K.COIN, nil
    end
    return m.stationery or "Interface\\Icons\\INV_Letter_15", nil
end

local function buildInbox(f)
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", 0, -TOP)
    p:SetSize(W, H - TOP - FOOT)
    local listH = H - TOP - FOOT - 56
    p.title = heading(p, "Your mail")
    p.title:SetPoint("TOPLEFT", PAD + 2, -2)
    p.summary = label(p, "GameFontDisableSmall")
    p.summary:SetPoint("TOPLEFT", PAD + 2, -24)
    p.summary:SetWidth(LIST_W - 300)
    p.summary:SetWordWrap(false)
    p.collect = withTip(button(p, "Collect all", 110, 24, function()
        local ok, why = MB.CollectAll()
        if not ok and why then MB.SetStatus("error", why) end
    end), { "Collect all", "Takes the gold and items from every mail it's safe to: never C.O.D. (that needs paying), never mail from a Game Master, never a sale that's still pending. It never returns or deletes mail." })
    p.collect:SetPoint("TOPRIGHT", p, "TOPLEFT", PAD + LIST_W, -4)
    p.collect:SetPrimary(true)
    p.gold = withTip(button(p, "Collect gold", 100, 24, function()
        local ok, why = MB.CollectGold()
        if not ok and why then MB.SetStatus("error", why) end
    end), { "Collect gold", "Takes only the gold, from every mail it's safe to." })
    p.gold:SetPoint("RIGHT", p.collect, "LEFT", -6, 0)
    p.stop = button(p, "Stop", 60, 24, function() MB.Stop() end)
    p.stop:SetPoint("RIGHT", p.gold, "LEFT", -6, 0)
    p.refresh = withTip(button(p, "Refresh", 70, 24, function() U.CheckInbox() end),
        { "Refresh", "Asks the server for new mail. It allows this about once a minute." })
    p.refresh:SetPoint("RIGHT", p.stop, "LEFT", -6, 0)

    p.list = newRows(p, LIST_W, listH, 46, {})
    p.list:SetPoint("TOPLEFT", PAD, -40)
    p.list.onClick = function(d)
        U.sel.mail = d.key
        U.sel.bodyKey = nil
        U.Refresh()
    end
    p.more = label(p, "GameFontDisableSmall")
    p.more:SetPoint("TOPLEFT", p.list, "BOTTOMLEFT", 2, -4)
    p.more:SetWidth(LIST_W)

    local s = newSide(p, listH + 40)
    s:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -2)
    s.from = smallCaps(s, "")
    s.from:SetPoint("TOPLEFT", 14, -12)
    s.from:SetWidth(SIDE_W - 28)
    s.from:SetWordWrap(false)
    s.subject = label(s, "GameFontNormalLarge")
    s.subject:SetTextColor(C.goldText[1], C.goldText[2], C.goldText[3])
    s.subject:SetPoint("TOPLEFT", 14, -30)
    s.subject:SetWidth(SIDE_W - 28)
    s.subject:SetWordWrap(true)
    s.expires = label(s, "GameFontDisableSmall")
    s.expires:SetPoint("TOPLEFT", 14, -70)
    s.expires:SetWidth(SIDE_W - 28)
    s.body = label(s, "GameFontHighlightSmall")
    s.body:SetPoint("TOPLEFT", 14, -90)
    s.body:SetWidth(SIDE_W - 28)
    s.body:SetHeight(110)
    s.body:SetJustifyV("TOP")
    s.body:SetWordWrap(true)
    s.rule = lineTex(s, -206)
    s.moneyIcon = s:CreateTexture(nil, "ARTWORK")
    s.moneyIcon:SetSize(24, 24)
    s.moneyIcon:SetPoint("TOPLEFT", 14, -216)
    setIcon(s.moneyIcon, K.COIN)
    s.money = label(s, "GameFontHighlight")
    s.money:SetPoint("TOPLEFT", 46, -216)
    s.moneySub = label(s, "GameFontDisableSmall")
    s.moneySub:SetPoint("TOPLEFT", 46, -232)
    s.takeGold = button(s, "Take gold", 90, 22, function()
        local ok, why = MB.TakeMoney(U.SelectedMail())
        if not ok and why then MB.SetStatus("error", why) end
    end)
    s.takeGold:SetPoint("TOPRIGHT", -14, -218)
    s.attCap = smallCaps(s, "ATTACHMENTS - click one to take it")
    s.attCap:SetPoint("TOPLEFT", 14, -256)
    s.atts = {}
    local per = 6
    for i = 1, 16 do
        local b = CreateFrame("Button", nil, s)
        b:SetSize(38, 38)
        local col, row = (i - 1) % per, floor((i - 1) / per)
        b:SetPoint("TOPLEFT", 14 + col * 44, -272 - row * 44)
        b.edge = b:CreateTexture(nil, "BORDER")
        b.edge:SetAllPoints()
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b.count = label(b, "NumberFontNormal")
        b.count:SetPoint("BOTTOMRIGHT", -2, 2)
        b.count:SetJustifyH("RIGHT")
        local hl = tex(b, "HIGHLIGHT", 1, 1, 1, 0.15)
        hl:SetAllPoints()
        b:SetScript("OnClick", function(self)
            local m = U.SelectedMail()
            if not m or not self.a then
                return
            end
            local ok, why = MB.TakeAttachment(m, self.a)
            if not ok and why then
                MB.SetStatus("error", why)
            end
        end)
        b:SetScript("OnEnter", function(self)
            local m = U.SelectedMail()
            if not m or not GameTooltip then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not (GameTooltip.SetInboxItem and pcall(GameTooltip.SetInboxItem, GameTooltip, m.index, self.a)) then
                GameTooltip:SetText(self.name or "Item", 1, 1, 1)
            end
            if m.cod > 0 then
                GameTooltip:AddLine("C.O.D. " .. plain(m.cod) .. ": pay for it in the game's mailbox.", 1, 0.45, 0.45, true)
            else
                GameTooltip:AddLine("Click to take it.", 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", untip)
        s.atts[i] = b
    end
    s.note = label(s, "GameFontHighlightSmall")
    s.note:SetPoint("BOTTOMLEFT", 14, 12)
    s.note:SetWidth(SIDE_W - 28)
    s.note:SetJustifyV("BOTTOM")
    s.note:SetWordWrap(true)
    s.noMail = label(s, "GameFontDisable")
    s.noMail:SetPoint("TOP", 0, -60)
    s.noMail:SetWidth(SIDE_W - 40)
    s.noMail:SetJustifyH("CENTER")
    p.side = s
    return p
end

function U.SelectedMail()
    for _, m in ipairs(MB.inbox) do
        if mailKey(m) == U.sel.mail then
            return m
        end
    end
    return nil
end

function U.CheckInbox()
    local can, wait = true, 0
    if C_Mail and C_Mail.CanCheckInbox then
        local ok, a, b = pcall(C_Mail.CanCheckInbox)
        if ok then
            can, wait = a, b or 0
        end
    end
    if can and type(CheckInbox) == "function" then
        pcall(CheckInbox)
        MB.SetStatus("working", "Checking for new mail...")
    else
        MB.SetStatus("idle", "The server allows a refresh again in " .. math.ceil(wait or 0) .. " seconds.")
    end
end

local function refreshInbox()
    local p = win.inbox
    local s = p.side
    local busy, op = MB.Busy()
    local rows = {}
    for _, m in ipairs(MB.inbox) do
        local icon, id = mailIcon(m)
        local title = m.subject ~= "" and m.subject or "(no subject)"
        if not m.read then
            title = GOLD .. title .. "|r"
        end
        local r1, r2
        if m.cod > 0 then
            r1, r2 = RED .. "C.O.D. " .. plain(m.cod) .. "|r", "open it in the game's mailbox"
        elseif m.money > 0 then
            r1 = ns.Money(m.money)
            r2 = #m.items > 0 and ("+ " .. plural(#m.items, "attachment")) or ""
        elseif #m.items > 0 then
            local n = 0
            for _, it in ipairs(m.items) do n = n + (it.count or 1) end
            r1 = #m.items == 1 and ("x" .. n) or plural(#m.items, "attachment")
            r2 = ""
        else
            r1, r2 = GREY .. "letter|r", ""
        end
        if m.restricted == "gm" then
            r2 = GOLD .. "From a Game Master|r"
        elseif m.restricted == "pending" then
            r2 = "sale pending"
        end
        rows[#rows + 1] = { key = mailKey(m), icon = icon, id = id, title = title,
            sub = (m.sender or "?") .. "  -  " .. expiryText(m.days), r1 = r1, r2 = r2,
            mail = m.items[1] and { index = m.index, a = m.items[1].a } or nil,
            tip = m.items[1] and nil or { m.subject, "From " .. (m.sender or "?") } }
    end
    if not U.SelectedMail() then
        U.sel.mail = rows[1] and rows[1].key or nil
        U.sel.bodyKey = nil
    end
    p.list.selected = U.sel.mail
    if MB.inboxState == "loading" then
        p.list:SetEmpty("Checking your mail...")
    elseif not MB.open then
        p.list:SetEmpty("Open a mailbox to read your mail.")
    else
        p.list:SetEmpty("All caught up. Your mailbox is empty.")
    end
    p.list:SetData(rows, true)
    local money, items, cod = MB.InboxTotals()
    local n = #MB.inbox
    if MB.inboxState == "loading" then
        p.summary:SetText("Checking...")
    else
        p.summary:SetText(plural(n, "message") .. "  -  " .. plain(money) .. " to collect"
            .. (items > 0 and (", " .. plural(items, "item")) or "") .. (cod > 0 and ("  -  " .. RED .. cod .. " C.O.D.|r") or ""))
    end
    if MB.numTotal > MB.numShown then
        p.more:SetText((MB.numTotal - MB.numShown) .. " more waiting on the server. They come in as you clear this list (use Refresh).")
    else
        p.more:SetText("")
    end
    local collecting = busy == "collect"
    p.collect:SetDisabled(not MB.open or busy or n == 0)
    p.collect:SetLabel(collecting and "Collecting..." or "Collect all")
    p.gold:SetDisabled(not MB.open or busy or money == 0)
    p.stop:SetShown(collecting)
    p.refresh:SetDisabled(not MB.open or busy)

    local m = U.SelectedMail()
    local hasMail = m ~= nil
    for _, x in ipairs({ s.from, s.subject, s.expires, s.body, s.rule, s.attCap }) do
        x:SetShown(hasMail)
    end
    s.noMail:SetShown(not hasMail)
    s.noMail:SetText(MB.inboxState == "loading" and "Checking your mail..." or "No mail selected.\nNew mail will appear here.")
    if not m then
        s.moneyIcon:Hide(); s.money:Hide(); s.moneySub:Hide(); s.takeGold:Hide()
        for _, b in ipairs(s.atts) do b:Hide() end
        s.note:SetText("")
        return
    end
    s.from:SetText("FROM " .. (m.sender or "?"):upper())
    s.subject:SetText(m.subject ~= "" and m.subject or "(no subject)")
    s.expires:SetText(expiryText(m.days) .. (m.returned and "  -  returned to you" or ""))
    local key = mailKey(m)
    if U.sel.bodyKey ~= key then
        U.sel.bodyKey = key
        U.sel.body = MB.Body(m)
    end
    local body = U.sel.body or ""
    if body == "" then
        if m.invoice == "seller" then
            body = "Your auction sold. Collect the gold below."
        elseif m.invoice == "seller_temp_invoice" then
            body = "Your auction sold. The gold is on its way and arrives in this mailbox later."
        elseif m.invoice == "buyer" then
            body = "You won this auction. The item is attached."
        else
            body = GREY .. "No letter.|r"
        end
    end
    s.body:SetText(body)
    local showMoney = m.money > 0 or m.cod > 0
    s.moneyIcon:SetShown(showMoney)
    s.money:SetShown(showMoney)
    s.moneySub:SetShown(showMoney)
    s.takeGold:SetShown(m.money > 0)
    s.takeGold:SetDisabled(busy or not MB.open)
    if m.cod > 0 then
        s.money:SetText(RED .. plain(m.cod) .. "|r")
        s.moneySub:SetText("C.O.D.: you'd pay this to take the items")
    else
        s.money:SetText(ns.Money(m.money))
        s.moneySub:SetText(m.invoice == "seller" and "Auction proceeds" or "Gold attached")
    end
    local ay = showMoney and -256 or -216
    s.attCap:ClearAllPoints()
    s.attCap:SetPoint("TOPLEFT", 14, ay)
    s.attCap:SetText(#m.items > 0 and (m.cod > 0 and "ATTACHMENTS - C.O.D., take them in the game's mailbox"
        or "ATTACHMENTS - click one to take it") or "NO ATTACHMENTS")
    for i, b in ipairs(s.atts) do
        local it = m.items[i]
        if it then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 14 + ((i - 1) % 6) * 44, ay - 16 - floor((i - 1) / 6) * 44)
            b:Show()
            b.a, b.name = it.a, it.name
            setIcon(b.icon, it.icon or ns.Icon(it.id))
            edgeFor(b.edge, it.id)
            b.count:SetText((it.count or 1) > 1 and tostring(it.count) or "")
            b.icon:SetAlpha(m.cod > 0 and 0.5 or 1)
        else
            b:Hide()
            b.a = nil
        end
    end
    local why = MB.BulkSkipReason(m)
    local text = why and (GOLD .. "Collect all skips this: " .. why .. ".|r") or ""
    if m.restricted == "cod" then
        text = RED .. "Cash on delivery: " .. plain(m.cod) .. ".|r Forever Gold never pays C.O.D. Use the game's mailbox (top right) to pay and take it."
    end
    s.note:SetText(text)
end

----------------------------------------------------------------------
-- Send mail
----------------------------------------------------------------------

local MODES = {
    banker = { title = "Send to your banker", sub = "Auction stock and the categories you added. Crafting materials and anything a rule sends elsewhere stay." },
    rules = { title = "Your rules, ready to send", sub = "Matching materials grouped by recipient, with your keep amounts left in your bags." },
    custom = { title = "Compose a mail", sub = "Pick a recipient and the stacks to attach. Gold and C.O.D. are optional." },
}

local SKIP_TEXT = {
    self = "stays here: the rule sends it to this character",
    nobanker = "the rule sends it to your banker, and none is picked",
    elsewhere = "the rule's character can't be mailed from here",
    unset = "the rule has no recipient yet",
    keep = "all of it is within the keep amount",
    stacks = "no whole stack fits under the keep amount",
    craft = "a profitable recipe of yours uses it",
    rule = "a rule sends it somewhere else",
    bound = "soulbound: can't be mailed",
    ["quest item"] = "quest item: can't be mailed",
    locked = "locked right now",
    unmailable = "can't be mailed",
}

local function buildSend(f)
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", 0, -TOP)
    p:SetSize(W, H - TOP - FOOT)
    p.title = heading(p, "")
    p.title:SetPoint("TOPLEFT", PAD + 2, -2)
    p.sub = label(p, "GameFontDisableSmall")
    p.sub:SetPoint("TOPLEFT", PAD + 2, -24)
    p.sub:SetWidth(LIST_W)
    p.sub:SetWordWrap(false)
    p.modes = {}
    local x = PAD
    for _, m in ipairs({ { "banker", "To banker" }, { "rules", "Apply rules" }, { "custom", "Custom mail" } }) do
        local key = m[1]
        local b = button(p, m[2], 110, 24, function() U.SetMode(key) end)
        b:SetPoint("TOPLEFT", x, -42)
        p.modes[key] = b
        x = x + 114
    end
    p.pill = label(p, "GameFontNormalSmall", "MAIL PREVIEW")
    p.pill:SetPoint("TOPRIGHT", p, "TOPLEFT", PAD + LIST_W - 6, -48)

    -- Custom mail fields.
    local c = CreateFrame("Frame", nil, p)
    c:SetPoint("TOPLEFT", PAD, -72)
    c:SetSize(LIST_W, 112)
    c.toCap = smallCaps(c, "Recipient")
    c.toCap:SetPoint("TOPLEFT", 0, 0)
    c.to = newEdit(c, 180, 22, function(text)
        U.form.to = text
        U.Refresh()
    end)
    c.to:SetPoint("TOPLEFT", 0, -14)
    c.toPick = picker(c, 120, function()
        local out = {}
        for _, ch in ipairs(MB.Characters(false)) do
            local coords = ch.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[ch.class]
            out[#out + 1] = { text = ch.name, value = ch.name, coords = coords }
        end
        if #out == 0 then
            out[1] = { text = "No other characters known", header = true }
        end
        return out
    end, function(name)
        U.form.to = name
        win.send.custom.to:SetText(name)
        U.Refresh()
    end)
    c.toPick:SetPoint("LEFT", c.to, "RIGHT", 4, 0)
    c.toPick:SetLabel("Your characters")
    c.subjCap = smallCaps(c, "Subject")
    c.subjCap:SetPoint("TOPLEFT", 312, 0)
    c.subject = newEdit(c, LIST_W - 312, 22, function(text)
        U.form.subject = text
        U.Refresh()
    end)
    c.subject:SetPoint("TOPLEFT", 312, -14)
    c.bodyCap = smallCaps(c, "Message")
    c.bodyCap:SetPoint("TOPLEFT", 0, -42)
    c.body = newEdit(c, 380, 52, function(text)
        U.form.body = text
    end, true)
    c.body:SetPoint("TOPLEFT", 0, -56)
    c.moneyCap = smallCaps(c, "Gold")
    c.moneyCap:SetPoint("TOPLEFT", 392, -42)
    c.money = newEdit(c, 80, 22, function(text)
        U.form.moneyText = text
        U.Refresh()
    end)
    c.money:SetPoint("TOPLEFT", 392, -56)
    c.sendMoney = button(c, "Send gold", 70, 22, function()
        U.form.cod = false
        U.Refresh()
    end)
    c.sendMoney:SetPoint("LEFT", c.money, "RIGHT", 4, 0)
    c.cod = withTip(button(c, "C.O.D.", 56, 22, function()
        U.form.cod = true
        U.Refresh()
    end), { "Cash on delivery", "The recipient pays this amount to take the attachments. Needs at least one attachment." })
    c.cod:SetPoint("LEFT", c.sendMoney, "RIGHT", 4, 0)
    c.hint = label(c, "GameFontDisableSmall", "Tick the stacks to attach below.")
    c.hint:SetPoint("TOPLEFT", 392, -84)
    p.custom = c

    p.list = newRows(p, LIST_W, H - TOP - FOOT - 72 - 40, 40, { check = true })
    p.list.onCheck = function(d)
        if d.check == nil then
            return -- a row that stays (or a queued mail): nothing to tick
        end
        if d.stackKey then
            U.form.picks[d.stackKey] = not U.form.picks[d.stackKey] or nil
        elseif d.id then
            MB.exclude[d.id] = not MB.exclude[d.id] or nil
        end
        U.Refresh()
    end
    p.list.onClick = p.list.onCheck
    p.list.onRight = function(d)
        if d.id and U.mode ~= "custom" then
            MB.SetKept(d.id, not MB.IsKept(d.id))
            U.Refresh()
        end
    end
    p.help = label(p, "GameFontDisableSmall")
    p.help:SetPoint("TOPLEFT", p.list, "BOTTOMLEFT", 2, -6)
    p.help:SetWidth(LIST_W)
    p.help:SetWordWrap(true)

    -- The outgoing panel.
    local s = newSide(p, H - TOP - FOOT - 4)
    s:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -2)
    s.cap = smallCaps(s, "OUTGOING")
    s.cap:SetPoint("TOPLEFT", 14, -12)
    s.title = label(s, "GameFontNormalLarge")
    s.title:SetTextColor(C.goldText[1], C.goldText[2], C.goldText[3])
    s.title:SetPoint("TOPLEFT", 14, -28)
    s.title:SetWidth(SIDE_W - 28)
    s.title:SetWordWrap(false)
    s.ships = {}
    for i = 1, 7 do
        local l = label(s, "GameFontHighlightSmall")
        l:SetPoint("TOPLEFT", 14, -54 - (i - 1) * 15)
        l:SetWidth(SIDE_W - 28)
        l:SetWordWrap(false)
        s.ships[i] = l
    end
    s.goldOpt = checkbox(s, "Include spare gold", 200, function(on)
        ns.db.opts.mailGold = on and true or false
        U.Refresh()
    end)
    s.goldOpt:SetPoint("TOPLEFT", 12, -166)
    withTip(s.goldOpt, { "Include spare gold", "Off unless you tick it. Sends what's above \"Keep at least\" after all the postage, on the last mail to your banker." })
    s.reserveCap = smallCaps(s, "Keep at least this much gold (postage counts)")
    s.reserveCap:SetPoint("TOPLEFT", 14, -192)
    s.reserve = newEdit(s, 70, 22, function(text)
        local c2 = parseGold(text)
        if c2 and c2 >= 0 then
            ns.db.opts.mailReserve = c2
            U.Refresh()
        end
    end)
    s.reserve:SetPoint("TOPLEFT", 14, -206)
    s.reserveG = label(s, "GameFontHighlightSmall", "g")
    s.reserveG:SetPoint("LEFT", s.reserve, "RIGHT", 4, 0)
    lineTex(s, -236)
    s.lines = {}
    for i = 1, 4 do
        s.lines[i] = summaryLine(s, -244 - (i - 1) * 16)
    end
    s.send = button(s, "Send", SIDE_W - 28, 28, function() U.SendClick() end)
    s.send:SetPoint("TOPLEFT", 14, -314)
    s.send:SetPrimary(true)
    s.stop = button(s, "Stop", 80, 22, function() MB.Stop() end)
    s.stop:SetPoint("TOPLEFT", 14, -348)
    s.clear = withTip(button(s, "New preview", 100, 22, function()
        MB.ClearShipments()
        U.Refresh()
    end), { "New preview", "Forget these mails and read your bags again." })
    s.clear:SetPoint("TOPRIGHT", -14, -348)
    s.status = label(s, "GameFontHighlightSmall")
    s.status:SetPoint("TOPLEFT", 14, -378)
    s.status:SetWidth(SIDE_W - 28)
    s.status:SetWordWrap(true)
    s.limit = label(s, "GameFontDisableSmall",
        "Each mail needs its own click: the game only sends mail from a real button press.")
    s.limit:SetPoint("BOTTOMLEFT", 14, 10)
    s.limit:SetWidth(SIDE_W - 28)
    s.limit:SetWordWrap(true)
    p.side = s
    return p
end

-- The plan on screen: the queue's mails while there are any, otherwise a
-- fresh preview from your bags.
local function currentPlan()
    local ships = MB.Shipments()
    if ships and MB.Q.plan then
        return MB.Q.plan, true
    end
    local plan
    if U.mode == "banker" then
        plan = MB.PlanBanker()
    elseif U.mode == "rules" then
        plan = MB.PlanRules()
    else
        local form = U.form
        plan = MB.PlanCustom({ to = form.to, subject = form.subject, body = form.body, cod = form.cod,
            money = parseGold(form.moneyText or "") or 0, picks = form.picks })
    end
    return plan, false
end
U.CurrentPlan = currentPlan

local SHIP_STATUS = { planned = GREY .. "waiting|r", preparing = "|cffe6d39aattaching|r", ready = GREEN .. "ready|r",
    sending = GOLD .. "with the server|r", sent = GREEN .. "sent|r", failed = RED .. "failed|r",
    cancelled = RED .. "cancelled|r", unclear = RED .. "check it|r", skipped = GREY .. "skipped|r" }

local function rowsForPlan(plan, inQueue)
    local rows = {}
    if U.mode == "custom" and not inQueue then
        local _, stacks = MB.ScanBags()
        table.sort(stacks, function(a, b)
            local na, nb = ns.ItemName(a.id), ns.ItemName(b.id)
            if na ~= nb then return na < nb end
            return a.count > b.count
        end)
        for _, st in ipairs(stacks) do
            local key = st.bag .. ":" .. st.slot
            local picked = U.form.picks[key] and true or false
            local tick = nil -- no box at all for stacks that can't be mailed
            if not st.why then
                tick = picked
            end
            rows[#rows + 1] = { key = key, stackKey = key, id = st.id, check = tick,
                title = ns.ItemText(st.id), sub = st.why and (GREY .. (SKIP_TEXT[st.why] or st.why) .. "|r")
                    or ("Bag " .. st.bag .. ", slot " .. st.slot),
                r1 = "x" .. st.count, r2 = picked and (GREEN .. "attached|r") or "", dim = st.why ~= nil }
        end
        return rows
    end
    for _, l in ipairs(plan.lines) do
        local sub = "To " .. (l.toName or "?")
        if l.rule then
            sub = sub .. "  -  rule: " .. MB.RuleName(l.rule) .. (l.keep > 0 and (", keep " .. l.keep) or "")
        elseif l.reason == "ticked" then
            sub = sub .. "  -  you ticked it to sell"
        elseif l.reason == "advice" then
            sub = sub .. "  -  worth auctioning"
        elseif l.reason and l.reason:sub(1, 4) == "cat:" then
            local cat = MB.CAT[l.reason:sub(5)]
            sub = sub .. "  -  " .. (cat and cat.name or "category") .. " (quick-send)"
        end
        local note = "of " .. l.total .. " in bags"
        if l.sendable and l.qty < l.sendable then
            note = note .. ", whole stacks"
        end
        local tick = nil -- no box once the mails are queued
        if not inQueue then
            tick = not l.excluded
        end
        rows[#rows + 1] = { key = "l" .. l.id, id = l.id, check = tick,
            title = ns.ItemText(l.id), sub = sub, r1 = l.excluded and (GREY .. "left out|r") or tostring(l.qty), r2 = note,
            dim = l.excluded, tip = { "Click to leave it out of this send.", "Right-click: always keep it (never mail it)." } }
    end
    if not inQueue then
        for _, sk in ipairs(plan.skipped) do
            local why = SKIP_TEXT[sk.why] or sk.why
            if sk.why == "rule" and sk.toName then
                why = "a rule sends it to " .. sk.toName
            elseif sk.why == "craft" and sk.recipe and sk.recipe.rec then
                why = "your " .. (sk.recipe.rec.name or "recipe") .. " recipe uses it"
            end
            rows[#rows + 1] = { key = "s" .. sk.id, id = sk.id, title = ns.ItemText(sk.id), sub = GREY .. "Stays: " .. why .. "|r",
                r1 = GREY .. "stays|r", r2 = "", dim = true }
        end
        for id, on in pairs(ns.db.opts.mailKeep or {}) do
            if on and MB.BagCount(id) > 0 then
                rows[#rows + 1] = { key = "k" .. id, id = id, title = ns.ItemText(id), sub = GREY .. "On your always-keep list|r",
                    r1 = GREY .. "kept|r", r2 = "right-click to allow", dim = true }
            end
        end
    end
    return rows
end

local function sendButtonState(plan, inQueue)
    local Q = MB.Q
    local busy = MB.Busy()
    local ships, i = MB.Shipments()
    local s = ships and ships[i]
    if busy == "collect" then
        return "Busy collecting mail", true
    end
    if busy == "send" and s then
        if s.status == "ready" then
            return "Send mail " .. i .. " of " .. #ships .. " to " .. (s.name or "?"), false
        elseif s.status == "sending" then
            return "Waiting for the server...", true
        end
        return "Getting mail " .. i .. " ready...", true
    end
    if inQueue then
        if MB.CanResume() then
            return "Continue with the next mail", false, "resume"
        end
        return "Done", true
    end
    if plan.problem then
        return "Can't send yet", true
    end
    if #plan.ships == 0 then
        return "Nothing to send", true
    end
    local label = (U.mode == "banker" and "Send to banker") or (U.mode == "rules" and "Send matching mail") or "Send message"
    return label .. " (" .. plural(#plan.ships, "mail") .. ")", not MB.open, "start"
end

function U.SendClick()
    local plan, inQueue = currentPlan()
    local _, _, what = sendButtonState(plan, inQueue)
    local busy = MB.Busy()
    if busy == "send" then
        local ok, why = MB.SendNext()
        if not ok and why then
            MB.SetStatus("error", why)
        end
    elseif what == "resume" then
        MB.Resume()
    elseif what == "start" then
        local ok, why = MB.StartSend(plan)
        if not ok and why then
            MB.SetStatus("error", why)
        end
    end
    U.Refresh()
end

local function refreshSend()
    local p = win.send
    local s = p.side
    for k, b in pairs(p.modes) do
        b:SetOn(k == U.mode)
    end
    local busy = MB.Busy()
    for _, b in pairs(p.modes) do
        b:SetDisabled(busy and true or false)
    end
    p.modes[U.mode]:SetDisabled(false)
    local info = MODES[U.mode]
    p.title:SetText(info.title)
    p.sub:SetText(info.sub)
    local custom = U.mode == "custom"
    p.custom:SetShown(custom)
    p.list:ClearAllPoints()
    -- The custom fields push the list down, so it gets shorter to stay inside the window.
    local listTop = custom and 190 or 72
    p.list:SetPoint("TOPLEFT", PAD, -listTop)
    p.list:SetListHeight(H - TOP - FOOT - listTop - (custom and 22 or 40))
    local plan, inQueue = currentPlan()
    local rows = rowsForPlan(plan, inQueue)
    if custom then
        local c = p.custom
        c.sendMoney:SetOn(not U.form.cod)
        c.cod:SetOn(U.form.cod)
        local codOK = not (C_Mail and C_Mail.IsCODEnabled) or ns.try(C_Mail.IsCODEnabled)
        c.cod:SetDisabled(not codOK)
        p.list:SetEmpty("Nothing in your bags can be mailed.")
    else
        p.list:SetEmpty(plan.problem or "Nothing matches this send method right now.")
    end
    p.list:SetData(rows, true)
    p.help:SetText(custom and "Mail sends whole stacks. Soulbound, quest and locked items can't be attached."
        or (U.mode == "banker" and "Click a row to leave it out. Right-click to always keep it. Your keep amounts and rule-assigned materials stay in your bags."
            or "Same-character deliveries are skipped. The first enabled matching rule owns each item; keep amounts are totals across all your bags."))

    -- Outgoing panel.
    local ships = plan.ships or {}
    local names, order = {}, {}
    for _, sh in ipairs(ships) do
        if not names[sh.name or "?"] then
            names[sh.name or "?"] = true
            order[#order + 1] = sh.name or "?"
        end
    end
    if #order == 1 then
        s.title:SetText(order[1])
    elseif #order > 1 then
        s.title:SetText(plural(#order, "recipient"))
    else
        s.title:SetText(GREY .. (plan.problem and "Not ready" or "Nothing to send") .. "|r")
    end
    local _, qi = MB.Shipments()
    for i, l in ipairs(s.ships) do
        local sh = ships[i]
        if i == #s.ships and #ships > #s.ships then
            l:SetText(GREY .. "+ " .. (#ships - #s.ships + 1) .. " more mails|r")
        elseif sh then
            local n = 0
            for _, it in ipairs(sh.items) do n = n + it.qty end
            local what = (#sh.atts > 0 and (plural(#sh.atts, "stack") .. " (" .. n .. ")") or "letter")
                .. ((sh.money or 0) > 0 and (" + " .. plain(sh.money)) or "") .. ((sh.cod or 0) > 0 and (" C.O.D. " .. plain(sh.cod)) or "")
            local mark = (inQueue and qi == i) and (GOLD .. "> |r") or ""
            l:SetText(mark .. i .. ". " .. (sh.name or "?") .. "  " .. GREY .. what .. ", " .. plain(sh.postage) .. "|r"
                .. (inQueue and ("  " .. (SHIP_STATUS[sh.status] or sh.status)) or ""))
        else
            l:SetText("")
        end
    end
    local banker = U.mode == "banker"
    s.goldOpt:SetShown(banker)
    s.goldOpt:SetChecked(ns.db.opts.mailGold)
    s.goldOpt.disabled = busy and true or false
    if not s.reserve.HasFocus or not s.reserve:HasFocus() then
        s.reserve:SetText(goldText(MB.Reserve()))
    end
    local totalItems = 0
    for _, sh in ipairs(ships) do
        for _, it in ipairs(sh.items) do totalItems = totalItems + it.qty end
    end
    local gold = 0
    for _, sh in ipairs(ships) do gold = gold + (sh.money or 0) end
    local postage = 0
    for _, sh in ipairs(ships) do postage = postage + (sh.postage or 0) end
    local have = ns.try(GetMoney) or 0
    s.lines[1]:Set("Items", tostring(totalItems))
    s.lines[2]:Set("Gold attached", gold > 0 and ns.Money(gold) or (GREY .. (banker and plan.goldNote and "None (see below)" or "None") .. "|r"))
    s.lines[3]:Set("Postage", ns.Money(postage))
    s.lines[4]:Set("Left after", ns.Money(max(0, have - gold - postage)))
    local text, disabled = sendButtonState(plan, inQueue)
    s.send:SetLabel(text)
    s.send:SetDisabled(disabled)
    s.stop:SetShown(busy == "send")
    s.clear:SetShown(inQueue and not busy)
    local st = statusText()
    local note = st
    if not note then
        note = plan.problem and (RED .. plan.problem .. "|r") or plan.warn and (RED .. plan.warn .. "|r")
            or (banker and ns.db.opts.mailGold and plan.goldNote) or nil
    end
    if inQueue then
        local sh = ships[qi]
        if sh and (sh.error or sh.result) and not st then
            note = (sh.status == "sent" and GREEN or RED) .. (sh.error or sh.result) .. "|r"
        end
    end
    s.status:SetText(note or (GREY .. "Nothing is sent until you press Send.|r"))
end

function U.SetMode(mode)
    if MB.Busy() then
        return
    end
    if MB.Shipments() then
        MB.ClearShipments()
    end
    U.mode = mode
    MB.exclude = {}
    hidePopup()
    U.Refresh()
end

function U.QuickSend()
    if MB.Busy() then
        return
    end
    U.SetMode("banker")
    U.SetTab("send")
end

----------------------------------------------------------------------
-- Auto-send rules
----------------------------------------------------------------------

local function scopeText(r)
    if r.scope == nil or r.scope == "account" then
        return "account-wide"
    end
    if r.scope == ns.charKey then
        return "this character only"
    end
    return "only " .. (MB.NameOf(r.scope) or "another character")
end

local function targetText(r)
    local _, name, problem = MB.RuleTarget(r)
    if r.to == "banker" then
        return "Banker" .. (name and (" (" .. name .. ")") or " (none picked)"), problem
    end
    return name or MB.NameOf(r.to) or "Pick a recipient", problem
end

local function buildRules(f)
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", 0, -TOP)
    p:SetSize(W, H - TOP - FOOT)
    p.title = heading(p, "A home for every material")
    p.title:SetPoint("TOPLEFT", PAD + 2, -2)
    p.sub = label(p, "GameFontDisableSmall", "Top to bottom: the first enabled rule that matches owns the item.")
    p.sub:SetPoint("TOPLEFT", PAD + 2, -24)
    p.sub:SetWidth(LIST_W - 220)
    p.sub:SetWordWrap(false)
    p.ask = checkbox(p, "Ask when a mailbox opens", 200, function(on)
        ns.db.opts.mailPrompt = on and true or false
        U.Refresh()
    end)
    p.ask:SetHeight(18)
    p.ask:SetPoint("TOPRIGHT", p, "TOPLEFT", PAD + LIST_W, -1)
    withTip(p.ask, { "Ask when a mailbox opens", "On by default. When a mailbox opens and items in your bags match your rules, a box shows what would go where, with Send now, Review first or Not now. Nothing is sent without your click." })
    p.auto = checkbox(p, "Auto-send on mailbox open", 200, function(on)
        ns.db.opts.mailAuto = on and true or false
        U.Refresh()
    end)
    p.auto:SetHeight(18)
    p.auto:SetPoint("TOPRIGHT", p, "TOPLEFT", PAD + LIST_W, -20)
    withTip(p.auto, { "Auto-send on mailbox open", "Off unless you tick it. When a mailbox opens, your rules' mail is put together and the first one made ready. You still press Send once per mail: the game needs a real click for each." })
    local listH = H - TOP - FOOT - 40 - 92
    p.list = newRows(p, LIST_W, listH, 44, { check = true, prio = true, buttons = true })
    p.list:SetPoint("TOPLEFT", PAD, -40)
    p.list.onCheck = function(d)
        if d.rule then
            MB.SetRuleOn(d.rule.id, not d.rule.on)
            if U.draft and U.draft.id == d.rule.id then
                U.draft.on = not d.rule.on and false or d.rule.on
            end
            U.Refresh()
        end
    end
    p.list.onClick = function(d)
        if d.rule then
            U.EditRule(d.rule.id)
        end
    end
    p.add = button(p, "Add rule", 90, 24, function() U.NewRule() end)
    p.add:SetPoint("TOPLEFT", p.list, "BOTTOMLEFT", 0, -8)
    p.presets = withTip(button(p, "Add suggested rules", 140, 24, function()
        local n = MB.AddPresets()
        MB.SetStatus("idle", n > 0 and (plural(n, "suggested rule") .. " added, switched off. Check each one, then tick it to use it.")
            or "The suggested rules are already in your list.")
        U.Refresh()
    end), { "Suggested rules", "Cloth and bolts to Xeon Hexspark (keep 20), herbs to Xeon Raincaller (keep 5), ore and bars to Xeon Mana (keep 20), leather and hides to Xeon Ironfang (keep 10), auction stock to your banker.", "They're added switched off for you to review." })
    p.presets:SetPoint("LEFT", p.add, "RIGHT", 6, 0)
    p.first = label(p, "GameFontDisableSmall", "First matching rule wins.")
    p.first:SetPoint("LEFT", p.presets, "RIGHT", 12, 0)
    p.preview = withTip(button(p, "Preview matching mail", 170, 24, function()
        if MB.Busy() then return end
        U.SetMode("rules")
        U.SetTab("send")
    end), { "Preview matching mail", "Shows every mail your rules would send, with quantities and postage. Nothing is sent from the preview." })
    p.preview:SetPoint("TOPRIGHT", p.list, "BOTTOMRIGHT", 0, -8)
    p.preview:SetPrimary(true)
    p.note = label(p, "GameFontDisableSmall")
    p.note:SetPoint("TOPLEFT", p.add, "BOTTOMLEFT", 2, -10)
    p.note:SetWidth(LIST_W)
    p.note:SetWordWrap(true)

    -- The editor.
    local s = newSide(p, H - TOP - FOOT - 4)
    s:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -2)
    s.iconEdge = s:CreateTexture(nil, "BORDER")
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetSize(34, 34)
    s.icon:SetPoint("TOPLEFT", 14, -12)
    s.iconEdge:SetPoint("TOPLEFT", s.icon, "TOPLEFT", -1, 1)
    s.iconEdge:SetPoint("BOTTOMRIGHT", s.icon, "BOTTOMRIGHT", 1, -1)
    s.title = label(s, "GameFontNormalLarge")
    s.title:SetTextColor(C.goldText[1], C.goldText[2], C.goldText[3])
    s.title:SetPoint("TOPLEFT", 58, -12)
    s.title:SetWidth(SIDE_W - 70)
    s.title:SetWordWrap(false)
    s.number = label(s, "GameFontDisableSmall")
    s.number:SetPoint("TOPLEFT", 58, -32)
    s.matchCap = smallCaps(s, "Match items")
    s.matchCap:SetPoint("TOPLEFT", 14, -58)
    s.match = picker(s, SIDE_W - 28, function() return U.MatchOptions() end, function(v)
        if not U.draft then return end
        if type(v) == "number" then
            U.draft.item, U.draft.cat = v, nil
        else
            U.draft.cat, U.draft.item = v, nil
        end
        U.Refresh()
    end)
    s.match:SetPoint("TOPLEFT", 14, -72)
    s.toCap = smallCaps(s, "Send to")
    s.toCap:SetPoint("TOPLEFT", 14, -100)
    s.to = picker(s, SIDE_W - 28, function() return U.TargetOptions() end, function(v)
        if U.draft then
            U.draft.to = v
            U.Refresh()
        end
    end)
    s.to:SetPoint("TOPLEFT", 14, -114)
    s.keepCap = smallCaps(s, "Keep in bags, of each matching item (all stacks)")
    s.keepCap:SetPoint("TOPLEFT", 14, -142)
    s.keep = newEdit(s, 60, 22, function(text)
        if U.draft then
            U.draft.keep = tonumber(text) or U.draft.keep
            U.draft.keepText = text
            U.Refresh()
        end
    end)
    s.keep:SetPoint("TOPLEFT", 14, -156)
    if s.keep.SetNumeric then
        s.keep:SetNumeric(true)
    end
    s.scopeAll = button(s, "Account-wide", 100, 22, function()
        if U.draft then U.draft.scope = "account"; U.Refresh() end
    end)
    -- Keep box + both buttons fit inside the panel's 14px margins (14 + 60 + 8 + 100 + 4 + 100 = 286).
    s.scopeAll:SetPoint("TOPLEFT", 82, -156)
    s.scopeMe = button(s, "This character", 100, 22, function()
        if U.draft then U.draft.scope = ns.charKey; U.Refresh() end
    end)
    s.scopeMe:SetPoint("LEFT", s.scopeAll, "RIGHT", 4, 0)
    s.on = checkbox(s, "Rule switched on", 200, function(on)
        if U.draft then U.draft.on = on; U.Refresh() end
    end)
    s.on:SetPoint("TOPLEFT", 12, -184)
    lineTex(s, -212)
    s.prevCap = smallCaps(s, "WITH YOUR CURRENT BAGS")
    s.prevCap:SetPoint("TOPLEFT", 14, -220)
    s.prev = {}
    for i = 1, 7 do
        s.prev[i] = summaryLine(s, -238 - (i - 1) * 15)
    end
    s.save = button(s, "Save rule", 130, 26, function() U.SaveDraft() end)
    s.save:SetPoint("TOPLEFT", 14, -352)
    s.save:SetPrimary(true)
    s.delete = button(s, "Delete", 70, 26, function() U.DeleteDraft() end)
    s.delete:SetPoint("LEFT", s.save, "RIGHT", 6, 0)
    s.cancel = button(s, "Undo", 60, 26, function()
        if U.draft then U.EditRule(U.draft.id) end
    end)
    s.cancel:SetPoint("LEFT", s.delete, "RIGHT", 6, 0)
    s.status = label(s, "GameFontHighlightSmall")
    s.status:SetPoint("TOPLEFT", 14, -386)
    s.status:SetWidth(SIDE_W - 28)
    s.status:SetWordWrap(true)
    s.empty = label(s, "GameFontDisable", "Pick a rule to edit it, or add one.")
    s.empty:SetPoint("TOP", 0, -80)
    s.empty:SetWidth(SIDE_W - 40)
    s.empty:SetJustifyH("CENTER")
    p.side = s
    return p
end

function U.MatchOptions()
    local out = { { text = "Material groups", header = true } }
    for _, c in ipairs(MB.CATS) do
        out[#out + 1] = { text = c.name, value = c.key, icon = catIcon(c.key) or K.COIN }
    end
    out[#out + 1] = { text = "Items in your bags", header = true }
    local items = MB.ScanBags()
    local ids = {}
    for id, e in pairs(items) do
        if e.mailable > 0 then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids, function(a, b) return ns.ItemName(a) < ns.ItemName(b) end)
    for _, id in ipairs(ids) do
        out[#out + 1] = { text = ns.ItemText(id), value = id, icon = ns.Icon(id) }
    end
    return out
end

function U.TargetOptions()
    local name = MB.NameOf(MB.BankerKey())
    local out = { { text = "Banker" .. GREY .. "  (" .. (name or "none picked") .. ", follows your banker)|r", value = "banker", icon = K.COIN } }
    for _, c in ipairs(MB.Characters(true)) do
        local coords = c.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.class]
        out[#out + 1] = { text = c.name .. (c.self and (GREY .. "  (you: items stay here)|r") or ""), value = c.key, coords = coords }
    end
    return out
end

function U.EditRule(id)
    local r = MB.FindRule(id)
    if not r then
        U.draft = nil
        U.Refresh()
        return
    end
    U.draft = { id = r.id, on = r.on, cat = r.cat, item = r.item, to = r.to, keep = r.keep, scope = r.scope or "account" }
    U.draftStatus = "Changes apply when you save this rule."
    win.rules.side.keep:SetText(tostring(r.keep or 0))
    hidePopup()
    U.Refresh()
end

function U.NewRule()
    local r = MB.AddRule({ cat = "cloth", to = "banker", keep = 0, on = false }, false)
    U.EditRule(r.id)
    U.draftStatus = "New rule, switched off. Pick what it matches and who gets it, then save."
    U.Refresh()
end

function U.SaveDraft()
    local d = U.draft
    if not d then
        return
    end
    if d.keepText and tonumber(d.keepText) == nil then
        U.draftStatus = RED .. "Keep must be a number.|r"
        U.Refresh()
        return
    end
    local ok, why = MB.SaveRule(d.id, { cat = d.cat, item = d.item, to = d.to, keep = d.keep, scope = d.scope, on = d.on })
    U.draftStatus = ok and (GREEN .. "Saved.|r") or (RED .. (why or "Couldn't save.") .. "|r")
    U.Refresh()
end

function U.DeleteDraft()
    local d = U.draft
    if not d then
        return
    end
    if U.confirmDelete ~= d.id then
        U.confirmDelete = d.id
        U.draftStatus = GOLD .. "Press Delete again to remove this rule.|r"
        U.Refresh()
        return
    end
    U.confirmDelete = nil
    MB.DeleteRule(d.id)
    U.draft = nil
    U.Refresh()
end

-- The rules with the draft swapped in, for the live preview.
local function rulesWithDraft()
    local list = {}
    for _, r in ipairs(MB.Rules()) do
        if U.draft and r.id == U.draft.id then
            local copy = {}
            for k, v in pairs(r) do copy[k] = v end
            for k, v in pairs(U.draft) do copy[k] = v end
            list[#list + 1] = copy
        else
            list[#list + 1] = r
        end
    end
    return list
end

local function refreshRules()
    local p = win.rules
    local s = p.side
    p.auto:SetChecked(ns.db.opts.mailAuto)
    p.ask:SetChecked(ns.db.opts.mailPrompt ~= false)
    local items = MB.ScanBags()
    local alloc = MB.Allocate(items, MB.ActiveRules(rulesWithDraft()))
    local byRule = {}
    for _, a in pairs(alloc) do
        if a.rule then
            local e = byRule[a.rule.id] or { qty = 0, n = 0 }
            e.qty = e.qty + (a.qty or 0)
            e.n = e.n + 1
            byRule[a.rule.id] = e
        end
    end
    local rows = {}
    local list = MB.Rules()
    for i, r in ipairs(list) do
        local icon, id = ruleIcon(r)
        local to, problem = targetText(r)
        local e = byRule[r.id]
        local r1
        if not r.on then
            r1 = GREY .. "Paused|r"
        elseif not MB.RuleApplies(r) then
            r1 = GREY .. "Not this character|r"
        elseif problem == "self" then
            r1 = GREY .. "Stays here|r"
        elseif problem == "nobanker" then
            r1 = RED .. "No banker|r"
        elseif problem then
            r1 = RED .. "Can't mail|r"
        else
            r1 = (e and e.qty > 0) and (GREEN .. e.qty .. " ready|r") or (GREY .. "0 ready|r")
        end
        rows[#rows + 1] = { key = "r" .. r.id, rule = r, check = r.on and true or false, prio = i, icon = icon, id = id,
            title = MB.RuleName(r) .. (r.preset and (GREY .. "  suggested|r") or ""),
            sub = "To " .. to .. "  -  " .. scopeText(r), r1 = r1, r2 = "Keep " .. (r.keep or 0) .. " each",
            dim = not r.on,
            b1 = { text = "^", disabled = i == 1, fn = function() MB.MoveRule(r.id, -1); U.Refresh() end },
            b2 = { text = "v", disabled = i == #list, fn = function() MB.MoveRule(r.id, 1); U.Refresh() end },
            tip = { MB.RuleName(r), "Click to edit. Tick to switch it on or off. ^ and v change its priority." } }
    end
    for id, on in pairs(ns.db.opts.mailKeep or {}) do
        if on then
            rows[#rows + 1] = { key = "k" .. id, id = id, title = ns.ItemText(id), sub = GREY .. "Always kept: never mailed by rules or quick-send|r",
                r1 = "", r2 = "", b2 = { text = "x", fn = function() MB.SetKept(id, false); U.Refresh() end } }
        end
    end
    p.list.selected = U.draft and ("r" .. U.draft.id) or nil
    p.list:SetEmpty("No rules yet. Add one, or add the suggested rules and review them.")
    p.list:SetData(rows, true)
    local banker = MB.NameOf(MB.BankerKey())
    p.note:SetText((ns.db.opts.mailAuto and "When a mailbox opens, the mail your rules make is put together and the first one made ready. You press Send once per mail."
        or "Keep amounts stay in your bags. Items addressed to this character stay here too.")
        .. (banker and "" or " Rules sent to \"Banker\" wait until you pick one."))

    local d = U.draft
    local shownEditor = d ~= nil
    for _, x in ipairs({ s.icon, s.iconEdge, s.title, s.number, s.matchCap, s.match, s.toCap, s.to, s.keepCap, s.keep,
        s.scopeAll, s.scopeMe, s.on, s.prevCap, s.save, s.delete, s.cancel, s.status }) do
        x:SetShown(shownEditor)
    end
    for _, l in ipairs(s.prev) do
        l.l:SetShown(shownEditor)
        l.r:SetShown(shownEditor)
    end
    s.empty:SetShown(not shownEditor)
    if not d then
        return
    end
    local _, index = MB.FindRule(d.id)
    local icon, id = ruleIcon(d)
    setIcon(s.icon, icon)
    edgeFor(s.iconEdge, id)
    s.title:SetText(MB.RuleName(d))
    s.number:SetText("Rule " .. (index or "?") .. "  -  " .. (d.on and "switched on" or "switched off"))
    s.match:SetLabel(MB.RuleName(d))
    s.to:SetLabel((targetText(d)))
    s.scopeAll:SetOn(d.scope == "account")
    s.scopeMe:SetOn(d.scope ~= "account")
    s.on:SetChecked(d.on)
    -- Preview: what this rule takes, given the rules above it.
    local lines = {}
    local draftRule
    for _, r in ipairs(rulesWithDraft()) do
        if r.id == d.id then draftRule = r end
    end
    local previewRules = MB.ActiveRules(rulesWithDraft())
    if not d.on and draftRule then
        -- Show what it would do if switched on.
        local copy = {}
        for k, v in pairs(draftRule) do copy[k] = v end
        copy.on = true
        previewRules = {}
        for _, r in ipairs(rulesWithDraft()) do
            if r.id == d.id then
                previewRules[#previewRules + 1] = copy
            elseif MB.RuleApplies(r) then
                previewRules[#previewRules + 1] = r
            end
        end
    end
    local _, _, problem = MB.RuleTarget(d)
    local pAlloc = MB.Allocate(items, previewRules)
    for iid, a in pairs(pAlloc) do
        if a.rule and a.rule.id == d.id then
            lines[#lines + 1] = a
        elseif not a.rule and not a.kept and draftRule and MB.RuleMatches(draftRule, iid) then
            -- matched, but out of scope
        end
    end
    -- Items it matches that a higher rule already owns.
    local owned = {}
    for iid, a in pairs(pAlloc) do
        if a.rule and a.rule.id ~= d.id and draftRule and MB.RuleMatches(draftRule, iid) then
            owned[#owned + 1] = a
        end
    end
    table.sort(lines, function(a, b) return ns.ItemName(a.id) < ns.ItemName(b.id) end)
    local i = 0
    for _, a in ipairs(lines) do
        i = i + 1
        if i <= #s.prev then
            local right
            if problem == "self" then
                right = GREY .. "stays (you)|r"
            elseif problem then
                right = RED .. "can't send|r"
            elseif a.qty > 0 then
                right = GREEN .. a.qty .. " to send|r" .. GREY .. ", keep " .. (a.total - a.qty) .. "|r"
            else
                right = GREY .. "keep all " .. a.total .. "|r"
            end
            s.prev[i]:Set(ns.ItemName(a.id), right)
        end
    end
    for _, a in ipairs(owned) do
        i = i + 1
        if i <= #s.prev then
            s.prev[i]:Set(GREY .. ns.ItemName(a.id) .. "|r", GREY .. "rule " .. (a.ruleIndex or "?") .. " owns it|r")
        end
    end
    if i == 0 then
        s.prev[1]:Set(GREY .. "Nothing in your bags matches.|r", "")
        i = 1
    end
    for j = i + 1, #s.prev do
        s.prev[j]:Set("", "")
    end
    if not s.keep.HasFocus or not s.keep:HasFocus() then
        if not d.keepText then
            s.keep:SetText(tostring(d.keep or 0))
        end
    end
    local warn = (problem == "self" and "This character is the recipient, so these stay in your bags.")
        or (problem == "nobanker" and "No banker picked yet: pick one in the strip above.")
        or (problem == "unset" and "Pick who gets these.")
        or (problem == "elsewhere" and "That character can't be mailed from here (another realm or faction).") or nil
    s.status:SetText((warn and (GOLD .. warn .. "|r\n") or "") .. (U.draftStatus or ""))
    if U.confirmDelete ~= d.id then
        s.delete:SetLabel("Delete")
    else
        s.delete:SetLabel("Sure?")
    end
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------

local tabs = {}

function U.SetTab(key)
    U.tab = key
    hidePopup()
    if not win then
        return
    end
    for k, b in pairs(tabs) do
        b:SetOn(k == key)
    end
    win.inbox:SetShown(key == "inbox")
    win.send:SetShown(key == "send")
    win.rules:SetShown(key == "rules")
    U.Refresh()
end

local function createWindow()
    local f = CreateFrame("Frame", "ForeverGoldMailFrame", UIParent)
    f:SetSize(W, H)
    local pos = ns.db.opts.mailPos
    if type(pos) == "table" and pos.x and pos.y then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 24, -104)
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
            ns.db.opts.mailPos = { x = floor(left + 0.5), y = floor(top + 0.5) }
        end
    end)
    f:SetScript("OnHide", function()
        hidePopup()
    end)
    skin(f)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(30, 30)
    icon:SetPoint("TOPLEFT", 10, -6)
    icon:SetTexture(K.LOGO)
    local title = label(f, K.SERIF_L, "Mailbox")
    title:SetTextColor(C.goldText[1], C.goldText[2], C.goldText[3])
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)

    local close = button(f, "X", 24, 22, function() U.Close() end)
    close:SetPoint("TOPRIGHT", -8, -8)
    f.blizz = withTip(button(f, "Game's mailbox", 110, 22, function() U.UseBlizzard() end),
        { "Game's mailbox", "Switch to the game's own mailbox window (needed to pay C.O.D.). A button on it switches back." })
    f.blizz:SetPoint("RIGHT", close, "LEFT", -6, 0)
    f.advice = withTip(button(f, "Advice", 64, 22, function() ns.ToggleUI() end), { "Advice", "Open the main Forever Gold window." })
    f.advice:SetPoint("RIGHT", f.blizz, "LEFT", -6, 0)
    f.who = label(f, "GameFontHighlight")
    f.who:SetPoint("RIGHT", f.advice, "LEFT", -16, 6)
    f.who:SetJustifyH("RIGHT")
    f.money = label(f, "GameFontHighlightSmall")
    f.money:SetPoint("RIGHT", f.advice, "LEFT", -16, -9)
    f.money:SetJustifyH("RIGHT")

    local x = PAD
    for _, t in ipairs({ { "inbox", "Inbox" }, { "send", "Send mail" }, { "rules", "Auto-send rules" } }) do
        local key = t[1]
        local b = button(f, t[2], 136, 24, function() U.SetTab(key) end)
        b:SetPoint("TOPLEFT", x, -44)
        tabs[key] = b
        x = x + 140
    end
    f.tabs = tabs
    local rule = tex(f, "BORDER", C.edge[1], C.edge[2], C.edge[3], 0.7)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", PAD, -72)
    rule:SetPoint("TOPRIGHT", -PAD, -72)

    f.strip = buildBankerStrip(f)
    f.inbox = buildInbox(f)
    f.send = buildSend(f)
    f.rules = buildRules(f)

    f.footRule = tex(f, "BORDER", C.edge[1], C.edge[2], C.edge[3], 0.5)
    f.footRule:SetHeight(1)
    f.footRule:SetPoint("BOTTOMLEFT", PAD, FOOT)
    f.footRule:SetPoint("BOTTOMRIGHT", -PAD, FOOT)
    f.dot = tex(f, "ARTWORK", 0.56, 0.83, 0.48, 1)
    f.dot:SetSize(6, 6)
    f.dot:SetPoint("BOTTOMLEFT", PAD + 4, 12)
    f.status = label(f, "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", PAD + 16, 10)
    f.status:SetWidth(W - 2 * PAD - 230)
    f.status:SetWordWrap(false)
    f.foot = label(f, "GameFontDisableSmall")
    f.foot:SetPoint("BOTTOMRIGHT", -PAD - 2, 10)
    f.foot:SetJustifyH("RIGHT")
    f:Hide()
    return f
end

local DOT = { idle = { 0.56, 0.83, 0.48 }, working = { 0.9, 0.8, 0.45 }, waiting = { 0.9, 0.8, 0.45 },
    ready = { 0.56, 0.83, 0.48 }, confirm = { 1, 0.82, 0 }, done = { 0.56, 0.83, 0.48 }, error = { 1, 0.4, 0.4 },
    unclear = { 1, 0.4, 0.4 } }

function U.Refresh()
    if not win or not win:IsShown() then
        return
    end
    local c = ns.Char()
    local coloured = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
    local className = c.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c.class]
    win.who:SetText((c.name or "?") .. (className and (GREY .. "  " .. className .. "|r") or ""))
    if coloured and coloured.r then
        win.who:SetTextColor(coloured.r, coloured.g, coloured.b)
    end
    win.money:SetText(ns.Money(ns.try(GetMoney) or 0) .. GREY .. " in bags|r")
    local n = #MB.inbox
    tabs.inbox:SetLabel("Inbox" .. (n > 0 and ("  " .. n) or ""))
    local rn = #MB.Rules()
    tabs.rules:SetLabel("Auto-send rules" .. (rn > 0 and ("  " .. rn) or ""))
    local busy, op = MB.Busy()
    win.blizz:SetDisabled(op ~= nil)
    refreshBankerStrip()
    if U.tab == "inbox" then
        refreshInbox()
    elseif U.tab == "send" then
        refreshSend()
    else
        refreshRules()
    end
    local text, kind = statusText()
    win.status:SetText(text or ("Mailbox " .. (MB.open and "open" or "closed") .. "  -  auto-send "
        .. (ns.db.opts.mailAuto and "on" or "off")))
    local dc = DOT[kind] or DOT.idle
    win.dot:SetColorTexture(dc[1], dc[2], dc[3], 1)
    win.foot:SetText(busy and "One mail action at a time" or "")
end

----------------------------------------------------------------------
-- Taking over from the game's mailbox
----------------------------------------------------------------------

local hidden = {}

local function hideBlizzard()
    for _, name in ipairs({ "MailFrame", "OpenMailFrame" }) do
        local f = _G[name]
        if f then
            if not hidden[name] then
                hidden[name] = f:GetScale() or 1
            end
            f:SetScale(0.001)
            f:SetAlpha(0)
            f:EnableMouse(false)
        end
    end
end

local function restoreBlizzard()
    for name, scale in pairs(hidden) do
        local f = _G[name]
        if f then
            f:SetScale(scale)
            f:SetAlpha(1)
            f:EnableMouse(true)
        end
    end
    hidden = {}
end

function U.UsingOurs()
    return not ns.db.opts.mailBlizzard
end

function U.IsShown()
    return win ~= nil and win:IsShown()
end

local strip
local function showStrip()
    local parent = MailFrame or UIParent
    if not strip then
        strip = CreateFrame("Frame", "ForeverGoldMailStrip", parent)
        strip:SetSize(300, 30)
        if MailFrame then
            strip:SetPoint("BOTTOMLEFT", MailFrame, "TOPLEFT", 0, 3)
        else
            strip:SetPoint("TOP", UIParent, "TOP", 0, -70)
        end
        strip:SetFrameStrata("HIGH")
        skin(strip)
        local icon = strip:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", 6, 0)
        icon:SetTexture(K.LOGO)
        strip.ours = button(strip, "Forever Gold mailbox", 150, 22, function() U.UseOurs() end)
        strip.ours:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        strip.ours:SetPrimary(true)
        strip.advice = button(strip, "Advice", 70, 22, function() ns.ToggleUI() end)
        strip.advice:SetPoint("LEFT", strip.ours, "RIGHT", 6, 0)
    end
    strip:Show()
end

local function hideStrip()
    if strip then
        strip:Hide()
    end
end

local hooked = false
local function hookBlizzard()
    if hooked or not MailFrame then
        return
    end
    hooked = true
    MailFrame:HookScript("OnShow", function()
        if U.UsingOurs() and MB.open then
            hideBlizzard()
        end
    end)
    if OpenMailFrame then
        OpenMailFrame:HookScript("OnShow", function()
            if U.UsingOurs() and MB.open then
                hideBlizzard()
            end
        end)
    end
end

function U.Open()
    if not MB.open then
        return
    end
    hookBlizzard()
    hideBlizzard()
    hideStrip()
    if not win then
        win = createWindow()
        U.win = win
    end
    win:Show()
    U.SetTab(U.tab or "inbox")
end

function U.Close()
    hidePopup()
    if MailFrame and HideUIPanel then
        pcall(HideUIPanel, MailFrame)
    end
    if MB.open and type(CloseMail) == "function" then
        pcall(CloseMail)
    end
    if win then
        win:Hide()
    end
end

function U.UseBlizzard()
    local ok, why = MB.HandOver()
    if not ok then
        MB.SetStatus("waiting", why)
        return false
    end
    ns.db.opts.mailBlizzard = true
    if win then
        win:Hide()
    end
    restoreBlizzard()
    showStrip()
    return true
end

function U.UseOurs()
    ns.db.opts.mailBlizzard = nil
    U.Open()
end

ns.Listen("MAIL_OPENED", function()
    U.sel = {}
    if U.UsingOurs() then
        U.Open()
        -- The game shows its own window a moment after the event; hide it again then.
        C_Timer.After(0, ns.Guard("mail-hide", function()
            if U.UsingOurs() and MB.open then
                hideBlizzard()
            end
        end))
    else
        C_Timer.After(0.2, ns.Guard("mail-strip", showStrip))
    end
end)

----------------------------------------------------------------------
-- "Your rules have mail to send" - offered when a mailbox opens
----------------------------------------------------------------------

local PROMPT_W, PROMPT_LINES = 440, 6

local function hidePrompt()
    if win and win.prompt then
        win.prompt:Hide()
    end
end
U.HidePrompt = hidePrompt

local function buildPrompt()
    -- A dimmed cover over the whole window so the box reads as a question.
    local cover = CreateFrame("Frame", nil, win)
    cover:SetAllPoints()
    cover:SetFrameLevel(win:GetFrameLevel() + 40)
    cover:EnableMouse(true)
    cover.shade = tex(cover, "BACKGROUND", 0, 0, 0, 0.55)
    cover.shade:SetAllPoints()
    local d = CreateFrame("Frame", nil, cover)
    d:SetSize(PROMPT_W, 120)
    d:SetPoint("CENTER", 0, 20)
    d:SetFrameLevel(cover:GetFrameLevel() + 2)
    skin(d)
    d.title = label(d, "GameFontNormalLarge", "Your rules have mail to send")
    d.title:SetTextColor(C.goldText[1], C.goldText[2], C.goldText[3])
    d.title:SetPoint("TOPLEFT", 16, -14)
    d.title:SetWidth(PROMPT_W - 32)
    d.title:SetWordWrap(false)
    d.lines = {}
    for i = 1, PROMPT_LINES do
        local l = label(d, "GameFontHighlightSmall")
        l:SetPoint("TOPLEFT", 16, -40 - (i - 1) * 16)
        l:SetWidth(PROMPT_W - 32)
        l:SetWordWrap(false)
        d.lines[i] = l
    end
    d.total = label(d, "GameFontDisableSmall")
    d.total:SetWidth(PROMPT_W - 32)
    d.total:SetWordWrap(false)
    d.send = button(d, "Send now", 130, 26, function() U.PromptSend() end)
    d.send:SetPrimary(true)
    d.review = withTip(button(d, "Review first", 120, 26, function() U.PromptReview() end),
        { "Review first", "Opens the Send mail tab with your rules' mail listed. Untick anything you want to keep, then press Send." })
    d.later = button(d, "Not now", 90, 26, function() hidePrompt() end)
    d.note = label(d, "GameFontDisableSmall", "Each mail still needs its own Send click. Switch this off on the Auto-send rules tab.")
    d.note:SetWidth(PROMPT_W - 32)
    d.note:SetWordWrap(true)
    cover.box = d
    cover:Hide()
    return cover
end

-- Fills the box from a plan: one line per recipient.
function U.ShowPrompt(plan)
    if not win or not win:IsShown() or not plan or #(plan.ships or {}) == 0 then
        return false
    end
    if not win.prompt then
        win.prompt = buildPrompt()
    end
    local d = win.prompt.box
    local by, order = {}, {}
    local postage = 0
    for _, sh in ipairs(plan.ships) do
        local name = sh.name or "?"
        local e = by[name]
        if not e then
            e = { stacks = 0, qty = {}, ids = {} }
            by[name] = e
            order[#order + 1] = name
        end
        e.stacks = e.stacks + #(sh.atts or {})
        for _, it in ipairs(sh.items or {}) do
            if not e.qty[it.id] then
                e.ids[#e.ids + 1] = it.id
            end
            e.qty[it.id] = (e.qty[it.id] or 0) + it.qty
        end
        postage = postage + (sh.postage or 0)
    end
    for i, l in ipairs(d.lines) do
        local name = order[i]
        if i == #d.lines and #order > #d.lines then
            l:SetText(GREY .. "+ " .. (#order - #d.lines + 1) .. " more characters|r")
        elseif name then
            local e = by[name]
            local parts = {}
            for k, id in ipairs(e.ids) do
                if k > 3 then
                    parts[#parts + 1] = "+" .. (#e.ids - 3) .. " more"
                    break
                end
                parts[#parts + 1] = (ns.ItemName(id) or ("item " .. id)) .. " x" .. e.qty[id]
            end
            l:SetText(GOLD .. name .. "|r  " .. GREY .. plural(e.stacks, "stack") .. ":|r " .. table.concat(parts, ", "))
        else
            l:SetText("")
        end
    end
    local shown = min(#order, #d.lines)
    local y = -40 - shown * 16 - 6
    d.total:ClearAllPoints()
    d.total:SetPoint("TOPLEFT", 16, y)
    d.total:SetText(plural(#plan.ships, "mail") .. "  -  postage " .. plain(postage))
    y = y - 24
    d.send:ClearAllPoints()
    d.send:SetPoint("TOPLEFT", 16, y)
    d.send:SetLabel("Send now (" .. plural(#plan.ships, "mail") .. ")")
    d.review:ClearAllPoints()
    d.review:SetPoint("LEFT", d.send, "RIGHT", 8, 0)
    d.later:ClearAllPoints()
    d.later:SetPoint("LEFT", d.review, "RIGHT", 8, 0)
    y = y - 36
    d.note:ClearAllPoints()
    d.note:SetPoint("TOPLEFT", 16, y)
    d:SetHeight(-y + 36)
    U.promptPlan = plan
    win.prompt:Show()
    return true
end

function U.PromptShown()
    return win ~= nil and win.prompt ~= nil and win.prompt:IsShown()
end

-- Starts the queue from a fresh read of your bags (they may have changed).
function U.PromptSend()
    hidePrompt()
    if MB.Busy() then
        return
    end
    if MB.Shipments() then
        MB.ClearShipments()
    end
    U.mode = "rules"
    MB.exclude = {}
    local ok, why = MB.StartSend(MB.PlanRules())
    if not ok and why then
        MB.SetStatus("error", why)
    end
    U.SetTab("send")
end

function U.PromptReview()
    hidePrompt()
    U.SetMode("rules")
    U.SetTab("send")
end

ns.Listen("MAIL_PROMPT", function(plan)
    if U.IsShown() and not MB.Busy() then
        U.ShowPrompt(plan)
    end
end)

ns.Listen("MAIL_CLOSED_UI", function()
    hidePopup()
    hidePrompt()
    if win then
        win:Hide()
    end
    restoreBlizzard()
    hideStrip()
end)

ns.Listen("MAIL_AUTO", function()
    if U.IsShown() then
        U.mode = "rules"
        U.SetTab("send")
    end
end)

ns.Listen("MAIL", function()
    ns.Later("mail-ui", 0.05, function() U.Refresh() end)
end)

for _, msg in ipairs({ "MAIL_BAGS", "ITEMS_UPDATED", "PRICES_UPDATED", "BAGS_UPDATED" }) do
    ns.Listen(msg, function()
        if U.IsShown() then
            ns.Later("mail-ui", 0.2, function() U.Refresh() end)
        end
    end)
end

ns.On("PLAYER_MONEY", function()
    if U.IsShown() then
        ns.Later("mail-ui", 0.2, function() U.Refresh() end)
    end
end)

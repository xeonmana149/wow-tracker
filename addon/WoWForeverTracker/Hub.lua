-- The in-game window (1.9.20): this character's lifetime gathering and loot
-- (Stats.lua) beside the account's totals, and the website's Crafting
-- Directory - who in the group can make what.
--
-- Open it with /wft stats, /wft craft, or Shift-click on the Sync button.
--
-- Everything that isn't this character comes from the website, by way of
-- the tray app: it writes SiteData.lua (WFTSiteData) into this addon's
-- folder every 20 minutes, and the game reads it at login or /reload.
-- Without the tray app, the window still shows this character.
--
-- No Blizzard tables are touched (UISpecialFrames, StaticPopupDialogs):
-- writing to them taints the Escape menu on this client - see the 1.9.9
-- note on the Sync box in WoWForeverTracker.lua.

local _, ns = ...
ns = ns or {}

local GOLD = { 0.89, 0.753, 0.416 }
local BORDER = { 0.788, 0.643, 0.361, 0.8 }
local BG = { 0.047, 0.039, 0.031, 0.95 }
local QUALITY_COLOR = {
    green = { 0.12, 1, 0 }, blue = { 0, 0.44, 0.87 }, epic = { 0.64, 0.21, 0.93 }, legendary = { 1, 0.5, 0 },
}
local QUALITY_LABEL = { green = "Uncommon (green)", blue = "Rare (blue)", epic = "Epic", legendary = "Legendary" }
local GATHER_ROWS = {
    { key = "herb", label = "Herbs gathered" },
    { key = "ore", label = "Ore mined" },
    { key = "skin", label = "Creatures skinned" },
    { key = "fish", label = "Fish caught" },
    { key = "chests", label = "Chests opened" },
    { key = "opened", label = "Clams, lockboxes and bags opened" },
}
local LIST_ROWS = 15
local ROW_H = 20

local hub -- the window, built on first open

local function secret(v)
    return type(issecretvalue) == "function" and issecretvalue(v) and true or false
end

local function fmt(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(n)
    while true do
        local done
        s, done = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if done == 0 then
            break
        end
    end
    return s
end

local function day(t)
    t = tonumber(t)
    if not t or t <= 0 then
        return "?"
    end
    return date("%d %b %Y", t)
end

local function site()
    return type(WFTSiteData) == "table" and WFTSiteData or nil
end

local function myName()
    local n = WFTHub and WFTHub.siteName and WFTHub.siteName()
    if type(n) == "string" and not secret(n) then
        return n
    end
    local short = UnitName and UnitName("player")
    return (type(short) == "string" and not secret(short)) and short or nil
end

-- Is this site character the one being played? Its full name, or its
-- first name when the game only gives the first.
local function isMe(name, me)
    if type(name) ~= "string" or type(me) ~= "string" then
        return false
    end
    return name == me or (not me:find(" ", 1, true) and name:match("^(%S+)") == me)
end

----------------------------------------------------------------------
-- Building blocks
----------------------------------------------------------------------

local function panel(f, inset)
    local border = f:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], BORDER[4])
    local bg = f:CreateTexture(nil, "BORDER")
    bg:SetPoint("TOPLEFT", inset or 1, -(inset or 1))
    bg:SetPoint("BOTTOMRIGHT", -(inset or 1), inset or 1)
    bg:SetColorTexture(BG[1], BG[2], BG[3], BG[4])
    return bg
end

local function text(parent, template, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    if fs.SetWordWrap then
        fs:SetWordWrap(false)
    end
    return fs
end

local function button(parent, label, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h or 22)
    panel(b)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(1, 0.85, 0.48, 0.12)
    b.sel = b:CreateTexture(nil, "ARTWORK")
    b.sel:SetPoint("BOTTOMLEFT", 1, 1)
    b.sel:SetPoint("BOTTOMRIGHT", -1, 1)
    b.sel:SetHeight(2)
    b.sel:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    b.sel:Hide()
    b.label = text(b, "GameFontNormalSmall", "CENTER")
    b.label:SetPoint("LEFT", 4, 0)
    b.label:SetPoint("RIGHT", -4, 0)
    b.label:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function savePos(f)
    local point, _, rel, x, y = f:GetPoint(1)
    WFTSyncDB = WFTSyncDB or {}
    WFTSyncDB.hubPos = { point = point, rel = rel, x = x, y = y }
end

----------------------------------------------------------------------
-- Loot and gathering page
----------------------------------------------------------------------

local function accountTotals(me)
    local mine = ns.LootTotals(WFTSyncDB and WFTSyncDB.lootStats)
    local total = ns.LootTotals(nil)
    ns.AddTotals(total, mine)
    local others, count = {}, 1
    local data = site()
    for _, c in ipairs(data and data.characters or {}) do
        if type(c) == "table" and not isMe(c.name, me) then
            local t = ns.LootTotals(c.loot)
            ns.AddTotals(total, t)
            count = count + 1
            others[#others + 1] = { name = c.name, t = t }
        end
    end
    return mine, total, others, count
end

local function dropSum(t, minQuality)
    local n = 0
    local counting = false
    for _, q in ipairs(ns.LOOT_QUALITY) do
        if q == minQuality then
            counting = true
        end
        if counting then
            for _, w in ipairs(ns.LOOT_WHERE) do
                n = n + t.drops[w][q]
            end
        end
    end
    return n
end

local function buildStats(page)
    page.since = text(page, "GameFontDisableSmall")
    page.since:SetPoint("TOPLEFT", 0, 0)
    page.since:SetPoint("RIGHT", 0, 0)

    -- Gathering: label | this character | account
    local head = text(page, "GameFontNormal")
    head:SetPoint("TOPLEFT", 0, -20)
    head:SetText("Gathering")
    local c1 = text(page, "GameFontNormalSmall", "RIGHT")
    c1:SetPoint("TOPLEFT", 250, -22)
    c1:SetWidth(120)
    c1:SetText("This character")
    page.accountHead = text(page, "GameFontNormalSmall", "RIGHT")
    page.accountHead:SetPoint("TOPLEFT", 380, -22)
    page.accountHead:SetWidth(130)
    page.gather = {}
    for i, row in ipairs(GATHER_ROWS) do
        local y = -22 - i * 17
        local l = text(page)
        l:SetPoint("TOPLEFT", 8, y)
        l:SetText(row.label)
        local a = text(page, nil, "RIGHT")
        a:SetPoint("TOPLEFT", 250, y)
        a:SetWidth(120)
        local b = text(page, nil, "RIGHT")
        b:SetPoint("TOPLEFT", 380, y)
        b:SetWidth(130)
        page.gather[row.key] = { a, b }
    end

    -- Drops: quality | world | dungeons | raids | account
    local y0 = -22 - (#GATHER_ROWS + 1) * 17 - 8
    local dh = text(page, "GameFontNormal")
    dh:SetPoint("TOPLEFT", 0, y0)
    dh:SetText("Loot picked up (green or better)")
    local cols = { { "World", 160 }, { "Dungeons", 245 }, { "Raids", 330 }, { "Account", 410 } }
    for _, col in ipairs(cols) do
        local h = text(page, "GameFontNormalSmall", "RIGHT")
        h:SetPoint("TOPLEFT", col[2], y0 - 18)
        h:SetWidth(100)
        h:SetText(col[1])
    end
    page.drops = {}
    for i, q in ipairs(ns.LOOT_QUALITY) do
        local y = y0 - 18 - i * 17
        local l = text(page)
        l:SetPoint("TOPLEFT", 8, y)
        l:SetText(QUALITY_LABEL[q])
        local c = QUALITY_COLOR[q]
        l:SetTextColor(c[1], c[2], c[3])
        local cells = {}
        for j, col in ipairs(cols) do
            local v = text(page, nil, "RIGHT")
            v:SetPoint("TOPLEFT", col[2], y)
            v:SetWidth(100)
            cells[j] = v
        end
        page.drops[q] = cells
    end

    -- Latest finds (blue or better), each hoverable for its tooltip
    local y1 = y0 - 18 - (#ns.LOOT_QUALITY + 1) * 17 - 8
    local rh = text(page, "GameFontNormal")
    rh:SetPoint("TOPLEFT", 0, y1)
    rh:SetText("Latest finds")
    page.recent = {}
    for i = 1, 5 do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(250, 16)
        b:SetPoint("TOPLEFT", 8, y1 - 2 - i * 16)
        b.text = text(b)
        b.text:SetAllPoints()
        b:SetScript("OnEnter", function(self)
            if self.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        page.recent[i] = b
    end

    -- Each other character, from the website
    local ch = text(page, "GameFontNormal")
    ch:SetPoint("TOPLEFT", 270, y1)
    ch:SetText("Your other characters")
    page.others = {}
    for i = 1, 5 do
        local l = text(page)
        l:SetPoint("TOPLEFT", 278, y1 - 2 - i * 16)
        l:SetWidth(240)
        page.others[i] = l
    end
end

local function refreshStats(page)
    local me = myName()
    local s = ns.LootStats()
    local mine, total, others, count = accountTotals(me)
    local data = site()
    local since = "Counting since " .. day(s.since) .. "."
    if data then
        since = since .. " Other characters as of their last sync (website data from " .. day(data.made) .. ")."
    else
        since = since .. " Your other characters show here once the tray app has run."
    end
    page.since:SetText(since)
    page.accountHead:SetText(count > 1 and ("Account (" .. count .. " characters)") or "Account")
    for _, row in ipairs(GATHER_ROWS) do
        local cells = page.gather[row.key]
        local items = mine[row.key .. "Items"]
        if items and items > 0 then
            cells[1]:SetText(fmt(mine[row.key]) .. "  |cff999999(" .. fmt(items) .. " items)|r")
        else
            cells[1]:SetText(fmt(mine[row.key]))
        end
        cells[2]:SetText(fmt(total[row.key]))
    end
    for _, q in ipairs(ns.LOOT_QUALITY) do
        local cells = page.drops[q]
        cells[1]:SetText(fmt(mine.drops.world[q]))
        cells[2]:SetText(fmt(mine.drops.dungeon[q]))
        cells[3]:SetText(fmt(mine.drops.raid[q]))
        local all = total.drops.world[q] + total.drops.dungeon[q] + total.drops.raid[q]
        cells[4]:SetText(fmt(all))
    end
    local recent = s.recent or {}
    for i, b in ipairs(page.recent) do
        local e = recent[#recent - i + 1]
        if type(e) == "table" and type(e.link) == "string" then
            b.link = e.link
            local where = e.where == "world" and "" or (" |cff999999(" .. (e.where or "") .. ")|r")
            b.text:SetText(e.link .. where)
            b:Show()
        elseif i == 1 then
            b.link = nil
            b.text:SetText("|cff999999Nothing blue or better yet.|r")
            b:Show()
        else
            b:Hide()
        end
    end
    table.sort(others, function(a, b)
        return (a.t.herb + a.t.ore + a.t.skin + a.t.chests) > (b.t.herb + b.t.ore + b.t.skin + b.t.chests)
    end)
    for i, l in ipairs(page.others) do
        local o = others[i]
        if o then
            local t = o.t
            l:SetText(("%s  |cff999999%s herbs, %s ore, %s skins, %s chests, %s blue+|r"):format(
                o.name, fmt(t.herb), fmt(t.ore), fmt(t.skin), fmt(t.chests), fmt(dropSum(t, "blue"))))
        elseif i == 1 then
            l:SetText(data and "|cff999999None synced yet.|r" or "|cff999999No website data yet.|r")
        else
            l:SetText("")
        end
    end
end

----------------------------------------------------------------------
-- Crafting directory page
----------------------------------------------------------------------

local craft = { search = "", profession = nil, offset = 0, selected = nil, list = {} }

local function professions()
    local data = site()
    local seen, out = {}, {}
    for _, r in ipairs(data and data.recipes or {}) do
        if type(r) == "table" and type(r.p) == "string" and not seen[r.p] then
            seen[r.p] = true
            out[#out + 1] = r.p
        end
    end
    table.sort(out)
    return out
end

local function filtered()
    local data = site()
    local out = {}
    local q = craft.search:lower()
    for _, r in ipairs(data and data.recipes or {}) do
        if type(r) == "table" and type(r.n) == "string"
            and (not craft.profession or r.p == craft.profession)
            and (q == "" or r.n:lower():find(q, 1, true)) then
            out[#out + 1] = r
        end
    end
    table.sort(out, function(a, b)
        if a.n ~= b.n then
            return a.n < b.n
        end
        return tostring(a.p) < tostring(b.p)
    end)
    return out
end

local function crafterLine(data, index, profession)
    local c = data.crafters and data.crafters[index]
    if type(c) ~= "table" then
        return nil
    end
    local skill = type(c.skills) == "table" and c.skills[profession]
    local line = c.name or "?"
    if c.mine then
        line = "|cff40ff40" .. line .. "|r"
    end
    if c.owner and c.owner ~= "" then
        line = line .. " |cff999999(" .. c.owner .. ")|r"
    end
    if skill then
        line = line .. " |cff999999- " .. skill .. "|r"
    end
    return line
end

local function showRecipe(page, r)
    local d = page.detail
    local data = site()
    if not r or not data then
        d.icon:Hide()
        d.name:SetText(data and "Pick a recipe on the left." or "")
        d.prof:SetText("")
        d.body:SetText(data and "" or ("The crafting directory comes from the website. Install the WoW Forever "
            .. "Tracker app (or update it) and it brings the directory into the game every 20 minutes - "
            .. "/reload to load the newest."))
        return
    end
    d.icon:SetTexture(r.i or 134400)
    d.icon:Show()
    d.name:SetText(r.n)
    d.prof:SetText(r.p or "")
    local lines = { "|cffe3c06aMade by|r" }
    for _, index in ipairs(r.c or {}) do
        local line = crafterLine(data, index, r.p)
        if line then
            lines[#lines + 1] = "  " .. line
        end
    end
    if type(r.r) == "table" and #r.r > 0 then
        lines[#lines + 1] = " "
        lines[#lines + 1] = "|cffe3c06aReagents|r"
        for _, reagent in ipairs(r.r) do
            if type(reagent) == "table" and reagent[1] then
                lines[#lines + 1] = "  " .. (tonumber(reagent[2]) or 1) .. " x " .. tostring(reagent[1])
            end
        end
    end
    if type(r.t) == "table" and #r.t > 0 then
        lines[#lines + 1] = " "
        for i, l in ipairs(r.t) do
            if i > 10 then
                break
            end
            lines[#lines + 1] = "|cffaaaaaa" .. tostring(l) .. "|r"
        end
    end
    d.body:SetText(table.concat(lines, "\n"))
end

local function refreshCraft(page)
    local data = site()
    craft.list = filtered()
    local maxOffset = math.max(0, #craft.list - LIST_ROWS)
    craft.offset = math.min(math.max(0, craft.offset), maxOffset)
    for i, row in ipairs(page.rows) do
        local r = craft.list[craft.offset + i]
        if r then
            row.recipe = r
            row.icon:SetTexture(r.i or 134400)
            row.name:SetText(r.n)
            local n = type(r.c) == "table" and #r.c or 0
            row.count:SetText(n == 1 and "1 crafter" or (n .. " crafters"))
            row.sel:SetShown(craft.selected == r)
            row:Show()
        else
            row.recipe = nil
            row:Hide()
        end
    end
    page.profButton.label:SetText(craft.profession or "All professions")
    if not data then
        page.status:SetText("No website data yet.")
    elseif #craft.list == 0 then
        page.status:SetText("No recipes match.")
    else
        page.status:SetText(("%d-%d of %d recipes   |cff999999website data from %s|r"):format(craft.offset + 1,
            math.min(#craft.list, craft.offset + LIST_ROWS), #craft.list, day(data.made)))
    end
    showRecipe(page, craft.selected)
end

local function buildCraft(page)
    local search = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    search:SetSize(200, 20)
    search:SetPoint("TOPLEFT", 6, 0)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self)
        local t = self:GetText() or ""
        craft.search = secret(t) and "" or t
        craft.offset = 0
        refreshCraft(page)
    end)
    search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    local hint = text(search, "GameFontDisableSmall")
    hint:SetPoint("LEFT", 4, 0)
    hint:SetText("Search recipes")
    search:HookScript("OnEditFocusGained", function() hint:Hide() end)
    search:HookScript("OnEditFocusLost", function(self)
        hint:SetShown((self:GetText() or "") == "")
    end)

    -- One button that steps through the professions (right-click goes back).
    page.profButton = button(page, "All professions", 150, 20, function(_, mouse)
        local list = professions()
        local at = 0
        for i, p in ipairs(list) do
            if p == craft.profession then
                at = i
            end
        end
        at = at + (mouse == "RightButton" and -1 or 1)
        if at > #list then
            at = 0
        elseif at < 0 then
            at = #list
        end
        craft.profession = list[at]
        craft.offset = 0
        refreshCraft(page)
    end)
    page.profButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    page.profButton:SetPoint("LEFT", search, "RIGHT", 10, 0)

    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", 0, -26)
    list:SetSize(260, LIST_ROWS * ROW_H + 4)
    panel(list)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        craft.offset = craft.offset - delta * 3
        refreshCraft(page)
    end)
    page.rows = {}
    for i = 1, LIST_ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetSize(256, ROW_H)
        row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.85, 0.48, 0.1)
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.18)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 3, 0)
        row.name = text(row)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        row.name:SetPoint("RIGHT", -64, 0)
        row.count = text(row, "GameFontDisableSmall", "RIGHT")
        row.count:SetPoint("RIGHT", -4, 0)
        row:SetScript("OnClick", function(self)
            craft.selected = self.recipe
            refreshCraft(page)
        end)
        page.rows[i] = row
    end
    page.status = text(page, "GameFontDisableSmall")
    page.status:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 2, -4)
    page.status:SetWidth(520)

    local d = CreateFrame("Frame", nil, page)
    d:SetPoint("TOPLEFT", list, "TOPRIGHT", 10, 0)
    d:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 266, 0)
    panel(d)
    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(28, 28)
    d.icon:SetPoint("TOPLEFT", 8, -8)
    d.name = text(d, "GameFontNormal")
    d.name:SetPoint("TOPLEFT", 42, -9)
    d.name:SetPoint("RIGHT", -8, 0)
    d.prof = text(d, "GameFontDisableSmall")
    d.prof:SetPoint("TOPLEFT", 42, -25)
    d.body = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.body:SetPoint("TOPLEFT", 10, -44)
    d.body:SetPoint("BOTTOMRIGHT", -10, 8)
    d.body:SetJustifyH("LEFT")
    d.body:SetJustifyV("TOP")
    page.detail = d

    local note = text(page, "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", page.status, "BOTTOMLEFT", 0, -3)
    note:SetWidth(520)
    note:SetText("A recipe missing? Its crafter opens that profession's window once, then syncs.")
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------

local function showTab(tab)
    hub.tab = tab
    hub.statsPage:SetShown(tab == "stats")
    hub.craftPage:SetShown(tab == "craft")
    hub.statsTab.sel:SetShown(tab == "stats")
    hub.craftTab.sel:SetShown(tab == "craft")
    if tab == "stats" then
        refreshStats(hub.statsPage)
    else
        refreshCraft(hub.craftPage)
    end
end

local function build()
    local f = CreateFrame("Frame", "WFTHubFrame", UIParent)
    f:SetSize(560, 450)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    panel(f)
    local pos = type(WFTSyncDB) == "table" and type(WFTSyncDB.hubPos) == "table" and WFTSyncDB.hubPos
    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.rel or pos.point, tonumber(pos.x) or 0, tonumber(pos.y) or 0)
    else
        f:SetPoint("CENTER")
    end

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(24)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function()
        f:StartMoving()
    end)
    bar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        savePos(f)
    end)
    local barBg = bar:CreateTexture(nil, "ARTWORK")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0.12, 0.09, 0.05, 0.9)
    local icon = bar:CreateTexture(nil, "OVERLAY")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexture("Interface\\AddOns\\WoWForeverTracker\\Art\\sync.tga")
    local title = text(bar, "GameFontNormal")
    title:SetPoint("LEFT", icon, "RIGHT", 5, 0)
    title:SetText("WoW Forever Tracker")
    local close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -1, 0)
    close:SetScript("OnClick", function()
        f:Hide()
    end)

    f.statsTab = button(f, "Loot & gathering", 130, 22, function() showTab("stats") end)
    f.statsTab:SetPoint("TOPLEFT", 12, -32)
    f.craftTab = button(f, "Crafting directory", 130, 22, function() showTab("craft") end)
    f.craftTab:SetPoint("LEFT", f.statsTab, "RIGHT", 6, 0)

    f.statsPage = CreateFrame("Frame", nil, f)
    f.statsPage:SetPoint("TOPLEFT", 16, -64)
    f.statsPage:SetPoint("BOTTOMRIGHT", -16, 12)
    f.craftPage = CreateFrame("Frame", nil, f)
    f.craftPage:SetPoint("TOPLEFT", 16, -64)
    f.craftPage:SetPoint("BOTTOMRIGHT", -16, 12)
    hub = f
    buildStats(f.statsPage)
    buildCraft(f.craftPage)
    f:SetScript("OnShow", function()
        showTab(f.tab or "stats")
    end)
    f:Hide()
    return f
end

local function open(tab)
    local ok, err = pcall(function()
        if not hub then
            build()
        end
        hub:Show()
        showTab(tab or hub.tab or "stats")
    end)
    if not ok then
        print("|cffffcc00WFT:|r Couldn't open the window: " .. tostring(err))
    end
end

WFTHub = WFTHub or {}
WFTHub.open = open
WFTHub.toggle = function()
    if hub and hub:IsShown() then
        hub:Hide()
    else
        open()
    end
end
ns.HubRefresh = function()
    if hub and hub:IsShown() then
        showTab(hub.tab)
    end
end

-- /wft stats and /wft craft, in front of the main file's /wft commands.
local mainSlash = SlashCmdList and SlashCmdList["WFT"]
if mainSlash then
    SlashCmdList["WFT"] = function(raw)
        local msg = type(raw) == "string" and raw:lower():match("^%s*(.-)%s*$") or ""
        if msg == "stats" or msg == "loot" or msg == "gathering" then
            open("stats")
        elseif msg == "craft" or msg == "crafting" or msg == "directory" then
            open("craft")
        elseif msg == "hub" or msg == "window" then
            WFTHub.toggle()
        else
            mainSlash(raw)
        end
    end
end

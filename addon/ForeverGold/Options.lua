-- Forever Gold - settings in the game's own Options window
--
-- Options > AddOns > WoW Forever, with a page each for:
--   Auction Forever   scanning, buying and selling at the auction house
--   Bags Forever      the bag and bank windows
--   Mail Forever      the mailbox, rules and your banker
--   Gathering Forever routes, map spots, minimap and loot beams
--   Azeroth Radio     the shared radio (it plays in the tray app)
-- Built from the game's own checkboxes, sliders and dropdowns. Each one reads
-- and writes ns.db.opts, so the bag window, the mailbox and the main window
-- see a change at once.

local _, ns = ...
local floor = math.floor

local OPT = { cats = {} }
ns.Options = OPT

local RADIO_URL = "https://wow-tracker-amber.vercel.app/radio"

local function O()
    return ns.db.opts
end

-- Everything that shows a setting, redrawn.
local function changed()
    if ns.RefreshUI then
        pcall(ns.RefreshUI, true)
    end
    if ns.BagUI and ns.BagUI.Refresh then
        pcall(ns.BagUI.Refresh)
    end
    if ns.MailUI and ns.MailUI.Refresh then
        pcall(ns.MailUI.Refresh)
    end
    if ns.RedrawWorldMap then
        pcall(ns.RedrawWorldMap)
    end
end

----------------------------------------------------------------------
-- Building blocks
----------------------------------------------------------------------

local function header(layout, text, tooltip)
    if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text, tooltip))
    end
end

local function button(layout, name, text, onClick, tooltip)
    if layout and layout.AddInitializer and CreateSettingsButtonInitializer then
        layout:AddInitializer(CreateSettingsButtonInitializer(name, text, onClick, tooltip, false))
    end
end

-- A checkbox. get() / set(value) default to ns.db.opts[key], where on is
-- "not false" when default is true and "== true" when default is false.
local function check(cat, key, name, tooltip, default, get, set)
    get = get or function()
        local v = O()[key]
        if v == nil then
            return default
        end
        return v == true
    end
    set = set or function(v)
        O()[key] = v
    end
    local setting = Settings.RegisterProxySetting(cat, "FOREVERGOLD_" .. key:upper(), Settings.VarType.Boolean, name,
        default, get, function(v)
            set(v and true or false)
            changed()
        end)
    Settings.CreateCheckbox(cat, setting, tooltip)
    return setting
end

-- A dropdown of { value, label } choices.
local function choose(cat, key, name, tooltip, default, choices, varType, get, set)
    get = get or function()
        local v = O()[key]
        if v == nil then
            return default
        end
        return v
    end
    set = set or function(v)
        O()[key] = v
    end
    local setting = Settings.RegisterProxySetting(cat, "FOREVERGOLD_" .. key:upper(), varType or Settings.VarType.Number, name,
        default, get, function(v)
            set(v)
            changed()
        end)
    local function options()
        local box = Settings.CreateControlTextContainer()
        for _, c in ipairs(choices) do
            box:Add(c[1], c[2])
        end
        return box:GetData()
    end
    Settings.CreateDropdown(cat, setting, options, tooltip)
    return setting
end

-- A slider from lo to hi in steps; label(v) is what it shows.
local function slide(cat, key, name, tooltip, default, lo, hi, step, label, get, set)
    get = get or function()
        return tonumber(O()[key]) or default
    end
    set = set or function(v)
        O()[key] = v
    end
    local setting = Settings.RegisterProxySetting(cat, "FOREVERGOLD_" .. key:upper(), Settings.VarType.Number, name,
        default, get, function(v)
            set(v)
            changed()
        end)
    local options = Settings.CreateSliderOptions(lo, hi, step)
    if options.SetLabelFormatter and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, label)
    end
    Settings.CreateSlider(cat, setting, options, tooltip)
    return setting
end

----------------------------------------------------------------------
-- The pages
----------------------------------------------------------------------

local function auctionPage(cat, layout)
    header(layout, "Scanning")
    check(cat, "autoScan", "Read prices when I open the auction house",
        "Scans by itself when the prices you have are older than the time below.", true)
    choose(cat, "autoAge", "Rescan when prices are older than",
        "How old prices can be before opening the auction house reads them again.", 300,
        { { 300, "5 minutes" }, { 900, "15 minutes" }, { 1800, "30 minutes" }, { 3600, "60 minutes" } })
    check(cat, "fastScan", "Fast scan",
        "Download the whole auction house at once. The game allows it every 15 minutes.", true)
    header(layout, "Buying")
    choose(cat, "dealMin", "Smallest profit worth showing",
        "Deals on the Buy tab that make less than this are left out.", 500,
        { { 100, "1 silver" }, { 500, "5 silver" }, { 2500, "25 silver" }, { 10000, "1 gold" } })
    check(cat, "buyConfirm", "Ask before paying well over the usual price",
        "Asks first when you buy at 20% or more over an item's usual price.", true)
    header(layout, "Selling")
    choose(cat, "postUndercut", "Undercut the cheapest listing by",
        "Never goes below your floor, and never undercuts your own auctions.", "copper",
        { { "copper", "1 copper" }, { "1%", "1%" }, { "5%", "5%" } }, Settings.VarType.String)
    choose(cat, "postQty", "Each listing holds",
        "With one full stack, Post all lists your stacks one at a time.", "stack",
        { { "stack", "One full stack" }, { "10", "10" }, { "5", "5" }, { "one", "One item" }, { "all", "Everything you have" } },
        Settings.VarType.String)
    local durations = {}
    for i = 1, 3 do
        durations[i] = { i, ns.SellDurationLabel and ns.SellDurationLabel(i) or tostring(i) }
    end
    choose(cat, "sellDuration", "Auctions last", "Longer costs a bigger deposit.", 2, durations)
    header(layout, "Tooltips")
    check(cat, "tooltip", "Auction prices in item tooltips",
        "What it sells for, how fast, and what it's worth to a vendor.", true)
end

local function bagsPage(cat, layout)
    local BU = function() return ns.BagUI end
    header(layout, "The bag window")
    check(cat, "bagUI", "Use Forever Gold's bags",
        "All your bags in one window, your other characters' bags and banks, banker marks and Sell junk. Off: the game's own bags.",
        true, nil, function(on)
            local bu = BU()
            if not bu then
                O().bagUI = on
            elseif on then
                bu.Enable()
            else
                O().bagUI = false
                bu.Uninstall()
            end
        end)
    check(cat, "bagSplit", "Split by bag",
        "Off: one big inventory. On: a section for each bag.", false)
    check(cat, "bagSpecialRows", "Quivers and special bags on their own rows",
        "Quivers, ammo pouches, reagent and profession bags each get a row under the main grid, named in their colour.", true)
    check(cat, "bagEmpty", "Show empty slots", nil, true)
    check(cat, "bagNew", "New loot in its own row", "What you've picked up since you last closed your bags, at the bottom.", true)
    check(cat, "bagBar", "Show the bag bar",
        "Your bags in a row under the title: click one to hide its slots, hover to light them up, right-click for its options.", true)
    check(cat, "bagJunkDim", "Tone down junk",
        "Gray items, and anything you mark as junk, are grayed out and darkened.", true)
    header(layout, "Look")
    slide(cat, "bagCols", "Columns", "How many slots across.", 10, 6, 16, 1,
        function(v) return tostring(floor(v + 0.5)) end)
    slide(cat, "bagAlphaPct", "Background", "How solid the window's background is.", 100, 20, 100, 5,
        function(v) return floor(v + 0.5) .. "%" end,
        function()
            return floor((tonumber(O().bagAlpha) or 1) * 100 + 0.5)
        end,
        function(v)
            O().bagAlpha = floor(v + 0.5) / 100
        end)
    header(layout, "Tooltips")
    check(cat, "bagTooltip", "Say which of my characters have an item",
        "Item tooltips list who has it, in their bags or bank.", true)
    button(layout, "Hidden bags", "Show them all", function()
        O().bagHidden = nil
        changed()
    end, "Shows every bag you've hidden from the bag bar.")
    button(layout, "Open", "Open my bags", function()
        local bu = BU()
        if bu then
            if not bu.Enabled() then
                bu.Enable()
            end
            bu.Open()
        end
    end)
end

local RESERVE = { { 0, "Nothing" }, { 10000, "1 gold" }, { 50000, "5 gold" }, { 100000, "10 gold" }, { 500000, "50 gold" },
    { 1000000, "100 gold" } }

local function mailPage(cat, layout)
    header(layout, "The mailbox")
    check(cat, "mailOurs", "Use Forever Gold's mailbox window",
        "Off: the game's own mailbox, with a button above it to switch back.", true,
        function() return not O().mailBlizzard end,
        function(on)
            local U = ns.MailUI
            if U and ns.Mail and ns.Mail.open and U.UseOurs then
                if on then U.UseOurs() else U.UseBlizzard() end
            else
                O().mailBlizzard = (not on) or nil
            end
        end)
    header(layout, "Your rules")
    check(cat, "mailPrompt", "Ask to send what my rules match",
        "When a mailbox opens: what would go where, with Send now, Review first or Not now.", true)
    check(cat, "mailAuto", "Send it by itself",
        "No asking: it starts sending as soon as the mailbox opens.", false)
    header(layout, "Gold")
    check(cat, "mailGold", "Quick-send also sends my spare gold",
        "Everything above \"Keep at least\" after postage goes to your banker.", false)
    choose(cat, "mailReserve", "Keep at least", "Postage counts. The mailbox's Send tab takes any amount.", 0, RESERVE,
        nil, function() return (ns.Mail and ns.Mail.Reserve and ns.Mail.Reserve()) or 0 end)
    header(layout, "Rules, banker and quick-send",
        "Rules, your banker and what quick-send includes are set in the mailbox window (Send and Rules tabs).")
end

local function gatherPage(cat, layout)
    header(layout, "Routes and maps")
    check(cat, "waypoint", "Waypoint to the next stop on a route", "Uses the game's own map waypoint.", true)
    check(cat, "worldMapSpots", "My spots and route on the world map", "OpenMap too.", true)
    check(cat, "mapButton", "A gathering button on the world map", "Filter herbs, ore, fishing and chests.", true)
    check(cat, "minimapSpots", "My spots and the next stop on the minimap", nil, true)
    check(cat, "onlyMyProfs", "Only spots for professions this character has",
        "Herbs, ore and fishing spots (map, minimap and beams) only when this character has Herbalism, Mining or Fishing.", true)
    check(cat, "revealMap", "Draw the whole zone on the Routes map", "Not just the parts you've explored.", true)
    header(layout, "Loot beams")
    check(cat, "lootBeam", "Loot beams",
        "Gold on a route stop, white on a spot you've recorded, light blue on one you haven't.", true)
    check(cat, "nearestBeam", "Beam on the nearest recorded spot",
        "With no route running, and only when you're not tracking anything else.", true)
    check(cat, "beamUnrecorded", "Beam on nodes right in front of me",
        "Herbs, veins and chests, recorded or not. Turns on the game's Interact Key and its icons.", true)
end

local radioBox
local function showRadioLink()
    if not radioBox then
        local f = CreateFrame("Frame", "ForeverGoldRadioLink", UIParent)
        f:SetFrameStrata("DIALOG")
        f:SetSize(380, 92)
        f:SetPoint("CENTER", 0, 120)
        f:EnableMouse(true)
        if ns.UIKit and ns.UIKit.skin then
            ns.UIKit.skin(f)
        end
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.text:SetPoint("TOP", 0, -12)
        f.text:SetText("Azeroth Radio - press Ctrl+C to copy")
        f.box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        f.box:SetSize(330, 24)
        f.box:SetPoint("TOP", 0, -36)
        f.box:SetAutoFocus(true)
        f.box:SetScript("OnEscapePressed", function() f:Hide() end)
        f.box:SetScript("OnEnterPressed", function() f:Hide() end)
        f.box:SetScript("OnTextChanged", function(self)
            if self:GetText() ~= RADIO_URL then
                self:SetText(RADIO_URL)
                self:HighlightText()
            end
        end)
        f.close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.close:SetSize(80, 22)
        f.close:SetPoint("BOTTOM", 0, 8)
        f.close:SetText("Close")
        f.close:SetScript("OnClick", function() f:Hide() end)
        radioBox = f
    end
    radioBox:Show()
    radioBox.box:SetText(RADIO_URL)
    radioBox.box:SetFocus()
    radioBox.box:HighlightText()
end
OPT.ShowRadioLink = showRadioLink

local function radioPage(cat, layout)
    header(layout, "Azeroth Radio",
        "Shared radio stations everyone in WoW Forever can listen to together. It plays in the WoW Forever Tracker app, not in the game.")
    header(layout, "To listen: the tray app > Azeroth Radio > pick a station",
        "Open the WoW Forever Tracker app's tray menu (by the clock), choose Azeroth Radio, and pick a station.")
    header(layout, "To request songs and vote: the radio page",
        "Stations, songs and votes are on the website.")
    button(layout, "The radio page", "Show the link", showRadioLink, RADIO_URL)
end

local function homePage(cat, layout)
    header(layout, "Forever Gold " .. tostring(ns.VERSION or ""),
        "Plain-English gold making: the auction house, crafting, farming, your bags and your mailbox.")
    button(layout, "Forever Gold", "Open the window", function()
        if SettingsPanel and SettingsPanel.Close then
            pcall(SettingsPanel.Close, SettingsPanel)
        end
        if ns.ShowTab then
            ns.ShowTab("todo")
        end
    end, "The same as /gold.")
    button(layout, "Tips and help", "Open", function()
        if SettingsPanel and SettingsPanel.Close then
            pcall(SettingsPanel.Close, SettingsPanel)
        end
        if ns.ShowTab then
            ns.ShowTab("settings")
        end
    end, "Ideas for your professions, sale rates, and what the words mean.")
end

----------------------------------------------------------------------
-- Registering, and opening a page
----------------------------------------------------------------------

local PAGES = {
    { key = "auction", name = "Auction Forever", build = auctionPage },
    { key = "bags", name = "Bags Forever", build = bagsPage },
    { key = "mail", name = "Mail Forever", build = mailPage },
    { key = "gathering", name = "Gathering Forever", build = gatherPage },
    { key = "radio", name = "Azeroth Radio", build = radioPage },
}

function OPT.Available()
    return type(Settings) == "table" and type(Settings.RegisterVerticalLayoutCategory) == "function"
        and type(Settings.RegisterProxySetting) == "function" and type(Settings.OpenToCategory) == "function"
end

function OPT.Register()
    if OPT.registered or not OPT.Available() then
        return OPT.registered
    end
    local root, rootLayout = Settings.RegisterVerticalLayoutCategory("WoW Forever")
    if not root then
        return false
    end
    homePage(root, rootLayout)
    OPT.cats.home = root
    for _, p in ipairs(PAGES) do
        local cat, layout = Settings.RegisterVerticalLayoutSubcategory(root, p.name)
        if cat then
            local ok, err = pcall(p.build, cat, layout)
            if not ok and ns.Err then
                ns.Err("options-" .. p.key, err)
            end
            OPT.cats[p.key] = cat
        end
    end
    Settings.RegisterAddOnCategory(root)
    OPT.registered = true
    return true
end

-- Opens Options > AddOns > WoW Forever at a page ("auction", "bags",
-- "mail", "gathering", "radio", or nil for the top). False if it can't.
function OPT.Open(which)
    if not OPT.Register() then
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        ns.Print("the Options window opens after combat.")
        return true
    end
    local cat = OPT.cats[which or "home"] or OPT.cats.home
    local ok = pcall(Settings.OpenToCategory, cat:GetID())
    return ok
end
ns.OpenOptions = OPT.Open

ns.Listen("READY", function()
    ns.Guard("options", OPT.Register)()
end)

-- Forever UI - tooltips.
--
-- The game's tooltips in the dark-and-gold look, and the ones that would
-- appear in the bottom right corner (over the bag bar) start from a spot
-- you can move (/fui move: "Tooltip").

local _, ns = ...

local function actionTooltip(button, fromDefaultAnchor)
    local tt = GameTooltip
    if not (tt and button) then return end
    if not fromDefaultAnchor and not (tt.GetOwner and tt:GetOwner() == button) then return end
    local ok, forbidden = pcall(function() return tt:IsForbidden() end)
    if not ok or forbidden then return end
    tt:ClearAllPoints()
    tt:SetPoint("BOTTOMLEFT", button, "TOPRIGHT", 4, 4)
    if tt.SetClampedToScreen then tt:SetClampedToScreen(true) end
end

local function recolor(tt)
    local ns9 = tt and tt.NineSlice
    if type(ns9) ~= "table" then
        return
    end
    local C = ns.C
    if ns9.SetCenterColor then
        ns9:SetCenterColor(C.dark[1], C.dark[2], C.dark[3], math.min(1, ns.PanelAlpha() + 0.1))
    end
    if ns9.SetBorderColor then
        ns9:SetBorderColor(C.gold[1], C.gold[2], C.gold[3], ns.EdgeAlpha())
    end
end

local m = ns.Module("tooltip", "Tooltips", function(m)
    -- the spot the default tooltip grows up and left from
    local anchor = CreateFrame("Frame", "ForeverUITooltipAnchor", UIParent)
    anchor:SetSize(220, 40)
    ns.Place(anchor, "tooltip", "Tooltip", { "BOTTOMRIGHT", "BOTTOMRIGHT", -24, 120 }, nil, { noResize = true })
    m.anchor = anchor

    local actionButtons = setmetatable({}, { __mode = "k" })
    local prefixes = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
        "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button", "PetActionButton", "StanceButton", "PossessButton" }
    for _, prefix in ipairs(prefixes) do
        for i = 1, 12 do
            local button = _G[prefix .. i]
            if type(button) == "table" then actionButtons[button] = true end
        end
    end

    if GameTooltip_SetDefaultAnchor then
        hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tt, parent)
            if not tt or tt:IsForbidden() then
                return
            end
            if tt == GameTooltip and actionButtons[parent] then
                actionTooltip(parent, true)
                return
            end
            tt:ClearAllPoints()
            tt:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
        end)
    end
    -- The native action-button hover owns the tooltip. Position it after the
    -- game's own handler, without clearing its contents or changing other UI.
    for button in pairs(actionButtons) do
        if button.HookScript then
            button:HookScript("OnEnter", function(self) actionTooltip(self) end)
        end
        -- The native tooltip periodically refreshes via SetTooltip, which
        -- can reapply its default anchor without another OnEnter event.
        if type(button.SetTooltip) == "function" then
            hooksecurefunc(button, "SetTooltip", function(self) actionTooltip(self) end)
        end
    end
    if SharedTooltip_SetBackdropStyle then
        hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tt)
            if tt and not tt:IsForbidden() then
                recolor(tt)
            end
        end)
    end
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
        if tt and tt.HookScript then
            tt:HookScript("OnShow", recolor)
            recolor(tt)
        end
    end
end)

function m:Restyle()
    recolor(GameTooltip)
end

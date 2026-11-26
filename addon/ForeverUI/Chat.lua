-- Forever UI chat: retain the game's actual chat frames, tabs and input.
local _, ns = ...

local HIDE = { "QuickJoinToastButton", "TextToSpeechButton", "TextToSpeechButtonFrame",
    "ChatFrameMenuButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton",
    "ChatFrameToggleVoiceMuteButton", "OneForAllChatHideButton" }

-- Remove only decorative artwork, leaving text, flashing alerts and the
-- native chat frame, input and interactions in place.
local function clearArt(owner, name, keys)
    for _, key in ipairs(keys) do
        local region = owner[key]
        if type(region) ~= "table" then region = _G[name .. key] end
        if type(region) == "table" and type(region.SetAlpha) == "function" then
            region:SetAlpha(0)
        end
    end
end

local TAB_ART = { "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight" }
local EDIT_ART = { "Left", "Mid", "Middle", "Right", "FocusLeft", "FocusMid", "FocusRight" }

local function applyChatFont(frame, source)
    if not (frame and type(frame.GetFont) == "function" and type(frame.SetFont) == "function"
        and source and type(source.GetFont) == "function") then return end
    local ok, face = pcall(source.GetFont, source)
    local got, current, size, flags = pcall(frame.GetFont, frame)
    if ok and got and type(face) == "string" and face ~= "" and type(size) == "number" and size > 0
        and current ~= face then
        pcall(frame.SetFont, frame, face, size, flags or "")
    end
end

-- OneForAll owns its anonymous copy buttons. Turn off that feature once,
-- before its PLAYER_LOGIN setup, rather than guessing at unrelated children.
local function disableCopySetting()
    if ns.db and not ns.db.fuiCopyChatDisabledV2 and type(OneForAllDB) == "table"
        and type(OneForAllDB.qol) == "table" then
        OneForAllDB.qol.copyChat = false
        ns.db.fuiCopyChatDisabledV2 = true
    end
    -- OneForAll can create/show its chat toggle after our initial skin pass.
    -- Disable the feature at its source before that addon's login setup.
    if ns.db and not ns.db.fuiChatToggleDisabled and type(OneForAllDB) == "table"
        and type(OneForAllDB.qol) == "table" then
        OneForAllDB.qol.chatHide = false
        ns.db.fuiChatToggleDisabled = true
    end
end
ns.On("ADDON_LOADED", disableCopySetting)

local function removeCopyButton(frame)
    if type(frame.GetChildren) ~= "function" then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        pcall(function()
            if child.IsForbidden and child:IsForbidden() then return end
            if not (child.IsObjectType and child:IsObjectType("Button") and child.GetName
                and not child:GetName() and child:GetWidth() == 18 and child:GetHeight() == 18) then return end
            local point, relative, relativePoint, x, y = child:GetPoint(1)
            if point == "TOPRIGHT" and relative == frame and relativePoint == "TOPRIGHT" and x == 2 and y == 2 then
                child:Hide()
                if child.EnableMouse then child:EnableMouse(false) end
            end
        end)
    end
end

local BORDER_ART = { "Background", "TopLeftTexture", "TopRightTexture", "BottomLeftTexture", "BottomRightTexture",
    "TopTexture", "BottomTexture", "LeftTexture", "RightTexture" }

local function clearSidePanel(frame, name)
    local side = frame.buttonFrame
    if type(side) ~= "table" then side = _G[name .. "ButtonFrame"] end
    if type(side) == "table" then clearArt(side, name .. "ButtonFrame", BORDER_ART) end
end

local function gold(region, alpha)
    if type(region) == "table" and type(region.SetVertexColor) == "function" then
        region:SetVertexColor(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], alpha or 1)
    end
end

local function styleArrow(button, up)
    if type(button) ~= "table" or type(button.CreateTexture) ~= "function" then return end
    -- MinimalScrollBar steppers use a Texture region instead of the usual
    -- Button texture. Hide it so the custom chevron cannot double up.
    if type(button.Texture) == "table" then
        button.Texture:SetAlpha(0)
        if not button.fuiHideNativeArrow and button.HookScript then
            local function hideNative(self)
                if self.Texture and self.Texture.SetAlpha then self.Texture:SetAlpha(0) end
            end
            for _, event in ipairs({ "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp", "OnEnable", "OnDisable" }) do
                button:HookScript(event, hideNative)
            end
            button.fuiHideNativeArrow = true
        end
    end
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        if type(button[getter]) == "function" then
            local ok, tex = pcall(button[getter], button)
            if ok and type(tex) == "table" and tex.SetAlpha then tex:SetAlpha(0) end
        end
    end
    if button.fuiGoldArrow then return end
    local arrow = button:CreateTexture(nil, "OVERLAY", nil, 6)
    arrow:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\scroll-arrow-" .. (up and "up" or "down"))
    arrow:SetSize(14, 14)
    arrow:SetPoint("CENTER", button, "CENTER")
    button.fuiGoldArrow = arrow
end

local function styleScrollbar(frame, name)
    styleArrow(frame.ScrollToBottomButton, false)
    styleArrow(_G[name .. "ButtonFrameUpButton"], true)
    styleArrow(_G[name .. "ButtonFrameDownButton"], false)
    styleArrow(_G[name .. "ButtonFrameBottomButton"], false)
    local s = frame.ScrollBar
    if type(s) ~= "table" then s = _G[name .. "ScrollBar"] end
    if type(s) ~= "table" then return end
    local track = s.Track
    local thumb = type(track) == "table" and track.Thumb or s.Thumb
    if type(track) == "table" and type(thumb) == "table" and track.CreateTexture and thumb.CreateTexture and not s.fuiGoldScroll then
        ns.Panel(track, { noBg = true, edge = 0.65 })
        clearArt(track, name .. "ScrollBarTrack", { "Begin", "Middle", "End" })
        clearArt(thumb, name .. "ScrollBarThumb", { "Begin", "Middle", "End" })
        local rail = track:CreateTexture(nil, "BACKGROUND")
        rail:SetPoint("TOP", track, "TOP"); rail:SetPoint("BOTTOM", track, "BOTTOM"); rail:SetWidth(2)
        rail:SetColorTexture(ns.C.gold[1], ns.C.gold[2], ns.C.gold[3], 0.3)
        local grip = thumb:CreateTexture(nil, "OVERLAY")
        grip:SetPoint("TOP", thumb, "TOP", 0, -1); grip:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 1); grip:SetWidth(4)
        grip:SetColorTexture(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3], 0.9)
        s.fuiGoldScroll = true
    end
    for _, part in pairs({ track, thumb }) do
        if type(part) == "table" then
            gold(part.Begin, 0.7); gold(part.Middle, 0.7); gold(part.End, 0.7)
            gold(part.Texture, 0.7)
        end
    end
    if type(s.GetThumbTexture) == "function" then
        local ok, tex = pcall(s.GetThumbTexture, s)
        if ok then gold(tex, 0.85) end
    end
    styleArrow(s.Back, true)
    styleArrow(s.Forward, false)
    styleArrow(s.ScrollUpButton, true)
    styleArrow(s.ScrollDownButton, false)
end

local function selectedTab(frame)
    return frame == (SELECTED_CHAT_FRAME or SELECTED_DOCK_FRAME or ChatFrame1)
end

local function hideControls()
    for _, name in ipairs(HIDE) do
        local f = _G[name]
        if type(f) == "table" and not f.fuiChatHidden then
            -- Do not Hide or reparent Quick Join: the secure Friends button
            -- forwards clicks to it. Alpha and hit testing affect only visuals.
            f.fuiChatHidden = true
            if f.SetAlpha then f:SetAlpha(0) end
            if f.EnableMouse then f:EnableMouse(false) end
        end
    end
end

local function skinChat()
    for i = 1, tonumber(NUM_CHAT_WINDOWS) or 10 do
        local name = "ChatFrame" .. i
        local frame, tab, edit = _G[name], _G[name .. "Tab"], _G[name .. "EditBox"]
        if type(frame) == "table" and frame.CreateTexture then
            -- ChatFontNormal is designed for dense chat lines; the UI face
            -- is wider and can make message text feel stretched.
            applyChatFont(frame, ChatFontNormal)
            clearArt(frame, name, { "Background" })
            -- Add ten percentage points of darkness only inside the message
            -- area, without restoring the oversized native background or border.
            if not frame.fuiChatShade then
                local shade = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
                shade:SetAllPoints(frame)
                shade:SetColorTexture(ns.C.dark[1], ns.C.dark[2], ns.C.dark[3], 0.10)
                frame.fuiChatShade = shade
            end
            styleScrollbar(frame, name)
            clearSidePanel(frame, name)
            removeCopyButton(frame)
        end
        if type(tab) == "table" and tab.CreateTexture and not tab.fuiChatPanel then
            local underline = tab:CreateTexture(nil, "ARTWORK")
            underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 8, 4)
            underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -8, 4)
            underline:SetHeight(1)
            underline:SetColorTexture(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3], 0.85)
            tab.fuiUnderline = underline
            local highlight = tab:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints(tab)
            highlight:SetColorTexture(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3], 0.16)
            tab.fuiChatPanel = true
        end
        if type(tab) == "table" and tab.fuiChatPanel then
            clearArt(tab, name .. "Tab", TAB_ART)
            tab.fuiUnderline:SetShown(selectedTab(frame))
        end
        if type(edit) == "table" and edit.CreateTexture and not edit.fuiChatPanel then
            if edit.SetHeight then edit:SetHeight(24) end
            ns.Panel(edit, { alpha = 0.5, edge = 1.4 })
            edit.fuiChatPanel = true
        end
        if type(edit) == "table" and edit.fuiChatPanel then
            applyChatFont(edit, GameFontHighlightSmall)
            clearArt(edit, name .. "EditBox", EDIT_ART)
            -- The input's custom 24px background must sit below the message
            -- area, rather than overlapping its final line.
            if type(frame) == "table" and edit.ClearAllPoints and edit.SetPoint
                and not (InCombatLockdown and InCombatLockdown() and edit.IsProtected and edit:IsProtected()) then
                edit:ClearAllPoints()
                edit:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -4)
                edit:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -4)
            end
        end
    end
    hideControls()
end

ns.Module("chat", "Chat", function()
    disableCopySetting()
    skinChat()
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function() disableCopySetting(); skinChat() end)
    end
    if type(FCF_OpenTemporaryWindow) == "function" then
        hooksecurefunc("FCF_OpenTemporaryWindow", skinChat)
    end
    if type(FCF_SelectDockFrame) == "function" then
        hooksecurefunc("FCF_SelectDockFrame", skinChat)
    end
    if type(FCF_Tab_OnClick) == "function" then
        hooksecurefunc("FCF_Tab_OnClick", skinChat)
    end
    if type(FCF_FadeInChatFrame) == "function" then
        hooksecurefunc("FCF_FadeInChatFrame", skinChat)
    end
    ns.On("PLAYER_ENTERING_WORLD", skinChat)
    ns.On("ADDON_LOADED", skinChat)
    ns.On("PLAYER_REGEN_ENABLED", skinChat)
end)

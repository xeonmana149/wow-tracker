-- Forever UI - where things sit, and move mode (/fui move).
--
-- ns.Place(frame, key, label, default) puts a frame at its saved spot, or at
-- default = { point, relativePoint, x, y } on the screen. Move mode lays a
-- gold box over each one: drag it, right-click to put it back.

local _, ns = ...

ns.placed = {}

local function uiScale()
    return UIParent:GetEffectiveScale()
end

-- Align the nearest edge or center to the visible Edit Mode grid when its
-- own snap option is on. All arguments and results are UIParent units.
local function snapToGrid(x, y, width, height)
    local manager = EditModeManagerFrame
    if not (type(manager) == "table" and type(manager.IsEditModeActive) == "function"
        and type(manager.IsSnapEnabled) == "function") then return x, y end
    local ok, active, snap = pcall(function() return manager:IsEditModeActive(), manager:IsSnapEnabled() end)
    if not ok or not active or not snap then return x, y end
    local grid = manager.Grid
    if type(grid) ~= "table" or not grid.IsShown or not grid:IsShown() or not grid.GetCenter then return x, y end
    local spacing = grid.gridSpacing
    local gx, gy = grid:GetCenter()
    local scale = uiScale()
    local gridScale = grid:GetEffectiveScale()
    if type(spacing) ~= "number" or spacing <= 0 or type(gx) ~= "number" or type(gy) ~= "number"
        or type(scale) ~= "number" or scale <= 0 or type(gridScale) ~= "number" or gridScale <= 0 then return x, y end
    local k = gridScale / scale
    gx, gy, spacing = gx * k, gy * k, spacing * k
    local threshold = math.min(10, spacing / 4)
    local function axis(center, half, origin)
        local best, distance, line = 0, threshold + 1, nil
        for _, offset in ipairs({ -half, 0, half }) do
            local point = center + offset
            local nearest = origin + math.floor((point - origin) / spacing + 0.5) * spacing
            local delta = nearest - point
            if math.abs(delta) < distance then best, distance, line = delta, math.abs(delta), nearest end
        end
        if distance <= threshold then return center + best, line end
        return center, nil
    end
    local sx, lx = axis(x, width / 2, gx)
    local sy, ly = axis(y, height / 2, gy)
    return sx, sy, lx, ly
end
ns.SnapToGrid = snapToGrid

-- Sizes chosen in Edit Mode (2026-11-26): a multiplier on the element's
-- own scale, saved per element beside its position. Elements whose module
-- already has a size setting (the micro menu) write that setting instead.
local MIN_SCALE, MAX_SCALE = 0.5, 2
local function clampScale(s)
    return math.max(MIN_SCALE, math.min(MAX_SCALE, math.floor(s * 100 + 0.5) / 100))
end

local function userScale(entry)
    if entry.ext then
        local ok, v = pcall(entry.ext.getScale)
        return ok and type(v) == "number" and v > 0 and v or 1
    end
    if entry.scaleOption then return tonumber(ns.Opt(entry.scaleOption)) or 1 end
    local saved = ns.db.scale and ns.db.scale[entry.key]
    return type(saved) == "number" and saved > 0 and saved or 1
end

local function canScale(frame)
    if InCombatLockdown and InCombatLockdown() and frame.IsProtected and frame:IsProtected() then return false end
    return type(frame.SetScale) == "function"
end

local function applyScale(frame, entry)
    -- a module's own size setting is applied by that module (onScale)
    if entry.noResize or entry.scaleOption or not canScale(frame) then return end
    entry.baseScale = entry.baseScale or (frame.GetScale and frame:GetScale()) or 1
    local wanted = entry.baseScale * userScale(entry)
    if frame.GetScale and math.abs((frame:GetScale() or 1) - wanted) < 0.001 then return end
    pcall(frame.SetScale, frame, wanted)
end

local function setAt(frame, entry)
    local pos = ns.db.pos[entry.key]
    applyScale(frame, entry)
    frame:ClearAllPoints()
    if pos and pos.x and pos.y then
        -- saved in screen units (UIParent's scale); the frame may have its own
        local k = uiScale() / (frame:GetEffectiveScale() or 1)
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x * k, pos.y * k)
    else
        local d = entry.default
        frame:SetPoint(d[1], UIParent, d[2], d[3], d[4])
    end
end

-- keep: the game also moves this frame (its own frames), so put it back each time.
-- opts.noResize: a position only (an anchor with no visible size of its own).
-- opts.scaleOption: the module's own size setting, which Edit Mode resizing
-- writes instead (between opts.scaleMin and opts.scaleMax), then calls
-- opts.onScale() so the module applies it.
function ns.Place(frame, key, label, default, keep, opts)
    opts = type(opts) == "table" and opts or {}
    local entry = { frame = frame, key = key, label = label, default = default, keep = keep,
        noResize = opts.noResize, scaleOption = opts.scaleOption, scaleMin = opts.scaleMin,
        scaleMax = opts.scaleMax, onScale = opts.onScale }
    ns.placed[key] = entry
    table.insert(ns.placed, entry)
    if keep then
        ns.Keep(frame, function(f) setAt(f, entry) end)
    else
        setAt(frame, entry)
    end
    -- An element built while Edit Mode is open still gets its handle.
    if ns.moving and ns.ShowMoveBox then ns.ShowMoveBox(entry) end
    return entry
end

-- Another addon's frame that keeps its own position and size (Forever
-- Gold's farming tracker): it gets an Edit Mode handle, and the handle hands
-- moves and resizes back to it. ext = { save(), getScale(), setScale(s),
-- reset() }.
function ns.Adopt(frame, key, label, ext)
    if type(frame) ~= "table" or type(ext) ~= "table" or ns.placed[key] then return ns.placed[key] end
    local entry = { frame = frame, key = key, label = label, ext = ext }
    ns.placed[key] = entry
    table.insert(ns.placed, entry)
    if ns.moving and ns.ShowMoveBox then ns.ShowMoveBox(entry) end
    return entry
end

local function reapply(entry)
    if entry.ext then
        if entry.ext.restore then pcall(entry.ext.restore) end
        return
    end
    if entry.frame.fuiApply then
        applyScale(entry.frame, entry)
        entry.frame.fuiApply()
    else
        setAt(entry.frame, entry)
    end
    if entry.key == "dispel" and not ns.db.pos.dispel then
        local dispel = ns.modules.dispel
        if dispel and dispel.AttachHealing then dispel:AttachHealing() end
    end
end

function ns.ResetPositions()
    wipe(ns.db.pos)
    if type(ns.db.windowPos) == "table" then wipe(ns.db.windowPos) end
    if type(ns.db.scale) == "table" then wipe(ns.db.scale) end
    if type(ns.db.windowScale) == "table" then wipe(ns.db.windowScale) end
    for _, window in pairs(ns.rememberedWindows or {}) do
        if window.IsShown and window:IsShown() and window.fuiRestore then ns.WhenSafe(window.fuiRestore) end
    end
    for _, entry in ipairs(ns.placed) do
        ns.WhenSafe(function() reapply(entry) end)
    end
    ns.Print("everything is back where it started.")
end

-- Blizzard panel windows are opened by the game's panel manager, not the HUD
-- mover. Drag their title bars and remember positions separately from Edit
-- Mode so opening a profession or spellbook does not reset its location.
local movableWindows, windowPanelHook = {}, false
local function otherAddonMovesWindow(frame)
    return frame.ofaMovable and type(OneForAllDB) == "table" and type(OneForAllDB.qol) == "table"
        and OneForAllDB.qol.moveWindows == true
end
local function applyWindowPosition(frame, name)
    local pos = ns.db and ns.db.windowPos and ns.db.windowPos[name]
    if not pos or otherAddonMovesWindow(frame) or frame.fuiWindowMoving then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if type(pos.x) ~= "number" or type(pos.y) ~= "number" then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
end

----------------------------------------------------------------------
-- Resize grips (2026-11-26)
----------------------------------------------------------------------

local function cursorUI()
    if type(GetCursorPosition) ~= "function" then return nil end
    local x, y = GetCursorPosition()
    local scale = uiScale()
    if type(x) ~= "number" or type(y) ~= "number" or type(scale) ~= "number" or scale <= 0 then return nil end
    return x / scale, y / scale
end

-- A small gold corner grip. Dragging it calls onScale(ratio) with how far
-- the cursor has moved from pivot() compared with where the drag began;
-- onDone() runs once on release.
function ns.ScaleGrip(parent, pivot, onStart, onScale, onDone)
    local grip = CreateFrame("Button", nil, parent)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    if grip.SetFrameLevel and parent.GetFrameLevel then grip:SetFrameLevel(parent:GetFrameLevel() + 5) end
    grip:EnableMouse(true)
    local lines = {}
    for i, len in ipairs({ 11, 7, 3 }) do
        local line = grip:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3], 0.85)
        line:SetSize(len, 1)
        line:SetPoint("BOTTOMRIGHT", -1, 1 + (i - 1) * 4)
        lines[i] = line
    end
    grip.lines = lines
    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or (InCombatLockdown and InCombatLockdown()) then return end
        if onStart and onStart() == false then return end
        local cx, cy = cursorUI()
        local px, py = pivot()
        if not (cx and px and type(py) == "number") then return end
        local distance = math.sqrt((cx - px) ^ 2 + (cy - py) ^ 2)
        if distance < 8 then return end
        self.fuiStart = { distance = distance }
    end)
    grip:SetScript("OnUpdate", function(self)
        local start = self.fuiStart
        if not start then return end
        local cx, cy = cursorUI()
        local px, py = pivot()
        if not (cx and px and type(py) == "number") then return end
        onScale(math.sqrt((cx - px) ^ 2 + (cy - py) ^ 2) / start.distance)
    end)
    local function finish(self)
        if not self.fuiStart then return end
        self.fuiStart = nil
        if onDone then onDone() end
    end
    grip:SetScript("OnMouseUp", finish)
    grip:SetScript("OnHide", finish)
    grip:SetScript("OnEnter", function(self)
        for _, line in ipairs(self.lines) do line:SetColorTexture(1, 0.9, 0.55, 1) end
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Drag to resize", 1, 0.82, 0)
            GameTooltip:Show()
        end
    end)
    grip:SetScript("OnLeave", function(self)
        for _, line in ipairs(self.lines) do line:SetColorTexture(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3], 0.85) end
        if GameTooltip then GameTooltip:Hide() end
    end)
    return grip
end

-- Addon windows (the Encyclopedia, Instance Guide, settings...) open where
-- they were last left and at the size they were given, rather than back in
-- the middle of the screen. Positions are the window's top-left corner.
ns.rememberedWindows = {}
function ns.RememberWindow(frame, key, opts)
    if type(frame) ~= "table" or type(key) ~= "string" or frame.fuiRemembered then return end
    opts = type(opts) == "table" and opts or {}
    frame.fuiRemembered = key
    ns.rememberedWindows[key] = frame
    local baseScale = frame.GetScale and frame:GetScale() or 1
    local function saved()
        ns.db.windowPos = ns.db.windowPos or {}
        ns.db.windowScale = ns.db.windowScale or {}
        return ns.db.windowPos[key], ns.db.windowScale[key]
    end
    local function save()
        local left, top = frame:GetLeft(), frame:GetTop()
        if type(left) ~= "number" or type(top) ~= "number" or ns.Secret(left) or ns.Secret(top) then return end
        saved()
        ns.db.windowPos[key] = { x = math.floor(left + 0.5), y = math.floor(top + 0.5) }
        if frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, false) end
    end
    local function restore()
        if InCombatLockdown and InCombatLockdown() and frame.IsProtected and frame:IsProtected() then return end
        local pos, scale = saved()
        local wanted = baseScale * (type(scale) == "number" and scale > 0 and scale or 1)
        if frame.SetScale and math.abs((frame:GetScale() or 1) - wanted) > 0.001 then frame:SetScale(wanted) end
        if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
        end
    end
    frame.fuiRestore = restore
    frame:HookScript("OnDragStop", save)
    frame:HookScript("OnShow", restore)
    if opts.resize ~= false then
        local startScale, leftUI, topUI
        frame.fuiGrip = ns.ScaleGrip(frame, function()
            return leftUI, topUI
        end, function()
            local _, scale = saved()
            startScale = type(scale) == "number" and scale or 1
            local eff, ui = frame:GetEffectiveScale(), uiScale()
            local left, top = frame:GetLeft(), frame:GetTop()
            if type(left) ~= "number" or type(top) ~= "number" or ns.Secret(left) or ns.Secret(top) then
                startScale = nil
                return false
            end
            leftUI, topUI = left * eff / ui, top * eff / ui
        end, function(ratio)
            if not startScale then return end
            local scale = clampScale(startScale * ratio)
            ns.db.windowScale[key] = math.abs(scale - 1) < 0.001 and nil or scale
            frame:SetScale(baseScale * scale)
            -- keep the top-left corner where it was
            local k = uiScale() / frame:GetEffectiveScale()
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftUI * k, topUI * k)
        end, function()
            if startScale then save() end
            startScale = nil
        end)
    end
    if frame:IsShown() then restore() end
end

function ns.MakeWindowMovable(frame, name)
    if type(frame) ~= "table" or type(name) ~= "string" or name == "" or frame.fuiWindowMovable then return end
    if InCombatLockdown and InCombatLockdown() then
        ns.WhenSafe(function() ns.MakeWindowMovable(frame, name) end)
        return
    end
    if frame.IsForbidden and frame:IsForbidden() then return end
    local title = frame.TitleContainer
    if type(title) ~= "table" or type(title.HookScript) ~= "function" or type(frame.SetMovable) ~= "function" then return end
    frame.fuiWindowMovable = true
    movableWindows[name] = frame
    frame:SetMovable(true)
    if title.EnableMouse then title:EnableMouse(true) end
    local close = frame.CloseButton or frame.ClosePanelButton
    if type(close) == "table" and close.SetFrameLevel and title.GetFrameLevel and close.GetFrameLevel
        and close:GetFrameLevel() <= title:GetFrameLevel() then close:SetFrameLevel(title:GetFrameLevel() + 2) end
    title:HookScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or otherAddonMovesWindow(frame) or (InCombatLockdown and InCombatLockdown()) then return end
        frame.fuiWindowMoving = true
        frame:StartMoving()
    end)
    title:HookScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" or not frame.fuiWindowMoving then return end
        frame.fuiWindowMoving = nil
        frame:StopMovingOrSizing()
        if frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, false) end
        local x, y = frame:GetLeft(), frame:GetTop()
        if type(x) == "number" and type(y) == "number" then
            ns.db.windowPos = ns.db.windowPos or {}
            ns.db.windowPos[name] = { x = x, y = y }
        end
    end)
    frame:HookScript("OnShow", function()
        applyWindowPosition(frame, name)
        if C_Timer and C_Timer.After then C_Timer.After(0, function() if frame:IsShown() then applyWindowPosition(frame, name) end end) end
    end)
    frame:HookScript("OnHide", function()
        if frame.fuiWindowMoving then frame.fuiWindowMoving = nil; frame:StopMovingOrSizing() end
    end)
    if not windowPanelHook and type(UpdateUIPanelPositions) == "function" then
        windowPanelHook = true
        hooksecurefunc("UpdateUIPanelPositions", function()
            for windowName, window in pairs(movableWindows) do
                if window.IsShown and window:IsShown() then applyWindowPosition(window, windowName) end
            end
        end)
    end
    if frame.IsShown and frame:IsShown() then applyWindowPosition(frame, name) end
end

----------------------------------------------------------------------
-- Move mode
----------------------------------------------------------------------

local boxes, bar = {}, nil
ns.moveBoxes = boxes
ns.moving = false
local guides
local function showGuides(x, y)
    if not guides then
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:SetAllPoints(UIParent)
        frame:SetFrameStrata("TOOLTIP")
        if frame.EnableMouse then frame:EnableMouse(false) end
        guides = { vertical = frame:CreateTexture(nil, "OVERLAY"), horizontal = frame:CreateTexture(nil, "OVERLAY") }
        for _, line in pairs(guides) do line:SetColorTexture(1, 0.12, 0.1, 0.9) end
    end
    local v, h = guides.vertical, guides.horizontal
    v:SetShown(x ~= nil); h:SetShown(y ~= nil)
    if x then v:ClearAllPoints(); v:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x, 0); v:SetPoint("TOP", UIParent, "TOPLEFT", x, 0); v:SetWidth(1) end
    if y then h:ClearAllPoints(); h:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, y); h:SetPoint("RIGHT", UIParent, "BOTTOMRIGHT", 0, y); h:SetHeight(1) end
end

local function box(entry)
    local b = boxes[entry.key]
    if not b then
        b = CreateFrame("Frame", nil, UIParent)
        b:SetFrameStrata("DIALOG")
        b:SetMovable(true)
        b:EnableMouse(true)
        b:RegisterForDrag("LeftButton")
        b:SetClampedToScreen(true)
        b.fill = b:CreateTexture(nil, "BACKGROUND")
        b.fill:SetAllPoints()
        b.fill:SetColorTexture(ns.C.bright[1], ns.C.bright[2], ns.C.bright[3], 0.18)
        ns.Panel(b, { bright = true, noBg = true })
        b.label = ns.Text(b, 11, ns.C.bright)
        b.label:SetPoint("CENTER")
        -- Resizing (2026-11-26): the corner grip, or the mouse wheel over
        -- the box. The element keeps its center while it changes size.
        if not entry.noResize then
            local function resizeTo(scale)
                scale = math.max(entry.scaleMin or MIN_SCALE, math.min(entry.scaleMax or MAX_SCALE, clampScale(scale)))
                if entry.ext then
                    local ok, err = pcall(entry.ext.setScale, scale)
                    if not ok then ns.Err("resize " .. entry.key, err) end
                    b:ClearAllPoints()
                    b:SetAllPoints(entry.frame)
                    return
                elseif entry.scaleOption then
                    ns.db.opts[entry.scaleOption] = scale
                    if entry.onScale then
                        local ok, err = pcall(entry.onScale, scale)
                        if not ok then ns.Err("resize " .. entry.key, err) end
                    end
                else
                    ns.db.scale = ns.db.scale or {}
                    ns.db.scale[entry.key] = math.abs(scale - 1) < 0.001 and nil or scale
                end
                setAt(entry.frame, entry)
                b:ClearAllPoints()
                b:SetAllPoints(entry.frame)
            end
            local function keepCenter()
                if entry.ext or ns.db.pos[entry.key] then return true end
                local cx, cy = entry.frame:GetCenter()
                local eff, ui = entry.frame:GetEffectiveScale(), uiScale()
                if type(cx) ~= "number" or type(cy) ~= "number" or ns.Secret(cx) or ns.Secret(cy)
                    or type(eff) ~= "number" or type(ui) ~= "number" or ui <= 0 then return false end
                ns.db.pos[entry.key] = { x = cx * eff / ui, y = cy * eff / ui }
                return true
            end
            local startScale
            local extPivotX, extPivotY
            b.grip = ns.ScaleGrip(b, function()
                if entry.ext then return extPivotX, extPivotY end
                local pos = ns.db.pos[entry.key]
                if pos then return pos.x, pos.y end
            end, function()
                if entry.ext then
                    -- external frames grow from their top-left corner
                    local left, top = entry.frame:GetLeft(), entry.frame:GetTop()
                    local eff, ui = entry.frame:GetEffectiveScale(), uiScale()
                    if type(left) ~= "number" or type(top) ~= "number" or ns.Secret(left) or ns.Secret(top) then return false end
                    extPivotX, extPivotY = left * eff / ui, top * eff / ui
                end
                if (entry.key == "healing" and ns.db.healMoveLocked) or not keepCenter() then return false end
                startScale = userScale(entry)
            end, function(ratio)
                if startScale then resizeTo(startScale * ratio) end
            end, function()
                startScale = nil
            end)
            b:EnableMouseWheel(true)
            b:SetScript("OnMouseWheel", function(_, delta)
                if (InCombatLockdown and InCombatLockdown()) or (entry.key == "healing" and ns.db.healMoveLocked) then return end
                if not keepCenter() then return end
                resizeTo(userScale(entry) + (delta > 0 and 0.05 or -0.05))
            end)
            b:SetScript("OnEnter", function(self)
                if not GameTooltip then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(entry.label, 1, 0.82, 0)
                GameTooltip:AddLine("Drag to move. Drag the corner or scroll to resize ("
                    .. math.floor(userScale(entry) * 100 + 0.5) .. "%). Right-click to reset.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        end
        b:SetScript("OnDragStart", function(self)
            if InCombatLockdown and InCombatLockdown() then return end
            if entry.key == "healing" and ns.db.healMoveLocked then
                ns.Print("healing frames are locked; right-click their move handle to unlock.")
                return
            end
            if entry.ext then
                -- the frame moves itself; the handle stays attached to it
                if not pcall(entry.frame.StartMoving, entry.frame) then return end
                self.fuiDragging = true
                return
            end
            local cx, cy = self:GetCenter()
            local width, height = self:GetWidth(), self:GetHeight()
            if type(cx) ~= "number" or type(cy) ~= "number" or type(width) ~= "number" or width <= 0
                or type(height) ~= "number" or height <= 0 then
                self.fuiDragging = nil
                ns.Print("can't move " .. entry.label .. " yet; try again once it is visible.")
                return
            end
            -- SetAllPoints supplies the handle's dimensions via anchors.
            -- Preserve them before clearing those anchors or it becomes a
            -- zero-size frame, with no center to save when dragging stops.
            self:ClearAllPoints()
            self:SetSize(width, height)
            self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
            -- The handle was anchored to the element; detach it first, then
            -- let the element follow the handle while it moves.
            entry.frame:ClearAllPoints()
            entry.frame:SetPoint("CENTER", self, "CENTER", 0, 0)
            self:StartMoving()
            self.fuiDragging = true
        end)
        b:SetScript("OnUpdate", function(self)
            if not self.fuiDragging then return end
            local cx, cy = self:GetCenter()
            local scale = uiScale()
            if type(cx) ~= "number" or type(cy) ~= "number" or type(scale) ~= "number" or scale <= 0 then
                showGuides(nil, nil); return
            end
            local k = (self:GetEffectiveScale() or 1) / scale
            local _, _, gx, gy = snapToGrid(cx * k, cy * k, self:GetWidth() * k, self:GetHeight() * k)
            showGuides(gx, gy)
        end)
        b:SetScript("OnDragStop", function(self)
            if not self.fuiDragging then return end
            self.fuiDragging = nil
            showGuides(nil, nil)
            if entry.ext then
                entry.frame:StopMovingOrSizing()
                local ok, err = pcall(entry.ext.save)
                if not ok then ns.Err("move " .. entry.key, err) end
                return
            end
            -- StopMovingOrSizing can clear/change the anchors before the
            -- client has resolved a new rectangle. Capture the live center
            -- first, then fall back to the post-stop coordinates if needed.
            local cx, cy = self:GetCenter()
            self:StopMovingOrSizing()
            if type(cx) ~= "number" or type(cy) ~= "number" then
                cx, cy = self:GetCenter()
            end
            if type(cx) == "number" and type(cy) == "number" then
                local scale = uiScale()
                if type(scale) == "number" and scale > 0 then
                    local k = (self:GetEffectiveScale() or 1) / scale
                    local x, y = snapToGrid(cx * k, cy * k, self:GetWidth() * k, self:GetHeight() * k)
                    ns.db.pos[entry.key] = { x = x, y = y }
                    ns.WhenSafe(function() reapply(entry) end)
                else
                    ns.Print("couldn't save " .. entry.label .. "'s position; try again.")
                    ns.WhenSafe(function() reapply(entry) end)
                end
            else
                ns.Print("couldn't save " .. entry.label .. "'s position; try again.")
                ns.WhenSafe(function() reapply(entry) end)
            end
            self:ClearAllPoints()
            self:SetAllPoints(entry.frame)
        end)
        b:SetScript("OnMouseUp", function(self, which)
            if which == "RightButton" then
                if entry.key == "healing" and ns.db.healMoveLocked then return end
                if entry.ext then
                    local ok, err = pcall(entry.ext.reset)
                    if not ok then ns.Err("reset " .. entry.key, err) end
                    self:ClearAllPoints()
                    self:SetAllPoints(entry.frame)
                    return
                end
                ns.db.pos[entry.key] = nil
                if ns.db.scale then ns.db.scale[entry.key] = nil end
                if entry.scaleOption then
                    ns.db.opts[entry.scaleOption] = 1
                    if entry.onScale then pcall(entry.onScale, 1) end
                end
                ns.WhenSafe(function() reapply(entry) end)
                self:ClearAllPoints()
                self:SetAllPoints(entry.frame)
            end
        end)
        b:SetScript("OnHide", function(self)
            if self.fuiDragging then
                self.fuiDragging = nil
                showGuides(nil, nil)
                self:StopMovingOrSizing()
                ns.WhenSafe(function()
                    reapply(entry)
                    self:ClearAllPoints()
                    self:SetAllPoints(entry.frame)
                end)
            end
        end)
        boxes[entry.key] = b
    end
    -- Elements that are hidden right now (no group, no dungeon quests...)
    -- still get a dimmer handle, so everything can be laid out at once.
    local shown = entry.frame:IsShown()
    b.label:SetText(shown and entry.label or (entry.label .. " (hidden)"))
    b.fill:SetAlpha(shown and 1 or 0.45)
    b:ClearAllPoints()
    b:SetAllPoints(entry.frame)
    return b
end

-- A handle is only usable when its element has somewhere on screen.
local function measurable(frame)
    local ok, w, h = pcall(function() return frame:GetWidth(), frame:GetHeight() end)
    if not ok or type(w) ~= "number" or type(h) ~= "number" or ns.Secret(w) or ns.Secret(h) then return false end
    if w <= 1 or h <= 1 then return false end
    local okC, cx = pcall(frame.GetCenter, frame)
    return okC and type(cx) == "number" and not ns.Secret(cx)
end

function ns.ShowMoveBox(entry)
    local b = box(entry)
    b:SetShown(ns.moving and measurable(entry.frame))
end

-- Keep each handle's label and visibility in step while Edit Mode is open.
local watched = setmetatable({}, { __mode = "k" })
local function watch(entry)
    local frame = entry.frame
    if watched[frame] or type(frame.HookScript) ~= "function" then return end
    watched[frame] = true
    local function update()
        if ns.moving and ns.placed[entry.key] == entry then ns.ShowMoveBox(entry) end
    end
    frame:HookScript("OnShow", update)
    frame:HookScript("OnHide", update)
    frame:HookScript("OnSizeChanged", update)
end

local function moveBar()
    if bar then
        return bar
    end
    bar = CreateFrame("Frame", nil, UIParent)
    bar:SetFrameStrata("DIALOG")
    bar:SetSize(440, 34)
    bar:SetPoint("TOP", 0, -120)
    ns.Panel(bar)
    bar.text = ns.Text(bar, 12)
    bar.text:SetPoint("LEFT", 12, 0)
    bar.text:SetText("Move mode: drag to move, corner or scroll to resize, right-click to reset.")
    local done = CreateFrame("Button", nil, bar)
    done:SetSize(56, 22)
    done:SetPoint("RIGHT", -6, 0)
    ns.Panel(done, { bright = true })
    done.text = ns.Text(done, 11, ns.C.bright)
    done.text:SetPoint("CENTER")
    done.text:SetText("Done")
    done:SetScript("OnClick", function() ns.ToggleMoveMode(false) end)
    bar.done = done
    return bar
end

local EXTERNAL = {
    ForeverGoldTracker = { "goldTracker", "Farming tracker" },
}

function ns.ToggleMoveMode(on, fromEditMode)
    if on == nil then
        on = not ns.moving
    end
    if on and InCombatLockdown and InCombatLockdown() then
        ns.Print("can't move things in combat.")
        return
    end
    ns.moving = on
    -- Other addons' frames that offer a handle (see ns.Adopt); they may be
    -- built at any time, so look each time Edit Mode opens.
    if on then
        for name, info in pairs(EXTERNAL) do
            local frame = _G[name]
            if type(frame) == "table" and type(frame.fuiExternal) == "table" then
                ns.Adopt(frame, info[1], info[2], frame.fuiExternal)
            end
        end
    end
    for _, entry in ipairs(ns.placed) do
        if on then watch(entry) end
        ns.ShowMoveBox(entry)
    end
    moveBar():SetShown(on and not fromEditMode)
end

-- Blizzard's own Edit Mode remains responsible for native systems. Our
-- independent gold handles are shown alongside it for the addon-owned pieces.
-- Positions are saved immediately by the addon, not in Blizzard's layout.
if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("EditMode.Enter", function()
        ns.ToggleMoveMode(true, true)
    end, ns)
    EventRegistry:RegisterCallback("EditMode.Exit", function()
        if ns.moving then ns.ToggleMoveMode(false, true) end
    end, ns)
end

ns.On("PLAYER_REGEN_DISABLED", function()
    if ns.moving then
        ns.ToggleMoveMode(false)
        ns.Print("move mode closed for combat.")
    end
end)

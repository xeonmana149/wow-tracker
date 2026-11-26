-- Estimated travel time from this character's completed taxi routes.
local _, ns = ...
local F = { pending = nil, active = nil }
ns.FlightTimer = F
local function safe(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok and not ns.Secret(value) then return value end
end
local function now() return safe(GetTime) or 0 end
local function clock(seconds)
    seconds = math.max(0, math.ceil(seconds))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
local function cleanName(value)
    return type(value) == "string" and value ~= "" and not ns.Secret(value) and value or nil
end
function F:Select(origin, destination)
    origin, destination = cleanName(origin), cleanName(destination)
    if destination then self.pending = {origin=origin, destination=destination, selectedAt=now()} end
end
function F:LegacySelection(index)
    local destination = cleanName(safe(TaxiNodeName, index))
    local source
    local count = safe(NumTaxiNodes)
    if type(count) == "number" and not ns.Secret(count) then
        for i=1,count do if safe(TaxiNodeGetType, i) == "CURRENT" then source = cleanName(safe(TaxiNodeName, i)); break end end
    end
    self:Select(source, destination)
end
function F:ModernSelection(mapID, nodeID)
    local nodes = safe(C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap, mapID)
    if type(nodes) ~= "table" then return end
    local origin, destination
    local current = Enum and Enum.FlightPathState and Enum.FlightPathState.Current
    for _, node in ipairs(nodes) do
        if type(node) == "table" and not ns.Secret(node) then
            if not ns.Secret(node.nodeID) and node.nodeID == nodeID then destination = cleanName(node.name) end
            if not ns.Secret(node.state) and current ~= nil and node.state == current then origin = cleanName(node.name) end
        end
    end
    self:Select(origin, destination)
end
function F:Update()
    local riding = safe(UnitOnTaxi, "player")
    if riding == nil then return end
    local t = now()
    if riding and not self.active then
        local p = self.pending
        if p and t - p.selectedAt > 30 then p = nil end
        self.pending = nil
        local key = p and p.origin and p.destination and (p.origin .. "\031" .. p.destination)
        local data = key and ns.db and ns.db.flightTimes and ns.db.flightTimes[key]
        local estimate = type(data) == "table" and tonumber(data.average) or nil
        self.active = {started=t, key=key, destination=p and p.destination, estimate=estimate}
        self.frame:Show()
    elseif not riding and self.active then
        local a = self.active
        local duration = t - a.started
        if a.key and duration >= 5 and duration <= 7200 and ns.db then
            ns.db.flightTimes = ns.db.flightTimes or {}
            local old = ns.db.flightTimes[a.key]
            local previous = type(old) == "table" and tonumber(old.average)
            ns.db.flightTimes[a.key] = {average=previous and (previous * 0.7 + duration * 0.3) or duration,
                samples=type(old) == "table" and (tonumber(old.samples) or 0) + 1 or 1}
        end
        self.active = nil; self.frame:Hide()
    end
    if self.active then
        local a = self.active
        local elapsed = math.max(0, t - a.started)
        self.frame.name:SetText(a.destination and ("Flight to " .. a.destination) or "Flight path")
        self.frame.time:SetText(a.estimate and (elapsed < a.estimate and ("~" .. clock(a.estimate - elapsed) .. " remaining") or "Arriving soon") or (clock(elapsed) .. " elapsed • learning route"))
    end
end
function F:Build()
    if self.frame then return end
    local f = CreateFrame("Frame", "ForeverUIFlightTimer", UIParent)
    self.frame = f; f:SetSize(260, 37); f:SetPoint("TOP", UIParent, "TOP", 0, -160); ns.Panel(f, {edge=0.65})
    f.name = ns.Text(f, 11, ns.C.bright); f.name:SetPoint("TOPLEFT", 8, -5); f.name:SetWidth(244); f.name:SetJustifyH("CENTER")
    f.time = ns.Text(f, 10, ns.C.text); f.time:SetPoint("BOTTOMLEFT", 8, 5); f.time:SetWidth(244); f.time:SetJustifyH("CENTER")
    f:Hide()
    local ticker = CreateFrame("Frame"); self.ticker = ticker
    local accumulated = 0
    ticker:SetScript("OnUpdate", function(_, elapsed)
        accumulated = accumulated + elapsed
        if accumulated >= 1 then accumulated = 0; F:Update() end
    end)
    if type(hooksecurefunc) == "function" then
        if type(TakeTaxiNode) == "function" then hooksecurefunc("TakeTaxiNode", function(index) F:LegacySelection(index) end) end
        if C_TaxiMap and type(C_TaxiMap.TakeTaxiNode) == "function" then
            hooksecurefunc(C_TaxiMap, "TakeTaxiNode", function(mapID, nodeID) F:ModernSelection(mapID, nodeID) end)
        end
    end
    self:Update()
end
ns.On("PLAYER_LOGIN", function() F:Build() end)
ns.OnOptional("PLAYER_CONTROL_LOST", function() if F.frame then F:Update() end end)
ns.OnOptional("PLAYER_CONTROL_GAINED", function() if F.frame then F:Update() end end)

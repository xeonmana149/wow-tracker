-- Apply the requested map-pin zoom once through OpenMap Tweaks' own command.
-- Subsequent /omt pins changes remain the player's choice.
local _, ns = ...

function ns.ConfigureOpenMapQuestPins()
    if not ns.db or ns.db.openMapQuestPinsAdjusted then return end
    local settings = _G.OpenMapTweaksDB
    local command = SlashCmdList and SlashCmdList.OPENMAPTWEAKS
    if type(settings) ~= "table" or type(command) ~= "function" or type(settings.pinZoom) ~= "number" then return end
    if settings.pinZoom > 1 then
        local ok = pcall(command, "pins 1")
        if not ok or settings.pinZoom ~= 1 then return end
    end
    ns.db.openMapQuestPinsAdjusted = true
end

ns.On("PLAYER_ENTERING_WORLD", function() ns.ConfigureOpenMapQuestPins() end)
ns.On("ADDON_LOADED", function(_, name)
    if name == "OpenMap_Tweaks" and C_Timer and C_Timer.After then
        C_Timer.After(0, ns.ConfigureOpenMapQuestPins)
    end
end)

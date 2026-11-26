-- Quest directory: live progress and clearly labelled reference information.
local _, ns = ...
local E = ns.Encyclopedia
local Q = { category = "zone", zoneOffset = 0, offset = 0, detailOffset = 0, collapsed = {}, zoneCollapsed = {}, statusCache = {} }
E.QuestPage = Q
local DETAIL_VIEW = 320 -- height of the scrolling strip of quest detail lines

local categories = {
    {"zone", "By zone"}, {"mine", "My quests"}, {"dungeon", "Dungeons & raids"},
    {"class", "Class quests"}, {"attunement", "Attunements"}, {"profession", "Professions"},
    {"reputation", "Reputation"}, {"pvp", "Battlegrounds"}, {"other", "Other quests"},
    {"group", "Group quests"}, {"repeatable", "Repeatable"},
}
local professions = {alchemy=true, blacksmithing=true, enchanting=true, engineering=true, herbalism=true,
    leatherworking=true, mining=true, skinning=true, tailoring=true, cooking=true, fishing=true, ["first aid"]=true, professions=true}
local classes = {warrior=true,paladin=true,hunter=true,rogue=true,priest=true,shaman=true,mage=true,warlock=true,druid=true}
-- The upstream field called "zone" also contains quest sorts and instance names.
local battlegrounds={["alterac valley"]=true,["arathi basin"]=true,["warsong gulch"]=true}
local otherSorts={["treasure map"]=true,["seasonal"]=true,["darkmoon faire"]=true,["lunar festival"]=true,["midsummer"]=true,["invasion"]=true,["ahn'qiraj war"]=true,["epic"]=true,["legendary"]=true,["special"]=true}
local instanceSorts={["blackfathom deeps"]=true,["blackrock depths"]=true,["blackrock spire"]=true,["blackwing lair"]=true,["dire maul"]=true,["gnomeregan"]=true,["maraudon"]=true,["molten core"]=true,["naxxramas"]=true,["onyxia's lair"]=true,["ragefire chasm"]=true,["razorfen downs"]=true,["razorfen kraul"]=true,["scarlet monastery"]=true,["scholomance"]=true,["shadowfang keep"]=true,["stratholme"]=true,["sunken temple"]=true,["the deadmines"]=true,["the stockade"]=true,["uldaman"]=true,["wailing caverns"]=true,["zul'farrak"]=true,["zul'gurub"]=true,["ahn'qiraj"]=true,["ruins of ahn'qiraj"]=true}
local raidSorts={["blackwing lair"]=true,["molten core"]=true,["naxxramas"]=true,["onyxia's lair"]=true,["zul'gurub"]=true,["ahn'qiraj"]=true,["ruins of ahn'qiraj"]=true}
local reference=ns.IndependentReference or _G.OneForAll
for _,instance in ipairs(reference and reference.DUNGEONS or {}) do
    if type(instance.name)=="string" then local name=instance.name:lower();instanceSorts[name]=true;if instance.raid then raidSorts[name]=true end end
end
local function questSort(zone)
    local value=type(zone)=="string" and zone:lower() or ""
    if professions[value] then return "profession" end
    if classes[value] then return "class" end
    if battlegrounds[value] then return "pvp" end
    if instanceSorts[value] or instanceSorts[value:gsub("^the%s+","")] then return "dungeon" end
    if value=="reputation" then return "reputation" end
    if otherSorts[value] then return "other" end
    return "zone"
end
local function normalName(name) return type(name)=="string" and name:lower():gsub("^the%s+",""):gsub("[^%w]","") or "" end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and not ns.Secret(value) then return value end
end
local function questDB(field, id)
    local db = _G.QuestDB
    if type(db) == "table" and type(id) == "number" then return safeCall(db[field], id) end
end
local function levelFor(entry, field)
    local d = entry.data or {}; local id = tonumber(d.id)
    local value = questDB(field == "level" and "questLevel" or "requiredLevel", id)
    if type(value) == "number" and value > 0 then return value end
    value = tonumber(d[field]); if value and value > 0 then return value end
end
function Q.Status(entry)
    local id = entry and entry.data and tonumber(entry.data.id)
    if not id or id <= 0 then return "Unknown" end
    local cached = Q.statusCache[id]; if cached then return cached end
    local log = C_QuestLog; local completed = log and log.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted
    local validIndex, index = false, nil
    if log and type(log.GetLogIndexForQuestID) == "function" then validIndex, index = pcall(log.GetLogIndexForQuestID, id); if ns.Secret(index) then validIndex=false end end
    if validIndex and type(index) == "number" and index > 0 then
        local status=safeCall(log.IsComplete,id)==true and "Ready to turn in" or "In progress"
        Q.statusCache[id]=status;return status
    end
    local done = safeCall(completed, id)
    if done == true then Q.statusCache[id] = "Completed"; return "Completed" end
    if done == false and validIndex and (index == nil or type(index) == "number") then
        Q.statusCache[id] = "Not recorded"; return "Not recorded"
    end
    return "Unknown"
end
local classBits={WARRIOR=1,PALADIN=2,HUNTER=4,ROGUE=8,PRIEST=16,DEATHKNIGHT=32,SHAMAN=64,MAGE=128,WARLOCK=256,MONK=512,DRUID=1024}
function Q.Faction(entry)
    local side=tostring(entry and entry.data and entry.data.side or ""):lower()
    if side=="h" or side=="horde" then return "Horde" end
    if side=="a" or side=="alliance" then return "Alliance" end
    if side=="both" then return "Both" end
    return "Unknown"
end
-- Reference restrictions are hints, not a guarantee of server-side availability.
function Q.Presentation(entry, status)
    status=status or Q.Status(entry)
    if status=="Completed" then return "Completed", "5ee879" end
    if status=="In progress" or status=="Ready to turn in" then return status, "ffd15a" end
    local d=entry and entry.data or {};local id=tonumber(d.id)
    local side=Q.Faction(entry):lower()
    local faction=safeCall(UnitFactionGroup,"player")
    if type(faction)=="string" and (side=="alliance" or side=="horde") and faction:lower()~=side then
        return "Unavailable (faction)", "a9a9a9", "Restricted to the other faction according to reference data."
    end
    local mask=questDB("requiredClasses",id);local class
    if type(UnitClass)=="function" then local ok,_,token=pcall(UnitClass,"player");if ok and type(token)=="string" and not ns.Secret(token) then class=token end end
    local classBit=class and classBits[class]
    if type(mask)=="number" and mask>0 and classBit and math.floor(mask/classBit)%2==0 then
        return "Unavailable (class)", "a9a9a9", "Another class is required according to QuestieDB reference data."
    end
    local required=levelFor(entry,"required");local level=safeCall(UnitLevel,"player")
    if required and type(level)=="number" and level>0 and level<required then
        return "Requires level "..required, "a9a9a9", "The recorded minimum level is "..required.."; other requirements may also apply."
    end
    if status=="Not recorded" then return "Not completed", "ff6969" end
    return "Unknown", "a9a9a9"
end
local function statusText(entry)
    local label,color,reason=Q.Presentation(entry)
    return "|cff"..color..label.."|r",reason
end
local function inDungeon(entry, selected)
    local zone=entry.data and entry.data.zone
    if selected and type(zone)=="string" and selected=="quest-zone:"..zone then return true end
    local instance=selected and E.byKey[selected]
    if instance and questSort(zone)=="dungeon" and normalName(instance.name)==normalName(zone) then return true end
    local function matches(other) return other.kind == "dungeon" and (not selected or other.key == selected) end
    for _, linked in ipairs(entry.links or {}) do
        if matches(linked) then return true end
        if linked.kind == "quest" then for _, other in ipairs(linked.links or {}) do if matches(other) then return true end end end
    end
    return false
end
local function questText(entry)
    local d = entry.data or {}; local terms = {entry.name or "", d.zone or "", d.starts or "", d.turnin or ""}
    for _, reward in ipairs((d.classic and d.classic.rewards) or {}) do terms[#terms+1] = reward.name or "" end
    for _, reward in ipairs(d.rewardEntries or {}) do terms[#terms+1] = reward.name or "" end
    return table.concat(terms, " "):lower()
end
local function matchesReward(entry, filter)
    if not filter or filter == "all" then return true end
    local seen={}
    local function classify(item)
        if not item or not item.data then return false end
        local d=item.data; local kind=d.itemClass or (d.reference and d.reference.itemClass) or ""
        if filter=="item" then return true end
        if filter=="gear" then return kind=="Armor" or kind=="Weapon" end
        if filter=="recipe" then return kind=="Recipe" end
        return false
    end
    for _,item in ipairs(entry.data.rewardEntries or {}) do if classify(item) then return true end;if item.data then seen[item.data.id]=true end end
    for _,reward in ipairs((entry.data.classic and entry.data.classic.rewards) or {}) do
        if not seen[reward.id] then
            local item=E.byKey["item:"..tostring(reward.id)]
            if filter=="item" or classify(item) then return true end
        end
    end
    return false
end
function Q.Matches(entry, category, zone, filters, query, dungeon)
    if not entry or entry.kind ~= "quest" or entry.category ~= "Quests" then return false end
    local d = entry.data or {}; local z = tostring(d.zone or ""):lower(); filters = filters or {}
    if category == "zone" and zone and tostring(d.zone or "") ~= zone then return false end
    local min, max = tonumber(filters.min), tonumber(filters.max)
    if min or max then local level=levelFor(entry,"level");if not level or min and level < min or max and level > max then return false end end
    local side = tostring(d.side or ""):lower()
    if side == "a" then side = "alliance" elseif side == "h" then side = "horde" end
    if filters.side and filters.side ~= "all" and side ~= filters.side and side ~= "both" then return false end
    if query and query ~= "" and not questText(entry):find(query:lower(), 1, true) then return false end
    if not matchesReward(entry,filters.reward) then return false end
    local status
    if category == "mine" or filters.status and filters.status ~= "all" then status = Q.Status(entry) end
    if filters.status and filters.status ~= "all" then
        if filters.status=="Unavailable" then
            local _,_,reason=Q.Presentation(entry,status);if not reason then return false end
        elseif filters.status=="Not recorded" then
            local _,_,reason=Q.Presentation(entry,status);if status~="Not recorded" or reason then return false end
        elseif filters.status=="Unknown" then
            local _,_,reason=Q.Presentation(entry,status);if status~="Unknown" or reason then return false end
        elseif status ~= filters.status then return false end
    end
    if category == "mine" then return status == "In progress" or status == "Ready to turn in" or status == "Completed" end
    if category == "zone" then return questSort(d.zone)=="zone" end
    if category == "dungeon" then return dungeon and inDungeon(entry,dungeon) or false end
    if category == "class" then return type(d.classes) == "string" and d.classes ~= "" or classes[z] or false end
    if category == "attunement" then return entry.name:lower():find("attunement", 1, true) ~= nil end
    if category == "profession" then return questSort(d.zone)=="profession" end
    if category == "reputation" then return questSort(d.zone)=="reputation" end
    if category == "pvp" or category == "other" then return questSort(d.zone)==category end
    if category == "group" then return d.classic and type(d.classic.suggestedPlayers)=="number" and d.classic.suggestedPlayers>1 or false end
    if category == "repeatable" then return d.repeatable == true end
    return false
end
function Q.BuildInstances(entries)
    local cached=Q.instanceCache
    if cached and cached.entries==entries and cached.version==(Q.zoneVersion or 0) then return cached.rows end
    local groups={Dungeons={},Raids={}};local seen={};local byName={}
    local function record(entry)
        if entry.kind=="dungeon" and not seen[entry.key] then seen[entry.key]=true;local group=entry.data.raid and "Raids" or "Dungeons";groups[group][#groups[group]+1]=entry end
    end
    for _,entry in ipairs(entries or {}) do if entry.kind=="dungeon" then byName[normalName(entry.name)]=entry end end
    for _,entry in ipairs(entries or {}) do if entry.kind=="quest" and entry.category=="Quests" then
        local zone=entry.data and entry.data.zone
        if questSort(zone)=="dungeon" then
            local instance=byName[normalName(zone)] or {kind="dungeon",key="quest-zone:"..zone,name=zone,data={raid=raidSorts[zone:lower()] or false}}
            record(instance)
        end
        for _,related in ipairs(entry.links or {}) do record(related);if related.kind=="quest" then for _,other in ipairs(related.links or {}) do record(other) end end end
    end end
    local rows={}
    for _,group in ipairs({"Dungeons","Raids"}) do local entriesInGroup=groups[group]
        if #entriesInGroup>0 then
            table.sort(entriesInGroup,function(a,b) return a.name:lower()<b.name:lower() end);rows[#rows+1]={group=group}
            if not Q.zoneCollapsed[group] then for _,entry in ipairs(entriesInGroup) do rows[#rows+1]={dungeon=entry.key,name=entry.name} end end
        end
    end
    Q.instanceCache={entries=entries,version=Q.zoneVersion or 0,rows=rows};return rows
end
local function continent(zone)
    local source = ns.IndependentReference or _G.OneForAll
    local mapID = source and source.MAP_IDS and source.MAP_IDS[zone]
    if type(mapID) == "number" and C_Map and type(C_Map.GetMapInfo) == "function" then
        for _ = 1, 8 do
            if mapID == 1414 then return "Kalimdor" elseif mapID == 1415 then return "Eastern Kingdoms" end
            local info = safeCall(C_Map.GetMapInfo, mapID)
            if type(info) ~= "table" or type(info.parentMapID) ~= "number" or info.parentMapID <= 0 or info.parentMapID == mapID then break end
            mapID = info.parentMapID
        end
    end
    return "Other / unclassified"
end
function Q.BuildZones(entries)
    local cached=Q.zoneCache
    if cached and cached.entries==entries and cached.version==(Q.zoneVersion or 0) then return cached.rows,cached.seen end
    local groups, seen = {}, {}
    for _, entry in ipairs(entries or {}) do
        local zone = entry.kind == "quest" and entry.category == "Quests" and entry.data.zone
        if type(zone) == "string" and zone ~= "" and not seen[zone] then
            seen[zone] = true; local group = continent(zone); groups[group] = groups[group] or {}; groups[group][#groups[group]+1] = zone
        end
    end
    local rows = {}
    for _, group in ipairs({"Eastern Kingdoms", "Kalimdor", "Other / unclassified"}) do
        local zones = groups[group]
        if zones and #zones > 0 then
            table.sort(zones); rows[#rows+1] = {group=group}
            if not Q.zoneCollapsed[group] then for _, zone in ipairs(zones) do rows[#rows+1] = {zone=zone} end end
        end
    end
    Q.zoneCache={entries=entries,version=Q.zoneVersion or 0,rows=rows,seen=seen}
    return rows, seen
end

-- OneForAll 6.2.12 zone-level reference (GPLv3; see Attribution). These are
-- suggested zone ranges, not quest requirements or confirmed availability.
local zoneLevels={
    [1411]={1,10},[1412]={1,10},[1438]={1,10},[1439]={10,20},[1413]={10,25},[1442]={15,27},
    [1440]={18,30},[1441]={25,35},[1443]={30,40},[1445]={35,45},[1444]={40,50},[1446]={40,50},
    [1447]={45,55},[1448]={48,55},[1449]={48,55},[1451]={55,60},[1452]={55,60},
    [1429]={1,10},[1426]={1,10},[1420]={1,10},[1436]={10,20},[1432]={10,20},[1421]={10,20},
    [1433]={15,25},[1431]={18,30},[1437]={20,30},[1424]={20,30},[1416]={30,40},[1417]={30,40},
    [1434]={30,45},[1418]={35,45},[1435]={35,45},[1425]={40,50},[1427]={43,50},[1419]={45,55},
    [1428]={50,58},[1422]={51,58},[1423]={53,60},[1430]={55,60},[2521]={1,12},[2665]={1,12},
    [2548]={35,45},[2482]={60,60},
}
-- Starter areas and settlements are often quest-sort names without a map ID.
-- Reuse the parent zone's map rather than showing blank or unrelated art.
local parentZoneMaps={
    ["northshire valley"]=1429,["northshire abbey"]=1429,
    ["coldridge valley"]=1426,["deathknell"]=1420,["shadowglen"]=1438,
    ["valley of trials"]=1411,["red cloud mesa"]=1412,["camp narache"]=1412,
    ["rut'theran village"]=1438,["alcaz island"]=1445,
    ["feathermoon stronghold"]=1444,["booty bay"]=1434,
    ["dalaran"]=1416,["city of dalaran"]=1416,
    -- These places connect multiple zones; the artwork shows one entrance.
    ["timbermaw hold"]=1448,["blackrock mountain"]=1427,["deeprun tram"]=1453,
}
local multiZoneMapNotes={
    ["timbermaw hold"]="Map artwork: Felwood entrance; Timbermaw Hold also connects to other zones.",
    ["blackrock mountain"]="Map artwork: Searing Gorge entrance; Blackrock Mountain also connects to Burning Steppes.",
    ["deeprun tram"]="Map artwork: Stormwind entrance; the tram also connects to Ironforge.",
}
local zoneArtNotes={
    ["dalaran"]="Map artwork: Alterac Mountains, the region containing the City of Dalaran entrance.",
    ["city of dalaran"]="Map artwork: Alterac Mountains, the region containing the City of Dalaran entrance.",
}
local function zoneMapID(zone)
    if type(zone)~="string" then return nil end
    local parent=parentZoneMaps[zone:lower()];if parent then return parent end
    local source=ns.IndependentReference or _G.OneForAll
    local id=source and source.MAP_IDS and source.MAP_IDS[zone]
    if type(id)~="number" or id<=0 then return nil end
    local mapTypes=Enum and Enum.UIMapType
    if not (mapTypes and mapTypes.Micro and mapTypes.Zone and C_Map and type(C_Map.GetMapInfo)=="function") then return id end
    -- Follow only explicit micro-map ancestry; never replace a zone with a continent.
    for _=1,8 do
        local info=safeCall(C_Map.GetMapInfo,id)
        if type(info)~="table" or info.mapType~=mapTypes.Micro or type(info.parentMapID)~="number" or info.parentMapID<=0 or info.parentMapID==id then break end
        local parentInfo=safeCall(C_Map.GetMapInfo,info.parentMapID)
        if type(parentInfo)~="table" or (parentInfo.mapType~=mapTypes.Micro and parentInfo.mapType~=mapTypes.Zone) then break end
        id=info.parentMapID
    end
    return id
end
Q.ZoneMapID=zoneMapID
local function zoneBracket(level)
    if not level then return -1 end
    if level>=60 then return 60 end
    return math.floor(level/10)*10
end
local function bracketLabel(key)
    return key==-1 and "Level unknown" or key==0 and "Levels 1–9" or key==60 and "Level 60+" or ("Levels "..key.."–"..(key+9))
end
local function bracketClosed(key)
    return not Q.zoneBracketClosed or Q.zoneBracketClosed[key] ~= false
end
function Q.BuildZoneTree(entries,filters,query,selectedBracket)
    filters=filters or {}
    local cacheKey=table.concat({tostring(E.entryRevision or 0),tostring(Q.zoneTreeVersion or 0),tostring(Q.statusVersion or 0),tostring(selectedBracket or "all"),tostring(query or ""),tostring(filters.min or ""),tostring(filters.max or ""),tostring(filters.side or ""),tostring(filters.status or ""),tostring(filters.reward or "")},"\031")
    local cached=Q.zoneTreeCache;if cached and cached.entries==entries and cached.key==cacheKey then return cached.rows,cached.nav end
    local groups,counts={},{}
    -- Progress totals describe the entire recorded zone, regardless of the
    -- current search/status filters. Cache them until the quest log changes.
    local progress=Q.zoneProgressCache
    if not progress or progress.entries~=entries or progress.revision~=(E.entryRevision or 0) or progress.statusVersion~=(Q.statusVersion or 0) then
        local totals={}
        for _,quest in ipairs(entries or {}) do
            if Q.Matches(quest,"zone",nil,{},"") then
                local zone=quest.data.zone;if type(zone)~="string" or zone=="" then zone="Unknown zone" end
                local value=totals[zone] or {completed=0,total=0,unknown=0};totals[zone]=value;value.total=value.total+1
                local status=Q.Status(quest);if status=="Completed" then value.completed=value.completed+1 elseif status=="Unknown" then value.unknown=value.unknown+1 end
            end
        end
        progress={entries=entries,revision=E.entryRevision or 0,statusVersion=Q.statusVersion or 0,totals=totals};Q.zoneProgressCache=progress
    end
    for _,entry in ipairs(entries or {}) do
        if Q.Matches(entry,"zone",nil,filters,query) then
            local zone=entry.data.zone;if type(zone)~="string" or zone=="" then zone="Unknown zone" end
            local id=zoneMapID(zone);local multiNote=multiZoneMapNotes[zone:lower()];local note=multiNote or zoneArtNotes[zone:lower()];local levels=not multiNote and id and zoneLevels[id] or nil;local bracket=zoneBracket(levels and levels[1])
            groups[bracket]=groups[bracket] or {};local bucket=groups[bracket][zone]
            if not bucket then bucket={name=zone,mapID=id,levels=levels,mapNote=note,quests={}};groups[bracket][zone]=bucket end
            bucket.quests[#bucket.quests+1]=entry;counts[bracket]=(counts[bracket] or 0)+1
        end
    end
    local keys={};for key in pairs(groups) do keys[#keys+1]=key end
    table.sort(keys,function(a,b) if a==-1 then return false elseif b==-1 then return true else return a<b end end)
    local rows,nav={},{{bracket="all",name="All zones"}}
    for _,key in ipairs(keys) do
        nav[#nav+1]={bracket=key,name=bracketLabel(key),count=counts[key]}
        if selectedBracket==nil or selectedBracket=="all" or selectedBracket==key then
            rows[#rows+1]={heading=bracketLabel(key),bracket=key,count=counts[key]}
            if not bracketClosed(key) then
                local zones={};for _,zone in pairs(groups[key]) do zones[#zones+1]=zone end
                table.sort(zones,function(a,b) return a.name:lower()<b.name:lower() end)
                for _,zone in ipairs(zones) do
                    rows[#rows+1]={zoneHeader=zone.name,mapID=zone.mapID,levels=zone.levels,mapNote=zone.mapNote,count=#zone.quests,progress=progress.totals[zone.name]}
                    if Q.zoneTreeOpen and Q.zoneTreeOpen[zone.name] then
                        table.sort(zone.quests,function(a,b) local x,y=levelFor(a,"level") or 0,levelFor(b,"level") or 0;if x~=y then return x<y end;return a.name:lower()<b.name:lower() end)
                        for _,entry in ipairs(zone.quests) do rows[#rows+1]={entry=entry} end
                    end
                end
            end
        end
    end
    Q.zoneTreeCache={entries=entries,key=cacheKey,rows=rows,nav=nav};return rows,nav
end

-- Draw the game's own map tiles in the small zone thumbnail. Missing art stays
-- blank instead of substituting an unrelated zone or requiring another addon.
local function paintZoneArt(frame,mapID)
    frame.tiles=frame.tiles or {};for _,tile in ipairs(frame.tiles) do tile:Hide() end
    local layers=mapID and C_Map and safeCall(C_Map.GetMapArtLayers,mapID)
    local layer=type(layers)=="table" and layers[1]
    local files=layer and C_Map and safeCall(C_Map.GetMapArtLayerTextures,mapID,1)
    if not (type(layer)=="table" and type(files)=="table" and type(layer.layerWidth)=="number" and type(layer.layerHeight)=="number" and type(layer.tileWidth)=="number" and type(layer.tileHeight)=="number" and layer.layerWidth>0 and layer.layerHeight>0 and layer.tileWidth>0 and layer.tileHeight>0) then frame:Hide();return end
    local cols=math.ceil(layer.layerWidth/layer.tileWidth);local rows=math.ceil(layer.layerHeight/layer.tileHeight)
    if cols*rows>64 then frame:Hide();return end
    local sx,sy=54/layer.layerWidth,33/layer.layerHeight;local used=0
    for row=1,rows do for col=1,cols do
        local file=files[(row-1)*cols+col]
        if file then
            used=used+1;local tile=frame.tiles[used];if not tile then tile=frame:CreateTexture(nil,"ARTWORK");frame.tiles[used]=tile end
            local x,y=(col-1)*layer.tileWidth,(row-1)*layer.tileHeight
            local fw=math.min(1,(layer.layerWidth-x)/layer.tileWidth);local fh=math.min(1,(layer.layerHeight-y)/layer.tileHeight)
            tile:SetTexture(file);tile:SetTexCoord(0,fw,0,fh);tile:SetSize(layer.tileWidth*fw*sx,layer.tileHeight*fh*sy);tile:ClearAllPoints();tile:SetPoint("TOPLEFT",frame,"TOPLEFT",x*sx,-y*sy);tile:Show()
        end
    end end
    frame:SetShown(used>0)
end
Q.PaintZoneArt=paintZoneArt
function Q.BuildRows(entries, category, zone, filters, query, dungeon)
    local groups = {}
    for _, entry in ipairs(entries or {}) do
        if Q.Matches(entry, category, zone, filters, query, dungeon) then
            local lvl = levelFor(entry, "level"); local key = lvl and math.floor(lvl / 10) * 10 or -1
            groups[key] = groups[key] or {}; groups[key][#groups[key]+1] = entry
        end
    end
    local keys = {}; for key in pairs(groups) do keys[#keys+1] = key end
    table.sort(keys, function(a,b) if a == -1 then return false elseif b == -1 then return true else return a < b end end)
    local rows = {}
    for _, key in ipairs(keys) do
        local entriesInGroup = groups[key]
        table.sort(entriesInGroup, function(a,b) local x,y = levelFor(a,"level") or 0, levelFor(b,"level") or 0; if x ~= y then return x < y end return a.name:lower() < b.name:lower() end)
        local label = key == -1 and "Level unknown" or key == 0 and "Levels 1–9" or ("Levels " .. key .. "–" .. (key+9))
        rows[#rows+1] = {heading=label, group=key, count=#entriesInGroup}
        if not Q.collapsed[key] then for _, entry in ipairs(entriesInGroup) do rows[#rows+1] = {entry=entry} end end
    end
    return rows
end
local function npcFor(entry, name, id)
    if type(id)=="number" and id>0 then return E.byKey["npc:"..id] end
    if type(name) ~= "string" or name == "" then return nil end
    name=name:match("^%s*(.-)%s*$")
    local found
    for _, related in ipairs(entry.links or {}) do
        if related.kind == "npc" and related.name:lower() == name:lower() then
            if found and found ~= related then return nil end
            found = related
        end
    end
    if found then return found end
    -- Some quest sources provide a name without linked records. Use a name
    -- only when it identifies one NPC; never guess among duplicate names.
    local cache=Q.npcNames
    if not cache or cache.entries~=E.entries or cache.revision~=E.entryRevision then
        cache={entries=E.entries,revision=E.entryRevision,byName={}}
        for _,npc in ipairs(E.entries or {}) do
            if npc.kind=="npc" and type(npc.name)=="string" then
                local key=npc.name:lower():match("^%s*(.-)%s*$")
                local existing=cache.byName[key]
                if existing==nil then cache.byName[key]=npc
                elseif existing~=npc then cache.byName[key]=false end
            end
        end
        Q.npcNames=cache
    end
    return cache.byName[name:lower()] or nil
end

-- Build this only when an NPC page is opened. Questie provides role-specific
-- IDs when installed; independent records supply the fallback. Generic
-- related-NPC links alone do not prove whether a quest starts or ends there.
function Q.NpcQuests(npc)
    local db=_G.QuestDB
    local cache=Q.npcQuestIndex
    if not cache or cache.entries~=E.entries or cache.revision~=E.entryRevision or cache.db~=db or cache.reference~=ns.NpcQuestRelations
        or cache.started~=(db and db.startedBy) or cache.finished~=(db and db.finishedBy) then
        cache={entries=E.entries,revision=E.entryRevision,db=db,reference=ns.NpcQuestRelations,started=db and db.startedBy,finished=db and db.finishedBy,starts={},turnins={}}
        local function add(bucket,target,quest)
            if not target or target.kind~="npc" or not target.key then return end
            local list=bucket[target.key];if not list then list={};bucket[target.key]=list end
            list[#list+1]=quest
        end
        local function addRole(quest,field,bucket)
            local d=quest.data or {};local id=tonumber(d.id);local info=questDB(field,id)
            local hasSources=false
            if type(info)=="table" then
                for i=1,3 do if type(info[i])=="table" and #info[i]>0 then hasSources=true end end
            end
            if hasSources then
                local seen={}
                for _,npcID in ipairs(type(info[1])=="table" and info[1] or {}) do
                    if type(npcID)=="number" and not ns.Secret(npcID) and npcID>0 and not seen[npcID] then
                        seen[npcID]=true;add(bucket,npcFor(quest,nil,npcID),quest)
                    end
                end
                return
            end
            local refs=ns.NpcQuestRelations and ns.NpcQuestRelations.quests
            local ref=refs and refs[id]
            if type(ref)=="table" and type(ref.name)=="string" and type(quest.name)=="string" and ref.name:lower()==quest.name:lower() then
                local known=field=="startedBy" and ref.startKnown or field=="finishedBy" and ref.turninKnown
                local ids=field=="startedBy" and ref.starts or ref.turnins
                if known then
                    for _,targetID in ipairs(type(ids)=="table" and ids or {}) do add(bucket,npcFor(quest,nil,targetID),quest) end
                    return
                end
            end
            local discovery=d.discovery
            local npcID=discovery and (field=="startedBy" and discovery.giverID or field=="finishedBy" and discovery.turninID)
            if type(npcID)=="number" and npcID>0 then add(bucket,npcFor(quest,nil,npcID),quest);return end
            local name=field=="startedBy" and d.starts or d.turnin
            if type(name)=="string" and name~="" then
                local seen={}
                for part in (name.." / "):gmatch("(.-)%s+/%s+") do
                    local target=npcFor(quest,part)
                    if target and not seen[target.key] then seen[target.key]=true;add(bucket,target,quest) end
                end
            end
        end
        local seen={}
        for _,quest in ipairs(E:CategoryEntries("Quests")) do
            local id=quest.data and tonumber(quest.data.id)
            local key=id and ("id:"..id) or quest.key
            if quest.kind=="quest" and key and not seen[key] and (not id or not E.questByID or not E.questByID[id] or E.questByID[id]==quest) then
                seen[key]=true;addRole(quest,"startedBy",cache.starts);addRole(quest,"finishedBy",cache.turnins)
            end
        end
        -- Also make referenced quests that are absent from the directory
        -- navigable from an NPC. Keep them labelled as reference data.
        local refs=ns.NpcQuestRelations and ns.NpcQuestRelations.quests
        for id,ref in pairs(type(refs)=="table" and refs or {}) do
            if type(id)=="number" and not seen["id:"..id] and type(ref.name)=="string" and ref.name~=""
                and not (E.IsTestName and E.IsTestName(ref.name)) then
                local quest={category="Quests",kind="quest",key="quest:npc-reference:"..id,name=ref.name,
                    data={id=id,level=ref.level,required=ref.required,zone=ref.zone,side=ref.side,
                        reference={provider="QuestieDB snapshot / EverlookDB / Classic quest reference"}},links={}}
                addRole(quest,"startedBy",cache.starts);addRole(quest,"finishedBy",cache.turnins)
            end
        end
        local function sortLists(groups)
            for _,list in pairs(groups) do table.sort(list,function(a,b)
                local al,bl=levelFor(a,"level") or 9999,levelFor(b,"level") or 9999
                if al~=bl then return al<bl end
                return tostring(a.name):lower()<tostring(b.name):lower()
            end) end
        end
        sortLists(cache.starts);sortLists(cache.turnins);Q.npcQuestIndex=cache
    end
    local function includeSnapshot(base, field, role)
        local snapshot=ns.NpcLocationsData
        local npcID=npc and npc.data and tonumber(npc.data.npcID or npc.data.id)
        local recorded=type(snapshot)=="table" and type(snapshot.npcs)=="table" and snapshot.npcs[npcID]
        if type(recorded)~="table" or type(recorded.name)~="string" or not npc or type(npc.name)~="string"
            or recorded.name:lower()~=npc.name:lower() then return base or {} end
        local list,seen={},{}
        for _,quest in ipairs(base or {}) do list[#list+1]=quest;local id=quest.data and tonumber(quest.data.id);if id then seen[id]=true end end
        for _,id in ipairs(type(recorded[field])=="table" and recorded[field] or {}) do
            local row=snapshot.quests and snapshot.quests[id]
            if type(id)=="number" and id>0 and not seen[id] and type(row)=="table" and type(row.name)=="string"
                and row.name~="" and not (E.IsTestName and E.IsTestName(row.name)) then
                local entry=E.questByID and E.questByID[id]
                local matches=not entry or (type(entry.name)=="string" and entry.name:lower()==row.name:lower())
                local info=questDB(role,id);local explicit=false;local allowed=false
                if type(info)=="table" then
                    for i=1,3 do if type(info[i])=="table" and #info[i]>0 then explicit=true end end
                    for _,target in ipairs(type(info[1])=="table" and info[1] or {}) do if target==npcID then allowed=true end end
                end
                if not explicit then
                    local refs=ns.NpcQuestRelations and ns.NpcQuestRelations.quests
                    local ref=refs and refs[id]
                    local known=type(ref)=="table" and type(ref.name)=="string" and ref.name:lower()==row.name:lower()
                        and (field=="starts" and ref.startKnown or field=="turnins" and ref.turninKnown)
                    if known then
                        local ids=field=="starts" and ref.starts or ref.turnins
                        for _,target in ipairs(type(ids)=="table" and ids or {}) do if target==npcID then allowed=true end end
                    else allowed=true end
                end
                if matches and allowed then
                    entry=entry or {category="Quests",kind="quest",key="quest:questiedb-snapshot:"..id,name=row.name,
                        data={id=id,level=row.level,required=row.required,reference={provider="QuestieDB base snapshot"}},links={}}
                    list[#list+1]=entry;seen[id]=true
                end
            end
        end
        return list
    end
    local function sortNpcQuests(list)
        table.sort(list,function(a,b)
            local al,bl=levelFor(a,"level") or 9999,levelFor(b,"level") or 9999
            return al==bl and tostring(a.name):lower()<tostring(b.name):lower() or al<bl
        end)
        return list
    end
    local function includeLive(base, field, role)
        local list, seen = {}, {}
        for _,quest in ipairs(base or {}) do
            list[#list+1]=quest
            local id=quest.data and tonumber(quest.data.id);if id then seen[id]=true end
        end
        local npcID=npc and npc.data and tonumber(npc.data.npcID or npc.data.id)
        local npcdb=_G.NpcDB
        local ids=npcID and type(npcdb)=="table" and safeCall(npcdb[field],npcID)
        if type(ids)~="table" or type(db)~="table" then return sortNpcQuests(list) end
        for _,id in ipairs(ids) do
            if type(id)=="number" and id>0 and not ns.Secret(id) and not seen[id] then
                local info=questDB(role,id);local explicit=false;local matches=false
                if type(info)=="table" then
                    for i=1,3 do if type(info[i])=="table" and #info[i]>0 then explicit=true end end
                    for _,target in ipairs(type(info[1])=="table" and info[1] or {}) do if target==npcID then matches=true end end
                end
                if not explicit or matches then
                    local entry=E.questByID and E.questByID[id]
                    local name=entry and entry.name or questDB("name",id)
                    if type(name)=="string" and name~="" and not (E.IsTestName and E.IsTestName(name)) then
                        entry=entry or {category="Quests",kind="quest",key="quest:questiedb:"..id,name=name,
                            data={id=id,level=questDB("questLevel",id),required=questDB("requiredLevel",id),
                                reference={provider="QuestieDB reference"}},links={}}
                        list[#list+1]=entry;seen[id]=true
                    end
                end
            end
        end
        return sortNpcQuests(list)
    end
    return includeLive(includeSnapshot(cache.starts[npc and npc.key],"starts","startedBy"),"questStarts","startedBy"),
        includeLive(includeSnapshot(cache.turnins[npc and npc.key],"turnins","finishedBy"),"questEnds","finishedBy")
end

-- Only item -> vendor source relations establish shop stock. Generic NPC
-- links can also be drops, quests or crafting links, so do not mix them in.
function Q.NpcSales(npc)
    local items, seen = {}, {}
    if type(npc) ~= "table" then return items end
    for _, entry in ipairs(npc.links or {}) do
        if entry.kind == "item" and entry.key and not seen[entry.key] then
            for _, source in ipairs(entry.data and entry.data.sourceLinks or {}) do
                if source.kind == "Vendor" and source.entry and source.entry.key == npc.key then
                    seen[entry.key] = true
                    items[#items + 1] = entry
                    break
                end
            end
        end
    end
    table.sort(items, function(a, b)
        local x, y = tostring(a.name or ""):lower(), tostring(b.name or ""):lower()
        if x == y then return tostring(a.key) < tostring(b.key) end
        return x < y
    end)
    return items
end

local function questByID(id)
    return E.questByID and E.questByID[id] or nil
end
local function moneyText(amount)
    local native=safeCall(GetCoinTextureString,amount) or safeCall(GetCoinText,amount)
    if type(native)=="string" and native~="" then return native end
    local gold=math.floor(amount/10000);local silver=math.floor(amount/100)%100;local copper=amount%100;local parts={}
    if gold>0 then parts[#parts+1]=gold.."|TInterface\\MoneyFrame\\UI-GoldIcon:0|t" end
    if silver>0 then parts[#parts+1]=silver.."|TInterface\\MoneyFrame\\UI-SilverIcon:0|t" end
    if copper>0 or #parts==0 then parts[#parts+1]=copper.."|TInterface\\MoneyFrame\\UI-CopperIcon:0|t" end
    return table.concat(parts," ")
end
-- City factions are not necessarily in the player's reputation list or in the
-- encyclopedia reward catalog. Names from the client work even before the
-- character meets a faction; these IDs cover common Classic fallbacks.
local factionNames={
    [21]="Booty Bay",[47]="Ironforge",[54]="Gnomeregan Exiles",[59]="Thorium Brotherhood",
    [68]="Undercity",[69]="Darnassus",[72]="Stormwind",[76]="Orgrimmar",[81]="Thunder Bluff",
    [87]="Bloodsail Buccaneers",[92]="Gelkis Clan Centaur",[93]="Magram Clan Centaur",
    [349]="Ravenholdt",[369]="Gadgetzan",[470]="Ratchet",[471]="Wildhammer Clan",
    [509]="The League of Arathor",[510]="The Defilers",[529]="Argent Dawn",[530]="Darkspear Trolls",
    [576]="Timbermaw Hold",[589]="Wintersaber Trainers",[609]="Cenarion Circle",
    [729]="Frostwolf Clan",[730]="Stormpike Guard",[809]="Shen'dralar",[889]="Warsong Outriders",
    [890]="Silverwing Sentinels",[909]="Darkmoon Faire",
}
function Q.FactionName(id)
    local entry=E.byKey["faction:"..tostring(id)]
    if entry and type(entry.name)=="string" and entry.name~="" then return entry.name,entry end
    local data=C_Reputation and safeCall(C_Reputation.GetFactionDataByID,id)
    local name=type(data)=="table" and data.name
    if type(name)=="string" and not ns.Secret(name) and name~="" then return name end
    name=safeCall(GetFactionInfoByID,id)
    if type(name)=="string" and name~="" then return name end
    return factionNames[id] or ("Unknown faction (ID "..tostring(id)..")")
end
function Q.Details(entry)
    if not entry then return {} end
    local d, out, used = entry.data or {}, {}, {}
    local discovered=d.discovery
    if discovered then used[discovered.provider or "EverlookDB client/reference snapshot"]=true end
    local id = tonumber(d.id)
    local function add(text, target, icon, npc)
        -- Large blocks are split at word boundaries so every part can be scrolled into view.
        text = tostring(text or "")
        while #text > 300 do
            local stop = text:sub(1,300):match("^.*()%s") or 300
            out[#out+1] = {text=text:sub(1,stop):gsub("%s+$", ""), target=target, icon=icon, npc=npc}
            text = text:sub(stop+1):gsub("^%s+", ""); icon=nil; npc=nil
        end
        if text ~= "" then out[#out+1] = {text=text, target=target, icon=icon, npc=npc} end
    end
    local function heading(text) out[#out+1] = {heading=text} end
    local status=Q.Status(entry)
    local logIndex = C_QuestLog and safeCall(C_QuestLog.GetLogIndexForQuestID,id)
    local description, summary
    if type(logIndex)=="number" and logIndex>0 and type(GetQuestLogQuestText)=="function" then
        local ok, desc, goal=pcall(GetQuestLogQuestText,logIndex)
        if ok then
            if type(desc)=="string" and not ns.Secret(desc) and desc~="" then description=desc; used["Quest log"]=true end
            if type(goal)=="string" and not ns.Secret(goal) and goal~="" then summary=goal; used["Quest log"]=true end
        end
    end
    heading("GOAL")
    if summary then add(summary) end
    local objectives, source = nil, nil
    if (status == "In progress" or status == "Ready to turn in") and C_QuestLog and type(C_QuestLog.GetQuestObjectives) == "function" then
        local rows = safeCall(C_QuestLog.GetQuestObjectives, id)
        if type(rows) == "table" then
            objectives = {}; for _, o in ipairs(rows) do if type(o) == "table" and type(o.text) == "string" and not ns.Secret(o.text) then objectives[#objectives+1] = o.text end end
            if #objectives > 0 then source = "Quest log" end
        end
    end
    if not source and not summary then
        local rows = questDB("objectivesText", id)
        if type(rows) == "table" then objectives = {}; for _, text in ipairs(rows) do if type(text) == "string" and text ~= "" and not ns.Secret(text) then objectives[#objectives+1] = text end end; if #objectives > 0 then source = "QuestieDB" end end
    end
    if not source and not summary and discovered and type(discovered.goal)=="string" and discovered.goal~="" then objectives,source={discovered.goal},"Cross-checked quest references" end
    if not source and not summary and type(d.objective)=="string" and d.objective~="" then objectives, source = {d.objective}, "Encyclopedia reference" end
    if not source and not summary and d.classic and d.classic.objectives then
        objectives = {}; for _, o in ipairs(d.classic.objectives) do objectives[#objectives+1] = tostring(o.count or 1) .. " × " .. tostring(o.name or "Unknown") end
        if #objectives > 0 then source = "Classic reference" end
    end
    if source then used[source]=true; for _, text in ipairs(objectives) do if text~=summary then add(text) end end
    elseif not summary then add("Goal not recorded yet.") end
    heading("START & TURN-IN")
    local function locations(field, label, fallback)
        local info=questDB(field,id);local added=0;local referenceKnown=false
        if type(info)=="table" then
            for index,kind in ipairs({"npc","object","item"}) do
                local ids=info[index]
                if type(ids)=="table" then for _,sourceID in ipairs(ids) do
                    if type(sourceID)=="number" and sourceID>0 and not ns.Secret(sourceID) then
                        local target=kind=="npc" and npcFor(entry,nil,sourceID) or E.byKey[kind..":"..sourceID];local name=target and target.name
                        if not name and kind=="npc" and type(_G.NpcDB)=="table" then name=safeCall(_G.NpcDB.name,sourceID) end
                        if not name and kind=="npc" and #ids==1 and type(fallback)=="string" and fallback~="" then name=fallback end
                        name=type(name)=="string" and name~="" and name or (kind.." "..sourceID)
                        add(label..": "..name,target,nil,kind=="npc" and (target and target.data or {}) or nil);added=added+1;used["QuestieDB"]=true
                    end
                end end
            end
        end
        if added==0 then
            local refs=ns.NpcQuestRelations and ns.NpcQuestRelations.quests
            local ref=refs and refs[id]
            if type(ref)=="table" and type(ref.name)=="string" and type(entry.name)=="string" and ref.name:lower()==entry.name:lower() then
                referenceKnown=field=="startedBy" and ref.startKnown or field=="finishedBy" and ref.turninKnown
                local ids=field=="startedBy" and ref.starts or ref.turnins
                for _,npcID in ipairs(type(ids)=="table" and ids or {}) do
                    local target=npcFor(entry,nil,npcID)
                    if target then add(label..": "..target.name,target,nil,target.data);added=added+1;used["QuestieDB snapshot / EverlookDB / Classic quest reference"]=true end
                end
            end
        end
        if added==0 and not referenceKnown then
            local snapshot=ns.NpcLocationsData and ns.NpcLocationsData.quests
            local row=snapshot and snapshot[id]
            if type(row)=="table" and type(row.name)=="string" and type(entry.name)=="string" and row.name:lower()==entry.name:lower() then
                local ids=field=="startedBy" and row.starts or row.turnins
                for _,npcID in ipairs(type(ids)=="table" and ids or {}) do
                    local target=npcFor(entry,nil,npcID)
                    if target then add(label..": "..target.name,target,nil,target.data);added=added+1;used["QuestieDB base snapshot"]=true end
                end
            end
        end
        if added==0 then
            local sourceID=discovered and (field=="startedBy" and discovered.giverID or field=="finishedBy" and discovered.turninID)
            local target=npcFor(entry,fallback,sourceID)
            if not target and not sourceID then target=npcFor(entry,fallback) end
            local name=target and target.name or fallback
            add(label..": "..tostring(name or "Not recorded"),target,nil,(target or sourceID) and (target and target.data or {}) or nil)
            if fallback or sourceID then used["Encyclopedia reference"]=true end
        end
    end
    locations("startedBy","Starts",d.starts);locations("finishedBy","Turn in",d.turnin)
    heading("REWARDS")
    local rewardSeen, rewardCount = {}, 0
    for _, reward in ipairs((d.classic and d.classic.rewards) or {}) do
        local target = E.byKey["item:" .. tostring(reward.id)]
        local name = target and target.name or reward.name or ("Item " .. tostring(reward.id))
        add((reward.choice and "Choose: " or "") .. name .. ((reward.count or 1) > 1 and (" ×" .. reward.count) or ""), target, reward.id);used["Classic reference"]=true
        rewardSeen[reward.id] = true; rewardCount = rewardCount + 1
    end
    for _, reward in ipairs(d.rewardEntries or {}) do
        if reward.data and not rewardSeen[reward.data.id] then add(reward.name, reward, reward.data.id);rewardSeen[reward.data.id]=true; rewardCount = rewardCount + 1;used["Encyclopedia reference"]=true end
    end
    if discovered then
        for _,kind in ipairs({"rewards","choices"}) do for _,itemID in ipairs(discovered[kind] or {}) do
            if not rewardSeen[itemID] then
                local target=E.byKey["item:"..tostring(itemID)]
                local name=target and target.name or safeCall(GetItemInfo,itemID) or ("Item "..itemID)
                add((kind=="choices" and "Choose: " or "")..name,target,itemID);rewardSeen[itemID]=true;rewardCount=rewardCount+1
            end
        end end
    end
    if rewardCount == 0 then add("Item rewards not recorded") end
    local liveXP,liveMoney
    if status=="In progress" or status=="Ready to turn in" then
        liveXP=safeCall(GetQuestLogRewardXP,id);if type(liveXP)=="number" and liveXP>0 then add("Experience: "..liveXP.." XP");used["Quest log"]=true end
        liveMoney=safeCall(GetQuestLogRewardMoney,id)
        if type(liveMoney)=="number" and liveMoney>0 then
            local formatted=moneyText(liveMoney)
            add("Money: "..formatted);used["Quest log"]=true
        end
    end
    if discovered and type(discovered.xp)=="number" and discovered.xp>0 and type(liveXP)~="number" then add("Experience: "..discovered.xp.." XP (estimate)") end
    if discovered and type(discovered.money)=="number" and discovered.money>0 and type(liveMoney)~="number" then
        local value=discovered.money;local formatted=moneyText(value)
        add("Money: "..formatted.." (estimate)")
    end
    local reputation=questDB("reputationReward",id)
    if type(reputation)=="table" then for _,reward in ipairs(reputation) do
        if type(reward)=="table" and type(reward[1])=="number" and type(reward[2])=="number" and not ns.Secret(reward[1]) and not ns.Secret(reward[2]) then
            local name,faction=Q.FactionName(reward[1]);add("Reputation: "..name.." "..(reward[2]>0 and "+" or "")..reward[2],faction);used["QuestieDB"]=true
        end
    end end
    if discovered and type(discovered.reputation)=="table" and not (type(reputation)=="table" and #reputation>0) then
        for _,reward in ipairs(discovered.reputation) do
            local target;for _,faction in ipairs(E.entries or {}) do if faction.kind=="faction" and type(faction.name)=="string" and faction.name:lower()==reward.name:lower() then target=faction;break end end
            add("Reputation: "..reward.name.." +"..reward.amount,target)
        end
    end
    if description then heading("DESCRIPTION");add(description) end
    heading("QUEST CHAIN")
    local previous, nextID = {}, questDB("nextQuestInChain", id)
    for _, field in ipairs({"preQuestGroup", "preQuestSingle"}) do
        local ids = questDB(field, id)
        if type(ids) == "table" then for _, value in ipairs(ids) do if type(value) == "number" and value ~= 0 then value=math.abs(value);if not previous[value] then previous[value] = field end end end end
    end
    local hasChain = false; local ids = {}; for value in pairs(previous) do ids[#ids+1]=value end; table.sort(ids)
    for _, value in ipairs(ids) do local target = questByID(value); add((previous[value] == "preQuestGroup" and "Required: " or "Alternative prerequisite: ") .. (target and target.name or ("Quest " .. value)), target); hasChain = true;used["QuestieDB"]=true end
    if not hasChain and d.classic and d.classic.previous then local target=questByID(d.classic.previous); add("Previous: " .. (target and target.name or ("Quest " .. d.classic.previous)), target); hasChain=true;used["Classic reference"]=true end
    if not hasChain and discovered then for _,value in ipairs(discovered.previous or {}) do local target=questByID(value);add("Previous: "..(target and target.name or ("Quest "..value)),target);hasChain=true end end
    local nextSource="QuestieDB"
    if not (type(nextID) == "number" and nextID > 0) then nextID = d.classic and d.classic.next;nextSource="Classic reference" end
    if not (type(nextID) == "number" and nextID > 0) and discovered and discovered.next then nextID=discovered.next[1];nextSource=discovered.provider or "EverlookDB client/reference snapshot" end
    if type(nextID) == "number" and nextID > 0 then local target=questByID(nextID); add("Next: " .. (target and target.name or ("Quest " .. nextID)), target); hasChain=true;used[nextSource]=true end
    if not hasChain then add("Chain information not recorded") end
    out[#out+1] = {heading=(Q.showSources and "− " or "+ ").."ABOUT THIS INFORMATION",toggleSources=true}
    if Q.showSources then
        local names={};for name in pairs(used) do names[#names+1]=name end;table.sort(names)
        add("Sources: "..(#names>0 and table.concat(names,", ") or "None recorded"))
        if discovered and discovered.zoneNote then add(discovered.zoneNote) end
        if discovered and discovered.compared then add("Compared with "..discovered.compared.."; sources can use different quest areas.") end
        if discovered and discovered.disagreements then for _,note in ipairs(discovered.disagreements) do add("Source difference: "..note) end end
        if discovered and discovered.url and discovered.url~="" then add("Quest reference: "..discovered.url) end
        if discovered and discovered.manualSources then for _,url in ipairs(discovered.manualSources) do add("Cross-check: "..url) end end
        add("Reference details may differ in WoW Forever. Quest progress comes from your character's quest log.")
    end
    return out
end

local function button(parent, label, width, height)
    local b=CreateFrame("Button",nil,parent); b:SetSize(width,height); ns.Panel(b,{edge=0.7})
    b.text=ns.Text(b,10,ns.C.text); b.text:SetPoint("LEFT",8,0); b.text:SetWidth(width-16); b.text:SetJustifyH("LEFT"); b.text:SetText(label or "")
    local hover=b:CreateTexture(nil,"HIGHLIGHT"); hover:SetAllPoints(); hover:SetColorTexture(1,0.85,0.48,0.12); b.hover=hover
    return b
end
local function setTip(row, text)
    row:SetScript("OnEnter",function(self)
        if not GameTooltip then return end
        local itemID=self.itemID or (self.target and self.target.kind=="item" and self.target.data and self.target.data.id)
        if itemID and GameTooltip.SetItemByID then
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT");pcall(GameTooltip.SetItemByID,GameTooltip,itemID);GameTooltip:Show()
        elseif self.tip then GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(self.tip);GameTooltip:Show() end
    end)
    row:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
end
function Q:Build(parent)
    local f=CreateFrame("Frame",nil,parent); f:SetPoint("TOPLEFT",18,-122); f:SetSize(1028,420); self.frame=f
    local side=CreateFrame("Frame",nil,f); side:SetPoint("TOPLEFT"); side:SetSize(150,420); ns.Panel(side,{edge=0.5}); f.side=side
    f.categories={}
    for i,spec in ipairs(categories) do
        local b=button(side,spec[2],138,21); b:SetPoint("TOPLEFT",6,-6-(i-1)*23); b:SetScript("OnClick",function() Q.category=spec[1];Q.offset=0;Q.zoneOffset=0;E.current=nil;Q.detailOffset=0;E:Render() end)
        if spec[1]=="attunement" then b.tip="Quests with attunement in their name; other attunement chains may be missing.";setTip(b) end;f.categories[spec[1]]=b
    end
    local title=ns.Text(side,10,ns.C.bright); title:SetPoint("TOPLEFT",8,-260);title:SetText("ZONES");f.zoneTitle=title
    local zoneBox=CreateFrame("Frame",nil,side);zoneBox:SetPoint("TOPLEFT",5,-278);zoneBox:SetSize(128,137);f.zoneBox=zoneBox
    f.zoneRows={}
    for i=1,6 do
        local b=button(zoneBox,"",125,25);b:SetPoint("TOPLEFT",0,-(i-1)*27);b:SetScript("OnClick",function(self)
            if self.bracket~=nil then Q.zoneBracket=self.bracket;Q.offset=0;E.current=nil;Q.detailOffset=0;if type(self.bracket)=="number" then Q.zoneBracketClosed=Q.zoneBracketClosed or {};Q.zoneBracketClosed[self.bracket]=false;Q.zoneTreeVersion=(Q.zoneTreeVersion or 0)+1 end
            elseif self.group then Q.zoneCollapsed[self.group]=not Q.zoneCollapsed[self.group] or nil;Q.zoneVersion=(Q.zoneVersion or 0)+1
            else if self.dungeon then Q.dungeon=self.dungeon;Q.category="dungeon" else Q.zone=self.zone;Q.category="zone" end;Q.offset=0;E.current=nil;Q.detailOffset=0 end;E:Render()
        end);if b.text.SetWordWrap then b.text:SetWordWrap(false) end;setTip(b);f.zoneRows[i]=b
    end
    -- the fixed-row lists glide like the rest of the Encyclopedia (one spare row each)
    E.SmoothList("questZones",{pane=zoneBox,rows=f.zoneRows,step=27,top=0,refresh=function() E:Render() end})
    local filters=CreateFrame("Frame",nil,f);filters:SetPoint("TOPLEFT",166,0);filters:SetSize(862,28);f.filters=filters
    local search=CreateFrame("EditBox",nil,filters,"InputBoxTemplate");search:SetSize(180,23);search:SetPoint("LEFT",4,0);search:SetAutoFocus(false);f.search=search
    search:SetScript("OnTextChanged",function(self) Q.query=self:GetText() or "";Q.offset=0;E:Render() end);search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    local hint=ns.Text(search,10,ns.C.muted);hint:SetPoint("LEFT",4,0);hint:SetText("Search quests...");f.hint=hint
    local lev=ns.Text(filters,10,ns.C.muted);lev:SetPoint("LEFT",192,0);lev:SetText("Level")
    local function levelBox(x,key)
        local edit=CreateFrame("EditBox",nil,filters,"InputBoxTemplate");edit:SetSize(35,23);edit:SetPoint("LEFT",x,0);edit:SetAutoFocus(false)
        if edit.SetNumeric then edit:SetNumeric(true) end;if edit.SetMaxLetters then edit:SetMaxLetters(3) end
        edit:SetScript("OnTextChanged",function(self) if not Q.syncing then Q.filters=Q.filters or {};Q.filters[key]=self:GetText();Q.offset=0;E:Render() end end)
        edit:SetScript("OnEscapePressed",function(self) self:ClearFocus() end);return edit
    end
    f.min=levelBox(226,"min"); f.max=levelBox(270,"max")
    local dash=ns.Text(filters,10,ns.C.muted);dash:SetPoint("LEFT",262,0);dash:SetText("–")
    f.myLevel=button(filters,"My level",70,23);f.myLevel:SetPoint("LEFT",312,0);f.myLevel:SetScript("OnClick",function()
        local level=safeCall(UnitLevel,"player");if type(level)=="number" and level>0 then Q.filters=Q.filters or {};Q.filters.min=tostring(math.max(1,level-5));Q.filters.max=tostring(level+5);Q.offset=0;E:Render() end
    end)
    f.sideFilter=button(filters,"Faction",116,23);f.sideFilter:SetPoint("LEFT",390,0);f.sideFilter:SetScript("OnClick",function()
        Q.filters=Q.filters or {};local values={"all","horde","alliance"};for i,v in ipairs(values) do if (Q.filters.side or "all")==v then Q.filters.side=values[i%#values+1];break end end;Q.offset=0;E:Render()
    end)
    f.statusFilter=button(filters,"Status",130,23);f.statusFilter:SetPoint("LEFT",514,0);f.statusFilter:SetScript("OnClick",function()
        Q.filters=Q.filters or {};local values={"all","In progress","Ready to turn in","Completed","Not recorded","Unavailable","Unknown"};for i,v in ipairs(values) do if (Q.filters.status or "all")==v then Q.filters.status=values[i%#values+1];break end end;Q.offset=0;E:Render()
    end)
    f.clear=button(filters,"Clear",58,23);f.clear:SetPoint("LEFT",652,0);f.clear:SetScript("OnClick",function() Q.filters={};Q.query="";Q.syncing=true;f.search:SetText("");Q.syncing=false;Q.offset=0;E:Render() end)
    f.rewardFilter=button(filters,"All rewards",140,23);f.rewardFilter:SetPoint("LEFT",718,0);f.rewardFilter:SetScript("OnClick",function()
        Q.filters=Q.filters or {};local values={"all","item","gear","recipe"};for i,v in ipairs(values) do if (Q.filters.reward or "all")==v then Q.filters.reward=values[i%#values+1];break end end;Q.offset=0;E:Render()
    end);f.rewardFilter.tip="Filters use recorded rewards. Missing reward data is not proof a quest has no rewards.";setTip(f.rewardFilter)
    local list=CreateFrame("Frame",nil,f);list:SetPoint("TOPLEFT",166,-36);list:SetSize(290,384);ns.Panel(list,{edge=0.5});f.list=list
    f.empty=ns.Text(list,10,ns.C.muted);f.empty:SetPoint("TOPLEFT",10,-12);f.empty:SetWidth(258);f.empty:SetJustifyH("LEFT")
    f.rows={}
    for i=1,10 do
        local b=button(list,"",274,39);b:SetPoint("TOPLEFT",6,-5-(i-1)*41)
        b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetSize(25,25);b.icon:SetPoint("LEFT",5,0);b.icon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\encyclopedia-quest")
        b.zoneArt=CreateFrame("Frame",nil,b);b.zoneArt:SetSize(54,33);b.zoneArt:SetPoint("LEFT",4,0);b.zoneArt:Hide()
        b.factionIcon=b:CreateTexture(nil,"ARTWORK");b.factionIcon:SetSize(16,16);b.factionIcon:SetPoint("TOPRIGHT",-7,-3)
        b.factionIcon2=b:CreateTexture(nil,"ARTWORK");b.factionIcon2:SetSize(16,16);b.factionIcon2:SetPoint("RIGHT",b.factionIcon,"LEFT",-1,0)
        b.factionText=ns.Text(b,9,ns.C.muted);b.factionText:SetPoint("BOTTOMRIGHT",-6,3);b.factionText:SetWidth(52);b.factionText:SetJustifyH("RIGHT")
        b.level=ns.Text(b,9,ns.C.bright);b.level:Hide()
        b.text:ClearAllPoints();b.text:SetPoint("TOPLEFT",36,-4);b.text:SetWidth(228);b.text:SetHeight(22);b.text:SetJustifyH("LEFT");if b.text.SetWordWrap then b.text:SetWordWrap(true) end
        b.sub=ns.Text(b,10,ns.C.muted);b.sub:SetPoint("BOTTOMLEFT",36,3);b.sub:SetWidth(228);b.sub:SetJustifyH("LEFT")
        b:SetScript("OnClick",function(self)
            if self.zoneHeader then Q.zoneTreeOpen=Q.zoneTreeOpen or {};Q.zoneTreeOpen[self.zoneHeader]=not Q.zoneTreeOpen[self.zoneHeader] or nil;Q.zoneTreeVersion=(Q.zoneTreeVersion or 0)+1;E:Render()
            elseif self.bracket~=nil then Q.zoneBracketClosed=Q.zoneBracketClosed or {};Q.zoneBracketClosed[self.bracket]=not bracketClosed(self.bracket);Q.zoneTreeVersion=(Q.zoneTreeVersion or 0)+1;E:Render()
            elseif self.group ~= nil then Q.collapsed[self.group]=not Q.collapsed[self.group] or nil;E:Render()
            elseif self.entry then E.current=self.entry;Q.detailOffset=0;E:Render() end
        end)
        setTip(b);f.rows[i]=b
    end
    E.SmoothList("questList",{pane=list,rows=f.rows,step=41,top=5,refresh=function() E:Render() end})
    local detail=CreateFrame("Frame",nil,f);detail:SetPoint("TOPLEFT",470,-36);detail:SetSize(548,384);ns.Panel(detail,{edge=0.5});f.detail=detail
    f.title=ns.Text(detail,14,ns.C.bright);f.title:SetPoint("TOPLEFT",10,-10);f.title:SetWidth(416);f.title:SetJustifyH("LEFT");if f.title.SetWordWrap then f.title:SetWordWrap(true) end
    f.meta=ns.Text(detail,10,ns.C.muted);f.meta:SetPoint("TOPLEFT",10,-31);f.meta:SetWidth(515);f.meta:SetJustifyH("LEFT")
    f.map=button(detail,"Map",65,24);f.map:SetPoint("TOPRIGHT",-10,-7);f.map:SetScript("OnClick",function() local loc=E.QuestStartLocation(E.current);if loc then E.ShowLocation(loc.mapID,loc.x,loc.y) end end)
    f.measure=ns.Text(detail,10,ns.C.text);f.measure:SetPoint("TOPLEFT",8,-55);f.measure:SetWidth(508);f.measure:SetHeight(0);f.measure:SetAlpha(0);if f.measure.SetWordWrap then f.measure:SetWordWrap(true) end
    f.details={}
    for i=1,16 do
        local b=button(detail,"",526,24);b:SetPoint("TOPLEFT",8,-55)
        b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetSize(23,23);b.icon:SetPoint("LEFT",4,0)
        b.npcBorder=CreateFrame("Frame",nil,b);b.npcBorder:SetAllPoints(b.icon);b.npcBorder:EnableMouse(false);ns.Panel(b.npcBorder,{noBg=true,edge=0.7});b.npcBorder:Hide()
        b.npcBadges={}
        for index,spec in ipairs({{"vendor","npc-role-vendor"},{"trainer","npc-role-trainer"},{"quest","npc-role-quest"}}) do
            local badge=CreateFrame("Frame",nil,b);badge:SetSize(23,23);badge:SetPoint("RIGHT",b,"RIGHT",-4-(index-1)*25,0);badge:EnableMouse(false);ns.Panel(badge,{edge=0.65,alpha=0.9})
            badge.icon=badge:CreateTexture(nil,"OVERLAY");badge.icon:SetPoint("TOPLEFT",1,-1);badge.icon:SetPoint("BOTTOMRIGHT",-1,1);badge.icon:SetTexture("Interface\\AddOns\\ForeverUI\\Art\\"..spec[2]);badge:Hide();b.npcBadges[spec[1]]=badge
        end
        b.text:ClearAllPoints();b.text:SetPoint("LEFT",32,0);b.text:SetWidth(484);b.text:SetJustifyH("LEFT");if b.text.SetWordWrap then b.text:SetWordWrap(true) end
        b:SetScript("OnClick",function(self) if self.toggleSources then Q.showSources=not Q.showSources;E:Render() elseif self.target then E:OpenEntry(self.target) end end);setTip(b);f.details[i]=b
    end
    -- Detail lines differ in height, so they scroll by pixel inside a clipped
    -- strip below the title; a wheel notch glides about one line.
    local clip=CreateFrame("Frame",nil,detail);clip:SetPoint("TOPLEFT",0,-55);clip:SetPoint("TOPRIGHT",0,-55);clip:SetHeight(DETAIL_VIEW)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end;f.detailClip=clip
    for _,b in ipairs(f.details) do b:SetParent(clip) end
    local glide=CreateFrame("Frame",nil,detail);glide:Hide();f.detailGlide=glide
    glide:SetScript("OnUpdate",function(self,elapsed)
        local target=Q.detailTarget;if not target then self:Hide();return end
        local diff=target-(Q.detailPixel or 0)
        if math.abs(diff)<0.5 then Q.detailPixel,Q.detailTarget=target,nil;self:Hide()
        else Q.detailPixel=(Q.detailPixel or 0)+diff*math.min(1,(tonumber(elapsed) or 0)*18) end
        Q:PlaceDetails()
    end)
    local function wheel(_,delta)
        Q.detailTarget=math.max(0,math.min(Q.detailMaxPixel or 0,(Q.detailTarget or Q.detailPixel or 0)-(tonumber(delta) or 0)*36));glide:Show()
    end
    detail.scrollbar=ns.ListScrollbar(detail,function(value) Q.detailPixel,Q.detailTarget=value,nil;glide:Hide();Q:PlaceDetails() end)
    detail:EnableMouseWheel(true);detail:SetScript("OnMouseWheel",wheel)
    for _,b in ipairs(f.details) do b:EnableMouseWheel(true);b:SetScript("OnMouseWheel",wheel) end
    f:Hide();return f
end

function Q:Render()
    local f=self.frame or self:Build(E.window); f:Show()
    E.window.list:Hide();E.window.detail:Hide();E.window.directoryFilters:Hide();E.window.sidebar:Hide()
    self.filters=self.filters or {};local filters=self.filters
    f.hint:SetShown(not self.query or self.query=="")
    self.syncing=true;if f.min:GetText()~=(filters.min or "") then f.min:SetText(filters.min or "") end;if f.max:GetText()~=(filters.max or "") then f.max:SetText(filters.max or "") end;self.syncing=false
    local sides={all="All factions",horde="Horde + Both",alliance="Alliance + Both"};f.sideFilter.text:SetText(sides[filters.side or "all"])
    f.statusFilter.text:SetText(filters.status=="Not recorded" and "Not completed" or filters.status and filters.status~="all" and filters.status or "All statuses")
    local rewardLabels={all="All rewards",item="Item rewards",gear="Gear rewards",recipe="Recipe rewards"};f.rewardFilter.text:SetText(rewardLabels[filters.reward or "all"])
    for id,b in pairs(f.categories) do b.fuiPanel.bright=id==self.category;ns.PaintPanel(b) end
    local directory,entries
    -- only the quests (a few thousand), not every entry (~40,000): Q.Matches
    -- skips everything else anyway, and the walk runs on every quest log change
    local quests=E.CategoryEntries and E:CategoryEntries("Quests") or E.entries
    if self.category=="zone" then entries,directory=self.BuildZoneTree(quests,filters,self.query,self.zoneBracket)
    else directory=self.category=="dungeon" and self.BuildInstances(E.entries) or {};entries=self.BuildRows(quests,self.category,self.zone,filters,self.query,self.dungeon) end
    self.zoneOffset=math.max(0,math.min(self.zoneOffset,math.max(0,#directory-#f.zoneRows)))
    self.zoneOffset=E.SmoothSync(E.smooth.questZones,self.zoneOffset,#directory)
    local showDirectory=self.category=="zone" or self.category=="dungeon";f.zoneBox:SetShown(showDirectory);f.zoneTitle:SetShown(showDirectory);f.zoneTitle:SetText(self.category=="dungeon" and "DUNGEONS & RAIDS" or "LEVEL BRACKETS")
    for i,b in ipairs(f.zoneRows) do local row=directory[i+self.zoneOffset];b:SetShown(showDirectory and row~=nil);b.group=row and row.group;b.zone=row and row.zone;b.dungeon=row and row.dungeon;b.bracket=row and row.bracket
        if row then local label=row.zone or row.name or row.group;b.text:SetText(row.group and ((self.zoneCollapsed[row.group] and "+ " or "– ")..label) or ("  "..label));b.tip=label;b.fuiPanel.bright=row.bracket~=nil and row.bracket==(self.zoneBracket or "all") or row.dungeon and row.dungeon==self.dungeon;ns.PaintPanel(b) end
    end
    f.empty:SetShown(#entries==0);f.empty:SetText(self.category=="dungeon" and not self.dungeon and "Choose a dungeon or raid on the left." or "No recorded quests match these filters.")
    local questCount=0;for _,row in ipairs(entries) do if row.heading then questCount=questCount+row.count end end
    E.window.source:SetText(questCount.." quests  •  Select a quest to see its details.")
    self.offset=math.max(0,math.min(self.offset,math.max(0,#entries-#f.rows)));self.offset=E.SmoothSync(E.smooth.questList,self.offset,#entries)
    for i,b in ipairs(f.rows) do local row=entries[i+self.offset];b:SetShown(row~=nil);b.entry=row and row.entry;b.group=row and row.group;b.bracket=row and row.bracket;b.zoneHeader=row and row.zoneHeader;b.tip=nil
        if row then
            local entry=row.entry;local isZone=row.zoneHeader~=nil;b.icon:SetShown(entry~=nil);b.level:Hide();b.sub:SetShown(entry~=nil or isZone);b.factionText:SetShown(entry~=nil);b.factionIcon:Hide();b.factionIcon2:Hide()
            if isZone then paintZoneArt(b.zoneArt,row.mapID) else b.zoneArt:Hide() end
            local inset=isZone and 64 or entry and 36 or 8
            b.text:ClearAllPoints();b.text:SetPoint("TOPLEFT",inset,-4);b.text:SetWidth(isZone and 200 or entry and 196 or 255)
            b.sub:ClearAllPoints();b.sub:SetPoint("BOTTOMLEFT",inset,3);b.sub:SetWidth(isZone and 200 or 181)
            if entry then
                local display,reason=statusText(entry);local faction=Q.Faction(entry)
                b.text:SetText(entry.name);b.tip=entry.name.."\nFaction: "..(faction=="Both" and "Horde and Alliance" or faction)..(reason and "\n"..reason or "")
                b.sub:SetText("Lv "..tostring(levelFor(entry,"level") or "?").."  •  "..display);b.factionText:SetText(faction)
                if faction=="Horde" or faction=="Both" then b.factionIcon:SetTexture("Interface\\TargetingFrame\\UI-PVP-Horde");b.factionIcon:Show() end
                if faction=="Alliance" then b.factionIcon:SetTexture("Interface\\TargetingFrame\\UI-PVP-Alliance");b.factionIcon:Show()
                elseif faction=="Both" then b.factionIcon2:SetTexture("Interface\\TargetingFrame\\UI-PVP-Alliance");b.factionIcon2:Show() end
            elseif isZone then
                local progress=row.progress or {completed=0,total=row.count,unknown=row.count}
                local count=progress.completed.."/"..progress.total..(progress.unknown>0 and "?" or "")
                b.text:SetText(((self.zoneTreeOpen and self.zoneTreeOpen[row.zoneHeader]) and "− " or "+ ")..row.zoneHeader)
                b.sub:SetText((row.levels and ("Levels "..row.levels[1].."–"..row.levels[2]) or "Level unknown").."  •  "..count.." completed")
                b.tip=row.zoneHeader.."\n"..count.." completed quests in the recorded zone"..(progress.unknown>0 and " (some completion statuses unavailable)" or "")..(row.mapNote and ("\n"..row.mapNote) or row.levels and "\nSuggested zone level." or "").."\nClick to expand quests."
            else local closed=row.bracket~=nil and bracketClosed(row.bracket) or row.group~=nil and self.collapsed[row.group];b.text:SetText((closed and "+ " or "− ")..row.heading.."  •  "..row.count) end
            b.fuiPanel.bright=entry and E.current and E.current.key==entry.key or false;ns.PaintPanel(b)
        end
    end
    local entry=E.current and E.current.kind=="quest" and E.current or nil
    f.title:SetText(entry and entry.name or (self.category=="zone" and not self.zone and "Choose a zone" or self.category=="dungeon" and not self.dungeon and "Choose a dungeon or raid" or "Choose a quest"))
    local d=entry and entry.data or {};local level=entry and levelFor(entry,"level");local required=entry and levelFor(entry,"required")
    f.meta:SetText(entry and ("Level "..tostring(level or "?")..(required and "  •  Requires "..required or "").."  •  "..statusText(entry).."  •  "..(Q.Faction(entry)=="Both" and "Both factions" or Q.Faction(entry)=="Unknown" and "Faction unknown" or Q.Faction(entry))..(d.zone and d.zone~="" and "  •  "..d.zone or "")) or "")
    local loc=entry and E.QuestStartLocation(entry);f.map:SetShown(loc~=nil)
    local details=self.Details(entry);local heights={};local available=DETAIL_VIEW
    for i,row in ipairs(details) do
        f.measure:SetWidth(row.npc and 414 or row.icon and 484 or 508);f.measure:SetText(row.heading or row.text or "")
        local measured=safeCall(f.measure.GetStringHeight,f.measure) or 12
        heights[i]=row.heading and 24 or math.max((row.icon or row.npc) and 34 or 21,math.ceil(measured)+10)
    end
    -- each line's top inside the strip; the strip scrolls by pixel
    local tops,total={},0
    for i=1,#details do tops[i]=total;total=total+heights[i]+2 end
    local maxPixel=math.max(0,total-2-available)
    -- A whole-line offset set elsewhere (0 for a new quest, the tests) is a
    -- request: it moves the strip there once, then the pixel position rules.
    local maximum=0;for i=1,#details do if tops[i]<=maxPixel then maximum=i-1 end end
    if entry~=self.detailEntry or self.detailOffset~=nil then
        local wanted=math.max(0,math.floor(tonumber(self.detailOffset) or 0))
        -- past the last line that can start the view means "the very end"
        self.detailPixel,self.detailTarget=wanted>maximum and maxPixel or tops[wanted+1] or 0,nil;f.detailGlide:Hide()
    end
    self.detailOffset=nil
    self.detailEntry,self.detailMaxPixel=entry,maxPixel
    self.detailLayout={details=details,heights=heights,tops=tops,rev=(self.detailLayout and self.detailLayout.rev or 0)+1}
    self:PlaceDetails()
end

local function fillDetail(b,row,height)
    b.target=row.target;b.itemID=row.icon;b.toggleSources=row.toggleSources;b.tip=row.text
    b:SetHeight(height)
    b.text:SetText(row.heading or row.text or "");local color=row.heading and ns.C.bright or row.target and ns.C.gold or ns.C.text;b.text:SetTextColor(color[1],color[2],color[3])
    b.fuiPanel.noBg=row.npc==nil;b.fuiPanel.bright=false;ns.PaintPanel(b);for lineIndex,line in ipairs(b.fuiPanel.lines) do line:SetShown(row.npc~=nil or (row.heading~=nil and lineIndex==2)) end
    b.hover:SetShown(row.target~=nil or row.toggleSources~=nil)
    local icon;if row.npc then icon=E.NpcTypeIcon(row.npc) elseif row.icon then if C_Item and C_Item.GetItemIconByID then icon=safeCall(C_Item.GetItemIconByID,row.icon) end;if not icon and GetItemIcon then icon=safeCall(GetItemIcon,row.icon) end end
    b.icon:SetShown(icon~=nil);if icon then b.icon:SetTexture(icon) end
    b.npcBorder:SetShown(row.npc~=nil)
    local roles=row.npc and E.NpcRoles(row.npc) or {};local count=0
    for _,key in ipairs({"vendor","trainer","quest"}) do local badge=b.npcBadges[key];badge:SetShown(roles[key] and true or false);if roles[key] then badge:ClearAllPoints();badge:SetPoint("RIGHT",b,"RIGHT",-4-count*25,0);count=count+1 end end
    b.text:ClearAllPoints();b.text:SetPoint("LEFT",icon and 32 or 8,0);b.text:SetWidth((icon and 484 or 508)-count*25);b.text:SetHeight(height-4)
end

-- Places the detail lines for the current pixel position. Gliding calls only
-- this; a line's text and icon are filled again only when it changes slot.
function Q:PlaceDetails()
    local f,layout=self.frame,self.detailLayout;if not f or not layout then return end
    local details,heights,tops=layout.details,layout.heights,layout.tops
    local maxPixel=self.detailMaxPixel or 0
    local pixel=math.max(0,math.min(self.detailPixel or 0,maxPixel));self.detailPixel=pixel
    if self.detailTarget then self.detailTarget=math.max(0,math.min(self.detailTarget,maxPixel)) end
    local first=1;for i=1,#details do if tops[i]<=pixel then first=i else break end end
    self.detailFirst=first
    ns.UpdateListScrollbar(f.detail.scrollbar,math.floor(pixel+0.5),math.floor(maxPixel+0.5))
    for i,b in ipairs(f.details) do
        local index=first+i-1;local row=details[index];local y=row and tops[index]-pixel
        local fits=row~=nil and y<DETAIL_VIEW
        b:SetShown(fits)
        if fits then
            b:ClearAllPoints();b:SetPoint("TOPLEFT",f.detailClip,"TOPLEFT",8,-y)
            if b.fuiDetailIndex~=index or b.fuiDetailRev~=layout.rev then b.fuiDetailIndex,b.fuiDetailRev=index,layout.rev;fillDetail(b,row,heights[index]) end
        else b.fuiDetailIndex=nil;b.target,b.itemID,b.toggleSources,b.tip=nil,nil,nil,nil end
    end
end

-- lands a detail glide at once (the tests)
function Q:FinishScroll()
    if self.detailTarget then self.detailPixel,self.detailTarget=self.detailTarget,nil;if self.frame then self.frame.detailGlide:Hide() end;self:PlaceDetails() end
end

-- These existing independent references include coordinates for profession,
-- weapon and pet trainers, tameable creatures and reputation vendors. Match
-- both ID and name before using one of their positions on an NPC page.
local function independentNpcLocation(entry)
    local source=ns.IndependentReference
    if type(source)~="table" then return nil end
    if not Q.independentNpcLocations or Q.independentNpcLocations.source~=source then
        local cache={source=source,byID={}}
        local function record(id,name,mapID,x,y)
            id,mapID,x,y=tonumber(id),tonumber(mapID),tonumber(x),tonumber(y)
            if not (id and id>0 and type(name)=="string" and name~="" and mapID and mapID>0 and x and y and x>=0 and x<=100 and y>=0 and y<=100) then return end
            local rows=cache.byID[id] or {};cache.byID[id]=rows
            rows[#rows+1]={name=name:lower(),mapID=mapID,x=x,y=y,provider="Independent reference"}
        end
        for _,trainers in pairs(source.PROFESSION_TRAINERS or {}) do
            for _,row in ipairs(trainers) do record(row[1],row[2],row[5],row[6],row[7]) end
        end
        for _,list in pairs(source.PET_TAMES_EXTRA or {}) do
            for _,row in ipairs(list) do record(row.npcID,row.name,row.mapID,row.x,row.y) end
        end
        for _,family in ipairs(source.PET_FAMILIES or {}) do
            for _,row in ipairs(family.tames or {}) do record(row.npcID,row.name,row.mapID,row.x,row.y) end
        end
        for _,row in ipairs(source.PET_RARES or {}) do record(row.npcID,row.name,row.mapID,row.x,row.y) end
        for _,rows in ipairs({source.PET_TRAINERS or {},source.WEAPON_TRAINERS or {}}) do
            for _,row in ipairs(rows) do record(row.npc,row.name,row.map,row.x,row.y) end
        end
        for _,faction in ipairs(source.ARMORY_REPUTATION or {}) do
            for _,row in ipairs(faction.v or {}) do record(row[1],row[2],row[3],row[4],row[5]) end
        end
        Q.independentNpcLocations=cache
    end
    local data=entry and entry.data or {};local id=tonumber(data.npcID or data.id)
    local name=entry and type(entry.name)=="string" and entry.name:lower()
    for _,row in ipairs(Q.independentNpcLocations.byID[id] or {}) do if row.name==name then return row end end
end

-- Only show actual recorded coordinates, never the center of the NPC's zone.
-- Questie's first valid spawn is one known location, not necessarily the only one.
function Q.NpcLocation(entry)
    local d=entry and entry.data or {};local ref=d.npcReference or {}
    local loc=d.location or ref.location
    if type(loc)=="table" and type(loc.mapID)=="number" and type(loc.x)=="number" and type(loc.y)=="number"
        and loc.x>=0 and loc.x<=100 and loc.y>=0 and loc.y<=100 then return loc end
    local id=tonumber(d.npcID or d.id)
    local loader,db=_G.QuestieLoader,_G.NpcDB
    local zones=loader and safeCall(loader.ImportModule,loader,"ZoneDB")
    local dbname=id and type(db)=="table" and safeCall(db.name,id)
    local nameMatches=not dbname or (type(dbname)=="string" and entry and type(entry.name)=="string" and dbname:lower()==entry.name:lower())
    local spawns=id and nameMatches and type(db)=="table" and safeCall(db.spawns,id)
    local areaMaps=ns.NpcQuestRelations and ns.NpcQuestRelations.areaMaps
    if type(spawns)=="table" then
        local areas={};for area in pairs(spawns) do if type(area)=="number" then areas[#areas+1]=area end end;table.sort(areas)
        for _,area in ipairs(areas) do
            local mapID=type(zones)=="table" and safeCall(zones.GetUiMapIdByAreaId,zones,area) or nil
            -- A zero from Questie's map adapter deliberately suppresses some
            -- indoor/unsupported areas; do not override that with a fallback.
            if mapID==nil and type(areaMaps)=="table" then mapID=areaMaps[area] end
            if type(mapID)=="number" and mapID>0 and type(spawns[area])=="table" then
                for _,pos in ipairs(spawns[area]) do
                    if type(pos)=="table" and type(pos[1])=="number" and type(pos[2])=="number" and pos[1]>=0 and pos[1]<=100 and pos[2]>=0 and pos[2]<=100 then
                        return {mapID=mapID,x=pos[1],y=pos[2],provider="QuestieDB"}
                    end
                end
            end
        end
    end
    local refs=ns.NpcQuestRelations and ns.NpcQuestRelations.locations
    if refs and refs[id] then return refs[id] end
    local snapshot=ns.NpcLocationsData and ns.NpcLocationsData.npcs
    local pos=snapshot and snapshot[id]
    if type(pos)=="table" and type(pos.name)=="string" and entry and type(entry.name)=="string"
        and pos.name:lower()==entry.name:lower() and type(pos.mapID)=="number" and pos.mapID>0
        and type(pos.x)=="number" and type(pos.y)=="number" then
        return {mapID=pos.mapID,x=pos.x,y=pos.y,provider="QuestieDB base reference"}
    end
    return independentNpcLocation(entry)
end

local trainerIcons={
    {"leatherwork","INV_Misc_ArmorKit_17"},{"blacksmith","Trade_BlackSmithing"},{"alchemi","Trade_Alchemy"},{"alchemy","Trade_Alchemy"},
    {"enchant","Trade_Engraving"},{"engineer","Trade_Engineering"},{"herbal","Spell_Nature_NatureTouchGrow"},{"mining","Trade_Mining"},{"miner","Trade_Mining"},
    {"skinn","INV_Misc_Pelt_Wolf_01"},{"tailor","Trade_Tailoring"},{"cook","INV_Misc_Food_15"},{"first aid","Spell_Holy_SealOfSacrifice"},{"fish","Trade_Fishing"},
}
function Q.NpcRoleIcon(data)
    local title=type(data.title)=="string" and data.title:lower() or ""
    for _,pair in ipairs(trainerIcons) do if title:find(pair[1],1,true) then return "Interface\\Icons\\"..pair[2] end end
    local roles=E.NpcRoles(data)
    local role=roles.trainer and "trainer" or roles.vendor and "vendor" or roles.quest and "quest"
    return role and ("Interface\\AddOns\\ForeverUI\\Art\\npc-role-"..role) or nil
end

function Q:BuildNpcPane(parent)
    local f=CreateFrame("Frame",nil,parent);f:SetAllPoints(parent);f:SetFrameLevel(parent:GetFrameLevel()+4);self.npcPane=f
    f.portrait=f:CreateTexture(nil,"ARTWORK");f.portrait:SetSize(28,28);f.portrait:SetPoint("TOPLEFT",10,-9)
    f.name=ns.Text(f,15,ns.C.bright);f.name:SetPoint("TOPLEFT",44,-10);f.name:SetWidth(445);f.name:SetJustifyH("LEFT");if f.name.SetWordWrap then f.name:SetWordWrap(false) end
    f.tabs={}
    for i,spec in ipairs({{"quests","Quests"},{"sells","Sells"},{"other","Other links"}}) do
        local b=button(f,spec[2],90,23);b:SetPoint("TOPRIGHT",-10-(3-i)*94,-8)
        b:SetScript("OnClick",function()
            if Q.npcView~=spec[1] then Q.npcOffsets={starts=0,turnins=0} end
            Q.npcView=spec[1];Q:RenderNpc()
        end);f.tabs[spec[1]]=b
    end
    f.roleIcon=f:CreateTexture(nil,"ARTWORK");f.roleIcon:SetSize(20,20);f.roleIcon:SetPoint("TOPLEFT",12,-42)
    f.role=ns.Text(f,11,ns.C.text);f.role:SetPoint("LEFT",f.roleIcon,"RIGHT",7,0);f.role:SetWidth(395);f.role:SetJustifyH("LEFT")
    f.meta=ns.Text(f,10,ns.C.muted);f.meta:SetPoint("TOPRIGHT",-12,-46);f.meta:SetWidth(220);f.meta:SetJustifyH("RIGHT")
    f.location=ns.Text(f,10,ns.C.text);f.location:SetPoint("TOPLEFT",14,-68);f.location:SetWidth(520);f.location:SetJustifyH("LEFT")
    f.map=button(f,"Map",62,22);f.map:SetPoint("TOPRIGHT",-12,-63)
    f.map:SetScript("OnClick",function() if f.position then E.ShowLocation(f.position.mapID,f.position.x,f.position.y) end end)
    f.map.tip="Show one recorded NPC location on the map.";setTip(f.map)
    f.columns={}
    for i,spec in ipairs({{"starts","Starts"},{"turnins","Turn-ins"}}) do
        local c=CreateFrame("Frame",nil,f);c:SetSize(333,230);c:SetPoint("TOPLEFT",12+(i-1)*347,-96);f.columns[spec[1]]=c
        c.title=ns.Text(c,11,ns.C.bright);c.title:SetPoint("TOPLEFT",2,-2);c.title:SetWidth(315);c.title:SetJustifyH("LEFT")
        c.empty=ns.Text(c,10,ns.C.muted);c.empty:SetPoint("TOPLEFT",5,-30);c.empty:SetWidth(305);c.empty:SetJustifyH("LEFT");c.empty:SetText("None recorded.")
        c.rows={}
        for n=1,8 do
            local row=button(c,"",317,27);row:SetPoint("TOPLEFT",2,-23-(n-1)*29)
            row.icon=row:CreateTexture(nil,"ARTWORK");row.icon:SetSize(20,20);row.icon:SetPoint("LEFT",4,0)
            row.text:ClearAllPoints();row.text:SetPoint("LEFT",29,0);row.text:SetWidth(281);row.text:SetJustifyH("LEFT");if row.text.SetWordWrap then row.text:SetWordWrap(false) end
            row:SetScript("OnClick",function(self) if self.entry then E:OpenEntry(self.entry,Q.npcView=="sells" and "Items" or nil) end end);setTip(row);c.rows[n]=row
        end
        E.SmoothList("npcQuest_"..spec[1],{pane=c,rows=c.rows,step=29,top=23,refresh=function() Q:RenderNpc() end})
    end
    f.source=CreateFrame("Frame",nil,f);f.source:SetPoint("BOTTOMLEFT",10,7);f.source:SetPoint("BOTTOMRIGHT",-10,7);f.source:SetHeight(34);ns.Panel(f.source,{edge=0.35,alpha=0.6})
    local heading=ns.Text(f.source,9,ns.C.bright);heading:SetPoint("TOPLEFT",8,-5);heading:SetText("SOURCE & DETAILS")
    f.source.text=ns.Text(f.source,9,ns.C.muted);f.source.text:SetPoint("BOTTOMLEFT",8,5);f.source.text:SetWidth(665);f.source.text:SetJustifyH("LEFT");if f.source.text.SetWordWrap then f.source.text:SetWordWrap(false) end
    f:Hide();return f
end

function Q:RenderNpc()
    local main=E.window;local npc=E.selected=="NPCs" and E.current and E.current.kind=="npc" and E.current or nil
    if not npc then if self.npcPane then self.npcPane:Hide() end;return end
    local f=self.npcPane or self:BuildNpcPane(main.detail)
    if self.npcPaneKey~=npc.key then
        self.npcPaneKey=npc.key
        local starts,turnins=self.NpcQuests(npc)
        self.npcView=(#starts==0 and #turnins==0 and E.NpcRoles(npc.data or {}).vendor) and "sells" or "quests"
        self.npcOffsets={starts=0,turnins=0}
    end
    f:Show();main.detailTitle:Hide();main.detailIcon:Hide();main.detailText:Hide();main.detail.scrollbar:Hide()
    main.relatedTitle:Hide();main.linksPrev:Hide();main.linksNext:Hide();main.linksPage:Hide()
    for _,b in ipairs(main.relatedButtons) do b:Hide() end
    local d=npc.data or {};f.name:SetText(npc.name);f.portrait:SetTexture(E.NpcTypeIcon(d))
    local roles=E.NpcRoles(d);local roleIcon=self.NpcRoleIcon(d);f.roleIcon:SetShown(roleIcon~=nil);if roleIcon then f.roleIcon:SetTexture(roleIcon) end
    f.role:SetText(d.title and d.title~="" and d.title or roles.trainer and "Trainer" or roles.vendor and "Vendor" or roles.quest and "Quest giver" or "Role not recorded")
    f.meta:SetText((d.level and ("Level "..tostring(d.level)) or "Level unknown")..(d.type and ("  •  "..d.type) or ""))
    f.position=self.NpcLocation(npc)
    local zone=d.zone or npc.extra or "Not recorded"
    local map=f.position and C_Map and safeCall(C_Map.GetMapInfo,f.position.mapID)
    if type(map)=="table" and type(map.name)=="string" and not ns.Secret(map.name) and map.name~="" then zone=map.name end
    f.location:SetText("Location: "..tostring(zone)..(f.position and string.format("  %.1f, %.1f",f.position.x,f.position.y) or ""))
    f.map:SetShown(f.position~=nil)
    local provider=d.reference and d.reference.provider or d.npcReference and (d.npcReference.classicOnly and "Classic reference" or "EverlookDB community reference") or "Reference not recorded"
    f.source.text:SetText(tostring(provider).."  •  NPC ID: "..tostring(d.id or d.npcID or "unknown")
        ..(f.position and f.position.provider and ("  •  Location: "..f.position.provider) or "").."  •  May need verification")
    f.tabs.sells:SetShown(roles.vendor or #self.NpcSales(npc)>0)
    for key,b in pairs(f.tabs) do b.fuiPanel.bright=key==(self.npcView or "quests");ns.PaintPanel(b) end
    local starts,turnins=self.NpcQuests(npc)
    if self.npcView=="sells" then
        starts=self.NpcSales(npc);turnins={}
    elseif self.npcView=="other" then
        starts={};for _,entry in ipairs(npc.links or {}) do if entry.kind~="quest" then starts[#starts+1]=entry end end
        turnins={}
    end
    self.npcOffsets=self.npcOffsets or {starts=0,turnins=0}
    for _,spec in ipairs({{"starts",starts},{"turnins",turnins}}) do
        local key,items=spec[1],spec[2];local c=f.columns[key];local single=self.npcView=="other" or self.npcView=="sells";local visible=not single or key=="starts"
        c:SetWidth(single and 680 or 333)
        c:SetShown(visible);c.title:SetWidth(single and 660 or 315)
        c.title:SetText((self.npcView=="sells" and "Sells · reference stock" or self.npcView=="other" and "Other links" or key=="starts" and "Starts" or "Turn-ins").."  •  "..#items)
        self.npcOffsets[key]=E.SmoothSync(E.smooth["npcQuest_"..key],self.npcOffsets[key] or 0,#items)
        c.empty:SetWidth(single and 650 or 305)
        c.empty:SetShown(#items==0);c.empty:SetText(self.npcView=="sells" and "No vendor stock recorded yet." or self.npcView=="other" and "No other links recorded." or "No quests recorded.")
        for i,row in ipairs(c.rows) do
            row:SetWidth(single and 664 or 317);row.text:SetWidth(single and 628 or 281)
            local entry=items[i+self.npcOffsets[key]];row.entry=entry;row:SetShown(visible and entry~=nil)
            if entry then
                local level=entry.kind=="quest" and levelFor(entry,"level")
                row.text:SetText((entry.kind=="quest" and ("Lv "..tostring(level or "?").."  ") or "")..entry.name)
                if not E.EntryIcon(row.icon,entry) then row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark");row.icon:Show() end
                row.tip=entry.name..(self.npcView=="sells" and "\nReference stock; availability may differ in game." or "").."\nClick to open."
            end
        end
    end
end

local render=E.Render
function E:Render(...)
    render(self,...)
    if not self.window then return end
    if self.selected=="Quests" then Q:Render() elseif Q.frame then Q.frame:Hide() end
    Q:RenderNpc()
end
local function questChanged() Q.statusCache={};Q.statusVersion=(Q.statusVersion or 0)+1; if E.selected=="Quests" and E.window and E.window:IsShown() then E:Render() end end
ns.On("QUEST_LOG_UPDATE",questChanged)
ns.On("QUEST_TURNED_IN",questChanged)

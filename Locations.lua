local MS = MapSearch
local Locs = MS.Locations or {
    nodes = nil,
    nodeMap = nil,
    zones = nil,
    players = nil,
    playerZones = nil,
    mapIndices = nil,
    knownNodes = {},
    harborageIndex = nil
}
local Utils = MS.Utils

function Locs:initialise()
end

function Locs:IsZone(zoneId)
    if (zoneId == GetParentZoneId(zoneId)
       or zoneId==267 -- Eyevea
       or zoneId==981 -- The Brass Fortress
       or zoneId==1027 -- Artaeum
       or zoneId==1413 -- Apocrypha
       or zoneId==1463 -- The Scholarium
       )
       and not (
        zoneId == 642 -- The Earth Forge
    --       zoneId==2 -- Tamriel
    --    or zoneId==MS.ZONE_CYRODIIL
       )
       then
        return true
    end
    return false
end

function Locs:setupNodes()
    self.nodes = {}
    self.nodeMap = {}
    self.zones = {}

    local totalNodes = GetNumFastTravelNodes()
    local nodeMap = {}
    for i = 1, totalNodes do
        local known, name, _, _, icon, glowIcon, typePOI, _, isLocked = GetFastTravelNodeInfo(i)

        local zoneIndex, _ = GetFastTravelNodePOIIndicies(i)
        local nodeZoneId = GetParentZoneId(GetZoneId(zoneIndex))

        if not isLocked and name ~= "" and (typePOI == 1 or glowIcon ~= nil) then
            local nodeInfo = self:CreateNodeInfo(i, name, typePOI, nodeZoneId, icon, glowIcon, known)

            table.insert(self.nodes, nodeInfo)
            self.nodeMap[i] = nodeInfo
            self.knownNodes[i] = known
            nodeMap[Utils.bareName(name)] = nodeInfo
        end
    end

    -- Iterate through zones to find correct zones for nodes
    for zoneId = 1, 2000 do
		local zoneName = GetZoneNameById(zoneId)
		if zoneName ~= nil and zoneName ~= ""
           and zoneId ~= 643 -- Imperial Sewers
           and zoneId ~= 1283 -- The Shambles
           then
            zoneName = Utils.FormatSimpleName(zoneName)
			local zoneIndex = GetZoneIndex(zoneId)
			local numPOIs = GetNumPOIs(zoneIndex)
			for poiIndex = 1, numPOIs do
				local poiName = GetPOIInfo(zoneIndex, poiIndex) -- might be wrong - "X" instead of "Dungeon: X"!
				local nodeInfo = nodeMap[Utils.bareName(poiName)]  -- that's why we use BareName to strip prefix
                if poiName ~= "" and nodeInfo ~= nil  then -- teleportable POI
					-- fix "Darkshade Caverns I" being returned for both DC1 and DC2
                    if zoneId==1146 then -- the Dragonguard Sanctuary wayshrine in Tideholm
                        zoneId = 1133 -- should appear in Southern Elsweyr
					elseif zoneId == 57 and poiIndex == 60 then -- zone Deshaan, POI 60 is DC2!
						for k, v in pairs(nodeMap) do
							if v.nodeIndex == 264 then
								nodeInfo = v
							end
						end
					end

                    if not self.zones[zoneId] then
                        if self:IsZone(zoneId) then
                            self.zones[zoneId] = {
                                name = zoneName,
                                zoneId = zoneId,
                                index = zoneIndex,
                                nodes = {}
                            }
                        else
                            MS.log("setupNodes: not zone: zoneId %d name %s", zoneId, zoneName)
                        end
                    end

                    if self.zones[zoneId] then
                        nodeInfo.zoneId = zoneId
                        table.insert(self.zones[zoneId].nodes, nodeInfo)
                    -- else
                    --     MS.log("Locs:setupNodes: node "..i.." '"..nodeInfo.name.."' in non-parent zoneId "..nodeZoneId)
                    end
				end
			end
		end
	end

    self:AddExtraZone(2, 27) -- Sort of true, but called 'Clean Test'
    self:AddExtraZone(1, 439) -- Fake!
end

function Locs:AddExtraZone(zoneId, mapId)
    local name, _, _, zoneIndex, _ = GetMapInfoById(mapId)
    self.zones[zoneId] = {
        name = name,
        zoneId = zoneId,
        index = zoneIndex,
        mapId = mapId,
        nodes = {}
    }
end

function Locs:CreateNodeInfo(i, name, typePOI, nodeZoneId, icon, glowIcon, known)
    if i >= 210 and i <= 212 then
        -- Save this character's alliance's Harborage
        self.harborageIndex = i
    end

    name = Utils.FormatSimpleName(name)

    local nodeInfo = {
        nodeIndex = i,
        name = Utils.DisplayName(name),
        originalName = name,
        type = typePOI,
        zoneId = nodeZoneId,
        glowIcon = glowIcon,
        icon = icon,
        originalIcon = icon
    }

    if typePOI == 6 then
        nodeInfo.poiType = MS.POI_GROUP_DUNGEON
        if i ~= 550 then -- not Infinite Archive
            nodeInfo.suffix = GetString(NAVIGATOR_DUNGEON)
        end
    elseif typePOI == 3 then
        nodeInfo.poiType = MS.POI_TRIAL
        nodeInfo.icon = "esoui/art/tutorial/poi_raiddungeon_complete.dds"
        nodeInfo.suffix = GetString(NAVIGATOR_TRIAL)
    elseif typePOI == 7 then
        nodeInfo.poiType = MS.POI_GROUP_HOUSE
        nodeInfo.owned = (icon:find("poi_group_house_owned") ~= nil)
        nodeInfo.freeRecall = true
    elseif typePOI == 1 then
        nodeInfo.poiType = MS.POI_WAYSHRINE
    elseif glowIcon == "/esoui/art/icons/poi/poi_soloinstance_glow.dds" or
           glowIcon == "/esoui/art/icons/poi/poi_groupinstance_glow.dds" then
        nodeInfo.poiType = MS.POI_ARENA
        nodeInfo.suffix = GetString(NAVIGATOR_ARENA)
    else
        MS.logWarning("Unknown POI " .. i .. " '" .. name .. "' type " .. typePOI .. " " .. (glowIcon or "-"))
    end

    nodeInfo.barename = Utils.bareName(nodeInfo.name)

    if icon == "/esoui/art/icons/icon_missing.dds" then
        nodeInfo.icon = "/esoui/art/crafting/crafting_smithing_notrait.dds"
    end

    if nodeInfo.zoneId == MS.ZONE_CYRODIIL and nodeInfo.poiType == MS.POI_WAYSHRINE then
        nodeInfo.icon = "/esoui/art/crafting/crafting_smithing_notrait.dds"
        nodeInfo.disabled = true
    end

    local traders = MS.Data.traderCounts[i]
    if traders and traders > 0 then
        nodeInfo.traders = traders
    end

    return nodeInfo
end

function Locs:addPlayerZone(zoneId, zoneName, userID, icon, poiType)
    if self.zones[zoneId] and CanJumpToPlayerInZone(zoneId) then
        local zoneInfo = {
            zoneId = zoneId,
            zoneName = Utils.FormatSimpleName(zoneName),
            userID = userID,
            icon = icon,
            poiType = poiType
        }

        self.players[userID] = zoneInfo
        self.playerZones[zoneId] = zoneInfo
    end
end

function Locs:setupPlayerZones()
    if not self.zones then
        self:setupNodes()
    end

    local myID = GetDisplayName()
    self.playerZones = {}
    self.players = {}

    local guildCount = GetNumGuilds()
    for guild = 1, guildCount do
        local guildID = GetGuildId(guild)
        local guildMembers = GetNumGuildMembers(guildID)

        for i=1, guildMembers do
            local userID, _, _, playerStatus = GetGuildMemberInfo(guildID, i)

            if playerStatus ~= PLAYER_STATUS_OFFLINE and userID~=myID then
                local _, _, zoneName, _, _, _, _, zoneId = GetGuildMemberCharacterInfo(guildID, i)
                self:addPlayerZone(zoneId, zoneName, userID, "/esoui/art/menubar/gamepad/gp_playermenu_icon_character.dds", MS.POI_GUILDMATE)
            end
        end
    end

    local friendCount = GetNumFriends()
    for i = 1, friendCount do
		local userID, _, playerStatus, secsSinceLogoff = GetFriendInfo(i)

		if playerStatus ~= PLAYER_STATUS_OFFLINE and secsSinceLogoff == 0 then
            local hasChar, _, zoneName, _, _, _, _, zoneId = GetFriendCharacterInfo(i)
            if hasChar then
                self:addPlayerZone(zoneId, zoneName, userID, "/esoui/art/menubar/gamepad/gp_playermenu_icon_character.dds", MS.POI_FRIEND)
            end
        end
    end
end

function Locs:ClearPlayers()
    self.playerZones = nil
    self.players = nil
end

function Locs:clearKnownNodes()
    self.knownNodes = {}
end

function Locs:isKnownNode(nodeIndex)
    if self.nodes == nil then
        self:setupNodes()
    end

    if self.knownNodes[nodeIndex] ~= nil then
        return self.knownNodes[nodeIndex]
    else
        local known, name, Xcord, Ycord, icon, glowIcon, typePOI, onMap, isLocked = GetFastTravelNodeInfo(nodeIndex)
        self.knownNodes[nodeIndex] = known
        return known
    end
end

function Locs:getNodes()
    if self.nodes == nil then
        self:setupNodes()
    end
    return self.nodes
end

function Locs:getNodeMap()
    if self.nodeMap == nil then
        self:setupNodes()
    end
    return self.nodeMap
end

function Locs:GetNode(nodeIndex)
    if self.nodeMap == nil then
        self:setupNodes()
    end
    return self.nodeMap[nodeIndex]
end

function Locs:getKnownNodes(zoneId)
    if self.nodes == nil then
        self:setupNodes()
    end

    local nodes = {}
    for i = 1, #self.nodes do
        local index = self.nodes[i].nodeIndex
        if self:isKnownNode(index) and (not zoneId or self.nodes[i].zoneId == zoneId) then
            local node = Utils.shallowCopy(self.nodes[i])
            local bookmarked = MS.Bookmarks:contains(self.nodes[i])
            node.known = true
            node.weight = 1.0
            node.bookmarked = bookmarked
            if not node.freeRecall and MS.isRecall then
                node.weight = bookmarked and 0.9 or 0.8
            elseif node.poiType == MS.POI_GROUP_HOUSE and not node.owned then
                node.weight = 0.7
            elseif bookmarked then
                node.weight = 1.2
            end
            if node.traders and node.traders > 0 then
                node.weight = node.weight * (1.0 + 0.02 * node.traders)
            end
            table.insert(nodes, node)
        end
    end
    return nodes
end

function Locs:getHouseList()
    if self.nodes == nil then
        self:setupNodes()
    end

    local nodes = {}
    for i = 1, #self.nodes do
        local index = self.nodes[i].nodeIndex
        if self:isKnownNode(index) and self.nodes[i].poiType == MS.POI_GROUP_HOUSE then
            local node = Utils.shallowCopy(self.nodes[i])
            if MS.Bookmarks:contains(node) then
                node.bookmarked = true
            end
            if not node.owned then
                node.weight = 0.7
            elseif node.bookmarked then
                node.weight = 1.2
            end
            node.known = true
            table.insert(nodes, node)
        end
    end
    return nodes
end

function Locs:getPlayerList()
    if self.players == nil then
        self:setupPlayerZones()
    end

    local nodes = {}
    for userID, info in pairs(self.players) do
        table.insert(nodes, {
            name = userID,
            barename = userID:sub(2), -- remove '@' prefix
            zoneId = info.zoneId,
            zoneName = info.zoneName,
            icon = info.icon,
            suffix = info.zoneName,
            poiType = info.poiType,
            userID = userID,
            known = true
        })
    end

    return nodes
end

function Locs:getPlayerZoneList()
    local nodes = {}

    if self.playerZones == nil then
        self:setupPlayerZones()
    end

    for zoneID, info in pairs(self.playerZones) do
        table.insert(nodes, {
            name = info.zoneName,
            barename = Utils.bareName(info.zoneName),
            zoneId = zoneID,
            zoneName = info.zoneName,
            icon = "Navigator/media/zone.dds",
            suffix = info.userID,
            poiType = info.poiType,
            userID = info.userID,
            known = true
        })
    end

    return nodes
end

function Locs:getPlayerInZone(zoneId)
    if self.playerZones == nil then
        self:setupPlayerZones()
    end

    local info = self.playerZones[zoneId]
    if info then
        return {
            name = info.zoneName,
            barename = Utils.bareName(info.zoneName),
            zoneId = zoneId,
            zoneName = info.zoneName,
            icon = info.icon,
            -- suffix = info.userID,
            poiType = info.poiType,
            userID = info.userID,
            known = true
        }
    else
        return nil
    end
end

function Locs:getZoneList()
    local nodes = {}

    if not self.zones then
        self:setupNodes()
    end

    for zoneID, info in pairs(self.zones) do
        table.insert(nodes, {
            name = info.name,
            barename = Utils.bareName(info.name),
            zoneId = zoneID,
            zoneName = info.name,
            mapId = info.mapId,
            icon = "Navigator/media/zone.dds",
            poiType = MS.POI_ZONE,
            weight = MS.isRecall and 1.0 or 0.9,
            known = true,
            bookmarked = MS.Bookmarks:contains(info)
        })
    end

    return nodes
end

function Locs:getZone(zoneId)
    if not self.zones then
        self:setupNodes()
    end

    local info = self.zones[zoneId]
    return {
        name = info.name,
        barename = Utils.bareName(info.name),
        zoneId = zoneId,
        zoneName = info.name,
        icon = "Navigator/media/zone.dds",
        poiType = MS.POI_ZONE,
        weight = MS.isRecall and 1.0 or 0.9,
        known = true
    }
end

function Locs:getCurrentMapZoneId()
    local mapId = GetCurrentMapId()
    local _, mapType, _, zoneIndex, _ = GetMapInfoById(mapId)
    local zoneId = GetZoneId(zoneIndex)
    -- MS.log("Locs:getCurrentMapZone zoneId = "..zoneId.." type "..mapType)
    if mapType == MAPTYPE_SUBZONE and not self:IsZone(zoneId) then
        zoneId = GetParentZoneId(zoneId)
        -- MS.log("Locs:getCurrentMapZone parent zoneId = "..zoneId)
    end

    return zoneId
end

function Locs:getCurrentMapZone()
    if self.zones == nil then
        self:setupNodes()
    end

    local mapId = GetCurrentMapId()
    local _, mapType, _, zoneIndex, _ = GetMapInfoById(mapId)
    local zoneId = GetZoneId(zoneIndex)
    -- MS.log("Locs:getCurrentMapZone zoneId = "..zoneId.." type "..mapType)
    if zoneId == 2 then
        return {
            zoneId = 2
        }
    elseif mapType == MAPTYPE_SUBZONE and not self:IsZone(zoneId) then
        zoneId = GetParentZoneId(zoneId)
        -- MS.log("Locs:getCurrentMapZone parent zoneId = "..zoneId)
    end
    if not self.zones[zoneId] then
        MS.log("Locs:getCurrentMapZone no info on zoneId "..zoneId)
    end
    return self.zones[zoneId]
end

function Locs:IsHarborage(nodeIndex)
	return nodeIndex >= 210 and nodeIndex <= 212
end

function Locs:GetHarborage()
    for i = 210, 212 do
        if self:isKnownNode(i) then
            return i
        end
    end
    MS.log("Locs:GetHarborage failed to find harborage")
    return 210
end

MapSearch.Locations = Locs

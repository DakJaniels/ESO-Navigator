local MT = MapSearch_MapTab -- from XML
local MS = MapSearch
local Search = MapSearch.Search
local Utils = MapSearch.Utils

MT.filter = MS.FILTER_NONE
MT.needsRefresh = false
MT.collapsedCategories = {}

function MT:queueRefresh()
    if not self.needsRefresh then
        self.needsRefresh = true
        if self.visible and not self.menuOpen then
            zo_callLater(function()
                if self.needsRefresh and self.visible and not self.menuOpen then
                    self:ImmediateRefresh()
                else
                    -- MS.log("MT:queueRefresh: skipped")
                end
            end, 50)
            -- MS.log("MT:queueRefresh: queued")
        else
            -- MS.log("MT:queueRefresh: not queued")
        end
    end
end

function MT:ImmediateRefresh()
    -- MS.log("MT:ImmediateRefresh")
    self:executeSearch(self.searchString, true)
    self.needsRefresh = false
end

function MT:layoutRow(rowControl, data, scrollList)
	local name = data.name
    local tooltipText = data.tooltip
    local icon = data.icon
    local iconColour = data.colour and { data.colour:UnpackRGBA() } or
                       ((data.known and not data.disabled) and { 1.0, 1.0, 1.0, 1.0 } or { 0.51, 0.51, 0.44, 1.0 })

    if data.suffix ~= nil then
        name = name .. " |c82826F" .. data.suffix .. "|r"
    end

	if data.icon ~= nil then
        rowControl.icon:SetColor(unpack(iconColour))
		rowControl.icon:SetTexture(icon)
		rowControl.icon:SetHidden(false)
    else
		rowControl.icon:SetHidden(true)
	end

    rowControl.cost:SetHidden(data.isFree)

	rowControl.keybind:SetHidden(not data.isSelected or not data.known or not self.editControl:HasFocus())
    rowControl.bg:SetHidden(not data.isSelected)
    if data.isSelected then
        rowControl.label:SetAnchor(TOPRIGHT, rowControl.keybind, TOPLEFT, -4, -1)
    else
        rowControl.label:SetAnchor(TOPRIGHT, rowControl, TOPRIGHT, -4, 0)
    end

	rowControl.label:SetText(name)

	if data.isSelected and data.known and not data.disabled then
		rowControl.label:SetColor(ZO_SELECTED_TEXT:UnpackRGBA())
    elseif data.colour ~= nil and not data.disabled then
        MapSearch.colour = data.colour
		rowControl.label:SetColor(data.colour:UnpackRGBA())
    elseif data.known and not data.disabled then
		rowControl.label:SetColor(ZO_NORMAL_TEXT:UnpackRGBA())
    else
		rowControl.label:SetColor(0.51, 0.51, 0.44, 1.0)
	end

    rowControl:SetHandler("OnMouseEnter", function(rc)
        if tooltipText then
            ZO_Tooltips_ShowTextTooltip(rc, LEFT, tooltipText)
        end
    end)
    rowControl:SetHandler("OnMouseExit", function(_)
        ZO_Tooltips_HideTextTooltip()
        if data.isSelected and data.known and not data.disabled then
            rowControl.label:SetColor(ZO_SELECTED_TEXT:UnpackRGBA())
        end
    end )
end

function MT:showFilterControl(text)
    self.filterControl:SetHidden(false)
    self.filterControl:SetText("|u6:6::"..text.."|u")
    self.editControl:SetAnchor(TOPLEFT, self.filterControl, TOPRIGHT, 2, -1)
end

function MT:hideFilterControl()
    self.filterControl:SetHidden(true)
    self.editControl:SetAnchor(TOPLEFT, self.searchControl, TOPLEFT, 4, -1)
end

function MT:updateFilterControl()
    if self.filter == MS.FILTER_NONE then
        self:hideFilterControl()
        return
    elseif self.filter == MS.FILTER_PLAYERS then
        self:showFilterControl('Players')
    elseif self.filter == MS.FILTER_HOUSES then
        self:showFilterControl('Houses')
    end
end

function MT:layoutCategoryRow(rowControl, data, scrollList)
	rowControl.label:SetText(data.name)
end

function MT:layoutHintRow(rowControl, data, scrollList)
	rowControl.label:SetText(data.hint or "-")
end

local function jumpToPlayer(node)
    local userID, poiType, zoneId, zoneName = node.userID, node.poiType, node.zoneId, node.zoneName
    local Locs = MapSearch.Locations

    Locs:setupPlayerZones()

    if not Locs.players[userID] or Locs.players[userID].zoneId ~= zoneId then
        -- Player has disappeared or moved!
        CHAT_SYSTEM:AddMessage(zo_strformat(GetString(NAVIGATOR_PLAYER_NOT_IN_ZONE), userID, zoneName))

        if Locs.playerZones[zoneId] then
            node = Locs.playerZones[zoneId]
            userID, poiType, zoneId, zoneName = node.userID, node.poiType, node.zoneId, node.zoneName
        else
            -- Eeek! Refresh the search results and finish
            MT:buildScrollList()
            return
        end
    end

    CHAT_SYSTEM:AddMessage(zo_strformat(GetString(NAVIGATOR_TRAVELING_TO_ZONE_VIA_PLAYER), zoneName, userID))
    SCENE_MANAGER:Hide("worldMap")

    if poiType == MS.POI_FRIEND then
        JumpToFriend(userID)
    elseif poiType == MS.POI_GUILDMATE then
        JumpToGuildMember(userID)
    end
end

function MT:jumpToNode(node)
    if not node.known or node.disabled then
        return
    end

    local isRecall = MapSearch.isRecall
	local nodeIndex,name,refresh,clicked = node.nodeIndex,node.originalName,node.refresh,node.clicked

    ZO_Dialogs_ReleaseDialog("FAST_TRAVEL_CONFIRM")
	ZO_Dialogs_ReleaseDialog("RECALL_CONFIRM")

    if node.poiType == MS.POI_FRIEND or node.poiType == MS.POI_GUILDMATE then
        jumpToPlayer(node)
        return
    end

	name = name or select(2, MapSearch.Wayshrine.Data.GetNodeInfo(nodeIndex)) -- just in case
	local id = (isRecall == true and "RECALL_CONFIRM") or "FAST_TRAVEL_CONFIRM"
	if isRecall == true then
		local _, timeLeft = GetRecallCooldown()
		if timeLeft ~= 0 then
			local text = zo_strformat(SI_FAST_TRAVEL_RECALL_COOLDOWN, name, ZO_FormatTimeMilliseconds(timeLeft, TIME_FORMAT_STYLE_DESCRIPTIVE, TIME_FORMAT_PRECISION_SECONDS))
		    ZO_Alert(UI_ALERT_CATEGORY_ERROR, SOUNDS.NEGATIVE_CLICK, text)
			return
		end
	end
	ZO_Dialogs_ShowPlatformDialog(id, {nodeIndex = nodeIndex}, {mainTextParams = {name}})
end

local function weightComparison(x, y)
    if x.weight ~= y.weight then
        return x.weight > y.weight
    end
	return (x.barename or x.name) < (y.barename or y.name)
end

local function nameComparison(x, y)
	return (x.barename or x.name) < (y.barename or y.name)
end

local function addDeveloperTooltip(nodeData)
    local items = {
        "bareName='" .. (nodeData.barename or '-').."'",
        "searchName='" .. Utils.SearchName(nodeData.originalName or nodeData.name or '-').."'",
        "weight="..(nodeData.weight or 0)
    }
    if nodeData.nodeIndex then
        table.insert(items, "nodeIndex="..(nodeData.nodeIndex or "-"))
    end
    if nodeData.zoneId then
        table.insert(items, "zoneId="..(nodeData.zoneId or "-"))
    end
    if nodeData.tooltip then
        table.insert(items, 1, nodeData.tooltip)
    end

    nodeData.tooltip = table.concat(items, "; ")
end

local function buildCategoryHeader(scrollData, id, title, collapsed)
    title = tonumber(title) ~= nil and GetString(title) or title
    local recentEntry = ZO_ScrollList_CreateDataEntry(collapsed and 2 or 0, { id = id, name = title })
    table.insert(scrollData, recentEntry)
end

local function buildResult(listEntry, currentNodeIndex)
    local nodeData = Utils.shallowCopy(listEntry)
    nodeData.isSelected = (currentNodeIndex == MapSearch.targetNode)
    nodeData.dataIndex = currentNodeIndex

    -- MS.log("%s: traders %d", nodeData.barename, nodeData.traders or 0)
    if listEntry.traders and listEntry.traders > 0 then
        if listEntry.traders >= 5 then
            nodeData.suffix = "|t20:23:Navigator/media/city_narrow.dds:inheritcolor|t"
        elseif listEntry.traders >= 2 then
            nodeData.suffix = "|t20:23:Navigator/media/town_narrow.dds:inheritcolor|t"
        end
        nodeData.suffix = (nodeData.suffix or "") .. "|t23:23:/esoui/art/icons/servicemappins/servicepin_guildkiosk.dds:inheritcolor|t"
    end

    if nodeData.bookmarked then --MapSearch.Bookmarks:contains(nodeData) then
        nodeData.suffix = (nodeData.suffix or "") .. "|t25:25:Navigator/media/bookmark.dds:inheritcolor|t"
    end

    if not nodeData.known and nodeData.nodeIndex then
        nodeData.tooltip = GetString(NAVIGATOR_NOT_KNOWN)
    end

    nodeData.isFree = true
    if MapSearch.isRecall and nodeData.known and nodeData.nodeIndex then -- and nodeData.poiType == MS.POI_WAYSHRINE
        local _, timeLeft = GetRecallCooldown()

        if timeLeft == 0 then
            local currencyType = CURT_MONEY
            local currencyAmount = GetRecallCost(nodeData.nodeIndex)
            if currencyAmount > 0 then
                local formatType = ZO_CURRENCY_FORMAT_AMOUNT_ICON
                local currencyString = zo_strformat(SI_NUMBER_FORMAT, ZO_Currency_FormatKeyboard(currencyType, currencyAmount, formatType))
                nodeData.tooltip = string.format(GetString(SI_TOOLTIP_RECALL_COST) .. "%s", currencyString)
                nodeData.isFree = false
            end
        end
    end


    if MapSearch.isDeveloper then
        addDeveloperTooltip(nodeData)
    end

    return nodeData
end

local function buildList(scrollData, id, title, list, defaultString)
    local collapsed = MT.collapsedCategories[id] and true or false

    buildCategoryHeader(scrollData, id, title, collapsed)

    if collapsed then
        return
    elseif #list == 0 and defaultString then
        list = {{ hint = GetString(defaultString) }}
    end

    local currentNodeIndex = MT.resultCount

    for i = 1, #list do
        if list[i].hint then
            local entry = ZO_ScrollList_CreateDataEntry(3, { hint = list[i].hint })
            table.insert(scrollData, entry)
        else
            local nodeData = buildResult(list[i], currentNodeIndex)

            local entry = ZO_ScrollList_CreateDataEntry(1, nodeData)
            table.insert(scrollData, entry)

            currentNodeIndex = currentNodeIndex + 1
        end
    end

    MT.resultCount = currentNodeIndex
end

function MT:UpdateEditDefaultText()
	local searchString = self.editControl:GetText()
	if searchString == "" then
		-- reinstate default text
        local openTabBinding = ZO_Keybindings_GetHighestPriorityNarrationStringFromAction("NAVIGATOR_OPENTAB") or '-'
        local s = zo_strformat(self.editControl:HasFocus() and GetString(NAVIGATOR_SEARCH) or GetString(NAVIGATOR_SEARCH_KEYPRESS),
            openTabBinding)
		ZO_EditDefaultText_Initialize(self.editControl, s)
	else
		-- remove default text
		ZO_EditDefaultText_Disable(self.editControl)
	end
end

function MT:buildScrollList(keepScrollPosition)
    local scrollPosition = 0
    if keepScrollPosition then
        scrollPosition = ZO_ScrollList_GetScrollValue(self.listControl)
        -- MS.log("MT:buildScrollList: pos=%d", scrollPosition)
    end

	ZO_ScrollList_Clear(self.listControl)

	self:UpdateEditDefaultText()

    local scrollData = ZO_ScrollList_GetDataList(self.listControl)

    local isSearching = #MapSearch.results > 0 or (self.searchString and self.searchString ~= "")
    MT.resultCount = 0
    if isSearching then
        buildList(scrollData, "results", NAVIGATOR_CATEGORY_RESULTS, MapSearch.results, NAVIGATOR_HINT_NORESULTS)
    else
        local bookmarks = MapSearch.Bookmarks:getBookmarks()
        buildList(scrollData, "bookmarks", NAVIGATOR_CATEGORY_BOOKMARKS, bookmarks, NAVIGATOR_HINT_NOBOOKMARKS)

        local recentCount = MS.saved.recentsCount
        local recents = MapSearch.Recents:getRecents(recentCount)
        buildList(scrollData, "recents", NAVIGATOR_CATEGORY_RECENT, recents, NAVIGATOR_HINT_NORECENTS)

        local zone = MapSearch.Locations:getCurrentMapZone()
        if zone and zone.zoneId == 2 then
            local list = MapSearch.Locations:getZoneList()
            table.sort(list, nameComparison)
            buildList(scrollData, "zones", NAVIGATOR_CATEGORY_ZONES, list)
        elseif zone then
            local list = MapSearch.Locations:getKnownNodes(zone.zoneId)

            if MapSearch.isRecall and zone.zoneId ~= MS.ZONE_CYRODIIL then
                local playerInfo = MapSearch.Locations:getPlayerInZone(zone.zoneId)
                if playerInfo then
                    playerInfo.name = zo_strformat(GetString(NAVIGATOR_TRAVEL_TO_ZONE), zone.name)
                    -- playerInfo.suffix = "via " .. playerInfo.suffix
                    playerInfo.colour = ZO_SECOND_CONTRAST_TEXT
                else
                    playerInfo = {
                        name = GetString(NAVIGATOR_NO_TRAVEL_PLAYER),
                        barename = "",
                        zoneId = zone.zoneId,
                        zoneName = GetZoneNameById(zone.zoneId),
                        icon = "/esoui/art/crafting/crafting_smithing_notrait.dds",
                        poiType = MS.POI_NONE,
                        known = false
                    }
                    end
                playerInfo.weight = 10.0 -- list this first!
                table.insert(list, playerInfo)
            end

            table.sort(list, weightComparison)
            buildList(scrollData, "results", zone.name, list)
        end
    end

	ZO_ScrollList_Commit(self.listControl)

    if keepScrollPosition then
        ZO_ScrollList_ScrollAbsolute(self.listControl, scrollPosition)
    elseif MT.resultCount > 0 then
        -- FIXME: this doesn't account for the headings
        ZO_ScrollList_ScrollDataIntoView(self.listControl, MapSearch.targetNode + 1, nil, true)
    end
end

function MT:executeSearch(searchString, keepTargetNode)
	local results

    MT.searchString = searchString

    results = Search.run(searchString or "", MT.filter)

	MapSearch.results = results
    if not keepTargetNode or MapSearch.targetNode >= (MT.resultCount or 0) then
        -- MS.log("executeSearch: reset targetNode keep=%d, oldTarget=%d, count=%d", keepTargetNode and 1 or 0, MapSearch.targetNode, (MT.resultCount or 0))
    	MapSearch.targetNode = 0
        keepTargetNode = false
    end

	MT:buildScrollList(keepTargetNode)
    MT:updateFilterControl()
end

function MT:getTargetDataIndex()
	local currentNodeIndex = 0

    local scrollData = ZO_ScrollList_GetDataList(self.listControl)

    for i = 1, #scrollData do
        if scrollData[i].typeId == 1 then -- wayshrine row
            if currentNodeIndex == MapSearch.targetNode then
                return i
            end
            currentNodeIndex = currentNodeIndex + 1
        end
    end

	return nil
end

function MT:getTargetNode()
    local i = self:getTargetDataIndex()

    if i then
        local scrollData = ZO_ScrollList_GetDataList(self.listControl)
        return scrollData[i].data
    end

    return nil
end

function MT:getNextCategoryFirstIndex()
    local scrollData = ZO_ScrollList_GetDataList(self.listControl)

    if #scrollData <= 2 then
        return -- nothing to find!
    end

    local currentIndex = self:getTargetDataIndex()
    local currentNodeIndex = MapSearch.targetNode + 1

    local i = currentIndex + 1
    local foundCategory = false

    while true do
        if scrollData[i].typeId == 1 then -- wayshrine row
            if (foundCategory and scrollData[i].data.known) or i == currentIndex then
                -- return the first entry after the category header
                -- MS.log("Index %d node %d is result - returning", i, currentNodeIndex)
                return currentNodeIndex
            end
            -- MS.log("Index %d node %d is result - incrementing", i, currentNodeIndex)
            currentNodeIndex = currentNodeIndex + 1
        elseif scrollData[i].typeId == 0 then -- category header
            -- MS.log("Index %d node %d is category", i, currentNodeIndex)
            foundCategory = true
        end

        if i >= #scrollData then
            -- MS.log("Wrapping at index %d node %d", i, currentNodeIndex)
            i = 1
            currentNodeIndex = 0
        else
            i = i + 1
        end
    end
end

function MT:init()
	MS.log("MapTab:init")

	local _refreshing = false
	local _isDirty = true 
	
	self.isDirty = function()
		return _isDirty
	end
	
	self.setDirty = function()
		_isDirty = true 
	end
	
	self.refreshIfRequired = function(self,...)
		--df("RefreshIfRequired isDirty=%s refreshing=%s", tostring(_isDirty), tostring(_refreshing))
		if _isDirty == true and _refreshing == false then 
			_refreshing = true -- only allow one refresh at any one time
			self:refresh(...)
			_isDirty = false
			_refreshing = false
		end 
	end
	
end

local function getMapIdByZoneId(zoneId)
    local mapIndex
    if zoneId == 2 then -- Tamriel
        return 27
    elseif zoneId == 981 then -- Brass Fortress
        return 1348
    elseif zoneId == 1463 then -- The Scholarium
        return 2515
    else
        return GetMapIdByZoneId(zoneId)
    end
end

function MT:onTextChanged(editbox, listcontrol)
	local searchString = string.lower(editbox:GetText())
    if searchString == "z:" then
        local mapId = getMapIdByZoneId(2) -- Tamriel
        MS.log("MT:onTextChanged mapId %d", mapId or -1)
        -- if mapId then
        WORLD_MAP_MANAGER:SetMapById(mapId)
        -- end
        MT.filter = MS.FILTER_NONE
        editbox:SetText("")
        editbox.editTextChanged = false
        searchString = ""
    elseif searchString == "h:" then
        self.filter = MS.FILTER_HOUSES
        editbox:SetText("")
        editbox.editTextChanged = false
        searchString = ""
    elseif searchString == '@' or searchString == "p:" then
        self.filter = MS.FILTER_PLAYERS
        editbox.editTextChanged = false
        editbox:SetText("")
        searchString = ""
    else
        self.editControl.editTextChanged = true
    end

    self:executeSearch(searchString)
end

function MT:selectCurrentResult()
	local data = self:getTargetNode()
	if data then
		self:selectResult(nil, data, 1)
	end
end

function MT:nextResult()
    local known = false
    local startNode = MapSearch.targetNode
    repeat
    	MapSearch.targetNode = (MapSearch.targetNode + 1) % MT.resultCount
        local node = self:getTargetNode()
        if node and node.known then
            known = true
        end
    until known or MapSearch.targetNode == startNode
	self:buildScrollList()
end

function MT:previousResult()
    local known = false
    local startNode = MapSearch.targetNode
    repeat
        MapSearch.targetNode = MapSearch.targetNode - 1
        if MapSearch.targetNode < 0 then
            MapSearch.targetNode = MT.resultCount - 1
        end
        local node = self:getTargetNode()
        if node and node.known then
            known = true
        end
    until known or MapSearch.targetNode == startNode
	self:buildScrollList()
end

function MT:nextCategory()
    MapSearch.targetNode = self:getNextCategoryFirstIndex()
	self:buildScrollList()
end

function MT:previousCategory()
    -- MapSearch.targetNode = self:getPreviousCategoryFirstIndex()
	-- self:buildScrollList()
end

function MT:resetFilter()
	MS.log("MT.resetFilter")
    self.filter = MS.FILTER_NONE
    self:hideFilterControl()
    self:ImmediateRefresh()
	ZO_ScrollList_ResetToTop(self.listControl)
end

function MT:resetSearch(lose_focus)
	MS.log("MT.resetSearch")
	self.editControl:SetText("")
    self.filter = MS.FILTER_NONE
    self:hideFilterControl()
    self:ImmediateRefresh()

	-- if lose_focus then
	-- 	editbox:LoseFocus()
	-- end
	--ZO_EditDefaultText_Initialize(editbox, GetString(FASTER_TRAVEL_WAYSHRINES_SEARCH))
	--ResetVisibility(listcontrol)
	ZO_ScrollList_ResetToTop(self.listControl)
end

local function showWayshrineMenu(owner, data)
	ClearMenu()

    local entry = {}
    if data.nodeIndex then
        entry.nodeIndex = data.nodeIndex
    elseif data.zoneId then
        entry.zoneId = data.zoneId
    else
        MS.log("showWayshrineMenu: unrecognised data")
        return
    end

    local bookmarks = MapSearch.Bookmarks
	if bookmarks:contains(entry) then
        MT.menuOpen = true
		AddMenuItem("Remove Bookmark", function()
			bookmarks:remove(entry)
			ClearMenu()
            MT.menuOpen = false
            MT:ImmediateRefresh()
		end)
	else
        MT.menuOpen = true
		AddMenuItem("Add Bookmark", function()
			bookmarks:add(entry)
			ClearMenu()
            MT.menuOpen = false
            MT:ImmediateRefresh()
		end)
	end
	ShowMenu(owner)
    SetMenuHiddenCallback(function()
        MS.log("SetMenuHiddenCallback: Menu hidden")
        MT.menuOpen = false
        if MT.needsRefresh then
            MT:ImmediateRefresh()
        end
    end)
end

function MT:selectResult(control, data, mouseButton)
    if mouseButton == 1 then
        if data.nodeIndex or data.userID then
            self:jumpToNode(data)
        elseif data.poiType == MS.POI_ZONE then
            MT.filter = MS.FILTER_NONE
            self.editControl:SetText("")

            local mapZoneId = MapSearch.Locations:getCurrentMapZoneId()
            local currentMapId = GetCurrentMapId()
            local mapId = data.mapId or getMapIdByZoneId(data.zoneId)
            MS.log("selectResult: data.zoneId %d data.mapId %d mapZoneId %d mapId %d", data.zoneId, data.mapId or 0, mapZoneId, mapId)
            if data.zoneId ~= mapZoneId or (data.mapId and data.mapId ~= currentMapId) then
                MS.log("selectResult: mapId %d", mapId or 0)
                if mapId then
                    WORLD_MAP_MANAGER:SetMapById(mapId)
                end
            end
        end
    elseif mouseButton == 2 then
        if data.nodeIndex or data.poiType == MS.POI_ZONE then
            showWayshrineMenu(control, data)
        end
    else
        MS.log("selectResult: unhandled; poiType=%d zoneId=%d", data.poiType or -1, data.zoneId or -1)
    end
end

function MT:RowMouseUp(control, mouseButton, upInside)
	if upInside then
		local data = ZO_ScrollList_GetData(control)
        self:selectResult(control, data, mouseButton)
	end
end

function MT:CategoryRowMouseUp(control, mouseButton, upInside)
	if upInside then
		local data = ZO_ScrollList_GetData(control)
        MS.log("Toggling category %s", data.id)
        self.collapsedCategories[data.id] = not self.collapsedCategories[data.id]
        MT:buildScrollList(true)
        MT:updateFilterControl()
	end
end

function MT:IsViewingInitialZone()
    local zone = MapSearch.Locations:getCurrentMapZone()
    return not zone or zone.zoneId == MapSearch.initialMapZoneId
end

function MT:OnMapChanged()
    local mapId = GetCurrentMapId()
    if MapSearch.mapVisible and mapId ~= self.currentMapId then
        self.currentMapId = mapId
        local zone = MapSearch.Locations:getCurrentMapZone()
        MS.log("OnMapChanged: now zoneId=%d mapId=%d initial=%d", zone and zone.zoneId or 0, mapId or 0, MapSearch.initialMapZoneId or 0)
        if zone and zone.zoneId <= 2 then
            self.collapsedCategories = { bookmarks = true, recents = true }
        else
            self.collapsedCategories = {}
        end
        MapSearch.targetNode = 0
        self.filter = MS.FILTER_NONE
        self:updateFilterControl()
        self.editControl:SetText("")
        -- end
        self:executeSearch("")
    end
end

MapSearch.MapTab = MT
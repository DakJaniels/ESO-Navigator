MapSearch = {
  name = "Navigator",
  menuName = "Navigator",          -- A UNIQUE identifier for menu object.
  displayName = "|c66CC66N|r|c66CCFFavigator|r",
  settingsName = "NavigatorSettings",
  author = "SirNightstorm",
  appVersion = "0",
  svName = "Navigator_SavedVariables",
  default = {
    recentNodes = {},
    bookmarkNodes = {},
    defaultTab = false,
    autoFocus = false,
    tpCommand = "/nav",
    loggingEnabled = false,
    recentsCount = 10
  },
  Location = {},
  Wayshrine = {},
  Search = {},
  isRecall = true,
  isCLI = false,
  isDeveloper = (GetDisplayName() == '@SirNightstorm' and true) or false,
  results = {},
  targetNode = 0,
  mapVisible = false,
}
local MS = MapSearch

local logger

if LibDebugLogger then
  logger = LibDebugLogger(MS.name)
end

local Utils = MS.Utils

local _events = {}

function MS.log(...)
  if logger and MS.saved and MS.saved["loggingEnabled"] then
    logger:Debug(string.format(...))
  end
end

function MS.logWarning(...)
  if logger and MS.saved and MS.saved["loggingEnabled"] then
    logger:Warn(string.format(...))
  end
end

local function GetUniqueEventId(id)
  local count = _events[id] or 0
  count = count + 1
  _events[id] = count
  return count
end

local function getEventName(id)
  return table.concat({ MS.name, tostring(id), tostring(GetUniqueEventId(id)) }, "_")
end

local function addEvent(id, func)
  local name = getEventName(id)
  EVENT_MANAGER:RegisterForEvent(name, id, func)
end

local function addEvents(func, ...)
  local count = select('#', ...)
  local id
  for i = 1, count do
  id = select(i, ...)
  if not id then
    df('%s element %d is nil.  Please report.', MS.name, i)
  else
    addEvent(id, func)
  end
  end
end


local ButtonGroup = {
  {
    name = GetString(NAVIGATOR_KEYBIND_SEARCH),
    keybind = "NAVIGATOR_OPENTAB", --"UI_SHORTCUT_QUICK_SLOTS", --"NAVIGATOR_SEARCH",
    order = 200,
    visible = function() return true end,
    callback = function() MS.showSearch() end,
    },
    alignment = KEYBIND_STRIP_ALIGN_CENTER,
  }

local function OnMapStateChange(oldState, newState)
  if newState == SCENE_SHOWING then
    MS.mapVisible = true
    local zone = MS.Locations:getCurrentMapZone()
    MS.initialMapZoneId = zone and zone.zoneId or nil
    MS.log("WorldMap showing; initialMapZoneId=%d", MS.initialMapZoneId or 0)
    PushActionLayerByName("Map")
    KEYBIND_STRIP:AddKeybindButtonGroup(ButtonGroup)
    if MS.saved and MS.saved["defaultTab"] and not FasterTravel then
      WORLD_MAP_INFO:SelectTab(NAVIGATOR_TAB_SEARCH)
    end

    if not zone or zone.zoneId > 2 then
      MS.MapTab.collapsedCategories = {}
    else
      MS.MapTab.collapsedCategories = { bookmarks = true, recents = true }
    end

    MS.log("WorldMap showing done")
  elseif newState == SCENE_HIDDEN then
    MS.log("WorldMap hidden")
    MS.mapVisible = false
    KEYBIND_STRIP:RemoveKeybindButtonGroup(ButtonGroup)
    RemoveActionLayerByName("Map")
  end
end

local function OnMapChanged()
  MS.MapTab:OnMapChanged()
end

local function OnStartFastTravel(eventCode, nodeIndex)
  MS.log("OnStartFastTravel: "..eventCode..", "..nodeIndex)
  MS.isRecall = false
  MS.MapTab:ImmediateRefresh()
end

local function OnEndFastTravel()
  MS.log("OnEndFastTravel")
  MS.isRecall = true
end

local function OnPlayerActivated()
  MS.log("OnPlayerActivated")
  MS.Recents:onPlayerActivated()
end

local function OnPOIUpdated()
  MS.log("OnPOIUpdated")
  MS.Locations:clearKnownNodes()
end

local function SetPlayersDirty(eventCode)
  -- MS.log("SetPlayersDirty("..eventCode..")")
  MS.Locations:ClearPlayers()
  MS.MapTab:queueRefresh()
end

function MS.showSearch()
  MS.log("showSearch")
  local tabVisible = MapSearch.MapTab.visible
  MAIN_MENU_KEYBOARD:ShowScene("worldMap")
  WORLD_MAP_INFO:SelectTab(NAVIGATOR_TAB_SEARCH)
  MS.MapTab:resetSearch(false)
  if MapSearch.saved.autoFocus or tabVisible then
    MS.MapTab.editControl:TakeFocus()
    MS.log("showSearch: setting editControl focus")
  end
end

local function moveTabToFirst()
  local buttons = WORLD_MAP_INFO.modeBar.menuBar.m_object.m_buttons
  local ourButton = buttons[#buttons]
  buttons[#buttons] = nil
  table.insert(buttons, 1, ourButton)

  local buttonData = WORLD_MAP_INFO.modeBar.buttonData
  local ourData = buttonData[#buttonData]
  buttonData[#buttonData] = nil
  table.insert(buttonData, 1, ourData)

  WORLD_MAP_INFO.modeBar:UpdateButtons(false)
  MS.log("Menu re-ordered")
end

function MS:initialize()
  MS.log("initialize starts")
  -- https://wiki.esoui.com/How_to_add_buttons_to_the_keybind_strip

  self.saved = ZO_SavedVars:NewAccountWide(self.svName, 1, nil, self.default)

  SCENE_MANAGER:GetScene('worldMap'):RegisterCallback("StateChange", OnMapStateChange)

  self.MapTab:init()
  self.Recents:init()
  self.Bookmarks:init()
  self.Chat:Init()
  self:loadSettings()

  CALLBACK_MANAGER:RegisterCallback("OnWorldMapChanged", OnMapChanged)
  CALLBACK_MANAGER:RegisterCallback("OnWorldMapModeChanged", OnMapChanged)

  addEvent(EVENT_START_FAST_TRAVEL_INTERACTION, OnStartFastTravel)
  addEvent(EVENT_END_FAST_TRAVEL_INTERACTION, OnEndFastTravel)
  addEvent(EVENT_PLAYER_ACTIVATED, OnPlayerActivated)

  addEvents(OnPOIUpdated, EVENT_POI_DISCOVERED, EVENT_POI_UPDATED, EVENT_FAST_TRAVEL_NETWORK_UPDATED)

  addEvents(SetPlayersDirty,
    EVENT_GROUP_MEMBER_JOINED, EVENT_GROUP_MEMBER_LEFT, EVENT_GROUP_MEMBER_CONNECTED_STATUS,
    EVENT_GUILD_SELF_JOINED_GUILD, EVENT_GUILD_SELF_LEFT_GUILD, EVENT_GUILD_MEMBER_ADDED, EVENT_GUILD_MEMBER_REMOVED,
    EVENT_GUILD_MEMBER_CHARACTER_ZONE_CHANGED, EVENT_FRIEND_CHARACTER_ZONE_CHANGED,
    EVENT_FRIEND_ADDED, EVENT_FRIEND_REMOVED)

  addEvent(EVENT_GUILD_MEMBER_PLAYER_STATUS_CHANGED, function(_, guildId, DisplayName, oldStatus, newStatus)
    if newStatus == PLAYER_STATUS_OFFLINE or (oldStatus == PLAYER_STATUS_OFFLINE and newStatus == PLAYER_STATUS_ONLINE) then
      SetPlayersDirty()
    end
  end)

  local buttonData = {
    pressed = "Navigator/media/tabicon_down.dds",
    highlight = "Navigator/media/tabicon_over.dds",
    normal = "Navigator/media/tabicon_up.dds",
    callback = function()
      -- Hide the modebar title
      WORLD_MAP_INFO.modeBar.label:SetText("")
    end
  }

  WORLD_MAP_INFO.modeBar:Add(NAVIGATOR_TAB_SEARCH, { self.MapTab.fragment }, buttonData)
  if self.saved["defaultTab"] and not FasterTravel then
    moveTabToFirst()
  end

  MS.log("Initialize exits")
end

local function OnAddOnLoaded(_, addonName)
    if addonName ~= "Navigator" then return end

    MS:initialize()

    if PP and PP.ADDON_NAME then
        PP.ScrollBar(MapSearch_MapTabListScrollBar)
        ZO_Scroll_SetMaxFadeDistance(MapSearch_MapTabList, PP.savedVars.ListStyle.list_fade_distance)
    end

    EVENT_MANAGER:UnregisterForEvent(MS.name, EVENT_ADD_ON_LOADED)
end

EVENT_MANAGER:RegisterForEvent(MS.name, EVENT_ADD_ON_LOADED, OnAddOnLoaded)

--[[SLASH_COMMANDS["/mapsearch"] = function (extra)
  if extra == 'save' then
      MapSearch.Locations:initialise()
      -- buildLocations()
      MapSearch.saved.locations = Utils.deepCopy(MS.Search.locations)
      MapSearch.saved.zones = Utils.deepCopy(MS.Search.zones)
      MapSearch.saved.result = Utils.deepCopy(MS.Search.result)
      d("Written MapSearch data to Saved Preferences")
  elseif extra == 'clear' then
      MapSearch.saved.categories = nil
      MapSearch.saved.locations = nil
      MapSearch.saved.zones = nil
      MapSearch.saved.result = nil
      d("Cleared MapSearch data from Saved Preferences")
  end
end ]]--
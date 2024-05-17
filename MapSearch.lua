MapSearch = {}
MapSearch.name = "MapSearch"
MapSearch.svName = "MapSearch_SavedVariables"
MapSearch.default = {}
MapSearch.Location = {}
MapSearch.Wayshrine = {}

-- Make this properly localisable!
ZO_CreateStringId("MAPSEARCH_SEARCH","Search")
ZO_CreateStringId("SI_BINDING_NAME_MAPSEARCH_SEARCH", "Search")
ZO_CreateStringId("MAPSEARCH_TAB_SEARCH","Search")

local logger = LibDebugLogger(MapSearch.name)
local Utils = MapSearch.Utils

local _events = {}

local function GetUniqueEventId(id)
  local count = _events[id] or 0
  count = count + 1
  _events[id] = count
  return count
end

local function GetEventName(id)
  return table.concat({ MapSearch.name, tostring(id), tostring(GetUniqueEventId(id)) }, "_")
end

local function addEvent(id, func)
  local name = GetEventName(id)
  EVENT_MANAGER:RegisterForEvent(name, id, func)
end

local function AddWorldMapFragment(strId, fragment, normal, highlight, pressed)
  WORLD_MAP_INFO.modeBar:Add(strId, { fragment }, { pressed = pressed, highlight = highlight, normal = normal })
  end

local function GetPaths(path, ...)
  return unpack(Utils.map({ ... }, function(p)
    return path .. p
  end))
end

function MapSearch.initialize()
  logger:Info("MapSearch.Initialize starts")
  -- https://wiki.esoui.com/How_to_add_buttons_to_the_keybind_strip

  local mapTabControl = MapSearch_WorldMapTab
  
  local ButtonGroup = {
		{
			name = "Search", --GetString(SI_BINDING_NAME_FASTER_TRAVEL_REJUMP),
			keybind = "UI_SHORTCUT_QUICK_SLOTS", --"MAPSEARCH_SEARCH",
			order = 20,
			visible = function() return true end,
			callback = function() MapSearch.showSearch() end,
		},
		alignment = KEYBIND_STRIP_ALIGN_LEFT,
	}

  SCENE_MANAGER:GetScene('worldMap'):RegisterCallback("StateChange",
  function(oldState, newState)
    if newState == SCENE_SHOWING then
      KEYBIND_STRIP:AddKeybindButtonGroup(ButtonGroup)
    elseif newState == SCENE_HIDDEN then
      KEYBIND_STRIP:RemoveKeybindButtonGroup(ButtonGroup)
    end
  end)

  local mapTab = MapSearch.MapTab(mapTabControl)

  -- local normal, highlight, pressed = GetPaths("/esoui/art/guild/guildhistory_indexicon_guildstore_", "up.dds", "over.dds", "down.dds")
  local normal = "/esoui/art/tradinghouse/tradinghouse_browse_tabicon_up.dds"
  local highlight = "/esoui/art/tradinghouse/tradinghouse_browse_tabicon_over.dds"
  local pressed = "/esoui/art/tradinghouse/tradinghouse_browse_tabicon_down.dds"

  AddWorldMapFragment(MAPSEARCH_TAB_SEARCH, mapTabControl.fragment, normal, highlight, pressed)

  logger:Info("MapSearch.Initialize exits")
end

-- Then we create an event handler function which will be called when the "addon loaded" event
-- occurs. We'll use this to initialize our addon after all of its resources are fully loaded.
function MapSearch.onAddOnLoaded(event, addonName)
  -- The event fires each time *any* addon loads - but we only care about when our own addon loads.
  if addonName ~= "MapSearch" then return end

  MapSearch.initialize()

  --unregister the event again as our addon was loaded now and we do not need it anymore to be run for each other addon that will load
  EVENT_MANAGER:UnregisterForEvent(MapSearch.name, EVENT_ADD_ON_LOADED)
end

function MapSearch.onStartFastTravel(eventCode, nodeIndex)
  logger:Info("onStartFastTravel: "..eventCode..", "..nodeIndex)
end

function MapSearch.showSearch()
  logger:Info("MapSearch.showSearch")
end

-- Finally, we'll register our event handler function to be called when the proper event occurs.
-->This event EVENT_ADD_ON_LOADED will be called for EACH of the addns/libraries enabled, this is why there needs to be a check against the addon name
-->within your callback function! Else the very first addon loaded would run your code + all following addons too.
EVENT_MANAGER:RegisterForEvent(MapSearch.name, EVENT_ADD_ON_LOADED, MapSearch.onAddOnLoaded)

addEvent(EVENT_START_FAST_TRAVEL_INTERACTION, MapSearch.onStartFastTravel)

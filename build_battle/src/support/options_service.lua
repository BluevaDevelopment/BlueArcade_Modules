-- Mirrors legacy OptionsService.java. Main/time/weather menus are built directly in Lua from the same
-- slot/material/action layout the legacy YAML menus shipped; labels stay hardcoded, matching legacy 1:1
-- (they were never routed through moduleConfig.getTranslation there either).
local OPTIONS_SLOT = 8

-- name, icon, biome - matches OptionsService.BIOMES exactly.
local BIOMES = {
  { name = "<green>Plains", icon = "GRASS_BLOCK", biome = "PLAINS" },
  { name = "<dark_green>Forest", icon = "OAK_SAPLING", biome = "FOREST" },
  { name = "<aqua>Birch Forest", icon = "BIRCH_SAPLING", biome = "BIRCH_FOREST" },
  { name = "<dark_blue>Dark Forest", icon = "DARK_OAK_SAPLING", biome = "DARK_FOREST" },
  { name = "<green>Jungle", icon = "JUNGLE_SAPLING", biome = "JUNGLE" },
  { name = "<yellow>Savanna", icon = "ACACIA_SAPLING", biome = "SAVANNA" },
  { name = "<yellow>Desert", icon = "SAND", biome = "DESERT" },
  { name = "<gold>Beach", icon = "SAND", biome = "BEACH" },
  { name = "<white>Snowy Plains", icon = "SNOW_BLOCK", biome = "SNOWY_PLAINS" },
  { name = "<white>Snowy Taiga", icon = "SPRUCE_SAPLING", biome = "SNOWY_TAIGA" },
  { name = "<dark_green>Taiga", icon = "SPRUCE_SAPLING", biome = "TAIGA" },
  { name = "<dark_green>Swamp", icon = "LILY_PAD", biome = "SWAMP" },
  { name = "<gold>Badlands", icon = "TERRACOTTA", biome = "BADLANDS" },
  { name = "<red>Mushroom Fields", icon = "RED_MUSHROOM", biome = "MUSHROOM_FIELDS" },
  { name = "<blue>Ocean", icon = "WATER_BUCKET", biome = "OCEAN" },
  { name = "<dark_blue>Deep Ocean", icon = "WATER_BUCKET", biome = "DEEP_OCEAN" },
  { name = "<green>Meadow", icon = "GRASS_BLOCK", biome = "MEADOW" },
  { name = "<light_purple>Flower Forest", icon = "POPPY", biome = "FLOWER_FOREST" },
}

local TIME_TICKS = { day = 1000, noon = 6000, sunset = 12000, night = 13000, midnight = 18000, sunrise = 23000 }
local WEATHER_TYPES = { clear = "CLEAR", sunny = "CLEAR", rain = "DOWNFALL", rainy = "DOWNFALL", downfall = "DOWNFALL" }

local M = {}
local bannerService, particleService, headsService

-- Set from main.lua after all support modules are required, avoiding a require cycle.
function M.wire(banner, particle, heads)
  bannerService = banner
  particleService = particle
  headsService = heads
end

function M.giveOptionsItem(session, handle)
  local name = session.config.translation(handle, "options.item.name")
  local lore = session.config.translationList(handle, "options.item.lore")
  session.player.giveEnchantedItem(handle, "NETHER_STAR", 1, OPTIONS_SLOT, nil, nil, false, name, lore)
end

function M.removeOptionsItem(session, handle)
  local item = session.player.getSlotItem(handle, OPTIONS_SLOT)
  if item and item.material == "NETHER_STAR" then
    session.player.giveItem(handle, "AIR", 1, OPTIONS_SLOT)
  end
end

local function buildMainMenuItems(session, handle)
  return {
    { slot = 10, material = "CLOCK", amount = 1, name = "<yellow>Time of Day</yellow>",
      lore = { "<gray>Change the time for your plot.</gray>", "<green>Click to open</green>" },
      actions = { "MODULE;build_battle;options menu time" } },
    { slot = 12, material = "WATER_BUCKET", amount = 1, name = "<aqua>Weather</aqua>",
      lore = { "<gray>Change the weather for your plot.</gray>", "<green>Click to open</green>" },
      actions = { "MODULE;build_battle;options menu weather" } },
    { slot = 14, material = "OAK_PLANKS", amount = 1, name = "<gold>Change Floor</gold>",
      lore = { "<gray>Change your plot floor material.</gray>", "<green>Click to activate</green>" },
      actions = { "MODULE;build_battle;options floor" } },
    { slot = 16, material = "GRASS_BLOCK", amount = 1, name = "<dark_green>Biome</dark_green>",
      lore = { "<gray>Change the biome of your plot.</gray>", "<green>Click to open</green>" },
      actions = { "MODULE;build_battle;options biome" } },
    { slot = 19, material = "BLAZE_POWDER", amount = 1, name = "<light_purple>Particles</light_purple>",
      lore = { "<gray>Add decorative particles to your plot.</gray>", "<green>Click to open</green>" },
      actions = { "MODULE;build_battle;options particle menu" } },
    { slot = 21, material = "PLAYER_HEAD", amount = 1, name = "<yellow>Player Heads</yellow>",
      lore = { "<gray>Get decorative player heads.</gray>", "<green>Click to open</green>" },
      actions = { "MODULE;build_battle;options heads menu" } },
    { slot = 23, material = "WHITE_BANNER", amount = 1, name = "<blue>Banner Creator</blue>",
      lore = { "<gray>Design custom banners.</gray>", "<green>Click to open</green>" },
      actions = { "MODULE;build_battle;options banner" } },
    { slot = 25, material = "BARRIER", amount = 1, name = "<red>Reset Plot</red>",
      lore = { "<gray>Clear your plot and reset the floor.</gray>", "<red>Click to reset</red>" },
      actions = { "MODULE;build_battle;options reset" } },
    { slot = 40, material = "RED_DYE", amount = 1, name = "<red>Close</red>",
      lore = { "<gray>Close this menu.</gray>" },
      actions = { "CLOSE" } },
  }
end

local function buildTimeMenuItems()
  return {
    { slot = 10, material = "SUNFLOWER", amount = 1, name = "<yellow>Day</yellow>",
      lore = { "<gray>Set time to day.</gray>", "<green>Click to select</green>" }, actions = { "MODULE;build_battle;options time day" } },
    { slot = 11, material = "YELLOW_DYE", amount = 1, name = "<gold>Noon</gold>",
      lore = { "<gray>Set time to noon.</gray>", "<green>Click to select</green>" }, actions = { "MODULE;build_battle;options time noon" } },
    { slot = 12, material = "ORANGE_DYE", amount = 1, name = "<gold>Sunset</gold>",
      lore = { "<gray>Set time to sunset.</gray>", "<green>Click to select</green>" }, actions = { "MODULE;build_battle;options time sunset" } },
    { slot = 13, material = "END_ROD", amount = 1, name = "<blue>Night</blue>",
      lore = { "<gray>Set time to night.</gray>", "<green>Click to select</green>" }, actions = { "MODULE;build_battle;options time night" } },
    { slot = 14, material = "OBSIDIAN", amount = 1, name = "<dark_blue>Midnight</dark_blue>",
      lore = { "<gray>Set time to midnight.</gray>", "<green>Click to select</green>" }, actions = { "MODULE;build_battle;options time midnight" } },
    { slot = 15, material = "PINK_DYE", amount = 1, name = "<yellow>Sunrise</yellow>",
      lore = { "<gray>Set time to sunrise.</gray>", "<green>Click to select</green>" }, actions = { "MODULE;build_battle;options time sunrise" } },
    { slot = 22, material = "ARROW", amount = 1, name = "<gray>Back</gray>",
      lore = { "<gray>Return to options menu.</gray>" }, actions = { "MODULE;build_battle;options menu main" } },
  }
end

local function buildWeatherMenuItems()
  return {
    { slot = 11, material = "SUNFLOWER", amount = 1, name = "<yellow>Clear</yellow>",
      lore = { "<gray>Set weather to clear.</gray>", "<green>Click to select</green>" }, actions = { "MODULE;build_battle;options weather clear" } },
    { slot = 15, material = "WATER_BUCKET", amount = 1, name = "<blue>Rain</blue>",
      lore = { "<gray>Set weather to rain.</gray>", "<green>Click to select</green>" }, actions = { "MODULE;build_battle;options weather rain" } },
    { slot = 22, material = "ARROW", amount = 1, name = "<gray>Back</gray>",
      lore = { "<gray>Return to options menu.</gray>" }, actions = { "MODULE;build_battle;options menu main" } },
  }
end

local function buildBiomeMenuItems(session, handle)
  local items = {}
  for i, entry in ipairs(BIOMES) do
    items[#items + 1] = {
      slot = i - 1,
      material = entry.icon,
      amount = 1,
      name = entry.name,
      lore = {},
      actions = { "MODULE;build_battle;options biome_select " .. entry.biome },
    }
  end
  return items
end

function M.openMenu(session, handle, menuId)
  local title, items, size
  if menuId == "time" then
    title, items, size = session.config.translation(handle, "options.time.title") or "Change Time", buildTimeMenuItems(), 27
  elseif menuId == "weather" then
    title, items, size = session.config.translation(handle, "options.weather.title") or "Change Weather", buildWeatherMenuItems(), 27
  else
    title, items, size = session.config.translation(handle, "options.menu.title") or "Build Options", buildMainMenuItems(session, handle), 45
  end
  return session.menu.open(handle, title, size, items, {})
end

function M.handleOptionsClick(session, handle)
  return M.openMenu(session, handle, "main")
end

local function getPlot(session, handle)
  if session.state.phase ~= "BUILDING" then
    return nil
  end
  return session.state.playerPlot[handle]
end

local function getPlotMembers(session, plot)
  local members = {}
  for _, handle in ipairs(session.players()) do
    if getPlot(session, handle) == plot then
      members[#members + 1] = handle
    end
  end
  return members
end

local function sendMessage(session, handle, path)
  local message = session.config.translation(handle, path)
  if message then
    session.messages.sendRaw(handle, message)
  end
end

local function applyTime(session, handle, timeKey)
  local plot = getPlot(session, handle)
  if not plot then
    return
  end
  local ticks = TIME_TICKS[timeKey:lower()]
  if not ticks then
    return
  end
  session.state.plotTimeOverride[handle] = ticks
  for _, member in ipairs(getPlotMembers(session, plot)) do
    session.player.setTime(member, ticks, false)
  end
  sendMessage(session, handle, "options.messages.time_changed")
end

local function applyWeather(session, handle, weatherKey)
  local plot = getPlot(session, handle)
  if not plot then
    return
  end
  local weather = WEATHER_TYPES[weatherKey:lower()]
  if not weather then
    return
  end
  session.state.plotWeatherOverride[handle] = weather
  for _, member in ipairs(getPlotMembers(session, plot)) do
    session.player.setWeather(member, weather)
  end
  sendMessage(session, handle, "options.messages.weather_changed")
end

local function enterFloorChangeMode(session, handle)
  local plot = getPlot(session, handle)
  if not plot then
    return
  end
  session.state.floorChangeMode[handle] = true
  sendMessage(session, handle, "options.messages.floor_mode_entered")
end

local NON_FLOOR_MATERIALS = { WATER_BUCKET = true, LAVA_BUCKET = true }

function M.handleFloorChange(session, handle, material)
  if not session.state.floorChangeMode[handle] then
    return false
  end
  session.state.floorChangeMode[handle] = nil

  local plot = getPlot(session, handle)
  if not plot or not plot.min or not plot.max then
    return false
  end
  if NON_FLOOR_MATERIALS[material] or not session.world.materialIsSolidBlock(material) then
    sendMessage(session, handle, "options.messages.floor_invalid")
    return false
  end

  local minX = math.min(math.floor(plot.min.x), math.floor(plot.max.x))
  local maxX = math.max(math.floor(plot.min.x), math.floor(plot.max.x))
  local minY = math.min(math.floor(plot.min.y), math.floor(plot.max.y))
  local minZ = math.min(math.floor(plot.min.z), math.floor(plot.max.z))
  local maxZ = math.max(math.floor(plot.min.z), math.floor(plot.max.z))

  for x = minX, maxX do
    for z = minZ, maxZ do
      session.world.setBlockType(x, minY, z, material)
    end
  end

  sendMessage(session, handle, "options.messages.floor_changed")
  return true
end

local function resetPlot(session, handle, plotService)
  local plot = getPlot(session, handle)
  if not plot then
    return
  end
  local minX = math.min(math.floor(plot.min.x), math.floor(plot.max.x))
  local maxX = math.max(math.floor(plot.min.x), math.floor(plot.max.x))
  local minY = math.min(math.floor(plot.min.y), math.floor(plot.max.y))
  local maxY = math.max(math.floor(plot.min.y), math.floor(plot.max.y))
  local minZ = math.min(math.floor(plot.min.z), math.floor(plot.max.z))
  local maxZ = math.max(math.floor(plot.min.z), math.floor(plot.max.z))
  for x = minX, maxX do
    for y = minY, maxY do
      for z = minZ, maxZ do
        session.world.setBlockType(x, y, z, "AIR")
      end
    end
  end
  plotService.regeneratePlotFloor(session, plot)
  sendMessage(session, handle, "options.messages.plot_reset")
end

local function openBiomeMenu(session, handle)
  local plot = getPlot(session, handle)
  if not plot then
    return
  end
  local title = session.config.translation(handle, "options.biome.title") or "Select Biome"
  session.menu.open(handle, title, 27, buildBiomeMenuItems(session, handle), {})
end

local function selectBiome(session, handle, biomeName)
  local plot = getPlot(session, handle)
  if not plot or not plot.min or not plot.max then
    return
  end
  local minX = math.min(math.floor(plot.min.x), math.floor(plot.max.x))
  local maxX = math.max(math.floor(plot.min.x), math.floor(plot.max.x))
  local minY = math.min(math.floor(plot.min.y), math.floor(plot.max.y))
  local maxY = math.max(math.floor(plot.min.y), math.floor(plot.max.y))
  local minZ = math.min(math.floor(plot.min.z), math.floor(plot.max.z))
  local maxZ = math.max(math.floor(plot.min.z), math.floor(plot.max.z))
  for x = minX, maxX do
    for y = minY, maxY do
      for z = minZ, maxZ do
        session.world.setBiome(x, y, z, biomeName)
      end
    end
  end
  sendMessage(session, handle, "options.messages.biome_changed")
end

function M.handleModuleAction(session, handle, args, plotService)
  local action = args[1] and args[1]:lower()
  if action == "menu" then
    M.openMenu(session, handle, args[2] and args[2]:lower() or "main")
    return true
  elseif action == "time" then
    if args[2] then applyTime(session, handle, args[2]) end
    return true
  elseif action == "weather" then
    if args[2] then applyWeather(session, handle, args[2]) end
    return true
  elseif action == "floor" then
    enterFloorChangeMode(session, handle)
    return true
  elseif action == "reset" then
    resetPlot(session, handle, plotService)
    return true
  elseif action == "biome" then
    openBiomeMenu(session, handle)
    return true
  elseif action == "biome_select" then
    if args[2] then selectBiome(session, handle, args[2]:upper()) end
    return true
  elseif action == "banner" then
    return bannerService.handleModuleAction(session, handle, args)
  elseif action == "particle" then
    return particleService.handleModuleAction(session, handle, args)
  elseif action == "heads" then
    return headsService.handleModuleAction(session, handle, args)
  end
  return false
end

return M

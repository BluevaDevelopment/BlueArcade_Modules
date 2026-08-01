--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy StormService.java - a real per-world WorldBorder-driven shrinking storm, same WorldBorderBinding surface battle_royale already proved.
local M = {}

local WORLD_BORDER_DEFAULT_SIZE = 59999968.0
local WORLD_BORDER_DEFAULT_DAMAGE_BUFFER = 5.0
local WORLD_BORDER_DEFAULT_DAMAGE_AMOUNT = 0.2
local WORLD_BORDER_DEFAULT_WARNING_DISTANCE = 5
local WORLD_BORDER_DEFAULT_WARNING_TIME = 15

local function resolveBounds(session)
  local min = session.arena.boundsMin()
  local max = session.arena.boundsMax()
  if not min or not max then
    return nil
  end
  return min, max
end

local function resolveCenter(session)
  local min, max = resolveBounds(session)
  if min then
    return { x = (min.x + max.x) / 2.0, y = (min.y + max.y) / 2.0, z = (min.z + max.z) / 2.0 }
  end
  local players = session.players()
  if #players == 0 then
    return nil
  end
  return session.player.location(players[1])
end

local function resolveMaxRadius(session)
  local min, max = resolveBounds(session)
  if not min then
    return 1.0
  end
  local halfX = math.abs(max.x - min.x) / 2.0
  local halfZ = math.abs(max.z - min.z) / 2.0
  return math.max(1.0, math.min(halfX, halfZ))
end

local function initializeWorldBorder(session)
  if not session.state.stormCenter then
    return
  end
  local border = session.world.border
  border.setCenter(session.state.stormCenter)
  border.setSize(math.max(1.0, session.state.stormRadius * 2.0))
  border.setWarningDistance(0)
  border.setWarningTime(0)
  border.setDamageBuffer(0)
  border.setDamageAmount(math.max(0.0, session.state.stormDamagePerSecond))
end

local function startStormShrink(session)
  local finalRadius = math.max(1.0, session.state.stormFinalRadius)
  local durationSeconds = math.max(0, session.state.stormShrinkDurationSeconds)
  session.world.border.setSize(finalRadius * 2.0, durationSeconds)
end

function M.initializeStorm(session)
  local center = resolveCenter(session)
  session.state.stormCenter = center
  local maxRadius = resolveMaxRadius(session)
  session.state.stormMaxRadius = maxRadius
  session.state.stormFinalRadius = math.max(1.0, session.config.getDouble("storm.final_radius_blocks", 5.0))
  session.state.stormShrinkDurationSeconds = math.max(0, session.config.getInt("storm.shrink_duration_seconds", 120))
  session.state.stormDamagePerSecond = math.max(0.0, session.config.getDouble("storm.damage_per_second", 2.0))
  session.state.stormRadius = maxRadius

  initializeWorldBorder(session)
  startStormShrink(session)
end

local function resolveCurrentRadius(session)
  return math.max(0.0, session.world.border.getSize() / 2.0)
end

local function randomStormLocation(center, maxRadius, safeRadius)
  local minRadius = math.min(maxRadius, math.max(safeRadius + 2.0, safeRadius))
  local maxPickRadius = math.max(minRadius, maxRadius + 1.0)
  local radius = minRadius + math.random() * (maxPickRadius - minRadius)
  local angle = math.random() * math.pi * 2
  return {
    x = center.x + radius * math.cos(angle),
    y = center.y,
    z = center.z + radius * math.sin(angle),
  }
end

local function spawnStormLightning(session)
  if not session.config.getBoolean("storm.lightning.enabled", true) then
    return
  end
  local interval = session.config.getInt("storm.lightning.interval_seconds", 3)
  if interval <= 0 then
    return
  end

  session.state.stormLightningTicks = (session.state.stormLightningTicks or 0) + 1
  if session.state.stormLightningTicks < interval then
    return
  end
  session.state.stormLightningTicks = 0

  local strikes = session.config.getInt("storm.lightning.strikes_per_wave", 3)
  local center = session.state.stormCenter
  if not center then
    return
  end

  local radius = math.max(0.0, session.state.stormMaxRadius)
  local currentRadius = resolveCurrentRadius(session)
  for _ = 1, strikes do
    session.world.strikeLightningEffect(randomStormLocation(center, radius, currentRadius))
  end
end

function M.tickStorm(session)
  if not session.state.stormCenter then
    M.initializeStorm(session)
  end
  session.state.stormRadius = math.max(0.0, session.world.border.getSize() / 2.0)
  spawnStormLightning(session)
end

function M.clearWorldBorder(session)
  local border = session.world.border
  border.setSize(WORLD_BORDER_DEFAULT_SIZE)
  border.setDamageBuffer(WORLD_BORDER_DEFAULT_DAMAGE_BUFFER)
  border.setDamageAmount(WORLD_BORDER_DEFAULT_DAMAGE_AMOUNT)
  border.setWarningDistance(WORLD_BORDER_DEFAULT_WARNING_DISTANCE)
  border.setWarningTime(WORLD_BORDER_DEFAULT_WARNING_TIME)
end

return M

--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local fallingBlockService = require("support.falling_block_service")
local statsService = require("support.stats_service")
local messagingService = require("support.messaging_service")

local M = {}

local MAX_FLOOR_SCAN = 100

local function loadFloor(session, basePath, floorKey, index)
  local min = session.dataAccess.getGameLocation(basePath .. ".bounds.min")
  local max = session.dataAccess.getGameLocation(basePath .. ".bounds.max")
  if min == nil or max == nil then return nil end

  local autoRemove = session.dataAccess.getGameDataNumber(basePath .. ".auto_remove_time")
  local autoRemoveTime = autoRemove ~= nil and math.floor(autoRemove) or session.config.getInt("floors.default_auto_remove_seconds", 0)

  return { key = floorKey, index = index, min = min, max = max, autoRemoveTimeSeconds = autoRemoveTime }
end

local function resolveFloorTotal(session)
  local last = 0
  for i = 1, MAX_FLOOR_SCAN do
    if session.dataAccess.hasGameData("game.floors.f" .. i .. ".bounds.min.x") then
      last = i
    end
  end
  return last
end

function M.loadFloors(session)
  local floors = {}

  local total = session.dataAccess.getGameDataNumber("game.floors.total")
  local floorTotal = total ~= nil and math.floor(total) or 0
  if floorTotal == 0 then
    floorTotal = resolveFloorTotal(session)
  end

  -- pre-multi-floor single "game.floor" config, kept for migration compatibility
  if floorTotal == 0 and session.dataAccess.hasGameData("game.floor.bounds.min.x") then
    local floor = loadFloor(session, "game.floor", "floor", 1)
    if floor ~= nil then floors[#floors + 1] = floor end
    return floors
  end

  for i = 1, floorTotal do
    local floorKey = "f" .. i
    local floor = loadFloor(session, "game.floors." .. floorKey, floorKey, i)
    if floor ~= nil then floors[#floors + 1] = floor end
  end

  return floors
end

local function floorContains(floor, x, y, z)
  local minX, maxX = math.min(floor.min.x, floor.max.x), math.max(floor.min.x, floor.max.x)
  local minY, maxY = math.min(floor.min.y, floor.max.y), math.max(floor.min.y, floor.max.y)
  local minZ, maxZ = math.min(floor.min.z, floor.max.z), math.max(floor.min.z, floor.max.z)
  return x >= minX and x <= maxX and y >= minY and y <= maxY and z >= minZ and z <= maxZ
end

function M.findFloorAt(state, x, y, z)
  for _, floor in ipairs(state.floors) do
    if floorContains(floor, x, y, z) then return floor end
  end
  return nil
end

function M.shouldEliminate(session, to)
  if not session.isInsideBounds(to) then return true end

  local deathBlock = session.dataAccess.getGameDataString("basic.death_block")
  if deathBlock == nil then
    deathBlock = session.coreConfig.getSettingsString("game.global.default_death_block", "BARRIER")
  end
  deathBlock = string.upper(deathBlock)

  local blockBelow = session.world.blockTypeAt(math.floor(to.x), math.floor(to.y - 1), math.floor(to.z))
  return blockBelow == deathBlock
end

local function isFloorCandidate(session, state, x, y, z)
  local material = session.world.blockTypeAt(x, y, z)
  if material == "AIR" or material == "BARRIER" then return false end
  return M.findFloorAt(state, x, y, z) ~= nil
end

local function addBlockIfValid(session, state, blocks, x, y, z)
  if isFloorCandidate(session, state, x, y, z) then
    blocks[x .. "," .. y .. "," .. z] = { x = x, y = y, z = z }
  end
end

local function findBaseBlock(session, state, location)
  local playerX = math.floor(location.x)
  local playerZ = math.floor(location.z)
  local scanDepth = session.config.getInt("trail.detection.scan_depth", 3)

  for depth = 1, scanDepth do
    local y = math.floor(location.y) - depth
    if isFloorCandidate(session, state, playerX, y, playerZ) then
      return playerX, y, playerZ
    end
  end

  local standingY = math.floor(location.y)
  if isFloorCandidate(session, state, playerX, standingY, playerZ) then
    return playerX, standingY, playerZ
  end

  return nil
end

local function detectTouchedBlocks(session, state, location)
  local blocks = {}
  local baseX, baseY, baseZ = findBaseBlock(session, state, location)
  if baseX == nil then return blocks end

  local additionalBelow = session.config.getInt("trail.detection.additional_blocks_below", 1)
  local edgeThreshold = session.config.getDouble("trail.detection.edge_threshold", 0.25)

  addBlockIfValid(session, state, blocks, baseX, baseY, baseZ)
  for i = 1, additionalBelow do
    addBlockIfValid(session, state, blocks, baseX, baseY - i, baseZ)
  end

  local moveX = (location.x - math.floor(location.x)) - 0.5
  local moveZ = (location.z - math.floor(location.z)) - 0.5

  local xDir = 0
  if moveX > edgeThreshold then xDir = 1 elseif moveX < -edgeThreshold then xDir = -1 end
  local zDir = 0
  if moveZ > edgeThreshold then zDir = 1 elseif moveZ < -edgeThreshold then zDir = -1 end

  if xDir ~= 0 then
    addBlockIfValid(session, state, blocks, baseX + xDir, baseY, baseZ)
    for i = 1, additionalBelow do
      addBlockIfValid(session, state, blocks, baseX + xDir, baseY - i, baseZ)
    end
  end

  if zDir ~= 0 then
    addBlockIfValid(session, state, blocks, baseX, baseY, baseZ + zDir)
    for i = 1, additionalBelow do
      addBlockIfValid(session, state, blocks, baseX, baseY - i, baseZ + zDir)
    end
  end

  if xDir ~= 0 and zDir ~= 0 then
    addBlockIfValid(session, state, blocks, baseX + xDir, baseY, baseZ + zDir)
    for i = 1, additionalBelow do
      addBlockIfValid(session, state, blocks, baseX + xDir, baseY - i, baseZ + zDir)
    end
  end

  return blocks
end

local function resolveFloorDelayTicks(session)
  local delay = session.dataAccess.getGameDataNumber("basic.floor_delay")
  if delay == nil or delay <= 0 then
    return session.config.getInt("trail.floor_delay_ticks", 10)
  end
  return math.floor(delay)
end

local function spawnParticles(session, x, y, z, material)
  if not session.config.getBoolean("blocks.particles.enabled", true) then return end

  local particle = session.config.getString("blocks.particles.type") or "BLOCK"
  local count = session.config.getInt("blocks.particles.count", 12)
  local spread = session.config.getDouble("blocks.particles.spread", 0.35)
  local speed = session.config.getDouble("blocks.particles.speed", 0.15)
  local location = { x = x + 0.5, y = y + 0.5, z = z + 0.5 }

  if not session.world.spawnParticleAt(location, particle, count, spread, spread * 0.6, spread, speed, material) then
    session.world.spawnParticleAt(location, "CLOUD", count, spread, spread * 0.6, spread, speed)
  end
end

local function handleBlockRemoval(session, state, x, y, z, trigger)
  local material = session.world.blockTypeAt(x, y, z)
  if material == "AIR" or material == "BARRIER" then return end

  spawnParticles(session, x, y, z, material)
  if session.config.getBoolean("blocks.falling.enabled", true) then
    fallingBlockService.spawnFallingShard(session, { x = x + 0.5, y = y + 0.1, z = z + 0.5 }, material)
  end

  session.world.setBlockType(x, y, z, "AIR")
  state.removedBlocks[x .. "," .. y .. "," .. z] = true

  if trigger ~= nil then
    statsService.recordBlockDrop(session, trigger)
  end
end

local function scheduleBlockRemoval(session, state, x, y, z, trigger)
  local material = session.world.blockTypeAt(x, y, z)
  if material == "AIR" or material == "BARRIER" or material == "BEDROCK" then return end

  local belowMaterial = session.world.blockTypeAt(x, y - 1, z)
  if belowMaterial == "BEDROCK" or belowMaterial == "BARRIER" then return end

  local key = x .. "," .. y .. "," .. z
  if state.removedBlocks[key] or state.scheduledBlocks[key] then return end
  if M.findFloorAt(state, x, y, z) == nil then return end

  state.scheduledBlocks[key] = true
  local delayTicks = resolveFloorDelayTicks(session)
  local taskId = "arena_" .. session.arenaId .. "_tnt_run_block_" .. key

  session.scheduler.runLater(taskId, function()
    state.scheduledBlocks[key] = nil
    if state.ended then return end
    handleBlockRemoval(session, state, x, y, z, trigger)
  end, delayTicks)
end

function M.handlePlayerStep(session, state, handle, to)
  if session.phase() ~= "PLAYING" then return end

  local touched = detectTouchedBlocks(session, state, to)
  for _, block in pairs(touched) do
    scheduleBlockRemoval(session, state, block.x, block.y, block.z, handle)
  end
end

local function scheduleAggressiveBlockRemoval(session, state, x, y, z, trigger)
  local material = session.world.blockTypeAt(x, y, z)
  if material == "AIR" or material == "BARRIER" or material == "BEDROCK" then return end

  local belowMaterial = session.world.blockTypeAt(x, y - 1, z)
  if belowMaterial == "BEDROCK" or belowMaterial == "BARRIER" then return end

  local key = x .. "," .. y .. "," .. z
  if state.removedBlocks[key] then return end
  if M.findFloorAt(state, x, y, z) == nil then return end

  state.scheduledBlocks[key] = true
  local taskId = "arena_" .. session.arenaId .. "_tnt_run_aggressive_block_" .. key

  session.scheduler.runLater(taskId, function()
    state.scheduledBlocks[key] = nil
    if state.ended then return end
    handleBlockRemoval(session, state, x, y, z, trigger)
  end, 1)
end

local function breakBlocksAroundPlayer(session, state, handle, location)
  local radius = session.config.getInt("trail.detection.stationary_break_radius", 2)
  local scanDepth = session.config.getInt("trail.detection.scan_depth", 3)
  local additionalBelow = session.config.getInt("trail.detection.additional_blocks_below", 1)
  local playerX = math.floor(location.x)
  local playerZ = math.floor(location.z)

  for depth = 0, scanDepth do
    local baseY = math.floor(location.y) - depth
    for dx = -radius, radius do
      for dz = -radius, radius do
        local x, z = playerX + dx, playerZ + dz
        if M.findFloorAt(state, x, baseY, z) ~= nil then
          scheduleAggressiveBlockRemoval(session, state, x, baseY, z, handle)
          for i = 1, additionalBelow do
            if M.findFloorAt(state, x, baseY - i, z) ~= nil then
              scheduleAggressiveBlockRemoval(session, state, x, baseY - i, z, handle)
            end
          end
        end
      end
    end
  end
end

function M.updatePlayerPosition(session, state, handle, location)
  local key = math.floor(location.x) .. "," .. math.floor(location.y) .. "," .. math.floor(location.z)
  local lastKey = state.lastPlayerPosition[handle]

  if lastKey == nil or lastKey ~= key then
    state.lastPlayerPosition[handle] = key
    state.playerStationaryTicks[handle] = 0
    return
  end

  local scanInterval = session.config.getInt("trail.detection.stationary_scan_ticks", 4)
  local stationaryTicks = (state.playerStationaryTicks[handle] or 0) + scanInterval
  state.playerStationaryTicks[handle] = stationaryTicks

  local maxTicks = session.config.getInt("trail.detection.stationary_max_ticks", 8)
  if stationaryTicks >= maxTicks then
    breakBlocksAroundPlayer(session, state, handle, location)
    state.playerStationaryTicks[handle] = 0
  end
end

function M.startFloorRemovalTimers(session, state)
  for _, floor in ipairs(state.floors) do
    local autoRemoveTime = floor.autoRemoveTimeSeconds
    if autoRemoveTime > 0 then
      local warnings = session.config.getStringList("floors.auto_remove_warnings_seconds")
      for _, warningStr in ipairs(warnings) do
        local warning = tonumber(warningStr)
        if warning ~= nil and warning > 0 and warning < autoRemoveTime then
          local delayTicks = (autoRemoveTime - warning) * 20
          session.scheduler.runLater("arena_" .. session.arenaId .. "_tnt_run_floor_warning_" .. floor.key .. "_" .. warning, function()
            if state.ended then return end
            messagingService.sendFloorRemovalWarning(session, floor.index, warning)
          end, delayTicks)
        end
      end

      session.scheduler.runLater("arena_" .. session.arenaId .. "_tnt_run_floor_remove_" .. floor.key, function()
        if state.ended then return end
        messagingService.sendFloorRemoved(session, floor.index)
        M.removeEntireFloor(session, state, floor)
      end, autoRemoveTime * 20)
    end
  end
end

function M.removeEntireFloor(session, state, floor)
  local minX, maxX = math.floor(math.min(floor.min.x, floor.max.x)), math.floor(math.max(floor.min.x, floor.max.x))
  local minY, maxY = math.floor(math.min(floor.min.y, floor.max.y)), math.floor(math.max(floor.min.y, floor.max.y))
  local minZ, maxZ = math.floor(math.min(floor.min.z, floor.max.z)), math.floor(math.max(floor.min.z, floor.max.z))

  for x = minX, maxX do
    for y = minY, maxY do
      for z = minZ, maxZ do
        local material = session.world.blockTypeAt(x, y, z)
        if material ~= "AIR" and material ~= "BARRIER" then
          handleBlockRemoval(session, state, x, y, z, nil)
        end
      end
    end
  end
end

return M

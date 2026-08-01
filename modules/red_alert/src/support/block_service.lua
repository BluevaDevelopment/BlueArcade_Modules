--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local fallingBlockService = require("support.falling_block_service")
local statsService = require("support.stats_service")

local M = {}

local STAGE_PATHS = { "blocks.stages.safe", "blocks.stages.warn", "blocks.stages.danger", "blocks.stages.critical" }
local STAGE_DEFAULTS = { "WHITE_CONCRETE", "YELLOW_CONCRETE", "ORANGE_CONCRETE", "RED_CONCRETE" }
local STAGE_DELAY_PATHS = {
  "trail_mode.stage_advance_ticks.safe_to_warn",
  "trail_mode.stage_advance_ticks.warn_to_danger",
  "trail_mode.stage_advance_ticks.danger_to_critical",
  "trail_mode.stage_advance_ticks.critical_to_air",
}

local function locationKey(x, y, z)
  return x .. "," .. y .. "," .. z
end

local function parseKey(key)
  local x, y, z = string.match(key, "(-?%d+),(-?%d+),(-?%d+)")
  return tonumber(x), tonumber(y), tonumber(z)
end

-- Settings cached once at match start (matching RedAlertSettings.load()) rather than re-reading
-- session.config on every block tick across a potentially large floor.
function M.cacheSettings(session)
  local stageMaterials = {}
  for i, path in ipairs(STAGE_PATHS) do
    stageMaterials[i] = session.config.getString(path) or STAGE_DEFAULTS[i]
  end

  local trailHoldInterval = math.max(1, session.config.getInt("trail_mode.hold_interval_ticks", 12))

  local stageAdvanceTicks = {}
  for i, path in ipairs(STAGE_DELAY_PATHS) do
    stageAdvanceTicks[i] = math.max(1, session.config.getInt(path, 12))
  end
  while #stageAdvanceTicks < #stageMaterials do
    local fallback = #stageAdvanceTicks == 0 and trailHoldInterval or stageAdvanceTicks[#stageAdvanceTicks]
    stageAdvanceTicks[#stageAdvanceTicks + 1] = fallback
  end

  session.state.settings = {
    stageMaterials = stageMaterials,
    stageAdvanceTicks = stageAdvanceTicks,
    particlesEnabled = session.config.getBoolean("blocks.particles.enabled", true),
    decayParticle = session.config.getString("blocks.particles.type") or "FLAME",
    particleCount = session.config.getInt("blocks.particles.count", 12),
    particleSpread = session.config.getDouble("blocks.particles.spread", 0.35),
    particleSpeed = session.config.getDouble("blocks.particles.speed", 0.15),
    fallingBlocksEnabled = session.config.getBoolean("blocks.falling.enabled", true),
    eliminationMargin = session.config.getDouble("gameplay.elimination_margin", 1.0),
    chaosBaseChance = session.config.getDouble("random_mode.change_color_chance", 1.5),
    chaosChanceIncrease = session.config.getDouble("random_mode.increase_chance_every_second", 1.0),
    chaosTickRate = math.max(1, session.config.getInt("random_mode.tick_rate", 20)),
    trailHoldInterval = trailHoldInterval,
    criticalBreakDelayTicks = math.max(0, session.config.getInt("trail_mode.critical_break_delay_ticks", 0)),
    detectionScanDepth = math.max(1, session.config.getInt("trail_mode.detection.scan_depth", 3)),
    detectionAdditionalBelow = math.max(0, session.config.getInt("trail_mode.detection.additional_blocks_below", 0)),
    detectionEdgeThreshold = math.max(0.0, session.config.getDouble("trail_mode.detection.edge_threshold", 0.25)),
    accelerateHotBlockTouches = session.config.getBoolean("trail_mode.accelerate_hot_block_touches", true),
  }
end

-- No static-arena FloorRegion fallback here (unlike legacy's findFloorBounds) - a .bamodule arena
-- is always dynamic and always writes game.floor.bounds itself.
function M.cacheFloorBounds(session)
  session.state.floorMin = session.dataAccess.getGameLocation("game.floor.bounds.min")
  session.state.floorMax = session.dataAccess.getGameLocation("game.floor.bounds.max")
end

local function floorBoundsRange(session)
  local min, max = session.state.floorMin, session.state.floorMax
  return math.min(math.floor(min.x), math.floor(max.x)), math.max(math.floor(min.x), math.floor(max.x)),
      math.min(math.floor(min.y), math.floor(max.y)), math.max(math.floor(min.y), math.floor(max.y)),
      math.min(math.floor(min.z), math.floor(max.z)), math.max(math.floor(min.z), math.floor(max.z))
end

function M.resetFloor(session)
  if session.state.floorMin == nil or session.state.floorMax == nil then return end
  local firstStage = session.state.settings.stageMaterials[1]
  if firstStage == nil then return end

  local minX, maxX, minY, maxY, minZ, maxZ = floorBoundsRange(session)
  for x = minX, maxX do
    for y = minY, maxY do
      for z = minZ, maxZ do
        session.world.setBlockType(x, y, z, firstStage)
      end
    end
  end
end

function M.shouldEliminate(session, to)
  if not session.isInsideBounds(to) then return true end

  local min, max = session.state.floorMin, session.state.floorMax
  if min == nil or max == nil then return false end

  local minY = math.min(min.y, max.y)
  return to.y < minY - session.state.settings.eliminationMargin
end

local function getStageIndex(session, materialName)
  local stageMaterials = session.state.settings.stageMaterials
  for i, material in ipairs(stageMaterials) do
    if material == materialName then return i - 1 end
  end
  return #stageMaterials
end

local function clampStage(session, stage)
  local count = #session.state.settings.stageMaterials
  if stage < 0 or stage >= count then return 0 end
  return stage
end

local function getStageDelay(session, stage)
  local ticks = session.state.settings.stageAdvanceTicks
  if #ticks == 0 then return session.state.settings.trailHoldInterval end
  if stage >= 0 and stage < #ticks then return ticks[stage + 1] end
  return ticks[#ticks]
end

local function resolveTrackedStage(session, key, fallbackMaterial)
  local stage = session.state.trackedTrailStages[key]
  if stage ~= nil then return stage end
  return clampStage(session, getStageIndex(session, fallbackMaterial))
end

local function removeBlockTracking(session, key)
  session.state.blockProgress[key] = nil
  session.state.trackedTrailBlocks[key] = nil
  session.state.trackedTrailStages[key] = nil
end

local function registerBlockTracking(session, key, currentTick, stage, allowImmediateAdvance)
  local clampedStage = clampStage(session, stage)
  local storedTick = currentTick
  if allowImmediateAdvance then
    storedTick = currentTick - getStageDelay(session, clampedStage)
  end
  session.state.blockProgress[key] = storedTick
  if session.state.mode == "trail" then
    session.state.trackedTrailBlocks[key] = true
    session.state.trackedTrailStages[key] = clampedStage
  end
end

local function updateProgressTracking(session, key, currentTick, result, resultingStage)
  if result == "NO_CHANGE" then return end
  if result == "REMOVED" then
    removeBlockTracking(session, key)
    return
  end
  registerBlockTracking(session, key, currentTick, resultingStage, false)
end

local function progressBlock(session, x, y, z, key, currentTick, targetStage, triggerHandle, ignoreCriticalDelay)
  local settings = session.state.settings
  local stageMaterials = settings.stageMaterials
  local stageCount = #stageMaterials
  local currentType = session.world.blockTypeAt(x, y, z)
  local currentStage = resolveTrackedStage(session, key, currentType)

  if currentStage >= stageCount and targetStage <= currentStage then return "NO_CHANGE" end
  if targetStage <= currentStage then return "NO_CHANGE" end

  local cappedStage = math.min(targetStage, stageCount)
  local nextMaterial = cappedStage >= stageCount and "AIR" or stageMaterials[cappedStage + 1]

  if cappedStage >= stageCount then
    if not ignoreCriticalDelay and settings.criticalBreakDelayTicks > 0 and currentStage == stageCount - 1 then
      local lastTick = session.state.blockProgress[key]
      if lastTick ~= nil and currentTick - lastTick < settings.criticalBreakDelayTicks then
        return "NO_CHANGE"
      end
    end

    session.world.setBlockType(x, y, z, "AIR")
    if settings.fallingBlocksEnabled and currentType ~= "AIR" then
      local shardLocation = { x = x + 0.5, y = y + 0.1, z = z + 0.5, yaw = 0, pitch = 0 }
      fallingBlockService.spawnFallingShard(session, shardLocation, currentType)
    end
    if settings.particlesEnabled then
      local particleLocation = { x = x + 0.5, y = y + 0.5, z = z + 0.5, yaw = 0, pitch = 0 }
      session.world.spawnParticleAt(particleLocation, settings.decayParticle, settings.particleCount,
        settings.particleSpread, settings.particleSpread * 0.6, settings.particleSpread, settings.particleSpeed)
    end
    if triggerHandle ~= nil then
      statsService.recordTileMelt(session, triggerHandle)
    end
    return "REMOVED"
  end

  session.world.setBlockType(x, y, z, nextMaterial)
  return "ADVANCED"
end

local function isOnCooldown(session, key, currentTick)
  local lastTick = session.state.blockProgress[key]
  return lastTick ~= nil and (currentTick - lastTick) < session.state.settings.trailHoldInterval
end

local function progressTrailTouch(session, x, y, z, triggerHandle, checkCooldown, expedite)
  local key = locationKey(x, y, z)
  local blockType = session.world.blockTypeAt(x, y, z)
  local settings = session.state.settings
  local stageCount = #settings.stageMaterials
  local currentStage = resolveTrackedStage(session, key, blockType)
  if currentStage >= stageCount then return end

  local currentTick = session.world.getFullTime()
  local lastTick = session.state.blockProgress[key]
  local requiredDelay = getStageDelay(session, currentStage)

  if not expedite and checkCooldown and currentStage < stageCount - 1 and isOnCooldown(session, key, currentTick) then
    return
  end
  if not expedite and settings.criticalBreakDelayTicks > 0 and currentStage == stageCount - 1 and lastTick ~= nil then
    if currentTick - lastTick < settings.criticalBreakDelayTicks then return end
  end
  if lastTick ~= nil then
    local adjustedDelay = expedite and math.max(1, math.floor(requiredDelay / 2)) or requiredDelay
    if currentTick - lastTick < adjustedDelay then return end
  end

  local targetStage = currentStage + 1
  local result = progressBlock(session, x, y, z, key, currentTick, targetStage, triggerHandle, expedite)
  updateProgressTracking(session, key, currentTick, result, targetStage)
end

local function ensureTrackedAndRescue(session, x, y, z, currentTick)
  local key = locationKey(x, y, z)
  local blockType = session.world.blockTypeAt(x, y, z)
  local stage = clampStage(session, getStageIndex(session, blockType))

  if session.state.blockProgress[key] ~= nil then return false end

  registerBlockTracking(session, key, currentTick, stage, true)
  if stage > 0 then
    progressTrailTouch(session, x, y, z, nil, false, true)
    return true
  end
  return false
end

local function isFloorCandidate(session, x, y, z)
  if session.state.floorMin == nil or session.state.floorMax == nil then return false end
  local minX, maxX, minY, maxY, minZ, maxZ = floorBoundsRange(session)
  if x < minX or x > maxX or y < minY or y > maxY or z < minZ or z > maxZ then return false end

  local blockType = session.world.blockTypeAt(x, y, z)
  return blockType ~= "AIR" and blockType ~= "BARRIER"
end

local function addBlockIfValid(session, blocks, x, y, z)
  if isFloorCandidate(session, x, y, z) then
    blocks[locationKey(x, y, z)] = { x = x, y = y, z = z }
  end
end

local function findBaseBlock(session, playerLocation)
  local settings = session.state.settings
  local px, pz = math.floor(playerLocation.x), math.floor(playerLocation.z)

  for depth = 1, settings.detectionScanDepth do
    local y = math.floor(playerLocation.y) - depth
    if isFloorCandidate(session, px, y, pz) then return px, y, pz end
  end

  local standingY = math.floor(playerLocation.y)
  if isFloorCandidate(session, px, standingY, pz) then return px, standingY, pz end

  return nil
end

local function detectTouchedBlocks(session, playerLocation)
  local blocks = {}
  local baseX, baseY, baseZ = findBaseBlock(session, playerLocation)
  if baseX == nil then return blocks end

  local settings = session.state.settings
  addBlockIfValid(session, blocks, baseX, baseY, baseZ)
  for i = 1, settings.detectionAdditionalBelow do
    addBlockIfValid(session, blocks, baseX, baseY - i, baseZ)
  end

  local moveX = playerLocation.x - math.floor(playerLocation.x) - 0.5
  local moveZ = playerLocation.z - math.floor(playerLocation.z) - 0.5

  local xDir = 0
  if moveX > settings.detectionEdgeThreshold then xDir = 1
  elseif moveX < -settings.detectionEdgeThreshold then xDir = -1 end

  local zDir = 0
  if moveZ > settings.detectionEdgeThreshold then zDir = 1
  elseif moveZ < -settings.detectionEdgeThreshold then zDir = -1 end

  if xDir ~= 0 then
    addBlockIfValid(session, blocks, baseX + xDir, baseY, baseZ)
    for i = 1, settings.detectionAdditionalBelow do
      addBlockIfValid(session, blocks, baseX + xDir, baseY - i, baseZ)
    end
  end

  if zDir ~= 0 then
    addBlockIfValid(session, blocks, baseX, baseY, baseZ + zDir)
    for i = 1, settings.detectionAdditionalBelow do
      addBlockIfValid(session, blocks, baseX, baseY - i, baseZ + zDir)
    end
  end

  if xDir ~= 0 and zDir ~= 0 then
    addBlockIfValid(session, blocks, baseX + xDir, baseY, baseZ + zDir)
    for i = 1, settings.detectionAdditionalBelow do
      addBlockIfValid(session, blocks, baseX + xDir, baseY - i, baseZ + zDir)
    end
  end

  return blocks
end

function M.handlePlayerStep(session, handle, to)
  if session.phase() ~= "PLAYING" then return end
  if session.state.mode ~= "trail" then return end
  if session.state.floorMin == nil or session.state.floorMax == nil then return end

  local touchedBlocks = detectTouchedBlocks(session, to)
  for _, block in pairs(touchedBlocks) do
    local currentTick = session.world.getFullTime()
    local rescued = ensureTrackedAndRescue(session, block.x, block.y, block.z, currentTick)
    local expedite = session.state.settings.accelerateHotBlockTouches
        and getStageIndex(session, session.world.blockTypeAt(block.x, block.y, block.z)) > 0
    if not rescued then
      progressTrailTouch(session, block.x, block.y, block.z, handle, false, expedite)
    end
  end
end

local function applyChaosTick(session, chance)
  if session.state.floorMin == nil or session.state.floorMax == nil then return end

  local minX, maxX, minY, maxY, minZ, maxZ = floorBoundsRange(session)
  local stageCount = #session.state.settings.stageMaterials

  for x = minX, maxX do
    for y = minY, maxY do
      for z = minZ, maxZ do
        if math.random() * 100 < chance then
          local blockType = session.world.blockTypeAt(x, y, z)
          local stage = getStageIndex(session, blockType)
          if stage < stageCount then
            local key = locationKey(x, y, z)
            local currentTick = session.world.getFullTime()
            local result = progressBlock(session, x, y, z, key, currentTick, stage + 1, nil, false)
            updateProgressTracking(session, key, currentTick, result, stage + 1)
          end
        end
      end
    end
  end
end

local function startChaosTask(session, taskId)
  if session.state.floorMin == nil then return end

  local settings = session.state.settings
  local chance = { settings.chaosBaseChance }
  local incrementPerRun = settings.chaosChanceIncrease * (settings.chaosTickRate / 20.0)

  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end

    applyChaosTick(session, chance[1])
    chance[1] = math.min(100.0, chance[1] + incrementPerRun)
  end, 0, settings.chaosTickRate)
end

local function resyncUntrackedBlocks(session, currentTick)
  if session.state.mode ~= "trail" then return end
  if session.state.floorMin == nil or session.state.floorMax == nil then return end

  local minX, maxX, minY, maxY, minZ, maxZ = floorBoundsRange(session)
  local stageCount = #session.state.settings.stageMaterials

  for x = minX, maxX do
    for y = minY, maxY do
      for z = minZ, maxZ do
        local key = locationKey(x, y, z)
        local blockType = session.world.blockTypeAt(x, y, z)

        if (blockType == "AIR" or blockType == "BARRIER") and session.state.trackedTrailBlocks[key] then
          removeBlockTracking(session, key)
        else
          local stage = getStageIndex(session, blockType)
          if stage > 0 and stage < stageCount then
            session.state.trackedTrailBlocks[key] = true
            session.state.trackedTrailStages[key] = stage

            local candidate = currentTick - getStageDelay(session, stage)
            local existing = session.state.blockProgress[key]
            if existing == nil or candidate < existing then
              session.state.blockProgress[key] = candidate
            end
          end
        end
      end
    end
  end
end

local function processStaleBlocks(session, currentTick)
  local trackedBlocks = session.state.trackedTrailBlocks
  local isEmpty = true
  for _ in pairs(trackedBlocks) do
    isEmpty = false
    break
  end
  if isEmpty then
    for key in pairs(session.state.blockProgress) do
      trackedBlocks[key] = true
    end
  end

  local keys = {}
  for key in pairs(trackedBlocks) do keys[#keys + 1] = key end

  for _, key in ipairs(keys) do
    local x, y, z = parseKey(key)
    local lastTick = session.state.blockProgress[key]
    local blockType = session.world.blockTypeAt(x, y, z)

    if session.state.trackedTrailStages[key] == nil then
      session.state.trackedTrailStages[key] = clampStage(session, getStageIndex(session, blockType))
    end
    local stage = resolveTrackedStage(session, key, blockType)
    local cappedStage = math.min(stage, #session.state.settings.stageMaterials - 1)

    if lastTick == nil then
      lastTick = currentTick
      session.state.blockProgress[key] = lastTick
    end

    local requiredDelay = getStageDelay(session, cappedStage)
    if currentTick - lastTick >= requiredDelay then
      local result = progressBlock(session, x, y, z, key, currentTick, cappedStage + 1, nil, false)
      updateProgressTracking(session, key, currentTick, result, cappedStage + 1)
    end
  end
end

local function startTrailHoldTask(session, taskId)
  local interval = session.state.settings.trailHoldInterval

  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end

    local currentTick = session.world.getFullTime()

    if session.state.floorMin ~= nil and session.state.floorMax ~= nil then
      for _, handle in ipairs(session.alivePlayers()) do
        local location = session.player.location(handle)
        local touchedBlocks = detectTouchedBlocks(session, location)
        for _, block in pairs(touchedBlocks) do
          local blockTick = session.world.getFullTime()
          local rescued = ensureTrackedAndRescue(session, block.x, block.y, block.z, blockTick)
          local expedite = session.state.settings.accelerateHotBlockTouches
              and getStageIndex(session, session.world.blockTypeAt(block.x, block.y, block.z)) > 0
          if not rescued then
            progressTrailTouch(session, block.x, block.y, block.z, handle, false, expedite)
          end
        end
      end

      resyncUntrackedBlocks(session, currentTick)
    end

    processStaleBlocks(session, currentTick)
  end, interval, interval)
end

function M.startModeTasks(session)
  local taskId = "arena_" .. session.arenaId .. "_red_alert_mode"
  if session.state.mode == "chaos" then
    startChaosTask(session, taskId)
  else
    startTrailHoldTask(session, taskId)
  end
end

return M

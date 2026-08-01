local M = {}

local POWERUP_TYPES = { "TELEPORT", "PATCH", "SPEED", "BONUS_TIME" }

local function locationKey(x, y, z)
  return x .. "," .. y .. "," .. z
end

local function randomType()
  return POWERUP_TYPES[math.random(#POWERUP_TYPES)]
end

local function plainName(powerupType)
  return powerupType:lower():gsub("_", " ")
end

local function schedulePowerupParticles(session, x, y, z)
  local taskId = "arena_" .. session.arenaId .. "_block_party_powerup_particles_" .. x .. "_" .. y .. "_" .. z
  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end
    local material = session.config.getString("powerups.item") or "BEACON"
    if session.world.blockTypeAt(x, y, z) ~= material then
      session.scheduler.cancelTask(taskId)
      return
    end

    local particle = session.config.getString("powerups.particles.type") or "WITCH"
    if particle:upper() == "WITCH" then particle = "SPELL_WITCH" end
    local count = session.config.getInt("powerups.particles.count", 12)
    local spread = session.config.getDouble("powerups.particles.spread", 0.35)
    local speed = session.config.getDouble("powerups.particles.speed", 0.12)
    local location = { x = x + 0.5, y = y + 0.6, z = z + 0.5 }
    if not session.world.spawnParticleAt(location, particle, count, spread, spread, spread, speed) then
      session.world.spawnParticleAt(location, "CLOUD", count, spread, spread, spread, speed)
    end
  end, 0, 10)
  return taskId
end

function M.startPowerupSpawns(session)
  if not session.config.getBoolean("powerups.enabled", true) then return end

  local interval = math.max(20, session.config.getInt("powerups.spawn_interval_ticks", 200))
  local taskId = "arena_" .. session.arenaId .. "_block_party_powerups"

  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end

    local maxActive = session.config.getInt("powerups.max_active", 2)
    local count = 0
    for _ in pairs(session.state.activePowerups) do count = count + 1 end
    if count >= maxActive then return end

    M.spawnPowerup(session)
  end, interval, interval)
end

function M.clearArenaPowerups(session)
  for key, instance in pairs(session.state.activePowerups) do
    M.removePowerupAt(session, instance.location, false)
  end
end

function M.spawnPowerup(session)
  local state = session.state
  if state.currentBlocks == nil or next(state.currentBlocks) == nil then return end

  local positions = {}
  for key, block in pairs(state.currentBlocks) do
    if block.material ~= state.targetMaterial then
      if session.world.blockTypeAt(block.x, block.y, block.z) ~= "AIR" then
        positions[#positions + 1] = block
      end
    end
  end
  if #positions == 0 then return end

  local support = positions[math.random(#positions)]
  local px, py, pz = support.x, support.y + 1, support.z
  local originalMaterial = session.world.blockTypeAt(px, py, pz)
  local itemMaterial = session.config.getString("powerups.item") or "BEACON"
  session.world.setBlockType(px, py, pz, itemMaterial)

  local powerupType = randomType()
  local lines = {
    "<gold>POWER UP</gold>",
    "<aqua>" .. (session.config.translation(nil, "powerup_names." .. powerupType) or powerupType) .. "</aqua>",
  }
  local hologramHandle = session.hologram.spawn({ x = px + 0.5, y = py + 1.35, z = pz + 0.5 }, lines)
  local particleTaskId = schedulePowerupParticles(session, px, py, pz)

  session.state.activePowerups[locationKey(px, py, pz)] = {
    type = powerupType,
    location = { x = px, y = py, z = pz },
    supportLocation = { x = support.x, y = support.y, z = support.z },
    originalMaterial = originalMaterial,
    hologram = hologramHandle,
    particleTaskId = particleTaskId,
  }
end

function M.isPowerupBlock(session, location)
  local key = locationKey(math.floor(location.x), math.floor(location.y), math.floor(location.z))
  return session.state.activePowerups[key] ~= nil
end

function M.removePowerupAt(session, location, restoreBlock)
  local x, y, z = math.floor(location.x), math.floor(location.y), math.floor(location.z)
  local key = locationKey(x, y, z)
  local instance = session.state.activePowerups[key]
  if instance == nil then return nil end
  session.state.activePowerups[key] = nil

  if instance.particleTaskId ~= nil then
    session.scheduler.cancelTask(instance.particleTaskId)
  end
  if instance.hologram ~= nil then
    session.hologram.delete(instance.hologram)
  end

  if restoreBlock then
    session.world.setBlockType(x, y, z, instance.originalMaterial)
  else
    session.world.setBlockType(x, y, z, "AIR")
  end

  return instance
end

function M.removePowerupWithSupport(session, supportLocation, restoreBlock)
  if supportLocation == nil then return nil end
  local sx, sy, sz = math.floor(supportLocation.x), math.floor(supportLocation.y), math.floor(supportLocation.z)
  for key, instance in pairs(session.state.activePowerups) do
    if instance.supportLocation ~= nil
        and math.floor(instance.supportLocation.x) == sx
        and math.floor(instance.supportLocation.y) == sy
        and math.floor(instance.supportLocation.z) == sz then
      return M.removePowerupAt(session, instance.location, restoreBlock)
    end
  end
  return nil
end

function M.removeActivePowerups(session)
  for _, instance in pairs(session.state.activePowerups) do
    M.removePowerupAt(session, instance.location, false)
  end
end

local function findSafeTarget(session, state)
  local targets = {}
  for _, block in pairs(state.currentBlocks) do
    if block.material == state.targetMaterial then
      targets[#targets + 1] = { x = block.x + 0.5, y = block.y + 1, z = block.z + 0.5 }
    end
  end
  if #targets == 0 then
    return session.arena.randomSpawn()
  end
  return targets[math.random(#targets)]
end

local function applyColorPatch(session, state)
  local alive = session.alivePlayers()
  if #alive == 0 then return end

  local minY = math.min(state.floor.min.y, state.floor.max.y)
  local player = alive[math.random(#alive)]
  local center = session.player.location(player)
  local radius = math.max(1, session.config.getInt("powerups.patch.radius", 2))
  local centerX, centerZ = math.floor(center.x), math.floor(center.z)

  for dx = -radius, radius do
    for dz = -radius, radius do
      local x, z = centerX + dx, centerZ + dz
      local loc = { x = x, y = minY, z = z }
      if state.floor ~= nil and x >= math.min(state.floor.min.x, state.floor.max.x) and x <= math.max(state.floor.min.x, state.floor.max.x)
          and z >= math.min(state.floor.min.z, state.floor.max.z) and z <= math.max(state.floor.min.z, state.floor.max.z) then
        session.world.setBlockType(x, minY, z, state.targetMaterial)
        state.currentBlocks[locationKey(x, minY, z)] = { x = x, y = minY, z = z, material = state.targetMaterial }
      end
    end
  end
end

function M.applyPowerupEffect(session, handle, powerupType)
  local state = session.state

  if powerupType == "TELEPORT" then
    local target = findSafeTarget(session, state)
    if target ~= nil then session.player.teleport(handle, target) end
  elseif powerupType == "PATCH" then
    applyColorPatch(session, state)
  elseif powerupType == "SPEED" then
    local duration = math.max(1, session.config.getInt("powerups.speed.duration_ticks", 160))
    local amplifier = math.max(0, session.config.getInt("powerups.speed.amplifier", 1))
    session.player.addPotionEffect(handle, "SPEED", duration, amplifier)
  elseif powerupType == "BONUS_TIME" then
    if state.phase == "SEARCH" then
      local bonus = session.config.getInt("powerups.bonus_time_ticks", 40)
      state.phaseTicksRemaining = state.phaseTicksRemaining + bonus
      state.phaseTotalTicks = state.phaseTotalTicks + bonus
    end
  end

  if session.config.getBoolean("powerups.particles.enabled", true) then
    local particle = session.config.getString("powerups.particles.type") or "WITCH"
    if particle:upper() == "WITCH" then particle = "SPELL_WITCH" end
    local count = session.config.getInt("powerups.particles.count", 12)
    local spread = session.config.getDouble("powerups.particles.spread", 0.35)
    local speed = session.config.getDouble("powerups.particles.speed", 0.12)
    local location = session.player.location(handle)
    location.y = location.y + 1
    if not session.world.spawnParticleAt(location, particle, count, spread, spread, spread, speed) then
      session.world.spawnParticleAt(location, "CLOUD", count, spread, spread, spread, speed)
    end
  end
end

function M.handlePowerupPickup(session, handle, location)
  if not session.isPlaying(handle) then return end

  local instance = M.removePowerupAt(session, location, true)
  if instance == nil then return end

  M.applyPowerupEffect(session, handle, instance.type)

  return instance.type
end

function M.plainName(powerupType)
  return plainName(powerupType)
end

return M

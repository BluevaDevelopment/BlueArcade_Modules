local M = {}

local function getRandomSheepSpawn(session)
  local min = session.arena.boundsMin()
  local max = session.arena.boundsMax()
  if min == nil or max == nil then return nil end

  local minX, maxX = math.min(min.x, max.x), math.max(min.x, max.x)
  local minZ, maxZ = math.min(min.z, max.z), math.max(min.z, max.z)

  local x = minX + (maxX - minX) * math.random()
  local z = minZ + (maxZ - minZ) * math.random()
  local highestY = session.world.getHighestBlockY(math.floor(x), math.floor(z))
  local topY = math.max(min.y, max.y)
  local bottomY = math.min(min.y, max.y)
  local spawnY = highestY + session.config.getDouble("sheep.spawning.height_offset", 1.0)
  local clampedY = math.min(math.max(spawnY, bottomY + 1), topY + 1)

  local spawn = { x = x + 0.5, y = clampedY, z = z + 0.5, yaw = 0, pitch = 0 }
  if session.isInsideBounds(spawn) then return spawn end
  return nil
end

function M.spawnSheep(session)
  local spawn = nil
  for _ = 1, 6 do
    spawn = getRandomSheepSpawn(session)
    if spawn ~= nil then break end
  end
  if spawn == nil then return end

  local handle = session.world.spawnEntity(spawn, "SHEEP")
  if handle == nil then return end
  session.entities.prepareGameSheep(handle)

  local fuseSeconds = math.max(5, session.config.getInt("sheep.fuse.duration_seconds", 16))
  session.state.sheep[handle] = {
    ticksLeft = fuseSeconds * 20,
    blinkState = false,
    warningTicks = 0,
    blinkTicks = 0,
  }
end

function M.startSheepSpawner(session)
  local taskId = "arena_" .. session.arenaId .. "_exploding_sheep_spawns"
  local intervalTicks = session.config.getInt("sheep.spawning.interval_ticks", 20)
  local perPlayer = math.max(1, session.config.getInt("sheep.spawning.per_player", 3))
  local minSheep = math.max(perPlayer, session.config.getInt("sheep.spawning.min_sheep", 20))
  local batchSize = math.max(1, session.config.getInt("sheep.spawning.batch_size", 5))
  local maxSheep = math.max(minSheep, session.config.getInt("sheep.spawning.max_sheep", 90))

  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end
    if session.phase() ~= "PLAYING" then return end

    local aliveCount = #session.alivePlayers()
    if aliveCount == 0 then return end

    local trackedCount = 0
    for _ in pairs(session.state.sheep) do trackedCount = trackedCount + 1 end
    if trackedCount >= maxSheep then return end

    local desiredSheep = math.min(maxSheep, math.max(minSheep, aliveCount * perPlayer))
    local toSpawn = math.min(batchSize, math.max(0, desiredSheep - trackedCount))

    for _ = 1, toSpawn do
      M.spawnSheep(session)
    end
  end, 0, intervalTicks)
end

local function applyFuseWarnings(session, handle, data, sheepLocation)
  local remainingSeconds = math.max(0, math.floor(data.ticksLeft / 20))

  local yellowAt = session.config.getInt("sheep.fuse.yellow_at_seconds", 22)
  local orangeAt = session.config.getInt("sheep.fuse.orange_at_seconds", 12)
  local redAt = session.config.getInt("sheep.fuse.red_at_seconds", 6)
  local blinkStart = session.config.getInt("sheep.fuse.blink_start_seconds", 3)
  local blinkInterval = math.max(2, session.config.getInt("sheep.fuse.blink_interval_ticks", 4))

  local targetColor = "WHITE"
  if remainingSeconds <= redAt then
    targetColor = "RED"
  elseif remainingSeconds <= orangeAt then
    targetColor = "ORANGE"
  elseif remainingSeconds <= yellowAt then
    targetColor = "YELLOW"
  end
  session.entities.setSheepColor(handle, targetColor)

  if remainingSeconds <= blinkStart then
    if data.blinkTicks >= blinkInterval then
      data.blinkState = not data.blinkState
      data.blinkTicks = 0
    end

    session.entities.setSheepColor(handle, data.blinkState and "WHITE" or "RED")

    local particleLocation = { x = sheepLocation.x, y = sheepLocation.y + 0.5, z = sheepLocation.z, yaw = 0, pitch = 0 }
    session.world.spawnParticleAt(particleLocation, "CLOUD", 6, 0.25, 0.25, 0.25, 0.02)

    if data.warningTicks >= 20 then
      local beepSound = session.config.getString("sounds.beep") or "BLOCK_NOTE_BLOCK_HAT"
      session.world.playSoundAt(sheepLocation, beepSound, 0.7, 1.0)
      data.warningTicks = 0
    end
  elseif data.warningTicks >= 20 then
    local warningSound = session.config.getString("sounds.warning") or "BLOCK_NOTE_BLOCK_PLING"
    session.world.playSoundAt(sheepLocation, warningSound, 0.6, 1.0)
    data.warningTicks = 0
    data.blinkTicks = 0
  end
end

local function breakBlocksAround(session, center, radius)
  local minX, maxX = math.floor(center.x - radius), math.ceil(center.x + radius)
  local minY, maxY = math.floor(center.y - 1), math.ceil(center.y + 1)
  local minZ, maxZ = math.floor(center.z - radius), math.ceil(center.z + radius)

  for x = minX, maxX do
    for y = minY, maxY do
      for z = minZ, maxZ do
        local target = { x = x, y = y, z = z, yaw = 0, pitch = 0 }
        if session.isInsideBounds(target) then
          local dx, dy, dz = x - center.x, y - center.y, z - center.z
          if dx * dx + dy * dy + dz * dz <= radius * radius then
            local blockType = session.world.blockTypeAt(x, y, z)
            if blockType ~= "AIR" and blockType ~= "BARRIER" and blockType ~= "BEDROCK" then
              session.world.setBlockType(x, y, z, "AIR")
            end
          end
        end
      end
    end
  end
end

local function knockNearbyPlayers(session, center, radius, damage, knockback)
  for _, handle in ipairs(session.alivePlayers()) do
    local location = session.player.location(handle)
    local dx, dy, dz = location.x - center.x, location.y - center.y, location.z - center.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if distance <= radius then
      local length = math.sqrt(dx * dx + dy * dy + dz * dz)
      local pushX, pushY, pushZ = 0, 0, 0
      if length > 0 then
        pushX, pushY, pushZ = (dx / length) * knockback, (dy / length) * knockback, (dz / length) * knockback
      end

      session.player.damage(handle, damage)
      session.player.addVelocity(handle, pushX, pushY, pushZ)
    end
  end
end

local function explodeSheep(session, handle, location)
  session.entities.remove(handle)

  local radius = session.config.getDouble("sheep.explosion.radius", 2.5)
  local damage = session.config.getDouble("sheep.explosion.damage", 6.0)
  local knockback = session.config.getDouble("sheep.explosion.knockback", 0.65)
  local smoke = session.config.getBoolean("sheep.explosion.smoke", true)
  local clearDrops = session.config.getBoolean("sheep.explosion.clear_drops", true)

  local explosionSound = session.config.getString("sounds.explosion") or "ENTITY_GENERIC_EXPLODE"
  session.world.playSoundAt(location, explosionSound, 1.0, 1.0)

  if smoke then
    session.world.spawnParticleAt(location, "EXPLOSION", 1, 0.2, 0.2, 0.2)
    session.world.spawnParticleAt(location, "CLOUD", 10, radius / 2, 0.4, radius / 2, 0.05)
  end

  breakBlocksAround(session, location, radius)
  knockNearbyPlayers(session, location, radius, damage, knockback)
  if clearDrops then
    session.world.clearNearbyDrops(location, radius + 1)
  end
end

function M.startSheepLifecycleTask(session)
  local taskId = "arena_" .. session.arenaId .. "_exploding_sheep_fuses"
  local tickRate = math.max(2, session.config.getInt("sheep.fuse.update_ticks", 5))

  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end

    for handle, data in pairs(session.state.sheep) do
      if not session.entities.isValid(handle) then
        session.state.sheep[handle] = nil
      else
        local location = session.entities.location(handle)
        if location == nil or not session.isInsideBounds(location) then
          session.entities.remove(handle)
          session.state.sheep[handle] = nil
        else
          data.ticksLeft = math.max(0, data.ticksLeft - tickRate)
          data.warningTicks = data.warningTicks + tickRate
          data.blinkTicks = data.blinkTicks + tickRate
          applyFuseWarnings(session, handle, data, location)

          if data.ticksLeft <= 0 then
            explodeSheep(session, handle, location)
            session.state.sheep[handle] = nil
          end
        end
      end
    end
  end, tickRate, tickRate)
end

function M.cleanupSheep(session)
  for handle in pairs(session.state.sheep) do
    if session.entities.isValid(handle) then
      session.entities.remove(handle)
    end
  end
  session.state.sheep = {}
end

return M

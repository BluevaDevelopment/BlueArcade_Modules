-- The plane vehicle and its 16 BLOCK_DISPLAY entities are purely visual - players never actually
-- ride them; a synced teleport/velocity each tick fakes it, matching legacy's own design.
local M = {}

local PLANE_OFFSETS = {
  { 0, 0, 3 }, { 0, 0, 2 }, { 0, 0, 1 }, { 0, 0, 0 }, { 0, 0, -1 }, { 0, 0, -2 }, { 0, 0, -3 },
  { -1, 0, 1 }, { -2, 0, 1 }, { -3, 0, 1 },
  { 1, 0, 1 }, { 2, 0, 1 }, { 3, 0, 1 },
  { -1, 0, -2 }, { 1, 0, -2 },
  { 0, 1, -2 },
}

local PLANE_MATERIALS = {
  "WHITE_STAINED_GLASS", "WHITE_STAINED_GLASS", "WHITE_STAINED_GLASS", "WHITE_STAINED_GLASS",
  "WHITE_STAINED_GLASS", "WHITE_STAINED_GLASS", "WHITE_STAINED_GLASS",
  "CYAN_STAINED_GLASS", "CYAN_STAINED_GLASS", "CYAN_STAINED_GLASS",
  "CYAN_STAINED_GLASS", "CYAN_STAINED_GLASS", "CYAN_STAINED_GLASS",
  "LIGHT_BLUE_STAINED_GLASS", "LIGHT_BLUE_STAINED_GLASS", "LIGHT_BLUE_STAINED_GLASS",
}

local DEFAULT_EXIT_GRACE_TICKS = 10

local function vecAdd(a, b)
  return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }
end

local function vecMultiply(v, scalar)
  return { x = v.x * scalar, y = v.y * scalar, z = v.z * scalar }
end

local function vecLength(v)
  return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

local function toLocation(v, yaw, pitch)
  return { x = v.x, y = v.y, z = v.z, yaw = yaw or 0, pitch = pitch or 0 }
end

local function getBounds(session)
  local min = session.arena.boundsMin()
  local max = session.arena.boundsMax()
  if not min or not max then
    return nil
  end
  return min, max
end

local function getPlayAreaCenter(session)
  local min, max = getBounds(session)
  if min then
    return { x = (min.x + max.x) / 2.0, y = (min.y + max.y) / 2.0, z = (min.z + max.z) / 2.0 }
  end
  local players = session.players()
  if #players == 0 then
    return nil
  end
  return session.player.location(players[1])
end

local function clampEdgeOffset(desiredOffset, size)
  if size <= 0.0 then
    return 0.0
  end
  local maxOffset = math.max(0.0, (size / 2.0) - 1.0)
  return math.max(0.0, math.min(desiredOffset, maxOffset))
end

local function resolveFlightHeight(session, center, min, max)
  local configuredHeight = session.config.getDouble("drop.flight_height", center.y + 40.0)
  if not min then
    return configuredHeight
  end
  local minY = math.min(min.y, max.y)
  local maxY = math.max(min.y, max.y)
  local minAllowed = minY + 1.0
  local maxAllowed = maxY - 1.0
  if maxAllowed < minAllowed then
    minAllowed = minY
    maxAllowed = maxY
  end
  return math.max(minAllowed, math.min(configuredHeight, maxAllowed))
end

local function computeRoute(session)
  local center = getPlayAreaCenter(session)
  if not center then
    return nil
  end

  local min, max = getBounds(session)
  local flightHeight = resolveFlightHeight(session, center, min, max)

  if min then
    local minX, maxX = math.min(min.x, max.x), math.max(min.x, max.x)
    local minZ, maxZ = math.min(min.z, max.z), math.max(min.z, max.z)
    local centerX, centerZ = (minX + maxX) / 2.0, (minZ + maxZ) / 2.0
    local sizeX, sizeZ = maxX - minX, maxZ - minZ
    local edgeOffset = session.config.getDouble("drop.edge_offset", 4.0)

    if sizeX >= sizeZ then
      local offset = clampEdgeOffset(edgeOffset, sizeX)
      return { x = minX + offset, y = flightHeight, z = centerZ }, { x = maxX - offset, y = flightHeight, z = centerZ }
    end
    local offset = clampEdgeOffset(edgeOffset, sizeZ)
    return { x = centerX, y = flightHeight, z = minZ + offset }, { x = centerX, y = flightHeight, z = maxZ - offset }
  end

  local halfSizeZ = session.config.getDouble("drop.default_half_size", 60.0)
  return { x = center.x, y = flightHeight, z = center.z - halfSizeZ }, { x = center.x, y = flightHeight, z = center.z + halfSizeZ }
end

local function applyDropInvisibility(session, handle)
  session.state.dropInvisiblePlayers[handle] = true
  -- particles=false - an invisible player showing potion swirl particles would give away their
  -- position, matching legacy's own explicit false here.
  session.player.addPotionEffect(handle, "INVISIBILITY", 999999, 0, false, false)
end

local function clearDropInvisibility(session, handle)
  if session.state.dropInvisiblePlayers[handle] then
    session.state.dropInvisiblePlayers[handle] = nil
    session.player.removePotionEffect(handle, "INVISIBILITY")
  end
end

local function blockLocation(origin, forward, right, lr, up, lf)
  return vecAdd(vecAdd(origin, vecMultiply(right, lr)), vecAdd({ x = 0, y = up, z = 0 }, vecMultiply(forward, lf)))
end

local function spawnPlaneDisplays(session, origin, forward, right, interpolationTicks)
  local displays = {}
  for i, offset in ipairs(PLANE_OFFSETS) do
    local loc = blockLocation(origin, forward, right, offset[1], offset[2], offset[3])
    local handle = session.world.spawnEntity(toLocation(loc), "BLOCK_DISPLAY")
    if handle then
      session.entities.configureBlockDisplay(handle, PLANE_MATERIALS[i], interpolationTicks)
      displays[#displays + 1] = handle
    end
  end
  return displays
end

local function teleportPlaneDisplays(session, displays, origin, forward, right)
  for i, handle in ipairs(displays) do
    local offset = PLANE_OFFSETS[i]
    if offset then
      session.entities.teleport(handle, toLocation(blockLocation(origin, forward, right, offset[1], offset[2], offset[3])))
    end
  end
end

function M.cleanup(session)
  for _, handle in ipairs(session.players()) do
    if session.state.planePlayers[handle] then
      clearDropInvisibility(session, handle)
      if session.player.isInsideVehicle(handle) then
        session.player.leaveVehicle(handle)
      end
      session.player.setFlying(handle, false)
      session.player.setAllowFlight(handle, false)
      session.player.setGravity(handle, true)
    end
  end
  session.state.planePlayers = {}
  session.state.planeBoardedAt = {}
  session.state.planeExitReleaseRequired = {}

  if session.state.dropVehicle then
    session.entities.remove(session.state.dropVehicle)
    session.state.dropVehicle = nil
  end

  for _, handle in ipairs(session.state.planeDisplays or {}) do
    session.entities.remove(handle)
  end
  session.state.planeDisplays = {}
end

local function movePlanePlayers(session, planePos)
  for _, handle in ipairs(session.players()) do
    if session.state.planePlayers[handle] then
      local playerLoc = session.player.location(handle)
      local dest = toLocation(planePos, playerLoc.yaw, playerLoc.pitch)
      session.player.teleport(handle, dest)
      session.player.setFallDistance(handle, 0.0)
      if not session.player.getAllowFlight(handle) then
        session.player.setAllowFlight(handle, true)
      end
      session.player.setFlying(handle, true)
    end
  end
end

local function updatePlanePlayersVelocity(session, target, perTickMove)
  local driftThresholdSquared = 16.0
  for _, handle in ipairs(session.players()) do
    if session.state.planePlayers[handle] then
      local loc = session.player.location(handle)
      local dx = target.x - loc.x
      local dy = target.y - loc.y
      local dz = target.z - loc.z
      local distSquared = dx * dx + dy * dy + dz * dz

      if not session.player.getAllowFlight(handle) then
        session.player.setAllowFlight(handle, true)
      end
      session.player.setFlying(handle, true)

      if distSquared > driftThresholdSquared then
        session.player.teleport(handle, toLocation(target, loc.yaw, loc.pitch))
      else
        session.player.setVelocity(handle,
          perTickMove.x + dx * 0.2,
          perTickMove.y + dy * 0.2,
          perTickMove.z + dz * 0.2)
      end
      session.player.setFallDistance(handle, 0.0)
    end
  end
end

local function handleDropExitInternal(session, handle)
  if not session.state.planePlayers[handle] then
    return
  end
  if session.player.isInsideVehicle(handle) then
    session.player.leaveVehicle(handle)
  end
  local previousChestplate = session.player.getSlotItem(handle, 38)
  session.state.planePlayers[handle] = nil
  session.state.planeBoardedAt[handle] = nil
  session.state.planeExitReleaseRequired[handle] = nil
  session.player.setFlying(handle, false)
  session.player.setAllowFlight(handle, false)
  session.player.setGravity(handle, true)
  session.state.droppingPlayers[handle] = true
  session.state.storedChestplates[handle] = previousChestplate
  session.player.giveItem(handle, "ELYTRA", 1, 38)
  session.player.setFallDistance(handle, 0.0)
  session.player.addPotionEffect(handle, "SLOW_FALLING", 999999, 0)
  clearDropInvisibility(session, handle)
end

function M.handleDropExit(session, handle)
  handleDropExitInternal(session, handle)
end

function M.handlePlaneSneakToggle(session, handle, sneaking)
  if not session.state.planePlayers[handle] then
    return
  end

  local graceMillis = math.max(0, session.config.getInt("drop.exit_grace_ticks", DEFAULT_EXIT_GRACE_TICKS)) * 0.05
  local boardedAt = session.state.planeBoardedAt[handle]
  local graceElapsed = boardedAt ~= nil and (os.clock() - boardedAt) >= graceMillis
  local requiresRelease = session.state.planeExitReleaseRequired[handle] == true

  if not sneaking then
    session.state.planeExitReleaseRequired[handle] = nil
    return
  end

  if not graceElapsed then
    return
  end
  if requiresRelease then
    return
  end

  handleDropExitInternal(session, handle)
end

function M.handleLanding(session, handle)
  if not session.state.droppingPlayers[handle] then
    return
  end
  session.state.droppingPlayers[handle] = nil
  local restore = session.state.storedChestplates[handle]
  session.state.storedChestplates[handle] = nil
  if restore then
    session.player.giveItem(handle, restore.material, restore.amount, 38)
  else
    session.player.giveItem(handle, "AIR", 1, 38)
  end
  session.player.removePotionEffect(handle, "SLOW_FALLING")
  session.player.setFallDistance(handle, 0.0)
end

local function forceDrop(session)
  for handle in pairs(session.state.planePlayers) do
    handleDropExitInternal(session, handle)
  end
end

function M.startDrop(session)
  if not session.config.getBoolean("drop.enabled", true) then
    return
  end

  local start, finish = computeRoute(session)
  if not start then
    return
  end

  local direction = { x = finish.x - start.x, y = finish.y - start.y, z = finish.z - start.z }
  local length = vecLength(direction)
  if length <= 0.1 then
    return
  end
  direction = vecMultiply(direction, 1.0 / length)
  local right = { x = -direction.z, y = 0.0, z = direction.x }

  local vehicle = session.world.spawnEntity(toLocation(start), "ARMOR_STAND")
  session.state.dropVehicle = vehicle
  if vehicle then
    session.entities.prepareDropVehicle(vehicle)
  end

  local speed = session.config.getDouble("drop.speed_blocks_per_tick", 0.6)
  local interpolationTicks = math.max(1, session.config.getInt("drop.interpolation_ticks", 5))
  session.state.planeDisplays = spawnPlaneDisplays(session, start, direction, right, interpolationTicks)

  for _, handle in ipairs(session.players()) do
    session.state.planePlayers[handle] = true
    session.state.planeBoardedAt[handle] = os.clock()
    session.state.planeExitReleaseRequired[handle] = nil
    applyDropInvisibility(session, handle)

    local playerLoc = session.player.location(handle)
    session.player.teleport(handle, toLocation(start, playerLoc.yaw, playerLoc.pitch))
    if session.player.isInsideVehicle(handle) then
      session.player.leaveVehicle(handle)
    end
    session.player.setGravity(handle, true)
    session.player.setFallDistance(handle, 0.0)
    session.player.setAllowFlight(handle, true)
    session.player.setFlying(handle, true)
  end

  local taskId = "arena_" .. session.arenaId .. "_battle_royale_drop"
  local playerTaskId = "arena_" .. session.arenaId .. "_battle_royale_drop_players"
  local traveled = 0.0
  local yaw = math.deg(math.atan(-direction.x, direction.z))
  local stepDistance = speed * interpolationTicks

  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      session.scheduler.cancelTask(playerTaskId)
      M.cleanup(session)
      return
    end

    local remaining = length - traveled
    local step = math.min(stepDistance, remaining)
    traveled = traveled + step

    local finished = traveled >= length - 1.0e-6
    local next
    if finished then
      next = { x = finish.x, y = finish.y, z = finish.z }
    else
      next = vecAdd(start, vecMultiply(direction, traveled))
    end

    if session.state.dropVehicle then
      session.entities.teleport(session.state.dropVehicle, toLocation(next, yaw))
    end
    teleportPlaneDisplays(session, session.state.planeDisplays, next, direction, right)

    if finished then
      session.scheduler.cancelTask(taskId)
      session.scheduler.cancelTask(playerTaskId)
      movePlanePlayers(session, next)
      forceDrop(session)
      M.cleanup(session)
    end
  end, 0, interpolationTicks)

  local tickCounter = 0
  local perTickMove = vecMultiply(direction, speed)
  session.scheduler.runTimer(playerTaskId, function()
    if session.state.ended then
      return
    end
    tickCounter = tickCounter + 1
    local traveledNow = math.min(length, speed * tickCounter)
    local target = vecAdd(start, vecMultiply(direction, traveledNow))
    updatePlanePlayersVelocity(session, target, perTickMove)
  end, 1, 1)
end

return M

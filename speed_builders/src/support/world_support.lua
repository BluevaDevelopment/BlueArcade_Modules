-- Mirrors legacy SpeedBuildersWorldSupport.java's region/view-finding math. Structure pasting and
-- clearing/resetting are handled by session.structure.paste and session.world.setRegion instead -
-- this file only ports the pure math (no real Bukkit call beyond block-type reads) that has no
-- Kotlin binding of its own.
local M = {}

local function isAir(name)
  return name == "AIR" or name == "CAVE_AIR" or name == "VOID_AIR"
end

local function isSafeForPlayer(session, x, y, z)
  return isAir(session.world.blockTypeAt(x, y, z)) and isAir(session.world.blockTypeAt(x, y + 1, z))
end

local function faceLocation(location, target)
  local dx = target.x - location.x
  local dy = target.y - location.y
  local dz = target.z - location.z
  local distanceXZ = math.sqrt(dx * dx + dz * dz)
  location.yaw = math.deg(math.atan(-dx, dz))
  location.pitch = -math.deg(math.atan(dy, distanceXZ))
  return location
end
M.faceLocation = faceLocation

local function firstSafeAtOrAbove(session, x, startY, z, maxY)
  for y = math.max(session.world.minHeight() + 1, startY), maxY do
    if isSafeForPlayer(session, x, y, z) then
      return { x = x, y = y, z = z }
    end
  end
  return nil
end

-- findSafeViewLocation - unbounded search: straight up from the region top, then four side
-- candidates. Used whenever gameplay.strict_plot_region is false (the default).
function M.findSafeViewLocation(session, min, max)
  local minX = math.min(min.x, max.x)
  local maxX = math.max(min.x, max.x)
  local minY = math.min(min.y, max.y)
  local maxY = math.max(min.y, max.y)
  local minZ = math.min(min.z, max.z)
  local maxZ = math.max(min.z, max.z)

  local centerX = minX + (maxX - minX + 1) / 2.0
  local centerZ = minZ + (maxZ - minZ + 1) / 2.0
  local lookAt = { x = centerX, y = minY + 1.0, z = centerZ }

  local worldMaxHeight = session.world.maxHeight()
  local topY = math.min(worldMaxHeight - 2, maxY + 3)
  for y = topY, worldMaxHeight - 2 do
    if isSafeForPlayer(session, centerX, y, centerZ) then
      return faceLocation({ x = centerX, y = y, z = centerZ }, lookAt)
    end
  end

  local sideCandidates = {
    { x = centerX, y = topY, z = minZ - 2.0 },
    { x = centerX, y = topY, z = maxZ + 2.0 },
    { x = minX - 2.0, y = topY, z = centerZ },
    { x = maxX + 2.0, y = topY, z = centerZ },
  }
  for _, candidate in ipairs(sideCandidates) do
    local safe = firstSafeAtOrAbove(session, candidate.x, candidate.y, candidate.z, worldMaxHeight - 2)
    if safe then
      return faceLocation(safe, lookAt)
    end
  end

  return faceLocation({ x = centerX, y = topY, z = centerZ }, lookAt)
end

-- findSafeViewLocationWithinBounds - exhaustive search inside [boundsMin, boundsMax] for the
-- closest safe spot to a preferred height above the region, used only when
-- gameplay.strict_plot_region is true.
function M.findSafeViewLocationWithinBounds(session, min, max, boundsMin, boundsMax)
  local minX = math.min(boundsMin.x, boundsMax.x)
  local maxX = math.max(boundsMin.x, boundsMax.x)
  local minY = math.max(session.world.minHeight(), math.min(boundsMin.y, boundsMax.y))
  local maxFeetY = math.min(session.world.maxHeight() - 2, math.max(boundsMin.y, boundsMax.y) - 1)
  local minZ = math.min(boundsMin.z, boundsMax.z)
  local maxZ = math.max(boundsMin.z, boundsMax.z)
  if minY > maxFeetY then
    return nil
  end

  local regionMinX = math.min(min.x, max.x)
  local regionMaxX = math.max(min.x, max.x)
  local regionMinY = math.min(min.y, max.y)
  local regionMaxY = math.max(min.y, max.y)
  local regionMinZ = math.min(min.z, max.z)
  local regionMaxZ = math.max(min.z, max.z)

  local centerX = regionMinX + (regionMaxX - regionMinX + 1) / 2.0
  local centerZ = regionMinZ + (regionMaxZ - regionMinZ + 1) / 2.0
  local preferredY = math.max(minY, math.min(maxFeetY, regionMaxY + 3))
  local lookAt = { x = centerX, y = regionMinY + 1.0, z = centerZ }

  local function insideRegion(x, y, z)
    return x >= regionMinX and x <= regionMaxX and y >= regionMinY and y <= regionMaxY and z >= regionMinZ and z <= regionMaxZ
  end

  local best, bestDistance = nil, math.huge
  for x = minX, maxX do
    for y = minY, maxFeetY do
      for z = minZ, maxZ do
        if not insideRegion(x, y, z) and not insideRegion(x, y + 1, z) then
          local cx, cy, cz = x + 0.5, y, z + 0.5
          if isSafeForPlayer(session, cx, cy, cz) then
            local dx, dy, dz = cx - centerX, cy - preferredY, cz - centerZ
            local distance = dx * dx + dy * dy + dz * dz
            if distance < bestDistance then
              best = { x = cx, y = cy, z = cz }
              bestDistance = distance
            end
          end
        end
      end
    end
  end
  return best and faceLocation(best, lookAt) or nil
end

local function isInsideRegion(location, min, max)
  if not location or not min or not max then
    return false
  end
  local x, y, z = math.floor(location.x), math.floor(location.y), math.floor(location.z)
  return x >= math.min(min.x, max.x) and x <= math.max(min.x, max.x)
    and y >= math.min(min.y, max.y) and y <= math.max(min.y, max.y)
    and z >= math.min(min.z, max.z) and z <= math.max(min.z, max.z)
end
M.isInsideRegion = isInsideRegion

local function teleportToSafeView(session, handle, area, plot, strictRegion)
  local safe
  if strictRegion and plot then
    safe = M.findSafeViewLocationWithinBounds(session, area.min, area.max, plot.min, plot.max)
  else
    safe = M.findSafeViewLocation(session, area.min, area.max)
  end
  if not safe then
    return
  end
  session.player.setAllowFlight(handle, true)
  session.player.setFlying(handle, true)
  session.player.teleport(handle, safe)
end

function M.moveOutOfBuildAreaIfInside(session, state, handle, strictRegion)
  local area = state.playerBuildArea[handle]
  if not area then
    return
  end
  local location = session.player.location(handle)
  if not isInsideRegion(location, area.min, area.max) then
    return
  end
  teleportToSafeView(session, handle, area, state.playerPlot[handle], strictRegion)
end

function M.moveOutOfRegionIfInside(session, handle, min, max)
  local location = session.player.location(handle)
  if not isInsideRegion(location, min, max) then
    return
  end
  local target = M.findSafeViewLocation(session, min, max)
  if not target then
    return
  end
  session.player.setAllowFlight(handle, true)
  session.player.setFlying(handle, true)
  session.player.teleport(handle, target)
end

function M.getBuildOrigin(state, handle)
  local area = state.playerBuildArea[handle]
  if area then
    local minX, maxX = math.min(area.min.x, area.max.x), math.max(area.min.x, area.max.x)
    local minY = math.min(area.min.y, area.max.y)
    local minZ, maxZ = math.min(area.min.z, area.max.z), math.max(area.min.z, area.max.z)
    local originX = minX + math.floor((maxX - minX + 1) / 2)
    local originZ = minZ + math.floor((maxZ - minZ + 1) / 2)
    return { x = originX, y = minY, z = originZ }
  end
  local plot = state.playerPlot[handle]
  return plot and plot.spawn or nil
end

function M.getPlayerRotationSteps(state, handle)
  local yaw = state.playerPlotYaw[handle] or 0
  yaw = ((yaw % 360.0) + 360.0) % 360.0
  return math.floor(yaw / 90.0 + 0.5) % 4
end

return M

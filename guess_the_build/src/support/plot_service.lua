-- Mirrors legacy GuessTheBuildPlotService.java. Only ever one plot in practice (every legacy call
-- site indexed plots.get(0)), so session.state.plot is singular here, not an array.
local M = {}

local function centerLocation(loc)
  return {
    x = math.floor(loc.x) + 0.5,
    y = loc.y,
    z = math.floor(loc.z) + 0.5,
    yaw = loc.yaw,
    pitch = loc.pitch,
  }
end

local function isAir(materialName)
  return materialName == "AIR" or materialName == "CAVE_AIR" or materialName == "VOID_AIR"
end

local function calculatePlotCenter(min, max)
  return {
    x = (min.x + max.x) / 2.0,
    y = math.min(min.y, max.y) + 1.0,
    z = (min.z + max.z) / 2.0,
  }
end

function M.loadPlot(session)
  local min = session.dataAccess.getGameLocation("game.plot.bounds.min")
  local max = session.dataAccess.getGameLocation("game.plot.bounds.max")

  if not min or not max then
    return
  end

  local floorName = session.dataAccess.getGameDataString("game.plot.floor")
  local floorMaterial = floorName or "GRASS_BLOCK"

  local spawn = session.dataAccess.getGameLocation("game.plot.spawn")
  if not spawn then
    spawn = calculatePlotCenter(min, max)
  end

  session.state.plot = { min = min, max = max, floorMaterial = floorMaterial, spawn = spawn, points = 0 }
end

function M.assignPlayersToPlot(session)
  local plot = session.state.plot
  if not plot then
    return
  end
  for _, handle in ipairs(session.players()) do
    session.state.playerPlotSpawn[handle] = plot.spawn
    session.state.playerPlot[handle] = plot
  end
end

function M.regeneratePlotFloor(session, plot)
  plot = plot or session.state.plot
  if not plot then
    return
  end
  local minX, maxX = math.min(plot.min.x, plot.max.x), math.max(plot.min.x, plot.max.x)
  local minY = math.min(plot.min.y, plot.max.y)
  local minZ, maxZ = math.min(plot.min.z, plot.max.z), math.max(plot.min.z, plot.max.z)
  for x = minX, maxX do
    for z = minZ, maxZ do
      session.world.setBlockType(x, minY, z, plot.floorMaterial)
    end
  end
end

function M.clearPlot(session)
  local plot = session.state.plot
  if not plot then
    return
  end
  local minX, maxX = math.min(plot.min.x, plot.max.x), math.max(plot.min.x, plot.max.x)
  local minY, maxY = math.min(plot.min.y, plot.max.y), math.max(plot.min.y, plot.max.y)
  local minZ, maxZ = math.min(plot.min.z, plot.max.z), math.max(plot.min.z, plot.max.z)
  for x = minX, maxX do
    for y = minY, maxY do
      for z = minZ, maxZ do
        session.world.setBlockType(x, y, z, "AIR")
      end
    end
  end
end

function M.teleportToPlot(session, handle)
  local spawn = session.state.playerPlotSpawn[handle]
  if not spawn then
    return
  end
  session.player.teleport(handle, centerLocation(spawn))
end

-- Scans the plot's vertical center column for the first two-block-tall air pocket, falling back
-- to just above the floor if nothing safe is found - matches legacy GuessTheBuildPlot#findSafeTeleport.
function M.findSafeTeleport(session, plot)
  if not plot then
    return nil
  end
  local centerX = math.floor((plot.min.x + plot.max.x) / 2)
  local centerZ = math.floor((plot.min.z + plot.max.z) / 2)
  local minY = math.min(plot.min.y, plot.max.y)
  local maxY = math.max(plot.min.y, plot.max.y)

  for y = minY + 1, maxY - 1 do
    local current = session.world.blockTypeAt(centerX, y, centerZ)
    local above = session.world.blockTypeAt(centerX, y + 1, centerZ)
    if isAir(current) and isAir(above) then
      return { x = centerX + 0.5, y = y, z = centerZ + 0.5 }
    end
  end

  return { x = centerX + 0.5, y = minY + 1.0, z = centerZ + 0.5 }
end

return M

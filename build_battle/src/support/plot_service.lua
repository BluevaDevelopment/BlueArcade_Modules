-- Mirrors legacy BuildBattlePlotService.java. Plot bounds/floor/spawn are read from
-- game.plots.list.p<N>.{bounds.min,bounds.max,floor,spawn}, written by setup.lua's own "plot add/
-- set" commands. Floor regeneration is a per-block Lua loop over session.world.setBlockType, same
-- convention as every other module's own region-fill code (e.g. lucky_pillars' fillLavaLayer).
local M = {}

local function calculatePlotCenter(min, max)
  return {
    x = (min.x + max.x) / 2.0,
    y = math.min(min.y, max.y) + 1.0,
    z = (min.z + max.z) / 2.0,
  }
end

function M.centerLocation(loc)
  return { x = math.floor(loc.x) + 0.5, y = loc.y, z = math.floor(loc.z) + 0.5, yaw = loc.yaw, pitch = loc.pitch }
end

function M.loadPlots(session)
  local totalPlots = session.dataAccess.getGameDataNumber("game.plots.total") or 0
  for i = 1, totalPlots do
    local basePath = "game.plots.list.p" .. i
    local min = session.dataAccess.getGameLocation(basePath .. ".bounds.min")
    local max = session.dataAccess.getGameLocation(basePath .. ".bounds.max")
    if min and max then
      local floorName = session.dataAccess.getGameDataString(basePath .. ".floor") or "GRASS_BLOCK"
      local spawn = session.dataAccess.getGameLocation(basePath .. ".spawn") or calculatePlotCenter(min, max)
      local plot = { min = min, max = max, floorMaterial = floorName, spawn = spawn }
      session.state.plots[#session.state.plots + 1] = plot
      session.state.plotSpawns[#session.state.plotSpawns + 1] = spawn
    end
  end
end

function M.assignPlayersToPlots(session)
  local players = session.players()
  local plots = session.state.plots
  if #plots == 0 then
    return
  end
  for i, handle in ipairs(players) do
    local plot = plots[((i - 1) % #plots) + 1]
    session.state.playerPlotSpawn[handle] = plot.spawn
    session.state.playerPlot[handle] = plot
  end
end

function M.regeneratePlotFloor(session, plot)
  if not plot or not plot.min or not plot.max then
    return
  end
  local minX = math.min(math.floor(plot.min.x), math.floor(plot.max.x))
  local maxX = math.max(math.floor(plot.min.x), math.floor(plot.max.x))
  local minY = math.min(math.floor(plot.min.y), math.floor(plot.max.y))
  local minZ = math.min(math.floor(plot.min.z), math.floor(plot.max.z))
  local maxZ = math.max(math.floor(plot.min.z), math.floor(plot.max.z))

  for x = minX, maxX do
    for z = minZ, maxZ do
      session.world.setBlockType(x, minY, z, plot.floorMaterial)
    end
  end
end

function M.regeneratePlotFloors(session)
  for _, plot in ipairs(session.state.plots) do
    M.regeneratePlotFloor(session, plot)
  end
end

function M.clearPlots(session)
  for _, plot in ipairs(session.state.plots) do
    if plot.min and plot.max then
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
    end
  end
end

function M.teleportToPlot(session, handle)
  local plot = session.state.playerPlotSpawn[handle]
  if not plot then
    return
  end
  session.player.teleport(handle, M.centerLocation(plot))
end

return M

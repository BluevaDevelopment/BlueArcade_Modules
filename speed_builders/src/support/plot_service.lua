-- Mirrors legacy PlotService.java.
local M = {}

local function regionCenter(min, max, yOffset)
  local centerX = math.min(min.x, max.x) + (math.abs(max.x - min.x) + 1) / 2.0
  local centerZ = math.min(min.z, max.z) + (math.abs(max.z - min.z) + 1) / 2.0
  return { x = centerX, y = math.min(min.y, max.y) + yOffset, z = centerZ }
end
M.regionCenter = regionCenter

function M.loadPlots(session, state)
  local totalPlots = math.floor(session.dataAccess.getGameDataNumber("game.plots.total") or 0)
  local totalAreas = math.floor(session.dataAccess.getGameDataNumber("game.build_areas.total") or 0)

  state.plots = {}
  for i = 1, totalPlots do
    local base = "game.plots.list.p" .. i
    local min = session.dataAccess.getGameLocation(base .. ".bounds.min")
    local max = session.dataAccess.getGameLocation(base .. ".bounds.max")
    if min and max then
      local spawn = session.dataAccess.getGameLocation(base .. ".spawn") or regionCenter(min, max, 1.0)
      state.plots[#state.plots + 1] = { min = min, max = max, spawn = spawn }
    end
  end

  state.buildAreas = {}
  for i = 1, totalAreas do
    local base = "game.build_areas.list.a" .. i
    local min = session.dataAccess.getGameLocation(base .. ".min")
    local max = session.dataAccess.getGameLocation(base .. ".max")
    local floor = session.dataAccess.getGameDataString(base .. ".floor")
    if min and max then
      state.buildAreas[#state.buildAreas + 1] = { min = min, max = max, floorMaterial = floor or "GRASS_BLOCK" }
    else
      state.buildAreas[#state.buildAreas + 1] = false
    end
  end

  local scMin = session.dataAccess.getGameLocation("game.showcase_plot.bounds.min")
  local scMax = session.dataAccess.getGameLocation("game.showcase_plot.bounds.max")
  if scMin and scMax then
    state.showcasePlot = { min = scMin, max = scMax, spawn = regionCenter(scMin, scMax, 0.0) }
  else
    state.showcasePlot = nil
  end
end

function M.assignPlayersToPlotsAndAreas(session, state)
  local players = session.players()
  state.playerPlot = {}
  state.playerPlotSpawn = {}
  state.playerPlotYaw = {}
  state.playerBuildArea = {}

  for i, handle in ipairs(players) do
    local plot = nil
    if #state.plots > 0 then
      plot = state.plots[((i - 1) % #state.plots) + 1]
    end
    local area = nil
    if #state.buildAreas > 0 then
      area = state.buildAreas[((i - 1) % #state.buildAreas) + 1]
    end

    if plot then
      state.playerPlot[handle] = plot
      state.playerPlotSpawn[handle] = plot.spawn
      state.playerPlotYaw[handle] = plot.spawn.yaw or 0
    end
    if area then
      state.playerBuildArea[handle] = area
    end
  end
end

local function regenerateBuildAreaFloor(session, area)
  if not area or not area.floorMaterial then
    return
  end
  local minX = math.min(area.min.x, area.max.x)
  local minY = math.min(area.min.y, area.max.y)
  local minZ = math.min(area.min.z, area.max.z)
  local maxX = math.max(area.min.x, area.max.x)
  local maxZ = math.max(area.min.z, area.max.z)
  session.world.setRegion(minX, minY, minZ, maxX, minY, maxZ, area.floorMaterial)
end
M.regenerateBuildAreaFloor = regenerateBuildAreaFloor

function M.regenerateBuildAreaFloors(session, state)
  for _, area in ipairs(state.buildAreas) do
    if area then
      regenerateBuildAreaFloor(session, area)
    end
  end
end

function M.clearBuildAreas(session, state)
  for _, area in ipairs(state.buildAreas) do
    if area then
      session.world.setRegion(area.min.x, area.min.y, area.min.z, area.max.x, area.max.y, area.max.z, "AIR")
    end
  end
end

-- clearRegionAboveFloor - the area above (not including) the floor layer, matching legacy
-- SpeedBuildersWorldSupport.clearRegionAboveFloorDirect.
local function clearRegionAboveFloor(session, min, max)
  local minY = math.min(min.y, max.y) + 1
  local maxY = math.max(min.y, max.y)
  if minY > maxY then
    return
  end
  session.world.setRegion(min.x, minY, min.z, max.x, maxY, max.z, "AIR")
end
M.clearRegionAboveFloor = clearRegionAboveFloor

-- resetBuildArea - clears everything above the floor, then re-fills the floor layer if a floor
-- material is set. Distinct from regenerateBuildAreaFloor, which only ever touches the floor.
function M.resetBuildArea(session, area)
  if not area then
    return
  end
  clearRegionAboveFloor(session, area.min, area.max)
  regenerateBuildAreaFloor(session, area)
end

function M.clearShowcasePlot(session, state)
  local showcase = state.showcasePlot
  if not showcase then
    return
  end
  local floorY = math.min(showcase.min.y, showcase.max.y)
  local topY = math.max(showcase.min.y, showcase.max.y)
  if floorY >= topY then
    return
  end
  local minY = floorY + 1
  session.world.setRegion(showcase.min.x, minY, showcase.min.z, showcase.max.x, topY, showcase.max.z, "AIR")
end

function M.teleportToPlot(session, handle, spawn)
  if not spawn then
    return
  end
  local centered = { x = math.floor(spawn.x) + 0.5, y = spawn.y, z = math.floor(spawn.z) + 0.5, yaw = spawn.yaw, pitch = spawn.pitch }
  session.player.teleport(handle, centered)
end

-- getMaxBuildDimensions - the largest build-area (or, if none configured, plot) footprint, used to
-- filter out structures too big to fit anywhere this arena has set up.
function M.getMaxBuildDimensions(state)
  local maxW, maxH, maxL = 0, 0, 0
  local regions = state.buildAreas
  local hasAreas = false
  for _, area in ipairs(regions) do
    if area then
      hasAreas = true
      break
    end
  end
  if not hasAreas then
    regions = state.plots
  end
  for _, region in ipairs(regions) do
    if region then
      local w = math.abs(region.max.x - region.min.x) + 1
      local h = math.abs(region.max.y - region.min.y) + 1
      local l = math.abs(region.max.z - region.min.z) + 1
      maxW = math.max(maxW, w)
      maxH = math.max(maxH, h)
      maxL = math.max(maxL, l)
    end
  end
  return maxW, maxH, maxL
end

return M

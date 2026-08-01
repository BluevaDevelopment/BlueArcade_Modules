-- Mirrors legacy SpeedBuildersSetup.java + SpeedBuildersPlotSetup.java + SpeedBuildersShowcaseSetup.java.
local RECOMMENDED_WIDTH = 7
local RECOMMENDED_HEIGHT = 10
local RECOMMENDED_LENGTH = 7

local M = {}

local function msg(key)
  return ba.config.translation(nil, "setup_messages." .. key) or ""
end

local function regionSize(pos1, pos2)
  local x = math.abs(pos2.x - pos1.x) + 1
  local y = math.abs(pos2.y - pos1.y) + 1
  local z = math.abs(pos2.z - pos1.z) + 1
  return x, y, z
end

-- ---- plot ----

local function parsePlotId(ctx, idArg)
  local plotId = tonumber(idArg)
  local totalPlots = ctx.data.getInt("game.plots.total", 0)
  if not plotId or plotId < 1 or plotId > totalPlots then
    ctx.reply(msg("plot.not_found"))
    return nil
  end
  return math.floor(plotId)
end

local function handlePlotAdd(ctx)
  if not ctx.selection.hasCompleteSelection() then
    ctx.reply(msg("plot.add.must_use_stick"))
    return true
  end
  local pos1 = ctx.selection.getPosition1()
  local pos2 = ctx.selection.getPosition2()

  local totalPlots = ctx.data.getInt("game.plots.total", 0)
  local newPlotNumber = totalPlots + 1
  local base = "game.plots.list.p" .. newPlotNumber

  ctx.data.setRegionBounds(base .. ".bounds", pos1, pos2)
  ctx.data.setLocation(base .. ".spawn", ctx.playerLocation)
  ctx.data.setInt("game.plots.total", newPlotNumber)
  ctx.data.save()

  local x, y, z = regionSize(pos1, pos2)
  local blocks = x * y * z
  ctx.reply(msg("plot.add.set")
    :gsub("{index}", tostring(newPlotNumber))
    :gsub("{blocks}", tostring(blocks))
    :gsub("{x}", tostring(x)):gsub("{y}", tostring(y)):gsub("{z}", tostring(z)))

  local spawnMsg = msg("plot.add.spawn_set")
  if spawnMsg ~= "" then
    ctx.reply(spawnMsg:gsub("{index}", tostring(newPlotNumber)))
  end
  return true
end

local function handlePlotSet(ctx)
  local idArg = ctx.args[2]
  if not idArg then
    ctx.reply(msg("plot.set.usage"))
    return true
  end
  local plotId = parsePlotId(ctx, idArg)
  if not plotId then
    return true
  end
  if not ctx.selection.hasCompleteSelection() then
    ctx.reply(msg("plot.add.must_use_stick"))
    return true
  end
  local pos1 = ctx.selection.getPosition1()
  local pos2 = ctx.selection.getPosition2()

  local base = "game.plots.list.p" .. plotId
  ctx.data.setRegionBounds(base .. ".bounds", pos1, pos2)
  ctx.data.setLocation(base .. ".spawn", ctx.playerLocation)
  ctx.data.save()

  local x, y, z = regionSize(pos1, pos2)
  local blocks = x * y * z
  ctx.reply(msg("plot.set.success")
    :gsub("{index}", tostring(plotId))
    :gsub("{blocks}", tostring(blocks))
    :gsub("{x}", tostring(x)):gsub("{y}", tostring(y)):gsub("{z}", tostring(z)))
  return true
end

local function handlePlotRemove(ctx)
  local idArg = ctx.args[2]
  if not idArg then
    ctx.reply(msg("plot.remove.usage"))
    return true
  end
  local plotId = parsePlotId(ctx, idArg)
  if not plotId then
    return true
  end

  local totalPlots = ctx.data.getInt("game.plots.total", 0)
  ctx.data.remove("game.plots.list.p" .. plotId)
  for i = plotId + 1, totalPlots do
    local oldBase = "game.plots.list.p" .. i
    local newBase = "game.plots.list.p" .. (i - 1)
    local oldMin = ctx.data.getLocation(oldBase .. ".bounds.min")
    local oldMax = ctx.data.getLocation(oldBase .. ".bounds.max")
    local oldSpawn = ctx.data.getLocation(oldBase .. ".spawn")
    if oldMin and oldMax then
      ctx.data.setRegionBounds(newBase .. ".bounds", oldMin, oldMax)
    end
    if oldSpawn then
      ctx.data.setLocation(newBase .. ".spawn", oldSpawn)
    end
    ctx.data.remove(oldBase)
  end
  ctx.data.setInt("game.plots.total", totalPlots - 1)
  ctx.data.save()

  ctx.reply(msg("plot.remove.success"):gsub("{index}", tostring(plotId)))
  return true
end

local function handlePlotSpawn(ctx)
  if not ctx.args[2] or ctx.args[2]:lower() ~= "set" then
    ctx.reply(msg("plot.spawn.usage"))
    return true
  end
  local idArg = ctx.args[3]
  if not idArg then
    ctx.reply(msg("plot.spawn.usage"))
    return true
  end
  local plotId = parsePlotId(ctx, idArg)
  if not plotId then
    return true
  end

  ctx.data.setLocation("game.plots.list.p" .. plotId .. ".spawn", ctx.playerLocation)
  ctx.data.save()
  ctx.reply(msg("plot.spawn.set"):gsub("{index}", tostring(plotId)))
  return true
end

-- ---- build area (shared by "build_area <add|set|remove>" and "plot build_area <set|remove> <id>") ----

local function countFloorLayers(ctx, minX, maxX, minY, maxY, minZ, maxZ)
  local layers = 0
  for y = minY, maxY do
    local hasBlock = false
    for x = minX, maxX do
      for z = minZ, maxZ do
        if ctx.world.blockTypeAt(x, y, z) ~= "AIR" then
          hasBlock = true
          break
        end
      end
      if hasBlock then
        break
      end
    end
    if hasBlock then
      layers = layers + 1
    else
      break
    end
  end
  return layers
end

local function detectFloorMaterial(ctx, minX, maxX, minY, minZ, maxZ)
  for x = minX, maxX do
    for z = minZ, maxZ do
      local material = ctx.world.blockTypeAt(x, minY, z)
      if material ~= "AIR" then
        return material
      end
    end
  end
  return "GRASS_BLOCK"
end

local function isBuildAreaInsidePlot(ctx, plotId, minX, maxX, minY, maxY, minZ, maxZ)
  local totalPlots = ctx.data.getInt("game.plots.total", 0)
  if not plotId or plotId < 1 or plotId > totalPlots then
    return true
  end
  local base = "game.plots.list.p" .. plotId .. ".bounds"
  local plotMin = ctx.data.getLocation(base .. ".min")
  local plotMax = ctx.data.getLocation(base .. ".max")
  if not plotMin or not plotMax then
    return true
  end
  local pMinX, pMaxX = math.min(plotMin.x, plotMax.x), math.max(plotMin.x, plotMax.x)
  local pMinY, pMaxY = math.min(plotMin.y, plotMax.y), math.max(plotMin.y, plotMax.y)
  local pMinZ, pMaxZ = math.min(plotMin.z, plotMax.z), math.max(plotMin.z, plotMax.z)
  return minX >= pMinX and maxX <= pMaxX and minY >= pMinY and maxY <= pMaxY and minZ >= pMinZ and maxZ <= pMaxZ
end

local function sendSizeWarning(ctx, width, height, length)
  if width >= RECOMMENDED_WIDTH and height >= RECOMMENDED_HEIGHT and length >= RECOMMENDED_LENGTH then
    return
  end
  local warning = msg("build_area.add.below_recommended_size")
    :gsub("{x}", tostring(width)):gsub("{y}", tostring(height)):gsub("{z}", tostring(length))
    :gsub("{recommended_x}", tostring(RECOMMENDED_WIDTH))
    :gsub("{recommended_y}", tostring(RECOMMENDED_HEIGHT))
    :gsub("{recommended_z}", tostring(RECOMMENDED_LENGTH))
  if warning ~= "" then
    ctx.reply(warning)
  end
end

local function saveSelectedBuildArea(ctx, areaId, plotId, updateTotal, successMessageKey)
  if not ctx.selection.hasCompleteSelection() then
    ctx.reply(msg("build_area.add.must_use_stick"))
    return true
  end
  local pos1 = ctx.selection.getPosition1()
  local pos2 = ctx.selection.getPosition2()

  local minX, maxX = math.min(pos1.x, pos2.x), math.max(pos1.x, pos2.x)
  local minY, maxY = math.min(pos1.y, pos2.y), math.max(pos1.y, pos2.y)
  local minZ, maxZ = math.min(pos1.z, pos2.z), math.max(pos1.z, pos2.z)
  local height = maxY - minY + 1
  if height < 2 then
    ctx.reply(msg("build_area.add.too_shallow"))
    return true
  end

  local floorLayers = countFloorLayers(ctx, minX, maxX, minY, maxY, minZ, maxZ)
  if floorLayers == 0 then
    ctx.reply(msg("build_area.add.no_floor"))
    return true
  end
  if floorLayers > 2 then
    ctx.reply(msg("build_area.add.too_many_floor_layers"))
    return true
  end

  local floorMaterial = detectFloorMaterial(ctx, minX, maxX, minY, minZ, maxZ)

  if not isBuildAreaInsidePlot(ctx, plotId, minX, maxX, minY, maxY, minZ, maxZ) then
    ctx.reply(msg("build_area.add.outside_plot"))
    return true
  end

  local base = "game.build_areas.list.a" .. areaId
  ctx.data.setRegionBounds(base, pos1, pos2)
  ctx.data.setString(base .. ".floor", floorMaterial)
  if updateTotal then
    local totalAreas = ctx.data.getInt("game.build_areas.total", 0)
    if areaId > totalAreas then
      ctx.data.setInt("game.build_areas.total", areaId)
    end
  end
  ctx.data.save()

  local x, y, z = regionSize(pos1, pos2)
  local blocks = x * y * z
  ctx.reply(msg(successMessageKey)
    :gsub("{index}", tostring(areaId))
    :gsub("{blocks}", tostring(blocks))
    :gsub("{x}", tostring(x)):gsub("{y}", tostring(y)):gsub("{z}", tostring(z))
    :gsub("{floor}", floorMaterial))
  sendSizeWarning(ctx, x, y, z)
  return true
end

local function parseAreaId(ctx, idArg)
  local areaId = tonumber(idArg)
  local totalAreas = ctx.data.getInt("game.build_areas.total", 0)
  if not areaId or areaId < 1 or areaId > totalAreas then
    ctx.reply(msg("build_area.not_found"))
    return nil
  end
  return math.floor(areaId)
end

local function trimBuildAreaTotal(ctx)
  local totalAreas = ctx.data.getInt("game.build_areas.total", 0)
  while totalAreas > 0 do
    local min = ctx.data.getLocation("game.build_areas.list.a" .. totalAreas .. ".min")
    local max = ctx.data.getLocation("game.build_areas.list.a" .. totalAreas .. ".max")
    if min and max then
      break
    end
    totalAreas = totalAreas - 1
  end
  ctx.data.setInt("game.build_areas.total", totalAreas)
end

local function handleBuildAreaAdd(ctx)
  local totalPlots = ctx.data.getInt("game.plots.total", 0)
  if totalPlots == 0 then
    ctx.reply(msg("build_area.add.requires_plot_first"))
    return true
  end
  local totalAreas = ctx.data.getInt("game.build_areas.total", 0)
  local newAreaNumber = totalAreas + 1
  return saveSelectedBuildArea(ctx, newAreaNumber, newAreaNumber, true, "build_area.add.set")
end

local function handleBuildAreaSet(ctx)
  local idArg = ctx.args[2]
  if not idArg then
    ctx.reply(msg("build_area.set.usage"))
    return true
  end
  local areaId = parseAreaId(ctx, idArg)
  if not areaId then
    return true
  end
  return saveSelectedBuildArea(ctx, areaId, areaId, false, "build_area.set.success")
end

local function handleBuildAreaRemove(ctx)
  local idArg = ctx.args[2]
  if not idArg then
    ctx.reply(msg("build_area.remove.usage"))
    return true
  end
  local areaId = parseAreaId(ctx, idArg)
  if not areaId then
    return true
  end

  local totalAreas = ctx.data.getInt("game.build_areas.total", 0)
  ctx.data.remove("game.build_areas.list.a" .. areaId)
  for i = areaId + 1, totalAreas do
    local oldBase = "game.build_areas.list.a" .. i
    local newBase = "game.build_areas.list.a" .. (i - 1)
    local oldMin = ctx.data.getLocation(oldBase .. ".min")
    local oldMax = ctx.data.getLocation(oldBase .. ".max")
    local oldFloor = ctx.data.getString(oldBase .. ".floor")
    if oldMin and oldMax then
      ctx.data.setRegionBounds(newBase, oldMin, oldMax)
    end
    if oldFloor then
      ctx.data.setString(newBase .. ".floor", oldFloor)
    end
    ctx.data.remove(oldBase)
  end
  ctx.data.setInt("game.build_areas.total", totalAreas - 1)
  ctx.data.save()

  ctx.reply(msg("build_area.remove.success"):gsub("{index}", tostring(areaId)))
  return true
end

local function handlePlotBuildArea(ctx)
  local action = ctx.args[2]
  if not action then
    ctx.reply(msg("plot.build_area.usage"))
    return true
  end
  if action:lower() == "set" or action:lower() == "add" then
    local idArg = ctx.args[3]
    if not idArg then
      ctx.reply(msg("plot.build_area.usage"))
      return true
    end
    local plotId = parsePlotId(ctx, idArg)
    if not plotId then
      return true
    end
    return saveSelectedBuildArea(ctx, plotId, plotId, true, "plot.build_area.set")
  end
  if action:lower() == "remove" then
    local idArg = ctx.args[3]
    if not idArg then
      ctx.reply(msg("plot.build_area.usage"))
      return true
    end
    local plotId = parsePlotId(ctx, idArg)
    if not plotId then
      return true
    end
    ctx.data.remove("game.build_areas.list.a" .. plotId)
    trimBuildAreaTotal(ctx)
    ctx.data.save()
    ctx.reply(msg("plot.build_area.remove"):gsub("{index}", tostring(plotId)))
    return true
  end
  ctx.reply(msg("plot.build_area.usage"))
  return true
end

local function handlePlot(ctx)
  local action = ctx.args[1]
  if action == "add" then return handlePlotAdd(ctx) end
  if action == "set" then return handlePlotSet(ctx) end
  if action == "remove" then return handlePlotRemove(ctx) end
  if action == "spawn" then return handlePlotSpawn(ctx) end
  if action == "build_area" then return handlePlotBuildArea(ctx) end
  ctx.reply(msg("plot.usage"))
  return true
end

local function handleBuildArea(ctx)
  local action = ctx.args[1]
  if action == "add" then return handleBuildAreaAdd(ctx) end
  if action == "set" then return handleBuildAreaSet(ctx) end
  if action == "remove" then return handleBuildAreaRemove(ctx) end
  ctx.reply(msg("build_area.usage"))
  return true
end

-- ---- showcase ----

local function handleShowcaseSet(ctx)
  if not ctx.selection.hasCompleteSelection() then
    ctx.reply(msg("showcase.set.must_use_stick"))
    return true
  end
  local pos1 = ctx.selection.getPosition1()
  local pos2 = ctx.selection.getPosition2()
  local height = math.abs(pos2.y - pos1.y) + 1
  if height < 10 then
    ctx.reply(msg("showcase.set.too_shallow"))
    return true
  end

  ctx.data.setRegionBounds("game.showcase_plot.bounds", pos1, pos2)
  ctx.data.setLocation("game.showcase_plot.spawn", ctx.playerLocation)
  ctx.data.save()

  local x, y, z = regionSize(pos1, pos2)
  local blocks = x * y * z
  ctx.reply(msg("showcase.set.success")
    :gsub("{blocks}", tostring(blocks))
    :gsub("{x}", tostring(x)):gsub("{y}", tostring(y)):gsub("{z}", tostring(z)))
  return true
end

local function handleShowcaseRemove(ctx)
  ctx.data.remove("game.showcase_plot")
  ctx.data.save()
  ctx.reply(msg("showcase.remove.success"))
  return true
end

local function handleShowcase(ctx)
  local action = ctx.args[1]
  if action == "set" then return handleShowcaseSet(ctx) end
  if action == "remove" then return handleShowcaseRemove(ctx) end
  ctx.reply(msg("showcase.usage"))
  return true
end

-- ---- structure ----

local function handleStructureCreate(ctx)
  local id = ctx.args[2]
  if not id or id == "" then
    ctx.reply(msg("structure.create.usage"))
    return true
  end
  if not ctx.selection.hasCompleteSelection() then
    ctx.reply(msg("structure.create.must_use_stick"))
    return true
  end
  local pos1 = ctx.selection.getPosition1()
  local pos2 = ctx.selection.getPosition2()

  local voxelCount = ctx.data.saveStructureTemplate(id, pos1, pos2)
  if not voxelCount then
    ctx.reply("<red>Failed to save structure.</red>")
    return true
  end
  ctx.reply(msg("structure.create.saved"):gsub("{id}", id:lower():gsub(" ", "_")):gsub("{voxels}", tostring(voxelCount)))
  return true
end

local function handleStructureRemove(ctx)
  local id = ctx.args[2]
  if not id or id == "" then
    ctx.reply(msg("structure.remove.usage"))
    return true
  end
  if not ctx.data.removeStructureTemplate(id) then
    ctx.reply(msg("structure.remove.not_found"))
    return true
  end
  ctx.reply(msg("structure.remove.success"):gsub("{id}", id))
  return true
end

local function handleStructureList(ctx)
  local ids = ctx.data.listStructureTemplateIds()
  if #ids == 0 then
    ctx.reply(msg("structure.list.empty"))
    return true
  end
  local lines = { msg("structure.list.header") }
  for _, id in ipairs(ids) do
    lines[#lines + 1] = "<gray>- </gray><yellow>" .. id .. "</yellow>"
  end
  ctx.reply(table.concat(lines, "\n"))
  return true
end

local function handleStructure(ctx)
  local action = ctx.args[1]
  if action == "create" then return handleStructureCreate(ctx) end
  if action == "remove" then return handleStructureRemove(ctx) end
  if action == "list" then return handleStructureList(ctx) end
  ctx.reply(msg("structure.usage"))
  return true
end

function M.register()
  ba.setup.on("plot", handlePlot)
  ba.setup.on("build_area", handleBuildArea)
  ba.setup.on("showcase", handleShowcase)
  ba.setup.on("structure", handleStructure)

  ba.setup.status("build_area", function(ctx)
    return ctx.data.getInt("game.build_areas.total", 0) > 0
  end)
  ba.setup.status("plot", function(ctx)
    return ctx.data.getInt("game.plots.total", 0) > 0 or ctx.data.has("game.plot.bounds.min.x")
  end)
  ba.setup.status("showcase", function(ctx)
    return ctx.data.has("game.showcase_plot.bounds.min.x") and ctx.data.has("game.showcase_plot.bounds.max.x")
  end)
  -- Deliberate improvement over legacy: satisfied as soon as the ~350 bundled default structures
  -- extract, not just admin-saved ones (legacy's own check ignored the bundled defaults).
  ba.setup.status("structure", function(ctx)
    return #ctx.data.listStructureTemplateIds() > 0
  end)
end

return M

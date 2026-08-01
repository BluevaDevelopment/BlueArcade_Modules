--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy BuildBattleSetup.java.
local M = {}

local function msg(ctx, key)
  local message = ba.config.translation(nil, "setup_messages." .. key)
  return message or ""
end

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

local function detectFloorMaterial(ctx, minX, minY, minZ)
  local material = ctx.world.blockTypeAt(minX, minY, minZ)
  if material ~= "AIR" then
    return material
  end
  return "GRASS_BLOCK"
end

local function boundsOf(pos1, pos2)
  return {
    minX = math.min(math.floor(pos1.x), math.floor(pos2.x)),
    maxX = math.max(math.floor(pos1.x), math.floor(pos2.x)),
    minY = math.min(math.floor(pos1.y), math.floor(pos2.y)),
    maxY = math.max(math.floor(pos1.y), math.floor(pos2.y)),
    minZ = math.min(math.floor(pos1.z), math.floor(pos2.z)),
    maxZ = math.max(math.floor(pos1.z), math.floor(pos2.z)),
  }
end

local function handlePlotAdd(ctx)
  if not ctx.selection.hasCompleteSelection() then
    ctx.reply(msg(ctx, "plot.add.must_use_stick"))
    return true
  end

  local pos1 = ctx.selection.getPosition1()
  local pos2 = ctx.selection.getPosition2()
  local b = boundsOf(pos1, pos2)
  local height = b.maxY - b.minY + 1

  if height < 3 then
    ctx.reply(msg(ctx, "plot.add.too_shallow"))
    return true
  end

  local floorLayers = countFloorLayers(ctx, b.minX, b.maxX, b.minY, b.maxY, b.minZ, b.maxZ)
  if floorLayers == 0 then
    ctx.reply(msg(ctx, "plot.add.no_floor"))
    return true
  end
  if floorLayers > 2 then
    ctx.reply(msg(ctx, "plot.add.too_many_floor_layers"))
    return true
  end

  local floorMaterial = detectFloorMaterial(ctx, b.minX, b.minY, b.minZ)

  local totalPlots = ctx.data.getInt("game.plots.total", 0)
  local newPlotNumber = totalPlots + 1
  local basePath = "game.plots.list.p" .. newPlotNumber

  ctx.data.setRegionBounds(basePath .. ".bounds", pos1, pos2)
  ctx.data.setString(basePath .. ".floor", floorMaterial)
  ctx.data.setLocation(basePath .. ".spawn", ctx.playerLocation)
  ctx.data.setInt("game.plots.total", newPlotNumber)
  ctx.data.save()

  local x = math.abs(pos2.x - pos1.x) + 1
  local z = math.abs(pos2.z - pos1.z) + 1
  local blocks = x * height * z

  ctx.reply(msg(ctx, "plot.add.set")
    :gsub("{index}", tostring(newPlotNumber))
    :gsub("{blocks}", tostring(blocks))
    :gsub("{x}", tostring(x))
    :gsub("{y}", tostring(height))
    :gsub("{z}", tostring(z))
    :gsub("{floor}", floorMaterial))

  local spawnMsg = msg(ctx, "plot.add.spawn_set")
  if spawnMsg ~= "" then
    ctx.reply(spawnMsg:gsub("{index}", tostring(newPlotNumber)))
  end
  return true
end

local function parsePlotId(ctx, idArg)
  local plotId = tonumber(idArg)
  if not plotId or plotId ~= math.floor(plotId) then
    ctx.reply(msg(ctx, "plot.invalid_id"))
    return nil
  end
  local totalPlots = ctx.data.getInt("game.plots.total", 0)
  if plotId < 1 or plotId > totalPlots then
    ctx.reply(msg(ctx, "plot.not_found"))
    return nil
  end
  return plotId
end

local function handlePlotSet(ctx)
  local idArg = ctx.args[2]
  if not idArg then
    ctx.reply(msg(ctx, "plot.set.usage"))
    return true
  end
  local plotId = parsePlotId(ctx, idArg)
  if not plotId then
    return true
  end

  if not ctx.selection.hasCompleteSelection() then
    ctx.reply(msg(ctx, "plot.add.must_use_stick"))
    return true
  end

  local pos1 = ctx.selection.getPosition1()
  local pos2 = ctx.selection.getPosition2()
  local b = boundsOf(pos1, pos2)
  local height = b.maxY - b.minY + 1

  if height < 3 then
    ctx.reply(msg(ctx, "plot.add.too_shallow"))
    return true
  end

  local floorLayers = countFloorLayers(ctx, b.minX, b.maxX, b.minY, b.maxY, b.minZ, b.maxZ)
  if floorLayers == 0 then
    ctx.reply(msg(ctx, "plot.add.no_floor"))
    return true
  end
  if floorLayers > 2 then
    ctx.reply(msg(ctx, "plot.add.too_many_floor_layers"))
    return true
  end

  local floorMaterial = detectFloorMaterial(ctx, b.minX, b.minY, b.minZ)
  local basePath = "game.plots.list.p" .. plotId

  ctx.data.setRegionBounds(basePath .. ".bounds", pos1, pos2)
  ctx.data.setString(basePath .. ".floor", floorMaterial)
  ctx.data.setLocation(basePath .. ".spawn", ctx.playerLocation)
  ctx.data.save()

  local x = math.abs(pos2.x - pos1.x) + 1
  local z = math.abs(pos2.z - pos1.z) + 1
  local blocks = x * height * z

  ctx.reply(msg(ctx, "plot.set.success")
    :gsub("{index}", tostring(plotId))
    :gsub("{blocks}", tostring(blocks))
    :gsub("{x}", tostring(x))
    :gsub("{y}", tostring(height))
    :gsub("{z}", tostring(z))
    :gsub("{floor}", floorMaterial))
  return true
end

local function handlePlotRemove(ctx)
  local idArg = ctx.args[2]
  if not idArg then
    ctx.reply(msg(ctx, "plot.remove.usage"))
    return true
  end
  local plotId = parsePlotId(ctx, idArg)
  if not plotId then
    return true
  end

  local totalPlots = ctx.data.getInt("game.plots.total", 0)
  ctx.data.remove("game.plots.list.p" .. plotId)

  for i = plotId + 1, totalPlots do
    local oldPath = "game.plots.list.p" .. i
    local newPath = "game.plots.list.p" .. (i - 1)

    local oldMin = ctx.data.getLocation(oldPath .. ".bounds.min")
    local oldMax = ctx.data.getLocation(oldPath .. ".bounds.max")
    local oldFloor = ctx.data.getString(oldPath .. ".floor")
    local oldSpawn = ctx.data.getLocation(oldPath .. ".spawn")

    if oldMin and oldMax then
      ctx.data.setRegionBounds(newPath .. ".bounds", oldMin, oldMax)
    end
    if oldFloor then
      ctx.data.setString(newPath .. ".floor", oldFloor)
    end
    if oldSpawn then
      ctx.data.setLocation(newPath .. ".spawn", oldSpawn)
    end
    ctx.data.remove(oldPath)
  end

  ctx.data.setInt("game.plots.total", totalPlots - 1)
  ctx.data.save()

  ctx.reply(msg(ctx, "plot.remove.success"):gsub("{index}", tostring(plotId)))
  return true
end

local function handlePlotSpawn(ctx)
  local action = ctx.args[2]
  if not action or action:lower() ~= "set" then
    ctx.reply(msg(ctx, "plot.spawn.usage"))
    return true
  end

  local idArg = ctx.args[3]
  if not idArg then
    ctx.reply(msg(ctx, "plot.spawn.usage"))
    return true
  end
  local plotId = parsePlotId(ctx, idArg)
  if not plotId then
    return true
  end

  local basePath = "game.plots.list.p" .. plotId
  ctx.data.setLocation(basePath .. ".spawn", ctx.playerLocation)
  ctx.data.save()

  ctx.reply(msg(ctx, "plot.spawn.set"):gsub("{index}", tostring(plotId)))
  return true
end

local function handlePlot(ctx)
  local action = ctx.args[1]
  if action and action:lower() == "add" then
    return handlePlotAdd(ctx)
  elseif action and action:lower() == "set" then
    return handlePlotSet(ctx)
  elseif action and action:lower() == "remove" then
    return handlePlotRemove(ctx)
  elseif action and action:lower() == "spawn" then
    return handlePlotSpawn(ctx)
  end
  ctx.reply(msg(ctx, "plot.usage"))
  return true
end

function M.register()
  ba.setup.on("plot", handlePlot)

  ba.setup.status("plot", function(ctx)
    return ctx.data.getInt("game.plots.total", 0) > 0
  end)
end

return M

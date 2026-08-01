-- Mirrors legacy GuessTheBuildSetup.java. Uses `ba.config` (not `ctx.coreConfig`) for translations -
-- `ctx.player` never resolves through it at setup time, so it falls back to server default locale.
local M = {}

local function setupMessage(key, fallback)
  local msg = ba.config.translation(nil, "setup_messages." .. key)
  if msg and msg ~= "" then
    return msg
  end
  return fallback
end

local function countFloorLayers(ctx, minX, maxX, minY, maxY, minZ, maxZ)
  local layers = 0
  for y = minY, maxY do
    local hasBlock = false
    for x = minX, maxX do
      if hasBlock then
        break
      end
      for z = minZ, maxZ do
        if ctx.world.blockTypeAt(x, y, z) ~= "AIR" then
          hasBlock = true
          break
        end
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

local function handlePlotSet(ctx)
  if not ctx.selection.hasCompleteSelection() then
    ctx.reply(setupMessage("plot.set.must_use_stick", "<red>Select two corners with the setup tool first.</red>"))
    return
  end

  local pos1 = ctx.selection.getPosition1()
  local pos2 = ctx.selection.getPosition2()

  local minX, maxX = math.min(pos1.x, pos2.x), math.max(pos1.x, pos2.x)
  local minY, maxY = math.min(pos1.y, pos2.y), math.max(pos1.y, pos2.y)
  local minZ, maxZ = math.min(pos1.z, pos2.z), math.max(pos1.z, pos2.z)
  local height = maxY - minY + 1

  if height < 3 then
    ctx.reply(setupMessage("plot.set.too_shallow", "<red>Plot is too shallow. The selection must be at least 3 blocks high (1 floor + 2 air).</red>"))
    return
  end

  local floorLayers = countFloorLayers(ctx, minX, maxX, minY, maxY, minZ, maxZ)
  if floorLayers == 0 then
    ctx.reply(setupMessage("plot.set.no_floor", "<red>No floor detected. The lowest layer of the selection must contain blocks.</red>"))
    return
  end
  if floorLayers > 2 then
    ctx.reply(setupMessage("plot.set.too_many_floor_layers", "<red>Too many floor layers detected. The floor must be 1-2 block layers thick. Clear excess blocks above the floor.</red>"))
    return
  end

  local floorMaterial = detectFloorMaterial(ctx, minX, minY, minZ)

  ctx.data.setRegionBounds("game.plot.bounds", pos1, pos2)
  ctx.data.setString("game.plot.floor", floorMaterial)
  ctx.data.setLocation("game.plot.spawn", ctx.playerLocation)
  ctx.data.save()

  local x = math.abs(pos2.x - pos1.x) + 1
  local y = height
  local z = math.abs(pos2.z - pos1.z) + 1
  local blocks = x * y * z

  local msg = setupMessage("plot.set.success",
    "<green>Plot set.</green> <gray>Blocks:</gray> <white>{blocks}</white> <gray>({x}x{y}x{z})</gray> <gray>Floor:</gray> <yellow>{floor}</yellow>")
  msg = msg:gsub("{blocks}", tostring(blocks)):gsub("{x}", tostring(x)):gsub("{y}", tostring(y)):gsub("{z}", tostring(z)):gsub("{floor}", floorMaterial)
  ctx.reply(msg)

  local spawnMsg = setupMessage("plot.set.spawn_set", "")
  if spawnMsg ~= "" then
    ctx.reply(spawnMsg)
  end
end

local function handlePlotSpawnSet(ctx)
  ctx.data.setLocation("game.plot.spawn", ctx.playerLocation)
  ctx.data.save()

  ctx.reply(setupMessage("plot.spawn.set", "<green>Plot spawn updated to your current location.</green>"))
end

local function handlePlot(ctx)
  local action = ctx.args[1]
  if action and action:lower() == "set" then
    handlePlotSet(ctx)
    return
  end
  if action and action:lower() == "spawn" then
    handlePlotSpawnSet(ctx)
    return
  end
  ctx.reply(setupMessage("plot.usage", "<red>Usage:</red> <yellow>/baa game <id> guess_the_build plot <set|spawn></yellow>"))
end

function M.register()
  ba.setup.on("plot", handlePlot)

  ba.setup.status("plot", function(ctx)
    return ctx.data.getInt("game.plots.total", 0) > 0 or ctx.data.has("game.plot.bounds.min.x")
  end)
end

return M

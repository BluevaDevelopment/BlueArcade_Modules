--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy SpeedBuildersListener.java. onEntityChangeBlock isn't ported - Kotlin's
-- UniversalEventListener already cancels registered FallingBlock shards from placing on landing.
local gameManager = require("game_manager")

local M = {}

local function sendCantBuildHere(session, handle)
  local msg = session.config.translation(handle, "messages.cant_build_here")
  if msg then
    session.messages.sendRaw(handle, msg)
  end
end

local function isFloorLayer(location, area)
  local floorY = math.min(area.min.y, area.max.y)
  return math.floor(location.y) == floorY
end

local function isInsideArea(location, area)
  local x, y, z = math.floor(location.x), math.floor(location.y), math.floor(location.z)
  return x >= math.min(area.min.x, area.max.x) and x <= math.max(area.min.x, area.max.x)
    and y >= math.min(area.min.y, area.max.y) and y <= math.max(area.min.y, area.max.y)
    and z >= math.min(area.min.z, area.max.z) and z <= math.max(area.min.z, area.max.z)
end

local function breakIntoInventory(session, handle, blockType, location)
  if not blockType or blockType == "AIR" then
    return
  end
  session.world.setBlockType(location.x, location.y, location.z, "AIR", false)
  session.player.giveBlockItem(handle, blockType, 1)
end

local function scheduleEvaluate(session, handle)
  session.scheduler.runLater("arena_" .. session.arenaId .. "_speed_builders_eval_" .. handle, function()
    gameManager.evaluateBuild(session, handle)
  end, 1)
end

function M.register()
  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end
    local state = session.state
    if not state or (state.phase ~= "SHOWCASE" and state.phase ~= "BUILDING") then
      return
    end
    local isAlive = false
    for _, handle in ipairs(session.alivePlayers()) do
      if handle == e.player then
        isAlive = true
        break
      end
    end
    if not isAlive then
      return
    end
    local plot = state.playerPlot[e.player]
    if not plot then
      return
    end

    local strictRegion = session.config.getBoolean("gameplay.strict_plot_region", false)
    local margin = strictRegion and 0 or math.max(0, session.config.getInt("gameplay.plot_border_margin", 6))
    local x, z = math.floor(e.to.x), math.floor(e.to.z)
    local minX = math.min(plot.min.x, plot.max.x) - margin
    local maxX = math.max(plot.min.x, plot.max.x) + margin
    local minZ = math.min(plot.min.z, plot.max.z) - margin
    local maxZ = math.max(plot.min.z, plot.max.z) + margin
    local inside
    if x < minX or x > maxX or z < minZ or z > maxZ then
      inside = false
    elseif not strictRegion then
      inside = true
    else
      local y = math.floor(e.to.y)
      inside = y >= math.min(plot.min.y, plot.max.y) and y <= math.max(plot.min.y, plot.max.y)
    end
    if not inside then
      e.setTo(e.from)
    end
  end)

  ba.events.on("block_break", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end
    local state = session.state
    if not state or state.phase ~= "BUILDING" then
      e.cancel()
      return
    end

    local area = state.playerBuildArea[e.player]
    if area then
      if not isInsideArea(e.location, area) then
        e.cancel()
        sendCantBuildHere(session, e.player)
        return
      end
      if isFloorLayer(e.location, area) then
        e.cancel()
        return
      end
    else
      local plot = state.playerPlot[e.player]
      if plot and not isInsideArea(e.location, plot) then
        e.cancel()
        sendCantBuildHere(session, e.player)
        return
      end
    end

    breakIntoInventory(session, e.player, e.blockType, e.location)
    e.setDropItems(false)
    e.cancel()
    scheduleEvaluate(session, e.player)
  end)

  -- LEFT_CLICK_BLOCK - legacy's second break path, needed because real survival break time can
  -- take several ticks; this gives speed_builders its "instant break" feel regardless of tool.
  ba.events.on("player_interact", function(session, e)
    if e.action ~= "LEFT_CLICK_BLOCK" or not e.clickedBlockType then
      return
    end
    if not session.isPlaying(e.player) then
      return
    end
    local state = session.state
    if not state or state.phase ~= "BUILDING" then
      e.cancel()
      return
    end

    local area = state.playerBuildArea[e.player]
    if area then
      if not isInsideArea(e.clickedBlockLocation, area) then
        e.cancel()
        sendCantBuildHere(session, e.player)
        return
      end
      if isFloorLayer(e.clickedBlockLocation, area) then
        e.cancel()
        return
      end
    end

    e.cancel()
    breakIntoInventory(session, e.player, e.clickedBlockType, e.clickedBlockLocation)
    scheduleEvaluate(session, e.player)
  end)

  ba.events.on("block_place", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end
    local state = session.state
    if not state or state.phase ~= "BUILDING" then
      e.cancel()
      return
    end

    local area = state.playerBuildArea[e.player]
    if area then
      if not isInsideArea(e.location, area) then
        e.cancel()
        sendCantBuildHere(session, e.player)
        return
      end
      e.allow()
    else
      local plot = state.playerPlot[e.player]
      if plot and not isInsideArea(e.location, plot) then
        e.cancel()
        sendCantBuildHere(session, e.player)
        return
      end
      e.allow()
    end

    scheduleEvaluate(session, e.player)
  end)

  ba.events.on("player_damage", function(session, e)
    if session.isPlaying(e.player) then
      e.cancel()
    end
  end)

  ba.events.on("player_drop_item", function(session, e)
    if session.isPlaying(e.player) then
      e.cancel()
    end
  end)
end

return M

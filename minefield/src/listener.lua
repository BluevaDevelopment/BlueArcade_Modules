local gameManager = require("game_manager")

local M = {}

local function isInsideFinishLine(session, location)
  local finishMin = session.dataAccess.getGameLocation("game.finish_line.bounds.min")
  local finishMax = session.dataAccess.getGameLocation("game.finish_line.bounds.max")
  if finishMin == nil or finishMax == nil then return false end

  return location.x >= math.min(finishMin.x, finishMax.x) and location.x <= math.max(finishMin.x, finishMax.x)
      and location.y >= math.min(finishMin.y, finishMax.y) and location.y <= math.max(finishMin.y, finishMax.y)
      and location.z >= math.min(finishMin.z, finishMax.z) and location.z <= math.max(finishMin.z, finishMax.z)
end

function M.register()
  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then return end

    local sameBlock = math.floor(e.from.x) == math.floor(e.to.x)
        and math.floor(e.from.y) == math.floor(e.to.y)
        and math.floor(e.from.z) == math.floor(e.to.z)
    if sameBlock then return end

    if session.phase() == "COUNTDOWN" then
      session.player.teleport(e.player, e.from)
      return
    end

    if not session.isInsideBounds(e.to) then
      gameManager.handlePlayerOutOfBounds(session, e.player, false)
      return
    end

    local deathBlockName = session.dataAccess.getGameDataString("basic.death_block")
    local deathBlock = deathBlockName ~= nil and string.upper(deathBlockName) or "BARRIER"
    local blockBelowType = session.world.blockTypeAt(math.floor(e.to.x), math.floor(e.to.y - 1), math.floor(e.to.z))
    if blockBelowType == deathBlock then
      gameManager.handlePlayerOutOfBounds(session, e.player, true)
      return
    end

    if isInsideFinishLine(session, e.to) then
      gameManager.handleFinishLineCross(session, e.player)
    end
  end)

  -- Mines are pressure plates: stepping on one fires player_interact with action == "PHYSICAL".
  ba.events.on("player_interact", function(session, e)
    if e.action ~= "PHYSICAL" then return end
    if e.clickedBlockType == nil then return end
    if not session.isPlaying(e.player) then return end
    if session.phase() ~= "PLAYING" then return end
    if not gameManager.isMineMaterial(session, e.clickedBlockType) then return end

    e:cancel()
    local loc = e.clickedBlockLocation
    session.world.setBlockType(loc.x, loc.y, loc.z, "AIR")
    gameManager.removeMineLocation(session, loc.x, loc.y, loc.z)
    gameManager.handleMineTrigger(session, e.player, loc)
  end)

  -- All damage is cancelled unconditionally while playing - death only comes from falling out of
  -- bounds/death block or a mine, matching legacy's no-cause-check cancel.
  ba.events.on("player_damage", function(session, e)
    if session.isPlaying(e.player) then e:cancel() end
  end)
end

return M

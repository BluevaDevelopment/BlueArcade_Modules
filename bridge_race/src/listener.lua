local gameManager = require("game_manager")

local M = {}

function M.register()
  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then return end

    local sameBlock = math.floor(e.from.x) == math.floor(e.to.x)
        and math.floor(e.from.y) == math.floor(e.to.y)
        and math.floor(e.from.z) == math.floor(e.to.z)
    if sameBlock then return end

    gameManager.handlePlayerMove(session, e.player, e.from, e.to)
  end)

  ba.events.on("player_damage", function(session, e)
    if e.cause ~= "FALL" then return end
    if session.isPlaying(e.player) then e:cancel() end
  end)

  -- Core cancels block placement by default; un-cancel within bounds while playing, then track for later break/cleanup.
  ba.events.on("block_place", function(session, e)
    if session.phase() ~= "PLAYING" then
      e:cancel()
      return
    end

    if not session.isInsideBounds(e.location) then
      e:cancel()
      return
    end

    e:allow()
    gameManager.handleBlockPlaced(session, e.player, e.location)
  end)

  -- Only un-cancels breaking a block this module tracked as player-placed; arena terrain stays protected.
  ba.events.on("block_break", function(session, e)
    if session.phase() ~= "PLAYING" then
      e:cancel()
      return
    end

    if gameManager.isPlacedBlock(session, e.location) then
      e:allow()
      gameManager.removePlacedBlock(session, e.location)
      return
    end

    e:cancel()
  end)
end

return M

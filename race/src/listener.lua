local gameManager = require("game_manager")

local M = {}

function M.register()
  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then return end

    local sameBlock = math.floor(e.from.x) == math.floor(e.to.x)
        and math.floor(e.from.y) == math.floor(e.to.y)
        and math.floor(e.from.z) == math.floor(e.to.z)
    if sameBlock then return end

    local phase = session.phase()

    if phase == "COUNTDOWN" then
      session.player.teleport(e.player, e.from)
      return
    end

    if phase == "PLAYING" then
      gameManager.processActiveMovement(session, e.player, e.to)
      return
    end

    -- WAITING / ENDING / FINISHED
    if not session.isInsideBounds(e.to) then
      gameManager.handleNonPlayingOutOfBounds(session, e.player)
    end
  end)

  ba.events.on("player_damage", function(session, e)
    if e.cause ~= "FALL" then return end
    if session.isPlaying(e.player) then e:cancel() end
  end)
end

return M

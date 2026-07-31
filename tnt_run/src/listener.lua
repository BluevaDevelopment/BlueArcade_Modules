local gameManager = require("game_manager")

local M = {}

function M.register()
  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then return end

    if session.phase() ~= "PLAYING" then
      if not session.isInsideBounds(e.to) then
        local spawn = session.arena.randomSpawn()
        if spawn ~= nil then
          session.player.teleport(e.player, spawn)
        end
      end
      return
    end

    gameManager.refreshDoubleJumpState(session, e.player)

    if gameManager.shouldEliminate(session, e.to) then
      gameManager.handlePlayerElimination(session, e.player)
      return
    end

    local sameBlock = math.floor(e.from.x) == math.floor(e.to.x)
        and math.floor(e.from.y) == math.floor(e.to.y)
        and math.floor(e.from.z) == math.floor(e.to.z)
    if not sameBlock then
      gameManager.handlePlayerStep(session, e.player, e.to)
    end
  end)

  ba.events.on("player_toggle_flight", function(session, e)
    if gameManager.handleDoubleJump(session, e.player) then
      e:cancel()
    end
  end)

  ba.events.on("player_damage", function(session, e)
    if e.cause ~= "FALL" then return end
    if session.phase() == "PLAYING" and session.isPlaying(e.player) then
      e:cancel()
    end
  end)
end

return M

local gameManager = require("game_manager")

local M = {}

function M.register()
  -- No COUNTDOWN-phase teleport-back branch here (unlike race/fast_zone) - it's real, provably
  -- dead code in the legacy module: `freezePlayersOnCountdown()` hardcodes `return false`, so the
  -- listener's own `phase == COUNTDOWN && freezePlayersOnCountdown()` guard can never be true.
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

    if gameManager.shouldEliminate(session, e.to) then
      gameManager.handlePlayerElimination(session, e.player)
      return
    end

    -- Only the (expensive) trail block-touch detection is gated on a real block change - the
    -- elimination/bounds checks above run on every move, matching `RedAlertListener.onPlayerMove`'s
    -- own placement of `hasChangedBlock` right before `handlePlayerStep`, not at the top.
    local sameBlock = math.floor(e.from.x) == math.floor(e.to.x)
        and math.floor(e.from.y) == math.floor(e.to.y)
        and math.floor(e.from.z) == math.floor(e.to.z)
    if not sameBlock then
      gameManager.handlePlayerStep(session, e.player, e.to)
    end
  end)

  ba.events.on("player_damage", function(session, e)
    if e.cause ~= "FALL" then return end
    if session.isPlaying(e.player) then e:cancel() end
  end)
end

return M

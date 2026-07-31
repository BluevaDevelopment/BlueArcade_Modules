local gameManager = require("game_manager")

local M = {}

function M.register()
  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then return end

    if session.phase() ~= "PLAYING" then
      if not session.isInsideBounds(e.to) then
        session.respawnPlayer(e.player)
      end
      return
    end

    if gameManager.shouldEliminate(session, e.to) then
      gameManager.handlePlayerElimination(session, e.player)
    end
  end)

  ba.events.on("player_interact", function(session, e)
    if e.action ~= "RIGHT_CLICK_BLOCK" and e.action ~= "LEFT_CLICK_BLOCK" then return end
    if e.clickedBlockLocation == nil then return end
    if not gameManager.isPowerupBlock(session, e.clickedBlockLocation) then return end
    if session.phase() ~= "PLAYING" then return end
    if not session.isPlaying(e.player) then return end

    e:cancel()
    gameManager.handlePowerupPickup(session, e.player, e.clickedBlockLocation)
  end)

  -- block_party has no combat at all - any PvP hit during a match is always blocked.
  ba.events.on("player_damage_by_entity", function(session, e)
    if not session.isPlaying(e.target) then return end
    e:cancel()
  end)

  -- the shared dispatch fires this for PvP hits too (EntityDamageByEntityEvent shares
  -- EntityDamageEvent's handler list) - only cancel FALL here, PvP is handled above.
  ba.events.on("player_damage", function(session, e)
    if e.cause ~= "FALL" then return end
    if session.isPlaying(e.player) then e:cancel() end
  end)

  ba.events.on("block_break", function(session, e)
    if session.isPlaying(e.player) then e:cancel() end
  end)

  ba.events.on("block_place", function(session, e)
    if session.isPlaying(e.player) then e:cancel() end
  end)
end

return M

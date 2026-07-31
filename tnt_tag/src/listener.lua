local gameManager = require("game_manager")

local M = {}

function M.register()
  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then return end
    if not session.isInsideBounds(e.to) then
      session.respawnPlayer(e.player)
    end
  end)

  ba.events.on("block_break", function(session, e)
    if session.isPlaying(e.player) then e:cancel() end
  end)

  ba.events.on("block_place", function(session, e)
    if session.isPlaying(e.player) then e:cancel() end
  end)

  ba.events.on("player_damage_by_entity", function(session, e)
    if not session.isPlaying(e.target) then return end

    if session.phase() ~= "PLAYING" then
      e:cancel()
      return
    end

    if e.damager == nil or not session.isPlaying(e.damager) then
      e:cancel()
      return
    end

    if not gameManager.playerCanTag(session, e.damager) then
      e:cancel()
      return
    end

    gameManager.passTNT(session, e.damager, e.target)
    e.setDamage(0)
  end)

  -- the shared dispatch fires this for the same PvP hit too (EntityDamageByEntityEvent shares
  -- EntityDamageEvent's handler list) - only cancel non-combat causes, combat is handled above.
  ba.events.on("player_damage", function(session, e)
    if not session.isPlaying(e.player) then return end
    if e.cause == "ENTITY_ATTACK" or e.cause == "ENTITY_SWEEP_ATTACK" then return end
    e:cancel()
  end)
end

return M

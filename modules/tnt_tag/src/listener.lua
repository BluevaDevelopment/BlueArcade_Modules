--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

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

  -- shared dispatch: EntityDamageByEntityEvent reuses EntityDamageEvent's handler list, so this also fires per hit; only cancel non-combat causes.
  ba.events.on("player_damage", function(session, e)
    if not session.isPlaying(e.player) then return end
    if e.cause == "ENTITY_ATTACK" or e.cause == "ENTITY_SWEEP_ATTACK" then return end
    e:cancel()
  end)
end

return M

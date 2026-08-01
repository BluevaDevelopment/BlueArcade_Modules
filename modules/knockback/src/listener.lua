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

    if session.phase() ~= "PLAYING" then
      if not session.isInsideBounds(e.to) then
        gameManager.respawnOutOfBounds(session, e.player)
      end
      return
    end

    if not session.isInsideBounds(e.to) then
      gameManager.handlePlayerFall(session, e.player)
      return
    end

    local blockBelow = session.world.blockTypeAt(math.floor(e.to.x), math.floor(e.to.y) - 1, math.floor(e.to.z))
    if blockBelow == gameManager.deathBlock(session) then
      gameManager.handlePlayerFall(session, e.player)
    end
  end)

  ba.events.on("block_break", function(session, e)
    if session.isPlaying(e.player) then e:cancel() end
  end)

  ba.events.on("player_damage", function(session, e)
    if session.phase() ~= "PLAYING" then return end
    if not session.isPlaying(e.player) then return end

    if e.cause == "VOID" then
      e:cancel()
      gameManager.handlePlayerFall(session, e.player)
    elseif e.cause == "FALL" then
      e:cancel()
    end
  end)

  ba.events.on("player_damage_by_entity", function(session, e)
    if e.target == nil then return end
    if session.phase() ~= "PLAYING" then return end

    if not session.isPlaying(e.target) or not session.isPlaying(e.damager) or e.damager == e.target then
      e:cancel()
      return
    end

    e.setDamage(0)
    gameManager.handleKnockbackHit(session, e.damager, e.target)
  end)
end

return M

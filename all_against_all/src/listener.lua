local gameManager = require("game_manager")

local M = {}

local function isSpectator(session, handle)
  for _, spectator in ipairs(session.spectators()) do
    if spectator == handle then return true end
  end
  return false
end

local function hasPlayRegion(session)
  return session.dataAccess.getGameLocation("game.play_area.bounds.min") ~= nil
      and session.dataAccess.getGameLocation("game.play_area.bounds.max") ~= nil
end

local function getDeathBlock(session)
  local deathBlockName = session.dataAccess.getGameDataString("basic.death_block")
  if deathBlockName ~= nil then
    return string.upper(deathBlockName)
  end
  return "BARRIER"
end

function M.register()
  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then return end
    if session.player.getGameMode(e.player) == "SPECTATOR" then return end
    if isSpectator(session, e.player) then return end

    if session.phase() ~= "PLAYING" then
      if not session.isInsideBounds(e.to) then
        gameManager.handleRespawn(session, e.player)
      end
      return
    end

    if not session.isInsideBounds(e.to) then
      gameManager.handleNonCombatDeath(session, e.player)
      return
    end

    local deathBlock = getDeathBlock(session)
    local blockBelowType = session.world.blockTypeAt(math.floor(e.to.x), math.floor(e.to.y - 1), math.floor(e.to.z))
    if blockBelowType == deathBlock then
      gameManager.handleNonCombatDeath(session, e.player)
    end
  end)

  ba.events.on("block_break", function(session, e)
    if not session.isPlaying(e.player) then return end

    if session.phase() ~= "PLAYING" then
      e:cancel()
      return
    end

    if not hasPlayRegion(session) then
      e:cancel()
      return
    end

    if not session.isInsideBounds(e.location) then
      e:cancel()
    end
  end)

  ba.events.on("block_place", function(session, e)
    if not session.isPlaying(e.player) then return end

    if session.phase() ~= "PLAYING" then
      e:cancel()
      return
    end

    if not hasPlayRegion(session) then
      e:cancel()
      return
    end
  end)

  ba.events.on("projectile_launch", function(session, e)
    if session.phase() ~= "PLAYING" then return end
    if not session.isPlaying(e.shooter) then return end

    if e.projectileType == "ARROW" or e.projectileType == "SPECTRAL_ARROW"
        or e.projectileType == "TIPPED_ARROW" or e.projectileType == "TRIDENT" then
      gameManager.handleProjectileShot(session, e.shooter)
    end
  end)

  ba.events.on("player_damage_by_entity", function(session, e)
    if e.target == nil then return end
    if not session.isPlaying(e.target) then return end

    if session.phase() ~= "PLAYING" then
      e:cancel()
      return
    end

    if e.damager == nil or not session.isPlaying(e.damager) then
      e:cancel()
      return
    end

    gameManager.handleHit(session, e.damager)

    local finalHealth = session.player.health(e.target) - e.finalDamage
    if finalHealth > 0 then return end

    e:cancel()
    gameManager.handleKill(session, e.damager, e.target)
  end)

  ba.events.on("player_damage", function(session, e)
    if not session.isPlaying(e.player) then return end

    if session.phase() ~= "PLAYING" then
      e:cancel()
      return
    end

    if e.cause == "FALL" then
      e:cancel()
      return
    end

    local finalHealth = session.player.health(e.player) - e.finalDamage
    if finalHealth > 0 then return end

    e:cancel()
    gameManager.handleNonCombatDeath(session, e.player)
  end)
end

return M

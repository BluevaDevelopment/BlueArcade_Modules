local gameManager = require("game_manager")

local M = {}

local ARROW_TYPES = { ARROW = true, SPECTRAL_ARROW = true, TIPPED_ARROW = true, TRIDENT = true }

function M.register()
  -- No COUNTDOWN-phase teleport-back branch here (unlike race/fast_zone) - it's real, provably
  -- dead code: `freezePlayersOnCountdown()` hardcodes `return false`, so the listener's own
  -- `phase == COUNTDOWN && freezePlayersOnCountdown()` guard can never be true. Falling through,
  -- an out-of-bounds move during COUNTDOWN takes the *same* `phase ~= PLAYING` branch below as any
  -- other non-playing phase - a real respawn (loadout, gamemode, sound), not a plain teleport like
  -- exploding_sheep/minefield/red_alert use for their own non-playing out-of-bounds correction.
  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then return end

    if session.phase() ~= "PLAYING" then
      if not session.isInsideBounds(e.to) then
        gameManager.handleRespawn(session, e.player)
      end
      return
    end

    if not session.isInsideBounds(e.to) then
      gameManager.handleRespawn(session, e.player)
      return
    end

    local deathBlock = gameManager.resolveDeathBlock(session)
    local blockBelowType = session.world.blockTypeAt(math.floor(e.to.x), math.floor(e.to.y - 1), math.floor(e.to.z))
    if blockBelowType == deathBlock then
      gameManager.handleRespawn(session, e.player)
    end
  end)

  ba.events.on("block_break", function(session, e)
    if session.isPlaying(e.player) then e:cancel() end
  end)

  ba.events.on("block_place", function(session, e)
    if session.isPlaying(e.player) then e:cancel() end
  end)

  ba.events.on("projectile_launch", function(session, e)
    if session.phase() ~= "PLAYING" then return end
    if not session.isPlaying(e.shooter) then return end
    if ARROW_TYPES[e.projectileType] then
      gameManager.handleProjectileShot(session, e.shooter)
    end
  end)

  -- The whole "one in the chamber" identity: any real arrow hit is *always* lethal, regardless of
  -- actual remaining health - matches `finalHealth = projectileHit ? -1 : realHealthCheck` exactly.
  -- Non-projectile (melee) damage still uses a genuine health check. Shooting yourself is a real,
  -- separate branch: an immediate elimination with no killer credited to anyone.
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

    if e.damager == e.target then
      e:cancel()
      gameManager.handlePlayerElimination(session, e.target, nil)
      return
    end

    gameManager.handleHit(session, e.damager)

    local isArrow = ARROW_TYPES[e.projectileType] == true
    local finalHealth = isArrow and -1 or (session.player.health(e.target) - e.finalDamage)
    if finalHealth > 0 then return end

    e:cancel()
    gameManager.handleKillCredit(session, e.damager)
    gameManager.handlePlayerElimination(session, e.target, e.damager)
  end)

  ba.events.on("player_damage", function(session, e)
    if not session.isPlaying(e.player) then return end

    if session.phase() ~= "PLAYING" then
      e:cancel()
      return
    end

    local finalHealth = session.player.health(e.player) - e.finalDamage
    if finalHealth > 0 then return end

    e:cancel()
    gameManager.handlePlayerElimination(session, e.player, nil)
  end)
end

return M

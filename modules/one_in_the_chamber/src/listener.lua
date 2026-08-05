--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local gameManager = require("game_manager")

local M = {}

local ARROW_TYPES = { ARROW = true, SPECTRAL_ARROW = true, TIPPED_ARROW = true, TRIDENT = true }

function M.register()
  -- freezePlayersOnCountdown() always returns false, so the COUNTDOWN teleport-back branch is dead
  -- code; out-of-bounds during COUNTDOWN falls through to the same real-respawn branch below.
  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then return end
    if gameManager.isWaitingRespawn(session, e.player) then return end

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

  -- Any arrow hit is unconditionally lethal (finalHealth = -1); melee uses a real health check.
  -- Self-damage is a separate branch: immediate elimination, no killer credited.
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

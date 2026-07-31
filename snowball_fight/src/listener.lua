local gameManager = require("game_manager")

local M = {}

function M.register()
  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then return end

    if not session.isInsideBounds(e.to) then
      gameManager.respawnOutOfBounds(session, e.player)
      return
    end

    if session.phase() ~= "PLAYING" then return end

    local blockBelow = session.world.blockTypeAt(math.floor(e.to.x), math.floor(e.to.y) - 1, math.floor(e.to.z))
    if blockBelow == gameManager.deathBlock(session) then
      gameManager.respawnOutOfBounds(session, e.player)
    end
  end)

  ba.events.on("block_break", function(session, e)
    if session.isPlaying(e.player) then e:cancel() end
  end)

  ba.events.on("projectile_launch", function(session, e)
    if e.projectileType ~= "SNOWBALL" then return end
    if not session.isPlaying(e.shooter) then return end
    gameManager.handleSnowballThrown(session, e.shooter)
  end)

  ba.events.on("projectile_hit", function(session, e)
    if e.projectileType ~= "SNOWBALL" then return end
    if e.hitPlayer == nil then return end
    if not session.isPlaying(e.hitPlayer) or e.hitPlayer == e.shooter then return end
    gameManager.handleSnowballHit(session, e.shooter)
  end)

  ba.events.on("player_damage_by_entity", function(session, e)
    if e.target == nil then return end

    if e.projectileType ~= "SNOWBALL" then
      if session.isPlaying(e.target) and session.isPlaying(e.damager) then e:cancel() end
      return
    end

    e:cancel()
    if not session.isPlaying(e.target) or not session.isPlaying(e.damager) or e.damager == e.target then return end

    gameManager.handleSnowballHit(session, e.damager)
    gameManager.handleKillCredit(session, e.damager)
    gameManager.handlePlayerElimination(session, e.target, e.damager)
  end)
end

return M

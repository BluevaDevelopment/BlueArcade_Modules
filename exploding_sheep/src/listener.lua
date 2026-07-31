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

    if not session.isInsideBounds(e.to) then
      gameManager.handlePlayerElimination(session, e.player)
      return
    end

    local boundsMin = session.arena.boundsMin()
    local boundsMax = session.arena.boundsMax()
    local minY = math.min(boundsMin.y, boundsMax.y)
    if e.to.y < minY - 1 then
      gameManager.handlePlayerElimination(session, e.player)
    end
  end)

  -- Any player-on-player (or player-shot-projectile) hit is unconditionally cancelled - this
  -- module's only real threat is a sheep's own explosion, matching the legacy `onDamage`'s own
  -- unconditional cancel (no `isPlaying` guard on the victim either).
  ba.events.on("player_damage_by_entity", function(session, e)
    if e.target == nil then return end
    if e.damager == nil then return end
    e:cancel()
  end)

  ba.events.on("player_damage", function(session, e)
    if e.cause ~= "FALL" then return end
    if session.isPlaying(e.player) then e:cancel() end
  end)

  ba.events.on("block_break", function(session, e)
    if not session.isPlaying(e.player) then return end
    if e.blockType ~= "AIR" then e:cancel() end
  end)

  ba.events.on("player_shear_entity", function(session, e)
    if session.phase() ~= "PLAYING" then return end
    if not session.isPlaying(e.player) then return end

    e:cancel()
    gameManager.handleSheepShear(session, e.player, e.entity)
  end)
end

return M

local gameManager = require("game_manager")

local PROJECTILE_TAG = "bluearcade_splegg_projectile"
local NON_BREAKABLE = { AIR = true, BARRIER = true, BEDROCK = true }

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

  -- Players never break blocks directly in Splegg - they shoot eggs.
  ba.events.on("block_break", function(session, e)
    if session.isPlaying(e.player) then e:cancel() end
  end)

  ba.events.on("player_interact", function(session, e)
    if e.action ~= "RIGHT_CLICK_AIR" and e.action ~= "RIGHT_CLICK_BLOCK"
        and e.action ~= "LEFT_CLICK_AIR" and e.action ~= "LEFT_CLICK_BLOCK" then
      return
    end
    if session.phase() ~= "PLAYING" then return end
    if not session.isPlaying(e.player) then return end
    if session.player.itemInMainHandType(e.player) ~= "DIAMOND_SHOVEL" then return end

    if not gameManager.canShoot(session, e.player) then
      e:cancel()
      return
    end

    e:cancel()
    gameManager.recordShoot(session, e.player)
    local egg = session.player.launchProjectile(e.player, "EGG")
    if egg ~= nil then
      session.entities.addTag(egg, PROJECTILE_TAG)
    end
  end)

  ba.events.on("projectile_hit", function(session, e)
    if e.projectileType ~= "EGG" then return end
    if session.phase() ~= "PLAYING" then return end
    if not session.isPlaying(e.shooter) then return end

    if e.hitBlock ~= nil then
      if not session.isInsideBounds(e.hitBlock) then return end

      if not NON_BREAKABLE[e.hitBlockType] then
        session.world.setBlockType(math.floor(e.hitBlock.x), math.floor(e.hitBlock.y), math.floor(e.hitBlock.z), "AIR")
        gameManager.handleBlockBreak(session, e.shooter)
      end
      return
    end

    if e.hitPlayer ~= nil then
      if not session.isPlaying(e.hitPlayer) then return end

      local lengthSquared = e.velocity.x * e.velocity.x + e.velocity.y * e.velocity.y + e.velocity.z * e.velocity.z
      if lengthSquared > 0 then
        local length = math.sqrt(lengthSquared)
        session.player.addVelocity(e.hitPlayer,
          e.velocity.x / length * 0.6,
          e.velocity.y / length * 0.6,
          e.velocity.z / length * 0.6)
      end
    end
  end)

  ba.events.on("player_drop_item", function(session, e)
    if session.isPlaying(e.player) then e:cancel() end
  end)

  ba.events.on("player_egg_throw", function(session, e)
    if not e.hasTag(PROJECTILE_TAG) then return end
    e.setHatching(false)
    e.setNumHatches(0)
  end)

  ba.events.on("player_damage", function(session, e)
    if e.cause ~= "FALL" then return end
    if not session.isPlaying(e.player) then return end
    if session.phase() ~= "PLAYING" then return end
    e:cancel()
  end)
end

return M

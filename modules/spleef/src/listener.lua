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

  ba.events.on("block_place", function(session, e)
    if session.isPlaying(e.player) then e:cancel() end
  end)

  ba.events.on("prepare_item_craft", function(session, e)
    if session.isPlaying(e.player) then e.clearResult() end
  end)

  ba.events.on("craft_item", function(session, e)
    if session.isPlaying(e.player) then e:cancel() end
  end)

  ba.events.on("player_drop_item", function(session, e)
    if session.isPlaying(e.player) then e:cancel() end
  end)

  ba.events.on("block_break", function(session, e)
    if not session.isPlaying(e.player) then return end

    if e.blockType == "SNOW_BLOCK" or e.blockType == "SNOW" then
      e:cancel()
      session.world.setBlockType(math.floor(e.location.x), math.floor(e.location.y), math.floor(e.location.z), "AIR")
      session.player.giveItem(e.player, "SNOWBALL", 1, -1)
      gameManager.handleSnowBreak(session, e.player)
      return
    end

    e:cancel()
  end)

  ba.events.on("projectile_hit", function(session, e)
    if e.projectileType ~= "SNOWBALL" then return end
    if session.phase() ~= "PLAYING" then return end
    if not session.isPlaying(e.shooter) then return end

    if e.hitBlock ~= nil then
      if e.hitBlockType == "SNOW_BLOCK" or e.hitBlockType == "SNOW" then
        session.world.setBlockType(math.floor(e.hitBlock.x), math.floor(e.hitBlock.y), math.floor(e.hitBlock.z), "AIR")
        gameManager.handleSnowBreak(session, e.shooter)
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

  ba.events.on("player_damage", function(session, e)
    if not session.isPlaying(e.player) then return end
    if session.phase() ~= "PLAYING" then return end
    if e.cause == "FALL" then
      e:cancel()
      return
    end
    if session.player.health(e.player) - e.finalDamage > 0 then return end
    e:cancel()
    gameManager.handlePlayerElimination(session, e.player)
  end)
end

return M

--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local gameManager = require("game_manager")

local M = {}

local function isWater(session, location)
  return session.world.blockTypeAt(math.floor(location.x), math.floor(location.y), math.floor(location.z)) == "WATER"
end

local function hasChangedBlock(from, to)
  return math.floor(from.x) ~= math.floor(to.x)
      or math.floor(from.y) ~= math.floor(to.y)
      or math.floor(from.z) ~= math.floor(to.z)
end

function M.register()
  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then return end

    if session.phase() ~= "PLAYING" then
      if not session.isInsideBounds(e.to) then
        session.player.setFallDistance(e.player, 0)
        session.respawnPlayer(e.player)
        gameManager.handlePlayerRespawn(session, e.player)
        return
      end

      if hasChangedBlock(e.from, e.to) then
        session.player.teleport(e.player, e.from)
      end
      return
    end

    if not session.isInsideBounds(e.to) then
      session.player.setFallDistance(e.player, 0)
      session.respawnPlayer(e.player)
      gameManager.handlePlayerRespawn(session, e.player)
      return
    end

    if not hasChangedBlock(e.from, e.to) then return end
    if e.to.y > e.from.y then return end
    if session.state.ended then return end

    local enteredWater = not isWater(session, e.from) and isWater(session, e.to)
    if not enteredWater then return end

    gameManager.handleWaterLanding(session, e.player, e.to)

    session.player.setFallDistance(e.player, 0)
    session.respawnPlayer(e.player)
  end)

  ba.events.on("player_damage", function(session, e)
    if e.cause ~= "FALL" then return end
    if not session.isPlaying(e.player) then return end

    e:cancel()
    session.player.setFallDistance(e.player, 0)

    if session.phase() ~= "PLAYING" then return end
    if session.state.ended then return end

    gameManager.handleMissedLanding(session, e.player)
  end)

  ba.events.on("player_interact", function(session, e)
    if session.isPlaying(e.player) then e:cancel() end
  end)

  ba.events.on("block_break", function(session, e)
    if session.isPlaying(e.player) then e:cancel() end
  end)
end

return M

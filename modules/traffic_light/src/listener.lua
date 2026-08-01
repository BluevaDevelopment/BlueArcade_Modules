--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local gameManager = require("game_manager")

local M = {}

local function isParticipant(session, handle)
  if session.isPlaying(handle) then return true end
  for _, spectator in ipairs(session.spectators()) do
    if spectator == handle then return true end
  end
  return false
end

function M.register()
  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then return end
    if session.state.redLockedHandles[e.player] then return end

    local sameBlock = math.floor(e.from.x) == math.floor(e.to.x)
        and math.floor(e.from.y) == math.floor(e.to.y)
        and math.floor(e.from.z) == math.floor(e.to.z)
    if sameBlock then return end

    if session.phase() == "COUNTDOWN" then
      e.setTo(e.from)
      return
    end

    if not session.isInsideBounds(e.to) then
      session.visualEffects.playDeathEffect(e.player)
      session.respawnPlayer(e.player)
      session.sounds.play(e.player, session.coreConfig.getSound("sounds.in_game.respawn"))
      gameManager.handlePlayerDeath(session, e.player, false)
      gameManager.handlePlayerRespawn(session, e.player)
      gameManager.cleanupPlayerState(session, e.player)
      return
    end

    local deathBlockName = session.dataAccess.getGameDataString("basic.death_block")
    local deathBlock = deathBlockName ~= nil and string.upper(deathBlockName) or "BARRIER"
    local blockBelowType = session.world.blockTypeAt(math.floor(e.to.x), math.floor(e.to.y - 1), math.floor(e.to.z))
    if blockBelowType == deathBlock then
      session.visualEffects.playDeathEffect(e.player)
      session.respawnPlayer(e.player)
      session.sounds.play(e.player, session.coreConfig.getSound("sounds.in_game.respawn"))
      gameManager.handlePlayerDeath(session, e.player, true)
      gameManager.handlePlayerRespawn(session, e.player)
      gameManager.cleanupPlayerState(session, e.player)
      return
    end

    if session.state.lightState == "RED" then
      gameManager.handleRedLightMovement(session, e.player, e.from, e.to)
      return
    end

    local isSpectator = false
    for _, spectator in ipairs(session.spectators()) do
      if spectator == e.player then isSpectator = true end
    end
    if isSpectator then return end

    if gameManager.isInsideFinishLine(session, e.to) then
      session.finishPlayer(e.player)
      gameManager.cleanupPlayerState(session, e.player)

      local position = 0
      for i, spectator in ipairs(session.spectators()) do
        if spectator == e.player then position = i end
      end

      gameManager.handlePlayerFinish(session, e.player)
      gameManager.broadcastFinish(session, e.player, position)

      local title = session.config.translation(e.player, "titles.finished.title")
      local subtitle = string.gsub(session.config.translation(e.player, "titles.finished.subtitle"), "{position}", tostring(position))
      session.titles.sendRaw(e.player, title, subtitle, 0, 80, 20)
      session.sounds.play(e.player, session.coreConfig.getSound("sounds.in_game.classified"))
    end
  end)

  ba.events.on("block_break", function(session, e)
    if isParticipant(session, e.player) then e:cancel() end
  end)

  ba.events.on("block_place", function(session, e)
    if isParticipant(session, e.player) then e:cancel() end
  end)

  ba.events.on("player_drop_item", function(session, e)
    if isParticipant(session, e.player) then e:cancel() end
  end)

  ba.events.on("player_damage_by_entity", function(session, e)
    if e.target == nil then return end
    if not session.isPlaying(e.target) then return end
    if not session.isPlaying(e.damager) then return end
    e:cancel()
  end)

  ba.events.on("player_damage", function(session, e)
    if e.cause ~= "FALL" then return end
    if session.isPlaying(e.player) then e:cancel() end
  end)
end

return M

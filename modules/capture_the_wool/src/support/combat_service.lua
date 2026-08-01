--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy CombatService.java. Unlike lucky_pillars/battle_royale's permanent elimination, capture_the_wool
-- respawns players after a temporary SPECTATOR gamemode lock, matching legacy - session.eliminate is never called here.
local loadoutService = require("support.loadout_service")

local M = {}

local function getRandomMessage(session, handle, path)
  local messages = session.config.translationList(handle, path)
  if #messages == 0 then
    return nil
  end
  return messages[math.random(#messages)]
end

local function broadcastDeathMessage(session, victimHandle, killerHandle)
  local path = killerHandle and "messages.deaths.killed_by_player" or "messages.deaths.generic"
  local message = getRandomMessage(session, nil, path)
  if not message then
    return
  end

  message = message:gsub("{victim}", session.player.name(victimHandle))
  message = message:gsub("{killer}", killerHandle and session.player.name(killerHandle) or "")

  for _, handle in ipairs(session.players()) do
    session.messages.sendRaw(handle, message)
  end
end

local function sendDeathTitle(session, targetHandle, killed)
  if killed then
    session.sounds.play(targetHandle, "sounds.in_game.dead")
    session.titles.sendRaw(targetHandle,
      session.config.translation(targetHandle, "titles.you_died.title"),
      session.config.translation(targetHandle, "titles.you_died.subtitle"),
      0, 80, 20)
    return
  end

  session.sounds.play(targetHandle, "sounds.in_game.classified")
  session.titles.sendRaw(targetHandle,
    session.config.translation(targetHandle, "titles.classified.title"),
    session.config.translation(targetHandle, "titles.classified.subtitle"),
    0, 80, 20)
end

function M.healKiller(session, killerHandle)
  loadoutService.handleKillRegeneration(session, killerHandle)
  session.sounds.play(killerHandle, "sounds.in_game.respawn")
end

function M.handleKillCredit(session, gameManager, killerHandle)
  session.stats.add(killerHandle, "kills", 1)
  gameManager.addPlayerKill(session, killerHandle)
  M.healKiller(session, killerHandle)
end

local function scheduleRespawn(session, gameManager, targetHandle)
  local delay = math.max(1, session.config.getInt("game.respawn_delay_seconds", 3))
  session.player.setGameMode(targetHandle, "SPECTATOR")
  local taskId = "arena_" .. session.arenaId .. "_respawn_" .. targetHandle
  session.scheduler.runLater(taskId, function()
    if session.isPlaying(targetHandle) then
      gameManager.respawnPlayer(session, targetHandle)
    end
  end, delay * 20)
end

function M.handleElimination(session, gameManager, targetHandle, killerHandle)
  for _, handle in ipairs(session.spectators()) do
    if handle == targetHandle then
      return
    end
  end
  if session.player.getGameMode(targetHandle) == "SPECTATOR" then
    return
  end

  local deathLocation = session.player.location(targetHandle)
  session.visualEffects.playDeathEffect(targetHandle, deathLocation)
  if killerHandle then
    session.visualEffects.playKillEffect(killerHandle)
  end

  broadcastDeathMessage(session, targetHandle, killerHandle)
  gameManager.addPlayerDeath(session, targetHandle)
  session.stats.add(targetHandle, "deaths", 1)
  gameManager.handleWoolDrop(session, targetHandle)

  session.player.clearInventory(targetHandle)
  sendDeathTitle(session, targetHandle, killerHandle ~= nil)
  scheduleRespawn(session, gameManager, targetHandle)
end

return M

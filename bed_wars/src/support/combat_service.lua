--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy CombatService.java. Resource drops (iron/gold/diamond/emerald) combine same-
-- material stacks into one dropped stack instead of legacy's one-drop-per-ItemStack - same total
-- resources either way. `healKiller` lives on game_manager.lua, not here - legacy's own
-- `CombatService.healKiller` is an unused duplicate; `handleKillCredit` calls `BedWarsGame.healKiller`.

local RESOURCE_MATERIALS = { "IRON_INGOT", "GOLD_INGOT", "DIAMOND", "EMERALD" }

local M = {}

local function getRandomMessage(session, handle, path)
  local messages = session.config.translationList(handle, path)
  if #messages == 0 then
    return nil
  end
  return messages[math.random(#messages)]
end

local function isSpectator(session, handle)
  for _, spectator in ipairs(session.spectators()) do
    if spectator == handle then return true end
  end
  return false
end

local function broadcastMessage(session, victimHandle, killerHandle, killedPath, genericPath)
  if isSpectator(session, victimHandle) then return end

  local path = killerHandle and killedPath or genericPath
  local message = getRandomMessage(session, victimHandle, path)
  if not message and killedPath == "messages.deaths.final_kill" then
    return broadcastMessage(session, victimHandle, killerHandle, "messages.deaths.killed_by_player", "messages.deaths.generic")
  end
  if not message then return end

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

function M.handleKillCredit(session, gameManager, killerHandle)
  session.stats.add(killerHandle, "kills", 1)
  gameManager.addPlayerKill(session, killerHandle)
  gameManager.healKiller(session, killerHandle)
end

local function dropResourcesAtLocation(session, handle, location)
  for _, material in ipairs(RESOURCE_MATERIALS) do
    local count = session.player.countItem(handle, material)
    if count > 0 then
      session.world.dropItemAt(location, material, count)
    end
  end
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
  if isSpectator(session, targetHandle) then return end
  if session.player.getGameMode(targetHandle) == "SPECTATOR" then return end

  local deathLocation = session.player.location(targetHandle)
  session.visualEffects.playDeathEffect(targetHandle, deathLocation)
  if killerHandle then
    session.visualEffects.playKillEffect(killerHandle)
  end

  local canRespawn = gameManager.canPlayerRespawn(session, targetHandle)

  if canRespawn then
    broadcastMessage(session, targetHandle, killerHandle, "messages.deaths.killed_by_player", "messages.deaths.generic")
  else
    broadcastMessage(session, targetHandle, killerHandle, "messages.deaths.final_kill", "messages.deaths.final_kill_generic")
    if killerHandle then
      session.stats.add(killerHandle, "final_kills", 1)
    end
  end

  gameManager.addPlayerDeath(session, targetHandle)
  session.stats.add(targetHandle, "deaths", 1)

  dropResourcesAtLocation(session, targetHandle, deathLocation)
  session.player.clearInventory(targetHandle)
  sendDeathTitle(session, targetHandle, killerHandle ~= nil)

  if canRespawn then
    scheduleRespawn(session, gameManager, targetHandle)
  else
    session.eliminate(targetHandle, session.config.translation(targetHandle, "messages.eliminated"))
    gameManager.checkForVictory(session)
  end
end

return M

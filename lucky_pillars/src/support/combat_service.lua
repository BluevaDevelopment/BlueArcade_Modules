--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- loadoutService is always nil (no kits), so healKiller only plays the respawn sound - CombatService.java's own dead healKiller overload (never called) isn't ported.
local M = {}

local function getRandomMessage(session, handle, path)
  local messages = session.config.translationList(handle, path)
  if #messages == 0 then
    return nil
  end
  return messages[math.random(#messages)]
end

local function broadcastDeathMessage(session, victimHandle, killerHandle)
  -- legacy's own spectator guard here is unreachable in practice - handleElimination already returns before this if the target is spectating.
  local path = killerHandle and "messages.deaths.killed_by_player" or "messages.deaths.generic"
  local message = getRandomMessage(session, victimHandle, path)
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
  session.sounds.play(killerHandle, "sounds.in_game.respawn")
end

function M.handleKillCredit(session, killerHandle)
  session.stats.add(killerHandle, "kills", 1)
  session.state.kills[killerHandle] = (session.state.kills[killerHandle] or 0) + 1
  M.healKiller(session, killerHandle)
end

function M.handleElimination(session, targetHandle, killerHandle)
  local isSpectator = false
  for _, handle in ipairs(session.spectators()) do
    if handle == targetHandle then
      isSpectator = true
      break
    end
  end
  if isSpectator then
    return
  end

  local deathLocation = session.player.location(targetHandle)
  session.visualEffects.playDeathEffect(targetHandle, deathLocation)
  if killerHandle then
    session.visualEffects.playKillEffect(killerHandle)
  end

  broadcastDeathMessage(session, targetHandle, killerHandle)
  session.player.dropInventory(targetHandle)
  session.eliminate(targetHandle, session.config.translation(targetHandle, "messages.eliminated"))
  session.setSpectating(targetHandle, true)
  sendDeathTitle(session, targetHandle, killerHandle ~= nil)
end

return M

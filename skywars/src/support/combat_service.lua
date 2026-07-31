-- Mirrors legacy CombatService.java. Permanent elimination via session.eliminate/setSpectating -
-- unlike capture_the_wool's respawn model, skywars has no respawn mechanism at all, same pattern
-- as battle_royale/lucky_pillars.
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
  loadoutService.handleKillRegeneration(session, killerHandle)
  session.sounds.play(killerHandle, "sounds.in_game.respawn")
end

function M.handleKillCredit(session, gameManager, killerHandle)
  session.stats.add(killerHandle, "kills", 1)
  gameManager.addPlayerKill(session, killerHandle)
  M.healKiller(session, killerHandle)
end

function M.handleElimination(session, targetHandle, killerHandle)
  for _, handle in ipairs(session.spectators()) do
    if handle == targetHandle then
      return
    end
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

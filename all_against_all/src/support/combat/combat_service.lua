local loadoutService = require("support.loadout.loadout_service")

local M = {}

local function getWinMode(session)
  local mode = session.dataAccess.getGameDataString("basic.win_mode")
  if mode == nil then return "last_standing" end
  mode = string.lower(mode)
  if mode ~= "last_standing" and mode ~= "most_kills" then return "last_standing" end
  return mode
end

function M.handleProjectileShot(session, shooter)
  session.stats.add(shooter, "arrows_shot", 1)
end

function M.handleHit(session, attacker)
  session.stats.add(attacker, "hits_landed", 1)
end

function M.handleKillCredit(session, killer)
  if killer == nil then return end

  session.stats.add(killer, "kills", 1)
  session.state.kills[killer] = (session.state.kills[killer] or 0) + 1

  loadoutService.handleKillRegeneration(session, killer)
  session.sounds.play(killer, session.coreConfig.getSound("sounds.in_game.respawn"))
end

local function isSpectator(session, handle)
  for _, spectator in ipairs(session.spectators()) do
    if spectator == handle then return true end
  end
  return false
end

local function randomMessage(session, path)
  local messages = session.config.translationList(nil, path)
  if #messages == 0 then return nil end
  return messages[math.random(#messages)]
end

local function broadcastDeathMessage(session, victim, killer)
  if isSpectator(session, victim) then return end

  local path = killer ~= nil and "messages.deaths.killed_by_player" or "messages.deaths.generic"
  local message = randomMessage(session, path)
  if message == nil then return end

  message = string.gsub(message, "{victim}", session.player.name(victim))
  message = string.gsub(message, "{killer}", killer ~= nil and session.player.name(killer) or "")

  for _, handle in ipairs(session.players()) do
    session.messages.sendRaw(handle, message)
  end
end

local function playVisualEffects(session, target, killer, deathLocation)
  session.visualEffects.playDeathEffect(target, deathLocation)
  if killer ~= nil then
    session.visualEffects.playKillEffect(killer)
  end
end

local function sendDeathTitle(session, target, killed)
  if killed then
    session.sounds.play(target, session.coreConfig.getSound("sounds.in_game.dead"))
    session.titles.sendRaw(target,
      session.config.translation(target, "titles.you_died.title"),
      session.config.translation(target, "titles.you_died.subtitle"),
      0, 80, 20)
    return
  end

  session.sounds.play(target, session.coreConfig.getSound("sounds.in_game.classified"))
  session.titles.sendRaw(target,
    session.config.translation(target, "titles.classified.title"),
    session.config.translation(target, "titles.classified.subtitle"),
    0, 80, 20)
end

local function handleRespawnFlow(session, target, killer)
  session.player.setGameMode(target, "SPECTATOR")
  session.player.clearInventory(target)
  session.titles.sendRaw(target,
    session.config.translation(target, "titles.you_died.title"),
    session.config.translation(target, "titles.you_died.subtitle"),
    0, 80, 20)
  broadcastDeathMessage(session, target, killer)

  local respawnDelayTicks = math.max(0, session.config.getInt("respawn.most_kills_delay_ticks", 60))
  session.scheduler.runLater("all_against_all_respawn_" .. session.arenaId .. "_" .. target, function()
    if session.state.ended or not session.isPlaying(target) then return end

    session.respawnPlayer(target)
    session.player.setGameMode(target, "SURVIVAL")
    loadoutService.restoreVitals(session, target)
    loadoutService.giveStartingItems(session, target)
    loadoutService.applyStartingEffects(session, target)
    loadoutService.applyRespawnEffects(session, target)
    session.sounds.play(target, session.coreConfig.getSound("sounds.in_game.respawn"))
  end, respawnDelayTicks)
end

function M.handleElimination(session, target, killer)
  if isSpectator(session, target) then return end

  local deathLocation = session.player.location(target)
  playVisualEffects(session, target, killer, deathLocation)

  local winMode = getWinMode(session)
  if winMode == "most_kills" then
    handleRespawnFlow(session, target, killer)
    return
  end

  broadcastDeathMessage(session, target, killer)
  if session.config.getBoolean("combat.drop_items_on_death", true) then
    session.player.dropInventory(target)
  else
    session.player.clearInventory(target)
  end
  session.eliminate(target, session.config.translation(target, "messages.eliminated"))
  session.setSpectating(target, true)
  sendDeathTitle(session, target, killer ~= nil)
end

return M

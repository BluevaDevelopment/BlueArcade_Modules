local descriptionService = require("support.description_service")
local loadoutService = require("support.loadout.loadout_service")
local supplyService = require("support.supply_service")
local placeholderService = require("support.placeholder_service")
local combatService = require("support.combat.combat_service")
local outcomeService = require("support.outcome.outcome_service")

local DEFAULT_GAME_TIME = 180

local M = {}

local function getWinMode(session)
  local mode = session.dataAccess.getGameDataString("basic.win_mode")
  if mode == nil then return "last_standing" end
  mode = string.lower(mode)
  if mode ~= "last_standing" and mode ~= "most_kills" then return "last_standing" end
  return mode
end

function M.getScoreboardPath(session)
  return "scoreboard." .. getWinMode(session)
end

function M.getModeLabel(session, handle, mode)
  if mode == "most_kills" then
    return session.config.translation(handle, "scoreboard.mode_labels.most_kills")
  end
  return session.config.translation(handle, "scoreboard.mode_labels.last_standing")
end

function M.startGame(session)
  session.scheduler.cancelArenaTasks()

  session.state = {
    ended = false,
    kills = {},
    supplyTicks = 0,
    previousDifficulty = nil,
    winnerId = nil,
  }

  descriptionService.sendDescription(session)
end

function M.handleCountdownTick(session, secondsLeft)
  for _, handle in ipairs(session.players()) do
    session.sounds.play(handle, session.coreConfig.getSound("sounds.starting_game.countdown"))
    local title = string.gsub(session.coreConfig.language(handle, "titles.starting_game.title"), "{game_display_name}", "All Against All")
    title = string.gsub(title, "{time}", tostring(secondsLeft))
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.starting_game.subtitle"), "{game_display_name}", "All Against All")
    subtitle = string.gsub(subtitle, "{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.handleCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    local title = string.gsub(session.coreConfig.language(handle, "titles.game_started.title"), "{game_display_name}", "All Against All")
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.game_started.subtitle"), "{game_display_name}", "All Against All")
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 20)
    session.sounds.play(handle, session.coreConfig.getSound("sounds.starting_game.start"))
  end
end

local function updateWorldDifficulty(session)
  local current = session.world.getDifficulty()
  if current == "PEACEFUL" then
    session.state.previousDifficulty = current
    session.world.setDifficulty("NORMAL")
  end
end

local function restoreWorldDifficulty(session)
  if session.state.previousDifficulty ~= nil then
    session.world.setDifficulty(session.state.previousDifficulty)
    session.state.previousDifficulty = nil
  end
end

local function formatCountdownTime(seconds)
  if seconds < 0 then seconds = 0 end
  return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function startGameTimer(session)
  local gameTime = session.dataAccess.getGameDataNumber("basic.time")
  if gameTime == nil or gameTime == 0 then gameTime = DEFAULT_GAME_TIME end
  session.state.timeLeft = math.floor(gameTime)

  local taskId = "arena_" .. session.arenaId .. "_all_against_all_timer"
  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end

    session.state.timeLeft = session.state.timeLeft - 1

    local alivePlayers = session.alivePlayers()
    if #alivePlayers <= 1 or session.state.timeLeft <= 0 then
      outcomeService.endGame(session)
      return
    end

    supplyService.giveTimedSupplies(session)

    for _, handle in ipairs(session.players()) do
      local template = session.coreConfig.language(handle, "action_bar.in_game.global")
      local placeholders = placeholderService.buildPlaceholders(session, handle)
      placeholders.time = formatCountdownTime(session.state.timeLeft)
      placeholders.alive = tostring(#alivePlayers)
      placeholders.spectators = tostring(#session.spectators())

      if template ~= nil then
        local message = string.gsub(template, "{time}", formatCountdownTime(session.state.timeLeft))
        message = string.gsub(message, "{round}", tostring(session.currentRound))
        message = string.gsub(message, "{round_max}", tostring(session.maxRounds))
        session.messages.sendActionBar(handle, message)
      end

      session.scoreboard.update(handle, M.getScoreboardPath(session), placeholders)
    end
  end, 0, 20)
end

function M.beginPlaying(session)
  updateWorldDifficulty(session)
  startGameTimer(session)

  for _, handle in ipairs(session.players()) do
    session.player.setGameMode(handle, "SURVIVAL")
    loadoutService.restoreVitals(session, handle)
    loadoutService.giveStartingItems(session, handle)
    loadoutService.applyStartingEffects(session, handle)
    loadoutService.applyRespawnEffects(session, handle)
    session.scoreboard.show(handle, M.getScoreboardPath(session))
  end
end

function M.finishGame(session)
  session.scheduler.cancelArenaTasks()
  restoreWorldDifficulty(session)

  for _, handle in ipairs(session.players()) do
    session.stats.add(handle, "games_played", 1)
  end
end

-- Mirrors legacy shutdown(): cancel tasks, restore world difficulty - no stats, no winner.
function M.handleDisable(session)
  session.scheduler.cancelArenaTasks()
  restoreWorldDifficulty(session)
end

function M.getPlaceholders(session, handle)
  return placeholderService.buildPlaceholders(session, handle)
end

function M.handleProjectileShot(session, shooter)
  combatService.handleProjectileShot(session, shooter)
end

function M.handleHit(session, attacker)
  combatService.handleHit(session, attacker)
end

function M.handleKill(session, attacker, victim)
  combatService.handleKillCredit(session, attacker)
  combatService.handleElimination(session, victim, attacker)
end

function M.handleNonCombatDeath(session, victim)
  combatService.handleElimination(session, victim, nil)
end

function M.handleRespawn(session, handle)
  session.respawnPlayer(handle)
  loadoutService.applyRespawnEffects(session, handle)
  session.sounds.play(handle, session.coreConfig.getSound("sounds.in_game.respawn"))
end

return M

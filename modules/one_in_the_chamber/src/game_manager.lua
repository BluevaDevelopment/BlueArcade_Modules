--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local messagingService = require("support.messaging_service")
local loadoutService = require("support.loadout_service")
local statsService = require("support.stats_service")
local supplyService = require("support.supply_service")
local outcomeService = require("support.outcome_service")

local DEFAULT_GAME_TIME = 180

local M = {}

local function isSpectator(session, handle)
  for _, spectator in ipairs(session.spectators()) do
    if spectator == handle then return true end
  end
  return false
end

-- Whether a most_kills player is mid-respawn-wait in native spectator mode.
local function isWaitingRespawn(session, handle)
  return session.state.waitingRespawn ~= nil and session.state.waitingRespawn[handle] == true
end
M.isWaitingRespawn = isWaitingRespawn

function M.handleStart(session)
  session.scheduler.cancelArenaTasks()

  session.state = {
    ended = false,
    winnerId = nil,
    kills = {},
    supplyTicks = 0,
    waitingRespawn = {},
  }

  messagingService.sendDescription(session, outcomeService.getWinMode(session))
end

function M.handleCountdownTick(session, secondsLeft)
  messagingService.sendCountdownTick(session, secondsLeft)
end

function M.handleCountdownFinish(session)
  messagingService.sendCountdownFinish(session)
end

local function formatCountdownTime(seconds)
  if seconds < 0 then seconds = 0 end
  return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function handleMostKillsOutcome(session)
  local topPlayers = outcomeService.getTopPlayersByKills(session, session.players(), 5)
  if #topPlayers == 0 then return end

  session.setWinner(topPlayers[1])
  outcomeService.awardWin(session, topPlayers[1])

  for i = 2, #topPlayers do
    local handle = topPlayers[i]
    if session.isPlaying(handle) then
      session.finishPlayer(handle)
    end
  end
end

local function handleLastStandingTimeout(session, alivePlayers)
  local sorted = outcomeService.getTopPlayersByKills(session, alivePlayers, #alivePlayers)
  if #sorted == 0 then return end

  session.setWinner(sorted[1])
  outcomeService.awardWin(session, sorted[1])

  for i = 2, #sorted do
    local handle = sorted[i]
    if session.isPlaying(handle) then
      session.finishPlayer(handle)
    end
  end
end

local function endGameOnce(session)
  if session.state.ended then return end
  session.state.ended = true

  session.scheduler.cancelArenaTasks()

  local alivePlayers = session.alivePlayers()
  local winMode = outcomeService.getWinMode(session)

  if #alivePlayers == 1 and winMode == "last_standing" then
    local winner = alivePlayers[1]
    session.setWinner(winner)
    outcomeService.awardWin(session, winner)
  elseif #alivePlayers > 1 and winMode == "last_standing" then
    handleLastStandingTimeout(session, alivePlayers)
  end

  if winMode == "most_kills" then
    handleMostKillsOutcome(session)
  end

  session.endGame()
end

local function startGameTimer(session)
  local gameTime = session.dataAccess.getGameDataNumber("basic.time")
  if gameTime == nil or gameTime == 0 then gameTime = DEFAULT_GAME_TIME end
  local timeLeft = math.floor(gameTime)

  local taskId = "arena_" .. session.arenaId .. "_one_in_the_chamber_timer"
  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end

    timeLeft = timeLeft - 1

    local alivePlayers = session.alivePlayers()
    local winMode = outcomeService.getWinMode(session)
    local lastStandingFinished = winMode == "last_standing" and #alivePlayers <= 1

    if lastStandingFinished or timeLeft <= 0 then
      endGameOnce(session)
      return
    end

    supplyService.tickSupplies(session)

    for _, handle in ipairs(session.players()) do
      local template = session.coreConfig.language(handle, "action_bar.in_game.global")
      local placeholders = M.getCustomPlaceholders(session, handle)
      placeholders.time = formatCountdownTime(timeLeft)
      placeholders.alive = tostring(#alivePlayers)
      placeholders.spectators = tostring(#session.spectators())

      if template ~= nil then
        local message = string.gsub(template, "{time}", formatCountdownTime(timeLeft))
        message = string.gsub(message, "{round}", tostring(session.currentRound))
        message = string.gsub(message, "{round_max}", tostring(session.maxRounds))
        session.messages.sendActionBar(handle, message)
      end

      session.scoreboard.update(handle, outcomeService.getScoreboardPath(session), placeholders)
    end
  end, 0, 20)
end

function M.handleGameStart(session)
  startGameTimer(session)

  for _, handle in ipairs(session.players()) do
    loadoutService.prepareForStart(session, handle)
    session.scoreboard.show(handle, outcomeService.getScoreboardPath(session))
  end
end

function M.handleEnd(session)
  session.scheduler.cancelArenaTasks()
  statsService.recordGamesPlayed(session)
end

-- Mirrors legacy onDisable(): cancel tasks only, no winner, no stats.
function M.handleDisable(session)
  session.scheduler.cancelArenaTasks()
end

function M.handleProjectileShot(session, handle)
  statsService.recordShot(session, handle)
end

function M.handleHit(session, handle)
  statsService.recordHit(session, handle)
end

function M.handleKillCredit(session, killer)
  if killer == nil then return end

  statsService.recordKill(session, killer)
  session.state.kills[killer] = (session.state.kills[killer] or 0) + 1
  loadoutService.rewardKillArrow(session, killer)
end

function M.handlePlayerElimination(session, target, killer)
  if isSpectator(session, target) or isWaitingRespawn(session, target) then return end

  local deathLocation = session.player.location(target)
  session.visualEffects.playDeathEffect(target, deathLocation)
  if killer ~= nil then
    session.visualEffects.playKillEffect(killer)
  end

  messagingService.broadcastDeathMessage(session, target, killer)

  local winMode = outcomeService.getWinMode(session)
  if winMode == "most_kills" then
    session.state.waitingRespawn[target] = true
    session.player.setGameMode(target, "SPECTATOR")
    if killer ~= nil then
      session.titles.sendRaw(target,
        session.config.translation(target, "titles.you_died.title"),
        session.config.translation(target, "titles.you_died.subtitle"),
        0, 80, 20)
    end

    local respawnDelayTicks = math.max(0, session.config.getInt("respawn.most_kills_delay_ticks", 60))
    session.scheduler.runLater("arena_" .. session.arenaId .. "_one_in_the_chamber_respawn_" .. target, function()
      if session.state.ended then return end
      if not isWaitingRespawn(session, target) then return end

      session.state.waitingRespawn[target] = nil
      session.respawnPlayer(target)
      session.player.setGameMode(target, "SURVIVAL")
      loadoutService.applyRespawnLoadout(session, target)
      session.sounds.play(target, session.coreConfig.getSound("sounds.in_game.respawn"))
    end, respawnDelayTicks)
    return
  end

  session.eliminate(target, session.config.translation(target, "messages.eliminated"))
  messagingService.sendDeathTitle(session, target, killer ~= nil)
end

function M.handleRespawn(session, handle)
  session.respawnPlayer(handle)
  session.player.setGameMode(handle, "SURVIVAL")
  loadoutService.applyRespawnLoadout(session, handle)
  session.sounds.play(handle, session.coreConfig.getSound("sounds.in_game.respawn"))
end

function M.resolveDeathBlock(session)
  local deathBlockName = session.dataAccess.getGameDataString("basic.death_block")
  if deathBlockName ~= nil then
    return string.upper(deathBlockName)
  end
  return "BARRIER"
end

function M.getCustomPlaceholders(session, handle)
  local winMode = outcomeService.getWinMode(session)
  local placeholders = {
    alive = tostring(#session.alivePlayers()),
    spectators = tostring(#session.spectators()),
    kills = tostring(session.state.kills[handle] or 0),
    mode = outcomeService.getModeLabel(session, handle, winMode),
  }

  if winMode == "most_kills" then
    local topPlayers = outcomeService.getTopPlayersByKills(session, session.players(), 5)
    for i = 1, 5 do
      local topHandle = topPlayers[i]
      if topHandle ~= nil then
        placeholders["place_" .. i] = session.player.name(topHandle)
        placeholders["kills_" .. i] = tostring(session.state.kills[topHandle] or 0)
      else
        placeholders["place_" .. i] = "-"
        placeholders["kills_" .. i] = "0"
      end
    end
  end

  return placeholders
end

return M

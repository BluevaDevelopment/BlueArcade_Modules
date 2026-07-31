local messageService = require("support.message_service")
local loadoutService = require("support.loadout_service")
local scoreboardService = require("support.scoreboard_service")
local sheepService = require("support.sheep.sheep_service")

local DEFAULT_GAME_TIME = 180

local M = {}

function M.handleStart(session)
  session.scheduler.cancelArenaTasks()

  session.state = {
    ended = false,
    winnerId = nil,
    timeLeft = 0,
    sheep = {},
    eliminationNotified = {},
    sheared = {},
  }

  messageService.sendDescription(session)
end

function M.handleCountdownTick(session, secondsLeft)
  for _, handle in ipairs(session.players()) do
    session.sounds.play(handle, session.coreConfig.getSound("sounds.starting_game.countdown"))
    local title = string.gsub(session.coreConfig.language(handle, "titles.starting_game.title"), "{game_display_name}", "Exploding Sheep")
    title = string.gsub(title, "{time}", tostring(secondsLeft))
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.starting_game.subtitle"), "{game_display_name}", "Exploding Sheep")
    subtitle = string.gsub(subtitle, "{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.handleCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    local title = string.gsub(session.coreConfig.language(handle, "titles.game_started.title"), "{game_display_name}", "Exploding Sheep")
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.game_started.subtitle"), "{game_display_name}", "Exploding Sheep")
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 20)
    session.sounds.play(handle, session.coreConfig.getSound("sounds.starting_game.start"))
  end
end

local function formatCountdownTime(seconds)
  if seconds < 0 then seconds = 0 end
  return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function endGameOnce(session)
  if session.state.ended then return end
  session.state.ended = true

  session.scheduler.cancelArenaTasks()
  sheepService.cleanupSheep(session)

  local leaderboard = scoreboardService.getTopPlayersByShears(session)
  if #leaderboard > 0 then
    local winner = leaderboard[1]
    session.setWinner(winner)
    if session.state.winnerId == nil then
      session.state.winnerId = winner
      session.stats.add(winner, "wins", 1)
    end

    for i = 2, math.min(3, #leaderboard) do
      local podiumHandle = leaderboard[i]
      local isSpectating = false
      for _, spectator in ipairs(session.spectators()) do
        if spectator == podiumHandle then isSpectating = true end
      end
      if not isSpectating then
        session.finishPlayer(podiumHandle)
      end
    end
  end

  session.endGame()
end

local function startGameTimer(session)
  local gameTime = session.dataAccess.getGameDataNumber("basic.time")
  if gameTime == nil or gameTime == 0 then gameTime = DEFAULT_GAME_TIME end
  session.state.timeLeft = math.floor(gameTime)

  local taskId = "arena_" .. session.arenaId .. "_exploding_sheep_timer"
  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end

    session.state.timeLeft = session.state.timeLeft - 1

    local alivePlayers = session.alivePlayers()
    if #alivePlayers <= 1 or session.state.timeLeft <= 0 then
      endGameOnce(session)
      return
    end

    for _, handle in ipairs(session.players()) do
      local template = session.coreConfig.language(handle, "action_bar.in_game.global")
      if template ~= nil then
        local message = string.gsub(template, "{time}", formatCountdownTime(session.state.timeLeft))
        message = string.gsub(message, "{round}", tostring(session.currentRound))
        message = string.gsub(message, "{round_max}", tostring(session.maxRounds))
        session.messages.sendActionBar(handle, message)
      end

      session.scoreboard.updateModule(handle, scoreboardService.getScoreboardPlaceholders(session, handle))
    end
  end, 0, 20)
end

function M.handleGameStart(session)
  startGameTimer(session)
  sheepService.startSheepSpawner(session)
  sheepService.startSheepLifecycleTask(session)

  for _, handle in ipairs(session.players()) do
    session.state.sheared[handle] = 0
    session.player.setGameMode(handle, "SURVIVAL")
    loadoutService.giveStartingItems(session, handle)
    loadoutService.applyStartingEffects(session, handle)
    session.scoreboard.showModule(handle)
    session.scoreboard.updateModule(handle, scoreboardService.getScoreboardPlaceholders(session, handle))
  end
end

function M.handleEnd(session)
  session.scheduler.cancelArenaTasks()
  sheepService.cleanupSheep(session)

  for _, handle in ipairs(session.players()) do
    session.stats.add(handle, "games_played", 1)
  end
end

function M.handlePlayerElimination(session, handle)
  local isSpectating = false
  for _, spectator in ipairs(session.spectators()) do
    if spectator == handle then isSpectating = true end
  end
  if isSpectating then return end

  if session.state.eliminationNotified[handle] then return end
  session.state.eliminationNotified[handle] = true

  messageService.broadcastDeathMessage(session, handle)
  session.eliminate(handle, session.config.translation(handle, "messages.eliminated"))
  session.player.clearInventory(handle)
  session.setSpectating(handle, true)
  session.sounds.play(handle, session.coreConfig.getSound("sounds.in_game.respawn"))
end

function M.handleSheepShear(session, playerHandle, sheepHandle)
  if session.phase() ~= "PLAYING" then return end
  if session.state.sheep[sheepHandle] == nil then return end

  session.state.sheep[sheepHandle] = nil
  session.entities.remove(sheepHandle)

  session.state.sheared[playerHandle] = (session.state.sheared[playerHandle] or 0) + 1
  session.stats.add(playerHandle, "sheep_sheared", 1)

  local shearSound = session.config.getString("sounds.shear") or "ENTITY_SHEEP_SHEAR"
  session.sounds.play(playerHandle, shearSound)

  for _, handle in ipairs(session.players()) do
    session.scoreboard.updateModule(handle, scoreboardService.getScoreboardPlaceholders(session, handle))
  end
end

function M.isTrackedSheep(session, sheepHandle)
  return session.state.sheep[sheepHandle] ~= nil
end

function M.getCustomPlaceholders(session, handle)
  return scoreboardService.getCustomPlaceholders(session, handle)
end

return M

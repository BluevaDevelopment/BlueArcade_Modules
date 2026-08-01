-- Mirrors legacy BuildBattleGame.java. ArenaState.java is a plain session.state table here, same convention as every other converted module.
local voteService = require("support.vote_service")
local plotService = require("support.plot_service")
local plotVotingService = require("support.plot_voting_service")
local outcomeService = require("support.outcome_service")
local optionsService = require("support.options_service")

local M = {}

local function newState()
  return {
    ended = false,
    phase = "THEME_VOTING",
    selectedTheme = "random",
    voteState = nil,

    plots = {},
    plotSpawns = {},
    playerPlotSpawn = {},
    playerPlot = {},

    points = {},
    plotVotes = {},
    votedCurrentPlot = {},
    currentPlotIndex = 0,

    buildTimeLeft = 0,

    plotTimeOverride = {},
    plotWeatherOverride = {},
    floorChangeMode = {},
    plotParticles = {},
    bannerBuilder = {},
  }
end

local function formatTime(totalSeconds)
  local minutes = math.floor(totalSeconds / 60)
  local seconds = totalSeconds % 60
  return string.format("%02d:%02d", minutes, seconds)
end

function M.startGame(session)
  session.state = newState()
  session.scheduler.cancelArenaTasks()

  session.state.voteState = voteService.createVoteState()
  voteService.applyPendingVotes(session)

  plotService.loadPlots(session)
  plotService.assignPlayersToPlots(session)
  plotService.regeneratePlotFloors(session)

  M.startParticleTask(session)

  for _, handle in ipairs(session.players()) do
    plotService.teleportToPlot(session, handle)
  end
end

function M.handleCountdownTick(session, secondsLeft)
  for _, handle in ipairs(session.players()) do
    session.sounds.play(handle, "sounds.starting_game.countdown")
    local title = (session.coreConfig.language(handle, "titles.starting_game.title") or "")
      :gsub("{game_display_name}", "Build Battle"):gsub("{time}", tostring(secondsLeft))
    local subtitle = (session.coreConfig.language(handle, "titles.starting_game.subtitle") or "")
      :gsub("{game_display_name}", "Build Battle"):gsub("{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.handleCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    session.sounds.play(handle, "sounds.starting_game.start")
  end
end

local function readBuildTimeSeconds(session)
  local ticks = session.dataAccess.getGameDataNumber("basic.time")
  if ticks and ticks > 0 then
    return math.max(10, math.floor(ticks))
  end
  return 300
end

local function updateScoreboard(session)
  local placeholders = { theme = session.state.selectedTheme, time = formatTime(session.state.buildTimeLeft) }
  for _, handle in ipairs(session.players()) do
    session.scoreboard.update(handle, "scoreboard.default", placeholders)
  end
end

local function broadcastTimeMessage(session, path, seconds)
  local template = session.config.translation(nil, path)
  if not template or template == "" then
    return
  end
  local message = template:gsub("{time}", tostring(seconds))
  for _, handle in ipairs(session.players()) do
    session.messages.sendRaw(handle, message)
  end
end

local function loadNotificationSeconds(session)
  local seconds = {}
  for _, raw in ipairs(session.coreConfig.getSettingsStringList("game.global.countdown_notifications")) do
    local n = tonumber(raw)
    if n then
      seconds[n] = true
    end
  end
  return seconds
end

local function startBuildTimer(session)
  local notificationSeconds = loadNotificationSeconds(session)
  local buildTimeSeconds = readBuildTimeSeconds(session)
  session.state.buildTimeLeft = buildTimeSeconds
  local taskId = "arena_" .. session.arenaId .. "_build_battle_build_timer"

  session.scheduler.runTimer(taskId, function()
    if session.state.ended or session.state.phase ~= "BUILDING" then
      session.scheduler.cancelTask(taskId)
      return
    end

    session.state.buildTimeLeft = math.max(0, session.state.buildTimeLeft - 1)
    local timeLeft = session.state.buildTimeLeft
    updateScoreboard(session)

    if timeLeft <= 0 then
      session.scheduler.cancelTask(taskId)
      M.endBuildPhase(session)
      return
    end

    if notificationSeconds[timeLeft] then
      for _, handle in ipairs(session.players()) do
        session.sounds.play(handle, "sounds.in_game.countdown")
      end
      broadcastTimeMessage(session, "build.time_remaining", timeLeft)
    end
  end, 20, 20)
end

function M.beginPlaying(session)
  session.state.phase = "BUILDING"

  voteService.applyVotes(session)
  voteService.broadcastVoteResults(session)

  local theme = session.state.selectedTheme
  for _, handle in ipairs(session.players()) do
    session.player.setGameMode(handle, "CREATIVE")
    session.player.setAllowFlight(handle, true)
    session.player.setFlying(handle, true)
    session.player.setHealth(handle, 20.0)
    session.player.setFoodLevel(handle, 20)
    session.player.setSaturation(handle, 20.0)
    session.player.setFireTicks(handle, 0)
    session.player.clearInventory(handle)
    optionsService.giveOptionsItem(session, handle)

    local title = session.config.translation(handle, "titles.theme_reveal.title")
    local subtitle = session.config.translation(handle, "titles.theme_reveal.subtitle")
    if title and subtitle then
      session.titles.sendRaw(handle, title, subtitle:gsub("{theme}", theme), 0, 40, 20)
    end

    local broadcast = session.config.translation(handle, "build.theme_broadcast")
    if broadcast then
      session.messages.sendRaw(handle, broadcast:gsub("{theme}", theme))
    end

    session.scoreboard.show(handle, "scoreboard.default")
  end

  updateScoreboard(session)
  startBuildTimer(session)
end

function M.endBuildPhase(session)
  session.state.phase = "PLOT_VOTING"

  for _, handle in ipairs(session.players()) do
    session.player.setGameMode(handle, "SURVIVAL")
    session.player.clearInventory(handle)
    session.player.resetTime(handle)
    session.player.resetWeather(handle)
    optionsService.removeOptionsItem(session, handle)

    local title = session.config.translation(handle, "titles.build_ended.title")
    local subtitle = session.config.translation(handle, "titles.build_ended.subtitle")
    if title and subtitle then
      session.titles.sendRaw(handle, title, subtitle, 0, 30, 10)
    end

    local message = session.config.translation(handle, "build.build_ended")
    if message then
      session.messages.sendRaw(handle, message)
    end
  end

  session.scheduler.runLater("arena_" .. session.arenaId .. "_build_battle_vote_delay", function()
    plotVotingService.startPlotVoting(session, outcomeService)
  end, 40)
end

function M.startParticleTask(session)
  local taskId = "arena_" .. session.arenaId .. "_build_battle_particles"
  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end
    for _, particles in pairs(session.state.plotParticles) do
      for _, particle in ipairs(particles) do
        session.world.spawnParticleAt(particle.location, particle.effect, 5, 0.5, 0.5, 0.5, 0.02)
      end
    end
  end, 20, 20)
end

function M.finishGame(session)
  session.scheduler.cancelArenaTasks()

  plotService.clearPlots(session)
  plotService.regeneratePlotFloors(session)
  session.state.plotParticles = {}

  session.world.setTime(1000)
  session.world.setStorm(false)
  session.world.setThundering(false)

  for _, handle in ipairs(session.players()) do
    session.player.setGameMode(handle, "SURVIVAL")
    session.player.resetTime(handle)
    session.player.resetWeather(handle)
    session.player.resetMaxHealth(handle)
    session.player.setHealth(handle, math.min(session.player.health(handle), 20.0))
    session.player.clearInventory(handle)
  end
end

function M.getCustomPlaceholders(session, handle)
  local placeholders = {}
  if session.state.phase == "BUILDING" then
    placeholders.theme = session.state.selectedTheme
    placeholders.time = formatTime(session.state.buildTimeLeft)
  elseif session.state.phase == "PLOT_VOTING" then
    local players = session.players()
    local current = math.min(session.state.currentPlotIndex + 1, #players)
    placeholders.current = tostring(current)
    placeholders.total = tostring(#players)
    local builder = players[session.state.currentPlotIndex + 1]
    if builder then
      placeholders.builder = session.player.name(builder)
    end
  end
  return placeholders
end

return M

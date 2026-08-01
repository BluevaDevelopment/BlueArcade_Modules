--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy GuessTheBuildGame.java - the top-level per-match orchestration.
local plotService = require("support.plot_service")
local roundService = require("support.round_service")
local themeService = require("support.theme_service")
local hintService = require("support.hint_service")
local cleanupService = require("support.cleanup_service")
local outcomeService = require("support.outcome_service")

local M = {}

local function formatTime(totalSeconds)
  return string.format("%02d:%02d", math.floor(totalSeconds / 60), totalSeconds % 60)
end

local function formatPhase(phase)
  if phase == "THEME_SELECTION" then
    return "Theme Selection"
  elseif phase == "BUILDING" then
    return "Building"
  elseif phase == "ROUND_END" then
    return "Round End"
  elseif phase == "ENDED" then
    return "Ended"
  end
  return "-"
end

local function displayedTimeLeft(session)
  local phase = session.state.phase
  if phase == "THEME_SELECTION" then
    return session.state.themeSelectionTimeLeft
  elseif phase == "BUILDING" then
    return session.state.buildTimeLeft
  elseif phase == "ROUND_END" then
    return session.state.roundDelayTimeLeft
  end
  return 0
end

local function scoreboardPlaceholders(session)
  local builder = session.state.currentBuilder
  return {
    theme = "???",
    time = formatTime(displayedTimeLeft(session)),
    round = tostring(session.state.round),
    arena = tostring(session.arenaId),
    phase = formatPhase(session.state.phase),
    builder = builder and session.player.name(builder) or "-",
  }
end

local function updateScoreboard(session)
  local placeholders = scoreboardPlaceholders(session)
  for _, handle in ipairs(session.players()) do
    session.scoreboard.update(handle, "scoreboard.default", placeholders)
  end
end

local function showScoreboard(session)
  for _, handle in ipairs(session.players()) do
    session.scoreboard.show(handle, "scoreboard.default")
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

local function newState()
  return {
    plot = nil,
    playerPlotSpawn = {},
    playerPlot = {},
    playerPoints = {},

    phase = "THEME_SELECTION",
    round = 1,
    buildTimeLeft = 0,
    themeSelectionTimeLeft = 0,
    roundDelayTimeLeft = 0,

    currentBuildPlot = nil,
    currentBuilder = nil,
    currentTheme = nil,
    currentThemeSynonyms = {},
    currentThemeDifficulty = nil,
    whoGuessed = {},
    revealedLetterIndices = {},
    playedThemes = {},

    characterCountBroadcasted = false,
    themeSelected = false,
    ended = false,
  }
end

local function startThemeSelectionTimer(session)
  local taskId = "arena_" .. session.arenaId .. "_guess_the_build_theme_timer"
  session.scheduler.cancelTask(taskId)
  session.scheduler.runTimer(taskId, function()
    if session.state.ended or session.state.phase ~= "THEME_SELECTION" then
      session.scheduler.cancelTask(taskId)
      return
    end

    session.state.themeSelectionTimeLeft = session.state.themeSelectionTimeLeft - 1
    updateScoreboard(session)

    if session.state.themeSelectionTimeLeft <= 0 then
      session.scheduler.cancelTask(taskId)
      roundService.forceThemeSelection(session)
      M.startBuildTimer(session)
      return
    end

    if session.state.themeSelected then
      session.scheduler.cancelTask(taskId)
      M.startBuildTimer(session)
    end
  end, 20, 20)
end

function M.startBuildTimer(session)
  local taskId = "arena_" .. session.arenaId .. "_guess_the_build_build_timer"
  session.scheduler.cancelTask(taskId)
  updateScoreboard(session)
  session.scheduler.runTimer(taskId, function()
    if session.state.ended or session.state.phase ~= "BUILDING" then
      session.scheduler.cancelTask(taskId)
      return
    end

    session.state.buildTimeLeft = session.state.buildTimeLeft - 1
    local timeLeft = session.state.buildTimeLeft

    hintService.tick(session)
    updateScoreboard(session)

    if timeLeft <= 0 then
      session.scheduler.cancelTask(taskId)
      M.endBuildPhase(session, false)
      return
    end

    local notificationSeconds = session.coreConfig.getSettingsStringList("game.global.countdown_notifications")
    for _, secondsStr in ipairs(notificationSeconds) do
      if tonumber(secondsStr) == timeLeft then
        for _, handle in ipairs(session.players()) do
          session.sounds.play(handle, "sounds.in_game.countdown")
        end
        broadcastTimeMessage(session, "build.time_remaining", timeLeft)
        break
      end
    end
  end, 20, 20)
end

local function startRoundDelayTimer(session)
  local taskId = "arena_" .. session.arenaId .. "_guess_the_build_round_delay"
  session.scheduler.runTimer(taskId, function()
    if session.state.ended or session.state.phase ~= "ROUND_END" then
      session.scheduler.cancelTask(taskId)
      return
    end

    session.state.roundDelayTimeLeft = session.state.roundDelayTimeLeft - 1
    if session.state.roundDelayTimeLeft <= 0 then
      session.scheduler.cancelTask(taskId)

      roundService.advanceRound(session)

      if roundService.shouldEndGame(session) then
        outcomeService.endGame(session)
      else
        M.startRound(session)
      end
    end
  end, 20, 20)
end

function M.endBuildPhase(session, allGuessed)
  session.scheduler.cancelTask("arena_" .. session.arenaId .. "_guess_the_build_build_timer")

  local theme = session.state.currentTheme or "???"
  if not allGuessed then
    for _, handle in ipairs(session.players()) do
      local msg = session.config.translation(handle, "game.theme_reveal_timeout")
      if msg then
        session.messages.sendRaw(handle, msg:gsub("{theme}", theme))
      end
      local title = session.config.translation(handle, "game.theme_reveal_timeout_title")
      local subtitle = session.config.translation(handle, "game.theme_reveal_timeout_subtitle")
      if title and subtitle then
        session.titles.sendRaw(handle, title, subtitle:gsub("{theme}", theme), 0, 40, 20)
      end
    end
  else
    for _, handle in ipairs(session.players()) do
      local msg = session.config.translation(handle, "game.all_guessed")
      if msg then
        session.messages.sendRaw(handle, msg:gsub("{theme}", theme))
      end
    end
  end

  roundService.endRound(session)
  startRoundDelayTimer(session)
end

function M.startRound(session)
  hintService.reset(session)
  roundService.startRound(session, function(theme)
    M.onThemeSelected(session, theme)
  end)
  showScoreboard(session)
  updateScoreboard(session)
  startThemeSelectionTimer(session)
end

function M.onThemeSelected(session, theme)
  if session.state.phase ~= "THEME_SELECTION" then
    return
  end
  session.scheduler.cancelTask("arena_" .. session.arenaId .. "_guess_the_build_open_theme_menu")
  roundService.applyTheme(session, theme)
  updateScoreboard(session)
  M.startBuildTimer(session)
end

function M.handleCorrectGuess(session, guesserHandle)
  if session.state.phase ~= "BUILDING" or hintService.hasGuessed(session, guesserHandle) then
    return
  end

  local guesserBonus = session.config.getInt("points.guesser_speed_bonus." .. (#session.state.whoGuessed + 1), 0)

  local basePoints = 1
  if session.state.currentThemeDifficulty then
    basePoints = session.config.getInt("points.difficulty_base." .. session.state.currentThemeDifficulty:lower(), 1)
  end
  local totalPoints = basePoints + guesserBonus

  session.state.playerPoints[guesserHandle] = (session.state.playerPoints[guesserHandle] or 0) + totalPoints
  table.insert(session.state.whoGuessed, guesserHandle)

  local broadcast = session.config.translation(guesserHandle, "game.correct_guess_broadcast")
  if broadcast then
    broadcast = broadcast:gsub("{player}", session.player.name(guesserHandle))
    for _, handle in ipairs(session.players()) do
      session.messages.sendRaw(handle, broadcast)
    end
  end

  local pointsMsg = session.config.translation(guesserHandle, "game.correct_guess_points")
  if pointsMsg then
    session.messages.sendRaw(guesserHandle, pointsMsg:gsub("{points}", tostring(totalPoints)))
  end

  local builder = session.state.currentBuilder
  if builder then
    local builderPoints = session.config.getInt("points.builder_per_guess", 1)
    session.state.playerPoints[builder] = (session.state.playerPoints[builder] or 0) + builderPoints
    local builderMsg = session.config.translation(guesserHandle, "game.builder_got_points")
    if builderMsg then
      session.messages.sendRaw(builder, builderMsg:gsub("{points}", tostring(builderPoints)))
    end
  end

  local reduction = session.config.getInt("timers.guess_time_reduction_seconds", 10)
  local minRemaining = session.config.getInt("timers.min_remaining_time_after_guess", 15)
  session.state.buildTimeLeft = math.max(minRemaining, session.state.buildTimeLeft - reduction)

  local totalPlayers = #session.players()
  if #session.state.whoGuessed >= totalPlayers - 1 then
    M.endBuildPhase(session, true)
  end
end

function M.startGame(session)
  session.state = newState()

  session.summary.setGameSummaryEnabled(false)
  session.summary.setFinalSummaryEnabled(false)

  session.scheduler.cancelArenaTasks()
  plotService.loadPlot(session)
  plotService.assignPlayersToPlot(session)
  plotService.clearPlot(session)
  plotService.regeneratePlotFloor(session)

  for _, handle in ipairs(session.players()) do
    plotService.teleportToPlot(session, handle)
  end
end

function M.handleCountdownTick(session, secondsLeft)
  for _, handle in ipairs(session.players()) do
    session.sounds.play(handle, "sounds.starting_game.countdown")
    local title = session.coreConfig.language(handle, "titles.starting_game.title") or ""
    local subtitle = session.coreConfig.language(handle, "titles.starting_game.subtitle") or ""
    title = title:gsub("{time}", tostring(secondsLeft))
    subtitle = subtitle:gsub("{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.handleCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    session.sounds.play(handle, "sounds.starting_game.start")
  end
end

function M.beginPlaying(session)
  M.startRound(session)
end

function M.finishGame(session)
  session.scheduler.cancelArenaTasks()

  if session.state.plot then
    plotService.clearPlot(session)
    plotService.regeneratePlotFloor(session)
  end

  cleanupService.resetWorldDefaults(session)
  cleanupService.resetPlayerStates(session)
  cleanupService.clearPlayerInventories(session)
end

-- Mirrors legacy shutdown(): cancel tasks, reset world/players/inventories - no plot clear, no winner.
function M.handleDisable(session)
  session.scheduler.cancelArenaTasks()
  cleanupService.resetWorldDefaults(session)
  cleanupService.resetPlayerStates(session)
  cleanupService.clearPlayerInventories(session)
end

function M.endGame(session)
  if session.state.ended then
    return
  end
  session.state.ended = true
  outcomeService.endGame(session)
end

function M.getCustomPlaceholders(session)
  return scoreboardPlaceholders(session)
end

return M

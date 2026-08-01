-- Mirrors legacy SpeedBuildersGame.java - the top-level per-match orchestration.
local plotService = require("support.plot_service")
local worldSupport = require("support.world_support")
local structurePool = require("support.structure_pool")
local guardianService = require("support.guardian_service")
local judgingService = require("support.judging_service")
local sessionService = require("support.session_service")
local scoreboardService = require("support.scoreboard_service")

local M = {}

local function newState()
  return {
    ended = false,
    phase = "SHOWCASE",
    currentRound = 0,
    timeLeft = 0,
    currentStructure = nil,
    plots = {},
    buildAreas = {},
    showcasePlot = nil,
    playerPlot = {},
    playerPlotSpawn = {},
    playerPlotYaw = {},
    playerBuildArea = {},
    perfectPlayers = {},
    perfectBuilds = {},
    roundsSurvived = {},
    lastScore = {},
    structures = {},
    structurePickOrder = {},
    structurePickIndex = 1,
    guardianOrbitAngle = 0,
    guardianBeamTarget = nil,
  }
end

local function notificationSeconds(session)
  local raw = session.coreConfig.getSettingsStringList("game.global.countdown_notifications")
  local seconds = {}
  for _, value in ipairs(raw) do
    local n = tonumber(value)
    if n then
      seconds[n] = true
    end
  end
  return seconds
end

local function enableGameFlight(session, handle, startFlying)
  session.player.setAllowFlight(handle, true)
  if startFlying then
    session.player.setFlying(handle, true)
  end
  session.player.setFallDistance(handle, 0.0)
end
M.enableGameFlight = enableGameFlight

function M.startGame(session)
  session.state = newState()
  session.scheduler.cancelArenaTasks()

  structurePool.load(session, session.state)
  if not structurePool.hasStructures(session.state) then
    for _, handle in ipairs(session.players()) do
      session.messages.sendRaw(handle, "<red>No structures loaded for Speed Builders!</red>")
    end
    session.endGame()
    return
  end

  plotService.loadPlots(session, session.state)
  if #session.state.buildAreas == 0 then
    for _, handle in ipairs(session.players()) do
      session.messages.sendRaw(handle, "<red>Speed Builders requires at least one build area per plot. Use /baa game <arena> speed_builders build_area add</red>")
    end
    session.endGame()
    return
  end

  plotService.assignPlayersToPlotsAndAreas(session, session.state)
  plotService.regenerateBuildAreaFloors(session, session.state)

  for _, handle in ipairs(session.players()) do
    session.state.lastScore[handle] = 0
    session.state.roundsSurvived[handle] = 0
    session.state.perfectBuilds[handle] = 0
    plotService.teleportToPlot(session, handle, session.state.playerPlotSpawn[handle])
  end
end

function M.handleCountdownTick(session, secondsLeft)
  for _, handle in ipairs(session.players()) do
    session.sounds.play(handle, "sounds.starting_game.countdown")
    local title = (session.coreConfig.language(handle, "titles.starting_game.title") or ""):gsub("{time}", tostring(secondsLeft))
    local subtitle = (session.coreConfig.language(handle, "titles.starting_game.subtitle") or ""):gsub("{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.handleCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    session.sounds.play(handle, "sounds.starting_game.start")
  end
end

local function startNextRound(session, state)
  if state.ended then
    return
  end

  session.structure.clearMobs()
  guardianService.remove(session, state)

  state.perfectPlayers = {}
  state.currentRound = state.currentRound + 1
  local structure = structurePool.pickNext(state)
  state.currentStructure = structure

  if not structure then
    judgingService.endGameWithWinner(session)
    return
  end

  local strictRegion = session.config.getBoolean("gameplay.strict_plot_region", false)
  for _, handle in ipairs(session.alivePlayers()) do
    enableGameFlight(session, handle, true)
    local buildOrigin = worldSupport.getBuildOrigin(state, handle)
    local buildArea = state.playerBuildArea[handle]
    if buildOrigin then
      worldSupport.moveOutOfBuildAreaIfInside(session, state, handle, strictRegion)
      plotService.resetBuildArea(session, buildArea)
      local rotationSteps = worldSupport.getPlayerRotationSteps(state, handle)
      session.structure.paste(buildOrigin, structure.id, rotationSteps)
    end
  end

  local showcase = state.showcasePlot
  if showcase and showcase.spawn then
    plotService.clearRegionAboveFloor(session, showcase.min, showcase.max)
    guardianService.ensureAtShowcase(session, state)
    guardianService.startWatchTask(session, state)
  end

  local structureName = structure.name or "Unknown"
  for _, handle in ipairs(session.players()) do
    local title = session.config.translation(handle, "titles.showcase.title")
    local subtitle = session.config.translation(handle, "titles.showcase.subtitle")
    if title and subtitle then
      session.titles.sendRaw(handle, title, subtitle:gsub("{structure}", structureName), 0, 40, 20)
    end
    local broadcast = session.config.translation(handle, "messages.showcase_started.broadcast")
    if broadcast then
      session.messages.sendRaw(handle, broadcast:gsub("{structure}", structureName))
    end
  end

  state.phase = "SHOWCASE"
  for _, handle in ipairs(session.alivePlayers()) do
    enableGameFlight(session, handle, true)
  end
  state.timeLeft = session.config.getInt("time.showcase", 10)
  scoreboardService.update(session, state)

  local notifications = notificationSeconds(session)
  local taskId = "arena_" .. session.arenaId .. "_speed_builders_showcase_timer"
  session.scheduler.runTimer(taskId, function()
    if state.ended or state.phase ~= "SHOWCASE" then
      session.scheduler.cancelTask(taskId)
      return
    end
    state.timeLeft = state.timeLeft - 1
    for _, alive in ipairs(session.alivePlayers()) do
      enableGameFlight(session, alive, true)
    end
    scoreboardService.update(session, state)
    if state.timeLeft <= 0 then
      session.scheduler.cancelTask(taskId)
      M.startBuildPhase(session, state)
      return
    end
    if notifications[state.timeLeft] then
      for _, handle in ipairs(session.players()) do
        session.sounds.play(handle, "sounds.in_game.countdown")
      end
    end
  end, 20, 20)
end
M.startNextRound = startNextRound

function M.beginPlaying(session)
  local state = session.state
  for _, handle in ipairs(session.players()) do
    session.player.setGameMode(handle, "SURVIVAL")
    enableGameFlight(session, handle, true)
    session.player.setHealth(handle, 20.0)
    session.player.setFoodLevel(handle, 20)
    session.player.setSaturation(handle, 20.0)
    session.player.setFireTicks(handle, 0)
    session.player.clearInventory(handle)
    session.player.clearArmor(handle)
  end

  for _, handle in ipairs(session.alivePlayers()) do
    if not state.playerBuildArea[handle] then
      for _, viewer in ipairs(session.players()) do
        session.messages.sendRaw(viewer, "<red>Not enough build areas configured for all players.</red>")
      end
      session.endGame()
      return
    end
  end

  local maxW, maxH, maxL = plotService.getMaxBuildDimensions(state)
  if maxW > 0 and maxH > 0 and maxL > 0 then
    structurePool.filterByMaxSize(state, maxW, maxH, maxL)
  end

  if not structurePool.hasStructures(state) then
    for _, handle in ipairs(session.players()) do
      session.messages.sendRaw(handle, "<red>No structures fit in the configured plot/build area sizes.</red>")
    end
    session.endGame()
    return
  end

  structurePool.reshuffle(state)
  startNextRound(session, state)
end

function M.startBuildPhase(session, state)
  if state.ended then
    return
  end
  state.phase = "BUILDING"
  local showcase = state.showcasePlot
  if showcase and showcase.spawn then
    plotService.clearRegionAboveFloor(session, showcase.min, showcase.max)
  end

  for _, handle in ipairs(session.alivePlayers()) do
    local area = state.playerBuildArea[handle]
    if worldSupport.getBuildOrigin(state, handle) and area then
      plotService.clearRegionAboveFloor(session, area.min, area.max)
    end
  end

  local structure = state.currentStructure
  for _, handle in ipairs(session.alivePlayers()) do
    enableGameFlight(session, handle, true)
    session.structure.giveBuildItems(handle, structure.id)
    state.roundsSurvived[handle] = (state.roundsSurvived[handle] or 0) + 1

    local title = session.config.translation(handle, "titles.build_start.title")
    local subtitle = session.config.translation(handle, "titles.build_start.subtitle")
    if title and subtitle then
      session.titles.sendRaw(handle, title, subtitle, 0, 20, 10)
    end
    local broadcast = session.config.translation(handle, "messages.build_started.broadcast")
    if broadcast then
      session.messages.sendRaw(handle, broadcast)
    end
  end

  local buildTime = session.dataAccess.getGameDataNumber("basic.time")
  if not buildTime or buildTime <= 0 then
    for _, handle in ipairs(session.players()) do
      session.messages.sendRaw(handle, "<red>Speed Builders requires the arena Core time setting.</red>")
    end
    session.endGame()
    return
  end
  state.timeLeft = math.floor(buildTime)
  scoreboardService.update(session, state)

  local notifications = notificationSeconds(session)
  local taskId = "arena_" .. session.arenaId .. "_speed_builders_build_timer"
  session.scheduler.runTimer(taskId, function()
    if state.ended or state.phase ~= "BUILDING" then
      session.scheduler.cancelTask(taskId)
      return
    end
    state.timeLeft = state.timeLeft - 1
    scoreboardService.update(session, state)
    if state.timeLeft <= 0 then
      session.scheduler.cancelTask(taskId)
      M.startJudgingPhase(session, state)
      return
    end
    if notifications[state.timeLeft] then
      for _, handle in ipairs(session.players()) do
        session.sounds.play(handle, "sounds.in_game.countdown")
      end
    end
  end, 20, 20)
end

function M.startJudgingPhase(session, state)
  if state.ended then
    return
  end
  state.phase = "JUDGING"
  guardianService.showJudgingAnimation(session)
  guardianService.ensureAtShowcase(session, state)

  local structure = state.currentStructure
  local showcase = state.showcasePlot
  if showcase and showcase.spawn and structure then
    for _, handle in ipairs(session.players()) do
      worldSupport.moveOutOfRegionIfInside(session, handle, showcase.min, showcase.max)
    end
    plotService.clearRegionAboveFloor(session, showcase.min, showcase.max)
    session.structure.paste(showcase.spawn, structure.id, 0)
  end

  local judgingDelay = math.max(1, session.config.getInt("time.elimination_delay", 4))
  state.timeLeft = judgingDelay
  scoreboardService.update(session, state)

  for _, handle in ipairs(session.players()) do
    session.player.clearInventory(handle)
    enableGameFlight(session, handle, false)
    local title = session.config.translation(handle, "titles.judging.title")
    local subtitle = session.config.translation(handle, "titles.judging.subtitle")
    if title and subtitle then
      session.titles.sendRaw(handle, title, subtitle, 0, 30, 10)
    end
    local broadcast = session.config.translation(handle, "messages.judging_started.broadcast")
    if broadcast then
      session.messages.sendRaw(handle, broadcast)
    end
  end

  session.scheduler.runLater("arena_" .. session.arenaId .. "_speed_builders_judging", function()
    judgingService.evaluateBuildsAndEliminate(session, state, startNextRound)
  end, judgingDelay * 20)
end

function M.evaluateBuild(session, handle)
  judgingService.evaluateBuild(session, session.state, handle, M.startJudgingPhase)
end

function M.finishGame(session)
  local state = session.state
  session.scheduler.cancelArenaTasks()
  if state then
    plotService.clearBuildAreas(session, state)
    plotService.clearShowcasePlot(session, state)
    session.structure.clearMobs()
    guardianService.remove(session, state)
    plotService.regenerateBuildAreaFloors(session, state)
  end
  sessionService.resetWorldDefaults(session)
  sessionService.resetPlayerStates(session)
  sessionService.clearPlayerInventories(session)
  if state then
    sessionService.recordStats(session, state)
  end
end

function M.getCustomPlaceholders(session, handle)
  if not session.state then
    return {}
  end
  return scoreboardService.getCustomPlaceholders(session.state, handle)
end

return M

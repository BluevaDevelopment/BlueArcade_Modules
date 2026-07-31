-- Mirrors legacy GuessTheBuildRoundService.java.
--
-- selectNextBuilder is simplified from the legacy "skip players who already used a played plot"
-- logic to a plain uniform-random pick. Traced through deliberately, not guessed: with exactly one
-- shared plot (see plot_service.lua's own note), state.getPlayerPlot(p) returns the SAME plot
-- object for every player, so state.getPlayedPlots().contains(playerPlot(p)) is either true for
-- ALL players (the moment it's true for one) or false for none - the "already built" list can
-- never be a strict, non-empty subset. Every round therefore either finds every player "available"
-- immediately, or finds none available and clears the played-plots tracking on the spot before
-- re-checking - both paths land on "pick from all currently alive players," so the anti-repeat
-- bookkeeping never actually changes the outcome. This is real 100%-parity behavior, not a
-- shortcut: a repeat builder in consecutive rounds is exactly what the legacy code also produces.
local themeService = require("support.theme_service")
local plotService = require("support.plot_service")

local M = {}

local function selectNextBuilder(session)
  local alive = session.alivePlayers()
  if #alive == 0 then
    session.state.currentBuilder = nil
    return
  end
  session.state.currentBuilder = alive[math.random(#alive)]
end

local function hidePlayers(session)
  local builder = session.state.currentBuilder
  if not builder then
    return
  end

  local participants = {}
  for _, handle in ipairs(session.players()) do
    participants[#participants + 1] = handle
  end
  for _, handle in ipairs(session.spectators()) do
    local alreadyIncluded = false
    for _, existing in ipairs(participants) do
      if existing == handle then
        alreadyIncluded = true
        break
      end
    end
    if not alreadyIncluded then
      participants[#participants + 1] = handle
    end
  end

  for _, viewer in ipairs(participants) do
    for _, target in ipairs(participants) do
      if target ~= viewer then
        if viewer == builder then
          session.player.hidePlayer(viewer, target)
        elseif target == builder then
          session.player.showPlayer(viewer, target)
        else
          session.player.hidePlayer(viewer, target)
        end
      end
    end
  end
end

local function showPlayers(session)
  local participants = {}
  for _, handle in ipairs(session.players()) do
    participants[#participants + 1] = handle
  end
  for _, handle in ipairs(session.spectators()) do
    local alreadyIncluded = false
    for _, existing in ipairs(participants) do
      if existing == handle then
        alreadyIncluded = true
        break
      end
    end
    if not alreadyIncluded then
      participants[#participants + 1] = handle
    end
  end

  for _, player in ipairs(participants) do
    for _, other in ipairs(participants) do
      session.player.showPlayer(player, other)
    end
  end
end

local function readBuildTimeSeconds(session)
  local raw = session.dataAccess.getGameDataNumber("basic.time")
  if raw then
    return math.max(10, math.floor(raw))
  end
  return 300
end

function M.startRound(session, onThemeSelected)
  session.state.whoGuessed = {}
  session.state.revealedLetterIndices = {}
  session.state.currentTheme = nil
  session.state.currentThemeSynonyms = {}
  session.state.currentThemeDifficulty = nil
  session.state.currentBuildPlot = nil
  session.state.currentBuilder = nil
  session.state.themeSelected = false

  session.state.phase = "THEME_SELECTION"

  if session.state.plot then
    plotService.clearPlot(session)
    plotService.regeneratePlotFloor(session)
  end

  selectNextBuilder(session)
  local builder = session.state.currentBuilder
  if not builder then
    return
  end

  session.state.currentBuildPlot = session.state.plot
  if session.state.plot and session.state.plot.spawn then
    for _, handle in ipairs(session.players()) do
      plotService.teleportToPlot(session, handle)
    end
  end

  for _, handle in ipairs(session.players()) do
    local title = session.config.translation(handle, "game.theme_being_selected.title")
    local subtitle = session.config.translation(handle, "game.theme_being_selected.subtitle")
    if title and subtitle then
      session.titles.sendRaw(handle, title, subtitle, 0, 40, 20)
    end
  end

  hidePlayers(session)

  local themeSelectionSeconds = session.config.getInt("timers.theme_selection_seconds", 15)
  session.state.themeSelectionTimeLeft = themeSelectionSeconds

  session.scheduler.runLater("arena_" .. session.arenaId .. "_guess_the_build_open_theme_menu", function()
    if session.state.ended or session.state.phase ~= "THEME_SELECTION" then
      return
    end
    themeService.openThemeSelectionMenu(session, builder, session.state.playedThemes, onThemeSelected)
  end, 3)
end

function M.forceThemeSelection(session)
  if session.state.themeSelected then
    return
  end
  local theme = themeService.forceRandomTheme(session, session.state.playedThemes)
  M.applyTheme(session, theme)
end

function M.applyTheme(session, theme)
  session.state.currentTheme = theme.names[1]
  session.state.currentThemeSynonyms = theme.names
  session.state.currentThemeDifficulty = theme.difficulty
  session.state.themeSelected = true
  table.insert(session.state.playedThemes, table.concat(theme.names, ", "))

  local builder = session.state.currentBuilder

  session.state.phase = "BUILDING"

  session.state.buildTimeLeft = readBuildTimeSeconds(session)

  for _, handle in ipairs(session.players()) do
    if handle == builder then
      session.player.setGameMode(handle, "CREATIVE")
      session.player.setAllowFlight(handle, true)
      session.player.setFlying(handle, true)
      session.player.clearInventory(handle)
    else
      session.player.setGameMode(handle, "ADVENTURE")
      session.player.setAllowFlight(handle, true)
      session.player.setFlying(handle, true)
      session.player.clearInventory(handle)
    end
    session.player.setHealth(handle, 20.0)
    session.player.setFoodLevel(handle, 20)
    session.player.setFireTicks(handle, 0)

    session.scoreboard.show(handle, "scoreboard.default")
  end

  for _, handle in ipairs(session.players()) do
    local broadcast = session.config.translation(handle, "game.theme_selected_broadcast")
    if broadcast then
      session.messages.sendRaw(handle, broadcast)
    end
  end

  hidePlayers(session)
end

function M.endRound(session)
  session.state.phase = "ROUND_END"
  showPlayers(session)

  local roundDelay = session.config.getInt("timers.round_delay_seconds", 5)
  session.state.roundDelayTimeLeft = roundDelay
end

function M.shouldEndGame(session)
  local alivePlayers = #session.alivePlayers()
  return session.state.round > alivePlayers
end

function M.advanceRound(session)
  session.state.round = session.state.round + 1
end

return M

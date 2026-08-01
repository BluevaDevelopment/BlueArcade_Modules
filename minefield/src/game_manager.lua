--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local messageService = require("support.message_service")
local loadoutService = require("support.loadout_service")
local scoreboardService = require("support.scoreboard_service")
local mineService = require("support.mine_service")

local DEFAULT_GAME_TIME = 60

local M = {}

local function isSpectator(session, handle)
  for _, spectator in ipairs(session.spectators()) do
    if spectator == handle then return true end
  end
  return false
end

function M.handleStart(session)
  session.scheduler.cancelArenaTasks()

  session.state = {
    ended = false,
    winnerId = nil,
    timeLeft = 0,
    tickCount = 0,
    mines = {},
    mineImmunity = {},
  }
  mineService.clearMineBlocks(session)

  messageService.sendDescription(session)
end

function M.handleCountdownTick(session, secondsLeft)
  for _, handle in ipairs(session.players()) do
    session.sounds.play(handle, session.coreConfig.getSound("sounds.starting_game.countdown"))
    local title = string.gsub(session.coreConfig.language(handle, "titles.starting_game.title"), "{game_display_name}", "Minefield")
    title = string.gsub(title, "{time}", tostring(secondsLeft))
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.starting_game.subtitle"), "{game_display_name}", "Minefield")
    subtitle = string.gsub(subtitle, "{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.handleCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    local title = string.gsub(session.coreConfig.language(handle, "titles.game_started.title"), "{game_display_name}", "Minefield")
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.game_started.subtitle"), "{game_display_name}", "Minefield")
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
  session.endGame()
end

local function updateHud(session, allPlayers, timeLeft)
  local topPlayers = scoreboardService.getTopPlayersByDistance(session)

  for _, handle in ipairs(allPlayers) do
    local template = session.coreConfig.language(handle, "action_bar.in_game.global")
    local message = ""
    if template ~= nil then
      message = string.gsub(template, "{time}", formatCountdownTime(timeLeft))
      message = string.gsub(message, "{round}", tostring(session.currentRound))
      message = string.gsub(message, "{round_max}", tostring(session.maxRounds))
    end
    session.messages.sendActionBar(handle, message)

    local placeholders = scoreboardService.getCustomPlaceholders(session, handle)
    placeholders.time = formatCountdownTime(timeLeft)
    placeholders.round = tostring(session.currentRound)
    placeholders.round_max = tostring(session.maxRounds)
    for i = 1, 5 do
      local topHandle = topPlayers[i]
      placeholders["distance_" .. i] = topHandle ~= nil and scoreboardService.formatDistance(session, topHandle) or "-"
    end
    placeholders.mines_active = tostring(mineService.getActiveMineCount(session))

    session.scoreboard.updateModule(handle, placeholders)
  end
end

-- Runs every 10 ticks but decrements timeLeft only every other call: 0.5s HUD refresh, 1s
-- countdown cadence (matches MinefieldGameTimerService's tickCount % 2 == 0 gate).
local function startGameTimer(session)
  local gameTime = session.dataAccess.getGameDataNumber("basic.time")
  if gameTime == nil or gameTime == 0 then gameTime = DEFAULT_GAME_TIME end
  session.state.timeLeft = math.floor(gameTime)
  session.state.tickCount = 0

  local taskId = "arena_" .. session.arenaId .. "_minefield_timer"
  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end

    session.state.tickCount = session.state.tickCount + 1
    if session.state.tickCount % 2 == 0 then
      session.state.timeLeft = session.state.timeLeft - 1
    end

    local allPlayers = session.players()
    local alivePlayers = session.alivePlayers()
    local spectators = session.spectators()

    if #allPlayers < 2 or #alivePlayers == 0 or #spectators >= 3 or session.state.timeLeft <= 0 then
      endGameOnce(session)
      return
    end

    updateHud(session, allPlayers, session.state.timeLeft)
  end, 0, 10)
end

function M.handleGameStart(session)
  startGameTimer(session)
  mineService.placeMines(session)

  for _, handle in ipairs(session.players()) do
    loadoutService.giveStartingItems(session, handle)
    loadoutService.applyStartingEffects(session, handle)
    session.scoreboard.showModule(handle)
  end
end

function M.handleEnd(session)
  session.scheduler.cancelArenaTasks()
  mineService.clearMineBlocks(session)

  for _, handle in ipairs(session.players()) do
    session.stats.add(handle, "games_played", 1)
  end
end

-- Mirrors legacy handleDisable(): cancel tasks, remove placed mine blocks - no stats, no winner.
function M.handleDisable(session)
  session.scheduler.cancelArenaTasks()
  mineService.clearMineBlocks(session)
end

function M.handlePlayerFinish(session, handle)
  session.stats.add(handle, "finish_line_crosses", 1)

  -- Same as race/traffic_light: finishing never calls session.setWinner(), only guards the
  -- "wins" stat via session.state.winnerId.
  if session.state.winnerId == nil then
    session.state.winnerId = handle
    session.stats.add(handle, "wins", 1)
  end
end

function M.handlePlayerDeath(session, handle, deathBlock)
  if isSpectator(session, handle) then return end
  messageService.broadcastDeathMessage(session, handle, deathBlock)
end

function M.handlePlayerRespawn(session, handle)
  loadoutService.applyRespawnEffects(session, handle)
end

function M.handlePlayerOutOfBounds(session, handle, deathBlock)
  if isSpectator(session, handle) then return end

  local deathLocation = session.player.location(handle)
  session.respawnPlayer(handle)
  session.sounds.play(handle, session.coreConfig.getSound("sounds.in_game.respawn"))
  session.visualEffects.playDeathEffect(handle, deathLocation)
  M.handlePlayerDeath(session, handle, deathBlock)
  M.handlePlayerRespawn(session, handle)
end

function M.handleFinishLineCross(session, handle)
  if isSpectator(session, handle) then return end

  session.finishPlayer(handle)

  local position = 0
  for i, spectator in ipairs(session.spectators()) do
    if spectator == handle then position = i end
  end

  M.handlePlayerFinish(session, handle)
  messageService.broadcastFinish(session, handle, position)

  local title = session.config.translation(handle, "titles.finished.title")
  local subtitle = string.gsub(session.config.translation(handle, "titles.finished.subtitle"), "{position}", tostring(position))
  session.titles.sendRaw(handle, title, subtitle, 0, 80, 20)
  session.sounds.play(handle, session.coreConfig.getSound("sounds.in_game.classified"))
end

function M.handleMineTrigger(session, handle, plateLocation)
  mineService.handleMineTrigger(session, handle, plateLocation)
end

function M.removeMineLocation(session, x, y, z)
  mineService.removeMineLocation(session, x, y, z)
end

function M.isMineMaterial(session, materialName)
  return mineService.isMineMaterial(session, materialName)
end

function M.getCustomPlaceholders(session, handle)
  local placeholders = scoreboardService.getCustomPlaceholders(session, handle)
  placeholders.mines_active = tostring(mineService.getActiveMineCount(session))
  return placeholders
end

return M

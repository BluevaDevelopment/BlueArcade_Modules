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
local fallingBlockService = require("support.falling_block_service")
local blockService = require("support.block_service")

local M = {}

local function resolveMode(session)
  local dataMode = session.dataAccess.getGameDataString("basic.mode")
  if dataMode == nil then return "chaos" end
  local lower = string.lower(dataMode)
  if lower == "chaos" or lower == "trail" then return lower end
  return "chaos"
end

local function isSpectator(session, handle)
  for _, spectator in ipairs(session.spectators()) do
    if spectator == handle then return true end
  end
  return false
end

function M.handleStart(session)
  session.scheduler.cancelArenaTasks()

  local mode = resolveMode(session)
  session.state = {
    ended = false,
    winnerId = nil,
    mode = mode,
    floorMin = nil,
    floorMax = nil,
    eliminatedPlayers = {},
    blockProgress = {},
    trackedTrailBlocks = {},
    trackedTrailStages = {},
    fallingBlocks = {},
  }

  blockService.cacheSettings(session)
  blockService.cacheFloorBounds(session)

  messagingService.sendDescription(session, mode)
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

local function endGameOnce(session)
  if session.state.ended then return end
  session.state.ended = true

  session.scheduler.cancelArenaTasks()

  local alivePlayers = session.alivePlayers()
  if #alivePlayers == 1 then
    local winner = alivePlayers[1]
    session.setWinner(winner)
    statsService.recordWin(session, winner)
  end

  session.endGame()
end

local function startGameTimer(session)
  local gameTime = session.dataAccess.getGameDataNumber("basic.time")
  if gameTime == nil or gameTime == 0 then gameTime = 180 end
  local timeLeft = math.floor(gameTime)

  local taskId = "arena_" .. session.arenaId .. "_red_alert_timer"
  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end

    timeLeft = timeLeft - 1

    local alivePlayers = session.alivePlayers()
    if #alivePlayers <= 1 or timeLeft <= 0 then
      endGameOnce(session)
      return
    end

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

      session.scoreboard.update(handle, "scoreboard.main", placeholders)
    end
  end, 0, 20)
end

function M.handleGameStart(session)
  blockService.resetFloor(session)
  messagingService.sendStartTitle(session)
  startGameTimer(session)
  blockService.startModeTasks(session)

  for _, handle in ipairs(session.players()) do
    session.player.setGameMode(handle, "SURVIVAL")
    loadoutService.giveStartingItems(session, handle)
    loadoutService.applyStartingEffects(session, handle)
    session.scoreboard.show(handle, "scoreboard.main")
  end
end

function M.handleEnd(session)
  session.scheduler.cancelArenaTasks()
  blockService.resetFloor(session)
  fallingBlockService.cleanupAll(session)
  statsService.recordGamesPlayed(session)
end

-- Mirrors legacy handleDisable(): cancel tasks, drop falling blocks - no floor reset, no stats.
function M.handleDisable(session)
  session.scheduler.cancelArenaTasks()
  fallingBlockService.cleanupAll(session)
end

function M.handlePlayerElimination(session, handle)
  if isSpectator(session, handle) then return end
  if session.state.eliminatedPlayers[handle] then return end
  session.state.eliminatedPlayers[handle] = true

  messagingService.sendDeathMessage(session, handle)
  session.eliminate(handle, session.config.translation(handle, "messages.eliminated"))
  session.player.clearInventory(handle)
  session.setSpectating(handle, true)
  session.sounds.play(handle, session.coreConfig.getSound("sounds.in_game.respawn"))
end

function M.handlePlayerStep(session, handle, to)
  blockService.handlePlayerStep(session, handle, to)
end

function M.shouldEliminate(session, to)
  return blockService.shouldEliminate(session, to)
end

function M.getCustomPlaceholders(session, handle)
  return {
    alive = tostring(#session.alivePlayers()),
    spectators = tostring(#session.spectators()),
    mode = messagingService.getModeDisplayName(session, handle, session.state.mode),
  }
end

return M

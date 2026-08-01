--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local loadoutService = require("support.loadout_service")
local messagingService = require("support.messaging_service")
local statsService = require("support.stats_service")

local M = {}

local DEFAULT_GAME_TIME = 180

local function formatTime(seconds)
  if seconds < 0 then seconds = 0 end
  return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function placeholders(session)
  return {
    alive = tostring(#session.alivePlayers()),
    spectators = tostring(#session.spectators()),
  }
end

function M.getCustomPlaceholders(session, handle)
  return placeholders(session)
end

local function handleWin(session, handle)
  if session.state.winnerCredited then return end
  session.state.winnerCredited = true
  statsService.recordWin(session, handle)
end

function M.handleBlockBreak(session, handle)
  statsService.recordBlockBreak(session, handle)
end

function M.handlePlayerElimination(session, handle)
  for _, spectator in ipairs(session.spectators()) do
    if spectator == handle then return end
  end

  if session.state.eliminatedHandles[handle] then return end
  session.state.eliminatedHandles[handle] = true

  messagingService.broadcastElimination(session, handle)
  session.eliminate(handle, session.config.translation(handle, "messages.eliminated"))
  session.player.clearInventory(handle)
  session.setSpectating(handle, true)
  messagingService.playRespawnSound(session, handle)
  loadoutService.applyRespawnEffects(session, handle)
end

-- os.clock() (monotonic, sub-second) is used instead of os.time() - the 0.2s default delay would round away to nothing otherwise.
function M.canShoot(session, handle)
  local delayTicks = session.config.getInt("game.shoot_delay_ticks", 0)
  if delayTicks <= 0 then return true end

  local lastTime = session.state.lastShootTime[handle]
  if lastTime == nil then return true end

  local delaySeconds = delayTicks * 50 / 1000
  return os.clock() - lastTime >= delaySeconds
end

function M.recordShoot(session, handle)
  session.state.lastShootTime[handle] = os.clock()
end

local function endGameOnce(session)
  if session.state.ended then return end
  session.state.ended = true

  session.scheduler.cancelArenaTasks()

  local alive = session.alivePlayers()
  if #alive == 1 then
    session.setWinner(alive[1])
    handleWin(session, alive[1])
  end

  session.endGame()
end

local function startGameTimer(session)
  local gameTime = session.dataAccess.getGameDataNumber("basic.time")
  if gameTime == nil or gameTime == 0 then gameTime = DEFAULT_GAME_TIME end
  session.state.timeLeft = math.floor(gameTime)

  session.scheduler.runTimer("arena_" .. session.arenaId .. "_splegg_timer", function()
    if session.state.ended then
      session.scheduler.cancelTask("arena_" .. session.arenaId .. "_splegg_timer")
      return
    end

    session.state.timeLeft = session.state.timeLeft - 1

    local alive = session.alivePlayers()
    if #alive <= 1 or session.state.timeLeft <= 0 then
      endGameOnce(session)
      return
    end

    for _, handle in ipairs(session.players()) do
      messagingService.sendActionBar(session, handle, session.state.timeLeft)

      local entries = placeholders(session)
      entries.time = formatTime(session.state.timeLeft)
      entries.round = tostring(session.currentRound)
      entries.round_max = tostring(session.maxRounds)
      session.scoreboard.updateModule(handle, entries)
    end
  end, 0, 20)
end

function M.handleStart(session)
  session.scheduler.cancelArenaTasks()

  session.state = {
    ended = false,
    winnerCredited = false,
    timeLeft = 0,
    eliminatedHandles = {},
    lastShootTime = {},
  }

  messagingService.sendDescription(session)
end

function M.handleCountdownTick(session, secondsLeft)
  messagingService.sendCountdownTick(session, secondsLeft)
end

function M.handleCountdownFinish(session)
  messagingService.sendCountdownFinish(session)
end

function M.handleGameStart(session)
  startGameTimer(session)

  for _, handle in ipairs(session.players()) do
    session.player.setGameMode(handle, "SURVIVAL")
    loadoutService.giveStartingItems(session, handle)
    loadoutService.applyStartingEffects(session, handle)
    session.scoreboard.showModule(handle)
  end
end

function M.handleEnd(session)
  session.scheduler.cancelArenaTasks()
  for _, handle in ipairs(session.players()) do
    statsService.recordGamePlayed(session, handle)
  end
end

-- Mirrors legacy handleDisable(): cancel tasks only, no winner, no stats.
function M.handleDisable(session)
  session.scheduler.cancelArenaTasks()
end

return M

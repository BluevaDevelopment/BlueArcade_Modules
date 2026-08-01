local messagingService = require("support.messaging_service")
local loadoutService = require("support.loadout_service")
local statsService = require("support.stats_service")
local progressService = require("support.progress_service")

local M = {}

local function locationKey(location)
  return math.floor(location.x) .. "," .. math.floor(location.y) .. "," .. math.floor(location.z)
end

local function parseKey(key)
  local x, y, z = string.match(key, "(-?%d+),(-?%d+),(-?%d+)")
  return tonumber(x), tonumber(y), tonumber(z)
end

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
    placedBlocks = {},
  }

  messagingService.sendDescription(session)
end

function M.handleCountdownTick(session, secondsLeft)
  messagingService.sendCountdownTick(session, secondsLeft)
end

function M.handleCountdownFinish(session)
  messagingService.sendCountdownFinished(session)
end

function M.getCustomPlaceholders(session, handle)
  local placeholders = { bridge_race_position = tostring(progressService.calculateLivePosition(session, handle)) }

  local topPlayers = progressService.getTopPlayersByDistance(session)
  for i = 1, 5 do
    local topHandle = topPlayers[i]
    placeholders["place_" .. i] = topHandle ~= nil and session.player.name(topHandle) or "-"
  end

  return placeholders
end

local function endGameOnce(session)
  if session.state.ended then return end
  session.state.ended = true

  session.scheduler.cancelArenaTasks()
  session.endGame()
end

local function startGameTimer(session)
  local gameTime = session.dataAccess.getGameDataNumber("basic.time")
  if gameTime == nil or gameTime == 0 then gameTime = 60 end
  local timeLeft = math.floor(gameTime)
  local tickCount = 0

  local taskId = "arena_" .. session.arenaId .. "_bridge_race_timer"
  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end

    tickCount = tickCount + 1
    if tickCount % 2 == 0 then
      timeLeft = timeLeft - 1
    end

    local allPlayers = session.players()
    local alivePlayers = session.alivePlayers()
    local spectators = session.spectators()

    if #allPlayers < 2 or #alivePlayers == 0 or #spectators >= 3 or timeLeft <= 0 then
      endGameOnce(session)
      return
    end

    local topPlayers = progressService.getTopPlayersByDistance(session)
    for _, handle in ipairs(allPlayers) do
      messagingService.sendActionBar(session, handle, timeLeft)

      local placeholders = M.getCustomPlaceholders(session, handle)
      placeholders.time = string.format("%02d:%02d", math.floor(math.max(0, timeLeft) / 60), math.max(0, timeLeft) % 60)
      placeholders.round = tostring(session.currentRound)
      placeholders.round_max = tostring(session.maxRounds)
      for i = 1, 5 do
        local topHandle = topPlayers[i]
        placeholders["distance_" .. i] = topHandle ~= nil and progressService.formatDistance(session, topHandle) or "-"
      end

      session.scoreboard.updateModule(handle, placeholders)
    end
  end, 0, 10)
end

function M.handleGameStart(session)
  startGameTimer(session)

  for _, handle in ipairs(session.players()) do
    loadoutService.prepareForStart(session, handle)
    session.scoreboard.showModule(handle)
  end
end

function M.handlePlayerFinish(session, handle)
  statsService.recordFinishLineCross(session, handle)

  -- Same anomaly as race/traffic_light/minefield/red_alert: never calls session.setWinner(), only guards the "wins" stat.
  if session.state.winnerId == nil then
    session.state.winnerId = handle
    statsService.recordWin(session, handle)
  end
end

function M.handlePlayerRespawn(session, handle)
  loadoutService.prepareForRespawn(session, handle)
end

function M.handlePlayerDeath(session, handle, deathBlock)
  messagingService.broadcastDeath(session, handle, deathBlock)
end

local function processActiveMovement(session, handle, to)
  if isSpectator(session, handle) then return end

  if not session.isInsideBounds(to) then
    session.visualEffects.playDeathEffect(handle, session.player.location(handle))
    session.respawnPlayer(handle)
    messagingService.playRespawnSound(session, handle)
    M.handlePlayerDeath(session, handle, false)
    M.handlePlayerRespawn(session, handle)
    return
  end

  local deathBlock = messagingService.getDeathBlock(session)
  local blockBelowType = session.world.blockTypeAt(math.floor(to.x), math.floor(to.y - 1), math.floor(to.z))
  if blockBelowType == deathBlock then
    session.visualEffects.playDeathEffect(handle, session.player.location(handle))
    session.respawnPlayer(handle)
    messagingService.playRespawnSound(session, handle)
    M.handlePlayerDeath(session, handle, true)
    M.handlePlayerRespawn(session, handle)
    return
  end

  if messagingService.isInsideFinishLine(session, to) then
    session.finishPlayer(handle)

    local position = 0
    for i, spectator in ipairs(session.spectators()) do
      if spectator == handle then position = i end
    end

    M.handlePlayerFinish(session, handle)
    messagingService.broadcastFinish(session, handle, position)
    messagingService.sendFinishTitles(session, handle, position)
  end
end

-- freezePlayersOnCountdown() is real here - COUNTDOWN moves are unconditionally snapped back, same as `race`.
function M.handlePlayerMove(session, handle, from, to)
  if session.phase() == "COUNTDOWN" then
    session.player.teleport(handle, from)
    return
  end

  if session.phase() == "PLAYING" then
    processActiveMovement(session, handle, to)
    return
  end

  if not session.isInsideBounds(to) then
    session.respawnPlayer(handle)
    messagingService.playRespawnSound(session, handle)
    M.handlePlayerDeath(session, handle, false)
    M.handlePlayerRespawn(session, handle)
  end
end

function M.handleBlockPlaced(session, handle, location)
  session.state.placedBlocks[locationKey(location)] = true
  statsService.recordBlockPlaced(session, handle)
end

function M.isPlacedBlock(session, location)
  return session.state.placedBlocks[locationKey(location)] == true
end

function M.removePlacedBlock(session, location)
  session.state.placedBlocks[locationKey(location)] = nil
end

local function clearPlacedBlocks(session)
  for key in pairs(session.state.placedBlocks) do
    local x, y, z = parseKey(key)
    session.world.setBlockType(x, y, z, "AIR")
  end
  session.state.placedBlocks = {}
end

function M.handleEnd(session)
  session.scheduler.cancelArenaTasks()
  clearPlacedBlocks(session)
  statsService.recordGamePlayed(session)
end

return M

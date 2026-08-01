local loadoutService = require("support.loadout_service")
local messagingService = require("support.messaging_service")
local statsService = require("support.stats_service")

local M = {}

local DEFAULT_GAME_TIME = 60

local function formatTime(seconds)
  if seconds < 0 then seconds = 0 end
  return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function distanceToFinish(session, handle)
  local finishMin = session.dataAccess.getGameLocation("game.finish_line.bounds.min")
  local finishMax = session.dataAccess.getGameLocation("game.finish_line.bounds.max")
  if finishMin == nil or finishMax == nil then return math.huge end

  local centerX = (finishMin.x + finishMax.x) / 2
  local centerY = (finishMin.y + finishMax.y) / 2
  local centerZ = (finishMin.z + finishMax.z) / 2

  local loc = session.player.location(handle)
  local dx, dy, dz = loc.x - centerX, loc.y - centerY, loc.z - centerZ
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function isSpectatorHandle(session, handle)
  for _, h in ipairs(session.spectators()) do
    if h == handle then return true end
  end
  return false
end

local function topPlayersByDistance(session)
  local top = {}
  for _, handle in ipairs(session.spectators()) do
    top[#top + 1] = handle
  end

  local alive = {}
  for _, handle in ipairs(session.alivePlayers()) do
    alive[#alive + 1] = { handle = handle, distance = distanceToFinish(session, handle) }
  end
  table.sort(alive, function(a, b) return a.distance < b.distance end)
  for _, entry in ipairs(alive) do
    top[#top + 1] = entry.handle
  end

  return top
end

local function livePosition(session, handle)
  local spectators = session.spectators()
  for i, h in ipairs(spectators) do
    if h == handle then return i end
  end

  local alive = {}
  for _, h in ipairs(session.alivePlayers()) do
    alive[#alive + 1] = { handle = h, distance = distanceToFinish(session, h) }
  end
  table.sort(alive, function(a, b) return a.distance < b.distance end)
  for i, entry in ipairs(alive) do
    if entry.handle == handle then return #spectators + i end
  end

  return #spectators + #alive
end

local function formatDistance(session, handle)
  if isSpectatorHandle(session, handle) then return "0" end

  local distance = distanceToFinish(session, handle)
  if distance == math.huge then return "?" end
  return string.format("%.0f", distance)
end

local function placeholders(session, handle)
  local result = {}
  result.race_position = tostring(livePosition(session, handle))

  local top = topPlayersByDistance(session)
  for i = 1, 5 do
    result["place_" .. i] = top[i] ~= nil and session.player.name(top[i]) or "-"
  end

  return result
end

function M.getCustomPlaceholders(session, handle)
  return placeholders(session, handle)
end

function M.handlePlayerFinish(session, handle)
  statsService.recordFinishLineCross(session, handle)

  -- Legacy never calls GameContext#setWinner here; only credits the "wins" stat once per arena.
  if not session.state.winnerCredited then
    session.state.winnerCredited = true
    statsService.recordWin(session, handle)
  end
end

function M.handlePlayerRespawn(session, handle)
  loadoutService.applyRespawnEffects(session, handle)
end

function M.handlePlayerDeath(session, handle, deathBlock)
  messagingService.broadcastDeath(session, handle, deathBlock)
end

function M.handleNonPlayingOutOfBounds(session, handle)
  session.respawnPlayer(handle)
  messagingService.playRespawnSound(session, handle)
  M.handlePlayerDeath(session, handle, false)
  M.handlePlayerRespawn(session, handle)
end

function M.processActiveMovement(session, handle, to)
  if isSpectatorHandle(session, handle) then return end

  if not session.isInsideBounds(to) then
    session.visualEffects.playDeathEffect(handle)
    session.respawnPlayer(handle)
    messagingService.playRespawnSound(session, handle)
    M.handlePlayerDeath(session, handle, false)
    M.handlePlayerRespawn(session, handle)
    return
  end

  local deathBlockType = messagingService.getDeathBlock(session)
  local blockBelowType = session.world.blockTypeAt(math.floor(to.x), math.floor(to.y - 1), math.floor(to.z))
  if blockBelowType == deathBlockType then
    session.visualEffects.playDeathEffect(handle)
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

local function endGameOnce(session)
  if session.state.ended then return end
  session.state.ended = true

  session.scheduler.cancelArenaTasks()
  session.endGame()
end

local function shouldForceEnd(session, timeLeft)
  local allCount = #session.players()
  if allCount < 2 then return true end
  if #session.alivePlayers() == 0 then return true end
  if #session.spectators() >= 3 then return true end
  return timeLeft <= 0
end

local function startGameTimer(session)
  local gameTime = session.dataAccess.getGameDataNumber("basic.time")
  if gameTime == nil or gameTime == 0 then gameTime = DEFAULT_GAME_TIME end
  session.state.timeLeft = math.floor(gameTime)
  session.state.tickCount = 0
  session.state.unstableEndChecks = 0

  session.scheduler.runTimer("arena_" .. session.arenaId .. "_race_timer", function()
    if session.state.ended then
      session.scheduler.cancelTask("arena_" .. session.arenaId .. "_race_timer")
      return
    end

    session.state.tickCount = session.state.tickCount + 1
    if session.state.tickCount % 2 == 0 then
      session.state.timeLeft = session.state.timeLeft - 1
    end

    if shouldForceEnd(session, session.state.timeLeft) then
      session.state.unstableEndChecks = session.state.unstableEndChecks + 1
      -- Avoid ending the round from a transient context snapshot right as the game starts.
      if session.state.tickCount < 4 or session.state.unstableEndChecks < 3 then
        return
      end
      endGameOnce(session)
      return
    end

    session.state.unstableEndChecks = 0

    for _, handle in ipairs(session.players()) do
      messagingService.sendActionBar(session, handle, session.state.timeLeft)

      local entries = placeholders(session, handle)
      entries.time = formatTime(session.state.timeLeft)
      entries.round = tostring(session.currentRound)
      entries.round_max = tostring(session.maxRounds)

      local top = topPlayersByDistance(session)
      for i = 1, 5 do
        entries["distance_" .. i] = top[i] ~= nil and formatDistance(session, top[i]) or "-"
      end

      session.scoreboard.updateModule(handle, entries)
    end
  end, 0, 10)
end

function M.handleStart(session)
  session.scheduler.cancelArenaTasks()

  session.state = {
    ended = false,
    winnerCredited = false,
    timeLeft = 0,
    tickCount = 0,
    unstableEndChecks = 0,
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

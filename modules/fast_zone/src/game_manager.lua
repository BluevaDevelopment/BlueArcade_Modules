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

local DEFAULT_GAME_TIME = 60

local function formatTime(seconds)
  if seconds < 0 then seconds = 0 end
  return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function randomMessage(session, path)
  local messages = session.config.translationList(nil, path)
  if #messages == 0 then return nil end
  return messages[math.random(#messages)]
end

local function distanceToFinish(session, handle)
  local finishMin = session.dataAccess.getGameLocation("game.finish_line.bounds.min")
  local finishMax = session.dataAccess.getGameLocation("game.finish_line.bounds.max")
  if finishMin == nil or finishMax == nil then return math.huge end

  local minX, maxX = math.min(finishMin.x, finishMax.x), math.max(finishMin.x, finishMax.x)
  local minY, maxY = math.min(finishMin.y, finishMax.y), math.max(finishMin.y, finishMax.y)
  local minZ, maxZ = math.min(finishMin.z, finishMax.z), math.max(finishMin.z, finishMax.z)

  local loc = session.player.location(handle)

  local dx, dy, dz = 0, 0, 0
  if loc.x < minX then dx = minX - loc.x elseif loc.x > maxX then dx = loc.x - maxX end
  if loc.y < minY then dy = minY - loc.y elseif loc.y > maxY then dy = loc.y - maxY end
  if loc.z < minZ then dz = minZ - loc.z elseif loc.z > maxZ then dz = loc.z - maxZ end

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
  return tostring(math.floor(distance + 0.5))
end

local function placeholders(session, handle)
  local result = {}
  result.fast_zone_position = tostring(livePosition(session, handle))

  local top = topPlayersByDistance(session)
  for i = 1, 5 do
    result["place_" .. i] = top[i] ~= nil and session.player.name(top[i]) or "-"
  end

  return result
end

function M.getCustomPlaceholders(session, handle)
  return placeholders(session, handle)
end

local function handleWin(session, handle)
  if session.state.winnerCredited then return end
  session.state.winnerCredited = true
  statsService.recordWin(session, handle)
  session.setWinner(handle)
end

function M.handlePlayerFinish(session, handle)
  statsService.recordFinishLineCross(session, handle)
  handleWin(session, handle)
end

function M.handlePlayerRespawn(session, handle)
  loadoutService.applyRespawnEffects(session, handle)
end

function M.playRespawnSound(session, handle)
  session.sounds.play(handle, session.coreConfig.getSound("sounds.in_game.respawn"))
end

function M.playFinishSound(session, handle)
  session.sounds.play(handle, session.coreConfig.getSound("sounds.in_game.classified"))
end

function M.handlePlayerDeath(session, handle, reasonPath)
  local message = randomMessage(session, reasonPath)
  messagingService.broadcastDeathMessage(session, handle, message)
end

function M.broadcastFinish(session, handle, position)
  local message = randomMessage(session, "messages.finish.crossed")
  messagingService.broadcastFinish(session, handle, position, message)
end

function M.handleWallCollision(session, handle)
  M.playRespawnSound(session, handle)
  session.visualEffects.playDeathEffect(handle)
  M.handlePlayerDeath(session, handle, "messages.deaths.wall")
  session.respawnPlayer(handle)
  M.handlePlayerRespawn(session, handle)
end

local function shouldForceEnd(session, timeLeft)
  local allCount = #session.players()
  if allCount < 2 then return true end
  if #session.alivePlayers() == 0 then return true end
  if #session.spectators() >= allCount then return true end
  return timeLeft <= 0
end

local function endGameOnce(session)
  if session.state.ended then return end
  session.state.ended = true

  local alive = session.alivePlayers()
  local spectators = session.spectators()

  if #alive == 1 then
    handleWin(session, alive[1])
  elseif #alive == 0 and #spectators > 0 then
    handleWin(session, spectators[1])
  end

  session.scheduler.cancelArenaTasks()
  session.endGame()
end

local function startGameTimer(session)
  local gameTime = session.dataAccess.getGameDataNumber("basic.time")
  if gameTime == nil or gameTime == 0 then gameTime = DEFAULT_GAME_TIME end
  session.state.timeLeft = math.floor(gameTime)
  session.state.tickCount = 0

  session.scheduler.runTimer("arena_" .. session.arenaId .. "_fast_zone_timer", function()
    if session.state.ended then
      session.scheduler.cancelTask("arena_" .. session.arenaId .. "_fast_zone_timer")
      return
    end

    session.state.tickCount = session.state.tickCount + 1
    if session.state.tickCount % 2 == 0 then
      session.state.timeLeft = session.state.timeLeft - 1
    end

    if shouldForceEnd(session, session.state.timeLeft) then
      endGameOnce(session)
      return
    end

    for _, handle in ipairs(session.players()) do
      local template = session.coreConfig.language(handle, "action_bar.in_game.global")
      local message = ""
      if template ~= nil then
        message = string.gsub(template, "{time}", formatTime(session.state.timeLeft))
        message = string.gsub(message, "{round}", tostring(session.currentRound))
        message = string.gsub(message, "{round_max}", tostring(session.maxRounds))
      end
      session.messages.sendActionBar(handle, message)

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

return M

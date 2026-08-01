local messagingService = require("support.messaging_service")
local statsService = require("support.stats_service")
local loadoutService = require("support.loadout_service")

local M = {}

local DEFAULT_GAME_TIME = 180

local WOOL_COLORS = {
  "WHITE_WOOL", "ORANGE_WOOL", "MAGENTA_WOOL", "LIGHT_BLUE_WOOL", "YELLOW_WOOL", "LIME_WOOL",
  "PINK_WOOL", "GRAY_WOOL", "LIGHT_GRAY_WOOL", "CYAN_WOOL", "PURPLE_WOOL", "BLUE_WOOL",
  "BROWN_WOOL", "GREEN_WOOL", "RED_WOOL", "BLACK_WOOL",
}

local function randomWool()
  return WOOL_COLORS[math.random(#WOOL_COLORS)]
end

local function formatTime(seconds)
  if seconds < 0 then seconds = 0 end
  return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Lazily creates a score entry on first score change, matching legacy (no pre-seeding).
local function addScore(session, handle, amount)
  session.state.scores[handle] = (session.state.scores[handle] or 0) + amount
end

local function topPlayersByScore(session, limit)
  local entries = {}
  for handle, score in pairs(session.state.scores) do
    entries[#entries + 1] = { handle = handle, score = score, name = session.player.name(handle) }
  end
  table.sort(entries, function(a, b) return a.score > b.score end)
  if limit == nil then return entries end
  local top = {}
  for i = 1, math.min(limit, #entries) do
    top[i] = entries[i]
  end
  return top
end

local function playerPosition(session, handle)
  local top = topPlayersByScore(session, nil)
  for i, entry in ipairs(top) do
    if entry.handle == handle then return i end
  end
  return #top + 1
end

local function placeholders(session, handle)
  local result = {}
  local top = topPlayersByScore(session, 5)
  for i = 1, 5 do
    if top[i] ~= nil then
      result["place_" .. i] = top[i].name
      result["score_" .. i] = tostring(top[i].score)
    else
      result["place_" .. i] = "-"
      result["score_" .. i] = "0"
    end
  end
  result.player_score = tostring(session.state.scores[handle] or 0)
  result.player_position = tostring(playerPosition(session, handle))
  return result
end

function M.getCustomPlaceholders(session, handle)
  return placeholders(session, handle)
end

local function handleWin(session, handle)
  if session.state.winnerCredited then return end
  session.state.winnerCredited = true
  statsService.recordWin(session, handle)
end

local function blockKey(location)
  return math.floor(location.x) .. "," .. math.floor(location.y) .. "," .. math.floor(location.z)
end

function M.handleWaterLanding(session, handle, blockLocation)
  local key = blockKey(blockLocation)
  if session.state.changedBlocks[key] == nil then
    session.state.changedBlocks[key] = blockLocation
  end
  session.world.setBlockType(math.floor(blockLocation.x), math.floor(blockLocation.y), math.floor(blockLocation.z), randomWool())

  addScore(session, handle, 2)
  statsService.recordWaterLanding(session, handle)
  messagingService.sendWaterLanding(session, handle)
end

function M.handleMissedLanding(session, handle)
  addScore(session, handle, -1)
  messagingService.sendMissedLanding(session, handle)
  session.respawnPlayer(handle)
end

function M.handlePlayerRespawn(session, handle)
  loadoutService.applyRespawnEffects(session, handle)
  messagingService.playRespawnSound(session, handle)
end

local function restoreBlocks(session)
  for _, location in pairs(session.state.changedBlocks) do
    session.world.setBlockType(math.floor(location.x), math.floor(location.y), math.floor(location.z), "WATER")
  end
  session.state.changedBlocks = {}
end

local function endGameOnce(session)
  if session.state.ended then return end
  session.state.ended = true
  session.scheduler.cancelArenaTasks()

  local top = topPlayersByScore(session, nil)
  if #top > 0 then
    session.setWinner(top[1].handle)
    handleWin(session, top[1].handle)

    for i = 2, #top do
      if session.isPlaying(top[i].handle) then
        session.finishPlayer(top[i].handle)
      end
    end
  end

  session.endGame()
end

local function startGameTimer(session)
  local gameTime = session.dataAccess.getGameDataNumber("basic.time")
  if gameTime == nil or gameTime == 0 then gameTime = DEFAULT_GAME_TIME end
  session.state.timeLeft = math.floor(gameTime)

  session.scheduler.runTimer("arena_" .. session.arenaId .. "_water_well_timer", function()
    if session.state.ended then
      session.scheduler.cancelTask("arena_" .. session.arenaId .. "_water_well_timer")
      return
    end

    session.state.timeLeft = session.state.timeLeft - 1

    if session.state.timeLeft <= 0 then
      endGameOnce(session)
      return
    end

    for _, handle in ipairs(session.players()) do
      messagingService.sendActionBar(session, handle, session.state.timeLeft)

      local entries = placeholders(session, handle)
      entries.time = formatTime(session.state.timeLeft)
      entries.round = tostring(session.currentRound)
      entries.round_max = tostring(session.maxRounds)
      entries.spectators = tostring(#session.spectators())
      session.scoreboard.updateModule(handle, entries)
    end
  end, 0, 20)
end

function M.handleStart(session)
  session.scheduler.cancelArenaTasks()

  session.state = {
    scores = {},
    changedBlocks = {},
    ended = false,
    winnerCredited = false,
    timeLeft = 0,
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
    session.player.setGameMode(handle, "ADVENTURE")
    loadoutService.giveStartingItems(session, handle)
    loadoutService.applyStartingEffects(session, handle)
    session.scoreboard.showModule(handle)
  end
end

function M.handleEnd(session)
  session.scheduler.cancelArenaTasks()
  restoreBlocks(session)
  for _, handle in ipairs(session.players()) do
    statsService.recordGamePlayed(session, handle)
  end
end

-- Mirrors legacy handleDisable(): cancel tasks only, no block restore, no stats.
function M.handleDisable(session)
  session.scheduler.cancelArenaTasks()
end

return M

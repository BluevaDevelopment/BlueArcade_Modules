local blockService = require("support.block_service")
local fallingBlockService = require("support.falling_block_service")
local jumpService = require("support.jump_service")
local loadoutService = require("support.loadout_service")
local messagingService = require("support.messaging_service")
local statsService = require("support.stats_service")

local M = {}

local function isSpectator(session, handle)
  for _, spectator in ipairs(session.spectators()) do
    if spectator == handle then return true end
  end
  return false
end

local function formatCountdownTime(seconds)
  local safe = math.max(0, seconds)
  return string.format("%02d:%02d", math.floor(safe / 60), safe % 60)
end

function M.handleStart(session)
  session.scheduler.cancelArenaTasks()

  session.state = {
    ended = false,
    winnerRecorded = false,
    floors = blockService.loadFloors(session),
    scheduledBlocks = {},
    removedBlocks = {},
    eliminated = {},
    doubleJumps = {},
    lastPlayerPosition = {},
    playerStationaryTicks = {},
    fallingBlocks = {},
    timeLeft = 0,
    maxDoubleJumps = 0,
  }
  session.state.maxDoubleJumps = jumpService.resolveMaxJumps(session)

  messagingService.sendDescription(session)
end

function M.handleCountdownTick(session, secondsLeft)
  messagingService.sendCountdownTick(session, secondsLeft)
end

function M.handleCountdownFinish(session)
  messagingService.sendCountdownFinish(session)
end

function M.freezePlayersOnCountdown()
  return false
end

function M.getCustomPlaceholders(session, handle)
  return {
    alive = tostring(#session.alivePlayers()),
    spectators = tostring(#session.spectators()),
    time = formatCountdownTime(session.state.timeLeft),
    double_jumps = tostring(jumpService.getRemainingJumps(session, handle)),
    double_jumps_max = tostring(session.state.maxDoubleJumps),
  }
end

local function endGameOnce(session)
  local state = session.state
  if state.ended then return end
  state.ended = true

  session.scheduler.cancelArenaTasks()

  local alive = session.alivePlayers()
  if #alive == 1 then
    local winner = alive[1]
    session.setWinner(winner)
    statsService.recordWin(session, winner)
    messagingService.sendVictoryMessage(session, winner)
  end

  session.endGame()
end

local function startGameTimer(session)
  local state = session.state
  local gameTime = session.dataAccess.getGameDataNumber("basic.time")
  if gameTime == nil or gameTime == 0 then
    gameTime = session.config.getInt("gameplay.time_limit_seconds", 300)
  end
  state.timeLeft = math.floor(gameTime)

  local taskId = "arena_" .. session.arenaId .. "_tnt_run_timer"
  session.scheduler.runTimer(taskId, function()
    if state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end

    state.timeLeft = state.timeLeft - 1

    local alivePlayers = session.alivePlayers()
    local allPlayers = session.players()

    if #alivePlayers <= 1 or state.timeLeft <= 0 then
      endGameOnce(session)
      return
    end

    for _, handle in ipairs(allPlayers) do
      local template = session.coreConfig.language(handle, "action_bar.in_game.global")
      if template ~= nil then
        local message = string.gsub(template, "{time}", formatCountdownTime(state.timeLeft))
        message = string.gsub(message, "{round}", tostring(session.currentRound))
        message = string.gsub(message, "{round_max}", tostring(session.maxRounds))
        session.messages.sendActionBar(handle, message)
      end

      local placeholders = M.getCustomPlaceholders(session, handle)
      session.scoreboard.update(handle, "scoreboard.main", placeholders)
    end
  end, 0, 20)
end

function M.handlePlayerElimination(session, handle)
  local state = session.state
  if isSpectator(session, handle) then return end
  if state.eliminated[handle] then return end
  state.eliminated[handle] = true

  messagingService.sendDeathMessage(session, handle)
  session.eliminate(handle, session.config.translation(handle, "messages.eliminated"))
  session.player.clearInventory(handle)

  jumpService.clearJumps(session, handle, false)

  local spawn = session.arena.randomSpawn()
  if spawn ~= nil then
    session.player.teleport(handle, spawn)
  end

  session.setSpectating(handle, true)

  session.scheduler.runLater("arena_" .. session.arenaId .. "_tnt_run_spectator_flight_" .. handle, function()
    if isSpectator(session, handle) then
      session.player.setAllowFlight(handle, true)
      session.player.setFlying(handle, true)
    end
  end, 20)

  session.sounds.play(handle, session.coreConfig.getSound("sounds.in_game.respawn"))
end

local function startTrailScanTimer(session)
  local state = session.state
  local intervalTicks = math.max(1, session.config.getInt("trail.detection.stationary_scan_ticks", 4))
  local taskId = "arena_" .. session.arenaId .. "_tnt_run_trail_scan"

  session.scheduler.runTimer(taskId, function()
    if state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end
    if session.phase() ~= "PLAYING" then return end

    for _, handle in ipairs(session.alivePlayers()) do
      if session.isPlaying(handle) then
        local location = session.player.location(handle)
        if blockService.shouldEliminate(session, location) then
          M.handlePlayerElimination(session, handle)
        else
          blockService.updatePlayerPosition(session, state, handle, location)
          blockService.handlePlayerStep(session, state, handle, location)
        end
      end
    end
  end, 0, intervalTicks)
end

function M.handleGameStart(session)
  local state = session.state
  startGameTimer(session)
  startTrailScanTimer(session)
  blockService.startFloorRemovalTimers(session, state)

  for _, handle in ipairs(session.players()) do
    loadoutService.giveStartingItems(session, handle)
    loadoutService.applyStartingEffects(session, handle)
    jumpService.initializeJumps(session, handle)
    if state.maxDoubleJumps > 0 then
      session.player.setAllowFlight(handle, true)
      session.player.setFlying(handle, false)
    end
    session.scoreboard.show(handle, "scoreboard.main")
  end
end

function M.refreshDoubleJumpState(session, handle)
  local state = session.state
  if session.phase() ~= "PLAYING" then return end
  if not session.isPlaying(handle) then return end
  if isSpectator(session, handle) then return end

  if state.maxDoubleJumps <= 0 then
    session.player.setAllowFlight(handle, false)
    session.player.setFlying(handle, false)
    return
  end

  local remaining = jumpService.getRemainingJumps(session, handle)
  if remaining <= 0 then
    session.player.setAllowFlight(handle, false)
    session.player.setFlying(handle, false)
    return
  end

  if session.player.isOnGround(handle) and not session.player.getAllowFlight(handle) then
    session.player.setAllowFlight(handle, true)
  end
end

function M.handleDoubleJump(session, handle)
  if session.phase() ~= "PLAYING" then return false end
  if not session.isPlaying(handle) then return false end
  if isSpectator(session, handle) then return false end

  if session.player.isOnGround(handle) then return true end

  local jumped = jumpService.performDoubleJump(session, handle)
  if not jumped then
    session.player.setAllowFlight(handle, false)
    session.player.setFlying(handle, false)
    return true
  end

  return true
end

function M.handlePlayerStep(session, handle, to)
  blockService.handlePlayerStep(session, session.state, handle, to)
end

function M.shouldEliminate(session, to)
  return blockService.shouldEliminate(session, to)
end

function M.handleEnd(session)
  session.scheduler.cancelArenaTasks()
  fallingBlockService.cleanupAll(session)
  statsService.recordGamesPlayed(session)
end

return M

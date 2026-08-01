local loadoutService = require("support.loadout_service")
local messagingService = require("support.messaging_service")
local statsService = require("support.stats_service")

local M = {}

local DEFAULT_GAME_TIME = 60

local LIGHT_INDICATORS = { GREEN = "LIME_WOOL", YELLOW = "YELLOW_WOOL", RED = "RED_WOOL" }
local LIGHT_COLORS = {
  GREEN = "<green>██████</green>",
  YELLOW = "<yellow>██████</yellow>",
  RED = "<red>██████</red>",
}

local function formatTime(seconds)
  if seconds < 0 then seconds = 0 end
  return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

function M.isInsideFinishLine(session, location)
  local finishMin = session.dataAccess.getGameLocation("game.finish_line.bounds.min")
  local finishMax = session.dataAccess.getGameLocation("game.finish_line.bounds.max")
  if finishMin == nil or finishMax == nil then return false end

  return location.x >= math.min(finishMin.x, finishMax.x) and location.x <= math.max(finishMin.x, finishMax.x)
      and location.y >= math.min(finishMin.y, finishMax.y) and location.y <= math.max(finishMin.y, finishMax.y)
      and location.z >= math.min(finishMin.z, finishMax.z) and location.z <= math.max(finishMin.z, finishMax.z)
end

local function customPlaceholders(session)
  return {
    light_color = LIGHT_COLORS[session.state.lightState] or LIGHT_COLORS.GREEN,
    light_state = session.state.lightState,
    round = tostring(session.currentRound),
    round_max = tostring(session.maxRounds),
  }
end

function M.getCustomPlaceholders(session, handle)
  return customPlaceholders(session)
end

function M.handlePlayerFinish(session, handle)
  statsService.recordFinishCross(session, handle)

  -- Same real anomaly as race: crossing the finish line never calls session.setWinner(), only
  -- guards the "wins" stat via the arena's own internal winner flag.
  if not session.state.winnerCredited then
    session.state.winnerCredited = true
    statsService.recordWin(session, handle)
  end
end

function M.handlePlayerRespawn(session, handle)
  loadoutService.applyRespawnEffects(session, handle)
end

function M.handlePlayerDeath(session, handle, deathBlock)
  messagingService.handlePlayerDeath(session, handle, deathBlock)
end

function M.broadcastFinish(session, handle, position)
  messagingService.broadcastFinish(session, handle, position)
end

function M.cleanupPlayerState(session, handle)
  session.state.pushbackPrimed[handle] = nil
  session.state.pushbackWindows[handle] = nil
  session.state.redLockedHandles[handle] = nil
end

local function directionFromLocation(loc)
  local yawRad = math.rad(loc.yaw)
  local pitchRad = math.rad(loc.pitch)
  local xz = math.cos(pitchRad)
  return {
    x = -xz * math.sin(yawRad),
    y = -math.sin(pitchRad),
    z = xz * math.cos(yawRad),
  }
end

local function applyPushback(session, handle, from, to, force)
  local dx, dy, dz = from.x - to.x, from.y - to.y, from.z - to.z

  if dx * dx + dy * dy + dz * dz == 0 then
    local direction = directionFromLocation(session.player.location(handle))
    dx, dy, dz = -direction.x, -direction.y, -direction.z
  end

  dy = 0

  if dx * dx + dy * dy + dz * dz == 0 then
    session.player.setVelocity(handle, 0, 0.3, 0)
    return
  end

  local length = math.sqrt(dx * dx + dy * dy + dz * dz)
  session.player.setVelocity(handle, (dx / length) * force, 0.25, (dz / length) * force)
end

local function punishRedMovement(session, handle)
  session.state.redLockedHandles[handle] = true
  session.state.pushbackPrimed[handle] = nil
  session.state.pushbackWindows[handle] = nil

  session.player.setGameMode(handle, "SPECTATOR")
  session.sounds.play(handle, session.coreConfig.getSound("sounds.in_game.dead"))
  messagingService.handleRedLightDeathMessage(session, handle)
end

function M.handleRedLightMovement(session, handle, from, to)
  local isSpectator = false
  for _, spectator in ipairs(session.spectators()) do
    if spectator == handle then isSpectator = true end
  end
  if isSpectator then return end
  if session.state.redLockedHandles[handle] then return end

  local pushbackEnabled = session.config.getBoolean("red_light.pushback.enabled", true)
  local immunityTicks = session.config.getInt("red_light.pushback.immunity_ticks", 15)
  local force = session.config.getDouble("red_light.pushback.force", 1.1)

  if pushbackEnabled then
    -- os.clock() is the sandbox's only sub-second clock - the default immunity window (15 ticks =
    -- 0.75s) would round away to nothing with os.time()'s whole-second precision.
    local now = os.clock()
    local windowEnd = session.state.pushbackWindows[handle]

    if not session.state.pushbackPrimed[handle] then
      applyPushback(session, handle, from, to, force)
      session.state.pushbackPrimed[handle] = true
      session.state.pushbackWindows[handle] = now + (immunityTicks * 50 / 1000)
      messagingService.sendPushbackWarning(session, handle)
      return
    end

    if windowEnd ~= nil and now < windowEnd then
      return
    end
  end

  punishRedMovement(session, handle)
end

local function randomDuration(session, minPath, maxPath, defaultMin, defaultMax)
  local min = session.config.getInt(minPath, defaultMin)
  local max = session.config.getInt(maxPath, defaultMax)
  if min <= 0 then min = defaultMin end
  if max < min then max = min end
  return math.random(min, max)
end

local function giveLightIndicators(session, state)
  local indicator = LIGHT_INDICATORS[state] or "LIME_WOOL"

  for _, handle in ipairs(session.players()) do
    if session.isPlaying(handle) then
      for slot = 0, 35 do
        session.player.giveItem(handle, indicator, 1, slot)
      end
      session.player.setItemInOffHand(handle, indicator)
    end
  end
end

local function clearPushbackState(session)
  session.state.pushbackPrimed = {}
  session.state.pushbackWindows = {}
end

local function respawnRedLockedPlayers(session)
  local handles = {}
  for handle in pairs(session.state.redLockedHandles) do
    handles[#handles + 1] = handle
  end

  for _, handle in ipairs(handles) do
    if session.player.isOnline(handle) then
      if session.isPlaying(handle) then
        session.respawnPlayer(handle)
        session.player.setGameMode(handle, "SURVIVAL")
        loadoutService.applyRespawnEffects(session, handle)
        session.sounds.play(handle, session.coreConfig.getSound("sounds.in_game.respawn"))
      end
      session.state.redLockedHandles[handle] = nil
    end
  end
end

local function switchLight(session)
  local current = session.state.lightState
  local nextState

  if current == "GREEN" then
    nextState = "YELLOW"
    session.state.lightTimer = randomDuration(session, "red_light.durations.yellow.min", "red_light.durations.yellow.max", 1, 3)
  elseif current == "YELLOW" then
    nextState = "RED"
    session.state.lightTimer = randomDuration(session, "red_light.durations.red.min", "red_light.durations.red.max", 1, 8)
  else
    nextState = "GREEN"
    session.state.lightTimer = randomDuration(session, "red_light.durations.green.min", "red_light.durations.green.max", 3, 6)
    respawnRedLockedPlayers(session)
    clearPushbackState(session)
  end

  session.state.lightState = nextState
  giveLightIndicators(session, nextState)
end

local function tickLightCycle(session)
  local newTime = session.state.lightTimer - 1
  if newTime <= 0 then
    switchLight(session)
    return
  end
  session.state.lightTimer = newTime
end

local function updateGameHud(session, timeLeft)
  local alive = session.alivePlayers()
  local spectators = session.spectators()

  for _, handle in ipairs(session.players()) do
    local template = session.coreConfig.language(handle, "action_bar.in_game.global")
    local message = ""
    if template ~= nil then
      message = string.gsub(template, "{time}", formatTime(timeLeft))
      message = string.gsub(message, "{round}", tostring(session.currentRound))
      message = string.gsub(message, "{round_max}", tostring(session.maxRounds))
    end
    session.messages.sendActionBar(handle, message)

    local entries = customPlaceholders(session)
    entries.time = formatTime(timeLeft)
    entries.alive = tostring(#alive)
    entries.spectators = tostring(#spectators)

    session.scoreboard.updateModule(handle, entries)
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
  if #session.spectators() >= math.min(3, allCount) then return true end
  return timeLeft <= 0
end

local function startGameTimer(session)
  local gameTime = session.dataAccess.getGameDataNumber("basic.time")
  if gameTime == nil or gameTime == 0 then gameTime = DEFAULT_GAME_TIME end
  session.state.timeLeft = math.floor(gameTime)

  session.scheduler.runTimer("arena_" .. session.arenaId .. "_traffic_light_timer", function()
    if session.state.ended then
      session.scheduler.cancelTask("arena_" .. session.arenaId .. "_traffic_light_timer")
      return
    end

    session.state.timeLeft = session.state.timeLeft - 1

    if shouldForceEnd(session, session.state.timeLeft) then
      endGameOnce(session)
      return
    end

    tickLightCycle(session)
    updateGameHud(session, session.state.timeLeft)
  end, 20, 20)

  return session.state.timeLeft
end

function M.handleStart(session)
  session.scheduler.cancelArenaTasks()

  session.state = {
    ended = false,
    winnerCredited = false,
    timeLeft = 0,
    lightState = "GREEN",
    lightTimer = 0,
    redLockedHandles = {},
    pushbackPrimed = {},
    pushbackWindows = {},
  }
  session.state.lightTimer = randomDuration(session, "red_light.durations.green.min", "red_light.durations.green.max", 3, 6)

  messagingService.sendDescription(session)
end

function M.handleCountdownTick(session, secondsLeft)
  for _, handle in ipairs(session.players()) do
    session.sounds.play(handle, session.coreConfig.getSound("sounds.starting_game.countdown"))
    local title = string.gsub(session.coreConfig.language(handle, "titles.starting_game.title"), "{game_display_name}", "Traffic Light")
    title = string.gsub(title, "{time}", tostring(secondsLeft))
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.starting_game.subtitle"), "{game_display_name}", "Traffic Light")
    subtitle = string.gsub(subtitle, "{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.handleCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    local title = string.gsub(session.coreConfig.language(handle, "titles.game_started.title"), "{game_display_name}", "Traffic Light")
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.game_started.subtitle"), "{game_display_name}", "Traffic Light")
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 20)
    session.sounds.play(handle, session.coreConfig.getSound("sounds.starting_game.start"))
  end
end

function M.handleGameStart(session)
  local initialTimeLeft = startGameTimer(session)

  for _, handle in ipairs(session.players()) do
    loadoutService.giveStartingItems(session, handle)
    loadoutService.applyStartingEffects(session, handle)
    session.scoreboard.showModule(handle)
  end

  giveLightIndicators(session, session.state.lightState)
  updateGameHud(session, initialTimeLeft)
end

function M.handleEnd(session)
  session.scheduler.cancelArenaTasks()
  for _, handle in ipairs(session.players()) do
    statsService.recordGamePlayed(session, handle)
  end
end

return M

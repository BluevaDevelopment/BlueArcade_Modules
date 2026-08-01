--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local indicatorService = require("support.indicator_service")
local loadoutService = require("support.loadout_service")
local messagingService = require("support.messaging_service")
local statsService = require("support.stats_service")

local M = {}

local function formatCountdownTime(seconds)
  local safe = math.max(0, seconds)
  return string.format("%02d:%02d", math.floor(safe / 60), safe % 60)
end

function M.handleStart(session)
  session.scheduler.cancelArenaTasks()

  session.state = {
    ended = false,
    winnerId = nil,
    roundNumber = 0,
    roundTimeLeft = 0,
    blinkTicks = 0,
    blinkState = false,
    taggedPlayers = {},
    taggedThisRound = {},
    indicatorStoredSlots = {},
  }

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

local function isTagged(session, handle)
  return session.state.taggedPlayers[handle] == true
end

function M.playerCanTag(session, handle)
  return isTagged(session, handle)
end

local function resolveRoundDuration(session)
  local configured = session.dataAccess.getGameDataNumber("basic.time")
  if configured == nil or configured <= 0 then
    configured = session.config.getInt("round.default_seconds", 15)
  else
    configured = math.floor(configured)
  end

  local convert = session.config.getBoolean("round.convert_setup_time_from_minutes", true)
  local threshold = math.max(1, session.config.getInt("round.minutes_conversion_minimum_seconds", 60))
  if convert and configured >= threshold and configured % 60 == 0 then
    configured = math.max(1, math.floor(configured / 60))
  end

  return math.max(1, configured)
end

local function calculateTaggedPlayers(session, playerCount)
  local rules = session.config.getStringList("tagging.tagged_players.rules")
  local fallback = math.max(1, session.config.getInt("tagging.tagged_players.fallback", 1))

  for _, rule in ipairs(rules) do
    local range, taggedStr = rule:match("^([^:]+):(%-?%d+)$")
    if range ~= nil then
      local tagged = tonumber(taggedStr)
      if tagged ~= nil then
        if range:find("+", 1, true) then
          local min = tonumber((range:gsub("%+", "")))
          if min ~= nil and playerCount >= min then return tagged end
        elseif range:find("-", 1, true) then
          local minStr, maxStr = range:match("^(%d+)-(%d+)$")
          local min, max = tonumber(minStr), tonumber(maxStr)
          if min ~= nil and max ~= nil and playerCount >= min and playerCount <= max then
            return tagged
          end
        end
      end
    end
  end

  return fallback
end

local function handleTaggedStatusChange(session, handle, tagged)
  if tagged then
    session.messages.sendRaw(handle, session.config.translation(handle, "messages.you_have_tnt"))
    loadoutService.applyTaggedState(session, handle)
    indicatorService.applyIndicator(session, handle, session.state.blinkState)
    return
  end

  session.messages.sendRaw(handle, session.config.translation(handle, "messages.you_no_have_tnt"))
  loadoutService.applyUntaggedState(session, handle)
  indicatorService.clearIndicator(session, handle)
end

local function selectTaggedPlayers(session)
  local state = session.state
  local alivePlayers = {}
  for _, handle in ipairs(session.alivePlayers()) do
    alivePlayers[#alivePlayers + 1] = handle
  end
  if #alivePlayers == 0 then return end

  -- Fisher-Yates shuffle, matching Collections.shuffle's real "any permutation" intent.
  for i = #alivePlayers, 2, -1 do
    local j = math.random(i)
    alivePlayers[i], alivePlayers[j] = alivePlayers[j], alivePlayers[i]
  end

  local taggedCount = math.min(#alivePlayers, calculateTaggedPlayers(session, #alivePlayers))
  for i = 1, taggedCount do
    local handle = alivePlayers[i]
    state.taggedPlayers[handle] = true
    state.taggedThisRound[handle] = true
    handleTaggedStatusChange(session, handle, true)
  end
end

local function getTaggedPlayerNames(session)
  local names = {}
  for _, handle in ipairs(session.players()) do
    if session.state.taggedPlayers[handle] then
      names[#names + 1] = session.player.name(handle)
    end
  end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  return names
end

function M.getCustomPlaceholders(session, handle)
  local state = session.state
  local placeholders = {
    alive = tostring(#session.alivePlayers()),
    spectators = tostring(#session.spectators()),
    round = tostring(state.roundNumber),
    time = formatCountdownTime(state.roundTimeLeft),
    total_players = tostring(#session.players()),
  }

  local taggedNames = getTaggedPlayerNames(session)
  local none = session.config.translation(handle, "placeholders.none") or "None"
  for i = 1, 5 do
    placeholders["tnt_holder_" .. i] = taggedNames[i] or none
  end

  return placeholders
end

local function applySmokeWarning(session, timeLeft)
  if not session.config.getBoolean("round.smoke_warning.enabled", true) then return end
  local atSeconds = session.config.getInt("round.smoke_warning.seconds", 4)
  if timeLeft > atSeconds then return end

  local particle = session.config.getString("round.smoke_warning.particle") or "SMOKE"
  local count = session.config.getInt("round.smoke_warning.count", 8)
  local offset = session.config.getDouble("round.smoke_warning.offset", 0.3)

  for _, handle in ipairs(session.alivePlayers()) do
    if isTagged(session, handle) then
      local location = session.player.location(handle)
      location.y = location.y + 0.9
      if not session.world.spawnParticleAt(location, particle, count, offset, offset, offset, 0.02) then
        session.world.spawnParticleAt(location, "CLOUD", count, offset, offset, offset, 0.02)
      end
    end
  end
end

local function sendHudUpdates(session, timeLeft)
  local aliveCount = #session.alivePlayers()
  local spectatorsCount = #session.spectators()

  for _, handle in ipairs(session.players()) do
    local actionBarTemplate = session.coreConfig.language(handle, "action_bar.in_game.global")
    local placeholders = M.getCustomPlaceholders(session, handle)
    placeholders.time = formatCountdownTime(timeLeft)
    placeholders.alive = tostring(aliveCount)
    placeholders.spectators = tostring(spectatorsCount)

    if actionBarTemplate ~= nil then
      local message = string.gsub(actionBarTemplate, "{time}", formatCountdownTime(timeLeft))
      message = string.gsub(message, "{round}", tostring(session.state.roundNumber))
      message = string.gsub(message, "{round_max}", tostring(session.maxRounds))
      session.messages.sendActionBar(handle, message)
    end

    session.scoreboard.update(handle, "scoreboard.main", placeholders)
  end

  applySmokeWarning(session, timeLeft)
end

function M.finishGameIfPossible(session)
  local state = session.state
  if state.ended then return end
  state.ended = true

  session.scheduler.cancelArenaTasks()

  local alive = session.alivePlayers()
  if #alive == 1 then
    local winner = alive[1]
    if state.winnerId == nil then
      state.winnerId = winner
      session.setWinner(winner)
      statsService.recordWin(session, winner)
    end
  end

  session.endGame()
end

local function resetTags(session)
  session.state.taggedPlayers = {}
  session.state.taggedThisRound = {}
end

local function beginNextRound(session)
  local state = session.state
  state.roundNumber = state.roundNumber + 1
  state.roundTimeLeft = resolveRoundDuration(session)
  state.blinkTicks = 0
  state.blinkState = false
  resetTags(session)

  selectTaggedPlayers(session)
  messagingService.announceNewRound(session, state.roundNumber)

  sendHudUpdates(session, state.roundTimeLeft)
end

local function awardSurvivalStats(session, currentTagged)
  local state = session.state
  for _, handle in ipairs(session.alivePlayers()) do
    if not currentTagged[handle] then
      statsService.recordSurvival(session, handle)
      if state.taggedThisRound[handle] then
        statsService.recordEscape(session, handle)
      end
    end
  end
end

local function detonateTaggedPlayers(session, currentTagged)
  for _, handle in ipairs(session.alivePlayers()) do
    if currentTagged[handle] then
      indicatorService.clearIndicator(session, handle)
      loadoutService.clearTransitionEffects(session, handle)
      session.messages.sendRaw(handle, session.config.translation(handle, "messages.detonated"))
      session.sounds.play(handle, session.coreConfig.getSound("sounds.in_game.dead"))

      local location = session.player.location(handle)
      location.y = location.y + 1
      local particleCount = session.config.getInt("explosion.particle_count", 6)
      if not session.world.spawnParticleAt(location, "EXPLOSION", particleCount, 0.35, 0.35, 0.35, 0.02) then
        session.world.spawnParticleAt(location, "CLOUD", particleCount, 0.35, 0.35, 0.35, 0.02)
      end

      session.eliminate(handle, session.config.translation(handle, "messages.eliminated"))
      session.player.clearInventory(handle)
      session.setSpectating(handle, true)
    end
  end

  sendHudUpdates(session, session.state.roundTimeLeft)
  resetTags(session)
end

local function handleRoundExpiration(session)
  local state = session.state
  local currentTagged = {}
  for handle in pairs(state.taggedPlayers) do
    currentTagged[handle] = true
  end

  awardSurvivalStats(session, currentTagged)
  detonateTaggedPlayers(session, currentTagged)

  if #session.alivePlayers() <= 1 then
    M.finishGameIfPossible(session)
    return
  end

  beginNextRound(session)
end

local function handleGameTick(session)
  local state = session.state
  if state.ended then
    session.scheduler.cancelTask("arena_" .. session.arenaId .. "_tnt_tag_timer")
    return
  end

  state.roundTimeLeft = state.roundTimeLeft - 1

  if #session.alivePlayers() <= 1 then
    M.finishGameIfPossible(session)
    return
  end

  if state.roundTimeLeft <= 0 then
    handleRoundExpiration(session)
    return
  end

  sendHudUpdates(session, state.roundTimeLeft)
end

local function updateIndicators(session)
  local state = session.state
  if state.ended then
    session.scheduler.cancelTask("arena_" .. session.arenaId .. "_tnt_tag_indicator")
    return
  end

  local maxTicks = math.max(1, session.config.getInt("tagging.inventory_indicator.blink.max_ticks", 10))
  local minTicks = math.max(1, session.config.getInt("tagging.inventory_indicator.blink.min_ticks", 2))
  local criticalSeconds = math.max(1, session.config.getInt("tagging.inventory_indicator.critical_seconds", 5))

  local normalized = math.min(state.roundTimeLeft, criticalSeconds) / criticalSeconds
  local interval = math.floor(minTicks + (maxTicks - minTicks) * normalized + 0.5)
  interval = math.max(minTicks, math.min(maxTicks, interval))

  state.blinkTicks = state.blinkTicks + 1
  if state.blinkTicks >= interval then
    state.blinkTicks = 0
    state.blinkState = not state.blinkState
  end

  for _, handle in ipairs(session.alivePlayers()) do
    if isTagged(session, handle) then
      indicatorService.applyIndicator(session, handle, state.blinkState)
    end
  end
end

function M.handleGameStart(session)
  for _, handle in ipairs(session.players()) do
    loadoutService.prepareForStart(session, handle)
    session.scoreboard.show(handle, "scoreboard.main")
  end

  beginNextRound(session)

  local timerTaskId = "arena_" .. session.arenaId .. "_tnt_tag_timer"
  session.scheduler.runTimer(timerTaskId, function() handleGameTick(session) end, 0, 20)

  local indicatorRate = math.max(1, session.config.getInt("tagging.inventory_indicator.tick_rate", 5))
  local indicatorTaskId = "arena_" .. session.arenaId .. "_tnt_tag_indicator"
  session.scheduler.runTimer(indicatorTaskId, function() updateIndicators(session) end, 0, indicatorRate)
end

function M.passTNT(session, from, to)
  local state = session.state
  if state.ended then return end
  if not state.taggedPlayers[from] then return end
  if from == to then return end
  if state.taggedPlayers[to] then return end

  state.taggedPlayers[from] = nil
  handleTaggedStatusChange(session, from, false)

  state.taggedPlayers[to] = true
  state.taggedThisRound[to] = true
  handleTaggedStatusChange(session, to, true)

  statsService.recordTag(session, from)
  messagingService.broadcastTaggedHolder(session, to)
end

function M.handleEnd(session)
  session.scheduler.cancelArenaTasks()
  statsService.recordGamesPlayed(session)
  for _, handle in ipairs(session.players()) do
    indicatorService.clearIndicator(session, handle)
    loadoutService.clearTransitionEffects(session, handle)
  end
end

-- Mirrors legacy TNTTagGameManager.onDisable(): cancel tasks and clear indicators, no stats/transition-effects reset.
function M.handleDisableCleanup(session)
  session.scheduler.cancelArenaTasks()
  indicatorService.clearAllIndicators(session)
end

return M

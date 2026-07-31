-- Mirrors legacy SkyWarsGame.java - the top-level per-match orchestration. ArenaState.java isn't a
-- separate file - it's a plain session.state table, same convention as every other converted
-- module. Team spawn/cage handling reuses lucky_pillars' own pattern (no JSON-migration-to-disk
-- fallback, same documented simplification - disabledRequirements=["SPAWNS"] means a properly
-- configured arena always has team spawns).
local combatService = require("support.combat_service")
local outcomeService = require("support.outcome_service")
local loadoutService = require("support.loadout_service")
local lootService = require("support.loot_service")
local stormService = require("support.storm_service")
local spawnCageService = require("support.spawn_cage_service")
local voteService = require("support.vote_service")
local descriptionService = require("support.description_service")
local placeholderService = require("support.placeholder_service")

local M = {}

local CAGE_GUARD_MAX_DISTANCE_SQUARED = 2.25

local function newState()
  return {
    ended = false,
    matchSeconds = 0,
    winnerId = nil,
    kills = {},

    trackedChests = {},
    chestRefillTimes = {},
    playerPlacedBlocks = {},

    teamSpawns = {},
    cageBlocks = {},
    cagedPlayers = {},
    cagedSpawnKeys = {},

    fallProtectionUntil = {},

    voteState = nil,
    selectedChestTier = nil,
    selectedHearts = nil,
    selectedTime = nil,
    selectedWeather = nil,

    scheduledEvents = {},
    nextEventIndex = 1,
    nextEvent = nil,

    stormActive = false,
    stormCenter = nil,
    stormRadius = 0,
    stormMaxRadius = 0,
    stormFinalRadius = 0,
    stormShrinkDurationSeconds = 0,
    stormDamagePerSecond = 0,
    stormLightningTicks = 0,

    countdownPrepared = {},
  }
end

local function formatCountdownTime(seconds)
  local safe = math.max(0, seconds)
  return string.format("%02d:%02d", math.floor(safe / 60), safe % 60)
end

local function centerSpawnLocation(spawn)
  return { x = math.floor(spawn.x) + 0.5, y = spawn.y, z = math.floor(spawn.z) + 0.5, yaw = spawn.yaw, pitch = spawn.pitch }
end

local function resolveDataBasePath(session, section)
  if session.dataAccess.hasGameData("game.play_area." .. section) then
    return "game.play_area." .. section
  end
  return "game." .. section
end

local function loadTeamSpawns(session)
  if not session.teams.isEnabled() then
    return
  end

  local spawnBase = resolveDataBasePath(session, "team_spawns")
  local teamIndex = 1
  for _, team in ipairs(session.teams.all()) do
    local teamId = team.id
    if teamId and teamId ~= "" then
      teamId = teamId:lower()
      local canonicalPath = spawnBase .. "." .. teamId
      local numericPath = spawnBase .. "." .. teamIndex

      local resolvedPath = nil
      if session.dataAccess.hasGameData(canonicalPath) then
        resolvedPath = canonicalPath
      elseif session.dataAccess.hasGameData(numericPath) then
        resolvedPath = numericPath
      end

      if resolvedPath then
        local spawn = session.dataAccess.getGameLocation(resolvedPath)
        if spawn then
          session.state.teamSpawns[teamId] = spawn
        end
      end
    end
    teamIndex = teamIndex + 1
  end
end

local function teleportToTeamSpawn(session, handle)
  if not session.teams.isEnabled() then
    return
  end
  local team = session.teams.forPlayer(handle)
  if not team then
    return
  end
  local spawn = session.state.teamSpawns[team.id:lower()]
  if not spawn then
    return
  end
  session.player.teleport(handle, centerSpawnLocation(spawn))
end

local function scheduleSpawnCages(session)
  local taskId = "arena_" .. session.arenaId .. "_skywars_cages"
  local ticks = 0
  local maxTicks = 40
  session.scheduler.runTimer(taskId, function()
    spawnCageService.buildCages(session)
    ticks = ticks + 1

    local cagedCount = 0
    for _ in pairs(session.state.cagedPlayers) do
      cagedCount = cagedCount + 1
    end
    if ticks >= maxTicks or cagedCount >= #session.players() then
      session.scheduler.cancelTask(taskId)
    end
  end, 1, 1)
end

local function scheduleCageGuard(session)
  local taskId = "arena_" .. session.arenaId .. "_skywars_cage_guard"
  session.scheduler.runTimer(taskId, function()
    if not session.teams.isEnabled() then
      return
    end
    for _, handle in ipairs(session.players()) do
      local team = session.teams.forPlayer(handle)
      if team then
        local spawn = session.state.teamSpawns[team.id:lower()]
        if spawn then
          local playerLoc = session.player.location(handle)
          local dx, dy, dz = playerLoc.x - spawn.x, playerLoc.y - spawn.y, playerLoc.z - spawn.z
          if dx * dx + dy * dy + dz * dz > CAGE_GUARD_MAX_DISTANCE_SQUARED then
            session.player.teleport(handle, centerSpawnLocation(spawn))
          end
        end
      end
    end
  end, 10, 10)
end

local function parseScheduledEvent(session, raw)
  local secondsStr, eventType, label = raw:match("^(%d+):([%u_]+):(.*)$")
  if not secondsStr or not eventType then
    return nil
  end
  if eventType == "STORM" and not session.config.getBoolean("storm.enabled", true) then
    return nil
  end
  if eventType == "CHEST_REFILL" and not session.config.getBoolean("loot.refill.enabled", true) then
    return nil
  end
  return { triggerSeconds = tonumber(secondsStr), type = eventType, label = label }
end

local function loadScheduledEvents(session)
  local events = {}
  for _, raw in ipairs(session.config.getStringList("events.schedule")) do
    local event = parseScheduledEvent(session, raw)
    if event then
      events[#events + 1] = event
    end
  end
  table.sort(events, function(a, b) return a.triggerSeconds < b.triggerSeconds end)
  session.state.scheduledEvents = events
  session.state.nextEventIndex = 1
  session.state.nextEvent = events[1]
end

local function broadcastEventMessage(session, path)
  local message = session.config.translation(nil, path)
  if not message or message == "" then
    return
  end
  for _, handle in ipairs(session.players()) do
    session.messages.sendRaw(handle, message)
  end
end

local function triggerEvent(session, event)
  if event.type == "CHEST_REFILL" then
    lootService.forceRefillChests(session)
    broadcastEventMessage(session, "messages.events.chest_refill")
  elseif event.type == "STORM" then
    session.state.stormActive = true
    stormService.initializeStorm(session)
    broadcastEventMessage(session, "messages.events.storm_started")
  end
end

local function handleScheduledEvents(session)
  local events = session.state.scheduledEvents
  local index = session.state.nextEventIndex
  while events[index] and events[index].triggerSeconds <= session.state.matchSeconds do
    triggerEvent(session, events[index])
    index = index + 1
  end
  session.state.nextEventIndex = index
  session.state.nextEvent = events[index]
end

function M.startGame(session)
  session.state = newState()
  session.scheduler.cancelArenaTasks()

  session.state.voteState = voteService.createVoteState()
  voteService.applyPendingVotes(session)

  loadTeamSpawns(session)
  loadScheduledEvents(session)

  for _, handle in ipairs(session.players()) do
    session.state.kills[handle] = 0
    if session.teams.isEnabled() and not session.teams.forPlayer(handle) then
      session.teams.autoAssign(handle)
    end
  end

  for _, handle in ipairs(session.players()) do
    teleportToTeamSpawn(session, handle)
  end

  scheduleSpawnCages(session)
  scheduleCageGuard(session)
  descriptionService.sendDescription(session)
end

function M.handleCountdownTick(session, secondsLeft)
  for _, handle in ipairs(session.players()) do
    session.sounds.play(handle, "sounds.starting_game.countdown")
    local title = (session.coreConfig.language(handle, "titles.starting_game.title") or "")
      :gsub("{game_display_name}", "SkyWars"):gsub("{time}", tostring(secondsLeft))
    local subtitle = (session.coreConfig.language(handle, "titles.starting_game.subtitle") or "")
      :gsub("{game_display_name}", "SkyWars"):gsub("{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.handleCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    local title = (session.coreConfig.language(handle, "titles.game_started.title") or ""):gsub("{game_display_name}", "SkyWars")
    local subtitle = (session.coreConfig.language(handle, "titles.game_started.subtitle") or ""):gsub("{game_display_name}", "SkyWars")
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 20)
    session.sounds.play(handle, "sounds.starting_game.start")
  end
end

function M.isSoloMode(session)
  if not session.teams.isEnabled() then
    return true
  end
  if session.teams.teamSize() <= 1 then
    return true
  end
  return session.teams.teamCount() <= 1
end

local function getScoreboardPath(session)
  return M.isSoloMode(session) and "scoreboard.solo" or "scoreboard.default"
end

function M.getAliveTeamIds(session)
  if not session.teams.isEnabled() then
    if #session.alivePlayers() > 0 then
      return { "solo" }
    end
    return {}
  end

  local seen = {}
  local ids = {}
  for _, handle in ipairs(session.alivePlayers()) do
    local team = session.teams.forPlayer(handle)
    if team and not seen[team.id] then
      seen[team.id] = true
      ids[#ids + 1] = team.id
    end
  end
  return ids
end

function M.getPlayerKills(session, handle)
  return session.state.kills[handle] or 0
end

function M.addPlayerKill(session, handle)
  session.state.kills[handle] = M.getPlayerKills(session, handle) + 1
end

function M.getTeamKills(session)
  local teamKills = {}
  for _, handle in ipairs(session.players()) do
    local kills = M.getPlayerKills(session, handle)
    local teamId = "solo"
    if session.teams.isEnabled() then
      local team = session.teams.forPlayer(handle)
      if team then
        teamId = team.id
      end
    end
    teamKills[teamId] = (teamKills[teamId] or 0) + kills
  end
  return teamKills
end

function M.getTeamPlayers(session, teamId)
  local players = {}
  for _, handle in ipairs(session.alivePlayers()) do
    if not session.teams.isEnabled() then
      players[#players + 1] = handle
    else
      local team = session.teams.forPlayer(handle)
      if team and team.id:lower() == teamId:lower() then
        players[#players + 1] = handle
      end
    end
  end
  return players
end

local function shouldEndForVictory(session)
  if session.teams.isEnabled() then
    return #M.getAliveTeamIds(session) <= 1
  end
  return #session.alivePlayers() <= 1
end

function M.checkForTeamVictory(session)
  if session.state.ended then
    return
  end
  if shouldEndForVictory(session) then
    M.endGame(session)
  end
end

function M.endGame(session)
  outcomeService.endGame(session, M)
end

function M.handleKill(session, attackerHandle, victimHandle)
  combatService.handleKillCredit(session, M, attackerHandle)
  combatService.handleElimination(session, victimHandle, attackerHandle)
  M.checkForTeamVictory(session)
end

function M.handleNonCombatDeath(session, victimHandle)
  combatService.handleElimination(session, victimHandle, nil)
  M.checkForTeamVictory(session)
end

local function blockKey(x, y, z)
  return x .. ":" .. y .. ":" .. z
end

function M.isPlayerPlacedBlock(session, x, y, z)
  return session.state.playerPlacedBlocks[blockKey(x, y, z)] == true
end

function M.trackPlacedBlock(session, x, y, z)
  session.state.playerPlacedBlocks[blockKey(x, y, z)] = true
end

function M.untrackPlacedBlock(session, x, y, z)
  session.state.playerPlacedBlocks[blockKey(x, y, z)] = nil
end

local function registerFallProtection(session, handle, protectionSeconds)
  if protectionSeconds <= 0 then
    return
  end
  session.state.fallProtectionUntil[handle] = os.clock() + protectionSeconds
end

local function refreshFallProtection(session, protectionSeconds)
  if protectionSeconds <= 0 then
    return
  end
  for _, handle in ipairs(session.players()) do
    if not session.state.fallProtectionUntil[handle] and session.state.matchSeconds == 1 then
      session.state.fallProtectionUntil[handle] = os.clock() + protectionSeconds
    end
  end
end

local function startGameTimer(session)
  local fallProtectionSeconds = math.max(0, session.config.getInt("spawn_protection.fall_damage_seconds", 5))
  local gameTime = session.config.getInt("game.time_limit_seconds", 0)
  local hasTimeLimit = gameTime > 0
  local timeLeft = gameTime
  local taskId = "arena_" .. session.arenaId .. "_skywars_timer"

  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end

    session.state.matchSeconds = session.state.matchSeconds + 1
    refreshFallProtection(session, fallProtectionSeconds)
    handleScheduledEvents(session)

    if session.state.stormActive then
      stormService.tickStorm(session)
    end

    if hasTimeLimit and timeLeft > 0 then
      timeLeft = timeLeft - 1
      if timeLeft <= 0 then
        M.endGame(session)
        return
      end
    end

    if shouldEndForVictory(session) then
      M.endGame(session)
      return
    end

    local alivePlayers = session.alivePlayers()
    for _, handle in ipairs(session.players()) do
      local actionBarTemplate = session.coreConfig.language(handle, "action_bar.in_game.global")
      local placeholders = placeholderService.buildPlaceholders(session, handle, M)
      if hasTimeLimit and timeLeft > 0 then
        placeholders.time = formatCountdownTime(timeLeft)
      end
      placeholders.alive = tostring(#alivePlayers)
      placeholders.spectators = tostring(#session.spectators())

      if actionBarTemplate and hasTimeLimit then
        local actionBarMessage = actionBarTemplate
          :gsub("{time}", formatCountdownTime(timeLeft))
          :gsub("{round}", tostring(session.currentRound))
          :gsub("{round_max}", tostring(session.maxRounds))
        session.messages.sendActionBar(handle, actionBarMessage)
      end

      session.scoreboard.update(handle, getScoreboardPath(session), placeholders)
    end
  end, 0, 20)
end

function M.beginPlaying(session)
  voteService.applyVotes(session)

  local fallProtectionSeconds = math.max(0, session.config.getInt("spawn_protection.fall_damage_seconds", 5))
  for _, handle in ipairs(session.players()) do
    session.player.setGameMode(handle, "SURVIVAL")
    loadoutService.restoreVitals(session, handle)
    loadoutService.giveStartingItems(session, handle)
    loadoutService.applySelectedKit(session, handle)
    loadoutService.applyStartingEffects(session, handle)
    registerFallProtection(session, handle, fallProtectionSeconds)
    session.scoreboard.show(handle, getScoreboardPath(session))
  end

  session.scheduler.cancelTask("arena_" .. session.arenaId .. "_skywars_cage_guard")
  spawnCageService.removeCages(session)
  voteService.broadcastVoteResults(session)

  lootService.startChestRefills(session)
  startGameTimer(session)
end

function M.finishGame(session)
  session.scheduler.cancelArenaTasks()
  spawnCageService.removeCages(session)
  lootService.restoreChests(session)
  stormService.clearWorldBorder(session)

  session.world.setTime(1000)
  session.world.setStorm(false)
  session.world.setThundering(false)

  for _, handle in ipairs(session.players()) do
    session.player.resetMaxHealth(handle)
    session.player.setHealth(handle, session.player.health(handle))
  end

  for _, handle in ipairs(session.players()) do
    session.stats.add(handle, "games_played", 1)
  end
end

function M.getCustomPlaceholders(session, handle)
  return placeholderService.buildPlaceholders(session, handle, M)
end

return M

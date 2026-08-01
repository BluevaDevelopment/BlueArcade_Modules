-- listener.lua calls support.drop_service/loot_service directly - legacy's own game-class
-- pass-throughs existed only for a null-arena-state check session.state doesn't need.
local combatService = require("support.combat_service")
local outcomeService = require("support.outcome_service")
local loadoutService = require("support.loadout_service")
local lootService = require("support.loot_service")
local stormService = require("support.storm_service")
local dropService = require("support.drop_service")
local descriptionService = require("support.description_service")
local placeholderService = require("support.placeholder_service")

local M = {}

local function newState()
  return {
    ended = false,
    winnerId = nil,
    kills = {},

    stormStageIndex = 0,
    stormNextStageIndex = 0,
    stormPhaseTicks = 0,
    stormPhaseDuration = 0,
    stormMoving = false,
    stormRadius = 0,
    stormMaxRadius = 0,
    stormCenter = nil,
    stormLightningTicks = 0,

    dropVehicle = nil,
    planeDisplays = {},
    droppingPlayers = {},
    dropInvisiblePlayers = {},
    planePlayers = {},
    planeExitReleaseRequired = {},
    planeBoardedAt = {},
    storedChestplates = {},

    lootedChests = {},
    trackedChests = {},
    playerPlacedBlocks = {},

    gracePeriodUntilClock = nil,
    gracePeriodEnded = true,

    respawnRegionCheckResult = nil,
    countdownPrepared = {},
  }
end

local function formatCountdownTime(seconds)
  local safe = math.max(0, seconds)
  return string.format("%02d:%02d", math.floor(safe / 60), safe % 60)
end

function M.hasRespawnRegion(session)
  if session.state.respawnRegionCheckResult == nil then
    session.state.respawnRegionCheckResult = session.dataAccess.hasGameData("game.play_area.bounds.min.x")
      and session.dataAccess.hasGameData("game.play_area.bounds.min.y")
      and session.dataAccess.hasGameData("game.play_area.bounds.min.z")
      and session.dataAccess.hasGameData("game.play_area.bounds.max.x")
      and session.dataAccess.hasGameData("game.play_area.bounds.max.y")
      and session.dataAccess.hasGameData("game.play_area.bounds.max.z")
  end
  return session.state.respawnRegionCheckResult
end

local function resolveCountdownSpectatorLocation(session)
  local min = session.arena.boundsMin()
  local max = session.arena.boundsMax()
  if not min or not max then
    return nil
  end

  local minY = math.min(min.y, max.y)
  local maxY = math.max(min.y, max.y)
  local centerX = (min.x + max.x) / 2.0
  local centerZ = (min.z + max.z) / 2.0
  local minAllowedY = minY + 1.0
  local maxAllowedY = maxY - 1.0
  local preferredY = maxY - 2.0
  local centerY
  if maxAllowedY >= minAllowedY then
    centerY = math.max(minAllowedY, math.min(preferredY, maxAllowedY))
  else
    centerY = (minY + maxY) / 2.0
  end

  return { x = centerX, y = centerY, z = centerZ, yaw = 0.0, pitch = 60.0 }
end

function M.startGame(session)
  session.state = newState()
  session.scheduler.cancelArenaTasks()

  for _, handle in ipairs(session.players()) do
    session.state.kills[handle] = 0
    if session.teams.isEnabled() and not session.teams.forPlayer(handle) then
      session.teams.autoAssign(handle)
    end
  end

  descriptionService.sendDescription(session)
end

function M.handleCountdownTick(session, secondsLeft)
  local countdownView = resolveCountdownSpectatorLocation(session)

  for _, handle in ipairs(session.players()) do
    if countdownView and not session.state.countdownPrepared[handle] then
      session.state.countdownPrepared[handle] = true
      session.player.teleport(handle, countdownView)
      session.player.setGameMode(handle, "SPECTATOR")
    end

    session.sounds.play(handle, "sounds.starting_game.countdown")
    local title = (session.coreConfig.language(handle, "titles.starting_game.title") or "")
      :gsub("{game_display_name}", "Battle Royale"):gsub("{time}", tostring(secondsLeft))
    local subtitle = (session.coreConfig.language(handle, "titles.starting_game.subtitle") or "")
      :gsub("{game_display_name}", "Battle Royale"):gsub("{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.handleCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    local title = (session.coreConfig.language(handle, "titles.game_started.title") or ""):gsub("{game_display_name}", "Battle Royale")
    local subtitle = (session.coreConfig.language(handle, "titles.game_started.subtitle") or ""):gsub("{game_display_name}", "Battle Royale")
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
  for _, handle in ipairs(session.players()) do
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

function M.getPlayersSortedByKills(session, candidates, limit)
  local entries = {}
  for _, handle in ipairs(candidates) do
    entries[#entries + 1] = { handle = handle, kills = M.getPlayerKills(session, handle) }
  end
  table.sort(entries, function(a, b)
    if a.kills ~= b.kills then
      return a.kills > b.kills
    end
    return session.player.name(a.handle):lower() < session.player.name(b.handle):lower()
  end)

  local ordered = {}
  for i, entry in ipairs(entries) do
    if i > limit then
      break
    end
    ordered[#ordered + 1] = entry.handle
  end
  return ordered
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
  combatService.handleKillCredit(session, attackerHandle)
  combatService.handleElimination(session, victimHandle, attackerHandle)
  M.checkForTeamVictory(session)
end

function M.handleNonCombatDeath(session, victimHandle)
  combatService.handleElimination(session, victimHandle, nil)
  M.checkForTeamVictory(session)
end

local function broadcastGraceMessage(session, path, seconds)
  for _, handle in ipairs(session.players()) do
    local message = session.config.translation(handle, path)
    if message and message ~= "" then
      session.messages.sendRaw(handle, message:gsub("{seconds}", tostring(seconds)))
    end
  end
end

local function startGameTimer(session)
  local gameTime = session.config.getInt("game.time_limit_seconds", 0)
  local hasTimeLimit = gameTime > 0
  local timeLeft = gameTime
  local taskId = "arena_" .. session.arenaId .. "_battle_royale_timer"

  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end

    stormService.tickStorm(session)

    if not (session.state.gracePeriodUntilClock and os.clock() < session.state.gracePeriodUntilClock)
        and not session.state.gracePeriodEnded then
      session.state.gracePeriodEnded = true
      broadcastGraceMessage(session, "messages.grace_period.ended", 0)
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
  for _, handle in ipairs(session.players()) do
    session.player.setGameMode(handle, "SURVIVAL")
    loadoutService.restoreVitals(session, handle)
    loadoutService.giveStartingItems(session, handle)
    loadoutService.applyStartingEffects(session, handle)
    session.scoreboard.show(handle, getScoreboardPath(session))
  end

  local graceSeconds = math.max(0, session.config.getInt("game.grace_period_seconds", 60))
  if graceSeconds > 0 then
    session.state.gracePeriodUntilClock = os.clock() + graceSeconds
    session.state.gracePeriodEnded = false
    broadcastGraceMessage(session, "messages.grace_period.started", graceSeconds)
  else
    session.state.gracePeriodUntilClock = nil
    session.state.gracePeriodEnded = true
  end

  stormService.initializeStorm(session)
  startGameTimer(session)
  dropService.startDrop(session)
end

function M.finishGame(session)
  session.scheduler.cancelArenaTasks()
  lootService.restoreChests(session)
  dropService.cleanup(session)
  stormService.clearWorldBorder(session)

  for _, handle in ipairs(session.players()) do
    session.stats.add(handle, "games_played", 1)
  end
end

function M.getCustomPlaceholders(session, handle)
  return placeholderService.buildPlaceholders(session, handle, M)
end

return M

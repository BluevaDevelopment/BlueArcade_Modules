--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy CaptureTheWoolGame.java; ArenaState.java folded into session.state. isSoloMode is dead code in legacy, not ported.
-- Reads "wools.carrier_hologram_update_ticks" (the real settings.yml key) - legacy's own read used the wrong key ("wool.") and always fell back to its default, a harmless legacy bug fixed here.
local combatService = require("support.combat_service")
local outcomeService = require("support.outcome_service")
local woolService = require("support.wool_service")
local loadoutService = require("support.loadout_service")
local descriptionService = require("support.description_service")
local placeholderService = require("support.placeholder_service")
local voteService = require("support.vote_service")

local M = {}

local function newState()
  return {
    ended = false,
    matchSeconds = 0,
    winnerId = nil,
    kills = {},
    deaths = {},
    teamSpawns = {},
    teamRestrictedZones = {},
    fallProtectionUntil = {},
    playerPlacedBlocks = {},
    countdownPrepared = {},
    voteState = nil,
    selectedHearts = 10,
    selectedTime = "day",
    selectedWeather = "sunny",
    woolDefinitions = {},
    woolStates = {},
    woolCarriers = {},
    woolCapturers = {},
    woolHolograms = {},
    carrierHolograms = {},
  }
end

local function applyVoteDefaults(session)
  session.state.selectedHearts = session.config.getInt("votes.defaults.hearts", 10)
  session.state.selectedTime = session.config.getString("votes.defaults.time") or "day"
  session.state.selectedWeather = session.config.getString("votes.defaults.weather") or "sunny"
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

local function loadTeamRestrictedZones(session)
  if not session.teams.isEnabled() then
    return
  end
  local zonesBase = resolveDataBasePath(session, "restricted_zones")
  local teamIndex = 1
  for _, team in ipairs(session.teams.all()) do
    local teamId = team.id
    if teamId and teamId ~= "" then
      teamId = teamId:lower()
      for i = 1, 10 do
        local canonicalBasePath = zonesBase .. "." .. teamId .. "." .. i
        local numericBasePath = zonesBase .. "." .. teamIndex .. "." .. i
        local resolvedBasePath = nil
        if session.dataAccess.hasGameData(canonicalBasePath .. ".min") then
          resolvedBasePath = canonicalBasePath
        elseif session.dataAccess.hasGameData(numericBasePath .. ".min") then
          resolvedBasePath = numericBasePath
        end
        if resolvedBasePath then
          local min = session.dataAccess.getGameLocation(resolvedBasePath .. ".min")
          local max = session.dataAccess.getGameLocation(resolvedBasePath .. ".max")
          if min and max then
            session.state.teamRestrictedZones[#session.state.teamRestrictedZones + 1] = { teamId = teamId, min = min, max = max }
          end
        end
      end
    end
    teamIndex = teamIndex + 1
  end
end

function M.startGame(session)
  session.state = newState()

  session.summary.setGameSummaryEnabled(false)
  session.summary.setFinalSummaryEnabled(false)
  session.summary.setRewardsEnabled(true)

  session.scheduler.cancelArenaTasks()

  session.state.voteState = voteService.createVoteState()
  voteService.applyPendingVotes(session)
  applyVoteDefaults(session)

  session.state.woolDefinitions = woolService.loadWoolDefinitions(session)

  loadTeamSpawns(session)
  loadTeamRestrictedZones(session)

  for _, handle in ipairs(session.players()) do
    session.state.kills[handle] = 0
    session.state.deaths[handle] = 0
    if session.teams.isEnabled() and not session.teams.forPlayer(handle) then
      session.teams.autoAssign(handle)
    end
  end

  descriptionService.sendDescription(session)
end

local function markCountdownPrepared(session, handle)
  if session.state.countdownPrepared[handle] then
    return false
  end
  session.state.countdownPrepared[handle] = true
  return true
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
  session.player.teleport(handle, spawn)
end

function M.handleCountdownTick(session, secondsLeft)
  for _, handle in ipairs(session.players()) do
    if markCountdownPrepared(session, handle) then
      teleportToTeamSpawn(session, handle)
      session.player.setGameMode(handle, "SPECTATOR")
    end

    session.sounds.play(handle, "sounds.starting_game.countdown")

    local title = (session.coreConfig.language(handle, "titles.starting_game.title") or "")
      :gsub("{game_display_name}", "Capture The Wool"):gsub("{time}", tostring(secondsLeft))
    local subtitle = (session.coreConfig.language(handle, "titles.starting_game.subtitle") or "")
      :gsub("{game_display_name}", "Capture The Wool"):gsub("{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.handleCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    local title = (session.coreConfig.language(handle, "titles.game_started.title") or ""):gsub("{game_display_name}", "Capture The Wool")
    local subtitle = (session.coreConfig.language(handle, "titles.game_started.subtitle") or ""):gsub("{game_display_name}", "Capture The Wool")
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 20)
    session.sounds.play(handle, "sounds.starting_game.start")
  end
end

local function getScoreboardPath(session)
  local teamCount = session.teams.isEnabled() and #session.teams.all() or 0
  if teamCount <= 2 then
    return "scoreboard.team_size_2"
  end
  if teamCount == 3 then
    return "scoreboard.team_size_3"
  end
  return "scoreboard.team_size_4"
end
M.getScoreboardPath = getScoreboardPath

local function shouldEndForVictory(session)
  if not session.teams.isEnabled() then
    return false
  end
  for _, team in ipairs(session.teams.all()) do
    if team.id and team.id ~= "" and woolService.hasTeamCapturedAllWools(session, team.id) then
      return true
    end
  end
  return false
end

local function registerFallProtection(session, handle)
  local protectionSeconds = math.max(0, session.config.getInt("spawn_protection.fall_damage_seconds", 5))
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
  local hologramIntervalTicks = math.max(1, session.config.getInt("wools.carrier_hologram_update_ticks", 2))

  local taskId = "arena_" .. session.arenaId .. "_capture_the_wool_timer"
  local hologramTaskId = "arena_" .. session.arenaId .. "_capture_the_wool_carrier_holograms"

  session.scheduler.runTimer(hologramTaskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(hologramTaskId)
      return
    end
    woolService.updateCarrierHolograms(session)
  end, 0, hologramIntervalTicks)

  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end

    session.state.matchSeconds = session.state.matchSeconds + 1
    refreshFallProtection(session, fallProtectionSeconds)

    woolService.spawnAllWools(session)

    if shouldEndForVictory(session) then
      M.endGame(session)
      return
    end

    for _, handle in ipairs(session.players()) do
      local placeholders = placeholderService.buildPlaceholders(session, handle, M)
      local actionBarTemplate = session.config.translation(handle, "messages.action_bar.in_game")
      if actionBarTemplate then
        local message = actionBarTemplate
          :gsub("{team}", placeholders.team or "-")
          :gsub("{captured}", placeholders.team_wools_captured or "0")
          :gsub("{objectives}", placeholders.team_wools_total or "0")
          :gsub("{kills}", placeholders.kills or "0")
          :gsub("{deaths}", placeholders.deaths or "0")
          :gsub("{carrying}", placeholders.carrying_wool or session.config.translation(handle, "messages.common.boolean_false"))
        session.messages.sendActionBar(handle, message)
      end

      session.scoreboard.update(handle, getScoreboardPath(session), placeholders)
    end
  end, 0, 20)
end

function M.beginPlaying(session)
  startGameTimer(session)
  woolService.spawnAllWools(session)

  for _, handle in ipairs(session.players()) do
    teleportToTeamSpawn(session, handle)
    session.player.setGameMode(handle, "SURVIVAL")
    loadoutService.restoreVitals(session, handle)
    loadoutService.giveStartingItems(session, handle)
    loadoutService.applyStartingEffects(session, handle)
    registerFallProtection(session, handle)
    session.scoreboard.show(handle, getScoreboardPath(session))
  end

  voteService.applyVotes(session)
  voteService.broadcastVoteResults(session)
end

function M.addLateJoiningPlayer(session, handle)
  if session.teams.isEnabled() and not session.teams.forPlayer(handle) then
    if not session.teams.autoAssign(handle) then
      return false
    end
  end

  session.state.kills[handle] = session.state.kills[handle] or 0
  session.state.deaths[handle] = session.state.deaths[handle] or 0

  teleportToTeamSpawn(session, handle)
  session.player.setGameMode(handle, "SURVIVAL")
  loadoutService.restoreVitals(session, handle)
  loadoutService.giveStartingItems(session, handle)
  loadoutService.applyStartingEffects(session, handle)
  registerFallProtection(session, handle)
  session.scoreboard.show(handle, getScoreboardPath(session))

  return true
end

function M.finishGame(session)
  session.scheduler.cancelArenaTasks()
  woolService.clearTrackedWoolItems(session)

  session.world.setTime(1000)
  session.world.setStorm(false)
  session.world.setThundering(false)

  for _, handle in ipairs(session.players()) do
    session.player.resetMaxHealth(handle)
    session.player.setHealth(handle, math.min(session.player.health(handle), 20.0))
  end

  for _, handle in ipairs(session.players()) do
    session.stats.add(handle, "games_played", 1)
  end
end

-- Mirrors legacy CaptureTheWoolGame.shutdown(): same reset as finishGame minus the games_played stat.
function M.handleDisableCleanup(session)
  session.scheduler.cancelArenaTasks()
  woolService.clearTrackedWoolItems(session)

  session.world.setTime(1000)
  session.world.setStorm(false)
  session.world.setThundering(false)

  for _, handle in ipairs(session.players()) do
    session.player.resetMaxHealth(handle)
    session.player.setHealth(handle, math.min(session.player.health(handle), 20.0))
  end
end

function M.getPlayerKills(session, handle)
  return session.state.kills[handle] or 0
end

function M.addPlayerKill(session, handle)
  session.state.kills[handle] = (session.state.kills[handle] or 0) + 1
end

function M.getPlayerDeaths(session, handle)
  return session.state.deaths[handle] or 0
end

function M.addPlayerDeath(session, handle)
  session.state.deaths[handle] = (session.state.deaths[handle] or 0) + 1
end

function M.handleKill(session, attackerHandle, victimHandle)
  combatService.handleKillCredit(session, M, attackerHandle)
  combatService.handleElimination(session, M, victimHandle, attackerHandle)
end

function M.handleNonCombatDeath(session, victimHandle)
  combatService.handleElimination(session, M, victimHandle, nil)
end

function M.handleWoolDrop(session, handle)
  woolService.handlePlayerDeath(session, handle)
end

function M.isPlayerCarryingWool(session, handle)
  return woolService.isPlayerCarryingWool(session, handle)
end

function M.isCarriedWoolMaterial(session, handle, material)
  return woolService.isCarriedWoolMaterial(session, handle, material)
end

function M.isObjectiveWoolMaterial(session, material)
  return woolService.isObjectiveWoolMaterial(session, material)
end

function M.respawnPlayer(session, handle)
  if not session.isPlaying(handle) then
    return
  end
  teleportToTeamSpawn(session, handle)
  session.player.setGameMode(handle, "SURVIVAL")
  loadoutService.restoreVitals(session, handle)
  loadoutService.giveStartingItems(session, handle)
  loadoutService.applyStartingEffects(session, handle)
  loadoutService.applyRespawnEffects(session, handle)
  registerFallProtection(session, handle)
end

function M.checkForWoolVictory(session)
  if session.state.ended then
    return
  end
  if shouldEndForVictory(session) then
    M.endGame(session)
  end
end

function M.handleWoolPickup(session, handle, x, y, z)
  local picked = woolService.handleWoolPickup(session, handle, x, y, z)
  if picked then
    session.stats.add(handle, "wools_stolen", 1)
    M.checkForWoolVictory(session)
  end
  return picked
end

function M.getWoolPickupBlockedMessage(session, handle, x, y, z)
  return woolService.resolveWoolPickupBlockedMessage(session, handle, x, y, z)
end

function M.handleWoolCapture(session, handle, x, y, z, placedMaterial)
  local captured = woolService.handleWoolCapture(session, handle, x, y, z, placedMaterial)
  if captured then
    session.stats.add(handle, "wools_captured", 1)
    M.checkForWoolVictory(session)
  end
  return captured
end

function M.isCaptureLocation(session, x, y, z)
  return woolService.isCaptureLocation(session, x, y, z)
end

function M.isWoolSpawnLocation(session, x, y, z)
  return woolService.isWoolSpawnLocation(session, x, y, z)
end

local function isInsideZoneBounds(loc, min, max)
  local minX, maxX = math.min(min.x, max.x), math.max(min.x, max.x)
  local minY, maxY = math.min(min.y, max.y), math.max(min.y, max.y)
  local minZ, maxZ = math.min(min.z, max.z), math.max(min.z, max.z)
  local bx, by, bz = math.floor(loc.x), math.floor(loc.y), math.floor(loc.z)
  return bx >= math.floor(minX) and bx <= math.floor(maxX)
    and by >= math.floor(minY) and by <= math.floor(maxY)
    and bz >= math.floor(minZ) and bz <= math.floor(maxZ)
end

function M.isInRestrictedZone(session, handle, location)
  if not session.teams.isEnabled() then
    return false
  end
  local team = session.teams.forPlayer(handle)
  if not team then
    return false
  end
  local teamId = team.id:lower()
  for _, zone in ipairs(session.state.teamRestrictedZones) do
    if zone.teamId == teamId and isInsideZoneBounds(location, zone.min, zone.max) then
      return true
    end
  end
  return false
end

function M.endGame(session)
  outcomeService.endGame(session, M)
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

function M.getTeamDeaths(session)
  local teamDeaths = {}
  for _, handle in ipairs(session.players()) do
    local deaths = M.getPlayerDeaths(session, handle)
    local teamId = "solo"
    if session.teams.isEnabled() then
      local team = session.teams.forPlayer(handle)
      if team then
        teamId = team.id
      end
    end
    teamDeaths[teamId] = (teamDeaths[teamId] or 0) + deaths
  end
  return teamDeaths
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

local function blockKey(x, y, z)
  return x .. ":" .. y .. ":" .. z
end

function M.trackPlacedBlock(session, x, y, z)
  session.state.playerPlacedBlocks[blockKey(x, y, z)] = true
end

function M.canBreakBlock(session, x, y, z)
  return session.state.playerPlacedBlocks[blockKey(x, y, z)] == true
end

function M.untrackPlacedBlock(session, x, y, z)
  session.state.playerPlacedBlocks[blockKey(x, y, z)] = nil
end

function M.getCustomPlaceholders(session, handle)
  return placeholderService.buildPlaceholders(session, handle, M)
end

return M

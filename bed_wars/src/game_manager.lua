-- Mirrors legacy BedWarsGame/BedWarsGameplayService/BedWarsRuntimeService/BedWarsArenaDataLoader
-- - the top-level per-match orchestration. ArenaState is a plain session.state table; its "storm"
-- fields are confirmed dead code in legacy and aren't ported.
local bedService = require("support.bed_service")
local spawnerService = require("support.spawner_service")
local npcService = require("support.npc_service")
local combatService = require("support.combat_service")
local loadoutService = require("support.loadout_service")
local descriptionService = require("support.description_service")
local placeholderService = require("support.placeholder_service")
local voteService = require("support.vote_service")
local outcomeService = require("support.outcome_service")
local shopService = require("support.shop_service")
local upgradeService = require("support.upgrade_service")
local cageService = require("support.cage_service")

local M = {}

local function newState()
  return {
    ended = false,
    winnerId = nil,
    matchSeconds = 0,
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
    beds = {},
    bedState = {},
    bedHolograms = {},
    spawners = {},
    spawnerTicks = {},
    spawnerHolograms = {},
    spawnerItemStands = {},
    spawnerItemRotation = {},
    npcs = {},
    npcHolograms = {},
    scheduledEvents = {},
    eventFired = {},
    globalSpawnerMultiplier = { iron = 1.0, gold = 1.0, diamond = 1.0, emerald = 1.0 },
    teamSpawnerMultiplier = {},
    cagedPlayers = {},
    cageBlocks = {},
    cagedSpawns = {},
    enderChests = {},
    shopSelectedCategory = {},
    shopCache = {},
    shopQuickBuy = {},
    playersInShop = {},
    upgradeTeamTiers = {},
    fireballCooldowns = {},
    trackedFireballs = {},
    specialProjectiles = {},
    teamEffects = {},
    teamSwordEnchantments = {},
    teamBowEnchantments = {},
    teamArmorEnchantments = {},
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
M.resolveDataBasePath = resolveDataBasePath

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

local function centerSpawnLocation(spawn)
  local centered = {}
  for k, v in pairs(spawn) do
    centered[k] = v
  end
  centered.x = math.floor(spawn.x) + 0.5
  centered.z = math.floor(spawn.z) + 0.5
  return centered
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
M.teleportToTeamSpawn = teleportToTeamSpawn

function M.startGame(session)
  session.state = newState()

  session.summary.setRewardsEnabled(true)
  session.scheduler.cancelArenaTasks()

  session.state.voteState = voteService.createVoteState()
  voteService.applyPendingVotes(session)
  applyVoteDefaults(session)

  session.state.beds = bedService.loadBedDefinitions(session)
  session.state.spawners = spawnerService.loadSpawnerDefinitions(session)
  session.state.scheduledEvents = spawnerService.loadGeneratorUpgradeEvents(session)
  session.state.npcs = npcService.loadNpcDefinitions(session)

  loadTeamSpawns(session)
  loadTeamRestrictedZones(session)

  for _, handle in ipairs(session.players()) do
    session.state.kills[handle] = 0
    session.state.deaths[handle] = 0
    if session.teams.isEnabled() and not session.teams.forPlayer(handle) then
      session.teams.autoAssign(handle)
    end
  end

  if cageService.isEnabled(session) then
    for _, handle in ipairs(session.players()) do
      teleportToTeamSpawn(session, handle)
    end
    cageService.scheduleSpawnCages(session)
    cageService.scheduleCageGuard(session, teleportToTeamSpawn)
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

function M.handleCountdownTick(session, secondsLeft)
  local cagesEnabled = cageService.isEnabled(session)
  for _, handle in ipairs(session.players()) do
    if markCountdownPrepared(session, handle) then
      teleportToTeamSpawn(session, handle)
      if not cagesEnabled then
        session.player.setGameMode(handle, "SPECTATOR")
      end
    end

    session.sounds.play(handle, "sounds.starting_game.countdown")

    local title = (session.coreConfig.language(handle, "titles.starting_game.title") or "")
      :gsub("{game_display_name}", "Bed Wars"):gsub("{time}", tostring(secondsLeft))
    local subtitle = (session.coreConfig.language(handle, "titles.starting_game.subtitle") or "")
      :gsub("{game_display_name}", "Bed Wars"):gsub("{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.handleCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    local title = (session.coreConfig.language(handle, "titles.game_started.title") or ""):gsub("{game_display_name}", "Bed Wars")
    local subtitle = (session.coreConfig.language(handle, "titles.game_started.subtitle") or ""):gsub("{game_display_name}", "Bed Wars")
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 20)
    session.sounds.play(handle, "sounds.starting_game.start")
  end
end

local function getScoreboardPath(session)
  local activeTeamCount = 0
  if session.teams.isEnabled() then
    for _, team in ipairs(session.teams.all()) do
      if team.id and team.id ~= "" then
        for _, handle in ipairs(session.players()) do
          local pTeam = session.teams.forPlayer(handle)
          if pTeam and pTeam.id:lower() == team.id:lower() then
            activeTeamCount = activeTeamCount + 1
            break
          end
        end
      end
    end
    if activeTeamCount == 0 then
      activeTeamCount = #session.teams.all()
    end
  end
  if activeTeamCount <= 2 then return "scoreboard.team_size_2" end
  if activeTeamCount == 3 then return "scoreboard.team_size_3" end
  if activeTeamCount == 4 then return "scoreboard.team_size_4" end
  if activeTeamCount == 5 then return "scoreboard.team_size_5" end
  if activeTeamCount == 6 then return "scoreboard.team_size_6" end
  if activeTeamCount == 7 then return "scoreboard.team_size_7" end
  return "scoreboard.team_size_8"
end
M.getScoreboardPath = getScoreboardPath

local function shouldEndForVictory(session)
  if not session.teams.isEnabled() then
    return false
  end
  return bedService.getAliveTeamCount(session) <= 1
end

local function registerFallProtection(session, handle)
  local protectionSeconds = math.max(0, session.config.getInt("spawn_protection.fall_damage_seconds", 5))
  if protectionSeconds <= 0 then
    return
  end
  session.state.fallProtectionUntil[handle] = os.clock() + protectionSeconds
end
M.registerFallProtection = registerFallProtection

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

local function formatMultiplier(multiplier)
  if multiplier == math.floor(multiplier) then
    return tostring(math.floor(multiplier))
  end
  return tostring(multiplier)
end

local function applyGeneratorUpgradeEvent(session, event)
  session.state.globalSpawnerMultiplier[event.type] = event.multiplier

  local multiplierFormatted = formatMultiplier(event.multiplier)
  for _, handle in ipairs(session.players()) do
    local template = session.config.translation(handle, "messages.generator_upgrade")
    if template then
      session.messages.sendRaw(handle, template
        :gsub("{label}", event.label)
        :gsub("{type}", event.type)
        :gsub("{multiplier}", multiplierFormatted))
    end
  end
end

local function processScheduledEvents(session)
  local matchSeconds = session.state.matchSeconds
  for i, event in ipairs(session.state.scheduledEvents) do
    if not session.state.eventFired[i] and matchSeconds >= event.triggerSeconds then
      session.state.eventFired[i] = true
      applyGeneratorUpgradeEvent(session, event)
    end
  end
end

local function startGameTimer(session)
  local fallProtectionSeconds = math.max(0, session.config.getInt("spawn_protection.fall_damage_seconds", 5))
  local taskId = "arena_" .. session.arenaId .. "_bed_wars_timer"
  local spawnerTaskId = "arena_" .. session.arenaId .. "_bed_wars_spawners"
  local itemRotationTaskId = "arena_" .. session.arenaId .. "_bed_wars_item_rot"

  session.scheduler.runTimer(spawnerTaskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(spawnerTaskId)
      return
    end
    spawnerService.spawnResources(session)
  end, 0, 1)

  session.scheduler.runTimer(itemRotationTaskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(itemRotationTaskId)
      return
    end
    spawnerService.rotateSpawnerItems(session)
  end, 0, 1)

  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end

    session.state.matchSeconds = session.state.matchSeconds + 1
    refreshFallProtection(session, fallProtectionSeconds)
    processScheduledEvents(session)
    spawnerService.updateSpawnerHolograms(session)

    if shouldEndForVictory(session) then
      M.endGame(session)
      return
    end

    for _, handle in ipairs(session.players()) do
      local actionBarTemplate = session.config.translation(handle, "messages.action_bar.in_game")
      local placeholders = placeholderService.buildPlaceholders(session, handle, M)
      if actionBarTemplate then
        session.messages.sendActionBar(handle, actionBarTemplate
          :gsub("{team}", placeholders.team or "-")
          :gsub("{kills}", placeholders.kills or "0")
          :gsub("{deaths}", placeholders.deaths or "0")
          :gsub("{bed_status}", placeholders.bed_status or "-")
          :gsub("{elapsed}", tostring(session.state.matchSeconds)))
      end
      session.scoreboard.update(handle, getScoreboardPath(session), placeholders)
    end
  end, 0, 20)
end

function M.beginPlaying(session)
  startGameTimer(session)

  session.scheduler.cancelTask("arena_" .. session.arenaId .. "_bed_wars_cage_guard")
  cageService.removeCages(session)
  bedService.removeEmptyTeamBeds(session)

  bedService.spawnBedHolograms(session)
  spawnerService.spawnSpawnerHolograms(session)
  npcService.spawnNpcs(session)

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

function M.finishGame(session)
  session.scheduler.cancelArenaTasks()

  cageService.removeCages(session)
  bedService.clearBedHolograms(session)
  spawnerService.clearSpawnerHolograms(session)
  npcService.despawnNpcs(session)
  shopService.clearArena(session)
  upgradeService.clearArena(session)

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

-- Mirrors legacy BedWarsGame.shutdown(): same reset as finishGame minus the games_played stat.
function M.handleDisableCleanup(session)
  session.scheduler.cancelArenaTasks()

  cageService.removeCages(session)
  bedService.clearBedHolograms(session)
  spawnerService.clearSpawnerHolograms(session)
  npcService.despawnNpcs(session)
  shopService.clearArena(session)
  upgradeService.clearArena(session)

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

function M.healKiller(session, killerHandle)
  loadoutService.handleKillRegeneration(session, killerHandle)
  session.sounds.play(killerHandle, "sounds.in_game.respawn")
end

function M.handleKill(session, attackerHandle, victimHandle)
  combatService.handleKillCredit(session, M, attackerHandle)
  combatService.handleElimination(session, M, victimHandle, attackerHandle)
end

function M.handleNonCombatDeath(session, victimHandle)
  combatService.handleElimination(session, M, victimHandle, nil)
end

function M.handleBedBreak(session, breakerHandle, x, y, z)
  local broken = bedService.handleBedBreak(session, breakerHandle, x, y, z)
  if broken then
    session.stats.add(breakerHandle, "beds_broken", 1)
    M.checkForVictory(session)
  end
  return broken
end

-- Called after a bed break or a final kill, mirroring legacy's own two `checkForVictory` call sites.
function M.checkForVictory(session)
  if shouldEndForVictory(session) then
    M.endGame(session)
  end
end

function M.isBedLocation(session, x, y, z)
  return bedService.isBedLocation(session, x, y, z)
end

function M.isSpawnerLocation(session, x, y, z)
  return spawnerService.isSpawnerLocation(session, x, y, z)
end

function M.canPlayerRespawn(session, handle)
  if not session.teams.isEnabled() then
    return true
  end
  local team = session.teams.forPlayer(handle)
  if not team then
    return false
  end
  return bedService.isTeamBedIntact(session, team.id)
end

local function resolveEnchantmentAliasName(name)
  return name
end

local function applyTeamUpgradesOnRespawn(session, handle)
  if not session.teams.isEnabled() then
    return
  end
  local team = session.teams.forPlayer(handle)
  if not team then
    return
  end
  local teamId = team.id:lower()

  for _, effect in ipairs(session.state.teamEffects[teamId] or {}) do
    session.player.addPotionEffect(handle, effect.type, effect.duration, effect.amplifier, true, true)
  end

  for _, enchant in ipairs(session.state.teamSwordEnchantments[teamId] or {}) do
    session.player.enchantEquipped(handle, "sword", resolveEnchantmentAliasName(enchant.name), enchant.level)
  end
  for _, enchant in ipairs(session.state.teamBowEnchantments[teamId] or {}) do
    session.player.enchantEquipped(handle, "bow", resolveEnchantmentAliasName(enchant.name), enchant.level)
  end
  for _, enchant in ipairs(session.state.teamArmorEnchantments[teamId] or {}) do
    session.player.enchantEquipped(handle, "armor", resolveEnchantmentAliasName(enchant.name), enchant.level)
  end
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
  shopService.restoreOnRespawn(session, handle)
  applyTeamUpgradesOnRespawn(session, handle)
  registerFallProtection(session, handle)
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

function M.handleMenuAction(playerHandle, payload)
  if not payload or payload == "" then
    return false
  end
  -- "vote"/"menu" payloads belong to the vote subsystem; shop/upgrade payloads are colon-prefixed.
  if payload:match("^vote") or payload:match("^menu") then
    return voteService.handleVoteAction(playerHandle, payload)
  end

  local session = ba.session.forPlayer(playerHandle)
  if not session or not session.isPlaying(playerHandle) then
    return false
  end

  if payload:match("^shop:") then
    return shopService.handleAction(session, playerHandle, payload)
  end
  if payload:match("^upgrade:") then
    return upgradeService.handleAction(session, playerHandle, payload)
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
  local ids = {}
  for _, team in ipairs(session.teams.all()) do
    local teamId = team.id
    if teamId and teamId ~= "" and bedService.isTeamAlive(session, teamId) then
      ids[#ids + 1] = teamId
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
      if team then teamId = team.id end
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
      if team then teamId = team.id end
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

-- Mirrors legacy's real, writable, per-team shared ender chest; `openTrackedInventory` hands the
-- final contents back via `inventory_close` using the tracking key it's opened with.
local function enderChestTeamId(session, handle)
  if not session.teams.isEnabled() then
    return "solo"
  end
  local team = session.teams.forPlayer(handle)
  if team and team.id then
    return team.id:lower()
  end
  return "solo"
end

function M.enderChestTrackingKey(session, teamId)
  return "bed_wars_ender_chest:" .. tostring(session.arenaId) .. ":" .. teamId
end

function M.openArenaEnderChest(session, handle)
  local teamId = enderChestTeamId(session, handle)
  local contents = session.state.enderChests[teamId] or {}
  local title = session.config.translation(nil, "inventories.ender_chest_title") or "Ender Chest"
  session.player.openTrackedInventory(handle, title, 27, contents, M.enderChestTrackingKey(session, teamId))
end

function M.saveArenaEnderChest(session, teamId, contents)
  session.state.enderChests[teamId] = contents
end

function M.getCustomPlaceholders(session, handle)
  return placeholderService.buildPlaceholders(session, handle, M)
end

return M

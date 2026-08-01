-- ArenaState.java isn't a separate file here - it's a plain session.state table, same convention as guess_the_build.
-- migrateSpawnsToDisk and the generic-spawns fallback aren't ported (documented simplification, see docs/BAMODULE_STATUS.md) - lucky_pillars ships disabledRequirements=["SPAWNS"], so a configured arena always has team spawns.
local combatService = require("support.combat_service")
local outcomeService = require("support.outcome_service")
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
    teamSpawns = {},
    cageBlocks = {},
    cagedPlayers = {},
    cagedSpawnKeys = {},
    fallProtectionUntil = {},
    voteState = nil,
    selectedModifier = "none",
    blockBreakingDisabled = false,
    nextBlockDropAtClock = nil,
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
  local taskId = "arena_" .. session.arenaId .. "_lucky_pillars_cages"
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
  local taskId = "arena_" .. session.arenaId .. "_lucky_pillars_cage_guard"
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

function M.startGame(session)
  session.state = newState()
  session.scheduler.cancelArenaTasks()

  session.state.voteState = voteService.createVoteState()
  voteService.applyPendingVotes(session)

  loadTeamSpawns(session)

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
  -- {game_display_name} resolves to module.toml's fixed name, not a per-locale translation - matches legacy's moduleInfo.getName() usage.
  for _, handle in ipairs(session.players()) do
    session.sounds.play(handle, "sounds.starting_game.countdown")
    local title = (session.coreConfig.language(handle, "titles.starting_game.title") or "")
      :gsub("{game_display_name}", "Lucky Pillars"):gsub("{time}", tostring(secondsLeft))
    local subtitle = (session.coreConfig.language(handle, "titles.starting_game.subtitle") or "")
      :gsub("{game_display_name}", "Lucky Pillars"):gsub("{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.handleCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    local title = (session.coreConfig.language(handle, "titles.game_started.title") or ""):gsub("{game_display_name}", "Lucky Pillars")
    local subtitle = (session.coreConfig.language(handle, "titles.game_started.subtitle") or ""):gsub("{game_display_name}", "Lucky Pillars")
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
  local taskId = "arena_" .. session.arenaId .. "_lucky_pillars_timer"

  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end

    session.state.matchSeconds = session.state.matchSeconds + 1
    refreshFallProtection(session, fallProtectionSeconds)

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

local function applyElytraModifier(session)
  for _, handle in ipairs(session.players()) do
    session.player.giveItem(handle, "ELYTRA", 1, 38)
  end
end

local function startPositionSwapTimer(session)
  local taskId = "arena_" .. session.arenaId .. "_position_swap"
  session.scheduler.runTimer(taskId, function()
    local alivePlayers = session.alivePlayers()
    if #alivePlayers < 2 then
      return
    end

    local locations = {}
    for _, handle in ipairs(alivePlayers) do
      locations[#locations + 1] = session.player.location(handle)
    end

    for i = #locations, 2, -1 do
      local j = math.random(i)
      locations[i], locations[j] = locations[j], locations[i]
    end

    for i, handle in ipairs(alivePlayers) do
      if locations[i] then
        session.player.teleport(handle, locations[i])
        session.world.spawnParticleAt(session.player.location(handle), "PORTAL", 50, 0.5, 0.5, 0.5, 0.1)
      end
    end
  end, 300, 300)
end

local function applySlowFallModifier(session)
  for _, handle in ipairs(session.players()) do
    session.player.addPotionEffect(handle, "SLOW_FALLING", 999999, 0)
  end
end

local function applyInvisibilityModifier(session)
  for _, handle in ipairs(session.players()) do
    session.player.addPotionEffect(handle, "INVISIBILITY", 600, 0)
  end
end

local function applyDoubleHealthModifier(session)
  for _, handle in ipairs(session.players()) do
    session.player.setMaxHealth(handle, 40.0)
    session.player.setHealth(handle, 40.0)
  end
end

local function applyOneHeartModifier(session)
  for _, handle in ipairs(session.players()) do
    session.player.setMaxHealth(handle, 2.0)
    session.player.setHealth(handle, 2.0)
  end
end

local function applyUltraJumpModifier(session)
  for _, handle in ipairs(session.players()) do
    session.player.addPotionEffect(handle, "JUMP_BOOST", 999999, 4)
  end
end

local function fillLavaLayer(session, minX, maxX, minZ, maxZ, y)
  for x = minX, maxX do
    for z = minZ, maxZ do
      if session.world.isChunkLoaded(math.floor(x / 16), math.floor(z / 16)) then
        if session.world.blockTypeAt(x, y, z) == "AIR" then
          session.world.setBlockType(x, y, z, "LAVA", false)
        end
      end
    end
  end
end

local function resolveRisingLavaBounds(session)
  local minX = session.dataAccess.getGameDataNumber("game.play_area.bounds.min.x")
  local minY = session.dataAccess.getGameDataNumber("game.play_area.bounds.min.y")
  local minZ = session.dataAccess.getGameDataNumber("game.play_area.bounds.min.z")
  local maxX = session.dataAccess.getGameDataNumber("game.play_area.bounds.max.x")
  local maxY = session.dataAccess.getGameDataNumber("game.play_area.bounds.max.y")
  local maxZ = session.dataAccess.getGameDataNumber("game.play_area.bounds.max.z")
  if minX and minY and minZ and maxX and maxY and maxZ then
    return { math.floor(minX), math.floor(minY), math.floor(minZ), math.floor(maxX), math.floor(maxY), math.floor(maxZ) }
  end

  local boundsMin = session.arena.boundsMin()
  local boundsMax = session.arena.boundsMax()
  if not boundsMin or not boundsMax then
    return nil
  end
  return {
    math.min(math.floor(boundsMin.x), math.floor(boundsMax.x)),
    math.min(math.floor(boundsMin.y), math.floor(boundsMax.y)),
    math.min(math.floor(boundsMin.z), math.floor(boundsMax.z)),
    math.max(math.floor(boundsMin.x), math.floor(boundsMax.x)),
    math.max(math.floor(boundsMin.y), math.floor(boundsMax.y)),
    math.max(math.floor(boundsMin.z), math.floor(boundsMax.z)),
  }
end

local function startRisingLava(session)
  local intervalSeconds = session.config.getInt("modifiers.rising_lava.rise_interval_seconds", 30)
  if intervalSeconds <= 0 then
    return
  end

  local bounds = resolveRisingLavaBounds(session)
  if not bounds then
    return
  end

  local minX, minY, minZ, maxX, maxY, maxZ = bounds[1], bounds[2], bounds[3], bounds[4], bounds[5], bounds[6]
  local startY = math.max(minY, session.world.minHeight())
  local endY = math.min(maxY, session.world.maxHeight() - 1)
  if startY > endY then
    return
  end

  local layerBlocks = (maxX - minX + 1) * (maxZ - minZ + 1)
  local maxLayerBlocks = session.config.getInt("modifiers.rising_lava.max_layer_blocks", 100000)
  if maxLayerBlocks > 0 and layerBlocks > maxLayerBlocks then
    return
  end

  local taskId = "arena_" .. session.arenaId .. "_rising_lava"
  local intervalTicks = intervalSeconds * 20
  local currentY = startY

  fillLavaLayer(session, minX, maxX, minZ, maxZ, currentY)
  currentY = currentY + 1

  session.scheduler.runTimer(taskId, function()
    if currentY > endY then
      session.scheduler.cancelTask(taskId)
      return
    end
    fillLavaLayer(session, minX, maxX, minZ, maxZ, currentY)
    currentY = currentY + 1
  end, intervalTicks, intervalTicks)
end

local function applyModifier(session)
  local modifier = session.state.selectedModifier
  if not modifier or modifier:lower() == "none" then
    return
  end
  if #session.players() == 0 then
    return
  end

  modifier = modifier:lower()
  if modifier == "elytra" then
    applyElytraModifier(session)
  elseif modifier == "swap" then
    startPositionSwapTimer(session)
  elseif modifier == "slow_fall" then
    applySlowFallModifier(session)
  elseif modifier == "invisibility" then
    applyInvisibilityModifier(session)
  elseif modifier == "double_health" then
    applyDoubleHealthModifier(session)
  elseif modifier == "one_heart" then
    applyOneHeartModifier(session)
  elseif modifier == "unbreakable" then
    session.state.blockBreakingDisabled = true
  elseif modifier == "ultra_jump" then
    applyUltraJumpModifier(session)
  elseif modifier == "rising_lava" then
    startRisingLava(session)
  end
  -- "speed" has no direct effect here - it halves the item-distribution interval instead, see startItemDistribution below.
end

local function isHiddenOrCreativeItem(material)
  if material:match("^LEGACY_") or material:match("_SPAWN_EGG$") then
    return true
  end
  if material:find("COMMAND_BLOCK", 1, true) then
    return true
  end
  local hidden = {
    BARRIER = true, LIGHT = true, STRUCTURE_VOID = true, STRUCTURE_BLOCK = true, JIGSAW = true,
    DEBUG_STICK = true, KNOWLEDGE_BOOK = true, END_PORTAL_FRAME = true, END_GATEWAY = true,
  }
  return hidden[material] == true
end

local function buildRandomItemCandidates(session)
  local blacklistValues = session.config.getStringList("item_distribution.blacklist")
  if #blacklistValues == 0 then
    blacklistValues = session.config.getStringList("item_distribution.block_blacklist")
  end
  local blacklist = {}
  for _, value in ipairs(blacklistValues) do
    blacklist[value:upper()] = true
  end

  local candidates = {}
  for _, material in ipairs(session.world.allItemMaterials()) do
    if material ~= "AIR" and material ~= "CAVE_AIR" and material ~= "VOID_AIR"
        and not blacklist[material] and not isHiddenOrCreativeItem(material) then
      candidates[#candidates + 1] = material
    end
  end
  return candidates
end

-- Overflow from a full inventory is silently dropped, not spawned on the ground (giveItem has no leftover-drop return) - accepted simplification for this rare edge case.
local function distributeRandomItem(session)
  if session.phase() ~= "PLAYING" then
    return
  end
  local alivePlayers = session.alivePlayers()
  if #alivePlayers == 0 then
    return
  end
  local candidates = buildRandomItemCandidates(session)
  if #candidates == 0 then
    return
  end
  for _, handle in ipairs(alivePlayers) do
    local material = candidates[math.random(#candidates)]
    session.player.giveItem(handle, material, 1)
  end
end

local function startItemDistribution(session)
  if not session.config.getBoolean("item_distribution.enabled", true) then
    return
  end
  local baseInterval = session.config.getInt("game.item_distribution_interval", 3)
  if baseInterval <= 0 then
    return
  end

  local intervalSeconds = baseInterval
  if session.state.selectedModifier and session.state.selectedModifier:lower() == "speed" then
    intervalSeconds = math.max(1, math.floor(baseInterval / 2))
  end

  local taskId = "arena_" .. session.arenaId .. "_item_distribution"
  local intervalTicks = intervalSeconds * 20

  session.state.nextBlockDropAtClock = os.clock() + 0.05
  session.scheduler.runTimer(taskId, function()
    distributeRandomItem(session)
    session.state.nextBlockDropAtClock = os.clock() + intervalSeconds
  end, 1, intervalTicks)
end

local function applyStartingItems(session, handle)
  for _, itemStr in ipairs(session.config.getStringList("items.starting_items")) do
    local parts = {}
    for part in itemStr:gmatch("[^:]+") do
      parts[#parts + 1] = part
    end
    if #parts >= 2 then
      local amount = tonumber(parts[2])
      local slot = parts[3] and tonumber(parts[3]) or -1
      if amount then
        session.player.giveItem(handle, parts[1], amount, slot)
      end
    end
  end
end

local function applyStartingEffects(session, handle)
  for _, effectStr in ipairs(session.config.getStringList("effects.starting_effects")) do
    local parts = {}
    for part in effectStr:gmatch("[^:]+") do
      parts[#parts + 1] = part
    end
    if #parts >= 3 then
      local duration = tonumber(parts[2])
      local amplifier = tonumber(parts[3])
      if duration and amplifier then
        session.player.addPotionEffect(handle, parts[1], duration, amplifier)
      end
    end
  end
end

function M.beginPlaying(session)
  voteService.applyVotes(session)
  applyModifier(session)

  startGameTimer(session)
  startItemDistribution(session)
  session.scheduler.cancelTask("arena_" .. session.arenaId .. "_lucky_pillars_cage_guard")
  spawnCageService.removeCages(session)
  voteService.broadcastVoteResults(session)

  local fallProtectionSeconds = math.max(0, session.config.getInt("spawn_protection.fall_damage_seconds", 5))
  for _, handle in ipairs(session.players()) do
    session.player.setGameMode(handle, "SURVIVAL")
    session.player.setHealth(handle, 20.0)
    session.player.setFoodLevel(handle, 20)
    session.player.setSaturation(handle, 20.0)
    session.player.setFireTicks(handle, 0)
    session.player.clearInventory(handle)

    applyStartingItems(session, handle)
    applyStartingEffects(session, handle)

    registerFallProtection(session, handle, fallProtectionSeconds)
    session.scoreboard.show(handle, getScoreboardPath(session))
  end
end

-- Uses dropInventory (drops at the player's feet) instead of legacy's silent discard - the arena resets right after this anyway, and no binding exposes a silent-discard equivalent.
function M.finishGame(session)
  session.scheduler.cancelArenaTasks()
  spawnCageService.removeCages(session)

  session.world.setTime(1000)
  session.world.setStorm(false)
  session.world.setThundering(false)

  for _, handle in ipairs(session.players()) do
    session.player.resetMaxHealth(handle)
    session.player.setHealth(handle, session.player.health(handle))
    session.player.dropInventory(handle)
  end

  for _, handle in ipairs(session.players()) do
    session.stats.add(handle, "games_played", 1)
  end
end

-- Mirrors legacy LuckyPillarsGame.shutdown(): cancel tasks, remove cages, reset world/hearts, clear (not drop) inventories - no stats.
function M.handleDisableCleanup(session)
  session.scheduler.cancelArenaTasks()
  spawnCageService.removeCages(session)

  session.world.setTime(1000)
  session.world.setStorm(false)
  session.world.setThundering(false)

  for _, handle in ipairs(session.players()) do
    session.player.resetMaxHealth(handle)
    session.player.setHealth(handle, math.min(session.player.health(handle), 20.0))
    session.player.clearInventory(handle)
  end
end

function M.getCustomPlaceholders(session, handle)
  return placeholderService.buildPlaceholders(session, handle, M)
end

return M

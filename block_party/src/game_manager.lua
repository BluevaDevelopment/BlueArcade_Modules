local fallingBlockService = require("support.falling_block_service")
local messagingService = require("support.messaging_service")
local musicPlaylist = require("support.music_playlist")
local patternService = require("support.pattern_service")
local playerEffectsService = require("support.player_effects_service")
local powerupService = require("support.powerup_service")
local statsService = require("support.stats_service")

local M = {}

local function secondsToTicks(seconds)
  return math.max(1, math.floor(seconds * 20 + 0.5))
end

local function ticksToSeconds(ticks)
  return math.max(0, ticks / 20)
end

local function formatSeconds(seconds)
  return string.format("%.1f", seconds)
end

local function locationKey(x, y, z)
  return x .. "," .. y .. "," .. z
end

local function resolveMusicTime(session)
  local override = session.dataAccess.getGameDataNumber("basic.initial_music_time")
  if override ~= nil and override > 0 then return override end
  return session.config.getDouble("gameplay.initial_music_time", 3.0)
end

local function resolveSearchTime(session)
  local override = session.dataAccess.getGameDataNumber("basic.search_time")
  if override ~= nil and override > 0 then return override end
  return session.config.getDouble("gameplay.search_time", 12.0)
end

local function resolveDecreaseTime(session)
  local override = session.dataAccess.getGameDataNumber("basic.decrease_time")
  if override ~= nil and override > 0 then return override end
  return session.config.getDouble("gameplay.decrease_time", 1.0)
end

local function resolveMinSearchTime(session)
  local override = session.dataAccess.getGameDataNumber("basic.min_search_time")
  if override ~= nil and override > 0 then return override end
  return session.config.getDouble("gameplay.min_search_time", 0.5)
end

local function findFloorBounds(session)
  local storedMin = session.dataAccess.getGameLocation("game.floor.bounds.min")
  local storedMax = session.dataAccess.getGameLocation("game.floor.bounds.max")
  if storedMin ~= nil and storedMax ~= nil then
    return { min = storedMin, max = storedMax }
  end
  return nil
end

local function findArenaBounds(session, fallback)
  local min = session.dataAccess.getArenaLocation("bounds.min")
  local max = session.dataAccess.getArenaLocation("bounds.max")
  if min ~= nil and max ~= nil then
    return { min = min, max = max }
  end
  return fallback
end

local function createState(session, floor)
  local patternType = session.dataAccess.getGameDataString("game.pattern.type") or "static"
  local procedural = patternType:lower() == "procedural"

  local patterns, order = {}, {}
  if not procedural then
    patterns, order = patternService.loadPatterns(session, floor)
  end

  local initialPatternKey = session.dataAccess.getGameDataString("game.patterns.initial")
  if initialPatternKey == nil or patterns[initialPatternKey] == nil then
    initialPatternKey = order[1]
  end

  local templatesRaw = session.dataAccess.getGameDataString("game.pattern.templates")
  local proceduralTemplates = {}
  if templatesRaw ~= nil and templatesRaw ~= "" then
    for value in templatesRaw:gmatch("[^,]+") do
      proceduralTemplates[#proceduralTemplates + 1] = value:match("^%s*(.-)%s*$"):lower()
    end
  end
  if #proceduralTemplates == 0 then
    local generator = require("support.procedural_pattern_generator")
    for _, template in ipairs(generator.TEMPLATE_TYPES) do proceduralTemplates[#proceduralTemplates + 1] = template end
  end

  return {
    ended = false,
    winnerId = nil,
    floor = floor,
    patterns = patterns,
    order = order,
    initialPatternKey = initialPatternKey,
    proceduralPatterns = procedural,
    proceduralTemplates = proceduralTemplates,
    matchSeed = math.random(1, 2147483646),
    recentProceduralTemplates = {},
    round = 0,
    searchSeconds = resolveSearchTime(session),
    currentPattern = nil,
    currentBlocks = {},
    targetMaterial = "AIR",
    phase = "MUSIC",
    phaseTicksRemaining = 0,
    phaseTotalTicks = 0,
    displayedTime = 0,
    musicTrack = nil,
    musicPaused = false,
    musicPlaylist = musicPlaylist,
    eliminated = {},
    fallingBlocks = {},
    activePowerups = {},
  }
end

function M.handleStart(session)
  session.scheduler.cancelArenaTasks()

  local floor = findFloorBounds(session)
  session.state = createState(session, floor)

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
  local state = session.state
  return {
    alive = tostring(#session.alivePlayers()),
    spectators = tostring(#session.spectators()),
    bp_round = tostring(state.round),
    bp_time = state.phase == "SEARCH" and formatSeconds(state.displayedTime) or "-",
  }
end

local function updateExperienceBar(session, handle, state)
  if state.phaseTotalTicks <= 0 or state.phase ~= "SEARCH" then
    session.player.setExp(handle, 0)
    session.player.setLevel(handle, 0)
    return
  end
  local progress = state.phaseTicksRemaining / state.phaseTotalTicks
  progress = math.max(0, math.min(1, progress))
  session.player.setExp(handle, progress)
  session.player.setLevel(handle, math.ceil(state.displayedTime))
end

local function updateActionBars(session, state)
  local showCountdown = state.phase == "SEARCH"
  state.displayedTime = showCountdown and math.max(0, ticksToSeconds(state.phaseTicksRemaining)) or 0

  for _, handle in ipairs(session.players()) do
    local placeholders = M.getCustomPlaceholders(session, handle)
    placeholders.bp_time = showCountdown and formatSeconds(state.displayedTime) or "-"
    placeholders.bp_round = tostring(state.round)

    if showCountdown then
      local message = session.config.translation(handle, "action_bar.search")
      message = string.gsub(message, "{bp_time}", formatSeconds(state.displayedTime))
      message = string.gsub(message, "{bp_round}", tostring(state.round))
      session.messages.sendActionBar(handle, message)
    else
      session.messages.sendActionBar(handle, "")
    end

    updateExperienceBar(session, handle, state)
    session.scoreboard.update(handle, "scoreboard.main", placeholders)
  end
end

function M.endGameOnce(session)
  local state = session.state
  if state.ended then return end
  state.ended = true

  session.scheduler.cancelArenaTasks()

  local alive = session.alivePlayers()
  if #alive == 1 then
    local winner = alive[1]
    session.setWinner(winner)
    M.handleWin(session, winner)
  end

  session.endGame()
end

function M.handleWin(session, handle)
  if session.state.winnerId == nil then
    session.state.winnerId = handle
    statsService.recordWin(session, handle)
  end
end

local function applyPattern(session, pattern)
  if pattern == nil then return end
  for _, block in ipairs(pattern.blocks) do
    session.world.setBlockType(block.x, block.y, block.z, block.material)
  end
end

local function selectMusicTrack(session)
  local playlist = session.state.musicPlaylist
  if playlist == nil or #playlist == 0 then return nil end
  return playlist[math.random(#playlist)]
end

local function startRound(session, state, firstRound)
  if state.ended then return end

  powerupService.clearArenaPowerups(session)

  state.round = state.round + 1
  local pattern
  if state.proceduralPatterns then
    local ok, result = pcall(patternService.createProceduralPattern, session, state)
    if ok then pattern = result end
  else
    local key = patternService.selectPatternKey(state, firstRound)
    pattern = key ~= nil and state.patterns[key] or nil
  end
  if pattern == nil and next(state.patterns) ~= nil then
    for _, candidate in pairs(state.patterns) do pattern = candidate break end
  end
  if pattern == nil then
    pattern = patternService.createFallbackPattern(session, state.floor)
  end

  state.currentPattern = pattern
  state.currentBlocks = {}
  for _, block in ipairs(pattern.blocks) do
    state.currentBlocks[locationKey(block.x, block.y, block.z)] = block
  end
  state.targetMaterial = patternService.selectTargetMaterial(session, pattern)
  state.phase = "MUSIC"
  state.phaseTicksRemaining = secondsToTicks(resolveMusicTime(session))
  state.phaseTotalTicks = state.phaseTicksRemaining
  state.displayedTime = ticksToSeconds(state.phaseTicksRemaining)

  applyPattern(session, pattern)

  local musicTrack = nil
  if state.musicPlaylist ~= nil and #state.musicPlaylist > 0 then
    musicTrack = state.musicTrack
    if musicTrack == nil then
      musicTrack = selectMusicTrack(session)
      state.musicTrack = musicTrack
    end
  end

  messagingService.sendRoundStarting(session, state.round)
  for _, handle in ipairs(session.players()) do
    if musicTrack ~= nil then
      if state.musicPaused then
        session.sounds.resumeMusic(handle)
      else
        session.sounds.play(handle, musicTrack)
      end
    end
  end

  state.musicPaused = false
end

local function revealTarget(session, state)
  state.phase = "SEARCH"
  state.phaseTicksRemaining = secondsToTicks(state.searchSeconds)
  state.phaseTotalTicks = state.phaseTicksRemaining
  state.displayedTime = ticksToSeconds(state.phaseTicksRemaining)

  messagingService.sendRoundReveal(session, state.targetMaterial)
  for _, handle in ipairs(session.players()) do
    playerEffectsService.giveTargetItem(session, handle, state.targetMaterial)
  end
end

local function evaluateSurvival(session, state)
  for _, handle in ipairs(session.alivePlayers()) do
    local location = session.player.location(handle)
    local belowType = session.world.blockTypeAt(math.floor(location.x), math.floor(location.y) - 1, math.floor(location.z))
    if belowType == state.targetMaterial then
      statsService.recordCorrectBlock(session, handle)
    end
  end
  if #session.alivePlayers() <= 1 then
    M.endGameOnce(session)
  end
end

local function collapseFloor(session, state)
  if state.currentBlocks == nil or next(state.currentBlocks) == nil then return end

  local fallingEnabled = session.config.getBoolean("gameplay.falling_blocks.enabled", true)
  local collapseParticlesEnabled = session.config.getBoolean("particles.collapse.enabled", false)

  for _, block in pairs(state.currentBlocks) do
    if block.material ~= nil and block.material ~= "AIR" and block.material ~= state.targetMaterial then
      local currentType = session.world.blockTypeAt(block.x, block.y, block.z)
      if currentType ~= "AIR" then
        session.world.setBlockType(block.x, block.y, block.z, "AIR")
        powerupService.removePowerupWithSupport(session, { x = block.x, y = block.y, z = block.z }, false)

        if fallingEnabled then
          fallingBlockService.spawnFallingShard(session, { x = block.x + 0.5, y = block.y + 0.1, z = block.z + 0.5 }, currentType)
        end
        if collapseParticlesEnabled then
          local particle = session.config.getString("particles.collapse.type") or "FLAME"
          local count = session.config.getInt("particles.collapse.count", 10)
          local spread = session.config.getDouble("particles.collapse.spread", 0.35)
          local speed = session.config.getDouble("particles.collapse.speed", 0.1)
          local location = { x = block.x + 0.5, y = block.y + 0.5, z = block.z + 0.5 }
          if not session.world.spawnParticleAt(location, particle, count, spread, spread * 0.6, spread, speed) then
            session.world.spawnParticleAt(location, "FLAME", count, spread, spread * 0.6, spread, speed)
          end
        end
      end
    end
  end

  messagingService.sendRoundCollapsing(session)
  playerEffectsService.clearPlayerInventories(session)
  evaluateSurvival(session, state)

  if state.musicTrack ~= nil then
    for _, handle in ipairs(session.players()) do
      session.sounds.pauseMusic(handle)
    end
    state.musicPaused = true
  end

  state.searchSeconds = math.max(resolveMinSearchTime(session), state.searchSeconds - resolveDecreaseTime(session))
end

local function advancePhase(session, state)
  if state.phase == "MUSIC" then
    revealTarget(session, state)
  elseif state.phase == "SEARCH" then
    collapseFloor(session, state)
    if state.ended then return end
    state.phase = "PAUSE"
    state.phaseTicksRemaining = session.config.getInt("gameplay.round_pause_ticks", 60)
    state.phaseTotalTicks = state.phaseTicksRemaining
    state.displayedTime = ticksToSeconds(state.phaseTicksRemaining)
  elseif state.phase == "PAUSE" then
    if #session.alivePlayers() <= 1 then
      M.endGameOnce(session)
      return
    end
    startRound(session, state, false)
  end
end

local function startGameLoop(session, state)
  startRound(session, state, true)

  local taskId = "arena_" .. session.arenaId .. "_block_party_loop"
  session.scheduler.runTimer(taskId, function()
    if state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end

    if state.phaseTicksRemaining > 0 then
      state.phaseTicksRemaining = state.phaseTicksRemaining - 1
    end

    updateActionBars(session, state)

    if state.phaseTicksRemaining <= 0 then
      advancePhase(session, state)
    end
  end, 0, 1)
end

local function scheduleMaxGameTime(session)
  if not session.config.getBoolean("gameplay.respect_max_game_time", false) then return end
  local maxTimeSeconds = session.dataAccess.getGameDataNumber("basic.time")
  if maxTimeSeconds == nil or maxTimeSeconds <= 0 then return end

  session.scheduler.runLater("arena_" .. session.arenaId .. "_block_party_max_time", function()
    if not session.state.ended then
      M.endGameOnce(session)
    end
  end, secondsToTicks(maxTimeSeconds))
end

local function spawnRegionParticles(session)
  local bounds = findArenaBounds(session, session.state.floor)
  if bounds == nil then return end

  local minX, maxX = math.min(bounds.min.x, bounds.max.x), math.max(bounds.min.x, bounds.max.x)
  local minZ, maxZ = math.min(bounds.min.z, bounds.max.z), math.max(bounds.min.z, bounds.max.z)
  local minY = math.min(bounds.min.y, bounds.max.y) + 0.5
  local maxY = math.max(bounds.min.y, bounds.max.y) + 1.5

  local spacing = math.max(0.5, session.config.getDouble("particles.region.spacing", 3.5))
  local perimeter = 2 * ((maxX - minX) + (maxZ - minZ))
  local samples = math.max(8, math.floor(perimeter / spacing + 0.5))

  local particle = session.config.getString("particles.region.type") or "NOTE"
  local count = session.config.getInt("particles.region.count", 6)
  local speed = session.config.getDouble("particles.region.speed", 0.02)

  for i = 1, samples do
    local verticalEdge = math.random() < 0.5
    local x, z
    if verticalEdge then
      x = (math.random() < 0.5) and (minX + 0.5) or (maxX + 0.5)
      z = minZ + 0.5 + math.random() * (maxZ - minZ)
    else
      x = minX + 0.5 + math.random() * (maxX - minX)
      z = (math.random() < 0.5) and (minZ + 0.5) or (maxZ + 0.5)
    end
    local y = minY + math.random() * (maxY - minY)
    if not session.world.spawnParticleAt({ x = x, y = y, z = z }, particle, count, 0, 0, 0, speed) then
      session.world.spawnParticleAt({ x = x, y = y, z = z }, "NOTE", count, 0, 0, 0, speed)
    end
  end
end

local function startRegionParticles(session)
  if not session.config.getBoolean("particles.region.enabled", true) then return end

  local taskId = "arena_" .. session.arenaId .. "_block_party_particles"
  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end
    spawnRegionParticles(session)
  end, 20, 20)
end

function M.handleGameStart(session)
  local state = session.state
  local gameMode = session.config.getString("gameplay.game_mode") or "SURVIVAL"

  for _, handle in ipairs(session.players()) do
    session.player.setGameMode(handle, gameMode)
    playerEffectsService.giveStartingItems(session, handle)
    playerEffectsService.applyStartingEffects(session, handle)
    session.scoreboard.show(handle, "scoreboard.main")
  end

  startRegionParticles(session)
  powerupService.startPowerupSpawns(session)
  startGameLoop(session, state)
  scheduleMaxGameTime(session)
end

function M.shouldEliminate(session, to)
  if not session.isInsideBounds(to) then return true end
  local state = session.state
  if state.floor == nil then return false end
  local minY = math.min(state.floor.min.y, state.floor.max.y)
  local margin = session.config.getDouble("gameplay.elimination_margin", 1.0)
  return to.y < minY - margin
end

function M.handlePlayerElimination(session, handle)
  local state = session.state
  local alreadySpectating = false
  for _, spectator in ipairs(session.spectators()) do
    if spectator == handle then alreadySpectating = true break end
  end
  if alreadySpectating then return end
  if state.eliminated[handle] then return end
  state.eliminated[handle] = true

  messagingService.broadcastDeathMessage(session, handle)
  session.eliminate(handle, session.config.translation(handle, "messages.eliminated"))
  session.player.clearInventory(handle)
  session.setSpectating(handle, true)
  session.sounds.play(handle, session.coreConfig.getSound("sounds.in_game.respawn"))

  if #session.alivePlayers() <= 1 then
    M.endGameOnce(session)
  end
end

function M.handlePowerupPickup(session, handle, location)
  local powerupType = powerupService.handlePowerupPickup(session, handle, location)
  if powerupType == nil then return end

  statsService.recordPowerupUsed(session, handle)
  local plainName = powerupService.plainName(powerupType)
  messagingService.sendPowerupCollected(session, handle, plainName)
end

function M.isPowerupBlock(session, location)
  return powerupService.isPowerupBlock(session, location)
end

function M.handleEnd(session)
  session.scheduler.cancelArenaTasks()
  fallingBlockService.cleanupAll(session)
  powerupService.removeActivePowerups(session)
  session.hologram.deleteArena()

  statsService.recordGamesPlayed(session)
  for _, handle in ipairs(session.players()) do
    session.sounds.stopMusic(handle)
  end
end

return M

local settingsSupport = require("support.settings")

local M = {}

local function resolveBounds(session)
  local min = session.dataAccess.getArenaLocation("bounds.min")
  local max = session.dataAccess.getArenaLocation("bounds.max")
  if min ~= nil and max ~= nil then return min, max end

  local spawn = session.arena.randomSpawn()
  if spawn == nil then return nil, nil end
  return
    { x = spawn.x - 8, y = spawn.y - 2, z = spawn.z - 8 },
    { x = spawn.x + 8, y = spawn.y + 8, z = spawn.z + 8 }
end

local function resolveConfiguredDouble(session, path, fallback)
  local configured = session.dataAccess.getGameDataNumber(path)
  if configured ~= nil and configured > 0 then return configured end
  return fallback
end

local function formatSeconds(seconds)
  if seconds < 0 then seconds = 0 end
  return string.format("%.1f", seconds)
end

local function sendDescription(session)
  for _, handle in ipairs(session.players()) do
    for _, line in ipairs(session.config.translationList(handle, "description.default")) do
      session.messages.sendRaw(handle, line)
    end
  end
end

function M.onStart(session)
  session.scheduler.cancelArenaTasks()

  local settings = settingsSupport.load(session)
  local boundsMin, boundsMax = resolveBounds(session)

  session.state = {
    settings = settings,
    round = 1,
    musicTime = resolveConfiguredDouble(session, "basic.initial_music_time", settings.initialMusicTime),
    sitTime = resolveConfiguredDouble(session, "basic.initial_sit_time", settings.initialSitTime),
    musicReduction = resolveConfiguredDouble(session, "basic.music_time_reduction", settings.musicTimeReduction),
    sitReduction = resolveConfiguredDouble(session, "basic.sit_time_reduction", settings.sitTimeReduction),
    boundsMin = boundsMin,
    boundsMax = boundsMax,
    phaseTime = 0,
    ended = false,
    activeSeats = {},
  }

  sendDescription(session)

  for _, handle in ipairs(session.players()) do
    session.player.setGameMode(handle, "SURVIVAL")
  end
end

function M.onCountdownTick(session, secondsLeft)
  for _, handle in ipairs(session.players()) do
    session.sounds.play(handle, session.coreConfig.getSound("sounds.starting_game.countdown"))
    local title = string.gsub(session.coreConfig.language(handle, "titles.starting_game.title"), "{game_display_name}", "Chairs")
    title = string.gsub(title, "{time}", tostring(secondsLeft))
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.starting_game.subtitle"), "{game_display_name}", "Chairs")
    subtitle = string.gsub(subtitle, "{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.onCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    local title = string.gsub(session.coreConfig.language(handle, "titles.game_started.title"), "{game_display_name}", "Chairs")
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.game_started.subtitle"), "{game_display_name}", "Chairs")
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 20)
    session.sounds.play(handle, session.coreConfig.getSound("sounds.starting_game.start"))
  end
end

local function playMusic(session)
  local tracks = session.state.settings.musicPlaylist
  if #tracks == 0 then return end
  local track = tracks[math.random(#tracks)]
  for _, handle in ipairs(session.players()) do
    session.sounds.play(handle, track)
  end
end

local function stopMusic(session)
  for _, handle in ipairs(session.players()) do
    session.sounds.stopMusic(handle)
  end
end

local function customPlaceholders(session)
  return {
    chairs_round = tostring(session.state.round),
    chairs_time = formatSeconds(session.state.phaseTime),
    alive = tostring(#session.alivePlayers()),
    spectators = tostring(#session.spectators()),
  }
end

local function updateDisplays(session, seatingPhase)
  local placeholders = customPlaceholders(session)
  local key = "action_bar.music"
  if seatingPhase then key = "action_bar.sit" end

  for _, handle in ipairs(session.players()) do
    local template = session.config.translation(handle, key)
    local actionBar = string.gsub(template, "{chairs_time}", placeholders.chairs_time)
    actionBar = string.gsub(actionBar, "{chairs_round}", placeholders.chairs_round)
    session.messages.sendActionBar(handle, actionBar)
    session.scoreboard.update(handle, "scoreboard.main", placeholders)
  end
end

local function findGroundY(session, blockX, blockZ, minY, maxY)
  local top = math.min(maxY, session.world.maxHeight() - 1)
  local bottom = math.max(minY, session.world.minHeight())

  for y = top, bottom, -1 do
    if not session.world.isPassable(blockX, y, blockZ) then
      return y
    end
  end

  return bottom
end

local function spawnSeats(session)
  local settings = session.state.settings
  local boundsMin, boundsMax = session.state.boundsMin, session.state.boundsMax
  if boundsMin == nil or boundsMax == nil then return end

  local alive = #session.alivePlayers()
  local seatCount = settingsSupport.resolveSeatCount(settings, session.state.round, alive)

  local minX, maxX = math.min(boundsMin.x, boundsMax.x), math.max(boundsMin.x, boundsMax.x)
  local minZ, maxZ = math.min(boundsMin.z, boundsMax.z), math.max(boundsMin.z, boundsMax.z)
  local minY, maxY = math.floor(math.min(boundsMin.y, boundsMax.y)), math.floor(math.max(boundsMin.y, boundsMax.y))

  for _ = 1, seatCount do
    local x = minX + 0.5 + math.random() * (maxX - minX)
    local z = minZ + 0.5 + math.random() * (maxZ - minZ)
    local groundY = findGroundY(session, math.floor(x), math.floor(z), minY, maxY)
    local spawnLocation = { x = x, y = groundY + settings.spawnHeightOffset, z = z }

    local seatType = settings.seatTypes[math.random(#settings.seatTypes)]
    local seat = session.world.spawnEntity(spawnLocation, seatType)
    if seat ~= nil then
      session.entities.prepareRideableSeat(seat)
      session.state.activeSeats[seat] = true
    end
  end
end

local function cleanupSeats(session)
  for handle, _ in pairs(session.state.activeSeats) do
    session.entities.remove(handle)
  end
  session.state.activeSeats = {}
end

local function eliminateStandingPlayers(session)
  for _, handle in ipairs(session.alivePlayers()) do
    local vehicle = session.entities.getVehicle(handle)
    if vehicle ~= nil and session.state.activeSeats[vehicle] then
      session.stats.add(handle, "rounds_survived", 1)
    else
      session.eliminate(handle, session.config.translation(handle, "messages.eliminated"))
      session.setSpectating(handle, true)
    end
  end
end

local function endGame(session)
  session.state.ended = true
  local alive = session.alivePlayers()
  if #alive > 0 then
    local winner = alive[1]
    session.setWinner(winner)
    session.stats.add(winner, "wins", 1)
  end
  session.endGame()
end

local function startDisplayLoop(session)
  local taskId = "arena_" .. session.arenaId .. "_chairs_display"
  if session.scheduler.isTaskRunning(taskId) then return end

  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end

    session.state.phaseTime = math.max(0, session.state.phaseTime - 0.05)
    local seatingPhase = next(session.state.activeSeats) ~= nil
    updateDisplays(session, seatingPhase)
  end, 0, 1)
end

local function runRound(session, first)
  if session.state.ended then return end

  if not first then
    session.state.round = session.state.round + 1
    session.state.musicTime = math.max(session.state.settings.minimumMusicTime, session.state.musicTime - session.state.musicReduction)
    session.state.sitTime = math.max(session.state.settings.minimumSitTime, session.state.sitTime - session.state.sitReduction)
  end

  playMusic(session)
  session.state.phaseTime = session.state.musicTime
  updateDisplays(session, false)

  local musicTicks = math.max(1, math.floor(session.state.musicTime * 20 + 0.5))
  session.scheduler.runLater("chairs_music_" .. session.arenaId, function()
    stopMusic(session)
    spawnSeats(session)
    session.state.phaseTime = session.state.sitTime
    updateDisplays(session, true)

    local sitTicks = math.max(1, math.floor(session.state.sitTime * 20 + 0.5))
    session.scheduler.runLater("chairs_sit_" .. session.arenaId, function()
      eliminateStandingPlayers(session)
      cleanupSeats(session)
      session.state.phaseTime = 0

      if #session.alivePlayers() <= 1 then
        endGame(session)
        return
      end
      runRound(session, false)
    end, sitTicks)
  end, musicTicks)

  startDisplayLoop(session)
end

function M.onGameStart(session)
  for _, handle in ipairs(session.players()) do
    session.scoreboard.show(handle, "scoreboard.main")
  end
  runRound(session, true)
end

function M.onEnd(session)
  session.scheduler.cancelArenaTasks()
  cleanupSeats(session)
  stopMusic(session)

  for _, handle in ipairs(session.players()) do
    session.stats.add(handle, "games_played", 1)
  end
end

return M

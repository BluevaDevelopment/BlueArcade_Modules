-- RewardService and StoreService's shredder/reset-wand/zapper/kit subsystem aren't ported - both
-- gated behind StoreAPI or a console-command binding, neither of which exists in this Lua layer.
local beastService = require("support.beast_service")
local disguiseService = require("support.disguise_service")
local cageService = require("support.cage_service")
local checkpointService = require("support.checkpoint_service")
local loadoutService = require("support.loadout_service")
local messagingService = require("support.messaging_service")
local distanceService = require("support.distance_service")

local M = {}

local function newState()
  return {
    ended = false,
    timeLeftSeconds = 0,
    releaseTimeSeconds = 0,
    cageBlocks = {},
    checkpoints = {},
    checkpointUses = {},
    beastId = nil,
    beastDisguiseHandle = nil,
  }
end

local function getGameTime(session)
  local ticks = session.dataAccess.getGameDataNumber("basic.time")
  if ticks and ticks > 0 then
    return math.floor(ticks)
  end
  return 240
end

function M.startGame(session)
  session.state = newState()

  session.summary.setGameSummaryEnabled(false)
  session.summary.setFinalSummaryEnabled(false)
  session.summary.setRewardsEnabled(false)

  session.scheduler.cancelArenaTasks()

  session.state.timeLeftSeconds = getGameTime(session)
  session.state.releaseTimeSeconds = session.config.getInt("game.release_delay_seconds", 15)
  session.state.cageBlocks = cageService.loadCageBlocks(session)
  cageService.restoreCage(session)

  messagingService.sendDescription(session)
end

function M.handleCountdownTick(session, secondsLeft)
  for _, handle in ipairs(session.players()) do
    session.sounds.play(handle, "sounds.starting_game.countdown")
    local title = (session.coreConfig.language(handle, "titles.starting_game.title") or "")
      :gsub("{game_display_name}", "Run From The Beast"):gsub("{time}", tostring(secondsLeft))
    local subtitle = (session.coreConfig.language(handle, "titles.starting_game.subtitle") or "")
      :gsub("{game_display_name}", "Run From The Beast"):gsub("{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.handleCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    local title = (session.coreConfig.language(handle, "titles.game_started.title") or ""):gsub("{game_display_name}", "Run From The Beast")
    local subtitle = (session.coreConfig.language(handle, "titles.game_started.subtitle") or ""):gsub("{game_display_name}", "Run From The Beast")
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 20)
    session.sounds.play(handle, "sounds.starting_game.start")
  end
end

local function isBeast(session, handle)
  return session.state.beastId ~= nil and session.state.beastId == handle
end
M.isBeast = isBeast

function M.getBeast(session)
  return beastService.getBeast(session)
end

function M.getAliveRunners(session)
  local runners = {}
  local beast = M.getBeast(session)
  for _, handle in ipairs(session.alivePlayers()) do
    if handle ~= beast then
      runners[#runners + 1] = handle
    end
  end
  return runners
end

local function preparePlayers(session)
  for _, handle in ipairs(session.players()) do
    session.player.setGameMode(handle, "SURVIVAL")
    session.player.setHealth(handle, session.player.maxHealth(handle))
    session.player.setFoodLevel(handle, 20)
    session.player.clearInventory(handle)
    distanceService.resetDistanceBar(session, handle)
    loadoutService.applyStartingEffects(session, handle, "effects.starting_effects")
    if not isBeast(session, handle) then
      loadoutService.giveItems(session, handle, "items.starting_items")
      checkpointService.giveCheckpointItems(session, handle)
    end
    session.scoreboard.showModule(handle)
  end

  local beast = M.getBeast(session)
  if beast then
    loadoutService.giveItems(session, beast, "items.beast_items")
    loadoutService.applyStartingEffects(session, beast, "effects.beast_effects")
    beastService.applyBeastGlow(session, beast)
    loadoutService.applyBeastEquipment(session, beast)
    disguiseService.apply(session, beast, "creeper")
    messagingService.sendBeastTitle(session, beast)
    session.messages.sendRaw(beast, session.config.translation(beast, "messages.roles.beast"))
    session.stats.add(beast, "beast_roles", 1)
  end

  for _, handle in ipairs(session.players()) do
    if handle ~= session.state.beastId then
      session.messages.sendRaw(handle, session.config.translation(handle, "messages.roles.runner"))
    end
  end
end

local function shouldNotifyRelease(session, seconds)
  local notifications = session.coreConfig.getSettingsStringList("game.global.countdown_notifications")
  if #notifications == 0 then
    notifications = { "15", "10", "5", "4", "3", "2", "1" }
  end
  for _, raw in ipairs(notifications) do
    if tonumber(raw) == seconds then
      return true
    end
  end
  return false
end

local function releaseBeast(session)
  local beast = M.getBeast(session)
  if beast then
    session.messages.sendRaw(beast, session.config.translation(beast, "messages.beast_released_beast"))
  end
  for _, handle in ipairs(session.players()) do
    if not beast or handle ~= beast then
      session.messages.sendRaw(handle, session.config.translation(handle, "messages.beast_released_runners"))
    end
  end
  cageService.clearCage(session)
end

local function startReleaseCountdown(session)
  local taskId = "arena_" .. session.arenaId .. "_rftb_release"
  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end
    if session.state.releaseTimeSeconds <= 0 then
      releaseBeast(session)
      session.scheduler.cancelTask(taskId)
      return
    end
    if shouldNotifyRelease(session, session.state.releaseTimeSeconds) then
      for _, handle in ipairs(session.players()) do
        local message = session.config.translation(handle, "messages.beast_release_countdown")
        if message then
          session.messages.sendRaw(handle, message:gsub("{time}", tostring(session.state.releaseTimeSeconds)))
        end
      end
    end
    session.state.releaseTimeSeconds = session.state.releaseTimeSeconds - 1
  end, 0, 20)
end

local function handleRunnerVictory(session, runners)
  for _, runner in ipairs(runners) do
    session.stats.add(runner, "runner_wins", 1)
  end

  local beast = M.getBeast(session)
  local placeholders = {
    beast = beast and session.player.name(beast) or "-",
    runner_count = tostring(#runners),
    runners = M.formatPlayerList(session, runners),
  }

  messagingService.sendOutcomeMessage(session, "messages.runners_win_lines", "messages.runners_win", placeholders)
  messagingService.sendVictoryTitles(session, "titles.victory.runners_won", placeholders)
  messagingService.showFinalScoreboard(session, "scoreboard.final.runners_won", placeholders)

  session.markSharedFirstPlace(runners)
  session.endGame()
end

local function handleBeastVictory(session, beast)
  if beast then
    session.stats.add(beast, "beast_wins", 1)
  end

  local runners = M.getAliveRunners(session)
  local placeholders = {
    beast = beast and session.player.name(beast) or "-",
    runner_count = tostring(#runners),
    runners = M.formatPlayerList(session, runners),
  }

  messagingService.sendOutcomeMessage(session, "messages.beast_win_lines", "messages.beast_wins", placeholders)
  messagingService.sendVictoryTitles(session, "titles.victory.beast_won", placeholders)
  messagingService.showFinalScoreboard(session, "scoreboard.final.beast_won", placeholders)

  if beast then
    session.setWinner(beast)
  end
  session.endGame()
end

local function startGameTimer(session)
  local taskId = "arena_" .. session.arenaId .. "_rftb_timer"
  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end

    if session.state.timeLeftSeconds <= 0 then
      session.state.ended = true
      session.endGame()
      return
    end

    local alivePlayers = session.alivePlayers()
    if #alivePlayers < 2 then
      session.state.ended = true
      session.endGame()
      return
    end

    local beast = M.getBeast(session)
    local beastAlive = false
    for _, handle in ipairs(alivePlayers) do
      if handle == beast then
        beastAlive = true
        break
      end
    end

    local runners = M.getAliveRunners(session)
    if not beastAlive then
      session.state.ended = true
      handleRunnerVictory(session, runners)
      return
    end

    if #runners == 0 then
      session.state.ended = true
      handleBeastVictory(session, beast)
      return
    end

    for _, handle in ipairs(session.players()) do
      local placeholders = messagingService.buildCustomPlaceholders(session, handle, beast, #runners)
      messagingService.sendActionBar(session, handle, placeholders)
    end

    session.state.timeLeftSeconds = session.state.timeLeftSeconds - 1
  end, 0, 20)
end

local function startDistanceTracking(session)
  if not session.config.getBoolean("distance_bar.enabled", true) then
    return
  end
  local interval = math.max(1, session.config.getInt("distance_bar.update_interval_ticks", 10))
  local taskId = "arena_" .. session.arenaId .. "_rftb_distance"
  session.scheduler.runTimer(taskId, function()
    if session.state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end
    distanceService.updateDistanceBars(session, M.getBeast(session))
  end, 0, interval)
end

function M.beginPlaying(session)
  session.state.releaseTimeSeconds = session.config.getInt("game.release_delay_seconds", 15)
  if #session.state.cageBlocks == 0 then
    session.state.cageBlocks = cageService.loadCageBlocks(session)
  end

  beastService.selectBeast(session)
  preparePlayers(session)
  startReleaseCountdown(session)
  startGameTimer(session)
  startDistanceTracking(session)
end

local function broadcastOutOfBoundsMessage(session, victim, deathBlock)
  local path = deathBlock and "messages.deaths.death_block" or "messages.deaths.void"
  local message = messagingService.getRandomMessage(session, path)
  if not message then
    return
  end
  message = message:gsub("{player}", session.player.name(victim))
  for _, handle in ipairs(session.players()) do
    session.messages.sendRaw(handle, message)
  end
end

local function resolveVoidFallAction(session, player)
  local path = isBeast(session, player) and "game.void_fall.beast_action" or "game.void_fall.runners_action"
  local value = session.config.getString(path) or "RESPAWN"
  return value:upper()
end

function M.handleOutOfBounds(session, player, deathBlock)
  if session.state.ended then
    return
  end

  local action = resolveVoidFallAction(session, player)
  if action == "ELIMINATE" then
    M.handleDamage(session, player, nil)
    broadcastOutOfBoundsMessage(session, player, deathBlock)
    return
  end

  local deathLocation = session.player.location(player)
  session.visualEffects.playDeathEffect(player, deathLocation)
  session.respawnPlayer(player)
  loadoutService.applyStartingEffects(session, player, "effects.respawn_effects")
  broadcastOutOfBoundsMessage(session, player, deathBlock)
end

local function isSpectator(session, handle)
  for _, spectator in ipairs(session.spectators()) do
    if spectator == handle then
      return true
    end
  end
  return false
end

function M.handleDamage(session, victim, killer)
  if session.state.ended then
    return
  end
  if isSpectator(session, victim) then
    return
  end

  local deathLocation = session.player.location(victim)
  session.visualEffects.playDeathEffect(victim, deathLocation)
  if killer then
    session.visualEffects.playKillEffect(killer)
  end

  if isBeast(session, victim) then
    disguiseService.remove(session, victim)
    if killer then
      session.stats.add(killer, "runner_kills", 1)
    end
    session.setSpectating(victim, true)
    session.player.clearInventory(victim)
    distanceService.resetDistanceBar(session, victim)
    session.state.ended = true
    handleRunnerVictory(session, M.getAliveRunners(session))
    return
  end

  session.eliminate(victim, session.config.translation(victim, "messages.eliminated"))
  session.player.clearInventory(victim)
  session.setSpectating(victim, true)
  distanceService.resetDistanceBar(session, victim)

  if killer and isBeast(session, killer) then
    session.stats.add(killer, "beast_kills", 1)
    messagingService.broadcastBeastKill(session, victim, killer)
  end

  if #M.getAliveRunners(session) == 0 then
    local beast = M.getBeast(session)
    if beast then
      session.state.ended = true
      handleBeastVictory(session, beast)
    end
  end
end

function M.handleDisguiseDamage(session, attacker, damage)
  local beast = M.getBeast(session)
  if not beast or not attacker or attacker == beast or damage <= 0.0 then
    return
  end
  if not session.isPlaying(attacker) then
    return
  end
  session.player.damageBy(beast, damage, attacker)
end

function M.onEnd(session)
  session.scheduler.cancelArenaTasks()
  cageService.restoreCage(session)
  beastService.removeBeastGlow(session)
  disguiseService.remove(session, M.getBeast(session))
  distanceService.resetDistanceBars(session)

  for _, handle in ipairs(session.players()) do
    session.stats.add(handle, "games_played", 1)
  end
end

function M.formatPlayerList(session, players)
  if #players == 0 then
    return "-"
  end
  local names = {}
  for _, handle in ipairs(players) do
    names[#names + 1] = session.player.name(handle)
  end
  return table.concat(names, ", ")
end

function M.getCustomPlaceholders(session, handle)
  local beast = M.getBeast(session)
  local runnersAlive = #M.getAliveRunners(session)
  return messagingService.buildCustomPlaceholders(session, handle, beast, runnersAlive)
end

return M

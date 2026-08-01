local loadoutService = require("support.loadout_service")
local messagingService = require("support.messaging_service")
local statsService = require("support.stats_service")

local M = {}

local DEFAULT_GAME_TIME = 180

function M.winMode(session)
  local mode = session.dataAccess.getGameDataString("basic.win_mode")
  if mode == nil then return "last_standing" end
  mode = string.lower(mode)
  if mode ~= "last_standing" and mode ~= "most_kills" then return "last_standing" end
  return mode
end

local function deathBlock(session)
  local name = session.dataAccess.getGameDataString("basic.death_block")
  if name == nil then return "BARRIER" end
  return string.upper(name)
end

M.deathBlock = deathBlock

local function scoreboardPath(session)
  return "scoreboard." .. M.winMode(session)
end

local function modeLabel(session, handle, mode)
  if mode == "most_kills" then
    return session.config.translation(handle, "scoreboard.mode_labels.most_kills")
  end
  return session.config.translation(handle, "scoreboard.mode_labels.last_standing")
end

local function formatTime(seconds)
  if seconds < 0 then seconds = 0 end
  return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function playerKills(session, handle)
  return session.state.kills[handle] or 0
end

local function topPlayersByKills(session)
  local entries = {}
  for _, handle in ipairs(session.players()) do
    entries[#entries + 1] = { handle = handle, kills = playerKills(session, handle), name = session.player.name(handle) }
  end
  table.sort(entries, function(a, b)
    if a.kills ~= b.kills then return a.kills > b.kills end
    return string.lower(a.name) < string.lower(b.name)
  end)
  local top = {}
  for i = 1, math.min(5, #entries) do
    top[i] = entries[i]
  end
  return top
end

local function customPlaceholders(session, handle)
  local mode = M.winMode(session)
  local placeholders = {
    alive = tostring(#session.alivePlayers()),
    spectators = tostring(#session.spectators()),
    kills = tostring(playerKills(session, handle)),
    mode = modeLabel(session, handle, mode),
  }
  if mode == "most_kills" then
    local top = topPlayersByKills(session)
    for i = 1, 5 do
      if top[i] ~= nil then
        placeholders["place_" .. i] = top[i].name
        placeholders["kills_" .. i] = tostring(top[i].kills)
      else
        placeholders["place_" .. i] = "-"
        placeholders["kills_" .. i] = "0"
      end
    end
  end
  return placeholders
end

local function handleWin(session, handle)
  if session.state.winnerCredited then return end
  session.state.winnerCredited = true
  statsService.recordWin(session, handle)
end

function M.handlePlayerElimination(session, target, killer)
  if session.state.spectatorHandles[target] then return end

  session.visualEffects.playDeathEffect(target)
  if killer ~= nil then session.visualEffects.playKillEffect(killer) end

  local mode = M.winMode(session)
  if mode == "most_kills" then
    session.player.setGameMode(target, "SPECTATOR")
    session.player.clearInventory(target)
    messagingService.sendDeathTitle(session, target)
    messagingService.broadcastDeathMessage(session, target, killer)

    local delayTicks = session.config.getInt("respawn.most_kills_delay_ticks", 60)
    if delayTicks < 0 then delayTicks = 0 end
    session.scheduler.runLater("snowball_fight_respawn_" .. session.arenaId .. "_" .. target, function()
      if session.state.ended or not session.isPlaying(target) then return end
      session.respawnPlayer(target)
      session.player.setGameMode(target, "SURVIVAL")
      loadoutService.giveStartingItems(session, target)
      loadoutService.applyStartingEffects(session, target)
      loadoutService.applyRespawnEffects(session, target)
      messagingService.playRespawnSound(session, target)
    end, delayTicks)
    return
  end

  messagingService.broadcastDeathMessage(session, target, killer)
  session.eliminate(target, session.config.translation(target, "messages.eliminated"))
  session.player.clearInventory(target)
  session.setSpectating(target, true)
  session.state.spectatorHandles[target] = true
  messagingService.playDeathSound(session, target)
  messagingService.sendDeathTitle(session, target)
end

function M.handleSnowballThrown(session, handle)
  statsService.recordSnowballThrown(session, handle)
end

function M.handleSnowballHit(session, handle)
  statsService.recordSnowballHit(session, handle)
end

function M.handleKillCredit(session, killer)
  statsService.recordSnowballKill(session, killer)
  session.state.kills[killer] = playerKills(session, killer) + 1
end

local function giveTimedItems(session)
  local interval = session.config.getInt("items.snowball_interval_ticks", 20)
  local amount = session.config.getInt("items.snowballs_per_interval", 4)
  if interval <= 0 or amount <= 0 then return end

  session.state.snowballTicks = session.state.snowballTicks + 20
  if session.state.snowballTicks % interval ~= 0 then return end

  for _, handle in ipairs(session.players()) do
    if session.isPlaying(handle) then
      session.player.giveItem(handle, "SNOWBALL", amount, -1)
    end
  end
end

local function handleMostKillsOutcome(session)
  local top = topPlayersByKills(session)
  if #top == 0 then return end

  session.setWinner(top[1].handle)
  handleWin(session, top[1].handle)

  for i = 2, #top do
    if session.isPlaying(top[i].handle) then
      session.finishPlayer(top[i].handle)
    end
  end
end

local function endGameOnce(session)
  if session.state.ended then return end
  session.state.ended = true

  session.scheduler.cancelArenaTasks()

  local mode = M.winMode(session)
  local alive = session.alivePlayers()
  if #alive == 1 and mode == "last_standing" then
    session.setWinner(alive[1])
    handleWin(session, alive[1])
  end

  if mode == "most_kills" then
    handleMostKillsOutcome(session)
  end

  session.endGame()
end

local function startGameTimer(session)
  local gameTime = session.dataAccess.getGameDataNumber("basic.time")
  if gameTime == nil or gameTime == 0 then gameTime = DEFAULT_GAME_TIME end
  session.state.timeLeft = math.floor(gameTime)

  session.scheduler.runTimer("arena_" .. session.arenaId .. "_snowball_fight_timer", function()
    if session.state.ended then
      session.scheduler.cancelTask("arena_" .. session.arenaId .. "_snowball_fight_timer")
      return
    end

    session.state.timeLeft = session.state.timeLeft - 1

    local alive = session.alivePlayers()
    if #alive <= 1 or session.state.timeLeft <= 0 then
      endGameOnce(session)
      return
    end

    giveTimedItems(session)
    for _, handle in ipairs(session.players()) do
      local template = session.coreConfig.language(handle, "action_bar.in_game.global")
      if template ~= nil then
        local message = string.gsub(template, "{time}", formatTime(session.state.timeLeft))
        message = string.gsub(message, "{round}", tostring(session.currentRound))
        message = string.gsub(message, "{round_max}", tostring(session.maxRounds))
        session.messages.sendActionBar(handle, message)
      end
      session.scoreboard.update(handle, scoreboardPath(session), customPlaceholders(session, handle))
    end
  end, 0, 20)
end

function M.handleStart(session)
  session.scheduler.cancelArenaTasks()

  session.state = {
    kills = {},
    ended = false,
    winnerCredited = false,
    snowballTicks = 0,
    timeLeft = 0,
    spectatorHandles = {},
  }
  for _, handle in ipairs(session.players()) do
    session.state.kills[handle] = 0
  end

  messagingService.sendDescription(session, M.winMode(session))
end

function M.handleCountdownTick(session, secondsLeft)
  messagingService.sendCountdownTick(session, secondsLeft)
end

function M.handleCountdownFinish(session)
  messagingService.sendCountdownFinish(session)
end

function M.handleGameStart(session)
  startGameTimer(session)

  for _, handle in ipairs(session.players()) do
    session.player.setGameMode(handle, "SURVIVAL")
    loadoutService.giveStartingItems(session, handle)
    loadoutService.applyStartingEffects(session, handle)
    loadoutService.applyRespawnEffects(session, handle)
    session.scoreboard.show(handle, scoreboardPath(session))
  end
end

function M.handleEnd(session)
  session.scheduler.cancelArenaTasks()
  for _, handle in ipairs(session.players()) do
    statsService.recordGamePlayed(session, handle)
  end
end

-- Mirrors legacy handleDisable(): cancel tasks only, no winner, no stats.
function M.handleDisable(session)
  session.scheduler.cancelArenaTasks()
end

function M.respawnOutOfBounds(session, handle)
  session.respawnPlayer(handle)
  loadoutService.applyRespawnEffects(session, handle)
  messagingService.playRespawnSound(session, handle)
end

return M

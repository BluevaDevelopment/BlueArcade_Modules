--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

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

function M.getCustomPlaceholders(session, handle)
  return customPlaceholders(session, handle)
end

local function handleWin(session, handle)
  if session.state.winnerCredited then return end
  session.state.winnerCredited = true
  statsService.recordWin(session, handle)
end

local function giveLoadout(session, handle)
  loadoutService.giveKnockbackStick(session, handle)
  loadoutService.giveStartingItems(session, handle)
  loadoutService.applyStartingEffects(session, handle)
  loadoutService.applyRespawnEffects(session, handle)
end

function M.handleKnockbackHit(session, attacker, victim)
  statsService.recordKnockbackHit(session, attacker)
  session.state.lastHitBy[victim] = attacker
  session.state.lastHitTime[victim] = os.time()
end

-- os.time() is second-precision (the sandbox has no millis clock), so the credit window is
-- rounded up to whole seconds rather than matching the legacy tick-exact comparison.
local function recentKiller(session, victim)
  local killer = session.state.lastHitBy[victim]
  local hitTime = session.state.lastHitTime[victim]
  if killer == nil or hitTime == nil then return nil end

  local windowTicks = session.config.getInt("kills.credit_window_ticks", 200)
  local windowSeconds = math.ceil(windowTicks * 50 / 1000)
  if os.time() - hitTime > windowSeconds then return nil end

  for _, handle in ipairs(session.players()) do
    if handle == killer then return handle end
  end
  return nil
end

function M.handleKillCredit(session, killer)
  statsService.recordKnockbackKill(session, killer)
  session.state.kills[killer] = playerKills(session, killer) + 1
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

  session.scheduler.runTimer("arena_" .. session.arenaId .. "_knockback_timer", function()
    if session.state.ended then
      session.scheduler.cancelTask("arena_" .. session.arenaId .. "_knockback_timer")
      return
    end

    session.state.timeLeft = session.state.timeLeft - 1

    local alive = session.alivePlayers()
    if #alive <= 1 or session.state.timeLeft <= 0 then
      endGameOnce(session)
      return
    end

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
    lastHitBy = {},
    lastHitTime = {},
    fallingPlayers = {},
    ended = false,
    winnerCredited = false,
    timeLeft = 0,
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
    giveLoadout(session, handle)
    session.scoreboard.show(handle, scoreboardPath(session))
  end
end

function M.handleEnd(session)
  session.scheduler.cancelArenaTasks()
  for _, handle in ipairs(session.players()) do
    statsService.recordGamePlayed(session, handle)
  end
end

function M.respawnOutOfBounds(session, handle)
  session.respawnPlayer(handle)
  loadoutService.applyRespawnEffects(session, handle)
end

function M.handlePlayerFall(session, handle)
  if session.state.ended then return end
  if session.state.fallingPlayers[handle] then return end
  session.state.fallingPlayers[handle] = true

  local killer = recentKiller(session, handle)
  if killer ~= nil then
    M.handleKillCredit(session, killer)
  end

  session.visualEffects.playDeathEffect(handle)
  if killer ~= nil then session.visualEffects.playKillEffect(killer) end

  local mode = M.winMode(session)
  messagingService.broadcastDeathMessage(session, handle, killer)

  if mode == "most_kills" then
    session.player.setGameMode(handle, "SPECTATOR")
    session.player.clearInventory(handle)

    local delayTicks = session.config.getInt("respawn.most_kills_delay_ticks", 60)
    if delayTicks < 0 then delayTicks = 0 end
    session.scheduler.runLater("knockback_respawn_" .. session.arenaId .. "_" .. handle, function()
      session.state.fallingPlayers[handle] = nil
      if session.state.ended or not session.isPlaying(handle) then return end
      session.respawnPlayer(handle)
      session.player.setGameMode(handle, "SURVIVAL")
      giveLoadout(session, handle)
      messagingService.playRespawnSound(session, handle)
    end, delayTicks)
    return
  end

  session.eliminate(handle, session.config.translation(handle, "messages.eliminated"))
  session.player.clearInventory(handle)
  session.setSpectating(handle, true)
  if killer ~= nil then
    messagingService.playDeathSound(session, handle)
    messagingService.sendYouDiedTitle(session, handle)
  else
    messagingService.playClassifiedSound(session, handle)
    messagingService.sendClassifiedTitle(session, handle)
  end
end

return M

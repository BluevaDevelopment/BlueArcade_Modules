--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local placeholderService = require("support.placeholder_service")

local M = {}

local function getWinMode(session)
  local mode = session.dataAccess.getGameDataString("basic.win_mode")
  if mode == nil then return "last_standing" end
  mode = string.lower(mode)
  if mode ~= "last_standing" and mode ~= "most_kills" then return "last_standing" end
  return mode
end

local function declareWinner(session, winner)
  session.setWinner(winner)

  if session.state.winnerId ~= nil then return end
  session.state.winnerId = winner
  session.stats.add(winner, "wins", 1)
end

local function handleMostKillsOutcome(session)
  local topPlayers = placeholderService.getPlayersSortedByKills(session, session.players(), #session.players())
  if #topPlayers == 0 then return end

  declareWinner(session, topPlayers[1])

  for i = 2, #topPlayers do
    local handle = topPlayers[i]
    if session.isPlaying(handle) then
      session.finishPlayer(handle)
    end
  end
end

local function handleLastStandingTimeout(session)
  local alive = session.alivePlayers()
  local sorted = placeholderService.getPlayersSortedByKills(session, alive, #alive)
  if #sorted == 0 then return end

  declareWinner(session, sorted[1])

  for i = 2, #sorted do
    local handle = sorted[i]
    if session.isPlaying(handle) then
      session.finishPlayer(handle)
    end
  end
end

function M.endGame(session)
  if session.state.ended then return end
  session.state.ended = true

  session.scheduler.cancelArenaTasks()

  local alivePlayers = session.alivePlayers()
  local winMode = getWinMode(session)

  if #alivePlayers == 1 and winMode == "last_standing" then
    declareWinner(session, alivePlayers[1])
  elseif #alivePlayers > 1 and winMode == "last_standing" then
    handleLastStandingTimeout(session)
  end

  if winMode == "most_kills" then
    handleMostKillsOutcome(session)
  end

  session.endGame()
end

return M

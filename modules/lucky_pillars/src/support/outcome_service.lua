--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- gameManager is passed in explicitly (not required) to avoid a require cycle, since game_manager.lua requires this file.
local M = {}

local function handleWinStats(session, winners)
  if #winners == 0 or session.state.winnerId then
    return
  end
  session.state.winnerId = winners[1]
  for _, handle in ipairs(winners) do
    session.stats.add(handle, "wins", 1)
  end
end

local function declareWinningTeam(session, gameManager, teamId)
  local winners = gameManager.getTeamPlayers(session, teamId)
  if session.teams.isEnabled() then
    session.teams.setWinner(teamId)
  end
  if #winners > 0 then
    session.markSharedFirstPlace(winners)
  end
  handleWinStats(session, winners)
end

local function declareTopTeamByKills(session, gameManager)
  local teamKills = gameManager.getTeamKills(session)
  local maxKills = -1
  local any = false
  for _, kills in pairs(teamKills) do
    any = true
    if kills > maxKills then
      maxKills = kills
    end
  end
  if not any then
    M.handleNoWinner(session, gameManager)
    return
  end

  local topTeams = {}
  for teamId, kills in pairs(teamKills) do
    if kills == maxKills then
      topTeams[#topTeams + 1] = teamId
    end
  end

  if session.teams.isEnabled() then
    session.teams.setWinners(topTeams)
  end

  local winners = {}
  for _, teamId in ipairs(topTeams) do
    for _, handle in ipairs(gameManager.getTeamPlayers(session, teamId)) do
      winners[#winners + 1] = handle
    end
  end
  if #winners > 0 then
    session.markSharedFirstPlace(winners)
  end
  handleWinStats(session, winners)
end

function M.handleNoWinner(session, gameManager)
  local candidates = session.alivePlayers()
  if #candidates == 0 then
    candidates = session.players()
  end
  local sortedByKills = gameManager.getPlayersSortedByKills(session, candidates, #candidates)
  if #sortedByKills == 0 then
    return
  end
  session.markSharedFirstPlace({ sortedByKills[1] })
end

function M.endGame(session, gameManager)
  if session.state.ended then
    return
  end
  session.state.ended = true

  session.scheduler.cancelArenaTasks()

  local aliveTeams = gameManager.getAliveTeamIds(session)
  if #aliveTeams == 1 then
    declareWinningTeam(session, gameManager, aliveTeams[1])
  elseif #aliveTeams == 0 then
    M.handleNoWinner(session, gameManager)
  else
    declareTopTeamByKills(session, gameManager)
  end

  session.endGame()
end

return M

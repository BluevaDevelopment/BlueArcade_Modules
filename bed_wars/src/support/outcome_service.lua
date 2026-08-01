-- Mirrors legacy OutcomeService.java - declares a winning team (the last team with either an
-- intact bed or a living player) or, if none, the team(s) tied for most kills, then a final
-- scoreboard and the "wins" stat (first-winner-only, matching legacy's own `state.getWinnerId()`
-- guard).
local M = {}

local function showFinalScoreboard(session, gameManager, winningTeamId)
  local winningDisplay = winningTeamId or "-"
  if session.teams.isEnabled() and winningTeamId then
    for _, team in ipairs(session.teams.all()) do
      if team.id and team.id:lower() == winningTeamId:lower() then
        winningDisplay = team.displayName or winningTeamId
        break
      end
    end
  end

  local placeholderService = require("support.placeholder_service")
  local topKillers = placeholderService.getPlayersSortedByKills(session, gameManager, session.players(), 5)

  local basePlaceholders = { winning_team = winningDisplay }
  for i = 1, 5 do
    local killer = topKillers[i]
    if killer then
      basePlaceholders["top_kills_" .. i] = session.player.name(killer)
      basePlaceholders["top_kills_value_" .. i] = tostring(gameManager.getPlayerKills(session, killer))
    else
      basePlaceholders["top_kills_" .. i] = "-"
      basePlaceholders["top_kills_value_" .. i] = "0"
    end
  end

  for _, handle in ipairs(session.players()) do
    local placeholders = {}
    for k, v in pairs(basePlaceholders) do placeholders[k] = v end
    for k, v in pairs(gameManager.getCustomPlaceholders(session, handle)) do placeholders[k] = v end
    session.scoreboard.showFinalModule(handle, "scoreboard.final.winner", placeholders)
  end
end

local function handleWinStats(session, winners)
  if #winners == 0 then return end
  if session.state.winnerId then return end
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
  showFinalScoreboard(session, gameManager, teamId)
  handleWinStats(session, winners)
end

local function declareTopTeamByKills(session, gameManager)
  local teamKills = gameManager.getTeamKills(session)
  local maxKills, hasAny = 0, false
  for _, kills in pairs(teamKills) do
    hasAny = true
    if kills > maxKills then maxKills = kills end
  end

  if not hasAny then
    local sorted = require("support.placeholder_service").getPlayersSortedByKills(session, gameManager, session.players(), #session.players())
    if #sorted > 0 then
      session.markSharedFirstPlace({ sorted[1] })
    end
    return
  end

  local topTeams = {}
  for teamId, kills in pairs(teamKills) do
    if kills == maxKills then topTeams[#topTeams + 1] = teamId end
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

  showFinalScoreboard(session, gameManager, topTeams[1] or "-")
  handleWinStats(session, winners)
end

function M.endGame(session, gameManager)
  if session.state.ended then return end
  session.state.ended = true

  session.scheduler.cancelArenaTasks()

  if session.teams.isEnabled() then
    local bedService = require("support.bed_service")
    for _, team in ipairs(session.teams.all()) do
      if team.id and team.id ~= "" and bedService.isTeamAlive(session, team.id) then
        declareWinningTeam(session, gameManager, team.id)
        session.endGame()
        return
      end
    end
  end

  declareTopTeamByKills(session, gameManager)
  session.endGame()
end

return M

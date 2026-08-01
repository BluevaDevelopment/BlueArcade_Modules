-- Mirrors legacy PlaceholderService.java, including the zero-width-space `uniqueSuffix` trick: a real client hides
-- scoreboard lines with duplicate text, so identical filler lines each need a distinct invisible suffix to render at all.
local woolService = require("support.wool_service")

local M = {}

local ZERO_WIDTH_SPACE = "\226\128\139"

local function uniqueSuffix(teamIndex, slotIndex)
  local count = math.max(1, (teamIndex * 3) + slotIndex)
  return ZERO_WIDTH_SPACE:rep(count)
end

local function compareWoolIds(a, b)
  local na, nb = tonumber(a), tonumber(b)
  if na and nb then
    return na < nb
  end
  return a:lower() < b:lower()
end

function M.getPlayersSortedByKills(session, gameManager, candidates, limit)
  local entries = {}
  for _, handle in ipairs(candidates) do
    entries[#entries + 1] = { handle = handle, kills = gameManager.getPlayerKills(session, handle) }
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

local function buildObjectiveLine(session, def, playerOwnsTeam, teamIndex, objectiveIndex)
  local state = woolService.getWoolState(session, def.key)
  local checkbox, label
  if state == "CAPTURED" then
    checkbox = "<red>☒</red>"
    label = playerOwnsTeam and "<red>Lost</red>" or "<green>Captured</green>"
  elseif state == "CARRIED" then
    checkbox = "<gold>☐</gold>"
    label = playerOwnsTeam and "<gold>Under Attack</gold>" or "<gold>Taken</gold>"
  else
    checkbox = "<green>☐</green>"
    label = playerOwnsTeam and "<green>Defended</green>" or "<green>Safe</green>"
  end
  return "<gray>-</gray> " .. checkbox .. " " .. label .. uniqueSuffix(teamIndex, objectiveIndex)
end

local function buildTeamSummaryPlaceholders(session, gameManager, teams, placeholders, playerTeam)
  local teamKills = gameManager.getTeamKills(session)
  local teamDeaths = gameManager.getTeamDeaths(session)

  local index = 1
  for _, teamInfo in ipairs(teams) do
    if teamInfo.id and teamInfo.id ~= "" then
      local teamId = teamInfo.id
      local isPlayerTeam = playerTeam ~= nil and playerTeam.id ~= nil and playerTeam.id:lower() == teamId:lower()

      local captured = woolService.getTeamCapturedObjectives(session, teamId)
      local total = woolService.getTeamObjectiveCount(session, teamId)
      local kills = teamKills[teamId] or 0
      local deaths = teamDeaths[teamId] or 0

      placeholders["team_header_" .. index] = "<white>" .. teamInfo.displayName
        .. (isPlayerTeam and " <green><bold><- You</bold></green>" or "") .. "</white>" .. uniqueSuffix(index, 0)
      placeholders["team_summary_" .. index] = "<white>" .. teamInfo.displayName .. "</white> <gray>W "
        .. captured .. "/" .. total .. " • K " .. kills .. " • D " .. deaths .. "</gray>"

      local teamWools = {}
      for _, def in ipairs(session.state.woolDefinitions) do
        if def.ownerTeamId == teamId:lower() then
          teamWools[#teamWools + 1] = def
        end
      end
      table.sort(teamWools, function(a, b) return compareWoolIds(a.woolId, b.woolId) end)

      for obj = 1, 2 do
        local key = "team_objective_" .. index .. "_" .. obj
        if obj <= #teamWools then
          placeholders[key] = buildObjectiveLine(session, teamWools[obj], isPlayerTeam, index, obj)
        else
          placeholders[key] = "<dark_gray>·</dark_gray>" .. uniqueSuffix(index, obj)
        end
      end

      index = index + 1
    end
  end

  for i = index, 6 do
    placeholders["team_header_" .. i] = "<black>.</black>" .. uniqueSuffix(i, 0)
    placeholders["team_summary_" .. i] = " "
    placeholders["team_objective_" .. i .. "_1"] = "<black>.</black>" .. uniqueSuffix(i, 1)
    placeholders["team_objective_" .. i .. "_2"] = "<black>.</black>" .. uniqueSuffix(i, 2)
  end
end

function M.buildPlaceholders(session, handle, gameManager)
  local placeholders = {}
  placeholders.alive = tostring(#session.alivePlayers())
  placeholders.spectators = tostring(#session.spectators())
  placeholders.kills = tostring(gameManager.getPlayerKills(session, handle))
  placeholders.deaths = tostring(gameManager.getPlayerDeaths(session, handle))
  placeholders.alive_teams = tostring(#gameManager.getAliveTeamIds(session))

  local carryingYes = session.config.translation(handle, "messages.common.boolean_true")
  local carryingNo = session.config.translation(handle, "messages.common.boolean_false")
  placeholders.carrying_wool = woolService.isPlayerCarryingWool(session, handle) and carryingYes or carryingNo

  if session.teams.isEnabled() then
    local team = session.teams.forPlayer(handle)
    placeholders.team = team and team.displayName or "-"

    if team then
      placeholders.team_wools_captured = tostring(woolService.getTeamCapturedObjectives(session, team.id))
      placeholders.team_wools_total = tostring(woolService.getTeamObjectiveCount(session, team.id))
    else
      placeholders.team_wools_captured = "0"
      placeholders.team_wools_total = "0"
    end

    local teams = session.teams.all()
    for index, teamInfo in ipairs(teams) do
      if teamInfo.id and teamInfo.id ~= "" then
        local teamId = teamInfo.id:lower()
        local woolStatus = woolService.buildWoolStatusLine(session, teamId)
        if not woolStatus or woolStatus == "" then
          woolStatus = "⬜"
        end
        placeholders["wool_status_" .. teamId] = woolStatus
        placeholders["wool_status_team_" .. index] = woolStatus
        placeholders["wool_status_team_" .. teamId] = woolStatus
      end
    end

    if team and team.id then
      placeholders.wool_status_team_id = placeholders["wool_status_team_" .. team.id:lower()] or "⬜"
    end

    buildTeamSummaryPlaceholders(session, gameManager, teams, placeholders, team)
  else
    placeholders.team = "-"
  end

  return placeholders
end

return M

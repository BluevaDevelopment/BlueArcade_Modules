--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy PlaceholderService.java. `uniqueSuffix`'s zero-width-space padding keeps
-- otherwise-identical filler scoreboard lines from being deduped by Bukkit's scoreboard API.
local bedService = require("support.bed_service")

local M = {}

local function hasTeamAnyPlayers(session, teamId)
  if not session.teams.isEnabled() then
    return true
  end
  for _, handle in ipairs(session.players()) do
    local pTeam = session.teams.forPlayer(handle)
    if pTeam and pTeam.id:lower() == teamId:lower() then
      return true
    end
  end
  return false
end

local function lang(session, handle, path, fallback)
  local value = session.config.translation(handle, path)
  return value or fallback
end

local function uniqueSuffix(teamIndex, slotIndex)
  local count = math.max(1, (teamIndex * 3) + slotIndex)
  return ("\u{200B}"):rep(count)
end

local function buildBedStatusLine(session, team, viewerHandle)
  local teamId = team.id
  local teamDisplay = team.displayName or teamId
  local bedIntact = bedService.isTeamBedIntact(session, teamId)

  local hasAlivePlayers = false
  for _, handle in ipairs(session.alivePlayers()) do
    local pTeam = session.teams.forPlayer(handle)
    if pTeam and pTeam.id:lower() == teamId:lower() then
      hasAlivePlayers = true
      break
    end
  end

  local status
  if bedIntact then
    status = lang(session, viewerHandle, "messages.team_status.bed_intact", "<green>\u{2714}</green>")
  elseif hasAlivePlayers then
    local aliveCount = 0
    for _, handle in ipairs(session.alivePlayers()) do
      local pTeam = session.teams.forPlayer(handle)
      if pTeam and pTeam.id:lower() == teamId:lower() then
        aliveCount = aliveCount + 1
      end
    end
    status = lang(session, viewerHandle, "messages.team_status.alive_count", "<yellow>{count}</yellow>"):gsub("{count}", tostring(aliveCount))
  else
    status = lang(session, viewerHandle, "messages.team_status.eliminated", "<red>\u{2718}</red>")
  end

  local viewerTeam = viewerHandle and session.teams.forPlayer(viewerHandle)
  local isOwnTeam = viewerTeam and viewerTeam.id:lower() == teamId:lower()
  local ownTeamSuffix = isOwnTeam and lang(session, viewerHandle, "messages.team_status.own_team_suffix", " <green><bold>YOU</bold></green>") or ""

  return lang(session, viewerHandle, "messages.team_status.bed_line", "<white>{team}</white> <gray>-</gray> {status}{own_team_suffix}")
    :gsub("{team}", teamDisplay):gsub("{status}", status):gsub("{own_team_suffix}", ownTeamSuffix)
end

local function buildTeamSummaryPlaceholders(session, gameManager, placeholders, playerTeam, viewerHandle)
  local teamKills = gameManager.getTeamKills(session)
  local teamDeaths = gameManager.getTeamDeaths(session)

  local index = 1
  for _, team in ipairs(session.teams.all()) do
    if team.id and team.id ~= "" and hasTeamAnyPlayers(session, team.id) then
      local teamId = team.id
      local isPlayerTeam = playerTeam and playerTeam.id and playerTeam.id:lower() == teamId:lower()
      local bedIntact = bedService.isTeamBedIntact(session, teamId)
      local kills = teamKills[teamId] or 0
      local deaths = teamDeaths[teamId] or 0

      local bedIcon = bedIntact
        and lang(session, viewerHandle, "messages.team_status.bed_intact", "<green>\u{2714}</green>")
        or lang(session, viewerHandle, "messages.team_status.eliminated", "<red>\u{2718}</red>")
      local ownTeamSuffix = isPlayerTeam
        and lang(session, viewerHandle, "messages.team_status.own_team_header_suffix", " <green><bold><- You</bold></green>")
        or ""

      placeholders["team_header_" .. index] = lang(session, viewerHandle, "messages.team_status.header", "<white>{team}{own_team_suffix}</white>")
        :gsub("{team}", team.displayName or teamId):gsub("{own_team_suffix}", ownTeamSuffix) .. uniqueSuffix(index, 0)
      placeholders["team_summary_" .. index] = lang(session, viewerHandle, "messages.team_status.summary", "<white>{team}</white> <gray>Bed {bed_status} \u{2022} K {kills} \u{2022} D {deaths}</gray>")
        :gsub("{team}", team.displayName or teamId):gsub("{bed_status}", bedIcon):gsub("{kills}", tostring(kills)):gsub("{deaths}", tostring(deaths))
      index = index + 1
    end
  end

  for i = index, 8 do
    placeholders["team_header_" .. i] = "<black>.</black>" .. uniqueSuffix(i, 0)
    placeholders["team_summary_" .. i] = " "
  end
end

function M.buildPlaceholders(session, handle, gameManager)
  local placeholders = {}
  if not session then return placeholders end

  placeholders.alive = tostring(#session.alivePlayers())
  placeholders.spectators = tostring(#session.spectators())
  placeholders.kills = tostring(gameManager.getPlayerKills(session, handle))
  placeholders.deaths = tostring(gameManager.getPlayerDeaths(session, handle))
  placeholders.alive_teams = tostring(#gameManager.getAliveTeamIds(session))

  if session.teams.isEnabled() then
    local team = session.teams.forPlayer(handle)
    placeholders.team = team and team.displayName or "-"

    if team and team.id then
      local bedIntact = bedService.isTeamBedIntact(session, team.id)
      local yesText = session.config.translation(handle, "messages.common.boolean_true")
      local noText = session.config.translation(handle, "messages.common.boolean_false")
      placeholders.bed_status = bedIntact and ("<green>" .. yesText .. "</green>") or ("<red>" .. noText .. "</red>")
    else
      placeholders.bed_status = "-"
    end

    local index = 1
    for _, teamInfo in ipairs(session.teams.all()) do
      if teamInfo.id and hasTeamAnyPlayers(session, teamInfo.id) then
        local teamId = teamInfo.id:lower()
        local line = buildBedStatusLine(session, teamInfo, handle)
        placeholders["bed_status_" .. teamId] = line
        placeholders["bed_status_team_" .. index] = line
        index = index + 1
      end
    end
    for i = index, 8 do
      placeholders["bed_status_team_" .. i] = " "
    end

    buildTeamSummaryPlaceholders(session, gameManager, placeholders, team, handle)
  else
    placeholders.team = "-"
    placeholders.bed_status = "-"
  end

  return placeholders
end

function M.getPlayersSortedByKills(session, gameManager, players, limit)
  local scored = {}
  for _, handle in ipairs(players) do
    scored[#scored + 1] = { handle = handle, kills = gameManager.getPlayerKills(session, handle) }
  end

  table.sort(scored, function(a, b)
    if a.kills ~= b.kills then
      return a.kills > b.kills
    end
    return session.player.name(a.handle):lower() < session.player.name(b.handle):lower()
  end)

  local ordered = {}
  for _, entry in ipairs(scored) do
    ordered[#ordered + 1] = entry.handle
    if #ordered >= limit then break end
  end
  return ordered
end

return M

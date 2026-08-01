-- Mirrors legacy OutcomeService.java, including the full wool-capture recap broadcast (sendWinnerOutcomeMessage) - a real,
-- visible per-match message worth preserving exactly. gameManager is passed in (not required) to avoid a require cycle with game_manager.lua.
local woolService = require("support.wool_service")
local placeholderService = require("support.placeholder_service")

local M = {}

local WOOL_COLOR_TAGS = {
  WHITE_WOOL = "white", ORANGE_WOOL = "gold", MAGENTA_WOOL = "light_purple", LIGHT_BLUE_WOOL = "aqua",
  YELLOW_WOOL = "yellow", LIME_WOOL = "green", PINK_WOOL = "light_purple", GRAY_WOOL = "gray",
  LIGHT_GRAY_WOOL = "gray", CYAN_WOOL = "aqua", PURPLE_WOOL = "dark_purple", BLUE_WOOL = "blue",
  BROWN_WOOL = "gold", GREEN_WOOL = "dark_green", RED_WOOL = "red", BLACK_WOOL = "dark_gray",
}

local function getWoolColorTag(material)
  return WOOL_COLOR_TAGS[material] or "white"
end

local function compareWoolIds(a, b)
  local na, nb = tonumber(a), tonumber(b)
  if na and nb then
    return na < nb
  end
  return a:lower() < b:lower()
end

local function applyPlaceholders(template, placeholders)
  local value = template
  for k, v in pairs(placeholders) do
    value = value:gsub("{" .. k .. "}", function() return tostring(v) end)
  end
  return value
end

local function handleWinStats(session, winners)
  if #winners == 0 or session.state.winnerId then
    return
  end
  session.state.winnerId = winners[1]
  for _, handle in ipairs(winners) do
    session.stats.add(handle, "wins", 1)
  end
end

local function formatCapturedEntry(color, playerName)
  return "<" .. color .. ">■</" .. color .. "> <white>" .. playerName .. "</white>"
end

local function formatMissingEntry(color, missingText)
  return "<" .. color .. ">□</" .. color .. "> <gray>" .. missingText .. "</gray>"
end

local function getCapturableWoolsForTeam(session, teamId, teamIndex)
  local normalizedTeamId = teamId:lower()
  local numericAlias = tostring(teamIndex)
  local result = {}
  for _, def in ipairs(session.state.woolDefinitions) do
    local matches = false
    for _, captureTeam in ipairs(def.captureTeamIds) do
      if captureTeam == normalizedTeamId or captureTeam == numericAlias then
        matches = true
        break
      end
    end
    if matches then
      result[#result + 1] = def
    end
  end
  table.sort(result, function(a, b) return compareWoolIds(a.woolId, b.woolId) end)
  return result
end

local function resolvePlayerName(session, playerId)
  if not playerId then
    return session.config.translation(nil, "messages.winner_board.unknown_player") or "Unknown"
  end
  local name = session.player.name(playerId) or ba.playerUtil.offlineName(playerId)
  if name then
    return name
  end
  return session.config.translation(nil, "messages.winner_board.unknown_player") or "Unknown"
end

local function sendWinnerOutcomeMessage(session, winningTeamId, placeholders)
  if not session.teams.isEnabled() then
    return
  end

  local separator = session.config.translation(nil, "messages.winner_board.separator") or ""
  local title = session.config.translation(nil, "messages.winner_board.title") or ""
  local teamCapturesTemplate = session.config.translation(nil, "messages.winner_board.team_title") or ""
  local missingText = session.config.translation(nil, "messages.winner_board.missing_text") or ""
  local linePrefix = session.config.translation(nil, "messages.winner_board.line_prefix") or ""
  local lineGap = session.config.translation(nil, "messages.winner_board.entry_gap") or ""
  local entriesPerLine = math.max(1, session.config.getInt("messages.winner_board.entries_per_line", 2))

  local lines = {}
  lines[#lines + 1] = separator
  lines[#lines + 1] = linePrefix .. applyPlaceholders(title, placeholders)
  lines[#lines + 1] = " "

  local teamIndex = 1
  for _, teamInfo in ipairs(session.teams.all()) do
    if teamInfo.id and teamInfo.id ~= "" then
      local teamId = teamInfo.id
      local teamDisplay = (teamInfo.displayName ~= nil and teamInfo.displayName ~= "") and teamInfo.displayName or teamId

      local teamLine = teamCapturesTemplate:gsub("{team}", teamDisplay):gsub("{team_id}", teamId):gsub("{team_index}", tostring(teamIndex))
      lines[#lines + 1] = linePrefix .. teamLine

      local capturableWools = getCapturableWoolsForTeam(session, teamId, teamIndex)
      if #capturableWools == 0 then
        lines[#lines + 1] = linePrefix .. formatMissingEntry("yellow", missingText)
      else
        local formattedEntries = {}
        for _, def in ipairs(capturableWools) do
          local woolColor = getWoolColorTag(def.material)
          local state = woolService.getWoolState(session, def.key)
          local capturerId = session.state.woolCapturers[def.key]
          if state == "CAPTURED" and capturerId then
            formattedEntries[#formattedEntries + 1] = formatCapturedEntry(woolColor, resolvePlayerName(session, capturerId))
          else
            formattedEntries[#formattedEntries + 1] = formatMissingEntry(woolColor, missingText)
          end
        end

        local i = 1
        while i <= #formattedEntries do
          local row = {}
          for j = i, math.min(i + entriesPerLine - 1, #formattedEntries) do
            row[#row + 1] = formattedEntries[j]
          end
          lines[#lines + 1] = linePrefix .. table.concat(row, lineGap)
          i = i + entriesPerLine
        end
      end

      teamIndex = teamIndex + 1
      lines[#lines + 1] = " "
    end
  end

  lines[#lines + 1] = separator

  for _, line in ipairs(lines) do
    local processed = applyPlaceholders(line, placeholders)
    for _, handle in ipairs(session.players()) do
      session.messages.sendRaw(handle, processed)
    end
  end
end

local function populateTopKillsPlaceholders(session, gameManager, placeholders)
  local topKillers = placeholderService.getPlayersSortedByKills(session, gameManager, session.players(), 5)
  for i = 1, 5 do
    if topKillers[i] then
      placeholders["top_kills_" .. i] = session.player.name(topKillers[i])
      placeholders["top_kills_value_" .. i] = tostring(gameManager.getPlayerKills(session, topKillers[i]))
    else
      placeholders["top_kills_" .. i] = "-"
      placeholders["top_kills_value_" .. i] = "0"
    end
  end
end

local function showFinalScoreboard(session, gameManager, winningTeamId)
  local placeholders = {}
  local winningDisplay = winningTeamId
  if session.teams.isEnabled() and winningTeamId then
    for _, team in ipairs(session.teams.all()) do
      if team.id and team.id:lower() == winningTeamId:lower() then
        winningDisplay = team.displayName
        break
      end
    end
  end

  placeholders.winning_team = winningDisplay or "-"
  placeholders.winning_captured = tostring(woolService.getTeamCapturedObjectives(session, winningTeamId))
  placeholders.winning_objectives = tostring(woolService.getTeamObjectiveCount(session, winningTeamId))
  populateTopKillsPlaceholders(session, gameManager, placeholders)

  sendWinnerOutcomeMessage(session, winningTeamId, placeholders)

  for _, handle in ipairs(session.players()) do
    local finalPlaceholders = {}
    for k, v in pairs(placeholders) do
      finalPlaceholders[k] = v
    end
    for k, v in pairs(gameManager.getCustomPlaceholders(session, handle)) do
      finalPlaceholders[k] = v
    end
    session.scoreboard.showFinalModule(handle, "scoreboard.final.winner", finalPlaceholders)
  end
end

function M.handleNoWinner(session, gameManager)
  local candidates = session.players()
  local sortedByKills = placeholderService.getPlayersSortedByKills(session, gameManager, candidates, #candidates)
  if #sortedByKills == 0 then
    return
  end
  session.markSharedFirstPlace({ sortedByKills[1] })
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
  local hasAny = false
  local maxKills = 0
  for _, kills in pairs(teamKills) do
    hasAny = true
    if kills > maxKills then
      maxKills = kills
    end
  end
  if not hasAny then
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

  showFinalScoreboard(session, gameManager, topTeams[1] or "-")
  handleWinStats(session, winners)
end

function M.endGame(session, gameManager)
  if session.state.ended then
    return
  end
  session.state.ended = true

  session.scheduler.cancelArenaTasks()

  if session.teams.isEnabled() then
    for _, team in ipairs(session.teams.all()) do
      if team.id and team.id ~= "" and woolService.hasTeamCapturedAllWools(session, team.id) then
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

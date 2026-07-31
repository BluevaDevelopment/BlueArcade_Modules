-- Mirrors legacy GuessTheBuildOutcomeService.java.
local plotService = require("support.plot_service")

local M = {}

local function calculateSortedResults(session)
  local entries = {}
  for handle, points in pairs(session.state.playerPoints) do
    entries[#entries + 1] = { handle = handle, points = points }
  end
  table.sort(entries, function(a, b) return a.points > b.points end)
  return entries
end

local function resolveWinner(session, sorted)
  if #sorted == 0 then
    return nil
  end
  local winnerHandle = sorted[1].handle
  session.setWinner(winnerHandle)
  return winnerHandle
end

local function teleportToSharedPlot(session)
  local target = plotService.findSafeTeleport(session, session.state.plot)
  if not target then
    return
  end
  for _, handle in ipairs(session.players()) do
    session.player.teleport(handle, target)
  end
end

local function playerPositionAndScore(sorted, handle)
  for i, entry in ipairs(sorted) do
    if entry.handle == handle then
      return i, entry.points
    end
  end
  return 0, 0
end

local function sendResultMessages(session, sorted, basePlaceholders)
  for _, handle in ipairs(session.players()) do
    local lines = session.config.translationList(handle, "messages.result_lines")
    if #lines > 0 then
      local placeholders = {}
      for k, v in pairs(basePlaceholders) do
        placeholders[k] = v
      end
      local position, score = playerPositionAndScore(sorted, handle)
      placeholders.player_position = position > 0 and tostring(position) or "-"
      placeholders.player_score = tostring(score)

      for _, line in ipairs(lines) do
        local processed = line
        for k, v in pairs(placeholders) do
          processed = processed:gsub("{" .. k .. "}", v)
        end
        session.messages.sendRaw(handle, processed)
      end
    end
  end
end

local function showFinalScoreboard(session, sorted, basePlaceholders)
  local placeholders = {}
  for k, v in pairs(basePlaceholders) do
    placeholders[k] = v
  end
  placeholders.players = tostring(#session.players())

  for _, handle in ipairs(session.players()) do
    local position, score = playerPositionAndScore(sorted, handle)
    local playerPlaceholders = {}
    for k, v in pairs(placeholders) do
      playerPlaceholders[k] = v
    end
    playerPlaceholders.player_position = position > 0 and tostring(position) or "-"
    playerPlaceholders.player_score = tostring(score)
    session.scoreboard.showFinalModule(handle, "scoreboard.final.winner", playerPlaceholders)
  end
end

local function sendWinnerTitles(session, winnerHandle)
  if not winnerHandle then
    return
  end
  local winnerName = session.player.name(winnerHandle)
  for _, handle in ipairs(session.players()) do
    local title = session.config.translation(handle, "titles.winner.title")
    local subtitle = session.config.translation(handle, "titles.winner.subtitle")
    if title and subtitle then
      session.titles.sendRaw(handle, title, subtitle:gsub("{player}", winnerName), 0, 40, 20)
    end
  end
end

local function recordStats(session, sorted)
  for _, entry in ipairs(sorted) do
    if entry.points > 0 then
      session.stats.add(entry.handle, "points_total", entry.points)
    end
    local highest = session.stats.get(entry.handle, "points_highest")
    if entry.points > highest then
      session.stats.add(entry.handle, "points_highest", entry.points - highest)
    end
  end
  if #sorted > 0 then
    session.stats.add(sorted[1].handle, "wins", 1)
  end
  for _, handle in ipairs(session.players()) do
    session.stats.add(handle, "games_played", 1)
  end
end

function M.endGame(session)
  if session.state.ended then
    return
  end
  session.state.ended = true

  session.scheduler.cancelArenaTasks()

  local sorted = calculateSortedResults(session)
  local winnerHandle = resolveWinner(session, sorted)

  local basePlaceholders = {}
  for i = 1, 5 do
    local entry = sorted[i]
    if entry then
      basePlaceholders["place_" .. i] = session.player.name(entry.handle)
      basePlaceholders["score_" .. i] = tostring(entry.points)
    else
      basePlaceholders["place_" .. i] = "-"
      basePlaceholders["score_" .. i] = "0"
    end
  end

  teleportToSharedPlot(session)
  sendResultMessages(session, sorted, basePlaceholders)
  showFinalScoreboard(session, sorted, basePlaceholders)
  sendWinnerTitles(session, winnerHandle)
  recordStats(session, sorted)

  session.scheduler.runLater("arena_" .. session.arenaId .. "_guess_the_build_end_delay", function()
    session.endGame()
  end, 100)
end

return M

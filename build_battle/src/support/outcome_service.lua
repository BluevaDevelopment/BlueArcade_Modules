-- Mirrors legacy OutcomeService.java. teleportToWinnerPlot uses the winner's own stored plot spawn
-- directly rather than porting Plot.findSafeTeleport's own air-pocket block scan - the spawn is
-- exactly where every player already stood throughout the match, so it's always safe in practice; a
-- documented, deliberate simplification.
local PlotService = require("support.plot_service")

local M = {}

local function calculateSortedResults(session)
  local sorted = {}
  for builder, votes in pairs(session.state.plotVotes) do
    local total = 0
    for _, points in pairs(votes) do
      total = total + points
    end
    session.state.points[builder] = (session.state.points[builder] or 0) + total
    sorted[#sorted + 1] = { handle = builder, score = total }
  end
  table.sort(sorted, function(a, b) return a.score > b.score end)
  return sorted
end

local function sendResultMessages(session, sorted)
  local basePlaceholders = {}
  for i = 1, 5 do
    if sorted[i] then
      basePlaceholders["place_" .. i] = session.player.name(sorted[i].handle)
      basePlaceholders["score_" .. i] = tostring(sorted[i].score)
    else
      basePlaceholders["place_" .. i] = "-"
      basePlaceholders["score_" .. i] = "0"
    end
  end

  for _, handle in ipairs(session.players()) do
    local lines = session.config.translationList(handle, "messages.result_lines")
    if #lines > 0 then
      local playerPos, playerScore = 0, 0
      for i, entry in ipairs(sorted) do
        if entry.handle == handle then
          playerPos, playerScore = i, entry.score
          break
        end
      end
      local placeholders = {}
      for k, v in pairs(basePlaceholders) do placeholders[k] = v end
      placeholders.player_position = playerPos > 0 and tostring(playerPos) or "-"
      placeholders.player_score = tostring(playerScore)

      for _, line in ipairs(lines) do
        local processed = line
        for key, value in pairs(placeholders) do
          processed = processed:gsub("{" .. key .. "}", value)
        end
        session.messages.sendRaw(handle, processed)
      end
    end
  end
end

local function showFinalScoreboard(session, sorted)
  local basePlaceholders = {}
  for i = 1, 5 do
    if sorted[i] then
      basePlaceholders["place_" .. i] = session.player.name(sorted[i].handle)
      basePlaceholders["score_" .. i] = tostring(sorted[i].score)
    else
      basePlaceholders["place_" .. i] = "-"
      basePlaceholders["score_" .. i] = "0"
    end
  end
  basePlaceholders.players = tostring(#session.players())

  for _, handle in ipairs(session.players()) do
    local playerPos, playerScore = 0, 0
    for i, entry in ipairs(sorted) do
      if entry.handle == handle then
        playerPos, playerScore = i, entry.score
        break
      end
    end
    local placeholders = {}
    for k, v in pairs(basePlaceholders) do placeholders[k] = v end
    placeholders.player_position = playerPos > 0 and tostring(playerPos) or "-"
    placeholders.player_score = tostring(playerScore)

    session.scoreboard.showFinalModule(handle, "scoreboard.final.winner", placeholders)
  end
end

local function sendWinnerTitles(session, winner)
  if not winner then
    return
  end
  for _, handle in ipairs(session.players()) do
    local title = session.config.translation(handle, "titles.winner.title")
    local subtitle = session.config.translation(handle, "titles.winner.subtitle")
    if title and subtitle then
      session.titles.sendRaw(handle, title, subtitle:gsub("{player}", session.player.name(winner)), 0, 40, 20)
    end
  end
end

local function recordStats(session, sorted)
  for _, entry in ipairs(sorted) do
    if entry.score > 0 then
      session.stats.add(entry.handle, "points_total", entry.score)
    end
    local highest = session.stats.get(entry.handle, "points_highest")
    if entry.score > highest then
      session.stats.add(entry.handle, "points_highest", entry.score - highest)
    end
  end
  if sorted[1] then
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
  local winner = sorted[1] and sorted[1].handle or nil
  if winner then
    session.setWinner(winner)
  end

  if winner then
    local winnerPlot = session.state.playerPlot[winner]
    local target = winnerPlot and winnerPlot.spawn or session.state.playerPlotSpawn[winner]
    if target then
      local centered = PlotService.centerLocation(target)
      for _, handle in ipairs(session.players()) do
        session.player.teleport(handle, centered)
      end
    end
  end

  sendResultMessages(session, sorted)
  showFinalScoreboard(session, sorted)
  sendWinnerTitles(session, winner)
  recordStats(session, sorted)

  session.scheduler.runLater("arena_" .. session.arenaId .. "_build_battle_end_delay", function()
    session.endGame()
  end, 100)
end

return M

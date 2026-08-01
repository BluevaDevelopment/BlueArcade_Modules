local M = {}

-- Legacy hardcodes English label/description strings here instead of reading the language file - replicated as-is.
function M.registerStats()
  ba.stats.define("wins", "Wins", "Race wins")
  ba.stats.define("games_played", "Games Played", "Races played")
  ba.stats.define("finish_line_crosses", "Finish line crosses", "Times you reached the finish line")
end

function M.recordWin(session, handle)
  session.stats.add(handle, "wins", 1)
end

function M.recordGamePlayed(session, handle)
  session.stats.add(handle, "games_played", 1)
end

function M.recordFinishLineCross(session, handle)
  session.stats.add(handle, "finish_line_crosses", 1)
end

return M

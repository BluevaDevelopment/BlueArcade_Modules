local M = {}

function M.registerStats()
  ba.stats.define("wins", ba.config.translation(nil, "stats.labels.wins"), ba.config.translation(nil, "stats.descriptions.wins"))
  ba.stats.define("games_played", ba.config.translation(nil, "stats.labels.games_played"), ba.config.translation(nil, "stats.descriptions.games_played"))
  ba.stats.define("finish_line_crosses", ba.config.translation(nil, "stats.labels.finish_line_crosses"), ba.config.translation(nil, "stats.descriptions.finish_line_crosses"))
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

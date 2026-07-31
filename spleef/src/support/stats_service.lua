local M = {}

function M.registerStats()
  ba.stats.define("wins", ba.config.translation(nil, "stats.labels.wins"), ba.config.translation(nil, "stats.descriptions.wins"))
  ba.stats.define("games_played", ba.config.translation(nil, "stats.labels.games_played"), ba.config.translation(nil, "stats.descriptions.games_played"))
  ba.stats.define("snow_blocks_broken", ba.config.translation(nil, "stats.labels.snow_blocks_broken"), ba.config.translation(nil, "stats.descriptions.snow_blocks_broken"))
end

function M.recordWin(session, handle)
  session.stats.add(handle, "wins", 1)
end

function M.recordGamePlayed(session, handle)
  session.stats.add(handle, "games_played", 1)
end

function M.recordSnowBreak(session, handle)
  session.stats.add(handle, "snow_blocks_broken", 1)
end

return M

local M = {}

function M.registerStats()
  ba.stats.define("wins", ba.config.translation(nil, "stats.labels.wins"), ba.config.translation(nil, "stats.descriptions.wins"))
  ba.stats.define("games_played", ba.config.translation(nil, "stats.labels.games_played"), ba.config.translation(nil, "stats.descriptions.games_played"))
  ba.stats.define("snowballs_thrown", ba.config.translation(nil, "stats.labels.snowballs_thrown"), ba.config.translation(nil, "stats.descriptions.snowballs_thrown"))
  ba.stats.define("snowball_kills", ba.config.translation(nil, "stats.labels.snowball_kills"), ba.config.translation(nil, "stats.descriptions.snowball_kills"))
  ba.stats.define("snowball_hits", ba.config.translation(nil, "stats.labels.snowball_hits"), ba.config.translation(nil, "stats.descriptions.snowball_hits"))
end

function M.recordWin(session, handle)
  session.stats.add(handle, "wins", 1)
end

function M.recordGamePlayed(session, handle)
  session.stats.add(handle, "games_played", 1)
end

function M.recordSnowballThrown(session, handle)
  session.stats.add(handle, "snowballs_thrown", 1)
end

function M.recordSnowballHit(session, handle)
  session.stats.add(handle, "snowball_hits", 1)
end

function M.recordSnowballKill(session, handle)
  session.stats.add(handle, "snowball_kills", 1)
end

return M

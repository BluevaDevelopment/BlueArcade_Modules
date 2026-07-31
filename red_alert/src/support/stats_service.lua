local M = {}

function M.registerStats()
  ba.stats.define("wins", ba.config.translation(nil, "stats.labels.wins"), ba.config.translation(nil, "stats.descriptions.wins"))
  ba.stats.define("games_played", ba.config.translation(nil, "stats.labels.games_played"), ba.config.translation(nil, "stats.descriptions.games_played"))
  ba.stats.define("tiles_melted", ba.config.translation(nil, "stats.labels.tiles_melted"), ba.config.translation(nil, "stats.descriptions.tiles_melted"))
end

function M.recordWin(session, handle)
  if session.state.winnerId == nil then
    session.state.winnerId = handle
    session.stats.add(handle, "wins", 1)
  end
end

function M.recordTileMelt(session, handle)
  session.stats.add(handle, "tiles_melted", 1)
end

function M.recordGamesPlayed(session)
  for _, handle in ipairs(session.players()) do
    session.stats.add(handle, "games_played", 1)
  end
end

return M

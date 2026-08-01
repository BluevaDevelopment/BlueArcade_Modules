local M = {}

-- Hardcoded strings, matching legacy's own anomaly: stats.labels exists in the language file but
-- is never read here either.
function M.registerStats()
  ba.stats.define("wins", "Wins", "One in the Chamber wins")
  ba.stats.define("games_played", "Games Played", "One in the Chamber games played")
  ba.stats.define("kills", "Kills", "Opponents defeated in One in the Chamber")
  ba.stats.define("arrows_shot", "Arrows shot", "Arrows fired in One in the Chamber")
  ba.stats.define("hits_landed", "Hits landed", "Successful hits in One in the Chamber")
end

function M.recordWin(session, handle)
  session.stats.add(handle, "wins", 1)
end

function M.recordGamesPlayed(session)
  for _, handle in ipairs(session.players()) do
    session.stats.add(handle, "games_played", 1)
  end
end

function M.recordKill(session, handle)
  session.stats.add(handle, "kills", 1)
end

function M.recordShot(session, handle)
  session.stats.add(handle, "arrows_shot", 1)
end

function M.recordHit(session, handle)
  session.stats.add(handle, "hits_landed", 1)
end

return M

local M = {}

function M.registerStats()
  ba.stats.define("wins", ba.config.translation(nil, "stats.labels.wins"), ba.config.translation(nil, "stats.descriptions.wins"))
  ba.stats.define("games_played", ba.config.translation(nil, "stats.labels.games_played"), ba.config.translation(nil, "stats.descriptions.games_played"))
  ba.stats.define("knockback_hits", ba.config.translation(nil, "stats.labels.knockback_hits"), ba.config.translation(nil, "stats.descriptions.knockback_hits"))
  ba.stats.define("knockback_kills", ba.config.translation(nil, "stats.labels.knockback_kills"), ba.config.translation(nil, "stats.descriptions.knockback_kills"))
end

function M.recordWin(session, handle)
  session.stats.add(handle, "wins", 1)
end

function M.recordGamePlayed(session, handle)
  session.stats.add(handle, "games_played", 1)
end

function M.recordKnockbackHit(session, handle)
  session.stats.add(handle, "knockback_hits", 1)
end

function M.recordKnockbackKill(session, handle)
  session.stats.add(handle, "knockback_kills", 1)
end

return M

--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local M = {}

function M.registerStats()
  ba.stats.define("wins", ba.config.translation(nil, "stats.labels.wins"), ba.config.translation(nil, "stats.descriptions.wins"))
  ba.stats.define("games_played", ba.config.translation(nil, "stats.labels.games_played"), ba.config.translation(nil, "stats.descriptions.games_played"))
  ba.stats.define("water_landings", ba.config.translation(nil, "stats.labels.water_landings"), ba.config.translation(nil, "stats.descriptions.water_landings"))
  ba.stats.define("total_score", ba.config.translation(nil, "stats.labels.total_score"), ba.config.translation(nil, "stats.descriptions.total_score"))
end

function M.recordWin(session, handle)
  session.stats.add(handle, "wins", 1)
end

function M.recordGamePlayed(session, handle)
  session.stats.add(handle, "games_played", 1)
end

function M.recordWaterLanding(session, handle)
  session.stats.add(handle, "water_landings", 1)
  session.stats.add(handle, "total_score", 2)
end

return M

--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local M = {}

-- Hardcoded label/description strings, matching legacy's own anomaly (stats.labels is never read).
function M.registerStats()
  ba.stats.define("wins", "Wins", "Bridge Race wins")
  ba.stats.define("games_played", "Games Played", "Bridge Races played")
  ba.stats.define("finish_line_crosses", "Finish line crosses", "Bridge Race finishes")
  ba.stats.define("blocks_placed", "Blocks Placed", "Blocks placed")
end

function M.recordFinishLineCross(session, handle)
  session.stats.add(handle, "finish_line_crosses", 1)
end

function M.recordWin(session, handle)
  session.stats.add(handle, "wins", 1)
end

function M.recordGamePlayed(session)
  for _, handle in ipairs(session.players()) do
    session.stats.add(handle, "games_played", 1)
  end
end

function M.recordBlockPlaced(session, handle)
  session.stats.add(handle, "blocks_placed", 1)
end

return M

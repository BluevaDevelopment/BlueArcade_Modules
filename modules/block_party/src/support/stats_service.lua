--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local M = {}

function M.registerStats()
  ba.stats.define("wins", "Wins", "Block Party wins")
  ba.stats.define("games_played", "Games Played", "Block Party games played")
  ba.stats.define("correct_blocks", "Correct blocks", "Correct colors matched")
  ba.stats.define("powerups_used", "Power-ups", "Power-ups collected")
end

function M.recordWin(session, handle)
  session.stats.add(handle, "wins", 1)
end

function M.recordGamesPlayed(session)
  for _, handle in ipairs(session.players()) do
    session.stats.add(handle, "games_played", 1)
  end
end

function M.recordCorrectBlock(session, handle)
  session.stats.add(handle, "correct_blocks", 1)
end

function M.recordPowerupUsed(session, handle)
  session.stats.add(handle, "powerups_used", 1)
end

return M

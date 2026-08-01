--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local M = {}

function M.registerStats()
  ba.stats.define("wins", "Wins", "TNT Tag wins")
  ba.stats.define("games_played", "Games Played", "TNT Tag games played")
  ba.stats.define("tags_given", "Tags passed", "Times you passed the TNT to others")
  ba.stats.define("rounds_survived", "Rounds survived", "Rounds outlived in TNT Tag")
  ba.stats.define("tnt_escaped", "TNT escapes", "Times you passed TNT before it exploded")
end

function M.recordWin(session, handle)
  session.stats.add(handle, "wins", 1)
end

function M.recordGamesPlayed(session)
  for _, handle in ipairs(session.players()) do
    session.stats.add(handle, "games_played", 1)
  end
end

function M.recordTag(session, handle)
  session.stats.add(handle, "tags_given", 1)
end

function M.recordSurvival(session, handle)
  session.stats.add(handle, "rounds_survived", 1)
end

function M.recordEscape(session, handle)
  session.stats.add(handle, "tnt_escaped", 1)
end

return M

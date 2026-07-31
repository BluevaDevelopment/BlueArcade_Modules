local M = {}

-- Hardcoded label/description strings, matching `BridgeRaceStatsService.registerStats`'s own
-- real anomaly - it never reads them from `moduleConfig.getTranslation(...)`, even though the
-- language file's own `stats.labels` section exists (it's simply never read). Not "fixed" into a
-- translation lookup, same shape as `race`/`one_in_the_chamber`'s own hardcoded stats.
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

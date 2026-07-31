local M = {}

function M.register()
  ba.stats.define("games_played", "Games played", "Chairs matches played")
  ba.stats.define("wins", "Wins", "Chairs wins")
  ba.stats.define("rounds_survived", "Rounds survived", "Rounds survived in Chairs")
end

return M

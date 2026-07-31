local gameManager = require("game_manager")
local listener = require("listener")
local setup = require("setup")

local M = {}

listener.register()
setup.register()

function M.onLoad()
  ba.stats.define("wins", ba.config.translation(nil, "stats.labels.wins"), ba.config.translation(nil, "stats.descriptions.wins"))
  ba.stats.define("games_played", ba.config.translation(nil, "stats.labels.games_played"), ba.config.translation(nil, "stats.descriptions.games_played"))
  ba.stats.define("finish_line_crosses", ba.config.translation(nil, "stats.labels.finish_line_crosses"), ba.config.translation(nil, "stats.descriptions.finish_line_crosses"))
  ba.stats.define("mines_triggered", ba.config.translation(nil, "stats.labels.mines_triggered"), ba.config.translation(nil, "stats.descriptions.mines_triggered"))

  ba.achievements.register("achievements.yml")

  ba.vote.register(
    ba.config.getString("menus.vote.item"),
    ba.config.translation(nil, "vote_menu.name"),
    ba.config.translationList(nil, "vote_menu.lore")
  )
end

function M.onStart(session)
  gameManager.handleStart(session)
end

function M.onCountdownTick(session, secondsLeft)
  gameManager.handleCountdownTick(session, secondsLeft)
end

function M.onCountdownFinish(session)
  gameManager.handleCountdownFinish(session)
end

function M.freezePlayersOnCountdown()
  return true
end

function M.onGameStart(session)
  gameManager.handleGameStart(session)
end

function M.onEnd(session, result)
  gameManager.handleEnd(session)
end

function M.getCustomPlaceholders(session, handle)
  return gameManager.getCustomPlaceholders(session, handle)
end

return M

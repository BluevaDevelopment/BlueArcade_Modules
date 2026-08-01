--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy SpeedBuildersModule.java; its store.yml has no categories and legacy never calls StoreAPI here, so there is nothing to register.
local gameManager = require("game_manager")
local listener = require("listener")
local setup = require("setup")

local M = {}

listener.register()
setup.register()

function M.onLoad()
  ba.stats.define("wins", ba.config.translation(nil, "stats.labels.wins"), ba.config.translation(nil, "stats.descriptions.wins"))
  ba.stats.define("games_played", ba.config.translation(nil, "stats.labels.games_played"), ba.config.translation(nil, "stats.descriptions.games_played"))
  ba.stats.define("rounds_survived", ba.config.translation(nil, "stats.labels.rounds_survived"), ba.config.translation(nil, "stats.descriptions.rounds_survived"))
  ba.stats.define("perfect_builds", ba.config.translation(nil, "stats.labels.perfect_builds"), ba.config.translation(nil, "stats.descriptions.perfect_builds"))

  ba.achievements.register("achievements.yml")

  local voteItem = ba.config.getString("menus.vote.item") or "BRICKS"
  ba.vote.register(voteItem, ba.config.translation(nil, "vote_menu.name"), ba.config.translationList(nil, "vote_menu.lore"))
end

function M.onStart(session)
  gameManager.startGame(session)
end

function M.onCountdownTick(session, secondsLeft)
  gameManager.handleCountdownTick(session, secondsLeft)
end

function M.onCountdownFinish(session)
  gameManager.handleCountdownFinish(session)
end

function M.freezePlayersOnCountdown()
  return false
end

function M.onGameStart(session)
  gameManager.beginPlaying(session)
end

function M.onEnd(session, result)
  gameManager.finishGame(session)
end

-- Defensive plugin-shutdown cleanup only - no winner, no stats, mirrors legacy shutdown().
function M.onDisable()
  for _, session in ipairs(ba.session.all()) do
    gameManager.handleDisable(session)
  end
end

function M.getCustomPlaceholders(session, handle)
  return gameManager.getCustomPlaceholders(session, handle)
end

return M

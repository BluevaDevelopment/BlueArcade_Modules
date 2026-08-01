-- Mirrors legacy SpeedBuildersModule.java. store.yml/StoreAPI registration isn't ported - StoreAPI
-- is entirely unbound in this project's Lua layer, matching every other converted module.
local gameManager = require("game_manager")
local listener = require("listener")
local setup = require("setup")

local M = {}

listener.register()
setup.register()

function M.onLoad()
  ba.stats.define("wins", ba.config.translation(nil, "stats.labels.wins"), "Speed Builders wins")
  ba.stats.define("games_played", ba.config.translation(nil, "stats.labels.games_played"), "Speed Builders games played")
  ba.stats.define("rounds_survived", ba.config.translation(nil, "stats.labels.rounds_survived"), "Rounds survived")
  ba.stats.define("perfect_builds", ba.config.translation(nil, "stats.labels.perfect_builds"), "Perfect builds")

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

-- Legacy shutdown() defensively re-cleans every still-active arena on module disable - not ported,
-- same documented gap as every other converted module's M.onDisable(), see docs/BAMODULE_STATUS.md.
function M.onDisable()
end

function M.getCustomPlaceholders(session, handle)
  return gameManager.getCustomPlaceholders(session, handle)
end

return M

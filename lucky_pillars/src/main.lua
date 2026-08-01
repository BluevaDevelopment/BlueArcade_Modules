--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- requiresSpawnCapacityValidation isn't defined here - legacy never overrides it either, so it keeps the framework default (true).
local gameManager = require("game_manager")
local listener = require("listener")
local setup = require("setup")
local voteService = require("support.vote_service")
local storeService = require("support.store_service")

local M = {}

listener.register()
setup.register()

function M.onLoad()
  ba.stats.define("wins", ba.config.translation(nil, "stats.labels.wins"), ba.config.translation(nil, "stats.descriptions.wins"))
  ba.stats.define("games_played", ba.config.translation(nil, "stats.labels.games_played"), ba.config.translation(nil, "stats.descriptions.games_played"))
  ba.stats.define("kills", ba.config.translation(nil, "stats.labels.kills"), ba.config.translation(nil, "stats.descriptions.kills"))

  ba.achievements.register("achievements.yml")

  storeService.registerStoreItems()

  ba.vote.register(
    ba.config.getString("menus.vote.item"),
    ba.config.translation(nil, "vote_menu.name"),
    ba.config.translationList(nil, "vote_menu.lore")
  )

  voteService.registerWaitingItem()
  voteService.registerClickHandler()

  -- payload already had "MODULE;lucky_pillars;" stripped by MenuActionExecutor; parse it back into an args array.
  ba.menu.onAction(function(playerHandle, payload)
    if not payload or payload == "" then
      return false
    end
    local args = {}
    for word in payload:gmatch("%S+") do
      args[#args + 1] = word
    end
    return voteService.handleVoteAction(playerHandle, args)
  end)
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

-- Mirrors legacy LuckyPillarsGame.shutdown(): defensive cleanup only, no winner/stats.
function M.onDisable()
  for _, session in ipairs(ba.session.all()) do
    gameManager.handleDisableCleanup(session)
  end
end

function M.getCustomPlaceholders(session, handle)
  return gameManager.getCustomPlaceholders(session, handle)
end

return M
